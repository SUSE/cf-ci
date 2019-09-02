#!/usr/bin/env bash
set -euo pipefail

# Deploys Caasp4 cluster on openstack, with an nfs server, and prepares
# it for CAP.
#
# Requires:
# - Built skuba docker image
# - Sourced openrc.sh
# - Key on the ssh keyring. If not, will put one

SKUBA_DEPLOY_PATH="$CF_CI_DIR"/qa-tools/skuba-deploy.sh
skuba-deploy() {
    bash "$SKUBA_DEPLOY_PATH" "$@"
}

if [[ -d "$WORKSPACE" ]]; then
    echo ">>> Aborting: WORKSPACE=$WORKSPACE already exists, you have an existing deployment"
    exit 1
else
    mkdir -p "$WORKSPACE"
fi

# check ssh key
agent="$(pgrep ssh-agent -u "$USER")"
if [[ "$agent" == "" ]]; then
    eval "$(ssh-agent -s)"
fi
if ! ssh-add -L | grep -q 'ssh' ; then
    echo ">>> Adding ssh key"
    curl "https://raw.githubusercontent.com/SUSE/skuba/master/ci/infra/id_shared" -o "$WORKSPACE"/id_rsa \
        && chmod 0600 "$WORKSPACE"/id_rsa
    ssh-add "$WORKSPACE"/id_rsa
fi

if [[ ! -v OS_PASSWORD ]]; then
    echo ">>> Missing openstack credentials" && exit 1
fi

echo ">>> Extracting terraform files from skuba package"
docker run \
       --name skuba-"$CAASP_VER" \
       --detach \
       --rm \
       skuba/"$CAASP_VER" sleep infinity
docker cp \
       skuba-"$CAASP_VER":/usr/share/caasp/terraform/openstack/. \
       "$WORKSPACE"/deployment
docker rm -f skuba-"$CAASP_VER"

echo ">>> Copying our own terraform files"
case "$CAASP_VER" in
    "devel")
         CAASP_REPO='caasp_40_devel_sle15sp1 = "http://download.suse.de/ibs/Devel:/CaaSP:/4.0/SLE_15_SP1/"'
         ;;
    "staging")
         CAASP_REPO='caasp_40_staging_sle15sp1 = "http://download.suse.de/ibs/SUSE:/SLE-15-SP1:/Update:/Products:/CASP40/staging/"'
         ;;
    "product")
         CAASP_REPO='caasp_40_product_sle15sp1 = "http://download.suse.de/ibs/SUSE:/SLE-15-SP1:/Update:/Products:/CASP40/standard/"'
         ;;
    "update")
         CAASP_REPO='caasp_40_update_sle15sp1 = "http://download.suse.de/ibs/SUSE:/SLE-15-SP1:/Update:/Products:/CASP40:/Update/standard/"'
         ;;
esac
echo ">>>>>> Using $CAASP_REPO"
escapeSubst() {
    # escape string for usage in a sed substitution expression
    IFS= read -d '' -r < <(sed -e ':a' -e '$!{N;ba' -e '}' -e 's%[&/\]%\\&%g; s%\n%\\&%g' <<<"$1")
    printf %s "${REPLY%$'\n'}"
}
SSHKEY="$(ssh-add -L)"
CAASP_PATTERN='patterns-caasp-Node-1.15'
sed -e "s%#~placeholder_stack~#%$(escapeSubst "$STACK")%g" \
    -e "s%#~placeholder_magic_dns~#%$(escapeSubst "$MAGIC_DNS_SERVICE")%g" \
    -e "s%#~placeholder_caasp_repo~#%$(escapeSubst "$CAASP_REPO")%g" \
    -e "s%#~placeholder_sshkey~#%$(escapeSubst "$SSHKEY")%g" \
    -e "s%#~placeholder_caasp_pattern~#%$(escapeSubst "$CAASP_PATTERN")%g" \
    "$(dirname "$0")/../cap-terraform/caasp4/terraform.tfvars.skel" > \
    "$WORKSPACE"/deployment/terraform.tfvars
sed -i '/\"\${openstack_networking_secgroup_v2\.secgroup.common\.name}\",/a \ \ \ \ "\${openstack_compute_secgroup_v2.secgroup_cap.name}",' \
    "$WORKSPACE"/deployment/worker-instance.tf

cp -r "$(dirname "$0")/../cap-terraform/caasp4"/* "$WORKSPACE"/deployment/

pushd "$WORKSPACE"/deployment
cd ~0

echo ">>> Deploying with terraform"
skuba-deploy --run-in-docker terraform init
skuba-deploy --run-in-docker terraform plan -out my-plan
skuba-deploy --run-in-docker terraform apply -auto-approve my-plan

echo ">>> Bootstrapping cluster with skuba"
export KUBECONFIG=
skuba-deploy --deploy
wait
cp "$WORKSPACE"/deployment/my-cluster/admin.conf "$WORKSPACE/kubeconfig"
export KUBECONFIG="$WORKSPACE"/kubeconfig
cp "$CF_CI_DIR"/qa-tools/misc/envrc "$WORKSPACE"/.envrc
echo ">>> Deployment at $WORKSPACE/deployment/"

echo ">>> Disabling automatic updates in cluster"
skuba-deploy --updates all disable
wait

echo ">>> Disabling automatic reboots in cluster"
skuba-deploy --reboots disable
wait

echo ">>> Enabling swapaccount on all nodes"
skuba-deploy --run-cmd all "sudo sed -i -r 's|^(GRUB_CMDLINE_LINUX_DEFAULT=)\"(.*.)\"|\1\"\2 cgroup_enable=memory swapaccount=1 \"|' /etc/default/grub"
wait
skuba-deploy --run-cmd all 'sudo grub2-mkconfig -o /boot/grub2/grub.cfg'
wait
skuba-deploy --run-cmd all 'sleep 2 && sudo nohup shutdown -r now > /dev/null 2>&1 &'
wait

echo ">>> Waiting for nodes to be up"
# skuba-deploy --wait-ssh all 100
sleep 100

# Create configmap:
PUBLIC_IP="$(skuba-deploy --run-in-docker terraform output ip_workers | cut -d, -f1 | head -n1)"
export PUBLIC_IP
# openstack images rootfs:
ROOTFS=overlay-xfs
export ROOTFS
NFS_SERVER_IP="$(skuba-deploy --run-in-docker terraform output ip_storage_int)"
export NFS_SERVER_IP
NFS_PATH="$(skuba-deploy --run-in-docker terraform output storage_share)"
export NFS_PATH

if kubectl get configmap -n kube-system 2>/dev/null | grep -qi cap-values; then
    echo ">>> Skipping creating configmap cap-values; already exists"
else
    echo ">>> Creating configmap cap-values"
    kubectl create configmap -n kube-system cap-values \
            --from-literal=public-ip="${PUBLIC_IP}" \
            --from-literal=garden-rootfs-driver="${ROOTFS}" \
            --from-literal=nfs-server-ip="${NFS_SERVER_IP}" \
            --from-literal=nfs-path="${NFS_PATH}" \
            --from-literal=platform=caasp4
fi

echo ">>> Deployed caasp4 on openstack. kubeconfig at $WORKSPACE/kubeconfig"
