# ============================================================
# utils_export.R - Export Format Generators
# ============================================================
#
# @noRd

# ── dbt schema.yml generator ──────────────────────────────────

generate_dbt_yaml <- function(tables, rels, pks, composite_pks = NULL) {
  lines <- c("version: 2", "", "models:")

  for (tname in names(tables)) {
    df <- tables[[tname]]
    lines <- c(lines, paste0("  - name: ", tname))
    lines <- c(lines, "    columns:")

    pk_cols <- pks[[tname]]
    cpk_groups <- if (!is.null(composite_pks)) {
      composite_pks[[tname]]
    } else {
      list()
    }
    cpk_cols <- unique(unlist(cpk_groups))
    t_rels <- Filter(function(r) r$from_table == tname, rels)
    # Every FK on a column gets its own relationships test
    fk_map <- split(t_rels, vapply(t_rels, `[[`, character(1), "from_col"))

    for (col in names(df)) {
      lines <- c(lines, paste0("      - name: ", col))

      tests <- character(0)
      if (col %in% pk_cols) {
        tests <- c(tests, "          - unique", "          - not_null")
      } else if (col %in% cpk_cols) {
        tests <- c(tests, "          - not_null")
      }
      for (r in fk_map[[col]]) {
        to_col <- if (!is.null(r$to_col) && !is.na(r$to_col)) r$to_col else col
        tests <- c(
          tests,
          paste0(
            "          - relationships:\n",
            "              to: ref('",
            r$to_table,
            "')\n",
            "              field: ",
            to_col
          )
        )
      }
      if (length(tests) > 0) {
        lines <- c(lines, "        tests:", tests)
      }
    }

    # Emit a dbt_utils unique_combination_of_columns test for composite keys
    if (length(cpk_groups) > 0) {
      lines <- c(lines, "    tests:")
      for (g in cpk_groups) {
        col_entries <- vapply(
          g,
          function(col) paste0("          - ", col),
          character(1L)
        )
        lines <- c(
          lines,
          "      - dbt_utils.unique_combination_of_columns:",
          "          combination_of_columns:",
          col_entries
        )
      }
    }
  }

  paste(lines, collapse = "\n")
}

# ── Shared helpers for ERD exports ────────────────────────────

# Mermaid/DBML-safe identifier: bare when simple, quoted otherwise
erd_ident <- function(x) {
  ifelse(
    grepl("^[A-Za-z_][A-Za-z0-9_]*$", x),
    x,
    paste0("\"", gsub("\"", "'", x), "\"")
  )
}

# Short provenance note, e.g. "inferred 87%"
erd_rel_note <- function(r) {
  if (identical(r$provenance, "inferred") && !is.null(r$score)) {
    sprintf("inferred %d%%", round(100 * r$score))
  } else {
    r$provenance
  }
}

# Header colours per subject area (stable: areas sorted by name)
erd_area_colors <- function(model) {
  areas <- sort(unique(vapply(
    model$tables,
    function(t) t$subject_area,
    character(1)
  )))
  palette <- c(
    "#1E3A5F", "#14532D", "#4C1D95", "#7C2D12", "#134E4A",
    "#713F12", "#831843", "#1E40AF", "#3F6212", "#9A3412"
  )
  cols <- palette[(seq_along(areas) - 1) %% length(palette) + 1]
  cols[areas == "Lookups"] <- "#475569"
  cols[areas == "Unconnected"] <- "#64748B"
  setNames(cols, areas)
}

# ── Mermaid ERD generator ─────────────────────────────────────
# Crow's-foot markers from the ERD model: parent end || (mandatory) or |o
# (optional FK), child end o{ (many) or o| (one). Lines are always solid
# (--): Mermaid draws each marker's centre line with the relationship line
# itself, so dashed (..) lines make the bars and crow's feet look broken and
# detached from the entity (seen in Mermaid 10 and 12). Identifying FKs
# remain visible as "PK, FK" columns. Output is sorted so diffs stay
# meaningful.

