# ============================================================
# Tests for erd_view() and erd_elk_graph() - the ERD Diagram tab
# ============================================================

low_rel <- function() {
  list(
    from_table = "order_items", from_col = "qty", to_table = "tlk_status",
    to_col = "id", detected_by = "naming", confidence = "low", score = 0.3,
    confirmed = FALSE
  )
}

view_model <- function(extra = list()) {
  erd_model(
    erd_fixture(),
    c(erd_fixture_rels(), extra),
    list(
      customers = "customer_id", orders = "order_id",
      customer_profile = "customer_id", products = "product_id",
      tlk_status = "id"
    ),
    list(order_items = list(c("order_id", "product_id")))
  )
}

test_that("no focus keeps every table and relationship", {
  v <- erd_view(view_model())
  expect_setequal(names(v$tables), names(erd_fixture()))
  expect_length(v$rels, 4)
  expect_equal(v$hidden_tables, 0)
  expect_equal(v$hidden_rels, 0)
  expect_setequal(v$orphans, c("tlk_status", "audit_log"))
})

test_that("focus keeps the N-hop neighbourhood", {
  m <- view_model()
  expect_setequal(
    names(erd_view(m, focus = "customers", hops = 1)$tables),
    c("customers", "orders", "customer_profile")
  )
  expect_setequal(
    names(erd_view(m, focus = "customers", hops = 2)$tables),
    c("customers", "orders", "customer_profile", "order_items")
  )
  v3 <- erd_view(m, focus = "customers", hops = Inf)
  expect_setequal(
    names(v3$tables),
    c("customers", "orders", "customer_profile", "order_items", "products")
  )
  expect_equal(v3$hidden_tables, 2)
  # Relationships only between kept tables
  v1 <- erd_view(m, focus = "customers", hops = 1)
  expect_true(all(vapply(v1$rels, function(r) {
    r$from_table %in% names(v1$tables) && r$to_table %in% names(v1$tables)
  }, logical(1))))
  # Unknown or blank focus means everything
  expect_length(erd_view(m, focus = "")$tables, 7)
  expect_length(erd_view(m, focus = "nope")$tables, 7)
})

test_that("low-confidence inferred links hide unless asked for", {
  m <- view_model(list(low_rel()))
  v <- erd_view(m)
  expect_length(v$rels, 4)
  expect_equal(v$hidden_rels, 1)
  expect_length(erd_view(m, show_low = TRUE)$rels, 5)
  # A confirmed low-confidence link is always shown
  conf <- low_rel()
  conf$confirmed <- TRUE
  expect_length(erd_view(view_model(list(conf)))$rels, 5)
})

test_that("subject-area filter keeps only those areas", {
  m <- view_model()
  area <- m$tables$customers$subject_area
  v <- erd_view(m, areas = area)
  expect_true(all(vapply(v$tables, function(t) t$subject_area == area, logical(1))))
  expect_true("customers" %in% names(v$tables))
  expect_false("audit_log" %in% names(v$tables))
})

test_that("detail levels choose the columns", {
  m <- view_model()
  all <- erd_view(m, detail = "all")
  expect_equal(nrow(all$tables$orders$columns), 3)
  expect_equal(all$tables$orders$hidden_columns, 0)

  keys <- erd_view(m, detail = "keys")
  expect_setequal(keys$tables$orders$columns$name, c("order_id", "customer_id"))
  expect_equal(keys$tables$orders$hidden_columns, 1)
  expect_equal(nrow(keys$tables$audit_log$columns), 0)

  nm <- erd_view(m, detail = "names")
  expect_equal(nm$tables$orders$hidden_columns, 3)
  expect_true(all(nzchar(vapply(nm$tables, `[[`, character(1), "header_color"))))
})

graph_ports <- function(g) {
  unlist(lapply(g$children, function(n) vapply(n$ports, `[[`, character(1), "id")))
}

test_that("erd_elk_graph edges reference existing ports at every detail", {
  m <- view_model(list(low_rel()))
  for (detail in c("all", "keys", "names")) {
    v <- erd_view(m, show_low = TRUE, detail = detail)
    g <- erd_elk_graph(v, detail = detail, direction = "DOWN")
    expect_equal(g$layoutOptions[["elk.direction"]], "DOWN")
    expect_equal(g$properties$detail, detail)
    ports <- graph_ports(g)
    expect_false(anyDuplicated(ports) > 0)
    ends <- unlist(lapply(g$edges, function(e) c(e$sources[[1]], e$targets[[1]])))
    expect_true(all(ends %in% ports), info = detail)
    expect_length(g$edges, length(v$rels))
    keys <- vapply(g$edges, function(e) e$properties$key, character(1))
    expect_setequal(keys, vapply(v$rels, rel_key, character(1)))
  }
})

