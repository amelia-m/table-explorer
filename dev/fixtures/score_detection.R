# ============================================================
# score_detection.R - score FK detection against access52's known links
# ============================================================
#
# Usage, from the repository root:
#   Rscript dev/fixtures/score_detection.R [min_confidence]
# Sources R/ directly (no package install). Prints how many links detection
# reports at medium confidence or higher, how many are real, which real ones
# it missed, and the most common false ones.
#
# Baseline (after PR #20): 157 of 157 real links found at medium+, 0 false.
# Before PR #19's names-first parent resolution, ~1,400 links were reported.

suppressMessages(library(shiny))
for (f in setdiff(list.files("R", full.names = TRUE), "R/run_app.R")) source(f)
source("dev/fixtures/access52.R")

args <- commandArgs(trailingOnly = TRUE)
min_conf <- if (length(args)) args[[1]] else "medium"
fx <- access52_fixture()

r <- detect_fks(fx$tables, "both", min_conf)
key <- vapply(r, function(x) paste(x$from_table, x$from_col, x$to_table, sep = "|"), "")
conf <- vapply(r, `[[`, "", "confidence")
shown <- key[conf != "low"]

cat(sprintf("reported: %d (%s)\n", length(r), paste(names(table(conf)), table(conf), collapse = ", ")))
cat(sprintf("medium+: %d   real: %d of %d   false: %d\n",
  length(shown), sum(shown %in% fx$truth), length(fx$truth), sum(!shown %in% fx$truth)))
missed <- setdiff(fx$truth, shown)
if (length(missed)) {
  cat("missed:\n")
  cat(paste0("  ", missed), sep = "\n")
}
fp <- r[conf != "low" & !key %in% fx$truth]
if (length(fp)) {
  cat("most common false links:\n")
  print(head(sort(table(vapply(fp, function(x) {
    paste(x$from_col, "->", x$to_table, paste0("(", x$detected_by, ")"))
  }, "")), decreasing = TRUE), 15))
}
