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
    default = "Standard_DS4_v2"
}

variable "dns_prefix" {
    default = "cap-on-aks"
}

variable "cluster_labels" {
    type = "map"
}

variable "disk_size_gb" {
    default = 120
}

variable client_id {
    type = "string"
}

variable client_secret {
    type = "string"
}
