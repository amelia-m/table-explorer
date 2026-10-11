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
  d <- list("t|email" = list(private = FALSE, public_for = privacy_data_hash(v)))
  expect_equal(dict_privacy(d, "t", "email", v)$status, "user_public")
  expect_false(dict_privacy(d, "t", "email", v)$private)
  # "Not private" was chosen for other data: back to the automatic flag
  expect_equal(dict_privacy(d, "t", "email", c("z@x.io", "y@x.io"))$status, "auto_unreviewed")
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

test_that("the review queue counts each flagged column's values", {
  tabs <- list(t = data.frame(
    email = c("a@x.io", NA),
    home_phone = c(NA_character_, NA_character_),
    n = 1:2
  ))
  q <- privacy_review_queue(tabs, list())
  expect_equal(q$n_values[q$column == "email"], 1L)
  # All-NA: flagged by name, but there is nothing in it to disclose
  expect_equal(q$n_values[q$column == "home_phone"], 0L)
})

test_that("an empty review queue still carries n_values", {
  q <- privacy_review_queue(list(t = data.frame(n = 1:2)), list())
  expect_equal(nrow(q), 0)
  expect_true("n_values" %in% names(q))
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
  off <- list(.settings = list(examples = "off"), "t|tier" = list(hide_examples = FALSE, examples_for = privacy_data_hash(tabs$t$tier)))
  dd <- build_data_dictionary(tabs, list(), list(t = "id"), dictionary = off)
  expect_equal(dd$examples[dd$column == "tier"], "a, b, c")
  expect_equal(dd$examples_note[dd$column == "id"], "examples off")
  # New data under the same name: examples go off again
  tabs2 <- list(t = data.frame(id = 1:3, tier = c("x", "y", "z"), stringsAsFactors = FALSE))
  dd2 <- build_data_dictionary(tabs2, list(), list(t = "id"), dictionary = off)
  expect_equal(dd2$examples_note[dd2$column == "tier"], "examples off")
})

test_that("labels replace business names; older entries still read", {
  expect_equal(dict_entry(list("t|c" = list(business_name = "Old")), "t", "c")$label, "Old")
  expect_equal(dict_entry(list("t|c" = list(label = "New", business_name = "Old")), "t", "c")$label, "New")
  expect_true(dict_entry_empty(list(label = "", description = "")))
  expect_false(dict_entry_empty(list(private = FALSE)))
  expect_false(dict_entry_empty(list(privacy_review = list(state = "rejected", reason = "x"))))
})

test_that("'name' after an entity word names a thing; qualifiers anywhere later count", {
  expect_null(privacy_guess("product_name"))
  expect_null(privacy_guess("category_name"))
  expect_null(privacy_guess("company_name"))
  expect_match(privacy_guess("customer_name")$reason, "name")
  expect_match(privacy_guess("display_name")$reason, "name")
  expect_match(privacy_guess("account_name")$reason, "name")
  expect_match(privacy_guess("name")$reason, "name")
  expect_null(privacy_guess("zip_code_type"))
  expect_match(privacy_guess("zip_code")$reason, "zip")
  # An all-missing column reads as logical, but its name still counts
  expect_match(privacy_guess("patient_name", c(NA, NA))$reason, "name")
})

test_that("name patterns match the table only when they say so", {
  d <- list(.settings = list(private_patterns = "dob*"))
  expect_equal(dict_privacy(d, "dob_log", "note")$status, "none")
  expect_equal(dict_privacy(d, "t", "dob_raw")$status, "pattern")
  d$.settings$private_patterns <- "dob_log.*"
  expect_equal(dict_privacy(d, "dob_log", "note")$status, "pattern")
})

test_that("privacy checks leave the session's random numbers alone", {
  set.seed(1)
  a <- runif(1)
  set.seed(1)
  privacy_guess("x", as.character(1:1000))
  format_fingerprint(as.character(1:1000))
  expect_equal(runif(1), a)
})

test_that("privacy_reset drops decisions that let values show", {
  d <- list(
    .settings = list(private_patterns = "x*"),
    "a|email" = list(private = FALSE, label = "Email"),
    "a|dob" = list(privacy_review = list(state = "rejected", reason = "r")),
    "a|ssn" = list(privacy_review = list(state = "confirmed", reason = "r")),
    "a|tier" = list(hide_examples = FALSE),
    "b|email" = list(private = FALSE)
  )
  r <- privacy_reset(d)
  expect_equal(r[["a|email"]], list(label = "Email"))
  expect_null(r[["a|dob"]])
  expect_equal(r[["a|ssn"]]$privacy_review$state, "confirmed")
  expect_null(r[["a|tier"]])
  expect_equal(r$.settings$private_patterns, "x*")
  one <- privacy_reset(d, "b")
  expect_null(one[["b|email"]])
  expect_false(one[["a|email"]]$private)
})

