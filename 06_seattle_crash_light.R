# =============================================================================
# 06_seattle_crash_light.R  -- PEDESTRIAN focus.
# Seattle SDOT collisions, SCHOOL-YEAR WEEKDAYS only (Sep-Jun, Mon-Fri).
# Goal: show that, beyond the rush-hour clock effect, DARKNESS raises pedestrian
# involvement in the school-travel window; then translate to expected extra
# pedestrian crashes/year from the mornings that become dark under permanent DST.
#
# Darkness = solar altitude < -0.833 deg at the crash instant (physical; uses the
# real historical local clock, so DST is already reflected). No age in data ->
# "pedestrian" overall; the 07:00-08:30 window is the school-arrival window.
# =============================================================================
suppressPackageStartupMessages({
  library(readr); library(dplyr); library(lubridate); library(suncalc); library(ggplot2)
})

OUT <- "paper_materials/seattle_crash"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
SEA_LAT <- 47.6062; SEA_LON <- -122.3321
W_START <- 7.0; W_END <- 8.5        # 07:00-08:30 school-arrival window (edit here)

# ---- data: SDOT collisions -------------------------------------------------
# The analysis reads open_data/SDOT_Collisions.csv. The full record-level file is
# large and is not stored in the repo. On first run the script uses, in order:
#   (1) open_data/SDOT_Collisions.csv if it already exists;
#   (2) any SDOT collisions CSV already on disk (open_data/ or data/) -> copied in;
#   (3) a direct download, IF you set SDOT_URL to the dataset's "Download -> CSV"
#       link (a single feature-service query paginates, so use the Download button
#       link, not a REST query URL).
# Dataset page: https://data-seattlecitygis.opendata.arcgis.com/datasets/SeattleCityGIS::sdot-collisions-all-years
SDOT_CSV <- "open_data/SDOT_Collisions.csv"
SDOT_URL <- ""    # <- paste the "Download -> CSV" link here to enable auto-download

if (!file.exists(SDOT_CSV)) {
  dir.create("open_data", showWarnings = FALSE, recursive = TRUE)
  local <- head(list.files(c("open_data", "data"),
                           pattern = "SDOT.*Collisions.*\\.csv$",
                           full.names = TRUE, ignore.case = TRUE), 1)
  if (length(local) == 1) {
    message("Using local SDOT file: ", local)
    file.copy(local, SDOT_CSV)
  } else if (nzchar(SDOT_URL)) {
    message("Downloading SDOT collisions CSV (large; may take a few minutes) ...")
    options(timeout = 1800)
    download.file(SDOT_URL, SDOT_CSV, mode = "wb")
  } else {
    stop("SDOT collisions CSV not found. Download it (Download -> CSV) from\n  ",
         "https://data-seattlecitygis.opendata.arcgis.com/datasets/SeattleCityGIS::sdot-collisions-all-years\n",
         "and save it as '", SDOT_CSV, "' (or set SDOT_URL in this script).")
  }
}
raw <- read_csv(SDOT_CSV, col_types = cols_only(
  INCDTTM = col_character(), PEDCOUNT = col_double(), WEATHER = col_character()))

d <- raw %>%
  mutate(dt = mdy_hms(INCDTTM, tz = "America/Los_Angeles", quiet = TRUE),
         ped = coalesce(PEDCOUNT, 0) > 0) %>%
  filter(!is.na(dt), !(hour(dt) == 0 & minute(dt) == 0),
         year(dt) >= 2004, year(dt) <= 2024,
         month(dt) %in% c(9:12, 1:6),        # school-year months
         wday(dt) %in% 2:6)                  # weekdays only

pos <- getSunlightPosition(data = data.frame(date = with_tz(d$dt, "UTC"), lat = SEA_LAT, lon = SEA_LON),
                           keep = "altitude")
d <- d %>% mutate(alt_deg = pos$altitude * 180 / pi,
                  dark = alt_deg < -0.833,
                  light_state = ifelse(dark, "Dark", "Light"),
                  hour = hour(dt), hourdec = hour(dt) + minute(dt) / 60)
cat(sprintf("School-year weekday crashes: %d | pedestrian-involved: %d\n", nrow(d), sum(d$ped)))

