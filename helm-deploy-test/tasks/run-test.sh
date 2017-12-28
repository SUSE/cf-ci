#!/bin/bash
set -o errexit -o nounset

# Set kube config from pool
mkdir -p /root/.kube/
cp  pool.kube-hosts/metadata /root/.kube/config

set -o allexport
DOMAIN=$(kubectl get pods -o json --namespace scf api-0 | jq -r '.spec.containers[0].env[] | select(.name == "DOMAIN").value')
CF_NAMESPACE=scf
set +o allexport

unzip s3.scf-config/scf-*.zip -d s3.scf-config/

kube_overrides() {
    ruby <<EOF
        require 'yaml'
        require 'json'
        obj = YAML.load_file('$1')
        obj['spec']['containers'].each do |container|
            container['env'].each do |env|
                env['value'] = '$DOMAIN'     if env['name'] == 'DOMAIN'
                env['value'] = 'tcp.$DOMAIN' if env['name'] == 'TCP_DOMAIN'
            end
        end
        puts obj.to_json
EOF
}

container_status() {
  kubectl get --output=json --namespace=scf pod $1 \
    | jq '.status.containerStatuses[0].state.terminated.exitCode | tonumber' 2>/dev/null
}

image=$(awk '$1 == "image:" { gsub(/"/, "", $2); print $2 }' "s3.scf-config/kube/cf${CAP_CHART}/bosh-task/${TEST_NAME}.yaml")
kubectl run \
    --namespace="${CF_NAMESPACE}" \
    --attach \
    --restart=Never \
    --image="${image}" \
    --overrides="$(kube_overrides "s3.scf-config/kube/cf${CAP_CHART}/bosh-task/${TEST_NAME}.yaml")" \
    "${TEST_NAME}" ||:

while [[ -z $(container_status ${TEST_NAME}) ]]; do
  kubectl attach --namespace=scf ${TEST_NAME} ||:
done

exit $(container_status ${TEST_NAME})
