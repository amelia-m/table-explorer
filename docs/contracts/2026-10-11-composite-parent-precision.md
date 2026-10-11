# Task contract: measure the precision cost of a composite-key parent

Date: 2026-10-11  Dispatch: one agent
Request as given: "; precision cost unmeasured; / measure it?"

## Intent and scope

The containment signal requires a foreign key's parent column to be a key or
a near key of its table. That requirement is why two real FAERS links cannot
be found: `drug24q1` has 1,909,327 rows and no unique or near-unique column
at all (`primaryid` 406,184 distinct, `drug_seq` 1,777 distinct). Its real
key is the pair `(primaryid, drug_seq)`, which is unique over the table.

Relaxing the rule so that a component of a composite key counts as a key
would recover those two links. The recall gain is certain: 1,082 of 1,082 and
1,297 of 1,297 distinct child values are present in `drug24q1.drug_seq`. The
precision cost has never been measured, and that is what this task measures.

In scope: a parameter on the detection call that selects how strict the
parent-key requirement is, a cheap composite-key test to support the middle
setting, per-confidence reporting in the public harness so the numbers can be
read at all, and a measured table of every setting against every dataset.

The audience is Amelia, deciding whether to relax the rule.

## Non-goals

- **No UI.** Do not touch `R/mod_*.R`, `R/app_ui.R`, `R/app_server.R` or
  `inst/app/www/`. The parameter is set by callers, including the harness,
  and gets a control later under the presets work.
- Do not change the containment signal's weights, its reason text, its
  minimum distinct count, or any other signal. Do not change `weight_map`,
  `label_map` or the confidence thresholds.
- Do not change the default. The default setting reproduces the branch's
  current behaviour exactly, so this change alone moves no number.
- Do not wire in `detect_composite_pks()`. It did not finish in about 25
  minutes on FAERS. Write the cheap test described below instead, and leave
  that function alone.
- Do not reintroduce a row cap in the harness. The harness reads whole
  tables because a foreign key is a claim about value containment.
- No reformatting, no Air run. Do not merge, open a pull request, or delete
  branches.

## Context

- R package `tableexplorer`. Branch from `feat/containment-signal` at commit
  3900821, which already carries the containment signal, the Lahman harness
  and the three detection rules under PR #54. Name your branch
  `feat/containment-composite-parent`. Create your own worktree under
  `_scratch/` rather than using an existing one: `_scratch/wt-containment` is
  in use.
- Detection lives in `R/utils_inference.R`. `detect_fks()` builds `pk_map`
  (strictly unique, non-null) and `near_pk_map` (99 percent distinct per
  `parent_key_min_frac`) per table. `parent_key_kind(v, p, n)` returns
  `"key"`, `"near key"` or `NULL` and is what the containment signal calls.
  `containment_min_distinct` is already a parameter of `detect_fks()` and
  `score_candidate()`, defaulting to `containment_min_distinct_default`
  (3L): thread the new parameter the same way.
- The public harness is `dev/fixtures/public/fetch.R` and
  `dev/fixtures/public/score_public.R <names>`. Chinook, FAERS and Lahman
  all work on this branch. Lahman is read from the CRAN `Lahman` package in
  the user library, so keep `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE` on every
  Rscript call. FAERS takes about 57 seconds per run, Chinook about 1 second,
  Lahman about 17.
- **A defect in the harness you must fix first, because the measurement is
  uninterpretable without it.** `score_one()` passes
  `min_confidence = "medium"` to `detect_fks()`, but `detect_fks()` returns
  rows that `resolve_fk_parents()` has since demoted to low, so the printed
  `found` count and the precision computed from it mix confidence levels. On
  Chinook on this branch the 59 found rows are 10 high and 49 low, and all 10
  high are true links: the printed precision of 16.9 percent is 100 percent
  at the level a reviewer acts on. Make `score_one()` print found, hit,
  recall and precision at each confidence level present as well as overall,
  and keep the overall line so earlier figures remain comparable.
