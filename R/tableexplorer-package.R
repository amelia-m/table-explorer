#' tableexplorer: Table Relationship Explorer
#'
#' Interactive Shiny app for exploring table relationships with multi-signal
#' FK detection, ERD visualization, and multi-format file support.
#'
#' @import shiny
#' @importFrom DT datatable DTOutput renderDT formatStyle styleEqual
#' @importFrom janitor clean_names make_clean_names
#' @importFrom shinythemes shinytheme
#' @importFrom visNetwork visNetwork visNetworkOutput renderVisNetwork
#'   visOptions visEdges visNodes visInteraction visEvents
#'   visHierarchicalLayout visPhysics visLayout
#' @importFrom golem with_golem_options get_golem_options
#' @importFrom stats cor median na.omit sd setNames
#' @importFrom utils head object.size read.csv read.delim write.csv
#' @keywords internal
"_PACKAGE"
