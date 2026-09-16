# =============================================================================
# 03_paper_figures.R  -- Current Biology Report materials.
# Builds, for BOTH metrics (SST = no commute; departure = SST - 20 min):
#   - a multipanel Washington FIGURE:
#       A calendar (school-year, 3 regimes)
#       B Washington point map (3 regimes) with a Seattle inset
#       C bar chart of dark-start days per child, by school type (3 regimes)
#   - a multi-state TABLE (child-mornings in darkness by regime).
# Everything is written to "paper_materials/" (SST and departure_20min subfolders).
# =============================================================================
source("00_common.R")
suppressPackageStartupMessages({
  library(sf); library(tigris); library(viridis); library(cowplot)
})
options(tigris_use_cache = TRUE)

PAPER_DIR <- "paper_materials"
dir.create(PAPER_DIR, showWarnings = FALSE, recursive = TRUE)
P <- function(f) file.path(PAPER_DIR, f)
# per-metric subfolder inside paper_materials/ (SST or departure_20min)
Pv <- function(commute, f) {
  d <- file.path(PAPER_DIR, variant_dir(commute)); dir.create(d, showWarnings = FALSE, recursive = TRUE)
  file.path(d, f)
}

REG_LV    <- c("Permanent ST", "Current system", "Permanent DST")
LAND_FILL <- "#cfe3f2"
TOTAL_SCHOOL_DAYS <- length(SCHOOL_DAYS)     # denominator for the % metric (183 instructional days)
# Legend/axis name for the color metric. Renamed from "Dark-start days" because it
# already nets out the 20-min commute (school start - 20 min vs sunrise) for the
# commute20 build; "Dark-commute" makes that explicit. The SST-only build (no
# commute subtracted) keeps "Dark-start" since there is no commute in that metric.
metric_label <- function(commute) if (commute > 0) "Dark-commute\ndays (%)" else "Dark-start\ndays (%)"
theme_map <- theme_void(base_size = 12) +
  theme(plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA),
        legend.position = "right", strip.text = element_text(face = "bold", size = 15),
        legend.title = element_text(size = 13), legend.text = element_text(size = 12))

# ---- per-school dark-start days (3 regimes) for a given commute --------------
per_school_dark <- function(df, commute) {
  g <- sunrise_grid(df, SCHOOL_DAYS)
  g$val <- df$SST_min[g$row] - commute
  g %>% group_by(row) %>%
    summarise(`Permanent ST`   = sum(val < sunrise_permST),
              `Current system` = sum(val < sunrise_current),
              `Permanent DST`  = sum(val < sunrise_permDST), .groups = "drop") %>%
    arrange(row)
}

# ---- calendar layout (school-year strip, winter centred) --------------------
gapx <- 1.8
.sm <- data.frame(sy = 1:10, yr = c(rep(2024,4), rep(2025,6)), mo = c(9:12, 1:6),
                  label = c("Sep","Oct","Nov","Dec","Jan","Feb","Mar","Apr","May","Jun"))
.sm$first_off <- vapply(seq_len(nrow(.sm)), function(i)
  as.integer(lubridate::wday(as.Date(sprintf("%d-%02d-01", .sm$yr[i], .sm$mo[i])), week_start = 1)) - 1L, integer(1))
CAL_DAYS <- seq(as.Date("2024-09-01"), as.Date("2025-06-30"), by = "day")
LAY <- data.frame(date = CAL_DAYS) %>%
  mutate(yr = year(date), mo = month(date), dom = mday(date)) %>%
  left_join(.sm, by = c("yr","mo")) %>%
  mutate(cell = dom - 1 + first_off, wk = cell %/% 7, dcol = cell %% 7,
         x = (sy - 1) * (7 + gapx) + (dcol + 1), y = wk + 2)
MLAB <- .sm %>% mutate(x = (sy - 1) * (7 + gapx) + 4, y = 1)