generate_mermaid_erd <- function(tables, rels, pks, composite_pks = NULL) {
  model <- erd_model(tables, rels, pks, composite_pks)
  lines <- c(
    "erDiagram",
    if (length(model$tables) > 0) {
      c(
        "    %% Crow's foot: || one, |o zero-or-one, o{ zero-or-many, o| zero-or-one.",
        "    %% Lines are solid on purpose; identifying FKs are the PK, FK columns.",
        "    %% Mermaid joins tables, not rows: labels name the FK -> key columns.",
        "    direction LR"
      )
    }
  )

  for (t in model$tables) {
    lines <- c(lines, paste0("    ", erd_ident(t$name), " {"))
    cols <- t$columns
    for (i in seq_len(nrow(cols))) {
      keys <- c(
        if (cols$pk[i]) "PK",
        if (!is.na(cols$fk_index[i])) "FK",
        if (cols$uk[i]) "UK"
      )
      comment <- if (isTRUE(cols$nullable[i])) " \"nullable\"" else ""
      lines <- c(
        lines,
        paste0(
          "        ",
          cols$type[i],
          " ",
          erd_ident(cols$name[i]),
          if (length(keys)) paste0(" ", paste(keys, collapse = ", ")) else "",
          comment
        )
      )
    }
    lines <- c(lines, "    }")
  }

  for (r in model$rels) {
    parent_end <- switch(r$parent_min, one = "||", zero = "|o", "|o")
    child_end <- switch(r$child_max, one = "o|", many = "o{", "o{")
    line <- "--"
    # Mermaid links entities, not rows, and places line ends evenly along
    # a box side, so name both columns in the label
    note <- erd_rel_note(r)
    cols <- paste0(r$from_col, " \u2192 ", r$to_col %||% r$from_col)
    label <- if (grepl("^inferred", note)) {
      paste0(cols, " (", note, ")")
    } else {
      cols
    }
    lines <- c(
      lines,
      paste0(
        "    ",
        erd_ident(r$to_table),
        " ",
        parent_end,
        line,
        child_end,
        " ",
        erd_ident(r$from_table),
        " : \"",
        gsub("\"", "'", label),
        "\""
      )
    )
  }

  paste(lines, collapse = "\n")
}

# ── DBML generator (dbdiagram.io / dbdocs) ────────────────────
# Keeps what Mermaid can't: not null, notes, composite PK indexes, subject
# area TableGroups and header colours, muted colour for inferred refs.

