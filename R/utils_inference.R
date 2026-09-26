# ============================================================
# utils_inference.R - PK/FK Detection Engine (7-Signal)
# ============================================================
#
# @noRd

# janitor functions available via package imports

# ── Confidence thresholds ────────────────────────────────────

overlap_high <- 0.98
overlap_medium <- 0.80
name_sim_high <- 0.85
name_sim_med <- 0.72
dist_sim_high <- 0.90
dist_sim_med <- 0.75

# ── Signal weight map for noisy-OR aggregation ───────────────

weight_map <- c(
  naming_exact = 1.00,
  naming_role = 0.90,
  naming_self = 0.90,
  cardinality_match = 0.95,
  overlap_high = 0.90,
  name_sim = 0.60,
  overlap_medium = 0.55,
  dist_high = 0.50,
  format_match = 0.40,
  dist_med = 0.30,
  name_sim_weak = 0.25,
  null_corr = 0.20
)

# ── Signal -> human-readable label map ───────────────────────

label_map <- c(
  naming_exact = "naming",
  naming_role = "naming",
  naming_self = "naming",
  name_sim = "name_similarity",
  name_sim_weak = "name_similarity",
  overlap_high = "value_overlap",
  overlap_medium = "value_overlap",
  cardinality_match = "cardinality",
  format_match = "format",
  dist_high = "distribution",
  dist_med = "distribution",
  null_corr = "null_pattern"
)

# ── Format fingerprint patterns ──────────────────────────────

format_patterns <- list(
  list(
    name = "uuid",
    pattern = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
  ),
  list(name = "email", pattern = "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"),
  list(name = "iso_ts", pattern = "^\\d{4}-\\d{2}-\\d{2}[ T]\\d{2}:\\d{2}"),
  list(name = "iso_date", pattern = "^\\d{4}-\\d{2}-\\d{2}$"),
  list(name = "zip_us", pattern = "^\\d{5}(-\\d{4})?$"),
  list(name = "phone", pattern = "^\\+?[\\d\\s\\-().]{7,15}$"),
  list(name = "hex_color", pattern = "^#[0-9a-fA-F]{3,6}$"),
  list(name = "int_code", pattern = "^\\d{1,6}$"),
  list(name = "alpha_code", pattern = "^[A-Z]{2,4}$")
)

# ── Name helpers ─────────────────────────────────────────────

# Memoised: detection calls this for every column pair, and
# janitor::make_clean_names is slow enough to dominate large scans.
.clean_name_cache <- new.env(parent = emptyenv())

clean_name <- function(name) {
  # Prefixed so an empty or "" input never becomes a zero-length env name
  key <- paste0("k:", paste(name, collapse = "\r"))
  hit <- .clean_name_cache[[key]]
  if (is.null(hit)) {
    hit <- janitor::make_clean_names(name)
    assign(key, hit, envir = .clean_name_cache)
  }
  hit
}

id_stem <- function(col_clean) sub("_id$", "", col_clean)

# ── Naming conventions ───────────────────────────────────────
# Covers common conventions across database tools:
#   FK columns:  customer_id (Rails/Django/Access), CustomerID (SQL Server;
#                cleaned to customer_id), id_customer, fk_customer,
#                customer_key / customer_sk (warehouses), state_code /
#                state_cd (code lookups), order_no / _num / _nbr,
#                customer_uuid / _guid
#   Role words:  referring_provider_id, trax_enrollment_status_id
#   Tables:      tbl_/tlk_/tlu_/lkp_/lu_/ref_/dim_/fact_/stg_/mst_ prefixes,
#                dbo./public. schemas, _lookup/_lkp/_ref/_dim/_codes/_types
#                suffixes, regular and common irregular plurals

schema_prefix_re <- "^(dbo|public|main|sys)_"
table_prefix_re <- paste0(
  "^(tbl|tlk|tlu|tb|lkp|lk|lu|lookup|ref|dim|fact|fct|stg|raw|mst|master)_"
)
table_suffix_re <- "_(lookup|lkp|lu|ref|dim|tbl|table|codes|types)$"
lookup_name_re <- paste0(
  "^(tlk|tlu|lkp|lk|lu|lookup|ref|code|cd)_|",
  "_(lookup|lkp|lu|ref|codes|types)$"
)
# FK column affixes; the rest of the name is the entity it points at
key_suffix_re <- paste0(
  "_(id|key|sk|fk|pk|code|cd|no|num|nbr|number|uuid|guid)$"
)
key_prefix_re <- "^(id|fk|key)_"
# Target-column names that identify a row on their own
generic_key_names <- c("id", "pk", "key", "code", "uuid", "guid")

strip_table_prefix <- function(tname_clean) {
  stripped <- sub(schema_prefix_re, "", tname_clean)
  stripped <- sub(table_prefix_re, "", stripped)
  if (nzchar(stripped)) stripped else tname_clean
}

irregular_plurals <- c(
  people = "person",
  children = "child",
  men = "man",
  women = "woman",
  geese = "goose",
  mice = "mouse",
  indices = "index",
  matrices = "matrix",
  criteria = "criterion"
)

