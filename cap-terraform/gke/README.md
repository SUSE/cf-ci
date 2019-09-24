1. Create a `terraform.tfvars` (should be in your `.gitignore` as contains sensitive information) file with the following information
- `project` (GCP project id)
- `location` (GCP region)
- `node_pool_name` (Node pool name)
- `vm_type` (must be Ubuntu as of now as `cos_containerd` VMs do not support swap accounting)
- `gke_sa_key` (location of the key file for the GCP service account)
- `gcp_dns_sa_key` (location of the key file for the GCP service account that will do the DNS records setup, can be same as above as long as the account has sufficent rights to do DNS management)
- `cluster_labels` (optional map of key-value pairs)

  **Note:** You can copy `terraform.tfvars.template` to `terraform.tfvars` and edit the values.

2. `terraform init`

3. `terraform plan -out <path-to-save-plan>`

4. `terraform apply <path-to-saved-plan>`

