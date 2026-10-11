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

## Re-checked against `main`, 2026-10-10

Every open item above was re-read against `main` at `c11748b`. Individual
items carry the result; the three things that change how the list should be
read are here.

**golem is still in.** The review branch's golem findings are live, not
historical. `R/run_app.R:11` calls `golem::with_golem_options()`,
`R/tableexplorer-package.R:13` imports from golem, `NAMESPACE:12-14` and
`DESCRIPTION:22` declare it, and `inst/golem-config.yml` is still present. The
work that removes golem is on the unmerged `drop-golem` branch
(`git merge-base --is-ancestor drop-golem main` fails). So I5, I13, M9, M10,
M11, D1 and D3 all still apply; do not close them on the strength of a
changelog entry.

**The visNetwork ERD moved.** The ERD Diagram tab is now an elkjs/SVG renderer
(`inst/app/www/erd.js`, loaded at `R/app_ui.R:19-21`) and `R/mod_erd.R`
contains no visNetwork at all. The pinning, layout and hint findings raised
against `R/mod_erd.R` now live in `R/mod_network.R`, behind the Network
overview tab. Their file and line references have been corrected in place;
I2, M2 and M3 are still real, I4 was fixed by the split.

**The test suite passes.** `testthat::test_local()` on 2026-10-10: no
failures, four skips. Three are optional-package skips, and two of those skip
because the package is *present* (readxl and haven, whose tests cover the
notification shown when they are missing); mdbtools is genuinely absent. The
fourth is M16's empty test. The "5 failures" in *Verified clean* below was
true of the review branch and is no longer true of `main`.

Resolved since the review: I4, I12, M17, P3, and D5 answered by the code.
Facts changed but still open: I6, I7, I10, M1, M2, M5, M6, M13, D4, D6.
Not re-checked: M18, which is about `README.md`.

---

## Critical

- [ ] **C1. `tests/testthat.R:5` runs zero tests under `R CMD check`.**
  Uses `test_package("tableexplorer")`, whose body returns early unless the package
  was installed with `--install-tests`. `tools:::.check_packages` contains zero
  references to `install-tests`, so `R CMD check` never passes it. The suite prints
  an informational line and passes green having executed nothing. Invisible locally
  because `devtools::test()` bypasses `testthat.R` entirely.
  **Fix:** `test_check("tableexplorer")`.
  Re-checked 2026-10-10: unchanged. `tests/testthat.R:5` still reads
  `test_package("tableexplorer")`.

- [x] **C2. `R/utils_inference.R:468` makes composite-PK detection inert on exactly the tables it exists for.**
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
  Done 2026-09-16, differently: `method = "uniqueness"` alone still skips both test fixtures,
  because `quantity` and `d` are unique on their own. The guard now skips only when a column
  is both PK-named and unique, and columns that are unique on their own are excluded from the
  combo search (otherwise `a + d` is returned before `a + b + c`). All tests pass.

- [ ] **C3. `options(shiny.maxRequestSize)` was dropped in the restructure.**
  `main`'s `app.R:14` set `shiny.maxRequestSize = Inf`. On this branch the value
  exists only at `inst/golem-config.yml:6` (104857600), which nothing reads (see I5).
  `grep -rn "options(" R/ app.R` returns nothing. Uploads silently revert to Shiny's
  5 MB default, breaking the app's primary workflow.
  **Fix:** set it in `run_app()` or `onStart`, ideally reading from config once I5 is resolved.
  Re-checked 2026-10-10: unchanged. `grep -rn maxRequestSize R/ app.R` finds nothing; the
  value still exists only at `inst/golem-config.yml:6`, which nothing reads.

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
  Re-checked 2026-10-10: unchanged. `app.R:13` still guards on `sys.frame(1L)$ofile`, and
  `app.R:1` still describes the app as launched "via the golem package", which is
  still accurate (see the re-check section).

---

## Important

### ERD module (reviewer A)