# Singularise the last word of a snake_case name
singularize <- function(name) {
  parts <- strsplit(name, "_", fixed = TRUE)[[1]]
  if (length(parts) == 0) {
    return(name)
  }
  w <- parts[[length(parts)]]
  w <- if (w %in% names(irregular_plurals)) {
    irregular_plurals[[w]]
  } else if (grepl("ies$", w) && nchar(w) > 4) {
    sub("ies$", "y", w)
  } else if (grepl("(ss|us|is)$", w)) {
    w
  } else if (grepl("(s|x|z|ch|sh)es$", w)) {
    sub("es$", "", w)
  } else if (grepl("s$", w) && nchar(w) > 3) {
    sub("s$", "", w)
  } else {
    w
  }
  parts[[length(parts)]] <- w
  paste(parts, collapse = "_")
}

# The entity a table is named for: tlk_providers -> provider,
# dbo_customer_lookup -> customer, tlk_city_id -> city
table_entity <- function(tname_clean) {
  x <- strip_table_prefix(tname_clean)
  y <- sub(table_suffix_re, "", x)
  if (nzchar(y)) x <- y
  y <- sub("_(id|key|code|cd)$", "", x)
  if (nzchar(y)) x <- y
  singularize(x)
}

# Entity stems named by a key column, longest first. Returns NULL when the
# column is not key-named. role = TRUE when leading words were dropped
# (referring_provider_id -> provider).
key_entities <- function(col_clean) {
  stem <- sub(key_suffix_re, "", col_clean)
  if (identical(stem, col_clean)) {
    stem <- sub(key_prefix_re, "", col_clean)
  }
  if (identical(stem, col_clean) || !nzchar(stem)) {
    return(NULL)
  }
  tokens <- strsplit(stem, "_", fixed = TRUE)[[1]]
  tokens <- tokens[nzchar(tokens)]
  n <- length(tokens)
  if (n == 0) {
    return(NULL)
  }
  lapply(seq_len(n), function(i) {
    list(
      stem = singularize(paste(tokens[i:n], collapse = "_")),
      role = i > 1,
      n_tokens = n - i + 1
    )
  })
}

# How a key column's name points at a table: "exact" (provider_id ->
# providers), "role" (referring_provider_id -> tlk_providers), or NULL.
# A role match on a single word is only trusted for lookup tables, since
# generic words (status, type) would otherwise match unrelated tables.
fk_name_match <- function(col_clean, tname_clean, is_lookup = FALSE) {
  entity <- table_entity(tname_clean)
  if (col_clean == paste0(entity, "_id")) {
    return("exact")
  }
  for (k in key_entities(col_clean) %||% list()) {
    if (identical(k$stem, entity)) {
      if (!k$role) {
        return("exact")
      }
      if (k$n_tokens >= 2 || is_lookup) {
        return("role")
      }
    }
  }
  NULL
}

# Key-like column names: customer_id, e2id, order_key, id_customer. A bare
# "id"/"key" is excluded because it says nothing about which entity it
# identifies.
is_key_name <- function(col_clean) {
  grepl("(_|[0-9])(id|key|sk|fk|uuid|guid)$", col_clean) |
    grepl("^(id|fk)_.", col_clean)
}

# Stricter than is_pk_name: the table is named for the key's entity
# (customers owns customer_id, order_items does not own order_id).
owns_key <- function(col_clean, tname_clean) {
  tname_clean == col_clean ||
    identical(fk_name_match(col_clean, tname_clean), "exact")
}

is_pk_name <- function(col_clean, tname_clean) {
  col_clean == "id" ||
    col_clean == paste0(tname_clean, "_id") ||
    (grepl("_id$", col_clean) && startsWith(tname_clean, id_stem(col_clean))) ||
    owns_key(col_clean, tname_clean)
}

is_fk_for <- function(col_clean, t2clean) {
  identical(fk_name_match(col_clean, t2clean), "exact")
}

is_lookup_name <- function(tname) {
  grepl(lookup_name_re, sub(schema_prefix_re, "", clean_name(tname)))
}

# Lookup tables: named like one (tlk_, lkp_, _lookup, ...) or shaped like
# one (few rows, few columns, a unique id/code column). Memoised per shape.
.lookup_cache <- new.env(parent = emptyenv())

is_lookup_table <- function(tname, df) {
  key <- paste("k", tname, nrow(df), ncol(df), sep = "\r")
  hit <- .lookup_cache[[key]]
  if (!is.null(hit)) {
    return(hit)
  }
  tc <- clean_name(tname)
  res <- grepl(lookup_name_re, sub(schema_prefix_re, "", tc)) ||
    (nrow(df) > 0 &&
      nrow(df) <= 500 &&
      ncol(df) <= 4 &&
      any(vapply(
        names(df),
        function(cn) {
          cc <- clean_name(cn)
          (cc %in% generic_key_names || is_key_name(cc)) &&
            !anyNA(df[[cn]]) &&
            length(unique(df[[cn]])) == nrow(df)
        },
        logical(1)
      )))
  assign(key, res, envir = .lookup_cache)
  res
}

# Preference among target columns when several score the same:
# id/code-style keys, then the same name as the source, then key-named
target_col_pref <- function(col2_clean, col1_clean) {
  if (col2_clean %in% generic_key_names) {
    3L
  } else if (col2_clean == col1_clean) {
    2L
  } else if (is_key_name(col2_clean)) {
    1L
  } else {
    0L
  }
}

# ── Type classification ──────────────────────────────────────

col_dtype_class <- function(x) {
  if (is.numeric(x)) {
    return("numeric")
  }
  if (inherits(x, c("Date", "POSIXt", "POSIXct", "POSIXlt"))) {
    return("datetime")
  }
  "string"
}

