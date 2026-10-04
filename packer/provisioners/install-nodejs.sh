#!/bin/bash

# Installs Node.js from the NodeSource apt repository.
# NODE_MAJOR_VERSION can be set via the environment (default: 24).

set -e

readonly NODE_MAJOR="${NODE_MAJOR_VERSION:-24}"

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg

curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
	| sudo gpg --dearmor --yes -o /usr/share/keyrings/nodesource.gpg

echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
	| sudo tee /etc/apt/sources.list.d/nodesource.list

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

node --version
npm --version
