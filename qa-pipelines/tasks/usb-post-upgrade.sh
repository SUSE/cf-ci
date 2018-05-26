#!/bin/bash
set -o errexit -o nounset

# Set kube config from pool
mkdir -p /root/.kube/
cp  pool.kube-hosts/metadata /root/.kube/config

DOMAIN=$(kubectl get pods -o json --namespace scf api-0 | jq -r '.spec.containers[0].env[] | select(.name == "DOMAIN").value')
cf api --skip-ssl-validation "https://api.${DOMAIN}"
cf login -u admin -p changeme -o system

# Temporary workaround for usb breakage after secret rotation
echo "Update broker password after rotation:"
CF_NAMESPACE=scf
SECRET=$(kubectl get --namespace $CF_NAMESPACE deploy -o json | jq -r '[.items[].spec.template.spec.containers[].env[] | select(.name == "INTERNAL_CA_CERT").valueFrom.secretKeyRef.name] | unique[]')
USB_PASSWORD=$(kubectl get -n scf secret $SECRET -o jsonpath='{@.data.cf-usb-password}' | base64 -d)
USB_ENDPOINT=$(cf curl /v2/service_brokers | jq -r '.resources[] | select(.entity.name=="usb").entity.broker_url')
cf update-service-broker usb broker-admin "$USB_PASSWORD" "$USB_ENDPOINT"

echo "Verify that app bound to postgres service instance is reachable:"
curl -Ikf https://scf-rails-example.$DOMAIN
echo "Verify that data created before upgrade can be retrieved:"
curl -kf https://scf-rails-example.$DOMAIN/todos/1 | jq .

cd rails-example
cf target -o usb-test-org -s usb-test-space
cf stop scf-rails-example
sleep 15
cf delete -f scf-rails-example
cf delete-service -f testpostgres
cf delete-org -f usb-test-org

cf unbind-staging-security-group pg-net-workaround
cf unbind-running-security-group pg-net-workaround
cf delete-security-group -f pg-net-workaround
