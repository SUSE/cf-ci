#!/bin/bash
set -o errexit -o nounset

# Set kube config from pool
mkdir -p /root/.kube/
cp  pool.kube-hosts/metadata /root/.kube/config

DOMAIN=$(kubectl get pods -o json --namespace scf api-0 | jq -r '.spec.containers[0].env[] | select(.name == "DOMAIN").value')
PROVISIONER=$(kubectl get storageclasses persistent -o "jsonpath={.provisioner}")

if [[ ${PROVISIONER} != "nfs" ]]; then
  echo "postgres and mysql charts can only be deployed with NFS storageclass"
  exit 1
fi

# Ensure persistent is the only default storageclass
for sc in $(kubectl get storageclass | tail -n+2 | cut -f1 -d ' '); do
  kubectl patch storageclass ${sc} -p '
    {
      "metadata": {
        "annotations": {
          "storageclass.kubernetes.io/is-default-class":
            "'$([[ $sc == "persistent" ]] && echo true || echo false)'"
        }
      }
    }
  '
done


get_internal_ca_cert() {
  local generated_secrets_secret=$(kubectl get --namespace ${1} deploy -o json | jq -r '[.items[].spec.template.spec.containers[].env[] | select(.name == "INTERNAL_CA_CERT").valueFrom.secretKeyRef.name] | unique[]')
  if [[ $(echo $generated_secrets_secret | wc -w) -ne 1 ]]; then
    echo "Internal cert or secret problem in ${1} namespace"
    return 1
  fi
  kubectl get secret ${generated_secrets_secret} \
    --namespace "${1}" \
    -o jsonpath="{.data['internal-ca-cert']}" \
    | base64 -d
}

UAA_CERT=$(get_internal_ca_cert uaa)
CF_CERT=$(get_internal_ca_cert scf)

# Get external IP from first node of sorted list
DB_EXTERNAL_IP=$(kubectl get nodes -o json | jq -r '[.items[] | .status.addresses[] | select(.type=="InternalIP").address] | sort | first')

helm init --client-only
helm install stable/postgresql --namespace postgres --name postgres --set "service.externalIPs={${DB_EXTERNAL_IP}}"
DB_USER=postgres
DB_PASS=$(kubectl get secret --namespace postgres postgres-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode)
HELM_PARAMS=(
  --set "env.SERVICE_TYPE=postgres"
  --set "env.SERVICE_LOCATION=http://cf-usb-sidecar-postgres.pg-sidecar:8081"
  --set "env.SERVICE_POSTGRESQL_HOST=${DB_EXTERNAL_IP}"
  --set "env.SERVICE_POSTGRESQL_PORT=5432"
  --set "env.SERVICE_POSTGRESQL_USER=${DB_USER}"
  --set "env.SERVICE_POSTGRESQL_PASS=${DB_PASS}"
  --set "env.SERVICE_POSTGRESQL_SSLMODE=disable"
  --set "env.CF_ADMIN_USER=admin"
  --set "env.CF_ADMIN_PASSWORD=changeme"
  --set "env.CF_DOMAIN=${DOMAIN}"
  --set "env.CF_CA_CERT=${CF_CERT}"
  --set "env.UAA_CA_CERT=${UAA_CERT}"
  --set "kube.registry.hostname=registry.suse.com"
  --set "kube.organization=cap"
)
# Maybe set credentials for docker registry?

tar xf s3.pg-sidecar/*.tgz -C s3.pg-sidecar/

helm install s3.pg-sidecar \
  --name pg-sidecar        \
  --namespace pg-sidecar   \
  "${HELM_PARAMS[@]}"


is_namespace_ready() {
  # This is simpler than is_namespace_ready in cf_deploy, because there's no HA
  [[ true == $(2>/dev/null kubectl get pods --namespace=${namespace} --output=custom-columns=':.status.containerStatuses[].ready' \
    | sed '/^ *$/d' \
    | sort \
    | uniq) ]]
}

wait_for_namespace() {
  # This should be the same as wait_for_namespace in cf_deploy, other than a shorter timeout
  local namespace="$1"
  start=$(date +%s)
  for (( i = 0  ; i < 120 ; i ++ )) ; do
    if is_namespace_ready "${namespace}" ; then
      break
    fi
    now=$(date +%s)
    printf "\rWaiting for %s at %s (%ss)..." "${namespace}" "$(date --rfc-2822)" $((${now} - ${start}))
    sleep 10
  done
  now=$(date +%s)
  printf "\rDone waiting for %s at %s (%ss)\n" "${namespace}" "$(date --rfc-2822)" $((${now} - ${start}))
  kubectl get pods --namespace="${namespace}"
  if ! is_namespace_ready "${namespace}" ; then
    printf "Namespace %s is still pending\n" "${namespace}"
    exit 1
  fi
}

wait_for_namespace pg-sidecar

cf api --skip-ssl-validation "https://api.${DOMAIN}"
cf login -u admin -p changeme
cf create-org usb-test-org
cf create-space -o usb-test-org usb-test-space
cf target -o usb-test-org -s usb-test-space
cf create-service postgres default testpostgres

echo > "pg-net-workaround.json" "[{ \"destination\": \"${DB_EXTERNAL_IP}/32\", \"protocol\": \"tcp\", \"ports\": \"5432\" }]"
cf create-security-group       pg-net-workaround pg-net-workaround.json
cf bind-running-security-group pg-net-workaround
cf bind-staging-security-group pg-net-workaround

cd rails-example
sed -i 's/scf-rails-example-db/testpostgres/g' manifest.yml

cf push scf-rails-example
cf ssh scf-rails-example -c "export PATH=/home/vcap/deps/0/bin:/usr/local/bin:/usr/bin:/bin && export BUNDLE_PATH=/home/vcap/deps/0/vendor_bundle/ruby/2.5.0 && export BUNDLE_GEMFILE=/home/vcap/app/Gemfile && cd app && bundle exec rake db:seed"
