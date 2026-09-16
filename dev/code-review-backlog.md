# Code review backlog

Findings from a three-agent review run on 2026-09-04 against branch
`copilot/create-implementation-plan-for-golem` (13 commits ahead of `main`,
plus ~1805 lines of uncommitted working-tree change).

Reviewer scopes:

- **A - modules**: uncommitted diff for `R/app_server.R`, `R/app_ui.R`, `R/mod_*.R`
- **B - utils/tests**: uncommitted diff for `R/utils_*.R`, `app.R`, `file_readers.R`, `tests/testthat/setup.R`, `DESCRIPTION`, `LICENSE`
- **C - structure**: whole branch vs `main`, packaging and golem conformance

Two reviewers independently AST-verified (parse, deparse at width 500, diff the
normalized token stream) that **~96% of the uncommitted diff is styler/air reflow
with zero semantic change**. Roughly 73 lines are substantive: ~50 in `R/mod_erd.R`,
23 across `app.R`, `R/utils_file_readers.R`, `file_readers.R`, `DESCRIPTION`, `LICENSE`.

## Environment caveats on these findings

- `golem`, `visNetwork` and `shinythemes` are not installed on the review machine.
  The ERD JavaScript was read, not executed. `R CMD check` findings are static
  analysis except where a repro is quoted.
- Test-suite results were produced by running the committed HEAD tree and the
  working tree in scratch copies. Nothing in the checkout was mutated.

---

## Critical

- [ ] **C1. `tests/testthat.R:5` runs zero tests under `R CMD check`.**
  Uses `test_package("tableexplorer")`, whose body returns early unless the package
  was installed with `--install-tests`. `tools:::.check_packages` contains zero
  references to `install-tests`, so `R CMD check` never passes it. The suite prints
  an informational line and passes green having executed nothing. Invisible locally
  because `devtools::test()` bypasses `testthat.R` entirely.
  **Fix:** `test_check("tableexplorer")`.

- [ ] **C2. `R/utils_inference.R:468` makes composite-PK detection inert on exactly the tables it exists for.**
  The guard calls `detect_pks(df, table_name, method = "both")`. The naming branch
  flags any `*_id` column as a PK with no uniqueness check, so a non-unique `order_id`
  short-circuits the guard. Repro on the test suite's own fixture:

  ```
  df <- data.frame(order_id = c(1,1,2,2,3), product_id = c(10,20,10,30,20), quantity = 1:5)
  detect_pks(df, "order_items", "both")    -> "order_id", "quantity"
  detect_composite_pks(df, "order_items")  -> length 0
  ```

  Any junction table with an `_id` column never gets a composite PK detected.
  Root cause of the four failing tests - the fixtures are not at fault.
  **Fix:** `method = "uniqueness"` in the guard.

- [ ] **C3. `options(shiny.maxRequestSize)` was dropped in the restructure.**
  `main`'s `app.R:14` set `shiny.maxRequestSize = Inf`. On this branch the value
  exists only at `inst/golem-config.yml:6` (104857600), which nothing reads (see I5).
  `grep -rn "options(" R/ app.R` returns nothing. Uploads silently revert to Shiny's
  5 MB default, breaking the app's primary workflow.
  **Fix:** set it in `run_app()` or `onStart`, ideally reading from config once I5 is resolved.

- [ ] **C4. `app.R:13` hard-errors under `Rscript app.R`.**
  `sys.frame(1L)` throws `not that many frames on the stack` when no frame exists;
  it does not return `NULL`, so the `!is.null(...)` guard can never fire. Reproduced
  independently by reviewers B and C. Regression: the previous bare `load_all()`
  defaulted to `path = "."` and worked.
  The block is also dead on every deployment path - Shiny never calls `source()`
  (`shiny:::sourceUTF8` uses `eval(parse(...))`), so `ofile` is never set. `runApp()`
  works only because `shiny:::shinyAppDir_appR` does `setwd(appDir)` first.

  | Launch path | `sys.frame(1L)$ofile` | Result |
  |---|---|---|
  | `Rscript app.R` | throws | hard error |
  | `source("app.R")` at top level | `"app.R"` | works |
  | `source()` inside a function | NULL | falls back to `getwd()` |
  | `shiny::runApp()` | NULL | falls back to `getwd()` |

  **Fix:** see D3. The `tableexplorer::` prefix is correct and should stay -
  `NAMESPACE` exports `run_app`, so it resolves after `load_all(export_all = FALSE)`.

