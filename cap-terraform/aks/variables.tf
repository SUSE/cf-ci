variable "az_resource_group" {
    type = "string"
}

variable "location" {
    type = "string"
}

variable "node_count" {
    default = "1"
}
variable "machine_type" {
    default = "Standard_DS3_v2"
}

variable "agent_admin" {
    type = "string"
}

variable "dns_prefix" {
    default = "cap-on-aks"
}

variable "cluster_labels" {
    type = "map"
}

variable "k8s_version" {
    default = "1.13.5"
}
variable "disk_size_gb" {
    default = 60
}

variable client_id {
    type = "string"
}

variable client_secret {
    type = "string"
}

variable "ssh_public_key" {
    type = "string"
}
