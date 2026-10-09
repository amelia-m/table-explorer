# Tests for mod_relationships.R

make_rel <- function(from_table, from_col, to_table, to_col, detected_by,
                     confirmed = FALSE, overlap = NA_real_,
                     n_from = NA_integer_, n_to = NA_integer_) {
  list(
    from_table = from_table, from_col = from_col,
    to_table = to_table, to_col = to_col,
    detected_by = detected_by, confirmed = confirmed,
    confidence = "high", score = 0.9,
    signals = list(naming_exact = 1), reasons = "exact FK naming",
    overlap = overlap, n_from = n_from, n_to = n_to
  )
}

test_that("rel_rows carries the evidence the table columns are built from", {
  skip_if_not_installed("shiny")
  # Regression: the Child rows, Parent rows and Overlap % columnDefs
  # shipped without the columns they index, so idx() returned integer(0)
  rels <- list(
    make_rel("visits", "client_id", "clients", "client_id", "naming",
             overlap = 0.97, n_from = 2688L, n_to = 1045L),
    make_rel("empty_t", "client_id", "clients", "client_id", "naming",
             overlap = NA_real_, n_from = 0L, n_to = 1045L)
  )
  shiny::testServer(
    mod_relationships_server,
    args = list(
      all_tables_rv = shiny::reactiveVal(list(visits = data.frame(client_id = 1:3))),
      all_rels_rv = shiny::reactive(rels),
      false_positives_rv = shiny::reactiveVal(character(0)),
      conf_overrides_rv = shiny::reactiveVal(list()),
      confirmed_rels_rv = shiny::reactiveVal(list())
    ),
    {
      session$setInputs(source_filter = "all", show_low = TRUE)
      session$flushReact()
      rows <- rel_rows()
      expect_true(all(c("overlap", "n_from", "n_to") %in% names(rows)))
      expect_equal(rows$n_from, c(2688L, 0L))
      expect_equal(rows$n_to, c(1045L, 1045L))
      expect_equal(rows$overlap[1], 0.97)
      expect_true(is.na(rows$overlap[2]))
    }
  )
})
