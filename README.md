# Dark morning school commutes under permanent DST

Code and data for quantifying how often U.S. schoolchildren would have to travel to
school **before sunrise** under three clock-policy regimes, for the 2024–25 school
year, across 14 states, plus a national approximation and a Seattle pedestrian-
collision analysis. Motivated by the Sunshine Protection Act (permanent Daylight
Saving Time): permanent DST pushes winter sunrise later on the clock, so more
children commute in darkness.

Everything runs from the single dataset in `open_data/`. The only extra input is
the Seattle collision file, which `06` reuses from a local copy (or downloads if
you set its `Download -> CSV` link).

## Repository layout

```
open_data/
  school_start_times_14states.csv            per-school dataset (all assessed schools)
  school_start_times_14states_DICTIONARY.md  column definitions + inclusion rules
  nces_national_minimal.csv                  national coords+enrollment (for 07)
  SDOT_Collisions.csv                        Seattle collisions for 06 (git-ignored)
00_common.R … 08_inclusion_summary.R         pipeline (see below)
run_all.R                                    master script: reproduces all outputs
install_packages.R                           install deps + print versions
outputs/ , plots/ , paper_materials/         generated (SST/ & departure_20min/ subfolders)
```

## The three clock regimes

Changing the clock policy does not move the sun; it moves the clock label. Sunrise
at a (lat, lon, date) is fixed; what changes is the UTC offset used to read it.

- **Permanent Standard Time (permST)** — standard offset all year.
- **Current system** — Standard Time in winter, DST in summer (2nd Sun Mar → 1st Sun Nov).
- **Permanent Daylight Saving (permDST)** — standard offset + 1 h all year.

Start times are held fixed across regimes. Sunrise = upper solar limb, −0.833°
(`suncalc`). Each school's **standard offset is derived from its coordinates** via
`lutz` (IANA time zone → January offset), which handles states spanning more than
one zone (Idaho, Tennessee, Oregon) automatically. Days with no sunrise are split
into polar night (always dark) / polar day (never) by solar-noon altitude.

## Data

`open_data/school_start_times_14states.csv` has one row per public school across the
14 states that have enacted permanent-DST legislation and are in scope. It lists
**all assessed schools** with an `inclusion_status` flag (included / start_time_not
_found / out_of_scope / no_enrollment / bad_coordinates), so the analytic sample and
every exclusion are transparent. Columns are documented in the accompanying
`_DICTIONARY.md`. NCES data are U.S. public-domain; manually collected start times
are released for reuse. School type (Elementary/Middle/High/Other-Mixed) is analyzed
only for Washington and its Seattle subset (Figure 1); all other states use the
three regime maps and the state-level table only.

## Reproduce

```r
source("install_packages.R")   # once: installs CRAN deps, prints versions
source("run_all.R")            # or: Rscript run_all.R
```

`run_all.R` runs `01`–`04` (per-state analysis, maps, flow, calendars), then the
inclusion summary (`08`), the Washington figure and Table 1 (`05`), the Seattle
crash analysis (`06`), and the national estimate (`07`). Kept figures/plots are
written for both metrics into `SST/` and `departure_20min/` subfolders.

## Scripts

- **`00_common.R`** — config, dataset loader, per-school time zones (`lutz`), DST
  rules, polar handling, sunrise helper, instructional calendar, commute grid.
- **`01_sunrise_analysis.R`** — per-school dark-day metrics, summaries, average SST,
  per-child bar plots (school-type breakdown only for WA/Seattle).
- **`02_maps.R`** — state 3-regime maps (type×regime matrix only for WA/Seattle).
- **`03_flow_diagram.R`** — inclusion/attrition flow per state.
- **`04_sunrise_calendar.R`** — school-year sunrise-vs-start calendar per state.
- **`05_paper_figures.R`** — Washington Figure 1 and multi-state Table 1.
- **`06_seattle_crash_light.R`** — darkness vs. pedestrian involvement (adjusted
  logistic OR); downloads the SDOT collisions CSV.
- **`07_national_estimate.R`** — national reference-departure ballpark (08:00, with
  a 07:45–08:15 band) from `nces_national_minimal.csv`.
- **`08_inclusion_summary.R`** — pooled inclusion/exclusion across states.

## Metrics and sensitivities

- Kept figures/plots are generated for two metrics: **SST** (start time vs sunrise)
  and **departure_20min** (start − 20 min vs sunrise), written to the matching
  subfolders under `plots/`, `outputs/`, and `paper_materials/`.
- Commute buffer sensitivity: 15 / 20 / 27.2 min (`COMMUTE_GRID`) is retained as
  columns in the per-school metrics CSVs (20 min is the main analysis).

## Sources

- School demographics, coordinates, enrollment: NCES ELSi
  (https://nces.ed.gov/ccd/elsi/). ELSi exports have no stable URL, so the derived
  files are deposited in `open_data/`.
- Seattle collisions: SDOT Collisions All Years, Seattle GeoData / ArcGIS Hub
  (https://data-seattlecitygis.opendata.arcgis.com/datasets/SeattleCityGIS::sdot-collisions-all-years).
  `06` reuses a local copy in `open_data/`; set its `Download -> CSV` link to fetch.

## Required R packages

`suncalc`, `lubridate`, `dplyr`, `tidyr`, `readr`, `ggplot2`, `lutz` (analysis);
`sf`, `tigris`, `viridis`, `cowplot` (maps); `DiagrammeR`,
`DiagrammeRsvg`, `rsvg` (flow diagrams). Install with `install_packages.R`.

## License

Code: MIT (see `LICENSE`). Data in `open_data/`: released for reuse (CC0 / CC BY 4.0
recommended).
