# ============================================================
# utils_privacy.R - Personal-data flags for the data dictionary
# ============================================================
#
# Decides which columns show example values (and value ranges) in the data
# dictionary and its exports. Metadata that can't identify anyone (type,
# format, % missing, unique count, text lengths) is always shown.
#
# Order of precedence for a column:
#   1. the user's explicit choice on that column (private TRUE/FALSE);
#   2. the user's private name patterns (e.g. "*_name, dob*, mrn");
#   3. the automatic guess (name words or value patterns), which stays
#      private until the user reviews it: "confirmed" keeps it private,
#      "rejected" clears it. A review is kept until the reason changes.
#
# Settings live in the dictionary edits under the reserved key ".settings":
#   private_patterns (string), examples ("auto" | "off").

# Name words that suggest personal data. Matched against the column name's
# parts (split at "_"), ignoring trailing digits, so zip5 and street1 count.
privacy_words <- c(
  "ssn", "sin", "nino", "password", "passwd", "pwd", "dob", "birth",
  "birthdate", "birthday", "email", "phone", "mobile", "telephone", "fax",
  "address", "addr", "street", "zip", "zipcode", "postcode", "postal",
  "name", "surname", "fname", "lname", "mrn", "medicaid", "medicare",
  "passport", "license", "licence"
)
privacy_phrases <- c(
  "e_mail", "first_name", "last_name", "full_name", "middle_name",
  "given_name", "insurance_id", "member_id", "ssn_last4", "birth_dt", "dob_dt"
)

# A name word followed by one of these describes the data rather than
# holding it: address_type, email_verified, name_count
# "name" after one of these names a thing, not a person: product_name,
# company_name, city_name
privacy_entity_words <- c(
  "product", "company", "org", "organization", "organisation", "category",
  "file", "table", "column", "field", "city", "country", "state", "county",
  "brand", "item", "site", "program", "programme", "service", "vendor",
  "supplier", "school", "project", "event", "facility", "department", "dept",
  "unit", "team", "group", "store", "branch", "business", "agency", "plan",
  "course", "campaign", "region", "location", "place", "street", "host",
  "server", "app", "model", "feature", "type", "status", "tag", "role",
  "code", "domain", "sheet", "report"
)

privacy_qualifiers <- c(
  "type", "types", "category", "kind", "count", "cnt", "flag", "status",
  "format", "verified", "valid", "length", "len", "source", "changed", "updated"
)

# Value patterns: share of a sample that must match
privacy_value_patterns <- list(
  list(what = "email addresses", pattern = "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"),
  list(
    what = "phone numbers",
    pattern = "^(\\+?1[-. ]?)?\\(?\\d{3}\\)?[-. ]\\d{3}[-. ]\\d{4}$"
  ),
  list(what = "social security numbers", pattern = "^\\d{3}-\\d{2}-\\d{4}$")
)
privacy_value_threshold <- 0.8

# NULL when nothing suggests personal data, else list(reason). Cached by
# column name and content: the dictionary asks again for every column on
# every edit, and the value checks scan the whole column.
.privacy_guess_cache <- new.env(parent = emptyenv())

privacy_guess <- function(column, values = NULL) {
  if (is.null(values)) {
    return(privacy_guess_uncached(column))
  }
  key <- paste0(column, "\r", rlang::hash(values))
  hit <- .privacy_guess_cache[[key]]
  if (!is.null(hit)) {
    return(hit$guess)
  }
  if (length(.privacy_guess_cache) > 5000) {
    rm(list = ls(.privacy_guess_cache), envir = .privacy_guess_cache)
  }
  guess <- privacy_guess_uncached(column, values)
  assign(key, list(guess = guess), envir = .privacy_guess_cache)
  guess
}

