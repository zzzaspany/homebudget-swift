# The WebAssembly client

## Tokamak is not an option

**Symptom.** The obvious choice for a SwiftUI-shaped web UI does not build against a current
toolchain.

**Cause.** [Tokamak](https://github.com/TokamakUI/Tokamak) was archived in January 2026 and targets
Swift 5.6.

**Fix.** Plain JavaScriptKit with a small hand-rolled render layer. The Phase 0 spike — one real
modal and one filterable list — was the deciding test, and it is worth keeping that habit: prove the
framework on the hardest screen before committing a phase to it.

## The bundle went from 9 MB to 60 MB

**Symptom.** Adding `import Foundation` to get `JSONDecoder` sextupled the release bundle.

**Cause.** Foundation under WebAssembly pulls in ICU and a great deal else. There is no tree-shaking
that rescues it.

**Fix.** No Foundation in `WebClient` or in `HomeBudgetCore`. JSON is parsed by the browser and
mapped onto `Codable` types with JavaScriptKit's `JSValueDecoder`. Calendar arithmetic and number
formatting are hand-written in `HomeBudgetCore` for the same reason — which incidentally matches
what the old JavaScript did, since it hand-formatted rather than using `Intl`.

Result: 12 MB, 2.3 MB over brotli.

This constraint is load-bearing. Anything added to `HomeBudgetCore` has to respect it, or the web
client's bundle regresses without anyone noticing until deployment.
