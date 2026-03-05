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
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;700&family=Sora:wght@500;700&display=swap"
      rel="stylesheet"
    />
    <style>
      :root {
        --bg: #050b14;
        --bg-soft: #081423;
        --ink: #ecf4ff;
        --muted: #9ab0c6;
        --line: #24445f;
        --blue: #4e9dff;
        --teal: #29d7ca;
        --font-display: "Sora", sans-serif;
        --font-body: "Space Grotesk", sans-serif;
      }

      * {
        box-sizing: border-box;
      }

      html,
      body {
        margin: 0;
        padding: 0;
      }

      body {
        font-family: var(--font-body);
        min-height: 100vh;
        color: var(--ink);
        background:
          radial-gradient(1100px 560px at 110% -8%, rgba(78, 157, 255, 0.2), transparent 60%),
          radial-gradient(900px 420px at -8% -5%, rgba(41, 215, 202, 0.12), transparent 60%),
          linear-gradient(180deg, var(--bg) 0%, #040911 100%);
      }

      body::before {
        content: "";
        position: fixed;
        inset: 0;
        z-index: 0;
        pointer-events: none;
        opacity: 0.15;
        background-image:
          linear-gradient(to right, rgba(149, 185, 221, 0.15) 1px, transparent 1px),
          linear-gradient(to bottom, rgba(149, 185, 221, 0.15) 1px, transparent 1px);
        background-size: 40px 40px;
      }

      .wrap {
        width: min(980px, calc(100% - 44px));
        margin: 0 auto;
        position: relative;
        z-index: 1;
      }

      .topbar {
        height: 78px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        border-bottom: 1px solid rgba(54, 90, 120, 0.45);
        position: sticky;
        top: 0;
        backdrop-filter: blur(8px);
        background: rgba(5, 11, 20, 0.88);
      }

      .brand {
        color: var(--ink);
        text-decoration: none;
        display: inline-flex;
        align-items: center;
        gap: 10px;
        font-size: 0.78rem;
        text-transform: uppercase;
        letter-spacing: 0.12em;
        font-weight: 700;
      }

      .logo {
        width: 34px;
        height: 34px;
        border: 1px solid #335c81;
        background: #10263b;
        display: grid;
        place-items: center;
      }

      .logo svg {
        width: 20px;
        height: 20px;
        fill: none;
        stroke-linecap: round;
        stroke-linejoin: round;
      }

      .logo .a {
        stroke: var(--blue);
        stroke-width: 2;
      }

      .logo .b {
        stroke: var(--teal);
        stroke-width: 2;
      }

      .top-link {
        color: var(--ink);
        text-decoration: none;
        font-size: 0.76rem;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        border: 1px solid #355f85;
        background: #10263b;
        padding: 9px 12px;
      }

      .hero {
        padding: 68px 0 44px;
        border-bottom: 1px solid rgba(48, 79, 107, 0.5);
      }

      .eyebrow {
        margin: 0 0 12px;
        color: #80b2ff;
        font-size: 0.76rem;
        text-transform: uppercase;
        letter-spacing: 0.16em;
        font-weight: 700;
      }

      h1 {
        margin: 0;
        font-family: var(--font-display);
        font-size: clamp(2rem, 5.8vw, 4.5rem);
        line-height: 1.04;
        letter-spacing: -0.015em;
        text-wrap: balance;
      }

      .hero-title-soft {
        color: #dce9f7;
      }

      .hero-title-accent {
        background: linear-gradient(110deg, #67a8ff 0%, #76c7ff 45%, #3fe3d6 100%);
        -webkit-background-clip: text;
        background-clip: text;
        color: transparent;
      }

      .lead {
        margin: 16px 0 0;
        color: var(--muted);
        font-size: 1rem;
        line-height: 1.62;
        max-width: 54ch;
      }

      .services {
        margin: 28px 0 24px;
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
        gap: 12px;
      }

      .card {
        border: 1px solid var(--line);
        background: linear-gradient(180deg, rgba(16, 41, 64, 0.56), rgba(9, 21, 33, 0.45));
        padding: 18px;
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .card h2 {
        margin: 0;
        font-family: var(--font-display);
        font-size: 1.45rem;
        letter-spacing: -0.01em;
      }

      .meta {
        margin: 0;
        color: var(--muted);
        font-size: 0.95rem;
      }

      .url {
        margin: 0;
        color: #d5e9fb;
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        font-size: 0.83rem;
      }

      .actions {
        margin-top: 4px;
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
      }

      .btn {
        text-decoration: none;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        font-size: 0.76rem;
        font-weight: 700;
        padding: 10px 13px;
        transition: transform 140ms ease;
      }

      .btn:hover {
        transform: translateY(-2px);
      }

      .btn.primary {
        color: #eef7ff;
        background: linear-gradient(140deg, #4b9cff, #3069d3);
      }

      .btn.secondary {
        color: var(--ink);
        border: 1px solid #3c648a;
        background: #112940;
      }

      footer {
        border-top: 1px solid var(--line);
        padding: 18px 0 28px;
        color: var(--muted);
        font-size: 0.88rem;
      }

      @media (max-width: 640px) {
        .topbar {
          height: 70px;
        }

        .brand span {
          display: none;
        }
      }
    </style>
  </head>
  <body>
    <div class="wrap">
      <header class="topbar">
        <a class="brand" href="${homepage_url}">
          <span class="logo" aria-hidden="true">
            <svg viewBox="0 0 24 24">
              <path class="a" d="M3 18L12 6l9 12" />
              <path class="b" d="M3 6h18" />
            </svg>
          </span>
          <span>Platform Control</span>
        </a>
        <a class="top-link" href="${homepage_url}">Homepage</a>
      </header>

      <main class="hero">
        <p class="eyebrow">Internal Platform</p>
        <h1>
          <span class="hero-title-soft">Self-Hosted</span>
          <span class="hero-title-accent">CI/CD Stack</span>
        </h1>
        <p class="lead">
          Quick access to your local developer platform services with a Helix-style control surface.
        </p>
      </main>

      <section class="services" aria-label="Services">
        <article class="card">
          <h2>Gitea</h2>
          <p class="meta">Git hosting and repository management</p>
          <p class="url">${gitea_url}</p>
          <div class="actions">
            <a class="btn primary" href="${gitea_url}">Open Gitea</a>
          </div>
        </article>
        <article class="card">
          <h2>TeamCity</h2>
          <p class="meta">Build server and pipeline orchestration</p>
          <p class="url">${teamcity_url}</p>
          <div class="actions">
            <a class="btn secondary" href="${teamcity_url}">Open TeamCity</a>
          </div>
        </article>
      </section>

      <footer>Homepage: ${homepage_url}</footer>
    </div>
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
