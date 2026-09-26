# ============================================================
# mod_erd.R - ERD Diagram (standard physical ERD)
# ============================================================
#
# Table cards with PK/FK/UK badges, lines from the FK row to the PK row,
# orthogonal routing and crow's-foot ends. Layout runs in the browser with
# elkjs (inst/app/www/erd.js); the server sends the ELK graph built from
# erd_model() / erd_view() / erd_elk_graph(). The force-directed view lives
# on in mod_network.R ("Network overview").

erd_large_schema <- 40L

#' ERD diagram module UI
#' @noRd
mod_erd_ui <- function(id) {
  ns <- NS(id)
  tagList(
    br(),
    conditionalPanel(
      "output.has_tables == 'false'",
      div(
        class = "empty-state",
        div(style = "font-size: 48px; margin-bottom: 16px;", "◫"),
        h4("No tables loaded"),
        p(
          style = "color:var(--text-muted); font-size:13px;",
          "Upload one or more files using the sidebar to begin."
        )
      )
    ),
    conditionalPanel(
      "output.has_tables == 'true'",
      div(
        class = "erd-controls",
        selectizeInput(
          ns("focus"),
          "Focus table",
          choices = c("All tables" = ""),
          width = "220px",
          options = list(placeholder = "All tables")
        ),
        sliderInput(
          ns("hops"),
          "Hops (4 = all)",
          min = 1,
          max = 4,
          value = 2,
          step = 1,
          width = "130px",
          ticks = FALSE
        ),
        radioButtons(
          ns("detail"),
          "Show",
          choices = c(
            "All columns" = "all",
            "Keys only" = "keys",
            "Names only" = "names"
          ),
          selected = "all",
          inline = TRUE
        ),
        selectizeInput(
          ns("areas"),
          "Subject areas",
          choices = NULL,
          multiple = TRUE,
          width = "220px",
          options = list(placeholder = "All areas")
        ),
        radioButtons(
          ns("direction"),
          "Layout",
          choices = c("Left → right" = "RIGHT", "Top → down" = "DOWN"),
          selected = "RIGHT",
          inline = TRUE
        ),
        checkboxInput(ns("show_low"), "Show low-confidence links", FALSE),
        div(
          class = "erd-buttons",
          tags$button(
            class = "btn-rel",
            onclick = sprintf("erdFit('%s')", ns("canvas")),
            "Fit"
          ),
          tags$button(
            class = "btn-rel",
            onclick = sprintf("erdDownload('%s', 'svg')", ns("canvas")),
            "⬇ SVG"
          ),
          tags$button(
            class = "btn-rel",
            onclick = sprintf("erdDownload('%s', 'png')", ns("canvas")),
            "⬇ PNG"
          )
        )
      ),
      uiOutput(ns("summary")),
      div(
        class = "erd-layout",
        div(
          class = "erd-main",
          div(id = ns("canvas"), class = "erd-canvas"),
          tags$details(
            class = "erd-legend",
            open = NA,
            tags$summary("Legend"),
            div(id = ns("legend"), class = "erd-legend-body")
          )
        ),
        div(class = "erd-side", uiOutput(ns("side")))
      )
    )
  )
}

