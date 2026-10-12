# A column that is unique by accident, not by design. Chinook's
# customer.address has 59 distinct values over 59 rows, so it passes every
# key test, and invoice.billingaddress is wholly inside it because the
# billing address was copied from the customer. The pair scores 1.000 and
# is the only high-confidence false positive Chinook produces.

test_that("prose is told from an identifier by its spaces, not by its name", {
  expect_true(is_prose_column(c(
    "Theodor-Heuss-Strasse 34",
    "Ullevaalsveien 14",
    "Klanova 9/506",
    "12 Oak Lane",
    "Rua Dona Margarida 359"
  )))
  # The shapes real keys take in the three measured schemas: Lahman player
  # ids, Lahman park keys, Lahman school ids, FAERS and Chinook integers.
  expect_false(is_prose_column(c("aardsda01", "abadfe01", "zuvelta01")))
  expect_false(is_prose_column(c("BOS07", "CHI11", "NYC17")))
  expect_false(is_prose_column(c("abilchrist", "yale", "texas")))
  expect_false(is_prose_column(c(101L, 102L, 103L)))
  expect_false(is_prose_column(c("1234", "1235", "1236")))
})

test_that("a code column padded by a careless export is still a code column", {
  # Leading and trailing space is not internal whitespace.
  expect_false(is_prose_column(c(" A101 ", " A102 ", " A103 ")))
})

test_that("a long opaque token reads as prose even without a space", {
  long <- paste0(strrep("x", 40L), 1:5)
  expect_true(is_prose_column(long))
})

test_that("a mostly single-word column with one spaced value is not prose", {
  # Half rather than all: one stray value must not flip a code column, and
  # a few single-word addresses must not rescue an address column.
  expect_false(is_prose_column(c("rock", "jazz", "blues", "heavy metal")))
})

test_that("an empty or all-missing column is not prose", {
  expect_false(is_prose_column(character(0)))
  expect_false(is_prose_column(c(NA_character_, NA_character_)))
})

# The behaviour the guard exists for, on an invented fixture of the same
# shape as the Chinook pair: a parent whose text values are unique by
# accident, and a child that copied them.
addr_tables <- function() {
  addresses <- paste(1:40, c("Oak Lane", "Elm Street", "High Road", "Mill Way"))
  list(
    customer = data.frame(
      customer_id = 1:40,
      address = addresses,
      stringsAsFactors = FALSE
    ),
    # The child repeats, as Chinook's does: 412 invoices over 59
    # addresses. A child column that is itself unique takes a different
    # path in detect_fks and would not exercise this at all.
    invoice = data.frame(
      invoice_id = 1:120,
      billing_address = rep(addresses, 3L),
      stringsAsFactors = FALSE
    )
  )
}

pair_keys <- function(rels) {
  vapply(
    rels,
    function(r) {
      sprintf(
        "%s.%s -> %s.%s",
        r$from_table,
        r$from_col,
        r$to_table,
        r$to_col %||% ""
      )
    },
    ""
  )
}

test_that("a prose parent is offered by default and refused as a target", {
  tabs <- addr_tables()
  found <- function(guard) {
    rels <- detect_fks(
      tabs,
      method = "both",
      min_confidence = "low",
      prose_parent_guard = guard
    )
    pair_keys(rels)
  }
  pair <- "invoice.billing_address -> customer.address"
  expect_true(pair %in% found("allow"))
  expect_false(pair %in% found("refuse_target"))
})

test_that("refusing containment alone does not remove the pair", {
  # The measured reason the guard has a target level at all: this pair
  # also carries identical value sets and full overlap, whose noisy-OR is
  # already high, so suppressing containment changes nothing a reviewer
  # would see. If this test ever fails because the pair disappears at
  # "refuse", the target level has become unnecessary.
  rels <- detect_fks(
    addr_tables(),
    method = "both",
    min_confidence = "low",
    prose_parent_guard = "refuse"
  )
  hit <- Filter(
    function(r) r$from_col == "billing_address" && r$to_col == "address",
    rels
  )
  expect_length(hit, 1L)
  expect_false(any(grepl("contained", paste(hit[[1]]$reasons, collapse = " "))))
})

test_that("a code-named text key survives the target refusal", {
  # The survival half: refusing prose parents must not cost a real text
  # key, which is the shape every Lahman link takes.
  players <- sprintf(
    "%s%02d",
    rep(c("aardsda", "abadfe", "zuvelta"), each = 5),
    1:5
  )
  tabs <- list(
    people = data.frame(player_id = players, stringsAsFactors = FALSE),
    batting = data.frame(
      player_id = rep(players, 2),
      runs = seq_along(rep(players, 2)),
      stringsAsFactors = FALSE
    )
  )
  rels <- detect_fks(
    tabs,
    method = "both",
    min_confidence = "medium",
    prose_parent_guard = "refuse_target"
  )
  keys <- pair_keys(rels)
  expect_true("batting.player_id -> people.player_id" %in% keys)
})

test_that("an unknown guard level is refused rather than ignored", {
  expect_error(
    detect_fks(
      list(a = data.frame(x = 1:3), b = data.frame(x = 1:3)),
      prose_parent_guard = "sometimes"
    ),
    "should be one of"
  )
})