- Ground truth: Chinook from its declared SQLite constraints, FAERS and
  Lahman from hand-written files under `dev/fixtures/public/truth/`. The
  Lahman file was rewritten from the data on 2026-10-10 and has 23 links; its
  header says what was checked.
- Measured on `feat/containment-signal` at 3900821, to compare against:
  Chinook recall 90.9 percent, precision 16.9 percent overall, 10 of 10 at
  high; FAERS recall 75.0 percent, precision 50.0 percent; Lahman recall 95.7
  percent, precision 100.0 percent. Synthetic scorer `real: 157 of 157`,
  `false: 0`.
- R is at "C:\Program Files\R\R-4.6.1\bin\Rscript.exe". Never run
  `Rscript -e` with inline code on this machine: paths with spaces make it
  segfault. Put code in a file and run the file.
- Verification, from your worktree root:
  `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" dev/check.R`

## Constraints

- The parameter has three settings and the default is the current behaviour:
  - `"key"` (default): parent must be a key or near key. Today's rule.
  - `"composite"`: parent may also be one column of a pair that is unique
    over the parent table, found by the cheap test below.
  - `"any"`: no parent-key requirement for containment at all. This exists to
    bracket the cost, as the lower bound on precision and the upper bound on
    recall. It is a measurement setting, not a recommendation.
- **The cheap composite test** has three parts, each of which cuts the work
  by an order of magnitude. `detect_composite_pks()` is slow because it
  enumerates combinations up to width 3 over every candidate column of every
  table and tests each against the whole table: on a 20-column table that is
  190 pairs plus 1,140 triples, times 1.9M rows.
  1. **Demand-driven.** Run the test only for a (parent table, parent column)
     that a child column is already wholly contained in at 100 percent. A
     scan asks about a handful of columns, not every column of every table.
     Cache the answer per (table, column) so a parent asked about twice is
     tested once.
  2. **Distinct-product prefilter, free from the profiles.** A pair `(a, b)`
     can be unique over `n` rows only if `d_a * d_b >= n`. Those distinct
     counts are already computed. Pair the parent column with each other
     column that passes, in descending product order, and test nothing else.
     For `drug24q1` that is `406,184 * 1,777 = 7.2e8` against 1.9e6, so the
     real key's pair survives and most pairs die for free.
  3. **Sample, then confirm.** Test the pair on a random sample of
     `composite_probe_sample_rows` rows (propose 100,000) with
     `anyDuplicated()`. A duplicate in the sample is a duplicate overall, so
     a reject costs a sample-sized pass. Only a pair that is unique on the
     sample is then confirmed on the whole table. This is exact, not
     approximate: it changes the order of work, not the answer.
  Cap the number of pairs confirmed per column (`composite_probe_max_pairs`,
  propose 8) and stop at the first unique pair. Every number is a named
  constant with its justification in a comment. Report the time the test adds
  per dataset, measured.
- Width stays at two columns. A three-column key is out of scope: say so in
  the report if a dataset appears to need one.
- Every threshold is a named constant beside the existing ones at the top of
  `R/utils_inference.R`, each with its justification in a comment.
- The synthetic scorer must still report `real: 157 of 157` with `false: 0`
  at the default, and `dev/check.R` must pass.
- At the default setting, `score_public.R chinook faers lahman` must
  reproduce the three lines above to one decimal place. If any moves, stop
  and report.
- Tests exercise behaviour, one per behaviour, each able to fail. Every rule
  that admits candidates needs a test that keeps junk out, and every rule
  that excludes needs a survival test.
- Test data is invented, or taken from the public datasets in the harness.
  Never copied from Amelia's extract.
- No em dash (U+2014) anywhere, including commit messages.
- A script must not write a file before all its assertions have passed.
- Stop and report rather than deciding alone when: the default moves any
  measured figure, the composite test makes a FAERS run take more than about
  five minutes, or the synthetic scorer drops below 157 of 157 at the
  default.

## Edge cases

- **A parent table with no unique pair** (genuinely keyless, or a key wider
  than two columns): the `"composite"` setting finds nothing there and
  behaves as `"key"` does. Say so in the report rather than widening the
  probe to triples.
