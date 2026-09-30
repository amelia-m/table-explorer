# ============================================================
# utils_file_readers.R - File Format Readers
# ============================================================
#
# @noRd

# ── Supported file extensions ──────────────────────────────────

supported_extensions <- c(
  ".csv",
  ".tsv",
  ".txt",
  ".xlsx",
  ".xls",
  ".xlsm",
  ".ods",
  ".parquet",
  ".json",
  ".ndjson",
  ".sav",
  ".por",
  ".sas7bdat",
  ".xpt",
  ".dta",
  ".rds",
  ".rdata",
  ".rda",
  ".mdb",
  ".accdb"
)

# ── Multi-format file reader dispatcher ────────────────────────

read_table_file <- function(path, name, notify_fn = message) {
  ext <- tolower(tools::file_ext(name))
  if (!startsWith(ext, ".")) {
    ext <- paste0(".", ext)
  }

  result <- tryCatch(
    switch(
      ext,
      ".csv" = list(
        tables = setNames(
          list(
            read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
          ),
          tools::file_path_sans_ext(name)
        )
      ),

      ".tsv" = ,
      ".txt" = list(
        tables = setNames(
          list(
            read.delim(path, stringsAsFactors = FALSE, check.names = FALSE)
          ),
          tools::file_path_sans_ext(name)
        )
      ),

      ".xlsx" = ,
      ".xls" = ,
      ".xlsm" = read_excel_file(path, name, notify_fn),

      ".ods" = read_ods_file(path, name, notify_fn),

      ".parquet" = read_parquet_file(path, name, notify_fn),

      ".json" = read_json_file(path, name, notify_fn),

      ".ndjson" = read_ndjson_file(path, name, notify_fn),

      ".sav" = read_haven_file(path, name, "sav", notify_fn),
      ".por" = read_haven_file(path, name, "por", notify_fn),
      ".sas7bdat" = read_haven_file(path, name, "sas", notify_fn),
      ".xpt" = read_haven_file(path, name, "xpt", notify_fn),
      ".dta" = read_haven_file(path, name, "dta", notify_fn),

      ".rds" = read_rds_file(path, name, notify_fn),
      ".rdata" = ,
      ".rda" = read_rdata_file(path, name, notify_fn),

      ".mdb" = ,
      ".accdb" = {
        tbls <- read_access_db(path, notify_fn)
        list(
          tables = tbls,
          relationships = if (length(tbls) > 0) {
            access_relationships(path, notify_fn)
          } else {
            list()
          }
        )
      },

      {
        notify_fn(paste0("Unsupported file format: ", ext))
        list(tables = list())
      }
    ),
    error = function(e) {
      notify_fn(paste0("Error reading ", name, ": ", conditionMessage(e)))
      list(tables = list())
    }
  )

  if (is.null(result$tables)) {
    result$tables <- list()
  }
  result
}

# ── Excel reader ───────────────────────────────────────────────

read_excel_file <- function(path, name, notify_fn) {
  if (!requireNamespace("readxl", quietly = TRUE)) {
    notify_fn(
      "Install the 'readxl' package to read Excel files: install.packages('readxl')"
    )
    return(list(tables = list()))
  }
  sheets <- readxl::excel_sheets(path)
  base <- tools::file_path_sans_ext(name)
  tbls <- list()
  for (s in sheets) {
    df <- tryCatch(
      as.data.frame(readxl::read_excel(path, sheet = s)),
      error = function(e) {
        notify_fn(paste0(
          "Could not read sheet '",
          s,
          "': ",
          conditionMessage(e)
        ))
        NULL
      }
    )
    if (!is.null(df) && nrow(df) > 0) {
      tname <- if (length(sheets) == 1) {
        base
      } else {
        paste0(base, "_", janitor::make_clean_names(s))
      }
      tbls[[tname]] <- df
    }
  }
  list(tables = tbls)
}

# ── ODS reader ─────────────────────────────────────────────────

