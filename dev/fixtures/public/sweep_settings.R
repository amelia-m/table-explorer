# Measure the detection settings against the public schemas.
#
# Why this exists: the rules that decide which foreign keys are reported
# are settings now, and nobody can say which combination suits which kind
# of schema because no combination other than the shipped one has been
# measured. PR #54's three rules have never been measured apart: every
# figure quoted anywhere is all three applied at once. This runs a grid
# over the six switches, writes one row per combination per dataset, and
# prints the recall-precision frontier so a preset list can be chosen
# from measured numbers rather than from taste.
#
#   Rscript dev/fixtures/public/sweep_settings.R
#   Rscript dev/fixtures/public/sweep_settings.R chinook
#   Rscript dev/fixtures/public/sweep_settings.R chinook lahman
#
# Datasets default to chinook, lahman and faers. Pagila is out: it needs a
# running PostgreSQL instance (Amelia, 2026-10-10).
#
# Nothing is fetched here. A dataset that is not in the cache stops the
# run before any scoring starts and no file is written, because a sweep
# that silently skips a dataset under-reports and reads as a whole one.
#
# Sourcing this file into an environment that already defines
# .sweep_no_setup gives its functions without running anything, which is
# how tests/testthat/test-inference.R exercises the loading step.
#
# Two things about the results file that its columns do not say. The `set`
# column records where a combination was first reached, not what it is:
# the sets are deduped in the order default, single flips, grid, variants,
# stack, so the all-flipped combination reads "grid" on chinook, whose
# grid contains it, and "stack" on the datasets whose grid does not.
# Filter on the settings columns, never on `set`, to compare one
# combination across datasets. And `secs` is the detection time for that
# run only, after two discarded warm-up runs per dataset; it is not a
# forecast for a cold process. The warm-up runs at the defaults, so a
# wider scan path can still pay a partial warm-up the first time it
# appears: Chinook's first composite row measured 2.74s against 1.66 to
# 2.15s over seven later rows doing identical work. Run-to-run spread on
# a shared desktop is of the same order, which is why the column ranks
# cost coarsely rather than benchmarking it.

# Named for this file, not .no_setup: score_public.R defines a variable of
# that name when it is sourced below, and sourcing it into the same
# environment overwrote the flag and silently skipped the whole driver.
.sweep_run <- !exists(".sweep_no_setup", inherits = TRUE)

