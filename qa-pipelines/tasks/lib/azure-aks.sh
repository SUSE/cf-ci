#!/bin/bash

set -eu # errexit, nounset

# Outputs a json representation of a yml document
y2j() {
    if [[ -e ${1:-} ]]; then
        ruby -r json -r yaml -e "puts YAML.load_stream(File.read('$1')).to_json"
    else
        ruby -r json -r yaml -e 'puts (YAML.load_stream(ARGF.read).to_json)'
    fi
}

az_login() {
    if ! az login --service-principal -u ${AZ_SP_APPID} --password ${AZ_SP_PASSWORD} --tenant ${AZ_SP_TENANT}; then
        echo "Azure login error"
        exit 1
    fi
}

AZURE_DNS_ZONE_NAME=susecap.net
AZURE_DNS_RESOURCE_GROUP=susecap-domain
if grep "eks.amazonaws.com" ~/.kube/config; then
    AZURE_AKS_RESOURCE_GROUP=$(y2j ~/.kube/config | jq -r .[0].clusters[0].name | cut -d / -f 2)
elif grep "gke" ~/.kube/config; then
     AZURE_AKS_RESOURCE_GROUP=${GKE_CLUSTER_NAME}
else
    AZURE_AKS_RESOURCE_GROUP=$(kubectl get configmap -n kube-system -o json cap-values | jq -r '.data["resource-group"]')
fi

azure_dns_clear() {
    local matching_record_sets matching_record_set
    matching_record_sets=$(
        az network dns record-set a list \
            --output tsv \
            --resource-group ${AZURE_DNS_RESOURCE_GROUP} \
            --zone-name ${AZURE_DNS_ZONE_NAME} \
            --query "[?name | ends_with(@, '.${AZURE_AKS_RESOURCE_GROUP}')].name" -o tsv
    )
    matching_record_sets="${matching_record_sets} ${AZURE_AKS_RESOURCE_GROUP}"
    for matching_record_set in ${matching_record_sets}; do
        az network dns record-set a delete \
            --yes \
            --resource-group ${AZURE_DNS_RESOURCE_GROUP} \
            --zone-name ${AZURE_DNS_ZONE_NAME} \
            --name ${matching_record_set}
    done
}
lbs_info() {
    kubectl get svc -n $namespace -o json |
    jq -c '
    [
      .items[] | select(.spec.type == "LoadBalancer") | {
        "svc": .metadata.name,
        "ip": .status.loadBalancer.ingress[0].ip,
        "hostname": .status.loadBalancer.ingress[0].hostname
       }
    ]'
}
uaa_lb_info() {
    kubectl get svc -n $namespace -o json |
    jq -c '
    [
      .items[] | select(.spec.type == "LoadBalancer") |
      select(.metadata.name == "uaa-uaa-public") | {
        "svc": .metadata.name,
        "ip": .status.loadBalancer.ingress[0].ip,
        "hostname": .status.loadBalancer.ingress[0].hostname
       }
    ]'
}

azure_check_lbs_ready_in_namespace() {
    # checks that all LoadBalancer type services in namespace have an ingress IP
    local namespace=$1
    local lb_name=${2:-""}
    local lb_info lb_count lb_ready_count
    if [[ -z "$lb_name" ]]; then
        lb_info=$(lbs_info)
    elif [[ ${lb_name} == "uaa-uaa-public" ]]; then
        lb_info=$(uaa_lb_info)
    fi

    lb_count=$(echo "${lb_info}" | jq length)
    if [[ ${cap_platform} == "eks" ]]; then
        lb_ready_count=$(echo "${lb_info}" | jq -r '[.[] | select(.hostname)] | length')
    else
        lb_ready_count=$(echo "${lb_info}" | jq -r '[.[] | select(.ip)] | length')
    fi
    [[ ${lb_count} -eq ${lb_ready_count} ]]
}

azure_wait_for_lbs_in_namespace() {
    local namespace=$1
    local lb_name=${2:-""}
    local count=0
    while ! azure_check_lbs_ready_in_namespace $namespace $lb_name; do
        if [[ -z "$lb_name" ]]; then
            sleep 30
        else
            sleep 180
        fi
        ((count++))
        if [[ $count -eq 10 ]]; then
            echo "Load balancers for $namespace not ready" >&2
            return 1
        fi
    done
}

