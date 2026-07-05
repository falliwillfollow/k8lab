#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

required=(docker kubectl kind helm make jq curl)
missing=()

for tool in "${required[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing+=("$tool")
  fi
done

if ((${#missing[@]})); then
  echo "Missing required tools: ${missing[*]}"
  echo "Install them, then rerun make check."
  echo "Ubuntu hints: Docker from docs.docker.com; kubectl/kind/helm from their official install docs; jq/curl/make via apt."
  exit 1
fi

if ! docker_info_output="$(docker info 2>&1 >/dev/null)"; then
  echo "Docker is installed, but this shell cannot talk to the Docker daemon."
  echo "$docker_info_output"
  echo
  docker_members="$(getent group docker | cut -d: -f4 || true)"
  if [[ ",$docker_members," == *",$USER,"* ]]; then
    echo "Your user is already in the docker group, but this terminal has not picked it up yet."
    echo "Run: newgrp docker"
    echo "Then rerun: make check"
  else
    echo "Add your user to the docker group:"
    echo "  sudo usermod -aG docker \"$USER\""
    echo "Then open a new terminal or run: newgrp docker"
  fi
  exit 1
fi

echo "All required tools are available and Docker is responding."
