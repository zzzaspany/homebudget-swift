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

On a simulator this is more awkward than it should be. `xcrun simctl keychain <device>
add-root-cert` reports success and writes nothing — the trust store stays zero bytes, on Xcode 26
and both booted and shut down. Until that is fixed, signing in has to be exercised on a device, or
against a server whose certificate the simulator already trusts.
