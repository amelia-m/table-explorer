# dev/usps_zip_locale.R is development tooling, not part of the package, so
# it is sourced here rather than loaded with the package.
source(test_path("..", "..", "dev", "usps_zip_locale.R"))

# The page's own shape, invented: a download link and a changelog line, in
# the markup the PostalPro page used when this was written (2026-10-16).
fake_page <- function(date = "10/01/2026", month = "2026-10", href = NULL) {
  href <- href %||% sprintf("/mnt/glusterfs/%s/Zip_Locale_Detail.xlsx", month)
  sprintf(
    paste0(
      '<a href="%s">Download</a>',
      '<div class="field__label">Changelog</div>',
      '<div class="field__item"><p>file updated %s</p></div>'
    ),
    href,
    date
  )
}

recorded <- list(
  file_updated = "2026-10-01",
  file_url = "https://postalpro.usps.com/mnt/glusterfs/2026-10/Zip_Locale_Detail.xlsx"
)

# ── Reading the page ─────────────────────────────────────────

test_that("the changelog date and the download link are read from the page", {
  p <- parse_locale_page(fake_page())
  expect_identical(p$updated, as.Date("2026-10-01"))
  expect_identical(p$file_url, recorded$file_url)
})

test_that("the latest of several changelog lines wins, wherever it sits", {
  # Regression: the first match won, so an old entry above a new one read as
  # current
  html <- paste(
    fake_page("09/01/2026", "2026-10"),
    "<p>file updated 10/01/2026</p>"
  )
  expect_identical(parse_locale_page(html)$updated, as.Date("2026-10-01"))
})

test_that("two different download links are refused, not chosen between", {
  html <- paste(fake_page(month = "2026-09"), fake_page(month = "2026-10"))
  p <- parse_locale_page(html)
  expect_true(is.na(p$file_url))
  expect_match(p$reason, "refusing to choose", fixed = TRUE)
})

test_that("a link off the USPS host is refused", {
  # The link ends up in an issue telling someone what to download
  p <- parse_locale_page(fake_page(
    href = "https://example.invalid/Zip_Locale_Detail.xlsx"
  ))
  expect_true(is.na(p$file_url))
})

test_that("protocol-relative and http links resolve to the same https link", {
  # Regression: "//postalpro..." became "https://postalpro.usps.com//postalpro..."
  # and an http link read as a moved file
  for (h in c(
    "//postalpro.usps.com/mnt/glusterfs/2026-10/Zip_Locale_Detail.xlsx",
    "http://postalpro.usps.com/mnt/glusterfs/2026-10/Zip_Locale_Detail.xlsx"
  )) {
    p <- parse_locale_page(fake_page(href = h))
    expect_identical(p$file_url, recorded$file_url, info = h)
  }
})

test_that("a link carrying a newline or whitespace is not read as a link", {
  # Regression: [^"]* crossed newlines, which let page text forge the
  # workflow's outputs
  html <- fake_page(
    href = "/mnt/glusterfs/2026-10/x\nEOF\ncode=0/Zip_Locale_Detail.xlsx"
  )
  expect_true(is.na(parse_locale_page(html)$file_url))
})

# ── Comparing with the record ────────────────────────────────

test_that("a page matching the record is current", {
  res <- compare_locale(recorded, parse_locale_page(fake_page()))
  expect_identical(res$state, "current")
})

test_that("a later changelog date is an update", {
  res <- compare_locale(
    recorded,
    parse_locale_page(fake_page("11/01/2026", "2026-11"))
  )
  expect_identical(res$state, "updated")
  expect_match(res$message, "file updated 2026-11-01", fixed = TRUE)
})

test_that("a new download link with the same date is still an update", {
  res <- compare_locale(
    recorded,
    parse_locale_page(fake_page("10/01/2026", "2026-11"))
  )
  expect_identical(res$state, "updated")
  expect_match(res$message, "download link changed", fixed = TRUE)
})

test_that("a page older than the record is not current", {
  # Regression: an earlier date with the same link read as current, with a
  # message claiming the dates matched
  res <- compare_locale(
    recorded,
    parse_locale_page(fake_page("09/01/2026", "2026-10"))
  )
  expect_identical(res$state, "unparseable")
  expect_match(res$message, "older than the recorded", fixed = TRUE)
})

