# ============================================================
# Tests for utils_erd_model.R - shared ERD model
# ============================================================

test_that("erd_col_type maps R classes to physical types", {
  expect_equal(erd_col_type(1:3), "int")
  expect_equal(erd_col_type(c(1, 2)), "int")
  expect_equal(erd_col_type(c(1.5, 2)), "float")
  expect_equal(erd_col_type(c(TRUE, NA)), "bool")
  expect_equal(erd_col_type(as.Date("2024-01-01")), "date")
  expect_equal(erd_col_type(Sys.time()), "datetime")
  expect_equal(erd_col_type(c("a", "b")), "string")
})

test_that("columns carry type, nullability and key badges", {
  m <- erd_fixture_model()
  cols <- m$tables$orders$columns
  expect_equal(cols$name[1], "order_id") # PK first
  expect_true(cols$pk[cols$name == "order_id"])
  expect_equal(cols$fk_index[cols$name == "customer_id"], 1L)
  expect_true(cols$nullable[cols$name == "customer_id"])
  expect_false(cols$nullable[cols$name == "order_id"])
  expect_equal(cols$type[cols$name == "amount"], "float")
  # Composite PK columns are both PK and numbered FKs
  oi <- m$tables$order_items$columns
  expect_true(all(oi$pk[oi$name %in% c("order_id", "product_id")]))
  expect_equal(oi$fk_index[oi$name == "product_id"], 2L)
})

test_that("cardinality and optionality come from the FK column", {
  m <- erd_fixture_model()
  r <- rel_of(m, "orders", "customer_id")
  expect_equal(r$child_max, "many")
  expect_equal(r$parent_min, "zero") # one NULL customer_id
  expect_equal(r$child_min, "zero")
  expect_false(r$identifying)
  one <- rel_of(m, "customer_profile", "customer_id")
  expect_equal(one$child_max, "one") # 1:1
  expect_equal(one$parent_min, "one")
  expect_true(one$identifying) # FK is the child's PK
})

test_that("identifying relationships follow composite PKs", {
  m <- erd_fixture_model()
  expect_true(rel_of(m, "order_items", "order_id")$identifying)
  expect_true(rel_of(m, "order_items", "product_id")$identifying)
})

test_that("provenance distinguishes declared, manual, confirmed, inferred", {
  m <- erd_fixture_model()
  expect_equal(rel_of(m, "orders", "customer_id")$provenance, "inferred")
  expect_equal(rel_of(m, "customer_profile", "customer_id")$provenance, "declared")
  expect_equal(rel_of(m, "order_items", "order_id")$provenance, "confirmed")
  expect_equal(rel_of(m, "order_items", "product_id")$provenance, "manual")
})

test_that("table roles and subject areas", {
  m <- erd_fixture_model()
  expect_equal(m$tables$order_items$role, "junction")
  expect_equal(m$tables$tlk_status$role, "lookup")
  expect_equal(m$tables$audit_log$role, "orphan")
  expect_equal(m$tables$customers$role, "entity")
  expect_equal(m$tables$tlk_status$subject_area, "Lookups")
  expect_equal(m$tables$audit_log$subject_area, "Unconnected")
  # Connected tables share an area named after the largest table
  areas <- vapply(
    m$tables[c("customers", "orders", "order_items", "products")],
    function(t) t$subject_area,
    character(1)
  )
  expect_true(all(areas == "orders"))
})

test_that("empty child tables give unknown cardinality", {
  tables <- list(
    customers = data.frame(customer_id = 1:3),
    tbl_income = data.frame(customer_id = integer(0))
  )
  rels <- list(list(
    from_table = "tbl_income", from_col = "customer_id",
    to_table = "customers", to_col = "customer_id", detected_by = "naming"
  ))
  m <- erd_model(tables, rels, list(customers = "customer_id"))
  expect_equal(m$rels[[1]]$child_max, "unknown")
  expect_equal(m$rels[[1]]$parent_min, "unknown")
  expect_true(is.na(m$tables$tbl_income$columns$nullable))
})
