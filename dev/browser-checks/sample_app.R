# ============================================================
# sample_app.R - the app with sample_data/ preloaded, for browser checks
# ============================================================
#
# Sources R/ directly (no package install) and replaces the upload,
# database and detection modules with stubs, so the tables load at start and
# a full detection scan runs at once. Used by privacy_check.js.
#
# Usage, from the repository root: Rscript dev/browser-checks/sample_app.R
# Env: REPO (repository root, default "."), PORT (default 8771), MINCONF.

library(shiny)
setwd(Sys.getenv("REPO", "."))
for (f in setdiff(list.files("R", full.names = TRUE), "R/run_app.R")) source(f)
addResourcePath("tableexplorer", "inst/app/www")
fs <- list.files("sample_data", full.names = TRUE)
tbls <- lapply(fs, function(f) janitor::clean_names(read.csv(f, stringsAsFactors = FALSE)))
names(tbls) <- sub("\\.csv$", "", basename(fs))
mod_upload_server <- function(id, all_tables_rv, ...) { all_tables_rv(tbls); list(manual_rels_rv = reactiveVal(list()), hide_empty_tables = reactive(FALSE)) }
mod_db_connect_server <- function(...) NULL
mod_detection_server <- function(...) list(
  scan_request_rv = reactive(list(id = 1L, scope = "all", strategy = "auto")),
  detection_settings_rv = reactive(list(method = "both", min_conf = Sys.getenv("MINCONF", "medium"), naming = TRUE,
    value_overlap = TRUE, cardinality = TRUE, format = TRUE, distribution = TRUE, null_pattern = FALSE)),
  enable_composite_pk = reactive(FALSE), detect_method = reactive("both"), rel_sources = reactive("both"), hide_detected_on_declared = reactive(FALSE))
runApp(shinyApp(app_ui, app_server), port = as.integer(Sys.getenv("PORT", "8771")), launch.browser = FALSE)