if (.sweep_run) {
  Sys.setenv(RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE")
  suppressMessages(pkgload::load_all(".", quiet = TRUE))
}

# The harness's own helpers, so the sweep loads the same tables and reads
# the same ground truth score_public.R scores. Both flags suppress the
# drivers at the bottom of those files.
.fetch_no_setup <- TRUE
.score_public_no_setup <- TRUE
source("dev/fixtures/public/fetch.R", local = TRUE, echo = FALSE)
source("dev/fixtures/public/score_public.R", local = TRUE, echo = FALSE)

# ── The pair cap ─────────────────────────────────────────────
# High enough that no combination measured here is truncated: the most
# expensive one (Lahman at parent_key = "composite") scores 117,620 pairs,
# and the default 50,000 cut it off at 60.9% recall where the whole scan
# reaches 95.7%. A capped row's recall is an artefact of where the scan
# stopped, so the cap is raised rather than the rows being flagged and
# read anyway. Every row records the pairs it scored and whether it was
# capped, so this stays checkable rather than assumed.
sweep_max_pairs <- 2000000L

# Switched off rather than removed: containment_min_distinct is a floor on
# the child's distinct count, so a floor no real column can reach is the
# signal never firing. Ten million rather than .Machine$integer.max so the
# value reads as a deliberate "off" in the results file.
containment_off <- 10000000L

# ── The grid ─────────────────────────────────────────────────
# Six switches, each at its default and at one alternative, is 64
# combinations. The alternatives, and why each is the one worth measuring:
#
#   parent_key_requirement  "key" -> "composite". "any" is documented in
#       utils_inference.R as a measurement bound rather than a setting to
#       ship, and it is the expensive one, so it is a Chinook-only variant
#       below instead of half the grid.
#   prose_parent_guard      "allow" -> "refuse_target". Measurement showed
#       "refuse" does nothing on its own for the Chinook pair the guard
#       exists for, so the level that can move a number is in the grid and
#       "refuse" is a variant.
#   containment_min_distinct  3 -> off. The question the grid asks is
#       whether the containment signal earns its place, not where its
#       floor belongs; 12 is a variant.
#   overlap_chance_discount  TRUE -> FALSE, carrying its threshold with
#       it: the Amendment counts the discount and its threshold as one
#       switch. With the discount off the threshold is inert, so those
#       rows record the threshold as NA and collapse onto each other,
#       which is why the threshold variants below keep the discount on.
#   cardinality_min_distinct  12 -> 1. One admits every pair of identical
#       value sets, which is the floor switched off.
#   possible_key_names      TRUE -> FALSE. The tier either runs or it does
#       not.
grid_axes <- list(
  parent_key_requirement = c("key", "composite"),
  prose_parent_guard = c("allow", "refuse_target"),
  containment_min_distinct = c(containment_min_distinct_default, containment_off),
  overlap_chance_discount = c(TRUE, FALSE),
  cardinality_min_distinct = c(cardinality_min_distinct_default, 1L),
  possible_key_names = c(TRUE, FALSE)
)

settings_default <- function() {
  list(
    parent_key_requirement = parent_key_requirement_default,
    prose_parent_guard = prose_parent_guard_default,
    containment_min_distinct = containment_min_distinct_default,
    overlap_chance_discount = overlap_chance_discount_default,
    overlap_chance_max_distinct = overlap_chance_max_distinct_default,
    cardinality_min_distinct = cardinality_min_distinct_default,
    possible_key_names = possible_key_names_default
  )
}

setting_names <- names(settings_default())

# The threshold is inert when the discount is off, so the two rows that
# differ only in it are the same run. Canonicalising to NA before the
# dedup is what makes "record the combination once, not twice" true of
# the output rather than only of the intention.
canonical_settings <- function(s) {
  if (!isTRUE(s$overlap_chance_discount)) {
    s$overlap_chance_max_distinct <- NA_integer_
  }
  s
}

settings_key <- function(s) {
  s <- canonical_settings(s)
  paste(vapply(setting_names, function(n) as.character(s[[n]]), ""), collapse = "|")
}

# One row per combination, deduped, defaults first so the reproduction
# check is the first thing a reader sees.
dedup_combos <- function(combos) {
  keys <- vapply(combos, function(c) settings_key(c$settings), "")
  combos[!duplicated(keys)]
}

full_grid <- function(axes = grid_axes) {
  vals <- expand.grid(axes, stringsAsFactors = FALSE)
  lapply(seq_len(nrow(vals)), function(i) {
    s <- settings_default()
    for (n in names(axes)) s[[n]] <- vals[[n]][[i]]
    list(settings = s, set = "grid")
  })
}

# One flip from the default, which is the whole reason this task exists:
# the three rules PR #54 added have only ever been measured together.
single_flips <- function(axes = grid_axes) {
  out <- list()
  for (n in names(axes)) {
    alts <- setdiff(axes[[n]], settings_default()[[n]])
    for (a in alts) {
      s <- settings_default()
      s[[n]] <- a
      out[[length(out) + 1]] <- list(settings = s, set = "flip")
    }
  }
  out
}

one_off <- function(set, ...) {
  s <- utils::modifyList(settings_default(), list(...))
  list(settings = s, set = set)
}

all_flipped <- function(axes = grid_axes) {
  s <- settings_default()
  for (n in names(axes)) {
    s[[n]] <- setdiff(axes[[n]], settings_default()[[n]])[[1]]
  }
  list(settings = s, set = "stack")
}

# Variants outside the 64: values the grid does not reach, each cheap
# enough to be worth a row on the two fast datasets.
cheap_variants <- function() {
  list(
    # The third documented guard level
    one_off("variant", prose_parent_guard = "refuse"),
    # A middle containment floor rather than off
    one_off("variant", containment_min_distinct = 12L),
    # The discount still applied, reaching narrower and wider children
    one_off("variant", overlap_chance_max_distinct = 12L),
    one_off("variant", overlap_chance_max_distinct = 100L),
    # A stricter cardinality floor rather than a looser one
    one_off("variant", cardinality_min_distinct = 100L)
  )
}

# ── What runs where, and why it is not the same everywhere ────
# Chinook is about 3 seconds a run and takes the full grid plus every
# variant. Lahman is 18 seconds at "key" and 122 at "composite", so 64
# runs would be about 65 minutes, past the contract's 30-minute stop
# line: it takes the 32 combinations at parent_key = "key" plus the single
# composite flip. FAERS is 50 seconds at "key" and 148 at "composite", so
# it takes the reduced set the Amendment names: the default, every single
# flip, the full stack, and every combination on the Chinook or Lahman
# frontier.
combos_for <- function(dataset, frontier = list()) {
  base <- c(list(one_off("default")), single_flips())
  combos <- switch(
    dataset,
    chinook = c(
      base,
      full_grid(),
      cheap_variants(),
      # "any" is measured on the cheapest dataset only: it is the lower
      # bound on precision and the upper bound on recall, and on the
      # larger schemas it offers every column as a parent.
      list(one_off("variant", parent_key_requirement = "any")),
      list(all_flipped())
    ),
    lahman = c(
      base,
      full_grid(utils::modifyList(
        grid_axes,
        list(parent_key_requirement = "key")
      )),
      cheap_variants(),
      list(all_flipped())
    ),
    faers = c(
      base,
      list(all_flipped()),
      lapply(frontier, function(s) list(settings = s, set = "frontier"))
    ),
    stop(sprintf("unknown dataset: %s", dataset))
  )
  dedup_combos(combos)
}

# ── Loading ──────────────────────────────────────────────────
# Loads whole tables, no row cap: a foreign key is a claim about value
# containment, so reading part of a table breaks the property being
# measured. Stops on a dataset that is unknown or not in the cache, which
# is what keeps a partial sweep from being written at all.
load_dataset <- function(name) {
  if (identical(name, "chinook")) {
    f <- file.path(public_cache(), "chinook.sqlite")
    if (!file.exists(f)) {
      stop(sprintf("chinook is not in the cache (%s): run fetch.R", f))
    }
    return(list(
      name = name,
      tables = tables_from_sqlite(f),
      truth = truth_from_sqlite(f)
    ))
  }
  if (identical(name, "lahman")) {
    tabs <- tables_from_lahman()
    if (is.null(tabs)) {
      stop("lahman needs install.packages(\"Lahman\")")
    }
    return(list(name = name, tables = tabs, truth = read_truth_file("lahman.txt")))
  }
  if (identical(name, "faers")) {
    tabs <- tables_from_faers()
    if (is.null(tabs)) {
      stop("faers is not in the cache: run fetch.R faers")
    }
    return(list(name = name, tables = tabs, truth = read_truth_file("faers.txt")))
  }
  stop(sprintf("unknown dataset: %s", name))
}

# Precision is NA with no candidates, not 0: a combination that reports
# nothing has no precision, and reading that as 0 would put it at the
# wrong end of a frontier. A file-level function rather than a closure so
# a test can reach it, because no dataset in the harness produces a row
# with nothing found and the rule would otherwise be checked by reading.
rate <- function(num, den) if (den > 0) 100 * num / den else NA_real_

# ── One run ──────────────────────────────────────────────────
# The same arithmetic score_one() prints, over the same pair strings, with
# every setting passed rather than three of them.
run_combo <- function(ds, combo, commit, today, run_index = NA_integer_) {
  s <- combo$settings
  t0 <- Sys.time()
  rels <- detect_fks(
    ds$tables,
    method = "both",
    min_confidence = "medium",
    max_pairs = sweep_max_pairs,
    containment_min_distinct = s$containment_min_distinct,
    parent_key_requirement = s$parent_key_requirement,
    prose_parent_guard = s$prose_parent_guard,
    overlap_chance_discount = s$overlap_chance_discount,
    overlap_chance_max_distinct = s$overlap_chance_max_distinct,
    cardinality_min_distinct = s$cardinality_min_distinct,
    possible_key_names = s$possible_key_names
  )
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  as_pair <- function(r) pair(r$from_table, r$from_col, r$to_table, r$to_col %||% "")
  found <- if (length(rels)) unique(vapply(rels, as_pair, "")) else character(0)
  hit <- intersect(found, ds$truth)
  high <- Filter(function(r) identical(r$confidence %||% "low", "high"), rels)
  hfound <- if (length(high)) unique(vapply(high, as_pair, "")) else character(0)
  hhit <- intersect(hfound, ds$truth)
  sc <- canonical_settings(s)
  data.frame(
    dataset = ds$name,
    set = combo$set,
    parent_key_requirement = sc$parent_key_requirement,
    prose_parent_guard = sc$prose_parent_guard,
    containment_min_distinct = sc$containment_min_distinct,
    overlap_chance_discount = sc$overlap_chance_discount,
    overlap_chance_max_distinct = sc$overlap_chance_max_distinct,
    cardinality_min_distinct = sc$cardinality_min_distinct,
    possible_key_names = sc$possible_key_names,
    is_default = identical(settings_key(s), settings_key(settings_default())),
    tables = length(ds$tables),
    truth = length(ds$truth),
    found = length(found),
    hit = length(hit),
    recall = rate(length(hit), length(ds$truth)),
    precision = rate(length(hit), length(found)),
    high_found = length(hfound),
    high_hit = length(hhit),
    high_recall = rate(length(hhit), length(ds$truth)),
    high_precision = rate(length(hhit), length(hfound)),
    pairs_scored = attr(rels, "pairs_scored") %||% NA_integer_,
    max_pairs = sweep_max_pairs,
    capped = isTRUE(attr(rels, "truncated")),
    secs = round(secs, 2),
    # Where in this dataset's order the run sat. The caches in
    # utils_inference.R (clean_name, lookup, naming_signal) persist across
    # detect_fks() calls in one process, so the first scored run of a
    # dataset pays a warm-up the rest do not: the first sweep recorded
    # 2.64s for Chinook's default against 0.54 to 0.91s for 21 other rows
    # that scored the identical 776 pairs. Two discarded warm-up passes
    # per dataset now absorb it, and this column is here so a reader can
    # still see the order rather than take that on trust.
    run_index = as.integer(run_index),
    commit = commit,
    date = format(today),
    stringsAsFactors = FALSE
  )
}

# ── The frontier ─────────────────────────────────────────────
# The combinations no other combination beats on both recall and precision
# at once. Rows that found nothing are left out: with no candidates there
# is no precision to compare, so they cannot be read against anything.
frontier_rows <- function(df, recall_col = "high_recall", prec_col = "high_precision") {
  keep <- df[!is.na(df[[recall_col]]) & !is.na(df[[prec_col]]), , drop = FALSE]
  if (nrow(keep) == 0) {
    return(keep)
  }
  dominated <- vapply(seq_len(nrow(keep)), function(i) {
    r <- keep[[recall_col]][i]
    p <- keep[[prec_col]][i]
    any(
      keep[[recall_col]] >= r & keep[[prec_col]] >= p &
        (keep[[recall_col]] > r | keep[[prec_col]] > p)
    )
  }, logical(1))
  keep[!dominated, , drop = FALSE]
}

# How many switches this row moved from the default. Used to choose the
# plainest of several combinations that score identically.
flips_from_default <- function(row) {
  d <- settings_default()
  sum(vapply(
    setting_names,
    function(n) {
      !identical(as.character(row[[n]]), as.character(d[[n]])) &&
        !(is.na(row[[n]]) && n == "overlap_chance_max_distinct")
    },
    logical(1)
  ))
}

# The frontier collapsed to its distinct recall-precision points, with one
# representative combination each: the fewest switches moved, then the
# fastest. Measurement showed why this is needed rather than tidier: on
# Chinook every one of the 24 non-dominated rows scores 81.8 / 100.0,
# because they all carry prose refuse_target and differ only in switches
# that change nothing there. Reading 24 tied rows as 24 findings, and
# worse, running all 24 on the dataset that costs 50 seconds a run, is
# what this avoids. n_tied says how many combinations share the point.
frontier_points <- function(df,
                            recall_col = "high_recall",
                            prec_col = "high_precision") {
  fr <- frontier_rows(df, recall_col, prec_col)
  if (nrow(fr) == 0) {
    return(fr)
  }
  fr$n_tied <- NA_integer_
  keys <- paste(fr[[recall_col]], fr[[prec_col]])
  out <- lapply(unique(keys), function(k) {
    tied <- fr[keys == k, , drop = FALSE]
    nflip <- vapply(
      seq_len(nrow(tied)),
      function(i) flips_from_default(tied[i, , drop = FALSE]),
      integer(1)
    )
    pick <- order(nflip, tied$secs)[1]
    row <- tied[pick, , drop = FALSE]
    row$n_tied <- nrow(tied)
    row
  })
  out <- do.call(rbind, out)
  out[order(-out[[recall_col]], -out[[prec_col]]), , drop = FALSE]
}

settings_in_words <- function(row) {
  d <- settings_default()
  bits <- character(0)
  say <- function(n, fmt) {
    if (!identical(as.character(row[[n]]), as.character(d[[n]]))) {
      bits <<- c(bits, sprintf(fmt, row[[n]]))
    }
  }
  say("parent_key_requirement", "parent key %s")
  say("prose_parent_guard", "prose %s")
  say("containment_min_distinct", "containment floor %s")
  if (!isTRUE(row$overlap_chance_discount)) {
    bits <- c(bits, "chance discount off")
  } else {
    say("overlap_chance_max_distinct", "chance ceiling %s")
  }
  say("cardinality_min_distinct", "cardinality floor %s")
  if (!isTRUE(row$possible_key_names)) {
    bits <- c(bits, "possible key names off")
  }
  if (length(bits) == 0) "the defaults" else paste(bits, collapse = ", ")
}

# ── The driver ───────────────────────────────────────────────
# Loads every dataset first, runs every combination, and only then writes.
# A failure anywhere leaves no file: a half-written sweep read as a whole
# one under-reports, which is worse than no file at all.
sweep <- function(datasets = c("chinook", "lahman", "faers"),
                  out_dir = "dev/fixtures/public",
                  run_fn = run_combo) {
  today <- Sys.Date()
  # Checked before the datasets are read rather than at the write: twenty
  # minutes of scoring thrown away because a directory does not exist is
  # the same loss as a failed run, for a reason that costs one line to
  # rule out.
  if (!dir.exists(out_dir)) {
    stop(sprintf("out_dir does not exist: %s", out_dir))
  }
  # The commit, and whether the tree it ran from matched it. A row that
  # names a commit whose code did not produce it is worse than a row with
  # no commit at all: the first sweep recorded a commit made a minute
  # after the run started, from a tree that still held the fixes being
  # tested, and nothing in the file said so.
  commit <- tryCatch(
    {
      sha <- trimws(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE))
      # system2 returns character(0) with a warning when git fails rather
      # than raising, and a zero-length commit would make the data.frame
      # below error on differing row counts instead of recording "no
      # commit".
      if (length(sha) != 1L || !nzchar(sha)) {
        NA_character_
      } else {
        dirty <- length(system2(
          "git",
          c("status", "--porcelain", "--untracked-files=no"),
          stdout = TRUE
        )) > 0L
        if (dirty) paste0(sha, "+dirty") else sha
      }
    },
    error = function(e) NA_character_
  )
  loaded <- lapply(datasets, function(d) {
    cat(sprintf("loading %s\n", d))
    ds <- load_dataset(d)
    bad <- validate_truth(ds$tables, ds$truth)
    if (length(bad)) {
      stop(sprintf(
        "%s ground truth does not resolve: %s",
        d, paste(bad, collapse = "; ")
      ))
    }
    cat(sprintf("  %s: %d tables, %d declared links\n", d, length(ds$tables), length(ds$truth)))
    ds
  })
  rows <- list()
  for (ds in loaded) {
    frontier <- list()
    if (identical(ds$name, "faers") && length(rows)) {
      done <- do.call(rbind, rows)
      # Per dataset, then the union: a frontier is only meaningful within
      # one schema, and the Amendment asks for every combination on the
      # Chinook or Lahman frontier, not on a pooled one.
      fr <- do.call(rbind, lapply(
        unique(done$dataset),
        function(d) frontier_points(done[done$dataset == d, , drop = FALSE])
      ))
      frontier <- lapply(seq_len(nrow(fr)), function(i) {
        s <- settings_default()
        for (n in setting_names) {
          v <- fr[[n]][i]
          if (!is.na(v)) s[[n]] <- v
        }
        s
      })
      cat(sprintf(
        "faers takes the reduced set plus %d frontier combination(s) from the faster datasets\n",
        length(frontier)
      ))
    }
    combos <- combos_for(ds$name, frontier)
    cat(sprintf("%s: %d combinations\n", ds$name, length(combos)))
    # Warm-up, discarded, twice. The caches in utils_inference.R live for
    # the whole process, so without this the first combination of each
    # dataset carries the cost of filling them and its seconds are not
    # comparable with any other row's: measured at 2.64s against 0.54 to
    # 0.91s for 21 Chinook rows that scored the identical 776 pairs to
    # identical results. It is always the default combination, which is
    # the row every reader compares against. Twice because R compiles a
    # function on its second or third call, so one pass left a residual
    # (1.6s against 0.4 to 0.9s on the same rows).
    for (w in 1:2) {
      cat(sprintf("  warming the caches (%d of 2)\n", w))
      invisible(run_fn(ds, one_off("warmup"), commit, today, run_index = 0L))
    }
    for (i in seq_along(combos)) {
      # The progress line is printed after the run, so a failure would
      # otherwise leave the reader to infer which combination errored from
      # the last line that printed. The whole sweep still fails and still
      # writes nothing; it just says what it was doing.
      row <- tryCatch(
        run_fn(ds, combos[[i]], commit, today, run_index = i),
        error = function(e) {
          stop(sprintf(
            "%s combination %d of %d (%s) failed: %s",
            ds$name, i, length(combos),
            settings_in_words(as.data.frame(
              canonical_settings(combos[[i]]$settings),
              stringsAsFactors = FALSE
            )),
            conditionMessage(e)
          ), call. = FALSE)
        }
      )
      cat(sprintf(
        "  %-8s %3d/%3d  %-9s  found %4d hit %3d  recall %5.1f  prec %5.1f  high %5.1f/%5.1f  %6.1fs  %s\n",
        ds$name, i, length(combos), combos[[i]]$set,
        row$found, row$hit, row$recall, row$precision,
        row$high_recall, row$high_precision, row$secs,
        settings_in_words(row)
      ))
      rows[[length(rows) + 1]] <- row
    }
  }
  out <- do.call(rbind, rows)
  path <- file.path(out_dir, sprintf("sweep-%s.csv", format(today)))
  utils::write.csv(out, path, row.names = FALSE, na = "NA")
  cat(sprintf("\nwrote %s: %d rows\n", path, nrow(out)))
  summarise(out)
  invisible(out)
}