privacy_guess_uncached <- function(column, values = NULL) {
  # true/false columns hold flags about people, not details of them (an
  # all-missing column also reads as logical; its name still counts)
  if (is.logical(values) && any(!is.na(values))) {
    return(NULL)
  }
  cn <- clean_name(column)
  parts <- sub("\\d+$", "", strsplit(cn, "_", fixed = TRUE)[[1]])
  n <- length(parts)
  # A word followed anywhere later by a qualifier describes the data
  # (address_type, zip_code_type); "name" after an entity word names a
  # thing (product_name)
  qualified <- vapply(seq_len(n), function(i) any(parts[-seq_len(i)] %in% privacy_qualifiers), logical(1))
  entity <- parts == "name" & c(FALSE, parts[-n] %in% privacy_entity_words)
  hit_word <- intersect(parts[!qualified & !entity], privacy_words)
  qual_re <- paste0("_(.*_)?(", paste(privacy_qualifiers, collapse = "|"), ")(_|$)")
  hit_phrase <- privacy_phrases[vapply(privacy_phrases, function(p) {
    m <- regexpr(paste0("(^|_)", p, "\\d*(_|$)"), cn)
    m > 0 && !grepl(qual_re, substring(cn, m + attr(m, "match.length") - 1L))
  }, logical(1))]
  hits <- c(hit_phrase, hit_word)
  if (length(hits) > 0) {
    return(list(reason = sprintf("name contains \"%s\"", hits[[1]])))
  }
  if (!is.null(values) && length(values) > 0) {
    v <- as.character(values[!is.na(values)])
    v <- trimws(v[nzchar(trimws(v))])
    if (length(v) > 0) {
      if (length(v) > 500) {
        v <- with_local_seed(7, sample(v, 500))
      }
      for (p in privacy_value_patterns) {
        share <- mean(grepl(p$pattern, v, perl = TRUE))
        if (share >= privacy_value_threshold) {
          return(list(reason = sprintf("%d%% of values look like %s", round(100 * share), p$what)))
        }
      }
    }
  }
  NULL
}

# Glob patterns ("*_name, dob*, mrn, clients.notes"): a pattern with a dot
# matches "table.column", any other only the column name
privacy_pattern_match <- function(patterns, table, column) {
  pats <- trimws(strsplit(patterns %||% "", ",", fixed = TRUE)[[1]])
  pats <- pats[nzchar(pats)]
  if (length(pats) == 0) {
    return(FALSE)
  }
  any(vapply(pats, function(p) {
    target <- if (grepl(".", p, fixed = TRUE)) paste(table, column, sep = ".") else column
    grepl(utils::glob2rx(tolower(p)), tolower(target))
  }, logical(1)))
}

# Privacy decisions that let values show; dropped when the data they were
# made for goes away, so new data starts on the safe side
privacy_reset <- function(dictionary, tables = NULL) {
  for (k in setdiff(names(dictionary), ".settings")) {
    if (!is.null(tables) && !(strsplit(k, "|", fixed = TRUE)[[1]][1] %in% tables)) next
    e <- dictionary[[k]]
    if (isFALSE(e[["private"]])) e[["private"]] <- NULL
    if (isFALSE(e$hide_examples)) e$hide_examples <- NULL
    e$public_for <- NULL
    e$examples_for <- NULL
    if (identical(e$privacy_review$state, "rejected")) e$privacy_review <- NULL
    dictionary[[k]] <- if (dict_entry_empty(e)) NULL else e
  }
  dictionary
}

# "Not private" and "show examples" let real values show, so they hold only
# for the data they were chosen for: each carries a hash of the column
# (public_for, examples_for). New data under the same name (an overwrite, a
# reload, another upload) goes back to the safe side.
privacy_data_hash <- function(values) {
  # Factors are compared as text, the way the dictionary reads them
  rlang::hash(if (is.factor(values)) as.character(values) else values)
}

privacy_holds <- function(stamp, values) {
  is.null(values) || identical(stamp, privacy_data_hash(values))
}

# TRUE when the user turned examples on for this column's current data
dict_examples_forced <- function(dictionary, table, column, values = NULL) {
  e <- dictionary[[dict_key(table, column)]] %||% list()
  isFALSE(e$hide_examples) && privacy_holds(e$examples_for, values)
}

