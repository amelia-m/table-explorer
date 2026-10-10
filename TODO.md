# TODO

## Open items from the 2026-10-09 session

Decisions waiting on Amelia, in full wording so they can be answered later.

- [ ] **Contrast remediation**: plan written at `docs/contrast-plan.md`, measured
      with `_scratch/contrast_audit.R`. Amelia asked to hold implementation until
      other work lands. Its own open question: after step 1 the tokens
      `--text-faint`, `--text-secondary` and `--empty-text` all hold `#94a3b8` in
      dark mode. Collapse them into one token, or give `--text-faint` a distinct
      value that still clears 4.5:1?
- [ ] **Column semantic types**: task contract at
      `_scratch/contracts/2026-10-09-column-semantic-types.md`, covering validated
      type guesses (ZIP first), a type confirmation queue reusing the Data
      Dictionary review pattern, a privacy-respecting value preview, type-driven
      FK matching (veto mismatched confirmed types, boost matched ones), bulk
      approval of grouped links, and cross-table column-pair rules. Not approved,
      not dispatched. Its open assumption: where does the list of valid 3-digit
      SCF ZIP prefixes come from, and is a one-off fetch at build time (recorded
      in a `dev/` script, generated data committed) acceptable on this machine?
- [ ] **Commit hygiene on `feat/dict-review-and-scroll`** (branch unpushed): it
      carries an empty commit of mine titled "placeholder", and commit `49fbd36`
      sweeps both the DT scrollbar fix and the empty-flagged-column queue work
      under a scrollbar-only message. Proposed fix: `git reset --soft HEAD~2` and
      recommit as two honest commits. Needs Amelia's go-ahead, per the rule on
      resets.
- [ ] **Dictionary scrollbar height**: currently `scrollY = "62vh"` plus
      `scrollCollapse`. Recommended instead:
      `max-height: calc(100dvh - var(--dict-chrome, 360px))` in CSS, so the
      offset lives in one place and the cap bites on short windows. The JS
      measure-and-set alternative needs three listeners and a visibility guard
      and was judged more fragile. Amelia to choose.
- [ ] **Merge order and visual checks for the open PRs**: #23 drop golem, #24
      schema quoting and port validation, #25 `db_load_table` dialect and strict
      limit, #26 collapsible sidebar, #27 ERD chips off shared trunks, #28
      relationship panel grid, #29 Table Details collapse. #27, #28 and #29 were
      verified only on an empty app or not at all, and need a look on the real
      schema before merging.
- [ ] **Detection noise: value overlap on counts and low-cardinality integers**
      (Amelia, 2026-10-09: its own PR, after the current PRs land). A count
      column such as a `*_month_count` holding {0..12} overlaps any `tlk_*.id`
      holding a contiguous 1..N almost perfectly, so `overlap_high` (weight
      0.90) plus `format_match` (0.40, shape `int_code`) produces a 49% low
      candidate. On the real schema this is a large share of the 357
      low-confidence rows. The only guard today is
      `is_fk_candidate()` at `R/utils_inference.R:748`, which rejects a column
      only when `n_unique <= 2 && n > 10` and it is not key-named.
      Agreed approach, rules 1 and 4:
      1. Chance-overlap discount: estimate expected overlap from the parent's
         domain density (distinct values `m` over range `R`) and score only the
         excess, `max(0, observed - expected)`. Overlap on a dense integer
         domain then carries almost no weight.
      4. Two-signal floor: a single content signal cannot raise a candidate when
         the child column's distinct count is below a threshold (start at 5);
         it needs overlap plus cardinality, or a naming signal.
      Rule 3 (a measure-name guard for `*_count`, `*_qty`, `*_amount`, `*_age`,
      `*_days`, `*_month`, `*_year`, `*_total`) is held back: `is_key_name()`
      already treats `_num` and `_no` as key-like, so the two lists contradict
      and that has to be resolved first.
      Acceptance: `Rscript dev/fixtures/score_detection.R` still reports 157 of
      157 real links at medium+ with 0 false, and the low-confidence count on
      Amelia's schema drops measurably (only she can measure that).
      Status 2026-10-09, branch `feat/detection-rules-scoring`: rule 1 is done
      (`overlap_expected_by_chance()` in `R/utils_inference.R`). Rule 4 is
      **not**. What landed beside rule 1 is narrower than rule 4: a floor on
      `cardinality_match` alone (`cardinality_min_distinct = 12`), not a floor
      on any single content signal. The gap is real and visible in the
      fixture: once chance overlap is discounted, the unhelpfully named `code`
      columns in access52 reach 0.70 medium on `dist_high` (0.50) plus
      `format_match` (0.40), with no naming signal and no value evidence left
      at all, and the only thing keeping them out of the medium+ count is
      `resolve_fk_parents()`' ambiguity guard, which needs two or more
      candidate parents before it fires. The same column with a single
      candidate parent would be reported at medium. Question for whoever
      takes rule 4: should a candidate carrying only `dist_high`/`dist_med`
      and `format_match` be capped at low whatever the child's distinct
      count, or should the floor be on the child's distinct count as
      originally written (start at 5)?
