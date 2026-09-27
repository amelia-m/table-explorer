# Shared fixtures for the ERD model / view / export tests

erd_fixture <- function() {
  list(
    customers = data.frame(
      customer_id = 1:4,
      email = c("a@x.io", "b@x.io", "c@x.io", "d@x.io"),
      stringsAsFactors = FALSE
    ),
    orders = data.frame(
      order_id = 1:6,
      customer_id = c(1L, 2L, 1L, NA, 3L, 4L),
      amount = c(10.5, 20, 30, 15.5, 1, 2),
      stringsAsFactors = FALSE
    ),
    customer_profile = data.frame(
      customer_id = 1:4,
      bio = letters[1:4],
      stringsAsFactors = FALSE
    ),
    order_items = data.frame(
      order_id = c(1L, 1L, 2L),
      product_id = c(1L, 2L, 1L),
      qty = c(1L, 3L, 2L)
    ),
    products = data.frame(product_id = 1:2, sku = c("A", "B")),
    tlk_status = data.frame(id = 1:3, label = c("a", "b", "c")),
    audit_log = data.frame(msg = c("x", "y"))
  )
}

erd_fixture_rels <- function() {
  mk <- function(ft, fc, tt, tc, by = "naming", conf = FALSE) {
    list(
      from_table = ft, from_col = fc, to_table = tt, to_col = tc,
      detected_by = by, confidence = "high", score = 0.9,
      confirmed = conf
    )
  }
  list(
    mk("orders", "customer_id", "customers", "customer_id"),
    mk("customer_profile", "customer_id", "customers", "customer_id",
       by = "schema"),
    mk("order_items", "order_id", "orders", "order_id", conf = TRUE),
    mk("order_items", "product_id", "products", "product_id", by = "manual")
  )
}

erd_fixture_model <- function() {
  erd_model(
    erd_fixture(),
    erd_fixture_rels(),
    list(
      customers = "customer_id", orders = "order_id",
      customer_profile = "customer_id", products = "product_id",
      tlk_status = "id"
    ),
    list(order_items = list(c("order_id", "product_id")))
  )
}

rel_of <- function(model, from_table, from_col) {
  Filter(
    function(r) r$from_table == from_table && r$from_col == from_col,
    model$rels
  )[[1]]
}
