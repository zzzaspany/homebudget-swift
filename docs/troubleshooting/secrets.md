# Secrets

This repository is public. The rules are in [AGENTS.md](https://github.com/zzzaspany/homebudget-swift/blob/main/AGENTS.md); this file is what went
wrong.

## The container stayed down for days because the secret fetch lost a race with DNS

**Symptom.** `homebudget-swift.service` inactive, `homebudget-swift-secrets.service` failed with
`curl: (6) Could not resolve host`. It had worked for days, then failed at every boot afterwards.
Nothing alerted, so it was found only when someone looked.

**Cause.** The unit starts before the resolver is reachable. It already declares
`After=network-online.target` and `Wants=network-online.target`, which reads as correct — but this
is a **user** unit, and in the user manager that target is not wired to anything that waits for the
network. The ordering is honoured and means nothing. `RemainAfterExit=yes` with no `Restart=`
then makes the failure permanent until the next boot.

**Fix.** `provision-secrets.sh` now waits for the Infisical host to resolve before its first
request, retrying for up to a minute, and passes `--retry --retry-connrefused` to both curl calls.
Do not trust `network-online.target` in a user unit; wait for the thing you actually need.

*Hit 2026-10-22, after the service had been failing since 2026-10-15.*

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

## Infisical

All credentials live there. Deployments fetch them into tmpfs at start.

**A session token pasted into a conversation is a live credential.** One was, on 2026-09-08, valid
until 2026-09-17 — it needs revoking. Prefer a scoped machine identity over a session token for
anything an agent will use.

**Infisical serves a stale frontend after an upgrade.** The symptom is a white page at
`https://vault.example.lab` with no error. The cause is the runit-supervised process continuing to
serve a frontend it loaded into memory before the upgrade; a restart of the service fixes it. That
belongs in `office-podman-services`, not here.
