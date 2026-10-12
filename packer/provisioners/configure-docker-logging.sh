#!/bin/bash
#
# Cap docker's json-file container logs. llama-server logs only go there, and
# without max-size they grow without limit on a nearly full root disk.
#
# Merges into /etc/docker/daemon.json rather than overwriting it, since
# nvidia-ctk has already written the nvidia runtime there.
#

set -e

readonly DAEMON_JSON=/etc/docker/daemon.json

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y jq

sudo mkdir -p /etc/docker
sudo test -s "$DAEMON_JSON" || echo '{}' | sudo tee "$DAEMON_JSON" > /dev/null

tmp=$(mktemp)
sudo jq '. + {
  "log-driver": "json-file",
  "log-opts": {"max-size": "100m", "max-file": "2"}
}' "$DAEMON_JSON" > "$tmp"
sudo install -m 0644 "$tmp" "$DAEMON_JSON"
rm "$tmp"

sudo cat "$DAEMON_JSON"
sudo dockerd --validate --config-file "$DAEMON_JSON"
