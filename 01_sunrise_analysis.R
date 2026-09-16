# =============================================================================
# 01_sunrise_analysis.R  -- per-school SST vs sunrise metrics, for every state.
# Outputs (one set per state, files prefixed with the state slug):
#   outputs/<State>_school_sunrise_metrics.csv
#   outputs/<State>_summary_dark_days.csv
#   outputs/<State>_summary_dark_days_by_type.csv
#   outputs/<State>_average_sst.csv
#   plots/<State>_mean_dark_days_per_child.png
#   plots/<State>_mean_dark_days_SST_by_type.png
#   plots/<State>_mean_dark_days_departure_by_type.png
# =============================================================================
source("00_common.R")

analyze_state <- function(state) {
  slug <- slugify(state)
  info <- STATES[STATES$state == state, ]
  do_type <- isTRUE(info$by_type)     # school-type breakdown only where flagged (WA/Seattle)
  cat("\n==== ", state, " ====\n", sep = "")
  df <- read_state(state)
  df$SchoolCode <- seq_len(nrow(df))          # simple within-state id
  cat(sprintf("  valid schools: %d | students: %s\n",
              nrow(df), format(sum(df$enroll, na.rm = TRUE), big.mark = ",")))

  # ---- sunrise per school x instructional day ----
  grid <- sunrise_grid(df, SCHOOL_DAYS) %>%
    mutate(SST_min = df$SST_min[row])

  # ---- per-school dark-day counts (SST) ----
  metrics_sst <- grid %>%
    group_by(row) %>%
    summarise(
      n_school_days    = n(),
      dark_SST_permST  = sum(SST_min < sunrise_permST),
      dark_SST_current = sum(SST_min < sunrise_current),
      dark_SST_permDST = sum(SST_min < sunrise_permDST),
      .groups = "drop")

  # ---- departure sensitivity (SST - commute) ----
  departure_metrics <- function(cc) {
    tag <- paste0("c", sub("\\.", "p", as.character(cc)))
    grid %>% mutate(dep = SST_min - cc) %>% group_by(row) %>%
      summarise(
        "dark_dep_permST_{tag}"  := sum(dep < sunrise_permST),
        "dark_dep_current_{tag}" := sum(dep < sunrise_current),
        "dark_dep_permDST_{tag}" := sum(dep < sunrise_permDST),
        .groups = "drop")
  }
  metrics_dep <- Reduce(function(a, b) left_join(a, b, by = "row"),
                        lapply(COMMUTE_GRID, departure_metrics))

  # ---- winter-solstice sunrise per school ----
  # "+ 1" on the requested date: see the note in 00_common.R::sunrise_grid --
  # getSunlightTimes() labels the sunrise it returns with the day BEFORE the
  # one requested, at these (western) longitudes.
  sol <- getSunlightTimes(data = data.frame(date = SOLSTICE + 1, lat = df$lat, lon = df$lon),
                          keep = SUN_KEEP, tz = "UTC")
  sol_h <- as.numeric(difftime(sol[[SUN_KEEP]], as.POSIXct(paste0(SOLSTICE, " 00:00:00"), tz = "UTC"),
                               units = "hours"))
  # December is always Standard Time under the current system, so ST == current.
  df$sunrise_solstice_ST_current_min <- (sol_h + df$std_offset)     * 60
  df$sunrise_solstice_permDST_min    <- (sol_h + df$std_offset + 1) * 60

  # ---- assemble per-school table ----
  result <- df %>%
    mutate(SST_hhmm = min_to_hhmm(SST_min),
           departure_min = SST_min - COMMUTE_MIN,
           departure_hhmm = min_to_hhmm(SST_min - COMMUTE_MIN),
           commute_default_min = COMMUTE_MIN,
           row = seq_len(n())) %>%
    left_join(metrics_sst, by = "row") %>%
    left_join(metrics_dep, by = "row") %>%
    mutate(
      sunrise_solstice_ST_current = min_to_hhmm(sunrise_solstice_ST_current_min),
      sunrise_solstice_permDST    = min_to_hhmm(sunrise_solstice_permDST_min)) %>%
    select(-row)
  write_csv(result, op("%s_school_sunrise_metrics.csv", slug))

  # ---- statewide summary (overall) ----
  w <- result$enroll
  summarize_metric <- function(dark, event, commute) data.frame(
    state = state, event = event, commute_min = commute,
    regime = c("permST","current","permDST"),
    mean_days_per_child      = sapply(dark, function(v) weighted.mean(v, w, na.rm = TRUE)),
    # total child-mornings in darkness over the school year = sum_schools enroll * dark_days
    total_child_days_dark    = sapply(dark, function(v) sum(w * v, na.rm = TRUE)),
    mean_days_per_school     = sapply(dark, function(v) mean(v, na.rm = TRUE)),
    median_days_per_school   = sapply(dark, function(v) median(v, na.rm = TRUE)),
    n_schools_always_after   = sapply(dark, function(v) sum(v == 0, na.rm = TRUE)),
    pct_schools_always_after = sapply(dark, function(v) 100 * mean(v == 0, na.rm = TRUE)),
    students_always_after    = sapply(dark, function(v) sum(w[v == 0], na.rm = TRUE)),
    row.names = NULL)
  sst_rows <- summarize_metric(list(result$dark_SST_permST, result$dark_SST_current,
                                    result$dark_SST_permDST), "SST", NA)
  dep_rows <- do.call(rbind, lapply(COMMUTE_GRID, function(cc) {
    tag <- paste0("c", sub("\\.", "p", as.character(cc)))
    summarize_metric(list(result[[paste0("dark_dep_permST_",  tag)]],
                          result[[paste0("dark_dep_current_", tag)]],
                          result[[paste0("dark_dep_permDST_", tag)]]), "departure", cc)
  }))
  summary_tbl <- rbind(sst_rows, dep_rows)
  write_csv(summary_tbl, op("%s_summary_dark_days.csv", slug))

  # ---- summary by school type (only where by_type = TRUE: WA / Seattle) ----
  if (do_type) {
    summary_by_type <- do.call(rbind, lapply(levels(result$school_type), function(ty) {
      sub <- result[result$school_type == ty, ]; wt <- sub$enroll
      if (nrow(sub) == 0) return(NULL)
      mk <- function(dark, event, commute) data.frame(
        state = state, school_type = ty, event = event, commute_min = commute,
        regime = c("permST","current","permDST"),
        mean_days_per_child  = sapply(dark, function(v) weighted.mean(v, wt, na.rm = TRUE)),
        mean_days_per_school = sapply(dark, function(v) mean(v, na.rm = TRUE)),
        n_schools = nrow(sub), students = sum(wt, na.rm = TRUE), row.names = NULL)
      sst <- mk(list(sub$dark_SST_permST, sub$dark_SST_current, sub$dark_SST_permDST), "SST", NA)
      dep <- do.call(rbind, lapply(COMMUTE_GRID, function(cc) {
        tag <- paste0("c", sub("\\.", "p", as.character(cc)))
        mk(list(sub[[paste0("dark_dep_permST_",  tag)]],
                sub[[paste0("dark_dep_current_", tag)]],
                sub[[paste0("dark_dep_permDST_", tag)]]), "departure", cc)
      }))
      rbind(sst, dep)
    }))
    write_csv(summary_by_type, op("%s_summary_dark_days_by_type.csv", slug))
    # analyzed schools + students by type (for Methods)
    type_counts <- result %>% group_by(school_type) %>%
      summarise(n_schools = n(), students = sum(enroll, na.rm = TRUE), .groups = "drop")
    write_csv(type_counts, op("%s_school_type_counts.csv", slug))
  }

  # ---- enrollment-weighted average SST (overall + by type) ----
  avg_one <- function(d, label) {
    m <- weighted.mean(d$SST_min, d$enroll, na.rm = TRUE)
    data.frame(state = state, group = label, n_students = sum(d$enroll, na.rm = TRUE),
               mean_SST_min = m, mean_departure_min = m - COMMUTE_MIN)
  }
  avg_sst <- avg_one(result, "ALL")
  if (do_type)
    avg_sst <- rbind(avg_sst,
                     do.call(rbind, lapply(levels(result$school_type),
                       function(ty) { s <- result[result$school_type == ty, ]
                         if (nrow(s)) avg_one(s, ty) else NULL })))
  avg_sst$mean_SST_hhmm       <- min_to_hhmm(avg_sst$mean_SST_min)
  avg_sst$mean_departure_hhmm <- min_to_hhmm(avg_sst$mean_departure_min)
  write_csv(avg_sst, op("%s_average_sst.csv", slug))

  # ---- plots ----
  fills <- c(permST = "#2e8b57", current = "#e0a020", permDST = "#c0392b")
  reg_lv <- c("permST","current","permDST")

  p1 <- summary_tbl %>%
    mutate(panel = ifelse(is.na(commute_min), "SST", paste0("Departure ", commute_min, " min")),
           panel = factor(panel, levels = c("SST", paste0("Departure ", COMMUTE_GRID, " min"))),
           regime = factor(regime, levels = reg_lv)) %>%
    ggplot(aes(regime, mean_days_per_child, fill = regime)) +
    geom_col(width = 0.7) +
    geom_text(aes(label = round(mean_days_per_child, 1)), vjust = -0.3, size = 3) +
    facet_wrap(~ panel, nrow = 1) +
    scale_fill_manual(values = fills, guide = "none") +
    labs(title = sprintf("%s: mean school days per child starting before sunrise", state),
         x = NULL, y = "Days per child (enrollment-weighted)") +
    theme_minimal(base_size = 11)
  if (do_type)   # per-child overview kept only for WA/Seattle (minimal for other states)
    ggsave(pp("%s_mean_dark_days_per_child.png", slug), p1, width = 11, height = 4.5, dpi = 300)

  by_type_plot <- function(ev, commute, fname, subtitle) {
    d <- summary_by_type %>%
      filter(event == ev, if (is.na(commute)) is.na(commute_min) else commute_min == commute) %>%
      mutate(regime = factor(regime, levels = reg_lv),
             school_type = factor(school_type, levels = c("Elementary","Middle","High","Other/Mixed")))
    p <- ggplot(d, aes(regime, mean_days_per_child, fill = regime)) +
      geom_col(width = 0.7) +
      geom_text(aes(label = round(mean_days_per_child, 1)), vjust = -0.3, size = 3) +
      facet_wrap(~ school_type, nrow = 1) +
      scale_fill_manual(values = fills, guide = "none") +
      labs(title = sprintf("%s: mean days per child before sunrise, by school type", state),
           subtitle = subtitle, x = NULL, y = "Days per child (enrollment-weighted)") +
      theme_minimal(base_size = 11)
    ggsave(fname, p, width = 12, height = 4.5, dpi = 300)
  }
  if (do_type) {
    by_type_plot("SST", NA, ppv(0, "%s_mean_dark_days_by_type.png", slug), "School start time")
    by_type_plot("departure", COMMUTE_MIN, ppv(COMMUTE_MIN, "%s_mean_dark_days_by_type.png", slug),
                 sprintf("Departure (commute %g min)", COMMUTE_MIN))
  }

  summary_tbl$total_students <- sum(w, na.rm = TRUE)
  invisible(summary_tbl)
}

all_summ <- do.call(rbind, lapply(STATES$state, analyze_state))

# ---- Combined cross-region table: child-mornings in darkness ---------------
# One row per region x event x commute; regimes as columns (total child-days).
child_days <- all_summ %>%
  mutate(regime = factor(regime, levels = c("permST","current","permDST"))) %>%
  select(state, event, commute_min, total_students, regime, total_child_days_dark) %>%
  tidyr::pivot_wider(names_from = regime, values_from = total_child_days_dark,
                     names_prefix = "child_days_") %>%
  arrange(event, commute_min, state)
write_csv(child_days, op("child_days_in_darkness.csv"))

cat("\nChild-mornings in darkness over the school year (SST):\n")
child_days %>% filter(event == "SST") %>%
  transmute(state, students = total_students,
            permST = round(child_days_permST), current = round(child_days_current),
            permDST = round(child_days_permDST)) %>%
  print(n = Inf)
cat("\nDone. Per-region outputs + outputs/child_days_in_darkness.csv written.\n")
