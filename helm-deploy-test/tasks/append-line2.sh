#!/bin/bash
METRICS_FILE="$(ls scf-metrics-in/scf-metrics-*.csv)"
sed -i '$aappended another new line' "${METRICS_FILE}"
mv "${METRICS_FILE}" scf-metrics-out