# Is the recorded USPS ZIP Locale Detail file still the latest?
#
# Usage, from the repository root:
#   Rscript dev/check_usps_zip_locale.R            check the page against the record
#   Rscript dev/check_usps_zip_locale.R --record   record the local copy as current
#
# Exit status, so a scheduled job can act on it:
#   0   current
#   10  USPS has published a newer file
#   20  the page could not be reached, or was reached and could not be read
#
# --record reads docs/ref/Zip_Locale_Detail.xlsx and the live page, and
# writes docs/ref/usps-zip-locale.csv (the derived list the repository
# tracks) and docs/ref/zip-locale-source.yml (where it came from) only after
# every value has been computed, so a failure part way leaves both untouched.
# The .xlsx itself stays local and ignored (Amelia, 2026-10-16).

source("dev/usps_zip_locale.R")

record_path <- "docs/ref/zip-locale-source.yml"
local_file <- "docs/ref/Zip_Locale_Detail.xlsx"
csv_path <- "docs/ref/usps-zip-locale.csv"
args <- commandArgs(trailingOnly = TRUE)

html <- fetch_page_text(usps_locale_page)
page <- parse_locale_page(html)

if ("--record" %in% args) {
  if (!file.exists(local_file)) {
    stop(sprintf("%s not found; download it first", local_file), call. = FALSE)
  }
  if (is.na(page$updated) || is.na(page$file_url)) {
    stop(
      "could not read the 'file updated' date and download link from the page",
      call. = FALSE
    )
  }
  facts <- summarise_locale_file(local_file)
  csv_rows <- locale_csv_rows(read_locale_rows(local_file))
  rec <- list(
    source_page = usps_locale_page,
    file_url = page$file_url,
    file_updated = format(page$updated),
    recorded_on = format(Sys.Date()),
    local_file = local_file,
    md5 = facts$md5,
    distinct_zips = facts$distinct_zips,
    lowest_zip = facts$lowest_zip,
    highest_zip = facts$highest_zip,
    csv_file = csv_path,
    csv_rows = nrow(csv_rows)
  )
  header <- c(
    "# The USPS ZIP Locale Detail file this repository was last checked against.",
    "# Written by: Rscript dev/check_usps_zip_locale.R --record",
    "# Read by:    Rscript dev/check_usps_zip_locale.R, and the weekly workflow",
    "#             .github/workflows/usps-zip-locale.yml. Do not edit by hand."
  )
  # Both files are written only now, after every value above was computed.
  # Binary connections, so Windows writes LF like every other platform and a
  # rebuild of an unchanged file does not show as modified.
  lf_out <- function(path) file(path, open = "wb")
  con <- lf_out(csv_path)
  utils::write.csv(csv_rows, con, row.names = FALSE, na = "", eol = "\n")
  close(con)
  con <- lf_out(record_path)
  writeLines(c(header, sub("\n$", "", yaml::as.yaml(rec))), con, sep = "\n")
  close(con)
  cat(sprintf(
    "recorded: file updated %s, %d distinct ZIPs, %s to %s\n",
    rec$file_updated,
    rec$distinct_zips,
    rec$lowest_zip,
    rec$highest_zip
  ))
  quit(status = 0L)
}

if (!file.exists(record_path)) {
  stop(
    sprintf("%s not found; run with --record first", record_path),
    call. = FALSE
  )
}
recorded <- yaml::read_yaml(record_path)
res <- compare_locale(recorded, page, reached = !is.null(html))
cat(sprintf("USPS ZIP Locale Detail: %s\n", res$message))
quit(status = switch(res$state, current = 0L, updated = 10L, 20L))
