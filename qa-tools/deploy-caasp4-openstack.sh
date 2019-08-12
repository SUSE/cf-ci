#!/usr/bin/env bash
set -euo pipefail

# Deploys Caasp4 cluster on openstack, with an nfs server, and prepares
# it for CAP.
# Creates WORKSPACE folder.
#
# Expected env var           Eg:
#   VERSION                  devel, staging, product, update
#   STACK                    yourname-cf-ci
#   WORKSPACE                deployment-caasp4. Defaults to deployment-$STACK
#
# Requirements:
# - Built skuba docker image
# - Sourced openrc.sh
# - Key on the ssh keyring. If not, will put one

if [[ ! -v VERSION ]]; then
    export VERSION="devel"
fi
if [[ ! -v STACK ]]; then
    STACK="$(whoami)-caasp4-cf-ci"
    export STACK
fi
if [[ ! -v WORKSPACE ]]; then
    WORKSPACE="$(pwd)/deployment-$STACK"
    export WORKSPACE
    mkdir "$WORKSPACE"
fi

export SKUBA_TAG="$VERSION"
SKUBA_DEPLOY_PATH=$(dirname "$(readlink -f "$0")")/skuba-deploy.sh
skuba-deploy() {
    bash "$SKUBA_DEPLOY_PATH" "$@"
}


# check ssh key
agent="$(pgrep ssh-agent -u "$USER")"
if [[ "$agent" == "" ]]; then
    eval "$(ssh-agent -s)"
fi
if ! ssh-add -L | grep -q 'ssh' ; then
    echo ">>> Adding ssh key"
    curl https://raw.githubusercontent.com/SUSE/skuba/master/ci/infra/id_shared -o id_rsa \
        && chmod 0600 id_rsa
    ssh-add "$WORKSPACE"/id_rsa
fi

if [[ ! -v OS_PASSWORD ]]; then
    echo ">>> Missing openstack credentials" && exit 1
fi
# TODO
# credentials for ecp? read from env meanwhile
# -v openstack_password="$(bosh int ../../secure/concourse-secrets.yml --path '/openstack-password')" \
    # cloudfoundry/cloud.suse.de/bosh-deployment/bosh.pem.gpg
# qa-pipelines/config-ecp.yml ?

echo ">>> Extracting terraform files from skuba package"
docker run \
       --name skuba-"$VERSION" \
       --detach \
       --rm \
       skuba/"$VERSION" sleep infinity
docker cp \
       skuba-"$VERSION":/usr/share/caasp/terraform/openstack/. \
       "$WORKSPACE"/deployment
docker rm -f skuba-"$VERSION"

echo ">>> Copying our own terraform files"
case "$VERSION" in
    "devel")
         CAASP_REPO='caasp_40_devel_sle15sp1 = "http://download.suse.de/ibs/Devel:/CaaSP:/4.0/SLE_15_SP1/"'
         ;;
    "staging")
         CAASP_REPO='caasp_40_staging_sle15sp1 = "http://download.suse.de/ibs/SUSE:/SLE-15-SP1:/Update:/Products:/CASP40/staging/"'
         ;;
    "product")
         CAASP_REPO="TODO"
         CAASP_REPO='caasp_40_product_sle15sp1 = "http://download.suse.de/ibs/SUSE:/SLE-15-SP1:/Update:/Products:/CASP40/standard/"'
         ;;
    "update")
         CAASP_REPO='caasp_40_update_sle15sp1 = "http://download.suse.de/ibs/SUSE:/SLE-15-SP1:/Update:/Products:/CASP40:/Update/standard/"'
         ;;
esac
echo ">>>>>> Using $CAASP_REPO"
sed -e "s%#~placeholder_stack~#%$STACK%g" \
    -e "s%#~placeholder_caasp_repo~#%$CAASP_REPO%g" \
    -e "s%#~placeholder_sshkey~#%$(ssh-add -L)%g" \
    "$(dirname "$0")/../cap-terraform/caasp4/terraform.tfvars.skel" > \
    "$WORKSPACE"/deployment/terraform.tfvars

cp -r "$(dirname "$0")/../cap-terraform/caasp4"/* "$WORKSPACE"/deployment/

pushd "$WORKSPACE"/deployment
cd ~0

echo ">>> Deploying with terraform"
skuba-deploy --run-in-docker terraform init
skuba-deploy --run-in-docker terraform plan -out my-plan
skuba-deploy --run-in-docker terraform apply -auto-approve my-plan

echo ">>> Deployment at $WORKSPACE/deployment/"

echo ">>> Bootstrapping cluster with skuba"
export KUBECONFIG=
skuba-deploy --deploy
wait

export KUBECONFIG="$WORKSPACE"/deployment/my-cluster/admin.conf

echo ">>> Disabling automatic updates in cluster"
skuba-deploy --updates all disable
wait

echo ">>> Disabling automatic reboots in cluster"
skuba-deploy --reboots disable
wait

echo ">>> Enabling swapaccount on all nodes"
skuba-deploy --run-cmd all "sudo sed -i -r 's|^(GRUB_CMDLINE_LINUX_DEFAULT=)\"(.*.)\"|\1\"\2 swapaccount=1 \"|' /etc/default/grub && \
sudo grub2-mkconfig -o /boot/grub2/grub.cfg && \
sudo shutdown -r now &
"
wait

echo ">>> Waiting for nodes to be up"
sleep 100

PUBLIC_IP="$(skuba-deploy --run-in-docker terraform output ip_load_balancer)"
export PUBLIC_IP
# openstack images rootfs:
ROOTFS=overlay-xfs
export ROOTFS

NFS_SERVER_IP="$(skuba-deploy --run-in-docker terraform output ip_storage_int)"
export NFS_SERVER_IP
NFS_PATH="$(skuba-deploy --run-in-docker terraform output storage_share)"
export NFS_PATH

popd
cd ~0

echo ">>> Preparing cluster for CAP"
bash "$(dirname "$(readlink -f "$0")")"/prepare-caasp4.sh

cp "$KUBECONFIG" "$WORKSPACE/kubeconfig"
echo ">>> Done. kubeconfig at $WORKSPACE/kubeconfig"
