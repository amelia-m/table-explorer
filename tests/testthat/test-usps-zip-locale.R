# dev/usps_zip_locale.R is development tooling, not part of the package, so
# it is sourced here rather than loaded with the package.
source(test_path("..", "..", "dev", "usps_zip_locale.R"))

# The page's own shape, invented: a download link and a changelog line, in
# the markup the PostalPro page used when this was written (2026-10-16).
fake_page <- function(date = "10/01/2026", month = "2026-10") {
  sprintf(
    paste0(
      '<a href="/mnt/glusterfs/%s/Zip_Locale_Detail.xlsx">Download</a>',
      '<div class="field__label">Changelog</div>',
      '<div class="field__item"><p>file updated %s</p></div>'
    ),
    month,
    date
  )
}

recorded <- list(
  file_updated = "2026-10-01",
  file_url = "https://postalpro.usps.com/mnt/glusterfs/2026-10/Zip_Locale_Detail.xlsx"
)

test_that("the changelog date and the download link are read from the page", {
  p <- parse_locale_page(fake_page())
  expect_identical(p$updated, as.Date("2026-10-01"))
  expect_identical(p$file_url, recorded$file_url)
})

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
  # USPS could replace the file without touching the changelog line
  res <- compare_locale(
    recorded,
    parse_locale_page(fake_page("10/01/2026", "2026-11"))
  )
  expect_identical(res$state, "updated")
  expect_match(res$message, "download link changed", fixed = TRUE)
})

test_that("an unreachable page is reported as such, never as current", {
  res <- compare_locale(recorded, parse_locale_page(NULL), reached = FALSE)
  expect_identical(res$state, "unreachable")
})

test_that("a page that changed shape is unparseable, never current", {
  # Reached, but with no changelog line: the check needs mending, and saying
  # "current" would hide that the file may have moved on
  res <- compare_locale(recorded, parse_locale_page("<html>redesigned</html>"))
  expect_identical(res$state, "unparseable")
})

# An invented workbook in the file's layout: ZIP_Locale with its header on
# row 1, Unique and Other with theirs on row 3 below two blank rows. The ZIPs
# are made up; 00501 and 99950 are the real ends of the range.
locale_workbook <- function(zip_locale_cols = NULL) {
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
  rows <- function(z, cls, place, st, order = cols) {
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
    d[, order, drop = FALSE]
  }
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "ZIP_Locale")
  order <- zip_locale_cols %||% cols
  openxlsx::writeData(
    wb,
    "ZIP_Locale",
    rbind(
      rows("10001", "", "ONE", "NY", order),
      rows("10002", "", "TWO", "NY", order)
    )
  )
  for (s in c("Unique", "Other")) {
    openxlsx::addWorksheet(wb, s)
    d <- if (s == "Unique") {
      rows("00501", "U", "HOLTSVILLE", "NY")
    } else {
      rows("99950", "P", "KETCHIKAN", "AK")
    }
    openxlsx::writeData(wb, s, d, startRow = 3)
  }
  openxlsx::saveWorkbook(wb, path)
  path
}

test_that("the local file's facts come from all three sheets", {
  f <- summarise_locale_file(locale_workbook())
  expect_identical(f$distinct_zips, 4L)
  expect_identical(f$lowest_zip, "00501")
  expect_identical(f$highest_zip, "99950")
})

test_that("columns are found by name, so a reordered sheet reads the same", {
  # USPS inserting or moving a column must not shift what is read
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

test_that("the derived CSV keeps only the four columns, sorted by ZIP", {
  csv <- locale_csv_rows(read_locale_rows(locale_workbook()))
  expect_identical(
    names(csv),
    c("zip", "class", "locale_name", "state", "sheet")
  )
  expect_identical(csv$zip, c("00501", "10001", "10002", "99950"))
  # The post office street address is in the file and must not be carried
  expect_false(any(grepl("MAIN ST", unlist(csv), fixed = TRUE)))
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