test_that("an import never overrides the user's own privacy decision", {
  imported <- list(
    "t|email" = list(private = TRUE, private_source = "import", label = "Email"),
    "t|dob" = list(private = TRUE, private_source = "import"),
    "t|new" = list(private = TRUE, private_source = "import")
  )
  current <- list(
    "t|email" = list(private = FALSE),
    "t|dob" = list(privacy_review = list(state = "rejected", reason = "r"))
  )
  m <- merge_dictionary(current, imported)
  expect_false(m[["t|email"]][["private"]])
  expect_null(m[["t|email"]][["private_source"]])
  expect_equal(m[["t|email"]]$label, "Email")
  # A rejected automatic flag doesn't block a file that marks it restricted
  expect_true(m[["t|dob"]][["private"]])
  expect_equal(dict_privacy(m, "t", "new")$status, "imported")
})

test_that("Remove all tables resets privacy decisions and declared keys", {
  all_tables <- reactiveVal(list(t = data.frame(email = "a@x.io")))
  dict <- reactiveVal(list("t|email" = list(private = FALSE, label = "Email")))
  pks <- reactiveVal(list(t = "email"))
  fk_cache <- new.env()
  testServer(
    mod_upload_server,
    args = list(
      all_tables_rv = all_tables,
      rename_log_rv = reactiveVal(data.frame()),
      schema_rels_rv = reactiveVal(list()),
      table_meta_rv = reactiveVal(list()),
      fk_cache = fk_cache,
      dictionary_rv = dict,
      declared_pks_rv = pks
    ),
    {
      session$setInputs(btn_clear_tables = 1)
      expect_equal(all_tables(), list())
      expect_equal(dict()[["t|email"]], list(label = "Email"))
      # Declared keys describe the source, like declared links: they stay
      expect_equal(pks(), list(t = "email"))
    }
  )
})

test_that("Dictionary tab: selected rows become private; review decisions save", {
  tabs <- list(t = data.frame(
    id = 1:3, email = c("a@x.io", "b@x.io", "c@x.io"), product_code = c("A", "B", "C"),
    dob = c("x", "y", "z"), stringsAsFactors = FALSE
  ))
  dict <- reactiveVal(list())
  testServer(
    mod_dictionary_server,
    args = list(
      tables_rv = reactive(tabs),
      rels_rv = reactive(list()),
      pk_map_rv = reactive(list(t = "id")),
      composite_pk_map_rv = reactive(list(t = NULL)),
      dictionary_rv = dict
    ),
    {
      session$setInputs(table = "", show = "all")
      d <- shown_rv()
      row <- which(d$column == "product_code")
      session$setInputs(dict_rows_selected = row)
      session$setInputs(set_private = 1)
      expect_true(dict()[["t|product_code"]][["private"]])
      session$setInputs(set_public = 2)
      expect_equal(dict()[["t|product_code"]]$public_for, privacy_data_hash(tabs$t$product_code))
      # Review: email -> not personal, dob -> private
      q <- queue_rv()
      expect_equal(q$column, c("email", "dob"))
      session$setInputs(review = 1)
      session$setInputs(rv_1 = "rejected", rv_2 = "confirmed")
      session$setInputs(review_save = 1)
      expect_equal(dict()[["t|email"]]$privacy_review$state, "rejected")
      expect_equal(dict()[["t|dob"]]$privacy_review$state, "confirmed")
      expect_equal(nrow(queue_rv()), 0)
      # A text edit on a cell lands on the right column
      d <- shown_rv()
      session$setInputs(dict_cell_edit = list(row = which(d$column == "id"), col = 12L, value = "Identifier"))
      expect_equal(dict()[["t|id"]]$label, "Identifier")
    }
  )
})

test_that("choices that let values show follow the data: factors, overwrites", {
  f <- factor(c("a@x.io", "b@x.io"))
  d <- list("t|email" = list(private = FALSE, public_for = privacy_data_hash(f)))
  expect_equal(dict_privacy(d, "t", "email", as.character(f))$status, "user_public")
  tabs <- list(t = data.frame(first_name = c("Ann", "Bo"), stringsAsFactors = FALSE))
  r <- privacy_review_set(list(), tabs, "t|first_name", "rejected")
  expect_equal(dict_privacy(r, "t", "first_name", tabs$t$first_name)$status, "not_personal")
  expect_equal(dict_privacy(r, "t", "first_name", c("Cy", "Di"))$status, "auto_unreviewed")
})
