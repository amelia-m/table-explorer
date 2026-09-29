# ============================================================
# mod_dictionary.R - Data Dictionary tab
# ============================================================
#
# One row per column: what the data says (type, missing values, keys, what
# it references, examples) next to what people add (description, business
# name). Edits live in dictionary_rv, keyed "table" or "table|column" (see
# build_data_dictionary() in utils_export.R), are saved with the session and
# flow into the dbt, DBML, Mermaid and dictionary exports.

#' Data dictionary module UI
#' @noRd
mod_dictionary_ui <- function(id) {
  ns <- NS(id)
  tagList(
    br(),
    div(
      class = "dict-toolbar",
      selectizeInput(
        ns("table"),
        "Table",
        choices = c("All tables" = ""),
        width = "260px",
        options = list(placeholder = "All tables")
      ),
      div(
        class = "dict-downloads",
        downloadButton(ns("dl_csv"), "CSV", class = "dl-btn"),
        downloadButton(ns("dl_md"), "Markdown", class = "dl-btn")
      )
    ),
    uiOutput(ns("table_desc_ui")),
    div(
      class = "dict-hint",
      "Double-click a Description or Business name cell to edit it; press ",
      "Enter or click away to save. ",
      "Edits are saved with the session and included in the dbt, DBML, ",
      "Mermaid and dictionary exports."
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
    # outside (a restored session); a cell edit is already on screen, and
    # redrawing would lose the page and scroll position
    redraw <- reactiveVal(0)
    last_written <- reactiveVal(NULL)
    observeEvent(dictionary_rv(), {
      if (!identical(dictionary_rv(), last_written())) redraw(redraw() + 1)
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
      # Pick up edits made since the last redraw
      dict <- isolate(dictionary_rv())
      for (i in seq_len(nrow(dd))) {
        e <- dict_entry(dict, dd$table[i], dd$column[i])
        dd$description[i] <- e$description
        dd$business_name[i] <- e$business_name
      }
      dd
    })

    write_entry <- function(key, field, value) {
      d <- dictionary_rv()
      e <- d[[key]] %||% list()
      e[[field]] <- value
      if (!nzchar(e$description %||% "") && !nzchar(e$business_name %||% "")) {
        d[[key]] <- NULL
      } else {
        d[[key]] <- e
      }
      last_written(d)
      dictionary_rv(d)
    }

    output$table_desc_ui <- renderUI({
      tn <- input$table %||% ""
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
      tn <- input$table %||% ""
      req(nzchar(tn))
      if (!identical(input$table_desc, dict_entry(dictionary_rv(), tn)$description)) {
        write_entry(dict_key(tn), "description", input$table_desc)
      }
    }, ignoreInit = TRUE)

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
    edit_cols <- c(description = 9L, business_name = 10L)

    output$dict <- DT::renderDT({
      d <- shown_rv()
      df <- data.frame(
        Table = d$table,
        `#` = d$position,
        Column = d$column,
        Type = d$type,
        Keys = d$keys,
        References = mapply(function(refs, srcs) {
          if (!nzchar(refs)) return("")
          refs <- strsplit(refs, "; ", fixed = TRUE)[[1]]
          srcs <- strsplit(srcs, "; ", fixed = TRUE)[[1]]
          paste0(refs, " (", srcs, ")", collapse = "; ")
        }, d$references, d$reference_source, USE.NAMES = FALSE),
        `Missing %` = d$pct_missing,
        Unique = d$n_unique,
        Examples = d$examples,
        Description = d$description,
        `Business name` = d$business_name,
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
      DT::datatable(
        df,
        rownames = FALSE,
        # No per-column filters: numeric ones need DT's slider library,
        # whose load failure stalls the page (see mod_relationships.R)
        filter = "none",
        selection = "none",
        editable = list(
          target = "cell",
          disable = list(columns = setdiff(seq_len(ncol(df)) - 1L, edit_cols))
        ),
        options = list(
          pageLength = 50,
          lengthMenu = list(c(25, 50, 100, -1), c("25", "50", "100", "All")),
          scrollX = TRUE,
          autoWidth = FALSE,
          order = list(list(0, "asc"), list(1, "asc")),
          columnDefs = list(
            list(className = "dict-editable", targets = unname(edit_cols)),
            list(className = "dt-center", targets = c(1L, 6L, 7L))
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

    invisible(NULL)
  })
}
