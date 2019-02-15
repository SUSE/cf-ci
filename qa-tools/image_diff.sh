#!/bin/sh

# Usage: images_diff.sh <helm chart 1> <helm chart 2>
# Compares checksums for images defined in the charts in helm chart 1 and
# helm chart 1 by fetching the container manifests and extracting their
# image layer blobSums.
# Username and Password for a protected docker registry are given as
# enviroment variables KUBE_REGISTRY_USERNAME and KUBE_REGISTRY_PASSWORD
#
# When checksums are identical, exit code is 1, otherwise 0


if [ ${#@} -lt 2 ]; then
    echo "Not enough parameters provided"
    echo "Usage: ${0} <Helm Chart 1> <Helm Chart 2>"
    echo
    echo "Helm Charts can be provided as dir, zip or tgz"
    exit 1
fi

[[ -z "$KUBE_REGISTRY_USERNAME" ]] && echo "No KUBE_REGISTRY_USERNAME set"
[[ -z "$KUBE_REGISTRY_PASSWORD" ]] && echo "No KUBE_REGISTRY_PASSWORD set"


PARAMETERS=($1 $2)
USER=${KUBE_REGISTRY_USERNAME}
PASSWD=${KUBE_REGISTRY_PASSWORD}


# examine parameters if directory or archive
MIMETYPE=$(file --mime-type ${PARAMETERS[0]})
case "$MIMETYPE" in
    *directory)
        echo "Parameters are directories"
        DIRECTORIES=(${1} ${2})
        ;;
    *gzip)
        echo "Parameters are gzipped, checking for tgz archives"
        if [[ ${PARAMETERS[0]} = *.tgz ]]; then
            DIRECTORIES=(${1%.*} ${2%.*})
            echo "tgz identified - unpacking to ${DIRECTORIES[0]} and ${DIRECTORIES[1]}"
            rm -rf ${DIRECTORIES[*]} && mkdir ${DIRECTORIES[*]}
            tar xzvf ${PARAMETERS[0]} -C ${DIRECTORIES[0]} --strip-components 1 > /dev/null
            tar xzvf ${PARAMETERS[1]} -C ${DIRECTORIES[1]} --strip-components 1 > /dev/null
        else
            echo "no tgz identified - exiting"
            exit 1
        fi
        ;;
    *zip)
        DIRECTORIES=(${1%.*} ${2%.*})
        echo "Parameters are zipped - unpacking ${DIRECTORIES[0]} and ${DIRECTORIES[1]}"
        rm -rf ${DIRECTORIES[*]} && mkdir ${DIRECTORIES[*]}
        unzip -d ${DIRECTORIES[0]} ${PARAMETERS[0]} > /dev/null
        unzip -d ${DIRECTORIES[1]} ${PARAMETERS[1]} > /dev/null
        ;;
    *)
        echo "Input file type is unknown - exiting"
        exit 1
        ;;
esac


CHARTS=($(ls ${DIRECTORIES[0]}/helm/))


function get_checksums_token {
    AUTHENTICATE=$(curl --silent -I https://${HOST}/v2/${ORG}/${NAME}/manifests/${TAG} | grep -i www-authenticate)
    IFS="|" read -r REALM SERVICE SCOPE <<< $(echo ${AUTHENTICATE} | sed 's/^Www-Authenticate: Bearer realm="\(.*\)",service="\(.*\)",scope="\(.*\)".*/\1|\2|\3/' )

    # escape spaces
    SERVICE_WEB=$(echo ${SERVICE} | sed 's/ /%20/g')

    # Fetch Auth Token for image
    if [ $HOST == "docker.io" ]; then
        # For docker.io we need to curl different hosts
        TOKEN=$(curl --silent "https://auth.docker.io/token?scope=repository:${ORG}/${NAME}:pull&service=registry.docker.io" | jq -r '.token')
        curl --silent -H "Authorization: Bearer ${TOKEN}" "https://registry-1.docker.io/v2/${ORG}/${NAME}/manifests/${TAG}" | grep blobSum
    else
        # For private repositories like registry.suse.com
        TOKEN=$(curl --silent -X GET "${REALM}?service=${SERVICE_WEB}&scope=${SCOPE}" | jq -r '.token')
        curl --silent -H "Authorization: Bearer ${TOKEN}" "https://${HOST}/v2/${ORG}/${NAME}/manifests/${TAG}" | grep blobSum
    fi
}


function get_checksums_basic {
    curl --silent --user ${USER}:${PASSWD} https://${HOST}/v2/$ORG/${NAME}/manifests/${TAG} | grep blobSum
}


function get_image_checksums {
    if [ ${HOST} == "staging.registry.howdoi.website" ]; then
        # staging.registry.howdoi.website has no token based authentication
        get_checksums_basic
    else
        get_checksums_token
    fi
}


# extract images from Charts and fetch image checksums from the image digests
echo "Retrieving image checksums from docker registry"
for DIR in ${DIRECTORIES[*]}; do
    rm -rf ${DIR}/image_checksums
    mkdir ${DIR}/image_checksums

    for CHART in ${CHARTS[*]}; do
        HOST=$(grep hostname: ${DIR}/helm/${CHART}/values.yaml | sed 's/.*"\(.*\)".*/\1/')
        ORG=$(grep organization: ${DIR}/helm/${CHART}/values.yaml | sed 's/.*"\(.*\)".*/\1/')

        # write image checksums into files
        for IMAGE in $(grep image: ${DIR}/helm/${CHART}/templates/*.yaml | sed 's/.*\/\(.*-.*:.*\)".*/\1/'); do
            read NAME TAG <<< $(echo ${IMAGE} | sed 's/\(.*\):\(.*\)/\1 \2/')
            echo Name: ${NAME} >> ${DIR}/image_checksums/${CHART}-${NAME}-image_checksums.txt
            get_image_checksums >> ${DIR}/image_checksums/${CHART}-${NAME}-image_checksums.txt
            #IMAGELIST[${#IMAGELIST[*]}]=${NAME}
        done
    done
done


# compare image checksum files and print them side by side
echo "Comparing image checksums"
for CHART in ${CHARTS[*]}; do
    for FILE in ${DIRECTORIES[0]}/image_checksums/${CHART}-*-image_checksums.txt; do
        echo
        echo
        echo "$(basename ${DIRECTORIES[0]})                                                             $(basename ${DIRECTORIES[1]})"
        if diff -y ${FILE} ${DIRECTORIES[1]}/image_checksums/$(basename ${FILE}); then
            # if checksums are identical add filename to array
            IDENTICAL[${#IDENTICAL[*]}]="${FILE}"
        fi
    done
done

# return 1 if checksums are identical for any images
if [ ${#IDENTICAL[*]} -gt 0 ]; then
    echo "Image checksums are identical for: ${IDENTICAL[*]}"
    exit 1
fi

echo "Image checksums differ"
exit 0
