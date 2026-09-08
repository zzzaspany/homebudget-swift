# Driving the iOS simulator

## `simctl keychain add-root-cert` appears to do nothing

**Symptom.** `xcrun simctl keychain <udid> add-root-cert ca.pem` exits 0, but
`data/Library/Keychains/TrustStore.sqlite3` under the device directory is 0 bytes and the certificate
is nowhere to be found. Repeating it, booted or shut down, changes nothing.

**Cause.** Two separate things, and the first hides the second.

The trust store has moved. On iOS 26 runtimes it is at

```
~/Library/Developer/CoreSimulator/Devices/<udid>/data/private/var/protected/trustd/private/TrustStore.sqlite3
```

The old `data/Library/Keychains/TrustStore.sqlite3` path is vestigial; a 0-byte file sitting there is
a leftover, not a failure signal. Hours went into "fixing" an empty file that nothing reads.

And `trustd` caches the store. A certificate added to a booted device is not picked up until the
device restarts.

**Fix.**

```bash
D=<udid>
xcrun simctl shutdown $D && sleep 3 && xcrun simctl boot $D && sleep 8
xcrun simctl keychain $D add-root-cert /path/to/ca.pem
xcrun simctl shutdown $D && sleep 3 && xcrun simctl boot $D
```

Verify against the right file, and compare fingerprints rather than trusting the exit code:

```bash
DB=~/Library/Developer/CoreSimulator/Devices/$D/data/private/var/protected/trustd/private/TrustStore.sqlite3
sqlite3 "$DB" "select hex(sha256) from tsettings;"
openssl x509 -in /path/to/ca.pem -outform der | shasum -a 256
```

The schema is `tsettings(sha256, subj, tset, data, uuid)` — there is no `sha1` column, despite what
most snippets on the internet say.

Installing the certificate as a configuration profile through the simulator's Safari also works
(serve the `.crt` over `python3 -m http.server`, open it, then Settings → Profile Downloaded →
Install, and switch it on under General → About → Certificate Trust Settings). It is slower and it
lands in the same store. Note that trusting the root is necessary but may not be sufficient — see
[internal-ca-and-tls.md](internal-ca-and-tls.md).

*Hit 2026-09-07, understood 2026-09-08.*

## `DEVELOP_MODE` is ignored when launching from the command line

**Symptom.** `xcrun simctl launch booted lab.office.homebudget --DEVELOP_MODE ON` starts the app,
but it asks for a login instead of showing sample data.

**Cause.** `UserDefaults` reads `-key value` pairs from the argument list. One dash. A double dash
is stored under a different key and never read.

**Fix.** Either form works:

```bash
xcrun simctl launch booted lab.office.homebudget -DEVELOP_MODE ON
SIMCTL_CHILD_DEVELOP_MODE=ON xcrun simctl launch booted lab.office.homebudget
```

`-DEVELOP_MODE ON` persists in the app's defaults, so a later plain launch stays in develop mode
until you pass `-DEVELOP_MODE OFF`. That bit us: an app relaunched to test the real login flow was
still showing fixtures.

`DEVELOP_TAB=charts|calendar` and `DEVELOP_SHEET=history` open a screen directly, which saves
tapping through to it. All of it is `#if DEBUG` — a release build cannot be talked into skipping
authentication.

*Hit 2026-09-07.*

## Taps land in the wrong place

**Symptom.** A tap driven from a screenshot hits the row above or below the intended one, or does
nothing at all.

**Cause.** Input coordinates are in **device points** (402 × 874 on an iPhone 17 Pro), while the
screenshot is 1206 × 2622 pixels and is rescaled again before you look at it. Deriving a scale
factor from the rendered image's apparent height is guesswork, and the error grows down the screen —
a factor read off a dialog near the top misses a row near the bottom by tens of points.

**Fix.** Take the true pixel size once and use a single factor for both axes:

```bash
xcrun simctl io <udid> screenshot shot.png && sips -g pixelWidth -g pixelHeight shot.png
```

`points = pixels / 3` on a 3× device. Do not scale x and y independently.

A tap that reports a timeout may still have been delivered — check the screen before repeating it,
or you will act twice.

*Hit 2026-09-08.*

## Which simulator am I actually talking to

`xcrun simctl listapps booted` picks one device when several are booted, and it may not be the one
whose panel is open. Always pass the UDID explicitly:

```bash
xcrun simctl list devices booted
```

*Hit 2026-09-08.*
