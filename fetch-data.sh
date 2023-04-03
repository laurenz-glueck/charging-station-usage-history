#!/bin/bash

# Array of station IDs and station names
stations=(
  '{ "stationName": "hausen-1", "stationId": 248099 }'
  '{ "stationName": "hausen-2", "stationId": 248102 }'
  '{ "stationName": "bahnhofsplatz", "stationId": 266295 }'
)

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
  --header 'Ocp-Apim-Subscription-Key: d4954e8b2e444fc89a89a463788c0a72' \
  --header 'Origin: https://www.enbw.com' \
  --header 'Pragma: no-cache' \
  --header 'Referer: https://www.enbw.com/' \
  --header 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36 Edg/111.0.1661.62')

  # Extract the required fields from the response using jq and store in a JSON object
  json=$(echo $response | jq -S -M '{availableChargePoints: .availableChargePoints, numberOfChargePoints: .numberOfChargePoints}')

  # Write the JSON object to a file with the stationName as the filename
  printf '%s\n' "$json" > "history-data/history--$stationName.json"
done
