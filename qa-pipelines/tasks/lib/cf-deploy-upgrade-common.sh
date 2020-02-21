#!/bin/bash

# Set kube config from pool
source "ci/qa-pipelines/tasks/lib/prepare-kubeconfig.sh"

#UAA_PORT=2793

CF_NAMESPACE=kubecf
CFO_NAMESPACE=cfo
CAP_DIRECTORY=s3.scf-config
AWS_CLUSTER_CIDR=0.0.0.0/0
AWS_SERVICE_CLUSTER_IP_RANGE=10.0.0.0/24

# Set SCF_LOG_HOST for sys log brain tests
log_uid=$(hexdump -n 8 -e '2/4 "%08x"' /dev/urandom)
SCF_LOG_HOST="log-${log_uid}.${CF_NAMESPACE}.svc.cluster.local"

if [ -n "${CAP_BUNDLE_URL:-}" ]; then
    # For pre-upgrade deploys
    echo "Using CAP ${CAP_BUNDLE_URL}"
    curl ${CAP_BUNDLE_URL} -Lo cap-install-version.tgz
    export CAP_DIRECTORY=cap-install-version
    mkdir ${CAP_BUNDLE_URL}
    #unzip ${CAP_DIRECTORY}.zip -d ${CAP_DIRECTORY}/
    tar -xvzf ${CAP_DIRECTORY}.tgz -C ${CAP_DIRECTORY}/
else
    tar -xvzf ${CAP_DIRECTORY}/bundle-*.tgz -C ${CAP_DIRECTORY}/
fi

# Check that the kube of the cluster is reasonable
#bash ${CAP_DIRECTORY}/kube-ready-state-check.sh kube

cap_platform=${cap_platform:-$(kubectl get configmap -n kube-system cap-values -o json | jq -r .data.platform)}

# kube-system configmap exits only for non eks clusters
if [[ ${cap_platform} != "eks" ]] ; then
    garden_rootfs_driver=$(kubectl get configmap -n kube-system cap-values -o json | jq -r '.data["garden-rootfs-driver"] // "btrfs"')
fi

# Storage class named persistent
if kubectl get storageclass | grep "persistent" > /dev/null ; then
    STORAGECLASS="persistent"
    PROVISIONER=$(kubectl get storageclasses ${STORAGECLASS} -o "jsonpath={.provisioner}")
# Storage class for eks cluster not using persistent name for sc
elif [[ ${cap_platform} == "eks" ]] && kubectl get storageclass | grep gp2 > /dev/null ; then
    STORAGECLASS="gp2"
    PROVISIONER=$(kubectl get storageclasses ${STORAGECLASS} -o "jsonpath={.provisioner}")
    garden_rootfs_driver="overlay-xfs"
else
    echo "Your k8s cluster must have a SC named persistent or gp2"
    exit 1
fi

eks_lb_workaround() {
    # For eks clusters, use a kubectl patch to set health check port
    # Otherwise, AWS loadbalancer health checks fail when the TCP service doesn't expose port 8080
    if [[ ${cap_platform} == "eks" ]]; then
        healthcheck_port=$(kubectl get service kubecf-tcp-router-public -o jsonpath='{.spec.ports[?(@.name == "healthcheck")].port}' --namespace kubecf)
        if [ -z "${healthcheck_port}" ]; then
            kubectl patch service kubecf-tcp-router-public --namespace kubecf --type strategic --patch '{"spec": {"ports": [{"name": "healthcheck", "port": 8080}]}}'
        fi
    fi
}

# Outputs a json representation of a yml document
y2j() {
    if [[ -e ${1:-} ]]; then
        ruby -r json -r yaml -e "puts YAML.load_stream(File.read('$1')).to_json"
    else
        ruby -r json -r yaml -e 'puts (YAML.load_stream(ARGF.read).to_json)'
    fi
}

