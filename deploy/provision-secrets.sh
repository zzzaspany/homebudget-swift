#!/usr/bin/env bash
# Renders this deployment's environment from Infisical and writes it where the container unit can
# read it.
#
# The output goes to the user's runtime directory, which is tmpfs: the secrets exist only while
# the machine is up and never reach persistent storage. What does live on disk is a single
# credential — a machine identity scoped to one project — instead of every secret it fetches.
#
# The template beside this script decides what the container receives. A secret's name in the
# vault is not the variable name the application reads, so the template is the mapping between
# them; it also keeps non-secret settings in git, where a change shows up in a diff.
#
# Run by homebudget-swift-secrets.service, which the container unit requires.

set -euo pipefail

CONFIG="${INFISICAL_CONFIG:-$HOME/.config/containers/systemd/infisical.env}"
# The instance is behind an internal CA the host does not trust. Verification is not turned off —
# this request carries every secret the deployment has — so the internal root CA is supplied as the
# trust anchor instead. Being the root rather than the leaf, it keeps working when the server
# certificate is renewed. Installing it into the system trust store would let CA_BUNDLE go away.
CA_BUNDLE="${INFISICAL_CA_BUNDLE:-$HOME/.config/containers/systemd/vault-ca.pem}"
TEMPLATE="${SECRETS_TEMPLATE:-$(dirname "$(readlink -f "$0")")/homebudget-swift.env.template}"
OUTPUT="${SECRETS_OUTPUT:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/homebudget-swift.env}"

if [[ ! -r "$CONFIG" ]]; then
    echo "Missing $CONFIG — it must define INFISICAL_HOST, INFISICAL_CLIENT_ID," >&2
    echo "INFISICAL_CLIENT_SECRET, INFISICAL_PROJECT_ID and INFISICAL_ENV." >&2
    exit 1
fi

# shellcheck source=/dev/null
set -a; source "$CONFIG"; set +a

: "${INFISICAL_HOST:?}" "${INFISICAL_CLIENT_ID:?}" "${INFISICAL_CLIENT_SECRET:?}"
: "${INFISICAL_PROJECT_ID:?}" "${INFISICAL_ENV:?}"

if [[ ! -r "$CA_BUNDLE" ]]; then
    echo "Missing $CA_BUNDLE — needed to verify the Infisical certificate." >&2
    exit 1
fi

if [[ ! -r "$TEMPLATE" ]]; then
    echo "Missing $TEMPLATE — it declares which secrets this deployment needs." >&2
    exit 1
fi

# At boot this unit has repeatedly started before the resolver was reachable and died on
# "Could not resolve host", leaving the container down until someone noticed. The unit already
# orders itself After=network-online.target, but in the *user* manager that target does not wait
# for anything, so the ordering reads as correct and does nothing. Waiting here is what works.
# See docs/troubleshooting/secrets.md.
host_only="${INFISICAL_HOST#*://}"; host_only="${host_only%%[:/]*}"
for attempt in $(seq 1 30); do
    if getent hosts "$host_only" >/dev/null 2>&1; then
        break
    fi
    if [[ "$attempt" -eq 30 ]]; then
        echo "Gave up waiting for $host_only to resolve after 30 attempts." >&2
        exit 1
    fi
    sleep 2
done

# Exchange the identity's credentials for a short-lived token. Passed over stdin rather than as
# arguments, which would be visible in the process list.
token=$(
    jq -n --arg id "$INFISICAL_CLIENT_ID" --arg secret "$INFISICAL_CLIENT_SECRET" \
        '{clientId: $id, clientSecret: $secret}' |
        curl -sS --fail-with-body --max-time 30 --retry 3 --retry-connrefused --cacert "$CA_BUNDLE" \
            -X POST "$INFISICAL_HOST/api/v1/auth/universal-auth/login" \
            -H 'Content-Type: application/json' --data @- |
        jq -r '.accessToken'
)

if [[ -z "$token" || "$token" == "null" ]]; then
    echo "Infisical rejected the machine identity" >&2
    exit 1
fi

# recursive=true because the secrets sit in folders — /homebudget for this deployment's own, and
# /shared and /ntfy for values other services use too, stored once rather than copied per service.
secrets=$(
    curl -sS --fail-with-body --max-time 30 --retry 3 --retry-connrefused --cacert "$CA_BUNDLE" \
        -H "Authorization: Bearer $token" \
        "$INFISICAL_HOST/api/v3/secrets/raw?workspaceId=$INFISICAL_PROJECT_ID&environment=$INFISICAL_ENV&secretPath=%2F&recursive=true"
)

count=$(jq '.secrets | length' <<<"$secrets")
if [[ "$count" -eq 0 ]]; then
    echo "Refusing to write an environment file: Infisical returned no secrets" >&2
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
    echo "# Rendered by provision-secrets.sh from Infisical ($INFISICAL_ENV). Do not edit."
    jq -rn --rawfile template "$TEMPLATE" --argjson secrets "$secrets" '
        ($secrets.secrets
          | map({key: ((.secretPath | rtrimstr("/")) + "/" + .secretKey), value: .secretValue})
          | from_entries) as $byPath
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
