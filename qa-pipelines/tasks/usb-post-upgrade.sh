#!/bin/bash
set -o errexit -o nounset

DOMAIN=$(kubectl get pods -o json --namespace scf api-0 | jq -r '.spec.containers[0].env[] | select(.name == "DOMAIN").value')
curl https://scf-rails-example.$DOMAIN
cd rails-example
cf target -o usb-test-org -s usb-test-space
cf delete scf-rails-example
cf delete-service testpostgres
cf delete-org usb-test-org

cf unbind-staging-security-group pg-net-workaround
cf unbind-running-security-group pg-net-workaround
cf delete-security-group -f pg-net-workaround