# ---- FIG 1: pedestrian share vs solar altitude, MORNING crashes only ---------
p1 <- d %>% filter(hourdec >= 5, hourdec <= 11) %>%
  mutate(altbin = cut(alt_deg, breaks = seq(-30, 45, by = 5))) %>%
  group_by(altbin) %>% summarise(share = mean(ped), n = n(), mid = mean(alt_deg), .groups = "drop") %>%
  filter(n >= 40) %>%
  ggplot(aes(mid, 100 * share)) +
  geom_vline(xintercept = 0, linetype = 2, color = "grey60") +
  geom_line(linewidth = 1, color = "#c0392b") + geom_point() +
  labs(x = "Solar altitude at crash (deg; 0 = horizon)", y = "Pedestrian share of crashes (%)",
       title = "Morning crashes: pedestrian share rises as the sun drops (05:00-11:00)") +
  theme_minimal(base_size = 12)
ggsave(file.path(OUT, "1_morning_ped_share_vs_altitude.png"), p1, width = 9, height = 5, dpi = 300, bg = "white")

# ---- FIG 2 + OR: 07:00-08:30 window, dark vs light --------------------------
win <- d %>% filter(hourdec >= W_START, hourdec < W_END)
tab <- table(dark = win$dark, ped = win$ped); print(tab)
ft <- fisher.test(tab)
win$weather2 <- ifelse(win$WEATHER %in% c("Clear","Overcast","Raining"), win$WEATHER, "Other")
m  <- glm(ped ~ dark + factor(hour) + weather2, data = win, family = binomial)
orA <- exp(coef(m)["darkTRUE"]); ciA <- exp(confint.default(m)["darkTRUE", ])
cat(sprintf("\nWindow 07:00-08:30  pedestrian share: dark=%.2f%%  light=%.2f%%\n",
            100*mean(win$ped[win$dark]), 100*mean(win$ped[!win$dark])))
cat(sprintf("  Crude OR (Fisher)   = %.2f (95%% CI %.2f-%.2f)\n", ft$estimate, ft$conf.int[1], ft$conf.int[2]))
cat(sprintf("  Adjusted OR (hour+weather) = %.2f (95%% CI %.2f-%.2f)\n", orA, ciA[1], ciA[2]))
p2 <- win %>% group_by(light_state) %>% summarise(share = mean(ped), .groups = "drop") %>%
  ggplot(aes(light_state, 100 * share, fill = light_state)) +
  geom_col(width = 0.6) + geom_text(aes(label = sprintf("%.1f%%", 100*share)), vjust = -0.3) +
  scale_fill_manual(values = c(Dark = "#1a3763", Light = "#e0a020"), guide = "none") +
  labs(x = NULL, y = "Pedestrian share of crashes (%)",
       title = "School-arrival window (07:00-08:30): pedestrian share by light") +
  theme_minimal(base_size = 12)
ggsave(file.path(OUT, "2_window_ped_share.png"), p2, width = 6, height = 5, dpi = 300, bg = "white")

# =============================================================================
# EXTRA PEDESTRIAN CRASHES / YEAR from mornings that darken under permanent DST
# =============================================================================
# DST rule for the current system (Seattle standard offset = -8)
nth_sun <- function(y,m,n){ dd<-seq(as.Date(sprintf("%d-%02d-01",y,m)),by="day",length.out=31)
  dd<-dd[format(dd,"%m")==sprintf("%02d",m)]; dd[wday(dd)==1][n] }
is_dst <- function(dates){                                    # vectorized over multiple years
  dates <- as.Date(dates); yrs <- unique(year(dates))
  b  <- setNames(lapply(yrs, function(y) c(nth_sun(y,3,2), nth_sun(y,11,1))), as.character(yrs))
  st <- as.Date(sapply(as.character(year(dates)), function(y) b[[y]][1]), origin = "1970-01-01")
  en <- as.Date(sapply(as.character(year(dates)), function(y) b[[y]][2]), origin = "1970-01-01")
  dates >= st & dates < en
}