---

## Important

### ERD module (reviewer A)

- [ ] **I1. `R/mod_erd.R:219-222` and `:292-295` - copy-pasted `else` branch that cannot work.**
  The branch sets `Shiny.setInputValue` with `id: params.nodes[0]` and calls
  `showNodePanel(params.nodes[0])`, but it runs precisely when `params.nodes.length == 0`,
  so `params.nodes[0]` is `undefined`. Lifted verbatim from the `click` handler, where the
  guard is inverted. Every empty double-click sets `input$vis_clicked_node` to `{ts: ...}`
  with `id` dropped by JSON serialization, waking the `observeEvent` at `R/mod_erd.R:333`
  for a `req()` that immediately stops it, and calls `showNodePanel(undefined)` which no-ops.
  Harmless today, but reads as intentional.
  **Fix:** delete the `else`, or make it close the panel via `vis_close_panel`.

- [ ] **I2. `R/mod_erd.R:199-226` - pinned node positions do not survive any re-render.**
  `dragEnd` writes `fixed: {x: true, y: true}` into the client-side vis DataSet only.
  `renderVisNetwork` depends on `all_tables_rv()`, `all_rels_rv()`, `pk_map_rv()`,
  `composite_pk_map_rv()`, `input$erd_layout` and `input$spring_length`. Suppressing a
  relationship, adding a manual relationship, changing detection method, or nudging the
  Spring length slider rebuilds the network and discards every pin. The slider is worst:
  it fires continuously while dragging, so a full rebuild per tick.
  **Fix:** round-trip positions to the server (a `reactiveVal` keyed by node id, written
  from `dragEnd`, read back into `net$nodes$x/y/fixed` in `build_network`), or move the
  mutable parts to `visNetworkProxy` so the network is never rebuilt. See D2.

- [ ] **I3. `R/mod_erd.R:211-226` - double-click also fires `click`, so unpinning opens the detail panel.**
  vis-network emits `click` for each click of a double-click, and the `click` handler at
  `:190-197` calls `showNodePanel`. The new unpin gesture pops the node overlay as a side
  effect.
  **Fix:** short suppression timer in the click handler, or document the behaviour in the hint.

- [ ] **I4. `R/mod_erd.R:186-226` vs `:255-299` - visNetwork chain and both JS blobs duplicated for the circular branch.**
  The circular layout rebuilds `vis` from scratch, so the two ~25-line JS strings exist
  twice, byte-identical apart from indentation. Direct cause of I1 appearing twice.
  **Fix:** hoist the JS into two local character variables, build the base chain once, and
  apply `visPhysics(enabled = FALSE)` plus the precomputed `x`/`y` as a modifier. The
  circular branch already computes `net$nodes$x/y` before the rebuild, so nothing forces
  the duplication.

### Packaging and golem conformance (reviewer C)

- [ ] **I5. `inst/golem-config.yml` is decorative - nothing can read it.**
  There is no `R/app_config.R`, so `app_sys()` and `get_golem_config()` do not exist in
  the package (`grep -rn "app_sys\|get_golem_config" R/` returns only comments). So
  `app_prod`, `app_url` and `shiny.maxRequestSize` are all inert. `app.R` also never sets
  `options("golem.app.prod" = TRUE)`, so prod mode is unreachable from either direction.
  Two further mismatches: `inst/golem-config.yml:4` uses `app_version` where golem's
  `get_golem_version()` reads `golem_version`, and there is no `dev:` block with
  `golem_wd: !expr golem::pkg_path()`, which `app_sys()` needs in dev mode.
  See D1 - the half-state is worse than either resolution.

