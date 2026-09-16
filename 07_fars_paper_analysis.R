# =============================================================================
# 07_fars_paper_analysis.R -- reproduces the FARS pedestrian-safety result
# actually cited in the Current Biology paper, using ONLY the minimal,
# repository-tracked dataset (open_data/fars_ped_national_minimal.csv), which
# contains EVERY FARS fatal crash nationwide, 2015-2024 (any day, any time --
# see the dictionary for why it is not pre-filtered). This script applies the
# real-school-year-weekday, 07:00-08:30 window used throughout the paper via
# fars_school_window() (defined once in 00_common.R and shared with
# 06_export_fars_minimal.R's own sanity check), then reproduces:
#   - Pedestrian involved (any age):   adjusted OR = 1.77 (95% CI 1.55-2.02)
#   - Pedestrian involved (ages 5-18): adjusted OR = 2.22 (95% CI 1.50-3.29)
#
# Needs NO raw data download -- this is the one anyone cloning this
# repository can run out of the box. See
# open_data/fars_ped_national_minimal_DICTIONARY.md for column definitions.
# =============================================================================
source("00_common.R")   # provides fars_school_window() + FARS_W_START/END

df <- read_csv("open_data/fars_ped_national_minimal.csv", show_col_types = FALSE)
cat(sprintf("Loaded %d FARS fatal crashes nationwide, 2015-2024 (all days/times)\n", nrow(df)))

win <- fars_school_window(df)
cat(sprintf("Analytic sample after fars_school_window() (real school-year weekdays, 07:00-08:30): %d\n", nrow(win)))
cat(sprintf("  dark mornings: %d | light mornings: %d\n", sum(win$dark), sum(!win$dark)))

run_composition_test <- function(data, outcome_col, label) {
  data$ped <- data[[outcome_col]]
  n_ped <- sum(data$ped)
  cat(sprintf("\n--- %s ---\n", label))
  cat(sprintf("  N crashes = %d | outcome-positive = %d\n", nrow(data), n_ped))

  tab <- table(dark = data$dark, ped = data$ped)
  print(tab)

  ft <- fisher.test(tab)
  cat(sprintf("  Crude OR (Fisher's exact)  = %.2f (95%% CI %.2f-%.2f), p = %.3g\n",
              ft$estimate, ft$conf.int[1], ft$conf.int[2], ft$p.value))

  m  <- glm(ped ~ dark + factor(hour) + weather, data = data, family = binomial)
  or <- exp(coef(m)["darkTRUE"])
  ci <- exp(confint.default(m)["darkTRUE", ])
  cat(sprintf("  Adjusted OR (hour+weather) = %.2f (95%% CI %.2f-%.2f)\n", or, ci[1], ci[2]))
  invisible(list(crude_or = unname(ft$estimate), adj_or = unname(or), adj_ci = ci))
}

r1 <- run_composition_test(win, "ped_involved_any",   "Pedestrian involved, any age")
r2 <- run_composition_test(win, "ped_involved_5to18", "Pedestrian involved, ages 5-18")

cat("\n---- Compare against the paper ----\n")
cat(sprintf("Any age:   this run adjusted OR = %.2f (expected 1.77, 95%% CI 1.55-2.02)\n", r1$adj_or))
cat(sprintf("Ages 5-18: this run adjusted OR = %.2f (expected 2.22, 95%% CI 1.50-3.29)\n", r2$adj_or))
