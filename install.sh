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
    data/caddy/data
    data/caddy/config
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
  : "${HOMEPAGE_DOMAIN:=localhost}"
  : "${GITEA_DOMAIN:=gitea.localhost}"
  : "${TEAMCITY_DOMAIN:=teamcity.localhost}"
  : "${CADDY_TLS_MODE:=internal}"
  : "${GITEA_ROOT_URL:=https://${GITEA_DOMAIN}/}"
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

render_homepage_html() {
  local homepage_url gitea_url teamcity_url
  homepage_url="https://${HOMEPAGE_DOMAIN}"
  gitea_url="${GITEA_ROOT_URL%/}"
  teamcity_url="https://${TEAMCITY_DOMAIN}"

  cat > homepage/index.html <<EOF
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Self-Hosted CI/CD</title>
    <style>
      :root {
        --bg: #0b1b2b;
        --bg-accent: #12324a;
        --card: #ffffff;
        --text: #0f1720;
        --muted: #415565;
        --gitea: #4ea23f;
        --teamcity: #0b7ed0;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        font-family: "Avenir Next", "Segoe UI", sans-serif;
        background:
          radial-gradient(55rem 55rem at 15% 10%, #1f5575 0%, transparent 60%),
          radial-gradient(50rem 50rem at 95% 90%, #204061 0%, transparent 60%),
          linear-gradient(160deg, var(--bg) 0%, var(--bg-accent) 100%);
        color: #eef4f9;
        display: grid;
        place-items: center;
        padding: 1.5rem;
      }
      main { width: min(920px, 100%); }
      h1 { margin: 0 0 0.5rem; font-size: clamp(1.8rem, 3vw, 2.7rem); }
      p.lead { margin: 0 0 1.5rem; color: #d2e1ec; }
      .grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
        gap: 1rem;
      }
      .card {
        background: var(--card);
        border-radius: 14px;
        padding: 1.1rem 1.2rem;
        color: var(--text);
        box-shadow: 0 12px 30px rgba(8, 20, 31, 0.28);
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
      }
      .card h2 { margin: 0; }
      .meta { color: var(--muted); font-size: 0.95rem; margin: 0; }
      a.btn {
        text-decoration: none;
        color: #fff;
        font-weight: 600;
        border-radius: 10px;
        padding: 0.62rem 0.85rem;
        width: fit-content;
      }
      a.gitea { background: var(--gitea); }
      a.teamcity { background: var(--teamcity); }
      footer { margin-top: 1.1rem; color: #c9d9e5; font-size: 0.95rem; }
    </style>
  </head>
  <body>
    <main>
      <h1>Self-Hosted CI/CD</h1>
      <p class="lead">Quick access to your local Gitea and TeamCity services.</p>
      <div class="grid">
        <section class="card">
          <h2>Gitea</h2>
          <p class="meta">Git hosting and repository management</p>
          <a class="btn gitea" href="${gitea_url}">Open Gitea</a>
          <p class="meta">${gitea_url}</p>
        </section>
        <section class="card">
          <h2>TeamCity</h2>
          <p class="meta">Build server and pipeline orchestration</p>
          <a class="btn teamcity" href="${teamcity_url}">Open TeamCity</a>
          <p class="meta">${teamcity_url}</p>
        </section>
      </div>
      <footer>
        Homepage: ${homepage_url}
      </footer>
    </main>
  </body>
</html>
EOF

  log "Rendered homepage/index.html with configured service URLs."
}

show_next_steps() {
  cat <<MSG

Stack started.

Open these URLs:
- Homepage: https://${HOMEPAGE_DOMAIN}
- Gitea:    ${GITEA_ROOT_URL}
- TeamCity: https://${TEAMCITY_DOMAIN}

First-run notes:
- Gitea is configured to use PostgreSQL.
- TeamCity is configured to use PostgreSQL via database.properties.
- TLS is provided by Caddy. With 'internal' mode, your browser may show a certificate warning until you trust Caddy's local CA.
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
  render_homepage_html

  log "Pulling container images..."
  $compose pull

  log "Starting stack with Docker Compose..."
  $compose up -d

  show_next_steps
}

main "$@"
