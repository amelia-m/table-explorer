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
      confirmed_rels_rv = shiny::reactiveVal(list()),
      shared_cols_rv = shiny::reactive(list())
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
      confirmed_rels_rv = shiny::reactiveVal(list()),
      shared_cols_rv = shiny::reactive(list())
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
      confirmed_rels_rv = shiny::reactiveVal(list()),
      shared_cols_rv = shiny::reactive(list())
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
      confirmed_rels_rv = shiny::reactiveVal(list()),
      shared_cols_rv = shiny::reactive(list())
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

# ── Shared columns (joinable, not foreign keys) ──────────────
# Invented tables: incident_id / inspection_id are unique, so they are keys
# and belong to FK detection; incident_year is a key in neither side.

shared_fixture_tables <- function() {
  list(
    incidents = data.frame(
      incident_id = 1:6,
      incident_year = c(2019L, 2019L, 2020L, 2020L, 2021L, 2021L)
    ),
    inspections = data.frame(
      inspection_id = 1:5,
      incident_year = c(2019L, 2020L, 2021L, 2021L, 2019L)
    )
  )
}

shared_settings <- function(...) {
  utils::modifyList(
    list(method = "both", min_conf = "medium", value_overlap = TRUE),
    list(...)
  )
}

shared_cache_env <- function() {
  e <- new.env(parent = emptyenv())
  e$result <- list()
  e$handled_id <- NULL
  e
}

test_that("shared_columns_for_scan reports the shared column with its counts", {
  found <- shared_columns_for_scan(
    shared_fixture_tables(),
    list(id = 1L, scope = "all", strategy = "auto"),
    shared_settings(),
    shared_cache_env()
  )
  expect_length(found, 1)
  expect_equal(found[[1]]$column, "incident_year")
  expect_equal(found[[1]]$from_table, "incidents")
  expect_equal(found[[1]]$to_table, "inspections")
  expect_equal(found[[1]]$n_distinct_from, 3L)
  expect_equal(found[[1]]$n_distinct_to, 3L)
  expect_equal(found[[1]]$n_shared, 3L)
  expect_equal(found[[1]]$overlap, 1)
  expect_true(found[[1]]$contained)
})

test_that("settings that ask for no value comparison skip the scan and say why", {
  tbls <- shared_fixture_tables()
  naming <- shared_columns_for_scan(
    tbls,
    list(id = 1L, scope = "all", strategy = "naming_only"),
    shared_settings(),
    shared_cache_env()
  )
  expect_length(naming, 0)
  expect_match(attr(naming, "skipped"), "naming only")

  no_overlap <- shared_columns_for_scan(
    tbls,
    list(id = 1L, scope = "all", strategy = "auto"),
    shared_settings(value_overlap = FALSE),
    shared_cache_env()
  )
  expect_length(no_overlap, 0)
  expect_match(attr(no_overlap, "skipped"), "value overlap")
})

test_that("the cached scan is reused per request id and filtered to loaded tables", {
  cache <- shared_cache_env()
  req1 <- list(id = 7L, scope = "all", strategy = "auto")
  expect_length(
    shared_columns_for_scan(
      shared_fixture_tables(), req1, shared_settings(), cache
    ),
    1
  )

  # A third table that would add two more pairs if a scan ran again. Same
  # request id, so it must not: this is the unrelated-change case.
  tbls <- shared_fixture_tables()
  tbls$reviews <- data.frame(
    review_id = 1:4,
    incident_year = c(2019L, 2020L, 2021L, 2019L)
  )
  expect_length(
    shared_columns_for_scan(tbls, req1, shared_settings(), cache),
    1
  )

  # A new request id does scan, and picks up the pairs the new table brings
  req2 <- list(id = 8L, scope = "all", strategy = "auto")
  expect_length(
    shared_columns_for_scan(tbls, req2, shared_settings(), cache),
    3
  )

  # Dropping a table filters its rows out of the cached result, no rescan
  expect_length(
    shared_columns_for_scan(
      tbls[c("incidents", "inspections")], req2, shared_settings(), cache
    ),
    1
  )
})

shared_found_fixture <- function() {
  list(
    list(
      from_table = "incidents", to_table = "inspections",
      column = "incident_year", n_shared = 3L,
      n_distinct_from = 3L, n_distinct_to = 4L,
      overlap = 0.75, contained = FALSE
    ),
    list(
      from_table = "incidents", to_table = "reviews",
      column = "county_code", n_shared = 12L,
      n_distinct_from = 12L, n_distinct_to = 40L,
      overlap = 1, contained = TRUE
    )
  )
}

shared_server_args <- function(found) {
  list(
    all_tables_rv = shiny::reactiveVal(
      list(incidents = data.frame(incident_year = 1:3))
    ),
    all_rels_rv = shiny::reactive(list()),
    false_positives_rv = shiny::reactiveVal(character(0)),
    conf_overrides_rv = shiny::reactiveVal(list()),
    confirmed_rels_rv = shiny::reactiveVal(list()),
    shared_cols_rv = shiny::reactive(found)
  )
}

test_that("the shared-column rows reaching the table carry the counts", {
  skip_if_not_installed("shiny")
  shiny::testServer(
    mod_relationships_server,
    args = shared_server_args(shared_found_fixture()),
    {
      session$flushReact()
      rows <- shared_rows()
      expect_equal(rows$table_a, c("incidents", "incidents"))
      expect_equal(rows$column, c("incident_year", "county_code"))
      expect_equal(rows$n_distinct_a, c(3L, 12L))
      expect_equal(rows$n_distinct_b, c(4L, 40L))
      expect_equal(rows$n_shared, c(3L, 12L))

      df <- shared_df()
      expect_true(all(
        c(
          "Table A", "Table B", "Column", "Distinct in A", "Distinct in B",
          "Shared values", "Overlap %", "Contained"
        ) %in%
          names(df)
      ))
      expect_equal(df$`Shared values`, c("3", "12"))
      expect_equal(df$`Overlap %`, c("75%", "100%"))
      expect_equal(df$Contained, c("no", "yes"))
      # Hidden sort columns are zero-padded so DT sorts them as numbers
      expect_equal(df$a_sort, c("000000000003", "000000000012"))
      expect_equal(df$shared_sort, c("000000000003", "000000000012"))
      expect_equal(df$overlap_sort, c("075", "100"))
    }
  )
})

test_that("no shared columns renders one quiet line, and says if none were sought", {
  skip_if_not_installed("shiny")
  html_of <- function(x) paste(as.character(x$html), collapse = " ")

  shiny::testServer(
    mod_relationships_server,
    args = shared_server_args(list()),
    {
      session$flushReact()
      expect_null(shared_rows())
      html <- html_of(output$shared_cols_ui)
      expect_match(html, "No shared columns")
      # No table at all, empty or otherwise
      expect_false(grepl("shared_table", html, fixed = TRUE))
    }
  )

  # Zero because nothing was looked for is a different answer, and says so
  shiny::testServer(
    mod_relationships_server,
    args = shared_server_args(
      structure(list(), skipped = "the last scan was naming only")
    ),
    {
      session$flushReact()
      html <- html_of(output$shared_cols_ui)
      expect_match(html, "not scanned")
      expect_match(html, "naming only")
    }
  )
})
