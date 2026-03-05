#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

log() {
  printf '[restore] %s\n' "$*"
}

fail() {
  printf '[restore] ERROR: %s\n' "$*" >&2
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
  : "${GITEA_DB_USER:=gitea}"
  : "${GITEA_DB_PASSWORD:=gitea_password}"
  : "${TEAMCITY_DB_NAME:=teamcity}"
  : "${TEAMCITY_DB_USER:=teamcity}"
  : "${TEAMCITY_DB_PASSWORD:=teamcity_password}"

  valid_ident "$POSTGRES_ADMIN_USER" || fail "Invalid POSTGRES_ADMIN_USER value"
  valid_ident "$POSTGRES_ADMIN_DB" || fail "Invalid POSTGRES_ADMIN_DB value"
  valid_ident "$GITEA_DB_NAME" || fail "Invalid GITEA_DB_NAME value"
  valid_ident "$GITEA_DB_USER" || fail "Invalid GITEA_DB_USER value"
  valid_ident "$TEAMCITY_DB_NAME" || fail "Invalid TEAMCITY_DB_NAME value"
  valid_ident "$TEAMCITY_DB_USER" || fail "Invalid TEAMCITY_DB_USER value"
}

wait_for_postgres() {
  local compose="$1"
  local i
  for i in $(seq 1 60); do
    if $compose exec -T postgres pg_isready -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_ADMIN_DB" >/dev/null 2>&1; then
      return
    fi
    sleep 2
  done

  fail "Postgres did not become ready in time"
}

ensure_role() {
  local compose="$1"
  local role="$2"
  local password="$3"
  local password_escaped

  password_escaped="${password//\'/\'\'}"

  $compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_ADMIN_DB" -c \
    "DO \\$\\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${role}') THEN CREATE ROLE ${role} LOGIN PASSWORD '${password_escaped}'; ELSE ALTER ROLE ${role} WITH LOGIN PASSWORD '${password_escaped}'; END IF; END \\$\\$;"
}

recreate_db() {
  local compose="$1"
  local db_name="$2"
  local owner="$3"

  $compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_ADMIN_DB" -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${db_name}' AND pid <> pg_backend_pid();"
  $compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_ADMIN_DB" -c "DROP DATABASE IF EXISTS ${db_name};"
  $compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_ADMIN_DB" -c "CREATE DATABASE ${db_name} OWNER ${owner};"
}

main() {
  local backup_dir="${1:-}"
  local confirm="${2:-}"

  [[ -n "$backup_dir" ]] || fail "Usage: ./scripts/restore.sh <backup-dir> --yes"
  [[ "$confirm" == "--yes" ]] || fail "Restore is destructive. Re-run with --yes"

  [[ -d "$backup_dir" ]] || fail "Backup directory not found: $backup_dir"
  [[ -f "$backup_dir/files.tar.gz" ]] || fail "Missing files archive in backup"
  [[ -f "$backup_dir/postgres/gitea.dump" ]] || fail "Missing gitea DB dump"
  [[ -f "$backup_dir/postgres/teamcity.dump" ]] || fail "Missing teamcity DB dump"

  require_cmd docker
  require_cmd tar
  local compose
  compose="$(compose_cmd)"

  load_env

  log "Stopping stack..."
  $compose down

  log "Restoring file data..."
  rm -rf data/caddy data/gitea data/nexus data/teamcity
  mkdir -p data
  tar -xzf "$backup_dir/files.tar.gz"

  log "Starting postgres..."
  $compose up -d postgres >/dev/null
  wait_for_postgres "$compose"

  log "Ensuring database roles..."
  ensure_role "$compose" "$GITEA_DB_USER" "$GITEA_DB_PASSWORD"
  ensure_role "$compose" "$TEAMCITY_DB_USER" "$TEAMCITY_DB_PASSWORD"

  log "Recreating application databases..."
  recreate_db "$compose" "$GITEA_DB_NAME" "$GITEA_DB_USER"
  recreate_db "$compose" "$TEAMCITY_DB_NAME" "$TEAMCITY_DB_USER"

  log "Restoring database dumps..."
  $compose exec -T postgres pg_restore -U "$POSTGRES_ADMIN_USER" -d "$GITEA_DB_NAME" --no-owner --no-privileges < "$backup_dir/postgres/gitea.dump"
  $compose exec -T postgres pg_restore -U "$POSTGRES_ADMIN_USER" -d "$TEAMCITY_DB_NAME" --no-owner --no-privileges < "$backup_dir/postgres/teamcity.dump"

  log "Starting full stack..."
  $compose up -d

  log "Restore completed from: $backup_dir"
}

main "$@"