read_ods_file <- function(path, name, notify_fn) {
  if (!requireNamespace("readODS", quietly = TRUE)) {
    notify_fn(
      "Install the 'readODS' package to read ODS files: install.packages('readODS')"
    )
    return(list(tables = list()))
  }
  sheets <- readODS::list_ods_sheets(path)
  base <- tools::file_path_sans_ext(name)
  tbls <- list()
  for (s in sheets) {
    df <- tryCatch(
      as.data.frame(readODS::read_ods(path, sheet = s)),
      error = function(e) {
        notify_fn(paste0(
          "Could not read sheet '",
          s,
          "': ",
          conditionMessage(e)
        ))
        NULL
      }
    )
    if (!is.null(df) && nrow(df) > 0) {
      tname <- if (length(sheets) == 1) {
        base
      } else {
        paste0(base, "_", janitor::make_clean_names(s))
      }
      tbls[[tname]] <- df
    }
  }
  list(tables = tbls)
}

# ── Parquet reader ─────────────────────────────────────────────

read_parquet_file <- function(path, name, notify_fn) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    notify_fn(
      "Install the 'arrow' package to read Parquet files: install.packages('arrow')"
    )
    return(list(tables = list()))
  }
  df <- as.data.frame(arrow::read_parquet(path))
  list(tables = setNames(list(df), tools::file_path_sans_ext(name)))
}

# ── JSON reader ────────────────────────────────────────────────

read_json_file <- function(path, name, notify_fn) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    notify_fn(
      "Install the 'jsonlite' package to read JSON files: install.packages('jsonlite')"
    )
    return(list(tables = list()))
  }
  raw <- jsonlite::fromJSON(path, flatten = TRUE)
  if (is.data.frame(raw)) {
    return(list(tables = setNames(list(raw), tools::file_path_sans_ext(name))))
  }
  if (is.list(raw) && all(vapply(raw, is.data.frame, logical(1)))) {
    return(list(tables = raw))
  }
  notify_fn(paste0("JSON in '", name, "' did not parse to a data frame."))
  list(tables = list())
}

# ── NDJSON reader ──────────────────────────────────────────────

read_ndjson_file <- function(path, name, notify_fn) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    notify_fn(
      "Install the 'jsonlite' package to read NDJSON files: install.packages('jsonlite')"
    )
    return(list(tables = list()))
  }
  df <- jsonlite::stream_in(file(path), verbose = FALSE)
  list(
    tables = setNames(list(as.data.frame(df)), tools::file_path_sans_ext(name))
  )
}

# ── Haven reader (SPSS, SAS, Stata) ───────────────────────────

read_haven_file <- function(path, name, fmt, notify_fn) {
  if (!requireNamespace("haven", quietly = TRUE)) {
    notify_fn(
      "Install the 'haven' package to read SPSS/SAS/Stata files: install.packages('haven')"
    )
    return(list(tables = list()))
  }
  df <- switch(
    fmt,
    sav = haven::read_sav(path),
    por = haven::read_por(path),
    sas = haven::read_sas(path),
    xpt = haven::read_xpt(path),
    dta = haven::read_dta(path)
  )
  df <- as.data.frame(df)
  list(tables = setNames(list(df), tools::file_path_sans_ext(name)))
}

# ── RDS reader ─────────────────────────────────────────────────

read_rds_file <- function(path, name, notify_fn) {
  obj <- readRDS(path)
  if (is.data.frame(obj)) {
    return(list(tables = setNames(list(obj), tools::file_path_sans_ext(name))))
  }
  notify_fn(paste0("RDS file '", name, "' does not contain a data frame."))
  list(tables = list())
}

# ── RData reader ───────────────────────────────────────────────

read_rdata_file <- function(path, name, notify_fn) {
  env <- new.env(parent = emptyenv())
  load(path, envir = env)
  objs <- ls(env)
  tbls <- list()
  for (nm in objs) {
    obj <- get(nm, envir = env)
    if (is.data.frame(obj)) {
      tbls[[nm]] <- obj
    }
  }
  if (length(tbls) == 0) {
    notify_fn(paste0("No data frames found in '", name, "'."))
  }
  list(tables = tbls)
}

