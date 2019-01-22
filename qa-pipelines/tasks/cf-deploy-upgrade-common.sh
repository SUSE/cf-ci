#!/bin/bash

# Set kube config from pool
mkdir -p /root/.kube/
cp pool.kube-hosts/metadata /root/.kube/config

UAA_PORT=2793

CF_NAMESPACE=scf
UAA_NAMESPACE=uaa
CAP_DIRECTORY=s3.scf-config

if [ -n "${CAP_INSTALL_VERSION:-}" ]; then
    # For pre-upgrade deploys
    echo "Using CAP ${CAP_INSTALL_VERSION}"
    curl ${CAP_INSTALL_VERSION} -Lo cap-install-version.zip
    export CAP_DIRECTORY=cap-install-version
    unzip ${CAP_DIRECTORY}.zip -d ${CAP_DIRECTORY}/
else
    unzip ${CAP_DIRECTORY}/scf-*.zip -d ${CAP_DIRECTORY}/
fi

# Check that the kube of the cluster is reasonable
bash ${CAP_DIRECTORY}/kube-ready-state-check.sh kube

PROVISIONER=$(kubectl get storageclasses persistent -o "jsonpath={.provisioner}")

# Password for SCF to authenticate with UAA
UAA_ADMIN_CLIENT_SECRET="$(head -c32 /dev/urandom | base64)"

# Wait until CF namespaces are ready
is_namespace_ready() {
    local namespace="$1"

    if [[ $(helm_chart_version) == "2.10.1" ]]; then
        # Create regular expression to match active_passive_pods
        # These are scaled services which were expected to only have one pod listed as ready prior to 2.11.0
        local active_passive_pod_regex='^diego-api$|^diego-brain$|^routing-api$'
        local active_passive_role_count=$(awk -F '|' '{ print NF }' <<< "${active_passive_pod_regex}")
    else
        local active_passive_pod_regex='$a' # A regex that will never match anything
        local active_passive_role_count=0
    fi

    # Get the container name and status for each pod in two columns
    # The name here will be the role name, not the pod name, e.g. 'diego-brain' not 'diego-brain-1'
    local active_passive_pod_status=$(2>/dev/null kubectl get pods --namespace=${namespace} --output=custom-columns=':.status.containerStatuses[].name,:.status.containerStatuses[].ready' \
        | awk '$1 ~ '"/${active_passive_pod_regex}/")

    # Check that the number of containers which are ready is equal to the number of active passive roles
    if [[ -n $active_passive_pod_status ]] && [[ $(echo "$active_passive_pod_status" | grep true | wc -l) -ne ${active_passive_role_count} ]]; then
        return 1
    fi

    # Finally, check that all pods which do not match the active_passive_pod_regex are ready
    [[ true == $(2>/dev/null kubectl get pods --namespace=${namespace} --output=custom-columns=':.status.containerStatuses[].name,:.status.containerStatuses[].ready' \
        | grep -vE 'secret-generation|post-deployment' \
        | awk '$1 !~ '"/${active_passive_pod_regex}/ { print \$2 }" \
        | sed '/^ *$/d' \
        | sort \
        | uniq) ]]
}
wait_for_jobs() {
    local release=$1
    local jobs_desired_remaining
    start=$(date +%s)
    for (( i = 0 ; i < 480 ; i ++ )); do
        # Get the list of all jobs in the helm release, and subtract the value of 'completed' from 'desired'
        # It would be better to parse this from `helm get manifest`, but since that command is broken in helm 
        # v2.8.2 (https://github.com/helm/helm/issues/3833) for now we'll parse it from the human-readable status
        jobs_desired_remaining=$(helm status $release | awk '/==> v1\/Job/ { getline; getline; while (NF>0) { print $2 - $3; getline } }')
        now=$(date +%s)
        if [[ $(echo "${jobs_desired_remaining}" | sort -n | tail -1) -le 0 ]]; then
           printf "\rDone waiting for %s jobs at %s (%ss)..." "${release}" "$(date --rfc-2822)" $((${now} - ${start}))
           return 0
        else
           sleep 10
        fi
        printf "\rWaiting for %s jobs at %s (%ss)..." "${release}" "$(date --rfc-2822)" $((${now} - ${start}))
    done
    printf "%s jobs not completed\n" "${release}"
    return 1
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
    if ! is_namespace_ready "${namespace}" ; then
        printf "%s pods are still pending\n" "${release}"
        exit 1
    fi
}