# (1) observed per-morning pedestrian crash rate in the window, dark vs light.
#     Denominator = every school-year weekday (mornings with 0 crashes count too).
alld <- data.frame(date = seq(as.Date(min(d$dt)), as.Date(max(d$dt)), by = "day")) %>%
  filter(wday(date) %in% 2:6, month(date) %in% c(9:12, 1:6))
srt <- getSunlightTimes(date = alld$date, lat = SEA_LAT, lon = SEA_LON, keep = "sunrise", tz = "UTC")
utc_h <- as.numeric(difftime(srt$sunrise, as.POSIXct(paste0(alld$date," 00:00:00"), tz="UTC"), units="hours"))
mid <- (W_START + W_END) / 2                                   # window midpoint (07:45)
off_cur <- ifelse(is_dst(alld$date), -7, -8)
alld <- alld %>% mutate(
  sunrise_current = utc_h + off_cur,          # sunrise clock hour, current system
  sunrise_permDST = utc_h - 7,                # sunrise clock hour, permanent DST
  dark_cur  = mid < sunrise_current,          # window midpoint before sunrise?
  dark_pdst = mid < sunrise_permDST)
perday <- win %>% mutate(date = as.Date(dt)) %>%
  group_by(date) %>% summarise(nped = sum(ped), nall = n(), .groups = "drop")
alld <- alld %>% left_join(perday, by = "date") %>%
  mutate(nped = coalesce(nped, 0), nall = coalesce(nall, 0))

# ---- TOTAL crashes per morning: dark vs light (same window, school-yr weekdays)
tot_dark <- mean(alld$nall[alld$dark_cur]); tot_light <- mean(alld$nall[!alld$dark_cur])
tt <- t.test(nall ~ dark_cur, data = alld)
rrT <- exp(coef(glm(nall ~ dark_cur, data = alld, family = poisson))["dark_curTRUE"])
cat(sprintf("\n--- TOTAL crashes per morning (07:00-08:30), dark vs light ---\n"))
cat(sprintf("  mean per morning: dark = %.3f  light = %.3f  (ratio %.2f, +%.0f%%; t-test p = %.2g)\n",
            tot_dark, tot_light, tot_dark/tot_light, 100*(tot_dark/tot_light - 1), tt$p.value))
p3 <- data.frame(state = c("Dark","Light"), rate = c(tot_dark, tot_light)) %>%
  ggplot(aes(state, rate, fill = state)) +
  geom_col(width = 0.6) + geom_text(aes(label = sprintf("%.3f", rate)), vjust = -0.3) +
  scale_fill_manual(values = c(Dark = "#1a3763", Light = "#e0a020"), guide = "none") +
  labs(x = NULL, y = "Total crashes per morning",
       title = "Total crashes per morning (07:00-08:30): dark vs light mornings") +
  theme_minimal(base_size = 12)
ggsave(file.path(OUT, "3_total_crashes_per_morning.png"), p3, width = 6, height = 5, dpi = 300, bg = "white")

rate_dark  <- mean(alld$nped[alld$dark_cur])
rate_light <- mean(alld$nped[!alld$dark_cur])
n_years    <- as.numeric(diff(range(alld$date))) / 365.25
flip_per_year <- sum(!alld$dark_cur & alld$dark_pdst) / n_years   # mornings light now, dark under permDST
extra_per_year <- flip_per_year * (rate_dark - rate_light)

cat(sprintf("\n--- Expected extra pedestrian crashes/year (Seattle, 07:00-08:30 window) ---\n"))
cat(sprintf("  ped crashes per morning: dark=%.4f  light=%.4f  (rate ratio %.2f)\n",
            rate_dark, rate_light, rate_dark/rate_light))
cat(sprintf("  school-year weekday mornings that flip light->dark under permanent DST: %.0f / year\n", flip_per_year))
cat(sprintf("  => extra pedestrian crashes/year in this window ~ %.1f\n", extra_per_year))
cat("\n  (Assumes similar weekday exposure across dark/light school mornings; Seattle only;\n")
cat("   pedestrian crashes overall, ages unknown. Adjusted OR for darkness = ")
cat(sprintf("%.2f.)\n", orA))
cat("\nFigures written to", OUT, "\n")