# ── Schema file import ─────────────────────────────────────────

parse_schema_file <- function(path, name, notify_fn = message) {
  ext <- tolower(tools::file_ext(name))
  schema <- tryCatch(
    {
      if (ext %in% c("json")) {
        if (!requireNamespace("jsonlite", quietly = TRUE)) {
          notify_fn("Install 'jsonlite' to import JSON schema files.")
          return(list(tables = list(), relationships = list()))
        }
        jsonlite::fromJSON(path, simplifyVector = FALSE)
      } else if (ext %in% c("yaml", "yml")) {
        if (!requireNamespace("yaml", quietly = TRUE)) {
          notify_fn(
            "Install the 'yaml' package to import YAML schema files: install.packages('yaml')"
          )
          return(list(tables = list(), relationships = list()))
        }
        yaml::read_yaml(path)
      } else {
        notify_fn(paste0(
          "Unsupported schema format: .",
          ext,
          ". Import Schema takes a .json or .yaml schema definition. ",
          "To reload a saved session, use Export \u2192 Restore Session."
        ))
        return(list(tables = list(), relationships = list()))
      }
    },
    error = function(e) {
      notify_fn(paste0("Error parsing schema file: ", conditionMessage(e)))
      return(list(tables = list(), relationships = list()))
    }
  )

  if (is.list(schema) && !is.null(schema[["$version"]])) {
    return(parse_data_dict_schema(schema, notify_fn))
  }

  tables <- list()
  relationships <- list()

  # Parse tables from schema + extract inline FK definitions
  if (!is.null(schema$tables)) {
    for (tdef in schema$tables) {
      tname <- tdef$name
      if (is.null(tname)) {
        next
      }
      cols <- tdef$columns
      if (is.null(cols)) {
        cols <- tdef$fields
      }
      if (!is.null(cols)) {
        col_names <- vapply(cols, function(c) c$name %||% "", character(1))
        col_names <- col_names[nzchar(col_names)]
        if (length(col_names) > 0) {
          df <- as.data.frame(
            matrix(nrow = 0, ncol = length(col_names)),
            stringsAsFactors = FALSE
          )
          names(df) <- col_names
          tables[[tname]] <- df
        }
        # Extract inline foreign_key definitions
        for (cdef in cols) {
          fk <- cdef$foreign_key
          if (!is.null(fk)) {
            rel <- list(
              from_table = tname,
              from_col = cdef$name %||% "",
              to_table = fk$table %||% "",
              to_col = fk$column %||% "",
              detected_by = "schema",
              confidence = "high",
              score = 1.0,
              signals = list(schema = 1.0),
              reasons = "schema-defined"
            )
            if (nzchar(rel$from_table) && nzchar(rel$to_table)) {
              relationships[[length(relationships) + 1]] <- rel
            }
          }
        }
      }
    }
  }

  # Parse top-level relationships array (if present)
  if (!is.null(schema$relationships)) {
    for (rdef in schema$relationships) {
      rel <- list(
        from_table = rdef$from_table %||% rdef$from %||% "",
        from_col = rdef$from_column %||% rdef$from_col %||% "",
        to_table = rdef$to_table %||% rdef$to %||% "",
        to_col = rdef$to_column %||% rdef$to_col %||% "",
        detected_by = "schema",
        confidence = "high",
        score = 1.0,
        signals = list(schema = 1.0),
        reasons = "schema-defined"
      )
      if (nzchar(rel$from_table) && nzchar(rel$to_table)) {
        relationships[[length(relationships) + 1]] <- rel
      }
    }
  }

  list(tables = tables, relationships = relationships)
}

