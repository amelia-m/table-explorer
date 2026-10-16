# Has USPS published a newer ZIP Locale Detail file than the one recorded,
# and what does a given edition of it hold? Functions only, no side effects
# except where a function's name says it writes. Sourced by
# dev/check_usps_zip_locale.R and by tests/testthat/test-usps-zip-locale.R.
#
# Why this exists: the ZIP checks use USPS's ZIP Locale Detail file as their
# reference list, and USPS replaces it monthly. A reference list that has
# gone stale reports new ZIPs as "not in the reference list" without saying
# why. The source page carries a changelog line, "file updated MM/DD/YYYY",
# and a download link whose path names the month, so either moving is an
# update.
#
# What "current" can mean: the page shows the same edition and the same link
# as the record. The check reads the page only, so a file USPS replaced at
# the same address without touching the page would still read as current.

usps_locale_page <- "https://postalpro.usps.com/ZIP_Locale_Detail"
usps_locale_host <- "postalpro.usps.com"

# A ZIP count that moves by more than this between two editions is refused
# by --record unless forced. Month to month USPS adds and retires a few dozen
# ZIPs; a swing of five percent is a file that was read wrongly or cut short.
locale_max_count_change <- 0.05

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

# Download a file to a path. TRUE when a non-empty file arrived.
fetch_file <- function(url, dest) {
  ok <- tryCatch(
    utils::download.file(
      url,
      dest,
      mode = "wb",
      quiet = TRUE,
      method = "libcurl"
    ),
    error = function(e) 1L,
    warning = function(w) 1L
  )
  identical(as.integer(ok), 0L) && file.exists(dest) && file.size(dest) > 0
}

# Pure: an href as an absolute https URL on the USPS host, or NA. Anything
# else is refused rather than trusted, because the link is scraped from a
# third-party page and ends up in an issue telling someone what to download:
# a link on another host, or one carrying whitespace or quote characters,
# is not one this check will repeat.
normalise_locale_href <- function(h) {
  h <- trimws(h)
  if (grepl("^//", h)) {
    h <- paste0("https:", h)
  } else if (grepl("^/", h)) {
    h <- paste0("https://", usps_locale_host, h)
  }
  h <- sub("^http://", "https://", h, ignore.case = TRUE)
  pattern <- paste0(
    "^https://",
    gsub(".", "[.]", usps_locale_host, fixed = TRUE),
    "/[^[:space:]\"'<>]+[.]xlsx$"
  )
  if (grepl(pattern, h, ignore.case = TRUE)) h else NA_character_
}

# Pure: the changelog date and the download link from the page's HTML, and
# why either is missing. Every "file updated" line is read and the latest
# wins, so an old changelog entry above a new one cannot pass for current.
# More than one distinct download link is refused as ambiguous rather than
# guessed between.
parse_locale_page <- function(html) {
  none <- function(reason) {
    list(updated = as.Date(NA), file_url = NA_character_, reason = reason)
  }
  if (is.null(html) || !nzchar(html)) {
    return(none("empty page"))
  }
  m <- regmatches(
    html,
    gregexpr(
      "file updated[[:space:]]+[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}",
      html,
      ignore.case = TRUE
    )
  )[[1]]
  dates <- as.Date(sub("^.*[[:space:]]", "", m), format = "%m/%d/%Y")
  dates <- dates[!is.na(dates)]
  hrefs <- regmatches(
    html,
    gregexpr(
      "href=\"[^\"[:space:]]*Zip_Locale_Detail[^\"[:space:]]*[.]xlsx\"",
      html,
      ignore.case = TRUE
    )
  )[[1]]
  links <- unique(vapply(
    sub("^href=\"", "", sub("\"$", "", hrefs)),
    normalise_locale_href,
    ""
  ))
  bad <- is.na(links)
  if (!length(dates)) {
    return(none("no 'file updated' line found"))
  }
  if (!length(links)) {
    return(none("no download link found"))
  }
  if (any(bad)) {
    return(none("a download link is not on the USPS host or is malformed"))
  }
  if (length(links) > 1L) {
    return(none(sprintf(
      "%d different download links; refusing to choose",
      length(links)
    )))
  }
  list(updated = max(dates), file_url = links, reason = NA_character_)
}

