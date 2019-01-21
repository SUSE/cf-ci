#!/bin/sh

# The index of the chart to download, 2 being the chart previous to the last one
index=2
CAP_DIRECTORY=s3.scf-config


if [ -z "${CAP_CHART}" ]; then
    OS_MATCH="sle-"
elif [ ${CAP_CHART} == "opensuse" ]; then
    OS_MATCH="opensuse-"
else
    echo "CAP_CHART not set, exiting"
fi

# get name of chart released previous to the latest chart and download it
prev_chart=$(curl -s https://cap-release-archives.s3.amazonaws.com/ | sed 's/>/\n/g' | grep master | grep ${OS_MATCH} | grep zip | sed 's/^master\/\(.*\)<\/Key.*$/\1/' | sort -V -r | sed "${index}q;d")
echo Chart will be compared with ${prev_chart}

rm -rf prev_chart
curl -s https://s3.amazonaws.com/cap-release-archives/master/$(echo ${prev_chart} | sed s/+/%2B/) > ${prev_chart} && unzip -d prev_chart ${prev_chart}

unzip -d ${CAP_DIRECTORY} ${CAP_DIRECTORY}/*.zip

ci/qa-tools/image_diff.sh prev_chart s3.scf-config
