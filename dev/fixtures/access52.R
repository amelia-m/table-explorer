# ============================================================
# access52.R - a synthetic 52-table Access-style schema with known links
# ============================================================
#
# The hard case for FK detection: 8 lookup tables (tlk_*) that all use ids
# 1..8, so values alone can't tell which lookup a column points at.
#   - 8 lookups: tlk_providers, tlk_services, ... (id, label)
#   - 40 entity tables tbl_<entity> (60 rows each), each linking to two
#     lookups (<lookup>_id) and up to two earlier entities (<entity>_id);
#     every third table has missing values in its lookup columns; every
#     tenth has an unhelpfully named `code` column holding lookup-like ids
#   - 4 unlinked tables tbl_misc1..4
# Deterministic (fixed seed). Used by score_detection.R; also handy as a big
# schema for trying the ERD by hand.
#
# Returns list(tables, truth): truth is "from_table|from_col|to_table" for
# every real link (157 of them).

access52_fixture <- function() {
  set.seed(7)
  lk <- c("providers", "services", "sites", "statuses", "programs", "funders", "regions", "outcomes")
  tbls <- list()
  for (l in lk) tbls[[paste0("tlk_", l)]] <- data.frame(id = 1:8, label = paste(l, 1:8))
  ents <- c("client", "visit", "staff", "referral", "invoice", "payment", "claim", "appointment", "assessment", "diagnosis", "medication", "prescription", "household", "contact", "address", "grant", "budget", "expense", "vendor", "contract", "training", "certificate", "incident", "complaint", "survey", "response", "event", "attendance", "donation", "donor", "volunteer", "shift", "vehicle", "trip", "device", "loan", "document", "note", "task", "goal")
  truth <- list()
  for (i in seq_along(ents)) {
    n <- 60
    df <- data.frame(x = i * 1000L + seq_len(n)); names(df) <- paste0(ents[i], "_id")
    for (l in sample(lk, 2)) {
      # statuses -> status_id, providers -> provider_id
    cn <- paste0(sub("(us)es$|s$", "\\1", l), "_id")
      df[[cn]] <- sample(c(1:8, if (i %% 3 == 0) NA), n, TRUE)
      truth[[length(truth) + 1]] <- c(paste0("tbl_", ents[i]), cn, paste0("tlk_", l))
    }
    if (i > 1) for (p in sample(ents[seq_len(i - 1)], min(i - 1, 2))) {
      df[[paste0(p, "_id")]] <- match(p, ents) * 1000L + sample(1:60, n, TRUE)
      truth[[length(truth) + 1]] <- c(paste0("tbl_", ents[i]), paste0(p, "_id"), paste0("tbl_", p))
    }
    if (i %% 10 == 0) df$code <- sample(1:8, n, TRUE)   # unhelpful name
    df$notes <- sample(letters, n, TRUE)
    df$amount <- sample(c(5, 10, 20, 50), n, TRUE)
    tbls[[paste0("tbl_", ents[i])]] <- df
  }
  for (j in 1:4) tbls[[paste0("tbl_misc", j)]] <- data.frame(msg = letters[1:5], val = runif(5))
  truth_keys <- vapply(truth, paste, "", collapse = "|")
  list(tables = tbls, truth = truth_keys)
}
