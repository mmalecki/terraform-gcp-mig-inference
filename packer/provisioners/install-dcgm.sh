#!/bin/bash
#
# Install NVIDIA DCGM and dcgm-exporter, for GPU profiling metrics (SM activity
# and occupancy, tensor pipe, DRAM bandwidth, PCIe) on top of Ops Agent's NVML
# ones. Ops Agent scrapes the exporter's Prometheus endpoint on localhost:9400.
#
# Ops Agent's own dcgm receiver is not used: it only supports DCGM 3.x, and
# only DCGM 4 is published for this OS.
#
# Must run as root, after cuda.sh has added NVIDIA's CUDA apt repo.
#

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

: "${DCGM_VERSION:?DCGM_VERSION must be set, e.g. 1:4.7.0-2}"
: "${DCGM_EXPORTER_VERSION:?DCGM_EXPORTER_VERSION must be set, e.g. 4.8.4.3955-1}"

# Core pulls in its dozen subpackages at exact versions, which apt can't resolve
# once the repo has a newer DCGM, so pin them all here.
cat > /etc/apt/preferences.d/nvidia-dcgm <<EOF
Package: datacenter-gpu-manager-4-* libdcgm dcgmi nv-hostengine
Pin: version ${DCGM_VERSION}
Pin-Priority: 1001

Package: datacenter-gpu-manager-exporter
Pin: version ${DCGM_EXPORTER_VERSION}
Pin-Priority: 1001
EOF

apt-get -o DPkg::Lock::Timeout=300 update
# Not datacenter-gpu-manager-4-cuda13: it's only diagnostics, and pulls in
# ~3.5 GB of CUDA libraries. The profiling module is in -proprietary.
apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends \
  datacenter-gpu-manager-4-core \
  datacenter-gpu-manager-4-proprietary \
  datacenter-gpu-manager-exporter
dpkg-query -W -f='${Package} ${Version}\n' \
  datacenter-gpu-manager-4-core datacenter-gpu-manager-4-proprietary datacenter-gpu-manager-exporter

# The packaged default counters, plus SM activity and occupancy
sed -E 's/^# (DCGM_FI_PROF_SM_(ACTIVE|OCCUPANCY),)/\1/' \
  /etc/dcgm-exporter/default-counters.csv > /etc/dcgm-exporter/counters.csv
grep -q '^DCGM_FI_PROF_SM_ACTIVE,' /etc/dcgm-exporter/counters.csv
grep -q '^DCGM_FI_PROF_SM_OCCUPANCY,' /etc/dcgm-exporter/counters.csv

# Use the nvidia-dcgm host engine instead of an embedded one: only one of them
# can hold the profiling counters. Listen on localhost only, for Ops Agent.
install -d -m 0755 /etc/systemd/system/nvidia-dcgm-exporter.service.d
cat > /etc/systemd/system/nvidia-dcgm-exporter.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/dcgm-exporter \
  --collectors /etc/dcgm-exporter/counters.csv \
  --remote-hostengine-info localhost:5555 \
  --address 127.0.0.1:9400
EOF

# Started at boot; there's no GPU on the build VM to start them against now.
systemctl daemon-reload
systemctl enable nvidia-dcgm nvidia-dcgm-exporter