# ── data-dict YAML ─────────────────────────────────────────────
# A data-dict.yaml file (https://data-dict.tidyverse.org/; see
# generate_data_dict_yaml() in utils_export.R): tables and columns, joins as
# declared relationships, and labels, descriptions, details, units, allowed
# values and display: restricted as dictionary entries.
data_dict_empty_column <- function(type) {
  type <- type %||% "string"
  if (startsWith(type, "number")) return(numeric(0))
  switch(
    type,
    boolean = logical(0),
    date = as.Date(character(0)),
    datetime = as.POSIXct(character(0), tz = "UTC"),
    character(0)
  )
}

parse_data_dict_schema <- function(schema, notify_fn = message) {
  txt <- function(x) if (is.null(x)) "" else trimws(paste(as.character(unlist(x)), collapse = " "))
  tables <- list()
  dictionary <- list()
  add_entry <- function(key, def, column = FALSE) {
    e <- list()
    for (f in c("label", "description", "details")) {
      if (nzchar(txt(def[[f]]))) e[[f]] <- txt(def[[f]])
    }
    if (column) {
      if (nzchar(txt(def$units))) e$units <- txt(def$units)
      if (!is.null(def$values)) e$values <- dict_format_values(def$values)
      if (identical(def$display, "restricted")) {
        e$private <- TRUE
        e$private_source <- "import"
      }
    }
    if (length(e)) dictionary[[key]] <<- e
  }
  for (tdef in schema$tables %||% list()) {
    tname <- tdef$name
    if (is.null(tname) || !nzchar(tname)) next
    add_entry(dict_key(tname), tdef)
    cols <- list()
    for (cdef in tdef$columns %||% list()) {
      cn <- cdef$name
      if (is.null(cn) || !nzchar(cn)) next
      # Empty columns of the declared type, so a re-export keeps the types
      cols[[cn]] <- data_dict_empty_column(cdef$type)
      add_entry(dict_key(tname, cn), cdef, column = TRUE)
    }
    tables[[tname]] <- if (length(cols)) {
      as.data.frame(cols, stringsAsFactors = FALSE, check.names = FALSE)
    } else {
      data.frame()
    }
  }

  relationships <- list()
  skipped <- 0L
  for (rdef in schema$relationships %||% list()) {
    m <- regmatches(
      rdef$join %||% "",
      regexec("^\\s*([^.\\s]+)\\.([^=\\s]+)\\s*=\\s*([^.\\s]+)\\.([^=\\s]+)\\s*$", rdef$join %||% "", perl = TRUE)
    )[[1]]
    if (length(m) != 5) {
      skipped <- skipped + 1L
      next
    }
    aliases <- rdef$aliases %||% list()
    side <- function(x) aliases[[x]] %||% x
    left <- list(table = side(m[2]), col = m[3])
    right <- list(table = side(m[4]), col = m[5])
    # The link points from the "many" side to the "one" side
    if (identical(rdef$cardinality, "one-to-many")) {
      tmp <- left
      left <- right
      right <- tmp
    }
    relationships[[length(relationships) + 1]] <- list(
      from_table = left$table,
      from_col = left$col,
      to_table = right$table,
      to_col = right$col,
      detected_by = "schema",
      confidence = "high",
      score = 1.0,
      signals = list(schema = 1.0),
      reasons = "declared in data-dict"
    )
  }
  if (skipped > 0) {
    notify_fn(sprintf(
      "%d data-dict relationship(s) skipped: only joins of the form a.x = b.y are read.",
      skipped
    ))
  }
  list(tables = tables, relationships = relationships, dictionary = dictionary)
}

# Add imported dictionary entries (keyed by the imported names, cleaned the
# way table and column names are) without overwriting non-empty user edits
merge_dictionary <- function(current, imported) {
  current <- current %||% list()
  for (k in names(imported)) {
    parts <- strsplit(k, "|", fixed = TRUE)[[1]]
    # One name at a time: cleaned together, a column named like its table
    # would be made unique ("status|status_2")
    ck <- paste(vapply(parts, janitor::make_clean_names, ""), collapse = "|")
    e <- current[[ck]] %||% list()
    for (f in names(imported[[k]])) {
      have <- e[[f]]
      empty <- is.null(have) || (is.character(have) && !nzchar(have))
      if (f == "label" && !is.null(e$business_name) && nzchar(e$business_name)) empty <- FALSE
      if (empty) e[[f]] <- imported[[k]][[f]]
    }
    current[[ck]] <- e
  }
  current
}

