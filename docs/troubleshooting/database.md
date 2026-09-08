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