- **A parent table where many pairs are unique** (a wide table of near-unique
  columns): the first unique pair found decides, and both of its columns
  become eligible parents. Record how many columns that admits per dataset,
  because that is where the precision cost comes from.
- **The same column eligible under both `pk_map` and the composite test**:
  the key tier wins and the reason text says "key", not "part of a composite
  key". No double counting.
- **A child column wholly contained in a composite component that is a dense
  integer run**: the chance-overlap discount still governs the overlap
  signals. State in a comment whether containment on a composite component
  is discounted and why.
- **A column that is unique in a pair only because both columns are mostly
  missing**: require both columns of the pair to be non-missing on the rows
  tested, and say what you did when they are not.
- **`"any"` producing an unusable number of candidates** (more than
  `max_pairs` allows): record it, flag the row as capped, and do not read its
  recall as a clean figure.
- **A dataset whose run errors at one setting**: report the error and the
  setting; do not drop the row silently.

## Output requirements

- Changes confined to `R/utils_inference.R`,
  `tests/testthat/test-inference.R` and
  `dev/fixtures/public/score_public.R`.
- A measured table in the report: 3 settings times 3 datasets, each row
  giving found, hit, recall and precision overall and at high confidence,
  plus seconds. Name the settings in words.
- For the two FAERS links, say at which settings each appears and at what
  confidence.
- Logical commits with messages saying what changed and why; push the
  branch; no pull request.

## Acceptance and evidence

1. `dev/check.R` prints ALL CHECKS PASSED with `real: 157 of 157` and
   `false: 0` at the default.
2. At the default setting, `score_public.R chinook faers lahman` reproduces
   Chinook 90.9 recall, FAERS 75.0 recall and Lahman 95.7 recall / 100.0
   precision, to one decimal place, shown verbatim.
3. The nine measured rows, shown verbatim from the harness output, not
   retyped.
4. At `"composite"`, both `ther24q1.dsg_drug_seq -> drug24q1.drug_seq` and
   `indi24q1.indi_drug_seq -> drug24q1.drug_seq` appear in the FAERS run, or
   the report explains with measurements why they do not.
5. Lahman precision at `"composite"` is reported, since Lahman is the
   regression guard: if it falls below 100.0 percent, say by how much and
   which links were invented.
6. A test that the default setting excludes a parent that is only a composite
   component, and a survival test that the `"composite"` setting includes it.
7. A test that the composite test rejects a pair that is unique only because
   both columns are mostly missing.
8. A test of the harness change: `score_one()` reports per-confidence figures
   and its overall line is unchanged for a fixed input.
9. A test that the distinct-product prefilter rejects a pair that cannot be
   unique, and a survival test that it keeps the pair that is.
10. A test that the sample-then-confirm step reaches the same verdict as a
    whole-table test on an invented table where the duplicate pair sits
    outside the first rows, so a prefix sample would miss it.
11. **The harness validates its own ground truth.** Every pair in a truth
    file names a table and a column that exist in the loaded data. The
    harness exits non-zero and names each pair that does not, instead of
    reporting it as a missed link. Add this to `score_public.R` and show it
    firing on a deliberately misspelled pair. This exists because the Lahman
    truth file named `homegames.parkkey` when the column is `park.key`, and
    the typo was reported as a detection failure for a day.
- The agent shows: `dev/check.R` output verbatim; the harness output for all
  nine runs verbatim; the test name behind each line above; the files it
  changed; the time the composite test adds per dataset.
- The agent lists, in full wording, everything it deferred, every threshold
  it chose and why, and every claim it did not verify directly, each with the
  check that would settle it.

## Settled (Amelia, 2026-10-11)

- The precision cost is measured rather than assumed, and measured at three
  settings so the cost of the middle one can be read against both ends.
- `detect_composite_pks()` stays out: it is too slow on FAERS to use here.
- This measures. Whether to change the default is Amelia's decision, taken
  from the table, and belongs with the sweep in
  `2026-10-10-detection-settings-and-sweep.md`.
