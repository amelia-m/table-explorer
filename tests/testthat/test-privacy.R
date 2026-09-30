# Privacy flags for the data dictionary (utils_privacy.R)

test_that("names and values suggest personal data", {
  expect_match(privacy_guess("patient_mrn")$reason, "mrn")
  expect_match(privacy_guess("zip5")$reason, "zip")
  expect_match(privacy_guess("street1")$reason, "street")
  expect_match(privacy_guess("DOB")$reason, "dob")
  expect_match(privacy_guess("first_name")$reason, "first_name")
  expect_null(privacy_guess("cell_type"))
  expect_null(privacy_guess("amount"))
  expect_null(privacy_guess("zipper_count"))
  expect_null(privacy_guess("address_type"))
  expect_null(privacy_guess("email_verified"))
  expect_null(privacy_guess("first_name_length"))
  expect_match(privacy_guess("email_address")$reason, "email")
  expect_null(privacy_guess("has_email", c(TRUE, FALSE)))
  emails <- c("a@x.io", "b@y.org", "c@z.com", NA)
  expect_match(privacy_guess("contact", emails)$reason, "100% of values look like email addresses")
  phones <- c("402-555-1234", "(402) 555-9999", "402.555.0000")
  expect_match(privacy_guess("contact", phones)$reason, "phone numbers")
  expect_match(privacy_guess("x", c("123-45-6789", "987-65-4321"))$reason, "social security")
  expect_null(privacy_guess("code", c("AB", "CD", "EF")))
})

test_that("user choices beat patterns, which beat automatic flags", {
  v <- c("a@x.io", "b@x.io")
  expect_equal(dict_privacy(list(), "t", "email", v)$status, "auto_unreviewed")
  expect_true(dict_privacy(list(), "t", "email", v)$private)
  expect_true(dict_privacy(list(), "t", "email", v)$needs_review)
  d <- list("t|email" = list(private = FALSE))
  expect_equal(dict_privacy(d, "t", "email", v)$status, "user_public")
  expect_false(dict_privacy(d, "t", "email", v)$private)
  d <- list("t|notes" = list(private = TRUE))
  expect_equal(dict_privacy(d, "t", "notes")$status, "user_private")
  d <- list(.settings = list(private_patterns = "*_notes, other.secret"))
  expect_equal(dict_privacy(d, "t", "case_notes")$status, "pattern")
  expect_equal(dict_privacy(d, "other", "secret")$status, "pattern")
  expect_equal(dict_privacy(d, "t", "secret")$status, "none")
  # Explicit choice wins over a pattern
  d[["t|case_notes"]] <- list(private = FALSE)
  expect_false(dict_privacy(d, "t", "case_notes")$private)
})

test_that("reviews confirm or clear automatic flags until the reason changes", {
  tabs <- list(t = data.frame(email = c("a@x.io", "b@x.io"), dob = c("x", "y"), n = 1:2))
  q <- privacy_review_queue(tabs, list())
  expect_equal(q$column, c("email", "dob"))
  d <- privacy_review_set(list(), tabs, "t|email", "rejected")
  d <- privacy_review_set(d, tabs, "t|dob", "confirmed")
  expect_equal(nrow(privacy_review_queue(tabs, d)), 0)
  expect_equal(dict_privacy(d, "t", "email", tabs$t$email)$status, "not_personal")
  expect_false(dict_privacy(d, "t", "email", tabs$t$email)$private)
  expect_equal(dict_privacy(d, "t", "dob", tabs$t$dob)$status, "confirmed")
  # A stale review (different reason) asks again
  d[["t|email"]]$privacy_review$reason <- "something else"
  expect_equal(dict_privacy(d, "t", "email", tabs$t$email)$status, "auto_unreviewed")
})

test_that("private columns keep metadata but lose examples and ranges", {
  tabs <- list(p = data.frame(
    id = 1:4,
    birth_year = c(1950, 1960, 1970, 1980),
    email = c("a@x.io", "bb@x.io", "ccc@x.io", NA),
    stringsAsFactors = FALSE
  ))
  dd <- build_data_dictionary(tabs, list(), list(p = "id"))
  by <- dd[dd$column == "birth_year", ]
  expect_true(by$private)
  expect_equal(c(by$min, by$median, by$max), rep("hidden", 3))
  expect_equal(by$examples, "")
  expect_equal(by$n_unique, 4)
  em <- dd[dd$column == "email", ]
  expect_equal(c(em$len_min, em$len_median, em$len_max), c(6, 7, 8))
  expect_equal(em$pct_missing, 25)
  # Reviewed as not personal: range and examples come back
  d <- privacy_review_set(list(), tabs, "p|birth_year", "rejected")
  by2 <- build_data_dictionary(tabs, list(), list(p = "id"), dictionary = d)
  by2 <- by2[by2$column == "birth_year", ]
  expect_equal(c(by2$min, by2$max), c("1950", "1980"))
  expect_equal(by2$examples, "1950, 1960, 1970, 1980")
  expect_match(dict_range_text(by2), "1950 – 1980")
  expect_equal(dict_range_text(dd[dd$column == "birth_year", ]), "hidden (private)")
})

test_that("hide_examples and the examples setting", {
  tabs <- list(t = data.frame(id = 1:3, tier = c("a", "b", "c"), stringsAsFactors = FALSE))
  d <- list("t|tier" = list(hide_examples = TRUE))
  dd <- build_data_dictionary(tabs, list(), list(t = "id"), dictionary = d)
  expect_equal(dd$examples_note[dd$column == "tier"], "hidden by you")
  expect_false(dd$private[dd$column == "tier"])
  off <- list(.settings = list(examples = "off"), "t|tier" = list(hide_examples = FALSE))
  dd <- build_data_dictionary(tabs, list(), list(t = "id"), dictionary = off)
  expect_equal(dd$examples[dd$column == "tier"], "a, b, c")
  expect_equal(dd$examples_note[dd$column == "id"], "examples off")
})

test_that("labels replace business names; older entries still read", {
  expect_equal(dict_entry(list("t|c" = list(business_name = "Old")), "t", "c")$label, "Old")
  expect_equal(dict_entry(list("t|c" = list(label = "New", business_name = "Old")), "t", "c")$label, "New")
  expect_true(dict_entry_empty(list(label = "", description = "")))
  expect_false(dict_entry_empty(list(private = FALSE)))
  expect_false(dict_entry_empty(list(privacy_review = list(state = "rejected", reason = "x"))))
})
