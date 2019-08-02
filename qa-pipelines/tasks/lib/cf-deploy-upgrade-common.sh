#!/bin/bash

# Set kube config from pool
source "ci/qa-pipelines/tasks/lib/prepare-kubeconfig.sh"

UAA_PORT=2793

CF_NAMESPACE=scf
UAA_NAMESPACE=uaa
CAP_DIRECTORY=s3.scf-config

# Set SCF_LOG_HOST for sys log brain tests
log_uid=$(hexdump -n 8 -e '2/4 "%08x"' /dev/urandom)
SCF_LOG_HOST="log-${log_uid}.${CF_NAMESPACE}.svc.cluster.local"

if [ -n "${CAP_BUNDLE_URL:-}" ]; then
    # For pre-upgrade deploys
    echo "Using CAP ${CAP_BUNDLE_URL}"
    curl ${CAP_BUNDLE_URL} -Lo cap-install-version.zip
    export CAP_DIRECTORY=cap-install-version
    unzip ${CAP_DIRECTORY}.zip -d ${CAP_DIRECTORY}/
else
    unzip ${CAP_DIRECTORY}/*scf-*.zip -d ${CAP_DIRECTORY}/
fi

# Check that the kube of the cluster is reasonable
bash ${CAP_DIRECTORY}/kube-ready-state-check.sh kube

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
    echo "Your k8s cluster must have a SC named persitent or gp2"
    exit 1
fi

# Password for SCF to authenticate with UAA
UAA_ADMIN_CLIENT_SECRET="$(head -c32 /dev/urandom | base64)"

# Wait until CF namespaces are ready
is_namespace_ready() {
    local namespace="$1"

    # Check that all pods which were not created by jobs are ready
    [[ true == $(2>/dev/null kubectl get pods --namespace=${namespace} --output=custom-columns=':.status.containerStatuses[].name,:.status.containerStatuses[].ready' \
        | grep -vE 'secret-generation|post-deployment' \
        | awk '{ print $2 }' \
        | sed '/^ *$/d' \
        | sort \
        | uniq) ]]
}

# Outputs a json representation of a yml document
y2j() {
    if [[ -e ${1:-} ]]; then
        ruby -r json -r yaml -e "puts YAML.load_stream(File.read('$1')).to_json"
    else
        ruby -r json -r yaml -e 'puts (YAML.load_stream(ARGF.read).to_json)'
    fi
}

wait_for_jobs() {
    local release=${1}
    local namespace=$(helm status ${release} -o json | jq -r .namespace)
    local jobs_in_namespace=$(helm get manifest ${release} | y2j | jq -r '.[] | select(.kind=="Job").metadata.name')
    local job seconds_remaining time_since_start kubectl_wait_status
    local start=$(date +%s)
    for job in ${jobs_in_namespace}; do
        echo "waiting for job ${job}"
        seconds_remaining=$(( 4800 + ${start} - $(date +%s) ))
        set +o errexit
        kubectl wait job ${job} --namespace ${namespace} --for=condition=complete --timeout ${seconds_remaining}s
        kubectl_wait_status=$?
        set -o errexit
        time_since_start=$(( $(date +%s) - ${start} ))
        if [[ ${kubectl_wait_status} -eq 0 ]]; then
            echo "Done waiting for ${release} jobs at $(date --rfc-2822) (${time_since_start}s)"
        elif [[ ${time_since_start} -ge 4800 ]]; then
            echo "${release} job ${job} not completed due to timeout"
            return 1
        else
            echo "waiting for ${release} job ${job} failed with exit status ${kubectl_wait_status}"
            return 1
        fi
    done
}

wait_for_release() {
    local release="$1"
    local namespace=$(helm list "${release}" | awk '$1=="'"$release"'" {print $NF}')
    start=$(date +%s)
    wait_for_jobs $release || exit 1
    for (( i = 0  ; i < 480 ; i ++ )) ; do
        if is_namespace_ready "${namespace}" ; then
            break
        fi
        now=$(date +%s)
        printf "\rWaiting for %s pods at %s (%ss)..." "${release}" "$(date --rfc-2822)" $((${now} - ${start}))
        sleep 10
    done
    now=$(date +%s)
    printf "\rDone waiting for %s pods at %s (%ss)\n" "${release}" "$(date --rfc-2822)" $((${now} - ${start}))
    kubectl get pods --namespace="${namespace}"
    if ! is_namespace_ready "${namespace}" && [[ $i -eq 480 ]]; then
        printf "%s pods are still pending after 80 minutes \n" "${release}"
        exit 1
    fi

    # For eks clusters, use a kubectl patch to set health check port
    # Otherwise, AWS loadbalancer health checks fail when the TCP service doesn't expose port 8080
    if [[ ${cap_platform} == "eks" &&  ${namespace} == "scf" ]]; then
        healthcheck_port=$(kubectl get service tcp-router-tcp-router-public -o jsonpath='{.spec.ports[?(@.name == "healthcheck")].port}' --namespace scf)
        if [ -z "${healthcheck_port}" ]; then
            kubectl patch service tcp-router-tcp-router-public --namespace scf --type strategic --patch '{"spec": {"ports": [{"name": "healthcheck", "port": 8080}]}}'
        fi
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
helm_chart_version() { grep "^version:"  ${CAP_DIRECTORY}/helm/uaa/Chart.yaml  | sed 's/version: *//g' ; }