#' ERD diagram module server
#'
#' @param id Module id
#' @param tables_rv reactive: visible tables
#' @param rels_rv reactive: visible relationships (with `confirmed`)
#' @param pk_map_rv reactive: PK candidates per table
#' @param composite_pk_map_rv reactive: composite keys per table
#' @param confirmed_rels_rv reactiveVal of confirmed relationships (by key)
#' @param false_positives_rv reactiveVal of suppressed relationship keys
#' @noRd
mod_erd_server <- function(
  id,
  tables_rv,
  rels_rv,
  pk_map_rv,
  composite_pk_map_rv,
  confirmed_rels_rv,
  false_positives_rv
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    selected_rel <- reactiveVal(NULL)
    selected_table <- reactiveVal(NULL)
    # Detail level the user picked; until then large schemas start in
    # "Keys only" (decided here, so the first draw is already the light one)
    user_detail <- reactiveVal(NULL)
    observeEvent(input$detail, user_detail(input$detail), ignoreInit = TRUE)
    detail_rv <- reactive({
      user_detail() %||%
        if (length(model_rv()$tables) > erd_large_schema) "keys" else "all"
    })

    model_rv <- reactive({
      tbls <- tables_rv()
      req(length(tbls) > 0)
      erd_model(tbls, rels_rv(), pk_map_rv(), composite_pk_map_rv())
    })

    # Keep the focus / area choices in step with the loaded tables
    observeEvent(model_rv(), {
      m <- model_rv()
      tnames <- names(m$tables)
      areas <- sort(unique(vapply(
        m$tables,
        function(t) t$subject_area,
        character(1)
      )))
      focus <- isolate(input$focus)
      updateSelectizeInput(
        session,
        "focus",
        choices = c("All tables" = "", tnames),
        selected = if (!is.null(focus) && focus %in% tnames) focus else ""
      )
      updateSelectizeInput(
        session,
        "areas",
        choices = areas,
        selected = intersect(isolate(input$areas), areas)
      )
      if (is.null(user_detail()) && !identical(detail_rv(), isolate(input$detail))) {
        updateRadioButtons(session, "detail", selected = detail_rv())
      }
    })

    view_rv <- reactive({
      m <- model_rv()
      hops <- input$hops %||% 2
      erd_view(
        m,
        focus = input$focus,
        hops = if (hops >= 4) Inf else hops,
        areas = input$areas,
        show_low = isTRUE(input$show_low),
        detail = detail_rv()
      )
    })

    observe({
      v <- view_rv()
      graph <- erd_elk_graph(
        v,
        detail = v$detail,
        direction = input$direction %||% "RIGHT"
      )
      session$sendCustomMessage(
        "erd-render",
        list(
          container = ns("canvas"),
          legend = ns("legend"),
          relInput = ns("erd_rel"),
          tableInput = ns("erd_table"),
          graph = graph
        )
      )
    })

    output$summary <- renderUI({
      v <- view_rv()
      m <- model_rv()
      n_all <- length(m$tables)
      parts <- c(
        sprintf(
          "%d of %d table%s",
          length(v$tables),
          n_all,
          if (n_all == 1) "" else "s"
        ),
        sprintf(
          "%d relationship%s",
          length(v$rels),
          if (length(v$rels) == 1) "" else "s"
        ),
        if (v$hidden_rels > 0) {
          sprintf("%d hidden by filters", v$hidden_rels)
        }
      )
      hint <- if (n_all > erd_large_schema && !nzchar(input$focus %||% "")) {
        " · Large schema: pick a focus table to explore its neighbourhood."
      }
      div(class = "erd-summary", paste(parts, collapse = " · "), hint)
    })

    observeEvent(input$erd_rel, {
      selected_rel(input$erd_rel)
      selected_table(NULL)
    })
    observeEvent(input$erd_table, {
      selected_table(input$erd_table)
      selected_rel(NULL)
    })
    observeEvent(input$focus_orphan, {
      updateSelectizeInput(session, "focus", selected = input$focus_orphan)
    })
    observeEvent(input$focus_selected, {
      updateSelectizeInput(session, "focus", selected = selected_table())
    })
    observeEvent(input$confirm, {
      review_confirm(selected_rel(), rels_rv(), confirmed_rels_rv)
    })
    observeEvent(input$unconfirm, {
      review_unconfirm(selected_rel(), confirmed_rels_rv)
    })
    observeEvent(input$suppress, {
      review_suppress(selected_rel(), confirmed_rels_rv, false_positives_rv)
      selected_rel(NULL)
    })

    words_child <- c(one = "at most one", many = "zero or more", unknown = "unknown (no rows)")
    words_parent <- c(one = "exactly one", zero = "zero or one", unknown = "unknown (no rows)")

    output$side <- renderUI({
      m <- model_rv()
      key <- selected_rel()
      tname <- selected_table()
      v <- view_rv()

      orphan_ui <- if (length(v$orphans) > 0) {
        tags$details(
          class = "erd-orphans",
          tags$summary(sprintf("Unconnected tables (%d)", length(v$orphans))),
          div(lapply(v$orphans, function(o) {
            tags$button(
              class = "erd-orphan",
              onclick = sprintf(
                "Shiny.setInputValue('%s', '%s', {priority: 'event'})",
                ns("focus_orphan"),
                gsub("'", "\\\\'", o)
              ),
              o
            )
          }))
        )
      }

      detail_ui <- if (!is.null(key)) {
        r <- Filter(function(x) identical(rel_key(x), key), m$rels)
        if (length(r) == 0) {
          NULL
        } else {
          r <- r[[1]]
          confirmed <- identical(r$provenance, "confirmed")
          div(
            class = "erd-panel",
            div(class = "erd-panel-title", "Relationship"),
            div(
              class = "erd-panel-rel",
              sprintf("%s.%s", r$from_table, r$from_col),
              tags$br(),
              "→ ",
              sprintf("%s.%s", r$to_table, r$to_col %||% r$from_col)
            ),
            tags$dl(
              tags$dt("Each child row has"),
              tags$dd(paste(words_parent[[r$parent_min]], "parent")),
              tags$dt("Each parent has"),
              tags$dd(paste(words_child[[r$child_max]], "children")),
              tags$dt("Identifying"),
              tags$dd(if (isTRUE(r$identifying)) "yes (FK is part of the PK)" else "no"),
              tags$dt("Source"),
              tags$dd(
                r$provenance,
                if (identical(r$provenance, "inferred") && !is.null(r$score)) {
                  sprintf(" · %s %d%%", r$confidence, round(100 * r$score))
                }
              ),
              if (length(r$reasons)) tags$dt("Evidence"),
              if (length(r$reasons)) tags$dd(paste(r$reasons, collapse = "; "))
            ),
            div(
              class = "erd-panel-actions",
              if (confirmed) {
                actionButton(ns("unconfirm"), "Undo confirm", class = "btn-rel")
              } else if (identical(r$provenance, "inferred")) {
                actionButton(ns("confirm"), "✓ Confirm", class = "btn-rel btn-rel-confirm")
              },
              if (r$provenance %in% c("inferred", "confirmed")) {
                actionButton(ns("suppress"), "✕ Suppress", class = "btn-rel btn-rel-suppress")
              }
            )
          )
        }
      } else if (!is.null(tname) && tname %in% names(m$tables)) {
        t <- m$tables[[tname]]
        cols <- t$columns
        div(
          class = "erd-panel",
          div(class = "erd-panel-title", t$name),
          div(
            class = "erd-panel-meta",
            sprintf(
              "%s rows · %d columns · %s · %s",
              format(t$n_rows, big.mark = ","),
              nrow(cols),
              t$role,
              t$subject_area
            )
          ),
          tags$table(
            class = "erd-panel-cols",
            lapply(seq_len(nrow(cols)), function(i) {
              tags$tr(
                tags$td(paste(c(
                  if (cols$pk[i]) "PK",
                  if (!is.na(cols$fk_index[i])) paste0("FK", cols$fk_index[i]),
                  if (cols$uk[i]) "UK"
                ), collapse = ",")),
                tags$td(cols$name[i]),
                tags$td(paste0(cols$type[i], if (isTRUE(cols$nullable[i])) " ∅"))
              )
            })
          ),
          actionButton(ns("focus_selected"), "Focus this table", class = "btn-rel")
        )
      } else {
        div(
          class = "erd-panel erd-panel-hint",
          "Click a line for its details and to confirm or suppress it; ",
          "click a table header to see its columns."
        )
      }
      tagList(detail_ui, orphan_ui)
    })

    invisible(NULL)
  })
}
