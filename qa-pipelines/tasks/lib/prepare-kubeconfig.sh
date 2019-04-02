#!/bin/bash

# usage: read_yaml_key test.yaml key-name
read_yaml_key() {
    ruby -r yaml -e "puts YAML.load_file('$1')[\"$2\"]"
}

pool_file=pool.kube-hosts/metadata
if [[ $(read_yaml_key ${pool_file} kind) == "Config" ]]; then
    cp ${pool_file} /root/.kube
elif [[ $(read_yaml_key ${pool_file} platform) == "gke" ]]; then
    export CLOUDSDK_PYTHON_SITEPACKAGES=1
    export GKE_CLUSTER_NAME=$(read_yaml_key ${pool_file} cluster-name)
    export GKE_CLUSTER_ZONE=$(read_yaml_key ${pool_file} cluster-zone)
    base64 -d <<< "${GKE_PRIVATE_KEY_BASE64}" > gke-key.json
    export GKE_SERVICE_ACCOUNT_EMAIL=$(jq -r .client_email gke-key.json)
    export GKE_PROJECT_ID=$(jq -r .project_id gke-key.json)
    gcloud auth activate-service-account ${GKE_SERVICE_ACCOUNT_EMAIL} --project=${GKE_PROJECT_ID} --key-file gke-key.json
    gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --zone ${GKE_CLUSTER_ZONE}
fi
