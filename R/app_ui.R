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
          "Load files or connect a database \u2192 detect keys and relationships \u2192 review, document, export"
        )
      ),
      tags$button(
        id = "theme-toggle",
        div(class = "toggle-track", div(class = "toggle-thumb")),
        tags$span(id = "toggle-label", "Light mode")
      )
    ),

    # Shown while Shiny is busy for more than a moment: switching to Table
    # Details on a wide schema can take seconds, and nothing on screen said
    # the app was working rather than stuck
    div(
      id = "app-busy",
      class = "app-busy",
      role = "status",
      `aria-live` = "polite",
      div(class = "app-busy-dot"),
      tags$span("Working...")
    ),

    div(
      id = "app-body",

      # Collapsed sidebar leaves this rail behind, in its place, so the
      # way back is where the thing that vanished was
      tags$button(
        id = "sidebar-rail",
        class = "sidebar-rail",
        type = "button",
        title = "Show controls",
        `aria-label` = "Show controls",
        `aria-expanded` = "false",
        `aria-controls` = "sidebar-col",
        tags$span(class = "sidebar-chevron", "â€º"),
        # A bare chevron does not say what comes back
        tags$span(class = "sidebar-rail-label", "DATA & DETECTION")
      ),

      fluidRow(
        # ---- Sidebar ----
        column(
          3,
          div(
            id = "sidebar-col",
            class = "sidebar-box",
            tags$button(
              id = "sidebar-collapse",
              class = "sidebar-collapse",
              type = "button",
              title = "Hide controls",
              `aria-label` = "Hide controls",
              `aria-expanded` = "true",
              `aria-controls` = "sidebar-col",
              tags$span(class = "sidebar-chevron", "â€¹")
            ),
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
            tabPanel("ERD", mod_erd_ui("erd")),
            tabPanel("Network overview", mod_network_ui("network")),
            tabPanel("Table Details", mod_table_details_ui("table_details")),
            tabPanel("Relationships", mod_relationships_ui("relationships")),
            tabPanel("Data Dictionary", mod_dictionary_ui("dictionary")),
            tabPanel("Name Changes", mod_name_changes_ui("name_changes")),
            tabPanel("Export", mod_export_ui("export"))
          )
        )
      )
    ),
    br(),

    # Which build is on screen: a trailing + means uncommitted changes
    div(class = "app-footer", app_build_stamp())
  )
}