function semver_is_gte() {
  # Returns successfully if the left-hand semver is greater than or equal to the right-hand semver
  # lexical comparison doesn't work on semvers, e.g. 10.0.0 > 2.0.0
  [[ "$(echo -e "$1\n$2" |
        sort -t '.' -k 1,1 -k 2,2 -k 3,3 -g |
        tail -n 1
    )" == $1 ]]
}

# Get the version of the helm chart for uaa
helm_chart_version() { grep "^version:"  ${CAP_DIRECTORY}/helm/uaa${CAP_CHART}/Chart.yaml  | sed 's/version: *//g' ; }

generated_secrets_secret() { kubectl get --namespace "${UAA_NAMESPACE}" secrets --output "custom-columns=:.metadata.name" | grep -F "secrets-$(helm_chart_version)-" | sort | tail -n 1 ; }

get_internal_ca_cert() (
    set -o pipefail
    local uaa_secret_name=$(generated_secrets_secret)
    kubectl get secret ${uaa_secret_name} \
      --namespace "${UAA_NAMESPACE}" \
      -o jsonpath="{.data['internal-ca-cert']}" \
      | base64 -d
)

set_psp() {
    HELM_PARAMS+=(--set "kube.psp.nonprivileged=suse.cap.psp.nonprivileged")
    HELM_PARAMS+=(--set "kube.psp.privileged=suse.cap.psp.privileged")
}

set_helm_params() {
    HELM_PARAMS=(--set "env.DOMAIN=${DOMAIN}"
                 --set "secrets.UAA_ADMIN_CLIENT_SECRET=${UAA_ADMIN_CLIENT_SECRET}"
                 --set "sizing.credhub_user.count=1")

    for (( i=0; i < ${#external_ips[@]}; i++ )); do
        HELM_PARAMS+=(--set "kube.external_ips[$i]=${external_ips[$i]}")
    done
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

    set_psp # Sets PSP
}

set_uaa_sizing_params() {
    # if [[ ${HA} == true ]]; then
    #     if semver_is_gte $(helm_chart_version) 2.11.0; then
    #         # HA UAA not supported prior to 2.11.0
    #         HELM_PARAMS+=(--set=config.HA=true)
    #     fi
    # elif [[ ${SCALED_HA} == true ]]; then
    #     HELM_PARAMS+=(--set=sizing.{uaa,mysql,mysql_proxy}.count=3)
    # fi
    :
}

set_scf_sizing_params() {
    if [[ ${HA} == true ]]; then
        if semver_is_gte $(helm_chart_version) 2.11.0; then
            HELM_PARAMS+=(--set=config.HA=true)
        else
            HELM_PARAMS+=(--set=sizing.HA=true)
        fi
    elif [[ ${SCALED_HA} == true ]]; then
        HELM_PARAMS+=(--set=sizing.routing_api.count=1)
        HELM_PARAMS+=(--set=sizing.{api,cc_uploader,cc_worker,cf_usb,diego_access,diego_brain,doppler,loggregator,mysql,nats,router,syslog_adapter,syslog_rlp,tcp_router,mysql_proxy}.count=2)
        HELM_PARAMS+=(--set=sizing.{diego_api,diego_locket,diego_cell}.count=3)
    fi
}

set -o allexport

# The internal/external and public IP addresses are now taken from the configmap set by prep-new-cluster
# The external_ip is set to the internal ip of a worker node. When running on openstack or azure,
# the public IP (used for DOMAIN) will be taken from the floating IP or load balancer IP.
external_ips=($(kubectl get configmap -n kube-system cap-values -o json | jq -r '.data["internal-ip"]'))
if [[ $(kubectl get configmap -o json -n kube-system cap-values  | jq -r .data.platform) == openstack ]]; then
  external_ips+=($(kubectl get nodes -o json | jq -r '.items[].status.addresses[] | select(.type == "InternalIP").address'))
fi
public_ip=$(kubectl get configmap -n kube-system cap-values -o json | jq -r '.data["public-ip"]')
garden_rootfs_driver=$(kubectl get configmap -n kube-system cap-values -o json | jq -r '.data["garden-rootfs-driver"] // "btrfs"')

# Domain for SCF. DNS for *.DOMAIN must point to the same kube node
# referenced by external_ip.
DOMAIN=${public_ip}.${MAGIC_DNS_SERVICE}

# UAA host/port that SCF will talk to.
UAA_HOST=uaa.${DOMAIN}

set +o allexport
