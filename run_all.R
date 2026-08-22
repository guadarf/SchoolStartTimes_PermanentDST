# =============================================================================
# run_all.R -- reproduce every output from open_data/.
# Run from the repository root:  Rscript run_all.R   (or source() in an R session)
#
#   01  per-state dark-day metrics + summaries (school-type breakdown: WA/Seattle).
#   02  state maps (3-regime map per state; type matrix only for WA/Seattle).
#   03  per-state inclusion flow diagrams.
#   04  school-year sunrise-vs-start calendars.
#   08  pooled inclusion/exclusion summary.
#   05  Washington Figure 1 (-> paper_materials/) + multi-state Table 1.
#   06  Seattle pedestrian-collision analysis (uses the SDOT CSV).
#   07  national reference-departure ballpark.
#
# Kept figures/outputs are produced for both metrics: SST (start vs sunrise) and
# departure_20min (start - 20 min vs sunrise). Sunrise threshold only.
# =============================================================================
source("01_sunrise_analysis.R")
source("02_maps.R")
source("03_flow_diagram.R")
source("04_sunrise_calendar.R")
message("\n########## INCLUSION SUMMARY ##########");  source("08_inclusion_summary.R")
message("\n########## PAPER FIGURE + TABLE 1 ##########"); source("05_paper_figures.R")
message("\n########## SEATTLE CRASH ANALYSIS ##########"); source("06_seattle_crash_light.R")
message("\n########## NATIONAL ESTIMATE ##########");   source("07_national_estimate.R")

message("\nAll done. Per-state outputs in outputs/ & plots/ (SST and departure_20min ",
        "subfolders); figures, Table 1, and national_estimate.csv in 'paper_materials/'.")
