#!/bin/bash

set -eu # errexit, nounset

set -x # trace for wip, remove before merging

az_login_error_msg() {
    cat << 'EOF' >& 2
    kubectl create secret generic -n kube-system aks-dns-sp \
        --from-literal appId=${AZ_SP_APPID} \
        --from-literal tenant=${AZ_SP_TENANT} \
        --from-literal password=${AZ_SP_PASSWORD}
EOF
}

az_login() {
    local sp_app_id sp_password sp_tenant
    sp_app_id=$(kubectl get secret -n kube-system -o json aks-dns-sp | jq -r .data.appId | base64 -d)
    sp_password=$(kubectl get secret -n kube-system -o json aks-dns-sp | jq -r .data.password | base64 -d)
    sp_tenant=$(kubectl get secret -n kube-system -o json aks-dns-sp | jq -r .data.tenant | base64 -d)
    if ! az login --service-principal -u ${sp_app_id} --password ${sp_password} --tenant ${sp_tenant}; then
        az_login_error_msg
        exit 1
    fi
}

AZURE_DNS_ZONE_NAME=susecap.net
AZURE_DNS_RESOURCE_GROUP=susecap-domain
AZURE_AKS_RESOURCE_GROUP=$(kubectl get configmap -n kube-system -o json cap-values | jq -r '.data["resource-group"]')

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

azure_check_lbs_ready_in_namespace() {
    # checks that all LoadBalancer type services in namespace have an ingress IP
    local namespace=$1
    local lb_info lb_count lb_ready_count
    lb_info=$(kubectl get svc -n $namespace -o json | jq -c '[.items[] | select(.spec.type == "LoadBalancer") | {"svc": .metadata.name, "ip": .status.loadBalancer.ingress[0].ip}]')
    lb_count=$(echo "${lb_info}" | jq length)
    lb_ready_count=$(echo "${lb_info}" | jq -r '[.[] | select(.ip)] | length')
    [[ ${lb_count} -eq ${lb_ready_count} ]]
}

azure_wait_for_lbs_in_namespace() {
    local namespace=$1
    local count=0
    while ! azure_check_lbs_ready_in_namespace $namespace; do
        sleep 30
        ((count++))
        if [[ $count -eq 10 ]]; then
            echo "Load balancers for $namespace not ready" >&2
            return 1
        fi
    done
}

azure_set_a_record() {
    az network dns record-set a create \
        --resource-group ${AZURE_DNS_RESOURCE_GROUP} \
        --zone-name ${AZURE_DNS_ZONE_NAME} \
        --name $1 \
        --ttl 300
    az network dns record-set a add-record \
        --resource-group ${AZURE_DNS_RESOURCE_GROUP} \
        --zone-name ${AZURE_DNS_ZONE_NAME} \
        --record-set-name $1 \
        --ipv4-address $2
}

azure_set_record_sets_for_namespace() {
    local namespace=$1
    local lb_info lb_ip
    lb_info=$(kubectl get svc -n $namespace -o json | jq -c '[.items[] | select(.spec.type == "LoadBalancer") | {"svc": .metadata.name, "ip": .status.loadBalancer.ingress[0].ip}]')
    for lb_svc in $(echo "${lb_info}" | jq -r '.[] | .svc'); do
        lb_ip=$(echo "${lb_info}" | jq -r '.[] | select(.svc == "'${lb_svc}'").ip')
        if [[ ${lb_svc} == "uaa-uaa-public" ]]; then
            azure_set_a_record uaa.$AZURE_AKS_RESOURCE_GROUP $lb_ip
            azure_set_a_record *.uaa.$AZURE_AKS_RESOURCE_GROUP $lb_ip
        elif [[ ${lb_svc} == diego-ssh-ssh-proxy-public ]]; then
            azure_set_a_record ssh.$AZURE_AKS_RESOURCE_GROUP $lb_ip
        elif [[ ${lb_svc} == tcp-router-tcp-router-public ]]; then
            azure_set_a_record tcp.$AZURE_AKS_RESOURCE_GROUP $lb_ip
        elif [[ ${lb_svc} == router-gorouter-public ]]; then
            azure_set_a_record $AZURE_AKS_RESOURCE_GROUP $lb_ip
            azure_set_a_record *.$AZURE_AKS_RESOURCE_GROUP $lb_ip
        elif [[ ${lb_svc} == autoscaler-api-apiserver-public ]]; then
            echo "Skipping record-set for autoscaler.$AZURE_AKS_RESOURCE_GROUP $lb_ip"
        elif [[ ${lb_svc} == autoscaler-servicebroker-servicebroker-public ]]; then
            echo "Skipping record-set for autoscalerservicebroker.$AZURE_AKS_RESOURCE_GROUP $lb_ip"
        else
            echo "Unrecognized service name $lb_svc"
            return 1
        fi
     done
}


