# ============================================================
# Tests for file_readers.R - File Format Readers
# ============================================================

# ── %||% operator ────────────────────────────────────────────

test_that("%||% returns a when a is non-null and non-empty", {
  expect_equal("hello" %||% "default", "hello")
  expect_equal(42 %||% 0, 42)
})

test_that("%||% returns b when a is NULL or empty", {
  expect_equal(NULL %||% "fallback", "fallback")
  expect_equal("" %||% "fallback", "fallback")
  expect_equal(character(0) %||% "fallback", "fallback")
})

# ── supported_extensions ─────────────────────────────────────

test_that("supported_extensions includes core formats", {
  expect_true(".csv" %in% supported_extensions)
  expect_true(".tsv" %in% supported_extensions)
  expect_true(".xlsx" %in% supported_extensions)
  expect_true(".json" %in% supported_extensions)
  expect_true(".parquet" %in% supported_extensions)
  expect_true(".rds" %in% supported_extensions)
  expect_true(".mdb" %in% supported_extensions)
})

test_that("supported_extensions are all lowercase with dot prefix", {
  for (ext in supported_extensions) {
    expect_true(startsWith(ext, "."), info = paste("Missing dot:", ext))
    expect_equal(ext, tolower(ext), info = paste("Not lowercase:", ext))
  }
})

# ── CSV reading via read_table_file ──────────────────────────

test_that("read_table_file reads CSV files", {
  skip_if_not(dir.exists(sample_data_dir), "sample_data directory not found")

  path <- file.path(sample_data_dir, "customers.csv")
  result <- read_table_file(path, "customers.csv")

  expect_true(is.list(result))
  expect_true("tables" %in% names(result))
  expect_true("customers" %in% names(result$tables))
  df <- result$tables[["customers"]]
  expect_true(is.data.frame(df))
  expect_gt(nrow(df), 0)
})

test_that("read_table_file returns empty for unsupported extension", {
  errors <- character(0)
  notify <- function(msg) errors <<- c(errors, msg)

  # Create a temp file with unknown extension
  tmp <- tempfile(fileext = ".xyz")
  writeLines("test", tmp)
  on.exit(unlink(tmp))

  result <- read_table_file(tmp, "test.xyz", notify)
  expect_equal(length(result$tables), 0)
  expect_true(length(errors) > 0)
  expect_true(any(grepl("Unsupported", errors)))
})

test_that("read_table_file handles read errors gracefully", {
  errors <- character(0)
  notify <- function(msg) errors <<- c(errors, msg)

  tmp <- tempfile(fileext = ".csv")
  writeLines("this,is\nnot,properly,formatted\na,b,c,d", tmp)
  on.exit(unlink(tmp))

  result <- read_table_file(tmp, "broken.csv", notify)
  # Should either return data (lenient parsing) or catch error
  expect_true(is.list(result))
  expect_true("tables" %in% names(result))
})

# ── TSV reading ──────────────────────────────────────────────

test_that("read_table_file reads TSV files", {
  tmp <- tempfile(fileext = ".tsv")
  write.table(
    data.frame(id = 1:3, name = c("alice", "bob", "carol")),
    tmp,
    sep = "\t",
    row.names = FALSE
  )
  on.exit(unlink(tmp))

  result <- read_table_file(tmp, "people.tsv")
  expect_true("people" %in% names(result$tables))
  expect_equal(nrow(result$tables[["people"]]), 3)
})

# ── RDS reading ──────────────────────────────────────────────

test_that("read_rds_file reads a data frame", {
  tmp <- tempfile(fileext = ".rds")
  df <- data.frame(x = 1:5, y = letters[1:5])
  saveRDS(df, tmp)
  on.exit(unlink(tmp))

  result <- read_rds_file(tmp, "test.rds", message)
  expect_true("test" %in% names(result$tables))
  expect_equal(nrow(result$tables[["test"]]), 5)
})

test_that("read_rds_file notifies for non-data-frame", {
  tmp <- tempfile(fileext = ".rds")
  saveRDS(list(a = 1, b = 2), tmp)
  on.exit(unlink(tmp))

  errors <- character(0)
  result <- read_rds_file(tmp, "test.rds", function(msg) {
    errors <<- c(errors, msg)
  })
  expect_equal(length(result$tables), 0)
  expect_true(any(grepl("does not contain", errors)))
})

