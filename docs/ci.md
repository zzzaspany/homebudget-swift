# Continuous integration

What runs today, what does not, and what it would cost to close the gap. Researched September 2026;
prices and free tiers move, so check them before acting on the numbers.

## What runs today

`.github/workflows/build.yml`, four jobs:

| Job | Runner | What it proves |
| --- | --- | --- |
| `secrets` | ubuntu | gitleaks over the pull request's history |
| `test` | ubuntu, `swift:6.3.3-noble` | `HomeBudgetCore` and `Server` suites |
| `web` | ubuntu, `swift:6.3.3-noble` | the client still compiles to WebAssembly |
| `ios` | macos-26 | the iOS app and its widget still compile (~3 min) |
| `image` | ubuntu | builds and pushes the container image on `main` |

The `web` job earns its place for a reason worth stating: it is the only automated check that
`HomeBudgetCore` has not quietly grown a Foundation dependency. A Foundation import compiles fine on
the server and takes the WebAssembly bundle from 9 MB to 60 MB — see
[troubleshooting/swift-wasm.md](troubleshooting/swift-wasm.md).

## The gap that used to exist

Until September 2026 the iOS app and its widget were never built in CI. They compiled on one Mac and
nothing would have caught a break until somebody next opened Xcode — roughly 2 900 lines, the
largest package in the repository, checked by nobody. The `ios` job closes that.

Two decisions in it are worth knowing about. It generates the Xcode project with XcodeGen rather
than expecting one, which also proves `project.yml` still describes a buildable project. And it
builds against `generic/platform=iOS Simulator` rather than a named device, so that a runner image
retiring "iPhone 17 Pro" cannot break the build for a reason unrelated to the change under test.
Simulator builds sign locally, so no certificates go anywhere near CI.

`HomeBudgetiOS` also has no test target. Most of what it does is SwiftUI, but not all: the EventKit
recurrence mapping, the widget snapshot and the reminder read-back are ordinary logic. The rules
already moved into `HomeBudgetCore` where they could (`Frequency.recurrenceInterval`,
`Dashboard.upcoming(limit:)`, `CategoryBudget`) and those have tests. What is left in the app target
is genuinely view-shaped, which is an argument for keeping the split rather than for adding a test
target with nothing to put in it.

## Closing it: what a macOS runner costs

The decisive fact for this repository: **GitHub Actions is free and unmetered on standard hosted
runners for public repositories, macOS included.** `homebudget-swift` is public, so adding a macOS
job costs nothing. `macos-26` is generally available and runs on Apple silicon.

For comparison, if the repository were private:

| Option | Cost | Notes |
| --- | --- | --- |
| GitHub Actions hosted macOS | ~$0.062/min, and macOS drains included minutes at a 10× multiplier | The usual reason iOS CI bills surprise people |
| Xcode Cloud | 25 compute hours a month included with the $99 membership; then $49.99/mo for 100 h | Handles signing itself — no certificates in secrets |
| Self-hosted Mac mini | $700–1 200 up front, ~$20–35/mo amortised over three years | From March 2026 GitHub also meters self-hosted minutes, though public repositories stay free |

## Do we need fastlane?

Probably not yet, and it is worth being clear about why rather than adding it because iOS projects
usually have it.

fastlane earns its keep on three things:

1. **Code signing** — `match` keeps certificates and profiles in a repository and syncs them to
   machines. Real value once more than one machine signs builds.
2. **Store metadata and upload** — `deliver` and `pilot` push builds and metadata to App Store
   Connect and TestFlight.
3. **Screenshots** — `snapshot` drives the simulator across devices and languages.

None of those apply to this project today. It is not on the App Store, it is signed on one machine,
and it has no store listing to feed. For *building and testing*, `xcodebuild` is already enough and
is what the Makefile drives.

**Add fastlane when there is a signing or upload need**, not before — that is, when builds start
going to TestFlight or the App Store from CI. At that point `match` and `pilot` replace a pile of
hand-rolled `security import` and upload steps, and are worth it. Until then it is a Ruby toolchain
and a `Fastfile` to keep current for no gain.

## What is still not covered

`HomeBudgetiOS` is built but not tested, because it has no test target — see the paragraph above for
why that is deliberate rather than an omission.

The `ios` job selects `/Applications/Xcode.app` explicitly and prints the version — **Xcode 26.6
(17F113)** on the image as of September 2026, comfortably new enough for the iOS 26 deployment
target. If the image ever ships one too old, that printed line is where it will be obvious; pinning
with `xcode-select -s /Applications/Xcode_26.x.app` is the fix, at the cost of bumping it by hand.

The job takes about three minutes, which is faster than either Linux Swift job — the macOS runner is
not the bottleneck people expect it to be at this size.

## Sources

- [GitHub Actions pricing changes, 2026](https://github.com/resources/insights/2026-pricing-changes-for-github-actions)
- [macos-26 generally available for GitHub-hosted runners](https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/)
- [25 hours of Xcode Cloud included with the Apple Developer Program](https://developer.apple.com/news/?id=ik9z4ll6)
- [Comparing CI/CD platforms for iOS apps](https://capawesome.io/blog/comparing-ci-cd-platforms-for-ios-apps/)
- [iOS CI/CD cost, 2026](https://cicdcalculator.com/ci-cd-cost-for-ios-apps)
