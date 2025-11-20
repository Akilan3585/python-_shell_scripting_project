#!/usr/bin/env bash
URL="${1:-http://54.84.202.22}"
TIMEOUT="${2:-5}"
RETRIES=2
SLEEP_BETWEEN=1

check_once() {
  http_code=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" --max-time "${TIMEOUT}" "$URL" 2>/dev/null)
  echo "$http_code"
}

for i in $(seq 0 $RETRIES); do
  out=$(check_once)
  resp_time=$(echo "$out" | awk '{print $2}')

  if [[ "$status_code" =~ ^2[0-9][0-9]$ || "$status_code" == "301" || "$status_code" == "302" ]]; then
    echo "$(date +"%Y-%m-%d %H:%M:%S") OK - $URL returned $status_code in ${resp_time}s"
    exit 0
  else
    echo "$(date +"%Y-%m-%d %H:%M:%S") WARN - attempt $((i+1)): returned ${status_code:-NO_RESPONSE}"
    sleep "$SLEEP_BETWEEN"
  fi
done

echo "$(date +"%Y-%m-%d %H:%M:%S") DOWN - $URL appears down after $((RETRIES+1)) tries"
exit 2
