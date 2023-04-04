# Charging Station Usage History

© 2023 - Laurenz Glück - www.laurenz.io

[![Fetch charging station data](https://github.com/laurenz-glueck/charging-station-usage-history/actions/workflows/fetch-data.yaml/badge.svg?branch=main)](https://github.com/laurenz-glueck/charging-station-usage-history/actions/workflows/fetch-data.yaml)
[![Generate History Charts](https://github.com/laurenz-glueck/charging-station-usage-history/actions/workflows/generate-history-charts.yaml/badge.svg?branch=main)](https://github.com/laurenz-glueck/charging-station-usage-history/actions/workflows/generate-history-charts.yaml)

This repository tracks the usage of three EV charging stations. For the tracking the EnBW API is used.

To store the data we use the git-scraping approach by saving the data as JSON files in the repository.
With each data update a new commit is created. This allows us to track the history of the data.
We fetch new data every 5 minutes using a GitHub Action.

We also have another GitHub Action that generates charts from the data and pushes them to the repository.
This happens once a day at 00:01 in the night.

This is a personal project and not affiliated with EnBW or any other company.

If you want to read more about git-scraping, check out this blog post from Simon Willison: https://simonwillison.net/2020/Oct/9/git-scraping/