# ── RData reading ────────────────────────────────────────────

test_that("read_rdata_file reads data frames from .RData", {
  tmp <- tempfile(fileext = ".rdata")
  my_df <- data.frame(a = 1:3, b = c("x", "y", "z"))
  another_df <- data.frame(c = 4:6)
  save(my_df, another_df, file = tmp)
  on.exit(unlink(tmp))

  result <- read_rdata_file(tmp, "test.rdata", message)
  expect_true("my_df" %in% names(result$tables))
  expect_true("another_df" %in% names(result$tables))
  expect_equal(nrow(result$tables[["my_df"]]), 3)
})

test_that("read_rdata_file notifies when no data frames found", {
  tmp <- tempfile(fileext = ".rdata")
  my_list <- list(a = 1)
  my_vec <- 1:10
  save(my_list, my_vec, file = tmp)
  on.exit(unlink(tmp))

  errors <- character(0)
  result <- read_rdata_file(tmp, "test.rdata", function(msg) {
    errors <<- c(errors, msg)
  })
  expect_equal(length(result$tables), 0)
  expect_true(any(grepl("No data frames", errors)))
})

# ── JSON reading ─────────────────────────────────────────────

test_that("read_json_file reads array-of-objects JSON", {
  skip_if_not_installed("jsonlite")

  tmp <- tempfile(fileext = ".json")
  jsonlite::write_json(
    data.frame(id = 1:3, name = c("a", "b", "c")),
    tmp
  )
  on.exit(unlink(tmp))

  result <- read_json_file(tmp, "items.json", message)
  expect_true("items" %in% names(result$tables))
  expect_equal(nrow(result$tables[["items"]]), 3)
})

test_that("read_json_file notifies for non-tabular JSON", {
  skip_if_not_installed("jsonlite")

  tmp <- tempfile(fileext = ".json")
  writeLines('{"key": "value", "nested": {"a": 1}}', tmp)
  on.exit(unlink(tmp))

  errors <- character(0)
  result <- read_json_file(tmp, "bad.json", function(msg) {
    errors <<- c(errors, msg)
  })
  expect_equal(length(result$tables), 0)
})

# ── Schema file parsing ─────────────────────────────────────

test_that("parse_schema_file reads the project schema.json", {
  skip_if_not_installed("jsonlite")
  skip_if_not(file.exists(schema_json_path), "schema.json not found")

  result <- parse_schema_file(schema_json_path, "schema.json")

  # Should have tables
  expect_true(length(result$tables) > 0)
  expect_true("customers" %in% names(result$tables))
  expect_true("orders" %in% names(result$tables))
  expect_true("products" %in% names(result$tables))

  # Should detect inline FK relationships
  expect_true(length(result$relationships) > 0)

  # Check relationship structure
  for (r in result$relationships) {
    expect_true(nzchar(r$from_table))
    expect_true(nzchar(r$from_col))
    expect_true(nzchar(r$to_table))
    expect_true(nzchar(r$to_col))
    expect_equal(r$detected_by, "schema")
    expect_equal(r$confidence, "high")
  }
})

test_that("parse_schema_file extracts FK from inline definitions", {
  skip_if_not_installed("jsonlite")
  skip_if_not(file.exists(schema_json_path), "schema.json not found")

  result <- parse_schema_file(schema_json_path, "schema.json")

  # orders.customer_id -> customers.customer_id should exist
  fk_descs <- vapply(
    result$relationships,
    function(r) {
      paste(r$from_table, r$from_col, r$to_table, r$to_col, sep = ".")
    },
    character(1)
  )

  expect_true(any(grepl("orders.*customer_id.*customers", fk_descs)))
  expect_true(any(grepl("orders.*product_id.*products", fk_descs)))
})

test_that("parse_schema_file handles YAML format", {
  skip_if_not_installed("yaml")

  tmp <- tempfile(fileext = ".yaml")
  writeLines(
    c(
      "tables:",
      "  - name: users",
      "    columns:",
      "      - name: user_id",
      "      - name: email",
      "relationships:",
      "  - from_table: orders",
      "    from_column: user_id",
      "    to_table: users",
      "    to_column: user_id"
    ),
    tmp
  )
  on.exit(unlink(tmp))

  result <- parse_schema_file(tmp, "schema.yaml")
  expect_true("users" %in% names(result$tables))
  expect_true(length(result$relationships) == 1)
  expect_equal(result$relationships[[1]]$from_table, "orders")
  expect_equal(result$relationships[[1]]$to_table, "users")
})

