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

BUILDPACK_NAME=$1
KUBECF_VALUES=$2
BUILT_IMAGE=$3
NEW_FILE_NAME=$4

PYTHON_CODE=$(cat <<EOF 
#!/usr/bin/python3

import ruamel.yaml

yaml = ruamel.yaml.YAML()
yaml.preserve_quotes = True

NEW_URL = "/".join(BUILT_IMAGE.split("/", 2)[:2])
BUILT_IMAGE = BUILT_IMAGE.split("-")
NEW_VERSION = BUILT_IMAGE[-1]
NEW_STEMCELL_OS = BUILT_IMAGE[3].split(":")[1]
NEW_STEMCELL_VERSION = "-".join(BUILT_IMAGE[4:6])

with open("${KUBECF_VALUES}") as fp:
    buildpacks = yaml.load(fp)['releases']

for release in releases:
    if release == "${BUILDPACK_NAME}":
        buildpack['url'] = "${NEW_URL}"
        buildpack['stemcell']['os'] = "${NEW_STEMCELL_OS}"
        buildpack['stemcell']['version'] = "${NEW_STEMCELL_VERSION}"
        new_file = buildpack['file'].split("/")[:3]
        new_file.append("${NEW_FILE_NAME}")
        buildpack['file'] = "/".join(new_file)
        break

with open("${KUBECF_VALUES}", 'w') as f:
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

RELEASE_VERSION=$(cat suse_final_release/version)
BUILT_IMAGE=$(cat built_image/image)
NEW_FILE=$(tar -zxOf suse_final_release/*.tgz packages | tar -ztf - | grep zip | cut -d'/' -f3)

COMMIT_TITLE="Bump ${BUILDPACK_NAME} release to ${RELEASE_VERSION}"

# Update release in kubecf repo
cp -r kubecf/. updated-kubecf/
cd updated-kubecf

git pull
export GIT_BRANCH_NAME="bump_${BUILDPACK_NAME}-`date +%Y%m%d%H%M%S`"
git checkout -b "${GIT_BRANCH_NAME}"

update_buildpack_info "${BUILDPACK_NAME}" "${KUBECF_VALUES}" "${BUILT_IMAGE}" "${NEW_FILE}"

git commit "${KUBECF_VALUES}" -m "${COMMIT_TITLE}"

# Open a Pull Request
PR_MESSAGE=`echo -e "${COMMIT_TITLE}"`
hub pull-request --push --message "${PR_MESSAGE}" --base "${KUBECF_BRANCH}"
