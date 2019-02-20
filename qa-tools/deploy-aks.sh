usage() {
  cat << 'EOF'
  Requirements:
  * Your Azure user needs the User Access Administrator role. Check your assigned roles with the az command:
    `az role assignment list --assignee $AZ_USER`
  * Verify that the Microsoft.Network, Microsoft.Storage, Microsoft.Compute, and Microsoft.ContainerService providers are enabled:
    `az provider list | egrep -w 'Microsoft.Network|Microsoft.Storage|Microsoft.Compute|Microsoft.ContainerService'`
EOF
}

cleanup() {
  for container in "${CONTAINERS_TMP[@]}"; do
    if docker ps --format '{{.Names}}' | grep -Eq "^$container\$"; then
      docker rm --force $container
    fi
  done
  for path in "${PATHS_TMP[@]}"; do
    # Only cleanup tmp paths in /tmp/
    if [[ -d "${path}" ]] && [[ ${path} =~ ^/tmp/ ]]; then
      rm -rf "${path}"
    fi
  done
  for file in "${FILES_TMP[@]}"; do
    if [[ -f "${file}" ]]; then
      rm -f "${file}"
    fi
  done
}

CONTAINERS_TMP=(aks-deploy)
PATHS_TMP=()
FILES_TMP=()
trap cleanup EXIT

set -o errexit

# interactive step requiring you to login in browser:
export AZ_USER=$(az login | jq -r .[0].user.name)
export AZ_SUBSCRIPTION_ID=$(az account show --query "{ subscription_id: id }" | jq -r .subscription_id)
az account set --subscription $AZ_SUBSCRIPTION_ID
az_user_prefix=${AZ_USER%%@*}-
export AZ_RG_NAME=${az_user_prefix}cap-aks
export AZ_AKS_NAME=$AZ_RG_NAME
export AZ_REGION=eastus
export AZ_AKS_NODE_COUNT=3
export AZ_AKS_NODE_VM_SIZE=Standard_DS4_v2
export AZ_ADMIN_USER=scf-admin
export AZ_SSH_KEY_PATH=$(mktemp -d)
export AZ_SSH_KEY=${AZ_SSH_KEY_PATH}/aks-deploy
ssh-keygen -f ${AZ_SSH_KEY} -N ""


az group create --name $AZ_RG_NAME --location $AZ_REGION
az aks create --resource-group $AZ_RG_NAME --name $AZ_AKS_NAME \
              --node-count $AZ_AKS_NODE_COUNT --admin-username $AZ_ADMIN_USER \
              --ssh-key-value ${AZ_SSH_KEY}.pub --node-vm-size $AZ_AKS_NODE_VM_SIZE \
              --node-osdisk-size 60 --kubernetes-version 1.11.6

export KUBECONFIG=$(mktemp -d)/config

while ! az aks get-credentials --admin --resource-group $AZ_RG_NAME --name $AZ_AKS_NAME --file $KUBECONFIG; do
  sleep 10
done


# All future kubectl commands will be run in this container. This ensures the
# correct version of kubectl is used, and that it matches the version used by CI
docker run \
  --name aks-deploy \
  --detach \
  --rm \
  --volume $KUBECONFIG:/root/.kube/config \
  splatform/cf-ci-orchestration sleep infinity

while [[ $node_readiness != "$AZ_AKS_NODE_COUNT True" ]]; do
  sleep 10
  node_readiness=$(
    docker exec aks-deploy kubectl get nodes -o json \
      | jq -r '.items[] | .status.conditions[] | select(.type == "Ready").status' \
      | uniq -c | grep -o '\S.*'
  )
done

export AZ_MC_RG_NAME=$(az group list -o table | grep MC_"$AZ_RG_NAME"_ | awk '{print $1}')
vmnodes=$(az vm list -g $AZ_MC_RG_NAME | jq -r '.[] | select (.tags.poolName | contains("node")) | .name')
for i in $vmnodes; do
   az vm run-command invoke -g $AZ_MC_RG_NAME -n $i --command-id RunShellScript \
     --scripts "sudo sed -i -r 's|^(GRUB_CMDLINE_LINUX_DEFAULT=)\"(.*.)\"|\1\"\2 swapaccount=1\"|' /etc/default/grub.d/50-cloudimg-settings.cfg"
   az vm run-command invoke -g $AZ_MC_RG_NAME -n $i --command-id RunShellScript --scripts "sudo update-grub"
