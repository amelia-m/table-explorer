# ============================================================
# Tests for inference.R - PK/FK Detection Engine
# ============================================================

# ── Name helpers ─────────────────────────────────────────────

test_that("clean_name lowercases and underscores", {
  expect_equal(clean_name("CustomerID"), "customer_id")
  expect_equal(clean_name("order items"), "order_items")
  expect_equal(clean_name("simple"), "simple")
})

test_that("id_stem strips _id suffix", {
  expect_equal(id_stem("customer_id"), "customer")
  expect_equal(id_stem("product_id"), "product")
  expect_equal(id_stem("name"), "name")
  expect_equal(id_stem("id"), "id")
})

test_that("is_pk_name detects pk-like columns", {
  expect_true(is_pk_name("id", "customers"))
  expect_true(is_pk_name("customer_id", "customer"))
  expect_true(is_pk_name("customers_id", "customers"))
  expect_false(is_pk_name("name", "customers"))
  expect_false(is_pk_name("email", "customers"))
})

test_that("is_fk_for detects fk-like columns for target table", {
  expect_true(is_fk_for("customer_id", "customer"))
  expect_true(is_fk_for("order_id", "order"))
  expect_false(is_fk_for("name", "customer"))
  expect_false(is_fk_for("customer_id", "product"))
})

# ── Type classification ──────────────────────────────────────

test_that("col_dtype_class classifies types correctly", {
  expect_equal(col_dtype_class(1:10), "numeric")
  expect_equal(col_dtype_class(c(1.5, 2.5)), "numeric")
  expect_equal(col_dtype_class(c("a", "b")), "string")
  expect_equal(col_dtype_class(as.Date("2024-01-01")), "datetime")
  expect_equal(col_dtype_class(Sys.time()), "datetime")
  expect_equal(col_dtype_class(factor(c("a", "b"))), "string")
})

# ── Format fingerprint ───────────────────────────────────────

test_that("format_fingerprint detects email format", {
  emails <- c("alice@example.com", "bob@example.com", "carol@test.org")
  expect_equal(format_fingerprint(emails), "email")
})

test_that("format_fingerprint detects uuid format", {
  uuids <- c(
    "550e8400-e29b-41d4-a716-446655440000",
    "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
    "f47ac10b-58cc-4372-a567-0e02b2c3d479"
  )
  expect_equal(format_fingerprint(uuids), "uuid")
})

test_that("format_fingerprint detects iso_date format", {
  dates <- c("2024-01-01", "2024-06-15", "2023-12-31")
  expect_equal(format_fingerprint(dates), "iso_date")
})

test_that("format_fingerprint detects int_code format", {
  codes <- c("101", "202", "303", "404")
  expect_equal(format_fingerprint(codes), "int_code")
})

test_that("format_fingerprint returns NULL for mixed data", {
  mixed <- c("hello", "123", "alice@test.com", "2024-01-01")
  expect_null(format_fingerprint(mixed))
})

test_that("format_fingerprint handles all-NA gracefully", {
  expect_null(format_fingerprint(c(NA, NA, NA)))
})

# ── Value overlap ────────────────────────────────────────────

test_that("value_overlap computes correct overlap ratio", {
  expect_equal(value_overlap(c(1, 2, 3), c(1, 2, 3, 4, 5)), 1.0)
  expect_equal(value_overlap(c(1, 2, 3, 4), c(1, 2)), 0.5)
  expect_equal(value_overlap(c("a", "b"), c("c", "d")), 0.0)
})

test_that("value_overlap handles NAs", {
  expect_equal(value_overlap(c(1, NA, 3), c(1, 3)), 1.0)
})

test_that("value_overlap returns 0 for empty input", {
  expect_equal(value_overlap(c(NA, NA), c(1, 2)), 0.0)
})

# ── Distribution similarity ─────────────────────────────────

test_that("distribution_similarity returns 1 for identical distributions", {
  v <- c("a", "a", "b", "b", "c")
  sim <- distribution_similarity(v, v)
  expect_equal(sim, 1.0, tolerance = 0.001)
})

test_that("distribution_similarity returns 0 for no-overlap", {
  sim <- distribution_similarity(c("a", "a"), c("x", "x"))
  expect_equal(sim, 0.0)
})

test_that("distribution_similarity handles empty input", {
  expect_equal(distribution_similarity(c(NA, NA), c("a")), 0.0)
})

# ── Null pattern correlation ─────────────────────────────────

test_that("null_pattern_correlation returns 0 for different-length dfs", {
  df1 <- data.frame(a = c(1, 2))
  df2 <- data.frame(b = c(1, 2, 3))
  expect_equal(null_pattern_correlation(df1, "a", df2, "b"), 0.0)
})

test_that("null_pattern_correlation returns 0 with no NAs", {
  df <- data.frame(a = c(1, 2, 3), b = c(4, 5, 6))
  expect_equal(null_pattern_correlation(df, "a", df, "b"), 0.0)
})

test_that("null_pattern_correlation detects correlated nulls", {
  df <- data.frame(
    a = c(1, NA, 3, NA, 5, NA, 7, NA, 9, NA),
    b = c(10, NA, 30, NA, 50, NA, 70, NA, 90, NA)
  )
  r <- null_pattern_correlation(df, "a", df, "b")
  expect_gt(r, 0.9)
})

# ── Primary key detection ────────────────────────────────────

test_that("detect_pks finds id column by naming", {
  df <- data.frame(id = 1:5, name = c("a", "b", "c", "d", "e"))
  pks <- detect_pks(df, "customers", method = "naming")
  expect_true("id" %in% pks)
})

test_that("detect_pks finds table_id column by naming", {
  df <- data.frame(customer_id = 1:5, name = letters[1:5])
  pks <- detect_pks(df, "customers", method = "naming")
  expect_true("customer_id" %in% pks)
})

test_that("detect_pks finds unique columns by content", {
  df <- data.frame(
    code = c("A1", "A2", "A3"),
    value = c(10, 10, 30)
  )
  pks <- detect_pks(df, "items", method = "both")
  expect_true("code" %in% pks)
  expect_false("value" %in% pks)
})

test_that("detect_pks returns empty for no candidates", {
  df <- data.frame(value = c(1, 1, 1))
  pks <- detect_pks(df, "items", method = "both")
  expect_length(pks, 0)
})

# ── Score candidate ──────────────────────────────────────────

