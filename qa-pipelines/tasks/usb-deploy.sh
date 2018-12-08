#!/bin/bash
set -o errexit -o nounset

if [[ $ENABLE_USB_DEPLOY != true ]]; then
  echo "usb-deploy.sh: Flag not set. Skipping USB deploy"
  exit 0
fi

# Set kube config from pool
mkdir -p /root/.kube/
cp  pool.kube-hosts/metadata /root/.kube/config

if kubectl get pod --namespace scf api-0 2>/dev/null; then
    api_pod_name=api-0
else
    api_pod_name=api-group-0
fi
DOMAIN=$(kubectl get pods -o json --namespace scf ${api_pod_name} | jq -r '.spec.containers[0].env[] | select(.name == "DOMAIN").value')
PROVISIONER=$(kubectl get storageclasses persistent -o "jsonpath={.provisioner}")

nfs_regex='\bnfs'
if ! [[ ${PROVISIONER} =~ $nfs_regex ]]; then
  echo "postgres and mysql charts can only be deployed with NFS storageclass"
  exit 1
fi

# Ensure persistent is the only default storageclass
for sc in $(kubectl get storageclass | tail -n+2 | cut -f1 -d ' '); do
  sc_desired_default_status=$([[ $sc == "persistent" ]] && echo true || echo false )
  sc_current_default_status=$(kubectl get -o json storageclass persistent | jq -r '.metadata.annotations["storageclass.kubernetes.io/is-default-class"]')
  if [[ ${sc_current_default_status} != ${sc_desired_default_status} ]]; then
    kubectl patch storageclass ${sc} -p '
      {
        "metadata": {
          "annotations": {
            "storageclass.kubernetes.io/is-default-class":
              "'${sc_desired_default_status}'"
          }
        }
      }
    '
  fi
done


