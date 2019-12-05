#!/usr/bin/env bash

set -o errexit -o nounset

# Updates release information in role-manifest
# Looks for a release like:
#
# - type: replace
#   path: /releases/name=go-buildpack
#   value:
#     name: suse-go-buildpack
#     url: "https://s3.amazonaws.com/suse-final-releases/go-buildpack-release-1.8.42.1.tgz"
#     version: "1.8.42.1"
#     sha1: "f811bef86bfba4532d6a7f9653444c7901c59989"

function update_buildpack_info() {

KUBECF_OPS_SET_SUSE_BUILDPACKS=$1
RELEASE=$2
NEW_URL=$3
NEW_VERSION=$4
NEW_SHA=$5

PYTHON_CODE=$(cat <<EOF 
#!/usr/bin/python3

import ruamel.yaml

yaml = ruamel.yaml.YAML()
yaml.preserve_quotes = True

with open("${KUBECF_OPS_SET_SUSE_BUILDPACKS}") as fp:
    buildpacks = yaml.load(fp)

for buildpack in buildpacks:
    if buildpack['value']['name'] == "${RELEASE}":
        buildpack['value']['url'] = "${NEW_URL}"
        buildpack['value']['version'] = "${NEW_VERSION}"
        buildpack['value']['sha1'] = "${NEW_SHA}"
        break

with open("${KUBECF_OPS_SET_SUSE_BUILDPACKS}", 'w') as f:
    yaml.dump(buildpacks, f)

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

base_dir=$(pwd)
# Get version from the GitHub release that triggered this task
pushd gh_release
RELEASE_VERSION=$(cat version)
RELEASE_URL=$(cat body | grep -o "Release Tarball: .*" | sed 's/Release Tarball: //')
RELEASE_SHA=$(sha1sum ${base_dir}/suse_final_release/*.tgz | cut -d' ' -f1)
popd

COMMIT_TITLE="Bump ${NAME_IN_ROLE_MANIFEST} release to ${RELEASE_VERSION}"

# Update release in kubecf repo
cp -r kubecf/. updated-kubecf/
cd updated-kubecf

git pull
export GIT_BRANCH_NAME="bump_${NAME_IN_ROLE_MANIFEST}-`date +%Y%m%d%H%M%S`"
git checkout -b "${GIT_BRANCH_NAME}"

update_buildpack_info "${KUBECF_OPS_SET_SUSE_BUILDPACKS}" "${NAME_IN_ROLE_MANIFEST}" "${RELEASE_URL}" "${RELEASE_VERSION}" "${RELEASE_SHA}"

git commit "${KUBECF_OPS_SET_SUSE_BUILDPACKS}" -m "${COMMIT_TITLE}"

# Open a Pull Request
PR_MESSAGE=`echo -e "${COMMIT_TITLE}"`
hub pull-request --push --message "${PR_MESSAGE}" --base "${KUBECF_BRANCH}"