generate_dbml <- function(tables, rels, pks, composite_pks = NULL) {
  model <- erd_model(tables, rels, pks, composite_pks)
  colors <- erd_area_colors(model)
  lines <- character(0)

  for (t in model$tables) {
    cols <- t$columns
    lines <- c(
      lines,
      sprintf(
        "Table %s [headerColor: %s] {",
        erd_ident(t$name),
        colors[[t$subject_area]]
      )
    )
    single_pk <- sum(cols$pk) == 1
    for (i in seq_len(nrow(cols))) {
      settings <- c(
        if (cols$pk[i] && single_pk) "pk",
        if (cols$uk[i]) "unique",
        if (isFALSE(cols$nullable[i])) "not null"
      )
      lines <- c(
        lines,
        paste0(
          "  ",
          erd_ident(cols$name[i]),
          " ",
          cols$type[i],
          if (length(settings)) {
            paste0(" [", paste(settings, collapse = ", "), "]")
          } else {
            ""
          }
        )
      )
    }
    if (sum(cols$pk) > 1) {
      lines <- c(
        lines,
        "",
        "  indexes {",
        sprintf(
          "    (%s) [pk]",
          paste(erd_ident(cols$name[cols$pk]), collapse = ", ")
        ),
        "  }"
      )
    }
    lines <- c(
      lines,
      sprintf(
        "  Note: '%s; %s rows'",
        t$role,
        format(t$n_rows, big.mark = ",")
      ),
      "}",
      ""
    )
  }

  for (r in model$rels) {
    op <- if (identical(r$child_max, "one")) "-" else ">"
    settings <- if (identical(r$provenance, "inferred")) " [color: #94a3b8]" else ""
    reasons <- paste(r$reasons %||% character(0), collapse = "; ")
    lines <- c(
      lines,
      sprintf(
        "// %s%s",
        erd_rel_note(r),
        if (nzchar(reasons)) paste0(": ", reasons) else ""
      ),
      sprintf(
        "Ref: %s.%s %s %s.%s%s",
        erd_ident(r$from_table),
        erd_ident(r$from_col),
        op,
        erd_ident(r$to_table),
        erd_ident(r$to_col %||% r$from_col),
        settings
      )
    )
  }

  areas <- split(
    vapply(model$tables, function(t) t$name, character(1)),
    vapply(model$tables, function(t) t$subject_area, character(1))
  )
  for (a in sort(names(areas))) {
    lines <- c(
      lines,
      "",
      sprintf("TableGroup %s {", erd_ident(gsub("[^A-Za-z0-9_]", "_", a))),
      paste0("  ", erd_ident(areas[[a]])),
      "}"
    )
  }

  paste(lines, collapse = "\n")
}

# ── ELK graph generator (elkjs) ───────────────────────────────
# One node per table. Ports sit exactly on their column's row at the card
# border (FIXED_POS; FIXED_ORDER would ignore the coordinates and spread the
# ports evenly): `table.col:out` on the east side for FK sources and
# `table.col:in` on the west side for relationship targets, created only
# when used, so a PK+FK column can be both. Edge-node spacing keeps the
# final segment at each end longer than a crow's-foot marker. `properties`
# carries the ERD model (and the row geometry) so any elkjs-based renderer
# can draw a standard ERD.

erd_elk_row_height <- 20
erd_elk_header_height <- 28
erd_elk_marker_room <- 30

