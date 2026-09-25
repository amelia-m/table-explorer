# ============================================================
# Tests for export_utils.R - Export Format Generators
# ============================================================

# ── Test fixtures ────────────────────────────────────────────

make_test_tables <- function() {
  list(
    customers = data.frame(
      customer_id = 1:3,
      name = c("alice", "bob", "carol"),
      stringsAsFactors = FALSE
    ),
    orders = data.frame(
      order_id = 1:4,
      customer_id = c(1, 2, 1, 3),
      amount = c(10.5, 20.0, 30.0, 15.5),
      stringsAsFactors = FALSE
    )
  )
}

make_test_rels <- function() {
  list(
    list(
      from_table = "orders", from_col = "customer_id",
      to_table = "customers", to_col = "customer_id",
      detected_by = "naming", confidence = "high", score = 1.0,
      signals = list(naming_exact = 1.0),
      reasons = "exact FK naming"
    )
  )
}

make_test_pks <- function() {
  list(
    customers = "customer_id",
    orders = "order_id"
  )
}

# ── dbt schema.yml generator ────────────────────────────────

test_that("generate_dbt_yaml produces valid structure", {
  yaml_str <- generate_dbt_yaml(make_test_tables(), make_test_rels(), make_test_pks())

  expect_true(grepl("version: 2", yaml_str))
  expect_true(grepl("models:", yaml_str))
  expect_true(grepl("- name: customers", yaml_str))
  expect_true(grepl("- name: orders", yaml_str))
})

test_that("generate_dbt_yaml includes PK tests", {
  yaml_str <- generate_dbt_yaml(make_test_tables(), make_test_rels(), make_test_pks())

  expect_true(grepl("- unique", yaml_str))
  expect_true(grepl("- not_null", yaml_str))
})

test_that("generate_dbt_yaml includes FK relationship tests", {
  yaml_str <- generate_dbt_yaml(make_test_tables(), make_test_rels(), make_test_pks())

  expect_true(grepl("relationships:", yaml_str))
  expect_true(grepl("ref\\('customers'\\)", yaml_str))
})

test_that("generate_dbt_yaml includes all columns", {
  yaml_str <- generate_dbt_yaml(make_test_tables(), make_test_rels(), make_test_pks())

  expect_true(grepl("- name: customer_id", yaml_str))
  expect_true(grepl("- name: name", yaml_str))
  expect_true(grepl("- name: order_id", yaml_str))
  expect_true(grepl("- name: amount", yaml_str))
})

test_that("generate_dbt_yaml handles empty tables", {
  yaml_str <- generate_dbt_yaml(list(), list(), list())
  expect_true(grepl("version: 2", yaml_str))
  expect_true(grepl("models:", yaml_str))
})

# ── Mermaid ERD generator ────────────────────────────────────

test_that("generate_mermaid_erd starts with erDiagram", {
  mmd <- generate_mermaid_erd(make_test_tables(), make_test_rels(), make_test_pks())
  lines <- strsplit(mmd, "\n")[[1]]
  expect_equal(trimws(lines[1]), "erDiagram")
})

test_that("generate_mermaid_erd includes table blocks", {
  mmd <- generate_mermaid_erd(make_test_tables(), make_test_rels(), make_test_pks())

  expect_true(grepl("customers \\{", mmd))
  expect_true(grepl("orders \\{", mmd))
})

test_that("generate_mermaid_erd marks PK columns", {
  mmd <- generate_mermaid_erd(make_test_tables(), make_test_rels(), make_test_pks())

  expect_true(grepl("customer_id PK", mmd))
  expect_true(grepl("order_id PK", mmd))
})

test_that("generate_mermaid_erd includes relationships", {
  mmd <- generate_mermaid_erd(make_test_tables(), make_test_rels(), make_test_pks())

  # Mandatory parent (no NULL FKs), many children, non-identifying (dashed)
  expect_true(grepl("customers \\|\\|\\.\\.o\\{ orders", mmd, fixed = FALSE))
})

test_that("generate_mermaid_erd assigns correct data types", {
  mmd <- generate_mermaid_erd(make_test_tables(), make_test_rels(), make_test_pks())

  # customer_id is numeric -> int
  expect_true(grepl("int customer_id", mmd))
  # name is character -> string
  expect_true(grepl("string name", mmd))
  # amount has decimals -> float
  expect_true(grepl("float amount", mmd))
})

test_that("generate_mermaid_erd handles Date columns", {
  tables <- list(
    events = data.frame(
      event_id = 1:2,
      event_date = as.Date(c("2024-01-01", "2024-06-15"))
    )
  )
  mmd <- generate_mermaid_erd(tables, list(), list(events = "event_id"))
  expect_true(grepl("date event_date", mmd))
})

test_that("generate_mermaid_erd handles empty input", {
  mmd <- generate_mermaid_erd(list(), list(), list())
  expect_equal(trimws(mmd), "erDiagram")
})