test_that("an unreachable page is reported as such, never as current", {
  res <- compare_locale(recorded, parse_locale_page(NULL), reached = FALSE)
  expect_identical(res$state, "unreachable")
})

test_that("a page that changed shape is unparseable, never current", {
  res <- compare_locale(recorded, parse_locale_page("<html>redesigned</html>"))
  expect_identical(res$state, "unparseable")
})

test_that("a missing or malformed record is broken, not an error", {
  # Regression: an empty record crashed the check with exit 1, which the
  # workflow read as success; a hand-edited m/d/Y date parsed as year 10
  page <- parse_locale_page(fake_page())
  expect_identical(compare_locale(NULL, page)$state, "broken")
  expect_identical(
    compare_locale(list(file_url = recorded$file_url), page)$state,
    "broken"
  )
  bad <- utils::modifyList(recorded, list(file_updated = "10/01/2026"))
  expect_identical(compare_locale(bad, page)$state, "broken")
})

# ── Reading the spreadsheet ──────────────────────────────────

# An invented workbook in the file's layout. ZIP_Locale has its header on
# row 1. Unique and Other split theirs over rows 1 to 3 the way the real file
# does ("ZIP" / "CLASS" / "CODE" down one column), with row 1 not empty, so
# readxl cannot collapse it into one row and the joining is really exercised.
# The ZIPs are made up apart from 00501 and 99950, the real ends of the range.
locale_workbook <- function(
  zip_locale_cols = NULL,
  extra_sheet = NULL,
  zip_override = NULL
) {
  skip_if_not_installed("readxl")
  skip_if_not_installed("openxlsx")
  cols <- c(
    "AREA NAME",
    "DISTRICT NO",
    "DELIVERY ZIPCODE",
    "ZIP CLASS CODE",
    "LOCALE NAME",
    "PHYSICAL DELV ADDR",
    "PHYSICAL STATE"
  )
  one <- function(z, cls, place, st) {
    d <- data.frame(
      "A",
      "001",
      z,
      cls,
      place,
      "1 MAIN ST",
      st,
      stringsAsFactors = FALSE
    )
    names(d) <- cols
    d
  }
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "ZIP_Locale")
  # The override replaces the second ZIP, not the first: the header is found
  # as everything above the first row holding a 5-digit ZIP, so a bad value
  # in the first data row is read as more header and fails as a missing
  # column instead, which is loud too but tests a different path
  zl <- rbind(
    one("10001", "", "ONE", "NY"),
    one(zip_override %||% "10002", "", "TWO", "NY")
  )
  openxlsx::writeData(
    wb,
    "ZIP_Locale",
    zl[, zip_locale_cols %||% cols, drop = FALSE]
  )
  split <- rbind(
    c("", "", "", "ZIP", "", "", ""),
    c("", "DISTRICT", "DELIVERY", "CLASS", "", "PHYSICAL", "PHYSICAL"),
    c("AREA NAME", "NO", "ZIPCODE", "CODE", "LOCALE NAME", "DELV ADDR", "STATE")
  )
  for (s in c("Unique", "Other")) {
    openxlsx::addWorksheet(wb, s)
    openxlsx::writeData(wb, s, as.data.frame(split), colNames = FALSE)
    d <- if (s == "Unique") {
      one("00501", "U", "HOLTSVILLE", "NY")
    } else {
      one("99950", "P", "KETCHIKAN", "AK")
    }
    openxlsx::writeData(wb, s, d, startRow = 4, colNames = FALSE)
  }
  if (!is.null(extra_sheet)) {
    openxlsx::addWorksheet(wb, extra_sheet)
    openxlsx::writeData(wb, extra_sheet, one("09001", "M", "APO", "AE"))
  }
  openxlsx::saveWorkbook(wb, path)
  path
}

test_that("the facts come from all three sheets, split headers included", {
  f <- summarise_locale_file(locale_workbook())
  expect_identical(f$distinct_zips, 4L)
  expect_identical(f$lowest_zip, "00501")
  expect_identical(f$highest_zip, "99950")
})

test_that("a header split over three rows is joined before columns are matched", {
  # Regression: the old fixture's split header was read as one row, so a
  # reader using only the last header row still passed. Here the last row
  # alone says "ZIPCODE" and "CODE", which match nothing.
  rows <- read_locale_rows(locale_workbook())
  u <- rows[rows$sheet == "Unique", ]
  expect_identical(u$zip, "00501")
  expect_identical(u$class, "U")
  expect_identical(u$state, "NY")
})

