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
    echo "Your k8s cluster must have a SC named persistent or gp2"
    exit 1
fi

# Password for SCF to authenticate with UAA
UAA_ADMIN_CLIENT_SECRET="$(head -c32 /dev/urandom | base64)"

# Wait until CF namespaces are ready
is_namespace_ready() {
    local namespace="$1"

    # Check that all pods not from jobs are ready
    if kubectl get pods --namespace "${namespace}" --selector '!job-name' \
        --output 'custom-columns=:.status.containerStatuses[*].ready' \
        | grep --quiet false
    then
        return 1
    fi

    return 0
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
    local start now elapsed
    local release="$1"
    local namespace=$(helm list "${release}" | awk '$1=="'"$release"'" {print $NF}')
    start=$(date +%s)

    wait_for_jobs $release || exit 1

    # Wait for config map
    local secret_name=""
    while true ; do
        secret_name="$(kubectl get configmap -n "${namespace}" secrets-config -o jsonpath='{.data.current-secrets-name}')"
        if [[ -n "${secret_name}" ]] && kubectl get secrets -n "${namespace}" "${secret_name}" ; then
            break
        fi
        now=$(date +%s)
        elapsed="$((now - start))"
        if (( elapsed > 4800 )) ; then
            printf "\nTimed out waiting for %s config map (%s is %s seconds since start)\n" "${release}" "$(date --rfc-2822)" "${elapsed}"
        fi
        printf "\rWaiting for %s config map at %s (%ss)..." "${release}" "$(date --rfc-2822)" "${elapsed}"
        sleep 10
    done

    for (( i = 0  ; i < 480 ; i ++ )) ; do
        if is_namespace_ready "${namespace}" ; then
            break
        fi
        now=$(date +%s)
        printf "\rWaiting for %s pods at %s (%ss)..." "${release}" "$(date --rfc-2822)" $((now - start))
        sleep 10
    done

    now=$(date +%s)
    printf "\rDone waiting for %s pods at %s (%ss)\n" "${release}" "$(date --rfc-2822)" $((now - start))
    kubectl get pods --namespace="${namespace}"
    if ! is_namespace_ready "${namespace}" && [[ $i -eq 480 ]]; then
        kubectl get pods --namespace "${namespace}" --selector '!job-name' \
            --output 'custom-columns=NAME:.metadata.name,CONTAINERS:.status.containerStatuses[*].name,READY:.status.containerStatuses[*].ready' \
            | grep -E 'READY|false' \
            || true
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

get_uaa_ca_cert() (
    local uaa_secret_name
    uaa_secret_name="$(kubectl get configmap --namespace "${UAA_NAMESPACE}" secrets-config -o jsonpath='{.data.current-secrets-name}')"
    if [[ -z "${uaa_secret_name}" ]] ; then
        echo "Failed to get UAA secret name" >&2
        exit 1
    fi
    local cert_data
    cert_data="$(kubectl get secret "${uaa_secret_name}" \
      --namespace "${UAA_NAMESPACE}" \
      -o jsonpath="{.data['internal-ca-cert']}")"
    if [[ -z "${cert_data}" ]]; then
        echo "Failed to get UAA CA certificate from secret ${uaa_secret_name}" >&2
        exit 1
    fi
    base64 -d <<< "${cert_data}"
)

# Helm parameters common to UAA and SCF, for helm install and upgrades
set_helm_params() {
    HELM_PARAMS=(--set "env.DOMAIN=${DOMAIN}"
                 --set "secrets.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}"
                 --set "enable.autoscaler=true"
                 --set "kube.storage_class.persistent=${STORAGECLASS}")
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
    if [[ "${EMBEDDED_UAA:-false}" == "true" ]]; then
        HELM_PARAMS+=(--set "enable.uaa=true")
    fi
    if [[ -n "${KUBE_REGISTRY_HOSTNAME:-}" ]]; then
        HELM_PARAMS+=(--set "kube.registry.hostname=${KUBE_REGISTRY_HOSTNAME%/}")
    fi
    if [[ -n "${KUBE_REGISTRY_USERNAME:-}" ]]; then
        HELM_PARAMS+=(--set "kube.registry.username=${KUBE_REGISTRY_USERNAME}")
    fi
    if [[ -n "${KUBE_REGISTRY_PASSWORD:-}" ]]; then
        HELM_PARAMS+=(--set "kube.registry.password=${KUBE_REGISTRY_PASSWORD}")
    fi
    if [[ -n "${KUBE_ORGANIZATION:-}" ]]; then
        HELM_PARAMS+=(--set "kube.organization=${KUBE_ORGANIZATION}")
    fi
    HELM_PARAMS+=(--set "env.GARDEN_ROOTFS_DRIVER=${garden_rootfs_driver}")
}

set_uaa_sizing_params() {
    if [[ "${HA}" == true ]]; then
        if [[ ${SCALED_HA} == true ]]; then
            HELM_PARAMS+=(--set=sizing.{uaa,mysql}.count=2)
        else
            # HA UAA not supported prior to 2.11.0
            HELM_PARAMS+=(--set=config.HA=true)
        fi
    fi
}

set_scf_sizing_params() {
    if [[ ${cap_platform} == "eks" ]] ; then
        HELM_PARAMS+=(--set=sizing.{cc_uploader,nats,routing_api,router,diego_brain,diego_api,diego_ssh}.capabilities[0]="SYS_RESOURCE")
    elif [[ ${HA} == true ]]; then
        if [[ ${SCALED_HA} == true ]]; then
            HELM_PARAMS+=(
                #--set=sizing.{autoscaler_postgres,bits,blobstore,credhub_user}.count=1
                --set=sizing.diego_cell.count=3
                --set=sizing.{adapter,api_group,autoscaler_actors,autoscaler_api,autoscaler_metrics,cc_clock,cc_uploader,cc_worker,cf_usb_group,diego_api,diego_brain,diego_cell,diego_ssh,doppler,locket,log_api,log_cache_scheduler,mysql,nats,nfs_broker,router,routing_api,syslog_scheduler,tcp_router}.count=2
            )
        else
            HELM_PARAMS+=(--set=config.HA=true)
        fi
    fi
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
UAA_HOST=uaa.${DOMAIN}

set +o allexport
