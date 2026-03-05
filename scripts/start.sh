#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

log() {
  printf '[start] %s\n' "$*"
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  else
    echo "docker-compose"
  fi
}

print_nexus_initial_password() {
  local compose password
  compose="$(compose_cmd)"

  password="$($compose exec -T nexus sh -c 'cat /nexus-data/admin.password 2>/dev/null || true' | tr -d '\r')"
  if [[ -n "${password}" ]]; then
    log "Nexus initial admin password: ${password}"
    return
  fi

  log "Nexus initial admin password not available yet (Nexus may still be initializing)."
  log "Retrieve it with: $compose exec nexus cat /nexus-data/admin.password"
}

compose="$(compose_cmd)"
$compose up -d
print_nexus_initial_password
