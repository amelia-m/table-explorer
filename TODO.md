# TODO

- [x] Add a "Hide empty tables" toggle (0-row tables) to the sidebar that filters
      them out of the ERD, Table Details, and Relationships views.
- [ ] (Maybe later) User-defined naming patterns for FK detection: a settings
      box for lookup-table prefix (e.g. `tlk_`), lookup key column (e.g. `id`)
      and FK template (e.g. `{entity}_id`), saved with the session. Built-in
      conventions (Access, Rails/Django, SQL Server, warehouse `_key`/`_sk`,
      code lookups, role prefixes) are detected automatically already.

- [ ] ERD redesign: see `docs/erd-redesign-plan.md` (done: model, exports,
      ERD Diagram tab, data dictionary, dbt constraints; next: session diff,
      lints).
- [x] Detection noise on Access-style schemas (lookups sharing ids 1..N):
      names now choose between parents that values can't tell apart, and
      Access files' declared relationships are read.
- [ ] (Maybe later) Read Access lookup-field `RowSource` queries as a second
      declared source (the Lookup Wizard already stores a relationship).
- [ ] (Maybe later) ERD, large schemas: **use the width**. ELK layer
      wrapping (`elk.layered.wrapping.strategy = MULTI_EDGE`) with
      `elk.aspectRatio` from the canvas, so hub-and-spoke schemas aren't one
      tall column.
- [ ] (Maybe later) Validate exported data-dict YAML with the data-dict
      command-line tool (`datadict::dd_validate_data()`, Suggests only). It
      downloads a binary at run time and validates Parquet files only, and
      the spec is pre-1.0 (0.1.0), so it stays optional. The export is
      checked against the spec's rules by hand for now.
- [ ] Lints / data-quality panel (Phase 4 in `docs/erd-redesign-plan.md`):
      tables without a PK, orphan tables, FKs whose values are missing from
      the parent (share of orphaned rows), nullable PK-like columns, and
      duplicate links into the same parent.
- [ ] (Maybe later) ERD, large schemas: **open focused**. With more than 40
      tables, start focused on the most-connected table with 2 hops instead
      of drawing everything.

## Follow-ups from the data dictionary work (PR #20)

Found in review, not fixed there. How the pieces work: `docs/internals.md`.

- [ ] "Hide empty tables" also hides tables imported from a schema or
      data-dict file (they have no rows), so their labels and descriptions
      vanish from the Data Dictionary tab and its downloads while it's on.
      Consider exempting tables that came from a schema import.
- [ ] A manual link identical to a declared one shows twice in the app
      (`combine_relationships()` in `R/utils_helpers.R` only folds detected
      links into declared ones). The data-dict export already de-duplicates.
- [ ] "Not personal" reviews re-ask after any data refresh, because they are
      tied to a hash of the column. Safe, but noisy for regularly refreshed
      data; a name-based review could survive refreshes if the column's
      value pattern doesn't change.
- [ ] The automatic personal-data guess still flags generic `name` columns
      on non-person tables (`products.name`). The review clears them; a
      table-name heuristic (people-like tables) could cut the noise.
