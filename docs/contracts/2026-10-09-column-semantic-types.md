# Task contract: column semantic types, review and type-driven matching

Date: 2026-10-09  Dispatch: 4 agents in parallel, disjoint file lists, then one integration pass
Request as given: "broaden this" (the ZIP semantic-type work), covering validated type guesses,
user confirmation with a value preview, type-driven FK matching, bulk approval of grouped links,
and cross-table column-pair rules.

## Intent and scope

Detection currently reads shape, not meaning. `format_fingerprint()` labels any mostly-5-digit
column `zip_us` (`R/utils_inference.R:62`, first pattern over 80% of a 200-value sample wins), so
`client_id` to `client_id` is reported as "shared format [zip_us]", and every 5-digit id column in
a schema looks alike to the `format_match` signal (weight 0.40, `weight_map`, `R/utils_inference.R:20`).
On a wide real extract this produces both noise and a misleading evidence line, and the
reviewer confirms the same kind of link dozens of times by hand.

In scope, four parts:

1. **Semantic type registry and validation.** A named type per column, guessed from values and
   column name, validated beyond shape where validation is cheap, with invalid values counted and
   surfaced. ZIP is the worked case: numeric range 00501 to 99950 plus a bundled list of valid
   3-digit SCF prefixes.
2. **Type confirmation UI.** The guess is a guess until the user confirms it, reusing the Data
   Dictionary review pattern (`R/mod_dictionary.R`: banner, modal, per-row radio, confirm-all,
   decisions hash-stamped against the column data, `privacy_review_set()` / `dict_privacy()`).
   Includes a value-preview control for judging a guess.
3. **Type-driven FK matching.** Confirmed types veto mismatched pairs and boost matched ones.
4. **Bulk confirmation.** Grouping of similar inferred links for one-action approval, and standing
   cross-table rules for a repeated column pair (`k9id` to `k9id`, `client_id` to `client_id`) that
   apply to tables loaded later.
5. **Overlap noise on counts and low-cardinality integers** (folded in by Amelia, 2026-10-09,
   superseding an earlier decision to do this as its own later PR). A count column holding
   {0..12} overlaps any `tlk_*.id` holding a contiguous 1..N almost perfectly, so `overlap_high`
   (weight 0.90) plus `format_match` (0.40) yields a 49% low candidate; this is a large share of
   the low-confidence rows on the real schema. The only guard today is `is_fk_candidate()`
   (`R/utils_inference.R:748`), which rejects a column only when `n_unique <= 2 && n > 10` and it
   is not key-named. Two agreed rules:
   - **Chance-overlap discount**: estimate expected overlap from the parent's domain density
     (distinct values `m` over range `R`) and score only the excess, `max(0, observed - expected)`.
   - **Two-signal floor**: a single content signal cannot raise a candidate when the child's
     distinct count is below a threshold (start at 5); it needs overlap plus cardinality, or a
     naming signal.
   Held back: a measure-name guard for `*_count`, `*_qty`, `*_amount`, `*_age`, `*_days`,
   `*_month`, `*_year`, `*_total`. `is_key_name()` already treats `_num` and `_no` as key-like, so
   the two lists contradict; resolve that before adding it.

Users: Amelia, reviewing a schema of roughly 50 tables in the running app, and the data dictionary
and dbt/data-dict exports that carry the result downstream.

## Non-goals

- No change to what counts as personal data, nor to the privacy flagging rules in
  `R/utils_privacy.R`. The type review is a second, separate queue.
- No user-defined types in v1 (type vocabulary is a fixed set, extensible in code only).
- No ZCTA or full ZIP database. Prefix list only.
- No network calls at runtime, in detection or in the UI.
- No change to the Python app (`app.py`), which is secondary (project profile).
- No reformatting of untouched code, no renaming of existing exported functions, no Air run
  (the Air reformat is a separate TODO item and must stay its own commit).
- Do not resolve the stale-`zip_us`-label question by deleting the format signal; the signal stays
  for unreviewed schemas (see Constraints).

## Context