function semver_is_gte() {
  # Returns successfully if the left-hand semver is greater than or equal to the right-hand semver
  # lexical comparison doesn't work on semvers, e.g. 10.0.0 > 2.0.0
  [[ "$(echo -e "$1\\n$2" |
        sort -t '.' -k 1,1 -k 2,2 -k 3,3 -g |
        tail -n 1
    )" == "$1" ]]
}

# Get the version of the helm chart for uaa
#helm_chart_version() { grep "^version:"  ${CAP_DIRECTORY}/helm/uaa/Chart.yaml  | sed 's/version: *//g' ; }

# Helm parameters common to cfo and kubecf, for helm install and upgrades
set_helm_params() {
    :
}

# Method to customize kubecf.
set_kubecf_params() {
    HELM_PARAMS=(--set "system_domain=${DOMAIN}")
    if [[ "${HA:-false}" == true ]]; then
        #HELM_PARAMS+=(--set=config.HA=true)
        echo "HA is not yet implemented. This is SA deployment"
    fi
    if [[ ${cap_platform} == "eks" ]] ; then
        HELM_PARAMS+=(--set "kube.pod_cluster_ip_range=${AWS_CLUSTER_CIDR}")
        HELM_PARAMS+=(--set "kube.service_cluster_ip_range=${AWS_SERVICE_CLUSTER_IP_RANGE}")
    elif [[ ${cap_platform} == "gke" ]]; then
        HELM_PARAMS+=(--set "kube.pod_cluster_ip_range=${GKE_CLUSTER_CIDR}")
        HELM_PARAMS+=(--set "kube.service_cluster_ip_range=${GKE_SERVICE_CLUSTER_IP_RANGE}")
    elif [[ ${cap_platform} == "caasp4" ]]; then
        HELM_PARAMS+=(--set "kube.service_cluster_ip_range=0.0.0.0/0")
        HELM_PARAMS+=(--set "kube.pod_cluster_ip_range=0.0.0.0/0")
        echo "TODO: remove kube.service_cluster_ip_range and kube.pod_cluster_ip_range settings for CaaSP"
        for svc in router tcp-router ssh-proxy; do
            HELM_PARAMS+=(--set "services.${svc}.type=ClusterIP" --set "services.${svc}.clusterIP=${public_ip}")
        done
    fi

    #Credhub is enabled by default
    #HELM_PARAMS+=(--set "enable.credhub=${ENABLE_CREDHUB}")

    #HELM_PARAMS+=(--set "enable.autoscaler=${ENABLE_AUTOSCALER}")
    if [[ "${EXTERNAL_DB:-false}" == "true" ]]; then
        echo "EXTERNAL_DB is not yet implemented in CI"
        # HELM_PARAMS+=(--set "features.external_database.enabled=true")
        # HELM_PARAMS+=(--set "features.external_database.host=external-db-mariadb.external-db.svc.cluster.local")
        # HELM_PARAMS+=(--set "env.DB_EXTERNAL_PORT=3306")
        # HELM_PARAMS+=(--set "env.DB_EXTERNAL_USER=root")
        # HELM_PARAMS+=(--set "enable.mysql=false")
        # HELM_PARAMS+=(--set "secrets.DB_EXTERNAL_PASSWORD=${EXTERNAL_DB_PASS}")
    fi
    HELM_PARAMS+=(--set "testing.brain_tests.enabled=true")
    HELM_PARAMS+=(--set "testing.cf_acceptance_tests.enabled=true")
}

set -o allexport

# The internal/external and public IP addresses are now taken from the configmap set by prep-new-cluster
# The external_ip is set to the internal ip of a worker node. When running on openstack or azure,
# the public IP (used for DOMAIN) will be taken from the floating IP or load balancer IP.

public_ip="$(kubectl get configmap -n kube-system cap-values -o json | jq -r '.data["public-ip"] // ""')"

if [[ -n "${public_ip}" ]]; then
    # If we have a public IP in the config map, we assume this is openstack / bare metal / etc. and have
    # external IPs hard-coded.
    # Domain for SCF. DNS for *.DOMAIN must point to the same kube node
    # referenced by external_ip.
    DOMAIN=${public_ip}.${MAGIC_DNS_SERVICE}
    # We use external_ips in set_helm_params()
    external_ips=($(kubectl get nodes -o json | jq -r '.items[].status.addresses[] | select(.type == "InternalIP").address'))
else
    # If we do _not_ have a public IP, assume this is in the cloud™ somewhere and we will use Azure DNS
    source "ci/qa-pipelines/tasks/lib/azure-aks.sh"
    DOMAIN=${AZURE_AKS_RESOURCE_GROUP}.${AZURE_DNS_ZONE_NAME}
fi

#Set INSECURE_DOCKER_REGISTRIES for brain test
INSECURE_DOCKER_REGISTRIES=\"insecure-registry.tcp.${DOMAIN}:20005\"

# UAA host/port that SCF will talk to.
#UAA_HOST=uaa.${DOMAIN}

set +o allexport