- [ ] **I6. No `.Rbuildignore` at all.**
  `R CMD build` will bundle `app.R`, `app.py`, `requirements.txt`, `dev/`, `sample_data/`,
  `schema.json`, `tmp/`, `.claude/` and the four legacy root `.R` files. `R CMD check`
  gives a "Non-standard file/directory found at top level" NOTE.
  Minimum contents:

  ```
  ^app\.R$
  ^app\.py$
  ^requirements\.txt$
  ^dev$
  ^tmp$
  ^\.claude$
  ^sample_data$
  ^schema\.json$
  ^(inference|file_readers|export_utils|db_connectors)\.R$
  ^README\.md$
  ```

- [ ] **I7. No `man/` directory - `R CMD check` WARNING.**
  `run_app` is exported with roxygen docs but no `.Rd` was generated or committed, and
  there is no `man/tableexplorer-package.Rd` for the `"_PACKAGE"` block. Produces
  `WARNING: Undocumented code objects: 'run_app'`. `DESCRIPTION` has no `RoxygenNote`
  field, corroborating that `NAMESPACE` was hand-written.
  **Fix:** `devtools::document()`, commit `man/`.

- [ ] **I8. `stats`, `utils` and `tools` are used but undeclared.**
  13 `tools::` calls and 1 `utils::` in `R/utils_file_readers.R` with neither in `Imports`
  gives NOTE `'::' or ':::' import not declared`. Plus 43 unqualified calls to `setNames`,
  `head`, `median`, `sd`, `var`, `cor`, `na.omit`, `read.csv`, `write.csv` across 9 files
  (`R/utils_inference.R` x16, `R/utils_file_readers.R` x10, `R/app_server.R` x4,
  `R/mod_table_details.R` x4, `R/mod_relationships.R` x3, `R/mod_detection.R` x3, plus
  `R/mod_name_changes.R`, `R/utils_export.R`, `R/utils_vis.R`), giving
  `no visible global function definition` NOTEs.
  **Fix:** add `stats`, `utils`, `tools` to `Imports` with matching `@importFrom` tags.

- [ ] **I9. `pkgload` is used but declared nowhere in `DESCRIPTION`.**
  Referenced by `app.R:18` and `dev/02_dev.R:7`. Add to `Suggests`.

- [ ] **I10. Legacy root files are dead duplicates and dual maintenance has already started.**
  `inference.R`, `file_readers.R`, `export_utils.R`, `db_connectors.R` are sourced by
  nothing (`tests/testthat/setup.R:30` sources `R/`, the package loads `R/`). Diffed
  CR-normalised against their `R/utils_*.R` counterparts they are the same code modulo
  formatting (241/474/107/192 diff lines, all cosmetic). The only surviving reference is
  a stale allow-list entry in `.claude/settings.local.json`.
  The urgency: the current working tree modifies **both** `file_readers.R` and
  `R/utils_file_readers.R`, applying the same cache-key rename to the dead copy.
  Same story for `sample_data/*.csv` and `schema.json`, byte-identical to `inst/extdata/`
  modulo line endings. Keep `app.py` and `requirements.txt` - the README documents the
  Python version as a live secondary implementation. See D4.

- [ ] **I11. `dev/` scripts have uncommented side-effecting lines.**
  `dev/01_start.R:18` has `usethis::use_mit_license()` uncommented while everything around
  it is commented out. Sourcing that file overwrites `LICENSE` and rewrites the `License:`
  field - it would clobber the working tree's `YEAR: 2026 / COPYRIGHT HOLDER: Amelia Miramonti`.
  `dev/02_dev.R:7,17,20` have `pkgload::load_all()`, `devtools::document()` and
  `devtools::test()` uncommented, so sourcing regenerates `NAMESPACE` and runs the suite.
  **Fix:** comment these out, matching the "run interactively" instruction in the headers.

