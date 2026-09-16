# =============================================================================
# 02_sunrise_calendar.R  -- school-year sunrise-vs-start calendar, per state (ALL).
# For each day: enrollment-weighted mean gap between sunrise (each school's own,
# with its own time zone) and the mean start time.
#   DARK  = mean SST before sunrise (dark start)   |  LIGHT = SST after sunrise
# School-year months Sep->Jun in one strip (winter centred); Permanent ST vs
# Permanent DST stacked; with and without commute.
# Outputs: plots/<State>_calendar.png, plots/<State>_calendar_commute20.png
# =============================================================================
source("00_common.R")

CAL_DAYS <- seq(as.Date("2024-09-01"), as.Date("2025-06-30"), by = "day")

# ---- calendar layout (school-year strip, winter centred; locale-safe) -------
gapx <- 1.8
sm <- data.frame(sy = 1:10,
                 yr = c(2024,2024,2024,2024,2025,2025,2025,2025,2025,2025),
                 mo = c(9,10,11,12,1,2,3,4,5,6),
                 label = c("Sep","Oct","Nov","Dec","Jan","Feb","Mar","Apr","May","Jun"))
sm$first_off <- vapply(seq_len(nrow(sm)), function(i)
  as.integer(lubridate::wday(as.Date(sprintf("%d-%02d-01", sm$yr[i], sm$mo[i])), week_start = 1)) - 1L, integer(1))
LAY <- data.frame(date = CAL_DAYS) %>%
  mutate(yr = year(date), mo = month(date), dom = mday(date)) %>%
  left_join(sm, by = c("yr","mo")) %>%
  mutate(cell = dom - 1 + first_off, wk = cell %/% 7, dcol = cell %% 7,
         x = (sy - 1) * (7 + gapx) + (dcol + 1), y = wk + 2)
MLAB <- sm %>% mutate(x = (sy - 1) * (7 + gapx) + 4, y = 1)

calendar_state <- function(state) {
  slug <- slugify(state)
  df <- read_state(state)
  meanSST <- weighted.mean(df$SST_min, df$enroll, na.rm = TRUE)

  # enrollment-weighted mean sunrise (permanent ST) per day; permDST = +60 min
  # "+ 1" on the requested date: see the note in 00_common.R::sunrise_grid --
  # getSunlightTimes() labels the sunrise it returns with the day BEFORE the
  # one requested, at these (western) longitudes.
  wmeanST <- vapply(CAL_DAYS, function(dd) {
    d <- as.Date(dd, origin = "1970-01-01")
    s <- getSunlightTimes(data = data.frame(date = d + 1, lat = df$lat, lon = df$lon),
                          keep = SUN_KEEP, tz = "UTC")
    h <- as.numeric(difftime(s[[SUN_KEEP]], as.POSIXct(paste0(d, " 00:00:00"), tz = "UTC"), units = "hours"))
    weighted.mean((h + df$std_offset) * 60, df$enroll, na.rm = TRUE)
  }, numeric(1))

  cal <- data.frame(date = CAL_DAYS, sunrise_ST = wmeanST) %>%
    mutate(`Permanent ST`  = sunrise_ST      - meanSST,
           `Permanent DST` = sunrise_ST + 60 - meanSST) %>%
    pivot_longer(c(`Permanent ST`, `Permanent DST`), names_to = "regime", values_to = "gap0") %>%
    mutate(regime = factor(regime, levels = c("Permanent ST", "Permanent DST")))
  write_csv(cal, op("%s_sunrise_calendar_data.csv", slug))

  make_cal <- function(commute, outfile) {
    d <- cal %>% left_join(LAY, by = "date") %>%
      mutate(status = factor(ifelse(gap0 + commute > 0, "Starts before sunrise", "Starts after sunrise"),
                             levels = c("Starts before sunrise", "Starts after sunrise")))
    p <- ggplot(d, aes(x, y, fill = status)) +
      geom_tile(color = "grey80", linewidth = 0.1) +
      geom_text(data = MLAB, aes(x, y, label = label), inherit.aes = FALSE, size = 4, fontface = "bold") +
      facet_wrap(~ regime, ncol = 1) +
      scale_y_reverse() +
      scale_fill_manual(values = c("Starts before sunrise" = "#1a3763",
                                   "Starts after sunrise"  = "#fde3a7"), name = NULL) +
      coord_equal() +
      theme_void(base_size = 14) +
      theme(strip.text = element_text(size = 17, face = "bold"),
            legend.text = element_text(size = 13), legend.position = "bottom",
            panel.spacing = unit(1, "lines"), plot.background = element_rect(fill = "white", color = NA))
    ggsave(outfile, p, width = 21, height = 9.5, dpi = 300, limitsize = FALSE)
  }
  make_cal(0,           pp("%s_calendar.png", slug))
  make_cal(COMMUTE_MIN, pp("%s_calendar_commute%g.png", slug, COMMUTE_MIN))
  cat(sprintf("%-14s mean SST %s  calendars written\n", state, min_to_hhmm(meanSST)))
}

for (st in STATES$state) calendar_state(st)
cat("\nDone. Per-state calendars written to plots/.\n")
