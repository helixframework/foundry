#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

log() {
  printf '[install] %s\n' "$*"
}

fail() {
  printf '[install] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
    return
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
    return
  fi

  fail "Docker Compose is required (docker compose plugin or docker-compose)."
}

generate_env() {
  if [[ -f .env ]]; then
    log ".env already exists; keeping existing configuration."
    return
  fi

  [[ -f .env.example ]] || fail ".env.example not found"

  local uid gid
  uid="$(id -u)"
  gid="$(id -g)"

  cp .env.example .env
  sed -i.bak "s/^PUID=.*/PUID=${uid}/" .env
  sed -i.bak "s/^PGID=.*/PGID=${gid}/" .env
  rm -f .env.bak

  log "Generated .env from .env.example using current UID/GID (${uid}:${gid})."
}

create_dirs() {
  local dirs=(
    data/gitea
    data/teamcity/server/data
    data/teamcity/server/logs
    data/teamcity/agent/conf
    data/teamcity/agent/work
    data/teamcity/agent/temp
    data/teamcity/agent/system
  )

  for d in "${dirs[@]}"; do
    mkdir -p "$d"
  done

  log "Ensured persistent data directories exist under ./data/."
}

show_next_steps() {
  cat <<'MSG'

Stack started.

Open these URLs:
- Homepage: http://localhost:8080
- Gitea:    http://localhost:3000
- TeamCity: http://localhost:8111

First-run notes:
- Gitea is pre-locked to sqlite and configured for containerized data persistence.
- TeamCity will take a minute or two on first boot and then ask for setup in the web UI.
- In TeamCity, connect VCS root to your Gitea repo URL.

Helpful commands:
- ./scripts/status.sh
- ./scripts/logs.sh
- ./scripts/stop.sh
- ./scripts/start.sh
MSG
}

main() {
  require_cmd docker

  if ! docker info >/dev/null 2>&1; then
    fail "Docker daemon is not running or current user cannot access it."
  fi

  local compose
  compose="$(compose_cmd)"

  create_dirs
  generate_env

  log "Pulling container images..."
  $compose pull

  log "Starting stack with Docker Compose..."
  $compose up -d

  show_next_steps
}

main "$@"
