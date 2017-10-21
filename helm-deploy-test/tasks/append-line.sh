#!/bin/bash
set -o errexit -o nounset
find . -not -path "./ci/*"
METRICS_FILE="$(ls scf-metrics-in/scf-metrics-*.csv)"
sed -i '$aappended a new line' "${METRICS_FILE}"
mv "${METRICS_FILE}" scf-metrics-out