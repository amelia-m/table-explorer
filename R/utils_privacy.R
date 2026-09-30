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

# NULL when nothing suggests personal data, else list(reason)
privacy_guess <- function(column, values = NULL) {
  # true/false columns hold flags about people, not details of them
  if (is.logical(values)) {
    return(NULL)
  }
  cn <- clean_name(column)
  parts <- sub("\\d+$", "", strsplit(cn, "_", fixed = TRUE)[[1]])
  qualified <- c(parts[-1] %in% privacy_qualifiers, FALSE)
  hit_word <- intersect(parts[!qualified], privacy_words)
  hit_phrase <- privacy_phrases[vapply(privacy_phrases, function(p) {
    grepl(paste0("(^|_)", p, "(\\d*)(_|$)"), cn) &&
      !grepl(paste0("(^|_)", p, "\\d*_(", paste(privacy_qualifiers, collapse = "|"), ")(_|$)"), cn)
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
        set.seed(7)
        v <- sample(v, 500)
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

# Glob patterns ("*_name, dob*, mrn, clients.notes") as one regex test
privacy_pattern_match <- function(patterns, table, column) {
  pats <- trimws(strsplit(patterns %||% "", ",", fixed = TRUE)[[1]])
  pats <- pats[nzchar(pats)]
  if (length(pats) == 0) {
    return(FALSE)
  }
  targets <- c(column, paste(table, column, sep = "."))
  any(vapply(pats, function(p) {
    any(grepl(utils::glob2rx(tolower(p)), tolower(targets)))
  }, logical(1)))
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
  if (isTRUE(e$private)) {
    status <- if (identical(e$private_source, "import")) "imported" else "user_private"
    return(list(private = TRUE, status = status, reason = reason, needs_review = FALSE))
  }
  if (isFALSE(e$private)) {
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
    if (identical(review$state, "rejected")) {
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
          table = t, column = cn, reason = p$reason, stringsAsFactors = FALSE
        )
      }
    }
  }
  if (length(rows) == 0) {
    return(data.frame(table = character(0), column = character(0), reason = character(0)))
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
    e$privacy_review <- list(state = state, reason = guess$reason %||% "")
    dictionary[[k]] <- e
  }
  dictionary
}
