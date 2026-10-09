# ============================================================
# mod_dictionary.R - Data Dictionary tab
# ============================================================
#
# One row per column: what the data says (type, format, missing values,
# unique values, lengths or range, keys, what it references, examples) next
# to what people add (label, description, units, allowed values, details)
# and whether the column is private. Edits live in dictionary_rv, keyed
# "table" or "table|column" (see build_data_dictionary() in utils_export.R),
# are saved with the session and flow into the exports.
#
# Private columns keep their metadata but show no examples and no value
# range. Columns flagged automatically as possibly personal count as private
# until the user confirms or rejects the flag (see utils_privacy.R).

#' Data dictionary module UI
#' @noRd
mod_dictionary_ui <- function(id) {
  ns <- NS(id)
  tagList(
    br(),
    div(
      class = "dict-toolbar",
      div(
        class = "dict-filters",
        selectizeInput(
          ns("table"),
          "Table",
          choices = c("All tables" = ""),
          width = "240px",
          options = list(placeholder = "All tables")
        ),
        selectInput(
          ns("show"),
          "Columns",
          choices = c(
            "All columns" = "all",
            "Private" = "private",
            "Flags to review" = "review",
            "Not private" = "public"
          ),
          width = "170px"
        )
      ),
      div(
        class = "dict-downloads",
        downloadButton(ns("dl_csv"), "CSV", class = "dl-btn"),
        downloadButton(ns("dl_md"), "Markdown", class = "dl-btn"),
        downloadButton(ns("dl_yaml"), "data-dict YAML", class = "dl-btn")
      )
    ),
    uiOutput(ns("review_banner")),
    tags$details(
      class = "dict-settings",
      tags$summary("Privacy and example settings"),
      div(
        class = "dict-settings-body",
        radioButtons(
          ns("examples"),
          "Example values",
          choices = c(
            "Show, except for private columns" = "auto",
            "Off (only where you turn them on)" = "off"
          ),
          inline = TRUE
        ),
        div(
          class = "dict-pattern-row",
          textInput(
            ns("private_patterns"),
            "Private column names (comma-separated, * as wildcard; applies to all tables)",
            placeholder = "*_name, dob*, mrn, patients.notes",
            width = "100%"
          ),
          actionButton(ns("apply_patterns"), "Apply", class = "btn-sm")
        )
      )
    ),
    uiOutput(ns("table_desc_ui")),
    div(
      class = "dict-row-actions",
      span(class = "dict-hint", "Selected rows:"),
      actionButton(ns("set_private"), "Private", class = "btn-sm"),
      actionButton(ns("set_public"), "Not private", class = "btn-sm"),
      actionButton(ns("set_auto"), "Automatic", class = "btn-sm",
        title = "Forget your choice and use the automatic flag"),
      actionButton(ns("hide_ex"), "Hide examples", class = "btn-sm"),
      actionButton(ns("show_ex"), "Show examples", class = "btn-sm")
    ),
    div(
      class = "dict-hint",
      "Click rows to select them for the buttons above. Double-click a Label, ",
      "Description, Units, Allowed values or Details cell to edit it; press ",
      "Enter or click away to save. Private columns keep their type, format, ",
      "counts and text lengths but show no example values or value range. ",
      "Edits are saved with the session and included in the exports."
    ),
    uiOutput(ns("dict_ui"))
  )
}

