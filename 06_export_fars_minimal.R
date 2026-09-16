# =============================================================================
# 06_export_fars_minimal.R -- exports a MINIMAL, repository-safe dataset from
# the raw NHTSA FARS bulk files: only the columns and files actually needed,
# merged across all 10 years (2015-2024) into ONE csv. This mirrors how the
# other open datasets in this repo are built (school_start_times_14states.csv,
# nces_national_minimal.csv): "minimal" means trimmed COLUMNS and SOURCE
# FILES, not a pre-filtered analytic subsample -- every fatal crash nationwide
# is included (any day of the week, any time, any month), so the school-year /
# weekday / 07:00-08:30 window used in the paper is applied later, in code
# (fars_school_window(), defined once in 00_common.R), not baked into this
# file. That keeps the sample definition auditable in one place instead of
# hidden inside a pre-filtered CSV -- see 07_fars_paper_analysis.R, which
# applies that same function to reproduce the two numbers cited in the paper.
#
# The only rows dropped here are ones where the darkness flag literally
# cannot be computed: invalid/missing coordinates, unknown crash hour/minute
# (FARS code 99), or a coordinate whose time zone could not be resolved.
# These are data-quality exclusions, not analytic choices -- counts for each
# are printed below.
#
# Output: open_data/fars_ped_national_minimal.csv
#         open_data/fars_ped_national_minimal_DICTIONARY.md (written separately)
#
# Needs the raw open_data/FARS<YEAR>National/accident.csv + person.csv files
# (gitignored, not distributed -- see README for how to obtain them from
# NHTSA). Most users won't need to run this: the exported file is already
# tracked in the repository.
# =============================================================================
source("00_common.R")   # TWI_ANGLE; dplyr/lubridate/suncalc/lutz/readr already loaded

# ---- discover available years ------------------------------------------------
year_dirs <- list.dirs("open_data", recursive = FALSE)
year_dirs <- year_dirs[grepl("FARS[0-9]{4}National$", year_dirs)]
years_found <- as.integer(sub(".*FARS([0-9]{4})National$", "\\1", year_dirs))
if (length(years_found) == 0) stop("No open_data/FARS<YEAR>National/ folders found.")
dir_by_year <- setNames(year_dirs, years_found)
cat("FARS years found:", paste(sort(years_found), collapse = ", "), "\n")

# ---- read accident.csv + person.csv for one year (only needed columns) -------
NEED_ACC <- c("STATE","STATENAME","ST_CASE","PEDS","MONTH","DAY","YEAR","HOUR","MINUTE",
              "DAY_WEEK","LATITUDE","LONGITUD","WEATHERNAME")
NEED_PER <- c("STATE","ST_CASE","AGE","PER_TYPNAME","INJ_SEVNAME")

read_year <- function(yr, dir) {
  acc <- read_csv(file.path(dir, "accident.csv"), show_col_types = FALSE, locale = locale(encoding = "latin1"))
  names(acc)[1] <- "STATE"
  acc <- acc %>% select(all_of(NEED_ACC)) %>% mutate(YEAR = yr)
  per <- read_csv(file.path(dir, "person.csv"), show_col_types = FALSE, locale = locale(encoding = "latin1"))
  names(per)[1] <- "STATE"
  per <- per %>% select(all_of(NEED_PER)) %>% mutate(YEAR = yr)
  list(acc = acc, per = per)
}

raw     <- lapply(as.character(years_found), function(y) read_year(as.integer(y), dir_by_year[[y]]))
acc_all <- dplyr::bind_rows(lapply(raw, `[[`, "acc"))
per_all <- dplyr::bind_rows(lapply(raw, `[[`, "per"))
cat(sprintf("Accidents read (ALL crashes, nationwide, %d-%d): %d | person-records read: %d\n",
            min(years_found), max(years_found), nrow(acc_all), nrow(per_all)))

# ---- pedestrian-involvement flags (from person-level records) ----------------
ped_only <- per_all %>% filter(PER_TYPNAME == "Pedestrian")
ped_involved_child_cases <- ped_only %>% filter(!is.na(AGE), AGE >= 5, AGE <= 18) %>%
  distinct(YEAR, ST_CASE) %>% mutate(ped_involved_child = TRUE)

# ---- data-quality filters ONLY (no analytic-sample / school-window filter) --
# Every crash is kept regardless of day of week, month, or time of day; only
# records for which the darkness flag cannot be computed at all are dropped.
n_total <- nrow(acc_all)
d <- acc_all %>%
  mutate(date = as.Date(sprintf("%04d-%02d-%02d", YEAR, MONTH, DAY)))

n_bad_coords <- sum(!(d$LATITUDE <= 72 & abs(d$LONGITUD) <= 180))
n_bad_time   <- sum(d$HOUR == 99 | d$MINUTE == 99)