test_that("columns are found by name, so a reordered sheet reads the same", {
  shuffled <- c(
    "PHYSICAL STATE",
    "LOCALE NAME",
    "AREA NAME",
    "ZIP CLASS CODE",
    "DELIVERY ZIPCODE",
    "DISTRICT NO",
    "PHYSICAL DELV ADDR"
  )
  rows <- read_locale_rows(locale_workbook(shuffled))
  r <- rows[rows$zip == "10001", ]
  expect_identical(r$locale_name, "ONE")
  expect_identical(r$state, "NY")
  expect_identical(r$class, "")
})

test_that("a ZIP cell that is not a ZIP stops the read instead of vanishing", {
  # Regression: such rows were dropped without a count or a word
  expect_error(
    read_locale_rows(locale_workbook(zip_override = "10003-0001")),
    "not a 5-digit ZIP"
  )
})

test_that("a sheet nobody expected stops the read instead of going unread", {
  expect_error(
    read_locale_rows(locale_workbook(extra_sheet = "Military")),
    "unexpected sheet"
  )
})

test_that("only an all-digit ZIP is padded, and nothing else is made into one", {
  expect_identical(
    pad_zip(c("501", "02134", "10001")),
    c("00501", "02134", "10001")
  )
  # Regression: every space was replaced, so "5 01" became "05001"
  expect_identical(
    pad_zip(c("5 01", NA, "12", "123456")),
    rep(NA_character_, 4)
  )
})

test_that("a workbook missing a sheet is refused rather than undercounted", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("openxlsx")
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "ZIP_Locale")
  openxlsx::writeData(wb, "ZIP_Locale", data.frame(a = 1))
  openxlsx::saveWorkbook(wb, path)
  expect_error(summarise_locale_file(path), "expected sheets not found")
})

# ── The derived CSV and the record ───────────────────────────

test_that("the derived CSV keeps only the five columns, sorted, with no address", {
  csv <- locale_csv_rows(read_locale_rows(locale_workbook()))
  expect_identical(
    names(csv),
    c("zip", "class", "locale_name", "state", "sheet")
  )
  expect_identical(csv$zip, c("00501", "10001", "10002", "99950"))
  expect_false(any(grepl("MAIN ST", unlist(csv), fixed = TRUE)))
})

test_that("two rows differing only by state sort the same every time", {
  # Regression: the sort key left state out, so ties kept USPS's row order
  rows <- data.frame(
    zip = c("24605", "24605"),
    class = "",
    locale_name = "BLUEFIELD",
    state = c("WV", "VA"),
    sheet = "ZIP_Locale",
    stringsAsFactors = FALSE
  )
  expect_identical(locale_csv_rows(rows)$state, c("VA", "WV"))
  expect_identical(locale_csv_rows(rows[2:1, ])$state, c("VA", "WV"))
})

test_that("a large swing in ZIP count is refused", {
  expect_true(count_change_ok(41486, 41500))
  expect_false(count_change_ok(41486, 5))
  # A first recording has nothing to compare with
  expect_true(count_change_ok(NULL, 5))
})

test_that("the CSV and the record are written both or neither", {
  # Regression: the CSV was written first, then the record was truncated
  # before its contents were computed, so a failure left a new CSV beside
  # an old or empty record
  dir <- tempfile("rec")
  dir.create(dir)
  csv <- file.path(dir, "z.csv")
  yml <- file.path(dir, "z.yml")
  writeLines("old csv", csv)
  writeLines("old yml", yml)
  rows <- data.frame(
    zip = "10001",
    class = "",
    locale_name = "ONE",
    state = "NY",
    sheet = "ZIP_Locale"
  )
  # yaml cannot serialise an environment, so the record fails to build
  expect_error(write_locale_record(list(x = new.env()), rows, csv, yml))
  expect_identical(readLines(csv), "old csv")
  expect_identical(readLines(yml), "old yml")
  expect_length(list.files(dir, pattern = "[.]tmp$"), 0L)
  # And a good write replaces both, with LF line endings
  write_locale_record(
    list(file_updated = "2026-10-01"),
    rows,
    csv,
    yml,
    header = "# h"
  )
  expect_identical(readLines(yml)[1], "# h")
  raw <- readBin(csv, "raw", file.size(csv))
  expect_false(any(raw == as.raw(13L)))
})
