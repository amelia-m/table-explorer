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
#   lahman   SABR publishes it; the Baseball Databank derivative is
#            CC BY-SA 3.0 and parts are licensed from Seamheads and
#            Retrosheet. SABR's own statement is unclear, so treat the
#            files as redistributable only by SABR, and keep them in the
#            cache rather than in this repository.

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
  lahman = list(
    file = "lahman.zip",
    url = paste0(
      "https://github.com/chadwickbureau/baseballdatabank/archive/",
      "refs/heads/master.zip"
    ),
    note = "~27 CSVs, composite keys, yearID/teamID/lgID shared everywhere"
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

args <- commandArgs(trailingOnly = TRUE)
keys <- if (length(args)) args else names(public_sources)
results <- vapply(keys, fetch_one, logical(1))
cat("\ncache:", public_cache(), "\n")
cat("ready:", paste(keys[results], collapse = ", "), "\n")
if (any(!results)) {
  cat("missing:", paste(keys[!results], collapse = ", "), "\n")
}
