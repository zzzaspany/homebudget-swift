# Secrets

This repository is public. The rules are in [AGENTS.md](../../AGENTS.md); this file is what went
wrong.

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
`https://vault.office.lab` with no error. The cause is the runit-supervised process continuing to
serve a frontend it loaded into memory before the upgrade; a restart of the service fixes it. That
belongs in `office-podman-services`, not here.