# ── Jaro-Winkler similarity ──────────────────────────────────

jaro_winkler_sim <- function(s1, s2) {
  if (!requireNamespace("stringdist", quietly = TRUE)) {
    return(0.0)
  }
  1 - stringdist::stringdist(s1, s2, method = "jw", p = 0.1)
}

# ── Format fingerprint ───────────────────────────────────────

format_fingerprint <- function(col, sample_size = 200) {
  vals <- na.omit(col)
  if (length(vals) == 0) {
    return(NULL)
  }
  vals <- as.character(vals)
  if (length(vals) > sample_size) {
    set.seed(42)
    vals <- sample(vals, sample_size)
  }
  for (fp in format_patterns) {
    hits <- sum(grepl(fp$pattern, vals, ignore.case = TRUE, perl = TRUE))
    if (hits / length(vals) >= 0.80) {
      return(fp$name)
    }
  }
  NULL
}

# ── Column profiles ──────────────────────────────────────────
# Everything the content signals need from one column, computed once per
# column rather than once per candidate pair.

column_profile <- function(v, sample_cap = 5000) {
  vals <- as.character(v[!is.na(v)])
  uniq <- unique(vals)
  uniq_sample <- uniq
  if (length(uniq_sample) > sample_cap) {
    set.seed(42)
    uniq_sample <- uniq_sample[sample(length(uniq_sample), sample_cap)]
  }
  count_vals <- vals
  if (length(count_vals) > sample_cap) {
    set.seed(42)
    count_vals <- count_vals[sample(length(count_vals), sample_cap)]
  }
  counts <- table(count_vals)
  list(
    dtype = col_dtype_class(v),
    uniq = uniq,
    uniq_sample = uniq_sample,
    counts = setNames(as.numeric(counts), names(counts)),
    fingerprint = format_fingerprint(v)
  )
}

# ── Value overlap ────────────────────────────────────────────

overlap_from_profiles <- function(p1, p2) {
  if (length(p1$uniq_sample) == 0) {
    return(0.0)
  }
  mean(p1$uniq_sample %in% p2$uniq)
}

value_overlap <- function(v1, v2, sample_cap = 5000) {
  overlap_from_profiles(
    column_profile(v1, sample_cap),
    column_profile(v2, sample_cap)
  )
}

# ── Distribution similarity (cosine) ────────────────────────

distribution_from_profiles <- function(p1, p2) {
  c1 <- p1$counts
  c2 <- p2$counts
  if (length(c1) == 0 || length(c2) == 0) {
    return(0.0)
  }

  # Use only shared vocabulary for cosine - much cheaper than full union.
  # match(), not c1[shared]: indexing by the name "" (blank strings) gives NA
  shared <- intersect(names(c1), names(c2))
  if (length(shared) == 0) {
    return(0.0)
  }
  a <- c1[match(shared, names(c1))]
  b <- c2[match(shared, names(c2))]

  norm_a <- sqrt(sum(c1^2))
  norm_b <- sqrt(sum(c2^2))
  if (norm_a == 0 || norm_b == 0) {
    return(0.0)
  }
  sum(a * b) / (norm_a * norm_b)
}

distribution_similarity <- function(v1, v2, sample_cap = 5000) {
  distribution_from_profiles(
    column_profile(v1, sample_cap),
    column_profile(v2, sample_cap)
  )
}

# ── Null pattern correlation ─────────────────────────────────

null_pattern_correlation <- function(df1, col1, df2, col2) {
  # sd() is NA below 2 rows
  if (nrow(df1) != nrow(df2) || nrow(df1) < 2) {
    return(0.0)
  }
  mask1 <- as.numeric(is.na(df1[[col1]]))
  mask2 <- as.numeric(is.na(df2[[col2]]))
  if (sd(mask1) == 0 || sd(mask2) == 0) {
    return(0.0)
  }
  tryCatch(
    cor(mask1, mask2),
    error = function(e) 0.0
  )
}

# ── Primary key detection ────────────────────────────────────

detect_pks <- function(df, table_name, method = "both") {
  cols <- names(df)
  candidates <- character(0)
  n <- nrow(df)

  if (method %in% c("naming", "both", "content", "all")) {
    tname <- strip_table_prefix(clean_name(table_name))
    cols_clean <- clean_name(cols)
    hits <- cols[vapply(
      cols_clean,
      is_pk_name,
      logical(1),
      tname_clean = tname
    )]
    candidates <- union(candidates, hits)
  }

  if (method %in% c("uniqueness", "both", "content", "all") && n > 0) {
    hits <- cols[vapply(
      cols,
      function(c) {
        v <- df[[c]]
        !anyNA(v) && length(unique(v)) == n
      },
      logical(1)
    )]
    candidates <- union(candidates, hits)
  }

  candidates
}

# ── Naming signal (memoised) ─────────────────────────────────
# Depends only on the three names, which repeat across tables (client_id,
# e2id, ...), so large scans hit the cache for most pairs.

.naming_signal_cache <- new.env(parent = emptyenv())

