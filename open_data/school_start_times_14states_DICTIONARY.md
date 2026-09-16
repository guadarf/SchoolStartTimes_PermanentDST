# School start times dataset — 14 U.S. states

`school_start_times_14states.csv` — one row per public school (2024–25) across the
14 states that have enacted legislation to adopt permanent daylight saving time and
are in scope: Washington, Oregon, Idaho, Utah, Colorado, Wyoming, Oklahoma,
Louisiana, Tennessee, Mississippi, Alabama, Georgia, Maine, Delaware.

School demographics, location, and enrollment are from the NCES Elementary/Secondary
Information System (ELSi); regular instructional start times were collected manually
(see the paper's Extended Methods). The file lists **all assessed schools**, with an
`inclusion_status` flag, so the analytic sample and every exclusion are transparent.

## Columns

| Column | Description |
|---|---|
| `state` | State name. |
| `state_abbr` | Two-letter state abbreviation. |
| `nces_school_id` | NCES 12-digit school ID (unique key). |
| `school_name` | School name (NCES). |
| `district_name` | District name (NCES). |
| `county` | County name (NCES). |
| `latitude` | Latitude, decimal degrees (NCES, 2024–25). Blank if not provided. |
| `longitude` | Longitude, decimal degrees (NCES, 2024–25). Blank if not provided. |
| `enrollment` | Total students, all grades (NCES, 2024–25). Blank if not reported. |
| `start_time` | Regular instructional start time, 24-h `HH:MM`. Blank if not found or not in scope. |
| `start_time_raw` | Start-time cell as collected when not a parseable time (e.g., `call`, `N/A`, blank). |
| `school_level` | Elementary / Middle / High / Other-Mixed, derived from the school name. |
| `inclusion_status` | See below. |

## `inclusion_status` values

| Value | Meaning |
|---|---|
| `included` | Analytic sample: meets inclusion criteria, has a parseable start time, valid coordinates, enrollment > 0. |
| `start_time_not_found` | Eligible (in scope, enrolled) but no start time was located. |
| `out_of_scope` | Flagged as not meeting inclusion criteria (start time recorded as `N/A`). |
| `no_enrollment` | No/zero reported enrollment. |
| `bad_coordinates` | Has a start time but missing/invalid coordinates. |

Inclusion criteria: in-person schools primarily serving students from elementary
through high school. Excluded categories (recorded as `out_of_scope` / not collected):
virtual/non-in-person schools, preschools, closed schools, juvenile detention
centers, reengagement programs, technical/adult-serving and supplementary-class
programs, and schools with highly irregular schedules.

## Notes

- When more than one bell time was reported, class-start time was used (over tardy or
  first bell); optional breakfast times were not considered. Multi-schedule schools
  were summarized as the day-weighted average start time.
- Enrollment and coordinates are 2024–25; start times reflect 2025–26 or 2026–27
  schedules depending on availability.
- Row counts by status (assessed = 18,549; included = 16,093) are reproduced by
  `05_inclusion_summary.R`.

## Source / license

NCES data are U.S. public-domain. Manually collected start times are factual and are
released for reuse. No personal data are included.
