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
#   Rscript dev/fixtures/public/score_public.R chinook parent_key=composite
#   Rscript dev/fixtures/public/score_public.R lahman parent_key=any max_pairs=400000
#
# parent_key= selects detect_fks()' parent_key_requirement: key (the
# default), composite or any. max_pairs= is detect_fks' own pair cap: the
# relaxed settings offer far more candidate parents, so a run at the
# default cap is truncated and its recall is an artefact of where the scan
# stopped. Every line prints the pairs scored against the cap and says
# CAPPED when it was reached, and a relaxed setting is measured twice: at
# the default cap, and at a cap high enough that nothing is truncated.
# TE_TRUTH_DIR overrides where the hand-written truth files are read from,
# which is how the ground-truth validation below is exercised without
# editing a real truth file.
#
# This file is sourced by tests/testthat/test-inference.R to test
# score_one() against a fixed input. Sourcing it into an environment that
# already defines .score_public_no_setup skips the package load and the
# dataset drivers, so nothing runs on import.

.no_setup <- exists(".score_public_no_setup", inherits = TRUE)

if (!.no_setup) {
  Sys.setenv(RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE")
  suppressMessages(pkgload::load_all(".", quiet = TRUE))
  source("dev/fixtures/public/fetch.R", local = TRUE, echo = FALSE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

truth_dir <- function() {
  Sys.getenv("TE_TRUTH_DIR", "dev/fixtures/public/truth")
}

read_truth_file <- function(basename) {
  f <- file.path(truth_dir(), basename)
  if (!file.exists(f)) {
    return(character(0))
  }
  tr <- trimws(readLines(f, warn = FALSE))
  tr[nzchar(tr) & !startsWith(tr, "#")]
}

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

# ── Ground-truth validation ──────────────────────────────────
# A truth pair that names a column the data does not have is reported as a
# missed link, and reads as a detection failure. The Lahman file said
# homegames.parkkey where the column is park.key, and that typo stood as a
# recall figure for a day. So every pair is checked against the loaded
# data before anything is scored, and a pair that does not resolve stops
# the run instead of lowering the score.
#
# Returns the offending pairs, each with what did not resolve. Table names
# here never contain a dot, so a side splits at its first one; column
# names do (Lahman's park.key), so everything after it is the column.
validate_truth <- function(tables, truth) {
  have <- stats::setNames(
    lapply(tables, function(df) tolower(names(df))),
    tolower(names(tables))
  )
  bad <- character(0)
  for (p in truth) {
    sides <- strsplit(p, " -> ", fixed = TRUE)[[1]]
    if (length(sides) != 2) {
      bad <- c(bad, sprintf("%s  (not a 'table.column -> table.column' pair)", p))
      next
    }
    why <- character(0)
    for (s in sides) {
      tname <- sub("[.].*$", "", s)
      cname <- sub("^[^.]*[.]", "", s)
      if (!tname %in% names(have)) {
        why <- c(why, sprintf("no table %s", tname))
      } else if (!cname %in% have[[tname]]) {
        why <- c(why, sprintf("no column %s in %s", cname, tname))
      }
    }
    if (length(why)) {
      bad <- c(bad, sprintf("%s  (%s)", p, paste(why, collapse = "; ")))
    }
  }
  bad
}

# ── Scoring ──────────────────────────────────────────────────

# Set by score_one when a dataset's ground truth does not resolve, read by
# the driver at the bottom to exit non-zero.
truth_failures <- 0L

# Confidence levels, strongest first, for the per-level breakdown.
conf_levels <- c("high", "medium", "low")

score_one <- function(
  name,
  tables,
  truth,
  min_conf = "medium",
  parent_key = parent_key_requirement_default,
  max_pairs = 50000L
) {
  if (length(tables) == 0) {
    cat(sprintf("%-8s SKIP  no tables loaded\n", name))
    return(invisible(NULL))
  }
  bad <- validate_truth(tables, truth)
  if (length(bad)) {
    cat(sprintf(
      "%-8s TRUTH FAIL  %d of %d pairs name something the data does not have\n",
      name, length(bad), length(truth)
    ))
    for (b in bad) cat("         ", b, "\n", sep = "")
    truth_failures <<- truth_failures + 1L
    return(invisible(NULL))
  }
  t0 <- Sys.time()
  rels <- detect_fks(
    tables,
    method = "both",
    min_confidence = min_conf,
    max_pairs = max_pairs,
    parent_key_requirement = parent_key,
    # TE_PROSE_GUARD rather than a command-line argument: this is a
    # measurement switch, not a setting the harness is asked for, and
    # threading a fourth argument through every run_* function to measure
    # it once would be the larger change.
    prose_parent_guard = Sys.getenv("TE_PROSE_GUARD", prose_parent_guard_default)
  )
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  as_pair <- function(r) {
    pair(r$from_table, r$from_col, r$to_table, r$to_col %||% "")
  }
  found <- unique(vapply(rels, as_pair, ""))
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
  # Per confidence level. detect_fks returns rows that resolve_fk_parents
  # has since demoted below min_confidence, so the overall line mixes
  # levels: on Chinook its 59 rows were 10 high and 49 low, and the 16.9%
  # precision it printed was 100% at the level a reviewer acts on. The
  # overall line is left exactly as it was so earlier figures stay
  # comparable, and these lines say what it is made of.
  by_conf <- list()
  for (lv in conf_levels) {
    rows <- Filter(function(r) identical(r$confidence %||% "low", lv), rels)
    if (length(rows) == 0) next
    f <- unique(vapply(rows, as_pair, ""))
    h <- intersect(f, truth)
    by_conf[[lv]] <- list(
      found = length(f), hit = length(h),
      recall = if (length(truth)) length(h) / length(truth) else NA_real_,
      precision = if (length(f)) length(h) / length(f) else NA_real_
    )
    cat(sprintf(
      "         %-6s found %3d  hit %3d  recall %5.1f%%  precision %5.1f%%\n",
      lv, length(f), length(h),
      100 * by_conf[[lv]]$recall, 100 * by_conf[[lv]]$precision
    ))
  }
  cat(sprintf(
    "         parent_key %-9s prose %-6s pairs scored %6d of %6d%s  composite probe %6.2fs  columns admitted %3d\n",
    parent_key,
    Sys.getenv("TE_PROSE_GUARD", prose_parent_guard_default),
    attr(rels, "pairs_scored") %||% NA_integer_,
    max_pairs,
    if (isTRUE(attr(rels, "truncated"))) "  CAPPED" else "        ",
    attr(rels, "composite_probe_secs") %||% 0,
    length(attr(rels, "composite_parents") %||% character(0))
  ))
  if (length(missed)) {
    cat("         missed: ", paste(utils::head(missed, 8), collapse = "; "),
        if (length(missed) > 8) sprintf(" (+%d more)", length(missed) - 8) else "", "\n", sep = "")
  }
  invisible(list(
    name = name, truth = truth, found = found,
    hit = hit, missed = missed, extra = extra,
    recall = recall, precision = prec, by_conf = by_conf,
    secs = secs, parent_key = parent_key, max_pairs = max_pairs,
    pairs_scored = attr(rels, "pairs_scored"),
    truncated = isTRUE(attr(rels, "truncated")),
    composite_probe_secs = attr(rels, "composite_probe_secs"),
    composite_parents = attr(rels, "composite_parents"),
    rels = rels
  ))
}

# ── Datasets ─────────────────────────────────────────────────

run_chinook <- function(parent_key = parent_key_requirement_default,
                        max_pairs = 50000L) {
  f <- file.path(public_cache(), "chinook.sqlite")
  if (!file.exists(f)) {
    cat("chinook  SKIP  not fetched\n")
    return(invisible(NULL))
  }
  score_one(
    "chinook", tables_from_sqlite(f), truth_from_sqlite(f),
    parent_key = parent_key, max_pairs = max_pairs
  )
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

# The CRAN package rather than a download: the canonical
# chadwickbureau/baseballdatabank repository returns 404, and the package
# ships the same tables as data frames. Licence: the package is GPL, the
# data is Lahman's, CC BY-SA 3.0 for the Baseball Databank derivative.
#
# Returns NULL when the package is not installed. Separate from run_lahman
# so sweep_settings.R loads the same tables this file scores, once, and
# then varies the settings over them.
tables_from_lahman <- function() {
  if (!requireNamespace("Lahman", quietly = TRUE)) {
    return(NULL)
  }
  items <- utils::data(package = "Lahman")$results[, "Item"]
  # Only the data frames: the package also ships label vectors
  tables <- list()
  env <- new.env(parent = emptyenv())
  for (nm in items) {
    # Lazy-loaded data: data() rather than get() on the namespace
    ok <- tryCatch({
      utils::data(list = nm, package = "Lahman", envir = env)
      TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok) next
    obj <- tryCatch(get(nm, envir = env), error = function(e) NULL)
    if (is.data.frame(obj) && nrow(obj) > 0) {
      tables[[tolower(nm)]] <- obj
    }
  }
  tables
}

run_lahman <- function(parent_key = parent_key_requirement_default,
                       max_pairs = 50000L) {
  tables <- tables_from_lahman()
  if (is.null(tables)) {
    cat("lahman   SKIP  install.packages(\"Lahman\")\n")
    return(invisible(NULL))
  }
  score_one(
    "lahman", tables, read_truth_file("lahman.txt"),
    parent_key = parent_key, max_pairs = max_pairs
  )
}

# Returns NULL when the quarterly archive has not been fetched. Separate
# from run_faers for the reason given above tables_from_lahman().
tables_from_faers <- function() {
  z <- file.path(public_cache(), "faers_ascii_2024q1.zip")
  if (!file.exists(z)) {
    return(NULL)
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
  tables
}

run_faers <- function(parent_key = parent_key_requirement_default,
                      max_pairs = 50000L) {
  tables <- tables_from_faers()
  if (is.null(tables)) {
    cat("faers    SKIP  not fetched\n")
    return(invisible(NULL))
  }
  score_one(
    "faers", tables, read_truth_file("faers.txt"),
    parent_key = parent_key, max_pairs = max_pairs
  )
}

if (!.no_setup) {
  args <- commandArgs(trailingOnly = TRUE)
  pk_arg <- grep("^parent_key=", args, value = TRUE)
  parent_key <- if (length(pk_arg)) {
    sub("^parent_key=", "", utils::tail(pk_arg, 1))
  } else {
    parent_key_requirement_default
  }
  if (!parent_key %in% parent_key_requirements) {
    cat("unknown parent_key:", parent_key, "\n")
    quit(status = 2L)
  }
  mp_arg <- grep("^max_pairs=", args, value = TRUE)
  max_pairs <- if (length(mp_arg)) {
    as.integer(sub("^max_pairs=", "", utils::tail(mp_arg, 1)))
  } else {
    50000L
  }
  if (is.na(max_pairs) || max_pairs < 1L) {
    cat("max_pairs must be a positive integer\n")
    quit(status = 2L)
  }
  want <- setdiff(args, c(pk_arg, mp_arg))
  if (length(want) == 0) {
    want <- c("chinook", "pagila", "lahman", "faers")
  }
  cat("dataset  shape and result\n")
  cat(
    "settings parent_key =", parent_key,
    " max_pairs =", max_pairs,
    " truth =", truth_dir(), "\n"
  )
  for (w in want) {
    switch(
      w,
      chinook = run_chinook(parent_key, max_pairs),
      pagila = run_pagila(),
      lahman = run_lahman(parent_key, max_pairs),
      faers = run_faers(parent_key, max_pairs),
      cat("unknown dataset:", w, "\n")
    )
  }
  if (truth_failures > 0L) {
    cat(sprintf(
      "\n%d dataset(s) have ground truth that does not resolve against the data\n",
      truth_failures
    ))
    quit(status = 1L)
  }
}
