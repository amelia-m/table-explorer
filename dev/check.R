# One command that says PASS or FAIL, with counts.
#
# Why this exists: twice in one session a scripted edit half-applied, the
# suite either aborted at parse time or never covered the gap, and an
# empty grep of the output was read as success. Silence is not evidence.
# This prints an explicit line for every check and exits non-zero on any
# failure, so a caller cannot mistake "no output" for "nothing wrong".
#
# Usage: Rscript dev/check.R

Sys.setenv(RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE")
fail <- 0L
say <- function(ok, label, detail = "") {
  if (!ok) fail <<- fail + 1L
  cat(sprintf("%-5s %s%s\n", if (ok) "PASS" else "FAIL", label,
              if (nzchar(detail)) paste0("  (", detail, ")") else ""))
}

# 1. Every R file parses. A dropped brace takes the whole suite down, and
# testthat reports that as an abort rather than a failure.
r_files <- c(
  list.files("R", pattern = "[.]R$", full.names = TRUE),
  list.files("tests/testthat", pattern = "[.]R$", full.names = TRUE),
  list.files("dev", pattern = "[.]R$", full.names = TRUE, recursive = TRUE)
)
bad <- character(0)
for (f in r_files) {
  err <- tryCatch({
    parse(f)
    NULL
  }, error = function(e) conditionMessage(e))
  if (!is.null(err)) bad <- c(bad, paste0(f, ": ", err))
}
say(length(bad) == 0, sprintf("parse (%d files)", length(r_files)),
    paste(bad, collapse = "; "))

# 2. JavaScript parses too, when node is available
js <- list.files("inst/app/www", pattern = "[.]js$", full.names = TRUE)
js <- js[!grepl("/vendor/", js)]
if (nzchar(Sys.which("node"))) {
  js_bad <- js[vapply(js, function(f) {
    system2("node", c("--check", shQuote(f)), stdout = FALSE, stderr = FALSE) != 0
  }, logical(1))]
  say(length(js_bad) == 0, sprintf("node --check (%d files)", length(js)),
      paste(js_bad, collapse = "; "))
} else {
  cat("SKIP  node --check  (node not on PATH)\n")
}

# 3. The suite runs, and the counts are stated rather than inferred
res <- tryCatch(
  testthat::test_local(reporter = "silent", stop_on_failure = FALSE),
  error = function(e) e
)
if (inherits(res, "error")) {
  say(FALSE, "test_local", conditionMessage(res))
} else {
  df <- as.data.frame(res)
  n_fail <- sum(df$failed)
  n_err <- sum(df$error)
  n_pass <- sum(df$passed)
  n_skip <- sum(df$skipped)
  say(n_fail == 0 && n_err == 0,
      sprintf("test_local: %d passed, %d failed, %d errors, %d skipped",
              n_pass, n_fail, n_err, n_skip))
  # A suite that runs no tests is a failure, not a pass
  say(n_pass > 0, "test_local ran tests at all")
}

# 4. Detection has not lost or invented links
out <- tryCatch(
  system2("Rscript", "dev/fixtures/score_detection.R", stdout = TRUE, stderr = FALSE),
  error = function(e) character(0)
)
line <- grep("^medium\\+:", out, value = TRUE)
if (length(line) != 1) {
  say(FALSE, "score_detection", "no medium+ line in output")
} else {
  real <- as.integer(sub(".*real: ([0-9]+) of ([0-9]+).*", "\\1", line))
  want <- as.integer(sub(".*real: ([0-9]+) of ([0-9]+).*", "\\2", line))
  false <- as.integer(sub(".*false: ([0-9]+).*", "\\1", line))
  say(!is.na(real) && !is.na(want) && real >= want && false == 0,
      sprintf("score_detection: %s", trimws(line)))
}

cat(if (fail == 0) "\nALL CHECKS PASSED\n" else sprintf("\n%d CHECK(S) FAILED\n", fail))
quit(status = if (fail == 0) 0L else 1L)
