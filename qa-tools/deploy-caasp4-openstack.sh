#!/usr/bin/env bash
set -exuo pipefail

usage() {
    echo "Deploys Caasp4 cluster on openstack, with an nfs server, and prepares
    it for CAP.
    Usage: $0 ---version CAASP_VERSION --openstack STACK
    CAASP_VERSION can be one of: devel, staging, product, update

    Requirements: a built skuba docker image, a sourced openrc.sh, a key on the
    ssh keyring"
}

# TODO add deployment folder for terraform deletion

# Parse options
while [[ $# -gt 0 ]] ; do
    case $1 in
        --version)
            export VERSION="${2:-devel}"
            ;;
        --openstack-stack)
            export STACK="${2:-$(whoami)-caasp4-cf-ci}"
            ;;
        -h|--help)
            echo usage
            exit 0
            ;;
    esac
    shift
done

export SKUBA_TAG="$VERSION"
SKUBA_DEPLOY_PATH=$(dirname "$(readlink -f "$0")")/skuba-deploy.sh
skuba-deploy() {
    bash "$SKUBA_DEPLOY_PATH" "$@"
}

TMPDIR=$(mktemp -d)

echo ">>> Extracting terraform files from skuba package"
docker run \
       --name skuba-"$VERSION" \
       --detach \
       --rm \
       skuba/"$VERSION" sleep infinity
docker cp \
       skuba-"$VERSION":/usr/share/caasp/terraform/openstack/. \
       "$TMPDIR"/deployment
docker rm -f skuba-"$VERSION"

# TODO change caasp repos
echo ">>> Copying our own terraform files"
sed -e "s%#~placeholder_stack~#%$STACK%g" \
    -e "s%#~placeholder_sshkey~#%$(ssh-add -L)%g" \
    "$(dirname "$0")/../cap-terraform/caasp4/terraform.tfvars.skel" > \
    "$TMPDIR"/deployment/terraform.tfvars
cp -r "$(dirname "$0")/../cap-terraform/caasp4"/* "$TMPDIR"/deployment/

# TODO add ssh key
# agent="$(pgrep ssh-agent -u "$USER")"
# if [[ "$agent" == "" ]]; then
#     eval "$(ssh-agent -s)"
# fi
# curl https://raw.githubusercontent.com/SUSE/skuba/master/ci/infra/id_shared -o "$TMPDIR"/id_rsa
# ssh-add "$TMPDIR"/id_rsa

# TODO source container-openrc.sh
# credentials for ecp? read from env meanwhile
# -v openstack_password="$(bosh int ../../secure/concourse-secrets.yml --path '/openstack-password')" \
# cloudfoundry/cloud.suse.de/bosh-deployment/bosh.pem.gpg
# qa-pipelines/config-ecp.yml ?

pushd "$TMPDIR"/deployment
cd ~0

echo ">>> Deploying with terraform"
skuba-deploy --run-in-docker terraform init
skuba-deploy --run-in-docker terraform plan -out my-plan
skuba-deploy --run-in-docker terraform apply -auto-approve my-plan

echo ">>> Deployment at "$TMPDIR"/deployment/"

echo ">>> Bootstrapping cluster with skuba"
export KUBECONFIG=
skuba-deploy --deploy

echo ">>> Disabling updates and reboots in cluster"
skuba-deploy --updates -all disable
skuba-deploy --reboots disable

export KUBECONFIG="$TMPDIR"/deployment/my-cluster/config
export PUBLIC_IP="$(skuba-deploy --run-in-docker terraform output ip_load_balancer)"
# openstack images rootfs:
export ROOTFS=overlay-xfs
export NFS_SERVER_IP="$(skuba-deploy --run-in-docker terraform output ip_storage_int)"
export NFS_PATH="$(skuba-deploy --run-in-docker terraform output storage_share)"

pushd "$TMPDIR"/deployment/my-cluster
cd ~0
echo ">>> Preparing cluster for CAP"
bash $(dirname "$(readlink -f "$0")")/prepare-caasp4.sh --public-ip "$PUBLIC_IP" --rootfs "$ROOTFS" --nfs-server-ip "$NFS_SERVER_IP"

popd
popd
cd ~0
