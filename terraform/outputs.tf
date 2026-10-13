output "instance_addresses" {
  description = "Addresses of the VMs in each instance's managed instance group, keyed by instance"
  value = {
    for name, vms in local.instance_vms : name => {
      names       = [for vm in vms : vm.name]
      public_ips  = [for vm in vms : vm.network_interface[0].access_config[0].nat_ip]
      private_ips = [for vm in vms : vm.network_interface[0].network_ip]
    }
  }
}

output "instance_groups" {
  description = "Self-link of each instance's managed instance group"
  value       = { for name, mig in google_compute_region_instance_group_manager.mig : name => mig.instance_group }
}

output "start_commands" {
  description = "Rendered start commands for each instance"
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
      for name, m in local.hosted_models : name => {
        idle_timeout      = "2m"
        health_check_path = try(local.resolved_instances[m.instance].stop_when_ready.health_check_path, "/health")
        options = {
          baseURL = "http://{{public_ips.${try(local.first_vm[m.instance].name, m.instance)}}}:${m.port}/"
        }
        backend = {
          type           = "gcp_compute_engine"
          instance_names = [try(local.first_vm[m.instance].name, m.instance)]
          zone           = try(local.first_vm[m.instance].zone, null)
          project_id     = var.project_id
        }
      }
    }
  }
}
