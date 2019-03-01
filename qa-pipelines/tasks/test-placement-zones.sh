#!/bin/bash

set -o errexit -o xtrace
test_pz_label=testpzlabel

get_apps_on_cell() {
    local cell=$1
    kubectl exec -n scf diego-cell-0 -c diego-cell -- bash -c '
        echo "$INTERNAL_CA_CERT" > ca-crt
        echo "$BBS_CLIENT_CRT" > bbs-crt
        echo "$BBS_CLIENT_CRT_KEY" > bbs-key
    '
    local bbs_url=$(kubectl exec -n scf diego-cell-0 -c diego-cell -- bash -c 'echo https://\$DIEGO_API_BBS_SERVICE_HOST:\$DIEGO_API_BBS_SERVICE_PORT_CELL_BBS_API')
    local cfdot_params="cell-state --clientCertFile bbs-crt --clientKeyFile bbs-key --caCertFile ca-crt --skipCertVerify --bbsURL=$bbs_url $cell"
    kubectl exec -n scf diego-cell-0 -c diego-cell -- bash -c "/var/vcap/packages/cfdot/bin/cfdot $cfdot_params | jq -r '.LRPs[] | .process_guid[0:36]'"
}

get_cells_in_pz() {
    # Prints list of cells on nodes with PZ label matching $1
    # If $1 is empty or not provided, it will print cells on nodes with an unset or empty PZ label
    local nodes_in_pz node
    if [[ -n $1 ]]; then
        nodes_in_pz=$(kubectl get nodes -l $test_pz_label=$1 --no-headers | awk '{print $1}')
    else
        nodes_in_pz=$(
            kubectl get nodes -l $test_pz_label= --no-headers | awk '{print $1}'
            kubectl get nodes -l \!$test_pz_label --no-headers | awk '{print $1}'
        )
    fi
    for node in $nodes_in_pz; do
        kubectl get pods -n scf --no-headers --field-selector spec.nodeName=$node -l skiff-role-name=diego-cell | awk '{ print $1 }'
    done
}

get_apps_in_pz() {
    # Print the app ID for all app instances in a PZ. For multiple instances of an app, the app ID will be repeated
    local cell
    for cell in $(get_cells_in_pz $1); do
        get_apps_on_cell $cell;
    done
}

git clone https://github.com/harts/go-env
cd go-env

pzs="pz0 pz1"
for pz in $pzs; do
    cf create-isolation-segment ${pz}
    cf create-org ${pz}-org
    cf enable-org-isolation ${pz}-org ${pz}
    cf set-org-default-isolation-segment ${pz}-org ${pz}
    cf create-space -o ${pz}-org ${pz}-space
    cf target -o ${pz}-org -s ${pz}-space
    cf push -i 10 go-env-${pz}
    app_guid=$(cf app --guid go-env-${pz})
    echo "App $app_guid running 10 instances in $pz"
    [[ $(get_apps_in_pz $pz | grep "^$app_guid\$" | wc -l) -eq 10 ]]
    echo "OK"
    cf delete -f -r go-env-${pz}
done
