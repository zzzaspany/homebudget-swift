# PostgreSQL

## Accented text sorts and compares wrongly

**Symptom.** Polish letters store and retrieve correctly but sort in the wrong order, and
`upper`/`lower` leave accented characters untouched.

**Cause.** A default Debian install initialises the cluster as `SQL_ASCII`.

**Fix.** Create the cluster with a UTF-8 encoding and a collation matching the language. This
applies **only when the data directory is first initialised** — changing it afterwards means a dump,
re-init and restore.

## `make db-psql` and `make db-backup` fail with command not found

**Symptom.** No `psql` or `pg_dump` on the Mac.

**Cause.** They are not installed, and installing a full PostgreSQL just for two client binaries is
disproportionate.

**Fix.** Both targets run the client inside `docker.io/library/postgres:17-alpine`. Nothing to
install; the version matches the server.

## Migrating from PocketBase

`scripts/migrate-from-pocketbase.py` emits SQL on stdout rather than writing to the database, so the
output can be read before it is applied.

It refuses `quarterly`, `semi_annual` and `biweekly` rows without `--allow-unsafe-periods`. That is
deliberate: the Python app stamped a bare year on those, which the Swift status calculation reads
differently — see the "Deliberate differences" section of the README. Migrating them blindly would
silently mark bills as unpaid or paid.

Sixteen production expenses (6919.67 zł/month) were migrated with every KPI matching the old app
exactly, apart from the two documented corrections.

## The database needs no reverse proxy

It speaks raw TCP. Give it a hostname resolving straight to it — an HTTP proxy in front has nothing
to contribute and only adds a failure mode.

## `CERTIFICATE_VERIFY_FAILED` after changing `sslmode`

```text
PSQLError(code: connectionError, underlying: NIOSSL.NIOSSLError.handshakeFailed(
  BoringSSLError.sslError([Error: ... CERTIFICATE_VERIFY_FAILED ...])))
```

`postgres-kit` does not implement `libpq`'s modes. Whenever it makes a TLS connection it enforces
**full certificate verification — chain of trust and hostname — regardless of the mode asked for**.
`require`, `verify-ca` and `verify-full` are aliases for one another, and `prefer` differs only in
falling back to plaintext when the server offers no TLS at all. There is no encrypt-without-
verifying setting, which is what `require` means in `libpq` and what most people expect it to mean
here.

So two things have to be true before `sslmode=require` works, and neither is about the client:

1. The server's certificate is valid for **the hostname in `DATABASE_URL`**. A certificate for
   `postgres.example.com` will not do when the URL says `postgres.example.lab`, and Debian's default
   `ssl-cert-snakeoil.pem` is valid for neither.
2. Its issuer is a root this image trusts. The image carries `OfficeLab Root CA 2026`; a public
   trust store alone will reject anything the lab issues.

To check the server's side without involving the app:

```bash
openssl s_client -starttls postgres -connect postgres.example.lab:5432 \
  -servername postgres.example.lab -verify_hostname postgres.example.lab </dev/null
```

`Verify return code: 0 (ok)` means the certificate is the problem's other half. To see whether a
connection is actually encrypted rather than assuming it, ask the server:

```sql
SELECT d.datname, a.client_addr, s.ssl
FROM pg_stat_ssl s JOIN pg_stat_activity a USING (pid)
LEFT JOIN pg_database d ON d.oid = a.datid
WHERE a.client_addr IS NOT NULL;
```