test_that("names-only cards are header height with ports on the header", {
  v <- erd_view(view_model(), detail = "names")
  g <- erd_elk_graph(v, detail = "names")
  for (n in g$children) {
    expect_equal(n$height, erd_elk_header_height)
    expect_length(n$properties$columns, 0)
    for (p in n$ports) expect_equal(p$y, erd_elk_header_height / 2)
  }
})

test_that("keys-only ports sit on the visible rows", {
  v <- erd_view(view_model(), detail = "keys")
  g <- erd_elk_graph(v, detail = "keys")
  for (n in g$children) {
    cols <- vapply(n$properties$columns, `[[`, character(1), "name")
    for (p in n$ports) {
      col <- sub(":(in|out)$", "", substring(p$id, nchar(n$id) + 2))
      i <- match(col, cols)
      expect_false(is.na(i), info = p$id)
      expect_equal(
        p$y,
        erd_elk_header_height + (i - 0.5) * erd_elk_row_height
      )
    }
  }
})

test_that("links without a usable target column attach to the parent key", {
  mk <- function(to_col) {
    list(
      from_table = "orders", from_col = "customer_id", to_table = "customers",
      to_col = to_col, detected_by = "schema", confidence = "high",
      score = 1, confirmed = FALSE
    )
  }
  for (tc in list("", NA_character_, "no_such_col", NULL)) {
    m <- erd_model(
      erd_fixture()[c("customers", "orders")],
      list(mk(tc)),
      list(customers = "customer_id", orders = "order_id")
    )
    expect_length(m$rels, 1)
    expect_equal(m$rels[[1]]$to_col, "customer_id")
    g <- erd_elk_graph(erd_view(m))
    expect_true(all(unlist(g$edges[[1]][c("sources", "targets")]) %in% graph_ports(g)))
  }
})

test_that("links that can't be placed on a row stay out of the model", {
  rel <- list(
    from_table = "audit_log", from_col = "msg", to_table = "order_items",
    to_col = "", detected_by = "schema", confidence = "high", score = 1,
    confirmed = FALSE
  )
  # order_items has a composite key and no "msg" column
  m <- erd_model(
    erd_fixture(), list(rel), list(),
    list(order_items = list(c("order_id", "product_id")))
  )
  expect_length(m$rels, 0)
  ghost <- rel
  ghost$from_col <- "missing"
  ghost$to_table <- "customers"
  expect_length(erd_model(erd_fixture(), list(ghost), list())$rels, 0)
})

test_that("large-schema 'Keys only' default isn't taken for a user choice", {
  skip_if_not_installed("shiny")
  big <- stats::setNames(
    lapply(1:45, function(i) data.frame(id = 1:3)),
    paste0("t", 1:45)
  )
  tables <- shiny::reactiveVal(big)
  shiny::testServer(
    mod_erd_server,
    args = list(
      tables_rv = tables,
      rels_rv = shiny::reactive(list()),
      pk_map_rv = shiny::reactive(list()),
      composite_pk_map_rv = shiny::reactive(list()),
      confirmed_rels_rv = shiny::reactiveVal(list()),
      false_positives_rv = shiny::reactiveVal(character(0))
    ),
    {
      session$setInputs(detail = "all", direction = "RIGHT", hops = 2)
      session$flushReact()
      expect_equal(detail_rv(), "keys")
      # The radio echoes the server's update back
      session$setInputs(detail = "keys")
      expect_null(user_detail())
      # A small dataset goes back to all columns
      tables(erd_fixture())
      session$flushReact()
      expect_equal(detail_rv(), "all")
      # A real choice sticks
      session$setInputs(detail = "names")
      tables(big)
      session$flushReact()
      expect_equal(detail_rv(), "names")
    }
  )
})

# ── Declared vs detected ─────────────────────────────────────

src_rel <- function(from_col, to_table, by, confirmed = FALSE, score = 0.9) {
  list(
    from_table = "tbl_visits", from_col = from_col, to_table = to_table,
    to_col = "id", detected_by = by, confidence = "high", score = score,
    confirmed = confirmed
  )
}

test_that("rel_source tells declared, manual, confirmed and detected apart", {
  expect_equal(rel_source(src_rel("a", "t", "schema")), "declared")
  expect_equal(rel_source(src_rel("a", "t", "manual")), "manual")
  expect_equal(rel_source(src_rel("a", "t", "naming", confirmed = TRUE)), "confirmed")
  expect_equal(rel_source(src_rel("a", "t", "cardinality")), "detected")
})