# Pure: is a recorded date a real ISO date? A hand-edited "10/01/2026"
# would otherwise parse as the year 10 and read as updated for ever.
valid_iso_date <- function(x) {
  is.character(x) &&
    length(x) == 1L &&
    grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x) &&
    !is.na(as.Date(x, format = "%Y-%m-%d"))
}

# Pure: compare what the page says with what was recorded.
#   current      same edition date and same link as the record
#   updated      the page shows a later date or a different link
#   unreachable  the page could not be fetched
#   unparseable  the page was fetched but could not be read, or it shows an
#                edition older than the record: either way this check cannot
#                tell, and says so rather than guessing
#   broken       the record itself is missing or malformed
compare_locale <- function(recorded, page, reached = TRUE) {
  if (!isTRUE(reached)) {
    return(list(
      state = "unreachable",
      message = sprintf("could not reach %s", usps_locale_page)
    ))
  }
  if (
    is.null(recorded) ||
      !valid_iso_date(recorded$file_updated) ||
      !is.character(recorded$file_url)
  ) {
    return(list(
      state = "broken",
      message = paste(
        "the record has no valid file_updated date or file_url;",
        "rebuild it with --record"
      )
    ))
  }
  if (is.na(page$updated) || is.na(page$file_url)) {
    return(list(
      state = "unparseable",
      message = sprintf(
        "the page was reached but could not be read (%s); this check needs mending",
        page$reason %||% "unknown reason"
      )
    ))
  }
  rec_date <- as.Date(recorded$file_updated)
  if (page$updated < rec_date) {
    return(list(
      state = "unparseable",
      message = sprintf(
        "the page shows file updated %s, older than the recorded %s; cannot tell",
        format(page$updated),
        format(rec_date)
      )
    ))
  }
  newer <- page$updated > rec_date
  moved <- !identical(tolower(page$file_url), tolower(recorded$file_url))
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
      "current: the page shows file updated %s and the recorded link",
      format(page$updated)
    )
  )
}

# The sheets the file is expected to hold, and nothing else: a sheet USPS
# adds would otherwise go unread without a word. ZIP_Locale has its header on
# one row; Unique and Other split theirs over three ("ZIP / CLASS / CODE").
locale_sheets <- c("ZIP_Locale", "Unique", "Other")
# The columns kept, by their header name once a split header is joined. The
# post office's street address is in the file and deliberately not kept.
locale_columns <- c(
  zip = "DELIVERY ZIPCODE",
  class = "ZIP CLASS CODE",
  locale_name = "LOCALE NAME",
  state = "PHYSICAL STATE"
)

# Pure: a ZIP cell as 5 digits, restoring leading zeros a spreadsheet lost,
# or NA. Only an all-digit value of 3 to 5 digits is padded; "5 01" is not a
# ZIP and is not turned into one.
pad_zip <- function(x) {
  x <- trimws(x)
  ok <- !is.na(x) & grepl("^[0-9]{3,5}$", x)
  out <- rep(NA_character_, length(x))
  out[ok] <- paste0(strrep("0", 5L - nchar(x[ok])), x[ok])
  out
}

