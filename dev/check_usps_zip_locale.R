# Is the recorded USPS ZIP Locale Detail edition still the latest?
#
# Usage, from the repository root:
#   Rscript dev/check_usps_zip_locale.R                     check the page against the record
#   Rscript dev/check_usps_zip_locale.R --record            download the current edition and record it
#   Rscript dev/check_usps_zip_locale.R --record --force    the same, accepting a large change in ZIP count
#
# Exit status, so a scheduled job can act on it:
#   0   current: the page shows the recorded edition and link
#   10  USPS has published a newer edition
#   20  the page could not be reached, or was reached and could not be read
#   30  broken: the record is missing or malformed, or the script failed
#
# --record downloads the edition the page links to, rather than reading
# whatever spreadsheet happens to be on disk: the record says which edition
# it holds, and that is only true if the file came from that page at that
# moment. It then writes docs/ref/usps-zip-locale.csv (the derived list the
# repository tracks) and docs/ref/zip-locale-source.yml (where it came from),
# both or neither. The spreadsheet itself is never tracked (Amelia,
# 2026-10-16); the download is kept at docs/ref/Zip_Locale_Detail.xlsx, which
# git ignores, so it can be inspected.

main <- function(args) {
  source("dev/usps_zip_locale.R")
  record_path <- "docs/ref/zip-locale-source.yml"
  csv_path <- "docs/ref/usps-zip-locale.csv"
  local_file <- "docs/ref/Zip_Locale_Detail.xlsx"

  html <- fetch_page_text(usps_locale_page)
  page <- parse_locale_page(html)
  previous <- if (file.exists(record_path)) {
    tryCatch(yaml::read_yaml(record_path), error = function(e) NULL)
  }

  if ("--record" %in% args) {
    if (is.null(html)) {
      stop(sprintf("could not reach %s", usps_locale_page), call. = FALSE)
    }
    if (is.na(page$updated) || is.na(page$file_url)) {
      stop(sprintf("could not read the page: %s", page$reason), call. = FALSE)
    }
    tmp <- tempfile(fileext = ".xlsx")
    on.exit(unlink(tmp), add = TRUE)
    if (!fetch_file(page$file_url, tmp)) {
      stop(sprintf("could not download %s", page$file_url), call. = FALSE)
    }
    rows <- read_locale_rows(tmp)
    facts <- summarise_locale_file(tmp, rows)
    if (
      !("--force" %in% args) &&
        !count_change_ok(previous$distinct_zips, facts$distinct_zips)
    ) {
      stop(
        sprintf(
          paste(
            "the new edition has %d distinct ZIPs against %d recorded, a change",
            "of more than %d percent; check the file, then rerun with --force"
          ),
          facts$distinct_zips,
          previous$distinct_zips,
          round(100 * locale_max_count_change)
        ),
        call. = FALSE
      )
    }
    csv_rows <- locale_csv_rows(rows)
    rec <- list(
      source_page = usps_locale_page,
      file_url = page$file_url,
      file_updated = format(page$updated),
      fetched_on = format(Sys.Date()),
      md5 = facts$md5,
      distinct_zips = facts$distinct_zips,
      lowest_zip = facts$lowest_zip,
      highest_zip = facts$highest_zip,
      csv_file = csv_path,
      csv_rows = nrow(csv_rows)
    )
    header <- c(
      "# The USPS ZIP Locale Detail edition this repository was last checked against.",
      "# Written by: Rscript dev/check_usps_zip_locale.R --record",
      "# Read by:    Rscript dev/check_usps_zip_locale.R, and the weekly workflow",
      "#             .github/workflows/usps-zip-locale.yml. Do not edit by hand."
    )
    write_locale_record(rec, csv_rows, csv_path, record_path, header)
    # The copy kept for inspection; ignored by git
    file.copy(tmp, local_file, overwrite = TRUE)
    cat(sprintf(
      "recorded: file updated %s, %d distinct ZIPs, %s to %s, %d CSV rows\n",
      rec$file_updated,
      rec$distinct_zips,
      rec$lowest_zip,
      rec$highest_zip,
      rec$csv_rows
    ))
    return(0L)
  }

  res <- compare_locale(previous, page, reached = !is.null(html))
  cat(sprintf("USPS ZIP Locale Detail: %s\n", res$message))
  switch(
    res$state,
    current = 0L,
    updated = 10L,
    unreachable = 20L,
    unparseable = 20L,
    30L
  )
}

status <- tryCatch(
  main(commandArgs(trailingOnly = TRUE)),
  error = function(e) {
    cat(sprintf("USPS ZIP Locale Detail: BROKEN: %s\n", conditionMessage(e)))
    30L
  }
)
quit(status = status)
