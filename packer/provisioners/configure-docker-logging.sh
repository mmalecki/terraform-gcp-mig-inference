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

sudo mkdir -p /etc/docker
sudo python3 - "$DAEMON_JSON" <<'EOF'
import json, os, sys

path = sys.argv[1]
config = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path) as f:
        config = json.load(f)

config["log-driver"] = "json-file"
config["log-opts"] = {"max-size": "100m", "max-file": "2"}

with open(path, "w") as f:
    json.dump(config, f, indent=4)
    f.write("\n")
EOF

sudo cat "$DAEMON_JSON"
sudo dockerd --validate --config-file "$DAEMON_JSON"
