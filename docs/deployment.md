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

## Secrets

Fetched from Infisical at start-up rather than kept in a file. `homebudget-swift-secrets.service`
runs before the container and writes them into the user's runtime directory, which is tmpfs — the
values exist only while the machine is up and never reach persistent storage.

What does live on disk is one credential: a machine identity scoped to read a single environment,
in `infisical.env`. Losing that file exposes far less than the secrets it fetches, and it can be
revoked without touching anything else.

The instance sits behind an internal CA the host does not trust. Verification is not disabled —
this connection carries every secret — so the expected certificate is pinned as the trust anchor in
`vault-ca.pem`. Replace it when the certificate is renewed, or better, install the root CA into the
system trust store and drop the `--cacert` argument.

## First install

```bash
mkdir -p ~/.config/containers/systemd
cp deploy/homebudget.network deploy/*.container ~/.config/containers/systemd/

cp deploy/infisical.env.example ~/.config/containers/systemd/infisical.env
# Fill in the machine identity's client id and secret, and the project id.
chmod 600 ~/.config/containers/systemd/infisical.env

install -m 755 deploy/provision-secrets.sh ~/.local/bin/
cp deploy/homebudget-swift-secrets.service ~/.config/systemd/user/

# Pin the certificate the Infisical instance presents.
openssl s_client -connect vault.example.lab:443 -servername vault.example.lab </dev/null 2>/dev/null \
  | openssl x509 -outform pem > ~/.config/containers/systemd/vault-ca.pem

systemctl --user daemon-reload
systemctl --user enable homebudget-swift-secrets.service
systemctl --user start homebudget-swift.service
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
make image                     # Apple container, the default on a Mac
make image CONTAINER=podman    # on the server
make image TAG=v1.0.0          # tag it
make image-push TAG=v1.0.0     # and push to GHCR
```

Three stages: the client is compiled to WebAssembly, the server binary is built with a statically
linked Swift runtime, and the runtime image carries neither toolchain. It comes out around 524MB
and runs as a non-root user.

**Build on the right architecture.** This host is x86_64; a Mac is arm64. An image built on a Mac
will not run here. The image the server pulls comes from CI, which runs on x86_64 — `make image`
locally is for testing on that machine only.

The WebAssembly SDK is close to a gigabyte and sits in its own stage, so it is refetched only when
the client changes. It is fetched with `curl --retry` rather than by `swift sdk install`, whose
downloader gives up after a minute without retrying — enough under Docker, but it failed every time
under Apple's `container`, whose VM networking is slower.

## Health

`GET /health` needs no authentication and touches no database, which makes it usable as a container
health check without granting anything.
