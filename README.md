# nova-ve

> [!WARNING]
> Alpha Development Version: Nova-VE is usable for early testing and feedback,
> but still expect incomplete features, workflow changes, and runtime instability.

A clean-room network virtualization environment built with modern tooling.

## Community

Official Telegram channel for Nova-VE updates and discussion:
<https://t.me/+-xHf0vpsUHI1MmY0>

## Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Svelte 5 + SvelteKit + Svelte Flow + Tailwind CSS |
| Backend | FastAPI + Pydantic + SQLAlchemy (async) |
| Database | PostgreSQL (app data) + JSON files (lab topology) |
| Virtualization | QEMU/KVM + Docker |
| Console | Apache Guacamole (HTML5) |
| Reverse Proxy | Caddy |
| Base OS | Ubuntu 26.04 LTS |

## Quick Start

On a fresh Ubuntu 26.04 LTS x86_64 host with sudo access:

```bash
curl -fsSL https://raw.githubusercontent.com/fahadysf/nova-ve/main/install.sh | sudo bash
```

> **Full documentation** lives at <https://docs.nova-ve.com/> (built from `docs/`).
> A GitHub Pages mirror remains available at <https://fahadysf.github.io/nova-ve/>.
>
> **Migrating from EVE-NG / UNetLab / PNETLab?** See the [Importing from EVE-NG](docs/importing-eveng/index.md) section for the importer walk-through (default image mode is move + symlink back — the original path keeps working via a symlink; `--copy-only` restores the conservative copy+verify mode and `--delete-source` is the destructive option).

That single command:

1. Installs git, Docker, PostgreSQL, Caddy, Node.js, Python 3 + venv, `dnsmasq`, `nftables`, build tooling, and other OS deps.
2. Creates/reuses the dedicated `nova-ve` service user and clones this repo to `/var/lib/nova-ve/nova-ve-git` by default.
3. Bootstraps the host PostgreSQL role/db (`nova` / `novadb`) and the dockerized Guacamole stack (`guacdb` / `guacd` / `guacamole`).
4. Builds the FastAPI backend (Python venv + Alembic migrations + initial seed).
5. Builds the SvelteKit frontend (`npm ci` + `vite build`) into `/var/lib/nova-ve/www`.
6. Installs the privileged network helper at `/opt/nova-ve/bin/` plus its `visudo`-validated sudoers fragment, including NAT-Cloud DHCP, NAT, and forwarding verbs.
7. Optionally installs the side-by-side QEMU version pack (`/opt/nova-ve/qemu/<version>`) from the `nova-ve-qemu` companion repo — enables per-node QEMU version selection; disable with `NOVA_VE_QEMU_PKGS=0`.
8. Drops systemd units (`nova-ve-backend`, `caddy`) and starts them.
9. Reconciles existing NAT-Cloud bridge state on upgraded hosts and deploys Docker runtime reconciliation for stale same-name containers.
10. Runs the in-tree smoke check.
11. Writes a private installation summary and reports its path.

The script is idempotent: re-running it fast-forwards the repo, reapplies templates, reinstalls the helper, reconciles NAT-Cloud runtime state for existing bridges, and restarts services without rotating existing secrets.

Override knobs (env vars):

| Var | Default | Purpose |
|-----|---------|---------|
| `NOVA_VE_REPO_URL` | `https://github.com/fahadysf/nova-ve.git` | Source repo |
| `NOVA_VE_REPO_REF` | `main` | Branch / tag / SHA to check out |
| `NOVA_VE_REPO_DIR` | `/var/lib/nova-ve/nova-ve-git` | Clone destination; legacy `~${SUDO_USER}/nova-ve-git` checkouts are reused during migration when present |
| `NOVA_VE_SERVICE_USER` | `nova-ve` | Dedicated UNIX service user that owns runtime state and runs the backend |
| `NOVA_VE_OWNER` | (unset) | Compatibility alias for `NOVA_VE_SERVICE_USER` |
| `NOVA_VE_QEMU_PKGS` | `1` | Install the side-by-side QEMU version pack (per-node QEMU version selection) |
| `NOVA_VE_QEMU_RELEASE` | `v1.0.0` | `nova-ve-qemu` GitHub Release tag to pull the pack from |
| `NOVA_VE_QEMU_VERSIONS` | `2.12.1 4.1.0 5.2.0 11.1.3` | QEMU versions to install side-by-side under `/opt/nova-ve/qemu/` |

After install, open `http://<host>/` and log in with the admin credentials reported by the installer.

