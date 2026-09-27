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