- [x] **I1. `R/mod_erd.R:219-222` and `:292-295` - copy-pasted `else` branch that cannot work.**
  The branch sets `Shiny.setInputValue` with `id: params.nodes[0]` and calls
  `showNodePanel(params.nodes[0])`, but it runs precisely when `params.nodes.length == 0`,
  so `params.nodes[0]` is `undefined`. Lifted verbatim from the `click` handler, where the
  guard is inverted. Every empty double-click sets `input$vis_clicked_node` to `{ts: ...}`
  with `id` dropped by JSON serialization, waking the `observeEvent` at `R/mod_erd.R:333`
  for a `req()` that immediately stops it, and calls `showNodePanel(undefined)` which no-ops.
  Harmless today, but reads as intentional.
  **Fix:** delete the `else`, or make it close the panel via `vis_close_panel`.
  Done 2026-09-16: `else` deleted from both `doubleClick` handlers, which no longer need
  `sprintf`.

- [ ] **I2. `R/mod_network.R:212-232` - pinned node positions do not survive any re-render.**
  `dragEnd` writes `fixed: {x: true, y: true}` into the client-side vis DataSet only.
  `renderVisNetwork` depends on `all_tables_rv()`, `all_rels_rv()`, `pk_map_rv()`,
  `composite_pk_map_rv()`, `input$erd_layout` and `input$spring_length`. Suppressing a
  relationship, adding a manual relationship, changing detection method, or nudging the
  Spring length slider rebuilds the network and discards every pin. The slider is worst:
  it fires continuously while dragging, so a full rebuild per tick.
  **Fix:** round-trip positions to the server (a `reactiveVal` keyed by node id, written
  from `dragEnd`, read back into `net$nodes$x/y/fixed` in `build_network`), or move the
  mutable parts to `visNetworkProxy` so the network is never rebuilt. See D2.
  Re-checked 2026-10-10: still true, and the file reference above has been corrected from
  `R/mod_erd.R` to `R/mod_network.R`, where this code now lives. `renderVisNetwork` at
  `R/mod_network.R:163` still depends on `all_tables_rv()`, `all_rels_rv()`,
  `pk_map_rv()`, `composite_pk_map_rv()`, `input$erd_layout` and `input$spring_length`,
  and `dragEnd` at `:212-232` still writes `fixed` into the client DataSet only. It is
  the Network overview tab that is affected now, not the ERD Diagram tab.

- [x] **I3. `R/mod_erd.R:211-226` - double-click also fires `click`, so unpinning opens the detail panel.**
  vis-network emits `click` for each click of a double-click, and the `click` handler at
  `:190-197` calls `showNodePanel`. The new unpin gesture pops the node overlay as a side
  effect.
  **Fix:** short suppression timer in the click handler, or document the behaviour in the hint.
  Done 2026-09-16: `click` now defers the panel by 250 ms, and `doubleClick` cancels the pending
  timer. Single clicks open the panel 250 ms later than before.

- [x] **I4. `R/mod_erd.R:186-226` vs `:255-299` - visNetwork chain and both JS blobs duplicated for the circular branch.**
  The circular layout rebuilds `vis` from scratch, so the two ~25-line JS strings exist
  twice, byte-identical apart from indentation. Direct cause of I1 appearing twice.
  **Fix:** hoist the JS into two local character variables, build the base chain once, and
  apply `visPhysics(enabled = FALSE)` plus the precomputed `x`/`y` as a modifier. The
  circular branch already computes `net$nodes$x/y` before the rebuild, so nothing forces
  the duplication.
  Done, found fixed 2026-10-10 in `R/mod_network.R` (the code moved there; see the
  re-check section). The chain is built once and the circular branch adds
  `visPhysics(enabled = FALSE)` as a modifier at `:243-244`, which is the fix proposed
  above. There is one `dragEnd` JS blob, at `:212`, not two.

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
  Re-checked 2026-10-10: unchanged and still live. `inst/golem-config.yml` is present, there
  is still no `R/app_config.R`, and `get_golem_options` is imported at `NAMESPACE:13`
  without a single call in `R/`.

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
  Re-checked 2026-10-10: partly resolved, so the heading above now overstates it. A
  `.Rbuildignore` exists, but holds only `^renv$`, `^renv\.lock$` and
  `^requirements\.txt$`. Everything else in the list above - `app.R`, `app.py`,
  `dev/`, `tmp/`, `.claude/`, `sample_data/`, `schema.json` and the four legacy root
  `.R` files - is still bundled by `R CMD build`.