For development workflows (running the backend with `--reload`, the frontend dev server, or a Rancher Desktop loop on macOS), see the [Deployment contract](docs/development/deployment-contract.md) and the helper scripts in [`deploy/scripts/`](deploy/scripts/).

## Build and publish Docker images to Azure ACR

ACR publishing is optional. From the checkout, authenticate as an identity
authorized to push to your registry, then run:

```bash
az login
az acr login --name <registry-resource-name>
export NOVA_VE_ACR_REGISTRY=<registry-login-server>
bash deploy/scripts/build-all-images.sh
```

Use the registry's actual login server (for example `myregistry.azurecr.io`),
not a URL. Run Azure login and the build scripts as the same OS user.
Scripts read exported environment variables; they do not source `.env`.
Without `NOVA_VE_ACR_REGISTRY`, builds still run but nothing is pushed.

This builds all eight repository Dockerfiles, including the Ubuntu desktop
demo, and pulls the runtime images used by the Compose stacks. Only after
everything succeeds does it check every source image, create local ACR-qualified
tags, and push them. Every ACR destination uses `:latest`; upstream base/runtime
versions remain pinned except `guacamole/guacd` and `guacamole/guacamole`,
which also use upstream `:latest`. Unrelated images on the Docker host are never published.
Original local tags and lab catalog markers remain available.

Application/demo/platform repositories retain their `nova-ve/` names.
Guacamole images retain `guacamole/guacd` and `guacamole/guacamole`.
Runtime variants use separate repositories to avoid overwriting each other:

- `alpine:3.22` becomes `nova-ve/runtime/alpine:latest`.
- `alpine:3.21` becomes `nova-ve/runtime/alpine-sandbox:latest`.
- `postgres:16-alpine` becomes `nova-ve/runtime/postgres-alpine:latest`.
- `postgres:16` becomes `nova-ve/runtime/postgres:latest`.

To retry publication without rebuilding, run
`bash deploy/scripts/publish-acr-images.sh`. A missing source, failed build,
pull, tag or push exits nonzero. Registry pushes are not atomic: a failed push
can leave earlier images published, so retry after fixing the failure.

The existing `build-demo-images.sh` and `build-platform-images.sh` helpers
publish their own images after completion when ACR is configured. Platform
`pull`/`auto` mode uses ACR instead of GHCR; ACR publication takes precedence
over `GHCR_PUSH`. The installer remains a host deployment, not the build-all
publishing command. Compose still uses the original local/runtime references;
publishing alone does not change running deployments.

### GitHub Actions and credentials

The container workflow builds all images and verifies platform containers
before publishing on `main`. Configure these GitHub repository **variables**:
`NOVA_VE_ACR_REGISTRY`, `AZURE_ACR_NAME`, `AZURE_CLIENT_ID`,
`AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID`. Configure an Azure federated
credential for this repository's `main` branch and grant the identity
registry-scoped push access (`AcrPush`, or the appropriate repository writer
role for an ABAC-enabled registry). With no registry variable, CI only builds
and verifies; it does not publish to ACR or GHCR.

Azure OIDC avoids stored registry passwords. Local publishing reuses Docker's
existing authentication; use an OS credential helper for Docker and never
commit access tokens, passwords or credential files. Inject application
secrets at runtime from a secret manager such as Azure Key Vault or a protected
runtime secret mount, not Docker build arguments or image layers. Backend and
frontend build contexts exclude local environment and credential files.

Run the isolated, mocked-Docker checks with
`bash deploy/scripts/test-acr-images.sh`.

## Project Structure

```
nova-ve/
├── backend/
│   ├── app/
│   │   ├── models/          # SQLAlchemy models
│   │   ├── routers/         # FastAPI route handlers
│   │   ├── schemas/         # Pydantic models
│   │   ├── services/        # Business logic
│   │   ├── config.py        # Settings
│   │   ├── database.py      # Async DB engine
│   │   └── main.py          # App entrypoint
│   ├── labs/                # Sample lab JSON files
│   ├── alembic/             # Database migrations
│   └── requirements.txt
├── frontend/
│   ├── src/
│   │   ├── lib/
│   │   │   ├── components/  # Svelte components
│   │   │   ├── stores/      # Svelte stores (auth, etc.)
│   │   │   └── types/       # TypeScript types
│   │   └── routes/          # SvelteKit pages
│   └── package.json
├── docker-compose.yml
└── README.md
```

## License

Copyright (c) 2026 Fahad Yousuf <fahadysf [at] gmail.com>.

This repository is licensed under the `Apache License 2.0`.
See [LICENSE](LICENSE) and [NOTICE](NOTICE).
