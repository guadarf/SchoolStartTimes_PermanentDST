# =============================================================================
# run_all.R -- reproduce every output backing the CURRENT (Current Biology)
# paper from open_data/. Run from the repository root:
#   Rscript run_all.R   (or source() in an R session)
#
#   01  per-state dark-day metrics + summaries (school-type breakdown: WA/Seattle).
#   02  school-year sunrise-vs-start calendars.
#   05  pooled inclusion/exclusion summary (the numbers cited in Methods).
#   03  Washington Figure 1 (-> paper_materials/) + multi-state Table 1.
#   04  national reference-departure ballpark.
#   07  FARS pedestrian-safety result cited in the paper, from the tracked
#       minimal dataset (open_data/fars_ped_national_minimal.csv) -- needs no
#       raw-data download, always runs.
#   06  (optional) re-derives open_data/fars_ped_national_minimal.csv from the
#       raw FARS folders; only needed if you want to regenerate that file
#       yourself rather than use the one already in the repository.
#
# NOT part of the current paper (kept in archive/, not deleted -- see
# archive/README.md for why each one is there, and note they kept their
# ORIGINAL numbers rather than being renumbered along with the active
# pipeline above):
#   - archive/06_seattle_crash_light.R -- superseded Seattle SDOT collision
#     analysis; replaced entirely by the FARS analysis above.
#   - archive/02_maps.R, archive/03_flow_diagram.R -- per-state maps and
#     inclusion-flow diagrams built for the PNAS submission's Supplementary
#     Information. The Current Biology Report format has no separate
#     Supplemental Information section, so these are not referenced by the
#     current paper, and nothing in the pipeline below reads their output.
#
# Kept figures/outputs are produced for both metrics: SST (start vs sunrise) and
# departure_20min (start - 20 min vs sunrise). Sunrise threshold only.
# =============================================================================
source("01_sunrise_analysis.R")
source("02_sunrise_calendar.R")
message("\n########## INCLUSION SUMMARY ##########");  source("05_inclusion_summary.R")
message("\n########## PAPER FIGURE + TABLE 1 ##########"); source("03_paper_figures.R")
message("\n########## NATIONAL ESTIMATE ##########");   source("04_national_estimate.R")
message("\n########## FARS PEDESTRIAN-SAFETY RESULT (paper-cited, minimal dataset) ##########")
source("07_fars_paper_analysis.R")

if (length(list.dirs("open_data", recursive = FALSE)[grepl("FARS[0-9]{4}National$", list.dirs("open_data", recursive = FALSE))]) > 0) {
  message("\n########## [optional] MINIMAL FARS RE-EXPORT ##########"); source("06_export_fars_minimal.R")
} else {
  message("\n(Skipping optional 06_export_fars_minimal.R -- raw open_data/FARS<YEAR>National/ folders not found; not needed to reproduce the paper, see script 07 above.)")
}

message("\nAll done. Per-state outputs in outputs/ & plots/ (SST and departure_20min ",
        "subfolders); figures, Table 1, and national_estimate.csv in 'paper_materials/'.")
