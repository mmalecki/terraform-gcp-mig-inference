locals {
  vllm_stop = {
    health_check_path = "/health"
    health_check_port = 8000
  }
  sizes = {
    "g2-standard-8" = {
      disks = 1
      gpus  = 1
      vram  = 24 # 1x L4
    }
    "g2-standard-24" = {
      disks = 2
      gpus  = 2
      vram  = 48 # 2x L4
    }
    "g4-standard-48" = {
      disk_type = "hyperdisk-balanced"
      disks     = 4
      gpus      = 1
      vram      = 96 # 1x RTX PRO 6000
    }
  }

  # Each model lists its variants: a `runtime` (a key of `var.machine_image`),
  # a `vram_min` and a `command` (runtime args as shell, with line
  # continuations, starting with the model to load; the runtime's common
  # `docker run` is wrapped around it). A full `run_command` can be given
  # instead of `command`.
  #
  # `vram_min` is a rough estimate in GB, across all GPUs, of the VRAM a
  # variant needs: weights, KV cache for its context and runtime overhead. The
  # models hosted on an instance must fit in its size's `vram`. Qwen3.5 and
  # Qwen3.6 keep a KV cache in only 1 in 4 layers: about 32K per token for the
  # 9Bs and 20K for the 35B-A3B. vLLM claims 90% of VRAM by default, and needs
  # the cache to fit one full-length sequence.
  models = {
    "Qwen/Qwen3.5-9B" = {
      variants = {
        vllm = {
          runtime  = "vllm"
          vram_min = 36 # 19.3G BF16 weights + 8.6G KV (262K) + overhead, / 0.9
          command  = <<-EOF
            Qwen/Qwen3.5-9B \
            --trust-remote-code \
            --max-model-len 262144 \
            --reasoning-parser qwen3 \
            --tool-call-parser qwen3_coder \
              #--speculative-config '{"method":"qwen3_next_mtp","num_speculative_tokens":2}'
          EOF
        }
        llamacpp-q5_k_m = {
          runtime  = "llamacpp"
          vram_min = 18 # 7.1G weights + 8.6G KV (262K) + overhead
          command  = <<-EOF
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
          runtime  = "llamacpp"
          vram_min = 22 # 7.1G weights + 12.9G KV (393K) + overhead
          command  = <<-EOF
            -hf bartowski/Qwen_Qwen3.5-9B-GGUF:Q5_K_M \
            -c 393216 \
            -np 5 --kv-unified \
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
    # Built on Qwen3.5, served with the model card's recommended sampling for
    # precise coding tasks. The model ships no generation_config.json, so vLLM
    # is given the sampling defaults explicitly.
    "ornith-ai/Ornith-1.5-9B" = {
      variants = {
        vllm = {
          runtime  = "vllm"
          vram_min = 36 # 19.3G BF16 weights + 8.6G KV (262K) + overhead, / 0.9
          command  = <<-EOF
            ornith-ai/Ornith-1.5-9B \
            --trust-remote-code \
            --max-model-len 262144 \
            --reasoning-parser qwen3 \
            --tool-call-parser qwen3_xml
          EOF
        }
        llamacpp-q5_k_m = {
          runtime  = "llamacpp"
          vram_min = 18 # 6.9G weights + 8.6G KV (262K) + overhead
          command  = <<-EOF
            -hf bartowski/Ornith-1.5-9B-GGUF:Q5_K_M \
            -c 262144 \
            -np 4 --kv-unified \
            --no-mmproj \
            --temp 0.6 \
            --top-k 20 \
            --top-p 0.95 \
            --min-p 0 \
            --presence-penalty 0.0 --repeat-penalty 1.0
          EOF
        }
        llamacpp-q5_k_m-multi = {
          runtime  = "llamacpp"
          vram_min = 22 # 6.9G weights + 12.9G KV (393K) + overhead
          command  = <<-EOF
            -hf bartowski/Ornith-1.5-9B-GGUF:Q5_K_M \
            -c 393216 \
            -np 5 --kv-unified \
            --no-mmproj \
            --temp 0.6 \
            --top-k 20 \
            --top-p 0.95 \
            --min-p 0 \
            --presence-penalty 0.0 --repeat-penalty 1.0
          EOF
        }
      }
    }
    "Qwen/Qwen3.6-35B-A3B" = {
      variants = {
        # Plenty of room on 1x RTX PRO 6000 (96G).
        vllm-fp8 = {
          runtime  = "vllm"
          vram_min = 54 # 37.5G FP8 weights + 5.4G KV (262K) + overhead, / 0.9
          command  = <<-EOF
            Qwen/Qwen3.6-35B-A3B-FP8 \
            --max-model-len 262144 \
            --reasoning-parser qwen3 \
            --tool-call-parser qwen3_coder \
            --language-model-only \
              #--speculative-config '{"method":"qwen3_next_mtp","num_speculative_tokens":2}'
          EOF
        }
        # ~25G of Q5_K_M weights plus ~5G of KV cache for the full 262K context
        # fits comfortably on 2x L4 (48G).
        llamacpp-q5_k_m = {
          runtime  = "llamacpp"
          vram_min = 34 # 25.9G weights + 5.4G KV (262K) + overhead
          command  = <<-EOF
            -hf bartowski/Qwen_Qwen3.6-35B-A3B-GGUF:Q5_K_M \
            -c 262144 \
            --no-mmproj \
            -np 5 --kv-unified \
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

  # Base port per runtime. Each model on an instance gets the next port of its
  # runtime, in list order: vLLM 8000, 8001, ..., llama.cpp 9931, 9932, ...
  runtime_ports = {
    vllm     = 8000
    llamacpp = 9931
  }

  # Deployed instances, keyed by VM name. Each one hosts `models`, a list of
  # `model` (a key of `local.models`) and `variant` (a key of its variants),
  # served under the model's name (which scallama routes by). A model can only
  # be hosted by one instance.
  #
  # Each instance sets its machine `size`, a key of `local.sizes`. Its models'
  # runtimes must all use the same machine image.
  #
  # Each instance sets the `region` it runs in, which must be a key of
  # `var.region_subnets`. Its group spreads instances across the zones of the
  # region that offer the instance's machine type. Set `zones` (a list of zone
  # names) to use exactly those zones instead.
  instances = {
    "qwen3-5-9b" = {
      region = "us-central1"
      size   = "g4-standard-48"
      count  = 0
      spot   = true
      models = [
        { model = "Qwen/Qwen3.5-9B", variant = "llamacpp-q5_k_m-multi" },
      ]
      # stop_when_ready = local.vllm_stop
    }
    "ornith-1-5-9b" = {
      region = "us-central1"
      size   = "g4-standard-48"
      count  = 0
      spot   = true
      models = [
        { model = "ornith-ai/Ornith-1.5-9B", variant = "llamacpp-q5_k_m-multi" },
      ]
      # stop_when_ready = local.vllm_stop
    }
    "qwen3-6-35b-a3b" = {
      region = "us-central1"
      size   = "g2-standard-24"
      count  = 0
      spot   = false
      models = [
        { model = "Qwen/Qwen3.6-35B-A3B", variant = "llamacpp-q5_k_m" },
      ]
      # stop_when_ready = local.vllm_stop
    }
  }

  resolved_instances = {
    for name, instance in local.instances : name => merge(instance, {
      models = [
        for i, m in instance.models : merge(m, {
          variant = local.models[m.model].variants[m.variant]
          port = local.runtime_ports[local.models[m.model].variants[m.variant].runtime] + length([
            for prev in slice(instance.models, 0, i) : prev
            if local.models[prev.model].variants[prev.variant].runtime == local.models[m.model].variants[m.variant].runtime
          ])
        })
      ]
      image = var.machine_image[local.models[instance.models[0].model].variants[instance.models[0].variant].runtime]
    })
  }
  active_instances = { for name, instance in local.resolved_instances : name => instance if instance.count > 0 }

  # Every hosted model, with the instance hosting it, keyed by model name.
  # A model listed on more than one instance fails here as a duplicate key.
  hosted_models = {
    for m in flatten([
      for name, instance in local.resolved_instances : [
        for m in instance.models : merge(m, { instance = name })
      ]
    ]) : m.model => m
  }

  # llama.cpp splits layers across all GPUs by default, and enables Jinja chat
  # templates (tool calling) and reasoning extraction out of the box.
  #
  # A variant's `run_command` replaces the whole `docker run`, and must serve
  # on the port assigned to it.
  run_commands = {
    for name, instance in local.resolved_instances : name => join("\n", [
      for m in instance.models : try(m.variant.run_command, {
        vllm     = <<-EOF
          docker run -d --name vllm-${m.port} --gpus all \
            --restart unless-stopped \
            --privileged --ipc=host -p ${m.port}:${m.port} \
            -e HF_TOKEN \
            -v /mnt/local-ssd/cache:/root/.cache \
            vllm/vllm-openai:latest \
            ${indent(2, trimspace(m.variant.command))} \
            --served-model-name ${m.model} \
            --port ${m.port} \
            --tensor-parallel-size ${local.sizes[instance.size].gpus} \
            --enable-auto-tool-choice
        EOF
        llamacpp = <<-EOF
          docker run -d --name llama-${m.port} --gpus all \
            --restart unless-stopped \
            --health-cmd 'curl -f http://localhost:${m.port}/health' \
            -p ${m.port}:${m.port} \
            -e HF_TOKEN \
            -v /mnt/local-ssd/cache:/root/.cache \
            ghcr.io/ggml-org/llama.cpp:server-cuda-b11429 \
            --alias ${m.model} \
            -ngl all \
            --metrics \
            --port ${m.port} \
            ${indent(2, trimspace(m.variant.command))}
        EOF
      }[m.variant.runtime])
    ])
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

# Instance template per active instance. The template carries everything that
# varies per instance (size, spot, service account and startup script), and is
# rolled out by the instance's managed instance group.
resource "google_compute_instance_template" "templates" {
  for_each = local.active_instances

  name_prefix  = "${each.key}-"
  machine_type = each.value.size

  labels = {
    gpus   = tostring(local.sizes[each.value.size].gpus)
    disks  = tostring(local.sizes[each.value.size].disks)
    region = each.value.region
  }

  // Disk configuration
  disk {
    source_image = each.value.image
    auto_delete  = true
    boot         = true
    disk_size_gb = 50
    disk_type    = lookup(local.sizes[each.value.size], "disk_type", "pd-balanced")
  }

  // Dynamic Local SSD (Scratch disks)
  dynamic "disk" {
    for_each = range(local.sizes[each.value.size].disks)
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

  # The token is read on first boot, and logs and metrics are written from the
  # first boot onwards, so access must be granted beforehand
  depends_on = [
    google_secret_manager_secret_iam_member.hf_token,
    google_project_iam_member.vm_observability,
  ]

  lifecycle {
    create_before_destroy = true
    precondition {
      condition     = contains(keys(var.region_subnets), each.value.region)
      error_message = "Region \"${each.value.region}\" for \"${each.key}\" has no entry in var.region_subnets."
    }
    precondition {
      condition     = sum([for m in each.value.models : m.variant.vram_min]) <= local.sizes[each.value.size].vram
      error_message = "Models on \"${each.key}\" need ~${sum([for m in each.value.models : m.variant.vram_min])}G of VRAM, but \"${each.value.size}\" has ${local.sizes[each.value.size].vram}G."
    }
    precondition {
      condition     = length(distinct([for m in each.value.models : var.machine_image[m.variant.runtime]])) == 1
      error_message = "Models on \"${each.key}\" have runtimes with different machine images."
    }
  }
}

# Dedicated service account per VM
resource "google_service_account" "vm" {
  for_each = local.active_instances

  account_id   = each.key
  display_name = "Scallama inference VM ${each.key}"

  lifecycle {
    precondition {
      condition     = length(each.key) >= 6 && length(each.key) <= 30
      error_message = "VM name \"${each.key}\" must be 6-30 characters to name its service account."
    }
  }
}

# APIs required by this deployment
resource "google_project_service" "services" {
  for_each = toset([
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
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

locals {
  # Roles a VM needs to write its logs and metrics
  vm_observability_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]
}

# Grant each VM's service account the writer roles for Cloud Logging and Cloud
# Monitoring. They are bound on the project because that is where their
# permissions take effect: bound on the service account itself they grant nothing.
resource "google_project_iam_member" "vm_observability" {
  for_each = {
    for pair in setproduct(keys(google_service_account.vm), local.vm_observability_roles) :
    "${pair[0]}|${pair[1]}" => {
      vm   = pair[0]
      role = pair[1]
    }
  }

  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.vm[each.value.vm].email}"

  depends_on = [google_project_service.services]
}

# All zones of each region with an active instance
data "google_compute_zones" "available" {
  for_each = toset([for instance in local.active_instances : instance.region])

  region = each.key
}

locals {
  # Candidate zones per instance: the `zones` override if given, else the region's
  zone_candidates = {
    for name, instance in local.active_instances :
    name => try(instance.zones, data.google_compute_zones.available[instance.region].names)
  }

  # Zone and machine type pairs to check, for instances without a `zones` override
  machine_type_checks = merge([
    for name, instance in local.active_instances : {
      for zone in local.zone_candidates[name] : "${zone}|${instance.size}" => {
        zone = zone
        size = instance.size
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
  # Zones each instance's group is spread over
  mig_zones = {
    for name, instance in local.active_instances : name => (
      try(instance.zones, null) != null ? instance.zones : [
        for zone in local.zone_candidates[name] : zone
        if length(data.google_compute_machine_types.available["${zone}|${instance.size}"].machine_types) > 0
      ]
    )
  }
}

# One regional managed instance group per active instance, spread across the
# zones of its region that offer its machine type. No load balancing: VMs are
# addressed individually.
resource "google_compute_region_instance_group_manager" "mig" {
  for_each = local.active_instances

  timeouts {
    create = "5m"
  }

  name                      = each.key
  base_instance_name        = each.key
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
      error_message = "No zone in \"${each.value.region}\" offers machine type \"${each.value.size}\" for \"${each.key}\". Set `zones` for it, or pick another size or region."
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

  # One entry per desired VM, keyed "<instance>#<index>"
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
  # VMs per instance, in a stable order
  instance_vms = {
    for name, instance in local.resolved_instances : name => [
      for i in range(instance.count) : data.google_compute_instance.mig["${name}#${i}"]
      if contains(keys(local.active_instances), name)
    ]
  }

  # For now only the first VM of an instance is used where one is needed
  # (scallama_config output).
  first_vm = { for name, vms in local.instance_vms : name => vms[0] if length(vms) > 0 }
}