test_that("parse_schema_file notifies for unsupported format", {
  errors <- character(0)
  tmp <- tempfile(fileext = ".txt")
  writeLines("not a schema", tmp)
  on.exit(unlink(tmp))

  result <- parse_schema_file(tmp, "schema.txt", function(msg) {
    errors <<- c(errors, msg)
  })
  expect_equal(length(result$tables), 0)
  expect_true(any(grepl("Unsupported", errors)))
})

# ── Excel/Haven/Parquet graceful failure ─────────────────────

test_that("read_excel_file notifies when readxl missing", {
  # Only test if readxl is NOT installed
  skip_if(requireNamespace("readxl", quietly = TRUE), "readxl is installed")
  errors <- character(0)
  result <- read_excel_file("/fake/path.xlsx", "test.xlsx", function(msg) {
    errors <<- c(errors, msg)
  })
  expect_equal(length(result$tables), 0)
  expect_true(any(grepl("readxl", errors)))
})

test_that("read_parquet_file notifies when arrow missing", {
  skip_if(requireNamespace("arrow", quietly = TRUE), "arrow is installed")
  errors <- character(0)
  result <- read_parquet_file(
    "/fake/path.parquet",
    "test.parquet",
    function(msg) errors <<- c(errors, msg)
  )
  expect_equal(length(result$tables), 0)
  expect_true(any(grepl("arrow", errors)))
})

test_that("read_haven_file notifies when haven missing", {
  skip_if(requireNamespace("haven", quietly = TRUE), "haven is installed")
  errors <- character(0)
  result <- read_haven_file("/fake/path.sav", "test.sav", "sav", function(msg) {
    errors <<- c(errors, msg)
  })
  expect_equal(length(result$tables), 0)
  expect_true(any(grepl("haven", errors)))
})

# ── App export detection ─────────────────────────────────────

test_that("detect_app_export recognises this app's CSV exports", {
  rels <- data.frame(
    from_table = "orders",
    from_col = "customer_id",
    to_table = "customers",
    to_col = "customer_id",
    detected_by = "naming",
    confidence = "high",
    score = 1,
    signals = "naming_exact",
    reasons = "exact FK naming"
  )
  details <- data.frame(
    table = "orders",
    table_rows = 5,
    table_cols = 3,
    column = "order_id",
    type = "integer",
    non_null = 5,
    unique_vals = 5,
    is_pk = TRUE,
    is_fk = FALSE
  )
  expect_equal(detect_app_export(rels), "relationships list")
  rels$status <- "confirmed"
  expect_equal(detect_app_export(rels), "relationships list")
  rels$source <- "detected"
  expect_equal(detect_app_export(rels), "relationships list")
  expect_equal(detect_app_export(details), "table details")
  expect_null(detect_app_export(data.frame(customer_id = 1:3, name = "a")))
  # A real mapping table sharing some export column names is still data
  mapping <- data.frame(
    from_table = "a",
    from_col = "x",
    to_table = "b",
    to_col = "y",
    owner = "team"
  )
  expect_null(detect_app_export(mapping))
})

# ── Relationships declared in Access files ───────────────────

msys_rows <- function() {
  data.frame(
    szRelationship = c("svc", "site", "sys"),
    grbit = c(0L, 2L, 0L),
    ccolumn = 1L,
    icolumn = 0L,
    szObject = c("tbl Visits", "tbl Visits", "MSysNavPaneGroups"),
    szColumn = c("ServiceID", "SiteID", "GroupID"),
    szReferencedObject = c(
      "tlk_services",
      "tlk_sites",
      "MSysNavPaneGroupCategories"
    ),
    szReferencedColumn = c("ID", "ID", "Id"),
    stringsAsFactors = FALSE
  )
}

