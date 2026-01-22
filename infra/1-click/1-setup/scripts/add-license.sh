
#!/usr/bin/env bash

eval "$(jq -r '@sh "CODER_DOMAIN=\(.domain) CODER_LICENSE=\(.license_key) CODER_SESSION_TOKEN=\(.session_token)"')"

# URL might not be available still. Retry request until available, or fail if max attempts reached.

IDX=0
IP_ADDR=$(dig +short $CODER_DOMAIN | head -n1)
while [[ -z "$IP_ADDR" ]]; do
    ((IDX++))
    if (( IDX >= 6 )); then
        >&2 echo "Error: Failed to run \"dig +short $CODER_DOMAIN | head -n1\". Unable to discover IP for \"$CODER_DOMAIN\"."
        exit 1;
    fi
    sleep 10
    IP_ADDR=$(dig +short $CODER_DOMAIN | head -n1)
done

RESOLVE_ARG="--resolve $CODER_DOMAIN:443:$IP_ADDR"

CODER_URL=https://$CODER_DOMAIN

RESPONSE=$(curl -ks $RESOLVE_ARG -X POST "$CODER_URL/api/v2/licenses" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -H "Coder-Session-Token: $CODER_SESSION_TOKEN" \
    -d "{\"license\": \"$CODER_LICENSE\"}")

if [[ $? -ne 0 ]]; then
    >&2 echo "Error: Unable to run 'curl -ks -X POST \"$CODER_URL/api/v2/licenses\"'."
    exit 1;
fi

jq -n '{"success":"true"}'

exit 0;