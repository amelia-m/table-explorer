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
# A foreign key's parent has to identify a row. pk_map holds the columns
# that are strictly unique and fully populated; in a real extract a key
# column arrives with a few duplicate or missing rows, so a column at or
# above this share of distinct, non-missing values counts as the dirty
# version of the same thing. Below 100 rows the share can only be met by
# exact uniqueness, which pk_map already covers, so the tolerance is for
# the larger tables, which is where duplicates actually turn up.
parent_key_min_frac <- 0.99
# Identical value sets are evidence only when the sets are large enough
# that holding the same one is a coincidence. Hand-maintained code domains
# run to about a dozen entries (the 52-table extract's lookups hold eight;
# months, weekdays and Likert scales all sit below twelve), and over any
# realistic row count two columns drawn from such a domain both end up
# holding the whole domain, so the match is the expected outcome rather
# than a finding. Past a dozen distinct values it stops being free.
# A caller that wants a different floor passes cardinality_min_distinct to
# detect_fks() or score_candidate(); 1 admits every identical pair of value
# sets, which is the floor switched off.
cardinality_min_distinct_default <- 12L

# Overlap inside a dense integer run is only a coincidence when the child
# has few distinct values to place. A column holding 500 distinct values,
# every one of them present in the parent key, is a reference whatever the
# parent's density: a count or a code column cannot reach that many
# distinct values by accident. Above this the discount is not applied.
overlap_chance_max_distinct_default <- 25L
# Whether the discount is applied at all. It is the rule that kept
# incident.number_of_suspects out of victim.height_inches, and it is also
# the rule that can take a real reference down with it when a small child
# domain sits inside a dense parent key, so it is a setting rather than a
# fact. FALSE makes overlap_expected_by_chance() return 0 for every pair,
# which leaves the raw overlap as the evidence, and makes
# overlap_chance_max_distinct inert: the threshold only decides which pairs
# a discount that is being applied reaches.
overlap_chance_discount_default <- TRUE

# Whether the weaker key-name tier runs at all. is_possible_key_name()
# admits a name that merely starts or ends with "id" and is not a common
# word (primaryid, caseid, supportrepid), which buys a column a hearing it
# would not otherwise get: it survives the low-cardinality reject in
# is_fk_candidate() and may take the one-to-one path in detect_fks(). FALSE
# leaves only is_key_name()'s strict test, which wants a separator
# (customer_id, order_key).
possible_key_names_default <- TRUE

# ── Containment thresholds ───────────────────────────────────
# Containment is the structural definition of a foreign key: every value
# the child holds appears in a parent column that identifies a row. It is
# the one signal here that needs neither a naming convention nor a
# distribution to agree, which is the whole point of it.

# Strict containment: every distinct child value tested was found. Set as a
# constant rather than written as "== 1" so the comparison reads the same
# as the tier below it, and so the two tiers sit side by side.
containment_full <- 1.0
# A real extract arrives with orphan rows: a filtered parent, a soft-deleted
# row, a child loaded after its parent snapshot. One value in a hundred
# missing is that, not a different domain, so it keeps a weaker signal
# rather than none. Below this the overlap signals in step 3 already cover
# the pair, and calling 95% "contained" would be a claim the data does not
# support.
containment_near <- 0.99
# Containment is free when the child has one or two distinct values: a flag
# or a two-code column sits inside almost any key. Three distinct values is
# the smallest set where being wholly inside a particular key says anything,
# and it is the same floor detect_shared_columns() uses for the same reason.
# A caller that wants a stricter scan raises it per scan: detect_fks() and
# score_candidate() both take containment_min_distinct.
containment_min_distinct_default <- 3L

# ── How strict the parent-key requirement is ─────────────────
# Containment needs a parent that identifies a row, and "identifies a row"
# has more than one defensible reading. The three settings exist so the
# precision cost of each reading can be measured rather than assumed, and
# the default reproduces the behaviour this file had before they existed.
#
#   "key"       parent must be a key or a near key (parent_key_kind's two
#               original tiers). The default. No number moves.
#   "composite" a parent may also be one column of a pair that is unique
#               over the parent table, found by composite_key_component().
#               FAERS drug24q1 is the case: 1.9M rows, no unique or
#               near-unique column at all, real key (primaryid, drug_seq),
#               and two documented links into drug_seq that "key" cannot
#               reach because the table offers no parent columns.
#   "any"       no parent-key requirement at all. A measurement setting,
#               not a recommendation: it is the lower bound on precision
#               and the upper bound on recall, so the middle setting can
#               be read against both ends.
parent_key_requirements <- c("key", "composite", "any")
parent_key_requirement_default <- "key"

# ── The cheap composite-key probe ────────────────────────────
# Rows sampled before a candidate pair is confirmed over the whole table.
# A duplicate in the sample is a duplicate overall, so a pair that is not
# unique is usually refused for the cost of a sample-sized pass instead of
# a 1.9M-row one; only a pair that survives the sample is confirmed in
# full. That makes this an ordering of the work, not an approximation: the
# verdict is the same either way. 100,000 is large enough that a pair with
# any real duplication almost certainly shows one (a table with k
# duplicate pairs over n rows hides them from a sample of this size with
# probability under (1 - 100000/n)^k), and small enough that a refusal
# costs tens of milliseconds rather than seconds.
composite_probe_sample_rows <- 100000L
# Whole-table confirmations allowed per column before the probe gives up.
# Each confirmation is the expensive pass, and a column that has failed
# eight sample-surviving pairs is not one unique pair away from being a
# key. Eight rather than one because the sample can pass a pair that the
# whole table then rejects, and a single allowance would let one such pair
# hide the real key behind it.
composite_probe_max_pairs <- 8L
# Fixed so a scan is reproducible: the same table gives the same verdict
# on every run. The same constant the profiles sample with.
composite_probe_seed <- 42L

# ── Prose parents: unique by accident, not by design ──────────
# Containment cannot tell a column that is unique by design from one that
# is unique by accident. Chinook's `customer.address` has 59 distinct
# values over 59 rows, so it passes the key test, and
# `invoice.billingaddress` is wholly inside it because the billing address
# was copied from the customer. The pair scores 1.000 and is the only
# high-confidence false positive Chinook produces at the default setting.
# It is a real functional dependency and not a foreign key: an address is
# not an identifier.
#
# The separation has to work without declared keys, because the files this
# app is pointed at routinely ship no schema: the CRAN Lahman tables
# declare nothing, so "prefer the table's primary key" has no key to
# prefer there. So the test is on the values, not on names or
# declarations. An identifier is written to be typed and matched: no
# internal spaces, short. Prose is not.
#
# This does not subsume can_be_parent_key's 60-character guard, which
# refuses free-text blocks. An address is about 25 characters and passes
# that; what gives it away is the space.
#
# Three levels, because measurement showed "refuse" does nothing on its
# own: the Chinook pair carries cardinality_match (identical value sets,
# 0.95) and overlap_high (0.90) as well as containment, and the noisy-OR
# of those two alone is 0.995, so it still reads as high with containment
# removed. Refusing a prose column as a parent at all is the only level
# that reaches it.
#   allow          today's behaviour
#   refuse         containment does not fire on a prose parent
#   refuse_target  a prose column is not offered as a parent at all
prose_parent_guards <- c("allow", "refuse", "refuse_target")
prose_parent_guard_default <- "allow"
# Half the sampled values carrying an internal space is the test. A
# genuine code column has none: `aardsda01`, `BOS07`, `abilchrist`, `1234`
# all pass. "Theodor-Heuss-Strasse 34" and "Jane Smith" do not. Half
# rather than all, because a code column with one stray spaced value is
# still a code column, and an address column with a few single-word
# values is still addresses.
prose_parent_space_frac <- 0.5
# A second test, for long opaque strings rather than for identifiers: no
# key in the three measured schemas is over 12 characters, and a token
# long enough to need 25 is being stored, not referenced.
prose_parent_median_nchar <- 25L

