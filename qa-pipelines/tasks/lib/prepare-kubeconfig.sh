#!/bin/bash

# usage: read_yaml_key test.yaml key-name
read_yaml_key() {
    ruby -r yaml -e "puts YAML.load_file('$1')[\"$2\"]"
}

# This needs to be applied to EKS cluster so that it accepts kubeconfig with
# eksServiceRole arn
aws_auth_cm_yaml() {
    cat << 'EOF' >& 2
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: aws-auth
      namespace: kube-system
    data:
      mapRoles: |
        - rolearn: <ARN-node-instance-role>
          username: system:node:{{EC2PrivateDNSName}}
          groups:
            - system:bootstrappers
            - system:nodes
        - rolearn: arn:aws:iam::138384977974:role/eksServiceRole
          username: eksServiceRole
          groups:
            - system:masters
EOF
}

pool_file=${pool_file:-pool.kube-hosts/metadata}
mkdir -p /root/.kube
if [[ $(read_yaml_key ${pool_file} kind) == "Config" ]]; then
    cp ${pool_file} /root/.kube/config
    if grep "eks.amazonaws.com" ~/.kube/config; then
        cap_platform="eks"
        if ! grep "arn:aws:iam::138384977974:role/eksServiceRole" ~/.kube/config ||
         kubectl get configmap -n kube-system aws-auth | grep "arn:aws:iam::138384977974:role/eksServiceRole" > /dev/null; then
            echo "Your cluster may not have been configured for eksServiceRole. Make sure you run:"
            # Update to kubeconfig is required by AWS Jenkins user to assume eksServiceRole
            echo "aws eks update-kubeconfig --role-arn arn:aws:iam::138384977974:role/eksServiceRole"
            echo "kubectl apply -f aws-auth-cm.yaml"
            echo "aws-auth-cm.yaml:"
            aws_auth_cm_yaml
            exit 1
        fi
    fi

elif [[ $(read_yaml_key ${pool_file} platform) == "gke" ]]; then
    cap_platform=gke
    export CLOUDSDK_PYTHON_SITEPACKAGES=1
    export GKE_CLUSTER_NAME=$(read_yaml_key ${pool_file} cluster-name)
    export GKE_CLUSTER_ZONE=$(read_yaml_key ${pool_file} cluster-zone)
    base64 -d <<< "${GKE_PRIVATE_KEY_BASE64}" > gke-key.json
    export GKE_SERVICE_ACCOUNT_EMAIL=$(jq -r .client_email gke-key.json)
    export GKE_PROJECT_ID=$(jq -r .project_id gke-key.json)
    gcloud auth activate-service-account ${GKE_SERVICE_ACCOUNT_EMAIL} --project=${GKE_PROJECT_ID} --key-file gke-key.json
    gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --zone ${GKE_CLUSTER_ZONE}
    if ! kubectl get clusterrolebinding cluster-admin-binding &>/dev/null; then
        kubectl create clusterrolebinding cluster-admin-binding \
            --clusterrole cluster-admin \
            --user $(gcloud config get-value account)
    fi

    # GKE --cluster-cidr and --service-cluster-ip-range
    GKE_CLUSTER_CIDR=$(gcloud container clusters describe ${GKE_CLUSTER_NAME} --zone ${GKE_CLUSTER_ZONE} | grep clusterIpv4Cidr: | awk '{ print $2 }')
    GKE_SERVICE_CLUSTER_IP_RANGE=$(gcloud container clusters describe ${GKE_CLUSTER_NAME} --zone ${GKE_CLUSTER_ZONE} | grep servicesIpv4Cidr: | awk '{ print $2 }')
fi

echo "kubectl version:"
kubectl version
helm init --upgrade
kubectl wait --timeout=10m --namespace kube-system --for=condition=ready pod --all
echo "helm/tiller version:"
helm version
