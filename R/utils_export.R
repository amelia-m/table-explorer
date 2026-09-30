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
    # Data dictionary edits (labels, descriptions, privacy), keyed
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
# One row per column with what the data says (type, format, missing values,
# unique values, lengths or range, keys, what it references, examples) and
# what people add (label, description, units, allowed values, details,
# privacy). `dictionary` holds the edits: a named list keyed "table"
# (table-level) or "table|column", plus the reserved ".settings" (see
# dict_settings() in utils_privacy.R). A column entry may hold:
#   label, description, units, values ("A = Active; I = Inactive"), details
#   private        TRUE / FALSE: the user's choice (absent: automatic)
#   hide_examples  TRUE / FALSE: no examples without calling it private
#   privacy_review list(state = "confirmed" | "rejected", reason)
# Older sessions stored the label as `business_name`; it is still read.

dict_text_fields <- c("label", "description", "units", "values", "details")

dict_key <- function(table, column = NULL) {
  if (is.null(column)) table else paste(table, column, sep = "|")
}

dict_entry <- function(dictionary, table, column = NULL) {
  e <- dictionary[[dict_key(table, column)]] %||% list()
  txt <- function(x) if (is.null(x) || length(x) == 0 || is.na(x[[1]])) "" else as.character(x[[1]])
  list(
    label = txt(e$label %||% e$business_name),
    description = txt(e$description),
    units = txt(e$units),
    values = txt(e$values),
    details = txt(e$details),
    private = if (is.logical(e$private) && length(e$private) == 1 && !is.na(e$private)) e$private else NA,
    hide_examples = if (is.logical(e$hide_examples) && length(e$hide_examples) == 1 && !is.na(e$hide_examples)) e$hide_examples else NA
  )
}

# TRUE when an entry holds nothing worth keeping
dict_entry_empty <- function(e) {
  texts <- unlist(lapply(c(dict_text_fields, "business_name"), function(f) e[[f]] %||% ""))
  all(!nzchar(texts)) && is.null(e$private) && is.null(e$hide_examples) &&
    is.null(e$privacy_review)
}

# A readable format: the value fingerprint for text, else from the type
dict_format <- function(v) {
  if (inherits(v, "POSIXt")) return("datetime")
  if (inherits(v, "Date")) return("date")
  if (is.logical(v)) return("true/false")
  if (is.numeric(v)) {
    x <- v[!is.na(v)]
    if (length(x) == 0) return("number")
    return(if (all(x == round(x))) "whole number" else "decimal")
  }
  fp <- format_fingerprint(v)
  labels <- c(
    uuid = "UUID", email = "email address", iso_ts = "ISO timestamp",
    iso_date = "ISO date", zip_us = "US ZIP code", phone = "phone number",
    hex_color = "hex colour", int_code = "numeric code", alpha_code = "letter code"
  )
  if (!is.null(fp) && fp %in% names(labels)) return(unname(labels[fp]))
  "text"
}

dict_num <- function(x) {
  if (inherits(x, c("Date", "POSIXt"))) return(as.character(x))
  format(signif(x, 6), trim = TRUE, scientific = FALSE, drop0trailing = TRUE)
}

