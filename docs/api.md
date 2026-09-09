# Calling the API from a machine

Everything on `office.lab` sits behind Authelia, which is a sign-in page. That is right for a
browser and useless for a shortcut, an automation or a cron job: there is nobody to type a password.
An **API token** is the way in for those, and it is deliberately the weaker way in — a request
carrying one may only read.

## Configuring tokens

`API_TOKENS` holds comma-separated `name:secret` pairs:

```
API_TOKENS=shortcuts:S0meLongRandomSecretValue,n8n:AnotherLongRandomSecret
```

- The **name** is not a password. It is what the access log and `/api/whoami` report, so an
  unexpected call can be traced to the client that made it.
- The **secret** must be at least 24 characters. Generate one, do not invent one:
  `openssl rand -base64 32`.
- Secrets live in Infisical alongside the rest, never in the repository — it is public.
- **Unset means off.** There is no built-in token and no default. An app nobody configured is an app
  no machine can call.

A malformed or too-short entry is dropped and logged at boot rather than taking the whole setting
down with it, so one bad pair cannot knock the working clients offline. Check the log after a change:

```
Read-only API tokens accepted for: shortcuts, n8n
```

## Making a request

Either header works. Bearer is the conventional one:

```bash
curl -H "Authorization: Bearer $TOKEN" https://rachunki.office.lab/api/expenses
```

`X-API-Key` exists because several automation tools only offer that shape:

```bash
curl -H "X-API-Key: $TOKEN" https://rachunki.office.lab/api/expenses
```

## What a token can reach

Every `GET` behind the authentication middleware, which is the whole read surface:

| Endpoint | What it answers |
|---|---|
| `GET /api/expenses` | The dashboard: KPIs, expenses with status, chart data, alerts, sinking funds |
| `GET /api/expenses/:id/history` | Price history for one bill, with the drift since the first payment |
| `GET /api/payments` | Recorded payments, with each one's expense name and category |
| `GET /api/reports/csv?lang=` | The bilingual CSV report |
| `GET /api/reports/pdf?lang=` | The PDF report |
| `GET /api/whoami` | Which client the token belongs to — useful for checking one works |

Anything else — creating, editing, deleting, marking a bill paid, sending the reminder e-mail — is
refused with **403 Forbidden**. That rule lives in the middleware rather than in a second route
table, so a write endpoint added later is closed to tokens the moment it exists, not whenever
somebody remembers to close it.

An unknown token is **401 Unauthorized**, and it does not fall through to the identity headers:
presenting a bad token must not be a way to lower the bar.

`GET /health` needs no credential at all and never did.

## What this token does *not* protect against

Read this before treating a token as a security boundary.

The identity headers (`Remote-User` and friends) are trusted because Authelia sets them, and the app
has no way to tell a header set by the proxy from one set by anybody else. That is safe only while
the app is unreachable except through the proxy — and **it is not**. The container publishes port
8000 on the lab network, so any host on `192.168.0.0/24` can do this:

```bash
curl -H "Remote-User: konrad" http://192.168.0.182:8000/api/expenses     # full read
curl -X DELETE -H "Remote-User: konrad" http://192.168.0.182:8000/api/expenses/<id>
```

That is full read *and write* access without any token, and it predates this feature — the token is
not what introduced it. But it does mean the read-only guarantee is a guarantee about **tokens**,
not about the lab network: it stops a token from being escalated into a write, and it stops a
credential you handed to an automation from deleting your payment history. It does not stop somebody
on the network who never bothers with a token.

Closing that properly means making the app trust identity headers only from the proxy. The two ways
that work here:

1. **A shared secret between the proxy and the app.** Nginx Proxy Manager (CT 106) adds a header
   with a value only it knows; the app ignores identity headers without it. Survives the container
   NAT, which a source-address check may not — the app sees the Podman network's address, not the
   proxy's.
2. **Stop publishing port 8000 on the LAN**, and route the proxy to it over a network only it
   shares. Cleaner, and a larger change to the Quadlets.

Neither is done. Tracked in [roadmap.md](roadmap.md).