### Utils (reviewer B)

- [ ] **I12. Both renamed cache keys are in unreachable code, so the rename is a no-op.**
  No orphaned UCanAccess JARs, but the reason is itself a finding:

  - `R/utils_file_readers.R:385` `access_jar_dir()` has no callers anywhere. Its
    `R_user_dir("table-explorer-access-jars", "cache")` at `:390` is unreachable.
  - `R/utils_file_readers.R:446-449` renames a key inside a `tryCatch` error handler that
    cannot fire: with `mustWork = FALSE`, `normalizePath` warns rather than errors, and
    neither `dirname` nor `file.path` errors.

  The runtime path is `dirname(<uploaded file>)/access_jars`. Two of the 23 semantic lines
  in this diff were spent editing code that cannot run, and the two new keys remain
  mutually inconsistent (`table-explorer-access-jars` vs `table-explorer`), same as the old
  pair. `access_jar_dir()` at `:386` also contains the same `sys.frame(1)$ofile` idiom as C4;
  inside a function it does not throw, but `$ofile` is always `NULL` so it always yields
  `dirname(".")`. See D5.

- [ ] **I13. `app.R` is missing `options("golem.app.prod" = TRUE)`.**
  The rest of the file matches golem's generated deployment template. Inert today since
  nothing reads `golem.app.prod`, but one line now prevents a future `golem::app_prod()`
  guard silently behaving as dev in production.

---

## Minor

- [ ] **M1. `R/mod_export.R:99` - user-visible filename change riding inside a 1100-line reflow.**
  Session download prefix `table_explorer_session_` to `table-explorer-session-`. Nothing
  consumes it (`restore_session_json` accepts any `.json`, no test asserts the name), so
  it is safe, but it should not be buried in a formatting commit.

- [ ] **M2. `R/mod_erd.R:109-111` - hint text now under-describes the widget.**
  Dropped "hover for details" and "click to highlight connections" though
  `visInteraction(tooltipDelay = 80, hover = TRUE)` and `visOptions(highlightNearest = ...)`
  are still enabled in every branch. Those capabilities are now undiscoverable.

- [ ] **M3. `R/mod_erd.R:109` - pin hint shown unconditionally but meaningless in two of three layouts.**
  Hierarchical (`:228-233`) and circular (`:280`) both set `visPhysics(enabled = FALSE)`,
  so nodes already stay where dropped and `fixed` changes nothing. The hint sits outside
  the layout selector.

- [ ] **M4. No formatter config committed.**
  No `air.toml`, `.air.toml` or styler config in the repo root. A reformat this size that
  is not pinned by a config will churn again the moment someone with different settings
  saves a file.

- [ ] **M5. `LICENSE` has a stray CR and no terminating newline.**
  `YEAR: 2026` then `COPYRIGHT HOLDER: Amelia Miramonti` with no final newline.
  `readLines()` warns `incomplete final line found`. `read.dcf` still parses correctly.
  `core.autocrlf = true` and no `.gitattributes`, so the CR normalises away on commit;
  the missing newline does not. `YEAR: 2026` was verified correct against the real date.

- [ ] **M6. `DESCRIPTION` identity is half-renamed.**
  `Authors@R` is still `person("Table Explorer", ...)` with no family name, while the email
  became `amelia.miramonti@gmail.com` and `LICENSE` now says `COPYRIGHT HOLDER: Amelia Miramonti`.
  Also missing `URL:` and `BugReports:` despite a known GitHub remote, and `RoxygenNote` (see I7).

- [ ] **M7. `inst/app/www/app.js:38` and `:44` call `Shiny.setInputValue` without a module namespace.**
  `remove_table_name` and `vis_close_panel` are sent unnamespaced while the consuming modules
  use `session$ns()`. Both have working server-generated inline `onclick` fallbacks, so the app
  functions and these handlers are simply dead. Delete rather than leave as a trap.