# ── App export detection ─────────────────────────────────────
# Returns a label if a data frame has exactly the column layout of one of this
# app's CSV exports (Relationships CSV, table details CSV), else NULL. The
# whole header must match so real mapping tables with some of these column
# names (from_table, to_table, ...) are still loaded as data.

app_export_signatures <- list(
  "relationships list" = c(
    "from_table", "from_col", "to_table", "to_col", "detected_by",
    "confidence", "score", "signals", "reasons"
  ),
  "table details" = c(
    "table", "table_rows", "table_cols", "column", "type", "non_null",
    "unique_vals", "is_pk", "is_fk"
  )
)

detect_app_export <- function(df) {
  cols <- janitor::make_clean_names(names(df))
  for (kind in names(app_export_signatures)) {
    sig <- app_export_signatures[[kind]]
    # Relationships CSVs gained a review "status" and then a "source" column;
    # accept every version
    optional <- c("status", "source")
    if (all(sig %in% cols) && all(setdiff(cols, sig) %in% optional)) {
      return(kind)
    }
  }
  NULL
}

# ── Access database support ──────────────────────────────────

# Persistent per-user cache. Uploads land in a fresh temp dir each time, so
# keeping the jars next to the uploaded file re-downloaded them on every upload.
access_jar_dir <- function() {
  file.path(tools::R_user_dir("tableexplorer", "cache"), "access_jars")
}

ucanaccess_jars <- list(
  list(
    file = "ucanaccess-5.0.1.jar",
    url = "https://repo1.maven.org/maven2/net/sf/ucanaccess/ucanaccess/5.0.1/ucanaccess-5.0.1.jar"
  ),
  list(
    file = "jackcess-4.0.1.jar",
    url = "https://repo1.maven.org/maven2/com/healthmarketscience/jackcess/jackcess/4.0.1/jackcess-4.0.1.jar"
  ),
  list(
    file = "commons-lang3-3.12.0.jar",
    url = "https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.12.0/commons-lang3-3.12.0.jar"
  ),
  list(
    file = "commons-logging-1.2.jar",
    url = "https://repo1.maven.org/maven2/commons-logging/commons-logging/1.2/commons-logging-1.2.jar"
  ),
  list(
    file = "hsqldb-2.7.1.jar",
    url = "https://repo1.maven.org/maven2/org/hsqldb/hsqldb/2.7.1/hsqldb-2.7.1.jar"
  )
)

ensure_ucanaccess_jars <- function(jar_dir, notify_fn) {
  if (!dir.exists(jar_dir)) {
    dir.create(jar_dir, recursive = TRUE, showWarnings = FALSE)
  }
  for (j in ucanaccess_jars) {
    dest <- file.path(jar_dir, j$file)
    if (!file.exists(dest)) {
      notify_fn(paste0("Downloading ", j$file, "..."))
      tryCatch(
        utils::download.file(j$url, dest, mode = "wb", quiet = TRUE),
        error = function(e) {
          notify_fn(paste0(
            "Failed to download ",
            j$file,
            ": ",
            conditionMessage(e)
          ))
        }
      )
    }
  }
  jar_paths <- file.path(
    jar_dir,
    vapply(ucanaccess_jars, `[[`, character(1), "file")
  )
  all(file.exists(jar_paths))
}

# ── Declared relationships in Access files ───────────────────
# Access keeps every relationship (enforced or not; the Lookup Wizard makes
# unenforced ones) in the MSysRelationships system table: one row per column
# pair, szObject/szColumn = child (FK) side, szReferencedObject/Column =
# parent, grbit bit 1 = one-to-one, bit 2 = integrity not enforced.
# Read it with Jackcess (already in the UCanAccess jar set, via rJava) or
# with mdbtools' mdb-export; either way the rows go through
# access_relationship_rels().

