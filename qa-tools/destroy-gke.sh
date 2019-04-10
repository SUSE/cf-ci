usage(){
    cat << 'EOF'
  Usage:
  destroy-gke.sh [CLUSTER_NAME]
EOF
}

if [ $# -lt 1 ]
then
	usage
	exit 0
fi

export CLUSTER_NAME=$1

gcloud -q container clusters delete $CLUSTER_NAME

# Pruning all the PV disks attached to the cluster
gcloud -q compute disks delete $(gcloud compute disks list --filter="name~'$CLUSTER_NAME'")