# ---- calendar panel (3 regimes) for a df + commute --------------------------
panel_calendar <- function(df, commute) {
  meanSST <- weighted.mean(df$SST_min, df$enroll, na.rm = TRUE)
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
  base <- meanSST - commute
  # For the AVERAGE school, Permanent ST and the current system are identical in
  # the calendar (confirmed: 0 differing days, with or without commute), because
  # the mean start time is late enough to fall after sunrise in the DST shoulder
  # months. They diverge only for early-starting schools -> shown in panels b, c.
  CAL_LV <- c("Permanent ST / Current system", "Permanent DST")
  cal <- data.frame(date = CAL_DAYS, permST = wmeanST) %>%
    mutate(`Permanent ST / Current system` = permST - base,
           `Permanent DST`                 = permST + 60 - base) %>%
    pivot_longer(all_of(CAL_LV), names_to = "regime", values_to = "gap") %>%
    mutate(regime = factor(regime, levels = CAL_LV)) %>%
    left_join(LAY, by = "date") %>%
    mutate(status = factor(ifelse(gap > 0, "Before sunrise", "After sunrise"),
                           levels = c("Before sunrise", "After sunrise")))
  ggplot(cal, aes(x, y, fill = status)) +
    geom_tile(color = "grey85", linewidth = 0.06) +
    geom_text(data = MLAB, aes(x, y, label = label), inherit.aes = FALSE, size = 3.8, fontface = "bold") +
    facet_wrap(~ regime, ncol = 1) +
    scale_y_reverse() +
    scale_fill_manual(values = c("Before sunrise" = "#1a3763", "After sunrise" = "#fde3a7"), name = NULL) +
    coord_equal() + theme_void(base_size = 12) +
    theme(strip.text = element_text(face = "bold", size = 15, margin = margin(b = 9)),
          legend.position = "bottom", legend.text = element_text(size = 12),
          plot.background = element_rect(fill = "white", color = NA), panel.spacing = unit(0.8, "lines"))
}

# ---- one regime column: WA map (single regime) + its own Seattle inset ------
# Uses cowplot ggdraw/draw_plot for a robust inset (no patchwork nesting).
wa_col <- function(wa_long, sea_long, rg, lims) {
  wamap <- ggplot() +
    geom_sf(data = wa_cty, fill = LAND_FILL, color = "white", linewidth = 0.15) +
    geom_sf(data = wa_st, fill = NA, color = "grey45", linewidth = 0.4) +
    geom_sf(data = wa_long %>% filter(regime == rg) %>% arrange(pct),
            aes(color = pct, size = enroll), alpha = 0.8) +
    scale_color_viridis(option = "magma", direction = -1, limits = lims, guide = "none") +
    scale_size_continuous(range = c(0.2, 3), guide = "none") +
    theme_map +
    theme(legend.position = "none")
  seamap <- ggplot() +
    geom_sf(data = sea_city, fill = LAND_FILL, color = "grey55", linewidth = 0.3) +
    geom_sf(data = sea_long %>% filter(regime == rg) %>% arrange(pct),
            aes(color = pct, size = enroll), alpha = 0.85) +
    scale_color_viridis(option = "magma", direction = -1, limits = lims, guide = "none") +
    scale_size_continuous(range = c(0.2, 2.2), guide = "none") +
    theme_void() +
    theme(legend.position = "none",
          plot.background = element_rect(fill = "white", color = "grey70", linewidth = 0.4))
  # WA drawn a bit smaller (shifted right) with Seattle inset in the TOP-LEFT.
  # Tune the two draw_plot() boxes to reposition/resize:
  ggdraw() +
    draw_plot(wamap,  x = 0.16, y = 0.00, width = 0.82, height = 0.88) +
    draw_plot(seamap, x = 0.17, y = 0.60, width = 0.15, height = 0.26) +
    draw_label("Seattle", x = 0.245, y = 0.875, fontface = "italic", size = 10) +  # label above the inset
    draw_label(rg, x = 0.56, y = 0.90, fontface = "bold", size = 15)   # title above Seattle
}

