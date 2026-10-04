output "instance_name" {
  description = "The name of the created compute instance"
  value       = [for instance in google_compute_instance_from_template.vm : instance.name]
}

output "instance_self_link" {
  description = "Self-link of the created compute instance"
  value       = [for instance in google_compute_instance_from_template.vm : instance.self_link]
}

output "public_ip" {
  description = "The public ephemeral IP address of the instance"
  value       = [for instance in google_compute_instance_from_template.vm : instance.network_interface[0].access_config[0].nat_ip]
}

output "start_commands" {
  description = "Rendered start command for each model instance"
  value       = local.run_commands
}

output "vpc_name" {
  description = "The name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "subnet_names" {
  description = "The names of the subnetworks, keyed by region"
  value       = { for region, subnet in google_compute_subnetwork.subnets : region => subnet.name }
}

output "scallama_config" {
  description = "Scallama configuration"
  value = {
    models = {
      for name, instance in local.instances : name => {
        idle_timeout      = "2m"
        health_check_path = try(instance.stop_when_ready.health_check_path, "/health")
        options = {
          baseURL = "http://{{public_ips.${instance.vm_name}}}:8000/"
        }
        backend = {
          type           = "gcp_compute_engine"
          instance_names = [instance.vm_name]
          zone           = instance.zone
          project_id     = var.project_id
        }
      }
    }
  }
}
