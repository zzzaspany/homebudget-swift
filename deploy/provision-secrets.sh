#!/usr/bin/env bash
# Fetches this deployment's secrets from Infisical and writes them where the container unit can
# read them.
#
# The output goes to the user's runtime directory, which is tmpfs: the secrets exist only while
# the machine is up and never reach persistent storage. What does live on disk is a single
# credential — a machine identity scoped to read one environment — instead of every secret it
# fetches.
#
# Run by homebudget-swift-secrets.service, which the container unit requires.

set -euo pipefail

CONFIG="${INFISICAL_CONFIG:-$HOME/.config/containers/systemd/infisical.env}"
# The instance is behind an internal CA the host does not trust. Verification is not turned off —
# this request carries every secret the deployment has — so the internal root CA is supplied as the
# trust anchor instead. Being the root rather than the leaf, it keeps working when the server
# certificate is renewed. Installing it into the system trust store would let CA_BUNDLE go away.
CA_BUNDLE="${INFISICAL_CA_BUNDLE:-$HOME/.config/containers/systemd/vault-ca.pem}"
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

# Exchange the identity's credentials for a short-lived token. Passed over stdin rather than as
# arguments, which would be visible in the process list.
token=$(
    jq -n --arg id "$INFISICAL_CLIENT_ID" --arg secret "$INFISICAL_CLIENT_SECRET" \
        '{clientId: $id, clientSecret: $secret}' |
        curl -sS --fail-with-body --max-time 30 --cacert "$CA_BUNDLE" \
            -X POST "$INFISICAL_HOST/api/v1/auth/universal-auth/login" \
            -H 'Content-Type: application/json' --data @- |
        jq -r '.accessToken'
)

if [[ -z "$token" || "$token" == "null" ]]; then
    echo "Infisical rejected the machine identity" >&2
    exit 1
fi

secrets=$(
    curl -sS --fail-with-body --max-time 30 --cacert "$CA_BUNDLE" \
        -H "Authorization: Bearer $token" \
        "$INFISICAL_HOST/api/v3/secrets/raw?workspaceId=$INFISICAL_PROJECT_ID&environment=$INFISICAL_ENV&secretPath=%2F"
)

count=$(jq '.secrets | length' <<<"$secrets")
if [[ "$count" -eq 0 ]]; then
    echo "Refusing to write an empty environment file: Infisical returned no secrets" >&2
    exit 1
fi

# Written to a temporary file and moved into place, so a failure midway cannot leave the unit
# reading a half-written file.
umask 077
temporary=$(mktemp "${OUTPUT}.XXXXXX")
trap 'rm -f "$temporary"' EXIT

{
    echo "# Written by provision-secrets.sh from Infisical ($INFISICAL_ENV). Do not edit."
    jq -r '.secrets[] | "\(.secretKey)=\(.secretValue)"' <<<"$secrets"
} >"$temporary"

mv "$temporary" "$OUTPUT"
trap - EXIT

echo "Wrote $count secrets to $OUTPUT"