# Does this column read as prose rather than as an identifier? Sampled,
# and computed once per column in column_profile() rather than per pair.
is_prose_column <- function(v, sample_size = 200L) {
  if (!is.character(v) && !is.factor(v)) {
    return(FALSE)
  }
  vals <- as.character(v)
  vals <- vals[!is.na(vals) & nzchar(vals)]
  if (length(vals) == 0L) {
    return(FALSE)
  }
  if (length(vals) > sample_size) {
    vals <- with_local_seed(composite_probe_seed, sample(vals, sample_size))
  }
  # Trimmed first, so a value padded by a careless export does not read as
  # prose for the sake of its padding.
  trimmed <- trimws(vals)
  if (mean(grepl("[[:space:]]", trimmed)) >= prose_parent_space_frac) {
    return(TRUE)
  }
  isTRUE(median(nchar(trimmed)) > prose_parent_median_nchar)
}


# ── Signal weight map for noisy-OR aggregation ───────────────

weight_map <- c(
  naming_exact = 1.00,
  naming_role = 0.90,
  naming_self = 0.90,
  cardinality_match = 0.95,
  # Containment is stronger evidence than bare overlap (0.90), because it
  # also knows the parent identifies a row, and weaker than two identical
  # value sets (0.95), which says the same thing in both directions. On its
  # own it reaches 0.92, so a link with no name evidence at all still lands
  # at high confidence, which is where a structural foreign key belongs.
  containment = 0.92,
  overlap_high = 0.90,
  # Nearly contained. Below 0.92, and deliberately below the 0.85
  # high-confidence threshold, so this tier can never assert a link on its
  # own. In practice it never has to: a child needs 100 distinct values
  # before one of them can be the missing 1%, and at that many the chance
  # discount no longer applies, so containment_near at 0.99 always arrives
  # alongside overlap_high (which fires from 0.98). What it adds is the
  # parent-is-a-key half of the evidence, and the count in the reason text.
  containment_near = 0.84,
  name_identical = 0.60,
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
  # Deliberately the same label as name_sim: detected_by feeds the Method
  # chip, its CSS class, the ERD edge colour and the exports, and a new
  # value would reach all four unhandled. The split lives in the signal
  # name and the reason text, which is all the evidence line needs.
  name_identical = "name_similarity",
  name_sim = "name_similarity",
  name_sim_weak = "name_similarity",
  overlap_high = "value_overlap",
  overlap_medium = "value_overlap",
  # Same label as the overlap signals, for the reason given above
  # name_identical: detected_by feeds the Method chip, its CSS class, the
  # ERD edge colour and the exports, and a new value would reach all four
  # unhandled. Containment is a value-overlap finding to a reviewer; the
  # evidence line is where the difference is spelled out.
  containment = "value_overlap",
  containment_near = "value_overlap",
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
  # Environment names are capped at 10000 bytes, and this is called with a
  # whole table's column names at once (detect_pks), so a wide table or
  # long names would otherwise stop detection with
  # "variable names are limited to 10000 bytes"
  if (nchar(key, type = "bytes") > 4000L) {
    key <- paste0("h:", rlang::hash(name))
  }
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
# Extract and snapshot suffixes: incident_6_30_26, visits_2024,
# claims_20240630, orders_v2, people_final, data_bak. Dropped before a
# table name is compared with a column name, or incident_id never
# matches incident_6_30_26 and the link is demoted as ambiguous.
table_stamp_re <- paste0(
  "(",
  "_[0-9]{1,2}_[0-9]{1,2}_[0-9]{2,4}",    # 6_30_26
  "|_[0-9]{4}[-_]?[0-9]{2}[-_]?[0-9]{2}", # 20240630, 2024_06_30
  "|_(19|20)[0-9]{2}",                    # _2024
  "|_v[0-9]+",                            # _v2
  "|_(final|draft|copy|bak|backup|old|new|tmp|temp|snapshot)",
  ")+$"
)

strip_table_stamp <- function(tname_clean) {
  out <- sub(table_stamp_re, "", tname_clean)
  if (nzchar(out)) out else tname_clean
}
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

# House-style surrogate keys: every table has one and none of them point
# at each other, so two of the same name is not evidence of a link.
generic_key_full <- c(
  generic_key_names,
  "record_id", "row_id", "rowid", "record_key", "record_number",
  "seq", "seq_id", "sequence", "sk", "surrogate_key", "uid", "oid",
  "objectid", "object_id", "autonumber", "counter"
)

is_generic_key <- function(col_clean) {
  isTRUE(col_clean %in% generic_key_full)
}

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
  x <- strip_table_stamp(strip_table_prefix(tname_clean))
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

# Words that end in "id" and are not keys. Without this list, a rule that
# reads any trailing "id" as a key turns is_valid, amount_paid, covid_test
# and medicaid_eligible into key candidates, which is noise in exactly the
# health and social-services extracts this app is pointed at.
not_key_words <- c(
  "valid", "invalid", "paid", "unpaid", "prepaid", "void", "avoid",
  "said", "aid", "acid", "fluid", "liquid", "rapid", "solid", "humid",
  "hybrid", "grid", "candid", "timid", "vivid", "lucid", "rigid", "arid",
  "covid", "medicaid", "mid", "kid", "lid", "bid", "did", "hid", "rid",
  "squid", "druid", "cupid", "morbid", "placid", "stupid", "torrid"
)

# Weaker than is_key_name: a name ending in "id" that is not one of those
# words. It earns no naming weight and no score of its own. It only buys
# the column a hearing: it is not dropped for low cardinality, and it may
# take the one-to-one path. primaryid, caseid and supportrepid are the
# cases that matter, none of which the strict test recognises.
# Word stems that begin with "id" and are not keys. ideation matters
# here: a violent-death or behavioural-health extract has columns like
# suicidal_ideation, and identified_gender is just as plausible.
not_key_prefixes <- "^(idea|ident|ideol|idio|idl|idol|idyl)"

is_possible_key_name <- function(
  col_clean,
  possible_key_names = possible_key_names_default
) {
  # The tier switched off: no name qualifies, so only is_key_name()'s
  # strict test speaks. Shaped like the answer it replaces, one logical
  # per name, because both call sites pass vectors.
  if (!isTRUE(possible_key_names)) {
    return(rep(FALSE, length(col_clean)))
  }
  # Leading id counts too (idnum, id2, idcode), but not a word that
  # merely starts with those letters
  head_id <- grepl("^id", col_clean) & !grepl(not_key_prefixes, col_clean)
  tail_id <- grepl("id$", col_clean) | head_id
  word <- sub("^.*_", "", col_clean)
  # A bare "id" names no entity, and every lookup table has one, so
  # treating it as a key makes each of them a parent for all the others.
  # is_key_name() excludes it for the same reason.
  tail_id &
    !(col_clean %in% generic_key_full) &
    !(col_clean %in% not_key_words) &
    !(word %in% not_key_words)
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
# one (few rows, few columns, a unique id/code column). Memoised per
# content for small tables, per name and shape for larger ones.
.lookup_cache <- new.env(parent = emptyenv())

is_lookup_table <- function(tname, df) {
  # The answer depends on column names and on which columns are unique, so
  # key on the content, not just the shape (small tables are cheap to hash;
  # larger ones fail the size test and never reach it)
  key <- paste(
    "k", tname, nrow(df), ncol(df),
    if (nrow(df) <= 500 && ncol(df) <= 4) rlang::hash(df) else paste(names(df), collapse = ","),
    sep = "\r"
  )
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
    vals <- with_local_seed(42, sample(vals, sample_size))
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

# The whole-number range a numeric column covers and how densely it fills
# it: 1..60 with no gaps has density 1, thirteen ids scattered over 14,000
# has density 0.001. NULL for anything that is not whole numbers, strings
# and measurements included: those have no positions to count, so there is
# no chance overlap to subtract from them.
integer_domain <- function(v) {
  if (!is.numeric(v)) {
    return(NULL)
  }
  x <- v[!is.na(v)]
  x <- x[is.finite(x)]
  if (length(x) < 2 || any(x != floor(x))) {
    return(NULL)
  }
  lo <- min(x)
  hi <- max(x)
  positions <- hi - lo + 1
  if (positions <= 1) {
    return(NULL)
  }
  list(lo = lo, hi = hi, density = min(length(unique(x)) / positions, 1))
}

column_profile <- function(v, sample_cap = 5000) {
  vals <- as.character(v[!is.na(v)])
  uniq <- unique(vals)
  uniq_sample <- uniq
  if (length(uniq_sample) > sample_cap) {
    uniq_sample <- uniq_sample[with_local_seed(42, sample(length(uniq_sample), sample_cap))]
  }
  count_vals <- vals
  if (length(count_vals) > sample_cap) {
    count_vals <- count_vals[with_local_seed(42, sample(length(count_vals), sample_cap))]
  }
  counts <- table(count_vals)
  list(
    dtype = col_dtype_class(v),
    # Rows with a value, counted before any sampling: with the distinct
    # count it says whether this column identifies a row, which is what
    # the containment signal needs of a parent. counts is sampled, so its
    # total cannot answer that.
    n_present = length(vals),
    uniq = uniq,
    uniq_sample = uniq_sample,
    counts = setNames(as.numeric(counts), names(counts)),
    fingerprint = format_fingerprint(v),
    int_domain = integer_domain(v),
    # Prose rather than an identifier: see is_prose_column(). Computed
    # here so the containment guard costs nothing per pair.
    is_prose = is_prose_column(vals)
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

# How much of an overlap a dense parent domain hands out for free.
#
# A count column holding 0..12 sits inside any contiguous 1..N id column,
# so raw overlap reports "nearly every value found" when nothing was
# really tested: incident.number_of_suspects scored 94% against
# victim.height_inches on exactly that. The parent's density is the chance
# that an arbitrary whole number in its range is present, so it is also
# the overlap a child drawn from that range gets for nothing. Only child
# values inside the parent's range can be found by chance; the rest miss
# either way, so they are not counted here.
#
# Returns 0 when the parent has no integer domain (a string column, a
# measurement, a single repeated value), which leaves those pairs scoring
# exactly as they did before.
overlap_expected_by_chance <- function(
  p_child,
  p_parent,
  overlap_chance_discount = overlap_chance_discount_default,
  overlap_chance_max_distinct = overlap_chance_max_distinct_default
) {
  # The discount switched off: nothing is given away for free, so the raw
  # overlap stands as the evidence for every pair.
  if (!isTRUE(overlap_chance_discount)) {
    return(0.0)
  }
  dom <- p_parent$int_domain
  if (is.null(dom) || length(p_child$uniq_sample) == 0) {
    return(0.0)
  }
  # Too many distinct values on the child side for containment to be luck
  if (length(p_child$uniq) >= overlap_chance_max_distinct) {
    return(0.0)
  }
  vals <- suppressWarnings(as.numeric(p_child$uniq_sample))
  inside <- sum(!is.na(vals) & vals >= dom$lo & vals <= dom$hi)
  dom$density * inside / length(p_child$uniq_sample)
}

# ── Is this parent column a key? ─────────────────────────────
# Containment only means something when the parent identifies a row:
# incident.number_of_suspects sits wholly inside victim.height_inches, and
# a column of heights is not a key, which is what keeps that pair out.
#
# Mirrors the two tests detect_fks() already applies when it chooses target
# columns, so a standalone score_candidate() call answers the question the
# same way the scan does: pk_map (strictly unique, fully populated) and
# near_unique_cols (parent_key_min_frac of both). Counts come off the
# cached profile, so this adds no pass over the data. Same quick rejects as
# both of those: a flag, a date and a block of free text are not keys
# whatever their values do.
#
# requirement selects how many tiers are open (parent_key_requirements).
# The two original tiers are tested first and in the same order whatever
# the requirement, so a column that is both strictly unique and half of a
# unique pair reads "key": the relaxed tiers only ever add parents the
# strict ones refused, and nothing is counted twice.
#
# composite_ok is the composite probe's answer for this column, passed in
# rather than computed here: the caller runs the probe only for a parent a
# child is already wholly contained in, and caches it per column. It is
# FALSE, TRUE, or the tier string the probe earned (composite_tier), and a
# function of no arguments returning one of those is called only if the
# two strict tiers have already refused - so a column that is a key
# outright is never probed and never counted as a composite admission.
#
# Returns "key", "near key", "composite key component", "non-key column"
# (all four go into the reason text) or NULL.
parent_key_kind <- function(
  v,
  p,
  n,
  requirement = parent_key_requirement_default,
  composite_ok = FALSE
) {
  if (n == 0 || !can_be_parent_key(v)) {
    return(NULL)
  }
  present <- p$n_present
  distinct <- length(p$uniq)
  if (present == n && distinct == n) {
    return("key")
  }
  if (
    present >= n * parent_key_min_frac &&
      distinct >= present * parent_key_min_frac
  ) {
    return("near key")
  }
  if (requirement == "composite") {
    ok <- if (is.function(composite_ok)) composite_ok() else composite_ok
    if (is.character(ok) && nzchar(ok)) {
      return(ok)
    }
    if (isTRUE(ok)) {
      return("composite key component")
    }
  }
  if (requirement == "any") {
    # "any" does not run the probe, so a composite component reads as the
    # plain column it is under this setting. The dtype rejects above still
    # apply: they are type guards, not a key requirement, and a date
    # column is not a parent under any reading of the word.
    return("non-key column")
  }
  NULL
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

# ── Near-unique columns (dirty keys) ─────────────────────────
#
# Parent candidates for a table that has no strictly unique column at all.
# A foreign key's parent is a key, so a column whose values repeat is not
# one; a key that arrives with a few duplicate or missing rows still is
# (parent_key_min_frac). Without this, every plausible column in such a
# table was offered as a target, which is where
# incident.number_of_suspects -> victim.height_inches came from at 94%.
#
# Same quick rejects as detect_fks' pk_map: a flag, a date and a block of
# free text are not keys whatever their uniqueness.
near_unique_cols <- function(df) {
  n <- nrow(df)
  if (n == 0) {
    return(character(0))
  }
  keep <- vapply(
    names(df),
    function(cn) {
      v <- df[[cn]]
      if (is.logical(v) || inherits(v, c("Date", "POSIXt"))) {
        return(FALSE)
      }
      # isTRUE: an all-NA text column has no median and would error
      if (
        is.character(v) &&
          isTRUE(median(nchar(head(na.omit(v), 20))) > 60)
      ) {
        return(FALSE)
      }
      present <- sum(!is.na(v))
      present >= n * parent_key_min_frac &&
        length(unique(v[!is.na(v)])) >= present * parent_key_min_frac
    },
    logical(1)
  )
  names(df)[keep]
}

# ── Can this column be a parent key at all? ──────────────────
# The dtype rejects every parent-key test in this file applies: a flag, a
# date and a block of free text are not keys whatever their values do.
# Stated once here for the composite probe and parent_key_kind; pk_map and
# near_unique_cols carry their own copies and are left alone.
can_be_parent_key <- function(v) {
  if (is.logical(v) || inherits(v, c("Date", "POSIXt"))) {
    return(FALSE)
  }
  # isTRUE: an all-NA text column has no median and would error
  if (
    is.character(v) &&
      isTRUE(median(nchar(head(na.omit(v), 20))) > 60)
  ) {
    return(FALSE)
  }
  TRUE
}

# ── Composite-key probe: the distinct-product prefilter ───────
# Which partner columns could possibly make `col` unique, and in what
# order to try them.
#
# A pair (a, b) can be unique over n rows only if d_a * d_b >= n: every row
# needs its own (value, value) slot and there are only d_a * d_b slots. So
# this is exact rather than a heuristic - no pair it drops could have been
# unique - and it is free, because the distinct counts are already
# computed. drug24q1 is the case it was written for: pairing drug_seq
# (1,777 distinct) with primaryid (406,184) gives 7.2e8 slots for 1.9e6
# rows, so the real key survives while the table's narrow pairings are
# refused without reading a row.
#
# Roomiest pair first, because the pair with the most slots per row is the
# likeliest to be unique, so the search usually stops on its first
# confirmation rather than its eighth.
composite_pair_candidates <- function(col, distinct_counts, n_rows) {
  others <- setdiff(names(distinct_counts), col)
  if (length(others) == 0) {
    return(character(0))
  }
  # as.numeric throughout: two columns of 50,000 distinct values overflow
  # an R integer, and the NA that produces would drop a pair that should
  # have survived
  product <- as.numeric(distinct_counts[[col]]) *
    as.numeric(distinct_counts[others])
  keep <- !is.na(product) & product >= n_rows
  others[keep][order(-product[keep])]
}

# ── Composite-key probe: is this column half of a key pair? ───
# Returns list(partner, exact) for the first pair that identifies the
# table's rows, or NULL. Width is two: a three-column key is out of scope
# here, so a table keyed on three columns reads as keyless and the
# "composite" setting finds nothing in it.
#
# "Identifies the rows" is read with the same tolerance parent_key_min_frac
# gives a dirty single-column key, and for the same reason. Measured on
# FAERS 2024Q1 on 2026-10-11: drug24q1 has 1,909,327 rows and
# (primaryid, drug_seq) takes 1,909,235 distinct values, so 92 rows share a
# key with another, across 86 keys, at a maximum multiplicity of 6. An
# exhaustive width-2 search over all 190 pairs of that table found no
# strictly unique pair at all, and no third column makes
# (primaryid, drug_seq) unique either. Requiring exact uniqueness would
# therefore refuse the one real composite key FAERS has, which is the case
# this whole setting exists for. exact says which it was, so the reason
# text can tell a reviewer the difference.
#
# detect_composite_pks() answers a related question by enumerating every
# combination up to width three over every candidate column and testing
# each against the whole table (190 pairs plus 1,140 triples on a
# 20-column table, times 1.9M rows), which did not finish in about 25
# minutes on FAERS. This is the cheap version: the prefilter above cuts
# the pairs, the sample cuts the rows, and the caller only asks about a
# column a child is already wholly contained in.
#
# Missing values: a pair can be "unique" only because both of its columns
# are mostly empty, which is not a key. So both columns have to be present
# on all but parent_key_min_frac of the rows - the same tolerance the near
# key tier allows a dirty single-column key - and uniqueness is then
# required exactly over the rows where both are present. A pair that
# clears the completeness bar but has one duplicate is refused: the
# tolerance is for missingness, not for duplication.
composite_key_component <- function(
  df,
  col,
  distinct_counts = NULL,
  sample_rows = composite_probe_sample_rows,
  max_pairs = composite_probe_max_pairs
) {
  n <- nrow(df)
  if (n < 2L || !col %in% names(df)) {
    return(NULL)
  }
  if (is.null(distinct_counts)) {
    distinct_counts <- vapply(
      df,
      function(v) length(unique(v[!is.na(v)])),
      integer(1)
    )
  }
  partners <- composite_pair_candidates(col, distinct_counts, n)
  if (length(partners) == 0) {
    return(NULL)
  }
  a <- df[[col]]
  confirmed <- 0L
  for (b_name in partners) {
    b <- df[[b_name]]
    idx <- which(!is.na(a) & !is.na(b))
    if (length(idx) < n * parent_key_min_frac) {
      next
    }
    # Duplicate rows the pair is allowed to carry and still be read as the
    # dirty version of a key, the same share parent_key_min_frac allows a
    # single column
    allowed <- length(idx) * (1 - parent_key_min_frac)
    if (length(idx) > sample_rows) {
      # A row that shares its key with another row inside the sample
      # shares it inside the whole table too, so the sample's duplicate
      # count can only understate the table's. Seeing more duplication
      # than the table is allowed therefore refuses the pair outright, for
      # the cost of a sample-sized pass rather than a 1.9M-row one. The
      # sample can only ever refuse: a pair it does not refuse is still
      # confirmed in full below, so this reorders the work and does not
      # approximate the answer.
      s <- with_local_seed(
        composite_probe_seed,
        sample(idx, sample_rows)
      )
      keys <- paste(a[s], b[s], sep = "\x01")
      if (length(keys) - length(unique(keys)) > allowed) {
        next
      }
    }
    confirmed <- confirmed + 1L
    keys <- paste(a[idx], b[idx], sep = "\x01")
    dup <- length(keys) - length(unique(keys))
    if (dup == 0L) {
      return(list(partner = b_name, exact = TRUE))
    }
    if (dup <= allowed) {
      return(list(partner = b_name, exact = FALSE))
    }
    if (confirmed >= max_pairs) {
      return(NULL)
    }
  }
  NULL
}

# The reason-text tier a probe result earns, or FALSE for no result.
composite_tier <- function(probe_result) {
  if (is.null(probe_result)) {
    return(FALSE)
  }
  if (isTRUE(probe_result$exact)) {
    "composite key component"
  } else {
    "near composite key component"
  }
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
    c2 <- clean_name(col2)
    stem1 <- sub("_(id|key|code|num|no)$", "", c1)
    stem2 <- sub("_(id|key|code|num|no)$", "", c2)
    sim <- jaro_winkler_sim(stem1, stem2)
    # Identical names are reported as such: "name similarity 1.00" reads as
    # a near miss, and the two cases are judged differently by a reviewer.
    # Same weight as name_sim, so scores do not move.
    # A house-style surrogate key on both sides is not evidence, and
    # blocking only the identical-name signal would hand the same pair to
    # the similarity branch at 1.00, which says the same thing louder
    if (identical(c1, c2) && is_generic_key(c1)) {
      NULL
    } else if (identical(c1, c2)) {
      list(
        signal = "name_identical",
        value = 1.0,
        reason = sprintf("identical column name (%s)", c1)
      )
    } else if (sim >= name_sim_high) {
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
  t2_is_lookup = NULL,
  containment_min_distinct = containment_min_distinct_default,
  parent_key_requirement = parent_key_requirement_default,
  composite_probe = NULL,
  prose_parent_guard = prose_parent_guard_default,
  overlap_chance_discount = overlap_chance_discount_default,
  overlap_chance_max_distinct = overlap_chance_max_distinct_default,
  cardinality_min_distinct = cardinality_min_distinct_default
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

  # 3. Value overlap, less the part a dense parent domain gives away for
  # free. The raw figure is still what gets reported and what the values
  # veto below reads: a reviewer wants to know how much of the child was
  # found, and the discount only decides whether that counts as evidence.
  ov <- NA_real_
  if (isTRUE(enable_flags[["value_overlap"]]) && n1 > 0 && n2 > 0) {
    ov <- overlap_from_profiles(p1, p2)
    ov_chance <- overlap_expected_by_chance(
      p1,
      p2,
      overlap_chance_discount,
      overlap_chance_max_distinct
    )
    ov_evidence <- max(0, ov - ov_chance)
    chance_note <- if (ov_chance >= 0.01) {
      sprintf(", %.0f%% of it expected by chance", ov_chance * 100)
    } else {
      ""
    }
    if (ov_evidence >= overlap_high) {
      signals[["overlap_high"]] <- ov
      reasons <- c(
        reasons,
        sprintf("value overlap %.0f%%%s", ov * 100, chance_note)
      )
    } else if (ov_evidence >= overlap_medium) {
      signals[["overlap_medium"]] <- ov
      reasons <- c(
        reasons,
        sprintf("partial overlap %.0f%%%s", ov * 100, chance_note)
      )
    }
  }

  # 3b. Containment: every value the child holds is present in a parent
  # column that identifies a row. That is what a foreign key is, so this
  # fires on a link whose name follows no convention and whose values are
  # spread nothing like the parent's, which is where the other six signals
  # between them have nothing to say.
  #
  # Deliberately exempt from step 3's chance-overlap discount. That
  # discount exists because a short dense integer run sits inside any other
  # dense run, and most of those runs are not keys at all: a count of
  # suspects fits a column of heights, and the parent key test above is
  # what rules that pair out rather than the density. The density still
  # governs the overlap signals, so a pair whose only evidence is a count
  # inside a non-key dense column still scores nothing. Two keys both
  # containing the same handful of values remain a real hazard, and
  # resolve_fk_parents' ambiguity rule is what answers it: the raw overlap
  # it reads is at or above overlap_high whenever containment fires here.
  #
  # That exemption extends to a composite key component, and deliberately:
  # the discount is a statement about the parent's density, not about which
  # tier admitted the parent, and a component of a real composite key is as
  # much a row identifier as half of one can be. The density still governs
  # the overlap signals in step 3 for these pairs exactly as it does for a
  # pk_map parent, so a count column sitting inside a dense composite
  # component still earns no overlap_high and no overlap_medium, and the
  # pair rests on containment alone. drug24q1.drug_seq is a dense integer
  # run (1,777 values, 1..1777), so this is the case it decides: the two
  # child columns reach it on containment and on nothing else.
  #
  # Reuses ov, which is already mean(child distinct in parent distinct),
  # so containment costs no second pass and no larger sample.
  if (
    isTRUE(enable_flags[["value_overlap"]]) &&
      n1 > 0 &&
      n2 > 0 &&
      !is.na(ov) &&
      length(p1$uniq) >= containment_min_distinct &&
      # A prose parent is unique by accident, not by design. Under either
      # refusal containment does not fire on one; the overlap and
      # distribution signals still do, so a copied address can still be
      # reported, just not on the strength of being inside a key.
      !(prose_parent_guard %in% c("refuse", "refuse_target") &&
        isTRUE(p2$is_prose))
  ) {
    # Demand-driven: the composite probe runs only for a parent column
    # this child is wholly inside, and only when the setting can use the
    # answer. A scan therefore asks about a handful of columns rather than
    # enumerating pairs over every column of every table, and the answer
    # is cached per (table, column) by the closure detect_fks passes in.
    # At partial containment the question is not asked: a child that is
    # only 99% inside a column is not the case this relaxation exists for.
    composite_ok <- if (
      parent_key_requirement == "composite" && ov >= containment_full
    ) {
      function() {
        if (is.null(composite_probe)) {
          # Standalone call: no cache to share, so probe this table here
          composite_tier(composite_key_component(df2, col2))
        } else {
          composite_probe(t2, col2)
        }
      }
    } else {
      FALSE
    }
    parent_kind <- parent_key_kind(
      df2[[col2]],
      p2,
      n2,
      parent_key_requirement,
      composite_ok
    )
    if (!is.null(parent_kind)) {
      # The distinct values actually tested. Above column_profile's
      # sampling cap that is a sample of the child's distinct values, so
      # "all n values" is a claim about those n, which is why the count is
      # in the reason text rather than a bare "all values".
      n_tested <- length(p1$uniq_sample)
      if (ov >= containment_full) {
        signals[["containment"]] <- 1.0
        reasons <- c(
          reasons,
          sprintf(
            "all %d values present in a %s (contained)",
            n_tested,
            parent_kind
          )
        )
      } else if (ov >= containment_near) {
        signals[["containment_near"]] <- ov
        reasons <- c(
          reasons,
          sprintf(
            "%d of %d values present in a %s (nearly contained)",
            round(ov * n_tested),
            n_tested,
            parent_kind
          )
        )
      }
    }
  }

  # 4. Exact cardinality match, above the floor where it says something.
  # Two tiny code domains holding the same handful of values is the
  # expected outcome, not a coincidence (cardinality_min_distinct).
  if (isTRUE(enable_flags[["cardinality"]]) && n1 > 0 && n2 > 0) {
    u1 <- p1$uniq
    u2 <- p2$uniq
    if (
      length(u1) >= cardinality_min_distinct &&
        length(u1) == length(u2) &&
        all(u1 %in% u2)
    ) {
      signals[["cardinality_match"]] <- 1.0
      reasons <- c(
        reasons,
        sprintf("identical value sets (%d values)", length(u1))
      )
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
  # Nothing to compare: with no rows on one side the content signals never
  # ran, so a name on its own is carrying the whole score. Medium implies
  # corroboration that does not exist here.
  if (
    (n1 == 0 || n2 == 0) &&
      !any(names(signals) %in% c("naming_exact", "naming_role", "naming_self")) &&
      confidence != "low"
  ) {
    confidence <- "low"
    score <- min(score, 0.54)
  }

  # Values veto: with data on both sides, a link whose values mostly aren't in
  # the parent can't rest on format or loose name likeness alone
  if (
    !is.na(ov) && ov < 0.5 &&
      !any(names(signals) %in% c("naming_exact", "naming_role", "naming_self")) &&
      confidence != "low"
  ) {
    confidence <- "low"
    score <- min(score, 0.54)
    reasons <- c(sprintf("only %.0f%% of values found in the parent", ov * 100), reasons)
  }

  # Carried for the Relationships table: a reviewer needs to see how much
  # the values actually overlap, and whether there were any values to
  # compare, without opening another tab
  if (n1 == 0 || n2 == 0) {
    reasons <- c(
      reasons,
      sprintf(
        "no rows to compare (child %s, parent %s)",
        format(n1, big.mark = ","),
        format(n2, big.mark = ",")
      )
    )
  }

  list(
    signals = signals,
    reasons = reasons,
    score = score,
    confidence = confidence,
    detected_by = detected_by,
    overlap = ov,
    n_from = n1,
    n_to = n2
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

is_fk_candidate <- function(
  col,
  col_name,
  possible_key_names = possible_key_names_default
) {
  # Fast heuristic checks - reject columns that almost never form relationships
  n <- length(col)
  if (n == 0) {
    return(FALSE)
  }

  # Boolean / low-cardinality columns are not FKs, unless named like a key
  # (provider_id holding one or two providers is still a foreign key)
  n_unique <- length(unique(na.omit(col)))
  cn <- clean_name(col_name)
  if (
    n_unique <= 2 &&
      n > 10 &&
      !is_key_name(cn) &&
      !is_possible_key_name(cn, possible_key_names)
  ) {
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
#
# containment_min_distinct: how many distinct values a child column needs
# before being wholly inside a parent key counts as evidence. A per-scan
# setting rather than a constant, because how much of a coincidence three
# shared values are depends on the schema: pass a higher number for a
# schema full of small code domains. Reaches score_candidate() from here.
#
# parent_key_requirement: how strict the containment signal's parent-key
# requirement is (parent_key_requirements). "key", the default, is the
# behaviour this function had before the setting existed. The other two
# widen the set of columns a table offers as parents, which is where the
# measurement of what they cost comes from; the UI does not set this yet.
#
# Two attributes come back for that measurement, alongside "truncated":
#   composite_probe_secs  seconds spent in the composite probe
#   composite_parents     admitted composite components, "table.column"

detect_fks <- function(
  tables,
  method = "both",
  min_confidence = "medium",
  enable_flags = NULL,
  progress_fn = NULL,
  max_pairs = 50000L,
  focus_tables = NULL,
  existing = list(),
  containment_min_distinct = containment_min_distinct_default,
  parent_key_requirement = parent_key_requirement_default,
  prose_parent_guard = prose_parent_guard_default,
  overlap_chance_discount = overlap_chance_discount_default,
  overlap_chance_max_distinct = overlap_chance_max_distinct_default,
  cardinality_min_distinct = cardinality_min_distinct_default,
  possible_key_names = possible_key_names_default
) {
  prose_parent_guard <- match.arg(prose_parent_guard, prose_parent_guards)
  parent_key_requirement <- match.arg(
    parent_key_requirement,
    parent_key_requirements
  )
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

  # Fallback parents for a table with no strictly unique column at all:
  # its near-unique columns only, never every plausible column. Computed
  # once per table because the target list is read for every source column
  # that reaches the table.
  near_pk_map <- lapply(tnames, function(t) {
    if (length(pk_map[[t]]) > 0 || nrow(tables[[t]]) == 0) {
      return(character(0))
    }
    near_unique_cols(tables[[t]])
  })
  names(near_pk_map) <- tnames

  # ── Relaxed parent-key settings ──────────────────────────────
  # Both relaxed settings widen the columns a table offers as parents,
  # because target_cols below is what decides whether containment is ever
  # measured for a column at all: a column no child is compared against
  # cannot be asked whether it is half of a key. Under "key" none of this
  # runs and the default costs nothing.
  #
  # "composite" offers the columns that could be half of a unique pair -
  # the distinct-product prefilter, which is exact - and the probe then
  # decides, on demand, whether a column a child is wholly inside really
  # is one. "any" offers every column that passes the dtype rejects.
  relaxed <- parent_key_requirement != "key"

  distinct_cache <- new.env(parent = emptyenv())
  get_distinct <- function(t) {
    hit <- distinct_cache[[t]]
    if (is.null(hit)) {
      hit <- vapply(
        tables[[t]],
        function(v) length(unique(v[!is.na(v)])),
        integer(1)
      )
      assign(t, hit, envir = distinct_cache)
    }
    hit
  }

  relaxed_parent_map <- lapply(tnames, function(t) {
    if (!relaxed) {
      return(character(0))
    }
    df <- tables[[t]]
    if (nrow(df) < 2L) {
      return(character(0))
    }
    ok <- names(df)[vapply(df, can_be_parent_key, logical(1))]
    if (parent_key_requirement == "any") {
      return(ok)
    }
    # Keep only the columns some partner could make unique. Cheap, exact,
    # and on a narrow table it drops nothing, which is why the probe is
    # still needed afterwards.
    d <- get_distinct(t)[ok]
    n <- nrow(df)
    ok[vapply(
      ok,
      function(cn) {
        length(composite_pair_candidates(cn, d, n)) > 0L
      },
      logical(1)
    )]
  })
  names(relaxed_parent_map) <- tnames

  # The composite probe, cached per (table, column) so a parent asked
  # about by two children is tested once, and timed so the report can say
  # what the test itself added as against what the wider candidate pool
  # added. score_candidate calls this only at full containment.
  composite_probe_cache <- new.env(parent = emptyenv())
  composite_probe_secs <- 0
  composite_parents <- character(0)
  composite_probe <- function(t, col) {
    key <- paste(t, col, sep = "|")
    hit <- composite_probe_cache[[key]]
    if (is.null(hit)) {
      t0 <- Sys.time()
      probe <- composite_key_component(
        tables[[t]],
        col,
        distinct_counts = get_distinct(t)
      )
      composite_probe_secs <<- composite_probe_secs +
        as.numeric(difftime(Sys.time(), t0, units = "secs"))
      hit <- composite_tier(probe)
      partner <- probe$partner
      assign(key, hit, envir = composite_probe_cache)
      if (!isFALSE(hit)) {
        # The partner is the other half of the same unique pair, so it
        # answers the same way without being probed again. Seeding its
        # cache entry is what makes "both columns of the pair become
        # eligible parents" true of the cache and not only of the column
        # that happened to be asked about first.
        assign(
          paste(t, partner, sep = "|"),
          hit,
          envir = composite_probe_cache
        )
      }
    }
    if (!isFALSE(hit)) {
      # Counted where the question was asked and answered yes, so this is
      # the set of columns the composite tier actually admitted as
      # parents: columns a child was wholly inside, that the key and near
      # key tiers had already refused. A column that is a key outright is
      # never probed, so it never appears here.
      composite_parents <<- union(composite_parents, paste(t, col, sep = "."))
    }
    hit
  }

  # Pre-compute FK-candidate columns per table (skip non-FK-like columns).
  # Empty tables have no values to screen, so their key-named columns are
  # candidates for name matching.
  fk_candidates <- lapply(tnames, function(t) {
    df <- tables[[t]]
    if (nrow(df) == 0) {
      return(names(df)[is_key_name(clean_name(names(df)))])
    }
    cols <- setdiff(names(df), pk_map[[t]])
    cols[vapply(
      cols,
      function(c) is_fk_candidate(df[[c]], c, possible_key_names),
      logical(1)
    )]
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
    # Possible key names count here too: a one-row-per-client table keyed
    # on primaryid or caseid is the same shape as one keyed on client_id,
    # and the strict test does not recognise a glued name
    pks[
      (is_key_name(pks_clean) |
        is_possible_key_name(pks_clean, possible_key_names)) &
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
      signals = res$signals,
      # Raw overlap, for resolve_fk_parents' ambiguity test: whether the
      # values fit a table is a different question from whether the fit is
      # evidence, and the chance discount only answers the second
      overlap = res$overlap
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
        strict_cols <- if (length(pk_map[[t2]]) > 0) {
          pk_map[[t2]]
        } else if (nrow(df2) == 0) {
          # Empty tables: their key-named and id/code columns
          names(df2)[vapply(
            clean_name(names(df2)),
            function(cc) is_key_name(cc) || cc %in% generic_key_names,
            logical(1)
          )]
        } else {
          # A parent has to be a key: near-unique columns only, and no
          # targets at all for a table where nothing identifies a row
          near_pk_map[[t2]]
        }
        # A relaxed setting adds its wider pool on top, never in place of
        # the strict choice above, so every parent "key" would have found
        # is still offered and still read by its own tier first.
        #
        # A column that only the relaxed pool offered is on probation: it
        # is here so that containment can be measured against it, and a
        # pair that does not end up carrying a containment signal is
        # discarded below. Without that, widening the pool would also hand
        # every other signal a parent it was never allowed to propose -
        # Lahman went from 22 found rows to 1,292 that way, almost none of
        # them through the rule being measured - and the setting would no
        # longer be measuring the parent-key requirement alone.
        relaxed_add <- if (relaxed) {
          setdiff(relaxed_parent_map[[t2]], strict_cols)
        } else {
          character(0)
        }
        target_cols <- union(strict_cols, relaxed_add)
        # A prose column is unique by accident: an address, a person's
        # name, a title. Under "refuse_target" it is not offered as a
        # parent at all, so no signal can propose it, which is what it
        # takes to keep invoice.billingaddress -> customer.address out.
        if (prose_parent_guard == "refuse_target" && length(target_cols)) {
          target_cols <- target_cols[!vapply(
            target_cols,
            function(cc) isTRUE(get_profile(t2, cc)$is_prose),
            logical(1L)
          )]
        }
        if (src_unique) {
          # A unique key only links to the same key, unique in the parent
          target_cols <- pk_map[[t2]][
            clean_name(pk_map[[t2]]) == clean_name(col1)
          ]
          relaxed_add <- character(0)
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
              lookup_flags[[t2]],
              containment_min_distinct,
              parent_key_requirement,
              composite_probe,
              prose_parent_guard,
              overlap_chance_discount,
              overlap_chance_max_distinct,
              cardinality_min_distinct
            ),
            error = function(e) NULL
          )
          if (is.null(result)) {
            next
          }
          # On probation: a parent only the relaxed pool offered has to
          # earn its place through the signal the setting relaxes. Either
          # containment tier counts; under "composite" only the full one
          # can arise, because the probe is asked only at full
          # containment.
          if (
            col2 %in% relaxed_add &&
              !any(c("containment", "containment_near") %in% names(result$signals))
          ) {
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

        # Candidate parents for this column are weighed against each other
        # afterwards (resolve_fk_parents), so the scan order doesn't matter
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

  # Weigh each column's candidate parents together, including links found
  # by earlier scans, but return only the new ones
  if (length(existing) > 0) {
    link_key <- function(r) {
      paste(r$from_table, r$from_col, r$to_table, r$to_col %||% "", sep = "|")
    }
    old_keys <- vapply(existing, link_key, character(1))
    resolved <- resolve_fk_parents(c(existing, results))
    results <- Filter(function(r) !(link_key(r) %in% old_keys), resolved)
  } else {
    results <- resolve_fk_parents(results)
  }
  results <- sort_rels(results)

  # Let callers warn that tables late in the scan order were not compared
  attr(results, "truncated") <- pair_count > max_pairs
  attr(results, "pairs_scored") <- pair_count
  # Measurement of the relaxed settings: what the probe itself cost, and
  # which columns it admitted that the strict tiers would have refused
  attr(results, "composite_probe_secs") <- composite_probe_secs
  attr(results, "composite_parents") <- sort(composite_parents)
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

# ── Choosing between candidate parents ───────────────────────
# A column can match several tables. On Access-style data every tlk_* lookup
# numbers its id 1..N, so service_id's values fit tlk_services, tlk_sites and
# every other lookup equally well. Values alone can't choose between them, so
# names come first (as in SchemaSpy, SchemaCrawler and FK-discovery research):
#   1. A parent the column's name points to wins; content-only matches to
#      other tables drop to low ("name points to ...").
#   2. No name evidence and 2+ parents contain the column's values: all drop
#      to low ("ambiguous: values fit N tables"), unless one parent's column
#      name is clearly the closest.
#   3. Otherwise the best parent is kept and parents scoring more than 0.05
#      below it are dropped.
# Demoted links stay (at low) so they can be reviewed. The pass works from
# each link's original score (base_score / base_confidence), so it can run
# again over cached plus new results and give the same answer.

fk_name_signals <- c("naming_exact", "naming_role", "naming_self")
# No containment entry is needed: containment only fires at 99% or above,
# and the raw-overlap test below catches every such pair at overlap_high.
fk_value_fit_signals <- c("cardinality_match", "overlap_high")

resolve_fk_parents <- function(rels) {
  if (length(rels) < 2) {
    return(rels)
  }
  rels <- lapply(rels, function(r) {
    if (is.null(r$base_score)) {
      r$base_score <- r$score %||% 0
      r$base_confidence <- r$confidence %||% "low"
      r$base_reasons <- r$reasons %||% character(0)
    }
    r$score <- r$base_score
    r$confidence <- r$base_confidence
    r$reasons <- r$base_reasons
    r$demoted <- NULL
    r
  })
  demote <- function(r, why) {
    r$score <- round(min(r$base_score, 0.54) * 0.9, 3)
    r$confidence <- "low"
    r$reasons <- c(why, r$base_reasons)
    r$demoted <- why
    r
  }
  sig_names <- function(r) names(r$signals %||% list())
  col_keys <- vapply(rels, function(r) paste(r$from_table, r$from_col, sep = "|"), "")
  keep <- rep(TRUE, length(rels))

  for (ck in unique(col_keys[duplicated(col_keys)])) {
    idx <- which(col_keys == ck)
    named <- idx[vapply(rels[idx], function(r) any(sig_names(r) %in% fk_name_signals), logical(1))]
    if (length(named) > 0) {
      # 1. The name decides
      targets <- paste(unique(vapply(rels[named], `[[`, "", "to_table")), collapse = ", ")
      for (i in setdiff(idx, named)) {
        rels[[i]] <- demote(rels[[i]], sprintf("name points to %s", targets))
      }
      idx <- named
    } else {
      # A column whose values sit inside eight lookups' domains fits all
      # eight, whether or not that fit counted as evidence: the chance
      # discount in score_candidate must not switch this guard off, so the
      # raw overlap is read here alongside the signals
      value_fit <- function(r) {
        any(sig_names(r) %in% fk_value_fit_signals) ||
          isTRUE((r$overlap %||% NA_real_) >= overlap_high)
      }
      fits <- idx[vapply(rels[idx], value_fit, logical(1))]
      if (length(fits) >= 2) {
        # 2. Values fit several tables: only a clearly closer name can choose
        close <- fits[vapply(rels[fits], function(r) any(c("name_identical", "name_sim") %in% sig_names(r)), logical(1))]
        winners <- if (length(close) == 1) close else integer(0)
        n_fit <- length(fits)
        fit_names <- vapply(rels[fits], `[[`, "", "to_table")
        why <- sprintf(
          "ambiguous: values fit %d tables (%s)",
          n_fit,
          paste(head(sort(unique(fit_names)), 6), collapse = ", ")
        )
        if (length(winners) == 1) {
          why <- sprintf("name is closest to %s", rels[[winners]]$to_table)
        }
        for (i in setdiff(fits, winners)) {
          rels[[i]] <- demote(rels[[i]], why)
        }
        idx <- c(winners, setdiff(idx, fits))
      }
    }
    # 3. Among the rest, drop parents well below the best one
    if (length(idx) > 1) {
      best <- max(vapply(rels[idx], `[[`, numeric(1), "base_score"))
      for (i in idx) {
        if (rels[[i]]$base_score < best - 0.05) keep[i] <- FALSE
      }
    }
  }
  rels[keep]
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

# ── Shared columns (not foreign keys) ────────────────────────
# A column that appears in two tables under the same name, holds
# overlapping values, and is a key in neither. incident_year to
# incident_year is the example: useful for joining, not a reference, and
# detect_fks() never sees it because targets are drawn from unique
# columns only. Reported as its own class so it is visible without
# being mislabelled as an FK.

detect_shared_columns <- function(
  tables,
  min_overlap = 0.5,
  min_distinct = 3L,
  max_pairs = 20000L
) {
  tnames <- names(tables)
  if (length(tnames) < 2) {
    return(list())
  }
  unique_cols <- lapply(tables, function(df) {
    n <- nrow(df)
    if (n == 0) {
      return(character(0))
    }
    names(df)[vapply(
      names(df),
      function(c) !anyNA(df[[c]]) && length(unique(df[[c]])) == n,
      logical(1)
    )]
  })
  names(unique_cols) <- tnames

  out <- list()
  pairs <- 0L
  for (i in seq_len(length(tnames) - 1L)) {
    for (j in seq.int(i + 1L, length(tnames))) {
      t1 <- tnames[[i]]
      t2 <- tnames[[j]]
      df1 <- tables[[t1]]
      df2 <- tables[[t2]]
      if (nrow(df1) == 0 || nrow(df2) == 0) {
        next
      }
      common <- intersect(names(df1), names(df2))
      for (cn in common) {
        if (pairs >= max_pairs) {
          return(out)
        }
        pairs <- pairs + 1L
        # A key on either side is a foreign key question, not this one
        if (cn %in% unique_cols[[t1]] || cn %in% unique_cols[[t2]]) {
          next
        }
        v1 <- df1[[cn]][!is.na(df1[[cn]])]
        v2 <- df2[[cn]][!is.na(df2[[cn]])]
        u1 <- unique(v1)
        u2 <- unique(v2)
        # Two-valued flags shared by every table say nothing
        if (length(u1) < min_distinct || length(u2) < min_distinct) {
          next
        }
        shared <- intersect(u1, u2)
        if (length(shared) == 0) {
          next
        }
        ov <- length(shared) / min(length(u1), length(u2))
        if (ov < min_overlap) {
          next
        }
        out[[length(out) + 1]] <- list(
          from_table = t1,
          to_table = t2,
          column = cn,
          n_shared = length(shared),
          n_distinct_from = length(u1),
          n_distinct_to = length(u2),
          overlap = ov,
          contained = length(shared) == min(length(u1), length(u2))
        )
      }
    }
  }
  out
}
