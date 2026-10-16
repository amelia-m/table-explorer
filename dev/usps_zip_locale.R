# Has USPS published a newer ZIP Locale Detail file than the one recorded?
# Functions only, no side effects. Sourced by dev/check_usps_zip_locale.R and
# by tests/testthat/test-usps-zip-locale.R.
#
# Why this exists: the ZIP checks use USPS's ZIP Locale Detail file as their
# reference list, and USPS replaces it monthly. A reference list that has
# gone stale reports new ZIPs as "not in the reference list" without saying
# why. The source page carries a changelog line, "file updated MM/DD/YYYY",
# and a download link whose path names the month, so either moving is an
# update.

usps_locale_page <- "https://postalpro.usps.com/ZIP_Locale_Detail"
usps_locale_base <- "https://postalpro.usps.com"

# Fetch a page as one string, or NULL when it cannot be reached. Nothing is
# written to disk.
fetch_page_text <- function(url) {
  con <- url(url, method = "libcurl")
  on.exit(try(close(con), silent = TRUE), add = TRUE)
  out <- tryCatch(
    suppressWarnings(readLines(con, warn = FALSE, encoding = "UTF-8")),
    error = function(e) NULL
  )
  if (is.null(out) || length(out) == 0L) NULL else paste(out, collapse = "\n")
}

# Pure: the changelog date and the download link from the page's HTML.
# Either may be NA when the page has changed shape, which the caller reports
# as unparseable rather than as current.
parse_locale_page <- function(html) {
  if (is.null(html) || !nzchar(html)) {
    return(list(updated = as.Date(NA), file_url = NA_character_))
  }
  m <- regmatches(
    html,
    regexpr(
      "file updated[[:space:]]+[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}",
      html,
      ignore.case = TRUE
    )
  )
  updated <- if (length(m)) {
    as.Date(sub("^.*[[:space:]]", "", m), format = "%m/%d/%Y")
  } else {
    as.Date(NA)
  }
  href <- regmatches(
    html,
    regexpr(
      "href=\"[^\"]*Zip_Locale_Detail[^\"]*[.]xlsx\"",
      html,
      ignore.case = TRUE
    )
  )
  file_url <- if (length(href)) {
    h <- sub("^href=\"", "", sub("\"$", "", href))
    if (startsWith(h, "/")) paste0(usps_locale_base, h) else h
  } else {
    NA_character_
  }
  list(updated = updated, file_url = file_url)
}

# Pure: compare what the page says with what was recorded.
#   current      same date and same link
#   updated      the page shows a later date or a different link
#   unreachable  the page could not be fetched
#   unparseable  the page was fetched but its date or link was not found,
#                which means the check needs mending, not that nothing moved
compare_locale <- function(recorded, page, reached = TRUE) {
  if (!isTRUE(reached)) {
    return(list(
      state = "unreachable",
      message = sprintf("could not reach %s", usps_locale_page)
    ))
  }
  if (is.na(page$updated) || is.na(page$file_url)) {
    return(list(
      state = "unparseable",
      message = paste(
        "the page was reached but its 'file updated' date or download link",
        "was not found; the page has probably changed shape and this check",
        "needs mending"
      )
    ))
  }
  rec_date <- as.Date(recorded$file_updated)
  newer <- is.na(rec_date) || page$updated > rec_date
  moved <- !identical(page$file_url, recorded$file_url)
  if (newer || moved) {
    return(list(
      state = "updated",
      message = sprintf(
        "USPS shows file updated %s (recorded %s)%s; download %s",
        format(page$updated),
        format(rec_date),
        if (moved && !newer) ", and the download link changed" else "",
        page$file_url
      )
    ))
  }
  list(
    state = "current",
    message = sprintf(
      "current: file updated %s, as recorded",
      format(page$updated)
    )
  )
}

# The sheets the file is expected to hold. ZIP_Locale has its header on one
# row; Unique and Other split theirs over three ("ZIP / CLASS / CODE").
locale_sheets <- c("ZIP_Locale", "Unique", "Other")
# The columns kept, by their header name once a split header is joined. The
# post office's street address is in the file and deliberately not kept.
locale_columns <- c(
  zip = "DELIVERY ZIPCODE",
  class = "ZIP CLASS CODE",
  locale_name = "LOCALE NAME",
  state = "PHYSICAL STATE"
)

# Every row of the three sheets, with the four kept columns found by header
# name rather than by position, so a column USPS inserts or moves cannot
# silently shift what is read.
read_locale_rows <- function(path) {
  sheets <- readxl::excel_sheets(path)
  missing <- setdiff(locale_sheets, sheets)
  if (length(missing)) {
    stop(
      sprintf("expected sheets not found: %s", paste(missing, collapse = ", ")),
      call. = FALSE
    )
  }
  pad <- function(x) gsub(" ", "0", sprintf("%5s", x))
  out <- lapply(locale_sheets, function(s) {
    d <- suppressMessages(readxl::read_excel(
      path,
      sheet = s,
      col_names = FALSE,
      col_types = "text"
    ))
    # The header is every row above the first one holding a 5-digit ZIP in
    # any column; its cells are joined per column
    first <- which(apply(d, 1, function(r) any(grepl("^[0-9]{5}$", r))))[1]
    if (is.na(first) || first < 2L) {
      stop(sprintf("no header found on sheet %s", s), call. = FALSE)
    }
    head_rows <- d[seq_len(first - 1L), , drop = FALSE]
    hdr <- vapply(
      head_rows,
      function(col) trimws(paste(stats::na.omit(col), collapse = " ")),
      ""
    )
    at <- match(locale_columns, hdr)
    if (anyNA(at)) {
      stop(
        sprintf(
          "sheet %s lacks column%s %s",
          s,
          if (sum(is.na(at)) == 1L) "" else "s",
          paste(locale_columns[is.na(at)], collapse = ", ")
        ),
        call. = FALSE
      )
    }
    body <- d[first:nrow(d), , drop = FALSE]
    data.frame(
      zip = pad(body[[at[1]]]),
      class = ifelse(is.na(body[[at[2]]]), "", body[[at[2]]]),
      locale_name = body[[at[3]]],
      state = body[[at[4]]],
      sheet = s,
      stringsAsFactors = FALSE
    )
  })
  rows <- do.call(rbind, out)
  rows[grepl("^[0-9]{5}$", rows$zip), , drop = FALSE]
}

# Facts about a local copy of the file, for the provenance record
summarise_locale_file <- function(path) {
  zips <- unique(read_locale_rows(path)$zip)
  list(
    md5 = unname(tools::md5sum(path)),
    distinct_zips = length(zips),
    lowest_zip = min(zips),
    highest_zip = max(zips)
  )
}

# The derived list the repository tracks: distinct rows of the kept columns,
# sorted, so a monthly update's diff shows exactly which ZIPs USPS added,
# retired or reclassified. Built only from the file; never edited by hand.
locale_csv_rows <- function(rows) {
  rows <- unique(rows[, c("zip", "class", "locale_name", "state", "sheet")])
  rows[order(rows$zip, rows$sheet, rows$locale_name), , drop = FALSE]
}
