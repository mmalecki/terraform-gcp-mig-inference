locals {
  vllm_stop = {
    health_check_path = "/health"
    health_check_port = 8000
  }
  sizes = {
    "g2-standard-4" = {
      disks = 1
      gpus  = 1
      # vram = 24G (1x L4)
    }
    "g2-standard-8" = {
      disks = 1
      gpus  = 1
      # vram = 24G (1x L4)
    }
    "g2-standard-16" = {
      disks = 1
      gpus  = 1
      # vram = 24G (1x L4)
    }
    "g2-standard-24" = {
      disks = 2
      gpus  = 2
      # vram = 48G (2x L4)
    }
    "g2-standard-48" = {
      disks = 4
      gpus  = 4
      # vram = 96G (4x L4)
    }
    "g4-standard-48" = {
      disk_type = "hyperdisk-balanced"
      disks     = 4
      gpus      = 1
      # vram = 96G (1x RTX PRO 6000)
    }
  }

  # Each model lists its variants: a `runtime` (a key of `var.machine_image`),
  # an instance `size` and a `command` (runtime args as shell, with line
  # continuations, starting with the model to load; the runtime's common
  # `docker run` is wrapped around it). A full `run_command` can be given
  # instead of `command`.
  models = {
    "google/gemma-4-E2B-it" = {
      variants = {
        vllm = {
          runtime = "vllm"
          size    = "g2-standard-4"
          command = <<-EOF
            google/gemma-4-E2B-it \
            --tool-call-parser gemma4 \
            --chat-template examples/tool_chat_template_gemma4.jinja \
            --reasoning-parser gemma4 \
            #--speculative-config '{"method":"mtp","model":"google/gemma-4-E2B-it-assistant","num_speculative_tokens":2}'
          EOF
        }
        # The repo's mtp-gemma-4-E2B-it-*.gguf drafter is fetched alongside the model
        llamacpp-bf16 = {
          runtime = "llamacpp"
          size    = "g2-standard-4"
          command = <<-EOF
            -hf ggml-org/gemma-4-E2B-it-GGUF:BF16 \
              #--spec-type draft-mtp --spec-draft-n-max 2
          EOF
        }
      }
    }
    "Qwen/Qwen3.5-9B" = {
      variants = {
        vllm = {
          runtime = "vllm"
          size    = "g2-standard-24"
          command = <<-EOF
            Qwen/Qwen3.5-9B \
            --trust-remote-code \
            --max-model-len 262144 \
            --reasoning-parser qwen3 \
            --tool-call-parser qwen3_coder \
              #--speculative-config '{"method":"qwen3_next_mtp","num_speculative_tokens":2}'
          EOF
        }
        llamacpp-q5_k_m = {
          runtime = "llamacpp"
          size    = "g2-standard-8"
          command = <<-EOF
            -hf bartowski/Qwen_Qwen3.5-9B-GGUF:Q5_K_M \
            -c 262144 \
            -np 4 --kv-unified \
            --no-mmproj \
            --temp 0.6 \
            --top-k 20 \
            --top-p 0.95 \
            --min-p 0 \
            --presence-penalty 0.0 --repeat-penalty 1.0 \
              #--spec-type draft-mtp --spec-draft-n-max 2
          EOF
        }
        llamacpp-q5_k_m-multi = {
          runtime = "llamacpp"
          size    = "g4-standard-48"
          command = <<-EOF
            -hf bartowski/Qwen_Qwen3.5-9B-GGUF:Q5_K_M \
            -c 262144 \
            -np 8 --kv-unified \
            --no-mmproj \
            --temp 0.6 \
            --top-k 20 \
            --top-p 0.95 \
            --min-p 0 \
            --presence-penalty 0.0 --repeat-penalty 1.0 \
              #--spec-type draft-mtp --spec-draft-n-max 2
          EOF
        }
      }
    }
    "Qwen/Qwen3.6-27B" = {
      variants = {
        vllm = {
          runtime = "vllm"
          size    = "g2-standard-48"
          command = <<-EOF
            Qwen/Qwen3.6-27B \
            --trust-remote-code \
            --tool-call-parser qwen3_coder \
            --reasoning-parser qwen3 \
            --language-model-only \
              #--speculative-config '{"method":"qwen3_next_mtp","num_speculative_tokens":2}'
          EOF
        }
      }
    }
    "Qwen/Qwen3.6-35B-A3B" = {
      variants = {
        # ~67G of BF16 weights on one 96G GPU. Only 10/40 layers use full
        # attention, so a full 262K context needs just ~5G of KV cache.
        vllm = {
          runtime = "vllm"
          size    = "g4-standard-48"
          command = <<-EOF
            Qwen/Qwen3.6-35B-A3B \
            --max-model-len 262144 \
            --reasoning-parser qwen3 \
            --tool-call-parser qwen3_coder \
            --language-model-only \
              #--speculative-config '{"method":"qwen3_next_mtp","num_speculative_tokens":2}'
          EOF
        }
        # ~36G of block FP8 weights on 2x L4 (48G) is tight, so the context is
        # halved to leave room for KV cache. Qwen advise at least 128K for thinking.
        vllm-fp8 = {
          runtime = "vllm"
          size    = "g2-standard-24"
          command = <<-EOF
            Qwen/Qwen3.6-35B-A3B-FP8 \
            --max-model-len 131072 \
            --reasoning-parser qwen3 \
            --tool-call-parser qwen3_coder \
            --language-model-only \
              #--speculative-config '{"method":"qwen3_next_mtp","num_speculative_tokens":2}'
          EOF
        }
        # ~25G of Q5_K_M weights plus ~5G of KV cache for the full 262K context
        # fits comfortably on 2x L4 (48G).
        llamacpp-q5_k_m = {
          runtime = "llamacpp"
          size    = "g2-standard-24"
          command = <<-EOF
            -hf bartowski/Qwen_Qwen3.6-35B-A3B-GGUF:Q5_K_M \
            -c 262144 \
            --no-mmproj \
            -np 4 --kv-unified \
            --chat-template-kwargs '{"preserve_thinking":true}' \
            --temp 0.6 \
            --top-k 20 \
            --top-p 0.95 \
            --min-p 0 \
            --presence-penalty 0.0 --repeat-penalty 1.0 \
              #--spec-type draft-mtp --spec-draft-n-max 2
          EOF
        }
        # ~37G of Q8_0 weights on 2x L4 (48G) is tight, so the context is halved
        # to leave room for KV cache.
        llamacpp-q8_0 = {
          runtime = "llamacpp"
          size    = "g2-standard-24"
          command = <<-EOF
            -hf bartowski/Qwen_Qwen3.6-35B-A3B-GGUF:Q8_0 \
            -c 131072 \
            --no-mmproj \
            -np 4 --kv-unified \
            --chat-template-kwargs '{"preserve_thinking":true}' \
            --temp 0.6 \
            --top-k 20 \
            --top-p 0.95 \
            --min-p 0 \
            --presence-penalty 0.0 --repeat-penalty 1.0 \
              #--spec-type draft-mtp --spec-draft-n-max 2
          EOF
        }
      }
    }
  }

  # Deployed instances, keyed by the model name they serve (and scallama routes
  # by). The VM is named after the last path segment of the key.
  #
  # Each instance sets the `region` it runs in, which must be a key of
  # `var.region_subnets`. Its group spreads instances across the zones of the
  # region that offer the instance's machine type. Set `zones` (a list of zone
  # names) to use exactly those zones instead.
  model_instances = {
    "google/gemma-4-E2B-it" = {
      model           = "google/gemma-4-E2B-it"
      variant         = "vllm"
      region          = var.region
      count           = 0
      spot            = false
      # stop_when_ready = local.vllm_stop
    }
    "Qwen/Qwen3.5-9B" = {
      model   = "Qwen/Qwen3.5-9B"
      region  = "us-central1"
      variant = "llamacpp-q5_k_m-multi"
      count   = 1
      spot    = true
      # stop_when_ready = local.vllm_stop
    }
    "Qwen/Qwen3.6-27B" = {
      model           = "Qwen/Qwen3.6-27B"
      variant         = "vllm"
      region          = var.region
      count           = 0
      spot            = true
      # stop_when_ready = local.vllm_stop
    }
    "Qwen/Qwen3.6-35B-A3B" = {
      model           = "Qwen/Qwen3.6-35B-A3B"
      variant         = "llamacpp-q5_k_m"
      region          = "us-east4"
      count           = 0
      spot            = false
      # stop_when_ready = local.vllm_stop
    }
    "Qwen/Qwen3.6-35B-A3B-FP8" = {
      model   = "Qwen/Qwen3.6-35B-A3B"
      variant = "vllm-fp8"
      region  = var.region
      count   = 0
      spot    = true
      # stop_when_ready  = local.vllm_stop
    }
  }

  instances = {
    for name, instance in local.model_instances : name => merge(instance, {
      vm_name = replace(lower(element(split("/", name), length(split("/", name)) - 1)), "/[^a-z0-9-]/", "-")
      variant = local.models[instance.model].variants[instance.variant]
    })
  }
  active_instances = { for name, instance in local.instances : name => instance if instance.count > 0 }

  # llama.cpp splits layers across all GPUs by default, and enables Jinja chat
  # templates (tool calling) and reasoning extraction out of the box.
  run_commands = {
    for name, instance in local.instances : name => try(instance.variant.run_command, {
      vllm     = <<-EOF
        docker run -d --name vllm --gpus all \
          --restart unless-stopped \
          --privileged --ipc=host -p 8000:8000 \
          -e HF_TOKEN \
          -v /mnt/local-ssd/cache:/root/.cache \
          vllm/vllm-openai:latest \
          ${indent(2, trimspace(instance.variant.command))} \
          --served-model-name ${name} \
          --tensor-parallel-size ${local.sizes[instance.variant.size].gpus} \
          --enable-auto-tool-choice
      EOF
      llamacpp = <<-EOF
        docker run -d --name llama --gpus all \
          --restart unless-stopped \
          -p 9931:9931 \
          -e HF_TOKEN \
          -v /mnt/local-ssd/cache:/root/.cache \
          ghcr.io/ggml-org/llama.cpp:server-cuda \
          --alias ${name} \
          -ngl all \
          --port 9931 \
          ${indent(2, trimspace(instance.variant.command))}
      EOF
    }[instance.variant.runtime])
  }
}