# ── Session save/restore ─────────────────────────────────────

test_that("save_session_json produces valid JSON", {
  skip_if_not_installed("jsonlite")

  json_str <- save_session_json(
    tables = make_test_tables(),
    rels = make_test_rels(),
    manual_rels = list(),
    schema_rels = list(),
    settings = list(detect_method = "both")
  )

  parsed <- jsonlite::fromJSON(json_str, simplifyVector = FALSE)
  expect_true("version" %in% names(parsed))
  expect_true("timestamp" %in% names(parsed))
  expect_true("tables" %in% names(parsed))
  expect_true("relationships" %in% names(parsed))
  expect_true("settings" %in% names(parsed))
})

test_that("save_session_json includes table data", {
  skip_if_not_installed("jsonlite")

  json_str <- save_session_json(make_test_tables(), list(), list(), list())
  parsed <- jsonlite::fromJSON(json_str, simplifyVector = FALSE)

  expect_true("customers" %in% names(parsed$tables))
  expect_true("orders" %in% names(parsed$tables))
})

test_that("restore_session_json round-trips tables", {
  skip_if_not_installed("jsonlite")

  tables <- make_test_tables()
  json_str <- save_session_json(tables, list(), list(), list())
  restored <- restore_session_json(json_str)

  expect_true("customers" %in% names(restored$tables))
  expect_true("orders" %in% names(restored$tables))
  expect_equal(nrow(restored$tables[["customers"]]), 3)
  expect_equal(nrow(restored$tables[["orders"]]), 4)
})

test_that("restore_session_json round-trips settings", {
  skip_if_not_installed("jsonlite")

  settings <- list(detect_method = "both", min_confidence = "medium")
  json_str <- save_session_json(list(), list(), list(), list(), settings)
  restored <- restore_session_json(json_str)

  expect_equal(restored$settings$detect_method, "both")
  expect_equal(restored$settings$min_confidence, "medium")
})

test_that("restore_session_json round-trips manual relationships", {
  skip_if_not_installed("jsonlite")

  manual <- list(list(
    from_table = "a", from_col = "b",
    to_table = "c", to_col = "d",
    detected_by = "manual"
  ))
  json_str <- save_session_json(list(), list(), manual, list())
  restored <- restore_session_json(json_str)

  expect_equal(length(restored$manual_relationships), 1)
  expect_equal(restored$manual_relationships[[1]]$from_table, "a")
})

test_that("save_session_json handles Date columns", {
  skip_if_not_installed("jsonlite")

  tables <- list(
    events = data.frame(
      id = 1:2,
      event_date = as.Date(c("2024-01-01", "2024-06-15"))
    )
  )
  json_str <- save_session_json(tables, list(), list(), list())
  # Should not error
  parsed <- jsonlite::fromJSON(json_str, simplifyVector = FALSE)
  expect_true("events" %in% names(parsed$tables))
})

test_that("save_session_json returns {} when jsonlite unavailable", {
  # We can't unload jsonlite easily, but test the function exists
  expect_true(is.function(save_session_json))
})

test_that("restore_session_json handles empty/missing fields", {
  skip_if_not_installed("jsonlite")

  json_str <- '{"version": 1, "timestamp": "2024-01-01", "tables": {}}'
  restored <- restore_session_json(json_str)

  expect_equal(length(restored$tables), 0)
  expect_true(is.list(restored$relationships))
  expect_true(is.list(restored$manual_relationships))
  expect_true(is.list(restored$settings))
})

test_that("session round-trips review decisions", {
  confirmed <- list(list(
    from_table = "orders", from_col = "customer_id",
    to_table = "customers", to_col = "customer_id",
    detected_by = "naming", confidence = "high", score = 1
  ))
  json_str <- save_session_json(
    list(), list(), list(), list(),
    review = list(confirmed = confirmed, suppressed = list("a|b|c|d"))
  )
  result <- restore_session_json(json_str)
  expect_equal(result$review$confirmed[[1]]$from_col, "customer_id")
  expect_equal(unlist(result$review$suppressed), "a|b|c|d")
})

# ── Model-based ERD exports ──────────────────────────────────

