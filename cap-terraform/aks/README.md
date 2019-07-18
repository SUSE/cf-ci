1. Create a terraform.tfvars (should be in your .gitignore as contains sensitive information) file with the following information
-  location
-  az_resource_group
-  ssh_public_key (SSH key file to SSH into worker nodes)
-  agent_admin(SSH user name)
-  client_id (Azure Service Principal client id - must be created with `az ad sp create-for-rbac`, cannot be created via portal)
-  client_secret ( Azure SP client secret)
- cluster_labels (any cluster labels, an optional map of key value pairs)
- project (for external-dns with GCP cloud DNS, GCP peoject id)
- gcp_dns_sa_key (for external-dns with GCP, GCP service account key location)

2. `terraform init`

3. `terraform plan`

4. `terraform apply`

5. A kube config named kubeconfig is generated in the same directory TF is run from.