dict_settings <- function(dictionary) {
  s <- dictionary[[".settings"]] %||% list()
  list(
    private_patterns = s$private_patterns %||% "",
    examples = s$examples %||% "auto"
  )
}

# Privacy for one column:
#   private       TRUE/FALSE, what the exports act on
#   status        auto_unreviewed | confirmed | not_personal | user_private |
#                 imported | user_public | pattern | none
#   reason        why it was flagged ("" when not)
#   needs_review  TRUE while an automatic flag hasn't been reviewed
dict_privacy <- function(dictionary, table, column, values = NULL) {
  e <- dictionary[[dict_key(table, column)]] %||% list()
  guess <- privacy_guess(column, values)
  reason <- guess$reason %||% ""
  if (isTRUE(e[["private"]])) {
    status <- if (identical(e$private_source, "import")) "imported" else "user_private"
    return(list(private = TRUE, status = status, reason = reason, needs_review = FALSE))
  }
  if (isFALSE(e[["private"]]) && privacy_holds(e$public_for, values)) {
    return(list(private = FALSE, status = "user_public", reason = reason, needs_review = FALSE))
  }
  if (privacy_pattern_match(dict_settings(dictionary)$private_patterns, table, column)) {
    return(list(private = TRUE, status = "pattern", reason = "matches a private name pattern", needs_review = FALSE))
  }
  if (is.null(guess)) {
    return(list(private = FALSE, status = "none", reason = "", needs_review = FALSE))
  }
  review <- e$privacy_review
  if (!is.null(review) && identical(review$reason, reason)) {
    if (identical(review$state, "confirmed")) {
      return(list(private = TRUE, status = "confirmed", reason = reason, needs_review = FALSE))
    }
    # "Not personal" lets values show, so it holds only for the data it
    # was decided for (reviews saved without a stamp hold as before)
    if (identical(review$state, "rejected") &&
      (is.null(review$data_for) || privacy_holds(review$data_for, values))) {
      return(list(private = FALSE, status = "not_personal", reason = reason, needs_review = FALSE))
    }
  }
  # Unreviewed automatic flags stay private: the safe side
  list(private = TRUE, status = "auto_unreviewed", reason = reason, needs_review = TRUE)
}

privacy_status_labels <- c(
  auto_unreviewed = "private (auto, to review)",
  confirmed = "private (confirmed)",
  not_personal = "not personal (reviewed)",
  user_private = "private (set by you)",
  imported = "private (from imported file)",
  user_public = "not private (set by you)",
  pattern = "private (name pattern)",
  none = ""
)

# Columns whose automatic flag still needs a decision, as a data frame
privacy_review_queue <- function(tables, dictionary) {
  rows <- list()
  for (t in names(tables)) {
    df <- tables[[t]]
    for (cn in names(df)) {
      p <- dict_privacy(dictionary, t, cn, df[[cn]])
      if (isTRUE(p$needs_review)) {
        rows[[length(rows) + 1]] <- data.frame(
          table = t, column = cn, reason = p$reason,
          # An all-NA column has nothing to disclose, so the caller can
          # keep it out of the review queue
          n_values = sum(!is.na(df[[cn]])),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(rows) == 0) {
    return(data.frame(
      table = character(0), column = character(0), reason = character(0),
      n_values = integer(0)
    ))
  }
  do.call(rbind, rows)
}

# Record review decisions for a set of columns
privacy_review_set <- function(dictionary, tables, keys, state) {
  for (k in keys) {
    parts <- strsplit(k, "|", fixed = TRUE)[[1]]
    t <- parts[1]
    cn <- paste(parts[-1], collapse = "|")
    guess <- privacy_guess(cn, tables[[t]][[cn]])
    e <- dictionary[[k]] %||% list()
    values <- tables[[t]][[cn]]
    e$privacy_review <- list(state = state, reason = guess$reason %||% "")
    if (identical(state, "rejected") && !is.null(values)) {
      e$privacy_review$data_for <- privacy_data_hash(values)
    }
    dictionary[[k]] <- e
  }
  dictionary
}
