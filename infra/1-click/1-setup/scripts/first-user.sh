
#!/usr/bin/env bash

eval "$(jq -r '@sh "CODER_DOMAIN=\(.domain) ADMIN_EMAIL=\(.admin_email) ADMIN_USERNAME=\(.admin_username) ADMIN_PASSWORD=\(.admin_password)"')"

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

RESPONSE=$(curl -ks $RESOLVE_ARG -X POST "$CODER_URL/api/v2/users/first" \
    -H "Content-Type: application/json" \
    -d "{
    \"email\": \"$ADMIN_EMAIL\",
    \"username\": \"$ADMIN_USERNAME\",
    \"password\": \"$ADMIN_PASSWORD\",
    \"trial\": false
    }")

LOGIN_RESPONSE=$(curl -ks $RESOLVE_ARG -X POST "$CODER_URL/api/v2/users/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" | jq -r '.session_token')

jq -n --arg session_token "$LOGIN_RESPONSE" '{"session_token":$session_token}'

exit 0;