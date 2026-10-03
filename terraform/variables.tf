variable "project_id" {
  type        = string
  description = "The Google Cloud project ID"
}

variable "region" {
  type        = string
  description = "The target GCP region"
}

variable "region_subnets" {
  default = {
    "europe-west1": "10.0.10.0/24",
    "europe-west2": "10.0.20.0/24",
    "europe-west3": "10.0.30.0/24",
    "europe-west4": "10.0.40.0/24",
    "us-central1": "10.0.100.0/24",
  }
}

variable "zone" {
  type        = string
  description = "The target GCP zone"
}

variable "machine_image" {
  type        = string
  description = "The source machine image for the boot disk"
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