# VPC network for Scallama inference VMs
resource "google_compute_network" "vpc" {
  name                    = "${var.instance_name}-vpc"
  auto_create_subnetworks = false
}

# One subnetwork per supported region
resource "google_compute_subnetwork" "subnets" {
  for_each = var.region_subnets

  name          = "${var.instance_name}-${each.key}"
  ip_cidr_range = each.value
  region        = each.key
  network       = google_compute_network.vpc.id
}

# Ingress firewall rule restricting SSH and HTTP/Inference access to the specified client IP
resource "google_compute_firewall" "allow_ingress" {
  name    = "${var.instance_name}-allow-ingress"
  network = google_compute_network.vpc.name

  allow {
    protocol = "all"
  }

  source_ranges = [var.client_ip]
}

# Egress firewall rule allowing VM instances to communicate out to the world
resource "google_compute_firewall" "allow_egress" {
  name    = "${var.instance_name}-allow-egress"
  network = google_compute_network.vpc.name

  allow {
    protocol = "all"
  }

  destination_ranges = ["0.0.0.0/0"]
  direction          = "EGRESS"
}

# Instance template per active model instance. The template carries everything
# that varies per model (size, spot, service account and startup script), and
# is rolled out by the model's managed instance group.
resource "google_compute_instance_template" "templates" {
  for_each = local.active_instances

  name_prefix  = "${each.value.vm_name}-"
  machine_type = each.value.variant.size

  labels = {
    gpus   = tostring(local.sizes[each.value.variant.size].gpus)
    disks  = tostring(local.sizes[each.value.variant.size].disks)
    region = each.value.region
  }

  // Disk configuration
  disk {
    source_image = var.machine_image[each.value.variant.runtime]
    auto_delete  = true
    boot         = true
    disk_size_gb = 50
    disk_type    = lookup(local.sizes[each.value.variant.size], "disk_type", "pd-balanced")
  }

  // Dynamic Local SSD (Scratch disks)
  dynamic "disk" {
    for_each = range(local.sizes[each.value.variant.size].disks)
    content {
      disk_type    = "local-ssd"
      interface    = "NVME"
      type         = "SCRATCH"
      auto_delete  = true
      disk_size_gb = 375
    }
  }

  // Network interface
  network_interface {
    subnetwork = google_compute_subnetwork.subnets[each.value.region].id
    access_config {
      // Assigns an ephemeral public IP for external access
    }
  }

  scheduling {
    preemptible                 = each.value.spot
    provisioning_model          = each.value.spot ? "SPOT" : "STANDARD"
    instance_termination_action = each.value.spot ? "STOP" : null
    on_host_maintenance         = "TERMINATE"
    automatic_restart           = false
  }

  service_account {
    email  = google_service_account.vm[each.key].email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = <<-EOF
    touch /run/startup-running

    DISKS=$(ls /dev/disk/by-id/google-local-nvme-ssd-* 2>/dev/null)
    if [ -n "$DISKS" ]; then
      if ! zpool list local-ssd &>/dev/null; then
        if ! zpool import local-ssd &>/dev/null; then
          zpool create -m /mnt/local-ssd -f local-ssd $DISKS
        fi
      fi
    fi

    mkdir -p /mnt/local-ssd/cache/

    # Optionally pull HF_TOKEN from the `hf-token` secret in this VM's project.
    METADATA=http://metadata.google.internal/computeMetadata/v1
    PROJECT=$(curl -sf --max-time 5 -H "Metadata-Flavor: Google" $METADATA/project/project-id)
    ACCESS_TOKEN=$(curl -sf --max-time 5 -H "Metadata-Flavor: Google" \
      $METADATA/instance/service-accounts/default/token | sed -n 's/.*"access_token" *: *"\([^"]*\)".*/\1/p')
    if [ -n "$PROJECT" ] && [ -n "$ACCESS_TOKEN" ]; then
      HF_TOKEN=$(curl -sf --max-time 10 -H "Authorization: Bearer $ACCESS_TOKEN" \
        "https://secretmanager.googleapis.com/v1/projects/$PROJECT/secrets/hf-token/versions/latest:access" \
        | sed -n 's/.*"data" *: *"\([^"]*\)".*/\1/p' | base64 -d 2>/dev/null | tr -d '\r\n')
    fi
    if [ -n "$HF_TOKEN" ]; then
      export HF_TOKEN
      echo "HF_TOKEN loaded from hf-token secret"
    else
      unset HF_TOKEN
      echo "hf-token secret not available, continuing without HF_TOKEN"
    fi
    unset ACCESS_TOKEN

    ${local.run_commands[each.key]}

    touch /run/startup-complete

    # For future runs, start speed is important.
    touch /etc/cloud/cloud-init.disabled
    systemctl stop cloud-init-local.service snapd.service snapd.socket snapd.seeded.service
    systemctl disable cloud-init-local.service snapd.service snapd.socket snapd.seeded.service
    systemctl mask cloud-init-local.service snapd.service snapd.socket snapd.seeded.service
EOF

  # The token is read on first boot, so access must be granted beforehand
  depends_on = [google_secret_manager_secret_iam_member.hf_token]

  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = contains(keys(var.region_subnets), each.value.region)
      error_message = "Region \"${each.value.region}\" for \"${each.key}\" has no entry in var.region_subnets."
    }
  }
}

