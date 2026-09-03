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

## Building and testing

```bash
make build   # both packages
make test    # both test suites
make run     # start the API on http://localhost:8000
```

The Makefile exists because this repository lives on the SMB-mounted `/Volumes/Multimedia` share,
which Swift tooling handles badly: the indexer's record writes fail on rename (`failed to rename …
File exists`), and dependency checkouts crawl. Every target therefore passes `--disable-index-store`
and keeps its build directory in `~/Library/Caches/homebudget-swift`. A clone on local disk can drop
both and use plain `swift build` / `swift test`.

### Toolchains

Two are needed, for different targets:

| Target | Toolchain | Why |
| --- | --- | --- |
| macOS build + tests | Xcode | XCTest and Swift Testing do not ship with the Command Line Tools |
| WebAssembly | swift.org toolchain + `swift sdk install …_wasm` | Apple's clang has no WebAssembly target, so JavaScriptKit's C target cannot build under Xcode's toolchain |

The Makefile points `DEVELOPER_DIR` at Xcode so no `sudo xcode-select --switch` is needed.

## Running locally

Copy `.env.example` to `.env` and point `DATABASE_URL` at a PostgreSQL instance. `DEV_MODE=true`
substitutes a local user, so no reverse proxy is required.

```bash
cd Packages/Server && swift run App migrate --yes
make run
```

The homelab instance is `db-host` — Proxmox container 120 (`db-host`,
PostgreSQL 17). Its cluster was recreated with `pl_PL.UTF-8`, because Debian's default install
produced a `SQL_ASCII` cluster, which breaks sorting and comparison of Polish text.

That hostname resolves straight to the container, unlike the rest of `*.example.lab`, which a
Pi-hole wildcard sends to Nginx Proxy Manager. A database speaks raw TCP, so an HTTP reverse proxy
has nothing to contribute; the more specific `98-homebudget.conf` record wins over the wildcard.
Connections currently run without TLS, matching every other internal service here.

Credentials live in `.env`, which is never committed.

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
- [ ] Phase 6 — native iOS/iPadOS app

Feature parity with the Python app is reached. See [docs/deployment.md](docs/deployment.md) for
running it.

## Deliberate differences from the Python app

Both are bug fixes agreed before the rewrite started, not redesigns:

1. **Biweekly expenses count towards the budget.** The Python app included them in the category chart
   but left them out of `pro_rated_monthly` and `sinking_fund_total`, so a fortnightly bill vanished
   from the monthly figure. They are now prorated at `amount × 26 ÷ 12` like every other cycle.
2. **Marking a non-monthly bill as paid actually registers.** The Python pay endpoint stamped a bare
   year (`"2026"`) on every non-monthly expense, while its status check compared against `"2026-10"`
   for quarterly bills — so the bill never read as paid. Payments now stamp the period in the format
   the status check expects, for every frequency.