- R package `tableexplorer`, Shiny app, plain R package (golem dropped, PR #23 pending). R 4.6.1,
  renv 1.2.4 with an explicit snapshot; test packages are not in `renv.lock`.
- Build, run and test:
  - tests: `testthat::test_local()` from the project root, or the script in `_scratch/`.
  - detection scorer: `Rscript dev/fixtures/score_detection.R`.
  - app: `pkgload::load_all(); run_app()`. Not `shiny::runApp()`, which warns about the R/
    directory being a package.
  - JS has no test runner. `node --check <file>` is the only automated check.
- Detection internals (`R/utils_inference.R`):
  - `column_profile()` computes per-column facts once, including `fingerprint`.
  - `score_candidate()` fills `signals`, aggregated noisy-OR over `weight_map`; `label_map` turns
    the top-weighted signal into the `detected_by` label.
  - `format_patterns` is an ordered list; first pattern matching >= 80% of the sample wins.
    `zip_us` sits above `int_code`, so 5-digit integers never reach `int_code`.
  - `format_fingerprint()` samples up to 200 non-NA values with a fixed seed (42).
- Review plumbing to copy (`R/utils_privacy.R`, `R/mod_dictionary.R`): `privacy_review_queue()`
  builds the queue, now carrying `n_values`; `privacy_review_set()` writes decisions keyed
  `table|column`; `privacy_data_hash()` stamps a decision against the data it was made for, so a
  refresh re-asks. Dictionary entries live in `dictionary_rv`, a named list keyed by `dict_key()`.
- Dictionary surface: `build_data_dictionary()` and `dict_format()` in `R/utils_export.R`; the tab
  renders a DT with Type and Format columns (`R/mod_dictionary.R:480`).
- Baseline to beat, measured on `main` before this work: `testthat::test_local()` 0 failures,
  0 errors, 7 skips; `dev/fixtures/score_detection.R` reports 157 of 157 real links at medium+,
  0 false.
- Branches in flight that touch the same files, all unmerged: #24, #25 (`R/utils_db_connectors.R`),
  #26 (sidebar: `R/app_ui.R`, `inst/app/www/app.js`, `styles.css`), #27 (`inst/app/www/erd.js`),
  #28 (`R/mod_erd.R`, `styles.css`), plus an unpushed branch touching `R/mod_dictionary.R` and
  `R/utils_privacy.R`. Branch this work off `main` and expect to rebase.

## Constraints

- **Detection stays deterministic without user input.** With no confirmations, scoring must match
  today's behaviour, and the scorer must still report 157 of 157 at medium+, 0 false.
- **Veto applies only when both columns have a user-confirmed type.** A guess never blocks a link.
- **Precedence**: an explicit per-link decision (confirm or suppress) wins over a cross-table rule;
  a cross-table rule wins over an unreviewed guess. A rule never silently overturns a suppression.
- **Privacy preview**: default is shape only (length, digit count, pattern, counts). Values appear
  only after an explicit per-column "Show values" click, and that click is not remembered across
  sessions. The dictionary's own no-examples-until-reviewed rule is unchanged.
- Keep `format_match` and `format_patterns` working for unreviewed schemas. Rename the misleading
  shape label (`zip_us` as a pure shape) to a shape name; the semantic name belongs to the
  confirmed type, not the fingerprint.
- No new runtime dependencies. The prefix list ships as package data built by a script under
  `dev/`, with its source URL and retrieval date recorded in the script and in `man/` or a comment.
- Decisions and rules persist with the session export and restore, and appear in the data
  dictionary and its exports (CSV, Markdown, data-dict YAML).
- Tests exercise behaviour, not source text; one test per behaviour per layer; every test must be
  able to fail. Test data is invented, never copied from the real extract.
- No em dashes anywhere, including UI strings and commit messages.
- Attribution lines are allowed in this repository (`.agents/project-profile.md`).
- **Stop and ask when**: the scorer baseline moves in either direction; a change would alter what
  is flagged as personal; the prefix data cannot be sourced without a network call at build time;
  or the veto rule would need to fire on an unconfirmed guess to be useful.

## Edge cases

- **Leading-zero ZIPs stored as integers** (`02134` becomes `2134`): flag as type ZIP with a
  "stored as integer, leading zero lost" note; do not rewrite the data.
- **ZIP+4** (`12345-6789`): valid ZIP, same type.
- **All-NA column**: no guess, excluded from the review queue (matches the privacy queue's
  `n_values` rule).
- **Mixed column, 80% valid ZIPs and 20% junk**: guess ZIP, report the invalid count and show up to
  10 offending values in the preview, subject to the privacy rule above.
- **Numerically valid, prefix unassigned** (`00000`, `99999`, unassigned 3-digit prefix): counts as
  invalid, contributes to the invalid count.
- **Column confirmed as a type, then data refreshed**: hash stamp no longer matches, so the type
  returns to guessed and the link re-enters the review queue. Confirmed links are not revoked.
- **Two columns, same confirmed type, different widths or formats** (ZIP vs ZIP+4): type matches,
  no veto.
- **Group with one dissenting member** (nine `provider_id` to `tlk_providers` links plus one
  `provider_id` to `tbl_staff`): group only identical (column, target table, target column)
  triples; never group across different targets.
- **Cross-table rule meeting a table loaded later**: rule applies on load, link appears as rule
  confirmed, and the rule is named in the evidence line.
- **Cross-table rule whose pair no longer exists** anywhere: keep the rule, show it as inactive;
  do not delete it silently.
- **Self-referencing table** (`k9id` to `k9id` within one table): rule does not create a self-link.
- **Confirmed type on a column with no links**: allowed, carried into the dictionary and exports.

## Output requirements

- R code in `R/`, matching surrounding style, no formatter run.
- New files expected: `R/utils_types.R` (registry, guessing, validation), `data/` or `R/sysdata.rda`
  for the prefix list with its generator under `dev/`.
- UI: type review reachable from the Data Dictionary tab, in the existing banner strip; modal with
  one row per column: table, column, guessed type, confidence or invalid count, preview control,
  decision radio (Confirm, Reject, Later), plus confirm-all.
- Bulk link approval: on the Relationships tab or the ERD panel, a grouped view of identical
  (column, target table, target column) triples with a count and one Confirm all action.
- Cross-table rules: listed somewhere the user can see and remove them; stored with the session.
- Dictionary and exports carry the confirmed type and its status (guessed, confirmed, rejected).
- Each part lands as its own commit, with its own PR, in this order: (1) registry and validation,
  (2) review UI and preview, (3) matching, (4) bulk approval and rules.

## Acceptance and evidence

Concrete checks, decided now:

1. `guess_type(c("68508", "68510", "68512"), "zip_code")` returns type `zip_us` with 0 invalid.
2. `guess_type(c("12345", "99999", "00000"), "client_id")` returns a 5-digit shape type, not
   `zip_us`, and names the invalid ZIP values when asked for ZIP specifically.
3. A column of valid ZIP-shaped values with an unassigned prefix reports invalid > 0.
4. **Survival check**: with no confirmations anywhere, `Rscript dev/fixtures/score_detection.R`
   still reports 157 of 157 real links at medium+ and 0 false. A link that exists today and is not
   affected by any confirmed type must still be detected after the change.
5. Two columns confirmed as different types produce no candidate link, shown by a scorer run on a
   fixture with those confirmations present.
6. Two columns confirmed as the same type score strictly higher than the same pair unconfirmed.
7. An unconfirmed guess of different types does **not** veto: same fixture, confirmations removed,
   link still present.
8. Confirming a group of nine identical (column, target, target column) links writes nine
   confirmations and leaves a tenth link to a different target untouched.
9. A cross-table rule for `client_id` to `client_id` applies to a table added after the rule was
   made, and does not override an existing suppression of one of those links.
10. A column flagged personal shows no values in the type-review preview until Show values is
    clicked; the shape summary is present before the click.
11. A child column of 13 distinct small integers against a parent holding a contiguous 1..N scores
    no candidate on overlap alone, and the same pair with a matching column name still does.
12. A genuine low-cardinality FK that exists today (a key-named column holding few distinct
    values) survives both new rules: survival check, so over-applying fails a test.
13. `testthat::test_local()`: 0 failures, 0 errors, and the skip list unchanged from the baseline.
14. `node --check` passes on any changed JS.

The agent shows: the commands and their output for 4, 13 and 14; the test name behind each of
1 to 12; the files it changed; and what it knows is weak or did not address. It lists, in full
wording, everything it deferred or left out of scope with who decides it, and every claim it did
not check directly, each with the check that would settle it.

## Open assumptions

- **Source of the SCF prefix list.** No offline copy exists in the repo, and the constraints forbid
  a runtime network call. Proposal: a script under `dev/` that fetches the list once from a named
  public source, records the URL and retrieval date, and writes package data; the repo carries the
  generated data, not the fetch. Needs Amelia's agreement on the source, and confirmation that a
  one-off fetch at build time is acceptable on this machine.
