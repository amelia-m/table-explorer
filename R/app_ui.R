# ============================================================
# app_ui.R - Main Application UI
# ============================================================

#' @noRd
app_ui <- function(request) {
  fluidPage(
    theme = shinythemes::shinytheme("flatly"),

    tags$head(
      # Static CSS
      tags$link(
        rel = "stylesheet",
        href = "tableexplorer/styles.css"
      ),
      # Static JS
      tags$script(src = "tableexplorer/app.js"),
      # ERD diagram: layout (elkjs, EPL-2.0) and pan/zoom (BSD-2)
      tags$script(src = "tableexplorer/vendor/elkjs/elk-api.js"),
      tags$script(src = "tableexplorer/vendor/svg-pan-zoom/svg-pan-zoom.min.js"),
      tags$script(src = "tableexplorer/erd.js")
    ),

    # ---- Header ----
    div(
      class = "app-header",
      div(
        h2("Table Relationship Explorer"),
        p(
          "Upload CSV files \u2192 detect FK relationships \u2192 visualise ERD"
        )
      ),
      tags$button(
        id = "theme-toggle",
        div(class = "toggle-track", div(class = "toggle-thumb")),
        tags$span(id = "toggle-label", "Light mode")
      )
    ),

    fluidRow(
      # ---- Sidebar ----
      column(
        3,
        div(
          class = "sidebar-box",
          mod_upload_ui("upload"),
          tags$hr(),
          mod_detection_ui("detection"),
          tags$hr(),
          mod_db_connect_ui("db"),
          tags$hr(),
          mod_manual_override_ui("upload")
        )
      ),

      # ---- Main Panel ----
      column(
        9,
        tabsetPanel(
          id = "main_tabs",
          tabPanel("ERD Diagram", mod_erd_ui("erd")),
          tabPanel("Network overview", mod_network_ui("network")),
          tabPanel("Table Details", mod_table_details_ui("table_details")),
          tabPanel("Relationships", mod_relationships_ui("relationships")),
          tabPanel("Name Changes", mod_name_changes_ui("name_changes")),
          tabPanel("Export", mod_export_ui("export"))
        )
      )
    ),
    br()
  )
}