- [ ] A data-dict re-import loses `number(id)` on foreign keys whose links
      were unconfirmed (they're under `todo`, not `relationships`), and all
      examples (no rows). Expected, but worth a note if round trips matter.

## Repository housekeeping (logged 2026-09-30)

Baseline: on `main` at `6276a1e`, with the real packages (R 4.6.1),
`testthat::test_local()` gives 209 tests, 1035 expectations, 0 failed, 0
errors and 4 expected skips. `Rscript dev/fixtures/score_detection.R` gives
157 of 157 real links at medium+, 0 false.

- [ ] **Framework research (on hold until Amelia dispatches it).** The
      contract for three research agents is in
      `docs/research/shiny-framework/contract.md`:
      - leprechaun;
      - golem, rhino, a plain package and plain `app.R`;
      - shipping as an R package or a Positron extension, and Shiny for
        Python structure.

      The outcome decides whether golem stays, and with it backlog decision
      D1 in `dev/code-review-backlog.md` (wire `inst/golem-config.yml` or
      delete it). Until then `shiny.maxRequestSize` in that file is never
      applied, so uploads are capped at Shiny's 5 MB default (backlog C3).
- [ ] **Adopt renv? Decide after the framework research.** Nothing records
      a past decision for or against it. Proposal: `renv::init()` with an
      explicit snapshot, locking Imports plus the test essentials
      (testthat, pkgload, jsonlite, yaml, readxl, RSQLite), and leaving the
      database drivers (rJava, RJDBC, odbc, RODBC, bigrquery, RPostgres,
      RMariaDB) optional. Check how current renv treats Suggests before
      snapshotting. It also needs a `.Rbuildignore`, which the repo lacks
      (backlog I6), covering `renv/`, `renv.lock`, `_scratch/`, `dev/` and
      the Python files.
- [ ] **Salvage two fixes from branch
      `copilot/review-codebase-and-make-edits`** (one Copilot commit,
      2026-08-06, never opened as a PR). Re-apply them by hand as a small PR
      on current `main`; the code has moved too far to cherry-pick.
      1. `db_introspect()` in `R/utils_db_connectors.R` pastes the schema
         name into SQL inside quotes, so a schema name containing an
         apostrophe breaks the query. Quote it with `DBI::dbQuoteString()`.
      2. `R/mod_db_connect.R` turns a non-numeric port into `NA` with only a
         warning. Reject non-numeric or non-positive ports with a message.

      Do not take the branch's `mod_upload.R` change (superseded). Its
      session-restore change (always replace state, even with empty lists)
      is a design choice, not a fix: leave it unless wanted. In the same
      PR, two leftovers from the `is_lookup_table()` cache fix (`bf1823e`):
      - the comment above `.lookup_cache` in `R/utils_inference.R` still
        says "Memoised per shape";
      - add a test that a same-shaped table with renamed columns
        (`foo`/`bar` instead of `id`/`label`) is re-checked.

      Then delete the branch. Do all this before the Air reformat.
- [ ] **Close draft PR #6 but keep its branch**
      (`copilot/evaluate-current-status`, 7 Copilot commits, 2026-09-11,
      conflicts with `main`) as a reference for the Python work. Its unique
      content is about 1050 lines of Python features in `app.py`: database
      connections, export, run detection, name cleaning and scan triage,
      plus SQLAlchemy in `requirements.txt`. Whether to port that depends
      on the framework research. Take two pieces separately:
      - its GitHub Actions R CI workflow (`.github/workflows/r-ci.yml`,
        Ubuntu, `devtools::test()`). `main` has no CI.
      - `URL`, `BugReports` and a real `person("Amelia", "Miramonti", ...)`
        in `DESCRIPTION`.

      Do not take its committed `__pycache__/*.pyc` file.
- [ ] **Air reformat as its own commit.** Add an `air.toml`, run
      `air format .`, run the tests, and commit the reformat alone so it is
      never mixed with content changes. Then add the commit to a
      `.git-blame-ignore-revs` file in a follow-up commit. With default
      settings, `air format --check .` reports 30 of 40 tracked R files
      would change. Do it after the salvage PR above. The research outcome
      does not block it.
- [ ] **Stale remote branches.** These have no commits that are not on
      `main`, and can be deleted with Amelia's go-ahead:
      - `copilot/expand-sample-data-composite-keys`
      - `copilot/fix-shiny-app-errors`
      - `copilot/fix-source-file-path-error`
      - `copilot/update-repo-sidebar-description`
      - `fix/composite-pk-and-erd-dblclick`

      These have one unmerged commit each, and need a look first:
      - `chore/package-metadata`: author email and LICENSE holder, mostly
        already on `main`;
      - `copilot/add-open-source-license`: an MIT LICENSE.

## Reference: ERD design examples

Third-party example diagrams, kept for design reference only (a possible
future redesign of the ERD tab). Local copies live in `docs/erd-examples/`
so agents without web access can view them. Sources, in the order given:

- https://lset.uk/blog/entity-relationship-diagram-explained-with-real-database-examples/
- https://lucid.co/diagram/erd/tutorial
- https://www.impacttechnology.co.uk/example-entity-relationship-diagram

Examples (source matched by the order the links were given, so likely
rather than certain):

- [`erd-student-course-enrollment.png`](docs/erd-examples/erd-student-course-enrollment.png)
  (likely lset.uk): Student / Course / Enrollment. Table cards with a
  colored header, a PK/FK badge column beside each field (FK1 marks a
  numbered FK group), 1:N cardinality labels on edges, relationship
  diamonds ("Enrolled In"), and a PK/FK legend.
- [`erd-hockey-playoffs-crowsfoot.png`](docs/erd-examples/erd-hockey-playoffs-crowsfoot.png)
  (likely lucid.co): hockey playoff app. Header colors group related
  tables, every column is listed, crow's-foot notation (one, many,
  zero-or-one), edges leave from the specific FK row and arrive at the PK
  row, orthogonal (right-angle) routing.
- [`erd-access-tbl-equipment-hire.png`](docs/erd-examples/erd-access-tbl-equipment-hire.png)
  (likely impacttechnology.co.uk): equipment hire / projects in Access
  `tbl*` style. `tblCATEGORIES`-style names, PK/FK1/FK2 badges with a
  separator between key and non-key sections, dashed crow's-foot lines for
  optional relationships, junction tables (`tblCONTACT_CAT`,
  `tblEQUIP_CAT`) for many-to-many links.

Ideas these suggest for this app (notes only, not scheduled):
column-level edges (FK row → PK row); PK/FK badges on nodes; crow's-foot
cardinality inferred from uniqueness; dashed lines for optional or
low-confidence links; grouping by header color (e.g. `tbl_` vs `tlk_`);
distinct styling for junction tables; an optional legend.
