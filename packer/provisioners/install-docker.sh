#!/bin/bash

# Instructions from
# https://docs.docker.com/engine/install/ubuntu/

set -e

# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

# =============================================================================

function print_usage {
  echo
  echo "Usage: install-docker [OPTIONS]"
  echo
  echo "This script can be used to install Docker CE on AWS EC2."
  echo
  echo "Options:"
  echo
  echo -e "  --version\tThe version of Docker to install."
  echo
  echo "Example:"
  echo
  echo "  install-docker --version 18.09.7"
}

function log {
  local readonly level="$1"
  local readonly message="$2"
  local readonly timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  >&2 echo -e "${timestamp} [${level}] [$SCRIPT_NAME] ${message}"
}

function log_info {
  local readonly message="$1"
  log "INFO" "$message"
}

function log_error {
  local readonly message="$1"
  log "ERROR" "$message"
}

# =============================================================================

function install_docker_ce {
  local readonly version="$1"
  local readonly arch=$(dpkg --print-architecture)
  local readonly codename=$(lsb_release -cs)

  local repo_url="https://download.docker.com/linux/ubuntu"
  log_info "Add Docker's official GPG Key"
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

  log_info "Add Docker's apt repository (stable)"
  echo "deb [arch=${arch} signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] ${repo_url} ${codename} stable" | sudo tee /etc/apt/sources.list.d/docker.list

  log_info 'apt-get update'
  sudo apt-get update

  log_info "Installing docker-ce=$version"
  apt list --all-versions docker-ce
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q docker-ce=$version docker-ce-cli=$version containerd.io docker-compose-plugin docker-buildx-plugin
}

function hold_docker_pkgs {
  log_info 'Pin docker-ce to current version'
  sudo apt-mark hold docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

function setup_docker_group {
  log_info 'Add current user to docker group'
  sudo gpasswd -a $USER docker
}

# =============================================================================

function install {
  local version="$DOCKER_VERSION"
  log_info "Start installing docker $version"

  install_docker_ce "$version"
  hold_docker_pkgs
  setup_docker_group
}

install "$@"
