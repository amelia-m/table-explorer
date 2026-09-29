# ============================================================
# utils_export.R - Export Format Generators
# ============================================================
#
# @noRd

# ── dbt schema.yml generator ──────────────────────────────────

# dictionary: descriptions from the data dictionary (see
#   build_data_dictionary), written as dbt `description:` fields.
# constraints: also emit dbt >= 1.9 `constraints:` for primary keys and for
#   declared, manual or confirmed foreign keys. Unreviewed detected links
#   stay as relationships tests only.
generate_dbt_yaml <- function(
  tables,
  rels,
  pks,
  composite_pks = NULL,
  dictionary = list(),
  constraints = FALSE
) {
  # Constraints need one primary key per table: the model's choice among
  # the candidate keys
  # dbt only applies constraints when the model's contract is enforced, and
  # an enforced contract needs a data_type for every column. The model also
  # resolves FK target columns (a link that names only the parent table
  # points at the parent's key).
  m <- if (isTRUE(constraints)) erd_model(tables, rels, pks, composite_pks)
  model_pk <- if (!is.null(m)) {
    lapply(m$tables, function(t) t$columns$name[t$columns$pk])
  } else {
    list()
  }
  dbt_type <- c(
    int = "integer", float = "float", string = "varchar", date = "date",
    datetime = "timestamp", bool = "boolean"
  )
  yq <- function(x) paste0("\"", gsub("([\"\\\\])", "\\\\\\1", gsub("[\r\n]+", " ", x)), "\"")
  lines <- c(
    "version: 2",
    if (!is.null(m)) {
      c(
        "# Constraints need an enforced contract. data_type values are generic",
        "# (integer, float, varchar, date, timestamp, boolean): adjust them to",
        "# your warehouse's types if needed."
      )
    },
    "",
    "models:"
  )

  for (tname in names(tables)) {
    df <- tables[[tname]]
    lines <- c(lines, paste0("  - name: ", tname))
    t_desc <- dict_entry(dictionary, tname)$description
    if (nzchar(t_desc)) {
      lines <- c(lines, paste0("    description: ", yq(t_desc)))
    }
    if (!is.null(m)) {
      lines <- c(lines, "    config:", "      contract:", "        enforced: true")
    }
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
      c_desc <- dict_entry(dictionary, tname, col)$description
      if (nzchar(c_desc)) {
        lines <- c(lines, paste0("        description: ", yq(c_desc)))
      }
      if (!is.null(m)) {
        mcols <- m$tables[[tname]]$columns
        ctype <- mcols$type[match(col, mcols$name)]
        lines <- c(lines, paste0("        data_type: ", dbt_type[[ctype %||% "string"]] %||% "varchar"))
        cons <- character(0)
        if (length(model_pk[[tname]]) == 1 && col %in% model_pk[[tname]]) {
          cons <- c(cons, "          - type: primary_key")
        }
        m_fks <- Filter(function(r) r$from_table == tname && r$from_col == col, m$rels)
        for (r in m_fks) {
          if (!rel_source(r) %in% c("declared", "manual", "confirmed")) next
          to_col <- r$to_col
          cons <- c(
            cons,
            "          - type: foreign_key",
            paste0("            to: ref('", r$to_table, "')"),
            paste0("            to_columns: [", to_col, "]")
          )
        }
        if (length(cons) > 0) {
          lines <- c(lines, "        constraints:", cons)
        }
      }

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

generate_mermaid_erd <- function(tables, rels, pks, composite_pks = NULL, dictionary = list()) {
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
      # Attribute comments are double-quoted strings, so no double quotes inside
      note <- c(
        gsub("\"", "'", gsub("[\r\n]+", " ", dict_entry(dictionary, t$name, cols$name[i])$description)),
        if (isTRUE(cols$nullable[i])) "nullable"
      )
      note <- note[nzchar(note)]
      comment <- if (length(note)) paste0(" \"", paste(note, collapse = "; "), "\"") else ""
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

generate_dbml <- function(tables, rels, pks, composite_pks = NULL, dictionary = list()) {
  model <- erd_model(tables, rels, pks, composite_pks)
  # Escape backslashes first so a trailing "\" can't escape the closing quote
  dq <- function(x) gsub("'", "\\\\'", gsub("\\", "\\\\", gsub("[\r\n]+", " ", x), fixed = TRUE))
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
      c_desc <- dict_entry(dictionary, t$name, cols$name[i])$description
      settings <- c(
        if (cols$pk[i] && single_pk) "pk",
        if (cols$uk[i]) "unique",
        if (isFALSE(cols$nullable[i])) "not null",
        if (nzchar(c_desc)) sprintf("note: '%s'", dq(c_desc))
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
      {
        facts <- sprintf("%s; %s rows", t$role, format(t$n_rows, big.mark = ","))
        t_desc <- dict_entry(dictionary, t$name)$description
        sprintf(
          "  Note: '%s'",
          if (nzchar(t_desc)) sprintf("%s (%s)", dq(t_desc), facts) else facts
        )
      },
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
  graph <- erd_elk_graph(erd_model(tables, rels, pks, composite_pks))
  jsonlite::toJSON(graph, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
}

# ELK graph (as an R list) from an ERD model or an erd_view() result.
# detail: "all" columns, "keys" (only key/linked columns; a view already
# trims these) or "names" (header only; ports sit on the header).
# direction: ELK direction, "RIGHT" (left to right) or "DOWN".
# ref_labels: links to reference tables (lookups, code tables) become a label
#   on the FK row ("-> tlk_providers") instead of a line. Not with "names",
#   which has no rows to put them on.
# side: tables left without lines (unlinked ones, and lookups whose links are
#   all labels) are flagged for a column beside the diagram instead of the
#   layout: properties$side is "lookups" or "unlinked".
erd_elk_graph <- function(
  model,
  detail = "all",
  direction = "RIGHT",
  ref_labels = FALSE,
  side = FALSE
) {
  colors <- erd_area_colors(model)
  row_h <- erd_elk_row_height
  head_h <- erd_elk_header_height
  names_only <- identical(detail, "names")

  is_label <- vapply(model$rels, function(r) {
    isTRUE(ref_labels) && !names_only &&
      !identical(r$from_table, r$to_table) &&
      isTRUE(model$tables[[r$to_table]]$is_reference)
  }, logical(1))
  line_idx <- which(!is_label)
  line_rels <- model$rels[line_idx]
  label_rels <- model$rels[is_label]

  out_cols <- split(
    vapply(line_rels, `[[`, character(1), "from_col"),
    vapply(line_rels, `[[`, character(1), "from_table")
  )
  in_cols <- split(
    vapply(line_rels, function(r) r$to_col %||% r$from_col, character(1)),
    vapply(line_rels, `[[`, character(1), "to_table")
  )
  # Labels per child table and column
  labels_for <- function(tname, col) {
    Filter(function(r) r$from_table == tname && r$from_col == col, label_rels)
  }
  on_lines <- unique(unlist(lapply(line_rels, function(r) c(r$from_table, r$to_table))))
  label_parents <- unique(vapply(label_rels, `[[`, character(1), "to_table"))

  children <- lapply(model$tables, function(t) {
    cols <- t$columns
    label_text <- vapply(seq_len(nrow(cols)), function(i) {
      ls <- labels_for(t$name, cols$name[i])
      if (length(ls) == 0) "" else paste0("-> ", ls[[1]]$to_table, if (length(ls) > 1) " +1" else "")
    }, character(1))
    width <- max(
      160,
      8 * max(nchar(c(
        t$name,
        if (!names_only) paste(cols$name, cols$type, label_text)
      ))) + 60
    )
    port <- function(i, dir) {
      east <- identical(dir, "out")
      list(
        id = paste0(t$name, ".", cols$name[i], ":", dir),
        layoutOptions = list("elk.port.side" = if (east) "EAST" else "WEST"),
        x = if (east) width else 0,
        y = if (names_only) head_h / 2 else head_h + (i - 0.5) * row_h,
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
      height = if (names_only) head_h else head_h + max(1, nrow(cols)) * row_h,
      layoutOptions = list("elk.portConstraints" = "FIXED_POS"),
      ports = ports,
      properties = list(
        role = t$role,
        subjectArea = t$subject_area,
        headerColor = t$header_color %||% colors[[t$subject_area]],
        rows = t$n_rows,
        hiddenColumns = t$hidden_columns %||% 0L,
        columns = if (names_only) {
          list()
        } else {
          lapply(seq_len(nrow(cols)), function(i) {
            refs <- lapply(labels_for(t$name, cols$name[i]), function(r) {
              list(
                key = rel_key(r),
                table = r$to_table,
                col = r$to_col %||% r$from_col,
                provenance = r$provenance,
                confidence = r$confidence %||% ""
              )
            })
            col <- list(
              name = cols$name[i],
              type = cols$type[i],
              nullable = cols$nullable[i],
              pk = cols$pk[i],
              fk = if (is.na(cols$fk_index[i])) NULL else cols$fk_index[i],
              uk = cols$uk[i]
            )
            if (length(refs)) col$refs <- refs
            Filter(Negate(is.null), col)
          })
        },
        # Only set for tables beside the layout: elkjs rejects null values
        side = if (isTRUE(side) && !t$name %in% on_lines) {
          if (t$name %in% label_parents) "lookups" else "unlinked"
        }
      )
    )
  })
  children <- lapply(children, function(n) {
    n$properties <- Filter(Negate(is.null), n$properties)
    n
  })

  edges <- lapply(line_idx, function(i) {
    r <- model$rels[[i]]
    to_col <- r$to_col %||% r$from_col
    e <- list(
      id = paste0("rel", i),
      sources = list(paste0(r$from_table, ".", r$from_col, ":out")),
      targets = list(paste0(r$to_table, ".", to_col, ":in")),
      properties = list(
        key = rel_key(r),
        fromTable = r$from_table,
        fromCol = r$from_col,
        toTable = r$to_table,
        toCol = to_col,
        childMax = r$child_max,
        childMin = r$child_min,
        parentMin = r$parent_min,
        identifying = isTRUE(r$identifying),
        selfRef = isTRUE(r$self_ref),
        provenance = r$provenance,
        detectedBy = r$detected_by %||% "",
        confidence = r$confidence %||% "",
        score = r$score
      )
    )
    # elkjs rejects null property values, so leave empty ones out
    e$properties <- Filter(
      function(v) !is.null(v) && !(length(v) == 1 && is.na(v)),
      e$properties
    )
    e
  })

  list(
    id = "root",
    layoutOptions = list(
      "elk.algorithm" = "layered",
      "elk.direction" = direction,
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
      headerHeight = head_h,
      detail = detail
    ),
    children = unname(children),
    edges = edges
  )
}

# ── Session save/restore ──────────────────────────────────────

save_session_json <- function(
  tables,
  rels,
  manual_rels,
  schema_rels,
  settings = list(),
  review = list(),
  dictionary = list()
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
    review = review,
    # Data dictionary edits (descriptions, business names), keyed
    # "table" or "table|column"
    dictionary = dictionary
  )

  # na = "null": numeric NAs would otherwise be written as the string "NA"
  # and turn the whole column into text on restore
  jsonlite::toJSON(session, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
}

restore_session_json <- function(json_text) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    return(list(
      tables = list(),
      relationships = list(),
      manual_relationships = list(),
      schema_relationships = list(),
      settings = list(),
      review = list(),
      dictionary = list()
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
        # Missing values come back from JSON as null; keep them as NA so
        # every column keeps its length
        col_list <- lapply(tdata, function(col) {
          if (is.list(col)) {
            unlist(lapply(col, function(v) if (is.null(v)) NA else v))
          } else {
            col
          }
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
    review = session$review %||% list(),
    dictionary = session$dictionary %||% list()
  )
}

# ── Data dictionary ───────────────────────────────────────────
# One row per column with what the data says (type, nullability, keys,
# what it references) and what people add (description, business name).
# `dictionary` holds the edits: a named list keyed "table" (table-level) or
# "table|column", each entry list(description, business_name).

dict_key <- function(table, column = NULL) {
  if (is.null(column)) table else paste(table, column, sep = "|")
}

dict_entry <- function(dictionary, table, column = NULL) {
  e <- dictionary[[dict_key(table, column)]] %||% list()
  list(
    description = e$description %||% "",
    business_name = e$business_name %||% ""
  )
}

# Example values are left out for columns whose name suggests personal data
dict_sensitive_re <- paste0(
  "(^|_)(ssn|sin|password|passwd|pwd|dob|birth|birthdate|email|e_mail|",
  "phone|mobile|cell|address|street|zip|postcode|first_name|last_name|",
  "full_name|surname|name)(_|$)"
)

build_data_dictionary <- function(
  tables,
  rels,
  pks,
  composite_pks = NULL,
  dictionary = list(),
  examples = TRUE
) {
  empty <- data.frame(
    table = character(0), table_description = character(0),
    column = character(0), position = integer(0), type = character(0),
    nullable = logical(0), pct_missing = numeric(0), n_unique = integer(0),
    keys = character(0), references = character(0), reference_source = character(0),
    examples = character(0), description = character(0),
    business_name = character(0), stringsAsFactors = FALSE
  )
  if (length(tables) == 0) {
    return(empty)
  }
  # Documentation lists links worth relying on: low-confidence detected
  # links (demoted or ambiguous) stay out
  rels <- Filter(function(r) {
    !(rel_source(r) == "detected" && identical(r$confidence, "low"))
  }, rels %||% list())
  model <- erd_model(tables, rels, pks, composite_pks)
  rows <- lapply(model$tables, function(t) {
    df <- tables[[t$name]]
    cols <- t$columns
    t_desc <- dict_entry(dictionary, t$name)$description
    out_rels <- Filter(function(r) r$from_table == t$name, model$rels)
    lapply(seq_len(nrow(cols)), function(i) {
      cn <- cols$name[i]
      v <- df[[cn]]
      n <- length(v)
      refs <- Filter(function(r) r$from_col == cn, out_rels)
      ex <- ""
      if (isTRUE(examples) && !grepl(dict_sensitive_re, clean_name(cn)) && n > 0) {
        vals <- unique(as.character(v[!is.na(v)]))
        vals <- vals[nzchar(trimws(vals))]
        vals <- substr(head(vals, 3), 1, 30)
        ex <- paste(vals, collapse = ", ")
      }
      e <- dict_entry(dictionary, t$name, cn)
      data.frame(
        table = t$name,
        table_description = t_desc,
        column = cn,
        position = match(cn, names(df)),
        type = cols$type[i],
        nullable = isTRUE(cols$nullable[i]),
        pct_missing = if (n > 0) round(100 * mean(is.na(v)), 1) else NA_real_,
        n_unique = if (n > 0) length(unique(v[!is.na(v)])) else NA_integer_,
        keys = paste(c(
          if (cols$pk[i]) "PK",
          if (!is.na(cols$fk_index[i])) paste0("FK", cols$fk_index[i]),
          if (cols$uk[i]) "UK"
        ), collapse = ", "),
        references = paste(vapply(refs, function(r) {
          paste0(r$to_table, ".", r$to_col %||% r$from_col)
        }, ""), collapse = "; "),
        reference_source = paste(vapply(refs, rel_source, ""), collapse = "; "),
        examples = ex,
        description = e$description,
        business_name = e$business_name,
        stringsAsFactors = FALSE
      )
    })
  })
  rows <- unlist(rows, recursive = FALSE)
  if (length(rows) == 0) {
    return(empty)
  }
  dd <- do.call(rbind, rows)
  dd <- dd[order(dd$table, dd$position), , drop = FALSE]
  rownames(dd) <- NULL
  dd
}

# Markdown: one section per table, with its description, a column table and
# what it links to
generate_data_dictionary_md <- function(dd, title = "Data dictionary") {
  cell <- function(x) {
    x <- ifelse(is.na(x), "", as.character(x))
    gsub("\n", " ", gsub("|", "\\|", x, fixed = TRUE))
  }
  lines <- c(paste0("# ", title), "")
  if (nrow(dd) == 0) {
    return(paste(c(lines, "_No tables loaded._"), collapse = "\n"))
  }
  lines <- c(lines, sprintf("%d tables, %d columns.", length(unique(dd$table)), nrow(dd)), "")
  for (t in unique(dd$table)) {
    d <- dd[dd$table == t, , drop = FALSE]
    lines <- c(lines, paste0("## ", t), "")
    if (nzchar(d$table_description[1])) {
      lines <- c(lines, cell(d$table_description[1]), "")
    }
    lines <- c(
      lines,
      "| Column | Business name | Type | Keys | Nullable | Missing % | Unique | Description | Examples |",
      "|---|---|---|---|---|---|---|---|---|"
    )
    for (i in seq_len(nrow(d))) {
      lines <- c(lines, paste0(
        "| ", paste(c(
          paste0("`", cell(d$column[i]), "`"),
          cell(d$business_name[i]),
          cell(d$type[i]),
          cell(d$keys[i]),
          if (d$nullable[i]) "yes" else "no",
          cell(d$pct_missing[i]),
          cell(d$n_unique[i]),
          cell(d$description[i]),
          cell(d$examples[i])
        ), collapse = " | "), " |"
      ))
    }
    linked <- d[nzchar(d$references), , drop = FALSE]
    if (nrow(linked) > 0) {
      lines <- c(lines, "", "**References**", "")
      for (i in seq_len(nrow(linked))) {
        tgt <- strsplit(linked$references[i], "; ", fixed = TRUE)[[1]]
        src <- strsplit(linked$reference_source[i], "; ", fixed = TRUE)[[1]]
        for (j in seq_along(tgt)) {
          lines <- c(lines, sprintf(
            "- `%s` → `%s` (%s)", linked$column[i], tgt[j], src[j] %||% ""
          ))
        }
      }
    }
    lines <- c(lines, "")
  }
  paste(lines, collapse = "\n")
}
