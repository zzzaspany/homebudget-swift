# Deployment

Runs as two rootless Podman containers managed by systemd Quadlets, the same pattern as the rest of
the homelab: the app and its PostgreSQL, on a private network, with only the app's port published.

## What runs where

| Unit | Image | Reachable from |
| --- | --- | --- |
| `homebudget.container` | `ghcr.io/zzzaspany/homebudget-swift` | the host, on port 8000 |
| `homebudget-postgres.container` | `postgres:17-alpine` | the app only, over the internal network |
| `homebudget.network` | — | joins the two |

The app is meant to sit behind Authelia, which supplies the signed-in user through request headers.
It performs no authentication of its own, so **anything that can reach port 8000 is treated as
signed in** — the port must not be exposed beyond the reverse proxy.

## First install

```bash
mkdir -p ~/.config/containers/systemd
cp deploy/homebudget.network deploy/*.container ~/.config/containers/systemd/

cp deploy/homebudget.env.example ~/.config/containers/systemd/homebudget.env
cp deploy/homebudget-postgres.env.example ~/.config/containers/systemd/homebudget-postgres.env
# Set the password in both files — they have to match.
chmod 600 ~/.config/containers/systemd/*.env

systemctl --user daemon-reload
systemctl --user start homebudget-postgres.service
systemctl --user start homebudget.service
```

Migrations run before the app starts, from `ExecStartPre` in the unit, so a deploy that adds a
migration applies it on restart without a separate step.

## Updates

`AutoUpdate=registry` means `podman-auto-update.timer` picks up new images pushed to GHCR. Enable it
once:

```bash
systemctl --user enable --now podman-auto-update.timer
```

## The database locale matters

The cluster is created with `--encoding=UTF8 --locale=pl_PL.UTF-8`. This is not cosmetic: a default
Debian install produced a `SQL_ASCII` cluster, which stores Polish text but sorts and compares it
wrongly, and `upper`/`lower` stop working on any accented letter. The setting only applies when the
data directory is first initialised — changing it later means recreating the cluster.

## Backups

Two volumes hold everything that cannot be rebuilt:

```bash
podman volume export homebudget-pgdata --output pgdata.tar
podman volume export homebudget-uploads --output uploads.tar
```

`homebudget-uploads` holds the invoice attachments. They are deliberately not in the database, to
keep dumps small, which does mean they need backing up separately.

## Building the image

```bash
podman build -f Containerfile -t homebudget-swift .
```

Three stages: the client is compiled to WebAssembly, the server binary is built with a statically
linked Swift runtime, and the runtime image carries neither toolchain. The WebAssembly SDK is a
large download but sits in its own stage, so it is only refetched when the client changes.

## Health

`GET /health` needs no authentication and touches no database, which makes it usable as a container
health check without granting anything.
