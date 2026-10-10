# Score FK detection against real public schemas.
#
# The point: dev/fixtures/score_detection.R measures one synthetic
# Access-style fixture, and every real link in it carries a naming
# signal. A rule that quietly kills content-only evidence passes it. These
# datasets have declared foreign keys, so ground truth is free: read the
# constraints, hide them, detect, compare.
#
#   Rscript dev/fixtures/public/fetch.R
#   Rscript dev/fixtures/public/score_public.R
#   Rscript dev/fixtures/public/score_public.R chinook

Sys.setenv(RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE")
suppressMessages(pkgload::load_all(".", quiet = TRUE))
source("dev/fixtures/public/fetch.R", local = TRUE, echo = FALSE)

`%||%` <- function(a, b) if (is.null(a)) b else a

# ── Ground truth ─────────────────────────────────────────────
# Declared constraints where the source has them, a hand-written file
# where it does not. A pair is "table.column -> table.column".

pair <- function(ft, fc, tt, tc) {
  sprintf("%s.%s -> %s.%s", tolower(ft), tolower(fc), tolower(tt), tolower(tc))
}

truth_from_sqlite <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con))
  tabs <- DBI::dbListTables(con)
  out <- character(0)
  for (t in tabs) {
    fks <- tryCatch(
      DBI::dbGetQuery(con, sprintf("PRAGMA foreign_key_list(%s)", DBI::dbQuoteIdentifier(con, t))),
      error = function(e) NULL
    )
    if (is.null(fks) || nrow(fks) == 0) next
    for (i in seq_len(nrow(fks))) {
      to_col <- fks$to[i]
      if (is.na(to_col) || !nzchar(to_col)) {
        # "to" is NULL when the FK points at the parent's primary key
        pk <- DBI::dbGetQuery(con, sprintf("PRAGMA table_info(%s)", DBI::dbQuoteIdentifier(con, fks$table[i])))
        to_col <- pk$name[pk$pk == 1][1]
      }
      out <- c(out, pair(t, fks$from[i], fks$table[i], to_col))
    }
  }
  unique(out)
}

tables_from_sqlite <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(DBI::dbDisconnect(con))
  tabs <- DBI::dbListTables(con)
  out <- lapply(tabs, function(t) {
    # Whole tables. A foreign key is a claim about value containment, so
    # reading part of a table breaks the property being measured: the
    # child rows kept are not the ones whose parents were kept.
    DBI::dbGetQuery(con, sprintf("SELECT * FROM %s", DBI::dbQuoteIdentifier(con, t)))
  })
  stats::setNames(out, tabs)
}

truth_from_pg_schema <- function(path) {
  # Pagila ships its constraints as ALTER TABLE statements
  txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
  stmts <- regmatches(txt, gregexpr(
    "ALTER TABLE ONLY [^;]+?FOREIGN KEY[^;]+;", txt, perl = TRUE
  ))[[1]]
  out <- character(0)
  for (s in stmts) {
    m <- regmatches(s, regexec(
      paste0(
        "ALTER TABLE ONLY (?:[a-z_]+\\.)?([a-z_]+).*?",
        "FOREIGN KEY \\(([a-z_, ]+)\\).*?",
        "REFERENCES (?:[a-z_]+\\.)?([a-z_]+)\\(([a-z_, ]+)\\)"
      ),
      s, perl = TRUE
    ))[[1]]
    if (length(m) == 5) out <- c(out, pair(m[2], trimws(m[3]), m[4], trimws(m[5])))
  }
  unique(out)
}

# ── Scoring ──────────────────────────────────────────────────

score_one <- function(name, tables, truth, min_conf = "medium") {
  if (length(tables) == 0) {
    cat(sprintf("%-8s SKIP  no tables loaded\n", name))
    return(invisible(NULL))
  }
  t0 <- Sys.time()
  rels <- detect_fks(tables, method = "both", min_confidence = min_conf)
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  found <- unique(vapply(
    rels,
    function(r) pair(r$from_table, r$from_col, r$to_table, r$to_col %||% ""),
    ""
  ))
  hit <- intersect(found, truth)
  missed <- setdiff(truth, found)
  extra <- setdiff(found, truth)
  recall <- if (length(truth)) length(hit) / length(truth) else NA_real_
  prec <- if (length(found)) length(hit) / length(found) else NA_real_
  cat(sprintf(
    "%-8s tables %3d  truth %3d  found %3d  hit %3d  recall %5.1f%%  precision %5.1f%%  %4.1fs\n",
    name, length(tables), length(truth), length(found), length(hit),
    100 * recall, 100 * prec, secs
  ))
  if (length(missed)) {
    cat("         missed: ", paste(utils::head(missed, 8), collapse = "; "),
        if (length(missed) > 8) sprintf(" (+%d more)", length(missed) - 8) else "", "\n", sep = "")
  }
  invisible(list(
    name = name, truth = truth, found = found,
    hit = hit, missed = missed, extra = extra,
    recall = recall, precision = prec
  ))
}

