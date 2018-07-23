#!/usr/bin/env sh

# Usage:
# setup-bucket.sh <bucket name> <dir name>
#
# Stores the index.yaml file in s3://<bucket name>/<dir name>/index.yaml
# and configures versioning for it.
#
# If the bucket name and dir name aren't specified, the defaults will be taken
# from the pipeline's config-production.yaml file.

set -e

HELM_CHARTS_BUCKET=${1:-$(awk '/^s3-bucket/ {print $2}' < config-production.yaml)}
HELM_CHARTS_DIR=${2:-$(awk '/^helm-charts-s3-prefix/ {print $2}' < config-production.yaml)}

aws s3api create-bucket --bucket "${HELM_CHARTS_BUCKET}"

aws s3api put-bucket-versioning --bucket "${HELM_CHARTS_BUCKET}" --versioning-configuration Status=Enabled

INDEX_YAML=$(mktemp)

cat <<EOF > "${INDEX_YAML}"
apiVersion: v1
entries: ~
generated: 1970-01-01T00:00:00.000000000Z
EOF

aws s3api put-object --acl public-read --bucket "${HELM_CHARTS_BUCKET}" --body "${INDEX_YAML}" --key "${HELM_CHARTS_DIR}/index.yaml"

rm "${INDEX_YAML}"
