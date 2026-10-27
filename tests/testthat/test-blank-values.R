# Blank text values ("" or whitespace only, Unicode spaces included) are
# missing values, wherever the app profiles values: detection, the data
# dictionary, the privacy queue, the ERD model and its exports, and the load
# notice for values blank only through non-standard spaces.

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

test_that("blank strings no longer make a foreign key between two code columns", {
  # Shaped like FAERS demo.to_mfr and drug.rechal: a mostly blank flag column
  # was contained in an unrelated code column through "" and one letter
  tables <- list(
    demo = data.frame(
      id = 1:8,
      to_mfr = c(rep("", 7), "Y"),
      stringsAsFactors = FALSE
    ),
    drug = data.frame(
      rechal = c("", "Y", "N", "D"),
      k = 1:4,
      stringsAsFactors = FALSE
    )
  )
  rels <- detect_fks(tables, method = "both", min_confidence = "low")
  pairs <- vapply(
    rels,
    function(r) paste(r$from_col, r$to_col %||% r$from_col),
    ""
  )
  expect_false("to_mfr rechal" %in% pairs)
})

test_that("a column holding a blank is not a primary key", {
  drug <- data.frame(
    rechal = c("", "Y", "N", "D"),
    k = 1:4,
    stringsAsFactors = FALSE
  )
  expect_identical(detect_pks(drug, "drug", method = "uniqueness"), "k")
  # Survival: the same column without the blank is still unique, so a key
  drug$rechal[1] <- "R"
  expect_setequal(
    detect_pks(drug, "drug", method = "uniqueness"),
    c("rechal", "k")
  )
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

test_that("a privacy decision on a column holding a blank does not go stale", {
  # Decisions are stamped with a hash of the raw values (write_flag,
  # privacy_review_set); the dictionary must check them against raw values
  # too, not against the blank-as-missing version
  tables <- list(
    x = data.frame(
      id = 1:3,
      email = c("a@example.org", "", "b@example.org"),
      stringsAsFactors = FALSE
    )
  )
  dictionary <- list()
  dictionary[[dict_key("x", "email")]] <- list(
    private = FALSE,
    public_for = privacy_data_hash(tables$x$email)
  )
  dd <- build_data_dictionary(
    tables,
    list(),
    list(x = "id"),
    dictionary = dictionary
  )
  row <- dd[dd$column == "email", ]
  expect_equal(row$privacy_status, "user_public")
  expect_false(row$private)
})

test_that("examples turned on for a column holding a blank stay on", {
  # The stamp is a hash of the raw values (examples_for), so the dictionary
  # must check it against raw values, not the blank-as-missing version
  tables <- list(
    x = data.frame(
      id = 1:3,
      colour = c("red", "", "blue"),
      stringsAsFactors = FALSE
    )
  )
  dictionary <- list(.settings = list(examples = "off"))
  dictionary[[dict_key("x", "colour")]] <- list(
    hide_examples = FALSE,
    examples_for = privacy_data_hash(tables$x$colour)
  )
  dd <- build_data_dictionary(
    tables,
    list(),
    list(x = "id"),
    dictionary = dictionary
  )
  row <- dd[dd$column == "colour", ]
  expect_equal(row$examples_note, "")
  expect_match(row$examples, "red", fixed = TRUE)
})

test_that("Unicode spaces are blank, zero-width characters and bad UTF-8 are not", {
  x <- c("\u00a0", " \u3000 ", "\u200b", "\ufeff", "a\u00a0")
  expect_identical(
    blank_as_na(x),
    c(NA, NA, "\u200b", "\ufeff", "a\u00a0")
  )
  bad <- "ab\xff"
  expect_no_warning(out <- is_blank_text(c(bad, "")))
  expect_identical(out, c(FALSE, TRUE))
  # A Latin-1 marked non-breaking space is blank too
  lat <- "\xa0"
  Encoding(lat) <- "latin1"
  expect_true(is_blank_text(lat))
})

test_that("a cached blank count does not go stale when the column changes", {
  x <- rep(c("a", "b"), 6000)
  df <- data.frame(x = x, stringsAsFactors = FALSE)
  unusual_blank_counts(df, store = TRUE)
  expect_equal(n_blank(df$x), 0L)
  df$x[1] <- ""
  expect_equal(n_blank(df$x), 1L)
  expect_true(is.na(blank_as_na(df$x)[1]))
})

test_that("the ERD model counts blank text as missing", {
  tables <- list(
    customer = data.frame(id = c("a", "b", "c"), stringsAsFactors = FALSE),
    orders = data.frame(
      order_id = 1:4,
      customer_id = c("a", "b", "", "c"),
      note = c("x", " ", "y", "z"),
      stringsAsFactors = FALSE
    )
  )
  rels <- list(list(
    from_table = "orders",
    from_col = "customer_id",
    to_table = "customer",
    to_col = "id"
  ))
  m <- erd_model(tables, rels, list(customer = "id", orders = "order_id"))
  cols <- m$tables$orders$columns
  expect_true(cols$nullable[cols$name == "note"])
  expect_equal(cols$n_blank[cols$name == "note"], 1L)
  expect_false(cols$unique[cols$name == "note"])
  # The blank customer_id is a missing parent, so the parent is optional,
  # and the remaining distinct values no longer make the link 1:1
  expect_equal(m$rels[[1]]$parent_min, "zero")
  expect_equal(m$rels[[1]]$child_max, "many")
})

test_that("a declared key holding '' is still the key", {
  # A database can store '' in a key column; that is its value, not a
  # contradiction of the declaration
  tables <- list(t = data.frame(code = c("", "A", "B"), n = 1:3))
  pk <- structure("code", declared = TRUE)
  m <- erd_model(tables, list(), list(t = pk))
  expect_true(m$tables$t$columns$pk[m$tables$t$columns$name == "code"])
})

test_that("DBML and YAML drop not null and required on a column with blanks, and say why", {
  tables <- list(
    customers = data.frame(
      id = 1:4,
      middle_name = c("Ann", "", "", "Lee"),
      city = c("X", "Y", "Z", "W"),
      nick = c("Bo", "Al", " ", "Cy"),
      stringsAsFactors = FALSE
    )
  )
  dictionary <- list()
  dictionary[[dict_key("customers", "nick")]] <- list(
    description = "Short name"
  )
  expect_match(
    generate_dbml(
      tables,
      list(),
      list(customers = "id"),
      dictionary = dictionary
    ),
    "nick string [note: 'Short name. 1 blank value counted as missing; a database would store it as an empty string.']",
    fixed = TRUE
  )
  pks <- list(customers = "id")
  dbml <- generate_dbml(tables, list(), pks)
  expect_match(
    dbml,
    "middle_name string [note: '2 blank values counted as missing; a database would store them as empty strings.']",
    fixed = TRUE
  )
  # Survival: a column without blanks keeps not null
  expect_match(dbml, "city string [not null]", fixed = TRUE)
  y <- strsplit(generate_data_dict_yaml(tables, list(), pks), "\n")[[1]]
  block <- function(col) {
    i <- grep(paste0("- name: ", col, "$"), y)
    j <- grep("^ *- name: ", y)
    end <- min(c(j[j > i], length(y) + 1)) - 1
    y[i:end]
  }
  mid <- paste(block("middle_name"), collapse = "\n")
  expect_false(grepl("- required", mid, fixed = TRUE))
  expect_match(mid, "2 blank values counted as missing", fixed = TRUE)
  expect_match(
    paste(block("city"), collapse = "\n"),
    "- required",
    fixed = TRUE
  )
})

test_that("the load notice names columns blank only through non-standard spaces", {
  tables <- list(
    a = data.frame(
      p = c("\u00a0", "x", "\u00a0 "),
      q = c("", " ", "y"),
      stringsAsFactors = FALSE
    ),
    b = data.frame(r = c("z", "\u3000"), stringsAsFactors = FALSE)
  )
  expect_identical(unusual_blank_counts(tables$a), c(p = 2L))
  msg <- unusual_blank_notice(tables)
  expect_match(msg, "3 values in 2 columns (a.p, b.r)", fixed = TRUE)
  # Ordinary blanks alone give no notice
  expect_null(unusual_blank_notice(list(a = tables$a["q"])))
})