# ── Datasets ─────────────────────────────────────────────────

run_chinook <- function() {
  f <- file.path(public_cache(), "chinook.sqlite")
  if (!file.exists(f)) {
    cat("chinook  SKIP  not fetched\n")
    return(invisible(NULL))
  }
  score_one("chinook", tables_from_sqlite(f), truth_from_sqlite(f))
}

run_pagila <- function() {
  f <- file.path(public_cache(), "pagila-schema.sql")
  if (!file.exists(f)) {
    cat("pagila   SKIP  not fetched\n")
    return(invisible(NULL))
  }
  truth <- truth_from_pg_schema(f)
  # Schema only: no rows to compare, so this reports the naming side
  # alone. Loading the data needs a PostgreSQL server.
  cat(sprintf("pagila   INFO  %d declared foreign keys parsed from the schema; needs a server for the data\n", length(truth)))
  invisible(list(name = "pagila", truth = truth))
}

run_lahman <- function() {
  z <- file.path(public_cache(), "lahman.zip")
  if (!file.exists(z)) {
    cat("lahman   SKIP  not fetched\n")
    return(invisible(NULL))
  }
  dir <- file.path(public_cache(), "lahman")
  if (!dir.exists(dir)) {
    utils::unzip(z, exdir = dir)
  }
  csvs <- list.files(dir, pattern = "[.]csv$", recursive = TRUE, full.names = TRUE)
  csvs <- csvs[grepl("/core/", csvs, fixed = TRUE)]
  tables <- lapply(csvs, function(f) utils::read.csv(f, stringsAsFactors = FALSE))
  names(tables) <- tools::file_path_sans_ext(basename(csvs))
  truth_file <- "dev/fixtures/public/truth/lahman.txt"
  truth <- if (file.exists(truth_file)) {
    tr <- trimws(readLines(truth_file, warn = FALSE))
    tr[nzchar(tr) & !startsWith(tr, "#")]
  } else {
    character(0)
  }
  score_one("lahman", tables, truth)
}

run_faers <- function() {
  z <- file.path(public_cache(), "faers_ascii_2024q1.zip")
  if (!file.exists(z)) {
    cat("faers    SKIP  not fetched\n")
    return(invisible(NULL))
  }
  dir <- file.path(public_cache(), "faers")
  if (!dir.exists(dir)) {
    utils::unzip(z, exdir = dir)
  }
  txts <- list.files(dir, pattern = "[.]txt$", recursive = TRUE, full.names = TRUE)
  txts <- txts[grepl("/ascii/", tolower(txts), fixed = TRUE)]
  tables <- lapply(txts, function(f) {
    message("  reading ", basename(f), " (", round(file.size(f) / 1024^2), " MB)")
    utils::read.delim(f, sep = "$", stringsAsFactors = FALSE, quote = "", comment.char = "")
  })
  names(tables) <- tolower(tools::file_path_sans_ext(basename(txts)))
  truth_file <- "dev/fixtures/public/truth/faers.txt"
  truth <- if (file.exists(truth_file)) {
    tr <- trimws(readLines(truth_file, warn = FALSE))
    tr[nzchar(tr) & !startsWith(tr, "#")]
  } else {
    character(0)
  }
  score_one("faers", tables, truth)
}

args <- commandArgs(trailingOnly = TRUE)
want <- if (length(args)) args else c("chinook", "pagila", "lahman", "faers")
cat("dataset  shape and result\n")
for (w in want) {
  switch(
    w,
    chinook = run_chinook(),
    pagila = run_pagila(),
    lahman = run_lahman(),
    faers = run_faers(),
    cat("unknown dataset:", w, "\n")
  )
}
