#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

log() {
  printf '[backup] %s\n' "$*"
}

fail() {
  printf '[backup] ERROR: %s\n' "$*" >&2
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

valid_ident() {
  [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

load_env() {
  [[ -f .env ]] || fail ".env not found. Run ./install.sh first."
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a

  : "${POSTGRES_ADMIN_USER:=postgres}"
  : "${POSTGRES_ADMIN_DB:=postgres}"
  : "${GITEA_DB_NAME:=gitea}"
  : "${TEAMCITY_DB_NAME:=teamcity}"

  valid_ident "$POSTGRES_ADMIN_USER" || fail "Invalid POSTGRES_ADMIN_USER value"
  valid_ident "$POSTGRES_ADMIN_DB" || fail "Invalid POSTGRES_ADMIN_DB value"
  valid_ident "$GITEA_DB_NAME" || fail "Invalid GITEA_DB_NAME value"
  valid_ident "$TEAMCITY_DB_NAME" || fail "Invalid TEAMCITY_DB_NAME value"
}

main() {
  require_cmd docker
  require_cmd tar
  local compose
  compose="$(compose_cmd)"

  load_env

  local ts backup_dir pg_dir
  ts="$(date +%Y%m%d-%H%M%S)"
  backup_dir="backups/${ts}"
  pg_dir="${backup_dir}/postgres"

  mkdir -p "$pg_dir"

  log "Ensuring postgres is running..."
  $compose up -d postgres >/dev/null

  log "Dumping PostgreSQL databases..."
  $compose exec -T postgres pg_dump -U "$POSTGRES_ADMIN_USER" -d "$GITEA_DB_NAME" -Fc > "${pg_dir}/gitea.dump"
  $compose exec -T postgres pg_dump -U "$POSTGRES_ADMIN_USER" -d "$TEAMCITY_DB_NAME" -Fc > "${pg_dir}/teamcity.dump"

  log "Archiving service data files..."
  tar -czf "${backup_dir}/files.tar.gz" \
    data/caddy \
    data/gitea \
    data/teamcity \
    homepage \
    caddy \
    postgres/init

  if [[ -f .env ]]; then
    cp .env "${backup_dir}/env.snapshot"
  fi

  cat > "${backup_dir}/metadata.txt" <<META
created_at=${ts}
gitea_db=${GITEA_DB_NAME}
teamcity_db=${TEAMCITY_DB_NAME}
META

  log "Backup completed: ${backup_dir}"
  log "Restore with: ./scripts/restore.sh ${backup_dir} --yes"
}

main "$@"