- [ ] **I7. No `man/` directory - `R CMD check` WARNING.**
  `run_app` is exported with roxygen docs but no `.Rd` was generated or committed, and
  there is no `man/tableexplorer-package.Rd` for the `"_PACKAGE"` block. Produces
  `WARNING: Undocumented code objects: 'run_app'`. `DESCRIPTION` has no `RoxygenNote`
  field, corroborating that `NAMESPACE` was hand-written.
  **Fix:** `devtools::document()`, commit `man/`.
  Re-checked 2026-10-10: `man/` is still absent, so the WARNING stands. One supporting
  detail no longer holds: `DESCRIPTION` now carries `Config/roxygen2/version: 8.1.0`,
  which is where roxygen2 8.x records what `RoxygenNote` used to, so that field's
  absence is no longer evidence of a hand-written `NAMESPACE`.

- [x] **I8. `stats`, `utils` and `tools` are used but undeclared.**
  13 `tools::` calls and 1 `utils::` in `R/utils_file_readers.R` with neither in `Imports`
  gives NOTE `'::' or ':::' import not declared`. Plus 43 unqualified calls to `setNames`,
  `head`, `median`, `sd`, `var`, `cor`, `na.omit`, `read.csv`, `write.csv` across 9 files
  (`R/utils_inference.R` x16, `R/utils_file_readers.R` x10, `R/app_server.R` x4,
  `R/mod_table_details.R` x4, `R/mod_relationships.R` x3, `R/mod_detection.R` x3, plus
  `R/mod_name_changes.R`, `R/utils_export.R`, `R/utils_vis.R`), giving
  `no visible global function definition` NOTEs.
  **Fix:** add `stats`, `utils`, `tools` to `Imports` with matching `@importFrom` tags.
  Done 2026-09-16: `stats`, `tools` and `utils` added to `Imports`. `@importFrom` tags in
  `R/tableexplorer-package.R` cover the 47 unqualified calls found by a parse-data scan
  (stats: `cor`, `median`, `na.omit`, `sd`, `setNames`; utils: `head`, `object.size`,
  `read.csv`, `read.delim`, `write.csv`). `NAMESPACE` regenerated with roxygen2 8.1.0.

- [x] **I9. `pkgload` is used but declared nowhere in `DESCRIPTION`.**
  Referenced by `app.R:18` and `dev/02_dev.R:7`. Add to `Suggests`.
  Done 2026-09-16: added to `Suggests`.

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
  Re-checked 2026-10-10: still open, but the "dead duplicates" premise no longer holds and
  deleting them blind would now lose data.

  - The four root `.R` files have diverged, not drifted: `inference.R` is 611 lines
    against `R/utils_inference.R`'s 1435, `file_readers.R` 492 against 883,
    `export_utils.R` 166 against 1293, `db_connectors.R` 284 against 353. They are
    stale copies, not formatting variants, so no diff of them is worth reading.
  - `sample_data/` at the root holds seven CSVs; `inst/extdata/sample_data/` holds
    four. The four in common are identical CR-normalised, but
    `customer_addresses.csv`, `product_suppliers.csv` and `suppliers.csv` exist only
    at the root, and `dev/browser-checks/sample_app.R` loads the root copy.
  - Root `schema.json` and `inst/extdata/schema.json` now differ.

  So D4 is no longer "delete the duplicates": the extra fixtures have to be moved or
  dropped deliberately first.

