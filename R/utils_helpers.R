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

# ── Relationship review actions ──────────────────────────────
# Shared by the Relationships tab and the ERD diagram. Keys are rel_key()
# strings; confirmed_rv holds a named list (key -> relationship) and
# suppressed_rv a character vector of keys.

#' @noRd
review_confirm <- function(keys, rels, confirmed_rv, notify = TRUE) {
  by_key <- setNames(rels, vapply(rels, rel_key, character(1)))
  keys <- intersect(keys, names(by_key))
  if (length(keys) == 0) {
    return(invisible(character(0)))
  }
  confirmed <- confirmed_rv()
  for (k in keys) {
    r <- by_key[[k]]
    r$confirmed <- NULL
    confirmed[[k]] <- r
  }
  confirmed_rv(confirmed)
  if (notify) {
    shiny::showNotification(
      sprintf(
        "%d relationship%s confirmed.",
        length(keys),
        if (length(keys) == 1) "" else "s"
      ),
      type = "message",
      duration = 3
    )
  }
  invisible(keys)
}

#' @noRd
review_unconfirm <- function(keys, confirmed_rv) {
  confirmed <- confirmed_rv()
  keys <- intersect(keys, names(confirmed))
  if (length(keys) > 0) {
    confirmed_rv(confirmed[setdiff(names(confirmed), keys)])
  }
  invisible(keys)
}

#' @noRd
review_suppress <- function(keys, confirmed_rv, suppressed_rv, notify = TRUE) {
  if (length(keys) == 0) {
    return(invisible(character(0)))
  }
  # Suppressing a link also withdraws any confirmation
  review_unconfirm(keys, confirmed_rv)
  suppressed_rv(union(suppressed_rv(), keys))
  if (notify) {
    shiny::showNotification(
      sprintf(
        "%d relationship%s suppressed.",
        length(keys),
        if (length(keys) == 1) "" else "s"
      ),
      type = "message",
      duration = 3
    )
  }
  invisible(keys)
}