generated_secrets_secret() { kubectl get --namespace "${UAA_NAMESPACE}" secrets --output "custom-columns=:.metadata.name" | grep -F "secrets-$(helm_chart_version)-" | sort | tail -n 1 ; }

get_internal_ca_cert() (
    set -o pipefail
    local uaa_secret_name=$(generated_secrets_secret)
    kubectl get secret ${uaa_secret_name} \
      --namespace "${UAA_NAMESPACE}" \
      -o jsonpath="{.data['internal-ca-cert']}" \
      | base64 -d
)

# Helm parameters common to UAA and SCF, for helm install and upgrades
set_helm_params() {
    HELM_PARAMS=(--set "env.DOMAIN=${DOMAIN}"
                 --set "secrets.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}"
                 --set "enable.autoscaler=true"
                 --set "kube.storage_class.persistent=${STORAGECLASS}")

    # CAP-370. Let the CC give brokers 10 minutes to respond with
    # their catalog. We have seen minibroker in the brain tests
    # require 4.5 minutes to assemble such, likely due to a slow
    # network. Doubling that should be generous enough. Together with
    # the doubled brain test timeout (see `run-test.sh`), such tests
    # will then still have the normal 10 minutes for any remaining
    # actions.
    HELM_PARAMS+=(--set "env.BROKER_CLIENT_TIMEOUT_SECONDS=600")

    if [[ ${cap_platform} == "eks" ]] ; then
        HELM_PARAMS+=(--set "kube.storage_class.shared=${STORAGECLASS}")
        HELM_PARAMS+=(--set "env.GARDEN_APPARMOR_PROFILE=")
    fi

    if [[ $(helm_chart_version) == "2.15.2" ]]; then
        HELM_PARAMS+=(--set "sizing.credhub_user.count=1")
    else
        HELM_PARAMS+=(--set "enable.credhub=true")
    fi

    if [[ ${cap_platform} == "azure" ]] || [[ ${cap_platform} == "gke" ]] ||
     [[ ${cap_platform} == "eks" ]]; then
        HELM_PARAMS+=(--set "services.loadbalanced=true")
    else
        for (( i=0; i < ${#external_ips[@]}; i++ )); do
            HELM_PARAMS+=(--set "kube.external_ips[$i]=${external_ips[$i]}")
        done
    fi
    if [ -n "${KUBE_REGISTRY_HOSTNAME:-}" ]; then
        HELM_PARAMS+=(--set "kube.registry.hostname=${KUBE_REGISTRY_HOSTNAME%/}")
    fi
    if [ -n "${KUBE_REGISTRY_USERNAME:-}" ]; then
        HELM_PARAMS+=(--set "kube.registry.username=${KUBE_REGISTRY_USERNAME}")
    fi
    if [ -n "${KUBE_REGISTRY_PASSWORD:-}" ]; then
        HELM_PARAMS+=(--set "kube.registry.password=${KUBE_REGISTRY_PASSWORD}")
    fi
    if [ -n "${KUBE_ORGANIZATION:-}" ]; then
        HELM_PARAMS+=(--set "kube.organization=${KUBE_ORGANIZATION}")
    fi
    HELM_PARAMS+=(--set "env.GARDEN_ROOTFS_DRIVER=${garden_rootfs_driver}")
}

set_uaa_sizing_params() {
    return 0 # Sizing UAA up breaks CATS
    if [[ "${HA}" == true ]]; then
        if semver_is_gte "$(helm_chart_version)" 2.11.0; then
            # HA UAA not supported prior to 2.11.0
            HELM_PARAMS+=(--set=config.HA=true)
        fi
    elif [[ ${SCALED_HA} == true ]]; then
        HELM_PARAMS+=(--set=sizing.{uaa,mysql,mysql_proxy}.count=3)
    fi
}

set_scf_sizing_params() {
    if [[ ${cap_platform} == "eks" ]] ; then
        HELM_PARAMS+=(--set=sizing.{cc_uploader,nats,routing_api,router,diego_brain,diego_api,diego_ssh}.capabilities[0]="SYS_RESOURCE")
    fi
    case "${HA}" in
    true)
        if semver_is_gte "$(helm_chart_version)" 2.11.0; then
            HELM_PARAMS+=(--set=config.HA=true)
        else
            HELM_PARAMS+=(--set=sizing.HA=true)
        fi
        ;;
    scaled)
        HELM_PARAMS+=(
            --set=sizing.routing_api.count=1
            --set=sizing.{api,cc_uploader,cc_worker,cf_usb,diego_access,diego_brain,doppler,loggregator,mysql,nats,router,syslog_adapter,syslog_rlp,tcp_router,mysql_proxy}.count=2
            --set=sizing.{diego_api,diego_locket,diego_cell}.count=3
        )
        ;;
    esac
}

set -o allexport

# The internal/external and public IP addresses are now taken from the configmap set by prep-new-cluster
# The external_ip is set to the internal ip of a worker node. When running on openstack or azure,
# the public IP (used for DOMAIN) will be taken from the floating IP or load balancer IP.

if [[ ${cap_platform} == caasp3 || ${cap_platform} == caasp4 || ${cap_platform} == bare ]]; then
  external_ips=($(kubectl get nodes -o json | jq -r '.items[].status.addresses[] | select(.type == "InternalIP").address'))
  public_ip=$(kubectl get configmap -n kube-system cap-values -o json | jq -r '.data["public-ip"]')
fi


if [[ ${cap_platform} =~ ^azure$|^gke$|^eks$ ]]; then
    source "ci/qa-pipelines/tasks/lib/azure-aks.sh"
    DOMAIN=${AZURE_AKS_RESOURCE_GROUP}.${AZURE_DNS_ZONE_NAME}
else
    # Domain for SCF. DNS for *.DOMAIN must point to the same kube node
    # referenced by external_ip.
    DOMAIN=${public_ip}.${MAGIC_DNS_SERVICE}
fi

#Set INSECURE_DOCKER_REGISTRIES for brain test
INSECURE_DOCKER_REGISTRIES=\"insecure-registry.tcp.${DOMAIN}:20005\"

# UAA host/port that SCF will talk to.
UAA_HOST=uaa.${DOMAIN}

set +o allexport