- [ ] **I11. `dev/` scripts have uncommented side-effecting lines.**
  `dev/01_start.R:18` has `usethis::use_mit_license()` uncommented while everything around
  it is commented out. Sourcing that file overwrites `LICENSE` and rewrites the `License:`
  field - it would clobber the working tree's `YEAR: 2026 / COPYRIGHT HOLDER: Amelia Miramonti`.
  `dev/02_dev.R:7,17,20` have `pkgload::load_all()`, `devtools::document()` and
  `devtools::test()` uncommented, so sourcing regenerates `NAMESPACE` and runs the suite.
  **Fix:** comment these out, matching the "run interactively" instruction in the headers.
  Re-checked 2026-10-10: unchanged. `dev/01_start.R:18` still has an uncommented
  `usethis::use_mit_license()`, and `dev/02_dev.R:7,17,20` are still uncommented.

### Utils (reviewer B)

- [x] **I12. Both renamed cache keys are in unreachable code, so the rename is a no-op.**
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
  Done, found fixed 2026-10-10. `access_jar_dir()` is now at
  `R/utils_file_readers.R:587` and returns
  `file.path(tools::R_user_dir("tableexplorer", "cache"), "access_jars")` - one key, not
  two - and it has callers: `read_access_db()` at `:776` and
  `access_relationship_rows_jackcess()` at `:724`. The `sys.frame(1)` idiom is gone, and
  so is the unreachable `tryCatch` rename. This also closes P3 and answers D5.

- [ ] **I13. `app.R` is missing `options("golem.app.prod" = TRUE)`.**
  The rest of the file matches golem's generated deployment template. Inert today since
  nothing reads `golem.app.prod`, but one line now prevents a future `golem::app_prod()`
  guard silently behaving as dev in production.
  Re-checked 2026-10-10: unchanged and still live, because golem is still a dependency.

---

## Minor

- [ ] **M1. `R/mod_export.R:99` - user-visible filename change riding inside a 1100-line reflow.**
  Session download prefix `table_explorer_session_` to `table-explorer-session-`. Nothing
  consumes it (`restore_session_json` accepts any `.json`, no test asserts the name), so
  it is safe, but it should not be buried in a formatting commit.
  Re-checked 2026-10-10: overtaken. The rename shipped - `R/mod_export.R:202` builds
  `table-explorer-session-` - and nothing consumes it, as the finding said. The
  process complaint cannot be acted on retrospectively; nothing to do but close it.

- [ ] **M2. `R/mod_network.R:110` - hint text under-describes the widget.**
  Dropped "hover for details" and "click to highlight connections" though
  `visInteraction(tooltipDelay = 80, hover = TRUE)` and `visOptions(highlightNearest = ...)`
  are still enabled in every branch. Those capabilities are now undiscoverable.
  Re-checked 2026-10-10: partly addressed, and the reference above has been corrected to
  `R/mod_network.R`. The hint at `:110` now reads "drag to pin nodes - double-click to
  unpin - scroll to zoom - click for details", so click-for-details is back. Still
  undescribed: the hover tooltips (`visInteraction(tooltipDelay = 80, hover = TRUE)` at
  `:194-195`) and highlight-on-hover (`highlightNearest(..., hover = TRUE)` at `:187`).

- [ ] **M3. `R/mod_network.R:104-111` - pin hint shown unconditionally but meaningless in two of three layouts.**
  Hierarchical (`:228-233`) and circular (`:280`) both set `visPhysics(enabled = FALSE)`,
  so nodes already stay where dropped and `fixed` changes nothing. The hint sits outside
  the layout selector.
  Re-checked 2026-10-10: unchanged, reference corrected to `R/mod_network.R`. Hierarchical
  at `:236-242` and circular at `:243-244` both set `visPhysics(enabled = FALSE)`, and
  the hint at `:104-111` still sits outside the layout selector at `:84-90`.

- [ ] **M4. No formatter config committed.**
  No `air.toml`, `.air.toml` or styler config in the repo root. A reformat this size that
  is not pinned by a config will churn again the moment someone with different settings
  saves a file.
  Re-checked 2026-10-10: unchanged. No `air.toml`, `.air.toml` or `.lintr` at the root.

