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

# ── Declared relationships (schema files, databases, Access) ──
# Tables and columns are loaded with janitor::clean_names(), so declared
# links must use the same cleaned names to line up with them.
clean_declared_rels <- function(rels) {
  lapply(rels, function(r) {
    for (f in c("from_table", "from_col", "to_table", "to_col")) {
      v <- r[[f]]
      if (length(v) == 1 && !is.na(v) && nzchar(v)) {
        r[[f]] <- janitor::make_clean_names(v)
      }
    }
    r
  })
}

# Add declared links to what's there, one entry per relationship
merge_declared_rels <- function(existing, new) {
  all <- c(existing %||% list(), clean_declared_rels(new %||% list()))
  if (length(all) == 0) {
    return(list())
  }
  keys <- vapply(all, rel_key, character(1))
  all[!duplicated(keys)]
}

# Where a relationship came from, for display, filtering and export:
# "declared" (schema file, database constraint, Access), "manual" (added by
# hand), "confirmed" (a detected link someone reviewed) or "detected".
rel_source <- function(r) {
  if (identical(r$detected_by, "schema")) {
    "declared"
  } else if (identical(r$detected_by, "manual")) {
    "manual"
  } else if (isTRUE(r$confirmed)) {
    "confirmed"
  } else {
    "detected"
  }
}

rel_source_labels <- c(
  declared = "Declared",
  manual = "Manual",
  confirmed = "Confirmed",
  detected = "Detected"
)

# Declared links win over the same detected link, which is folded into the
# declared entry ("also detected"). With hide_detected_on_declared, detected
# links from a column that has a declared link are dropped as well.
combine_relationships <- function(
  auto,
  manual = list(),
  declared = list(),
  hide_detected_on_declared = FALSE
) {
  declared <- declared %||% list()
  auto <- auto %||% list()
  if (length(declared) > 0 && length(auto) > 0) {
    dkeys <- vapply(declared, rel_key, character(1))
    akeys <- vapply(auto, rel_key, character(1))
    for (i in which(akeys %in% dkeys)) {
      j <- match(akeys[i], dkeys)
      declared[[j]]$also_detected <- auto[[i]]$score %||% NA_real_
    }
    auto <- auto[!akeys %in% dkeys]
    if (isTRUE(hide_detected_on_declared) && length(auto) > 0) {
      dcols <- vapply(declared, function(r) paste(r$from_table, r$from_col), "")
      acols <- vapply(auto, function(r) paste(r$from_table, r$from_col), "")
      auto <- auto[!acols %in% dcols]
    }
  }
  c(auto, manual %||% list(), declared)
}

# sources: "both", "declared" (declared + manual) or "detected"
# (detected + confirmed)
filter_rel_sources <- function(rels, sources = "both") {
  if (identical(sources, "declared")) {
    Filter(function(r) rel_source(r) %in% c("declared", "manual"), rels)
  } else if (identical(sources, "detected")) {
    Filter(function(r) rel_source(r) %in% c("detected", "confirmed"), rels)
  } else {
    rels
  }
}