done

for i in $vmnodes; do
   az vm restart -g $AZ_MC_RG_NAME -n $i
done

az network public-ip create \
  --resource-group $AZ_MC_RG_NAME \
  --name $AZ_AKS_NAME-public-ip \
  --allocation-method Static

az network lb create \
  --resource-group $AZ_MC_RG_NAME \
  --name $AZ_AKS_NAME-lb \
  --public-ip-address $AZ_AKS_NAME-public-ip \
  --frontend-ip-name $AZ_AKS_NAME-lb-front \
  --backend-pool-name $AZ_AKS_NAME-lb-back

AZ_NIC_NAMES=$(az network nic list --resource-group $AZ_MC_RG_NAME | jq -r '.[].name')
for i in $AZ_NIC_NAMES; do
  az network nic ip-config address-pool add \
    --resource-group $AZ_MC_RG_NAME \
    --nic-name $i \
    --ip-config-name ipconfig1 \
    --lb-name $AZ_AKS_NAME-lb \
    --address-pool $AZ_AKS_NAME-lb-back
done

export CAP_PORTS="80 443 4443 2222 2793 8443 $(echo 2000{0..9})"

for i in $CAP_PORTS; do
  az network lb probe create \
    --resource-group $AZ_MC_RG_NAME \
    --lb-name $AZ_AKS_NAME-lb \
    --name probe-$i \
    --protocol tcp \
    --port $i 
    
  az network lb rule create \
    --resource-group $AZ_MC_RG_NAME \
    --lb-name $AZ_AKS_NAME-lb \
    --name rule-$i \
    --protocol Tcp \
    --frontend-ip-name $AZ_AKS_NAME-lb-front \
    --backend-pool-name $AZ_AKS_NAME-lb-back \
    --frontend-port $i \
    --backend-port $i \
    --probe probe-$i 
done

az network lb rule list -g $AZ_MC_RG_NAME --lb-name $AZ_AKS_NAME-lb | grep -i port

nsg=$(az network nsg list --resource-group=$AZ_MC_RG_NAME | jq -r '.[].name')
pri=200

for i in $CAP_PORTS; do
  az network nsg rule create \
    --resource-group $AZ_MC_RG_NAME \
    --priority $pri \
    --nsg-name $nsg \
    --name $AZ_AKS_NAME-$i \
    --direction Inbound \
    --destination-port-ranges $i \
    --access Allow
  pri=$(expr $pri + 1)
done

internal_ips=($(az network nic list --resource-group $AZ_MC_RG_NAME | jq -r '.[].ipConfigurations[].privateIpAddress'))
public_ip=$(az network public-ip show --resource-group $AZ_MC_RG_NAME --name $AZ_AKS_NAME-public-ip --query ipAddress --output tsv)
echo -e "\n Resource Group:\t$AZ_RG_NAME\n \
Public IP:\t\t${public_ip}\n \
Private IPs:\t\t\"$(IFS=,; echo "${internal_ips[*]}")\"\n"

# TODO: check if -i and -it are really needed in the following 3 commands
docker exec -it aks-deploy kubectl create configmap -n kube-system cap-values \
  --from-literal=internal-ip=${internal_ips[0]} \
  --from-literal=public-ip=$public_ip \
  --from-literal=garden-rootfs-driver=overlay-xfs \
  --from-literal=platform=azure \
  --from-literal="node-ssh-access=$(cat $AZ_SSH_KEY)"
rm -rf "/tmp/tmp.${AZ_SSH_KEY_PATH##/tmp/tmp.}"
cat persistent-sc.yaml cluster-admin.yaml | docker exec -i aks-deploy kubectl create -f -
docker exec -it aks-deploy helm init