summarise <- function(out) {
  for (d in unique(out$dataset)) {
    df <- out[out$dataset == d, , drop = FALSE]
    base <- df[df$is_default, , drop = FALSE]
    cat(sprintf("\n── %s ──  %d rows\n", d, nrow(df)))
    if (nrow(base)) {
      cat(sprintf(
        "defaults: recall %.1f precision %.1f overall; recall %.1f precision %.1f at high\n",
        base$recall[1], base$precision[1], base$high_recall[1], base$high_precision[1]
      ))
    }
    for (lab in c("high", "overall")) {
      cols <- if (lab == "high") {
        c("high_recall", "high_precision")
      } else {
        c("recall", "precision")
      }
      fr <- frontier_points(df, cols[1], cols[2])
      cat(sprintf(
        "frontier at %s confidence (%d point(s), %d combination(s)):\n",
        lab, nrow(fr), sum(fr$n_tied)
      ))
      for (i in seq_len(nrow(fr))) {
        cat(sprintf(
          "  recall %5.1f  precision %5.1f  found %4d  hit %3d  %6.1fs  %s%s%s\n",
          fr[[cols[1]]][i], fr[[cols[2]]][i], fr$found[i], fr$hit[i], fr$secs[i],
          settings_in_words(fr[i, , drop = FALSE]),
          if (fr$n_tied[i] > 1) {
            sprintf("  (+%d tied)", fr$n_tied[i] - 1L)
          } else {
            ""
          },
          if (isTRUE(fr$capped[i])) "  CAPPED" else ""
        ))
      }
    }
    flips <- df[df$set %in% c("flip", "variant"), , drop = FALSE]
    if (nrow(flips)) {
      cat("one flip from the default:\n")
      for (i in seq_len(nrow(flips))) {
        cat(sprintf(
          "  high recall %5.1f  precision %5.1f  (overall %5.1f/%5.1f)  %s\n",
          flips$high_recall[i], flips$high_precision[i],
          flips$recall[i], flips$precision[i],
          settings_in_words(flips[i, , drop = FALSE])
        ))
      }
    }
  }
}

if (.sweep_run) {
  args <- commandArgs(trailingOnly = TRUE)
  want <- if (length(args)) args else c("chinook", "lahman", "faers")
  ok <- tryCatch({
    sweep(want)
    TRUE
  }, error = function(e) {
    cat("sweep failed, nothing written: ", conditionMessage(e), "\n", sep = "")
    FALSE
  })
  quit(status = if (ok) 0L else 1L)
}
