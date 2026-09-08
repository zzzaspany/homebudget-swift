# Changelog

Notable changes to HomeBudget. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The version lives in [VERSION](VERSION), which is the single source of truth. `make release
VERSION=x.y.z` bumps it, checks there is a section here for it, and tags — see
[AGENTS.md](AGENTS.md#releases).

What "breaking" means for a project with one deployment: a change that needs a migration run by
hand, a change to the API the web and iOS clients share, or a change that needs configuration
updating before the container will start.

## [Unreleased]

## [1.0.0] — 2026-09-08

The Swift rewrite of `homebudget-python`, at parity with it on the web and ahead of it on the phone.

### Added

- **Domain core** (`HomeBudgetCore`) shared unchanged by the server, the web client and the iOS app:
  status calculation, proration, projections, price history, sinking funds and bilingual labels. It
  imports no Foundation, which is what keeps the WebAssembly bundle at 12 MB rather than 60.
- **Vapor API over PostgreSQL**, with Authelia identity taken from reverse-proxy headers — the same
  trust model the Python app used, reimplemented rather than redesigned.
- **Web client compiled to WebAssembly**: dashboard, hand-drawn SVG charts, month calendar, expense
  and payment dialogs, invoice attachments.
- **Reports written in Swift**: bilingual CSV, and a PDF produced by a hand-written writer with an
  embedded TrueType font, because the fourteen standard PDF fonts cannot render Polish.
- **Payment reminders over SMTP**, from a hand-rolled NIO client.
- **Native iOS and iPadOS app**: expenses with search, filters and full editing; charts; calendar;
  price history; reserves; per-category ceilings; CSV and PDF export; and Liquid Glass, which is the
  reason the rewrite happened at all.
- **Home-screen widget** showing the next bills due and the days left, fed by a snapshot the app
  leaves in a shared app group rather than by the widget calling the API.
- **Reminders and Calendar export**, including reading ticked-off reminders back as payments.
- **Local notifications** warning a bill's own `dueSoonThresholdDays` ahead of its due date.
- **Deployment**: multi-stage container image, rootless Podman Quadlets, and secrets fetched from
  Infisical into tmpfs at start rather than kept on disk.

### Changed — deliberate differences from the Python app

Both are bug fixes agreed before the rewrite began. Figures will not match the old app here.

- **Fortnightly bills count towards the budget.** The Python app included them in the category chart
  but left them out of `pro_rated_monthly` and `sinking_fund_total`, so a fortnightly bill vanished
  from the headline figure while still appearing in the chart beneath it.
- **Marking a non-monthly bill as paid registers.** The old pay endpoint stamped a bare year on
  every non-monthly expense while its status check compared quarterly bills against a
  year-and-month key. The two never matched, so a quarterly bill could not be marked paid at all.

### Fixed

- The web client's type scale, which resolved `rem` against `html` while the size was set on `body`,
  leaving every label at 16 px.
- The price chart's Y axis, forced to zero by `AreaMark`, which flattened the trend the chart exists
  to show.
- A reminder's due date, which Reminders was taking from the attached alarm — putting every bill
  `dueSoonThresholdDays` early and anchoring its recurrence on the wrong day of the month.

### Infrastructure

- The `office.lab` wildcard certificate was reissued for 397 days under a new root
  (`OfficeLab Root CA 2026`). iOS rejects any TLS certificate valid for more than 398 days, even
  from a user-installed root, so the previous ten-year certificate made the app unusable on a phone.
  Recorded in `office-proxmox-server/08-officelab-ca.md`.

[Unreleased]: https://github.com/zzzaspany/homebudget-swift/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/zzzaspany/homebudget-swift/releases/tag/v1.0.0
