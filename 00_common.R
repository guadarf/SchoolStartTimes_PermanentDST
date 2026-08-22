# =============================================================================
# 00_common.R  -- shared config & helpers for the SST-vs-sunrise study.
# Sourced by 01..08. Reads the single open dataset (one row per school, all 14
# states) from open_data/, so the repository is self-contained.
# =============================================================================
suppressPackageStartupMessages({
  library(suncalc); library(lubridate)
  library(dplyr);   library(tidyr); library(readr); library(ggplot2)
  library(lutz)     # per-school IANA time zone from coordinates
})

# ---- Paths (all relative to the repository root) ----------------------------
DATA_DIR    <- "open_data"
DATASET_CSV <- file.path(DATA_DIR, "school_start_times_14states.csv")
NCES_CSV    <- file.path(DATA_DIR, "nces_national_minimal.csv")   # national ballpark input

# ---- Sunrise threshold ------------------------------------------------------
# Sunrise only (upper solar limb, -0.833 deg). The civil-dawn sensitivity option
# has been removed.
SUN_KEEP  <- "sunrise"
TWI_ANGLE <- -0.833
OUT_DIR   <- "outputs"
PLOT_DIR  <- "plots"
dir.create(OUT_DIR,  showWarnings = FALSE, recursive = TRUE)
dir.create(PLOT_DIR, showWarnings = FALSE, recursive = TRUE)
op <- function(fmt, ...) file.path(OUT_DIR,  sprintf(fmt, ...))
pp <- function(fmt, ...) file.path(PLOT_DIR, sprintf(fmt, ...))

# ---- Metric variant (kept figures are produced for both) --------------------
# "SST"             = start time vs sunrise (commute = 0)
# "departure_20min" = departure (start - 20 min) vs sunrise
# ppv()/opv() write into plots/<variant>/ and outputs/<variant>/ subfolders.
variant_dir <- function(commute) if (commute > 0) "departure_20min" else "SST"
ppv <- function(commute, fmt, ...) {
  d <- file.path(PLOT_DIR, variant_dir(commute)); dir.create(d, showWarnings = FALSE, recursive = TRUE)
  file.path(d, sprintf(fmt, ...))
}
opv <- function(commute, fmt, ...) {
  d <- file.path(OUT_DIR, variant_dir(commute)); dir.create(d, showWarnings = FALSE, recursive = TRUE)
  file.path(d, sprintf(fmt, ...))
}

# ---- The open dataset (one row per school; see the data dictionary) ----------
SCHOOLS <- read_csv(DATASET_CSV, show_col_types = FALSE,
                    col_types = cols(nces_school_id = col_character(),
                                     start_time     = col_character(),
                                     start_time_raw = col_character()))
# Inclusion-status groupings used throughout:
INCLUDED_STATUS <- "included"                                     # analytic sample
ELIGIBLE_STATUS <- c("included", "start_time_not_found", "bad_coordinates")  # meet criteria

# Regions to process. `csv_state` = state label in the dataset; `abbr` = for map
# geometry; `district_filter` = optional regex on district_name (e.g. Seattle).
# School type (Elementary/Middle/High/Other-Mixed) is analyzed only for the states
# below flagged by_type = TRUE (Washington + its Seattle subset, used in Figure 1).
STATES_ALL <- tibble::tribble(
  ~state,        ~csv_state,    ~abbr, ~district_filter, ~by_type,
  "Washington",  "Washington",  "WA",  NA,               TRUE,
  "Oregon",      "Oregon",      "OR",  NA,               FALSE,
  "Idaho",       "Idaho",       "ID",  NA,               FALSE,
  "Utah",        "Utah",        "UT",  NA,               FALSE,
  "Colorado",    "Colorado",    "CO",  NA,               FALSE,
  "Wyoming",     "Wyoming",     "WY",  NA,               FALSE,
  "Oklahoma",    "Oklahoma",    "OK",  NA,               FALSE,
  "Louisiana",   "Louisiana",   "LA",  NA,               FALSE,
  "Tennessee",   "Tennessee",   "TN",  NA,               FALSE,
  "Mississippi", "Mississippi", "MS",  NA,               FALSE,
  "Alabama",     "Alabama",     "AL",  NA,               FALSE,
  "Georgia",     "Georgia",     "GA",  NA,               FALSE,
  "Maine",       "Maine",       "ME",  NA,               FALSE,
  "Delaware",    "Delaware",    "DE",  NA,               FALSE,
  "Seattle",     "Washington",  "WA",  "Seattle",        TRUE   # subset of WA
)
STATES <- STATES_ALL[STATES_ALL$csv_state %in% unique(SCHOOLS$state), ]