# Up to n examples spread across the sorted distinct values
dict_examples <- function(v, n = 5, width = 30) {
  # Sorted on the values themselves, so 2 comes before 10
  vals <- as.character(sort(unique(v[!is.na(v)])))
  vals <- vals[nzchar(trimws(vals))]
  if (length(vals) == 0) return(character(0))
  idx <- unique(round(seq(1, length(vals), length.out = min(n, length(vals)))))
  substr(vals[idx], 1, width)
}

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
    format = character(0), nullable = logical(0), pct_missing = numeric(0),
    n_unique = integer(0), len_min = integer(0), len_median = numeric(0),
    len_max = integer(0), min = character(0), median = character(0),
    max = character(0), keys = character(0), references = character(0),
    reference_source = character(0), private = logical(0),
    privacy_status = character(0), privacy_reason = character(0),
    examples = character(0), examples_note = character(0),
    label = character(0), description = character(0), units = character(0),
    values = character(0), details = character(0), stringsAsFactors = FALSE
  )
  if (length(tables) == 0) {
    return(empty)
  }
  settings <- dict_settings(dictionary)
  examples_on <- isTRUE(examples) && !identical(settings$examples, "off")
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
      if (is.factor(v)) v <- as.character(v)
      n <- length(v)
      present <- v[!is.na(v)]
      refs <- Filter(function(r) r$from_col == cn, out_rels)
      e <- dict_entry(dictionary, t$name, cn)
      p <- dict_privacy(dictionary, t$name, cn, v)

      # Text lengths never identify anyone; a numeric or date range can
      # (ages, birth dates), so it is left out for private columns
      lens <- if (is.character(v) && length(present) > 0) nchar(present) else NULL
      ranged <- (is.numeric(v) || inherits(v, c("Date", "POSIXt"))) && length(present) > 0
      rng <- c("", "", "")
      if (ranged) {
        rng <- if (p$private) rep("hidden", 3) else {
          c(dict_num(min(present)), dict_num(stats::median(present)), dict_num(max(present)))
        }
      }

      note <- if (p$private) {
        "private"
      } else if (isTRUE(e$hide_examples)) {
        "hidden by you"
      } else if (!examples_on && !isFALSE(e$hide_examples)) {
        "examples off"
      } else {
        ""
      }
      ex <- if (!nzchar(note) && n > 0) paste(dict_examples(v), collapse = ", ") else ""

      data.frame(
        table = t$name,
        table_description = t_desc,
        column = cn,
        position = match(cn, names(df)),
        type = cols$type[i],
        format = dict_format(v),
        nullable = isTRUE(cols$nullable[i]),
        pct_missing = if (n > 0) round(100 * mean(is.na(v)), 1) else NA_real_,
        n_unique = if (n > 0) length(unique(present)) else NA_integer_,
        len_min = if (length(lens)) min(lens) else NA_integer_,
        len_median = if (length(lens)) stats::median(lens) else NA_real_,
        len_max = if (length(lens)) max(lens) else NA_integer_,
        min = rng[1],
        median = rng[2],
        max = rng[3],
        keys = paste(c(
          if (cols$pk[i]) "PK",
          if (!is.na(cols$fk_index[i])) paste0("FK", cols$fk_index[i]),
          if (cols$uk[i]) "UK"
        ), collapse = ", "),
        references = paste(vapply(refs, function(r) {
          paste0(r$to_table, ".", r$to_col %||% r$from_col)
        }, ""), collapse = "; "),
        reference_source = paste(vapply(refs, rel_source, ""), collapse = "; "),
        private = p$private,
        privacy_status = p$status,
        privacy_reason = p$reason,
        examples = ex,
        examples_note = note,
        label = e$label,
        description = e$description,
        units = e$units,
        values = e$values,
        details = e$details,
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

# "length 2–12 (median 6)" for text, "1 – 40 (median 7)" for numbers and
# dates, "hidden (private)" when the range is withheld
dict_range_text <- function(dd) {
  vapply(seq_len(nrow(dd)), function(i) {
    if (!is.na(dd$len_min[i])) {
      return(sprintf(
        "length %s–%s (median %s)",
        dd$len_min[i], dd$len_max[i], dict_num(dd$len_median[i])
      ))
    }
    if (identical(dd$min[i], "hidden")) return("hidden (private)")
    if (nzchar(dd$min[i])) {
      return(sprintf("%s – %s (median %s)", dd$min[i], dd$max[i], dd$median[i]))
    }
    ""
  }, "")
}

# Markdown: one section per table, with its description, a column table,
# notes (units, allowed values, details, privacy) and what it links to
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
      "| Column | Label | Type | Format | Keys | Nullable | Missing % | Unique | Range | Description | Examples |",
      "|---|---|---|---|---|---|---|---|---|---|---|"
    )
    rng <- dict_range_text(d)
    for (i in seq_len(nrow(d))) {
      ex <- if (nzchar(d$examples_note[i])) paste0("_", d$examples_note[i], "_") else cell(d$examples[i])
      lines <- c(lines, paste0(
        "| ", paste(c(
          paste0("`", cell(d$column[i]), "`"),
          cell(d$label[i]),
          cell(d$type[i]),
          cell(d$format[i]),
          cell(d$keys[i]),
          if (d$nullable[i]) "yes" else "no",
          cell(d$pct_missing[i]),
          cell(d$n_unique[i]),
          cell(rng[i]),
          cell(d$description[i]),
          ex
        ), collapse = " | "), " |"
      ))
    }
    notes <- character(0)
    for (i in seq_len(nrow(d))) {
      bits <- c(
        if (nzchar(d$units[i])) paste0("units: ", cell(d$units[i])),
        if (nzchar(d$values[i])) paste0("values: ", cell(d$values[i])),
        if (d$private[i]) privacy_status_labels[[d$privacy_status[i]]],
        if (nzchar(d$details[i])) cell(d$details[i])
      )
      if (length(bits)) notes <- c(notes, sprintf("- `%s`: %s", d$column[i], paste(bits, collapse = "; ")))
    }
    if (length(notes)) lines <- c(lines, "", "**Notes**", "", notes)
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