test_that("a detected link that is also declared shows once, as declared", {
  declared <- list(src_rel("service_id", "tlk_services", "schema", score = 1))
  auto <- list(
    src_rel("service_id", "tlk_services", "naming", score = 0.87),
    src_rel("service_id", "tlk_sites", "cardinality"),
    src_rel("site_id", "tlk_sites", "naming")
  )
  both <- combine_relationships(auto, list(), declared)
  keys <- vapply(both, rel_key, "")
  expect_equal(sum(keys == "tbl_visits|service_id|tlk_services|id"), 1)
  kept <- both[[which(keys == "tbl_visits|service_id|tlk_services|id")]]
  expect_equal(rel_source(kept), "declared")
  expect_equal(kept$also_detected, 0.87)
  # Other detected links, even on the declared column, stay by default
  expect_length(both, 3)
  # ... unless hidden on columns that have a declared link
  trimmed <- combine_relationships(auto, list(), declared, hide_detected_on_declared = TRUE)
  expect_setequal(
    vapply(trimmed, rel_key, ""),
    c("tbl_visits|service_id|tlk_services|id", "tbl_visits|site_id|tlk_sites|id")
  )
})

test_that("source filters keep declared or detected links", {
  rels <- list(
    src_rel("a", "t1", "schema"),
    src_rel("b", "t2", "manual"),
    src_rel("c", "t3", "naming", confirmed = TRUE),
    src_rel("d", "t4", "cardinality")
  )
  src <- function(x) vapply(x, rel_source, "")
  expect_equal(src(filter_rel_sources(rels, "declared")), c("declared", "manual"))
  expect_equal(src(filter_rel_sources(rels, "detected")), c("confirmed", "detected"))
  expect_length(filter_rel_sources(rels, "both"), 4)
})

test_that("links without a score (manual) give no null ELK properties", {
  manual <- list(
    from_table = "orders", from_col = "customer_id", to_table = "customers",
    to_col = "customer_id", detected_by = "manual"
  )
  m <- erd_model(
    erd_fixture()[c("customers", "orders")],
    list(manual),
    list(customers = "customer_id", orders = "order_id")
  )
  g <- erd_elk_graph(erd_view(m))
  props <- g$edges[[1]]$properties
  expect_false(any(vapply(props, function(v) is.null(v) || anyNA(v), logical(1))))
  expect_equal(props$provenance, "manual")
})

# ── Reference tables shown as labels; unlinked tables to the side ──

ref_fixture <- function() {
  set.seed(5)
  list(
    status = data.frame(status_code = c("A", "B", "C"), label = c("a", "b", "c")),
    countries = data.frame(country_id = 1:20, name = paste0("c", 1:20), iso = letters[1:20]),
    orders = data.frame(order_id = 1:600, status_code = sample(c("A", "B", "C"), 600, TRUE), country_id = sample(1:20, 600, TRUE)),
    shipments = data.frame(shipment_id = 1:50, order_id = sample(1:600, 50), country_id = sample(1:20, 50, TRUE)),
    suppliers = data.frame(supplier_id = 1:10, country_id = sample(1:20, 10, TRUE)),
    notes = data.frame(text = c("x", "y"))
  )
}
ref_rels <- function() {
  mk <- function(ft, fc, tt, tc) list(from_table = ft, from_col = fc, to_table = tt, to_col = tc, detected_by = "naming", confidence = "high", score = 1)
  list(
    mk("orders", "status_code", "status", "status_code"),
    mk("orders", "country_id", "countries", "country_id"),
    mk("shipments", "order_id", "orders", "order_id"),
    mk("shipments", "country_id", "countries", "country_id"),
    mk("suppliers", "country_id", "countries", "country_id")
  )
}
ref_model <- function() {
  erd_model(ref_fixture(), ref_rels(), list(
    status = "status_code", countries = "country_id", orders = "order_id",
    shipments = "shipment_id", suppliers = "supplier_id"
  ))
}

test_that("reference tables are found without Access-style names", {
  m <- ref_model()
  is_ref <- vapply(m$tables, function(t) isTRUE(t$is_reference), logical(1))
  # status: lookup-shaped; countries: narrow and referenced by 3 tables
  expect_true(is_ref[["status"]])
  expect_true(is_ref[["countries"]])
  # orders is referenced but has FKs of its own; the rest aren't parents
  expect_false(any(is_ref[c("orders", "shipments", "suppliers", "notes")]))
  am <- view_model()
  expect_true(isTRUE(am$tables$tlk_status$is_reference) || !"tlk_status" %in% unlist(lapply(am$rels, `[[`, "to_table")))
})

