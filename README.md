# Self-Hosted CI/CD Platform

This repository provides a local/self-hosted CI/CD baseline using Docker containers:

- **Caddy** as reverse proxy + TLS terminator (serves dashboard static files + `/api/*` proxy)
- **Dashboard API** (Spring Boot) for dynamic dashboard data
- **PostgreSQL** for persistent application databases
- **Dashboard Web** for quick navigation
- **Gitea** for source hosting
- **TeamCity Server** for build orchestration
- **TeamCity Agent** for build execution
- **Nexus Repository** for artifact hosting and proxying
- **Gradle Build Cache** for remote build caching

All components run with Docker Compose, and setup is driven by a single executable:

```bash
./install.sh
```

## What You Get

- Containerized stack (`docker-compose.yml`)
- Spring Boot dashboard backend (`dashboard-api/`)
- Persistent data volumes under `./data`
- Environment template (`.env.example`)
- One-shot installer (`install.sh`)
- Helper scripts in `./scripts`
- Dashboard API endpoint: `https://localhost/api/dashboard`
- Live logs page: `https://localhost/logs.html?service=gitea`
- Backups page: `https://localhost/backups.html`
- Gradle build cache endpoint: `https://build-cache.localhost/cache/`

## Prerequisites

- Docker Engine installed and running
- Docker Compose plugin (`docker compose`) or legacy binary (`docker-compose`)

## Quick Start

1. Run the installer:

```bash
./install.sh
```

