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

## Machine callers

`API_TOKENS` holds comma-separated `name:secret` pairs and grants **read-only** access without an
Authelia session, for shortcuts and automations. Unset means no machine can call the API, which is
the default. Secrets go in Infisical with the rest. See [api.md](api.md), which also sets out what
the token does not protect against — the app publishes port 8000 on the lab network, and a request
that reaches it directly can set its own identity headers and write.

## Daily payment push (ntfy)

Every morning the server publishes a single notification listing the bills that are unpaid and due
within five days, overdue ones included. If nothing is due it sends nothing — a notification that
arrives every day saying all is well is one you stop reading, and the morning it matters you will
not read it either.

| Variable | Meaning | Default |
| --- | --- | --- |
| `NTFY_URL` | Full URL of the ntfy server to publish to | — (unset turns the push off) |
| `NTFY_TOPIC` | Topic to publish on | — (unset turns the push off) |
| `NTFY_USER` / `NTFY_PASSWORD` | Basic auth for a publish-capable ntfy user | none |
| `NTFY_DUE_WINDOW_DAYS` | How many days ahead counts as due | `5` |
| `NTFY_DIGEST_HOUR` / `NTFY_DIGEST_MINUTE` | Local time to publish at | `08:00` |
| `NTFY_LANG` | `pl` or `en` | `pl` |

Leaving `NTFY_URL` or `NTFY_TOPIC` empty disables the feature rather than failing the boot, the
same rule `API_TOKENS` follows.

### What to set in this lab

ntfy already runs on the same Podman host as this app, so the push never leaves the machine.
These go into Infisical (project **Podman Services**, environment **`homebudget-prd`**) like every
other secret — `provision-secrets.sh` writes them into the runtime env file at boot, and nothing
lands on disk.

```
NTFY_URL=http://host.containers.internal:8095/
NTFY_TOPIC=lab-alerts
NTFY_USER=labalerts
NTFY_PASSWORD=<the ntfy publisher password, already in the ntfy-prd environment>
```

`host.containers.internal` rather than an address: from inside a rootless container `127.0.0.1` is
the container itself, and the host's own LAN address (`192.0.2.10:8095`) is **not** reachable —
verified, it times out. `host.containers.internal` resolves and answers.

Going straight to the container also keeps Cloudflare out of the path, which matters: the tunnel in
front of `apns.whoami.com.pl` blocks unrecognised User-Agents, which is what broke the lab agent's
notifications once already. Publishing locally still reaches the phone, because the ntfy server
forwards upstream to ntfy.sh itself.

**Topic.** `lab-alerts` is the phone's existing subscription, so this works with nothing to set up,
at the cost of mixing bills in with infrastructure alerts. To separate them, grant the publisher a
topic of its own and subscribe to it on the phone:

```bash
podman exec ntfy ntfy access labalerts homebudget rw
```

then set `NTFY_TOPIC=homebudget`. The `labalerts` user currently has read-write on `lab-alerts`
and nothing else, so changing the topic without that grant would make every push fail with 403.

After changing anything in Infisical, the secrets unit has to re-run — the env file is built once
at boot:

```bash
systemctl --user restart homebudget-swift-secrets.service homebudget-swift.service
```

The window is deliberately one flat number rather than the per-frequency `dueSoonThresholdDays`
the dashboard colours by. The dashboard answers "is this bill in trouble"; the push answers "what
do I owe this week", and one answer per bill is enough.

Overdue bills raise the ntfy priority to 5 and add a siren tag, so the phone treats a missed
payment differently from one due on Friday.

To prove the wiring without waiting for tomorrow morning:

```bash
curl -X POST 'http://localhost:8000/api/notifications/send-push?lang=pl'
```

That runs exactly what the schedule runs. It reports `alert_count: 0` and sends nothing when
nothing is due, which is a pass, not a failure. Note this is a `POST`, so an `API_TOKENS` token
cannot call it — those are read-only by design.

Scheduling is in-process: each run schedules only the next one, so a restart part-way through the
day does not replay a push that already went out. There is no cron entry and no systemd timer to
keep in step.
