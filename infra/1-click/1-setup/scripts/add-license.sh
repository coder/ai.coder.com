
#!/usr/bin/env bash

eval "$(jq -r '@sh "CODER_IP_ADDR=\(.ip_addr) CODER_DOMAIN=\(.domain) CODER_LICENSE=\(.license_key) CODER_SESSION_TOKEN=\(.session_token)"')"

RESOLVE_ARG="--resolve $CODER_DOMAIN:443:$CODER_IP_ADDR"
CODER_URL=https://$CODER_DOMAIN

RESPONSE=$(curl -ks $RESOLVE_ARG -X POST "$CODER_URL/api/v2/licenses" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -H "Coder-Session-Token: $CODER_SESSION_TOKEN" \
    -d "{\"license\": \"$CODER_LICENSE\"}")

if [ $? -ne 0 ]; then
    >&2 echo "Error: Unable to run 'curl -ks -X POST \"$CODER_URL/api/v2/licenses\"'. Can't add license."
    jq -n '{"success":"false"}'
    exit 1;
fi

jq -n '{"success":"true"}'

exit 0;

echo "Hello!"