# Dedicated service account per VM
resource "google_service_account" "vm" {
  for_each = local.active_instances

  account_id   = each.value.vm_name
  display_name = "Scallama inference VM for ${each.key}"

  lifecycle {
    precondition {
      condition     = length(each.value.vm_name) >= 6 && length(each.value.vm_name) <= 30
      error_message = "VM name \"${each.value.vm_name}\" must be 6-30 characters to name its service account."
    }
  }
}

# APIs required by this deployment
resource "google_project_service" "services" {
  for_each = toset([
    "secretmanager.googleapis.com",
  ])

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# Allow each VM to read the optional `hf-token` secret
resource "google_secret_manager_secret_iam_member" "hf_token" {
  for_each = google_service_account.vm

  project   = var.project_id
  secret_id = "hf-token"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${each.value.email}"

  depends_on = [google_project_service.services]
}

# All zones of each region with an active model instance
data "google_compute_zones" "available" {
  for_each = toset([for instance in local.active_instances : instance.region])

  region = each.key
}

locals {
  # Candidate zones per model: the `zones` override if given, else the region's
  zone_candidates = {
    for name, instance in local.active_instances :
    name => try(instance.zones, data.google_compute_zones.available[instance.region].names)
  }

  # Zone and machine type pairs to check, for models without a `zones` override
  machine_type_checks = merge([
    for name, instance in local.active_instances : {
      for zone in local.zone_candidates[name] : "${zone}|${instance.variant.size}" => {
        zone = zone
        size = instance.variant.size
      }
    } if try(instance.zones, null) == null
  ]...)
}

# Zones don't all offer every machine type, especially GPU ones
data "google_compute_machine_types" "available" {
  for_each = local.machine_type_checks

  zone   = each.value.zone
  filter = "name = \"${each.value.size}\""
}

locals {
  # Zones each model's group is spread over
  mig_zones = {
    for name, instance in local.active_instances : name => (
      try(instance.zones, null) != null ? instance.zones : [
        for zone in local.zone_candidates[name] : zone
        if length(data.google_compute_machine_types.available["${zone}|${instance.variant.size}"].machine_types) > 0
      ]
    )
  }
}

# One regional managed instance group per active model instance, spread across
# the zones of the model's region that offer its machine type. No load
# balancing: instances are addressed individually.
resource "google_compute_region_instance_group_manager" "mig" {
  for_each = local.active_instances

  timeouts {
    create = "5m"
  }

  name                      = each.value.vm_name
  base_instance_name        = each.value.vm_name
  region                    = each.value.region
  distribution_policy_zones = local.mig_zones[each.key]
  target_size               = each.value.count

  # Place instances in whichever zone has capacity, rather than evenly
  distribution_policy_target_shape = "ANY"

  version {
    instance_template = google_compute_instance_template.templates[each.key].self_link
  }

  # GPU quota rarely allows a surge instance: replace in place. Fixed values on
  # a regional group must be 0 or at least the number of zones, and percentages
  # need a group of at least 10. RECREATE keeps instance names across
  # replacements, and the ANY distribution shape needs redistribution off.
  update_policy {
    type                         = "PROACTIVE"
    minimal_action               = "REPLACE"
    replacement_method           = "RECREATE"
    instance_redistribution_type = "NONE"
    max_surge_fixed              = 0
    max_unavailable_fixed        = length(local.mig_zones[each.key])
  }

  # Scallama stops idle instances and Spot preemption stops them too. By default
  # the group treats a VM stopped outside its control as failed and recreates
  # it, booting it straight back up from a fresh disk.
  instance_lifecycle_policy {
    default_action_on_failure = "DO_NOTHING"
  }

  # Instances must exist for the data sources below to read their addresses
  wait_for_instances = true

  lifecycle {
    precondition {
      condition     = length(local.mig_zones[each.key]) > 0
      error_message = "No zone in \"${each.value.region}\" offers machine type \"${each.value.variant.size}\" for \"${each.key}\". Set `zones` for it, or pick another size or region."
    }
  }
}

# Instances currently in each group
data "google_compute_region_instance_group" "mig" {
  for_each = google_compute_region_instance_group_manager.mig

  name   = each.value.name
  region = each.value.region
}

locals {
  mig_instance_links = {
    for name, group in data.google_compute_region_instance_group.mig :
    name => sort([for i in group.instances : i.instance])
  }

  # One entry per desired instance, keyed "<model>#<index>"
  mig_instance_keys = merge([
    for name, instance in local.active_instances : {
      for i in range(instance.count) : "${name}#${i}" => {
        name  = name
        index = i
      }
    }
  ]...)
}

data "google_compute_instance" "mig" {
  for_each = local.mig_instance_keys

  # The data source doesn't fill in `name` and `zone` when given a self link,
  # so pass them explicitly. Instances land in any zone of the region, so both
  # are taken from the link: .../zones/<zone>/instances/<name>
  name = element(split("/", local.mig_instance_links[each.value.name][each.value.index]), -1)
  zone = element(split("/", local.mig_instance_links[each.value.name][each.value.index]), -3)
}

locals {
  # Instances per model, in a stable order
  model_vms = {
    for name, instance in local.instances : name => [
      for i in range(instance.count) : data.google_compute_instance.mig["${name}#${i}"]
      if contains(keys(local.active_instances), name)
    ]
  }

  # For now only the first instance of a model is used where one is needed
  # (scallama_config output).
  first_vm = { for name, vms in local.model_vms : name => vms[0] if length(vms) > 0 }
}
