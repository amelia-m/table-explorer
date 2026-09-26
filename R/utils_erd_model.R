# ============================================================
# utils_erd_model.R - Shared ERD model
# ============================================================
#
# Derives the facts a standard physical ERD needs from the loaded tables and
# detected relationships: column types / nullability / key badges, table
# roles and subject areas, and per-relationship cardinality, optionality,
# identifying-ness and provenance. Exports (Mermaid, DBML, ELK) and the ERD
# view read this model so every output shows the same thing.
#
# Cardinality is inferred from a data snapshot:
#   child_max  "one" when the FK column is unique in the child (1:1),
#              otherwise "many"
#   parent_min "zero" when the FK column has NULLs (optional parent),
#              otherwise "one"
#   child_min  always "zero": a snapshot can't prove every parent has a child
# Empty (0-row) child tables give "unknown".
#
# @noRd

# Readable physical type for a column
erd_col_type <- function(x) {
  if (is.logical(x)) {
    return("bool")
  }
  if (inherits(x, "POSIXt")) {
    return("datetime")
  }
  if (inherits(x, "Date")) {
    return("date")
  }
  if (is.numeric(x)) {
    v <- x[!is.na(x) & is.finite(x)]
    if (is.integer(x) || (length(v) > 0 && all(v == round(v)))) {
      return("int")
    }
    return(if (length(v) == 0) "int" else "float")
  }
  "string"
}

erd_col_type_vec <- function(df) {
  vapply(df, erd_col_type, character(1))
}

# Where a relationship came from
erd_provenance <- function(r) {
  by <- r$detected_by %||% ""
  if (identical(by, "schema")) {
    "declared"
  } else if (identical(by, "manual")) {
    "manual"
  } else if (isTRUE(r$confirmed)) {
    "confirmed"
  } else {
    "inferred"
  }
}

# The table's primary key. pk_map lists every candidate key (all unique
# columns), so pick one: a generic id, then the table's own key
# (client_id in clients), then a key-named column, then the first. With no
# single-column candidate, fall back to the first composite key group.
erd_primary_key <- function(
  tname,
  candidates,
  composite_groups = NULL,
  n_fks = 0L
) {
  candidates <- candidates %||% character(0)
  if (length(candidates) == 0) {
    groups <- composite_groups %||% list()
    return(if (length(groups) > 0) groups[[1]] else character(0))
  }
  cc <- clean_name(candidates)
  tc <- clean_name(tname)
  score <- ifelse(
    cc %in% generic_key_names,
    3L,
    ifelse(
      vapply(cc, owns_key, logical(1), tname_clean = tc),
      2L,
      ifelse(is_key_name(cc), 1L, 0L)
    )
  )
  # A table with several FKs and no key-named candidate is usually keyed by
  # its FKs (product_suppliers); don't promote an attribute that happens to
  # be unique
  if (max(score) == 0 && n_fks >= 2) {
    groups <- composite_groups %||% list()
    return(if (length(groups) > 0) groups[[1]] else character(0))
  }
  candidates[order(-score, seq_along(candidates))][[1]]
}

