# =============================================================================
# 03_flow_diagram.R  -- inclusion / attrition flow diagram, per state.
# Reads the open dataset's inclusion_status:
#   assessed -> eligible (meet criteria) -> analytic sample (included)
#   excluded: out of scope / no enrollment ; excluded: start time not found / bad coords
# Outputs: plots/<State>_inclusion_flow.png, outputs/<State>_school_inclusion_summary.csv
# =============================================================================
source("00_common.R")
library(DiagrammeR); library(DiagrammeRsvg); library(rsvg)

g <- function(d) c(schools = nrow(d), students = sum(d$enrollment, na.rm = TRUE))

flow_state <- function(state) {
  slug <- slugify(state)
  info <- STATES[STATES$state == state, ]
  s <- SCHOOLS[SCHOOLS$state == info$csv_state, , drop = FALSE]
  if (!is.na(info$district_filter))
    s <- s[grepl(info$district_filter, s$district_name, ignore.case = TRUE), , drop = FALSE]
  by <- function(st) g(s[s$inclusion_status == st, , drop = FALSE])

  tot <- c(nrow(s), sum(s$enrollment, na.rm = TRUE))
  oos <- by("out_of_scope") + by("no_enrollment")             # excluded before eligibility
  nf  <- by("start_time_not_found") + by("bad_coordinates")   # eligible but unusable
  inc <- by("included")
  elig <- nf + inc

  summ <- data.frame(
    state = state,
    step  = c("assessed","excluded_out_of_scope_or_no_enrollment","eligible",
              "excluded_no_start_time_or_bad_coords","analytic_sample"),
    schools  = c(tot[1], oos[["schools"]],  elig[["schools"]],  nf[["schools"]],  inc[["schools"]]),
    students = c(tot[2], oos[["students"]], elig[["students"]], nf[["students"]], inc[["students"]]))
  write.csv(summ, op("%s_school_inclusion_summary.csv", slug), row.names = FALSE)

  lbl <- function(t, v) sprintf("%s\\nn = %s schools | %s students",
                                t, format(v[["schools"]], big.mark = ","),
                                format(round(v[["students"]]), big.mark = ","))
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
    lbl(sprintf("%s: schools assessed (2024-25)", state), c(schools = tot[1], students = tot[2])),
    lbl("Excluded: out of scope (N/A) or no enrollment", oos),
    lbl("Eligible (meet inclusion criteria)", elig),
    lbl("Excluded: start time not found / invalid coordinates", nf),
    lbl("Analytic sample (included)", inc))

  gr <- grViz(flow)
  rsvg_png(charToRaw(export_svg(gr)), pp("%s_inclusion_flow.png", slug), width = 1400)
  cat(sprintf("%-14s assessed=%d eligible=%d included=%d\n",
              state, tot[1], elig[["schools"]], inc[["schools"]]))
}

for (st in STATES$state[is.na(STATES$district_filter)]) flow_state(st)
cat("\nDone. Per-state flow diagrams written to plots/.\n")
