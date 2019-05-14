#!/bin/bash
set -o errexit -o nounset

if [[ $ENABLE_USB_POST_UPGRADE != true ]]; then
  echo "usb-post-upgrade.sh: Flag not set. Skipping upgrade"
  exit 0
fi

# Set kube config from pool
source "ci/qa-pipelines/tasks/lib/prepare-kubeconfig.sh"

DOMAIN=$(kubectl get pods -o json --namespace scf api-group-0 | jq -r '.spec.containers[0].env[] | select(.name == "DOMAIN").value')
cf api --skip-ssl-validation "https://api.${DOMAIN}"
cf login -u admin -p changeme -o system
cf target -o usb-test-org -s usb-test-space
cd ci/sample-apps/rails-example

# CAP 1.3 Workaround
cf update-service-broker usb broker-admin "$(kubectl get secret secrets-2.14.5-1 --namespace scf -o yaml | grep \\scf-usb-password: | cut -d: -f2 | base64 -id)" https://cf-usb-cf-usb.scf.svc.cluster.local:24054

echo "Verify that app bound to postgres service instance is reachable:"
curl -Ikf https://scf-rails-example-postgres.$DOMAIN
echo "Verify that data created before upgrade can be retrieved:"
curl -kf https://scf-rails-example-postgres.$DOMAIN/todos/1 | jq .
cf stop scf-rails-example-postgres
sleep 15
cf delete -f scf-rails-example-postgres
cf delete-service -f testpostgres

echo "Verify that app bound to mysql service instance is reachable:"
curl -Ikf https://scf-rails-example-mysql.$DOMAIN
echo "Verify that data created before upgrade can be retrieved:"
curl -kf https://scf-rails-example-mysql.$DOMAIN/todos/1 | jq .
cf stop scf-rails-example-mysql
sleep 15
cf delete -f scf-rails-example-mysql
cf delete-service -f testmysql

cf delete-org -f usb-test-org

cf unbind-staging-security-group sidecar-net-workaround
cf unbind-running-security-group sidecar-net-workaround
cf delete-security-group -f sidecar-net-workaround

cf install-plugin -f "https://github.com/SUSE/cf-usb-plugin/releases/download/1.0.0/cf-usb-plugin-1.0.0.0.g47b49cd-linux-amd64"
yes | cf usb-delete-driver-endpoint postgres
yes | cf usb-delete-driver-endpoint mysql

for namespace in mysql-sidecar pg-sidecar postgres mysql; do
    while [[ $(kubectl get statefulsets --output json --namespace "${namespace}" | jq '.items | length == 0') != "true" ]]; do
      kubectl delete statefulsets --all --namespace "${namespace}" ||:
    done
    while [[ $(kubectl get deploy --output json --namespace "${namespace}" | jq '.items | length == 0') != "true" ]]; do
      kubectl delete deploy --all --namespace "${namespace}" ||:
    done
    while kubectl get namespace "${namespace}" 2>/dev/null; do
      kubectl delete namespace "${namespace}" ||:
      sleep 30
    done
    while [[ -n $(helm list --short --all ${namespace}) ]]; do
        helm delete --purge ${namespace} ||:
        sleep 10
    done
done