azure_set_record() {
    local lb_hostname=$(jq -r .hostname <<< $2)
    local lb_ip=$(jq -r .ip <<< $2)
    if [[ ${cap_platform} == "eks" ]]; then
        az network dns record-set cname create \
            --resource-group ${AZURE_DNS_RESOURCE_GROUP} \
            --zone-name ${AZURE_DNS_ZONE_NAME} \
            --name $1 \
            --ttl 300

        az network dns record-set cname set-record \
            --resource-group ${AZURE_DNS_RESOURCE_GROUP} \
            --zone-name ${AZURE_DNS_ZONE_NAME} \
            --record-set-name $1 \
            --cname $lb_hostname
    else
        az network dns record-set a create \
            --resource-group ${AZURE_DNS_RESOURCE_GROUP} \
            --zone-name ${AZURE_DNS_ZONE_NAME} \
            --name $1 \
            --ttl 300

        az network dns record-set a add-record \
            --resource-group ${AZURE_DNS_RESOURCE_GROUP} \
            --zone-name ${AZURE_DNS_ZONE_NAME} \
            --record-set-name $1 \
            --ipv4-address $lb_ip
    fi
}

azure_set_record_sets_for_namespace() {
    local namespace=$1
    local lb_info lb_ip
    lb_info=$(lbs_info)
    for lb_svc_obj in $(echo "${lb_info}" | jq -c '.[]'); do
        lb_svc=$(jq -r .svc <<< "${lb_svc_obj}")
        if [[ ${lb_svc} == "uaa-uaa-public" ]]; then
            if [[ "${EMBEDDED_UAA:-false}" != "true" ]]; then
                azure_set_record uaa.$AZURE_AKS_RESOURCE_GROUP "${lb_svc_obj}"
                azure_set_record *.uaa.$AZURE_AKS_RESOURCE_GROUP "${lb_svc_obj}"
            fi
        elif [[ ${lb_svc} == diego-ssh-ssh-proxy-public ]]; then
            azure_set_record ssh.$AZURE_AKS_RESOURCE_GROUP "${lb_svc_obj}"
        elif [[ ${lb_svc} == tcp-router-tcp-router-public ]]; then
            azure_set_record tcp.$AZURE_AKS_RESOURCE_GROUP "${lb_svc_obj}"
            azure_set_record *.tcp.$AZURE_AKS_RESOURCE_GROUP "${lb_svc_obj}"
        elif [[ ${lb_svc} == router-gorouter-public ]]; then
            azure_set_record $AZURE_AKS_RESOURCE_GROUP "${lb_svc_obj}"
            azure_set_record *.$AZURE_AKS_RESOURCE_GROUP "${lb_svc_obj}"
        elif [[ ${lb_svc} == autoscaler-api-apiserver-public ]]; then
            echo "Skipping record-set for autoscaler.$AZURE_AKS_RESOURCE_GROUP"
        elif [[ ${lb_svc} == autoscaler-servicebroker-servicebroker-public ]]; then
            echo "Skipping record-set for autoscalerservicebroker.$AZURE_AKS_RESOURCE_GROUP"
        else
            echo "Unrecognized service name $lb_svc"
            return 1
        fi
     done
}

azure_set_record_embedded_uaa() {
    local namespace="scf"
    local lb_info lb_ip
    lb_info=$(uaa_lb_info)
    for lb_svc_obj in $(echo "${lb_info}" | jq -c '.[]'); do
        lb_svc=$(jq -r .svc <<< "${lb_svc_obj}")
        if [[ ${lb_svc} == "uaa-uaa-public" ]]; then
            azure_set_record uaa.$AZURE_AKS_RESOURCE_GROUP "${lb_svc_obj}"
            azure_set_record *.uaa.$AZURE_AKS_RESOURCE_GROUP "${lb_svc_obj}"
        else
            echo "Unrecognized service name $lb_svc"
            return 1
        fi
     done
}
