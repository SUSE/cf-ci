#!/bin/bash
#
# This script captures usage metrics from Prometheus and calculates their mean.
# Prometheus queries are based on Kubernetes/Nodes and Kubernetes/Pods Grafana dashboards
# It assumes you have a prometheus operator running in your Kube Cluster,
# Instructions for installing Prometheus: https://github.com/SUSE/cloudfoundry/wiki/Resource-metrics-collection
#
# NOTE:
#   Wait for atleast 10 mins after installing prometheus operator for metrics data to be collected 
#   Make sure port 9100 is whitelisted in your Kube deployment for master and worker nodes
#

#set -x

# Port to forward Prometheus
PORT="8080"

# Prometheus local port forwarding.
kubectl port-forward prometheus-prometheus-operator-prometheus-0 ${PORT}:9090 -n monitoring >/dev/null &

# Wait for port fowarding.
sleep 5
PID=$(echo $!)

# ---For monitoring node level resource usage---

# Get Internal IPs of nodes.
NODES=($(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'))

if [[ -z "$NODES" ]]; then
    echo "No nodes found"
    exit
fi

PROMETHEUS_BASE_URL="http://localhost:${PORT}/api/v1/query_range"

# Setting time period for past 10 mins.
END=$(date +%s)
START=$((END - 600))

make_request() {
    curl -s \
        --data-urlencode "query=$1" \
        --data "start=${START}" \
        --data "end=${END}" \
        --data "step=60" \
        ${PROMETHEUS_BASE_URL} |
        python -c 'import json,sys;obj=json.load(sys.stdin);l = [float(item) for sublist in obj["data"]["result"][0]["values"] for item in [sublist[1]]]; print "{0:0.3f}".format(sum(l)/float(len(l)))'
}

NC='\033[0m' # No Color
GREEN='\033[0;32m'
CYAN='\033[0;36m'
printf "${GREEN}Retrieving node level metrics...${NC}\n"

for NODE in "${NODES[@]}"; do
    printf "\n${CYAN}NODE:${NC} ${NODE} \n "

    QUERY="avg(sum by (cpu) (irate(node_cpu_seconds_total{job=\"node-exporter\", mode!=\"idle\", 
            instance=\"${NODE}:9100\"}[2m]))) * 100"

    printf " ${CYAN}CPU(%%):${NC} $(make_request "${QUERY}")"

    QUERY="max(((node_memory_MemTotal_bytes{job=\"node-exporter\", instance=\"${NODE}:9100\"}
           - node_memory_MemFree_bytes{job=\"node-exporter\", instance=\"${NODE}:9100\"}
           - node_memory_Buffers_bytes{job=\"node-exporter\", instance=\"${NODE}:9100\"}
           - node_memory_Cached_bytes{job=\"node-exporter\", instance=\"${NODE}:9100\"}
           ) / node_memory_MemTotal_bytes{job=\"node-exporter\", instance=\"${NODE}:9100\"}
           ) * 100)"

    printf " ${CYAN}MEM(%%):${NC} $(make_request "${QUERY}")"

    QUERY="max(node_memory_MemTotal_bytes{job=\"node-exporter\", instance=\"${NODE}:9100\"} 
            - node_memory_MemFree_bytes{job=\"node-exporter\", instance=\"${NODE}:9100\"} 
            - node_memory_Buffers_bytes{job=\"node-exporter\", instance=\"${NODE}:9100\"} 
            - node_memory_Cached_bytes{job=\"node-exporter\", instance=\"${NODE}:9100\"})"

    printf " ${CYAN}MEM(MiB):${NC} $(make_request "${QUERY}"/1000000)"

    QUERY="node:node_filesystem_usage:"

    printf " ${CYAN}DISK SPACE USAGE(%%):${NC} $(make_request "${QUERY}"*100)\n"

done

# ---For monitoring pod-level resource usage---

printf "\n${GREEN}Retrieving pod level metrics...${NC}\n"

# Uncomment to run for all namespaces.
#NAMESPACES=($(kubectl get namespace -o jsonpath='{.items[*].metadata.name}'))
NAMESPACES=(uaa scf)

for NS in "${NAMESPACES[@]}"; do
    printf "\n${CYAN}NAMESPACE:${NC}${NS}\n"
    
    PODS=($(kubectl get pods --namespace ${NS} --field-selector=status.phase=Running -o jsonpath='{.items[*].metadata.name}'))

    for PO in "${PODS[@]}"; do

        printf " ${CYAN}POD:${NC} ${PO} \n "

        QUERY="sum by (container_name) (rate(container_cpu_usage_seconds_total{job=\"kubelet\", 
               namespace=\"${NS}\", image!=\"\", container_name!=\"POD\", pod_name=\"${PO}\"}[1m]))"

        printf "  ${CYAN}CPU(%%):${NC} $(make_request "${QUERY}")"

        QUERY="sum by(container_name) (container_memory_usage_bytes{job=\"kubelet\", 
               namespace=\"${NS}\", pod_name=\"${PO}\", container_name!=\"POD\"})"

        printf " ${CYAN}MEMORY(MiB):${NC} $(make_request "${QUERY}"/1000000)"

        QUERY="sort_desc(sum by (pod_name) (rate(container_network_receive_bytes_total{job=\"kubelet\", 
               namespace=\"${NS}\", pod_name=\"${PO}\"}[1m])))"

        printf " ${CYAN}NETWORK IO(KiB):${NC} $(make_request "${QUERY}"/1000)\n"
    done
done

kill -9 ${PID}