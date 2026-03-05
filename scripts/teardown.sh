#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

log() {
  printf '[teardown] %s\n' "$*"
}

fail() {
  printf '[teardown] ERROR: %s\n' "$*" >&2
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

main() {
  local confirm="${1:-}"

  [[ "$confirm" == "--yes" ]] || fail "This is destructive. Usage: ./scripts/teardown.sh --yes"

  require_cmd docker
  local compose
  compose="$(compose_cmd)"

  log "Stopping and removing stack containers..."
  $compose down --remove-orphans

  log "Deleting persisted runtime data..."
  rm -rf data backups postgres/init

  log "Recreating base directories..."
  mkdir -p data postgres/init

  log "Teardown complete. Run ./install.sh to rebuild from scratch."
}

main "$@"
