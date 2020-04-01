#!/usr/bin/env bash

set -o errexit -o nounset

# Updates default stemcell os and version in values.yaml
# releases:
#   # The defaults for all releases, where we do not otherwise override them.
#   defaults:
#     url: docker.io/cfcontainerization
#     stemcell:
#       os: <stemcell-os>
#       version: <stemcell-version>

function update_stemcell_version() {

KUBECF_VALUES=$1
FISSILE_VERSION=$2
STEMCELL_VERSION=$3

PYTHON_CODE=$(cat <<EOF 
#!/usr/bin/python3

import ruamel.yaml

# Adds ~ to the null values to preserve existing structure of values.yaml.
def represent_none(self, data):
    return self.represent_scalar(u'tag:yaml.org,2002:null', u'~')

yaml = ruamel.yaml.YAML()
yaml.preserve_quotes = True
yaml.representer.add_representer(type(None), represent_none)

# Extract stemcell os and version values from input resources.
new_stemcell_os, new_stemcell_version = "${STEMCELL_VERSION}".split("-")
fissile_version = "${FISSILE_VERSION}".split("-")[1].replace(".linux", "").replace("+", "_")
new_stemcell_version = new_stemcell_version+"-"+fissile_version

with open("${KUBECF_VALUES}") as fp:
    values = yaml.load(fp)

values['releases']['defaults']['stemcell']['os'] = new_stemcell_os
values['releases']['defaults']['stemcell']['version'] = new_stemcell_version

with open("${KUBECF_VALUES}", 'w') as f:
    yaml.dump(values, f)

EOF
)

python3 -c "${PYTHON_CODE}"
}

if [ -z "$GITHUB_TOKEN"  ]; then
  echo "GITHUB_TOKEN environment variable not set"
  exit 1
fi

# Setup git
mkdir -p ~/.ssh
echo "github.com ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==" >> ~/.ssh/known_hosts
echo -e ${GITHUB_PRIVATE_KEY} | sed -E 's/(-+(BEGIN|END) OPENSSH PRIVATE KEY-+) *| +/\1\n/g' > ~/.ssh/id_ecdsa
chmod 0600 ~/.ssh/id_ecdsa

git config --global user.email "$GIT_MAIL"
git config --global user.name "$GIT_USER"

stemcell_version="$(cat s3.stemcell-version/"${STEMCELL_VERSIONED_FILE##*/}")"
fissile_version="$(ls s3.fissile-linux | grep fissile)"

# Update release in kubecf repo
cp -r kubecf/. updated-kubecf/
cd updated-kubecf

git pull
export GIT_BRANCH_NAME="bump_stemcell-`date +%Y%m%d%H%M%S`"
git checkout -b "${GIT_BRANCH_NAME}"

update_stemcell_version "${KUBECF_VALUES}" "${fissile_version}" "${stemcell_version}"

COMMIT_TITLE="Bump stemcell version to ${stemcell_version}"
git commit "${KUBECF_VALUES}" -m "${COMMIT_TITLE}"

# Open a Pull Request
PR_MESSAGE=`echo -e "${COMMIT_TITLE}"`
hub pull-request --push --message "${PR_MESSAGE}" --base "${KUBECF_BRANCH}"
