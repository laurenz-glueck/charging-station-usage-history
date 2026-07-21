#!/bin/bash
set -uo pipefail

# Configuration per tracked location.
#
# "stationIds"  - the EVSE IDs that make up the location, counted for the history data.
# "wirelaneStations" - the Wirelane stations hosting those EVSE IDs, addressed by
#                 provider/owner/station_id. One Wirelane station usually hosts several
#                 of our EVSE IDs, and one location can span several Wirelane stations
#                 (e.g. bahnhofsplatz).
#
# These coordinates are looked up once via the (slow) search endpoint - see
# resolve_via_search below - and then persisted here, because the direct station endpoint
# is far faster than searching on every run.
stations=(
  '{ "stationName": "hausen-1", "stationIds": "DE*WLN*E7001012*1,DE*WLN*E7001012*2", "wirelaneStations": [{ "provider": "emc", "owner": "o0014", "stationId": "Kirchheim0004" }] }'
  '{ "stationName": "hausen-2", "stationIds": "DE*WLN*ES001608,DE*WLN*ES001609", "wirelaneStations": [{ "provider": "emc", "owner": "o0014", "stationId": "HausenNord" }] }'
  '{ "stationName": "bahnhofsplatz", "stationIds": "DE*WLN*EL01056,DE*WLN*ES001959,DE*WLN*ES001912,DE*WLN*ES001913", "wirelaneStations": [{ "provider": "emc", "owner": "o0014", "stationId": "1319611SW.10129" }, { "provider": "emc", "owner": "o0014", "stationId": "PfrCasparMayr-West" }] }'
  '{ "stationName": "mittelschule", "stationIds": "DE*WLN*EL00959,DE*WLN*EL00960,DE*WLN*EL00961,DE*WLN*EL00962", "wirelaneStations": [{ "provider": "emc", "owner": "o0014", "stationId": "140832422.00756" }, { "provider": "emc", "owner": "o0014", "stationId": "140832422.00563" }] }'
)

API_BASE="https://api.wirelane.com/apis/emc"
OAUTH_URL="https://oauth.emobilitycloud.com/token"
USER_AGENT="Wirelane/2.4.2 (com.emobilitycloud.Wirelane; build:1; iOS 18.2.0) Alamofire/5.9.1"

# Environment variables for authentication
WIRELANE_USERNAME=${WIRELANE_USERNAME}
WIRELANE_PASSWORD=${WIRELANE_PASSWORD}
WIRELANE_AUTH_TOKEN=${WIRELANE_AUTH_TOKEN}

# Check if username and password are set
if [ -z "$WIRELANE_USERNAME" ] || [ -z "$WIRELANE_PASSWORD" ]; then
  echo "Error: Wirelane username or password not set."
  exit 1
fi

# Cache of "evseid<TAB>status" pairs, filled per Wirelane station so that a station
# hosting several of our EVSE IDs only costs a single request
statusCache=$(mktemp)
trap 'rm -f "$statusCache"' EXIT