COMMUTE_MIN  <- 20                 # default student commute (min)
COMMUTE_GRID <- c(15, 20, 27.2)    # commute sensitivity values
SOLSTICE     <- as.Date("2024-12-21")

# ---- Instructional calendar (generic; one for all states) -------------------
SCHOOL_START <- as.Date("2024-09-04")
SCHOOL_END   <- as.Date("2025-06-20")
# Every element must already be class Date before entering c(): c() dispatches on
# the class of its first argument, so wrapping each piece in as.Date() avoids a
# silent coercion of the seq()-generated Date vectors.
NON_SCHOOL <- c(
  as.Date(c("2024-09-02","2024-11-11","2024-11-28","2024-11-29")),
  seq(as.Date("2024-12-23"), as.Date("2025-01-03"), by = "day"),
  as.Date("2025-01-20"),
  seq(as.Date("2025-02-17"), as.Date("2025-02-21"), by = "day"),
  seq(as.Date("2025-04-07"), as.Date("2025-04-11"), by = "day"),
  as.Date("2025-05-26"))

slugify <- function(s) gsub("_+$", "", gsub("[^A-Za-z0-9]+", "_", s))

.all_days   <- seq(SCHOOL_START, SCHOOL_END, by = "day")
SCHOOL_DAYS <- {
  wd <- .all_days[lubridate::wday(.all_days) %in% 2:6]      # Mon..Fri
  wd[!wd %in% NON_SCHOOL]
}

# ---- DST rules (2nd Sun Mar -> 1st Sun Nov), vectorized ---------------------
nth_sunday <- function(year, month, n) {
  first <- as.Date(sprintf("%04d-%02d-01", year, month)); d <- first + 0:31
  d <- d[month(d) == month]; d[lubridate::wday(d) == 1][n]
}
dst_start <- function(y) nth_sunday(y, 3, 2)
dst_end   <- function(y) nth_sunday(y, 11, 1)
is_dst <- function(d) {
  d <- as.Date(d); yrs <- unique(year(d))
  b  <- setNames(lapply(yrs, function(y) c(dst_start(y), dst_end(y))), as.character(yrs))
  ds <- as.Date(sapply(as.character(year(d)), function(y) b[[y]][1]), origin = "1970-01-01")
  de <- as.Date(sapply(as.character(year(d)), function(y) b[[y]][2]), origin = "1970-01-01")
  d >= ds & d < de
}

min_to_hhmm <- function(m) sprintf("%02d:%02d", m %/% 60, round(m %% 60))

# ---- Start-time parser (time text "HH:MM" / "H:MM AM" / Excel fraction) ------
parse_sst_min <- function(x) {
  if (inherits(x, "POSIXct")) return(hour(x) * 60 + minute(x))
  if (inherits(x, "hms"))     return(as.numeric(x) / 60)
  xc  <- trimws(as.character(x))
  num <- suppressWarnings(as.numeric(xc))
  out <- rep(NA_real_, length(xc))
  frac <- !is.na(num) & num > 0 & num < 1
  out[frac] <- round(num[frac] * 24 * 60)
  hm <- grepl("^[0-9]{1,2}:[0-9]{2}", xc) & is.na(out)
  out[hm] <- vapply(xc[hm], function(s) {
    p <- as.integer(strsplit(s, ":")[[1]]); p[1] * 60 + p[2]
  }, numeric(1))
  out
}

