# =============================================================================
# install_packages.R -- install the CRAN packages needed to run the pipeline,
# then print the R and package versions actually used (record these for the
# repository / paper's reproducibility statement).
# =============================================================================
pkgs <- c(
  # analysis
  "suncalc", "lubridate", "dplyr", "tidyr", "readr", "ggplot2", "lutz",
  # maps
  "sf", "tigris", "viridis", "cowplot",
  # flow diagrams
  "DiagrammeR", "DiagrammeRsvg", "rsvg"
)

new <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(new)) install.packages(new)

cat(R.version.string, "\n\n")
cat("Package versions:\n")
for (p in pkgs) cat(sprintf("  %-14s %s\n", p, as.character(packageVersion(p))))

# For a fully pinned environment, consider renv:  renv::init(); renv::snapshot()
