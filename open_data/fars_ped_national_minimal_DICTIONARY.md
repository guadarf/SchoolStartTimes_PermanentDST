# National FARS pedestrian-involvement dataset (minimal, all crashes)

`fars_ped_national_minimal.csv` — one row per fatal motor-vehicle crash in the
NHTSA Fatality Analysis Reporting System (FARS), 2015–2024, **all 50 states +
DC, every day of the year, any time of day**. This file is NOT restricted to
the school-year-weekday/morning window used in the paper — see "Reproducing
the paper's numbers" below for how that sample is derived from it.

This is a **minimal** dataset in the sense of columns and source files, not
rows: it merges the accident- and person-level fields actually needed (from
`accident.csv` / `person.csv`, gitignored due to size, one pair per year)
into a single file, dropping everything else (crash coordinates, other
person-level fields, etc.). It is produced by `06_export_fars_minimal.R`.

The only rows excluded from this file are ones where the darkness flag
literally cannot be computed: invalid/missing coordinates, unknown crash
hour/minute (FARS code 99), or a coordinate whose time zone could not be
resolved. These are data-quality exclusions, not part of the paper's analytic
sample definition; `06_export_fars_minimal.R` prints how many crashes were
dropped for each reason when it runs.

## Columns

| Column | Description |
|---|---|
| `year` | Crash year (2015–2024). |
| `st_case` | NHTSA crash case number. Unique only within a year; use `(year, st_case)` as the crash key. |
| `state` | U.S. state name (FARS `STATENAME`). |
| `date` | Crash date, `YYYY-MM-DD`. |
| `hour` | Crash hour, local clock time, 24-h. |
| `minute` | Crash minute, local clock time. |
| `day_week` | Day of week, FARS convention (1 = Sunday … 7 = Saturday). |
| `weather` | Weather at the time of the crash: `Clear`, `Cloudy`, `Rain`, or `Other` (collapsed from FARS `WEATHERNAME`). |
| `solar_altitude_deg` | Solar altitude (degrees) at the crash's exact time and coordinates, computed with the `suncalc` package. |
| `dark` | `TRUE` if `solar_altitude_deg < -0.833°` (upper solar limb below the horizon, i.e. before sunrise; same threshold used throughout the paper), else `FALSE`. |
| `ped_involved_any` | `TRUE` if a pedestrian of any age was involved in the crash (from FARS `PEDS > 0`, cross-checked against person-level records). |
| `ped_involved_5to18` | `TRUE` if a pedestrian aged 5–18 was involved in the crash. |

Crash-level latitude/longitude, and any person-level fields other than the two
pedestrian-involvement flags above (e.g., individual ages, injury severity),
are intentionally **not** included — they are not needed for the paper's
analysis and this keeps the file minimal.

## Reproducing the paper's numbers

The paper's analytic sample (real school-year weekdays, 07:00–08:30 local
time) is derived from this file at analysis time by `fars_school_window()`
(defined once in `00_common.R`, so the exact same filter is used everywhere
it matters — not re-implemented separately in each script):

```r
source("00_common.R")
df  <- read_csv("open_data/fars_ped_national_minimal.csv")
win <- fars_school_window(df)   # -> the paper's analytic sample

m <- glm(ped_involved_any ~ dark + factor(hour) + weather, data = win, family = binomial)
exp(coef(m)["darkTRUE"])                      # adjusted OR = 1.77
exp(confint.default(m)["darkTRUE", ])         # 95% CI 1.55-2.02

m2 <- glm(ped_involved_5to18 ~ dark + factor(hour) + weather, data = win, family = binomial)
exp(coef(m2)["darkTRUE"])                     # adjusted OR = 2.22
exp(confint.default(m2)["darkTRUE", ])        # 95% CI 1.50-3.29
```

`07_fars_paper_analysis.R` runs exactly this, and `06_export_fars_minimal.R`
runs the identical check on the file it just wrote, so any discrepancy
between the two would be caught immediately.

## Notes

- Fatal crashes only (FARS is a census of fatal motor-vehicle crashes, not
  all crashes). "Pedestrian involved" means present in the crash, not
  necessarily the person who died.
- This file is intentionally **not** pre-filtered to the school-year/weekday/
  morning window, so the sample definition stays auditable in code
  (`fars_school_window()`) rather than hidden inside a pre-filtered CSV.
- The 14-state breakdown, the crash-rate (as opposed to composition)
  analysis, and any other outcome are not derived from or included in this
  file; only the two composition outcomes cited in the paper are computed.

## Source / license

NHTSA FARS data are U.S. public-domain (https://www.nhtsa.gov/research-data/fatality-analysis-reporting-system-fars).
No personal data are included — FARS is already de-identified at the point of
public release, and this file drops even the crash coordinates.