#' Data dictionary module server
#'
#' @param id Module id
#' @param tables_rv reactive: visible tables
#' @param rels_rv reactive: visible relationships
#' @param pk_map_rv reactive: PK candidates per table
#' @param composite_pk_map_rv reactive: composite keys per table
#' @param dictionary_rv reactiveVal of dictionary edits
#' @noRd
mod_dictionary_server <- function(
  id,
  tables_rv,
  rels_rv,
  pk_map_rv,
  composite_pk_map_rv,
  dictionary_rv
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # The table is redrawn only when the data or the dictionary changes from
    # outside (a restored session, an import) or a privacy choice changes
    # what is shown; a text edit is already on screen, and redrawing would
    # lose the page and scroll position
    redraw <- reactiveVal(0)
    bump <- function() redraw(isolate(redraw()) + 1)
    last_written <- reactiveVal(NULL)
    observeEvent(dictionary_rv(), {
      if (!identical(dictionary_rv(), last_written())) {
        s <- dict_settings(dictionary_rv())
        updateRadioButtons(session, "examples", selected = s$examples)
        updateTextInput(session, "private_patterns", value = s$private_patterns)
        bump()
      }
    }, ignoreInit = TRUE)

    observeEvent(tables_rv(), {
      tnames <- sort(names(tables_rv()))
      cur <- isolate(input$table)
      updateSelectizeInput(
        session,
        "table",
        choices = c("All tables" = "", tnames),
        selected = if (!is.null(cur) && cur %in% tnames) cur else ""
      )
    })

    commit <- function(d, redraw_table = FALSE) {
      last_written(d)
      dictionary_rv(d)
      if (redraw_table) bump()
    }

    write_entry <- function(key, field, value) {
      d <- dictionary_rv()
      e <- d[[key]] %||% list()
      e[[field]] <- value
      # The old name for the label goes once the label is edited
      if (identical(field, "label")) e$business_name <- NULL
      d[[key]] <- if (dict_entry_empty(e)) NULL else e
      commit(d)
    }

    # Set (or, with NULL, clear) a flag on several columns at once. A choice
    # that lets values show is stamped with the data it was made for (see
    # privacy_holds() in utils_privacy.R).
    write_flag <- function(keys, field, value) {
      d <- dictionary_rv()
      stamp_field <- c(private = "public_for", hide_examples = "examples_for")[[field]]
      for (k in keys) {
        e <- d[[k]] %||% list()
        e[[field]] <- value
        parts <- strsplit(k, "|", fixed = TRUE)[[1]]
        values <- tables_rv()[[parts[1]]][[paste(parts[-1], collapse = "|")]]
        e[[stamp_field]] <- if (isFALSE(value) && !is.null(values)) privacy_data_hash(values)
        if (identical(field, "private")) e$private_source <- NULL
        d[[k]] <- if (dict_entry_empty(e)) NULL else e
      }
      commit(d, redraw_table = TRUE)
    }

    write_setting <- function(field, value) {
      d <- dictionary_rv()
      s <- d[[".settings"]] %||% list()
      s[[field]] <- value
      d[[".settings"]] <- s
      commit(d, redraw_table = TRUE)
    }

    dd_rv <- reactive({
      redraw()
      req(length(tables_rv()) > 0)
      build_data_dictionary(
        tables_rv(),
        rels_rv(),
        pk_map_rv(),
        composite_pk_map_rv(),
        dictionary = isolate(dictionary_rv())
      )
    })

    shown_rv <- reactive({
      dd <- dd_rv()
      tn <- input$table %||% ""
      if (nzchar(tn)) dd <- dd[dd$table == tn, , drop = FALSE]
      dd <- switch(
        input$show %||% "all",
        private = dd[dd$private, , drop = FALSE],
        review = dd[dd$privacy_status == "auto_unreviewed", , drop = FALSE],
        public = dd[!dd$private, , drop = FALSE],
        dd
      )
      # Pick up text edits made since the last redraw
      dict <- isolate(dictionary_rv())
      for (i in seq_len(nrow(dd))) {
        e <- dict_entry(dict, dd$table[i], dd$column[i])
        for (f in dict_text_fields) dd[[f]][i] <- e[[f]]
      }
      dd
    })

    # ── Settings ─────────────────────────────────────────────
    observeEvent(input$examples, {
      if (!identical(input$examples, dict_settings(dictionary_rv())$examples)) {
        write_setting("examples", input$examples)
      }
    }, ignoreInit = TRUE)
    observeEvent(input$apply_patterns, {
      write_setting("private_patterns", trimws(input$private_patterns %||% ""))
    })

    # ── Row actions ──────────────────────────────────────────
    selected_keys <- function() {
      d <- shown_rv()
      rows <- input$dict_rows_selected
      rows <- rows[rows >= 1 & rows <= nrow(d)]
      if (length(rows) == 0) {
        showNotification("Select one or more rows first.", type = "message", duration = 3)
        return(NULL)
      }
      mapply(dict_key, d$table[rows], d$column[rows], USE.NAMES = FALSE)
    }
    observeEvent(input$set_private, {
      k <- selected_keys()
      if (length(k)) write_flag(k, "private", TRUE)
    })
    observeEvent(input$set_public, {
      k <- selected_keys()
      if (length(k)) write_flag(k, "private", FALSE)
    })
    observeEvent(input$set_auto, {
      k <- selected_keys()
      if (length(k)) write_flag(k, "private", NULL)
    })
    observeEvent(input$hide_ex, {
      k <- selected_keys()
      if (length(k)) write_flag(k, "hide_examples", TRUE)
    })
    observeEvent(input$show_ex, {
      k <- selected_keys()
      if (length(k)) write_flag(k, "hide_examples", FALSE)
    })

    # ── Reviewing automatic flags ────────────────────────────
    queue_all_rv <- reactive({
      req(length(tables_rv()) > 0)
      privacy_review_queue(tables_rv(), dictionary_rv())
    })

    # A column with no values cannot disclose anything, and on a wide
    # extract these dominate the queue. Hidden by default, counted in the
    # banner so they are not a secret.
    queue_rv <- reactive({
      q <- queue_all_rv()
      if (isTRUE(input$review_hide_empty %||% TRUE)) {
        q <- q[q$n_values > 0, , drop = FALSE]
      }
      q
    })

    # Say so once when new columns are flagged
    notified <- reactiveVal(character(0))
    observeEvent(queue_rv(), {
      q <- queue_rv()
      keys <- mapply(dict_key, q$table, q$column, USE.NAMES = FALSE)
      new <- setdiff(keys, notified())
      if (length(new) > 0) {
        showNotification(
          sprintf(
            "%d column%s flagged as possibly personal. Review them on the Data Dictionary tab.",
            length(new), if (length(new) == 1) " was" else "s were"
          ),
          type = "warning",
          duration = 8
        )
        notified(union(notified(), keys))
      }
    })

    output$review_banner <- renderUI({
      q <- tryCatch(queue_rv(), error = function(e) NULL)
      all_q <- tryCatch(queue_all_rv(), error = function(e) NULL)
      if (is.null(all_q) || nrow(all_q) == 0) {
        return(NULL)
      }
      n_empty <- sum(all_q$n_values == 0)
      n <- nrow(q)
      div(
        class = "dict-review-banner",
        div(
          if (n == 0) {
            sprintf(
              "All %d flagged column%s are empty, so nothing needs reviewing.",
              n_empty, if (n_empty == 1) "" else "s"
            )
          } else {
            sprintf(
              "%d column%s flagged as possibly personal. Until you review them they are treated as private: no example values or value ranges.",
              n, if (n == 1) " was" else "s were"
            )
          },
          if (n_empty > 0) {
            checkboxInput(
              ns("review_hide_empty"),
              sprintf(
                "Hide %d flagged column%s with no values",
                n_empty, if (n_empty == 1) "" else "s"
              ),
              # Isolated: this banner re-renders when the box is ticked,
              # and reading it reactively here would reset it each time
              value = isTRUE(isolate(input$review_hide_empty) %||% TRUE)
            )
          }
        ),
        if (nrow(q) > 0) actionButton(ns("review"), "Review", class = "btn-sm")
      )
    })

    modal_queue <- reactiveVal(NULL)
    observeEvent(input$review, {
      q <- queue_rv()
      req(nrow(q) > 0)
      modal_queue(q)
      tabs <- tables_rv()
      rows <- lapply(seq_len(nrow(q)), function(i) {
        v <- tabs[[q$table[i]]][[q$column[i]]]
        tags$tr(
          tags$td(q$table[i]),
          tags$td(tags$code(q$column[i])),
          tags$td(q$reason[i]),
          tags$td(dict_format(v)),
          tags$td(length(unique(v[!is.na(v)]))),
          tags$td(radioButtons(
            ns(paste0("rv_", i)),
            NULL,
            choices = c("Private" = "confirmed", "Not personal" = "rejected", "Later" = "later"),
            selected = "later",
            inline = TRUE
          ))
        )
      })
      showModal(modalDialog(
        title = "Review possibly personal columns",
        size = "l",
        easyClose = TRUE,
        p(
          class = "dict-hint",
          "These columns were flagged by their name or by what their values look like. ",
          "Private columns show no example values or value ranges in the dictionary ",
          "and its exports. No values are shown here."
        ),
        div(
          class = "dict-review-scroll",
          tags$table(
            class = "table table-condensed dict-review-table",
            tags$thead(tags$tr(
              tags$th("Table"), tags$th("Column"), tags$th("Why"),
              tags$th("Format"), tags$th("Unique"), tags$th("Decision")
            )),
            tags$tbody(rows)
          )
        ),
        footer = tagList(
          modalButton("Review later"),
          actionButton(ns("review_all_private"), "Confirm all as private"),
          actionButton(ns("review_save"), "Save decisions", class = "btn-primary")
        )
      ))
    })

    save_review <- function(states) {
      q <- modal_queue()
      req(!is.null(q))
      keys <- mapply(dict_key, q$table, q$column, USE.NAMES = FALSE)
      d <- dictionary_rv()
      for (s in c("confirmed", "rejected")) {
        d <- privacy_review_set(d, tables_rv(), keys[states == s], s)
      }
      commit(d, redraw_table = TRUE)
      removeModal()
      modal_queue(NULL)
    }
    observeEvent(input$review_save, {
      q <- modal_queue()
      req(!is.null(q))
      states <- vapply(seq_len(nrow(q)), function(i) {
        input[[paste0("rv_", i)]] %||% "later"
      }, "")
      save_review(states)
    })
    observeEvent(input$review_all_private, {
      q <- modal_queue()
      req(!is.null(q))
      save_review(rep("confirmed", nrow(q)))
    })

    # ── Table description ────────────────────────────────────
    # The table the description box was drawn for: switching tables while
    # typing must not save the text onto the newly selected table
    desc_table <- reactiveVal("")
    output$table_desc_ui <- renderUI({
      tn <- input$table %||% ""
      desc_table(tn)
      if (!nzchar(tn)) {
        return(NULL)
      }
      redraw()
      textAreaInput(
        ns("table_desc"),
        paste0("Description of ", tn),
        value = dict_entry(isolate(dictionary_rv()), tn)$description,
        width = "100%",
        rows = 2,
        placeholder = "What this table holds, where it comes from, who owns it"
      )
    })
    observeEvent(input$table_desc, {
      tn <- desc_table()
      req(nzchar(tn), tn %in% names(tables_rv()))
      if (!identical(input$table_desc, dict_entry(dictionary_rv(), tn)$description)) {
        write_entry(dict_key(tn), "description", input$table_desc)
      }
    # Runs before the box is redrawn for a newly selected table
    }, ignoreInit = TRUE, priority = 10)

    # ── The table ────────────────────────────────────────────
    output$dict_ui <- renderUI({
      if (length(tables_rv()) == 0) {
        return(div(
          class = "empty-state",
          h4("No tables loaded"),
          p(
            style = "color:var(--text-muted); font-size:13px;",
            "Upload one or more files using the sidebar to begin."
          )
        ))
      }
      DT::DTOutput(ns("dict"))
    })

    # Editable columns, 0-based, for DT
    edit_cols <- c(label = 12L, description = 13L, units = 14L, values = 15L, details = 16L)

    output$dict <- DT::renderDT({
      d <- shown_rv()
      privacy <- ifelse(
        d$privacy_status == "none",
        "",
        paste0(
          unname(privacy_status_labels[d$privacy_status]),
          ifelse(nzchar(d$privacy_reason) & d$privacy_status %in% c("auto_unreviewed", "confirmed", "not_personal"),
            paste0(": ", d$privacy_reason), "")
        )
      )
      df <- data.frame(
        Table = d$table,
        `#` = d$position,
        Column = d$column,
        Type = d$type,
        Format = d$format,
        Keys = d$keys,
        References = mapply(function(refs, srcs) {
          if (!nzchar(refs)) return("")
          refs <- strsplit(refs, "; ", fixed = TRUE)[[1]]
          srcs <- strsplit(srcs, "; ", fixed = TRUE)[[1]]
          paste0(refs, " (", srcs, ")", collapse = "; ")
        }, d$references, d$reference_source, USE.NAMES = FALSE),
        `Missing %` = d$pct_missing,
        Unique = d$n_unique,
        Range = dict_range_text(d),
        Privacy = privacy,
        Examples = ifelse(nzchar(d$examples_note), paste0("(", d$examples_note, ")"), d$examples),
        Label = d$label,
        Description = d$description,
        Units = d$units,
        `Allowed values` = d$values,
        Details = d$details,
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
      DT::datatable(
        df,
        rownames = FALSE,
        # No per-column filters: numeric ones need DT's slider library,
        # whose load failure stalls the page (see mod_relationships.R)
        filter = "none",
        selection = "multiple",
        editable = list(
          target = "cell",
          disable = list(columns = setdiff(seq_len(ncol(df)) - 1L, edit_cols))
        ),
        options = list(
          pageLength = 50,
          lengthMenu = list(c(25, 50, 100, -1), c("25", "50", "100", "All")),
          scrollX = TRUE,
          # Without a capped body the horizontal bar sits under the last
          # row, so on a 50-row page it is off screen until you scroll
          # past everything. Capping the body keeps it in view.
          scrollY = "62vh",
          scrollCollapse = TRUE,
          autoWidth = FALSE,
          order = list(list(0, "asc"), list(1, "asc")),
          columnDefs = list(
            list(className = "dict-editable", targets = unname(edit_cols)),
            list(className = "dt-center", targets = c(1L, 7L, 8L)),
            list(className = "dict-range", targets = 9L),
            list(className = "dict-muted dict-privacy", targets = 10L),
            list(className = "dict-examples", targets = 11L)
          )
        ),
        class = "compact hover dict-dt",
        # DT saves an edit when the cell loses focus; make Enter save too
        callback = DT::JS(
          "table.on('keydown', 'td input, td textarea', function(e) {",
          "  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); this.blur(); }",
          "});"
        )
      )
    },
    # Client-side data: an edit stays put when the table is paged or sorted
    # (server-side data would reload the old value)
    server = FALSE
    )

    observeEvent(input$dict_cell_edit, {
      info <- input$dict_cell_edit
      d <- shown_rv()
      i <- info$row
      req(i >= 1, i <= nrow(d))
      field <- names(edit_cols)[match(info$col, edit_cols)]
      req(!is.na(field))
      value <- trimws(as.character(info$value))
      write_entry(dict_key(d$table[i], d$column[i]), field, value)
    })

    # ── Downloads ────────────────────────────────────────────
    export_dd <- reactive({
      build_data_dictionary(
        tables_rv(),
        rels_rv(),
        pk_map_rv(),
        composite_pk_map_rv(),
        dictionary = dictionary_rv()
      )
    })
    output$dl_csv <- downloadHandler(
      filename = "data_dictionary.csv",
      content = function(file) write.csv(export_dd(), file, row.names = FALSE, na = "")
    )
    output$dl_md <- downloadHandler(
      filename = "data_dictionary.md",
      content = function(file) writeLines(generate_data_dictionary_md(export_dd()), file)
    )
    output$dl_yaml <- downloadHandler(
      filename = "data-dict.yaml",
      content = function(file) {
        writeLines(
          generate_data_dict_yaml(
            tables_rv(),
            rels_rv(),
            pk_map_rv(),
            composite_pk_map_rv(),
            dictionary = dictionary_rv()
          ),
          file
        )
      }
    )

    invisible(NULL)
  })
}