generate_elk_json <- function(tables, rels, pks, composite_pks = NULL) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return("{}")
  }
  model <- erd_model(tables, rels, pks, composite_pks)
  colors <- erd_area_colors(model)
  row_h <- erd_elk_row_height
  head_h <- erd_elk_header_height

  out_cols <- split(
    vapply(model$rels, `[[`, character(1), "from_col"),
    vapply(model$rels, `[[`, character(1), "from_table")
  )
  in_cols <- split(
    vapply(model$rels, function(r) r$to_col %||% r$from_col, character(1)),
    vapply(model$rels, `[[`, character(1), "to_table")
  )

  children <- lapply(model$tables, function(t) {
    cols <- t$columns
    width <- max(160, 8 * max(nchar(c(t$name, paste(cols$name, cols$type)))) + 60)
    port <- function(i, dir) {
      east <- identical(dir, "out")
      list(
        id = paste0(t$name, ".", cols$name[i], ":", dir),
        layoutOptions = list("elk.port.side" = if (east) "EAST" else "WEST"),
        x = if (east) width else 0,
        y = head_h + (i - 0.5) * row_h,
        width = 0,
        height = 0
      )
    }
    ports <- c(
      lapply(which(cols$name %in% out_cols[[t$name]]), port, dir = "out"),
      lapply(which(cols$name %in% in_cols[[t$name]]), port, dir = "in")
    )
    list(
      id = t$name,
      width = width,
      height = head_h + max(1, nrow(cols)) * row_h,
      layoutOptions = list("elk.portConstraints" = "FIXED_POS"),
      ports = ports,
      properties = list(
        role = t$role,
        subjectArea = t$subject_area,
        headerColor = colors[[t$subject_area]],
        rows = t$n_rows,
        columns = lapply(seq_len(nrow(cols)), function(i) {
          list(
            name = cols$name[i],
            type = cols$type[i],
            nullable = cols$nullable[i],
            pk = cols$pk[i],
            fk = if (is.na(cols$fk_index[i])) NULL else cols$fk_index[i],
            uk = cols$uk[i]
          )
        })
      )
    )
  })

  edges <- lapply(seq_along(model$rels), function(i) {
    r <- model$rels[[i]]
    list(
      id = paste0("rel", i),
      sources = list(paste0(r$from_table, ".", r$from_col, ":out")),
      targets = list(paste0(r$to_table, ".", r$to_col %||% r$from_col, ":in")),
      properties = list(
        childMax = r$child_max,
        childMin = r$child_min,
        parentMin = r$parent_min,
        identifying = isTRUE(r$identifying),
        selfRef = isTRUE(r$self_ref),
        provenance = r$provenance,
        detectedBy = r$detected_by %||% "",
        confidence = r$confidence %||% "",
        score = r$score %||% NA
      )
    )
  })

  graph <- list(
    id = "root",
    layoutOptions = list(
      "elk.algorithm" = "layered",
      "elk.direction" = "RIGHT",
      "elk.edgeRouting" = "ORTHOGONAL",
      "elk.layered.spacing.nodeNodeBetweenLayers" = 80,
      "elk.layered.spacing.edgeNodeBetweenLayers" = erd_elk_marker_room,
      "elk.spacing.edgeNode" = erd_elk_marker_room,
      # Self-references (manager_id -> id) loop around their own card
      "elk.spacing.nodeSelfLoop" = erd_elk_marker_room,
      "elk.spacing.nodeNode" = 40
    ),
    properties = list(
      rowHeight = row_h,
      headerHeight = head_h
    ),
    children = unname(children),
    edges = edges
  )
  jsonlite::toJSON(graph, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
}

# ── Session save/restore ──────────────────────────────────────

save_session_json <- function(
  tables,
  rels,
  manual_rels,
  schema_rels,
  settings = list(),
  review = list()
) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return("{}")
  }

  # Convert data frames to serializable format
  tables_ser <- lapply(tables, function(df) {
    lapply(df, function(col) {
      if (inherits(col, c("Date", "POSIXt"))) {
        as.character(col)
      } else {
        col
      }
    })
  })

  session <- list(
    version = 1L,
    timestamp = as.character(Sys.time()),
    tables = tables_ser,
    relationships = rels,
    manual_relationships = manual_rels,
    schema_relationships = schema_rels,
    settings = settings,
    # User review decisions: confirmed relationships and suppressed keys
    review = review
  )

  jsonlite::toJSON(session, auto_unbox = TRUE, pretty = TRUE, null = "null")
}

restore_session_json <- function(json_text) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(
      tables = list(),
      relationships = list(),
      manual_relationships = list(),
      schema_relationships = list(),
      settings = list(),
      review = list()
    ))
  }

  session <- jsonlite::fromJSON(json_text, simplifyVector = FALSE)

  # Reconstruct data frames
  tables <- list()
  if (!is.null(session$tables)) {
    for (tname in names(session$tables)) {
      tdata <- session$tables[[tname]]
      if (length(tdata) > 0) {
        # tdata is a named list of columns (each column is a list of values)
        col_list <- lapply(tdata, function(col) {
          if (is.list(col)) unlist(col) else col
        })
        df <- tryCatch(
          as.data.frame(col_list, stringsAsFactors = FALSE),
          error = function(e) as.data.frame(tdata, stringsAsFactors = FALSE)
        )
        tables[[tname]] <- df
      }
    }
  }

  list(
    tables = tables,
    relationships = session$relationships %||% list(),
    manual_relationships = session$manual_relationships %||% list(),
    schema_relationships = session$schema_relationships %||% list(),
    settings = session$settings %||% list(),
    review = session$review %||% list()
  )
}
