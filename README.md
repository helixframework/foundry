# Self-Hosted CI/CD Scaffold (Gitea + TeamCity)

This repository provides a local/self-hosted CI/CD baseline using Docker containers:

- **Homepage** for quick navigation
- **Gitea** for source hosting
- **TeamCity Server** for build orchestration
- **TeamCity Agent** for build execution

All components run with Docker Compose, and setup is driven by a single executable:

```bash
./install.sh
```

## What You Get

- Containerized stack (`docker-compose.yml`)
- Persistent data volumes under `./data`
- Environment template (`.env.example`)
- One-shot installer (`install.sh`)
- Helper scripts in `./scripts`

## Prerequisites

- Docker Engine installed and running
- Docker Compose plugin (`docker compose`) or legacy binary (`docker-compose`)

## Quick Start

1. Run the installer:

```bash
./install.sh
```

2. Open:
- Homepage: [http://localhost:8080](http://localhost:8080)
- Gitea: [http://localhost:3000](http://localhost:3000)
- TeamCity: [http://localhost:8111](http://localhost:8111)

3. Complete first-run web setup:
- In Gitea, create your user/org/repos.
- In TeamCity, finish server setup, authorize the connected agent, and configure VCS roots pointing to Gitea.

## Configuration

Installer behavior:
- Creates required data directories under `./data`.
- Generates `.env` from `.env.example` if `.env` is missing.
- Auto-sets `PUID`/`PGID` in `.env` to your current user.
- Pulls images and starts the stack.

Edit `.env` to change ports, names, and root URL.

Important variables:
- `HOMEPAGE_PORT` (default `8080`)
- `GITEA_HTTP_PORT` (default `3000`)
- `GITEA_SSH_PORT` (default `2222`)
- `TEAMCITY_HTTP_PORT` (default `8111`)
- `GITEA_ROOT_URL` (default `http://localhost:3000/`)

## Operations

Use helper scripts:

```bash
./scripts/start.sh
./scripts/stop.sh
./scripts/status.sh
./scripts/logs.sh
```

You can also use Docker Compose directly.

## Directory Layout

```text
.
├── docker-compose.yml
├── install.sh
├── .env.example
├── homepage/
│   └── index.html
├── scripts/
│   ├── start.sh
│   ├── stop.sh
│   ├── status.sh
│   └── logs.sh
└── data/
    ├── gitea/
    └── teamcity/
        ├── server/
        └── agent/
```

## Notes

- TeamCity first startup can take several minutes.
- Agent uses the host Docker socket (`/var/run/docker.sock`) so builds can run Docker commands.
- For internet-facing deployments, place a reverse proxy and TLS in front of both services.