# ---- bar panel: per-child dark days by school type (3 regimes) --------------
panel_bars <- function(dark_df, enroll, types) {
  d <- dark_df %>% mutate(enroll = enroll, school_type = types) %>%
    pivot_longer(all_of(REG_LV), names_to = "regime", values_to = "dark") %>%
    group_by(school_type, regime) %>%
    summarise(mean_child = weighted.mean(dark, enroll, na.rm = TRUE), .groups = "drop") %>%
    mutate(regime = factor(regime, levels = REG_LV),
           school_type = factor(school_type, levels = c("Elementary","Middle","High","Other/Mixed")))
  ggplot(d, aes(regime, mean_child, fill = regime)) +
    geom_col(width = 0.72) +
    geom_text(aes(label = sprintf("%.1f (%.0f%%)", mean_child, 100 * mean_child / TOTAL_SCHOOL_DAYS)),
              vjust = -0.3, size = 4.3) +
    facet_wrap(~ school_type, nrow = 1) +
    scale_fill_manual(values = c("Permanent ST" = "#2e8b57", "Current system" = "#e0a020",
                                 "Permanent DST" = "#c0392b"), name = NULL) +
    scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
    labs(x = NULL, y = "Days per child") +
    theme_minimal(base_size = 12) +
    theme(axis.text.x = element_blank(), axis.ticks.x = element_blank(),
          axis.title.y = element_text(size = 13), axis.text.y = element_text(size = 11),
          # strip.text (Elementary/Middle/High/Other-Mixed) and the geom_text bar
          # labels above are intentionally left at their original size.
          strip.text = element_text(face = "bold", size = 13),
          legend.position = "bottom", legend.text = element_text(size = 12),
          plot.background = element_rect(fill = "white", color = NA))
}

# ---- geometries -------------------------------------------------------------
proj    <- 32610   # UTM 10N: keeps Washington roughly north-up (no Albers tilt)
wa_st   <- suppressMessages(states(cb = TRUE, year = 2023)) %>% filter(STUSPS == "WA") %>% st_transform(proj)
wa_cty  <- suppressMessages(counties(state = "WA", cb = TRUE, year = 2023)) %>% st_transform(proj)
sea_city<- suppressMessages(places(state = "WA", cb = TRUE, year = 2023)) %>%
  filter(grepl("Seattle", NAME, ignore.case = TRUE)) %>% st_transform(proj)

wa  <- read_state("Washington")
sea <- read_state("Seattle")

# ---- build one full figure for a given commute ------------------------------
build_figure <- function(commute, tag) {
  wa_dark  <- bind_cols(per_school_dark(wa,  commute) %>% select(-row),
                        wa  %>% select(lat, lon, enroll, school_type, SchoolName))
  sea_dark <- bind_cols(per_school_dark(sea, commute) %>% select(-row),
                        sea %>% select(lat, lon, enroll))
  # color scale = % of the 183 instructional days (not raw day counts)
  lims <- c(0, 100 * max(unlist(wa_dark[REG_LV]), na.rm = TRUE) / TOTAL_SCHOOL_DAYS)

  # ---- worst-case school: highest share of school days with a dark commute ----
  # (reported under Permanent DST, since dark days are monotonic permST <= current <= permDST)
  worst <- wa_dark %>%
    mutate(pct_permDST = 100 * `Permanent DST` / TOTAL_SCHOOL_DAYS) %>%
    arrange(desc(pct_permDST)) %>% slice(1)
  cat(sprintf("[%s] Highest dark-commute share (Permanent DST): %s -- %.1f%% of %d school days (%d days), enrollment %d\n",
              tag, worst$SchoolName, worst$pct_permDST, TOTAL_SCHOOL_DAYS, worst$`Permanent DST`, worst$enroll))

  to_long <- function(d) d %>%
    pivot_longer(all_of(REG_LV), names_to = "regime", values_to = "dark") %>%
    mutate(regime = factor(regime, levels = REG_LV),
           pct = 100 * dark / TOTAL_SCHOOL_DAYS) %>%
    st_as_sf(coords = c("lon","lat"), crs = 4326) %>% st_transform(proj)
  wa_long  <- to_long(wa_dark)
  sea_long <- to_long(sea_dark)

  pA <- panel_calendar(wa, commute)
  cols <- plot_grid(wa_col(wa_long, sea_long, "Permanent ST",   lims),
                    wa_col(wa_long, sea_long, "Current system", lims),
                    wa_col(wa_long, sea_long, "Permanent DST",  lims),
                    nrow = 1)
  # shared color legend (extracted once)
  leg_src <- ggplot() +
    geom_sf(data = wa_long %>% filter(regime == "Permanent DST"), aes(color = pct)) +
    scale_color_viridis(option = "magma", direction = -1, limits = lims,
                        name = metric_label(commute),
                        labels = function(x) paste0(round(x), "%")) +
    theme_map + theme(legend.position = "right")
  pB <- plot_grid(cols, get_legend(leg_src), nrow = 1, rel_widths = c(1, 0.16))
  pC <- panel_bars(wa_dark %>% select(all_of(REG_LV)), wa$enroll, wa$school_type)

  # individual panels kept as standalone files (white background)
  ggsave(Pv(commute, "panelA_calendar.png"), pA, width = 12, height = 5.5, dpi = 300, bg = "white")
  ggsave(Pv(commute, "panelB_maps.png"),     pB, width = 13, height = 3.6, dpi = 300, bg = "white")
  ggsave(Pv(commute, "panelC_bars.png"),     pC, width = 11, height = 4,   dpi = 300, bg = "white")

  # compact heights so the map row doesn't leave large empty space
  fig <- plot_grid(pA, pB, pC, ncol = 1, rel_heights = c(0.78, 0.9, 1.0),
                   labels = c("a", "b", "c"), label_size = 16, label_fontface = "bold")
  ggsave(Pv(commute, "Figure1_WA.png"), fig, width = 13, height = 11, dpi = 300,
         bg = "white", limitsize = FALSE)
  cat("Figure written:", tag, "\n")
}