# ── data-dict YAML ────────────────────────────────────────────
# The data-dict.yaml format (https://data-dict.tidyverse.org/, spec 0.1.0),
# written in plain R so the app doesn't need the data-dict tool. The whole
# mapping lives here; if the spec changes, this and
# parse_data_dict_schema() in utils_file_readers.R are what change.
#
# - Key columns that hold numbers are number(id); a number with units is
#   number(quantity) (the spec only allows units there), other numbers are
#   plain number. Columns with allowed values are enums.
# - Private columns get display: restricted, and neither real examples nor a
#   real range: an open range, or a todo asking for fake examples.
# - Declared, manual and confirmed links are relationships (with a
#   foreign_key constraint on the column); unreviewed detected links are
#   listed under the top-level todo, since the spec has no provenance field.

data_dict_spec_version <- "0.1.0"

# "A = Active; I = Inactive" -> list(A = "Active", I = "Inactive");
# "A; B; C" -> c("A", "B", "C")
dict_parse_values <- function(txt) {
  parts <- trimws(strsplit(txt %||% "", ";", fixed = TRUE)[[1]])
  parts <- parts[nzchar(parts)]
  if (length(parts) == 0) return(NULL)
  has_label <- grepl("=", parts, fixed = TRUE)
  codes <- trimws(sub("=.*$", "", parts))
  if (!any(has_label)) return(codes)
  labels <- ifelse(has_label, trimws(sub("^[^=]*=", "", parts)), codes)
  stats::setNames(as.list(labels), codes)
}

# The reverse, for imports
dict_format_values <- function(values) {
  if (is.null(values) || length(values) == 0) return("")
  if (!is.null(names(values)) && all(nzchar(names(values)))) {
    return(paste(paste(names(values), "=", unlist(values)), collapse = "; "))
  }
  paste(unlist(values), collapse = "; ")
}

# Stand-ins that match a withheld column's type and format
dict_placeholder_examples <- function(v, format) {
  if (is.numeric(v)) return(list(0L))
  switch(
    format,
    "email address" = list("person@example.com"),
    "phone number" = list("555-0100"),
    "US ZIP code" = list("00000"),
    "UUID" = list("00000000-0000-0000-0000-000000000000"),
    "ISO date" = list("2000-01-01"),
    "numeric code" = list("000"),
    "letter code" = list("XX"),
    list("(withheld)")
  )
}