naming_signal <- function(col1, t2, col2, t2_is_lookup = FALSE) {
  key <- paste("k", col1, t2, col2, t2_is_lookup, sep = "\r")
  if (exists(key, envir = .naming_signal_cache, inherits = FALSE)) {
    return(get(key, envir = .naming_signal_cache))
  }
  c1 <- clean_name(col1)
  # The table match doesn't depend on col2, so cache it per (col1, t2)
  mkey <- paste("m", col1, t2, t2_is_lookup, sep = "\r")
  match <- .naming_signal_cache[[mkey]]
  if (is.null(match)) {
    match <- fk_name_match(c1, clean_name(t2), t2_is_lookup) %||% "none"
    assign(mkey, match, envir = .naming_signal_cache)
  }
  res <- if (identical(match, "exact")) {
    list(signal = "naming_exact", value = 1.0, reason = "exact FK naming")
  } else if (identical(match, "role")) {
    list(
      signal = "naming_role",
      value = 0.9,
      reason = sprintf("FK naming with prefix (%s)", c1)
    )
  } else {
    stem1 <- sub("_(id|key|code|num|no)$", "", c1)
    stem2 <- sub("_(id|key|code|num|no)$", "", clean_name(col2))
    sim <- jaro_winkler_sim(stem1, stem2)
    if (sim >= name_sim_high) {
      list(
        signal = "name_sim",
        value = sim,
        reason = sprintf("name similarity %.2f", sim)
      )
    } else if (sim >= name_sim_med) {
      list(
        signal = "name_sim_weak",
        value = sim,
        reason = sprintf("weak name similarity %.2f", sim)
      )
    }
  }
  assign(key, res, envir = .naming_signal_cache)
  res
}

# ── Score a single candidate pair ────────────────────────────

# p1/p2: optional column_profile() results for col1/col2. detect_fks passes
# cached profiles; standalone callers can omit them.
score_candidate <- function(
  t1,
  col1,
  df1,
  t2,
  col2,
  df2,
  enable_flags,
  p1 = NULL,
  p2 = NULL,
  t2_is_lookup = NULL
) {
  signals <- list()
  reasons <- character(0)

  # 1. Naming conventions
  if (isTRUE(enable_flags[["naming"]])) {
    ns <- naming_signal(
      col1,
      t2,
      col2,
      t2_is_lookup %||% is_lookup_table(t2, df2)
    )
    if (!is.null(ns)) {
      signals[[ns$signal]] <- ns$value
      reasons <- c(reasons, ns$reason)
    }
  }

  n1 <- nrow(df1)
  n2 <- nrow(df2)

  # 2. Type compatibility guard (skipped for empty tables, whose column types
  # are whatever the reader defaulted to)
  if (n1 > 0 && n2 > 0) {
    dtype1 <- col_dtype_class(df1[[col1]])
    dtype2 <- col_dtype_class(df2[[col2]])
    if (dtype1 != dtype2) {
      return(NULL)
    }
  }

  content_flags <- c(
    "value_overlap",
    "cardinality",
    "format",
    "distribution"
  )
  if (
    n1 > 0 &&
      n2 > 0 &&
      any(vapply(enable_flags[content_flags], isTRUE, logical(1)))
  ) {
    if (is.null(p1)) {
      p1 <- column_profile(df1[[col1]])
    }
    if (is.null(p2)) {
      p2 <- column_profile(df2[[col2]])
    }
  }

  # 3. Value overlap
  if (isTRUE(enable_flags[["value_overlap"]]) && n1 > 0 && n2 > 0) {
    ov <- overlap_from_profiles(p1, p2)
    if (ov >= overlap_high) {
      signals[["overlap_high"]] <- ov
      reasons <- c(reasons, sprintf("value overlap %.0f%%", ov * 100))
    } else if (ov >= overlap_medium) {
      signals[["overlap_medium"]] <- ov
      reasons <- c(reasons, sprintf("partial overlap %.0f%%", ov * 100))
    }
  }

  # 4. Exact cardinality match
  if (isTRUE(enable_flags[["cardinality"]]) && n1 > 0 && n2 > 0) {
    u1 <- p1$uniq
    u2 <- p2$uniq
    if (
      length(u1) > 0 &&
        length(u1) == length(u2) &&
        all(u1 %in% u2)
    ) {
      signals[["cardinality_match"]] <- 1.0
      reasons <- c(reasons, "identical value sets")
    }
  }

  # 5. Format fingerprint
  if (isTRUE(enable_flags[["format"]]) && n1 > 0 && n2 > 0) {
    fmt1 <- p1$fingerprint
    fmt2 <- p2$fingerprint
    if (!is.null(fmt1) && !is.null(fmt2) && fmt1 == fmt2) {
      signals[["format_match"]] <- 0.6
      reasons <- c(reasons, sprintf("shared format [%s]", fmt1))
    }
  }

  # 6. Distribution similarity
  if (isTRUE(enable_flags[["distribution"]]) && n1 > 0 && n2 > 0) {
    dist_sim <- distribution_from_profiles(p1, p2)
    if (dist_sim >= dist_sim_high) {
      signals[["dist_high"]] <- dist_sim
      reasons <- c(reasons, sprintf("distribution similarity %.2f", dist_sim))
    } else if (dist_sim >= dist_sim_med) {
      signals[["dist_med"]] <- dist_sim
      reasons <- c(
        reasons,
        sprintf("weak distribution similarity %.2f", dist_sim)
      )
    }
  }

  # 7. Null pattern correlation
  if (isTRUE(enable_flags[["null_pattern"]]) && n1 == n2) {
    null_r <- null_pattern_correlation(df1, col1, df2, col2)
    if (null_r >= 0.80) {
      signals[["null_corr"]] <- null_r
      reasons <- c(reasons, sprintf("null pattern corr %.2f", null_r))
    }
  }

  if (length(signals) == 0) {
    return(NULL)
  }

  # Composite confidence score (noisy-OR)
  weights <- vapply(
    names(signals),
    function(k) if (k %in% names(weight_map)) weight_map[[k]] else 0.1,
    numeric(1)
  )
  score <- 1 - prod(1 - weights)
  score <- round(min(score, 1.0), 3)

  # Primary detected_by label (highest-weight signal)
  top_signal <- names(signals)[which.max(weights)]
  detected_by <- if (top_signal %in% names(label_map)) {
    label_map[[top_signal]]
  } else {
    "content"
  }

  # Confidence tier
  confidence <- if (score >= 0.85) {
    "high"
  } else if (score >= 0.55) {
    "medium"
  } else {
    "low"
  }

  list(
    signals = signals,
    reasons = reasons,
    score = score,
    confidence = confidence,
    detected_by = detected_by
  )
}