- [ ] **M5. `LICENSE` has a stray CR and no terminating newline.**
  `YEAR: 2026` then `COPYRIGHT HOLDER: Amelia Miramonti` with no final newline.
  `readLines()` warns `incomplete final line found`. `read.dcf` still parses correctly.
  `core.autocrlf = true` and no `.gitattributes`, so the CR normalises away on commit;
  the missing newline does not. `YEAR: 2026` was verified correct against the real date.
  Re-checked 2026-10-10: the newline is still missing (`cat -A LICENSE` ends without a `$`),
  but two of the premises have changed: there is now a committed `.gitattributes`
  pinning `* text=auto eol=lf`, and the working-tree CR is gone.

- [ ] **M6. `DESCRIPTION` identity is half-renamed.**
  `Authors@R` is still `person("Table Explorer", ...)` with no family name, while the email
  became `amelia.miramonti@gmail.com` and `LICENSE` now says `COPYRIGHT HOLDER: Amelia Miramonti`.
  Also missing `URL:` and `BugReports:` despite a known GitHub remote, and `RoxygenNote` (see I7).
  Re-checked 2026-10-10: `Authors@R` is still `person("Table Explorer", ...)` with no family
  name, and there is still no `URL:` or `BugReports:`. The `RoxygenNote` part is
  answered: `Config/roxygen2/version: 8.1.0` is present (see I7).

- [ ] **M7. `inst/app/www/app.js:14` and `:41` call `Shiny.setInputValue` without a module namespace.**
  `remove_table_name` and `vis_close_panel` are sent unnamespaced while the consuming modules
  use `session$ns()`. Both have working server-generated inline `onclick` fallbacks, so the app
  functions and these handlers are simply dead. Delete rather than leave as a trap.
  Re-checked 2026-10-10: unchanged; the line numbers above have been corrected from `:38`
  and `:44` to `:14` and `:41`.

- [ ] **M8. `R/utils_db_connectors.R:122` - sqlite branch has no `requireNamespace()` guard.**
  Calls `DBI::dbConnect(RSQLite::SQLite(), ...)` unguarded, unlike the postgres/mysql/odbc/
  bigquery branches beside it (lines 39, 52, 65, 84, 99). `DBI` itself is unguarded throughout.
  Both are Suggests, so `R CMD check --as-cran` flags unconditional Suggests use, and the user
  gets a raw "no package called 'RSQLite'" instead of the friendly notification.
  Re-checked 2026-10-10: unchanged. `R/utils_db_connectors.R:122` still calls
  `DBI::dbConnect(RSQLite::SQLite(), ...)` with no guard.

- [ ] **M9. `NAMESPACE` imports `golem::get_golem_options`, never called.**
  Drop from `R/tableexplorer-package.R:13`.
  Re-checked 2026-10-10: unchanged and still live. `NAMESPACE:13` imports it; no call in `R/`.

- [ ] **M10. `R/run_app.R:5` takes only `...`.**
  golem's template signature is `run_app(onStart, options, enableBookmarking, uiPattern, ...)`
  passed to `shinyApp()`. As written you cannot set a port, bookmarking or `onStart` without
  editing the function.
  Re-checked 2026-10-10: unchanged. `R/run_app.R:5` is still `run_app <- function(...)`.

- [ ] **M11. `R/run_app.R:8-9` - `addResourcePath("tableexplorer", "")` on a missing package.**
  If `system.file()` returns `""`, this errors with a confusing message. `app_sys()` exists
  to wrap exactly this.
  Re-checked 2026-10-10: unchanged. `R/run_app.R:7-10` still calls `addResourcePath()` on a
  bare `system.file()` result.

- [ ] **M12. Dead CSS rule.**
  `inst/app/www/styles.css:117` styles `#theme-toggle .toggle-icon`, but the
  `span(class = "toggle-icon", ...)` moon-icon element from `main`'s header was dropped in
  `R/app_ui.R:29-33`. Decide whether to restore the element or drop the rule.
  Re-checked 2026-10-10: unchanged; the rule has moved to `inst/app/www/styles.css:149` and
  `R/app_ui.R:33-37` still builds only `.toggle-track`, `.toggle-thumb` and
  `#toggle-label`.