2. Open:
- Dashboard: [https://localhost](https://localhost)
- Gitea: [https://gitea.localhost](https://gitea.localhost)
- TeamCity: [https://teamcity.localhost](https://teamcity.localhost)
- Nexus: [https://nexus.localhost](https://nexus.localhost)
- Build Cache: [https://build-cache.localhost/cache/](https://build-cache.localhost/cache/)

3. Complete first-run web setup:
- In Gitea, create your user/org/repos.
- In TeamCity, finish server setup, authorize the connected agent, and configure VCS roots pointing to Gitea.
- In Nexus, sign in with the initial admin password and complete the onboarding flow.

## Configuration

Installer behavior:
- Creates required data directories under `./data`.
- Generates `.env` from `.env.example` if `.env` is missing.
- Auto-sets `PUID`/`PGID` in `.env` to your current user.
- Generates PostgreSQL init SQL for Gitea/TeamCity databases.
- Generates TeamCity `database.properties` for PostgreSQL.
- Pulls images and starts the stack.

Edit `.env` to change ports, names, and root URL.

Important variables:
- `HTTP_PORT` / `HTTPS_PORT` (reverse proxy entry ports)
- `DASHBOARD_DOMAIN` / `GITEA_DOMAIN` / `TEAMCITY_DOMAIN` / `NEXUS_DOMAIN` / `BUILD_CACHE_DOMAIN`
- `FOUNDRY_VERSION` (shown in environment summary; default `dev`)
- `BACKUP_STALE_HOURS` (dashboard warning threshold; default `24`)
- `BACKUP_SCHEDULE_ENABLED` (enable scheduled backups from `dashboard-api`; default `true`)
- `BACKUP_CRON` (Spring cron expression with 6 fields; default `0 0 2 * * *`)
- `CADDY_TLS_MODE` (default `internal`)
- `POSTGRES_PORT` (default `5432`)
- `POSTGRES_ADMIN_USER` / `POSTGRES_ADMIN_PASSWORD`
- `GITEA_DB_NAME` / `GITEA_DB_USER` / `GITEA_DB_PASSWORD`
- `TEAMCITY_DB_NAME` / `TEAMCITY_DB_USER` / `TEAMCITY_DB_PASSWORD`
- `GITEA_SSH_PORT` (default `2222`)
- `TEAMCITY_HTTP_PORT` (default `8111`)
- `NEXUS_HTTP_PORT` (default `8081`)
- `BUILD_CACHE_PORT` (default `5071`)
- `GITEA_ROOT_URL` (default `https://gitea.localhost/`)
- `GRADLE_CACHE_STORAGE_DIR` (default `/data/cache`)

TLS note:
- Default mode uses `CADDY_TLS_MODE=internal` so certificates are issued by Caddy's internal CA.
- For public trusted certificates, replace this with an ACME-enabled Caddy config and real DNS records.

### Trust local cert on macOS

If your browser shows "Connection is not secure", trust Caddy's local root CA:

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain \
  $HOME/foundry/data/caddy/data/caddy/pki/authorities/local/root.crt
```

Then fully restart your browser and reload:
- `https://localhost`
- `https://gitea.localhost`
- `https://teamcity.localhost`
- `https://nexus.localhost`

## Nexus Setup

After first startup, open:
- `https://nexus.localhost`

### Initial admin login

Nexus creates a one-time admin password inside the container volume. Read it with:

```bash
docker compose exec nexus cat /nexus-data/admin.password
```

Then log in with:
- Username: `admin`
- Password: value from `admin.password`

### First-run wizard

Recommended choices:
1. Set a new admin password.
2. Choose anonymous access policy based on your needs (usually disabled for private/internal use).
3. Finish onboarding.

### Create repositories

Common internal repos to create:
- `docker-hosted` (for your private container images)
- `maven2-hosted` (for internal Java artifacts)
- `npm-hosted` (for internal JS packages)

You can also add proxy repos (`docker-proxy`, `maven-central`, `npmjs`) and then group repos for a single endpoint per ecosystem.

## Operations

Use helper scripts:

```bash
./scripts/start.sh
./scripts/stop.sh
./scripts/status.sh
./scripts/logs.sh
./scripts/backup.sh
./scripts/restore.sh backups/<timestamp> --yes
./scripts/teardown.sh --yes
```

You can also use Docker Compose directly.

## Backup And Restore

Create a backup:

```bash
./scripts/backup.sh
```

Automated backups are also scheduled by the `dashboard-api` service when `BACKUP_SCHEDULE_ENABLED=true`.
The schedule is controlled by `BACKUP_CRON` (default: daily at `02:00` server time).

This creates a timestamped folder in `./backups/` containing:
- PostgreSQL dumps for Gitea and TeamCity
- Tar archive of `data/caddy`, `data/gitea`, `data/nexus`, `data/teamcity`, `dashboard-web`, `caddy`, and `postgres/init`
- `env.snapshot` and metadata

Restore a backup (destructive):

```bash
./scripts/restore.sh backups/<timestamp> --yes
```

Restore behavior:
- Stops the full stack
- Restores file data archive
- Recreates Gitea and TeamCity databases
- Restores database dumps
- Starts the stack again

Full teardown (destructive):

```bash
./scripts/teardown.sh --yes
```

Teardown behavior:
- Stops and removes the full stack
- Deletes persisted runtime data under `data/`, `backups/`, and `postgres/init/`
- Recreates base empty directories so `./install.sh` can bootstrap cleanly

## Directory Layout

```text
.
├── docker-compose.yml
├── install.sh
├── .env.example
├── caddy/
│   └── Caddyfile
├── dashboard-web/
│   └── index.html
├── dashboard-api/
│   ├── Dockerfile
│   ├── build.gradle.kts
│   ├── settings.gradle.kts
│   └── src/
├── postgres/
│   └── init/
│       └── 01-init-app-dbs.sql (generated by installer)
├── scripts/
│   ├── backup.sh
│   ├── restore.sh
│   ├── teardown.sh
│   ├── start.sh
│   ├── stop.sh
│   ├── status.sh
│   └── logs.sh
├── backups/ (generated; gitignored)
└── data/
    ├── nexus/
    ├── gitea/
    ├── postgres/
    └── teamcity/
        ├── server/
        └── agent/
```

## Notes

- TeamCity first startup can take several minutes.
- Nexus first startup can take several minutes.
- Agent uses the host Docker socket (`/var/run/docker.sock`) so builds can run Docker commands.
- Caddy is already included as reverse proxy + TLS entrypoint.
- If you previously started with SQLite/internal DB, remove old data directories before reinstalling to start clean with PostgreSQL.
