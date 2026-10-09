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

rel_fixture <- function() {
  list(
    make_rel("visits", "client_id", "clients", "client_id", "naming"),
    make_rel("visits", "site_id", "sites", "site_id", "naming", confirmed = TRUE),
    make_rel("visits", "staff_id", "staff", "staff_id", "schema"),
    make_rel("visits", "note_id", "notes", "note_id", "manual")
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

test_that("'To review only' keeps just the links still awaiting a decision", {
  skip_if_not_installed("shiny")
  rels <- rel_fixture()
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
      session$setInputs(source_filter = "all", show_low = TRUE, hide_reviewed = FALSE)
      session$flushReact()
      expect_equal(length(shown_rels_rv()), 4)

      # Detected only: confirmed, declared and manual all drop out
      session$setInputs(hide_reviewed = TRUE)
      session$flushReact()
      kept <- shown_rels_rv()
      expect_equal(length(kept), 1)
      expect_equal(kept[[1]]$from_col, "client_id")

      # Survival check: turning it off brings the other three back, so an
      # over-eager filter fails here rather than only an under-eager one
      session$setInputs(hide_reviewed = FALSE)
      session$flushReact()
      expect_equal(length(shown_rels_rv()), 4)
    }
  )
})

test_that("the source filter and 'To review only' combine", {
  skip_if_not_installed("shiny")
  rels <- rel_fixture()
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
      # Declared plus to-review is empty: nothing is both at once
      session$setInputs(source_filter = "declared", show_low = TRUE, hide_reviewed = TRUE)
      session$flushReact()
      expect_equal(length(shown_rels_rv()), 0)
      # And the table reports no rows rather than pretending to have some
      expect_null(rel_rows())
    }
  )
})

test_that("the row data carries the evidence the table shows", {
  skip_if_not_installed("shiny")
  rels <- rel_fixture()
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
      session$setInputs(source_filter = "all", show_low = TRUE, hide_reviewed = FALSE)
      session$flushReact()
      df <- rel_df()
      expect_true(all(
        c("Child rows", "Parent rows", "Overlap %", "Evidence") %in% names(df)
      ))
      expect_equal(nrow(df), 4)
    }
  )
})
