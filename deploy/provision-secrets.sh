#!/usr/bin/env bash
# Renders this deployment's environment from OpenBao and writes it where the container unit can
# read it.
#
# The output goes to the user's runtime directory, which is tmpfs: the secrets exist only while
# the machine is up and never reach persistent storage. What does live on disk is a single
# credential — an AppRole whose policy covers three paths — instead of every secret it fetches.
# That scoping is enforced by the server and was tested: the role reads its three paths and is
# refused with a 403 on every other one, including the other services on this same host.
#
# The template beside this script decides what the container receives. A secret's name in the
# vault is not the variable name the application reads, so the template is the mapping between
# them; it also keeps non-secret settings in git, where a change shows up in a diff.
#
# Run by homebudget-swift-secrets.service, which the container unit requires.

set -euo pipefail

CONFIG="${BAO_CONFIG:-$HOME/.config/containers/systemd/openbao.env}"
# The instance is behind an internal CA the host does not trust. Verification is not turned off —
# this request carries every secret the deployment has — so the internal root CA is supplied as the
# trust anchor instead. Being the root rather than the leaf, it keeps working when the server
# certificate is renewed. Installing it into the system trust store would let CA_BUNDLE go away.
CA_BUNDLE="${BAO_CACERT:-$HOME/.config/containers/systemd/vault-ca.pem}"
TEMPLATE="${SECRETS_TEMPLATE:-$(dirname "$(readlink -f "$0")")/homebudget-swift.env.template}"
OUTPUT="${SECRETS_OUTPUT:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/homebudget-swift.env}"

if [[ ! -r "$CONFIG" ]]; then
    echo "Missing $CONFIG — it must define BAO_ADDR, BAO_ROLE_ID and BAO_SECRET_ID." >&2
    exit 1
fi

# shellcheck source=/dev/null
set -a; source "$CONFIG"; set +a

: "${BAO_ADDR:?}" "${BAO_ROLE_ID:?}" "${BAO_SECRET_ID:?}"

if [[ ! -r "$CA_BUNDLE" ]]; then
    echo "Missing $CA_BUNDLE — needed to verify the OpenBao certificate." >&2
    exit 1
fi

if [[ ! -r "$TEMPLATE" ]]; then
    echo "Missing $TEMPLATE — it declares which secrets this deployment needs." >&2
    exit 1
fi

# This unit has started before the resolver was ready and died on "Could not resolve host". The
# unit orders itself After=network-online.target, but in the *user* manager that target does not
# wait for anything, so the ordering reads as correct and does nothing.
#
# The wait must stay well inside the unit's TimeoutStartSec, or systemd kills the script before it
# does any work and the failure is reported as a timeout instead of naming the cause -- which is
# exactly what happened the first time this was written with a 60s budget against a 60s timeout.
# See docs/troubleshooting/secrets.md.
RESOLVE_ATTEMPTS="${RESOLVE_ATTEMPTS:-10}"
host_only="${BAO_ADDR#*://}"; host_only="${host_only%%[:/]*}"
for attempt in $(seq 1 "$RESOLVE_ATTEMPTS"); do
    if getent hosts "$host_only" >/dev/null 2>&1; then
        break
    fi
    if [[ "$attempt" -eq "$RESOLVE_ATTEMPTS" ]]; then
        echo "$host_only did not resolve after ${RESOLVE_ATTEMPTS} attempts over $((RESOLVE_ATTEMPTS * 2))s." >&2
        echo "This is a name resolution fault, not a slow boot -- check the resolver this host uses" >&2
        echo "for the internal domain. 'resolvectl status' shows per-link and global servers separately," >&2
        echo "and a stale global entry wins over a correct one supplied by DHCP on the link." >&2
        exit 1
    fi
    sleep 2
done

# Exchange the AppRole's credentials for a short-lived token. Passed over stdin rather than as
# arguments, which would be visible in the process list.
token=$(
    jq -n --arg id "$BAO_ROLE_ID" --arg secret "$BAO_SECRET_ID" \
        '{role_id: $id, secret_id: $secret}' |
        curl -sS --fail-with-body --max-time 30 --retry 3 --retry-connrefused --cacert "$CA_BUNDLE" \
            -X POST "$BAO_ADDR/v1/auth/approle/login" \
            -H 'Content-Type: application/json' --data @- |
        jq -r '.auth.client_token'
)

if [[ -z "$token" || "$token" == "null" ]]; then
    echo "OpenBao rejected the AppRole" >&2
    exit 1
fi

# Only the paths the template names are read, so the request matches what the policy allows and
# nothing more. They are derived from the template rather than listed here, so adding a placeholder
# cannot forget to widen the fetch — and if it names a path outside the policy, the 403 below says
# so rather than the run quietly succeeding with a gap.
paths=$(
    grep -v '^[[:space:]]*#' "$TEMPLATE" |
        grep -oE '\{\{[[:space:]]*/[A-Za-z0-9_./-]+[[:space:]]*\}\}' |
        tr -d '{} ' | sed 's|/[^/]*$||; s|^/||' | sort -u
)

if [[ -z "$paths" ]]; then
    echo "Refusing to write an environment file: $TEMPLATE names no secrets" >&2
    exit 1
fi

# Collected into one flat object keyed by full path, which is how the template addresses them.
secrets='{}'
count=0
for path in $paths; do
    if ! response=$(
        curl -sS --fail-with-body --max-time 30 --retry 3 --retry-connrefused --cacert "$CA_BUNDLE" \
            -H "X-Vault-Token: $token" "$BAO_ADDR/v1/secret/data/$path"
    ); then
        echo "Could not read secret/data/$path — the AppRole's policy may not cover it." >&2
        exit 1
    fi
    secrets=$(
        jq -c --arg prefix "/$path" --argjson response "$response" --argjson acc "$secrets" '
            $acc + ($response.data.data
                    | to_entries
                    | map({key: ($prefix + "/" + .key), value: .value})
                    | from_entries)' <<<'null'
    )
    count=$((count + $(jq '.data.data | length' <<<"$response")))
done

if [[ "$count" -eq 0 ]]; then
    echo "Refusing to write an environment file: OpenBao returned no secrets" >&2
    exit 1
fi

# Written to a temporary file and moved into place, so a failure midway cannot leave the unit
# reading a half-written file.
umask 077
temporary=$(mktemp "${OUTPUT}.XXXXXX")
trap 'rm -f "$temporary"' EXIT

# Substitution happens inside jq rather than through sed, so a value containing a slash, an
# ampersand or a newline cannot corrupt the output or be interpreted as a pattern. A placeholder
# with no matching secret aborts the run: a partially rendered file would start the container with
# a literal "{{/path/NAME}}" as a password, which fails far from its cause.
{
    echo "# Rendered by provision-secrets.sh from OpenBao. Do not edit."
    jq -rn --rawfile template "$TEMPLATE" --argjson secrets "$secrets" '
        $secrets as $byPath
        | $template
        | split("\n")
        | map(
            if (ltrimstr(" ") | startswith("#")) then .
            else gsub("\\{\\{[[:space:]]*(?<p>[^}[:space:]]+)[[:space:]]*\\}\\}";
                      $byPath[.p] // error("no secret at " + .p))
            end
          )
        | join("\n")
    ' </dev/null
} >"$temporary"

mv "$temporary" "$OUTPUT"
trap - EXIT

echo "Wrote $(grep -cE '^[A-Za-z0-9_]+=' "$OUTPUT") variables to $OUTPUT from $count secrets"
