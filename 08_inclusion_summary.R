# =============================================================================
# 08_inclusion_summary.R  -- POOLED inclusion / exclusion summary across states,
# read straight from the open dataset's inclusion_status field:
#   assessed
#     - excluded, out of scope        : start time flagged "N/A" (fails inclusion)
#     - excluded, no/zero enrollment
#   eligible (meets inclusion criteria)
#     - excluded, start time not found
#     - excluded, invalid coordinates
#     - included (analytic sample)
# Outputs: outputs/inclusion_summary_all_states.csv  and a pooled flow diagram
#          plots/inclusion_flow_all_states.png
# =============================================================================
source("00_common.R")
suppressPackageStartupMessages({
  library(DiagrammeR); library(DiagrammeRsvg); library(rsvg)
})

state_rows <- STATES$state[is.na(STATES$district_filter)]     # true states (not Seattle)

g <- function(d) c(schools = nrow(d), students = sum(d$enrollment, na.rm = TRUE))
state_counts <- function(csv_state) {
  s  <- SCHOOLS[SCHOOLS$state == csv_state, , drop = FALSE]
  by <- function(st) g(s[s$inclusion_status == st, , drop = FALSE])
  oos <- by("out_of_scope"); noe <- by("no_enrollment")
  nf  <- by("start_time_not_found"); bad <- by("bad_coordinates"); inc <- by("included")
  data.frame(
    state = csv_state,
    assessed_schools       = nrow(s),                assessed_students       = sum(s$enrollment, na.rm = TRUE),
    excl_out_of_scope_sch  = oos["schools"],         excl_out_of_scope_stu   = oos["students"],
    excl_no_enroll_sch     = noe["schools"],         excl_no_enroll_stu      = noe["students"],
    eligible_schools       = nf["schools"] + bad["schools"] + inc["schools"],
    eligible_students      = nf["students"] + bad["students"] + inc["students"],
    excl_sst_notfound_sch  = nf["schools"],          excl_sst_notfound_stu   = nf["students"],
    excl_bad_coords_sch    = bad["schools"],         excl_bad_coords_stu     = bad["students"],
    included_schools       = inc["schools"],         included_students       = inc["students"],
    row.names = NULL)
}

per_state <- do.call(rbind, lapply(state_rows, state_counts))
total <- data.frame(state = "TOTAL", as.list(colSums(per_state[-1])), check.names = FALSE)
tbl <- rbind(per_state, total)
tbl$pct_children_included <- round(100 * tbl$included_students / tbl$eligible_students, 1)
tbl$pct_schools_included  <- round(100 * tbl$included_schools  / tbl$eligible_schools,  1)

write_csv(tbl, op("inclusion_summary_all_states.csv"))
cat("\nPooled inclusion / exclusion across", length(state_rows), "states:\n")
print(tbl[, c("state","assessed_schools","eligible_students","included_students",
              "pct_children_included","pct_schools_included")], row.names = FALSE)

# ---- pooled flow diagram ----------------------------------------------------
T <- as.list(colSums(per_state[-1]))
lbl <- function(t, sch, stu) sprintf("%s\\nn = %s schools | %s students",
          t, format(sch, big.mark = ","), format(round(stu), big.mark = ","))
flow <- sprintf('
digraph inclusion {
  graph [rankdir = TB, splines = ortho, nodesep = 0.5, ranksep = 0.6]
  node  [shape = box, style = "rounded,filled", fontname = "Helvetica", fontsize = 11]
  total [label = "%s", fillcolor = "#E8EEF7"]
  oos   [label = "%s", fillcolor = "#FCF3CF"]
  elig  [label = "%s", fillcolor = "#D5F5E3"]
  nf    [label = "%s", fillcolor = "#F2DEDE"]
  inc   [label = "%s", fillcolor = "#ABEBC6"]
  total -> elig
  {rank=same; total; oos}
  total -> oos [minlen=1]
  elig -> inc
  {rank=same; elig; nf}
  elig -> nf [minlen=1]
}',
  lbl(sprintf("Schools assessed across %d states (2024-25)", length(state_rows)),
      T$assessed_schools, T$assessed_students),
  lbl("Excluded: out of scope (N/A) or no enrollment",
      T$excl_out_of_scope_sch + T$excl_no_enroll_sch, T$excl_out_of_scope_stu + T$excl_no_enroll_stu),
  lbl("Eligible (meet inclusion criteria)", T$eligible_schools, T$eligible_students),
  lbl("Excluded: start time not found / invalid coordinates",
      T$excl_sst_notfound_sch + T$excl_bad_coords_sch, T$excl_sst_notfound_stu + T$excl_bad_coords_stu),
  lbl("Analytic sample (included)", T$included_schools, T$included_students))

tryCatch({
  gr <- grViz(flow)
  rsvg_png(charToRaw(export_svg(gr)), pp("inclusion_flow_all_states.png"), width = 1500)
  cat("\nPooled flow diagram written to", pp("inclusion_flow_all_states.png"), "\n")
}, error = function(e) cat("\nFlow diagram skipped:", conditionMessage(e), "\n"))
