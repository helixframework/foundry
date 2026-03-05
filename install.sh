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
    data/nexus
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
  : "${NEXUS_DOMAIN:=nexus.localhost}"
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
  local homepage_url gitea_url teamcity_url nexus_url started_at
  homepage_url="https://${HOMEPAGE_DOMAIN}"
  gitea_url="${GITEA_ROOT_URL%/}"
  teamcity_url="https://${TEAMCITY_DOMAIN}"
  nexus_url="https://${NEXUS_DOMAIN}"
  started_at="$(date '+%Y-%m-%d %H:%M:%S %Z')"

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
        --bg-end: #040911;
        --bg-glow-1: rgba(78, 157, 255, 0.2);
        --bg-glow-2: rgba(41, 215, 202, 0.12);
        --grid-line: rgba(149, 185, 221, 0.15);
        --ink: #ecf4ff;
        --muted: #9ab0c6;
        --line: #24445f;
        --blue: #4e9dff;
        --teal: #29d7ca;
        --topbar-bg: rgba(5, 11, 20, 0.88);
        --topbar-border: rgba(54, 90, 120, 0.45);
        --panel-bg: linear-gradient(180deg, rgba(16, 41, 64, 0.56), rgba(9, 21, 33, 0.45));
        --logo-bg: #10263b;
        --logo-border: #335c81;
        --control-bg: #10263b;
        --control-border: #355f85;
        --section-border: rgba(48, 79, 107, 0.5);
        --accent-soft: #8cbcff;
        --code: #d5e9fb;
        --subtle-line: #2d506f;
        --footer-ink: #89a4bf;
        --badge-ok-text: #b9efd9;
        --badge-ok-border: #2f7a5e;
        --badge-ok-bg: rgba(34, 103, 78, 0.3);
        --btn-secondary-bg: #112940;
        --btn-secondary-border: #3c648a;
        --font-display: "Sora", sans-serif;
        --font-body: "Space Grotesk", sans-serif;
      }

      [data-theme="light"] {
        --bg: #edf4fb;
        --bg-end: #dfeaf6;
        --bg-glow-1: rgba(47, 115, 200, 0.2);
        --bg-glow-2: rgba(25, 143, 132, 0.12);
        --grid-line: rgba(72, 102, 132, 0.14);
        --ink: #0f1a26;
        --muted: #4b5d71;
        --line: #b6c9dd;
        --blue: #2f73c8;
        --teal: #198f84;
        --topbar-bg: rgba(237, 244, 251, 0.88);
        --topbar-border: #b8cde0;
        --panel-bg: linear-gradient(180deg, rgba(255, 255, 255, 0.9), rgba(241, 247, 253, 0.92));
        --logo-bg: #f5f9ff;
        --logo-border: #9eb8d2;
        --control-bg: #f2f7fd;
        --control-border: #9cb9d7;
        --section-border: #c3d5e7;
        --accent-soft: #2f73c8;
        --code: #17314a;
        --subtle-line: #c3d5e7;
        --footer-ink: #4f6277;
        --badge-ok-text: #1f674e;
        --badge-ok-border: #4f9f7f;
        --badge-ok-bg: rgba(29, 133, 97, 0.12);
        --btn-secondary-bg: #edf4fb;
        --btn-secondary-border: #8dadca;
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
          radial-gradient(1100px 560px at 110% -8%, var(--bg-glow-1), transparent 60%),
          radial-gradient(900px 420px at -8% -5%, var(--bg-glow-2), transparent 60%),
          linear-gradient(180deg, var(--bg) 0%, var(--bg-end) 100%);
      }

      body::before {
        content: "";
        position: fixed;
        inset: 0;
        z-index: 0;
        pointer-events: none;
        opacity: 0.15;
        background-image:
          linear-gradient(to right, var(--grid-line) 1px, transparent 1px),
          linear-gradient(to bottom, var(--grid-line) 1px, transparent 1px);
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
        border-bottom: 1px solid var(--topbar-border);
        position: sticky;
        top: 0;
        backdrop-filter: blur(8px);
        background: var(--topbar-bg);
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
        border: 1px solid var(--logo-border);
        background: var(--logo-bg);
        display: grid;
        place-items: center;
      }

      .top-actions {
        display: inline-flex;
        align-items: center;
        gap: 8px;
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
        border: 1px solid var(--control-border);
        background: var(--control-bg);
        padding: 9px 12px;
      }

      .theme-toggle {
        color: var(--ink);
        border: 1px solid var(--control-border);
        background: var(--control-bg);
        font: 700 0.72rem var(--font-body);
        text-transform: uppercase;
        letter-spacing: 0.08em;
        padding: 6px 10px 6px 8px;
        min-width: 102px;
        display: inline-flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        cursor: pointer;
      }

      .switch-track {
        width: 36px;
        height: 20px;
        border: 1px solid var(--control-border);
        background: rgba(0, 0, 0, 0.15);
        display: inline-flex;
        align-items: center;
        padding: 2px;
        transition: background 160ms ease;
      }

      .switch-thumb {
        width: 14px;
        height: 14px;
        background: var(--ink);
        transition: transform 160ms ease;
      }

      .theme-toggle[data-theme="light"] .switch-track {
        background: rgba(34, 103, 78, 0.32);
      }

      .theme-toggle[data-theme="light"] .switch-thumb {
        transform: translateX(16px);
      }

      .switch-label {
        line-height: 1;
      }

      .hero {
        padding: 44px 0 28px;
        border-bottom: 1px solid var(--section-border);
        display: grid;
        grid-template-columns: 1.2fr 0.8fr;
        gap: 14px;
        align-items: start;
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
        font-size: clamp(2rem, 5vw, 3.3rem);
        line-height: 1.1;
        letter-spacing: -0.015em;
        text-wrap: balance;
      }

      .title-accent {
        background: linear-gradient(110deg, #67a8ff 0%, #76c7ff 45%, #3fe3d6 100%);
        -webkit-background-clip: text;
        background-clip: text;
        color: transparent;
      }

      .lead {
        margin: 12px 0 0;
        color: var(--muted);
        font-size: 0.95rem;
        line-height: 1.55;
        max-width: 54ch;
      }

      .hero-panel {
        border: 1px solid var(--line);
        background: var(--panel-bg);
        padding: 14px;
      }

      .hero-panel h2 {
        margin: 0 0 10px;
        font-size: 0.8rem;
        text-transform: uppercase;
        letter-spacing: 0.11em;
        color: var(--accent-soft);
      }

      .kv {
        display: grid;
        grid-template-columns: auto 1fr;
        gap: 8px 12px;
        margin: 0;
      }

      .kv dt {
        color: var(--muted);
        font-size: 0.8rem;
      }

      .kv dd {
        margin: 0;
        color: var(--code);
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        font-size: 0.8rem;
      }

      .badge {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-size: 0.7rem;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        border: 1px solid var(--control-border);
        padding: 4px 7px;
      }

      .badge::before {
        content: "";
        width: 7px;
        height: 7px;
        border-radius: 50%;
      }

      .badge.ok {
        color: var(--badge-ok-text);
        border-color: var(--badge-ok-border);
        background: var(--badge-ok-bg);
      }

      .badge.ok::before {
        background: #37dca2;
      }

      .services {
        margin: 18px 0 16px;
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 12px;
      }

      .card {
        border: 1px solid var(--line);
        background: var(--panel-bg);
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

      .card-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
      }

      .meta {
        margin: 0;
        color: var(--muted);
        font-size: 0.95rem;
      }

      .url {
        margin: 0;
        color: var(--code);
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
        border: 0;
        font-family: var(--font-body);
        cursor: pointer;
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
        border: 1px solid var(--btn-secondary-border);
        background: var(--btn-secondary-bg);
      }

      .activity {
        border: 1px solid var(--line);
        background: var(--panel-bg);
        padding: 16px 18px;
        margin: 0 0 22px;
      }

      .activity h2 {
        margin: 0;
        font-family: var(--font-display);
        font-size: 1.2rem;
      }

      .activity-list {
        margin: 12px 0 0;
        padding: 0;
        list-style: none;
        display: grid;
        gap: 8px;
      }

      .activity-list li {
        border-top: 1px solid var(--subtle-line);
        padding-top: 8px;
        display: grid;
        gap: 4px;
      }

      .activity-list p {
        margin: 0;
        color: var(--muted);
        font-size: 0.88rem;
      }

      .cmd {
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        color: var(--code);
        font-size: 0.8rem;
      }

      .footer {
        border-top: 1px solid var(--line);
        padding: 14px 0 24px;
        display: grid;
        grid-template-columns: 1fr auto;
        align-items: center;
        gap: 8px;
        color: var(--footer-ink);
        font-size: 0.8rem;
        text-transform: uppercase;
        letter-spacing: 0.09em;
      }

      .footer a {
        color: inherit;
        text-decoration: none;
      }

      .github-link {
        width: 18px;
        height: 18px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
      }

      .github-link svg {
        width: 18px;
        height: 18px;
        fill: currentColor;
        opacity: 0.9;
      }

      .github-link:hover svg {
        opacity: 1;
      }

      .footer > :first-child {
        justify-self: start;
      }

      .footer > :last-child {
        justify-self: end;
      }

      @media (max-width: 640px) {
        .topbar {
          height: 70px;
        }

        .brand > span:last-child {
          display: none;
        }

        .hero {
          grid-template-columns: 1fr;
        }

        .services {
          grid-template-columns: 1fr;
        }

        .footer {
          grid-template-columns: 1fr;
        }

        .footer > :first-child,
        .footer > :last-child {
          justify-self: start;
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
          <span>Helix</span>
        </a>
        <div class="top-actions">
          <button class="theme-toggle" id="theme-toggle" type="button" aria-label="Toggle color mode">
            <span class="switch-track" aria-hidden="true"><span class="switch-thumb"></span></span>
            <span class="switch-label" id="theme-toggle-label">Dark</span>
          </button>
        </div>
      </header>

      <main class="hero">
        <article>
          <p class="eyebrow">Operations Dashboard</p>
          <h1>Helix <span class="title-accent">Foundry</span></h1>
        </article>
        <aside class="hero-panel" aria-label="Environment Summary">
          <h2>Environment Summary</h2>
          <dl class="kv">
            <dt>Environment</dt>
            <dd>local</dd>
            <dt>Homepage</dt>
            <dd>${homepage_url}</dd>
            <dt>Started</dt>
            <dd>${started_at}</dd>
          </dl>
        </aside>
      </main>

      <section class="services" aria-label="Services">
        <article class="card">
          <div class="card-head">
            <h2>Gitea</h2>
            <span class="badge ok">Healthy</span>
          </div>
          <p class="meta">Git hosting and repository management</p>
          <p class="url">${gitea_url}</p>
          <div class="actions">
            <a class="btn primary" href="${gitea_url}" target="_blank" rel="noopener noreferrer">Open</a>
            <a class="btn secondary" href="https://docs.gitea.com/" target="_blank" rel="noopener noreferrer">Docs</a>
            <button class="btn secondary" type="button" data-copy="docker compose ps gitea">Status</button>
            <button class="btn secondary" type="button" data-copy="docker compose logs -f gitea">Logs</button>
            <button class="btn secondary" type="button" data-copy="docker compose restart gitea">Restart</button>
          </div>
        </article>
        <article class="card">
          <div class="card-head">
            <h2>TeamCity</h2>
            <span class="badge ok">Healthy</span>
          </div>
          <p class="meta">Build server and pipeline orchestration</p>
          <p class="url">${teamcity_url}</p>
          <div class="actions">
            <a class="btn primary" href="${teamcity_url}" target="_blank" rel="noopener noreferrer">Open</a>
            <a class="btn secondary" href="https://www.jetbrains.com/help/teamcity/" target="_blank" rel="noopener noreferrer">Docs</a>
            <button class="btn secondary" type="button" data-copy="docker compose ps teamcity-server">Status</button>
            <button class="btn secondary" type="button" data-copy="docker compose logs -f teamcity-server">Logs</button>
            <button class="btn secondary" type="button" data-copy="docker compose restart teamcity-server">Restart</button>
          </div>
        </article>
        <article class="card">
          <div class="card-head">
            <h2>Nexus</h2>
            <span class="badge ok">Healthy</span>
          </div>
          <p class="meta">Artifact and repository management</p>
          <p class="url">${nexus_url}</p>
          <div class="actions">
            <a class="btn primary" href="${nexus_url}" target="_blank" rel="noopener noreferrer">Open</a>
            <a class="btn secondary" href="https://help.sonatype.com/en/nexus-repository-manager.html" target="_blank" rel="noopener noreferrer">Docs</a>
            <button class="btn secondary" type="button" data-copy="docker compose ps nexus">Status</button>
            <button class="btn secondary" type="button" data-copy="docker compose logs -f nexus">Logs</button>
            <button class="btn secondary" type="button" data-copy="docker compose restart nexus">Restart</button>
          </div>
        </article>
      </section>

      <section class="activity" aria-label="Recent Activity">
        <h2>Recent Activity</h2>
        <ul class="activity-list">
          <li>
            <p>Stack bootstrap completed and services are reachable.</p>
            <span class="cmd">./install.sh</span>
          </li>
          <li>
            <p>Check current container state and health.</p>
            <span class="cmd">./scripts/status.sh</span>
          </li>
          <li>
            <p>View combined logs for troubleshooting.</p>
            <span class="cmd">./scripts/logs.sh</span>
          </li>
        </ul>
      </section>

      <footer class="footer">
        <span>&copy; 2026 Helix Framework</span>
        <a class="github-link" href="https://github.com/helixframework/foundry" aria-label="Foundry on GitHub" target="_blank" rel="noopener noreferrer">
          <svg viewBox="0 0 16 16" role="img" focusable="false" aria-hidden="true">
            <path d="M8 0C3.58 0 0 3.58 0 8a8 8 0 0 0 5.47 7.59c.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52 0-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.5-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.53 7.53 0 0 1 4 0c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8 8 0 0 0 16 8c0-4.42-3.58-8-8-8Z"></path>
          </svg>
        </a>
      </footer>
    </div>
    <script>
      (function () {
        var key = "foundry-theme";
        var root = document.documentElement;
        var toggle = document.getElementById("theme-toggle");
        var label = document.getElementById("theme-toggle-label");
        if (!toggle) return;

        function applyTheme(theme) {
          root.setAttribute("data-theme", theme);
          toggle.setAttribute("aria-checked", theme === "light" ? "true" : "false");
          toggle.setAttribute("data-theme", theme);
          if (label) label.textContent = theme === "dark" ? "Dark" : "Light";
        }

        var stored = localStorage.getItem(key);
        var preferred = window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches
          ? "light"
          : "dark";
        applyTheme(stored || preferred);

        toggle.addEventListener("click", function () {
          var next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
          applyTheme(next);
          localStorage.setItem(key, next);
        });

        var copyButtons = document.querySelectorAll("[data-copy]");
        copyButtons.forEach(function (button) {
          button.addEventListener("click", function () {
            var command = button.getAttribute("data-copy");
            navigator.clipboard.writeText(command);
          });
        });
      })();
    </script>
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
- Nexus:    https://${NEXUS_DOMAIN}

First-run notes:
- Gitea is configured to use PostgreSQL.
- TeamCity is configured to use PostgreSQL via database.properties.
- TLS is provided by Caddy. With 'internal' mode, your browser may show a certificate warning until you trust Caddy's local CA.
- TeamCity will take a minute or two on first boot and then ask for setup in the web UI.
- In TeamCity, connect VCS root to your Gitea repo URL.
- Nexus will initialize on first startup; open its web UI to complete setup.

Helpful commands:
- ./scripts/status.sh
- ./scripts/logs.sh
- ./scripts/stop.sh
- ./scripts/start.sh
- ./scripts/teardown.sh --yes
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
