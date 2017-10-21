#!/bin/bash
set -o errexit -o nounset
echo test >  scf-metrics/scf-metrics-$(date +%Y%m%d%H%M%S).csv
ls -al scf-metrics/*
touch ci/foo