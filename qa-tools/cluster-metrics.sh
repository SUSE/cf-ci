#!/bin/bash
#
# This script captures CPU, Memory and INode usage metrics from Prometheus and calculates their mean.
# Prometheus queries are based on Kubernetes/Nodes and Kubernetes/Pods Grafana dashboards
# It assumes you have a prometheus operator running in your Kube Cluster,
# Instructions: https://github.com/SUSE/cloudfoundry/wiki/Resource-metrics-collection
#

#set -x

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
    printf "${CYAN}NODE:${NC} ${NODE} --> "

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

    QUERY="max(((node_filesystem_files{job=\"node-exporter\", 
            instance=\"${NODE}:9100\"} - node_filesystem_files_free{job=\"node-exporter\", 
            instance=\"${NODE}:9100\"}) / node_filesystem_files{job=\"node-exporter\", 
            instance=\"${NODE}:9100\"}) * 100)"

    printf " ${CYAN}INODE(%%):${NC} $(make_request "${QUERY}")\n"

done

# ---For monitoring pod-level resource usage---

printf "\n${GREEN}Retrieving pod level metrics...${NC}\n"

NAMESPACES=($(kubectl get namespace -o jsonpath='{.items[*].metadata.name}'))

for NS in "${NAMESPACES[@]}"; do
    PODS=($(kubectl get pods --namespace ${NS} -o jsonpath='{.items[*].metadata.name}'))
    for PO in "${PODS[@]}"; do

        printf "${CYAN}NAMESPACE:${NC} ${NS}, ${CYAN}POD:${NC} ${PO} ---> "

        QUERY="sum by (container_name) (rate(container_cpu_usage_seconds_total{job=\"kubelet\", 
               namespace=\"${NS}\", image!=\"\", container_name!=\"POD\", pod_name=\"${PO}\"}[1m]))"

        printf " ${CYAN}CPU(%%):${NC} $(make_request "${QUERY}")"

        QUERY="sum by(container_name) (container_memory_usage_bytes{job=\"kubelet\", 
               namespace=\"${NS}\", pod_name=\"${PO}\", container_name!=\"POD\"})"

        printf " ${CYAN}MEMORY(MiB):${NC} $(make_request "${QUERY}"/1000000)"

        QUERY="sort_desc(sum by (pod_name) (rate(container_network_receive_bytes_total{job=\"kubelet\", 
               namespace=\"${NS}\", pod_name=\"${PO}\"}[1m])))"

        printf " ${CYAN}NETWORK IO(KiB):${NC} $(make_request "${QUERY}"/1000)\n"
    done
done

kill -9 ${PID}
