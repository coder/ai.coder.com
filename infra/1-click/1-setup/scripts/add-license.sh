
#!/usr/bin/env bash

eval "$(jq -r '@sh "CODER_URL=\(.access_url) CODER_LICENSE=\(.license_key) CODER_SESSION_TOKEN=\(.session_token)"')"

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


RESPONSE=$(curl -ks -X POST "$CODER_URL/api/v2/licenses" \
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