# ── Complexity estimator ───────────────────────────────────────

estimate_scan_complexity <- function(tables) {
  n_tables <- length(tables)
  total_cols <- sum(vapply(tables, ncol, integer(1)))
  total_rows <- sum(vapply(tables, nrow, integer(1)))
  max_rows <- if (n_tables > 0) max(vapply(tables, nrow, integer(1))) else 0

  # Estimate pairs: each non-PK col in t1 x each PK-like col in t2
  # Rough: ~40% of cols are non-PK, ~15% are PK-like targets
  est_source_cols <- total_cols * 0.40
  est_target_cols_per_table <- max(total_cols / max(n_tables, 1) * 0.15, 1)
  est_pairs <- est_source_cols * (n_tables - 1) * est_target_cols_per_table

  # Cost per pair: ~1ms for naming-only, ~5ms for content signals on small data,
  # ~20ms if rows are large
  cost_per_pair_ms <- if (max_rows > 5000) {
    20
  } else if (max_rows > 500) {
    5
  } else {
    1
  }
  est_time_sec <- (est_pairs * cost_per_pair_ms) / 1000

  tier <- if (est_pairs < 2000 || est_time_sec < 5) {
    "fast"
  } else if (est_pairs < 15000 || est_time_sec < 30) {
    "moderate"
  } else {
    "slow"
  }

  list(
    n_tables = n_tables,
    total_cols = total_cols,
    total_rows = total_rows,
    max_rows = max_rows,
    est_pairs = round(est_pairs),
    est_time_sec = round(est_time_sec, 1),
    tier = tier
  )
}

# ── Column pre-screening heuristic ─────────────────────────────
# Skip columns that are very unlikely to be FK/PK candidates
# to avoid the expensive score_candidate call entirely.

is_fk_candidate <- function(col, col_name) {
  # Fast heuristic checks - reject columns that almost never form relationships
  n <- length(col)
  if (n == 0) {
    return(FALSE)
  }

  # Boolean / low-cardinality columns are not FKs, unless named like a key
  # (provider_id holding one or two providers is still a foreign key)
  n_unique <- length(unique(na.omit(col)))
  if (n_unique <= 2 && n > 10 && !is_key_name(clean_name(col_name))) {
    return(FALSE)
  }

  # All-NA columns
  if (n_unique == 0) {
    return(FALSE)
  }

  # Very high cardinality text (long free-text, descriptions, notes)
  if (is.character(col)) {
    sample_vals <- head(na.omit(col), 50)
    if (length(sample_vals) > 0) {
      median_len <- median(nchar(sample_vals))
      if (median_len > 80) return(FALSE)
    }
  }

  TRUE
}

# ── Composite primary key detection ──────────────────────────
# Returns a list of character vectors, each representing one composite key
# group whose combined values are unique across all rows.
# Only runs when no column is both PK-named and unique. A PK-named column that
# repeats (order_id in order_items) is a composite key component, not a PK.

detect_composite_pks <- function(
  df,
  table_name,
  max_combo_size = 3L,
  max_candidates = 20L
) {
  n <- nrow(df)
  if (n < 2L) {
    return(list())
  }

  unique_cols <- detect_pks(df, table_name, method = "uniqueness")

  # Skip if a genuine single-column PK already exists
  named_cols <- detect_pks(df, table_name, method = "naming")
  if (length(intersect(named_cols, unique_cols)) > 0L) {
    return(list())
  }

  # Columns unique on their own would make any combo containing them
  # trivially unique, so they are not composite key components
  cols <- setdiff(names(df), unique_cols)

  # Collect candidate columns: skip logicals, all-NA, and long free-text
  candidates <- cols[vapply(
    cols,
    function(col) {
      v <- df[[col]]
      if (is.logical(v)) {
        return(FALSE)
      }
      v_clean <- na.omit(v)
      if (length(v_clean) == 0L) {
        return(FALSE)
      }
      if (
        is.character(v) &&
          median(nchar(head(as.character(v_clean), 50L))) > 80
      ) {
        return(FALSE)
      }
      TRUE
    },
    logical(1L)
  )]

  if (length(candidates) < 2L) {
    return(list())
  }

  # Sort: id-like columns first for faster discovery
  id_like <- grepl(
    "(_id|_key|id$|key$|_code|_num|_no)$",
    vapply(candidates, clean_name, character(1L))
  )
  candidates <- c(candidates[id_like], candidates[!id_like])
  candidates <- head(candidates, max_candidates)
  n_cand <- length(candidates)

  # Try 2-column combinations
  for (i in seq_len(n_cand - 1L)) {
    for (j in seq.int(i + 1L, n_cand)) {
      c1 <- candidates[[i]]
      c2 <- candidates[[j]]
      if (anyNA(df[[c1]]) || anyNA(df[[c2]])) {
        next
      }
      if (length(unique(paste(df[[c1]], df[[c2]], sep = "\x01"))) == n) {
        return(list(c(c1, c2)))
      }
    }
  }

  # Try 3-column combinations
  if (max_combo_size >= 3L && n_cand >= 3L) {
    for (i in seq_len(n_cand - 2L)) {
      for (j in seq.int(i + 1L, n_cand - 1L)) {
        for (k in seq.int(j + 1L, n_cand)) {
          c1 <- candidates[[i]]
          c2 <- candidates[[j]]
          c3 <- candidates[[k]]
          if (anyNA(df[[c1]]) || anyNA(df[[c2]]) || anyNA(df[[c3]])) {
            next
          }
          if (
            length(unique(
              paste(df[[c1]], df[[c2]], df[[c3]], sep = "\x01")
            )) ==
              n
          ) {
            return(list(c(c1, c2, c3)))
          }
        }
      }
    }
  }

  list()
}

