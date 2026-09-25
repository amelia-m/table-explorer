# ============================================================
# utils_helpers.R - Shared helper utilities
# ============================================================

#' @noRd
`%||%` <- function(a, b) {
  if (
    !is.null(a) &&
      length(a) > 0 &&
      !(is.character(a) && length(a) == 1L && !nzchar(a))
  ) {
    a
  } else {
    b
  }
}

#' Stable key for a relationship, used for suppress/confirm decisions
#' @noRd
rel_key <- function(r) {
  to_col <- r$to_col
  if (is.null(to_col) || length(to_col) == 0 || is.na(to_col)) {
    to_col <- ""
  }
  paste(r$from_table, r$from_col, r$to_table, to_col, sep = "|")
}
