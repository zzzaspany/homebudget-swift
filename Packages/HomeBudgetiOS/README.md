# HomeBudget for iOS and iPadOS

A native client for the same API the web app uses, sharing `HomeBudgetCore` for the domain logic,
calculations and translations.

## Building

The Xcode project is generated rather than committed, so changes show up as readable diffs in
`project.yml` instead of a churning `.pbxproj`:

```bash
xcodegen generate
open HomeBudget.xcodeproj
```

## Signing in

The server knows one thing about identity: the headers its reverse proxy sets for a request
carrying a valid Authelia session. The app signs in the same way the browser does — a web view
presents Authelia's own login page, and the resulting cookie is copied into the `URLSession` the
app makes its API calls with. `WKWebView` and `URLSession` do not share cookie storage, so that
copy is deliberate.

The alternative would have been a token endpoint for native clients: a second way to authenticate,
with its own expiry rules and its own failure modes, against a server that currently has exactly
one. Authelia answers an expired session with a redirect rather than a 401, so a response arriving
from a different host is what tells the app it has been signed out.

Note that the session expires after an hour and goes inactive after five minutes, so the app will
ask for a sign-in more often than a native token would. Ticking "remember me" at the Authelia
prompt extends it to a month.

## The certificate

The server sits behind an internal certificate authority. A device that does not trust it cannot
sign in — the web view fails with `NSURLErrorServerCertificateUntrusted` — and the app says so, in
terms that name the fix, rather than sitting on a blank page.

On a real device: install the CA through a configuration profile, then enable it under
Settings → General → About → Certificate Trust Settings. iOS keeps user-installed roots untrusted
until that switch is thrown, which is a separate step from installing them.

On a simulator, `xcrun simctl keychain <device> add-root-cert` does work, but the store it writes to
moved and `trustd` caches it, so the device has to be restarted afterwards. The details, and how to
verify the certificate actually landed, are in
[docs/troubleshooting/ios-simulator.md](../../docs/troubleshooting/ios-simulator.md).

Trusting the root is necessary but currently not sufficient. iOS rejects any TLS server certificate
valid for more than 398 days — including one chaining to a user-installed root — and the lab's
wildcard is issued for ten years, so `trustd` fails it with `[leaf OtherTrustValidityPeriod]`.
macOS does not enforce this, which is why the same URL loads fine from a Mac. See
[docs/troubleshooting/internal-ca-and-tls.md](../../docs/troubleshooting/internal-ca-and-tls.md);
the fix is to reissue the leaf, not to change anything here.

## What it does

Four tabs. The dashboard lists the recurring expenses with search and filters, and lets you add,
edit, delete and pay them — the same validation the server applies, so the form does not wait for a
round trip to say the amount is missing. Then charts, a month calendar, and a "More" tab for
everything that is not opened daily: the reserves for non-monthly bills, per-category ceilings,
CSV and PDF reports, the e-mail alerts, and where the server lives.

Category ceilings are stored on the device, not on the server — they are intentions, not facts about
the expenses, and the web client keeps its own in the browser for the same reason. The two can
disagree; that is the accepted cost of not inventing a server-side model for a number one person
picks. The arithmetic behind them lives in `HomeBudgetCore` and has tests.

The one thing the web client has and this does not: attaching an invoice when recording a payment.
Tracked as issue #3.

## The widget

A home-screen tile showing the next bills due and how many days are left. Small shows one, medium
shows three; overdue counts up in red, "due soon" in orange.

It does **not** call the API. A widget runs in its own short-lived process with no Authelia cookie,
so the app writes a small snapshot into a shared app group whenever the dashboard changes, and the
extension reads that. The timeline refreshes just after midnight, because the number of days left is
the only thing that changes on its own and it changes once a day.

Which bills count as upcoming is decided in `HomeBudgetCore` (`Dashboard.upcoming(limit:)`), not in
the widget, so the rule has tests.

## Notifications

A bill warns on the phone as many days ahead as its own cycle's threshold — three for a fortnightly
bill, fourteen for a yearly one, the same numbers the dashboard colours by rather than a second
opinion about what "soon" means.

Local notifications, not push. The schedule is known days in advance and needs no server; push would
mean APNs certificates, a device-token store and a sender in the Vapor app, all to deliver something
the phone can work out from data it already has.

They are rescheduled from scratch on every dashboard refresh rather than diffed — there are at most
a few dozen, and reconciling two sets of pending notifications is more code and more ways to be
wrong. Signing out cancels them: a device without a session should not be announcing bills it can no
longer show. A warning day already past is skipped, because a notification cannot be scheduled into
the past and an overdue bill is already being shouted about by three other things.

Which bills warn, and on what day, is decided in `HomeBudgetCore` (`Dashboard.dueReminders`) and has
tests.

## Reminders and Calendar

The recurring expenses can be mirrored into Apple Reminders, on a list of their own called
HomeBudget — one reminder per active bill, on its real due date, repeating on the expense's own
cycle. A bill is a task: it has a due date and it gets ticked off. Re-running the export updates in
place rather than duplicating, and one menu item removes the lot.

Separately, any single expense can be pushed to the Calendar from its context menu, through Apple's
own event editor. That path needs only write-only calendar access, so the app never sees the diary
it is adding to.

Reminders that have been ticked off can be read back and recorded as payments, from the More tab.
This is what full access to Reminders was taken for. A completed recurring reminder immediately
spawns its next occurrence, so "completed" is a moment rather than a state — the completion date is
compared against a high-water mark, which only moves when something is actually found, so a
completion landing a moment after a sync is not swallowed.

The recurrence mapping lives in `HomeBudgetCore` (`Frequency.recurrenceInterval`) rather than here,
so it is testable without EventKit. The awkward parts of EventKit — why a reminder carries no alarm,
why its due date needs a time — are recorded in
[docs/troubleshooting/eventkit.md](../../docs/troubleshooting/eventkit.md).