# ── Foreign key detection (multi-signal) ─────────────────────

detect_fks <- function(
  tables,
  method = "both",
  min_confidence = "medium",
  enable_flags = NULL,
  progress_fn = NULL,
  max_pairs = 50000L,
  focus_tables = NULL,
  existing = list()
) {
  if (method == "manual" || length(tables) < 2) {
    return(list())
  }

  conf_rank <- c(low = 0L, medium = 1L, high = 2L)
  min_rank <- conf_rank[[min_confidence]]

  # Build enable_flags from method if not provided
  if (is.null(enable_flags)) {
    use_naming <- method %in% c("naming", "both", "all")
    use_content <- method %in% c("content", "both", "all", "uniqueness")
    enable_flags <- list(
      naming = use_naming,
      value_overlap = use_content,
      cardinality = use_content,
      format = use_content,
      distribution = use_content,
      null_pattern = use_content
    )
  }

  tnames <- names(tables)

  # Pre-compute PK columns per table (optimized: stop early, skip wide text)
  pk_map <- lapply(tnames, function(t) {
    df <- tables[[t]]
    n <- nrow(df)
    if (n == 0) {
      return(character(0))
    }
    pks <- character(0)
    for (c in names(df)) {
      v <- df[[c]]
      # Quick reject: skip long-text, logical, Date columns as PK candidates
      if (is.logical(v) || inherits(v, c("Date", "POSIXt"))) {
        next
      }
      # isTRUE: an all-NA text column has no median and would error
      if (
        is.character(v) &&
          isTRUE(median(nchar(head(na.omit(v), 20))) > 60)
      ) {
        next
      }
      if (!anyNA(v) && length(unique(v)) == n) {
        pks <- c(pks, c)
      }
    }
    pks
  })
  names(pk_map) <- tnames

  # Pre-compute FK-candidate columns per table (skip non-FK-like columns).
  # Empty tables have no values to screen, so their key-named columns are
  # candidates for name matching.
  fk_candidates <- lapply(tnames, function(t) {
    df <- tables[[t]]
    if (nrow(df) == 0) {
      return(names(df)[is_key_name(clean_name(names(df)))])
    }
    cols <- setdiff(names(df), pk_map[[t]])
    cols[vapply(cols, function(c) is_fk_candidate(df[[c]], c), logical(1))]
  })
  names(fk_candidates) <- tnames

  # Unique key-named columns (client_id unique in several one-row-per-client
  # tables) can still reference the same key in another table (1:1 links).
  # A table named for the key (customers.customer_id) is the parent, not a
  # source.
  unique_key_sources <- lapply(tnames, function(t) {
    pks <- pk_map[[t]]
    pks_clean <- clean_name(pks)
    tclean <- strip_table_prefix(clean_name(t))
    pks[
      is_key_name(pks_clean) &
        !vapply(pks_clean, owns_key, logical(1), tname_clean = tclean)
    ]
  })
  names(unique_key_sources) <- tnames

  # Deterministic table ranking (most rows first, then name) used to pick a
  # single parent for 1:1 and empty-table links, so N tables sharing a key
  # form a star rather than an N x N mesh.
  rank_order <- order(-vapply(tables, nrow, integer(1)), tnames)
  table_rank <- setNames(integer(length(tnames)), tnames)
  table_rank[rank_order] <- seq_along(tnames)

  # Column profiles, computed lazily once per column (only content signals
  # use them, so a naming-only scan never builds any)
  use_profiles <- any(vapply(
    enable_flags[c("value_overlap", "cardinality", "format", "distribution")],
    isTRUE,
    logical(1)
  ))
  profile_cache <- new.env(parent = emptyenv())

  get_profile <- function(tname, cname) {
    if (!use_profiles || nrow(tables[[tname]]) == 0) {
      return(NULL)
    }
    key <- paste(tname, cname, sep = "|")
    hit <- profile_cache[[key]]
    if (is.null(hit)) {
      hit <- column_profile(tables[[tname]][[cname]])
      assign(key, hit, envir = profile_cache)
    }
    hit
  }

  results <- list()
  seen <- new.env(parent = emptyenv()) # O(1) lookup vs character vector
  best_scores <- new.env(parent = emptyenv())

  # Incremental scan: with focus_tables set, only pairs involving at least one
  # focus table are compared, and `existing` (earlier results for the other
  # tables) seeds the dedup state so known links are not re-added or reversed
  existing_sources <- new.env(parent = emptyenv())
  for (r in existing) {
    assign(paste(r$from_table, r$from_col, r$to_table, sep = "|"), TRUE, envir = seen)
    assign(
      paste(r$from_table, r$from_col, r$to_table, r$to_col, sep = "|"),
      TRUE,
      envir = seen
    )
    col_key <- paste(r$from_table, r$from_col, sep = "|")
    prev <- best_scores[[col_key]]
    score <- r$score %||% 0
    if (is.null(prev) || score > prev) {
      assign(col_key, score, envir = best_scores)
    }
    assign(col_key, TRUE, envir = existing_sources)
  }
  in_focus <- function(t) is.null(focus_tables) || t %in% focus_tables

  # max_pairs caps total pair evaluations to prevent runaway on huge schemas
  pair_count <- 0L

  lookup_flags <- vapply(
    tnames,
    function(t) is_lookup_table(t, tables[[t]]),
    logical(1)
  )

  make_rel <- function(t1, col1, t2, col2, res) {
    list(
      from_table = t1,
      from_col = col1,
      to_table = t2,
      to_col = col2,
      detected_by = res$detected_by,
      confidence = res$confidence,
      score = res$score,
      reasons = res$reasons,
      signals = res$signals
    )
  }

  for (t1_idx in seq_along(tnames)) {
    t1 <- tnames[[t1_idx]]
    if (!is.null(progress_fn)) {
      progress_fn(t1_idx, length(tnames), t1)
    }
    df1 <- tables[[t1]]
    t1_empty <- nrow(df1) == 0
    if (t1_empty && !isTRUE(enable_flags[["naming"]])) {
      next
    }

    source_cols <- union(fk_candidates[[t1]], unique_key_sources[[t1]])

    for (col1 in source_cols) {
      # Self-reference (employees.manager_id -> employees.id)
      if (isTRUE(enable_flags[["naming"]]) && in_focus(t1)) {
        self <- self_ref_match(t1, col1, df1, pk_map[[t1]])
        if (!is.null(self)) {
          self_key <- paste(t1, col1, t1, sep = "|")
          if (
            !exists(self_key, envir = seen) &&
              conf_rank[[self$res$confidence]] >= min_rank
          ) {
            assign(self_key, TRUE, envir = seen)
            results[[length(results) + 1]] <- make_rel(
              t1,
              col1,
              t1,
              self$to_col,
              self$res
            )
          }
        }
      }

      # Unique-key and empty-table sources link to one best parent only
      src_unique <- col1 %in% unique_key_sources[[t1]]
      single_parent <- src_unique || t1_empty
      parent <- NULL
      # A one-parent source that already has its parent keeps it
      if (
        single_parent &&
          !in_focus(t1) &&
          exists(paste(t1, col1, sep = "|"), envir = existing_sources)
      ) {
        next
      }

      for (t2 in tnames) {
        if (t2 == t1) {
          next
        }
        if (!in_focus(t1) && !in_focus(t2)) {
          next
        }
        # An empty table is only a plausible parent for another empty table,
        # or when it is named as a lookup table (tlk_services with no rows)
        if (
          nrow(tables[[t2]]) == 0 &&
            !t1_empty &&
            !lookup_flags[[t2]]
        ) {
          next
        }
        # 1:1 links point up the ranking (or to the table that owns the key),
        # so each pair appears once
        if (
          src_unique &&
            table_rank[[t2]] > table_rank[[t1]] &&
            !owns_key(clean_name(col1), strip_table_prefix(clean_name(t2)))
        ) {
          next
        }

        rel_key <- paste(t1, col1, t2, sep = "|")
        if (exists(rel_key, envir = seen)) {
          next
        }

        df2 <- tables[[t2]]
        target_cols <- if (length(pk_map[[t2]]) > 0) {
          pk_map[[t2]]
        } else if (nrow(df2) == 0) {
          # Empty tables: their key-named and id/code columns
          names(df2)[vapply(
            clean_name(names(df2)),
            function(cc) is_key_name(cc) || cc %in% generic_key_names,
            logical(1)
          )]
        } else {
          fk_candidates[[t2]]
        }
        if (src_unique) {
          # A unique key only links to the same key, unique in the parent
          target_cols <- pk_map[[t2]][
            clean_name(pk_map[[t2]]) == clean_name(col1)
          ]
        }
        if (length(target_cols) == 0) {
          next
        }

        best_result <- NULL
        best_to_col <- NULL

        for (col2 in target_cols) {
          pair_count <- pair_count + 1L
          if (pair_count > max_pairs) {
            break
          }

          # One unscorable pair (odd column type or values) must not abort
          # the whole scan, which would hide every relationship
          result <- tryCatch(
            score_candidate(
              t1,
              col1,
              df1,
              t2,
              col2,
              df2,
              enable_flags,
              get_profile(t1, col1),
              get_profile(t2, col2),
              lookup_flags[[t2]]
            ),
            error = function(e) NULL
          )
          if (is.null(result)) {
            next
          }
          if (
            is.null(best_result) ||
              result$score > best_result$score ||
              (result$score == best_result$score &&
                target_col_pref(col2, col1) > target_col_pref(best_to_col, col1))
          ) {
            best_result <- result
            best_to_col <- col2
          }
        }

        if (pair_count > max_pairs) {
          break
        }
        if (is.null(best_result)) {
          next
        }
        if (conf_rank[[best_result$confidence]] < min_rank) {
          next
        }

        if (single_parent) {
          if (
            is.null(parent) ||
              best_result$score > parent$res$score ||
              (best_result$score == parent$res$score &&
                table_rank[[t2]] < table_rank[[parent$t2]])
          ) {
            parent <- list(t2 = t2, col2 = best_to_col, res = best_result)
          }
          next
        }

        # Deduplicate: keep best target per source column
        col_key <- paste(t1, col1, sep = "|")
        prev_score <- if (exists(col_key, envir = best_scores)) {
          get(col_key, envir = best_scores)
        } else {
          NULL
        }
        if (!is.null(prev_score) && prev_score > best_result$score + 0.05) {
          next
        }
        assign(col_key, best_result$score, envir = best_scores)

        assign(rel_key, TRUE, envir = seen)
        results[[length(results) + 1]] <- make_rel(
          t1, col1, t2, best_to_col, best_result
        )
      }

      if (!is.null(parent)) {
        # Skip if the parent already links back here on the same columns
        reverse_key <- paste(parent$t2, parent$col2, t1, col1, sep = "|")
        if (!exists(reverse_key, envir = seen)) {
          assign(
            paste(t1, col1, parent$t2, parent$col2, sep = "|"),
            TRUE,
            envir = seen
          )
          results[[length(results) + 1]] <- make_rel(
            t1, col1, parent$t2, parent$col2, parent$res
          )
        }
      }
      if (pair_count > max_pairs) break
    }
    if (pair_count > max_pairs) break
  }

  results <- sort_rels(results)

  # Let callers warn that tables late in the scan order were not compared
  attr(results, "truncated") <- pair_count > max_pairs
  results
}