test_that("MSysRelationships rows become declared links with cleaned names", {
  rels <- access_relationship_rels(msys_rows())
  expect_length(rels, 2)
  expect_equal(
    vapply(rels, rel_key, ""),
    c(
      "tbl_visits|service_id|tlk_services|id",
      "tbl_visits|site_id|tlk_sites|id"
    )
  )
  expect_true(all(vapply(rels, `[[`, "", "detected_by") == "schema"))
  expect_match(rels[[1]]$reasons, "integrity enforced")
  expect_match(rels[[2]]$reasons, "not enforced")
  expect_length(access_relationship_rels(msys_rows()[0, ]), 0)
})

test_that("relationships are read from a real .accdb with mdbtools", {
  skip_if(!nzchar(Sys.which("mdb-export")), "mdbtools not installed")
  path <- test_path("fixtures", "declared_rels.accdb")
  rels <- access_relationships(path, notify_fn = function(...) NULL)
  expect_setequal(
    vapply(rels, rel_key, ""),
    c(
      "tbl_visits|service_id|tlk_services|id",
      "tbl_visits|site_id|tlk_sites|id"
    )
  )
})

test_that("declared links are cleaned and de-duplicated when merged", {
  a <- list(
    from_table = "Orders",
    from_col = "CustomerID",
    to_table = "Customers",
    to_col = "ID"
  )
  merged <- merge_declared_rels(list(), list(a, a))
  expect_length(merged, 1)
  expect_equal(rel_key(merged[[1]]), "orders|customer_id|customers|id")
  expect_length(merge_declared_rels(merged, list(a)), 1)
})

test_that("the Access jar set pins the HSQLDB that UCanAccess expects", {
  # HSQLDB 2.7 refuses to resolve UCanAccess's Java routines without
  # hsqldb.method_class_names, which floods the console with
  # "user lacks privilege or object not found" for every Access function
  files <- vapply(ucanaccess_jars, `[[`, character(1), "file")
  expect_true(any(grepl("^hsqldb-2[.]5[.]", files)))
  expect_false(any(grepl("^hsqldb-2[.][67][.]", files)))
  # Every jar is fetched from Maven Central over https
  urls <- vapply(ucanaccess_jars, `[[`, character(1), "url")
  expect_true(all(grepl("^https://repo1[.]maven[.]org/", urls)))
  # The file named in each entry is the one the URL ends with
  expect_equal(basename(urls), files)
})

# ── Excel column type guessing ───────────────────────────────
# readxl's default guesses each column's type from its first 1000 rows, so a
# value that does not fit the guess further down is read as missing without
# a word. These pin the three settings and the warning that replaces silence.

# A workbook whose `code` column holds numbers for 1,500 rows and then one
# text cell, the shape that loses data under readxl's default. Written with
# openxlsx so the numbers are stored as numbers, as a spreadsheet holds them.
late_text_xlsx <- function() {
  skip_if_not_installed("readxl")
  skip_if_not_installed("openxlsx")
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "s")
  openxlsx::writeData(wb, "s", data.frame(id = 1:1501, code = c(1:1500, NA)))
  openxlsx::writeData(wb, "s", "A-17", startCol = 2, startRow = 1502)
  openxlsx::saveWorkbook(wb, path)
  path
}

test_that("guessing from the first 1000 rows loses a late text value, and says so", {
  path <- late_text_xlsx()
  msgs <- character(0)
  res <- read_excel_file(
    path,
    "late.xlsx",
    function(m) msgs <<- c(msgs, m),
    excel_types = "sample"
  )
  df <- res$tables[["late"]]
  expect_true(is.numeric(df$code))
  expect_true(is.na(df$code[1501]))
  # Two messages: the sheet is longer than the guess window, and one value
  # did not fit the guess
  expect_length(msgs, 2L)
  expect_true(any(grepl("has 1,501 rows", msgs, fixed = TRUE)))
  expect_true(any(grepl("1 value could not be read", msgs, fixed = TRUE)))
})

test_that("a sheet within the guess window loads without a row-count notice", {
  skip_if_not_installed("readxl")
  skip_if_not_installed("openxlsx")
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "s")
  openxlsx::writeData(wb, "s", data.frame(id = 1:1000, code = 1:1000))
  openxlsx::saveWorkbook(wb, path)
  msgs <- character(0)
  read_excel_file(
    path,
    "short.xlsx",
    function(m) msgs <<- c(msgs, m),
    excel_types = "sample"
  )
  expect_length(msgs, 0L)
})

