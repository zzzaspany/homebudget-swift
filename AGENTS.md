# Working rules for this repository

Conventions an agent (or a person) has to know before changing anything here. Narrative context —
why the project exists, what each package does — is in [README.md](README.md). Problems already hit
and how they were solved are in [docs/troubleshooting/](docs/troubleshooting/); read the index there
before debugging something that smells familiar. What is worth building next, and what has been
deliberately ruled out, is in [docs/roadmap.md](docs/roadmap.md) — check it before proposing
something that was already considered and rejected.

## Writing things down

Three places, and they do not overlap:

| Where | What goes in it |
| --- | --- |
| `README.md` | What the project is and how to run it. Written for someone who has never seen it. |
| `AGENTS.md` (this file) | Rules and conventions. Short, imperative, no war stories. |
| `docs/troubleshooting/*.md` | One file per area. Every problem that cost more than a few minutes: symptom, cause, fix, date. |
| `HomeBudgetCore.docc` | The API reference, built by DocC from doc comments plus the catalog's articles. What a type *is*, not how the project is run. |
| `docs/roadmap.md` | What is worth building next, and what has been ruled out and why. |
| `docs/ci.md` | Research with a date on it. Re-check the numbers before acting on them. |

**Every non-obvious problem gets an entry the same session it is solved.** A fix nobody can find
again is worth about as much as no fix. Keep the format in
[docs/troubleshooting/README.md](docs/troubleshooting/README.md): symptom first — that is what the
next person searches for — then cause, then fix, then the date.

Do not write a troubleshooting entry for something the code already makes obvious, and do not
restate README prose. Link to it instead.

Every public type in `HomeBudgetCore` carries a doc comment — it is the module three front ends
share, so a summary line is the least it owes them. `make docs` must build without DocC warnings;
an unresolved symbol link is a broken reference, not a cosmetic one.

## Code

Comments explain *why*, never *what*. If a line needs a comment to say what it does, rewrite the
line. Match the density and idiom of the surrounding file.

Prose in comments and documentation is British-flavoured English, plain, no exclamation marks and
no marketing. User-facing strings are Polish and English, both in
`HomeBudgetCore/I18n/UIStrings.swift` — never hard-code either one in a view.

`HomeBudgetCore` does not import Foundation. This is not a style preference: importing it for
`JSONDecoder` took the WebAssembly bundle from 9 MB to 60 MB. Calendar arithmetic and number
formatting are hand-written for that reason. Anything added there has to hold to it.

Domain logic goes in `HomeBudgetCore` so the server, the web client and the iOS app share one copy.
A calculation that exists in two of them is a bug waiting to happen — the Python app had three
copies of its translations.

Swift 6 language mode, strict concurrency. Types crossing an isolation boundary are `Sendable` or
they do not cross it.

## Behaviour differences from the Python app

Fixing a latent bug found while porting is preferred over reproducing it — but the deviation must be
stated, in the "Deliberate differences" section of the README and in the commit message. Two exist
so far. Do not add a third silently.

## Tests

`make test` runs everything. A change to date logic, proration, status calculation or period
stamping needs a test case before it is considered done — that is the whole business contract and
it has no other guardrail.

The API suite talks to a real database and reads **`TEST_DATABASE_URL`**, never `DATABASE_URL`.
`.env` points the latter at the live household database, and these tests truncate tables. There is
no fallback and there must not be one; unset, the suite reports as skipped.

Tests must not depend on process-wide mutable state. `DEV_MODE` is read from `Application` storage
rather than the environment precisely because parallel suites raced on it.

## Verifying

Test the thing the way it actually runs. Two failures in this repository came from not doing that,
and both looked like success at the time:

- A service's `NODE_EXTRA_CA_CERTS` was checked by running `node` from an interactive shell, which
  does not have the service's environment. The check passed; the service was still broken. Read the
  value back from `/proc/<pid>/environ` instead of trusting a command you ran differently.
- A reminder's due date was "verified" by reading the code that set it. The screen showed something
  else entirely, because Reminders treats an alarm as the item's date. Look at the output, not at
  the intent.