erd_model <- function(tables, rels, pk_map, composite_pk_map = NULL) {
  tnames <- sort(names(tables))
  rels <- Filter(
    function(r) r$from_table %in% tnames && r$to_table %in% tnames,
    rels %||% list()
  )
  # Deterministic relationship order
  if (length(rels) > 0) {
    ord <- order(
      vapply(rels, `[[`, character(1), "from_table"),
      vapply(rels, `[[`, character(1), "from_col"),
      vapply(rels, `[[`, character(1), "to_table")
    )
    rels <- rels[ord]
  }

  primary_keys <- lapply(names(tables), function(t) {
    df <- tables[[t]]
    cands <- intersect(pk_map[[t]] %||% character(0), names(df))
    # detect_pks also flags PK-named columns that aren't unique; with data,
    # only a truly unique column can be the primary key
    if (nrow(df) > 0) {
      cands <- cands[vapply(
        cands,
        function(cn) !anyNA(df[[cn]]) && !anyDuplicated(df[[cn]]),
        logical(1)
      )]
      # A column that is unique by chance (unit_cost, a timestamp) is not a
      # key unless its name says so
      cands <- cands[
        erd_col_type_vec(df[cands]) %in% c("int", "string") |
          is_key_name(clean_name(cands)) |
          clean_name(cands) %in% generic_key_names
      ]
    }
    n_fks <- length(unique(unlist(lapply(
      Filter(function(r) r$from_table == t, rels),
      function(r) r$from_col
    ))))
    erd_primary_key(
      t,
      cands,
      if (!is.null(composite_pk_map)) composite_pk_map[[t]],
      n_fks
    )
  })
  names(primary_keys) <- names(tables)
  pk_cols_of <- function(t) primary_keys[[t]] %||% character(0)

  # ── Relationships ──────────────────────────────────────────
  rels <- lapply(rels, function(r) {
    child <- tables[[r$from_table]]
    fk <- child[[r$from_col]]
    empty <- is.null(fk) || nrow(child) == 0
    r$child_max <- if (empty) {
      "unknown"
    } else if (!anyNA(fk) && length(unique(fk)) == length(fk)) {
      "one"
    } else {
      "many"
    }
    r$parent_min <- if (empty) {
      "unknown"
    } else if (anyNA(fk)) {
      "zero"
    } else {
      "one"
    }
    r$child_min <- "zero"
    r$identifying <- r$from_col %in% pk_cols_of(r$from_table)
    r$self_ref <- identical(r$from_table, r$to_table)
    r$provenance <- erd_provenance(r)
    r
  })

  # ── Tables ─────────────────────────────────────────────────
  fk_cols_of <- function(t) {
    unique(vapply(
      Filter(function(r) r$from_table == t, rels),
      `[[`,
      character(1),
      "from_col"
    ))
  }
  target_cols_of <- function(t) {
    unique(unlist(lapply(
      Filter(function(r) r$to_table == t, rels),
      function(r) r$to_col
    )))
  }
  linked <- unique(c(
    vapply(rels, `[[`, character(1), "from_table"),
    vapply(rels, `[[`, character(1), "to_table")
  ))

  tbl_models <- lapply(tnames, function(t) {
    df <- tables[[t]]
    n <- nrow(df)
    pks <- pk_cols_of(t)
    fks <- fk_cols_of(t)
    targets <- target_cols_of(t)
    cols <- names(df)
    # PK columns first, then original order
    cols <- c(intersect(cols, pks), setdiff(cols, pks))
    fk_in_order <- intersect(names(df), fks)
    is_unique <- vapply(
      cols,
      function(cn) {
        v <- df[[cn]]
        n > 0 && !anyNA(v) && length(unique(v)) == n
      },
      logical(1)
    )
    columns <- data.frame(
      name = cols,
      type = vapply(cols, function(cn) erd_col_type(df[[cn]]), character(1)),
      nullable = if (n == 0) {
        rep(NA, length(cols))
      } else {
        vapply(cols, function(cn) anyNA(df[[cn]]), logical(1))
      },
      unique = unname(is_unique),
      pk = cols %in% pks,
      fk_index = match(cols, fk_in_order),
      stringsAsFactors = FALSE,
      row.names = NULL
    )
    columns$uk <- columns$unique &
      !columns$pk &
      (columns$name %in% targets | is_key_name(clean_name(columns$name)))

    non_key <- setdiff(names(df), union(pks, fks))
    # Junction: two or more FKs and either a PK made only of FKs, or its own
    # id with no other attributes (tblCONTACT_CAT: id + 3 FKs)
    role <- if (
      length(fks) >= 2 &&
        ((length(pks) > 0 && all(pks %in% fks)) || length(non_key) == 0)
    ) {
      "junction"
    } else if (is_lookup_name(t)) {
      # Named lookups only: the size-based lookup guess used for detection
      # would put every small table in the Lookups area
      "lookup"
    } else if (!t %in% linked) {
      "orphan"
    } else {
      "entity"
    }
    list(name = t, n_rows = n, role = role, columns = columns)
  })
  names(tbl_models) <- tnames

  # ── Subject areas ──────────────────────────────────────────
  # Lookups and orphans get their own groups; the rest are connected
  # components over links between non-lookup tables (lookups would otherwise
  # join everything), named after their largest table.
  area <- setNames(rep(NA_character_, length(tnames)), tnames)
  for (t in tnames) {
    role <- tbl_models[[t]]$role
    if (role == "lookup") area[[t]] <- "Lookups"
    if (role == "orphan") area[[t]] <- "Unconnected"
  }
  core <- tnames[is.na(area)]
  if (length(core) > 0) {
    parent <- setNames(core, core)
    find <- function(x) {
      while (parent[[x]] != x) x <- parent[[x]]
      x
    }
    for (r in rels) {
      a <- r$from_table
      b <- r$to_table
      if (a %in% core && b %in% core) {
        ra <- find(a)
        rb <- find(b)
        if (ra != rb) parent[[rb]] <- ra
      }
    }
    roots <- vapply(core, find, character(1))
    for (root in unique(roots)) {
      members <- core[roots == root]
      sizes <- vapply(members, function(m) tbl_models[[m]]$n_rows, numeric(1))
      label <- members[order(-sizes, members)][[1]]
      area[members] <- label
    }
  }
  for (t in tnames) {
    tbl_models[[t]]$subject_area <- area[[t]]
  }

  list(tables = tbl_models, rels = rels)
}