# ── Incremental scan bookkeeping ─────────────────────────────
# A table is rescanned only if it is new or its contents changed since the
# last scan (a re-upload under the same name). The hash covers values too, so
# a replacement with the same shape and column names still counts as changed.

table_signature <- function(df) {
  rlang::hash(df)
}

tables_needing_scan <- function(tables, scanned_sig) {
  if (length(tables) == 0) {
    return(character(0))
  }
  sig <- vapply(tables, table_signature, character(1))
  prev <- unname(scanned_sig[names(tables)])
  names(tables)[is.na(prev) | prev != sig]
}

# ── Self-referencing FKs ─────────────────────────────────────
# A key-named column pointing back at its own table's key. It needs a
# hierarchy word (manager_id, parent_id, reports_to_id), and whatever is left
# of the name must be empty or name the table itself (parent_category_id in
# categories). prior_status_id is not a self-reference: "status" names
# another entity. When the table has values, most must appear in the key.

self_ref_words <- c(
  "parent", "manager", "supervisor", "reports_to", "superior",
  "predecessor", "successor", "previous", "prior", "next", "root",
  "master", "boss"
)

self_ref_match <- function(t1, col1, df1, pk_cols) {
  c1 <- clean_name(col1)
  if (!is_key_name(c1)) {
    return(NULL)
  }
  tc <- clean_name(t1)
  # Target: the table's own key column (id / <entity>_id / unique key)
  cand <- setdiff(
    unique(c(
      pk_cols %||% character(0),
      names(df1)[clean_name(names(df1)) %in% generic_key_names],
      names(df1)[vapply(names(df1), function(cn) owns_key(clean_name(cn), tc), logical(1))]
    )),
    col1
  )
  if (length(cand) == 0) {
    return(NULL)
  }
  prefs <- vapply(cand, target_col_pref, integer(1), col1_clean = c1)
  to_col <- cand[order(-prefs)][[1]]

  stem <- sub(key_suffix_re, "", c1)
  rest <- stem
  for (w in self_ref_words) {
    rest <- gsub(paste0("(^|_)", w, "(_|$)"), "_", rest)
  }
  rest <- gsub("^_+|_+$", "", gsub("_+", "_", rest))
  hierarchy <- !identical(rest, stem)
  if (!hierarchy || (nzchar(rest) && singularize(rest) != table_entity(tc))) {
    return(NULL)
  }

  if (nrow(df1) > 0) {
    v <- df1[[col1]]
    v <- as.character(v[!is.na(v)])
    if (length(v) == 0) {
      return(NULL)
    }
    target <- as.character(df1[[to_col]])
    if (mean(v %in% target) < 0.8) {
      return(NULL)
    }
  }

  list(
    to_col = to_col,
    res = list(
      signals = list(naming_self = 0.9),
      reasons = sprintf("self-reference naming (%s)", c1),
      score = 0.9,
      confidence = "high",
      detected_by = "naming"
    )
  )
}

# Sort relationships by confidence desc, then score desc
sort_rels <- function(rels) {
  if (length(rels) == 0) {
    return(rels)
  }
  conf_rank <- c(low = 0L, medium = 1L, high = 2L)
  order_idx <- order(
    -vapply(rels, function(r) conf_rank[[r$confidence %||% "low"]], integer(1)),
    -vapply(rels, function(r) r$score %||% 0, numeric(1))
  )
  rels[order_idx]
}
