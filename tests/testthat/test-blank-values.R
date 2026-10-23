# Blank text values ("" or whitespace only) are missing values, wherever the
# app profiles values: detection, the data dictionary and the privacy queue.

test_that("blank_as_na turns empty and whitespace-only text into NA", {
  x <- c("a", "", " ", "\t", "  \n", NA, " b ")
  expect_identical(
    blank_as_na(x),
    c("a", NA, NA, NA, NA, NA, " b ")
  )
  f <- factor(c("x", "", "y", " "))
  out <- blank_as_na(f)
  expect_true(is.factor(out))
  expect_identical(as.character(out), c("x", NA, "y", NA))
  # Other types pass through untouched
  expect_identical(blank_as_na(c(1, NA, 3)), c(1, NA, 3))
  expect_identical(blank_as_na(c(TRUE, NA)), c(TRUE, NA))
})

test_that("blanks_as_na touches only text and factor columns", {
  df <- data.frame(
    n = c(1L, 2L, 3L),
    s = c("a", "", " "),
    f = factor(c("", "u", "v")),
    stringsAsFactors = FALSE
  )
  out <- blanks_as_na(df)
  expect_identical(out$n, df$n)
  expect_identical(out$s, c("a", NA, NA))
  expect_identical(as.character(out$f), c(NA, "u", "v"))
})

test_that("blank strings no longer make two text columns a shared column", {
  # Each side has two real values; "" was being counted as a third, shared
  # one, which met the three-distinct-values minimum and the overlap rule.
  tables <- list(
    a = data.frame(notes = rep(c("", "a", "b"), 10), stringsAsFactors = FALSE),
    b = data.frame(notes = rep(c("", "a", "c"), 10), stringsAsFactors = FALSE)
  )
  expect_length(detect_shared_columns(tables), 0)
})

test_that("a shared column with enough real values still shows next to blanks", {
  tables <- list(
    a = data.frame(
      notes = rep(c("", "a", "b", "c"), 10),
      stringsAsFactors = FALSE
    ),
    b = data.frame(
      notes = rep(c("", "a", "b", "d"), 10),
      stringsAsFactors = FALSE
    )
  )
  out <- detect_shared_columns(tables)
  expect_length(out, 1)
  # Counted on real values only: a and b, not the blank
  expect_equal(out[[1]]$n_shared, 2)
  expect_equal(out[[1]]$n_distinct_from, 3)
})

test_that("the data dictionary counts blank text as missing", {
  tables <- list(
    x = data.frame(
      id = 1:4,
      note = c("a", "", " ", NA),
      stringsAsFactors = FALSE
    )
  )
  dd <- build_data_dictionary(tables, list(), list(x = "id"))
  expect_equal(dd$pct_missing[dd$column == "note"], 75)
  expect_equal(dd$n_unique[dd$column == "note"], 1L)
})

test_that("the privacy review queue counts only non-blank values", {
  tables <- list(
    p = data.frame(
      first_name = c("Ann", "", " ", NA),
      last_name = c("", " ", NA, ""),
      stringsAsFactors = FALSE
    )
  )
  q <- privacy_review_queue(tables, list())
  expect_equal(q$n_values[q$column == "first_name"], 1)
  expect_equal(q$n_values[q$column == "last_name"], 0)
})