access_relationships <- function(path, notify_fn = message) {
  rows <- access_relationship_rows_jackcess(path)
  if (is.null(rows)) {
    rows <- access_relationship_rows_mdbtools(path)
  }
  if (is.null(rows)) {
    notify_fn(paste0(
      "Relationships declared in ",
      basename(path),
      " could not be read (needs Java with rJava, or mdbtools), so they ",
      "will be inferred from the data instead."
    ))
    return(list())
  }
  access_relationship_rels(rows)
}

# rows: data frame with szRelationship, grbit, icolumn, szObject, szColumn,
# szReferencedObject, szReferencedColumn (MSysRelationships layout)
access_relationship_rels <- function(rows) {
  if (is.null(rows) || nrow(rows) == 0) {
    return(list())
  }
  rows <- rows[!grepl("^MSys", rows$szObject) & !grepl("^MSys", rows$szReferencedObject), , drop = FALSE]
  lapply(seq_len(nrow(rows)), function(i) {
    grbit <- suppressWarnings(as.integer(rows$grbit[i]))
    if (is.na(grbit)) grbit <- 0L
    enforced <- bitwAnd(grbit, 2L) == 0L
    list(
      from_table = janitor::make_clean_names(rows$szObject[i]),
      from_col = janitor::make_clean_names(rows$szColumn[i]),
      to_table = janitor::make_clean_names(rows$szReferencedObject[i]),
      to_col = janitor::make_clean_names(rows$szReferencedColumn[i]),
      detected_by = "schema",
      confidence = "high",
      score = 1.0,
      signals = list(schema = 1.0),
      reasons = if (enforced) {
        "declared in Access (integrity enforced)"
      } else {
        "declared in Access (not enforced, e.g. a lookup field)"
      },
      one_to_one = bitwAnd(grbit, 1L) != 0L
    )
  })
}

access_relationship_rows_mdbtools <- function(path) {
  if (!nzchar(Sys.which("mdb-export"))) {
    return(NULL)
  }
  out <- tryCatch(
    suppressWarnings(system2(
      "mdb-export",
      c(shQuote(path), "MSysRelationships"),
      stdout = TRUE,
      stderr = FALSE
    )),
    error = function(e) NULL
  )
  if (is.null(out) || length(out) == 0 || !is.null(attr(out, "status"))) {
    return(NULL)
  }
  tryCatch(
    utils::read.csv(text = out, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) NULL
  )
}

access_relationship_rows_jackcess <- function(path) {
  if (!requireNamespace("rJava", quietly = TRUE)) {
    return(NULL)
  }
  jar_dir <- access_jar_dir()
  jar_paths <- file.path(jar_dir, vapply(ucanaccess_jars, `[[`, character(1), "file"))
  jar_paths <- jar_paths[file.exists(jar_paths)]
  if (!any(grepl("jackcess", jar_paths))) {
    return(NULL)
  }
  tryCatch(
    {
      rJava::.jinit()
      rJava::.jaddClassPath(jar_paths)
      builder <- rJava::J("com.healthmarketscience.jackcess.DatabaseBuilder")
      db <- builder$open(rJava::.jnew("java/io/File", normalizePath(path)))
      on.exit(try(db$close(), silent = TRUE), add = TRUE)
      rels <- db$getRelationships()
      out <- list()
      for (i in seq_len(rels$size()) - 1L) {
        r <- rels$get(i)
        # Jackcess names the parent ("one") side "from"
        parent_cols <- r$getFromColumns()
        child_cols <- r$getToColumns()
        # Same bits as MSysRelationships.grbit: 1 = one-to-one, 2 = not enforced
        flags <- as.integer(r$isOneToOne()) + 2L * as.integer(!r$hasReferentialIntegrity())
        for (j in seq_len(child_cols$size()) - 1L) {
          out[[length(out) + 1]] <- data.frame(
            szRelationship = r$getName(),
            grbit = flags,
            icolumn = j,
            szObject = r$getToTable()$getName(),
            szColumn = child_cols$get(j)$getName(),
            szReferencedObject = r$getFromTable()$getName(),
            szReferencedColumn = parent_cols$get(j)$getName(),
            stringsAsFactors = FALSE
          )
        }
      }
      if (length(out) == 0) {
        out <- list(data.frame(
          szRelationship = character(0), grbit = integer(0),
          icolumn = integer(0), szObject = character(0),
          szColumn = character(0), szReferencedObject = character(0),
          szReferencedColumn = character(0)
        ))
      }
      do.call(rbind, out)
    },
    error = function(e) NULL
  )
}

