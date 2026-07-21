# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A git-scraping project (see https://simonwillison.net/2020/Oct/9/git-scraping/) that tracks availability of four EV charging stations. There is no build system, no package manager, no tests. The repository itself is the database: every 5 minutes a GitHub Action overwrites four small JSON files and commits them, so **the commit history is the time series**.

## Architecture

Three independent GitHub Actions pipelines, all in `.github/workflows/`:

1. **`fetch-data.yaml`** (cron `*/5 * * * *`) runs `fetch-data-wirelane.sh`, which writes `history-data/history--<station>.json` (only `availableChargePoints` / `numberOfChargePoints`) and commits with message `Latest data: DD.MM.YYYY HH:MM`. The commit is intentionally the timestamp carrier - the JSON contains no date field.
2. **`generate-history-charts.yaml`** (cron `1 0 * * *`) installs `pygit2` + `matplotlib` ad hoc (no `requirements.txt` exists despite the cache key referencing one) and runs `generate-history-chart.py`, which walks the git history with pygit2 to reconstruct yesterday's availability curve per station and writes `history-charts/<station>/YYYY-MM-DD.png`.
3. **`generate-website.yml`** (cron `5 0 * * *`) deploys `website/` to GitHub Pages.

Because charts are derived from commit history, the chart workflow checks out with `fetch-depth: 0`. Any change to commit cadence, commit messages, or the JSON schema breaks chart generation retroactively.

The website is static HTML with no build step. It does **not** read `history-charts/` from the deployed artifact (only `website/` is uploaded); instead `website/fetch-gallery.js` and the inline script in `index.html` call the GitHub Contents API against the hardcoded repo `laurenz-glueck/charging-station-usage-history` at runtime. Renaming the repo or moving `history-charts/` breaks the site silently.

## Station configuration is duplicated in four places

Adding or renaming a station means touching all of these, and they use the same slug (`hausen-1`, `hausen-2`, `bahnhofsplatz`, `mittelschule`):

- `fetch-data-wirelane.sh` - `stations` array (slug -> comma-separated Wirelane EVSE IDs **plus** the `wirelaneStations` provider/owner/station_id coordinates that host them; a location can span several Wirelane stations)
- `generate-history-chart.py` - `config` list (slug, display name, JSON path)
- `history-charts/<slug>/` - the directory must exist, `plt.savefig` will not create it
- `website/` - a `<slug>.html` page calling `fetchGallery('<slug>')`, plus nav links in *every* page and a card in `index.html`

Known drift: `mittelschule` is fetched and charted but has no website page and no nav entry.

## Data sources

Current provider is **Wirelane** (`api.wirelane.com`), authenticated via an OAuth password grant against `oauth.emobilitycloud.com` using the `WIRELANE_USERNAME`, `WIRELANE_PASSWORD`, and `WIRELANE_AUTH_TOKEN` secrets. The endpoints used here are not covered by the published spec at https://wirelane.github.io/wirelane-api/ and can change without notice - treat every response as untrusted and validate its shape before using it.

Availability comes from `GET /apis/emc/stations/provider/{provider}/owner/{owner}/station/id/{station_id}`, which returns **one station object** carrying `connectors[] = {evseid, status, ...}`; a charge point counts as available when `status == "FREE"`. The script caches every connector of every response, so one request per physical station covers all its EVSE IDs (6 requests, ~1s total including auth).

`GET /apis/emc/points?evseid=...` was the original endpoint. It stopped existing on 2026-07-20 and now returns 404, which is what broke the pipeline.

`GET /apis/emc/stations?search=<evseid>` also returns availability, as an *array* of stations, but a request takes tens of seconds, so it is only a fallback for when a configured station no longer resolves. It logs the provider/owner/station_id it found so the `wirelaneStations` config can be corrected. Before trying to make it the main path again:

- `search` takes exactly one value. `search=A,B` matches nothing, repeated params keep the last, `search[]=` returns 400, `evseid=` is ignored.
- Keep requests sequential. Firing several at once ran them all into timeouts and returned 504s.
- Pagination is not an escape hatch: hundreds of thousands of stations at a fixed 50 per page, `limit` ignored.

EVSE IDs go stale when hardware is swapped - `hausen-2` and `bahnhofsplatz` silently recorded `0/0` for months before this was caught. The script now exits non-zero when a configured EVSE ID cannot be resolved, while still writing the stations that did resolve (the commit step runs with `if: always()`).

`fetch-data-enbw.sh` is the **legacy, unwired** EnBW scraper (scrapes an APIM subscription key out of the EnBW website, with a hardcoded fallback key). No workflow references it. Don't assume it reflects current behaviour; the README still describes EnBW as the source and is out of date.

## Running things locally

```bash
# Fetch (requires jq and the three WIRELANE_* env vars; overwrites history-data/*.json)
WIRELANE_USERNAME=... WIRELANE_PASSWORD=... WIRELANE_AUTH_TOKEN=... bash ./fetch-data-wirelane.sh

# Generate yesterday's charts (requires a full clone, not a shallow one)
pip3 install pygit2 matplotlib pytz
TZ=Europe/Berlin python3 generate-history-chart.py
```

Both scripts write into the working tree. Restore with `git checkout -- history-data history-charts` when experimenting.

`generate-history-chart.py` only ever produces charts for *yesterday* in `Europe/Berlin` - there is no date argument. To backfill or test another day you have to edit the `yesterday` computation.

## Conventions

- `.editorconfig` applies: 4-space indent, UTF-8, trim trailing whitespace, **no final newline**.
- Committed data JSON is `jq`-formatted (2-space indent) - keep it stable so diffs stay minimal.
- Automated commits use the author `Automated <actions@users.noreply.github.com>`; use a normal authored commit for code changes.
- Charts scale the y-axis from the day's maximum value, not from `numberOfChargePoints`, so a day where a station was never fully free renders a shorter axis than its capacity.
