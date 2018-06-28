#!/usr/bin/env sh

set -e
set -x

s3cmd mb s3://minibroker-helm-charts

aws s3api put-bucket-versioning --bucket minibroker-helm-charts --versioning-configuration Status=Enabled

cat <<EOF > index.yaml
apiVersion: v1
entries: ~
generated: 2018-06-28T21:56:27.538677094Z
EOF

s3cmd put --acl-public index.yaml s3://minibroker-helm-charts/kubernetes-charts/index.yaml
