
#!/usr/bin/env bash

eval "$(jq -r '@sh "CODER_URL=\(.coder_url) ADMIN_EMAIL=\(.admin_email) ADMIN_PASSWORD=\(.admin_password)"')"

# URL might not be available still. Retry request until available, or fail if max attempts reached.

IDX=0
until curl -s -o /dev/null -kL "$CODER_URL"; do
    if (( IDX >= 6 )); then
        >&2 echo "Error: Unable to run 'curl -s -o /dev/null -kL \"$CODER_URL\"'."
        exit 1;
    fi
    sleep 10
    ((IDX++))
done

LOGIN_RESPONSE=$(curl -ks -X POST "$CODER_URL/api/v2/users/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}" | jq -r '.session_token')

jq -n --arg session_token "$LOGIN_RESPONSE" '{"session_token":$session_token}'

exit 0;