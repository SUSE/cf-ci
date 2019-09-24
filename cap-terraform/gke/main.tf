resource "random_string" "cluster_name" {
  length  = 18
  special = false
  upper   = false
  number  = false
}

resource "google_container_cluster" "gke-cluster" {
  name     = "${var.cluster_name}"
  location = "${var.location}"

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true

  initial_node_count = 1
  min_master_version = "${var.k8s_version}"
  node_version = "${var.k8s_version}"

  resource_labels = "${var.cluster_labels}"

  # Setting an empty username and password explicitly disables basic auth
  master_auth {
    username = ""
    password = ""
  }

  addons_config {
    http_load_balancing {
      disabled = true
    }

    horizontal_pod_autoscaling {
      disabled = true
    }

    kubernetes_dashboard {
      disabled = true
    }
  }
}

resource "google_container_node_pool" "np" {
  name       = "${var.node_pool_name}"
  location   = "${var.location}"
  cluster    = "${google_container_cluster.gke-cluster.name}"
  node_count = "${var.node_count}"

  node_config {
    preemptible  = false
    machine_type = "${var.machine_type}"
    disk_size_gb = "${var.disk_size_gb}"
    image_type   = "${var.vm_type}"

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
  }

  management {
    auto_repair  = false
    auto_upgrade = false
  }
}

resource "null_resource" "post_processor" {
  depends_on = ["google_container_node_pool.np"]

  provisioner "local-exec" {
    command = "/bin/sh gke-post-processing.sh"

    environment = {
      CLUSTER_NAME = "${google_container_cluster.gke-cluster.name}"
      CLUSTER_ZONE = "${var.location}"
      NODE_COUNT   = "${var.node_count}"
      SA_KEY_FILE  = "${var.gke_sa_key}"
      PROJECT      = "${var.project}"
    }
  }
}

data "google_client_config" "current" {}
