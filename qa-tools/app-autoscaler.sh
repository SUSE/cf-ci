#!/bin/bash

set -o errexit -o nounset -o xtrace
shopt -s nullglob

public_ip=$(kubectl get configmap -n kube-system cap-values -o json | jq -r '.data["public-ip"]')
MAGIC_DNS_SERVICE=omg.howdoi.website
DOMAIN=${public_ip}.${MAGIC_DNS_SERVICE}
autoscaler_service_broker_password=$(kubectl get secrets --namespace scf secrets-2.13.3-1 -o jsonpath="{.data['autoscaler-service-broker-password']}"|base64 -d)
echo ${autoscaler_service_broker_password}

username=admin
password=changeme
APP="dora-autoscaler"
ORG="ORG-autoscaler"
SPACE="SPACE-autocaler"
BROKER="SCALER-autoscaler"
SERVICE="SERVICE-autoscaler"
URL="http://${APP}.${DOMAIN}"
autoscaler_service_broker_endpoint=https://autoscalerservicebroker.${DOMAIN}
autoscaler_smoke_service_plan=autoscaler-free-plan
autoscaler_smoke_service_name=autoscaler

cleanup() {
    set +o errexit
    cf unbind-service "${APP}" "${SERVICE}"
    cf delete-org -f "${ORG}"
    cf delete-service-broker "${BROKER}" -f
}

trap cleanup EXIT

cf api --skip-ssl-validation "https://api.${DOMAIN}"
cf login -u ${username} -p ${password} -o system
cf create-org "${ORG}"
cf create-space "${SPACE}" -o "${ORG}"
cf target -o "${ORG}" -s "${SPACE}"
#git clone https://github.com/prabalsharma/cf-acceptance-tests.git
cf push "${APP}" --no-start \
    -p cf-acceptance-tests/assets/dora


cf create-service-broker "${BROKER}" username ${autoscaler_service_broker_password} ${autoscaler_service_broker_endpoint}

cf service-access
cf enable-service-access ${autoscaler_smoke_service_name} -p ${autoscaler_smoke_service_plan}
cf create-service ${autoscaler_smoke_service_name} ${autoscaler_smoke_service_plan} ${SERVICE}
cf bind-service "${APP}" "${SERVICE}" -c ' {
    "instance_min_count": 1,
    "instance_max_count": 4,
    "scaling_rules": [{
        "metric_type": "memoryused",
        "stat_window_secs": 60,
        "breach_duration_secs": 60,
        "threshold": 10,
        "operator": ">=",
        "cool_down_secs": 300,
        "adjustment": "+1"
    }]
} '
cf start "${APP}"

# We don't need xtrace while waiting for things
set +o xtrace
echo

printf "Waiting for the app to start..."
while ! curl --silent "${URL}/" | grep Dora ; do
    printf "."
    sleep 1
done
printf "\nApp started.\n"

get_count() {
    cf curl /v2/apps/$(cf app --guid "${APP}") | jq .entity.instances
}

printf "Checking that we initially have one instance...\n"
count="$(get_count)"
if ! test "${count}" -eq 1 ; then
    printf "App has %d instances!\n" "${count}"
    cf app "${APP}"
    exit 1
fi

cf app "${APP}"
printf "Causing memory stress...\n"
curl -X POST "${URL}/stress_testers?vm=10"
printf "Waiting for new instances to start..."
for (( i = 0 ; i < $(( 60 * 2 / 5)) ; i ++ )) ; do
    if test "$(get_count)" -gt 1 ; then
        break
    fi
    printf "."
    sleep 5
done
printf "\nInstances increased.\n"
cf app "${APP}"