- [ ] **M8. `R/utils_db_connectors.R:122` - sqlite branch has no `requireNamespace()` guard.**
  Calls `DBI::dbConnect(RSQLite::SQLite(), ...)` unguarded, unlike the postgres/mysql/odbc/
  bigquery branches beside it (lines 39, 52, 65, 84, 99). `DBI` itself is unguarded throughout.
  Both are Suggests, so `R CMD check --as-cran` flags unconditional Suggests use, and the user
  gets a raw "no package called 'RSQLite'" instead of the friendly notification.

- [ ] **M9. `NAMESPACE` imports `golem::get_golem_options`, never called.**
  Drop from `R/tableexplorer-package.R:13`.

- [ ] **M10. `R/run_app.R:5` takes only `...`.**
  golem's template signature is `run_app(onStart, options, enableBookmarking, uiPattern, ...)`
  passed to `shinyApp()`. As written you cannot set a port, bookmarking or `onStart` without
  editing the function.

- [ ] **M11. `R/run_app.R:8-9` - `addResourcePath("tableexplorer", "")` on a missing package.**
  If `system.file()` returns `""`, this errors with a confusing message. `app_sys()` exists
  to wrap exactly this.

- [ ] **M12. Dead CSS rule.**
  `inst/app/www/styles.css:117` styles `#theme-toggle .toggle-icon`, but the
  `span(class = "toggle-icon", ...)` moon-icon element from `main`'s header was dropped in
  `R/app_ui.R:29-33`. Decide whether to restore the element or drop the rule.

- [ ] **M13. `.gitignore` is 3 lines and misses R artefacts.**
  Add `.Rhistory`, `.RData`, `.Rproj.user`, `*.Rcheck/`, `*.tar.gz`.

- [ ] **M14. `inst/app/www/styles.css` and `app.js` carry 4-6 spaces of leading indent.**
  Artefact of being lifted out of an R string literal. Cosmetic, but they read oddly as
  standalone assets.

- [ ] **M15. No `.github/workflows/`.**
  Nothing runs `R CMD check`, which is precisely why C1 and I6/I7/I8 went unnoticed.
  `usethis::use_github_action("check-standard")`.

- [ ] **M16. `tests/testthat/test-inference.R:468` is a vacuous test.**
  Named "detect_composite_pks skips columns with NAs in the combo", but its only expectation
  is inside `if (length(result) > 0)`, which is never entered - testthat reports it as
  "empty test". It covers exactly the C2 gap that is already failing four assertions.
  Fill it in once C2 is fixed.

- [ ] **M17. `tests/testthat/test-db_connectors.R:148` - `db_close` on an already-closed connection emits an unexpected warning.**
  Fifth of the five current failures.

- [ ] **M18. README "Sample data" section points at the repo root.**
  Update to `inst/extdata/sample_data/` when I10 is actioned.

---

## Pre-existing, not introduced by this branch

Confirmed present before the restructure. Logged so they are not rediscovered.

- [ ] **P1. SQL built by string interpolation in `R/utils_db_connectors.R`.**
  `:150-170`, `:186-218`, `:237-256` interpolate `schema` into `information_schema` queries
  with `'` quoting; `db_load_table` at `:313-330` interpolates `schema` and `table_name` into
  quoted and backticked identifiers. Should use `DBI::dbQuoteIdentifier` / `DBI::dbQuoteLiteral`.
  Exposure is limited - the schema comes from a text input supplied by the connecting user,
  who already holds the credentials - so this is closer to a robustness bug than privilege
  escalation. A schema named `O'Brien` breaks it.

- [ ] **P2. `db_load_table` SQL is not portable to SQL Server and fails silently.**
  `LIMIT` is not valid T-SQL, so both the primary query and the backtick fallback fail, and
  `error = function(e2) NULL` returns `NULL` with no user-visible reason.

