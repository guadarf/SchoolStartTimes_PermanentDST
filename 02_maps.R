# =============================================================================
# 02_maps.R  -- state maps, one set per state (reads 01 outputs). Written to
# plots/<variant>/ for both metrics (variant = SST or departure_20min):
#   <State>_facets_regimes.png         points faceted by the 3 clock regimes
#   <State>_matrix_type_by_regime.png  school type x regime matrix (WA/Seattle only)
# Each state is wrapped in tryCatch so one failure does not stop the rest.
# =============================================================================
source("00_common.R")
suppressPackageStartupMessages({
  library(sf); library(tigris); library(viridis)
})
options(tigris_use_cache = TRUE)

LAND_FILL <- "#cfe3f2"
theme_map <- theme_void(base_size = 11) +
  theme(plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA),
        legend.position = "right", strip.text = element_text(face = "bold"))
hhmm <- function(m) sprintf("%02d:%02d", m %/% 60, round(m %% 60))

crs_for <- function(abbr) if (abbr == "AK") 3338 else 5070   # Alaska Albers else CONUS Albers

maps_state <- function(state, abbr) {
  slug <- slugify(state)
  proj <- crs_for(abbr)
  info <- STATES[STATES$state == state, ]
  result <- read_csv(op("%s_school_sunrise_metrics.csv", slug), show_col_types = FALSE)

  if (!is.na(info$district_filter)) {
    # city / district subset (e.g. Seattle): use the city (place) boundary as base
    # so the map zooms to the city instead of drawing the whole state.
    city <- suppressMessages(tigris::places(state = abbr, cb = TRUE, year = 2023)) %>%
      filter(grepl(info$district_filter, NAME, ignore.case = TRUE)) %>%
      st_transform(proj)
    wa_state <- city
    wa_cty   <- city
  } else {
    wa_state <- suppressMessages(states(cb = TRUE, year = 2023)) %>% filter(STUSPS == abbr) %>% st_transform(proj)
    wa_cty   <- suppressMessages(counties(state = abbr, cb = TRUE, year = 2023)) %>% st_transform(proj)
  }

  # ---- 3-regime facet map (produced for both metrics: SST and departure_20min)
  regime_levels <- c("Permanent ST","Current system","Permanent DST")
  tag      <- paste0("c", sub("\\.", "p", as.character(COMMUTE_MIN)))
  sst_cols <- c("dark_SST_permST","dark_SST_current","dark_SST_permDST")
  dep_cols <- paste0(c("dark_dep_permST_","dark_dep_current_","dark_dep_permDST_"), tag)

  facet_map <- function(cols, commute) {
    long <- result %>%
      transmute(lon, lat, enroll,
                `Permanent ST`   = .data[[cols[1]]],
                `Current system` = .data[[cols[2]]],
                `Permanent DST`  = .data[[cols[3]]]) %>%
      pivot_longer(all_of(regime_levels), names_to = "regime", values_to = "dark_days") %>%
      mutate(regime = factor(regime, levels = regime_levels)) %>%
      st_as_sf(coords = c("lon","lat"), crs = 4326) %>% st_transform(proj) %>% arrange(dark_days)
    p <- ggplot() +
      geom_sf(data = wa_state, fill = LAND_FILL, color = "grey60", linewidth = 0.3) +
      geom_sf(data = long, aes(color = dark_days, size = enroll), alpha = 0.75) +
      scale_color_viridis(option = "magma", direction = -1, name = "Dark days") +
      scale_size_continuous(range = c(0.25, 3), name = "Enrollment") +
      facet_wrap(~ regime) +
      labs(title = sprintf("%s: school days before sunrise, by regime", state)) +
      theme_map
    ggsave(ppv(commute, "%s_facets_regimes.png", slug), p, width = 13, height = 5, dpi = 300)
  }
  facet_map(sst_cols, 0)
  facet_map(dep_cols, COMMUTE_MIN)

  # ---- school-type x regime matrix, only for WA/Seattle (both metrics) -------
  type_levels <- c("High","Middle","Elementary","Other/Mixed")
  base3 <- result %>% filter(.data[["school_type"]] %in% type_levels)
  if (isTRUE(info$by_type) && nrow(base3) > 0) {
    common_lims <- c(0, max(unlist(base3[c(sst_cols, dep_cols)]), na.rm = TRUE))
    make_matrix <- function(cols, outfile) {
      sub <- data.frame(
        lon = base3$lon, lat = base3$lat, enroll = base3$enroll,
        school_type = factor(base3$school_type, levels = type_levels),
        `Permanent ST`   = base3[[cols[1]]],
        `Current system` = base3[[cols[2]]],
        `Permanent DST`  = base3[[cols[3]]], check.names = FALSE)
      lg <- sub %>%
        pivot_longer(all_of(regime_levels), names_to = "regime", values_to = "dark_days") %>%
        mutate(regime = factor(regime, levels = regime_levels)) %>%
        st_as_sf(coords = c("lon","lat"), crs = 4326) %>% st_transform(proj) %>% arrange(dark_days)
      p <- ggplot() +
        geom_sf(data = wa_state, fill = LAND_FILL, color = "grey60", linewidth = 0.3) +
        geom_sf(data = lg, aes(color = dark_days, size = enroll), alpha = 0.75) +
        scale_color_viridis(option = "magma", direction = -1, name = "Dark days", limits = common_lims) +
        scale_size_continuous(range = c(0.25, 3), name = "Enrollment") +
        facet_grid(school_type ~ regime, switch = "y") +
        theme_map + theme(strip.text = element_text(size = 16, face = "bold"), strip.placement = "outside")
      ggsave(outfile, p, width = 12, height = 13, dpi = 300)
    }
    make_matrix(sst_cols, ppv(0,           "%s_matrix_type_by_regime.png", slug))
    make_matrix(dep_cols, ppv(COMMUTE_MIN, "%s_matrix_type_by_regime.png", slug))
  }
  cat(sprintf("%-14s maps written\n", state))
}

for (i in seq_len(nrow(STATES))) {
  st <- STATES$state[i]; ab <- STATES$abbr[i]
  tryCatch(maps_state(st, ab),
           error = function(e) cat(sprintf("[%s] maps FAILED: %s\n", st, conditionMessage(e))))
}
cat("\nDone. Per-state maps written to plots/.\n")