test_that("guessing from every row keeps the late text value", {
  path <- late_text_xlsx()
  msgs <- character(0)
  res <- read_excel_file(
    path,
    "late.xlsx",
    function(m) msgs <<- c(msgs, m),
    excel_types = "all"
  )
  expect_identical(res$tables[["late"]]$code[1501], "A-17")
  expect_length(msgs, 0L)
})

test_that("reading every column as text keeps everything as text", {
  path <- late_text_xlsx()
  res <- read_excel_file(
    path,
    "late.xlsx",
    function(m) NULL,
    excel_types = "text"
  )
  df <- res$tables[["late"]]
  expect_true(all(vapply(df, is.character, logical(1))))
  expect_identical(df$code[c(1, 1501)], c("1", "A-17"))
})

test_that("read_table_file guesses from the first 1000 rows by default, and says so", {
  # The default favours a fast first load (Amelia, 2026-10-16); the notice is
  # what makes that safe. This pins that a caller naming nothing reaches the
  # Excel reader with the fast setting and is told about it.
  path <- late_text_xlsx()
  msgs <- character(0)
  res <- read_table_file(path, "late.xlsx", function(m) msgs <<- c(msgs, m))
  expect_true(is.na(res$tables[["late"]]$code[1501]))
  expect_true(any(grepl("guessed from the first", msgs, fixed = TRUE)))
})

# ── Hidden Excel sheets ──────────────────────────────────────
# readxl lists hidden and very hidden sheets with the visible ones, so a
# workbook that shows one tab in Excel loaded as several tables with no
# explanation. The reader still loads every sheet unless told otherwise
# (Amelia, 2026-10-21: "don't skip hidden by default"); the upload module asks
# which hidden sheets to load. These pin the reader's half of that.

# One visible sheet, one hidden, one very hidden (settable only from VBA in
# Excel). The hidden one's name needs XML escaping in workbook.xml.
hidden_sheets_xlsx <- function() {
  skip_if_not_installed("readxl")
  skip_if_not_installed("openxlsx")
  path <- tempfile(fileext = ".xlsx")
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Shown")
  openxlsx::addWorksheet(wb, "R&D <old>", visible = FALSE)
  openxlsx::addWorksheet(wb, "Lookup", visible = "veryHidden")
  openxlsx::writeData(wb, "Shown", data.frame(id = 1:3))
  openxlsx::writeData(wb, "R&D <old>", data.frame(x = 1:2))
  openxlsx::writeData(wb, "Lookup", data.frame(y = 1:4))
  openxlsx::saveWorkbook(wb, path)
  path
}

test_that("excel_sheet_visibility reads each sheet's state, unescaping names", {
  path <- hidden_sheets_xlsx()
  vis <- excel_sheet_visibility(path)
  expect_identical(
    vis,
    c(Shown = "visible", `R&D <old>` = "hidden", Lookup = "veryHidden")
  )
  expect_identical(names(vis), readxl::excel_sheets(path))
})

test_that("excel_sheet_visibility returns NULL for a file that is not a workbook zip", {
  path <- tempfile(fileext = ".xlsx")
  writeLines("not a zip", path)
  expect_null(excel_sheet_visibility(path))
})

test_that("parse_workbook_sheets accepts prefixed tags, either quote and numeric entities", {
  xml <- paste0(
    "<x:workbook><x:sheets>",
    "<x:sheet name=\"A&#38;B\" sheetId=\"1\" r:id=\"rId1\"/>",
    "<x:sheet name='Old &#x2013; copy' state='hidden' sheetId='2'/>",
    "<x:sheet name=\"&amp;lt;raw&amp;gt;\" state=\"veryHidden\"/>",
    "</x:sheets></x:workbook>"
  )
  expect_identical(
    parse_workbook_sheets(xml),
    stats::setNames(
      c("visible", "hidden", "veryHidden"),
      c("A&B", "Old – copy", "&lt;raw&gt;")
    )
  )
  # The <sheets> container is not mistaken for a sheet
  expect_null(parse_workbook_sheets("<workbook><sheets></sheets></workbook>"))
})

