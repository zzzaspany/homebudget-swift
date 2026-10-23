# Secrets

This repository is public. The rules are in [AGENTS.md](https://github.com/zzzaspany/homebudget-swift/blob/main/AGENTS.md); this file is what went
wrong.

## The container stayed down for a week because the internal domain stopped resolving

**Symptom.** `homebudget-swift.service` inactive, `homebudget-swift-secrets.service` failed with
`curl: (6) Could not resolve host`. It had worked, then failed at every boot afterwards. Nothing
alerted, so it was found only when someone looked.

**Cause.** Not a slow boot, which is what the boot-time failures suggested and what the first
attempt at this entry claimed. The name did not resolve *at all* — `getent hosts` and `curl` both
failed days after boot, while public names resolved fine. `resolvectl status` showed why: a
**global** DNS server statically configured in `/etc/systemd/resolved.conf`, pointing at the
resolver's address from before the network was renumbered, together with `Domains=<internal domain>`.
That routes every query for the internal domain to a dead server, while everything else falls
through to the per-link servers DHCP supplies correctly. Public names worked, internal names did
not, and the split made it look like a service problem rather than a host one.

**Fix.** Drop the static global entry and let DHCP's per-link configuration apply. When a host
resolves public names but not internal ones, read `resolvectl status` rather than `/etc/resolv.conf`:
the stub resolver lists global and per-link servers separately, and a stale global entry wins.

`provision-secrets.sh` also now waits for the host to resolve before its first request, so the
failure names the cause instead of surfacing as a connection error. The wait is a diagnostic, not
the fix — it cannot help when resolution is broken rather than late. Keep its budget well inside the
unit's `TimeoutStartSec`: written first as 30 attempts of 2s against a 60s timeout, it consumed the
whole allowance and systemd killed the script before it did any work, reporting a timeout and hiding
the real error.

*Hit 2026-10-22; the service had been failing since 2026-10-15, the first boot after the renumbering.*

## A password was echoed into the terminal

**Symptom.** A generated database password appeared in command output.

**Cause.** The password contained `$`, and the command was built as a double-quoted shell string
passed over SSH. The shell expanded `$` — to the shell's PID — which both corrupted the password and
broke the quoting so the remainder was echoed.

**Fix.** The exposed password was discarded and a new one generated, written to a local SQL file and
applied from the file rather than interpolated into a command line. Never put a secret inside a
double-quoted shell string; never construct one inline for SSH.

*Hit 2026-09-07.*

## An Authelia session secret was leaked by dumping a config section

**Symptom.** A configuration section printed to inspect one setting included the session secret.

**Cause.** The whole section was dumped unfiltered.

**Fix.** Grep for the key you want; never print a configuration block whole. `session.secret` needs
rotating — **still outstanding**, and rotating it invalidates every active session.

*Hit 2026-09-07. Open.*

## Publishing the repository

Before the first push, both the working tree and the full history were scanned with gitleaks and
trufflehog. Internal topology — hostnames and addresses that map the private network — was removed
from history with `git filter-repo` (`--replace-text` for blob contents, `--replace-message` for
commit messages).

Order matters: rotate the credential first, rewrite history second. A rewritten history does not
un-leak a credential that is still live, and anyone who cloned in between still has it.

## The AppRole could not be scoped below the project, so the store changed

**Symptom.** Not a failure — a limit. Infisical would not let a machine identity read one folder and
not another, so this deployment's on-disk credential could read every secret in its project: 74 of
them, including infrastructure API tokens and host SSH keys. Its own comment claimed it was "scoped
to read one environment". It was not.

**Cause.** Scoping below the project is a paid feature there. Custom roles with a `secretPath`
condition, identity additional privileges and folder-level access controls were each tried against
the instance and each refused, the first with *"Upgrade to Infisical Enterprise plan"*.

**Fix.** Moved to OpenBao, where a policy per consumer is free. This deployment's AppRole reads three
paths and is refused with a 403 on everything else — tested by logging in and watching it refuse,
including on the other services' paths on this same host. The credential now reaches 12 secrets
rather than 74.

*Hit 2026-10-22.*

## Infisical

All credentials live there. Deployments fetch them into tmpfs at start.

**A session token pasted into a conversation is a live credential.** One was, on 2026-09-08, valid
until 2026-09-17 — it needs revoking. Prefer a scoped machine identity over a session token for
anything an agent will use.

**Infisical serves a stale frontend after an upgrade.** The symptom is a white page at
`https://vault.example.lab` with no error. The cause is the runit-supervised process continuing to
serve a frontend it loaded into memory before the upgrade; a restart of the service fixes it. That
belongs in `office-podman-services`, not here.
