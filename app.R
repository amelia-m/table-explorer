# Launch the Table Relationship Explorer via the golem package.
# To deploy on shinyapps.io / Posit Connect, use this file as the entry point.
#
# Development usage:
#   pkgload::load_all(export_all = FALSE, helpers = FALSE, attach_testthat = FALSE)
#   run_app()
#
# Production usage (after install.packages / remotes::install_github):
#   library(tableexplorer)
#   run_app()

# Resolve package root from this file's location
pkg_root <- if (!is.null(sys.frame(1L)$ofile)) {
  normalizePath(dirname(sys.frame(1L)$ofile), mustWork = TRUE)
} else {
  normalizePath(".", mustWork = TRUE)
}
pkgload::load_all(pkg_root, export_all = FALSE, helpers = FALSE, attach_testthat = FALSE)
tableexplorer::run_app()
