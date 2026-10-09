#' Launch the Table Relationship Explorer
#'
#' @param onStart,options,enableBookmarking,uiPattern Passed to
#'   \code{shiny::shinyApp()}.
#' @param max_request_size Largest upload accepted, in bytes (default 100 MB).
#'   Applied when the app starts and restored when it stops.
#' @export
run_app <- function(onStart = NULL,
                    options = list(),
                    enableBookmarking = NULL,
                    uiPattern = "/",
                    max_request_size = 100 * 1024^2) {
  # Register static assets (CSS, JS) under the package resource path
  www <- system.file("app/www", package = "tableexplorer")
  if (!nzchar(www)) {
    stop("Can't find the app's static files: is the tableexplorer package installed or loaded?", call. = FALSE)
  }
  shiny::addResourcePath("tableexplorer", www)

  start <- function() {
    # Shiny's default upload limit is 5 MB, too small for typical tables
    old <- base::options(shiny.maxRequestSize = max_request_size)
    shiny::onStop(function() base::options(old))
    if (is.function(onStart)) onStart()
  }

  shiny::shinyApp(
    ui = app_ui,
    server = app_server,
    onStart = start,
    options = options,
    enableBookmarking = enableBookmarking,
    uiPattern = uiPattern
  )
}
