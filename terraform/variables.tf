variable "project_id" {
  type        = string
  description = "The Google Cloud project ID"
}

variable "region" {
  type        = string
  description = "The provider's default GCP region"
}

variable "region_subnets" {
  default = {
    "europe-west1": "10.0.110.0/24",
    "europe-west2": "10.0.120.0/24",
    "europe-west3": "10.0.130.0/24",
    "europe-west4": "10.0.140.0/24",
    "us-central1": "10.0.200.0/24",
    "us-east4": "10.0.210.0/24",
    "us-east5": "10.0.220.0/24",
  }
}

variable "zone" {
  type        = string
  description = "The provider's default GCP zone"
}

variable "machine_image" {
  type        = map(string)
  description = "Source machine image for the boot disk, keyed by runtime"
}

variable "client_ip" {
  type        = string
  description = "Allowed IP address or CIDR range for SSH and HTTP ingress (defaults to specific IP /32)"
}

variable "instance_name" {
  type        = string
  description = "Name prefix for the compute instance and resources"
  default     = "scallama-inference"
}