- [ ] **M13. `.gitignore` is 3 lines and misses R artefacts.**
  Add `.Rhistory`, `.RData`, `.Rproj.user`, `*.Rcheck/`, `*.tar.gz`.
  Re-checked 2026-10-10: still open, four lines now rather than three (`tmp/`, `/venv`,
  `.claude/settings.local.json`, `_scratch/`). None of the five R artefacts above has
  been added.

- [ ] **M14. `inst/app/www/styles.css` and `app.js` carry 4-6 spaces of leading indent.**
  Artefact of being lifted out of an R string literal. Cosmetic, but they read oddly as
  standalone assets.
  Re-checked 2026-10-10: unchanged. `inst/app/www/styles.css:1` still begins with four spaces.

- [ ] **M15. No `.github/workflows/`.**
  Nothing runs `R CMD check`, which is precisely why C1 and I6/I7/I8 went unnoticed.
  `usethis::use_github_action("check-standard")`.
  Re-checked 2026-10-10: unchanged. There is no `.github/workflows/`. `TODO.md` tracks
  pulling the workflow out of draft PR #6.

- [ ] **M16. `tests/testthat/test-inference.R:468` is a vacuous test.**
  Named "detect_composite_pks skips columns with NAs in the combo", but its only expectation
  is inside `if (length(result) > 0)`, which is never entered - testthat reports it as
  "empty test". It covers exactly the C2 gap that is already failing four assertions.
  Fill it in once C2 is fixed.
  Re-checked 2026-10-10: still vacuous, and now unblocked. `testthat::test_local()` on
  2026-10-10 reports `detect_composite_pks skips columns with NAs in the combo
  ('test-inference.R:468:1') - Reason: empty test`. C2 is done, so the condition this
  item was waiting on is satisfied.

- [x] **M17. `tests/testthat/test-db_connectors.R:148` - `db_close` on an already-closed connection emits an unexpected warning.**
  Fifth of the five current failures.
  Done, found fixed 2026-10-10 by commit bf1823e, "Fix db_close on closed connections
  and a stale lookup-table cache". `testthat::test_local()` reports no failures.

- [ ] **M18. README "Sample data" section points at the repo root.**
  Update to `inst/extdata/sample_data/` when I10 is actioned.
  Not re-checked on 2026-10-10: `README.md` was outside this pass's file list
  (a parallel agent owned it), so whether the section still points at the repo root is
  unverified. Reading the "Sample data" section of `README.md` would settle it. Note
  that I10's re-check changes what the right target is: the root `sample_data/` has
  three CSVs that `inst/extdata/sample_data/` does not.

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
  Re-checked 2026-10-10: unchanged. No `dbQuoteIdentifier` or `dbQuoteLiteral` anywhere in
  `R/utils_db_connectors.R`. The interpolation sites are now `:147-163`, `:188-225`
  and `:245-262`, with `db_load_table` at `:319-330`.

- [ ] **P2. `db_load_table` SQL is not portable to SQL Server and fails silently.**
  `LIMIT` is not valid T-SQL, so both the primary query and the backtick fallback fail, and
  `error = function(e2) NULL` returns `NULL` with no user-visible reason.
  Re-checked 2026-10-10: unchanged. `LIMIT` is still interpolated at
  `R/utils_db_connectors.R:319`, `:321` and `:330`.

- [x] **P3. `read_access_db` re-downloads roughly 10 MB of UCanAccess JARs every session.**
  `R/utils_file_readers.R:446` targets `dirname(<uploaded .mdb>)/access_jars`, which under
  Shiny is a per-upload temp directory, with no cleanup. Presumably what the now-dead
  `access_jar_dir()` (I12) was meant to prevent.
  Done, found fixed 2026-10-10. The jars now go to the persistent per-user
  cache `tools::R_user_dir("tableexplorer", "cache")/access_jars`, not beside the
  upload: `R/utils_file_readers.R:585-589` says so in a comment and `read_access_db()`
  uses it at `:776`. Same change as I12.

