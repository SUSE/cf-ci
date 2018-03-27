#!/usr/bin/env sh
set -e
PATH=$PATH:$PWD/bin
GOPATH=$PWD
TOP=$PWD

# This is the long-living fork of upstream we use to generate the PR
# from.
FORK=SUSE/cli-plugin-repo

if [ -z "$UPSTREAM"  ]; then
  echo "Don't know where to make the pull request, UPSTREAM is undefined"
  exit 1
fi

# Configuration for `hub`.

if [ -z "$GITHUB_USER"  ]; then
  echo "GITHUB_USER environment variable not set"
  # Example: "cf-ci-bot@suse.de"
  exit 1
fi
if [ -z "$GITHUB_TOKEN"  ]; then
  echo "GITHUB_TOKEN environment variable not set"
  exit 1
fi

# # ## ### ##### ######## ############# #####################
## SSH to github

echo
echo SSH setup ...

# Need to set up access to the appropriate repos
eval "$(ssh-agent)"
trap "ssh-agent -k" EXIT

grep --null-data '^GITHUB_KEY=' /proc/self/environ \
    | tail -c +12 \
    | tr '\0' '\n' \
    | ssh-add /dev/stdin
unset GITHUB_KEY

# Pick up the SSH host key
ssh -o StrictHostKeyChecking=no -l git github.com <&- 2>&1 \
    | grep "successfully authenticated"

# # ## ### ##### ######## ############# #####################
## configuration

echo
echo Configuration ...

# Inputs:
# release/
#	tag
#	version
#	body
#	commit_sha
#	<assets> (cf-*, L*, R*)
# src-ci/

TAG=$(cat release/tag)
VER=$(cat release/version)
NOW=$(date -u --iso-8601=s | sed -e 's/\+.*$/Z/')

PR_BRANCH=cf-usb-plugin-${TAG}
PR_TITLE="Release cf-usb-plugin ${TAG}"
PR_DESC="Release cf-usb-plugin ${TAG} from https://github.com/SUSE/cf-usb-plugin/releases/${TAG}"

echo 'TAG:    ' ${TAG}
echo 'VERSION:' ${VER}
echo 'NOW:    ' ${NOW}
echo 'BRANCH: ' ${PR_BRANCH}
echo 'gh_USER:' ${GITHUB_USER}
# No, we will not show the token.

# # ## ### ##### ######## ############# #####################
## Assemble index information

echo
echo Assembling the yaml ...

rm -f  index.yml
cat >> index.yml <<EOF
- authors:
  - contact:  ${CONTACT}
    homepage: ${HOMEURL}
    name:     ${NAME}
  binaries:
EOF

platform() {
    local path="$1"
    case $path in
	*darwin-amd64*)  echo osx ;;
	*linux-386*)     echo linux32 ;;
	*linux-amd64*)   echo linux64 ;;
	*windows-386*)   echo win32 ;;
	*windows-amd64*) echo win64 ;;
	*)               echo Unable to determine platform code
	                 exit 1 ;;
    esac
}

# Ignore the checksum files
rm release/*.SHA256

for asset in release/cf-usb-plugin-*
do
    echo
    echo Processing $asset ...
    HASH=$(sha1sum $asset | sed -e 's/ .*$//')
    BASE=$(basename $asset)
    PLAT=$(platform $asset)
    echo '- SHA1:' $HASH
    echo '- PLAT:' $PLAT

    cat >> index.yml <<EOF
  - checksum: ${HASH}
    platform: ${PLAT}
    url: https://github.com/SUSE/cf-usb-plugin/releases/download/${TAG}/${BASE}
EOF
done

cat >> index.yml <<EOF
  company:     ${COMPANY}
  created:     ${NOW}
  description: A plugin that controls the Universal Service Broker (https://github.com/SUSE/cf-usb)
  homepage:    https://github.com/SUSE/cf-usb-plugin
  name:        cf-usb-plugin
  updated:     ${NOW}
  version:     ${VER}
EOF

echo
echo Assembled index:
cat index.yml
echo

# # ## ### ##### ######## ############# #####################
## Start on making the upstream PR

echo
echo Creating the pull request ...

tar xvzf hub-release/hub-linux-amd64-* --wildcards --strip-components=2 '*/bin/hub'
HUB="${PWD}/hub"
chmod +x ${HUB}

# Clone the upstream github repo. The chosen directory name is
# independent of the configured upstream name, during testing we may
# operate on a repo with a different name.
#
# Note also that the chosen directory matches what the GO code expects
# for its imports to work.

echo ; echo = Clone

mkdir -p                 src/code.cloudfoundry.org
${HUB} clone ${UPSTREAM} src/code.cloudfoundry.org/cli-plugin-repo

# Enter local checkout
cd src/code.cloudfoundry.org/cli-plugin-repo

# Admin stuff for the checkout. Notably, point it to the SUSE fork,
# that is where we will push the changes to.

${HUB} config user.email "${GITHUB_USER}"
${HUB} config user.name  "${GITHUB_USER}"
${HUB} remote add -p FORK ${FORK}

# Show the configured remotes
git remote -v

echo ; echo = Modify

# Add our release to the index -- This are our changes
cat ${TOP}/index.yml >> repo-index.yml
go run sort/main.go   repo-index.yml

# Create the branch, stage, commit and push the changes.
# Note that the changes are pushed to the FORK, not origin

echo ; echo = Branch
${HUB} checkout -b ${PR_BRANCH}

echo ; echo = Stage
${HUB} -c core.fileMode=false add .

echo ; echo = Commit
${HUB} commit -m "Submitting ${PR_BRANCH}"

echo ; echo = Push
${HUB} push FORK ${PR_BRANCH}

echo ; echo = PR
# At last, open the Pull Request, head: current branch, base: master
${HUB} pull-request \
    -m "$(printf "${PR_TITLE}\n\n${PR_DESC}\n")" \
    -b ${UPSTREAM}:master \
    -h ${FORK}:${PR_BRANCH}

echo ... Goodbye and godspeed
exit