test_that("labels replace lines to reference tables; unlinked tables go to the side", {
  v <- erd_view(ref_model())
  lines <- erd_elk_graph(v, side = TRUE)
  labels <- erd_elk_graph(v, ref_labels = TRUE, side = TRUE)
  expect_length(lines$edges, 5)
  expect_length(labels$edges, 1) # shipments -> orders
  node <- function(g, id) g$children[[which(vapply(g$children, `[[`, "", "id") == id)]]
  cols <- node(labels, "orders")$properties$columns
  refs <- Filter(Negate(is.null), lapply(cols, `[[`, "refs"))
  expect_setequal(vapply(refs, function(r) r[[1]]$table, ""), c("status", "countries"))
  side <- vapply(labels$children, function(n) n$properties$side %||% "", "")
  names(side) <- vapply(labels$children, `[[`, "", "id")
  expect_equal(side[["status"]], "lookups")
  expect_equal(side[["countries"]], "lookups")
  expect_equal(side[["notes"]], "unlinked")
  # suppliers only links to a lookup, so it has no lines either
  expect_equal(side[["suppliers"]], "unlinked")
  expect_equal(side[["orders"]], "")
  # Line mode: only the orphan is set aside
  side_l <- vapply(lines$children, function(n) n$properties$side %||% "", "")
  expect_equal(sum(nzchar(side_l)), 1)
  # Edge ends still exist; names-only never uses labels
  ports <- graph_ports(labels)
  expect_true(all(unlist(lapply(labels$edges, function(e) c(e$sources[[1]], e$targets[[1]]))) %in% ports))
  expect_length(erd_elk_graph(erd_view(ref_model(), detail = "names"), detail = "names", ref_labels = TRUE)$edges, 5)
  # The export stays unchanged
  expect_length(erd_elk_graph(v)$edges, 5)
})

test_that("large schemas default to lookup labels without locking the choice", {
  skip_if_not_installed("shiny")
  big <- stats::setNames(lapply(1:45, function(i) data.frame(id = 1:3)), paste0("t", 1:45))
  tables <- shiny::reactiveVal(big)
  shiny::testServer(
    mod_erd_server,
    args = list(
      tables_rv = tables,
      rels_rv = shiny::reactive(list()),
      pk_map_rv = shiny::reactive(list()),
      composite_pk_map_rv = shiny::reactive(list()),
      confirmed_rels_rv = shiny::reactiveVal(list()),
      false_positives_rv = shiny::reactiveVal(character(0))
    ),
    {
      session$setInputs(detail = "all", ref_links = "lines", direction = "RIGHT", hops = 2)
      session$flushReact()
      expect_equal(ref_links_rv(), "labels")
      session$setInputs(ref_links = "labels") # the radio echoing the server
      expect_null(user_ref())
      tables(erd_fixture())
      session$flushReact()
      expect_equal(ref_links_rv(), "lines")
      session$setInputs(ref_links = "labels") # a real choice
      tables(big)
      session$flushReact()
      expect_equal(ref_links_rv(), "labels")
      expect_equal(user_ref(), "labels")
    }
  )
})

test_that("the ELK graph has no null node or column properties", {
  g <- erd_elk_graph(erd_view(ref_model()), ref_labels = TRUE, side = TRUE)
  has_null <- function(x) {
    if (is.null(x)) return(TRUE)
    if (is.list(x)) return(any(vapply(x, has_null, logical(1))))
    FALSE
  }
  for (n in g$children) expect_false(has_null(n$properties), info = n$id)
  expect_false(has_null(erd_elk_graph(erd_view(ref_model()))$children))
})

# ── Automatic detail level ───────────────────────────────────

test_that("erd_auto_detail counts columns, not only tables", {
  tbl <- function(n_cols) {
    list(columns = data.frame(name = paste0("c", seq_len(n_cols))))
  }
  # Few narrow tables: show everything
  expect_equal(erd_auto_detail(list(a = tbl(5), b = tbl(5))), "all")
  # Six very wide tables: the old table-count rule said "all" and the
  # cards rendered as unreadable strips
  expect_equal(
    erd_auto_detail(stats::setNames(rep(list(tbl(150)), 6), letters[1:6])),
    "keys"
  )
  # One wide table is enough
  expect_equal(erd_auto_detail(list(a = tbl(41), b = tbl(2))), "keys")
  # Many narrow tables, as before
  expect_equal(
    erd_auto_detail(stats::setNames(rep(list(tbl(2)), 41), paste0("t", 1:41))),
    "keys"
  )
  # Totals across the view count too
  expect_equal(
    erd_auto_detail(stats::setNames(rep(list(tbl(39)), 9), paste0("t", 1:9))),
    "keys"
  )
  expect_equal(erd_auto_detail(list()), "all")
})
