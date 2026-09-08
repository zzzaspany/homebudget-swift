# The internal CA and TLS on Apple devices

Everything on `*.office.lab` is served by Nginx Proxy Manager with one wildcard certificate issued
by a private root, "OfficeLab Root CA". macOS accepts it once the root is in the keychain. iOS does
not, and the reason is not obvious.

## iOS refuses the wildcard certificate even with the root CA installed and fully trusted

**Symptom.** On an iPhone, an iPad, or the simulator: Safari shows "This Connection Is Not Private —
This website may be impersonating rachunki.office.lab". In the app, `WKWebView` fails navigation
with `NSURLErrorServerCertificateUntrusted`. The OfficeLab root is installed as a configuration
profile *and* switched on under Settings → General → About → Certificate Trust Settings. macOS on
the same network loads the site without complaint.

**Cause.** Not the root, and not the trust setting — both are fine. The leaf certificate is valid
for 3650 days (23 Jun 2026 → 20 Jun 2036). Since iOS 13 Apple rejects any TLS server certificate
whose validity period exceeds **398 days**, and on iOS 26 this applies to certificates chaining to a
user-installed root as well, not only to the built-in ones. macOS does not enforce it, which is why
`curl` and `security verify-cert -p ssl` both pass on the Mac and mislead you.

The proof is in the simulator's own log — there is no need to guess:

```bash
xcrun simctl spawn <device-udid> log stream --style compact \
  --predicate 'process == "trustd" OR subsystem == "com.apple.securityd"'
```

```
trustd: cert[0]: OtherTrustValidityPeriod =(path)[]> 0
Trust evaluate failure: [leaf OtherTrustValidityPeriod]
```

`OtherTrustValidityPeriod` is exactly this check. Note that the chain built successfully first —
had the root been missing or untrusted, the failure would name an anchor problem instead.

**Fix.** Reissue the leaf with a validity of 397 days or less and load it into Nginx Proxy Manager.
The root CA itself is not subject to the limit and can keep its ten years. Confirm before and after:

```bash
echo | openssl s_client -connect rachunki.office.lab:443 -servername rachunki.office.lab 2>/dev/null \
  | openssl x509 -noout -dates
```

A yearly reissue then has to be scripted, or every Apple device on the network breaks silently a
year from now.

*Alternative, if the certificate cannot be changed:* pin the OfficeLab CA inside the app —
`URLSessionDelegate` and `WKNavigationDelegate` both get `didReceive challenge`, and the chain can
be validated against a bundled copy of the root with `SecTrustSetAnchorCertificates`. This fixes
only this app. Safari and every other lab service stay broken on the phone. Prefer reissuing.

*Hit 2026-09-08. Certificate reissue not yet done — pending the owner's go-ahead, because the
wildcard is shared by every service on office.lab.*

## Diagnosing "is it the certificate or the trust store"

Worth knowing which question you are answering, because the two failures look identical from the UI.

Apple's own trust evaluation, run on the Mac against a specific root — this answers "would Apple's
policy accept this chain":

```bash
echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null | openssl x509 > leaf.pem
security verify-cert -c leaf.pem -r /path/to/ca.pem -p ssl -s <host>
```

Beware: macOS skips the 398-day rule, so a pass here does not mean iOS will accept it. Only the
`trustd` log on the device settles that.

Certificate consistency, when more than one proxy might be answering:

```bash
dig +short <host>
for i in 1 2 3 4 5; do
  echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null \
    | openssl x509 -noout -fingerprint -sha256
done
```

*Written 2026-09-08.*
