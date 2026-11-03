# check_answer_key.R - assert every name, count and flag in the answer key against
# a built file, read directly with Jackcess. Exits non-zero and names each
# offending entry when the key and the file disagree, in either direction.
#
# Usage: Rscript --vanilla check_answer_key.R <file.mdb|.accdb> [key.csv]

args <- commandArgs(trailingOnly = TRUE)
script <- sub(
  "^--file=",
  "",
  grep("^--file=", commandArgs(FALSE), value = TRUE)
)
here <- dirname(normalizePath(script))
source(file.path(here, "fixture_jackcess.R"))
path <- args[[1]]
key_path <- if (length(args) >= 2) {
  args[[2]]
} else {
  file.path(here, "../../../tests/testthat/fixtures/access_fixture_key.csv")
}

key <- utils::read.csv(
  key_path,
  stringsAsFactors = FALSE,
  check.names = FALSE,
  na.strings = "",
  fileEncoding = "UTF-8",
  colClasses = c(pk = "character")
)
db <- jack_open(path)
bad <- character(0)
fail <- function(...) bad <<- c(bad, paste0(...))

objs <- jack_objects(db)
local_tbls <- objs$name[objs$type == 1 & !engine_table(objs$name)]
query_objs <- objs$name[objs$type == 5 & !startsWith(objs$name, "~")]
ktab <- key[key$kind == "table", ]
kcol <- key[key$kind == "column", ]
krel <- key[key$kind == "relationship", ]
kqry <- key[key$kind == "query", ]

for (i in seq_len(nrow(ktab))) {
  t <- ktab$table_raw[i]
  if (!t %in% local_tbls) {
    fail("table in key, not in file: ", t)
    next
  }
  tb <- jack_table(db, t)
  if (tb$getRowCount() != ktab$rows[i]) {
    fail(
      "row count for ",
      t,
      ": key ",
      ktab$rows[i],
      ", file ",
      tb$getRowCount()
    )
  }
  pk <- jack_pk(tb)
  want <- if (is.na(ktab$pk[i])) "" else ktab$pk[i]
  if (!identical(pk, want)) {
    fail("primary key of ", t, ": key '", want, "', file '", pk, "'")
  }
  if (!identical(janitor::make_clean_names(t), ktab$table_clean[i])) {
    fail("clean table name for ", t, ": key ", ktab$table_clean[i])
  }
  cols <- jack_columns(tb)
  kc <- kcol[kcol$table_raw == t, ]
  for (cn in setdiff(kc$column_raw, cols)) {
    fail("column in key, not in file: ", t, ".", cn)
  }
  for (cn in setdiff(cols, kc$column_raw)) {
    fail("column in file, not in key: ", t, ".", cn)
  }
  if (identical(sort(kc$column_raw), sort(cols))) {
    df <- as.data.frame(
      setNames(rep(list(1), length(cols)), cols),
      check.names = FALSE
    )
    cl <- setNames(names(janitor::clean_names(df)), cols)
    for (j in seq_len(nrow(kc))) {
      if (!identical(unname(cl[[kc$column_raw[j]]]), kc$column_clean[j])) {
        fail(
          "clean column name for ",
          t,
          ".",
          kc$column_raw[j],
          ": key ",
          kc$column_clean[j],
          ", janitor ",
          cl[[kc$column_raw[j]]]
        )
      }
    }
  }
}
for (t in setdiff(local_tbls, ktab$table_raw)) {
  fail("table in file, not in key: ", t)
}
for (q in setdiff(kqry$table_raw, query_objs)) {
  fail("query in key, not in file: ", q)
}
for (q in setdiff(query_objs, kqry$table_raw)) {
  fail("query in file, not in key: ", q)
}

fr <- jack_rels(db)
rk <- function(d) {
  paste(
    d$rel_name,
    d$icolumn,
    d$table_raw,
    d$column_raw,
    d$ref_table_raw,
    d$ref_column_raw,
    d$grbit_native,
    sep = "|"
  )
}
for (x in setdiff(rk(krel), rk(fr))) {
  fail("relationship in key, not in file: ", x)
}
for (x in setdiff(rk(fr), rk(krel))) {
  fail("relationship in file, not in key: ", x)
}
db$close()

cat(sprintf(
  "%s: checked %d tables, %d columns, %d relationship rows, %d queries\n",
  basename(path),
  nrow(ktab),
  nrow(kcol),
  nrow(krel),
  nrow(kqry)
))
if (length(bad)) {
  cat("ANSWER KEY FAILED\n", paste0("  ", bad, "\n"), sep = "")
  quit(save = "no", status = 1)
}
cat("answer key OK\n")