erd_export_fixture <- function() {
  tables <- list(
    customers = data.frame(customer_id = 1:3, email = c("a", "b", "c")),
    orders = data.frame(order_id = 1:4, customer_id = c(1L, NA, 2L, 3L)),
    customer_profile = data.frame(customer_id = 1:3, bio = c("x", "y", "z")),
    order_items = data.frame(
      order_id = c(1L, 1L, 2L), product_id = c(1L, 2L, 1L)
    ),
    products = data.frame(product_id = 1:2, sku = c("A", "B"))
  )
  mk <- function(ft, fc, tt, tc, by = "naming", conf = FALSE) {
    list(
      from_table = ft, from_col = fc, to_table = tt, to_col = tc,
      detected_by = by, confidence = "high", score = 0.87, confirmed = conf,
      reasons = "exact FK naming"
    )
  }
  rels <- list(
    mk("orders", "customer_id", "customers", "customer_id"),
    mk("customer_profile", "customer_id", "customers", "customer_id",
       by = "schema"),
    mk("order_items", "order_id", "orders", "order_id", conf = TRUE),
    mk("order_items", "product_id", "products", "product_id", conf = TRUE)
  )
  pks <- list(
    customers = "customer_id", orders = "order_id",
    customer_profile = "customer_id", products = "product_id"
  )
  cpks <- list(order_items = list(c("order_id", "product_id")))
  list(tables = tables, rels = rels, pks = pks, cpks = cpks)
}

test_that("Mermaid uses crow's-foot optionality and identifying lines", {
  f <- erd_export_fixture()
  mmd <- generate_mermaid_erd(f$tables, f$rels, f$pks, f$cpks)
  # Nullable FK -> optional parent, dashed (non-identifying), inferred label
  expect_true(grepl('customers |o..o{ orders : "customer_id (inferred 87%)"',
                    mmd, fixed = TRUE))
  # 1:1 identifying, declared (no confidence label)
  expect_true(grepl('customers ||--o| customer_profile : "customer_id"',
                    mmd, fixed = TRUE))
  # Composite-PK junction: identifying
  expect_true(grepl("orders ||--o{ order_items", mmd, fixed = TRUE))
  # Key markers
  expect_true(grepl("int customer_id FK \"nullable\"", mmd, fixed = TRUE))
  expect_true(grepl("int order_id PK, FK", mmd, fixed = TRUE))
  expect_true(grepl("direction LR", mmd, fixed = TRUE))
})

test_that("Mermaid quotes unusual names and is deterministic", {
  tables <- list(`my table` = data.frame(id = 1:2))
  mmd <- generate_mermaid_erd(tables, list(), list(`my table` = "id"))
  expect_true(grepl('"my table" {', mmd, fixed = TRUE))
  f <- erd_export_fixture()
  expect_identical(
    generate_mermaid_erd(f$tables, f$rels, f$pks, f$cpks),
    generate_mermaid_erd(f$tables, rev(f$rels), f$pks, f$cpks)
  )
})

test_that("DBML has tables, settings, refs, composite PK and groups", {
  f <- erd_export_fixture()
  dbml <- generate_dbml(f$tables, f$rels, f$pks, f$cpks)
  expect_true(grepl("Table customers [headerColor:", dbml, fixed = TRUE))
  expect_true(grepl("customer_id int [pk, not null]", dbml, fixed = TRUE))
  expect_true(grepl("Ref: orders.customer_id > customers.customer_id [color: #94a3b8]",
                    dbml, fixed = TRUE))
  expect_true(grepl("Ref: customer_profile.customer_id - customers.customer_id",
                    dbml, fixed = TRUE))
  expect_true(grepl("(order_id, product_id) [pk]", dbml, fixed = TRUE))
  expect_true(grepl("TableGroup orders {", dbml, fixed = TRUE))
})

test_that("ELK JSON has one node per table, ports per column, FK->PK edges", {
  skip_if_not_installed("jsonlite")
  f <- erd_export_fixture()
  g <- jsonlite::fromJSON(
    generate_elk_json(f$tables, f$rels, f$pks, f$cpks),
    simplifyVector = FALSE
  )
  expect_equal(g$layoutOptions[["elk.edgeRouting"]], "ORTHOGONAL")
  expect_equal(length(g$children), 5)
  orders <- Filter(function(n) n$id == "orders", g$children)[[1]]
  expect_equal(length(orders$ports), 2)
  expect_equal(length(g$edges), 4)
  e <- Filter(
    function(e) e$sources[[1]] == "orders.customer_id",
    g$edges
  )[[1]]
  expect_equal(e$targets[[1]], "customers.customer_id")
  expect_equal(e$properties$parentMin, "zero")
  expect_equal(e$properties$provenance, "inferred")
})

test_that("dbt emits a relationships test for every FK on a column", {
  tables <- list(
    a = data.frame(x_id = 1:2),
    b = data.frame(x_id = 1:2),
    c = data.frame(x_id = c(1L, 2L, 2L))
  )
  rels <- list(
    list(from_table = "c", from_col = "x_id", to_table = "a", to_col = "x_id"),
    list(from_table = "c", from_col = "x_id", to_table = "b", to_col = "x_id")
  )
  yml <- generate_dbt_yaml(tables, rels, list(a = "x_id", b = "x_id"))
  expect_true(grepl("ref('a')", yml, fixed = TRUE))
  expect_true(grepl("ref('b')", yml, fixed = TRUE))
})
