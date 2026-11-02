# fixture_jackcess.R - read an Access file directly with Jackcess, independently
# of the app's reader code. Used by check_answer_key.R, so the measuring side
# does not lean on the code it measures. Opens read-only.

jack_jars <- function() {
  d <- file.path(tools::R_user_dir("tableexplorer", "cache"), "access_jars")
  need <- c(
    "jackcess-4.0.1.jar",
    "commons-lang3-3.12.0.jar",
    "commons-logging-1.2.jar"
  )
  p <- file.path(d, need)
  if (!all(file.exists(p))) {
    stop(
      "Jackcess jars missing; not downloading them. Looked for: ",
      paste(need, collapse = ", ")
    )
  }
  p
}

jack_open <- function(path) {
  rJava::.jinit()
  rJava::.jaddClassPath(jack_jars())
  f <- rJava::.jnew("java/io/File", normalizePath(path))
  b <- rJava::.jnew("com/healthmarketscience/jackcess/DatabaseBuilder", f)
  b$setReadOnly(TRUE)$open()
}

jack_iter <- function(tbl, f) {
  it <- tbl$iterator()
  out <- list()
  while (it$hasNext()) {
    out[[length(out) + 1]] <- f(it$`next`())
  }
  out
}

jack_str <- function(x) {
  # rJava's `$` hands Strings back as R strings and everything else as a reference
  if (is.null(x)) {
    NA_character_
  } else if (inherits(x, "jobjRef")) {
    if (rJava::is.jnull(x)) NA_character_ else rJava::.jcall(x, "S", "toString")
  } else {
    as.character(x)
  }
}

# Objects from MSysObjects: Type 1 local table, 5 query, 6 linked table
jack_objects <- function(db) {
  rows <- jack_iter(db$getSystemCatalog(), function(r) {
    data.frame(
      name = jack_str(r$get("Name")),
      type = as.integer(jack_str(r$get("Type"))),
      flags = as.numeric(jack_str(r$get("Flags"))),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

# A table is the user's unless its name is an engine table. Name lists are
# not used here because they already apply Jackcess's own view of hidden and
# system objects, which is one of the things being measured.
engine_table <- function(nm) {
  grepl(
    "^(MSysObjects|MSysACEs|MSysQueries|MSysRelationships|MSysAccessObjects|MSysAccessXML|MSysAccessStorage|MSysNavPane.*|MSysNameMap|MSysComplex.*|MSysIMEX.*|MSysCmdbars|MSysDb|MSysModules.*|MSysResources|MSysObjects|f_[0-9A-F]+_.*)$",
    nm
  )
}

# Java 21 refuses rJava's `$` on the JDK's private unmodifiable list classes, so
# lists come across through the public toArray() instead
jack_list <- function(x) {
  rJava::.jcall(x, "[Ljava/lang/Object;", "toArray")
}

jack_columns <- function(tbl) {
  vapply(jack_list(tbl$getColumns()), function(cc) jack_str(cc$getName()), "")
}

jack_pk <- function(tbl) {
  tryCatch(
    {
      ix <- tbl$getPrimaryKeyIndex()
      paste(
        vapply(
          jack_list(ix$getColumns()),
          function(cc) jack_str(cc$getName()),
          ""
        ),
        collapse = "|"
      )
    },
    error = function(e) {
      if (
        grepl(
          "IllegalArgument|no primary key",
          conditionMessage(e),
          ignore.case = TRUE
        )
      ) {
        ""
      } else {
        stop(e)
      }
    }
  )
}

jack_rels <- function(db) {
  rows <- jack_iter(db$getSystemTable("MSysRelationships"), function(r) {
    data.frame(
      rel_name = jack_str(r$get("szRelationship")),
      icolumn = as.integer(jack_str(r$get("icolumn"))),
      table_raw = jack_str(r$get("szObject")),
      column_raw = jack_str(r$get("szColumn")),
      ref_table_raw = jack_str(r$get("szReferencedObject")),
      ref_column_raw = jack_str(r$get("szReferencedColumn")),
      grbit_native = as.numeric(jack_str(r$get("grbit"))),
      stringsAsFactors = FALSE
    )
  })
  if (length(rows) == 0) {
    return(data.frame())
  }
  d <- do.call(rbind, rows)
  d[order(d$rel_name, d$icolumn), ]
}

# getTable() refuses system-flagged tables; getSystemTable() opens those
jack_table <- function(db, name) {
  tb <- db$getTable(name)
  if (is.null(tb) || rJava::is.jnull(tb)) {
    tb <- db$getSystemTable(name)
  }
  if (is.null(tb) || rJava::is.jnull(tb)) {
    stop("Jackcess cannot open table: ", name)
  }
  tb
}
