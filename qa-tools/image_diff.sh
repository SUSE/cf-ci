#!/bin/sh

# Usage: images_diff.sh <helm chart dir1> <helm chart dir2>
# Compares checksums for images defined in the charts in helm chart dir1 and
# helm chart dir1 by fetching the container manifests and extracting their
# image layer blobSums.
# When checksums are identical, exit code is 1, otherwise 0


DIRECTORIES=($1 $2)

USER=${KUBE_REGISTRY_USERNAME}
PASSWD=${KUBE_REGISTRY_PASSWORD}


if [ -z "${CAP_CHART}" ]; then
    CHARTS=(cf uaa)
elif [ ${CAP_CHART} == "opensuse" ]; then
    CHARTS=(cf-opensuse uaa-opensuse)
else
    echo "CAP_CHART not set, exiting"
    exit 1
fi


IDENTICAL=0


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
for DIR in ${DIRECTORIES[*]}; do
    rm -rf ${DIR}/*-image_checksums.txt

    for CHART in ${CHARTS[*]}; do
        HOST=$(grep hostname: ${DIR}/helm/${CHART}/values.yaml | sed 's/.*"\(.*\)".*/\1/')
        ORG=$(grep organization: ${DIR}/helm/${CHART}/values.yaml | sed 's/.*"\(.*\)".*/\1/')

        for IMAGE in $(grep image: ${DIR}/helm/${CHART}/templates/*.yaml | sed 's/.*\/\(.*-.*:.*\)".*/\1/'); do
            read NAME TAG <<< $(echo ${IMAGE} | sed 's/\(.*\):\(.*\)/\1 \2/')
            echo Name: ${NAME} >> ${DIR}/${CHART}-image_checksums.txt
            get_image_checksums >> ${DIR}/${CHART}-image_checksums.txt
        done
    done
done


# compare image checksums
for CHART in ${CHARTS[*]}; do
    diff ${DIRECTORIES[0]}/${CHART}-image_checksums.txt ${DIRECTORIES[1]}/${CHART}-image_checksums.txt && IDENTICAL=1
done

# return 1 if checksums are identical
if [ ${IDENTICAL} -eq 1 ]; then
    echo "Image checksums are identical"
    exit 1
fi

exit 0
