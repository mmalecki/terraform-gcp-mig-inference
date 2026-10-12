#!/bin/bash
#
# Install Google Cloud Ops Agent, pinned, with GPU (NVML) host metrics and
# Prometheus scrapes of llama-server's and dcgm-exporter's /metrics. See
# ops-agent-poc.md.
#
# Must run as root. The config is instance-agnostic (localhost only); the agent
# reads instance metadata itself when it starts, so nothing needs to run at boot.
#

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

: "${OPS_AGENT_VERSION:?OPS_AGENT_VERSION must be set, e.g. 2.72.0~ubuntu26.04}"
CODENAME=$(. /etc/os-release; echo $VERSION_CODENAME)

# We don't use Google's add-google-cloud-ops-agent-repo.sh: with --version it
# switches to the google-cloud-ops-agent-$CODENAME-2 repo, which 404s on resolute.
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  -o /etc/apt/keyrings/google-cloud-ops-agent.asc
chmod 0644 /etc/apt/keyrings/google-cloud-ops-agent.asc
echo "deb [signed-by=/etc/apt/keyrings/google-cloud-ops-agent.asc] https://packages.cloud.google.com/apt google-cloud-ops-agent-${CODENAME}-all main" \
  > /etc/apt/sources.list.d/google-cloud-ops-agent.list

# Refresh only this repo
apt-get -o DPkg::Lock::Timeout=300 update \
  -o Dir::Etc::sourcelist=sources.list.d/google-cloud-ops-agent.list \
  -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0
apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends \
  "google-cloud-ops-agent=${OPS_AGENT_VERSION}"
# To upgrade: unhold, install with -o Dpkg::Options::=--force-confold (config.yaml
# below is a modified conffile), then hold again.
apt-mark hold google-cloud-ops-agent
dpkg-query -W -f='${Package} ${Version}\n' google-cloud-ops-agent

# Written after the install: config.yaml is a dpkg conffile.
cat > /etc/google-cloud-ops-agent/config.yaml <<'EOF'
# /etc/google-cloud-ops-agent/config.yaml
# Merged on top of the Ops Agent built-in defaults:
#   logging: syslog receiver (/var/log/syslog, /var/log/messages) -> Cloud Logging
#   metrics: hostmetrics (incl. NVML GPU metrics, agent.googleapis.com/gpu/*)
# llama-server logs are deliberately NOT collected (billing). They live only in
# docker's json-file log (/var/lib/docker/containers/*/*-json.log), which the
# default syslog receiver does not read.
# Instance-agnostic (localhost only), so it can be baked into the image.
metrics:
  receivers:
    llama_server:
      # Needs llama-server started with --metrics (it is, in the startup script).
      type: prometheus
      config:
        scrape_configs:
          - job_name: llama-server
            scrape_interval: 30s
            metrics_path: /metrics
            static_configs:
              - targets: ["localhost:9931"]
    dcgm_exporter:
      # GPU profiling metrics from nvidia-dcgm-exporter (install-dcgm.sh)
      type: prometheus
      config:
        scrape_configs:
          - job_name: dcgm-exporter
            scrape_interval: 30s
            metrics_path: /metrics
            static_configs:
              - targets: ["localhost:9400"]
  service:
    pipelines:
      llama_server:
        receivers: [llama_server]
      dcgm_exporter:
        receivers: [dcgm_exporter]
EOF
chmod 0644 /etc/google-cloud-ops-agent/config.yaml

# Validate; a bad config fails the build
for svc in fluentbit otel; do
  d=$(mktemp -d)
  /opt/google-cloud-ops-agent/libexec/google_cloud_ops_agent_engine \
    -service=$svc -in /etc/google-cloud-ops-agent/config.yaml \
    -out "$d" -logs "$d/logs" -state "$d/state" >/dev/null
  rm -rf "$d"
done

# Leave it enabled, but ship no build-VM state in the image. The stop can take up
# to 90s (fluent-bit's stop timeout) when exports are failing, as they do here.
systemctl enable google-cloud-ops-agent
systemctl stop google-cloud-ops-agent
rm -rf /var/lib/google-cloud-ops-agent/* /var/log/google-cloud-ops-agent/*
apt-get clean
