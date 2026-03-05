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
    data/postgres
    data/teamcity/server/data
    data/teamcity/server/data/config
    data/teamcity/server/logs
    data/teamcity/agent/conf
    data/teamcity/agent/work
    data/teamcity/agent/temp
    data/teamcity/agent/system
    postgres/init
  )

  for d in "${dirs[@]}"; do
    mkdir -p "$d"
  done

  log "Ensured persistent data directories exist under ./data/."
}

load_env() {
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
}

apply_env_defaults() {
  : "${GITEA_DB_NAME:=gitea}"
  : "${GITEA_DB_USER:=gitea}"
  : "${GITEA_DB_PASSWORD:=gitea_password}"
  : "${TEAMCITY_DB_NAME:=teamcity}"
  : "${TEAMCITY_DB_USER:=teamcity}"
  : "${TEAMCITY_DB_PASSWORD:=teamcity_password}"
}

render_postgres_init_sql() {
  local gitea_pw teamcity_pw
  gitea_pw="${GITEA_DB_PASSWORD//\'/\'\'}"
  teamcity_pw="${TEAMCITY_DB_PASSWORD//\'/\'\'}"

  cat > postgres/init/01-init-app-dbs.sql <<EOF
CREATE ROLE ${GITEA_DB_USER} LOGIN PASSWORD '${gitea_pw}';
CREATE DATABASE ${GITEA_DB_NAME} OWNER ${GITEA_DB_USER};

CREATE ROLE ${TEAMCITY_DB_USER} LOGIN PASSWORD '${teamcity_pw}';
CREATE DATABASE ${TEAMCITY_DB_NAME} OWNER ${TEAMCITY_DB_USER};
EOF

  log "Generated postgres/init/01-init-app-dbs.sql from .env."
}

render_teamcity_database_properties() {
  cat > data/teamcity/server/data/config/database.properties <<EOF
connectionUrl=jdbc:postgresql://postgres:5432/${TEAMCITY_DB_NAME}
connectionProperties.user=${TEAMCITY_DB_USER}
connectionProperties.password=${TEAMCITY_DB_PASSWORD}
maxConnections=50
testOnBorrow=true
EOF

  log "Generated TeamCity database config at data/teamcity/server/data/config/database.properties."
}

show_next_steps() {
  cat <<'MSG'

Stack started.

Open these URLs:
- Homepage: http://localhost:8080
- Gitea:    http://localhost:3000
- TeamCity: http://localhost:8111

First-run notes:
- Gitea is configured to use PostgreSQL.
- TeamCity is configured to use PostgreSQL via database.properties.
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
  load_env
  apply_env_defaults
  render_postgres_init_sql
  render_teamcity_database_properties

  log "Pulling container images..."
  $compose pull

  log "Starting stack with Docker Compose..."
  $compose up -d

  show_next_steps
}

main "$@"
