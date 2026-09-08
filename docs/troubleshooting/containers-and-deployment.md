# Containers and deployment

## Apple `container` cannot build this image

**Symptom.** `container build` on the Mac runs for an hour on the Swift compile and never finishes.

**Cause.** `container` 1.3.1 resets its builder VM to 2 CPU and 2 GB at the start of every build,
discarding whatever `container builder start --cpus --memory` was given. Verified by watching
`containers/buildkit/config.json` revert seconds after a build begins.

**Fix.** Build where the image will run. Running containers under `container` is unaffected and
works well — it is only the builder.

```bash
make image-remote        # builds on the Podman host
make image-remote-push
```

## An image built on the Mac will not start on the server

**Symptom.** The container exits immediately on the Podman host.

**Cause.** The Mac is arm64; the Podman VM on Proxmox is x86_64. There is no single image that
serves both, and an early claim in this project that there was, was simply wrong.

**Fix.** As above — build remotely, or in CI on an x86_64 runner. `make image` is for a machine that
can use it.

## A Quadlet unit silently fails to generate

**Symptom.** `systemctl --user daemon-reload` produces no unit at all, and no obvious error.

**Cause.** `ExecStartPre` was placed under `[Container]`. The Quadlet generator rejects the whole
unit rather than reporting the offending key.

**Fix.** `ExecStartPre` belongs to `[Service]`. See `deploy/homebudget-swift.container`, which runs
migrations there before the container starts.

When a unit does not appear, check the generator directly rather than guessing:

```bash
/usr/libexec/podman/quadlet -dryrun -user
```

*Hit 2026-09-07.*

## Secrets in the deployment

The environment file is written into the runtime directory (`%t`, tmpfs) by a separate unit rather
than an `ExecStartPre`, so systemd is guaranteed to be able to read it when it starts the container.
`Requires=homebudget-swift-secrets.service`. Only one scoped Infisical credential is on disk; every
other secret is fetched at start and never persisted. See `deploy/provision-secrets.sh`.

## Still unverified

- The Quadlet units have not been exercised from a cold host boot.
- Service worker registration could not be confirmed in the preview browser.
