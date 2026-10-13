# Fetch public test datasets into the user cache. Nothing is committed:
# the files are large, and three of the four carry licences that are
# someone else's to grant. Run this once, then run score_public.R.
#
#   Rscript dev/fixtures/public/fetch.R          # all available
#   Rscript dev/fixtures/public/fetch.R chinook  # just one
#
# Licences, checked 2026-10-09:
#   chinook  MIT (lerocha/chinook-database)
#   pagila   BSD (devrimgunduz/pagila)
#   faers    US government work, public domain (FDA)
#   lahman   not fetched here: the canonical baseballdatabank repository
#            returns 404, so the harness reads the CRAN Lahman package
#            instead (install.packages("Lahman")). The data is Lahman's,
#            CC BY-SA 3.0 for the Baseball Databank derivative, with parts
#            licensed from Seamheads and Retrosheet.

public_cache <- function() {
  file.path(tools::R_user_dir("tableexplorer", "cache"), "public-fixtures")
}

public_sources <- list(
  chinook = list(
    file = "chinook.sqlite",
    url = paste0(
      "https://raw.githubusercontent.com/lerocha/chinook-database/",
      "master/ChinookDatabase/DataSources/Chinook_Sqlite.sqlite"
    ),
    note = "11 tables, declared foreign keys, read straight from SQLite"
  ),
  pagila = list(
    file = "pagila-schema.sql",
    url = paste0(
      "https://raw.githubusercontent.com/devrimgunduz/pagila/master/",
      "pagila-schema.sql"
    ),
    note = "Sakila for PostgreSQL; schema only, needs a server to load"
  ),
  faers = list(
    file = "faers_ascii_2024q1.zip",
    url = paste0(
      "https://fis.fda.gov/content/Exports/faers_ascii_2024Q1.zip"
    ),
    note = "DEMO/DRUG/REAC/OUTC joined on primaryid, date-stamped names"
  )
)

fetch_one <- function(key) {
  if (identical(key, "lahman")) {
    have <- requireNamespace("Lahman", quietly = TRUE)
    message(sprintf(
      "%-8s %s", key,
      if (have) "read from the CRAN Lahman package, nothing to fetch"
      else "needs install.packages(\"Lahman\"); nothing to fetch"
    ))
    return(invisible(have))
  }
  src <- public_sources[[key]]
  if (is.null(src)) {
    message("unknown dataset: ", key)
    return(invisible(FALSE))
  }
  dir.create(public_cache(), recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(public_cache(), src$file)
  if (file.exists(dest) && file.size(dest) > 0) {
    message(sprintf("%-8s already present (%s)", key, format_size(file.size(dest))))
    return(invisible(TRUE))
  }
  message(sprintf("%-8s fetching %s", key, src$url))
  ok <- tryCatch(
    {
      utils::download.file(src$url, dest, mode = "wb", quiet = TRUE)
      file.exists(dest) && file.size(dest) > 0
    },
    error = function(e) {
      message("  failed: ", conditionMessage(e))
      FALSE
    }
  )
  if (ok) {
    message(sprintf("  %s  %s", format_size(file.size(dest)), src$note))
  } else if (file.exists(dest)) {
    unlink(dest)
  }
  invisible(ok)
}

format_size <- function(n) {
  if (n > 1024^2) sprintf("%.1f MB", n / 1024^2) else sprintf("%.0f KB", n / 1024)
}

# Sourcing this file into an environment that already defines
# .fetch_no_setup gives its helpers (public_cache above all) without
# running the driver below, the same convention score_public.R uses. It is
# what lets sweep_settings.R find the cache without a fetch: a sweep that
# downloads a dataset it was told was missing is a sweep whose first run
# is timed against a network transfer.
if (!exists(".fetch_no_setup", inherits = TRUE)) {
  args <- commandArgs(trailingOnly = TRUE)
  keys <- if (length(args)) args else names(public_sources)
  results <- vapply(keys, fetch_one, logical(1))
  cat("\ncache:", public_cache(), "\n")
  cat("ready:", paste(keys[results], collapse = ", "), "\n")
  if (any(!results)) {
    cat("missing:", paste(keys[!results], collapse = ", "), "\n")
  }
}
