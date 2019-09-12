provider "google" {
#	You can also set GOOGLE_CREDENTIALS to point to the service account key file to pick up the credentials
#   See https://www.terraform.io/docs/providers/google/provider_reference.html
	version 	= "~> 2.3"
	credentials = "${var.gke_sa_key}"
	project     = "${var.project}"
}