**Prefer a controlled experiment to a plausible explanation.** When the wildcard certificate was
rejected by iOS, the log named a reason — but the reason was only established by serving two
certificates that differed in exactly one property and watching one work. If a diagnosis rests on a
single line of output, it is a hypothesis.

**Do not assert a version, price, API behaviour or platform limit from memory.** They move, and a
confidently wrong number is worse than an admitted gap. Look it up, and cite where you looked.

## Build

`make` on its own lists every target. Use it rather than raw `swift build` — the Makefile sets
`DEVELOPER_DIR`, keeps build directories off the SMB share and disables the index store, all of
which this repository needs. See [docs/troubleshooting/build-and-toolchains.md](docs/troubleshooting/build-and-toolchains.md).

Two toolchains, deliberately: Xcode for macOS builds and tests, a swift.org toolchain plus the WASM
SDK for the web client. `make doctor` reports on both.

Container images are built where they will run — the Podman host is x86_64, the Mac is arm64, and
Apple's `container` builder cannot build this image at all. `make image-remote`.

The Xcode project for the iOS app is generated by XcodeGen from
`Packages/HomeBudgetiOS/project.yml` and is **not** committed. Edit the YAML, run `xcodegen`, never
edit the `.xcodeproj`.

## Secrets

This is a public repository. Nothing secret is committed, ever — not in code, not in fixtures, not
in a comment, not in a commit message, and not in an internal hostname or IP that maps the private
network.

Credentials live in Infisical. `.env` is local only and gitignored. Deployments fetch secrets into
tmpfs at start; see `deploy/provision-secrets.sh`.

CI runs gitleaks on every pull request, because this repository is public and a secret that reaches
a commit is a secret that is gone. That is a backstop, not permission to stop thinking: before
pushing anything that touched configuration, run gitleaks over the working tree *and* the
history. If something leaked, the password is rotated first and the history rewritten second — in
that order, because a rewritten history does not un-leak a live credential.

Never echo a secret into a log, a terminal or a commit. When a command needs one, put it in a file
and reference the file. Beware `$` inside double-quoted shell strings: it cost us a password once.

## Infrastructure

The lab's documentation lives in `office-podman-services` and `office-proxmox-server`.
**`office-docs` only aggregates those two — never edit it directly**, edit the source repository and
let the aggregation pick it up.

Log into lab hosts as the ordinary user documented there, never as root.

**Before deleting anything shared, find out who points at it by path.** Refreshing a system trust
store is not the same as satisfying a service that names a specific file in
`NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE` or `--cacert`. Removing the old CA broke Uptime Kuma's
monitors while `curl` in the same container kept working, because the two read different stores.
Sweep the units and env files first; the sweep is in `office-proxmox-server/08-officelab-ca.md`.

Deployment changes to shared infrastructure — the reverse proxy, the wildcard certificate, anything
another service depends on — need the owner's explicit go-ahead, per change. Approval for one is not
approval for the next.

## Releases

`VERSION` at the repository root is the single source of truth. The same number is carried in
`Packages/HomeBudgetiOS/project.yml`, and CI fails the build if the two disagree — or if a `v*` tag
does not match either.

```bash
make version              # what the number is, and everywhere it is recorded
make release NEW=1.1.0    # bump, commit, tag
```

`make release` refuses to run on a dirty tree, and refuses to tag a version that has no section in
`CHANGELOG.md`. It does **not** push. Pushing the tag is what triggers the image build and push to
GHCR, which is the moment a release becomes real — that stays a deliberate act.

Write the changelog entry *before* tagging, not after. An entry written from the diff a week later
records what changed; one written while the work is fresh records why, which is the part worth
having.

Semantic versioning, with "breaking" read for a project that has one deployment: a change needing a
migration run by hand, a change to the API the web and iOS clients share, or a change needing
configuration updated before the container will start.

A running container reports its version at `/health`, so "what is actually deployed" has an answer
that does not involve reading image tags.

## Git

Work on a branch named for the change. Check which branch is checked out before the first commit,
not after the third.

Read a file before overwriting it, including files that look boilerplate. `.gitignore` is a file.

Commit messages say what changed and why, in the imperative. Reference the troubleshooting document
when a commit is the fix for a recorded problem.