# Authenticate and obtain an access token
get_auth_token() {
  local response httpCode body

  response=$(curl -sS -w '\n%{http_code}' -X POST "$OAUTH_URL" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "User-Agent: $USER_AGENT" \
    -H "Authorization: $WIRELANE_AUTH_TOKEN" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "response_type=token" \
    --data-urlencode "tenant=dewln" \
    --data-urlencode "username=$WIRELANE_USERNAME" \
    --data-urlencode "password=$WIRELANE_PASSWORD")

  httpCode=${response##*$'\n'}
  body=${response%$'\n'*}

  if [ "$httpCode" != "200" ]; then
    echo "Error: Token request failed with HTTP $httpCode: $body" >&2
    return 1
  fi

  echo "$body" | jq -r '.access_token // empty'
}

# Look up a cached status for an EVSE ID, returns non-zero if not cached yet
lookup_status() {
  awk -F'\t' -v id="$1" '$1 == id { print $2; found = 1; exit } END { if (!found) exit 1 }' "$statusCache"
}

# Cache the status of every connector contained in a station object
cache_connectors() {
  echo "$1" | jq -r '.connectors[]? | select(.evseid != null) | [.evseid, .status] | @tsv' >> "$statusCache"
}

# Percent-encode a value for use inside a URL path
url_encode() {
  jq -rn --arg value "$1" '$value | @uri'
}

# Fetch a single Wirelane station directly. This is the hot path: roughly two orders of
# magnitude faster than the search endpoint below.
fetch_station() {
  local provider=$1 owner=$2 stationId=$3
  local url response httpCode body

  url="$API_BASE/stations/provider/$(url_encode "$provider")/owner/$(url_encode "$owner")/station/id/$(url_encode "$stationId")"

  response=$(curl -sS -w '\n%{http_code}' "$url" \
    -H "Accept: */*" \
    -H "Accept-Language: de" \
    -H "User-Agent: $USER_AGENT" \
    -H "Authorization: Bearer $token")

  httpCode=${response##*$'\n'}
  body=${response%$'\n'*}

  if [ "$httpCode" != "200" ]; then
    echo "::warning::Direct lookup of station $stationId failed with HTTP $httpCode: $body"
    return 1
  fi

  # Guard against the API changing shape again: we expect a single station object
  if ! echo "$body" | jq -e 'type == "object" and has("connectors")' > /dev/null 2>&1; then
    echo "::warning::Unexpected response shape for station $stationId: $body"
    return 1
  fi

  cache_connectors "$body"
}

# Fallback for EVSE IDs the direct lookups did not return, e.g. because a station was
# renamed or a charge point moved. Slow, so this must stay off the hot path.
resolve_via_search() {
  local evseId=$1
  local response httpCode body

  echo "Falling back to the search endpoint for $evseId - update the wirelaneStations config with the provider/owner/station_id it reports."

  response=$(curl -sS -w '\n%{http_code}' -G "$API_BASE/stations" \
    --data-urlencode "search=$evseId" \
    -H "Accept: */*" \
    -H "Accept-Language: de" \
    -H "User-Agent: $USER_AGENT" \
    -H "Authorization: Bearer $token")

  httpCode=${response##*$'\n'}
  body=${response%$'\n'*}

  if [ "$httpCode" != "200" ]; then
    echo "::warning::Search for $evseId failed with HTTP $httpCode: $body"
    return 1
  fi

  # The search endpoint returns an array of stations, the direct endpoint a single object
  if ! echo "$body" | jq -e 'type == "array"' > /dev/null 2>&1; then
    echo "::warning::Unexpected search response shape for $evseId: $body"
    return 1
  fi

  echo "$body" | jq -c '.[]' | while read -r station; do
    echo "  found in station $(echo "$station" | jq -r '[.charging_provider, .owner, .station_id] | join("/")')"
  done

  echo "$body" | jq -r '.[].connectors[]? | select(.evseid != null) | [.evseid, .status] | @tsv' >> "$statusCache"
}

# Get the access token
token=$(get_auth_token)
if [ -z "$token" ] || [ "$token" == "null" ]; then
  echo "Error: Failed to obtain access token."
  exit 1
fi

echo "Successfully obtained access token."

hasMissingEvseIds=0

# Fetch charging station data
for station in "${stations[@]}"; do
  stationIds=$(echo "$station" | jq -r '.stationIds')
  stationName=$(echo "$station" | jq -r '.stationName')

  echo "Fetching data for station $stationName with stationIds: $stationIds"

  # Requests stay sequential on purpose: concurrent requests run into server-side timeouts
  while read -r wirelaneStation; do
    [ -z "$wirelaneStation" ] && continue
    fetch_station \
      "$(echo "$wirelaneStation" | jq -r '.provider')" \
      "$(echo "$wirelaneStation" | jq -r '.owner')" \
      "$(echo "$wirelaneStation" | jq -r '.stationId')"
  done < <(echo "$station" | jq -c '.wirelaneStations[]?')

  available=0
  total=0
  missing=0

  IFS=',' read -ra evseIds <<< "$stationIds"
  for evseId in "${evseIds[@]}"; do
    if ! status=$(lookup_status "$evseId"); then
      resolve_via_search "$evseId"
      status=$(lookup_status "$evseId") || status=""
    fi

    if [ -z "$status" ]; then
      echo "::warning::EVSE $evseId ($stationName) is unknown to the Wirelane API - it was probably decommissioned or re-labelled."
      missing=$((missing + 1))
      continue
    fi

    total=$((total + 1))
    if [ "$status" == "FREE" ]; then
      available=$((available + 1))
    fi
  done

  if [ "$missing" -gt 0 ]; then
    hasMissingEvseIds=1
  fi

  # Never overwrite good history with a partial reading
  if [ "$total" -eq 0 ]; then
    echo "::error::No EVSE of $stationName could be resolved - keeping the previous value."
    continue
  fi

  echo "Successfully fetched data for $stationName: availableChargePoints: $available, numberOfChargePoints: $total"

  # Write via a temp file so a failure can never truncate the committed history
  tmpFile=$(mktemp)
  if jq -n --argjson available "$available" --argjson total "$total" \
      '{availableChargePoints: $available, numberOfChargePoints: $total}' > "$tmpFile"; then
    mv "$tmpFile" "history-data/history--$stationName.json"
  else
    rm -f "$tmpFile"
    echo "Error: Failed to write data for $stationName" >&2
    exit 1
  fi
done

# Surface decommissioned EVSE IDs as a failed run - the data above is still written
# and committed, but a red run makes stale station IDs visible instead of silently
# recording zeros for months.
if [ "$hasMissingEvseIds" -ne 0 ]; then
  echo "Error: At least one configured EVSE ID no longer exists. Update the stations array." >&2
  exit 1
fi