- [ ] **P3. `read_access_db` re-downloads roughly 10 MB of UCanAccess JARs every session.**
  `R/utils_file_readers.R:446` targets `dirname(<uploaded .mdb>)/access_jars`, which under
  Shiny is a per-upload temp directory, with no cleanup. Presumably what the now-dead
  `access_jar_dir()` (I12) was meant to prevent.

- [ ] **P4. `readxl::read_excel()` is called on the raw path with no binary-copy workaround.**
  `R/utils_file_readers.R:121`. In the Shiny upload flow paths are tempfiles so this is
  usually safe, but it bites if `TEMP` contains a space or if `read_table_file` is called
  directly on a project path. The `jdbc:ucanaccess://` URL construction at `:459` has the same
  exposure. Known machine-level trap on this Windows setup.

---

## Decisions needed

- [ ] **D1. `inst/golem-config.yml`: wire it or delete it.**
  Either add a real `R/app_config.R` (golem's `app_sys()` + `get_golem_config()`), fix
  `app_version` to `golem_version`, and add the `dev:` block - or remove the file so it stops
  implying behaviour it does not have. Wiring it is the prerequisite for reading
  `shiny.maxRequestSize` from config (C3). Blocks I5.

- [ ] **D2. ERD node pinning: what should the feature actually be?**
  Server round-trip of positions, `visNetworkProxy` so the network is never rebuilt, or drop
  the pin/unpin gesture. Determines I2 and I3.

- [ ] **D3. `app.R`: revert to golem's template?**
  Recommended by both reviewers B and C:

  ```r
  pkgload::load_all(export_all = FALSE, helpers = FALSE, attach_testthat = FALSE)
  options("golem.app.prod" = TRUE)
  tableexplorer::run_app()
  ```

  Resolves C4 and I13 together. The alternative is keeping the block and fixing the guard with
  `tryCatch(sys.frame(1L)$ofile, error = function(e) NULL)`, but the block buys nothing shiny's
  own `setwd(appDir)` does not already provide.

- [ ] **D4. Delete the legacy root files?**
  `inference.R`, `file_readers.R`, `export_utils.R`, `db_connectors.R`, `sample_data/`,
  `schema.json`. Confirmed dead duplicates. Keep `app.py` and `requirements.txt`. Best done in
  the same change as the uncommitted work so the duplicate edit to `file_readers.R` never lands.
  Blocks I10 and M18.

- [ ] **D5. `access_jar_dir()`: wire it into `read_access_db` or delete it?**
  Wiring it would also fix P3. Leaving it is what attracted the pointless edit in I12.

- [ ] **D6. Split the uncommitted work into two commits?**
  Both AST-verifying reviewers recommend it: one mechanical reflow commit (a verified no-op,
  and a good `.git-blame-ignore-revs` candidate) and one commit for the ~73 semantic lines.
  As it stands the real defects are hidden in ~1730 lines of noise and `git blame` on
  `R/mod_erd.R` will point at "reformat" indefinitely. Pair with M4 so the style is reproducible.

- [ ] **D7. Mirror this backlog to GitHub issues?**
  Remote is `https://github.com/amelia-m/table-explorer.git`. The GitHub MCP server failed to
  connect this session (`AUTH_HEADER_REJECTED`, HTTP 401), so this would need `gh` or a fixed
  token, and it is an outward-facing action requiring explicit approval.

---

## Verified clean - no action

Recorded so these are not re-litigated.

**The reformat itself is safe.** AST-verified identical across all six `R/utils_*.R` files and
`tests/testthat/setup.R`, and token-verified with braces stripped across the eight reflow-only
module files. No dropped branch, no reordered argument, no `else` swallowed by a reflowed `if`,
no `==`/`identical` swap, no NA-handling change, no FK scoring or threshold change. The `switch`
arm reflow in `R/utils_file_readers.R:41-64` and `R/utils_db_connectors.R:143-170` correctly
preserves fall-through arms, which is the most common way an automated R reformat breaks
silently. `%||%` in `R/utils_helpers.R` kept its non-obvious empty-string-is-falsy semantics.

**Module decomposition.** `R/app_server.R` owns all shared `reactiveVal`s and the `fk_cache` env
and passes them down; modules return only what the parent needs. No module reaches into another's
namespace. `mod_detection_server` still returns the six members `app_server.R` consumes;
`mod_upload_server` still returns `manual_rels_rv`. The README's reactive-flow diagram matches
the code.

**Namespacing.** `NS(id)` in every UI, `session$ns()` in every `renderUI`, dynamic `DTOutput` /
`downloadHandler` id, `sprintf`-built `onclick`, and modal footer button.
`R/mod_table_details.R:75` and `R/mod_upload.R:660` are the fiddly cases and both are correct.

**Asset extraction is byte-perfect.** `inst/app/www/styles.css` diffs to zero lines against
`main`'s inline `tags$style(HTML(...))` block (`app.R:279-623`) and `inst/app/www/app.js` diffs to
zero against the inline `tags$script` block (`app.R:627-671`). Assets are live, not dead:
`R/run_app.R:7-10` registers `addResourcePath` before `shinyApp()` is constructed and
`R/app_ui.R:12-18` references both files.

**`NAMESPACE` is consistent with the roxygen tags.** Every `importFrom` traces to a tag in
`R/tableexplorer-package.R`; `export(run_app)` matches the single `@export`. `DT::DTOutput` /
`renderDT` are imported specifically rather than `dataTableOutput`, correctly avoiding the
shiny/DT name clash.

**`Suggests` discipline.** All 17 optional packages are declared and actually referenced via `::`
in `R/`; every `::`-referenced third-party package is declared. 19 `requireNamespace()` guards
across the optional format and DB paths. Nothing declared-but-unused.

**`Depends: R (>= 4.1.0)` is correct** - the native pipe is used 17 times.

**Repo slug.** README's `remotes::install_github("amelia-m/table-explorer")` matches `origin`.
The hyphen fix in 268efb9 is right. (Commit 704fe6e's `Agent-Logs-Url` trailer says
`table_explorer` with an underscore; the remote is authoritative.)

**No credential leakage.** `R/mod_db_connect.R:131` passes `input$db_pass` straight to
`db_connect` and does not store it. Nothing logs it. Connections use `on.exit` for
`dbDisconnect` / `odbcClose` (`R/utils_file_readers.R:472`, `:520`).

**No injection surface added.** No new `eval` or `parse` of user input, no upload path handling
touched, no `file.copy()` anywhere in `R/` so the silent-failure trap on spaced Windows paths does
not apply.

**Export writes are safe.** All five `write.csv` / `writeLines` calls in `R/mod_export.R`,
`mod_name_changes.R`, `mod_relationships.R`, `mod_table_details.R` write to the `file` argument
supplied by a Shiny `downloadHandler`, a framework-managed temp path. No risk of overwriting user
files.

**`tests/testthat/setup.R` still matches what the code exposes.** Both branches were exercised:
the pkgload branch, and the legacy source-fallback branch that sources the five `R/utils_*.R`
files. Both resolve and run.

**All 18 files in `R/` parse cleanly.** Line endings unchanged (LF, no CRLF churn). No test
references any changed string. `devtools::load_all()` would statically succeed - the 21
"no visible global function" hits from `codetools::checkUsageEnv` are all `visNetwork` /
`shinythemes` names, properly declared in `NAMESPACE` and unresolvable only because those
packages are absent from the review machine.

**Test-suite status is unchanged by the uncommitted diff** - 5 failures and 6 skips at both HEAD
and working tree. `main` itself passes clean; the failures arrive with this branch (C2, M16, M17).
