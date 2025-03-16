#!/bin/bash

# Array of station IDs and station names
stations=(
  '{ "stationName": "hausen-1", "stationIds": "DE*WLN*E7001012*1,DE*WLN*E7001012*2" }'
  '{ "stationName": "hausen-2", "stationIds": "DE*WLN*E7001013*1,DE*WLN*E7001013*2" }'
  '{ "stationName": "bahnhofsplatz", "stationIds": "DE*WLN*E10010291,DE*WLN*E10010292" }'
  '{ "stationName": "mittelschule", "stationIds": "DE*WLN*EL00959,DE*WLN*EL00960,DE*WLN*EL00961,DE*WLN*EL00962" }'
)


# Environment variables for authentication
WIRELANE_USERNAME=${WIRELANE_USERNAME}
WIRELANE_PASSWORD=${WIRELANE_PASSWORD}
WIRELANE_AUTH_TOKEN=${WIRELANE_AUTH_TOKEN}

# Check if username and password are set
if [ -z "$WIRELANE_USERNAME" ] || [ -z "$WIRELANE_PASSWORD" ]; then
  echo "Error: Wirelane username or password not set."
  exit 1
fi

# Authenticate and obtain an access token
get_auth_token() {
  local response
  response=$(curl -s -X POST "https://oauth.emobilitycloud.com/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Authorization: $WIRELANE_AUTH_TOKEN" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "response_type=token" \
    --data-urlencode "tenant=dewln" \
    --data-urlencode "username=$WIRELANE_USERNAME" \
    --data-urlencode "password=$WIRELANE_PASSWORD")

  echo "$response" | jq -r .access_token
}

# Get the access token
token=$(get_auth_token)
if [ -z "$token" ] || [ "$token" == "null" ]; then
  echo "Error: Failed to obtain access token."
  exit 1
fi

echo "Successfully obtained access token."

# Fetch charging station data
for station in "${stations[@]}"; do
  stationIds=$(echo $station | jq -r '.stationIds')
  stationName=$(echo $station | jq -r '.stationName')

  echo "Fetching data for station $stationName with stationIds: $stationIds"

  response=$(curl -s -X GET "https://api.wirelane.com/apis/emc/points?evseid=$stationIds" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer $token")

  if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch data for station $stationName"
    exit 1
  fi

  # Extract available and total charge points
  available=$(echo "$response" | jq '[.[] | select(.status == "FREE")] | length')
  total=$(echo "$response" | jq 'length')

  echo "Successfully fetched data for $stationName: availableChargePoints: $available, numberOfChargePoints: $total"

  # Write the JSON object to a file
  echo "{\"availableChargePoints\": $available, \"numberOfChargePoints\": $total}" | jq '.' > "history-data/history--$stationName.json"
done