generate_data_dict_yaml <- function(
  tables,
  rels,
  pks,
  composite_pks = NULL,
  dictionary = list(),
  name = NULL
) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Install the 'yaml' package to export data-dict YAML: install.packages('yaml')")
  }
  dd <- build_data_dictionary(tables, rels, pks, composite_pks, dictionary = dictionary)
  kept <- Filter(function(r) {
    !(rel_source(r) == "detected" && identical(r$confidence, "low"))
  }, rels %||% list())
  model <- erd_model(tables, kept, pks, composite_pks)
  reviewed <- Filter(function(r) rel_source(r) != "detected", model$rels)
  unreviewed <- Filter(function(r) rel_source(r) == "detected", model$rels)
  # The spec wants a foreign key to point at a primary key, and the "one"
  # side of a join to be a key or unique
  key_cols <- unlist(lapply(model$tables, function(t) {
    c(
      paste(t$name, t$columns$name[t$columns$pk], sep = "|"),
      paste(t$name, t$columns$name[t$columns$uk], sep = "|")
    )
  }))
  pk_cols <- unlist(lapply(model$tables, function(t) paste(t$name, t$columns$name[t$columns$pk], sep = "|")))
  reviewed <- Filter(function(r) paste(r$to_table, r$to_col, sep = "|") %in% key_cols, reviewed)
  fk_cols <- unique(unlist(lapply(reviewed, function(r) {
    if (paste(r$to_table, r$to_col, sep = "|") %in% pk_cols) paste(r$from_table, r$from_col, sep = "|")
  })))

  settings <- dict_settings(dictionary)
  examples_on <- !identical(settings$examples, "off")
  iso <- function(x) {
    if (inherits(x, "POSIXt")) format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC") else as.character(x)
  }

  column_yaml <- function(t, i) {
    row <- dd[dd$table == t$name & dd$column == t$columns$name[i], , drop = FALSE]
    cn <- t$columns$name[i]
    v <- tables[[t$name]][[cn]]
    if (is.factor(v)) v <- as.character(v)
    present <- v[!is.na(v)]
    is_key <- t$columns$pk[i] || !is.na(t$columns$fk_index[i])
    allowed <- dict_parse_values(row$values)
    units <- row$units
    details <- row$details
    todo <- character(0)

    type <- if (!is.null(allowed)) {
      "enum"
    } else if (is.logical(v)) {
      "boolean"
    } else if (inherits(v, "POSIXt")) {
      "datetime"
    } else if (inherits(v, "Date")) {
      "date"
    } else if (is.numeric(v)) {
      if (is_key) "number(id)" else if (nzchar(units)) "number(quantity)" else "number"
    } else {
      "string"
    }
    if (nzchar(units) && type != "number(quantity)") {
      # The spec allows units on quantities only; keep them in the details
      details <- paste(c(if (nzchar(details)) details, paste0("Units: ", units)), collapse = "\n\n")
      units <- ""
    }

    constraints <- c(
      if (t$columns$pk[i]) "primary_key",
      if (paste(t$name, cn, sep = "|") %in% fk_cols) "foreign_key",
      if (!t$columns$pk[i] && !isTRUE(t$columns$nullable[i])) "required",
      if (!t$columns$pk[i] && isTRUE(t$columns$uk[i])) "unique"
    )

    needs_range <- type %in% c("number(quantity)", "number(ordinal)", "date", "datetime")
    range <- NULL
    if (needs_range) {
      range <- if (row$private || length(present) == 0) {
        list(-Inf, Inf)
      } else if (is.numeric(v)) {
        list(min(present), max(present))
      } else {
        list(iso(min(present)), iso(max(present)))
      }
      if (row$private) todo <- c(todo, "Range withheld: private column.")
    }

    examples <- NULL
    if (!type %in% c("boolean", "enum") && !needs_range) {
      show <- !row$private && !isTRUE(dict_entry(dictionary, t$name, cn)$hide_examples) &&
        (examples_on || isFALSE(dict_entry(dictionary, t$name, cn)$hide_examples))
      if (show && length(present) > 0) {
        ex <- dict_examples(v)
        examples <- if (is.numeric(v)) {
          x <- as.numeric(ex)
          if (all(x == round(x))) {
            # Whole numbers written as such (not 1.0 or 9.8765432e+09),
            # including ones too large for an R integer
            lapply(format(x, scientific = FALSE, trim = TRUE), structure, class = "verbatim")
          } else {
            as.list(x)
          }
        } else {
          as.list(ex)
        }
      } else {
        # The spec requires examples; a withheld column gets placeholders
        examples <- dict_placeholder_examples(v, row$format)
        todo <- c(todo, if (row$private) {
          "Examples are placeholders: real values withheld (private column)."
        } else if (length(present) == 0) {
          "Examples are placeholders: no data was loaded for this column."
        } else {
          "Examples are placeholders: real values withheld in Table Relationship Explorer."
        })
      }
    }
    if (identical(row$privacy_status, "auto_unreviewed")) {
      todo <- c(todo, sprintf("Confirm this column is personal data (%s).", row$privacy_reason))
    }

    out <- list(name = cn)
    if (nzchar(row$label)) out$label <- row$label
    out$type <- type
    if (nzchar(row$description)) out$description <- row$description
    if (nzchar(details)) out$details <- details
    if (row$private) out$display <- "restricted"
    if (length(constraints)) out$constraints <- as.list(constraints)
    if (nzchar(units)) out$units <- units
    if (!is.null(allowed)) out$values <- if (is.list(allowed)) allowed else as.list(allowed)
    if (!is.null(range)) out$range <- range
    if (!is.null(examples)) out$examples <- examples
    if (length(todo)) out$todo <- paste(todo, collapse = "\n")
    out
  }

  table_names <- vapply(model$tables, `[[`, "", "name")
  alias_for <- function(base) {
    a <- base
    while (a %in% table_names) a <- paste0(a, "_")
    a
  }
  rel_yaml <- function(r) {
    left <- r$from_table
    right <- r$to_table
    out <- list()
    if (isTRUE(r$self_ref)) {
      left <- alias_for("child")
      right <- alias_for("parent")
      aliases <- list()
      aliases[[left]] <- r$from_table
      aliases[[right]] <- r$to_table
    }
    out$join <- sprintf("%s.%s = %s.%s", left, r$from_col, right, r$to_col)
    if (isTRUE(r$self_ref)) out$aliases <- aliases
    one_to_one <- identical(r$child_max, "one") &&
      paste(r$from_table, r$from_col, sep = "|") %in% key_cols
    out$cardinality <- if (one_to_one) "one-to-one" else "many-to-one"
    out$description <- switch(
      rel_source(r),
      manual = "Added by hand in Table Relationship Explorer.",
      confirmed = "Detected and confirmed in Table Relationship Explorer.",
      NULL
    )
    out
  }

  doc <- list(
    `$version` = data_dict_spec_version,
    `$learn_more` = "https://data-dict.tidyverse.org/"
  )
  if (!is.null(name)) doc$name <- name
  doc$tables <- lapply(unname(model$tables), function(t) {
    te <- dict_entry(dictionary, t$name)
    out <- list(name = t$name)
    if (nzchar(te$label)) out$label <- te$label
    if (nzchar(te$description)) out$description <- te$description
    if (nzchar(te$details)) out$details <- te$details
    out$columns <- lapply(seq_len(nrow(t$columns)), function(i) column_yaml(t, i))
    out
  })
  # A single-table dictionary is described at the top level
  if (length(doc$tables) == 1) {
    for (f in c("label", "description", "details")) {
      doc[[f]] <- doc$tables[[1]][[f]]
      doc$tables[[1]][[f]] <- NULL
    }
    doc <- doc[c(setdiff(names(doc), "tables"), "tables")]
  }
  if (length(reviewed)) doc$relationships <- lapply(unname(reviewed), rel_yaml)
  if (length(unreviewed)) {
    doc$todo <- paste(c(
      "Unconfirmed links found by detection (confirm or remove, then move to relationships):",
      vapply(unreviewed, function(r) {
        sprintf(
          "- %s.%s = %s.%s (%s confidence)",
          r$from_table, r$from_col, r$to_table, r$to_col, r$confidence %||% "unknown"
        )
      }, "")
    ), collapse = "\n")
  }
  yaml::as.yaml(doc, indent.mapping.sequence = TRUE, column.major = FALSE)
}
