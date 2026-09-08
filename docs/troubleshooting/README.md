# Troubleshooting log

Problems that cost real time, and what actually fixed them. One file per area. Written so the
symptom is findable — that is what you will search for at the point you need this.

| Area | What is in it |
| --- | --- |
| [build-and-toolchains.md](build-and-toolchains.md) | Two Swift toolchains, the SMB share, XcodeGen, index store |
| [swift-wasm.md](swift-wasm.md) | WebAssembly client: framework choice, Foundation, bundle size |
| [ios-simulator.md](ios-simulator.md) | Driving the simulator, launch arguments, trust store, screen coordinates |
| [internal-ca-and-tls.md](internal-ca-and-tls.md) | The OfficeLab CA, and why iOS rejects the wildcard certificate |
| [eventkit.md](eventkit.md) | Reminders and Calendar export: dates, alarms, permission levels |
| [containers-and-deployment.md](containers-and-deployment.md) | Apple `container`, Podman Quadlets, image architecture |
| [secrets.md](secrets.md) | Leaks, rotation, history rewriting, Infisical |
| [ui.md](ui.md) | Web typography and Swift Charts axis behaviour |
| [database.md](database.md) | PostgreSQL encoding, migration from PocketBase, client tooling |

## Format

Each entry:

```markdown
## Short statement of the symptom

**Symptom.** What you see, in the words you would search for.

**Cause.** What was actually happening.

**Fix.** What to do. Commands, not prose, where a command will do.

*Hit YYYY-MM-DD.*
```

Symptom first, because that is the only part you know when you arrive. If a problem is still open,
say so in the entry rather than leaving it out.