test_that("include_hidden = FALSE says so when hidden sheets cannot be told apart", {
  path <- hidden_sheets_xlsx()
  local_mocked_bindings(excel_sheet_visibility = function(path) NULL)
  msgs <- character(0)
  res <- read_excel_file(
    path,
    "book.xlsx",
    function(m) msgs <<- c(msgs, m),
    include_hidden = FALSE
  )
  expect_length(res$tables, 3L)
  expect_match(msgs, "Could not tell which sheets in 'book.xlsx' are hidden")
})

test_that("read_table_file loads hidden and very hidden sheets by default", {
  path <- hidden_sheets_xlsx()
  res <- read_table_file(path, "book.xlsx", function(m) NULL)
  expect_identical(
    vapply(res$tables, nrow, integer(1), USE.NAMES = FALSE),
    c(3L, 2L, 4L)
  )
})

test_that("include_hidden = FALSE loads only the visible sheet, under the file's name", {
  path <- hidden_sheets_xlsx()
  res <- read_excel_file(
    path,
    "book.xlsx",
    function(m) NULL,
    include_hidden = FALSE
  )
  # One sheet read, so it is named as a one-sheet workbook is
  expect_named(res$tables, "book")
  expect_equal(res$tables[["book"]]$id, c(1, 2, 3))
})

test_that("include_hidden as names loads the visible sheets and only those hidden ones", {
  path <- hidden_sheets_xlsx()
  res <- read_excel_file(
    path,
    "book.xlsx",
    function(m) NULL,
    include_hidden = "R&D <old>"
  )
  expect_identical(
    vapply(res$tables, nrow, integer(1), USE.NAMES = FALSE),
    c(3L, 2L)
  )
})

# Runs mod_upload_server, adds `path` as book.xlsx, then `answer` (a call on
# `session`), and returns the row counts of the tables that loaded.
upload_hidden_and_answer <- function(path, answer) {
  all_tables <- shiny::reactiveVal(list())
  shiny::testServer(
    mod_upload_server,
    args = list(
      all_tables_rv = all_tables,
      rename_log_rv = shiny::reactiveVal(data.frame()),
      schema_rels_rv = shiny::reactiveVal(list()),
      table_meta_rv = shiny::reactiveVal(list()),
      fk_cache = new.env()
    ),
    {
      session$setInputs(
        excel_types = "sample",
        data_files = data.frame(
          name = "book.xlsx",
          size = file.size(path),
          type = "",
          datapath = path,
          stringsAsFactors = FALSE
        )
      )
      answer(session)
    }
  )
  unname(vapply(shiny::isolate(all_tables()), nrow, integer(1)))
}

test_that("'Load visible sheets only' skips every hidden sheet", {
  path <- hidden_sheets_xlsx()
  counts <- upload_hidden_and_answer(
    path,
    function(session) session$setInputs(hidden_visible_only = 1)
  )
  expect_identical(counts, 3L)
})

test_that("upload waits for the hidden-sheet choice, then loads what was ticked", {
  path <- hidden_sheets_xlsx()
  all_tables <- shiny::reactiveVal(list())
  shiny::testServer(
    mod_upload_server,
    args = list(
      all_tables_rv = all_tables,
      rename_log_rv = shiny::reactiveVal(data.frame()),
      schema_rels_rv = shiny::reactiveVal(list()),
      table_meta_rv = shiny::reactiveVal(list()),
      fk_cache = new.env()
    ),
    {
      session$setInputs(
        excel_types = "sample",
        data_files = data.frame(
          name = "book.xlsx",
          size = file.size(path),
          type = "",
          datapath = path,
          stringsAsFactors = FALSE
        )
      )
      # Nothing is read until the user answers
      expect_length(all_tables(), 0L)
      expect_named(pending_upload_rv()$hidden[["1"]], c("R&D <old>", "Lookup"))
      session$setInputs(hidden_pick_1 = "Lookup", hidden_confirm = 1)
      expect_null(pending_upload_rv())
      expect_identical(
        unname(vapply(all_tables(), nrow, integer(1))),
        c(3L, 4L)
      )
    }
  )
})

test_that("an unknown Excel type setting is refused", {
  skip_if_not_installed("readxl")
  expect_error(
    read_excel_file(
      "x.xlsx",
      "x.xlsx",
      function(m) NULL,
      excel_types = "guess"
    ),
    "should be one of"
  )
})
