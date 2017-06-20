#!/bin/bash
mkdir work

version="$(tr -d '[:space:]' < semver.scf-version/version)"

for i in "${PWD}/s3."*-release-tarball ; do
    release_name="${i##*/s3.}"
    release_name="${release_name%-tarball}"
    mkdir "work/${release_name}"
    tar x -C "work/${release_name}" -zf "${i}"/*-release-tarball-*.tgz
done

tar c -C work -zf "${PWD}/out/all-releases-tarball-${version}.tgz" .
