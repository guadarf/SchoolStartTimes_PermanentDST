# =============================================================================
# 08_national_map_figure.R -- National per-school map, all 14 included states,
# by clock regime (Current Biology revision -- Reviewer #2 asked to de-emphasize
# Washington and show the full 14-state footprint "at a glance").
#
# One dot per included school (16093 schools pooled across all 14 states),
# colored by % of instructional days with a pre-sunrise departure (20-min
# commute buffer -- same definition as Figure 1 and Table 1), sized by
# enrollment, faceted into 3 stacked panels (Permanent ST / Current system /
# Permanent DST) on a shared 0-100% color scale. Non-included continental
# states are shown in grey for geographic context only.
#
# REQUIRES 01_sunrise_analysis.R to have already been run (reads its per-school
# output outputs/<State>_school_sunrise_metrics.csv for each of the 14 states,
# rather than recomputing sunrise times itself -- those numbers are identical
# to the ones already backing Table 1 and Figure 1C).
#
# State boundaries come from a small bundled GeoJSON (open_data/
# us_states_boundaries.geojson; US Census cartographic boundaries, public
# domain, via https://github.com/python-visualization/folium) rather than
# tigris/Census TIGER at run time, so this script has no network dependency
# and needs no internet access to reproduce the figure.
#
# Candidate placement (pending PI sign-off -- see Paper/R1/revision_plan.md):
#   - this national map -> main text
#   - Supplementary: a few individual-state versions of this same map
#   - existing Washington Figure 1 (03_paper_figures.R) -> unchanged
#
# Output: paper_materials/departure_20min/Figure_NationalMap.png
# =============================================================================
source("00_common.R")
suppressPackageStartupMessages({
  library(sf); library(viridis); library(cowplot)
})

PAPER_DIR <- file.path("paper_materials", variant_dir(COMMUTE_MIN))
dir.create(PAPER_DIR, showWarnings = FALSE, recursive = TRUE)

REG_LV            <- c("Permanent ST", "Current system", "Permanent DST")
REG_COL           <- c("Permanent ST"   = "dark_dep_permST_c20",
                       "Current system" = "dark_dep_current_c20",
                       "Permanent DST"  = "dark_dep_permDST_c20")
LAND_FILL         <- "#cfe3f2"   # same fill as the Washington map (03_paper_figures.R)
NOT_INCLUDED_FILL <- "#f2f2f0"

theme_map <- theme_void(base_size = 12) +
  theme(plot.background = element_rect(fill = "white", color = NA),
        panel.background = element_rect(fill = "white", color = NA),
        legend.position = "right", strip.text = element_text(face = "bold", size = 15),
        legend.title = element_text(size = 13), legend.text = element_text(size = 12))

# ---- pool all 14 included states' per-school metrics (from 01_) ------------
state_rows <- STATES %>% filter(is.na(district_filter))   # exclude the Seattle subset row
missing <- state_rows$state[!file.exists(op("%s_school_sunrise_metrics.csv", state_rows$state))]
if (length(missing) > 0)
  stop("Missing outputs/<state>_school_sunrise_metrics.csv for: ", paste(missing, collapse = ", "),
       " -- run 01_sunrise_analysis.R first (or run_all.R).")

national <- do.call(rbind, lapply(state_rows$state, function(st) {
  d <- read_csv(op("%s_school_sunrise_metrics.csv", st), show_col_types = FALSE)
  for (reg in REG_LV) d[[reg]] <- 100 * d[[REG_COL[[reg]]]] / d$n_school_days
  d[, c("lat", "lon", "enroll", "state", REG_LV)]
}))
cat("Total schools pooled:", nrow(national), "(paper text cites 16093)\n")
write_csv(national, file.path(PAPER_DIR, "national_map_per_school.csv"))

# ---- US state boundaries (bundled GeoJSON; contiguous US only) -------------
GEOJSON <- file.path(DATA_DIR, "us_states_boundaries.geojson")
if (!file.exists(GEOJSON))
  stop("Missing ", GEOJSON, " -- see script header for provenance.")
us_states <- suppressWarnings(suppressMessages(st_read(GEOJSON, quiet = TRUE))) %>%
  filter(!id %in% c("AK", "HI", "PR"))
included_abbr <- state_rows$abbr
us_states$included <- us_states$id %in% included_abbr

national_sf <- st_as_sf(national, coords = c("lon", "lat"), crs = 4326)

# ---- one stacked panel per regime -------------------------------------------
build_panel <- function(regime, lims) {
  ggplot() +
    geom_sf(data = us_states, aes(fill = included), color = "grey60", linewidth = 0.2) +
    scale_fill_manual(values = c(`TRUE` = LAND_FILL, `FALSE` = NOT_INCLUDED_FILL), guide = "none") +
    geom_sf(data = national_sf %>% arrange(.data[[regime]]),
            aes(color = .data[[regime]], size = enroll), alpha = 0.75, shape = 16) +
    scale_color_viridis(option = "magma", direction = -1, limits = lims,
                        name = "Dark-commute\ndays (%)",
                        labels = function(x) paste0(round(x), "%")) +
    scale_size_continuous(range = c(0.15, 3), guide = "none") +
    coord_sf(xlim = c(-125, -66), ylim = c(24, 50)) +
    labs(title = regime) +
    theme_map + theme(plot.title = element_text(face = "bold", size = 15, hjust = 0.5))
}

lims <- c(0, 100)
panels <- lapply(REG_LV, build_panel, lims = lims)
leg <- get_legend(panels[[1]] + theme(legend.position = "right"))
panels_nolegend <- lapply(panels, function(p) p + theme(legend.position = "none"))

fig <- plot_grid(
  plot_grid(plotlist = panels_nolegend, ncol = 1,
            labels = c("A", "B", "C"), label_size = 16, label_fontface = "bold"),
  leg, nrow = 1, rel_widths = c(1, 0.22)
)

ggsave(file.path(PAPER_DIR, "Figure_NationalMap.png"), fig,
       width = 10, height = 15.5, dpi = 300, bg = "white", limitsize = FALSE)
cat("Figure written:", file.path(PAPER_DIR, "Figure_NationalMap.png"), "\n")
