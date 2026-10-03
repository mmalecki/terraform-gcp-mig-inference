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
    "g4-standard-192" = {
      disk_type = "hyperdisk-balanced"
      disks     = 16
      gpus      = 4
      # vram = 384G (4x RTX PRO 6000)
    }
  }

  # Each model sets either `vllm_command` (extra vLLM args as shell, with line
  # continuations, appended to the common `docker run` below) or a full
  # `run_command`.
  models = {
    "google/gemma-4-E2B-it" = {
      size            = "g2-standard-4"
      spot            = false
      count           = 0
      stop_when_ready = local.vllm_stop
      vllm_command    = <<-EOF
        --tool-call-parser gemma4 \
        --chat-template examples/tool_chat_template_gemma4.jinja \
        --reasoning-parser gemma4
      EOF
    }
    "Qwen/Qwen3.5-9B" = {
      size  = "g2-standard-24"
      spot  = false
      count = 1
      # stop_when_ready = local.vllm_stop
      vllm_command = <<-EOF
        --trust-remote-code \
        --max-model-len 262144 \
        --reasoning-parser qwen3 \
        --tool-call-parser qwen3_coder \
        --speculative-config '{"method":"qwen3_next_mtp","num_speculative_tokens":2}'
      EOF
    }
    "Qwen/Qwen3.6-27B" = {
      size            = "g2-standard-48"
      spot            = true
      count           = 0
      stop_when_ready = local.vllm_stop
      vllm_command    = <<-EOF
        --trust-remote-code \
        --tool-call-parser qwen3_coder \
        --reasoning-parser qwen3 \
        --language-model-only \
        --speculative-config '{"method":"qwen3_next_mtp","num_speculative_tokens":2}'
      EOF
    }
    "Qwen/Qwen3.6-35B-A3B" = {
      # ~67G of BF16 weights on one 96G GPU. Only 10/40 layers use full
      # attention, so a full 262K context needs just ~5G of KV cache.
      size            = "g4-standard-48"
      spot            = false
      count           = 1
      stop_when_ready = local.vllm_stop
      vllm_command    = <<-EOF
        --max-model-len 262144 \
        --reasoning-parser qwen3 \
        --tool-call-parser qwen3_coder \
        --language-model-only \
        --speculative-config '{"method":"qwen3_next_mtp","num_speculative_tokens":2}'
      EOF
    }
    "Qwen/Qwen3.6-35B-A3B-FP8" = {
      # ~36G of block FP8 weights on 2x L4 (48G) is tight, so the context is
      # halved to leave room for KV cache. Qwen advise at least 128K for thinking.
      size            = "g2-standard-24"
      spot            = true
      count           = 0
      stop_when_ready = local.vllm_stop
      vllm_command    = <<-EOF
        --max-model-len 131072 \
        --reasoning-parser qwen3 \
        --tool-call-parser qwen3_coder \
        --language-model-only \
        --speculative-config '{"method":"qwen3_next_mtp","num_speculative_tokens":2}'
      EOF
    }
  }

  run_commands = {
    for name, model in local.models : name => try(model.run_command, <<-EOF
      docker run -d --name vllm --gpus all \
        --restart unless-stopped \
        --privileged --ipc=host -p 8000:8000 \
        -e HF_TOKEN \
        -v /mnt/local-ssd/cache:/root/.cache \
        vllm/vllm-openai:latest ${name} \
        --tensor-parallel-size ${google_compute_instance_template.templates[model.size].labels.gpus} \
        --enable-auto-tool-choice \
        ${indent(2, trimspace(model.vllm_command))}
    EOF
    )
  }
}

# VPC network for Scallama inference VMs
resource "google_compute_network" "vpc" {
  name                    = "${var.instance_name}-vpc"
  auto_create_subnetworks = false
}

# Subnetwork in the target region
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.instance_name}-subnet"
  ip_cidr_range = var.region_subnets[var.region]
  region        = var.region
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

# Instance template specifying the machine image, disk size, and Spot VM settings
resource "google_compute_instance_template" "templates" {
  for_each = local.sizes

  name_prefix  = each.key
  machine_type = each.key

  labels = {
    gpus  = tostring(each.value.gpus)
    disks = tostring(each.value.disks)
  }

  // Disk configuration
  disk {
    source_image = var.machine_image
    auto_delete  = true
    boot         = true
    disk_size_gb = 50
    disk_type    = lookup(each.value, "disk_type", "pd-balanced")
  }

  // Dynamic Local SSD (Scratch disks)
  dynamic "disk" {
    for_each = range(each.value.disks)
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
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {
      // Assigns an ephemeral public IP for external access
    }
  }

  // Spot VM scheduling options
  scheduling {
    preemptible                 = lookup(each.value, "spot", false)
    provisioning_model          = lookup(each.value, "spot", false) ? "SPOT" : "STANDARD"
    instance_termination_action = lookup(each.value, "spot", false) ? "STOP" : null
    on_host_maintenance         = "TERMINATE"
    automatic_restart           = false
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Dedicated service account per VM
resource "google_service_account" "vm" {
  for_each = { for k, v in local.models : k => v if v.count > 0 }

  account_id   = replace(lower(split("/", each.key)[1]), ".", "-")
  display_name = "Scallama inference VM for ${each.key}"
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

# Compute Instance created from the template
resource "google_compute_instance_from_template" "vm" {
  for_each = { for k, v in local.models : k => v if v.count > 0 }

  name                     = replace(lower(split("/", each.key)[1]), ".", "-")
  zone                     = var.zone
  source_instance_template = google_compute_instance_template.templates[each.value.size].id

  service_account {
    email  = google_service_account.vm[each.key].email
    scopes = ["cloud-platform"]
  }

  # The token is read on first boot, so access must be granted beforehand
  depends_on = [google_secret_manager_secret_iam_member.hf_token]

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

  provisioner "local-exec" {
    command = <<-EOT
      %{if lookup(each.value, "stop_when_ready", null) != null}
      echo "Waiting for health check at port ${lookup(each.value.stop_when_ready, "health_check_port", 8000)} and path ${lookup(each.value.stop_when_ready, "health_check_path", "/health")} to pass..."
      while ! curl -s -f http://${self.network_interface[0].access_config[0].nat_ip}:${lookup(each.value.stop_when_ready, "health_check_port", 8000)}${lookup(each.value.stop_when_ready, "health_check_path", "/health")} > /dev/null; do
        sleep 10
      done
      echo "Health check passed. Stopping VM while persisting local disks..."
      gcloud compute instances stop ${self.name} --zone=${self.zone} --discard-local-ssd=False
      %{endif}
    EOT
  }
}