read_access_db <- function(path, notify_fn = message) {
  # Strategy 1: RJDBC + UCanAccess (all platforms, needs Java)
  if (requireNamespace("RJDBC", quietly = TRUE)) {
    jar_dir <- access_jar_dir()
    jars_ok <- tryCatch(
      ensure_ucanaccess_jars(jar_dir, notify_fn),
      error = function(e) FALSE
    )

    if (jars_ok) {
      jar_paths <- file.path(
        jar_dir,
        vapply(ucanaccess_jars, `[[`, character(1), "file")
      )
      result <- tryCatch(
        {
          drv <- RJDBC::JDBC(
            driverClass = "net.ucanaccess.jdbc.UcanaccessDriver",
            classPath = jar_paths
          )
          jdbc_url <- paste0(
            "jdbc:ucanaccess://",
            normalizePath(path, winslash = "/")
          )
          con <- DBI::dbConnect(drv, jdbc_url)
          on.exit(
            tryCatch(DBI::dbDisconnect(con), error = function(e) NULL),
            add = TRUE
          )

          all_tables <- DBI::dbListTables(con)
          user_tables <- all_tables[!grepl("^MSys|^USys|^~", all_tables)]

          tbls <- setNames(
            lapply(user_tables, function(tname) {
              tryCatch(
                DBI::dbReadTable(con, tname),
                error = function(e) {
                  notify_fn(paste0(
                    "Could not read table '",
                    tname,
                    "': ",
                    conditionMessage(e)
                  ))
                  NULL
                }
              )
            }),
            user_tables
          )
          Filter(Negate(is.null), tbls)
        },
        error = function(e) {
          notify_fn(paste0(
            "RJDBC/UCanAccess error: ",
            conditionMessage(e),
            " - is Java installed? Run `Sys.getenv('JAVA_HOME')` to check."
          ))
          NULL
        }
      )
      if (!is.null(result) && length(result) > 0) return(result)
    }
  }

  # Strategy 2: RODBC (Windows - needs Access Database Engine)
  if (
    requireNamespace("RODBC", quietly = TRUE) && .Platform$OS.type == "windows"
  ) {
    result <- tryCatch(
      {
        con <- RODBC::odbcConnectAccess2007(path)
        if (inherits(con, "RODBC")) {
          on.exit(RODBC::odbcClose(con), add = TRUE)
          tnames <- RODBC::sqlTables(con, tableType = "TABLE")$TABLE_NAME
          tbls <- setNames(
            lapply(tnames, function(tname) {
              tryCatch(
                RODBC::sqlFetch(con, tname, stringsAsFactors = FALSE),
                error = function(e) {
                  notify_fn(paste0(
                    "RODBC: could not fetch '",
                    tname,
                    "': ",
                    conditionMessage(e)
                  ))
                  NULL
                }
              )
            }),
            tnames
          )
          Filter(Negate(is.null), tbls)
        } else {
          NULL
        }
      },
      error = function(e) NULL
    )
    if (!is.null(result) && length(result) > 0) return(result)
  }

  # No strategy succeeded
  notify_fn(paste0(
    "Could not read Access file. ",
    "Install the RJDBC package (install.packages('RJDBC')) and ensure Java is available. ",
    "The required UCanAccess JARs will be downloaded automatically on first use. ",
    "On Windows, RODBC + the Microsoft Access Database Engine are also accepted."
  ))
  list()
}
