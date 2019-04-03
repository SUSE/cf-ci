usage() {
  cat << 'EOF'
  Usage:
  deploy-gke.sh [SERVICE_ACCOUNT_EMAIL] [KEY_FILE] [PROJ_ID] (optional)
  Requirements:
  * The GKE user/service account user needs the following roles:
    container.admin compute.admin iam.serviceAccountUser
    Roles can be granted to a service account via the following :
    `gcloud projects add-iam-policy-binding <proj-id> --member \ 
     serviceAccount:sa@proj-id.iam.gserviceaccount.com --role \ 
     roles/container.admin --role roles/compute.admin --role roles/iam.serviceAccountUser`
    etc. *
EOF
}

if [ $# -lt 2 ]
then
	usage
	exit 0
fi


cleanup() {
  for container in "${CONTAINERS_TMP[@]}"; do
    if docker container ls -a --format '{{.Names}}' | grep -Eq "^$container\$"; then
      docker container rm --force $container
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

CONTAINERS_TMP=(gke-deploy)
PATHS_TMP=()
FILES_TMP=()
trap cleanup EXIT

set -o errexit
postfix=$(cat /dev/urandom | env LC_CTYPE=C tr -dc 'a-z0-9' | fold -w 16 | head -n 1)
export CLUSTER_NAME=${CLUSTER_NAME:-cap-${postfix}}
export CLUSTER_ZONE=${CLUSTER_ZONE:-us-west1-a}

#  We are setting up a zonal cluster, not a regional one  

export NODE_COUNT=3
export SA_USER=$1
export KEY_FILE=$2
export PROJECT=${3:-suse-css-platform}
# Log out from any existing context and log in with the GKE service account

gcloud auth revoke || true
gcloud auth activate-service-account $SA_USER --key-file $KEY_FILE --project=$PROJECT

# Clusters on k8s 1.10 and above will no longer get compute-rw and storage-ro scopes
gcloud config set container/new_scopes_behavior true

# Create GKE cluster 
gcloud container clusters create ${CLUSTER_NAME} --image-type=UBUNTU --machine-type=n1-standard-4 --zone \
${CLUSTER_ZONE} --num-nodes=$NODE_COUNT --no-enable-basic-auth --no-issue-client-certificate \
--no-enable-autoupgrade --metadata disable-legacy-endpoints=true \
--labels=owner=$(gcloud config get-value account | tr [:upper:] [:lower:] | tr -c a-z0-9_- _ )

# All future kubectl commands will be run in this container. This ensures the
# correct version of kubectl is used, and that it matches the version used by CI
docker container run \
  --name gke-deploy \
  --detach \
  --volume $(realpath $KEY_FILE):/.kube/sa-key \
  --env KUBECONFIG=/.kube/kubecfg \
  splatform/cf-ci-orchestration:latest tail -f /dev/null

docker container exec gke-deploy gcloud auth activate-service-account $SA_USER --key-file /.kube/sa-key --project=$PROJECT
docker container exec gke-deploy gcloud container clusters get-credentials  ${CLUSTER_NAME} --zone ${CLUSTER_ZONE:?required}

checkready() {
	while [[ $node_readiness != "$NODE_COUNT True" ]]; do
		sleep 10
		node_readiness=$(
			docker container exec gke-deploy kubectl get nodes -o json \
      		| jq -r '.items[] | .status.conditions[] | select(.type == "Ready").status' \
      		| uniq -c | grep -o '\S.*'
  		)
	done
}

checkready

if [ "$(uname)" == "Darwin" ]; then
	args=I
else
	args=i
fi
echo "Setting swap accounting"

#Grab node instance names
instance_names=$(gcloud compute instances list --filter=name~${CLUSTER_NAME:?required} --format json | jq --raw-output '.[].name')

# Set correct zone
gcloud config set compute/zone ${CLUSTER_ZONE:?required}

# Update kernel command line
echo "$instance_names" | xargs -${args}{} gcloud compute ssh {} -- "sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"console=ttyS0 net.ifnames=0\"/GRUB_CMDLINE_LINUX_DEFAULT=\"console=ttyS0 net.ifnames=0 cgroup_enable=memory swapaccount=1\"/g' /etc/default/grub.d/50-cloudimg-settings.cfg"

# Update grub
echo "$instance_names" | xargs -${args}{} gcloud compute ssh {} -- "sudo update-grub"

# Restart VMs
echo "$instance_names" | xargs gcloud compute instances reset
echo "restarted the VMs"
checkready

# Is this really required in the context of GKE? What should be in the configmap?
docker container exec -it gke-deploy kubectl create configmap -n kube-system cap-values \
  --from-literal=garden-rootfs-driver=overlay-xfs \
  --from-literal=platform=gke 

#Set up Helm
cat gke-helm-sa.yaml | docker container exec -i gke-deploy kubectl create -f -
docker container exec -i gke-deploy helm init --service-account tiller