# Every row of the three sheets, with the four kept columns found by header
# name rather than by position, so a column USPS inserts or moves cannot
# silently shift what is read. A row whose ZIP cell is filled but is not a
# ZIP stops the read instead of vanishing, and so does a sheet nobody
# expected: a reference list built with rows quietly missing is worse than
# none.
read_locale_rows <- function(path) {
  sheets <- readxl::excel_sheets(path)
  missing <- setdiff(locale_sheets, sheets)
  if (length(missing)) {
    stop(
      sprintf("expected sheets not found: %s", paste(missing, collapse = ", ")),
      call. = FALSE
    )
  }
  extra <- setdiff(sheets, locale_sheets)
  if (length(extra)) {
    stop(
      sprintf(
        "unexpected sheet%s %s; read them or list them in locale_sheets before recording",
        if (length(extra) == 1L) "" else "s",
        paste(extra, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  out <- lapply(locale_sheets, function(s) {
    d <- suppressMessages(readxl::read_excel(
      path,
      sheet = s,
      col_names = FALSE,
      col_types = "text",
      trim_ws = TRUE
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
    raw_zip <- body[[at[1]]]
    zip <- pad_zip(raw_zip)
    filled <- !is.na(raw_zip) & nzchar(raw_zip)
    bad <- filled & is.na(zip)
    if (any(bad)) {
      stop(
        sprintf(
          "sheet %s: %d row%s with a ZIP cell that is not a 5-digit ZIP (first: '%s')",
          s,
          sum(bad),
          if (sum(bad) == 1L) "" else "s",
          raw_zip[bad][1]
        ),
        call. = FALSE
      )
    }
    keep <- !is.na(zip)
    data.frame(
      zip = zip[keep],
      class = ifelse(is.na(body[[at[2]]][keep]), "", body[[at[2]]][keep]),
      locale_name = body[[at[3]]][keep],
      state = body[[at[4]]][keep],
      sheet = s,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, out)
}

# Facts about a copy of the file, for the provenance record
summarise_locale_file <- function(path, rows = read_locale_rows(path)) {
  zips <- unique(rows$zip)
  list(
    md5 = unname(tools::md5sum(path)),
    distinct_zips = length(zips),
    lowest_zip = min(zips),
    highest_zip = max(zips)
  )
}

# The derived list the repository tracks: distinct rows of the kept columns,
# sorted on every column with a locale-independent sort, so the order never
# depends on USPS's row order or the machine's collation, and a monthly
# update's diff shows exactly which ZIPs USPS added, retired or reclassified.
# Built only from the file; never edited by hand.
locale_csv_rows <- function(rows) {
  cols <- c("zip", "class", "locale_name", "state", "sheet")
  rows <- unique(rows[, cols])
  o <- order(
    rows$zip,
    rows$sheet,
    rows$locale_name,
    rows$state,
    rows$class,
    method = "radix"
  )
  rows <- rows[o, , drop = FALSE]
  rownames(rows) <- NULL
  rows
}

# Pure: is a new edition's ZIP count plausible against the last recorded one?
count_change_ok <- function(
  previous,
  new,
  max_change = locale_max_count_change
) {
  if (is.null(previous) || is.na(previous) || previous <= 0) {
    return(TRUE)
  }
  abs(new - previous) / previous <= max_change
}

# Writes: the CSV and the record, both or neither. Each is written in full to
# a temporary file beside its target first, and only once both are complete
# are they moved into place, so an error at any point leaves the previous
# pair untouched. LF line endings on every platform.
write_locale_record <- function(
  rec,
  csv_rows,
  csv_path,
  record_path,
  header = character(0)
) {
  yml_text <- c(header, sub("\n$", "", yaml::as.yaml(rec)))
  tmp_csv <- tempfile("csv", tmpdir = dirname(csv_path), fileext = ".tmp")
  tmp_yml <- tempfile("yml", tmpdir = dirname(record_path), fileext = ".tmp")
  on.exit(unlink(c(tmp_csv, tmp_yml)), add = TRUE)
  con <- file(tmp_csv, open = "wb")
  tryCatch(
    utils::write.csv(csv_rows, con, row.names = FALSE, na = "", eol = "\n"),
    finally = close(con)
  )
  con <- file(tmp_yml, open = "wb")
  tryCatch(
    writeLines(yml_text, con, sep = "\n"),
    finally = close(con)
  )
  if (!file.rename(tmp_csv, csv_path) || !file.rename(tmp_yml, record_path)) {
    stop("could not move the new files into place", call. = FALSE)
  }
  invisible(TRUE)
}
