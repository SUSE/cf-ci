#!/bin/bash
mkdir work

version="$(tr -d '[:space:]' < hcf-version/version)"

for i in "${PWD}/"*-release-tarball ; do
    release_name="${i##*/}"
    release_name="${release_name%-tarball}"
    mkdir "work/${release_name}"
    tar x -C "work/${release_name}" -zf "${i}"/*-release-tarball-*.tgz
done

tar c -C work -zf "${PWD}/out/all-releases-tarball-${version}.tgz" .
