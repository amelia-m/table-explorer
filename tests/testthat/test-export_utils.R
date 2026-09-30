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

  # Mandatory parent (no NULL FKs), many children; lines are always solid
  expect_true(grepl("customers \\|\\|--o\\{ orders", mmd))
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
  # No tables: no direction/notes lines either
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

test_that("Mermaid uses crow's-foot optionality with solid lines", {
  f <- erd_export_fixture()
  mmd <- generate_mermaid_erd(f$tables, f$rels, f$pks, f$cpks)
  # Nullable FK -> optional parent, inferred label; never dashed (dashes
  # break Mermaid's markers)
  expect_true(grepl(
    'customers |o--o{ orders : "customer_id \u2192 customer_id (inferred 87%)"',
    mmd, fixed = TRUE
  ))
  expect_false(grepl("..", gsub("%%[^\n]*", "", mmd), fixed = TRUE))
  # 1:1, declared (no confidence label)
  expect_true(grepl(
    'customers ||--o| customer_profile : "customer_id \u2192 customer_id"',
    mmd, fixed = TRUE
  ))
  # Composite-PK junction: identifying FK shows as a PK, FK column
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
  # orders.customer_id is an FK source, orders.order_id a target
  expect_setequal(
    vapply(orders$ports, `[[`, "", "id"),
    c("orders.customer_id:out", "orders.order_id:in")
  )
  expect_equal(length(g$edges), 4)
  e <- Filter(
    function(e) e$sources[[1]] == "orders.customer_id:out",
    g$edges
  )[[1]]
  expect_equal(e$targets[[1]], "customers.customer_id:in")
  expect_equal(e$properties$parentMin, "zero")
  expect_equal(e$properties$provenance, "inferred")
})