- [ ] **`limit = 0` semantics** (`db_load_table`, PR #25): currently 0 means zero
      rows, following `DBI::dbFetch()`. Useful only once a caller can use an
      empty frame for a schema-only probe: `mod_db_connect.R` drops frames with
      `nrow(df) == 0`. Build that path, or leave the semantics unused?

- [x] Add a "Hide empty tables" toggle (0-row tables) to the sidebar that filters
      them out of the ERD, Table Details, and Relationships views.
- [ ] (Maybe later) User-defined naming patterns for FK detection: a settings
      box for lookup-table prefix (e.g. `tlk_`), lookup key column (e.g. `id`)
      and FK template (e.g. `{entity}_id`), saved with the session. Built-in
      conventions (Access, Rails/Django, SQL Server, warehouse `_key`/`_sk`,
      code lookups, role prefixes) are detected automatically already.

- [ ] ERD redesign: see `docs/erd-redesign-plan.md` (done: model, exports,
      ERD tab, data dictionary, dbt constraints; next: session diff,
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

## Follow-ups from the FK precision rules (2026-10-09)

Branch `feat/detection-rules-scoring`: the parent-must-be-a-key rule and the
chance-overlap and cardinality discounts. Deliberately left out of that
branch, in full wording. Measurement there was `Rscript dev/check.R` (1188
passed, 0 failed, 0 errors, 4 skipped) plus the access52 scorer (157 of 157
at medium+, 0 false, unchanged before and after).

- [ ] **Not checked: the effect on the real 52-table extract.** Everything
      measured on this branch is the synthetic access52 fixture and unit
      tests. The three named false links were reproduced from their shape, as
      invented data, and are gone; whether the real extract loses any genuine
      link to these two rules has not been measured, and only Amelia can
      measure it. The check that would settle it: run detection on the
      extract before and after and diff the medium+ link list.
- [ ] **`parent_key_min_frac = 0.99` is a share, so below 100 rows it is
      exactly strict uniqueness.** A small dirty lookup parent, say 7
      distinct codes in 8 rows, is therefore no longer offered as a parent at
      all, and any real link into it is lost rather than demoted. Assumed not
      to occur, not checked: access52 cannot show it either way, because
      every table in the fixture has at least one strictly unique column, so
      the near-unique fallback never runs there. The check that would settle
      it: for each table in the real extract with no fully unique column,
      print the row count and the distinct and non-missing counts per column.
      If small dirty parents do occur, the fix is an absolute tolerance (for
      example "at most one duplicate row, whatever the table's size")
      alongside the share.
- [ ] **The chance discount silences `overlap_high` for any numeric parent
      whose integer domain is denser than about 0.02**, and `overlap_medium`
      above about 0.20, which includes every contiguous id run. That is the
      rule working as specified, and it is also its cost: a real link into a
      contiguous id parent with no naming match now rests on format and
      distribution alone and drops from medium to low. In access52 every real
      link carries `naming_exact`, so nothing moved there. Decide whether a
      perfect overlap on a dense domain should keep a floor of
      `overlap_medium` rather than nothing.
- [ ] **`resolve_fk_parents()` was changed beyond the two rules.** Its
      "values fit several tables" test now reads the raw overlap carried on
      the relationship (`overlap`, added to `make_rel()`) as well as the
      `cardinality_match`/`overlap_high` signals. Without it the ambiguity
      guard switched off for exactly the candidates the discount silences and
      the fixture went to 32 false links at medium+. Flagged because it was
      not in the brief: whether the ambiguity guard should read raw values
      while the score reads discounted ones is a design call worth a second
      opinion.
- [ ] **The legacy root `inference.R` still holds the old detection engine**
      and was not updated with either rule. It is a known dead duplicate,
      sourced by nothing (backlog items I10 and D4 in
      `dev/code-review-backlog.md`), which is why it was left. If D4 is
      answered by keeping the root files rather than deleting them, both
      rules have to be ported into it.
- [ ] **`detect_fks()`' 1:1 path draws targets from `pk_map` only.** A unique
      key-named child column (`src_unique`) looks for its parent in
      `pk_map[[t2]]`, so a table whose key is merely near-unique offers it no
      target and the 1:1 link is not found at all. Noticed while writing the
      survival test for the parent-key rule and left alone, because the brief
      scoped that rule to the `target_cols` fallback. Decide whether 1:1
      links should accept a dirty parent key too.
- [ ] **`Rscript dev/check.R` needs `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE`
      in a fresh worktree.** A new worktree has no `renv` library, so
      `renv/activate.R` bootstraps renv at R startup, points the library at
      an empty project library and the suite aborts with "there is no package
      called 'testthat'". `dev/check.R` already sets that variable, but from
      inside the script, which is too late for its own startup (it does reach
      the scorer subprocess). Every run quoted for this branch set it on the
      command line. Worth deciding whether the repository should carry an
      `.Renviron`, or whether `dev/check.R` should re-exec itself.

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

- [x] **Framework decision (2026-10-02): golem dropped, plain package.**
      Why, what changed, and when golem would be worth bringing back are in
      `docs/research/shiny-framework/decision.md`. Rejected: leprechaun,
      rhino and a plain `app.R`. This also resolved backlog items C3 (the
      upload limit now applies, 100 MB), I5, I13, M9, M10, M11 and D1.
- [ ] **R version for Connect Cloud (deferred 2026-10-02).** Connect Cloud
      supports R 4.0.0 to 4.6.0 (its R platform docs). This machine has only
      R 4.6.1, so a `manifest.json` written here names an unsupported
      version, and what Connect Cloud does then is undocumented. Amelia chose
      to wait: deployment is not imminent and Connect Cloud may add 4.6.1.
      Before the first deploy, check its supported range again. If 4.6.1 is
      still missing, either `rig add 4.6.0` (alongside 4.6.1; packages share
      the 4.6 user library) and write the manifest from it, or test-deploy
      on 4.6.1.
- [x] **renv adopted 2026-10-02** (`31b89ae`, Amelia's instruction).
      Explicit snapshot: `renv.lock` holds DESCRIPTION's Imports and their
      dependencies (93 packages, R 4.6.1). renv 1.2.4 leaves Suggests out
      (`snapshot.dev: false`), so testthat, pkgload, RSQLite and the database
      drivers are installed in the project library but not locked.
- [ ] **Lock the test packages in `renv.lock`?** A fresh `renv::restore()`
      on another machine gets the app's Imports but not testthat, so tests
      can't run there until it is installed by hand. Options:
      1. set `snapshot.dev = TRUE`, which locks all of Suggests, the heavy
         database drivers (rJava, odbc, bigrquery and so on) included;
      2. keep it as is, and document `renv::install(c("testthat",
         "pkgload", "RSQLite"))` for contributors;
      3. move the test essentials into a separate setup step.

      Recommendation: 2, until there is CI.
- [ ] **`.Rbuildignore` is still minimal** (backlog I6). renv created it
      with `^renv$`, `^renv\.lock$` and `^requirements\.txt$` only. A
      package release also needs `app.R`, `app.py`, `dev/`, `docs/`,
      `_scratch/`, `sample_data/`, the legacy root `.R` files, `CLAUDE.md`,
      `TODO.md`, `.agents/` and `.vscode/`.
- [x] **Salvage two fixes from branch
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

      Done 2026-10-08 in PR #24 (`salvage/db-hardening`): both fixes, the
      stale comment and the renamed-columns test. Schema quoting turned out
      to be six query sites, not one. Tests 0 failures; detection scorer
      still 157 of 157 at medium+, 0 false. Still open from this item:
      - [ ] Delete branch `copilot/review-codebase-and-make-edits` (local
            and remote) once PR #24 is merged. Needs Amelia's go-ahead.
      - [ ] **Third fix in the same branch commit, not salvaged (deferred
            2026-10-08, decision for Amelia).** `db_load_table()` in
            `R/utils_db_connectors.R` builds SQL with hand-quoted
            identifiers (`"schema"."table"`) and a backtick fallback, and
            does not sanitise `limit`. The branch rewrites it with
            `DBI::Id()` and `DBI::dbQuoteIdentifier()`, coerces a bad limit
            back to 10000, and replaces the fallback with
            `DBI::dbReadTable()`, plus 2 tests (a table name containing a
            space and a hyphen; `limit = 0`). This is old backlog item P2
            (not portable to SQL Server, fails silently). Left out to keep
            PR #24 to the logged scope. Worth its own PR; say whether to
            take it, and whether the `dbReadTable()` fallback is wanted.
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
