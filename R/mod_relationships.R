# ============================================================
# mod_relationships.R - Relationships Tab
# ============================================================

#' Relationships module UI
#' @noRd
mod_relationships_ui <- function(id) {
  ns <- NS(id)
  tagList(
    br(),
    # Above the table: at the bottom it sat past 477 rows of review and
    # went unnoticed
    div(
      class = "rel-export",
      downloadButton(ns("dl_rels"), "\u2b07  Export CSV", class = "dl-btn")
    ),
    uiOutput(ns("relationships_summary")),
    uiOutput(ns("relationships_ui")),
    br()
  )
}

#' Relationships module server
#'
#' @param id Module id
#' @param all_tables_rv reactiveVal holding tables
#' @param all_rels_rv reactive returning all relationships
#' @param false_positives_rv reactiveVal holding suppressed relationship keys
#' @param conf_overrides_rv reactiveVal holding confidence overrides
#' @param confirmed_rels_rv reactiveVal: named list (rel_key -> rel) of
#'   relationships the user confirmed
#' @noRd
mod_relationships_server <- function(
  id,
  all_tables_rv,
  all_rels_rv,
  false_positives_rv,
  conf_overrides_rv,
  confirmed_rels_rv
) {
  moduleServer(id, function(input, output, session) {
    method_labels <- c(
      naming = "naming",
      name_similarity = "name similarity",
      value_overlap = "value overlap",
      cardinality = "cardinality",
      format = "format",
      distribution = "distribution",
      null_pattern = "null pattern",
      content = "content",
      schema = "schema",
      manual = "manual"
    )

    rels_rv <- reactive({
      req(length(all_tables_rv()) > 0)
      all_rels_rv()
    })

    # ---- Review summary + bulk actions ----
    # Rows shown: source filter, and low confidence only when asked for
    shown_rels_rv <- reactive({
      rels <- rels_rv()
      src <- input$source_filter %||% "all"
      if (!identical(src, "all")) {
        rels <- Filter(function(r) rel_source(r) == src, rels)
      }
      if (!isTRUE(input$show_low)) {
        rels <- Filter(function(r) !identical(r$confidence, "low"), rels)
      }
      # Narrows to links still awaiting a decision: declared, manual and
      # confirmed all drop out. Independent of the source dropdown, which
      # is single-select, so the two can be combined.
      if (isTRUE(input$hide_reviewed)) {
        rels <- Filter(function(r) identical(rel_source(r), "detected"), rels)
      }
      rels
    })

    output$relationships_summary <- renderUI({
      rels <- rels_rv()
      src <- vapply(rels, rel_source, character(1))
      n_supp <- length(false_positives_rv())
      n_low <- sum(vapply(rels, function(r) identical(r$confidence, "low"), logical(1)))
      count <- function(k) sum(src == k)
      div(
        class = "rel-toolbar",
        span(
          class = "rel-toolbar-counts",
          sprintf(
            "%d relationship%s · %d declared · %d manual · %d confirmed · %d to review",
            length(rels),
            if (length(rels) == 1) "" else "s",
            count("declared"),
            count("manual"),
            count("confirmed"),
            count("detected")
          ),
          if (n_supp > 0) sprintf(" · %d suppressed", n_supp)
        ),
        span(
          class = "rel-toolbar-filters",
          selectInput(
            session$ns("source_filter"),
            NULL,
            choices = c(
              "All sources" = "all",
              "Declared" = "declared",
              "Manual" = "manual",
              "Confirmed" = "confirmed",
              "Detected (to review)" = "detected"
            ),
            selected = isolate(input$source_filter) %||% "all",
            width = "190px"
          ),
          checkboxInput(
            session$ns("show_low"),
            sprintf("Show low confidence (%d)", n_low),
            value = isTRUE(isolate(input$show_low))
          ),
          checkboxInput(
            session$ns("hide_reviewed"),
            sprintf("To review only (%d)", count("detected")),
            value = isTRUE(isolate(input$hide_reviewed))
          )
        ),
        span(
          class = "rel-toolbar-actions",
          actionButton(
            session$ns("confirm_selected"),
            "✓ Confirm selected",
            class = "btn-rel btn-rel-confirm"
          ),
          actionButton(
            session$ns("unconfirm_selected"),
            "Unconfirm selected",
            class = "btn-rel"
          ),
          actionButton(
            session$ns("suppress_selected"),
            "✕ Suppress selected",
            class = "btn-rel btn-rel-suppress"
          ),
          if (n_supp > 0) {
            actionButton(
              session$ns("restore_suppressed"),
              "Restore suppressed",
              class = "btn-rel"
            )
          }
        )
      )
    })

    # Row data for the table, in the same order as rels_rv()
    rel_rows <- reactive({
      rels <- shown_rels_rv()
      if (length(rels) == 0) {
        return(NULL)
      }
      conf_rank <- c(low = 1L, medium = 2L, high = 3L)
      data.frame(
        key = vapply(rels, rel_key, character(1)),
        confirmed = vapply(rels, function(r) isTRUE(r$confirmed), logical(1)),
        source = vapply(rels, rel_source, character(1)),
        from_table = vapply(rels, `[[`, character(1), "from_table"),
        from_col = vapply(rels, `[[`, character(1), "from_col"),
        to_table = vapply(rels, `[[`, character(1), "to_table"),
        to_col = vapply(
          rels,
          function(r) {
            if (is.null(r$to_col) || is.na(r$to_col)) "?" else r$to_col
          },
          character(1)
        ),
        method = vapply(rels, function(r) r$detected_by %||% "", character(1)),
        confidence = vapply(
          rels,
          function(r) r$confidence %||% "",
          character(1)
        ),
        conf_rank = vapply(
          rels,
          function(r) {
            unname(conf_rank[r$confidence %||% "low"]) %||% 0L
          },
          integer(1)
        ),
        score = vapply(
          rels,
          function(r) round(100 * (r$score %||% NA_real_)),
          numeric(1)
        ),
        signals = vapply(
          rels,
          function(r) paste(names(r$signals), collapse = ", "),
          character(1)
        ),
        reasons = vapply(
          rels,
          function(r) paste(r$reasons, collapse = "; "),
          character(1)
        ),
        stringsAsFactors = FALSE
      )
    })

    # Only whether there are rows, not which: a reactiveVal does not notify
    # on an identical value, so the DTOutput is emitted once and the proxy
    # keeps the page, sort and scroll. A plain reactive would re-render the
    # widget on every confirm and undo the point of the proxy.
    has_rows_rv <- reactiveVal(FALSE)
    observe({
      has_rows_rv(!is.null(rel_rows()))
    })

    output$relationships_ui <- renderUI({
      if (!has_rows_rv()) {
        filtered <- length(rels_rv()) > 0
        return(div(
          class = "empty-state",
          h4(if (filtered) {
            "No relationships match the current filters"
          } else {
            "No relationships detected"
          }),
          p(
            style = "color:var(--text-muted); font-size:13px;",
            if (filtered) {
              "Clear the source filter, the confidence filter or \"To review only\" to see the rest."
            } else {
              "Try uploading more tables or adjusting the detection method."
            }
          )
        ))
      }
      DT::DTOutput(session$ns("rel_table"))
    })

    .js_str <- function(x) {
      paste0("'", gsub("(['\\\\])", "\\\\\\1", x), "'")
    }
    .row_button <- function(input_id, key, label, cls, title) {
      sprintf(
        paste0(
          "<button class=\"btn-rel-row %s\" title=\"%s\" ",
          "onclick=\"event.stopPropagation();",
          "Shiny.setInputValue('%s', %s, {priority: 'event'})\">%s</button>"
        ),
        cls,
        title,
        session$ns(input_id),
        htmltools::htmlEscape(.js_str(key), attribute = TRUE),
        label
      )
    }

    # Built as its own reactive so a confirm or suppress can push new data
    # through the proxy below instead of re-rendering the widget, which
    # threw away the page, sort, search and scroll position every time.
    rel_df <- reactive({
      rows <- rel_rows()
      req(rows)
      source_badge <- c(
        declared = "<span class=\"rel-status rel-status-declared\">declared</span>",
        manual = "<span class=\"rel-status rel-status-manual\">manual</span>",
        confirmed = "<span class=\"rel-status rel-status-confirmed\">✓ confirmed</span>",
        detected = "<span class=\"rel-status rel-status-review\">? to review</span>"
      )
      status <- unname(source_badge[rows$source])
      source_rank <- match(rows$source, names(source_badge))
      method <- sprintf(
        "<span class=\"rel-method m-%s\">%s</span>",
        htmltools::htmlEscape(rows$method),
        htmltools::htmlEscape(
          ifelse(
            rows$method %in% names(method_labels),
            method_labels[rows$method],
            rows$method
          )
        )
      )
      actions <- vapply(
        seq_len(nrow(rows)),
        function(i) {
          paste0(
            if (rows$source[i] %in% c("declared", "manual")) {
              ""
            } else if (rows$confirmed[i]) {
              .row_button("unconfirm_rel", rows$key[i], "undo", "", "Unconfirm")
            } else {
              .row_button(
                "confirm_rel",
                rows$key[i],
                "✓",
                "btn-rel-confirm",
                "Confirm"
              )
            },
            .row_button(
              "suppress_rel",
              rows$key[i],
              "✕",
              "btn-rel-suppress",
              "Suppress"
            )
          )
        },
        character(1)
      )
      df <- data.frame(
        Source = status,
        source_rank = as.character(source_rank),
        `From table` = rows$from_table,
        `From column` = rows$from_col,
        `To table` = rows$to_table,
        `To column` = rows$to_col,
        Method = method,
        Confidence = rows$confidence,
        # Numbers passed as text on purpose: DT gives numeric columns a
        # range-slider filter that needs the noUiSlider library, and if it
        # fails to load the error stalls every later Shiny update on the
        # page. Hidden zero-padded copies keep the sort numeric.
        conf_rank = as.character(rows$conf_rank),
        `Score %` = ifelse(is.na(rows$score), "", as.character(rows$score)),
        score_sort = ifelse(
          is.na(rows$score),
          "000",
          sprintf("%03d", as.integer(rows$score))
        ),
        # The reasons carry the numbers ("value overlap 97%", "distribution
        # similarity 0.82"); the bare signal names say only which tests fired
        Evidence = ifelse(nzchar(rows$reasons), rows$reasons, rows$signals),
        Actions = actions,
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
      df
    })

    # Columns holding HTML, excluded from escaping in both the initial
    # render and every proxy update
    .html_cols <- c("Source", "Method", "Actions")

    # server = TRUE is required by dataTableProxy below, and is spelled out
    # because the other renderDT calls in this app pass server = FALSE
    output$rel_table <- DT::renderDT(server = TRUE, {
      # Isolated on purpose: updates arrive through rel_proxy
      df <- isolate(rel_df())
      req(df)
      # 0-based column indices for DataTables options
      idx <- function(name) which(names(df) == name) - 1L
      DT::datatable(
        df,
        rownames = FALSE,
        escape = setdiff(names(df), .html_cols),
        selection = list(mode = "multiple", target = "row"),
        filter = "top",
        options = list(
          pageLength = 25,
          lengthMenu = list(c(25, 50, 100, -1), c("25", "50", "100", "All")),
          order = list(list(idx("Score %"), "desc")),
          stateSave = TRUE,
          autoWidth = FALSE,
          scrollX = TRUE,
          columnDefs = list(
            # Sort Confidence by rank (high > medium > low), not alphabetically
            list(targets = idx("Confidence"), orderData = idx("conf_rank")),
            list(targets = idx("Score %"), orderData = idx("score_sort")),
            # Source sorts declared, manual, confirmed, then to review
            list(targets = idx("Source"), orderData = c(idx("source_rank"), idx("score_sort"))),
            list(targets = idx("Child rows"), orderData = idx("from_sort")),
            list(targets = idx("Parent rows"), orderData = idx("to_sort")),
            list(targets = idx("Overlap %"), orderData = idx("overlap_sort")),
            list(
              targets = c(
                idx("conf_rank"), idx("score_sort"), idx("source_rank"),
                idx("from_sort"), idx("to_sort"), idx("overlap_sort")
              ),
              visible = FALSE,
              searchable = FALSE
            ),
            list(targets = idx("Actions"), orderable = FALSE, searchable = FALSE),
            list(
              className = "dt-center",
              targets = c(
                idx("Score %"), idx("Child rows"), idx("Parent rows"),
                idx("Overlap %")
              )
            )
          )
        ),
        class = "compact hover rel-dt"
      )
    })

    # Push data changes through the proxy: paging, sort, search and scroll
    # survive. Selection is cleared, because the action that triggered the
    # update consumed it and row numbers no longer mean the same rows.
    rel_proxy <- DT::dataTableProxy("rel_table")
    observeEvent(rel_df(), {
      df <- rel_df()
      req(df)
      DT::replaceData(
        rel_proxy,
        df,
        resetPaging = FALSE,
        clearSelection = "all",
        rownames = FALSE
        # No escape argument: DT::replaceData passes ... to dataTableAjax,
        # which has no such formal, so passing it errors on every update.
        # The escaping set at render time applies to the new data too.
      )
    }, ignoreInit = TRUE)

    .selected_keys <- function() {
      rows <- rel_rows()
      sel <- input$rel_table_rows_selected
      if (is.null(rows) || length(sel) == 0) {
        showNotification(
          "Select one or more rows first.",
          type = "warning",
          duration = 3
        )
        return(character(0))
      }
      rows$key[sel]
    }

    .confirm <- function(keys) {
      review_confirm(keys, rels_rv(), confirmed_rels_rv)
    }
    .unconfirm <- function(keys) {
      review_unconfirm(keys, confirmed_rels_rv)
    }
    .suppress <- function(keys) {
      review_suppress(keys, confirmed_rels_rv, false_positives_rv)
    }

    observeEvent(input$confirm_rel, .confirm(input$confirm_rel))
    observeEvent(input$unconfirm_rel, .unconfirm(input$unconfirm_rel))
    observeEvent(input$suppress_rel, .suppress(input$suppress_rel))
    observeEvent(input$confirm_selected, .confirm(.selected_keys()))
    observeEvent(input$unconfirm_selected, .unconfirm(.selected_keys()))
    observeEvent(input$suppress_selected, .suppress(.selected_keys()))

    observeEvent(input$restore_suppressed, {
      false_positives_rv(character(0))
      showNotification(
        "All suppressed relationships restored.",
        type = "message",
        duration = 3
      )
    })

    output$dl_rels <- downloadHandler(
      filename = "table_relationships.csv",
      content = .rels_csv_content(all_rels_rv)
    )

    invisible(NULL)
  })
}

# Helper: build downloadHandler content function for relationships CSV
.rels_csv_content <- function(all_rels_rv) {
  function(file) {
    rels <- all_rels_rv()
    if (length(rels) == 0) {
      write.csv(
        data.frame(
          from_table = "",
          from_col = "",
          to_table = "",
          to_col = "",
          source = "",
          detected_by = "",
          confidence = "",
          score = numeric(0),
          signals = "",
          reasons = "",
          status = ""
        )[0, ],
        file,
        row.names = FALSE
      )
    } else {
      df <- do.call(
        rbind,
        lapply(rels, function(r) {
          data.frame(
            from_table = r$from_table,
            from_col = r$from_col,
            to_table = r$to_table,
            to_col = if (!is.na(r$to_col) && !is.null(r$to_col)) {
              r$to_col
            } else {
              ""
            },
            source = rel_source(r),
            detected_by = r$detected_by %||% "",
            confidence = if (!is.null(r$confidence)) r$confidence else "",
            score = if (!is.null(r$score)) r$score else NA_real_,
            signals = if (!is.null(r$signals)) {
              paste(names(r$signals), collapse = "; ")
            } else {
              ""
            },
            reasons = if (!is.null(r$reasons)) {
              paste(r$reasons, collapse = "; ")
            } else {
              ""
            },
            status = if (isTRUE(r$confirmed)) "confirmed" else "unreviewed",
            stringsAsFactors = FALSE
          )
        })
      )
      write.csv(df, file, row.names = FALSE)
    }
  }
}