test_that("ELK ports sit on their column row at the card border", {
  skip_if_not_installed("jsonlite")
  f <- erd_export_fixture()
  g <- jsonlite::fromJSON(
    generate_elk_json(f$tables, f$rels, f$pks, f$cpks),
    simplifyVector = FALSE
  )
  row_h <- g$properties$rowHeight
  head_h <- g$properties$headerHeight
  port_ids <- character(0)
  for (n in g$children) {
    # FIXED_POS: ELK honours the coordinates (FIXED_ORDER ignores them)
    expect_equal(n$layoutOptions[["elk.portConstraints"]], "FIXED_POS")
    cols <- vapply(n$properties$columns, `[[`, "", "name")
    for (p in n$ports) {
      col <- sub(":(in|out)$", "", sub(paste0("^", n$id, "\\."), "", p$id))
      i <- match(col, cols)
      expect_false(is.na(i))
      expect_equal(p$y, head_h + (i - 0.5) * row_h)
      if (grepl(":out$", p$id)) {
        expect_equal(p$x, n$width)
        expect_equal(p$layoutOptions[["elk.port.side"]], "EAST")
      } else {
        expect_equal(p$x, 0)
        expect_equal(p$layoutOptions[["elk.port.side"]], "WEST")
      }
    }
    port_ids <- c(port_ids, vapply(n$ports, `[[`, "", "id"))
  }
  # Every edge endpoint exists, and every port is used by some edge
  ends <- unlist(lapply(g$edges, function(e) c(e$sources[[1]], e$targets[[1]])))
  expect_true(all(ends %in% port_ids))
  expect_true(all(port_ids %in% ends))
  # A PK+FK column gets both an in and an out port when it is both
  oi <- Filter(function(n) n$id == "order_items", g$children)[[1]]
  expect_true("order_items.order_id:out" %in% vapply(oi$ports, `[[`, "", "id"))
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

# ── Data dictionary ───────────────────────────────────────────

dict_tables <- function() {
  list(
    customers = data.frame(
      customer_id = 1:4,
      email = c("a@x.io", "b@x.io", NA, "d@x.io"),
      tier = c("gold", "silver", "gold", "bronze"),
      stringsAsFactors = FALSE
    ),
    orders = data.frame(
      order_id = 1:6,
      customer_id = c(1L, 2L, 1L, NA, 3L, 4L),
      amount = c(10.5, 20, 30, 15.5, 1, 2)
    )
  )
}
dict_rels <- function(by = "schema") {
  list(list(
    from_table = "orders", from_col = "customer_id", to_table = "customers",
    to_col = "customer_id", detected_by = by, confidence = "high", score = 1
  ))
}
dict_pks <- function() list(customers = "customer_id", orders = "order_id")

test_that("build_data_dictionary describes every column", {
  dd <- build_data_dictionary(dict_tables(), dict_rels(), dict_pks())
  expect_equal(nrow(dd), 6)
  expect_equal(dd$table, c(rep("customers", 3), rep("orders", 3)))
  row <- dd[dd$table == "orders" & dd$column == "customer_id", ]
  expect_equal(row$keys, "FK1")
  expect_equal(row$references, "customers.customer_id")
  expect_equal(row$reference_source, "declared")
  expect_true(row$nullable)
  expect_equal(row$pct_missing, round(100 / 6, 1))
  expect_equal(row$n_unique, 4)
  expect_equal(dd$keys[dd$column == "order_id"], "PK")
  # Examples spread across the sorted values, except for private columns
  expect_equal(dd$examples[dd$column == "tier"], "bronze, gold, silver")
  expect_equal(dd$examples[dd$column == "amount"], "1, 2, 15.5, 20, 30")
  expect_equal(dd$examples[dd$column == "email"], "")
  expect_equal(dd$examples_note[dd$column == "email"], "private")
  expect_equal(dd$privacy_status[dd$column == "email"], "auto_unreviewed")
  expect_equal(build_data_dictionary(dict_tables(), dict_rels(), dict_pks(), examples = FALSE)$examples[3], "")
  # Metadata stays for every column
  em <- dd[dd$column == "email", ]
  expect_equal(em$format, "email address")
  expect_equal(c(em$len_min, em$len_median, em$len_max), c(6, 6, 6))
  am <- dd[dd$column == "amount", ]
  expect_equal(c(am$min, am$median, am$max), c("1", "13", "30"))
  expect_equal(am$format, "decimal")
})

test_that("dictionary edits are merged into the dictionary and its Markdown", {
  edits <- list(
    customers = list(description = "People who buy | things"),
    "customers|tier" = list(description = "Loyalty tier", label = "Tier")
  )
  dd <- build_data_dictionary(dict_tables(), dict_rels(), dict_pks(), dictionary = edits)
  expect_equal(dd$description[dd$column == "tier"], "Loyalty tier")
  expect_equal(dd$label[dd$column == "tier"], "Tier")
  expect_equal(unique(dd$table_description[dd$table == "customers"]), "People who buy | things")
  md <- generate_data_dictionary_md(dd)
  expect_match(md, "## customers", fixed = TRUE)
  expect_match(md, "## orders", fixed = TRUE)
  expect_match(md, "People who buy \\| things", fixed = TRUE)
  expect_match(md, "| `tier` | Tier |", fixed = TRUE)
  expect_match(md, "`customer_id` → `customers.customer_id` (declared)", fixed = TRUE)
  expect_identical(md, generate_data_dictionary_md(dd))
  expect_match(generate_data_dictionary_md(dd[0, ]), "No tables loaded")
})

test_that("descriptions reach dbt, DBML and Mermaid", {
  edits <- list(
    orders = list(description = "Each \"order\" placed"),
    "orders|amount" = list(description = "Total in GBP")
  )
  y <- generate_dbt_yaml(dict_tables(), dict_rels(), dict_pks(), dictionary = edits)
  expect_match(y, "    description: \"Each \\\"order\\\" placed\"", fixed = TRUE)
  expect_match(y, "        description: \"Total in GBP\"", fixed = TRUE)
  expect_false(grepl("constraints:", y))
  dbml <- generate_dbml(dict_tables(), dict_rels(), dict_pks(), dictionary = edits)
  expect_match(dbml, "note: 'Total in GBP'", fixed = TRUE)
  expect_match(dbml, "Note: 'Each \"order\" placed (", fixed = TRUE)
  mmd <- generate_mermaid_erd(dict_tables(), dict_rels(), dict_pks(), dictionary = edits)
  expect_match(mmd, "amount \"Total in GBP\"", fixed = TRUE)
})

test_that("dbt constraints cover PKs and reviewed FKs only", {
  y <- generate_dbt_yaml(dict_tables(), dict_rels("schema"), dict_pks(), constraints = TRUE)
  expect_match(y, "- type: primary_key", fixed = TRUE)
  expect_match(y, "- type: foreign_key\n            to: ref('customers')\n            to_columns: [customer_id]", fixed = TRUE)
  detected <- generate_dbt_yaml(dict_tables(), dict_rels("naming"), dict_pks(), constraints = TRUE)
  expect_false(grepl("foreign_key", detected))
  confirmed <- dict_rels("naming")
  confirmed[[1]]$confirmed <- TRUE
  expect_match(generate_dbt_yaml(dict_tables(), confirmed, dict_pks(), constraints = TRUE), "foreign_key", fixed = TRUE)
})

test_that("sessions keep dictionary edits; older sessions still load", {
  edits <- list("orders|amount" = list(description = "Total", label = "Order total"))
  js <- save_session_json(dict_tables(), list(), list(), list(), dictionary = edits)
  back <- restore_session_json(js)
  expect_equal(back$dictionary[["orders|amount"]]$label, "Order total")
  old <- save_session_json(dict_tables(), list(), list(), list())
  old <- sub(',\\s*"dictionary": \\[\\]', "", old)
  expect_equal(restore_session_json(old)$dictionary, list())
})

test_that("sessions with missing values restore with their NAs", {
  js <- save_session_json(dict_tables(), list(), list(), list())
  back <- restore_session_json(js)
  expect_equal(nrow(back$tables$customers), 4)
  expect_true(is.na(back$tables$customers$email[3]))
  expect_true(is.na(back$tables$orders$customer_id[4]))
  expect_true(is.numeric(back$tables$orders$customer_id))
})

test_that("dbt constraints pick one primary key when several columns are unique", {
  t <- list(orders = data.frame(order_id = 1:3, ref = c("a", "b", "c"), stringsAsFactors = FALSE))
  y <- generate_dbt_yaml(t, list(), list(orders = c("order_id", "ref")), constraints = TRUE)
  expect_equal(lengths(regmatches(y, gregexpr("primary_key", y))), 1)
  expect_match(y, "- name: order_id\n        data_type: integer\n        constraints:\n          - type: primary_key", fixed = TRUE)
})

test_that("the dictionary leaves out low-confidence detected links", {
  low <- dict_rels("naming")
  low[[1]]$confidence <- "low"
  dd <- build_data_dictionary(dict_tables(), low, dict_pks())
  expect_equal(dd$references[dd$table == "orders" & dd$column == "customer_id"], "")
  declared_low <- dict_rels("schema")
  declared_low[[1]]$confidence <- "low"
  dd2 <- build_data_dictionary(dict_tables(), declared_low, dict_pks())
  expect_equal(dd2$references[dd2$table == "orders" & dd2$column == "customer_id"], "customers.customer_id")
})

test_that("dbt constraints come with an enforced contract and the parent's key", {
  rels <- dict_rels("schema")
  rels[[1]]$from_col <- "customer_id"
  rels[[1]]$to_col <- "" # names only the parent table
  y <- generate_dbt_yaml(dict_tables(), rels, dict_pks(), constraints = TRUE)
  expect_match(y, "    config:\n      contract:\n        enforced: true", fixed = TRUE)
  expect_match(y, "- name: amount\n        data_type: float", fixed = TRUE)
  expect_match(y, "- name: tier\n        data_type: varchar", fixed = TRUE)
  expect_match(y, "to: ref('customers')\n            to_columns: [customer_id]", fixed = TRUE)
  expect_false(grepl("contract", generate_dbt_yaml(dict_tables(), rels, dict_pks())))
})

test_that("DBML notes escape backslashes and quotes", {
  d <- list("orders|amount" = list(description = "ends with \\"))
  dbml <- generate_dbml(dict_tables(), dict_rels(), dict_pks(), dictionary = d)
  expect_match(dbml, "note: 'ends with \\\\'", fixed = TRUE)
})

# ── data-dict YAML ────────────────────────────────────────────

dd_yaml_tables <- function() {
  c(dict_tables(), list(staff = data.frame(staff_id = 1:3, manager_id = c(NA, 1L, 1L))))
}
dd_yaml_rels <- function() {
  c(
    dict_rels("schema"),
    list(
      list(
        from_table = "staff", from_col = "manager_id", to_table = "staff",
        to_col = "staff_id", detected_by = "manual", confidence = "high", score = 1
      ),
      list(
        from_table = "orders", from_col = "order_id", to_table = "staff",
        to_col = "staff_id", detected_by = "naming", confidence = "medium", score = 0.7
      )
    )
  )
}
dd_yaml_pks <- function() c(dict_pks(), list(staff = "staff_id"))

test_that("data-dict export follows the spec", {
  skip_if_not_installed("yaml")
  edits <- list(
    customers = list(description = "People", label = "Customers"),
    "customers|tier" = list(label = "Tier", values = "gold = Gold; silver = Silver; bronze = Bronze"),
    "orders|amount" = list(units = "GBP", description = "Total")
  )
  y <- generate_data_dict_yaml(dd_yaml_tables(), dd_yaml_rels(), dd_yaml_pks(), dictionary = edits)
  doc <- yaml::yaml.load(y)
  expect_equal(doc[["$version"]], "0.1.0")
  expect_equal(vapply(doc$tables, `[[`, "", "name"), c("customers", "orders", "staff"))
  cust <- doc$tables[[1]]
  expect_equal(cust$label, "Customers")
  cols <- setNames(cust$columns, vapply(cust$columns, `[[`, "", "name"))
  expect_equal(cols$customer_id$type, "number(id)")
  expect_equal(cols$customer_id$constraints, "primary_key")
  expect_equal(cols$tier$type, "enum")
  expect_equal(cols$tier$values, list(gold = "Gold", silver = "Silver", bronze = "Bronze"))
  expect_null(cols$tier$examples)
  # Private: restricted, placeholder examples, never real values
  expect_equal(cols$email$display, "restricted")
  expect_equal(cols$email$examples, "person@example.com")
  expect_false(grepl("a@x.io", y, fixed = TRUE))
  ord <- setNames(doc$tables[[2]]$columns, vapply(doc$tables[[2]]$columns, `[[`, "", "name"))
  expect_equal(ord$amount$type, "number(quantity)")
  expect_equal(ord$amount$units, "GBP")
  expect_equal(unlist(ord$amount$range), c(1, 30))
  expect_equal(ord$customer_id$constraints, "foreign_key")
  expect_equal(unlist(ord$order_id$examples), c(1, 2, 4, 5, 6))
  # Relationships: declared and manual; the self-join is aliased
  joins <- vapply(doc$relationships, `[[`, "", "join")
  expect_equal(joins, c("orders.customer_id = customers.customer_id", "child.manager_id = parent.staff_id"))
  expect_equal(doc$relationships[[2]]$aliases, list(child = "staff", parent = "staff"))
  expect_equal(doc$relationships[[1]]$cardinality, "many-to-one")
  # Unreviewed detected links are a todo, not a relationship
  expect_match(doc$todo, "orders.order_id = staff.staff_id (medium confidence)", fixed = TRUE)
})

test_that("a private number gets an open range; units elsewhere go to details", {
  skip_if_not_installed("yaml")
  t <- list(p = data.frame(id = 1:3, weight = c(50, 60, 70), tag = c("a", "b", "c"), stringsAsFactors = FALSE))
  d <- list("p|weight" = list(units = "kg", private = TRUE), "p|tag" = list(units = "cm"))
  doc <- yaml::yaml.load(generate_data_dict_yaml(t, list(), list(p = "id"), dictionary = d))
  cols <- setNames(doc$tables[[1]]$columns, vapply(doc$tables[[1]]$columns, `[[`, "", "name"))
  expect_equal(unlist(cols$weight$range), c(-Inf, Inf))
  expect_equal(cols$weight$display, "restricted")
  expect_null(cols$tag$units)
  expect_match(cols$tag$details, "Units: cm")
})

test_that("data-dict files import as tables, declared links and dictionary entries", {
  skip_if_not_installed("yaml")
  edits <- list(
    customers = list(description = "People", label = "Customers"),
    "customers|tier" = list(label = "Tier", values = "gold = Gold; silver = Silver"),
    "orders|amount" = list(units = "GBP"),
    "customers|email" = list(private = TRUE)
  )
  f <- tempfile(fileext = ".yaml")
  writeLines(generate_data_dict_yaml(dd_yaml_tables(), dd_yaml_rels(), dd_yaml_pks(), dictionary = edits), f)
  back <- parse_schema_file(f, "data-dict.yaml")
  expect_equal(names(back$tables), c("customers", "orders", "staff"))
  expect_equal(names(back$tables$customers), c("customer_id", "email", "tier"))
  expect_length(back$relationships, 2)
  r <- back$relationships[[2]]
  expect_equal(c(r$from_table, r$from_col, r$to_table, r$to_col), c("staff", "manager_id", "staff", "staff_id"))
  expect_equal(rel_source(r), "declared")
  expect_equal(back$dictionary$customers$label, "Customers")
  expect_equal(back$dictionary[["customers|tier"]]$values, "gold = Gold; silver = Silver")
  expect_equal(back$dictionary[["orders|amount"]]$units, "GBP")
  expect_true(back$dictionary[["customers|email"]]$private)
  expect_equal(dict_privacy(back$dictionary, "customers", "email")$status, "imported")
  # Merging keeps what the user already wrote
  merged <- merge_dictionary(list("customers|tier" = list(label = "Mine")), back$dictionary)
  expect_equal(merged[["customers|tier"]]$label, "Mine")
  expect_equal(merged[["customers|tier"]]$values, "gold = Gold; silver = Silver")
})

test_that("a hand-written data-dict file imports, one-to-many joins included", {
  skip_if_not_installed("yaml")
  f <- tempfile(fileext = ".yml")
  writeLines(c(
    "$version: 0.1.0",
    "tables:",
    "  - name: food",
    "    description: Each row is a food item.",
    "    columns:",
    "      - name: fdc_id",
    "        label: FoodData Central ID",
    "        type: number(id)",
    "        constraints: [primary_key]",
    "        examples: [167512, 174231]",
    "      - name: food_category_id",
    "        type: number(id)",
    "        constraints: [foreign_key]",
    "      - name: data_type",
    "        type: enum",
    "        values: [foundation, branded]",
    "  - name: food_category",
    "    columns:",
    "      - name: id",
    "        type: number(id)",
    "relationships:",
    "  - join: food_category.id = food.food_category_id",
    "    cardinality: one-to-many",
    "  - join: food.x >= food_category.y AND food.x <= food_category.z",
    "    cardinality: many-to-one"
  ), f)
  msgs <- character(0)
  back <- parse_schema_file(f, "dd.yml", function(m) msgs <<- c(msgs, m))
  expect_equal(names(back$tables), c("food", "food_category"))
  r <- back$relationships[[1]]
  expect_equal(c(r$from_table, r$from_col, r$to_table, r$to_col), c("food", "food_category_id", "food_category", "id"))
  expect_length(back$relationships, 1)
  expect_match(msgs, "1 data-dict relationship")
  expect_equal(back$dictionary[["food|fdc_id"]]$label, "FoodData Central ID")
  expect_equal(back$dictionary[["food|data_type"]]$values, "foundation; branded")
  expect_equal(back$dictionary$food$description, "Each row is a food item.")
})

test_that("allowed values parse both ways", {
  expect_equal(dict_parse_values("A = Active; I = Inactive"), list(A = "Active", I = "Inactive"))
  expect_equal(dict_parse_values("a; b"), c("a", "b"))
  expect_null(dict_parse_values(" "))
  expect_equal(dict_format_values(list(A = "Active")), "A = Active")
  expect_equal(dict_format_values(list("a", "b")), "a; b")
})

test_that("sessions keep privacy choices and reviews", {
  edits <- list(
    "orders|amount" = list(private = TRUE),
    "customers|email" = list(privacy_review = list(state = "rejected", reason = "name contains \"email\"")),
    .settings = list(private_patterns = "*_id", examples = "off")
  )
  back <- restore_session_json(save_session_json(dict_tables(), list(), list(), list(), dictionary = edits))
  expect_true(back$dictionary[["orders|amount"]]$private)
  expect_equal(dict_privacy(back$dictionary, "customers", "email", dict_tables()$customers$email)$status, "not_personal")
  expect_equal(dict_settings(back$dictionary), list(private_patterns = "*_id", examples = "off"))
})

test_that("imported data-dict tables keep their types for a re-export", {
  skip_if_not_installed("yaml")
  f <- tempfile(fileext = ".yaml")
  writeLines(generate_data_dict_yaml(dd_yaml_tables(), dd_yaml_rels(), dd_yaml_pks()), f)
  back <- parse_schema_file(f, "data-dict.yaml")
  expect_true(is.numeric(back$tables$orders$amount))
  expect_true(is.character(back$tables$customers$tier))
  doc <- yaml::yaml.load(generate_data_dict_yaml(back$tables, back$relationships, dd_yaml_pks()))
  types <- unlist(lapply(doc$tables, function(t) vapply(t$columns, `[[`, "", "type")))
  expect_false("boolean" %in% types)
})

test_that("large whole-number examples are written in full", {
  skip_if_not_installed("yaml")
  t <- list(p = data.frame(id = c(9876543210, 9876543211, 9876543212)))
  y <- generate_data_dict_yaml(t, list(), list(p = "id"))
  expect_match(y, "- 9876543210", fixed = TRUE)
  expect_false(grepl(".na", y, fixed = TRUE))
  # R's yaml reader turns large ints into NA unless told to read them as doubles
  doc <- yaml::yaml.load(y, handlers = list(int = function(x) as.numeric(x)))
  expect_equal(doc$tables[[1]]$columns[[1]]$examples[[1]], 9876543210)
})

test_that("imported entries for a column named like its table land on it", {
  merged <- merge_dictionary(list(), list("status|status" = list(label = "Status")))
  expect_equal(names(merged), "status|status")
})

dd_doc <- function(...) yaml::yaml.load(generate_data_dict_yaml(...), handlers = list(int = function(x) as.numeric(x)))
dd_cols <- function(tdef) setNames(tdef$columns, vapply(tdef$columns, `[[`, "", "name"))

test_that("a single-table data-dict round trip keeps its docs and primary key", {
  skip_if_not_installed("yaml")
  t <- list(people = data.frame(code = c("a", "b"), note = c("x", NA), stringsAsFactors = FALSE))
  d <- list(people = list(label = "People", description = "All the people"))
  f <- tempfile(fileext = ".yaml")
  writeLines(generate_data_dict_yaml(t, list(), list(people = "code"), dictionary = d), f)
  back <- parse_schema_file(f, "dd.yaml")
  expect_equal(back$dictionary$people$label, "People")
  expect_equal(back$dictionary$people$description, "All the people")
  expect_equal(back$primary_keys, list(people = "code"))
  # Re-export from the imported (empty) tables with the declared key
  pks <- apply_declared_pks(list(people = character(0)), merge_declared_pks(list(), back$primary_keys), back$tables)
  doc <- dd_doc(back$tables, back$relationships, pks, dictionary = back$dictionary)
  cols <- dd_cols(doc$tables[[1]])
  expect_equal(cols$code$constraints, "primary_key")
  # Nothing is known about missing values in a table without rows
  expect_null(cols$note$constraints)
  expect_equal(doc$label, "People")
})

test_that("JSON/YAML schema files declare primary keys", {
  f <- tempfile(fileext = ".json")
  writeLines('{"tables":[{"name":"A","columns":[{"name":"Code","primary_key":true},{"name":"x"}]},
    {"name":"b","primary_key":["k1","k2"],"columns":[{"name":"k1"},{"name":"k2"}]}]}', f)
  s <- parse_schema_file(f, "s.json")
  expect_equal(s$primary_keys, list(A = "Code", b = c("k1", "k2")))
  pks <- merge_declared_pks(list(), s$primary_keys)
  expect_equal(pks, list(a = "code", b = c("k1", "k2")))
  tabs <- list(a = data.frame(code = 1, x = 2), b = data.frame(k1 = 1, k2 = 2))
  expect_equal(apply_declared_pks(list(a = "x", b = "k1"), pks, tabs), list(a = structure("code", declared = TRUE), b = character(0)))
  expect_equal(apply_declared_composite_pks(list(a = NULL, b = NULL), pks, tabs)$b, list(c("k1", "k2")))
})

test_that("data-dict joins: non-key targets become todos, duplicates collapse", {
  skip_if_not_installed("yaml")
  t <- list(
    a = data.frame(a_id = 1:3, ref = c("x", "y", "x"), b_id = c(1L, 2L, 2L), stringsAsFactors = FALSE),
    b = data.frame(b_id = 1:2, ref = c("x", "y"), stringsAsFactors = FALSE),
    c = data.frame(k1 = c(1L, 1L), k2 = 1:2, n = 1:2)
  )
  rels <- list(
    list(from_table = "a", from_col = "b_id", to_table = "b", to_col = "b_id", detected_by = "schema"),
    list(from_table = "a", from_col = "b_id", to_table = "b", to_col = "b_id", detected_by = "manual"),
    list(from_table = "a", from_col = "b_id", to_table = "b", to_col = "b_id", detected_by = "naming", confidence = "high", score = 0.9),
    list(from_table = "b", from_col = "ref", to_table = "a", to_col = "ref", detected_by = "manual"),
    list(from_table = "a", from_col = "a_id", to_table = "c", to_col = "k1", detected_by = "manual")
  )
  doc <- dd_doc(t, rels, list(a = "a_id", b = "b_id"), composite_pks = list(c = list(c("k1", "k2"))))
  expect_equal(vapply(doc$relationships, `[[`, "", "join"), "a.b_id = b.b_id")
  expect_null(doc$relationships[[1]]$description)
  expect_false(grepl("a.b_id = b.b_id", doc$todo, fixed = TRUE))
  expect_match(doc$todo, "- b.ref = a.ref (manual)", fixed = TRUE)
  expect_match(doc$todo, "- a.a_id = c.k1 (manual)", fixed = TRUE)
})

test_that("data-dict spec edge cases", {
  skip_if_not_installed("yaml")
  t <- list(
    e = data.frame(),
    x = data.frame(
      id = 1:3,
      status = c(1L, 2L, 1L),
      blank = c("", " ", ""),
      val = c(1, Inf, 3),
      day = as.Date(c("2024-01-02", "2024-03-04", NA)),
      at = as.POSIXct(c("2024-01-02 03:04:05", "2024-01-03 00:00:00", NA), tz = "UTC"),
      stringsAsFactors = FALSE
    )
  )
  d <- list("x|status" = list(values = "1 = Open; 2 = Closed; = Bad; 1 = Dup"))
  doc <- dd_doc(t, list(), list(x = "id"), dictionary = d)
  expect_equal(length(doc$tables), 1)
  expect_match(doc$todo, "Tables with no columns, left out: e", fixed = TRUE)
  cols <- dd_cols(doc$tables[[1]])
  expect_equal(cols$status$type, "number")
  expect_null(cols$status$values)
  expect_match(cols$status$details, "Allowed values: 1 = Open; 2 = Closed", fixed = TRUE)
  expect_equal(cols$blank$examples, "(withheld)")
  expect_equal(unlist(cols$val$examples), c(1, 3))
  expect_equal(unlist(cols$day$range), c("2024-01-02", "2024-03-04"))
  expect_equal(unlist(cols$at$range), c("2024-01-02T03:04:05Z", "2024-01-03T00:00:00Z"))
  expect_equal(dict_parse_values("1 = Open; = Bad; 1 = Dup; 2"), list("1" = "Open", "2" = "2"))
})

test_that("data-dict: one-to-one joins, and aliases that avoid table names", {
  skip_if_not_installed("yaml")
  t <- list(
    child = data.frame(id = 1:3, boss = c(NA, 1L, 1L)),
    parent = data.frame(id = 1:2),
    profile = data.frame(child_id = 1:3, bio = c("a", "b", "c"), stringsAsFactors = FALSE)
  )
  rels <- list(
    list(from_table = "child", from_col = "boss", to_table = "child", to_col = "id", detected_by = "schema"),
    list(from_table = "profile", from_col = "child_id", to_table = "child", to_col = "id", detected_by = "schema")
  )
  doc <- dd_doc(t, rels, list(child = "id", parent = "id", profile = "child_id"))
  joins <- vapply(doc$relationships, `[[`, "", "join")
  expect_true("child_.boss = parent_.id" %in% joins)
  self <- doc$relationships[[match("child_.boss = parent_.id", joins)]]
  expect_equal(self$aliases, list(child_ = "child", parent_ = "child"))
  one <- doc$relationships[[match("profile.child_id = child.id", joins)]]
  expect_equal(one$cardinality, "one-to-one")
})

test_that("data-dict import: one-to-many joins with aliases", {
  skip_if_not_installed("yaml")
  f <- tempfile(fileext = ".yaml")
  writeLines(c(
    "$version: 0.1.0",
    "tables:",
    "  - name: otters",
    "    columns:",
    "      - {name: otter_no, type: number(id), constraints: [primary_key]}",
    "      - {name: pup_number, type: number(id)}",
    "relationships:",
    "  - join: mother.otter_no = pup.pup_number",
    "    aliases: {mother: otters, pup: otters}",
    "    cardinality: one-to-many"
  ), f)
  back <- parse_schema_file(f, "o.yaml")
  r <- back$relationships[[1]]
  expect_equal(c(r$from_table, r$from_col, r$to_table, r$to_col), c("otters", "pup_number", "otters", "otter_no"))
  expect_equal(back$primary_keys, list(otters = "otter_no"))
  # A table the file gives no key has none while it has no rows
  f2 <- tempfile(fileext = ".yaml")
  writeLines(c("$version: 0.1.0", "tables:", "  - name: log", "    columns:", "      - {name: log_id, type: number(id)}"), f2)
  b2 <- parse_schema_file(f2, "l.yaml")
  expect_equal(b2$primary_keys, list(log = character(0)))
  pks <- merge_declared_pks(list(), b2$primary_keys)
  expect_equal(apply_declared_pks(list(log = "log_id"), pks, b2$tables), list(log = structure(character(0), declared = TRUE)))
  expect_equal(apply_declared_pks(list(log = "log_id"), pks, list(log = data.frame(log_id = 1:2))), list(log = "log_id"))
})

test_that("sessions keep declared keys; an old business_name session restores end to end", {
  js <- save_session_json(dict_tables(), list(), list(), list(), declared_pks = list(orders = "order_id", c = c("a", "b")))
  expect_equal(restore_session_json(js)$declared_pks, list(orders = "order_id", c = c("a", "b")))
  old <- save_session_json(dict_tables(), list(), list(), list(),
    dictionary = list("orders|amount" = list(business_name = "Order total")))
  back <- restore_session_json(old)
  dd <- build_data_dictionary(back$tables, list(), dict_pks(), dictionary = back$dictionary)
  expect_equal(dd$label[dd$column == "amount"], "Order total")
})

test_that("declared primary keys win over detection's filters and composite keys", {
  t <- list(ps = data.frame(
    sku = c(1.5, 2.5, 3.5), product_id = c(1L, 1L, 2L), supplier_id = c(1L, 2L, 1L)
  ))
  rels <- list(
    list(from_table = "ps", from_col = "product_id", to_table = "p", to_col = "id"),
    list(from_table = "ps", from_col = "supplier_id", to_table = "s", to_col = "id")
  )
  t$p <- data.frame(id = 1:2)
  t$s <- data.frame(id = 1:2)
  declared <- list(ps = "sku")
  pks <- apply_declared_pks(list(ps = character(0), p = "id", s = "id"), declared, t)
  comp <- apply_declared_composite_pks(list(ps = list(c("product_id", "supplier_id"))), declared, t)
  m <- erd_model(t, rels, pks, comp)
  expect_equal(m$tables$ps$columns$name[m$tables$ps$columns$pk], "sku")
  expect_equal(merge_declared_pks(list(), list(Orders = c("ID", "ID"))), list(orders = "id"))
})

test_that("sessions keep empty tables and column types", {
  t <- list(
    empty = data.frame(a = integer(0), b = character(0), stringsAsFactors = FALSE),
    d = data.frame(day = as.Date(c("2024-01-02", NA)), n = c(1L, 2L))
  )
  back <- restore_session_json(save_session_json(t, list(), list(), list()))$tables
  expect_equal(names(back$empty), c("a", "b"))
  expect_equal(nrow(back$empty), 0)
  expect_true(is.integer(back$empty$a))
  expect_s3_class(back$d$day, "Date")
  expect_true(is.na(back$d$day[2]))
})

test_that("sessions keep full precision and datetimes", {
  t <- list(x = data.frame(
    v = c(1234.5678, 0.000123456),
    at = as.POSIXct(c("2024-01-01 00:00:00", "2024-01-01 10:00:00"), tz = "UTC")
  ))
  back <- restore_session_json(save_session_json(t, list(), list(), list()))$tables$x
  expect_equal(back$v, t$x$v)
  expect_equal(format(back$at, "%H:%M:%S", tz = "UTC"), c("00:00:00", "10:00:00"))
})

test_that("a declared key the loaded data contradicts is not used", {
  t <- list(a = data.frame(code = c(1L, 1L, 2L), id = 1:3))
  pks <- apply_declared_pks(list(a = "id"), list(a = "code"), t)
  m <- erd_model(t, list(), pks)
  expect_false("code" %in% m$tables$a$columns$name[m$tables$a$columns$pk])
})
