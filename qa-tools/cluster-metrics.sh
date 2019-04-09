#!/bin/bash

#set -x

PORT="8080"

# Prometheus local port forwarding
#kubectl port-forward prometheus-prometheus-operator-prometheus-0 8080:9090 -n monitoring

#Get Internal IPs of nodes
NODES=($(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'))

PROMETHEUS_BASE_URL="http://localhost:${PORT}/api/v1/query_range"

# Setting time period for past 10 mins
END=`date +%s`
START=$((END-600))

make_request () {
    curl -s \
            --data-urlencode "query=$1" \
            --data "start=${START}" \
            --data "end=${END}" \
            --data "step=60" \
            ${PROMETHEUS_BASE_URL} | \
            python -c 'import json,sys;obj=json.load(sys.stdin);l = [float(item) for sublist in obj["data"]["result"][0]["values"] for item in [sublist[1]]]; print "{0:0.3f}".format(sum(l)/float(len(l)))'
}

for NODE in "${NODES[@]}"
do  
    echo ${NODE}
    QUERY="avg(sum by (cpu) (irate(node_cpu_seconds_total{job=\"node-exporter\", mode!=\"idle\", instance=\"${NODE}:9100\"}[2m]))) * 100"
    
    echo "CPU: $(make_request "${QUERY}")"

    QUERY="max(node_filesystem_files_free{job=\"node-exporter\", instance=\"${NODE}:9100\"})"

    echo "MEM: $(make_request "${QUERY}")"

    QUERY="max(((node_filesystem_files{job=\"node-exporter\", instance=\"${NODE}:9100\"} - node_filesystem_files_free{job=\"node-exporter\", instance=\"${NODE}:9100\"}) / node_filesystem_files{job=\"node-exporter\", instance=\"${NODE}:9100\"}) * 100)"

    echo "INODE: $(make_request "${QUERY}")"

done
