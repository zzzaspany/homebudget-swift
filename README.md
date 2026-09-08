# HomeBudget (Swift)

Swift rewrite of [homebudget-python](../homebudget-python): household expense tracking with sinking
funds, category budgets and bilingual (PL/EN) reports. A Vapor web app first, a native SwiftUI
iOS/iPadOS app after that.

## Why a rewrite

The Python app works, but Apple's Liquid Glass material is only reachable from native SwiftUI/UIKit —
no browser API exposes it. Getting there means a native app, and a native app is best served by a
Swift stack it can share domain code with.

## Layout

| Package | What it is | Runs on |
| --- | --- | --- |
| `Packages/HomeBudgetCore` | Domain logic, aggregation and translations. Pure Swift, Foundation-only. | everywhere |
| `Packages/Server` | Vapor API + Fluent/PostgreSQL, serves the web client. | Linux (container) |
| `Packages/WebClient` | Web UI compiled to WebAssembly. | browser |

Each package builds independently — a WebAssembly target cannot link Vapor's dependencies, so they
deliberately do not share one manifest.

The iOS app will be added later as a fourth package, reusing `HomeBudgetCore` unchanged.

## Working on it

`make` on its own lists every target. The ones you need most:

```bash
make doctor   # check the toolchains, runtime and database this project expects
make build    # all three packages
make test     # every suite
make run      # serve on http://localhost:8000, reading .env
make docs     # build the HomeBudgetCore reference with DocC
make image    # build the container image
```

There is no Xcode project, and none is needed — open a package directly:

```bash
open Packages/Server/Package.swift
```

`WebClient` is the exception: Xcode cannot build it, because Apple's clang has no WebAssembly
target and JavaScriptKit has a C target. Use `make web`.

### Toolchains

Two, for different targets. `make doctor` reports on both.

| Target | Toolchain | Why |
| --- | --- | --- |
| macOS build and tests | Xcode | XCTest and Swift Testing do not ship with the Command Line Tools |
| WebAssembly | swift.org toolchain plus `swift sdk install …_wasm` | Apple's clang has no WebAssembly backend |

The Makefile points `DEVELOPER_DIR` at Xcode, so no `sudo xcode-select --switch` is needed, and
unsets it for the WebAssembly build.

Every target passes `--disable-index-store` and keeps its build directory under
`~/Library/Caches/homebudget-swift`, because this repository lives on an SMB share where the
indexer's writes fail on rename and checkouts crawl. A clone on local disk needs neither.

### Container runtime

Apple's [`container`](https://github.com/apple/container) runs OCI images natively on Apple
silicon, each in its own lightweight VM:

```bash
brew install container && container system start
```

**Build images elsewhere.** Two reasons, both discovered the hard way:

Architecture. A Mac is arm64; the Podman host that runs this is x86_64. An image built on the Mac
will not start there.

And `container` 1.3.1 cannot build this image at all. Its builder VM resets to 2 CPU and 2 GB on
every build, discarding whatever `container builder start --cpus --memory` was given — verified by
watching the setting revert in `containers/buildkit/config.json` seconds after a build begins. The
Swift compile ran an hour on 2 GB without finishing. Running containers is unaffected and works
well.

So images are built where they will run:

```bash
make image-remote        # on the Podman host, natively x86_64
make image-remote-push   # and push to GHCR
```

CI does the same on an x86_64 runner. `make image` builds locally, for a machine that can.

## Running locally

Copy `.env.example` to `.env` and point `DATABASE_URL` at a PostgreSQL instance. `DEV_MODE=true`
substitutes a local user, so no reverse proxy is required.

```bash
make migrate
make run
```

One thing worth copying if you set this up yourself: create the cluster with a UTF-8 encoding and
a collation matching your language. A default Debian install produces a `SQL_ASCII` cluster, which
stores accented text but sorts and compares it wrongly, and breaks `upper`/`lower` on any accented
letter. The setting only applies when the data directory is first initialised.

Give the database its own hostname resolving straight to it. It speaks raw TCP, so an HTTP reverse
proxy has nothing to contribute.

Credentials live in `.env`, which is never committed, and in a secret manager for deployments.

## Web client

Plain Swift compiled to WebAssembly, talking to the DOM through JavaScriptKit.
[Tokamak](https://github.com/TokamakUI/Tokamak) — the SwiftUI-shaped framework that would have been
the closer fit — was archived in January 2026 and targets Swift 5.6, so it was ruled out.

Two constraints shaped the result. Foundation stays out of the client: importing it for
`JSONDecoder` took the binary from 9 MB to 60 MB, so JSON is parsed by the browser and mapped onto
`Codable` types by JavaScriptKit's `JSValueDecoder`. And `HomeBudgetCore` avoids Foundation for the
same reason, which is why it carries its own calendar arithmetic and number formatting rather than
leaning on `Calendar` and `NumberFormatter`. The release bundle is 12 MB, 2.3 MB over brotli.

Charts are SVG built in Swift, and the month calendar's layout lives in `HomeBudgetCore` so the iOS
app can reuse it.

## Documentation

The domain module carries a DocC reference — Apple's own documentation compiler, which reads the
doc comments and the catalog under
`Packages/HomeBudgetCore/Sources/HomeBudgetCore/HomeBudgetCore.docc` and produces a browsable
reference with the business rules written up as an article beside the symbols.

```bash
make docs        # build the archive
make docs-open   # and open it in Xcode
make docs-html   # export a static site, for serving anywhere
```

It is driven through `xcodebuild docbuild` rather than swift-docc-plugin so that
`HomeBudgetCore`'s manifest gains no dependency — that manifest is resolved by the WebAssembly
build too, where a documentation plugin has no business being.

## Reports

CSV is generated in `HomeBudgetCore`. PDF is written by hand in `Packages/Server/Sources/App/PDF`:
the fourteen standard PDF fonts are Latin-1, so Polish text needs an embedded font, which in turn
needs enough TrueType parsing to read glyph metrics and the character map. DejaVu Sans is vendored
under `Packages/Server/Resources/Fonts` (Bitstream Vera licence, which permits embedding).

## Status

- [x] Phase 1 — domain logic (status, proration, projections, price history, i18n) + tests
- [x] Phase 2 — Vapor API + PostgreSQL
- [x] Phase 3 — web client: dashboard, charts, calendar, dialogs, invoice attachments
- [x] Phase 4 — CSV and PDF reports, e-mail alerts
- [x] Phase 5 — container image, Quadlet units, CI
- [ ] Phase 6 — native iOS/iPadOS app: feature parity with the web client apart from invoice
      attachments, plus Reminders/Calendar export and a home-screen widget

Feature parity with the Python app is reached. See [docs/deployment.md](docs/deployment.md) for
running it, [AGENTS.md](AGENTS.md) for the conventions this repository holds to, and
[docs/troubleshooting/](docs/troubleshooting/) for problems already hit and what fixed them.

## Deliberate differences from the Python app

Both are bug fixes agreed before the rewrite started, not redesigns:

1. **Biweekly expenses count towards the budget.** The Python app included them in the category chart
   but left them out of `pro_rated_monthly` and `sinking_fund_total`, so a fortnightly bill vanished
   from the monthly figure. They are now prorated at `amount × 26 ÷ 12` like every other cycle.
2. **Marking a non-monthly bill as paid actually registers.** The Python pay endpoint stamped a bare
   year (`"2026"`) on every non-monthly expense, while its status check compared against `"2026-10"`
   for quarterly bills — so the bill never read as paid. Payments now stamp the period in the format
   the status check expects, for every frequency.