build_figure(0,           "SST")
build_figure(COMMUTE_MIN, "commute20")

# ---- multi-state table (child-mornings in darkness) -------------------------
# The reported share is analyzed children / ELIGIBLE children in that state.
# Eligible = schools meeting the inclusion criteria (dataset inclusion_status in
# ELIGIBLE_STATUS: included, start_time_not_found, or bad_coordinates), i.e. we
# keep eligible schools whose start time we could not find. The TOTAL row pools
# across the included states (sum analyzed / sum eligible), consistent with the
# per-state column.
state_rows <- STATES %>% filter(is.na(district_filter))    # true states (not Seattle)

table_metric <- function(commute) {
  per_state <- do.call(rbind, lapply(state_rows$state, function(st) {
    info  <- STATES[STATES$state == st, ]
    elig  <- SCHOOLS[SCHOOLS$state == info$csv_state &
                     SCHOOLS$inclusion_status %in% ELIGIBLE_STATUS, ]
    denom <- sum(elig$enrollment, na.rm = TRUE)
    df    <- read_state(st)
    d     <- per_school_dark(df, commute)
    cd    <- sapply(REG_LV, function(r) sum(df$enroll * d[[r]], na.rm = TRUE))
    mSST  <- weighted.mean(df$SST_min, df$enroll, na.rm = TRUE)      # enrollment-weighted mean SST
    data.frame(state = st,
               students_included     = sum(df$enroll),
               eligible_children     = round(denom),
               pct_children_included = round(100 * sum(df$enroll) / denom, 1),
               mean_SST              = min_to_hhmm(mSST),
               mean_SST_min          = round(mSST, 1),
               school_days           = length(SCHOOL_DAYS),
               child_days_permST     = round(cd[["Permanent ST"]]),
               child_days_current    = round(cd[["Current system"]]),
               child_days_permDST    = round(cd[["Permanent DST"]]))
  }))
  tot_mSST <- weighted.mean(per_state$mean_SST_min, per_state$students_included, na.rm = TRUE)
  elig_tot <- sum(per_state$eligible_children)                       # summed across included states
  total <- data.frame(
    state                 = "TOTAL (all included states)",
    students_included     = sum(per_state$students_included),
    eligible_children     = elig_tot,
    pct_children_included = round(100 * sum(per_state$students_included) / elig_tot, 1),
    mean_SST              = min_to_hhmm(tot_mSST),
    mean_SST_min          = round(tot_mSST, 1),
    school_days           = length(SCHOOL_DAYS),
    child_days_permST     = sum(per_state$child_days_permST),
    child_days_current    = sum(per_state$child_days_current),
    child_days_permDST    = sum(per_state$child_days_permDST))
  rbind(per_state, total)
}
write_csv(table_metric(0),           P("Table1_child_days_SST.csv"))
write_csv(table_metric(COMMUTE_MIN), P("Table1_child_days_commute20.csv"))
cat("Tables written to", PAPER_DIR, "\n")
