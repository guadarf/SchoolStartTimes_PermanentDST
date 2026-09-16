# =============================================================================
# 04_national_estimate.R  -- ROUGH nationwide ballpark of pre-sunrise arrivals.
#
# We do NOT have per-school start times nationally, so we apply a fixed REFERENCE
# DEPARTURE (home-leaving) TIME to every US public school (NCES coordinates +
# enrollment) and count, per school and instructional day, whether that departure
# precedes sunrise under each clock regime. Reference departure = 08:00, with
# 07:45 / 08:15 as a sensitivity band.
#
# IMPORTANT (matches the state analysis, which uses departure = start - 20 min):
# the 08:00 value here is the DEPARTURE time and is compared to sunrise directly,
# i.e. NO further commute is subtracted. Equivalently, this assumes a start time of
# 08:20 with a 20-min commute. Because a later departure crosses sunrise on fewer
# mornings, this is the CONSERVATIVE choice (it underestimates the national impact).
#
# This is intentionally a dimensioning number (one sentence in the paper), not a
# substitute for the per-state analysis. Output: paper_materials/national_estimate.csv
#
# Uses each school's per-school standard offset (lutz, via 00_common) and the same
# sunrise model (upper limb, -0.833 deg) and instructional calendar as the states.
# Alaska polar night/day handled explicitly. Memory-light: one day at a time.
# =============================================================================
source("00_common.R")

OUT_CSV <- file.path("paper_materials", "national_estimate.csv")
dir.create("paper_materials", showWarnings = FALSE, recursive = TRUE)

# reference DEPARTURE times (minutes past midnight): 07:45 / 08:00 / 08:15
# (compared to sunrise directly; equivalent start time = departure + 20-min commute)
REF_MIN <- c(`07:45` = 465, `08:00` = 480, `08:15` = 495)

# ---- read the national school file (minimal NCES export in open_data/) -------
nat <- read_csv(NCES_CSV, show_col_types = FALSE) %>%
  transmute(enroll = enrollment, lat = latitude, lon = longitude, abbr = state_abbr) %>%
  filter(!is.na(lat), !is.na(lon), !is.na(enroll), enroll > 0,
         lat > 15, lat < 72, lon > -180, lon < -60)     # plausible US coordinates

# per-school standard UTC offset from coordinates (this is the slow step: ~100k
# point-in-polygon lookups; a couple of minutes).
cat("Assigning time zones to", nrow(nat), "schools via lutz ...\n")
nat$std_offset <- std_offset_from_coords(nat$lat, nat$lon)
nat <- nat %>% filter(!is.na(std_offset))
cat(sprintf("National schools used: %d | students: %s\n",
            nrow(nat), format(sum(nat$enroll), big.mark = ",")))

E <- nat$enroll; off <- nat$std_offset; LAT <- nat$lat; LON <- nat$lon
tot_students <- sum(E)

# ---- accumulate child-days of pre-sunrise arrival, per regime x reference ----
regs <- c("permST", "current", "permDST")
acc  <- matrix(0, nrow = length(REF_MIN), ncol = 3,
               dimnames = list(names(REF_MIN), regs))

for (dnum in as.numeric(SCHOOL_DAYS)) {
  d <- as.Date(dnum, origin = "1970-01-01")
  # "+ 1" on the requested date: see the note in 00_common.R::sunrise_grid --
  # getSunlightTimes() labels the sunrise it returns with the day BEFORE the
  # one requested, at these (western) longitudes.
  s <- getSunlightTimes(data = data.frame(date = d + 1, lat = LAT, lon = LON),
                        keep = SUN_KEEP, tz = "UTC")
  utc_h <- as.numeric(difftime(s[[SUN_KEEP]],
             as.POSIXct(paste0(d, " 00:00:00"), tz = "UTC"), units = "hours"))
  # polar handling: no sunrise -> polar night (always dark) or polar day (never)
  doy    <- as.integer(format(d, "%j"))
  decl   <- -23.44 * cos((360 / 365) * (doy + 10) * pi / 180)
  altn   <- 90 - abs(LAT - decl)                       # max daily solar altitude
  no_sun <- is.na(utc_h)
  pnight <- no_sun & (altn < TWI_ANGLE)

  sr_permST  <- utc_h + off                            # sunrise clock-hour by regime
  sr_current <- utc_h + off + if (is_dst(d)) 1 else 0
  sr_permDST <- utc_h + off + 1

  dark_enroll <- function(sr, refh) {
    dk <- refh < sr                                    # arrival before sunrise
    dk[no_sun] <- pnight[no_sun]                       # polar night dark / day light
    sum(E[dk], na.rm = TRUE)
  }
  for (i in seq_along(REF_MIN)) {
    refh <- REF_MIN[[i]] / 60
    acc[i, "permST"]  <- acc[i, "permST"]  + dark_enroll(sr_permST,  refh)
    acc[i, "current"] <- acc[i, "current"] + dark_enroll(sr_current, refh)
    acc[i, "permDST"] <- acc[i, "permDST"] + dark_enroll(sr_permDST, refh)
  }
}

# ---- assemble + write --------------------------------------------------------
res <- data.frame(
  ref_time            = names(REF_MIN),
  total_students      = tot_students,
  school_days         = length(SCHOOL_DAYS),
  child_days_permST   = round(acc[, "permST"]),
  child_days_current  = round(acc[, "current"]),
  child_days_permDST  = round(acc[, "permDST"]),
  mean_days_per_child_permST  = round(acc[, "permST"]  / tot_students, 1),
  mean_days_per_child_current = round(acc[, "current"] / tot_students, 1),
  mean_days_per_child_permDST = round(acc[, "permDST"] / tot_students, 1),
  extra_child_days_permDST_vs_current = round(acc[, "permDST"] - acc[, "current"]),
  extra_child_days_permDST_vs_permST  = round(acc[, "permDST"] - acc[, "permST"]),
  row.names = NULL)

write_csv(res, OUT_CSV)
cat("\nNational estimate (reference-arrival ballpark):\n")
print(res)
cat(sprintf("\nHeadline (08:00 reference): permanent DST adds ~%s child-days of pre-sunrise\n",
            format(res$extra_child_days_permDST_vs_current[res$ref_time == "08:00"], big.mark = ",")))
cat("arrival vs the current system nationwide. Written to", OUT_CSV, "\n")
