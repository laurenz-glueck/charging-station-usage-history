#!/bin/bash

# Array of station IDs and station names
stations=(
  '{ "stationName": "hausen-1", "stationId": 248099 }'
  '{ "stationName": "hausen-2", "stationId": 248102 }'
  '{ "stationName": "bahnhofsplatz", "stationId": 266295 }'
)

# Fetch the APIM subscription key from the environment variable
apim_subscription_key=$APIM_SUBSCRIPTION_KEY

# Loop over the array of stations and fetch the API endpoint for each station
for station in "${stations[@]}"; do
  stationId=$(echo $station | jq -r '.stationId')
  stationName=$(echo $station | jq -r '.stationName')

  # Fetch the API endpoint and store the response in a variable
  response=$(curl --location "https://enbw-emp.azure-api.net/emobility-public-api/api/v1/chargestations/$stationId" \
  --header 'Accept: application/json' \
  --header 'Accept-Language: de' \
  --header 'Cache-Control: no-cache' \
  --header 'Connection: keep-alive' \
  --header "Ocp-Apim-Subscription-Key: $apim_subscription_key" \
  --header 'Origin: https://www.enbw.com' \
  --header 'Pragma: no-cache' \
  --header 'Referer: https://www.enbw.com/' \
  --header 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36 Edg/111.0.1661.62' \
  --fail --silent --show-error)

  # Check if the curl request succeeded or failed
  if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch data for station $stationId"
    exit 1
  else
    echo "Successfully fetched data for station $stationId"
  fi

  # Extract the required fields from the response using jq and store in a JSON object
  json=$(echo $response | jq -S -M '{availableChargePoints: .availableChargePoints, numberOfChargePoints: .numberOfChargePoints}')

  # Check if the required fields were found in the JSON response
  if [ -z "$json" ]; then
    echo "Error: Required fields not found in response for station $stationId"
    exit 1
  else
    echo "Successfully extracted data for station $stationId: availableChargePoints: $(echo $json | jq -r '.availableChargePoints'), numberOfChargePoints: $(echo $json | jq -r '.numberOfChargePoints')"
  fi

  # Write the JSON object to a file with the stationName as the filename
  printf '%s\n' "$json" > "history-data/history--$stationName.json"
done
