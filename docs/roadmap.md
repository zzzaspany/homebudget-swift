# What is worth doing next

Written after the rewrite reached parity, from the state of the code rather than from a wish list.
Ordered by what would actually hurt if left alone, not by what is fun.

## Known gaps, smallest first

**Invoice attachment on iOS.** The one feature the web client has and the app does not. The server
side is done and in use; this is client work only. Tracked as
[#3](https://github.com/zzzaspany/homebudget-swift/issues/3).

~~**The iOS app is not built in CI.**~~ Done — the `ios` job on a free macOS runner builds the app
and the widget on every pull request. See [ci.md](ci.md).

**The Quadlet units have never been exercised from a cold boot.** They work when started by hand.
Whether the machine comes back correctly after a power cut is untested, and that is exactly when you
find out. A scheduled reboot of the Podman VM, watched, would settle it.

**Service worker registration is unverified.** The PWA assets are served and the tests check they
exist, but nobody has confirmed a browser actually registers the worker.

## Things that will bite on a date

**The wildcard certificate expires 10 October 2027.** An earlier draft of this file claimed nothing
would remind anyone. That was wrong, and checking took two minutes: Uptime Kuma already has
`tlsExpiryNotifyDays = [7,14,21]`, an active default notification channel, and currently reports 396
days remaining on the `office.lab` wildcard. The warning will arrive.

What is *not* covered: **`rachunki.office.lab` has no monitor at all**, and five monitors — including
**Authelia**, whose failure takes every other service with it — have no notification attached, so
their alerts go nowhere. Both are worth fixing in the Kuma UI; a new monitor picks up the
notification automatically because the channel is marked default.

A monitor on HomeBudget should point at `http://192.168.0.182:8000/health` rather than the public
URL. Everything on `office.lab` sits behind Authelia, so `https://rachunki.office.lab/` answers 200
whenever *Authelia* is healthy — it would stay green with the app dead behind it.

The reissue itself is one script; see `office-proxmox-server/08-officelab-ca.md`.

**Authelia's `session.secret` is known to have been exposed** in a terminal on 2026-09-07 and was
deliberately not rotated — the value never left the machine or the lab, and rotation invalidates
every active session. Recorded here so it is a decision on the record rather than an oversight
somebody rediscovers. See [troubleshooting/secrets.md](troubleshooting/secrets.md).

**`homebudget-python/pb_client.py` carries a password in the source.** Harmless while that
repository stays private. It stops being harmless the moment it does not.

## Worth building, in rough order of value

### Read payments back from Reminders automatically

The read-back exists but is a button. It could run when the app comes to the foreground, which is
what would make the Reminders integration feel like it belongs rather than like a feature you have
to remember to use. The high-water-mark logic is already there and already careful about the
"completed is a moment, not a state" problem.

### ~~Notifications that do not depend on opening the app~~ — done

Local notifications, scheduled on every dashboard refresh alongside the widget snapshot. Local
rather than push: the schedule is known days ahead and needs no server, where push would mean APNs
certificates, a device-token store and a sender in the Vapor app to deliver something the phone can
work out for itself.

### An iPad-shaped layout

The app is `1,2` in `TARGETED_DEVICE_FAMILY` and runs on iPad, but only the KPI grid adapts. A
`NavigationSplitView` with the expense list beside the detail would use the space properly. Modest
work, and the domain is already free of assumptions about screen size.

### Variable bills could predict better

`PriceHistory` computes the drift between first and latest payment. For a bill that swings
seasonally — gas, electricity — the average of the same month last year is a much better suggestion
than the last payment, which is what the pay sheet offers now. That is a `HomeBudgetCore` change
with a clear test, and it would improve both clients at once.

### Multi-household, or at least multi-user

Everything assumes one household and trusts whoever Authelia lets through. `paid_by` is recorded but
never used to separate anything. If a second person ever needs their own view, that assumption is
load-bearing in the schema, and it is much cheaper to face before there is data to migrate.

## Deliberately not doing

**Publishing to the App Store.** Reviewers cannot reach a server behind a VPN and an internal CA, so
it would be rejected, correctly. See [releasing-and-costs.md](releasing-and-costs.md).

**fastlane.** It earns its keep on code signing across machines, store metadata and screenshots.
None of those apply while the app is signed on one Mac and sold nowhere. Add it when builds start
going to TestFlight, not before.

**A test target for `HomeBudgetiOS`.** The rules worth testing were moved into `HomeBudgetCore`
where they are tested — recurrence intervals, upcoming selection, category budgets. What is left in
the app target is view code, and a test target with nothing but snapshot tests in it is a
maintenance cost pretending to be coverage.

**Retiring `homebudget-python`.** It still runs, and it is the only thing that can be compared
against when a figure looks wrong. It costs a container. Keep it until a full year has passed with
the Swift app in daily use.