d <- d %>%
  filter(LATITUDE <= 72, abs(LONGITUD) <= 180, HOUR != 99, MINUTE != 99) %>%
  mutate(ped_involved_any = PEDS > 0,
         weather2 = case_when(
           WEATHERNAME == "Clear"  ~ "Clear",
           WEATHERNAME == "Cloudy" ~ "Cloudy",
           WEATHERNAME == "Rain"   ~ "Rain",
           TRUE                   ~ "Other")) %>%
  left_join(ped_involved_child_cases, by = c("YEAR", "ST_CASE")) %>%
  mutate(ped_involved_child = coalesce(ped_involved_child, FALSE))

# ---- solar altitude at each crash's own location/instant ---------------------
d <- d %>% mutate(tzid = lutz::tz_lookup_coords(LATITUDE, LONGITUD, method = "accurate", warn = FALSE))
n_tz_na <- sum(is.na(d$tzid))
if (n_tz_na > 0) d <- d %>% filter(!is.na(tzid))

d <- d %>%
  mutate(.dt_char = sprintf("%04d-%02d-%02d %02d:%02d:00", YEAR, MONTH, DAY, HOUR, MINUTE)) %>%
  group_by(tzid) %>%
  mutate(dt_local = force_tz(ymd_hms(.dt_char, quiet = TRUE), tzone = dplyr::first(tzid))) %>%
  ungroup() %>%
  select(-.dt_char)

pos <- getSunlightPosition(data = data.frame(date = with_tz(d$dt_local, "UTC"),
                                             lat = d$LATITUDE, lon = d$LONGITUD),
                           keep = "altitude")
d <- d %>% mutate(alt_deg = pos$altitude * 180 / pi, dark = alt_deg < TWI_ANGLE)

cat(sprintf("\nData-quality exclusions (out of %d total crashes, %d-%d):\n", n_total, min(years_found), max(years_found)))
cat(sprintf("  invalid/missing coordinates: %d\n", n_bad_coords))
cat(sprintf("  unknown crash hour/minute (FARS code 99): %d\n", n_bad_time))
cat(sprintf("  unresolvable time zone from coordinates: %d\n", n_tz_na))
cat(sprintf("Rows in the exported minimal file: %d (ALL times/days kept -- no school-window filter applied here)\n", nrow(d)))

# =============================================================================
# Minimal export -- only the columns needed downstream, for ALL crashes (any
# day, any time) that survived the data-quality filters above. The school-
# year / weekday / 07:00-08:30 window used in the paper is applied later by
# fars_school_window() (00_common.R), not here.
# =============================================================================
out <- d %>%
  transmute(
    year               = YEAR,
    st_case            = ST_CASE,
    state              = STATENAME,
    date               = date,
    hour               = HOUR,
    minute             = MINUTE,
    day_week           = DAY_WEEK,
    weather            = weather2,
    solar_altitude_deg = round(alt_deg, 3),
    dark               = dark,
    ped_involved_any   = ped_involved_any,
    ped_involved_5to18 = ped_involved_child
  )

write_csv(out, "open_data/fars_ped_national_minimal.csv")
cat(sprintf("\nWrote %d rows (ALL FARS fatal crashes nationwide, %d-%d) to open_data/fars_ped_national_minimal.csv\n",
            nrow(out), min(years_found), max(years_found)))

# ---- sanity check: apply the SAME school-window filter used by the paper's --
# analysis script, on the just-exported data, and confirm it reproduces the
# two cited numbers.
cat("\n---- Sanity check (apply fars_school_window() to the exported file, should match the paper) ----\n")
win <- fars_school_window(out)
cat(sprintf("Crashes in the paper's analytic sample (real school-year weekdays, 07:00-08:30): %d\n", nrow(win)))

check_outcome <- function(data, outcome_col, label) {
  data$ped <- data[[outcome_col]]
  tab <- table(dark = data$dark, ped = data$ped)
  ft  <- fisher.test(tab)
  m   <- glm(ped ~ dark + factor(hour) + weather, data = data, family = binomial)
  ci  <- exp(confint.default(m)["darkTRUE", ])
  cat(sprintf("%s: N=%d, outcome-positive=%d | crude OR=%.2f | adjusted OR=%.2f (95%% CI %.2f-%.2f)\n",
              label, nrow(data), sum(data$ped), ft$estimate, exp(coef(m)["darkTRUE"]), ci[1], ci[2]))
}
check_outcome(win, "ped_involved_any",   "Pedestrian involved, any age")
check_outcome(win, "ped_involved_5to18", "Pedestrian involved, ages 5-18")
cat("\nExpected from the manuscript: any age adjusted OR = 1.77 (95% CI 1.55-2.02);\n")
cat("ages 5-18 adjusted OR = 2.22 (95% CI 1.50-3.29). Compare against the two lines above.\n")
