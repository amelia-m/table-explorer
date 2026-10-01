# ============================================================
# plain_app.R - the full app, empty, for browser checks
# ============================================================
#
# Sources R/ directly (no package install). Used by import_check.js.
#
# Usage, from the repository root: Rscript dev/browser-checks/plain_app.R
# Env: REPO (repository root, default "."), PORT (default 8772).

library(shiny)
setwd(Sys.getenv("REPO", "."))
for (f in setdiff(list.files("R", full.names = TRUE), "R/run_app.R")) source(f)
addResourcePath("tableexplorer", "inst/app/www")
runApp(shinyApp(app_ui, app_server), port = as.integer(Sys.getenv("PORT", "8772")), launch.browser = FALSE)
