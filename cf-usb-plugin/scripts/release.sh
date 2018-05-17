#!/usr/bin/env sh
set -e
PATH=$PATH:$PWD/bin
GOPATH=$PWD

SRC=${PWD}/src/github.com/SUSE/cf-usb-plugin
TAG=$(git -C "${SRC}" describe --tags --abbrev=0)
LAST_TAG=$(git -C "${SRC}" describe --tags --abbrev=0 HEAD^)
NAME=$(basename "$(git -C "${SRC}" config --get remote.origin.url)" .git)

# Show incoming state
echo NAME: ${NAME}
echo TAG_: ${TAG}
echo LAST: ${LAST_TAG}

# Assemble configuration data for `out` to git-release resource.
echo > release/commitish "${TAG}"
echo > release/name "${TAG}"
echo > release/tag  "${TAG}"
echo > release/body "${NAME}: Release ${TAG}"
echo >> release/body ""
git -C "${SRC}" log --reverse --pretty=%s --merges ${LAST_TAG}...${TAG} \
    >> release/body

# Build the tarballs for the release
make -C "${SRC}" build dist

# Show configuration in log
echo Release information:
for path in release/*
do
    printf "%s: " "${path#**/}"
    cat "$path"
done

# Unpack the tarballs into the release.
mkdir release/assets
for path in ${SRC}/*.tgz
do
    echo "Processing ${path} ..."

    tar xfz "${path}" \
	-C release/assets/ \
	--strip-components=2 \
	--overwrite \
	--transform="s@/cf-usb-plugin@/$(basename "${path}" .tgz)@"
done

# And calculate the checksums for all the executables
(
    cd release/assets
    for path in cf-*
    do
	sha256sum "${path}" > "$(basename "${path}" .exe).SHA256"
    done
)

# Collect the release into a single tarball for S3 side load.
tar czf "cf-usb-plugin/cf-usb-plugin-${TAG}-release.tgz" -C release .

# Show assembly in log
echo Assembled:
ls -lR release

# Show assembly in log
echo Assembled:
ls -lR cf-usb-plugin
