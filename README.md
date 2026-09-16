# Dark morning school commutes under permanent DST

Code and data for quantifying how often U.S. schoolchildren would have to travel to
school **before sunrise** under three clock-policy regimes, for the 2024–25 school
year, across 14 states, plus a national approximation and a national pedestrian-
safety analysis (NHTSA FARS). Motivated by the Sunshine Protection Act (permanent
Daylight Saving Time): permanent DST pushes winter sunrise later on the clock, so
more children commute in darkness.

Everything needed to reproduce the current (Current Biology) paper runs from the
datasets already tracked in `open_data/` — no extra downloads required. An earlier
version of the pedestrian-safety analysis, based on Seattle (SDOT) collisions only,
has been archived (see `archive/README.md`); it is no longer part of the paper.

## Repository layout

```
open_data/
  school_start_times_14states.csv            per-school dataset (all assessed schools)
  school_start_times_14states_DICTIONARY.md  column definitions + inclusion rules
  nces_national_minimal.csv                  national coords+enrollment (for 07)
  fars_ped_national_minimal.csv              ALL FARS fatal crashes nationwide (for 11)
  fars_ped_national_minimal_DICTIONARY.md    column definitions
  FARS<YEAR>National/                        raw NHTSA FARS bulk files, git-ignored
                                              (only needed to run 10, optional)
  SDOT_Collisions.csv                        Seattle collisions, git-ignored
                                              (only needed for the archived analysis)
00_common.R … 05_inclusion_summary.R         pipeline (see below)
06_export_fars_minimal.R, 07_fars_paper_analysis.R
                                              FARS pedestrian-safety analysis (see below)
archive/06_seattle_crash_light.R, archive/02_maps.R, archive/03_flow_diagram.R
                                              superseded / PNAS-supplementary-only (see archive/README.md)
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

`open_data/fars_ped_national_minimal.csv` has one row per FARS fatal crash
nationwide, 2015–2024 -- **every crash, any day, any time**, not pre-filtered
to the paper's analytic window. It carries no coordinates or person-level
fields beyond the two pedestrian-involvement outcomes needed for the paper.
The real-school-year-weekday, 07:00–08:30 window actually used for the
paper's result is applied at analysis time by `fars_school_window()`
(`00_common.R`), so the sample definition stays auditable in code rather than
baked into the file — see the `_DICTIONARY.md` for columns and details.

## Reproduce

```r
source("install_packages.R")   # once: installs CRAN deps, prints versions
source("run_all.R")            # or: Rscript run_all.R
```

`run_all.R` runs `01` and `02` (per-state analysis, calendars), then the
inclusion summary (`05`), the Washington figure and Table 1 (`03`), the national
estimate (`04`), and the FARS pedestrian-safety result cited in the paper (`07`,
from the tracked minimal dataset — no download needed). If raw FARS bulk files
have been downloaded locally (see `06`'s header), it also re-runs the
minimal-dataset export (`06`); this is optional and skipped automatically
otherwise. Kept figures/plots are written for both metrics into `SST/` and
`departure_20min/` subfolders. `archive/02_maps.R` and `archive/03_flow_diagram.R`
(per-state maps and flow diagrams, PNAS-supplementary-only) are not part of
this pipeline — see `archive/README.md`.

## Scripts

- **`00_common.R`** — config, dataset loader, per-school time zones (`lutz`), DST
  rules, polar handling, sunrise helper, instructional calendar, commute grid.
- **`01_sunrise_analysis.R`** — per-school dark-day metrics, summaries, average SST,
  per-child bar plots (school-type breakdown only for WA/Seattle).
- **`02_sunrise_calendar.R`** — school-year sunrise-vs-start calendar per state.
- **`03_paper_figures.R`** — Washington Figure 1 and multi-state Table 1.
- **`04_national_estimate.R`** — national reference-departure ballpark (08:00, with
  a 07:45–08:15 band) from `nces_national_minimal.csv`.
- **`05_inclusion_summary.R`** — pooled inclusion/exclusion across states.
- **`06_export_fars_minimal.R`** — re-derives `fars_ped_national_minimal.csv`
  (ALL FARS fatal crashes nationwide, not analytic-sample-filtered) from the raw
  FARS bulk files; needs `open_data/FARS<YEAR>National/` (not distributed here,
  see the script's header). Only needed to regenerate that file; most users
  won't need to run this.
- **`07_fars_paper_analysis.R`** — applies `fars_school_window()` (`00_common.R`)
  to `fars_ped_national_minimal.csv` to derive the paper's analytic sample, then
  reproduces the cited FARS result (adjusted OR = 1.77, any age; OR = 2.22, ages
  5–18). No raw-data download needed.

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
- National fatal-crash records: NHTSA Fatality Analysis Reporting System (FARS)
  (https://www.nhtsa.gov/research-data/fatality-analysis-reporting-system-fars).
  Raw bulk files are only needed to run `06`; the derived, repository-tracked
  `fars_ped_national_minimal.csv` (all crashes, filtered to the paper's sample
  at analysis time by `fars_school_window()`) is sufficient to reproduce the
  paper's result.
- Seattle collisions (archived analysis only): SDOT Collisions All Years, Seattle
  GeoData / ArcGIS Hub
  (https://data-seattlecitygis.opendata.arcgis.com/datasets/SeattleCityGIS::sdot-collisions-all-years).
  `archive/06_seattle_crash_light.R` reuses a local copy in `open_data/`; set its
  `Download -> CSV` link to fetch.

## Required R packages

`suncalc`, `lubridate`, `dplyr`, `tidyr`, `readr`, `ggplot2`, `lutz` (analysis);
`sf`, `tigris`, `viridis`, `cowplot` (maps); `DiagrammeR`,
`DiagrammeRsvg`, `rsvg` (flow diagrams). Install with `install_packages.R`.

## License

Code: MIT (see `LICENSE`). Data in `open_data/`: released for reuse (CC0 / CC BY 4.0
recommended).