- [ ] **P4. `readxl::read_excel()` is called on the raw path with no binary-copy workaround.**
  `R/utils_file_readers.R:121`. In the Shiny upload flow paths are tempfiles so this is
  usually safe, but it bites if `TEMP` contains a space or if `read_table_file` is called
  directly on a project path. The `jdbc:ucanaccess://` URL construction at `:459` has the same
  exposure. Known machine-level trap on this Windows setup.
  Re-checked 2026-10-10: unchanged; the call has moved to `R/utils_file_readers.R:128`.

---

## Decisions needed

- [ ] **D1. `inst/golem-config.yml`: wire it or delete it.**
  Either add a real `R/app_config.R` (golem's `app_sys()` + `get_golem_config()`), fix
  `app_version` to `golem_version`, and add the `dev:` block - or remove the file so it stops
  implying behaviour it does not have. Wiring it is the prerequisite for reading
  `shiny.maxRequestSize` from config (C3). Blocks I5.
  Re-checked 2026-10-10: still to decide, and still live - golem has not been removed.

- [ ] **D2. ERD node pinning: what should the feature actually be?**
  Server round-trip of positions, `visNetworkProxy` so the network is never rebuilt, or drop
  the pin/unpin gesture. Determines I2 and I3.
  Re-checked 2026-10-10: still to decide. Now a question about the Network overview tab
  only: the ERD Diagram tab no longer uses visNetwork and has no pinning.

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
  Re-checked 2026-10-10: still to decide, and still applicable as written, because golem is
  still a dependency.

- [ ] **D4. Delete the legacy root files?**
  `inference.R`, `file_readers.R`, `export_utils.R`, `db_connectors.R`, `sample_data/`,
  `schema.json`. Confirmed dead duplicates. Keep `app.py` and `requirements.txt`. Best done in
  the same change as the uncommitted work so the duplicate edit to `file_readers.R` never lands.
  Blocks I10 and M18.
  Re-checked 2026-10-10: the decision has changed shape. They are no longer "confirmed dead
  duplicates" (see I10): the root `sample_data/` holds three CSVs that
  `inst/extdata/sample_data/` does not, `dev/browser-checks/sample_app.R` reads the
  root copy, and the two `schema.json` files differ. The four root `.R` files are
  simply stale and can go. This needs Amelia: move the extra fixtures into
  `inst/extdata/` first, or keep `sample_data/` as the browser-check input.

- [x] **D5. `access_jar_dir()`: wire it into `read_access_db` or delete it?**
  Wiring it would also fix P3. Leaving it is what attracted the pointless edit in I12.
  Answered 2026-10-10 by the code, not by a decision here: it was wired in. `read_access_db()`
  calls it at `R/utils_file_readers.R:776` and `access_relationship_rows_jackcess()` at
  `:724`, and it now points at the persistent per-user cache. See I12 and P3.

- [ ] **D6. Split the uncommitted work into two commits?**
  Both AST-verifying reviewers recommend it: one mechanical reflow commit (a verified no-op,
  and a good `.git-blame-ignore-revs` candidate) and one commit for the ~73 semantic lines.
  As it stands the real defects are hidden in ~1730 lines of noise and `git blame` on
  `R/mod_erd.R` will point at "reformat" indefinitely. Pair with M4 so the style is reproducible.
  Re-checked 2026-10-10: overtaken. That branch's work is long since in history, so the
  split can no longer be made. M4 (no formatter config) is the part still open.

- [ ] **D7. Mirror this backlog to GitHub issues?**
  The remote is the repository's `origin` on GitHub (see `git remote -v`; the URL is
  deliberately not written here). The GitHub MCP server failed to connect this session
  (`AUTH_HEADER_REJECTED`, HTTP 401), so this would need `gh` or a fixed token, and it
  is an outward-facing action requiring explicit approval.
  Re-checked 2026-10-10: still to decide. The GitHub MCP server is still failing to
  connect (HTTP 400, badly formatted Authorization header).

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
Re-checked 2026-10-10: no longer the state of `main`. `testthat::test_local()` reports no
failures and four skips - three for absent optional packages (readxl and haven present
so their "notifies when missing" tests skip, mdbtools absent) and one for M16's empty
test. C2 and M17 are fixed; M16 is still empty.