# ---- Per-school STANDARD (winter) UTC offset from coordinates ----------------
# lutz maps (lat, lon) to its IANA time zone; the STANDARD offset is the zone's
# wall clock minus UTC on a mid-January date (Standard Time everywhere in the US).
# Base-R offset (system tz database) avoids depending on lutz::tz_offset's schema.
.std_off_cache <- new.env(parent = emptyenv())
tz_std_offset <- function(z) {
  if (is.na(z) || !nzchar(z)) return(NA_real_)
  hit <- .std_off_cache[[z]]; if (!is.null(hit)) return(hit)
  t <- as.POSIXct("2025-01-15 00:00:00", tz = "UTC")
  v <- tryCatch({
    lt <- as.POSIXct(format(t, tz = z), tz = "UTC")
    as.numeric(difftime(lt, t, units = "hours"))
  }, error = function(e) NA_real_)
  assign(z, v, envir = .std_off_cache); v
}
std_offset_from_coords <- function(lat, lon) {
  tzname <- lutz::tz_lookup_coords(lat, lon, method = "accurate", warn = FALSE)
  vapply(tzname, tz_std_offset, numeric(1), USE.NAMES = FALSE)
}

# ---- Reader: analytic sample for one region, from the open dataset -----------
# Returns the included schools with a parseable start time, valid coordinates, and
# per-school standard offset. `state` is any row of STATES (a state, or Seattle).
read_state <- function(state) {
  info <- STATES[STATES$state == state, ]
  d <- SCHOOLS[SCHOOLS$state == info$csv_state &
               SCHOOLS$inclusion_status == INCLUDED_STATUS, , drop = FALSE]
  if (!is.na(info$district_filter))
    d <- d[grepl(info$district_filter, d$district_name, ignore.case = TRUE), , drop = FALSE]
  tibble(
    SchoolName  = d$school_name,
    enroll      = d$enrollment,
    lat         = d$latitude,
    lon         = d$longitude,
    SST_min     = parse_sst_min(d$start_time),
    SchoolID    = as.character(d$nces_school_id),
    state       = state,
    school_type = factor(d$school_level,
                         levels = c("Elementary","Middle","High","Other/Mixed")),
    std_offset  = std_offset_from_coords(d$latitude, d$longitude)
  ) %>% filter(!is.na(SST_min), !is.na(lat), !is.na(lon), !is.na(std_offset), enroll > 0)
}

# ---- Sunrise clock minutes per school x day under the 3 regimes --------------
# Uses each school's own standard offset. Polar handling: when the sun never
# reaches the threshold, split into polar NIGHT (always dark -> +Inf) and polar
# DAY (never dark -> -Inf) by the solar-noon altitude.
sunrise_grid <- function(df, dates) {
  grid <- tidyr::crossing(row = seq_len(nrow(df)), date = dates) %>%
    mutate(lat = df$lat[row], lon = df$lon[row], std_offset = df$std_offset[row])
  s <- getSunlightTimes(data = data.frame(date = grid$date, lat = grid$lat, lon = grid$lon),
                        keep = SUN_KEEP, tz = "UTC")
  utc_h <- as.numeric(difftime(s[[SUN_KEEP]],
                               as.POSIXct(paste0(grid$date, " 00:00:00"), tz = "UTC"),
                               units = "hours"))
  doy      <- as.integer(format(grid$date, "%j"))
  decl     <- -23.44 * cos((360 / 365) * (doy + 10) * pi / 180)
  alt_noon <- 90 - abs(grid$lat - decl)
  no_sun   <- is.na(utc_h)
  polar_night <- no_sun & (alt_noon < TWI_ANGLE)
  clock <- function(extra) {
    v <- (utc_h + grid$std_offset + extra) * 60
    v[no_sun] <- ifelse(polar_night[no_sun], Inf, -Inf)
    v
  }
  grid %>% mutate(
    utc_h           = utc_h,
    sunrise_permST  = clock(0),
    sunrise_permDST = clock(1),
    sunrise_current = clock(ifelse(is_dst(date), 1, 0))
  )
}