get_internal_ca_cert() {
  local generated_secrets_secret=$(kubectl get --namespace ${1} statefulset,deploy -o json | jq -r '[.items[].spec.template.spec.containers[].env[] | select(.name == "INTERNAL_CA_CERT").valueFrom.secretKeyRef.name] | unique[]')
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

is_namespace_ready() {
  # Check that the setup pod is Completed. Return with a failure status if not
  if [[ Completed != $(kubectl get pods -a --namespace=pg-sidecar 2>/dev/null \
        | grep setup \
        | awk '{print $3}') ]]; then
    return 1
  fi
  # Return successfully if all non-setup pods are ready
  [[ true == $(2>/dev/null kubectl get pods --namespace=${namespace} --output=custom-columns=':.status.containerStatuses[].name,:.status.containerStatuses[].ready' \
    | grep -v 'setup' \
    | awk '{ print $2 }' \
    | sed '/^ *$/d' \
    | sort \
    | uniq) ]]
}

wait_for_namespace() {
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


# Unzip sidecar tars
tar xf s3.pg-sidecar/*.tgz -C s3.pg-sidecar/
tar xf s3.mysql-sidecar/*.tgz -C s3.mysql-sidecar/

COMMON_SIDECAR_PARAMS=(
  --set "env.CF_ADMIN_USER=admin"
  --set "env.CF_ADMIN_PASSWORD=changeme"
  --set "env.CF_DOMAIN=${DOMAIN}"
  --set "env.CF_CA_CERT=${CF_CERT}"
  --set "env.UAA_CA_CERT=${UAA_CERT}"
  --set "kube.registry.hostname=registry.suse.com"
  --set "kube.organization=cap"
)

cf api --skip-ssl-validation "https://api.${DOMAIN}"
cf login -u admin -p changeme
cf create-org usb-test-org
cf create-space -o usb-test-org usb-test-space
cf target -o usb-test-org -s usb-test-space

echo > "sidecar-net-workaround.json" "[{ \"destination\": \"${DB_EXTERNAL_IP}/32\", \"protocol\": \"tcp\", \"ports\": \"5432,30306\" }]"
cf create-security-group sidecar-net-workaround sidecar-net-workaround.json
cf bind-running-security-group sidecar-net-workaround
cf bind-staging-security-group sidecar-net-workaround

# Test POSTGRES
helm install stable/postgresql \
  --version 0.18.1             \
  --namespace postgres         \
  --name postgres              \
  --set "service.externalIPs={${DB_EXTERNAL_IP}}"

PG_PASS=$(kubectl get secret --namespace postgres postgres-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode)

PG_SIDECAR_PARAMS=(
  --set "env.SERVICE_TYPE=postgres"
  --set "env.SERVICE_LOCATION=http://cf-usb-sidecar-postgres.pg-sidecar:8081"
  --set "env.SERVICE_POSTGRESQL_HOST=${DB_EXTERNAL_IP}"
  --set "env.SERVICE_POSTGRESQL_PORT=5432"
  --set "env.SERVICE_POSTGRESQL_USER=postgres"
  --set "env.SERVICE_POSTGRESQL_PASS=${PG_PASS}"
  --set "env.SERVICE_POSTGRESQL_SSLMODE=disable"
)

helm install s3.pg-sidecar  \
  --name pg-sidecar         \
  --namespace pg-sidecar    \
  "${PG_SIDECAR_PARAMS[@]}" \
  "${COMMON_SIDECAR_PARAMS[@]}"


wait_for_namespace pg-sidecar
cf api --skip-ssl-validation "https://api.${DOMAIN}"
cf login -u admin -p changeme -o usb-test-org -s usb-test-space
cf create-service postgres default testpostgres

# push app in subshell to avoid changing directory
(
  cd ci/sample-apps/rails-example
  sed -i 's/scf-rails-example-db/testpostgres/g' manifest.yml
  cf push scf-rails-example-postgres -s cflinuxfs2
)
cf ssh scf-rails-example-postgres -c "export PATH=/home/vcap/deps/0/bin:/usr/local/bin:/usr/bin:/bin && export BUNDLE_PATH=/home/vcap/deps/0/vendor_bundle/ruby/2.5.0 && export BUNDLE_GEMFILE=/home/vcap/app/Gemfile && cd app && bundle exec rake db:seed"


# Test MYSQL
helm install stable/mysql                   \
  --name mysql                              \
  --namespace mysql                         \
  --set imageTag=5.7.22                     \
  --set mysqlRootPassword=password          \
  --set persistence.storageClass=persistent \
  --set persistence.size=4Gi                \
  --set service.type=NodePort               \
  --set service.nodePort=30306              \
  --set service.port=3306

MYSQL_SIDECAR_PARAMS=(
  --set "env.SERVICE_TYPE=mysql"
  --set "env.SERVICE_LOCATION=http://cf-usb-sidecar-mysql.mysql-sidecar:8081"
  --set "env.SERVICE_MYSQL_HOST=${DB_EXTERNAL_IP}"
  --set "env.SERVICE_MYSQL_PORT=30306"
  --set "env.SERVICE_MYSQL_USER=root"
  --set "env.SERVICE_MYSQL_PASS=password"
)

helm install s3.mysql-sidecar  \
  --name mysql-sidecar         \
  --namespace mysql-sidecar    \
  "${MYSQL_SIDECAR_PARAMS[@]}" \
  "${COMMON_SIDECAR_PARAMS[@]}"

wait_for_namespace mysql-sidecar
cf api --skip-ssl-validation "https://api.${DOMAIN}"
cf login -u admin -p changeme -o usb-test-org -s usb-test-space
cf create-service mysql default testmysql

# push app in subshell to avoid changing directory
(
  cd ci/sample-apps/rails-example
  git checkout manifest.yml
  sed -i 's/scf-rails-example-db/testmysql/g' manifest.yml
  cf push scf-rails-example-mysql -s cflinuxfs2
)
cf ssh scf-rails-example-mysql -c "export PATH=/home/vcap/deps/0/bin:/usr/local/bin:/usr/bin:/bin && export BUNDLE_PATH=/home/vcap/deps/0/vendor_bundle/ruby/2.5.0 && export BUNDLE_GEMFILE=/home/vcap/app/Gemfile && cd app && bundle exec rake db:seed"
