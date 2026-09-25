# HomeBudget (Swift)

A household budget application, rewritten from Python in Swift: [Vapor](https://vapor.codes) on the
server, the same domain code compiled to WebAssembly in the browser, and a native iOS client sharing
it again.

One package holds the domain logic and all three clients use it, which is the point of the rewrite —
a due-date rule or a currency calculation exists once.

## Where to start

<div class="grid cards" markdown>

- **[Deployment](deployment.md)** — how the container is built, where secrets come from, what runs
  where.
- **[Continuous integration](ci.md)** — what runs on a pull request and why Swift analysis is not
  one of those things every time.
- **[API](api.md)** — calling the server from a script rather than a browser.
- **[Roadmap](roadmap.md)** — what is worth doing next, and what deliberately is not.

</div>

## Troubleshooting

The [troubleshooting log](troubleshooting/README.md) is the part worth reading before you need it.
It is not a FAQ: each entry is a failure that actually happened here, with the symptom that led to
it and the reason it was not what it looked like. A few that cost the most time:

- [The internal CA and TLS](troubleshooting/internal-ca-and-tls.md) — why iOS rejected a
  certificate that macOS accepted, and why the server image carries a root CA.
- [PostgreSQL](troubleshooting/database.md) — why `sslmode=require` is not what `libpq` means by it,
  and what that does to a connection.
- [The WebAssembly client](troubleshooting/swift-wasm.md) — the toolchain coupling that breaks the
  image build when only one version moves.

!!! note "This documents one particular installation"

    The examples name real hosts on a private network — `postgres.office.lab`, addresses in
    `192.168.0.0/24`. They are here because a runbook with the names filed off is a runbook nobody
    can follow. None of it is reachable from the internet.