test_that("score_candidate detects exact FK naming", {
  df1 <- data.frame(customer_id = c(1, 2, 3))
  df2 <- data.frame(id = c(1, 2, 3))
  flags <- list(
    naming = TRUE, value_overlap = FALSE, cardinality = FALSE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  result <- score_candidate("orders", "customer_id", df1, "customer", "id", df2, flags)
  expect_false(is.null(result))
  expect_equal(result$detected_by, "naming")
  expect_equal(result$confidence, "high")
  expect_equal(result$score, 1.0)
})

test_that("score_candidate returns NULL for type mismatch", {
  df1 <- data.frame(customer_id = c("a", "b", "c"))
  df2 <- data.frame(id = c(1, 2, 3))
  flags <- list(
    naming = TRUE, value_overlap = TRUE, cardinality = TRUE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  result <- score_candidate("orders", "customer_id", df1, "customer", "id", df2, flags)
  expect_null(result)
})

test_that("score_candidate returns NULL with no signals triggered", {
  df1 <- data.frame(foo = c(1, 2, 3))
  df2 <- data.frame(bar = c(4, 5, 6))
  flags <- list(
    naming = TRUE, value_overlap = TRUE, cardinality = TRUE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  result <- score_candidate("t1", "foo", df1, "t2", "bar", df2, flags)
  expect_null(result)
})

test_that("score_candidate detects high value overlap", {
  # Scattered ids, not 1..5: a contiguous run is a domain any small number
  # lands in, and overlap on one is discounted as chance
  ids <- c(104, 2071, 3318, 4290, 5307)
  df1 <- data.frame(cust_ref = ids)
  df2 <- data.frame(pk = ids)
  flags <- list(
    naming = FALSE, value_overlap = TRUE, cardinality = TRUE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  result <- score_candidate("orders", "cust_ref", df1, "customers", "pk", df2, flags)
  expect_false(is.null(result))
  expect_true(result$score >= 0.85)
  expect_equal(result$confidence, "high")
})

test_that("score_candidate noisy-OR aggregation combines signals", {
  # Create data that triggers multiple signals
  ids <- c(1, 2, 3, 4, 5)
  df1 <- data.frame(customer_id = ids)
  df2 <- data.frame(id = ids)
  flags <- list(
    naming = TRUE, value_overlap = TRUE, cardinality = TRUE,
    format = TRUE, distribution = TRUE, null_pattern = FALSE
  )
  result <- score_candidate("orders", "customer_id", df1, "customer", "id", df2, flags)
  expect_false(is.null(result))
  # Naming exact alone = 1.0, so score should be 1.0
  expect_equal(result$score, 1.0)
  # Should have multiple signals triggered
  expect_true(length(result$signals) >= 1)
})

# ── Full FK detection pipeline ───────────────────────────────

test_that("detect_fks returns empty for manual method", {
  tables <- list(a = data.frame(id = 1), b = data.frame(id = 2))
  expect_equal(detect_fks(tables, method = "manual"), list())
})

test_that("detect_fks returns empty for single table", {
  tables <- list(only = data.frame(id = 1:3, name = letters[1:3]))
  expect_equal(detect_fks(tables, method = "both"), list())
})

test_that("detect_fks detects naming-based relationship", {
  customers <- data.frame(
    customer_id = 1:5,
    name = letters[1:5]
  )
  orders <- data.frame(
    order_id = 1:5,
    customer_id = c(1, 2, 1, 3, 2),
    amount = c(10, 20, 30, 40, 50)
  )
  tables <- list(customers = customers, orders = orders)
  rels <- detect_fks(tables, method = "naming", min_confidence = "low")
  # Should detect orders.customer_id -> customers
  fk_cols <- vapply(rels, `[[`, character(1), "from_col")
  expect_true("customer_id" %in% fk_cols)
})

test_that("detect_fks respects min_confidence filter", {
  # Create a scenario where only weak signals exist
  df1 <- data.frame(ref = c(1, 2, 3, 4, 5))
  df2 <- data.frame(pk = c(1, 2, 3, 4, 5))
  tables <- list(source = df1, target = df2)

  rels_low <- detect_fks(tables, method = "content", min_confidence = "low")
  rels_high <- detect_fks(tables, method = "content", min_confidence = "high")
  # High filter should be equal or more restrictive
  expect_true(length(rels_high) <= length(rels_low))
})

test_that("detect_fks with sample data detects expected relationships", {
  skip_if_not(
    dir.exists(sample_data_dir),
    "sample_data directory not found"
  )

  customers <- read.csv(file.path(sample_data_dir, "customers.csv"),
                        stringsAsFactors = FALSE, check.names = FALSE)
  orders <- read.csv(file.path(sample_data_dir, "orders.csv"),
                     stringsAsFactors = FALSE, check.names = FALSE)
  products <- read.csv(file.path(sample_data_dir, "products.csv"),
                       stringsAsFactors = FALSE, check.names = FALSE)
  order_items <- read.csv(file.path(sample_data_dir, "order_items.csv"),
                          stringsAsFactors = FALSE, check.names = FALSE)

  # Clean names like the app does
  customers <- janitor::clean_names(customers)
  orders <- janitor::clean_names(orders)
  products <- janitor::clean_names(products)
  order_items <- janitor::clean_names(order_items)

  tables <- list(
    customers = customers,
    orders = orders,
    products = products,
    order_items = order_items
  )

  rels <- detect_fks(tables, method = "both", min_confidence = "low")
  expect_true(length(rels) > 0)

  # Each result should have required fields
  for (r in rels) {
    expect_true(!is.null(r$from_table))
    expect_true(!is.null(r$from_col))
    expect_true(!is.null(r$to_table))
    expect_true(!is.null(r$detected_by))
    expect_true(!is.null(r$confidence))
    expect_true(!is.null(r$score))
    expect_true(r$confidence %in% c("low", "medium", "high"))
    expect_true(r$score >= 0 && r$score <= 1)
  }
})

test_that("detect_fks results are sorted by confidence then score", {
  skip_if_not(dir.exists(sample_data_dir), "sample_data directory not found")

  customers <- janitor::clean_names(read.csv(
    file.path(sample_data_dir, "customers.csv"), stringsAsFactors = FALSE))
  orders <- janitor::clean_names(read.csv(
    file.path(sample_data_dir, "orders.csv"), stringsAsFactors = FALSE))

  tables <- list(customers = customers, orders = orders)
  rels <- detect_fks(tables, method = "both", min_confidence = "low")

  if (length(rels) > 1) {
    conf_rank <- c(low = 0, medium = 1, high = 2)
    for (i in seq_len(length(rels) - 1)) {
      r1 <- rels[[i]]
      r2 <- rels[[i + 1]]
      rank1 <- conf_rank[[r1$confidence]]
      rank2 <- conf_rank[[r2$confidence]]
      # Either higher confidence or same confidence with >= score
      expect_true(rank1 > rank2 || (rank1 == rank2 && r1$score >= r2$score))
    }
  }
})

# ── Complexity estimator ──────────────────────────────────────

test_that("estimate_scan_complexity returns correct structure", {
  tables <- list(
    a = data.frame(id = 1:10, name = letters[1:10]),
    b = data.frame(id = 1:5, a_id = c(1, 2, 3, 4, 5))
  )
  est <- estimate_scan_complexity(tables)
  expect_true(is.list(est))
  expect_true(all(c("n_tables", "total_cols", "total_rows", "max_rows",
                     "est_pairs", "est_time_sec", "tier") %in% names(est)))
  expect_equal(est$n_tables, 2)
  expect_equal(est$total_cols, 4)
  expect_equal(est$tier, "fast")
})

test_that("estimate_scan_complexity flags large schemas as slow", {
  # Simulate 30 tables x 50 columns x 1000 rows each
  tables <- lapply(1:30, function(i) {
    df <- as.data.frame(matrix(sample(1000, 50 * 1000, replace = TRUE), ncol = 50))
    names(df) <- paste0("col_", seq_len(50))
    df
  })
  names(tables) <- paste0("table_", seq_along(tables))
  est <- estimate_scan_complexity(tables)
  expect_true(est$tier %in% c("moderate", "slow"))
  expect_gt(est$est_pairs, 2000)
})

test_that("is_fk_candidate rejects boolean and low-cardinality columns", {
  expect_false(is_fk_candidate(c(TRUE, FALSE, TRUE, FALSE, TRUE, TRUE,
                                  FALSE, TRUE, FALSE, FALSE, TRUE), "is_active"))
  expect_false(is_fk_candidate(c(NA, NA, NA, NA, NA), "empty"))
})

test_that("is_fk_candidate accepts id-like columns", {
  expect_true(is_fk_candidate(1:100, "customer_id"))
  expect_true(is_fk_candidate(c("A1", "A2", "A3", "A4"), "code"))
})

test_that("is_fk_candidate rejects long free-text columns", {
  long_text <- paste(rep("lorem ipsum dolor sit amet consectetur adipiscing", 5), collapse = " ")
  expect_false(is_fk_candidate(rep(long_text, 20), "description"))
})

test_that("clean_name handles a table wider than the 10000-byte name cap", {
  # Regression: the memo cache keyed on the pasted vector, and R caps
  # environment names at 10000 bytes, so a wide table stopped detection
  # with "variable names are limited to 10000 bytes"
  cols <- paste0("a_very_long_column_name_number_", seq_len(400))
  expect_gt(sum(nchar(cols)) + length(cols), 10000)
  out <- clean_name(cols)
  expect_length(out, length(cols))
  expect_equal(out, janitor::make_clean_names(cols))
  # Second call comes from the cache and must agree
  expect_equal(clean_name(cols), out)
})

test_that("detect_pks works on a table wide enough to blow the name cap", {
  cols <- paste0("a_very_long_column_name_number_", seq_len(400))
  df <- as.data.frame(stats::setNames(
    lapply(seq_along(cols), function(i) c(i, i + 1L)),
    cols
  ))
  df$id <- c(1L, 2L)
  expect_true("id" %in% detect_pks(df, "wide_table", method = "both"))
})

test_that("identical column names report as identical, not as similarity", {
  df1 <- data.frame(provider_id = c(1, 2, 3))
  df2 <- data.frame(provider_id = c(1, 2, 3))
  flags <- list(
    naming = TRUE, value_overlap = TRUE, cardinality = TRUE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  res <- score_candidate("tbl_a", "provider_id", df1, "tbl_b", "provider_id", df2, flags)
  expect_true("name_identical" %in% names(res$signals))
  expect_false("name_sim" %in% names(res$signals))
  expect_true(any(grepl("identical column name", res$reasons)))
})

test_that("near-identical column names still report as similarity", {
  df1 <- data.frame(provider_ids = c(1, 2, 3))
  df2 <- data.frame(provider_id = c(1, 2, 3))
  flags <- list(
    naming = TRUE, value_overlap = TRUE, cardinality = TRUE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  res <- score_candidate("tbl_a", "provider_ids", df1, "tbl_b", "provider_id", df2, flags)
  expect_false("name_identical" %in% names(res$signals))
  # Assert the positive too: without it this passes when res is NULL
  expect_true("name_sim" %in% names(res$signals))
})

test_that("splitting out name_identical leaves the score and the label alone", {
  # Fifteen scattered ids, so the value signals are still evidence: three
  # values out of a contiguous 1..3 run is both too small a set for
  # cardinality_match and too dense an overlap to count
  ids <- (1:15) * 100
  df1 <- data.frame(provider_id = ids)
  df2 <- data.frame(provider_id = ids)
  flags <- list(
    naming = TRUE, value_overlap = TRUE, cardinality = TRUE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  res <- score_candidate("tbl_a", "provider_id", df1, "tbl_b", "provider_id", df2, flags)
  # cardinality_match (0.95) outranks the naming signal here, so check the
  # label on a naming-only pass as well
  name_only <- score_candidate(
    "tbl_a", "provider_id", df1, "tbl_b", "provider_id", df2,
    list(
      naming = TRUE, value_overlap = FALSE, cardinality = FALSE,
      format = FALSE, distribution = FALSE, null_pattern = FALSE
    )
  )
  expect_equal(name_only$detected_by, "name_similarity")
  # Same weight as name_sim, so the noisy-OR is unchanged
  expect_equal(unname(weight_map[["name_identical"]]), unname(weight_map[["name_sim"]]))
  # cardinality_match, overlap_high, containment (the ids are a key in
  # tbl_b and all fifteen are found) and name_identical
  expect_equal(
    res$score,
    round(1 - (1 - 0.95) * (1 - 0.92) * (1 - 0.90) * (1 - 0.60), 3)
  )
  # And detected_by keeps its old value: the Method chip, its CSS class,
  # the ERD edge colour and the exports all read this string
  expect_equal(res$detected_by, "cardinality")
  expect_equal(unname(label_map[["name_identical"]]), "name_similarity")
})

test_that("the ambiguity tie-break still treats a closer name as closer", {
  # resolve_fk_parents' "name is closest" branch: the child column name
  # matches one parent's column, and values fit both parents
  tables <- list(
    visits = data.frame(provider_id = c(1, 2, 3, 1)),
    staff = data.frame(provider_id = c(1, 2, 3)),
    sites = data.frame(code = c(1, 2, 3))
  )
  rels <- detect_fks(tables, method = "both", min_confidence = "low")
  to_staff <- Filter(
    function(r) r$from_table == "visits" && r$to_table == "staff",
    rels
  )
  expect_length(to_staff, 1)
  expect_true(
    any(c("name_identical", "name_sim") %in% names(to_staff[[1]]$signals))
  )
})

# ── Constants and maps ───────────────────────────────────────

test_that("weight_map has all expected signal keys", {
  expected_keys <- c(
    "naming_exact", "cardinality_match", "overlap_high", "name_sim",
    "overlap_medium", "dist_high", "format_match", "dist_med",
    "name_sim_weak", "null_corr"
  )
  for (k in expected_keys) {
    expect_true(k %in% names(weight_map), info = paste("Missing key:", k))
  }
})

test_that("label_map covers all weight_map keys", {
  for (k in names(weight_map)) {
    expect_true(k %in% names(label_map), info = paste("Missing label for:", k))
  }
})

test_that("all weight_map values are in [0, 1]", {
  for (w in weight_map) {
    expect_true(w >= 0 && w <= 1)
  }
})

test_that("format_patterns list has expected entries", {
  pattern_names <- vapply(format_patterns, `[[`, character(1), "name")
  expect_true("uuid" %in% pattern_names)
  expect_true("email" %in% pattern_names)
  expect_true("iso_date" %in% pattern_names)
  expect_true("int_code" %in% pattern_names)
})

# ── Composite primary key detection ──────────────────────────

test_that("detect_composite_pks returns empty when single-column PK exists", {
  df <- data.frame(id = 1:5, order_id = c(1, 1, 2, 2, 3), product_id = 1:5)
  result <- detect_composite_pks(df, "items")
  expect_length(result, 0)
})

test_that("detect_composite_pks detects 2-column composite key", {
  df <- data.frame(
    order_id   = c(1, 1, 2, 2, 3),
    product_id = c(10, 20, 10, 30, 20),
    quantity   = c(1, 2, 3, 4, 5)
  )
  result <- detect_composite_pks(df, "order_items")
  expect_length(result, 1)
  expect_setequal(result[[1]], c("order_id", "product_id"))
})

test_that("detect_composite_pks detects 3-column composite key", {
  df <- data.frame(
    a = c(1, 1, 1, 2),
    b = c(1, 1, 2, 1),
    c = c(1, 2, 1, 1),
    d = c("x", "y", "z", "w")
  )
  result <- detect_composite_pks(df, "t")
  expect_length(result, 1)
  expect_setequal(result[[1]], c("a", "b", "c"))
})

test_that("detect_composite_pks returns empty for truly non-unique data", {
  df <- data.frame(
    a = c(1, 1, 1),
    b = c(1, 1, 1)
  )
  result <- detect_composite_pks(df, "t")
  expect_length(result, 0)
})

test_that("detect_composite_pks returns empty for df with fewer than 2 rows", {
  df <- data.frame(order_id = 1L, product_id = 2L)
  result <- detect_composite_pks(df, "items")
  expect_length(result, 0)
})

test_that("detect_composite_pks skips columns with NAs in the combo", {
  df <- data.frame(
    order_id   = c(1, 1, 2, NA, 3),
    product_id = c(10, 20, 10, 30, 20),
    quantity   = c(1, 2, 3, 4, 5)
  )
  # order_id has NA so the pair (order_id, product_id) cannot be a CPK
  result <- detect_composite_pks(df, "order_items")
  if (length(result) > 0) {
    expect_false("order_id" %in% result[[1]])
  }
})

test_that("detect_composite_pks returns empty for single-column table", {
  df <- data.frame(val = c(1, 1, 2))
  result <- detect_composite_pks(df, "t")
  expect_length(result, 0)
})

# ── Prefixed names, 1:1 tables, empty tables ────────────────

test_that("strip_table_prefix removes common table prefixes", {
  expect_equal(strip_table_prefix("tbl_clients"), "clients")
  expect_equal(strip_table_prefix("tlk_city_id"), "city_id")
  expect_equal(strip_table_prefix("customers"), "customers")
  expect_equal(strip_table_prefix("tbl"), "tbl")
})

test_that("is_fk_for requires the table to be named for the key", {
  expect_true(is_fk_for("customer_id", "customers"))
  expect_true(is_fk_for("city_id", "cities"))
  expect_false(is_fk_for("client_id", "client_units"))
  expect_false(is_fk_for("product_id", "product_suppliers"))
})

test_that("detect_fks survives all-NA text columns and one-row tables", {
  tables <- list(
    a = data.frame(client_id = 1:5, uci = NA_character_),
    b = data.frame(client_id = 3L, uci = NA_character_)
  )
  expect_no_error(detect_fks(tables, method = "both", min_confidence = "low"))
})

test_that("detect_fks matches naming through tbl_/tlk_ prefixes", {
  tables <- list(
    tbl_address = data.frame(addr = 1:6, city_id = c(1, 2, 1, 3, 2, 1)),
    tlk_city_id = data.frame(city_id = 1:3, city = c("x", "y", "z"))
  )
  rels <- detect_fks(tables, method = "naming", min_confidence = "medium")
  expect_true(any(vapply(
    rels,
    function(r) r$from_col == "city_id" && r$to_table == "tlk_city_id",
    logical(1)
  )))
})

test_that("detect_fks links 1:1 tables sharing a unique key as a star", {
  ids <- 101:150
  tables <- list(
    enrollment = data.frame(client_id = ids, status = rep(1:2, 25)),
    demographics = data.frame(client_id = ids, age = 21:70),
    hiv_status = data.frame(client_id = ids, flag = rep(0:1, 25))
  )
  rels <- detect_fks(tables, method = "both", min_confidence = "medium")
  key_rels <- Filter(function(r) r$from_col == "client_id", rels)
  # N tables -> N - 1 links to one parent, no mesh or reverse duplicates
  expect_length(key_rels, 2)
  expect_length(unique(vapply(key_rels, `[[`, character(1), "to_table")), 1)
})

test_that("detect_fks name-matches key columns of empty tables", {
  tables <- list(
    tbl_clients = data.frame(client_id = 1:10, age = 21:30),
    tbl_income = data.frame(client_id = integer(0), amount = numeric(0))
  )
  rels <- detect_fks(tables, method = "both", min_confidence = "medium")
  expect_length(rels, 1)
  expect_equal(rels[[1]]$from_table, "tbl_income")
  expect_equal(rels[[1]]$to_table, "tbl_clients")
})

test_that("distribution_similarity handles blank strings", {
  sim <- distribution_similarity(c("", "a", "b", ""), c("", "a", "c"))
  expect_false(is.na(sim))
  expect_gt(sim, 0)
})

test_that("detect_fks survives blank strings in compared text columns", {
  tables <- list(
    a = data.frame(grp = rep(1:10, 4), note = rep(c("", "x", "y", "z"), 10)),
    b = data.frame(grp = rep(1:5, 8), note = rep(c("", "x", "y", "w"), 10))
  )
  expect_no_error(detect_fks(tables, method = "both", min_confidence = "low"))
})

# ── Incremental scans ─────────────────────────────────────────

test_that("tables_needing_scan flags new and changed tables only", {
  tables <- list(a = data.frame(x = 1:3), b = data.frame(y = 1:2))
  sig <- vapply(tables, table_signature, character(1))
  expect_equal(tables_needing_scan(tables, sig), character(0))
  expect_equal(tables_needing_scan(tables, character(0)), c("a", "b"))
  tables$b <- data.frame(y = 1:5)
  tables$c <- data.frame(z = 1)
  expect_equal(tables_needing_scan(tables, sig), c("b", "c"))
  # Same shape and column names, different values
  tables <- list(a = data.frame(x = 4:6))
  expect_equal(tables_needing_scan(tables, sig), "a")
})

test_that("focused detect_fks adds links for new tables and keeps old ones", {
  ids <- 1:40
  old <- list(
    customers = data.frame(customer_id = ids, name = paste0("n", ids)),
    orders = data.frame(order_id = 1:80, customer_id = rep(ids, 2))
  )
  first <- detect_fks(old, "both", "medium")
  all_tables <- c(old, list(
    tbl_income = data.frame(customer_id = integer(0), amount = numeric(0))
  ))
  added <- detect_fks(
    all_tables, "both", "medium",
    focus_tables = "tbl_income",
    existing = first
  )
  # Only relationships involving the new table are returned
  expect_true(length(added) > 0)
  expect_true(all(vapply(
    added,
    function(r) "tbl_income" %in% c(r$from_table, r$to_table),
    logical(1)
  )))
  # Together they match a full scan
  full <- detect_fks(all_tables, "both", "medium")
  key <- function(rs) {
    sort(vapply(rs, function(r) {
      paste(r$from_table, r$from_col, r$to_table, r$to_col)
    }, ""))
  }
  expect_equal(key(c(first, added)), key(full))
})

# ── Naming conventions across database tools ─────────────────

test_that("table_entity strips prefixes, schemas, suffixes and plurals", {
  expect_equal(table_entity("tlk_providers"), "provider")
  expect_equal(table_entity("tlk_city_id"), "city")
  expect_equal(table_entity("dbo_customers"), "customer")
  expect_equal(table_entity("dim_customer"), "customer")
  expect_equal(table_entity("state_lookup"), "state")
  expect_equal(table_entity("ref_categories"), "category")
  expect_equal(table_entity("tbl_addresses"), "address")
  expect_equal(table_entity("enrollment_statuses"), "enrollment_status")
  expect_equal(table_entity("people"), "person")
  expect_equal(table_entity("status"), "status")
})

test_that("fk_name_match recognises common FK column conventions", {
  expect_equal(fk_name_match("provider_id", "tlk_providers"), "exact")
  expect_equal(fk_name_match("id_customer", "customers"), "exact")
  expect_equal(fk_name_match("fk_customer", "customers"), "exact")
  expect_equal(fk_name_match("customer_key", "dim_customer"), "exact")
  expect_equal(fk_name_match("customer_sk", "dim_customer"), "exact")
  expect_equal(fk_name_match("state_code", "ref_states"), "exact")
  expect_equal(fk_name_match("order_no", "orders"), "exact")
  expect_equal(fk_name_match("category_id", "tbl_categories"), "exact")
  expect_equal(fk_name_match("person_id", "people"), "exact")
  # Role / source prefixes
  expect_equal(
    fk_name_match("referring_provider_id", "tlk_providers", is_lookup = TRUE),
    "role"
  )
  expect_equal(
    fk_name_match("trax_enrollment_status_id", "tlk_enrollment_status"),
    "role"
  )
  # Not matches
  expect_null(fk_name_match("status_id", "tlk_enrollment_status"))
  expect_null(fk_name_match("client_id", "client_units"))
  expect_null(fk_name_match("product_id", "product_suppliers"))
  expect_null(fk_name_match("name", "customers"))
  # A single-word role match needs a lookup table
  expect_null(fk_name_match("referring_provider_id", "tbl_providers"))
})

test_that("is_lookup_table uses names and shape", {
  expect_true(is_lookup_table("tlk_services", data.frame(id = integer(0))))
  expect_true(is_lookup_table("state_lookup", data.frame(code = "NE")))
  expect_true(is_lookup_table(
    "statuses",
    data.frame(id = 1:3, label = c("a", "b", "c"))
  ))
  expect_false(is_lookup_table(
    "orders",
    data.frame(id = 1:600, a = 1, b = 2, c = 3, d = 4)
  ))
})

test_that("detect_fks links Access-style lookups keyed on id", {
  prov <- data.frame(id = 1:12, provider_name = paste("p", 1:12))
  visits <- data.frame(
    visit = 1:100,
    provider_id = rep(1:2, 50), # only two distinct providers
    referring_provider_id = rep(1:12, length.out = 100),
    service_id = rep(1:4, 25)
  )
  tables <- list(
    tbl_visits = visits,
    tlk_providers = prov,
    tlk_services = data.frame(id = integer(0), service = character(0))
  )
  rels <- detect_fks(tables, method = "naming", min_confidence = "medium")
  got <- vapply(
    rels,
    function(r) paste0(r$from_col, "->", r$to_table, ".", r$to_col),
    ""
  )
  expect_true("provider_id->tlk_providers.id" %in% got)
  expect_true("referring_provider_id->tlk_providers.id" %in% got)
  expect_true("service_id->tlk_services.id" %in% got)
})

# ── Self-referencing FKs ─────────────────────────────────────

test_that("detect_fks finds self-referencing hierarchy columns", {
  tables <- list(
    employees = data.frame(
      id = 1:6,
      name = letters[1:6],
      manager_id = c(NA, 1L, 1L, 2L, 2L, 3L)
    ),
    categories = data.frame(
      id = 1:5,
      parent_category_id = c(NA, 1L, 1L, 2L, 2L)
    ),
    orders = data.frame(order_id = 1:5, customer_id = c(1L, 2L, 1L, 3L, 2L)),
    customers = data.frame(customer_id = 1:3)
  )
  rels <- detect_fks(tables, method = "naming", min_confidence = "medium")
  key <- vapply(rels, function(r) {
    paste0(r$from_table, ".", r$from_col, "->", r$to_table, ".", r$to_col)
  }, "")
  expect_true("employees.manager_id->employees.id" %in% key)
  expect_true("categories.parent_category_id->categories.id" %in% key)
  expect_false(any(grepl("^orders\\.customer_id->orders", key)))
})

test_that("self_ref_match rejects non-hierarchy and other-entity names", {
  df <- data.frame(id = 1:5, prior_status_id = c(1L, 2L, 1L, 2L, 3L),
                   trax_client_id = 1:5)
  expect_null(self_ref_match("tbl_clients", "prior_status_id", df, "id"))
  expect_null(self_ref_match("tbl_clients", "trax_client_id", df, "id"))
  # Values not in the key
  emp <- data.frame(id = 1:3, manager_id = c(90L, 91L, 92L))
  expect_null(self_ref_match("employees", "manager_id", emp, "id"))
})

# ── Choosing between candidate parents (Access lookups share ids 1..N) ──

access_lookup_fixture <- function() {
  set.seed(11)
  lk <- c("services", "sites", "providers", "programs")
  tbls <- lapply(lk, function(l) data.frame(id = 1:8, label = paste(l, 1:8)))
  names(tbls) <- paste0("tlk_", lk)
  tbls$tbl_visits <- data.frame(
    visit_id = 1:60,
    service_id = sample(1:8, 60, TRUE),
    site_id = sample(1:8, 60, TRUE),
    code = sample(1:8, 60, TRUE)
  )
  tbls
}

links_from <- function(rels, col) {
  Filter(function(r) r$from_table == "tbl_visits" && r$from_col == col, rels)
}

test_that("a column's name picks its lookup; other lookups drop to low", {
  rels <- detect_fks(access_lookup_fixture(), "both", "medium")
  svc <- links_from(rels, "service_id")
  strong <- Filter(function(r) r$confidence != "low", svc)
  expect_equal(vapply(strong, `[[`, "", "to_table"), "tlk_services")
  weak <- Filter(function(r) r$confidence == "low", svc)
  expect_setequal(
    vapply(weak, `[[`, "", "to_table"),
    c("tlk_sites", "tlk_providers", "tlk_programs")
  )
  expect_true(all(vapply(weak, function(r) {
    identical(r$reasons[[1]], "name points to tlk_services")
  }, logical(1))))
})

test_that("values that fit several lookups with no name to go on are low", {
  rels <- detect_fks(access_lookup_fixture(), "both", "medium")
  code <- links_from(rels, "code")
  expect_length(code, 4)
  expect_true(all(vapply(code, `[[`, "", "confidence") == "low"))
  expect_match(code[[1]]$reasons[[1]], "^ambiguous: values fit 4 tables")
})

test_that("a content-only match to a single parent is left alone", {
  # Scattered keys, so the overlap is evidence rather than the free fit any
  # small number gets inside a contiguous 1..5 run
  keys <- c(104, 2071, 3318, 4290, 5307)
  tbls <- list(
    parent = data.frame(pk = keys, label = letters[1:5]),
    child = data.frame(row = 1:20, cust_ref = rep(keys, 4))
  )
  rels <- detect_fks(tbls, "both", "medium")
  r <- Filter(function(r) r$from_col == "cust_ref", rels)
  expect_length(r, 1)
  expect_equal(r[[1]]$confidence, "high")
})

test_that("resolving parents is repeatable and order-independent", {
  rels <- detect_fks(access_lookup_fixture(), "both", "medium")
  key <- function(rs) {
    sort(vapply(rs, function(r) paste(r$from_col, r$to_table, r$confidence), ""))
  }
  expect_equal(key(resolve_fk_parents(rels)), key(rels))
  expect_equal(key(resolve_fk_parents(rev(rels))), key(rels))
})

test_that("a new lookup the name points to demotes an older value-only link", {
  tbls <- access_lookup_fixture()
  first <- detect_fks(tbls[setdiff(names(tbls), "tlk_services")], "both", "medium")
  svc_first <- links_from(first, "service_id")
  # Without tlk_services, service_id's values fit 3 lookups: ambiguous
  expect_true(all(vapply(svc_first, `[[`, "", "confidence") == "low"))
  added <- detect_fks(tbls, "both", "medium", focus_tables = "tlk_services", existing = first)
  merged <- resolve_fk_parents(c(first, added))
  svc <- links_from(merged, "service_id")
  strong <- Filter(function(r) r$confidence != "low", svc)
  expect_equal(vapply(strong, `[[`, "", "to_table"), "tlk_services")
  full <- links_from(detect_fks(tbls, "both", "medium"), "service_id")
  key <- function(rs) sort(vapply(rs, function(r) paste(r$to_table, r$confidence), ""))
  expect_equal(key(svc), key(full))
})

test_that("format and loose name likeness can't carry a link without shared values", {
  tbls <- list(
    tbl_payment = data.frame(payment_id = 6001:6060),
    tbl_client = data.frame(client_id = 1:60, amount = rep(c(5, 10, 20, 50), 15))
  )
  rels <- detect_fks(tbls, "both", "medium")
  expect_length(Filter(function(r) r$from_col == "amount", rels), 0)
})

test_that("is_lookup_table re-checks a same-shaped table with renamed columns", {
  keyed <- data.frame(id = 1:5, label = letters[1:5])
  renamed <- data.frame(foo = 1:5, bar = letters[1:5])
  expect_true(is_lookup_table("statuses_z", keyed))
  # Same name and shape, but no key-named column any more
  expect_false(is_lookup_table("statuses_z", renamed))
})

test_that("is_lookup_table re-checks a table whose content changed", {
  a <- data.frame(id = 1:5, label = letters[1:5])
  b <- data.frame(id = c(1L, 1L, 2L, 3L, 4L), label = letters[1:5])
  expect_true(is_lookup_table("statuses_x", a))
  # Same name and shape, but the key is no longer unique
  expect_false(is_lookup_table("statuses_x", b))
  expect_true(is_lookup_table("statuses_x", a))
})

# ── Shared columns ───────────────────────────────────────────

test_that("detect_shared_columns finds a shared attribute neither side keys", {
  tables <- list(
    toxicology = data.frame(
      victim_substance_id = 1:6,
      incident_year = c(2023, 2024, 2024, 2025, 2025, 2025)
    ),
    document = data.frame(
      document_id = 1:5,
      incident_year = c(2024, 2024, 2025, 2025, 2023)
    )
  )
  out <- detect_shared_columns(tables)
  expect_length(out, 1)
  expect_equal(out[[1]]$column, "incident_year")
  expect_equal(out[[1]]$overlap, 1)
  expect_true(out[[1]]$contained)
})

test_that("detect_shared_columns leaves foreign keys to detect_fks", {
  # client_id is unique in clients, so this pair is an FK question
  tables <- list(
    visits = data.frame(visit_id = 1:4, client_id = c(1, 1, 2, 3)),
    clients = data.frame(client_id = 1:3, name = letters[1:3])
  )
  expect_length(detect_shared_columns(tables), 0)
})

test_that("detect_shared_columns ignores flags and tiny domains", {
  tables <- list(
    a = data.frame(id = 1:6, is_active = rep(c(TRUE, FALSE), 3)),
    b = data.frame(id = 1:6, is_active = rep(c(TRUE, FALSE), 3))
  )
  expect_length(detect_shared_columns(tables), 0)
})

test_that("detect_shared_columns needs the values to actually overlap", {
  tables <- list(
    a = data.frame(k = 1:6, year = c(2001, 2002, 2003, 2004, 2005, 2006)),
    b = data.frame(k = 1:6, year = c(2011, 2012, 2013, 2014, 2015, 2016))
  )
  expect_length(detect_shared_columns(tables), 0)
})

test_that("score_candidate reports overlap and row counts for the table", {
  flags <- list(
    naming = TRUE, value_overlap = TRUE, cardinality = TRUE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  df1 <- data.frame(client_id = c(1, 2, 3, 4))
  df2 <- data.frame(client_id = c(1, 2, 3, 4, 5, 6))
  res <- score_candidate("visits", "client_id", df1, "clients", "client_id", df2, flags)
  expect_equal(res$n_from, 4L)
  expect_equal(res$n_to, 6L)
  expect_equal(res$overlap, 1)
})

test_that("score_candidate says when there were no rows to compare", {
  flags <- list(
    naming = TRUE, value_overlap = TRUE, cardinality = TRUE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  empty <- data.frame(client_id = integer(0))
  df2 <- data.frame(client_id = c(1, 2, 3))
  res <- score_candidate("visits", "client_id", empty, "clients", "client_id", df2, flags)
  expect_true(any(grepl("no rows to compare", res$reasons)))
  expect_equal(res$n_from, 0L)
  expect_true(is.na(res$overlap))
})

# ── Precision rules ──────────────────────────────────────────

test_that("a date-stamped table name still matches its key column", {
  # incident_6_30_26 reads as incident, so incident_id is exact FK naming
  # rather than a loose name similarity that gets demoted as ambiguous
  expect_equal(table_entity("incident_6_30_26"), "incident")
  expect_equal(table_entity("visits_2024"), "visit")
  expect_equal(table_entity("claims_20240630"), "claim")
  expect_equal(table_entity("orders_v2"), "order")
  expect_equal(table_entity("people_final"), "person")
  # A name that is only a stamp keeps its own text rather than emptying
  expect_true(nzchar(table_entity("2024")))
  # Digits that carry meaning are left alone
  expect_equal(table_entity("icd10"), "icd10")
})

test_that("identical generic key names are not evidence of a link", {
  flags <- list(
    naming = TRUE, value_overlap = FALSE, cardinality = FALSE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  df <- data.frame(record_id = c(1, 2, 3))
  # record_id is this extract's house surrogate key: every table has one
  res <- score_candidate("tbl_a", "record_id", df, "tbl_b", "record_id", df, flags)
  expect_null(res)
  # An entity-named key still counts
  df2 <- data.frame(client_id = c(1, 2, 3))
  res2 <- score_candidate("tbl_a", "client_id", df2, "tbl_b", "client_id", df2, flags)
  expect_true("name_identical" %in% names(res2$signals))
})

test_that("a name-only candidate with no rows to compare cannot reach medium", {
  flags <- list(
    naming = TRUE, value_overlap = TRUE, cardinality = TRUE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  empty <- data.frame(client_id = integer(0))
  res <- score_candidate("tbl_a", "client_id", empty, "tbl_b", "client_id", empty, flags)
  expect_equal(res$confidence, "low")
  expect_lte(res$score, 0.54)
  # Survival check: the same pair with rows and matching values is not capped
  full <- data.frame(client_id = c(1, 2, 3))
  res2 <- score_candidate("tbl_a", "client_id", full, "tbl_b", "client_id", full, flags)
  expect_true(res2$confidence %in% c("medium", "high"))
})

test_that("a parent column whose values repeat is not offered as a target", {
  # Nothing in victim identifies a row: every value appears twice. Before
  # this rule a table like that offered every plausible column as a target,
  # and a free-text description matched a label column on values alone.
  labs <- sprintf("label_%02d", 1:15)
  victim <- data.frame(
    homeless_label = rep(labs, 2),
    height_inches = rep(60:74, 2)
  )
  pdo <- data.frame(
    pdo_id = 1:30,
    witnessed_drug_use_description = rep(labs, 2)
  )
  expect_equal(near_unique_cols(victim), character(0))
  rels <- detect_fks(list(pdo = pdo, victim = victim), "both", "medium")
  expect_false(any(vapply(rels, `[[`, "", "to_table") == "victim"))
})

test_that("a key with a few duplicate rows is still a parent", {
  # Survival check for the rule above: five repeated ids in a thousand rows
  # is a dirty key, not a non-key, and the strict uniqueness test in
  # detect_fks' pk_map misses it
  client <- data.frame(
    client_id = c(1:995, 1:5),
    region = rep(c("north", "south", "east", "west", "central"), 200)
  )
  visit <- data.frame(visit_id = 1:200, client_id = rep(1:100, 2))
  expect_equal(near_unique_cols(client), "client_id")
  rels <- detect_fks(list(visit = visit, client = client), "both", "medium")
  to_client <- Filter(function(r) r$to_table == "client", rels)
  expect_length(to_client, 1)
  expect_equal(to_client[[1]]$from_col, "client_id")
  expect_equal(to_client[[1]]$to_col, "client_id")
})

test_that("overlap inside a dense integer run is not evidence", {
  flags <- list(
    naming = FALSE, value_overlap = TRUE, cardinality = TRUE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  # A weapon count of 0..12 sits inside any contiguous 1..N id column, so
  # 92% of its values are "found" without anything being tested
  counts <- data.frame(number_of_weapons = rep(0:12, 5))
  dense <- data.frame(height_inches = 1:60)
  expect_null(score_candidate(
    "incident", "number_of_weapons", counts,
    "victim", "height_inches", dense, flags
  ))
  # Survival check: the same overlap over a sparse domain is still evidence,
  # because landing on 13 scattered values is not something a count does by
  # accident
  spread <- (0:12) * 500
  sparse_child <- data.frame(number_of_weapons = rep(spread, 5))
  sparse_parent <- data.frame(ticket_no = spread)
  res <- score_candidate(
    "incident", "number_of_weapons", sparse_child,
    "ticket", "ticket_no", sparse_parent, flags
  )
  expect_true("overlap_high" %in% names(res$signals))
})

test_that("identical value sets on a small domain are not evidence", {
  flags <- list(
    naming = FALSE, value_overlap = FALSE, cardinality = TRUE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  # Two code columns over 1..8 both end up holding all eight values: the
  # match is the expected outcome, not a coincidence worth 0.95
  severity <- data.frame(severity = rep(1:8, 10))
  priority <- data.frame(priority = rep(1:8, 4))
  expect_null(score_candidate(
    "incident", "severity", severity, "task", "priority", priority, flags
  ))
  # Survival check: past the floor an exact set match still counts
  dx <- sprintf("D%03d", 1:14)
  res <- score_candidate(
    "claim", "dx", data.frame(dx = rep(dx, 3)),
    "tlk_dx", "dx_code", data.frame(dx_code = rep(dx, 2)), flags
  )
  expect_true("cardinality_match" %in% names(res$signals))
})

test_that("a genuine lookup link with six distinct values is still found", {
  # Survival check for both value rules at once: a real FK into a small
  # lookup has no value evidence left once chance overlap and tiny
  # identical sets are discounted, and has to reach medium+ on its name
  tbls <- list(
    tlk_statuses = data.frame(id = 1:6, label = paste("status", 1:6)),
    tbl_visit = data.frame(visit_id = 1:40, status_id = rep(1:6, length.out = 40))
  )
  rels <- detect_fks(tbls, "both", "medium")
  link <- Filter(function(r) r$from_col == "status_id", rels)
  expect_length(link, 1)
  expect_equal(link[[1]]$to_table, "tlk_statuses")
  expect_equal(link[[1]]$to_col, "id")
  expect_true("naming_exact" %in% names(link[[1]]$signals))
})

test_that("a wide child column keeps its overlap evidence on a dense parent", {
  # Coincidence needs a small child domain. 500 distinct values all
  # present in a contiguous 1..1000 key is a reference, not luck, and
  # discounting it by the parent's density lost the link entirely.
  flags <- list(
    naming = FALSE, value_overlap = TRUE, cardinality = TRUE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  parent <- data.frame(pid = 1:1000)
  child <- data.frame(ref = with_local_seed(1, sample(1:1000, 500)))
  res <- score_candidate("child_t", "ref", child, "parent_t", "pid", parent, flags)
  expect_false(is.null(res))
  expect_true("overlap_high" %in% names(res$signals))

  # The coincidence the discount exists for, same parent, still rejected
  counts <- data.frame(n = with_local_seed(2, sample(0:12, 400, replace = TRUE)))
  expect_null(
    score_candidate("child_t", "n", counts, "parent_t", "pid", parent, flags)
  )
})

# ── The chance discount as a setting ─────────────────────────
# Both tests below use the coincidence the discount exists for: a count
# column of 13 distinct values inside a contiguous 1..1000 key, which the
# test above shows is rejected at the defaults. One switches the discount
# off, the other moves the threshold that decides which pairs it reaches,
# so each can fail on its own.

chance_fixture <- function() {
  list(
    flags = list(
      naming = FALSE, value_overlap = TRUE, cardinality = TRUE,
      format = FALSE, distribution = FALSE, null_pattern = FALSE
    ),
    parent = data.frame(pid = 1:1000),
    # A count column: 13 distinct values, 12 of them inside a contiguous
    # 1..1000 key, so the raw overlap is 0.92 and a parent of density 1.0
    # hands out every bit of it for free. Deliberately short of the 0.99
    # containment tier, so the overlap signals are the only evidence in
    # play and the discount is the only thing deciding the pair.
    counts = data.frame(n = with_local_seed(2, sample(0:12, 400, replace = TRUE)))
  )
}

test_that("switching the chance discount off restores the coincidence", {
  fx <- chance_fixture()
  # Default: the discount is applied and the pair is not evidence
  expect_null(score_candidate(
    "child_t", "n", fx$counts, "parent_t", "pid", fx$parent, fx$flags
  ))
  off <- score_candidate(
    "child_t", "n", fx$counts, "parent_t", "pid", fx$parent, fx$flags,
    overlap_chance_discount = FALSE
  )
  expect_true("overlap_medium" %in% names(off$signals))

  # And through detect_fks, which is how a scan sets it. The child column
  # is named nothing like the parent, so the overlap is all it has.
  tbls <- list(parent_t = fx$parent, child_t = fx$counts)
  link <- function(...) {
    Filter(
      function(r) r$from_col == "n",
      detect_fks(tbls, "both", "medium", ...)
    )
  }
  expect_length(link(), 0)
  expect_length(link(overlap_chance_discount = FALSE), 1)
})

test_that("the chance discount reaches only children below its threshold", {
  fx <- chance_fixture()
  # 13 distinct values on the child side, so a threshold at 12 puts this
  # pair above the ceiling and the discount is never computed for it
  wide <- score_candidate(
    "child_t", "n", fx$counts, "parent_t", "pid", fx$parent, fx$flags,
    overlap_chance_max_distinct = 12L
  )
  expect_true("overlap_medium" %in% names(wide$signals))
  # Survival check at the default ceiling of 25: the same pair is still
  # discounted away, so it is the threshold and not the fixture talking
  expect_null(score_candidate(
    "child_t", "n", fx$counts, "parent_t", "pid", fx$parent, fx$flags
  ))

  tbls <- list(parent_t = fx$parent, child_t = fx$counts)
  link <- function(...) {
    Filter(
      function(r) r$from_col == "n",
      detect_fks(tbls, "both", "medium", ...)
    )
  }
  expect_length(link(), 0)
  expect_length(link(overlap_chance_max_distinct = 12L), 1)
})

test_that("the cardinality floor is honoured when a caller lowers it", {
  # Six shared codes is below the default floor of twelve, so two columns
  # holding the same half-dozen values is the expected outcome rather than
  # a finding. A caller who knows the schema's domains are small lowers
  # the floor and gets the signal back.
  codes <- c("AA", "BB", "CC", "DD", "EE", "FF")
  flags <- list(
    naming = FALSE, value_overlap = TRUE, cardinality = TRUE,
    format = FALSE, distribution = FALSE, null_pattern = FALSE
  )
  parent <- data.frame(code = codes, stringsAsFactors = FALSE)
  child <- data.frame(
    kind = rep(codes, 10),
    stringsAsFactors = FALSE
  )
  at_default <- score_candidate(
    "visit", "kind", child, "tlk_code", "code", parent, flags
  )
  expect_false("cardinality_match" %in% names(at_default$signals))
  lowered <- score_candidate(
    "visit", "kind", child, "tlk_code", "code", parent, flags,
    cardinality_min_distinct = 2L
  )
  expect_true("cardinality_match" %in% names(lowered$signals))

  # And through detect_fks: the same pair, the floor set for the scan
  tbls <- list(tlk_code = parent, visit = data.frame(
    visit_id = seq_len(60), kind = rep(codes, 10), stringsAsFactors = FALSE
  ))
  sigs <- function(...) {
    hit <- Filter(
      function(r) r$from_col == "kind",
      detect_fks(tbls, "both", "medium", ...)
    )
    if (length(hit) == 0) character(0) else names(hit[[1]]$signals)
  }
  expect_false("cardinality_match" %in% sigs())
  expect_true("cardinality_match" %in% sigs(cardinality_min_distinct = 2L))
})

test_that("a name ending in id is a possible key, unless it is a word", {
  # The strict test wants a separator, so glued names never qualified
  expect_false(is_key_name("primaryid"))
  expect_true(is_possible_key_name("primaryid"))
  expect_true(is_possible_key_name("caseid"))
  expect_true(is_possible_key_name("supportrepid"))
  # Words that end in id are not keys, plain or suffixed
  expect_false(is_possible_key_name("valid"))
  expect_false(is_possible_key_name("covid"))
  expect_false(is_possible_key_name("medicaid"))
  expect_false(is_possible_key_name("amount_paid"))
  expect_false(is_possible_key_name("is_valid"))
  expect_false(is_possible_key_name("fluid"))
  # Not a key name at all
  expect_false(is_possible_key_name("height_inches"))
})

test_that("a low-cardinality column named like a key is still a candidate", {
  # Two distinct values over many rows is normally dropped outright
  col <- rep(c(1, 2), 60)
  expect_false(is_fk_candidate(col, "homeless_label"))
  expect_true(is_fk_candidate(col, "siteid"))
  expect_true(is_fk_candidate(col, "site_id"))
})

test_that("switching the possible-key-name tier off leaves only the strict test", {
  # The tier admits a glued name the strict test cannot see, and all it
  # buys the column is a hearing: it survives the low-cardinality reject
  # and so reaches a scan at all.
  expect_true(is_possible_key_name("primaryid"))
  expect_false(is_possible_key_name("primaryid", possible_key_names = FALSE))
  col <- rep(c(1, 2), 60)
  expect_true(is_fk_candidate(col, "siteid"))
  expect_false(is_fk_candidate(col, "siteid", possible_key_names = FALSE))
  # The strict test is untouched by the switch: a separated name still
  # qualifies, so this is the tier going quiet and not the whole screen
  expect_true(is_fk_candidate(col, "site_id", possible_key_names = FALSE))

  # And through detect_fks, which is how a scan sets it: a two-site column
  # named without a separator is a link at the default and is not even
  # offered as a source with the tier off
  tbls <- list(
    tlk_site = data.frame(siteid = 1:2, label = c("north", "south")),
    visit = data.frame(visit_id = 1:60, siteid = rep(1:2, 30))
  )
  link <- function(...) {
    Filter(
      function(r) r$from_col == "siteid",
      detect_fks(tbls, "both", "medium", ...)
    )
  }
  expect_length(link(), 1)
  expect_length(link(possible_key_names = FALSE), 0)
})

test_that("a bare id is not a possible key name", {
  # Every lookup table has one, so treating it as a key made each lookup
  # a parent for all the others: 7 false links in the fixture
  expect_false(is_possible_key_name("id"))
  expect_false(is_possible_key_name("uuid"))
  expect_false(is_possible_key_name("guid"))
  expect_true(is_possible_key_name("clientid"))
})

# ── Containment ──────────────────────────────────────────────

# Every containment test needs value_overlap on, because that is the flag
# containment is gated behind: it is a value-overlap finding, and a new
# flag of its own would be invisible to the caller in app_server.R, which
# passes an explicit list.
containment_flags <- function(...) {
  utils::modifyList(
    list(
      naming = TRUE, value_overlap = TRUE, cardinality = TRUE,
      format = FALSE, distribution = FALSE, null_pattern = FALSE
    ),
    list(...)
  )
}

test_that("containment is evidence on a key parent with no name to go on", {
  # The Chinook shape: customer.supportrepid holds three of employee's
  # eight ids under a name no convention connects to that table, and is
  # spread nothing like the key. The chance discount removed the only
  # signal the pair had, so the link was lost entirely.
  staff <- data.frame(employeeid = 1:8, surname = paste0("s", 1:8))
  customers <- data.frame(
    custid = 1:59,
    supportrepid = rep(c(3, 4, 5), length.out = 59)
  )
  res <- score_candidate(
    "customers", "supportrepid", customers,
    "staff", "employeeid", staff, containment_flags()
  )
  expect_true("containment" %in% names(res$signals))
  expect_equal(res$confidence, "high")
  expect_match(
    paste(res$reasons, collapse = " | "),
    "all 3 values present in a key \\(contained\\)"
  )
  # Nothing else fired: no naming convention connects the two names, and
  # three values inside a contiguous 1..8 run is exactly the overlap the
  # chance discount exists to take away
  expect_equal(names(res$signals), "containment")
})

test_that("full containment in a column that is not a key is not evidence", {
  # incident.number_of_suspects against victim.height_inches: every count
  # is somewhere among the heights, and a column of heights identifies no
  # row, so being inside it says nothing
  flags <- containment_flags(naming = FALSE)
  counts <- data.frame(number_of_suspects = rep(1:5, 24))
  heights <- data.frame(height_inches = rep(1:60, 2))
  expect_null(score_candidate(
    "incident", "number_of_suspects", counts,
    "victim", "height_inches", heights, flags
  ))
  # Survival check: the same values inside a column of the same shape that
  # does identify a row are evidence, which is the whole signal
  key <- data.frame(victim_no = 1:60)
  res <- score_candidate(
    "incident", "number_of_suspects", counts,
    "victim", "victim_no", key, flags
  )
  expect_equal(names(res$signals), "containment")
})

test_that("a near-unique parent counts as a key, and the reason says so", {
  # A key column in a real extract arrives with a duplicate row or two.
  # near_pk_map is detect_fks' name for that tolerance, and containment
  # has to read a parent the same way the scan chose it.
  parent <- data.frame(client_num = c(1:199, 199L))
  child <- data.frame(ref = rep((1:30) * 6, 4))
  res <- score_candidate(
    "visit", "ref", child,
    "client", "client_num", parent, containment_flags(naming = FALSE)
  )
  expect_true("containment" %in% names(res$signals))
  expect_match(
    paste(res$reasons, collapse = " | "),
    "all 30 values present in a near key \\(contained\\)"
  )
  # Survival check the other way: 199 distinct values over 400 rows is not
  # a key by any tolerance, and the same child gets no containment from it
  not_key <- data.frame(client_num = rep(1:199, 2))
  res2 <- score_candidate(
    "visit", "ref", child,
    "client", "client_num", not_key, containment_flags(naming = FALSE)
  )
  expect_false("containment" %in% names(res2$signals))
})

test_that("orphan rows leave a weaker nearly contained signal", {
  # A filtered parent extract, or a child loaded after the parent
  # snapshot: one value in two hundred has no parent row. Treating that as
  # "not contained" loses a real link to one missing row.
  flags <- containment_flags(naming = FALSE)
  parent <- data.frame(pid = 1:1000)
  child <- data.frame(ref = c((1:199) * 5, 5000))
  res <- score_candidate("child_t", "ref", child, "parent_t", "pid", parent, flags)
  expect_true("containment_near" %in% names(res$signals))
  expect_false("containment" %in% names(res$signals))
  expect_match(
    paste(res$reasons, collapse = " | "),
    "199 of 200 values present in a key \\(nearly contained\\)"
  )
  # Below the tier there is no containment claim of either kind: at 95%
  # the overlap signals already describe the pair, and calling one in
  # twenty missing "contained" is a claim the data does not support
  loose <- data.frame(ref = c((1:190) * 5, (1:10) * 5000))
  res2 <- score_candidate("child_t", "ref", loose, "parent_t", "pid", parent, flags)
  expect_false(any(
    c("containment", "containment_near") %in% names(res2$signals)
  ))
})

test_that("a child with two distinct values gives no containment signal", {
  # Trivially satisfied: a two-code column sits inside almost any key, so
  # below the minimum it is not evidence of anything. format_match keeps
  # the pair scorable, so this is about the signal and not about the pair
  # being thrown out for some other reason.
  flags <- containment_flags(naming = FALSE, format = TRUE)
  parent <- data.frame(status_id = 1:40)
  two <- data.frame(flagcode = rep(c(7, 9), 30))
  res <- score_candidate(
    "visit", "flagcode", two, "tlk_status", "status_id", parent, flags
  )
  expect_equal(names(res$signals), "format_match")
  # Survival check at the default minimum of 3: one more distinct value
  # and the same shape is evidence
  three <- data.frame(flagcode = rep(c(7, 9, 11), 20))
  res2 <- score_candidate(
    "visit", "flagcode", three, "tlk_status", "status_id", parent, flags
  )
  expect_true("containment" %in% names(res2$signals))
})

test_that("the containment minimum is honoured when a caller raises it", {
  # The minimum is a per-scan parameter, not a constant: how much of a
  # coincidence a handful of shared values is depends on the schema.
  flags <- containment_flags(naming = FALSE, format = TRUE)
  parent <- data.frame(status_id = 1:40)
  six <- data.frame(flagcode = rep(c(2, 4, 6, 8, 10, 12), 10))
  res_default <- score_candidate(
    "visit", "flagcode", six, "tlk_status", "status_id", parent, flags
  )
  expect_true("containment" %in% names(res_default$signals))
  res_strict <- score_candidate(
    "visit", "flagcode", six, "tlk_status", "status_id", parent, flags,
    containment_min_distinct = 12L
  )
  expect_false("containment" %in% names(res_strict$signals))

  # And through detect_fks, which is how a caller sets it for a scan: the
  # no-name link from the first test rests on containment alone, so a
  # raised minimum drops it below medium and out of the results
  tbls <- list(
    staff = data.frame(employeeid = 1:8, surname = paste0("s", 1:8)),
    customers = data.frame(
      custid = 1:59,
      supportrepid = rep(c(3, 4, 5), length.out = 59)
    )
  )
  found <- function(rels) {
    Filter(function(r) r$from_col == "supportrepid", rels)
  }
  expect_length(found(detect_fks(tbls, "both", "medium")), 1)
  expect_length(
    found(detect_fks(tbls, "both", "medium", containment_min_distinct = 12L)),
    0
  )
})

test_that("a unique child column wholly inside a parent key is one-to-one", {
  # A shared-primary-key extension table: the child column is itself
  # unique, and requiring a non-unique child would lose the link. The ERD
  # reads that uniqueness as a one-to-one.
  tbls <- list(
    clients = data.frame(client_id = 1:40, name = paste0("c", 1:40)),
    client_profile = data.frame(client_id = 1:25, risk = (1:25) * 3)
  )
  rels <- detect_fks(tbls, "both", "medium")
  link <- Filter(function(r) r$from_table == "client_profile", rels)
  expect_length(link, 1)
  expect_equal(link[[1]]$to_table, "clients")
  expect_true("containment" %in% names(link[[1]]$signals))
  m <- erd_model(tbls, link, list(clients = "client_id"))
  expect_equal(m$rels[[1]]$child_max, "one")
})

test_that("a name starting with id is a possible key, unless it is a word", {
  expect_true(is_possible_key_name("idnum"))
  expect_true(is_possible_key_name("idcode"))
  # Words beginning with those letters are not keys. ideation is the one
  # that matters: behavioural-health extracts carry suicidal_ideation
  expect_false(is_possible_key_name("ideation"))
  expect_false(is_possible_key_name("suicidal_ideation"))
  expect_false(is_possible_key_name("identity"))
  expect_false(is_possible_key_name("identified_gender"))
  expect_false(is_possible_key_name("idle"))
})

# ── The parent-key requirement setting ───────────────────────

# A table whose only key is the pair (order_id, line_no). Neither column is
# unique, neither is near-unique, so under the default the table offers no
# parent columns at all and nothing can reference it. This is the FAERS
# drug24q1 shape in miniature: primaryid repeats, drug_seq repeats, and the
# pair is unique over the table.
composite_parent_fixture <- function(orders = 50L, lines = 4L) {
  data.frame(
    order_id = rep(seq_len(orders), each = lines),
    line_no = rep(seq_len(lines), times = orders),
    qty = rep(c(1L, 2L), orders * lines / 2L)
  )
}

test_that("a parent that is only half of a composite key is refused by default and admitted under composite", {
  # ther24q1.dsg_drug_seq -> drug24q1.drug_seq is the real link this
  # decides: the child sits wholly inside a column that identifies no row
  # on its own, and is half of the parent's real key.
  items <- composite_parent_fixture()
  expect_equal(detect_pks(items, "items", "uniqueness"), character(0))
  expect_equal(near_unique_cols(items), character(0))
  child <- data.frame(seq_ref = rep(1:4, 30))

  strict <- score_candidate(
    "ther", "seq_ref", child,
    "items", "line_no", items, containment_flags(naming = FALSE)
  )
  expect_false("containment" %in% names(strict$signals %||% list()))

  # Survival check: the same pair under the relaxed setting
  relaxed <- score_candidate(
    "ther", "seq_ref", child,
    "items", "line_no", items, containment_flags(naming = FALSE),
    parent_key_requirement = "composite"
  )
  expect_true("containment" %in% names(relaxed$signals))
  expect_match(
    paste(relaxed$reasons, collapse = " | "),
    "all 4 values present in a composite key component \\(contained\\)"
  )

  # And through detect_fks, which is how a scan sets it: the link is
  # absent at the default and present under "composite"
  tbls <- list(items = items, ther = data.frame(
    ther_id = 1:120, seq_ref = rep(1:4, 30)
  ))
  link <- function(req) {
    Filter(
      function(r) r$from_col == "seq_ref" && r$to_col == "line_no",
      detect_fks(tbls, "both", "medium", parent_key_requirement = req)
    )
  }
  expect_length(link("key"), 0)
  expect_length(link("composite"), 1)
})

test_that("a column that is both a key and half of a unique pair reads as a key", {
  # No double counting: the strict tiers answer first, so the reason text
  # names the tier that actually admitted the parent.
  n <- 60L
  both <- data.frame(
    row_id = seq_len(n),
    grp = rep(1:6, each = 10),
    pos = rep(1:10, times = 6)
  )
  # row_id is strictly unique and is also half of several unique pairs
  expect_false(is.null(composite_key_component(both, "row_id")))
  child <- data.frame(ref = c(1L, 5L, 9L, 20L))
  res <- score_candidate(
    "child_t", "ref", child, "both_t", "row_id", both,
    containment_flags(naming = FALSE),
    parent_key_requirement = "composite"
  )
  expect_match(
    paste(res$reasons, collapse = " | "),
    "all 4 values present in a key \\(contained\\)"
  )
})

test_that("the composite probe refuses a pair that is unique only because both columns are mostly missing", {
  # 200 rows, and (sparse_a, sparse_b) is unique over the 6 rows where both
  # are present. A key that identifies six rows out of two hundred is not
  # a key, so the pair has to clear a completeness bar before its
  # uniqueness is read at all.
  n <- 200L
  mostly_na <- data.frame(
    sparse_a = c(1:6, rep(NA_integer_, n - 6L)),
    sparse_b = c(101:106, rep(NA_integer_, n - 6L)),
    filler = rep(1:4, length.out = n)
  )
  expect_null(composite_key_component(mostly_na, "sparse_a"))

  # Survival check: the same pair fully populated is found, so the refusal
  # is about the missingness and not about the pair
  full <- data.frame(
    sparse_a = rep(1:50, each = 4),
    sparse_b = rep(1:4, times = 50),
    filler = rep(1:4, length.out = n)
  )
  expect_equal(composite_key_component(full, "sparse_a")$partner, "sparse_b")
})

test_that("the distinct-product prefilter keeps only the pairs that could be unique", {
  # d_a * d_b >= n is necessary for a pair to be unique over n rows, so a
  # partner that cannot supply enough slots is dropped without reading a
  # row. 1,000 rows: 40 x 4 = 160 slots cannot cover them, 40 x 30 = 1,200
  # can.
  d <- c(a = 40L, narrow = 4L, wide = 30L)
  expect_equal(composite_pair_candidates("a", d, 1000L), "wide")
  # Survival check the other way: over 120 rows the narrow partner has
  # room too, and the roomier one is still offered first
  expect_equal(composite_pair_candidates("a", d, 120L), c("wide", "narrow"))
})

test_that("sampling before confirmation reaches the whole-table verdict when the duplicate is late", {
  # The sample is an ordering of the work, not an approximation: a pair
  # that passes on the rows sampled is still confirmed over the whole
  # table. Here the only duplicate pair sits in the last fifty rows, so a
  # prefix sample would have passed it.
  late_dup <- data.frame(
    a = c(rep(1:50, each = 5), rep(1:10, each = 5)),
    b = c(rep(1:5, times = 50), rep(1:5, times = 10))
  )
  expect_equal(nrow(late_dup), 300L)
  # The last fifty rows repeat the first fifty, so fifty rows share a key
  # where the tolerance allows three
  expect_equal(300L - length(unique(paste(late_dup$a, late_dup$b))), 50L)
  # A prefix sample sees none of it
  first <- utils::head(late_dup, 100L)
  expect_equal(anyDuplicated(paste(first$a, first$b)), 0L)
  expect_null(composite_key_component(late_dup, "a", sample_rows = 100L))

  # Survival check: the same shape with the late rows made distinct is
  # found, so the refusal came from the confirmation and not from the
  # fixture being unreadable
  clean <- late_dup
  clean$a[251:300] <- rep(51:60, each = 5)
  expect_equal(
    composite_key_component(clean, "a", sample_rows = 100L)$partner,
    "b"
  )
})

test_that("a table keyed on three columns reads as keyless under composite", {
  # Width stays at two. A full 4 x 5 x 6 grid is keyed on all three of its
  # columns and no pair of them is unique, so the relaxed setting finds
  # nothing in it and behaves as the default does rather than widening the
  # probe to triples. Here the prefilter sees that for free: no pair has
  # enough slots to cover 120 rows.
  three <- expand.grid(x = 1:4, y = 1:5, z = 1:6)
  expect_equal(nrow(three), 120L)
  expect_null(composite_key_component(three, "x"))
  expect_null(composite_key_component(three, "y"))
  expect_null(composite_key_component(three, "z"))
})

# ── The public harness (dev/fixtures/public/score_public.R) ───

# score_public.R loads the package and runs its datasets when executed.
# Sourcing it into an environment that already defines
# .score_public_no_setup skips both, which is what makes its two
# measurement functions testable here.
score_public_env <- function() {
  env <- new.env(parent = asNamespace("tableexplorer"))
  assign(".score_public_no_setup", TRUE, envir = env)
  sys.source(
    testthat::test_path("..", "..", "dev", "fixtures", "public", "score_public.R"),
    envir = env
  )
  env
}

test_that("the harness reports found, hit, recall and precision at each confidence level present", {
  env <- score_public_env()
  # visits.code fits two parents equally, so resolve_fk_parents demotes
  # both candidates to low after detect_fks has already returned them at
  # medium+. That is the defect these lines exist for: without them the
  # printed precision mixes a reviewer-facing high row with rows the
  # resolver has since thrown away.
  tbls <- list(
    clients = data.frame(client_id = 1:40, label = paste0("c", 1:40)),
    staff = data.frame(staff_id = 1:40, label = paste0("s", 1:40)),
    visits = data.frame(
      visit_id = 1:60,
      client_id = rep(1:20, 3),
      code = rep(1:20, 3)
    )
  )
  truth <- "visits.client_id -> clients.client_id"
  out <- capture.output(
    res <- env$score_one("demo", tbls, truth)
  )

  # The one real link is found, and found at high
  expect_equal(res$hit, truth)
  expect_equal(res$by_conf$high$hit, 1L)
  # More than one level is present, so the overall line really is a mix
  expect_gt(length(res$by_conf), 1)
  # Every level present has a line, and no level that is absent does
  for (lv in c("high", "medium", "low")) {
    pattern <- sprintf("^ +%s +found", lv)
    expect_equal(
      length(grep(pattern, out)),
      if (is.null(res$by_conf[[lv]])) 0L else 1L
    )
  }
  # The per-level counts account for the overall ones exactly
  expect_equal(
    sum(vapply(res$by_conf, function(x) x$found, numeric(1))),
    length(res$found)
  )
  expect_equal(
    sum(vapply(res$by_conf, function(x) x$hit, numeric(1))),
    length(res$hit)
  )

  # The overall line still renders through the format it always used, so
  # figures measured before the per-level lines existed stay comparable.
  # This test holds its own copy of that format: if score_one's changes,
  # the two diverge and this fails.
  overall <- grep("^demo ", out, value = TRUE)
  expect_length(overall, 1)
  expect_equal(
    sub("[0-9.]+s$", "", overall),
    sub("[0-9.]+s$", "", sprintf(
      "%-8s tables %3d  truth %3d  found %3d  hit %3d  recall %5.1f%%  precision %5.1f%%  %4.1fs",
      "demo", length(tbls), length(truth), length(res$found), length(res$hit),
      100 * res$recall, 100 * res$precision, res$secs
    ))
  )
})

test_that("the harness refuses ground truth that names a table or column the data does not have", {
  env <- score_public_env()
  tbls <- list(
    parks = data.frame(park.key = paste0("P", 1:20), city = paste0("c", 1:20)),
    homegames = data.frame(hg_id = 1:40, park.key = rep(paste0("P", 1:20), 2))
  )
  # The real typo this exists for: the Lahman file said parkkey where the
  # column is park.key, and the pair was reported as a missed link for a
  # day instead of as a broken truth file.
  expect_equal(
    env$validate_truth(tbls, "homegames.park.key -> parks.park.key"),
    character(0)
  )
  bad <- env$validate_truth(tbls, c(
    "homegames.parkkey -> parks.park.key",
    "homegames.park.key -> parkz.park.key"
  ))
  expect_length(bad, 2)
  expect_match(bad[[1]], "no column parkkey in homegames", fixed = TRUE)
  expect_match(bad[[2]], "no table parkz", fixed = TRUE)
})

test_that("a composite key carrying a few duplicate rows is admitted, and the reason says near", {
  # Measured on FAERS 2024Q1: drug24q1 has 1,909,327 rows,
  # (primaryid, drug_seq) takes 1,909,235 distinct values, and an
  # exhaustive width-2 search found no strictly unique pair in the table at
  # all. Requiring exact uniqueness would refuse the one composite key
  # FAERS has, so the pair gets the same tolerance parent_key_min_frac
  # already gives a dirty single-column key.
  n <- 1000L
  dirty <- data.frame(
    grp = rep(1:200, each = 5),
    pos = rep(1:5, times = 200)
  )
  dirty$pos[996:1000] <- 1L
  expect_equal(n - length(unique(paste(dirty$grp, dirty$pos))), 4L)
  probe <- composite_key_component(dirty, "pos")
  expect_equal(probe$partner, "grp")
  expect_false(probe$exact)

  child <- data.frame(ref = 1:5)
  res <- score_candidate(
    "child_t", "ref", child, "dirty_t", "pos", dirty,
    containment_flags(naming = FALSE),
    parent_key_requirement = "composite"
  )
  expect_equal(names(res$signals), "containment")
  expect_match(
    paste(res$reasons, collapse = " | "),
    "all 5 values present in a near composite key component \\(contained\\)"
  )

  # Survival check the other way: a pair where a sixth of the rows share a
  # key is not a key by any tolerance, and is refused
  heavy <- dirty
  heavy$pos[1:200] <- 1L
  expect_gt(n - length(unique(paste(heavy$grp, heavy$pos))), n * 0.01)
  expect_null(composite_key_component(heavy, "pos"))
})

# ── The settings sweep (dev/fixtures/public/sweep_settings.R) ──

# sweep_settings.R runs its grid when executed. Sourcing it into an
# environment that already defines .sweep_no_setup gives its functions
# without running anything. Its own source() calls are relative to the
# package root, which is why the working directory moves first.
sweep_env <- function() {
  withr::local_dir(testthat::test_path("..", ".."), .local_envir = parent.frame())
  env <- new.env(parent = asNamespace("tableexplorer"))
  assign(".sweep_no_setup", TRUE, envir = env)
  sys.source("dev/fixtures/public/sweep_settings.R", envir = env)
  env
}

test_that("the sweep writes nothing when a dataset is unavailable", {
  # A sweep that skips a dataset and writes anyway under-reports, and the
  # file reads as a whole run. So every dataset is loaded before any
  # scoring, and a name that does not resolve stops the run.
  env <- sweep_env()
  out <- withr::local_tempdir()
  # capture.output so the sweep's own progress line does not land in the
  # middle of the suite's output
  expect_error(
    capture.output(env$sweep("nosuchdataset", out_dir = out)),
    "unknown dataset: nosuchdataset"
  )
  expect_equal(list.files(out), character(0))
})

test_that("a combination whose chance threshold is inert is recorded once", {
  # With the discount off the threshold decides nothing, so the two rows
  # that differ only in it are the same run. Without the collapse the
  # results file would carry a duplicate and the frontier would count it
  # twice.
  env <- sweep_env()
  off <- utils::modifyList(
    env$settings_default(),
    list(overlap_chance_discount = FALSE)
  )
  off_wide <- utils::modifyList(off, list(overlap_chance_max_distinct = 100L))
  expect_equal(env$settings_key(off), env$settings_key(off_wide))
  expect_true(is.na(env$canonical_settings(off)$overlap_chance_max_distinct))
  # And the threshold still separates two combinations while the discount
  # is on, so the collapse is specific to the inert case
  on_wide <- utils::modifyList(
    env$settings_default(),
    list(overlap_chance_max_distinct = 100L)
  )
  expect_false(
    env$settings_key(env$settings_default()) == env$settings_key(on_wide)
  )
  expect_length(
    env$dedup_combos(list(
      list(settings = off, set = "a"),
      list(settings = off_wide, set = "b"),
      list(settings = on_wide, set = "c")
    )),
    2L
  )
})
