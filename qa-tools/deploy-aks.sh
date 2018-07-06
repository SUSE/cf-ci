usage() {
  cat << 'EOF'
  Requirements:
  * Your Azure user needs the User Access Administrator role. Check your assigned roles with the az command:
    `az role assignment list --assignee $AZ_USER`
  * Verify that the Microsoft.Network, Microsoft.Storage, Microsoft.Compute, and Microsoft.ContainerService providers are enabled:
    `az provider list | egrep -w 'Microsoft.Network|Microsoft.Storage|Microsoft.Compute|Microsoft.ContainerService'`
EOF
}

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
export AZ_AKS_NODE_VM_SIZE=Standard_D2_v2
export AZ_SSH_KEY=~/.ssh/id_rsa.pub
export AZ_ADMIN_USER=scf-admin

az group create --name $AZ_RG_NAME --location $AZ_REGION
az aks create --resource-group $AZ_RG_NAME --name $AZ_AKS_NAME \
              --node-count $AZ_AKS_NODE_COUNT --admin-username $AZ_ADMIN_USER \
              --ssh-key-value $AZ_SSH_KEY --node-vm-size $AZ_AKS_NODE_VM_SIZE

export KUBECONFIG=$(mktemp -d)/config

while ! az aks get-credentials --admin --resource-group $AZ_RG_NAME --name $AZ_AKS_NAME --file $KUBECONFIG; do
  sleep 10
done

while [[ $node_readiness != "$AZ_AKS_NODE_COUNT True" ]]; do
  sleep 10
  node_readiness=$(
    docker run -v "$KUBECONFIG:/root/.kube/config" --rm  splatform/cf-ci-orchestration kubectl get nodes -o json \
      | jq -r '.items[] | .status.conditions[] | select(.type == "Ready").status' \
      | uniq -c | grep -o '\S.*'
  )
done

export AZ_MC_RG_NAME=$(az group list -o table | grep MC_"$AZ_RG_NAME"_ | awk '{print $1}')
vmnodes=$(az vm list -g $AZ_MC_RG_NAME | jq -r '.[] | select (.tags.poolName | contains("node")) | .name')
for i in $vmnodes; do
   az vm run-command invoke -g $AZ_MC_RG_NAME -n $i --command-id RunShellScript \
     --scripts "sudo sed -i 's|linux.*./boot/vmlinuz-.*|& swapaccount=1|' /boot/grub/grub.cfg"
   sleep 1 # avoid a weird timing issue?
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

echo -e "\n Resource Group:\t$AZ_RG_NAME\n \
Public IP:\t\t$(az network public-ip show --resource-group $AZ_MC_RG_NAME --name $AZ_AKS_NAME-public-ip --query ipAddress)\n \
Private IPs:\t\t\"$(az network nic list --resource-group $AZ_MC_RG_NAME | jq -r '.[].ipConfigurations[].privateIpAddress' | paste -s -d " " | sed -e 's/ /", "/g')\"\n"
