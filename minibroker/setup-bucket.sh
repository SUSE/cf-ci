#!/usr/bin/env sh

set -e
set -x

s3cmd mb s3://minibroker-helm-charts

aws s3api put-bucket-versioning --bucket minibroker-helm-charts --versioning-configuration Status=Enabled

cat <<EOF > index.yaml
apiVersion: v1
entries: ~
generated: 1970-01-01T00:00:00.000000000Z
EOF

s3cmd put --acl-public index.yaml s3://minibroker-helm-charts/kubernetes-charts/index.yaml
