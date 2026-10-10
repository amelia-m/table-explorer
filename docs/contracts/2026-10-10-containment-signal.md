# Task contract: containment signal for FK detection

Date: 2026-10-10  Dispatch: one agent
Request as given: "build the containment signal" (split from the presets work)

## Intent and scope

Detection currently has no signal for the structural definition of a foreign
key: a child column whose values all appear in a parent column that is a key.
Every signal it has is either a naming heuristic or a statistical similarity,
so a link whose name follows no convention rests on overlap and distribution,
which the chance-overlap discount on `feat/detection-rules-scoring` then
removes. Three real foreign keys measured on public data are lost that way:

- `customer.supportrepid -> employee.employeeid` (Chinook)
- `ther24q1.dsg_drug_seq -> drug24q1.drug_seq` (FAERS)
- `indi24q1.indi_drug_seq -> drug24q1.drug_seq` (FAERS)

In scope: a `containment` signal in `R/utils_inference.R`, its weight, its
reason text, its interaction with the chance discount, and the cardinality it
implies (one-to-one when the child column is itself unique, many-to-one
otherwise). Users are reviewers on the Relationships tab and the ERD.

## Non-goals

- No UI work, no presets, no settings: that is the other contract. Do not
  touch `R/mod_*.R`, `R/app_ui.R`, `R/app_server.R` or `inst/app/www/`.
- Do not change `weight_map` entries for existing signals, the 0.85 and 0.55
  confidence thresholds, or the naming rules.
- Do not change `detect_shared_columns()` or anything the shared-columns PR
  touches.
- Do not relax or remove the rules already on the base branch (parent must be
  a key, chance-overlap discount, cardinality floor, possible-key names).
- No reformatting, no Air run, no renaming of exported functions.
- Do not merge, open a pull request, or delete branches.

## Context

- R package `tableexplorer`, a Shiny app for finding and documenting table
  relationships. Branch `feat/possible-key-names`, which sits on
  `feat/detection-rules-scoring` (PR #54) and `feat/detection-precision`.
- Detection lives in `R/utils_inference.R`. `score_candidate()` fills a named
  `signals` list, aggregated noisy-OR over `weight_map`; `label_map` turns the
  top-weighted signal into the `detected_by` label shown in the UI and the
  exports. `column_profile()` computes per-column facts once, including
  `uniq`, `uniq_sample`, `counts` and `int_domain`.
- `pk_map` (strictly unique, non-null) and `near_pk_map` (99 percent distinct
  and non-missing) are already computed per table in `detect_fks()`.
- `overlap_from_profiles()` is `mean(child_distinct %in% parent_distinct)`.
  `overlap_expected_by_chance()` discounts it by the parent's integer density,
  and is skipped when the child has 25 or more distinct values.
- R is at "C:\Program Files\R\R-4.6.1\bin\Rscript.exe". Never run `Rscript -e`
  with inline code on this machine: spaced paths make it segfault. Put code in
  a file and run the file.
- Verification, from the worktree root, with the environment variable set
  because a fresh worktree has no renv library:
  `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" dev/check.R`
  It parses every R and JS file, runs the suite with counts, runs the synthetic
  scorer, and exits non-zero on any failure.
- Public measurement: `dev/fixtures/public/fetch.R` then
  `dev/fixtures/public/score_public.R chinook faers`. Chinook and FAERS are
  already in the user cache. The harness reads whole tables: do not reintroduce
  a row cap, which previously produced recall figures that were artefacts.
- Measured baselines on the base branch, to beat: Chinook recall 81.8 percent,
  precision 31.0 percent; FAERS recall 75.0 percent, precision 50.0 percent;
  synthetic scorer 157 of 157 real at medium+, 0 false.
- On `main`, for reference: Chinook 90.9 / 14.7, FAERS 100.0 / 12.3.

## Constraints

- The synthetic scorer must still report `real: 157 of 157` with `false: 0`.
- Chinook and FAERS recall must both rise above the baselines above, and
  neither precision may fall below the `main` figure for that dataset.
- The signal must not require a key-shaped column name. That is the point.
- Containment is computed from the profiles already built. Do not add a second
  pass over the data, and do not raise the sampling caps.
- Tests exercise behaviour, one per behaviour, each able to fail. Every rule
  that admits candidates needs a test that keeps junk out, and every rule that
  excludes needs a survival test.
- Test data is invented, or taken from the public datasets in the harness
  (Chinook, FAERS), which are public and carry no confidential content.
  Never from Amelia's own extract.
- No em dash (U+2014) anywhere, including comments and commit messages.
- A script must not write a file before all its assertions have passed.
- Stop and report rather than deciding alone when: the synthetic scorer drops
  below 157 of 157, a public dataset's precision falls below the `main`
  figure, or the signal cannot be made to fire on the three named links
  without also admitting the junk links named in Edge cases.

## Edge cases

- **Child column is unique**: still a candidate. Set cardinality one-to-one.
  Requiring a non-unique child would lose shared-primary-key extension tables.
- **Child has one or two distinct values**: containment is trivially satisfied.
  Exclude from the signal; `<min distinct for containment>` decides the line.
- **Parent is near-unique rather than strictly unique** (`near_pk_map`):
  include, and say "near key" in the reason text.
- **Parent is not a key at all**: exclude. This is what keeps
  `number_of_items -> width_cm` out.
- **A few child values missing from the parent** (orphan rows, a filtered
  extract): `<orphan tolerance>` decides whether this still counts.
- **Child column is entirely NA**: exclude, no signal.
- **Child and parent are both small dense integer runs**: the chance discount
  governs the overlap signal; state in a comment whether containment is also
  discounted and why.
- **Self-reference** (`employee.reportsto -> employee.employeeid`): allowed to
  fire. It is missed on both branches today; recovering it is a bonus, not a
  requirement.
- **Text columns**: containment applies, there is no density to discount.

## Output requirements

- Changes confined to `R/utils_inference.R` and `tests/testthat/test-inference.R`.
- A named constant for every threshold, beside the existing ones at the top of
  the file, each with its justification in a comment.
- The reason text names the evidence and the counts, in the style of the
  existing strings: for example `all 500 values present in a key (contained)`.
- Logical commits with messages saying what changed and why; push the branch;
  no pull request.

## Acceptance and evidence

1. `dev/check.R` prints ALL CHECKS PASSED, with the scorer line showing
   `real: 157 of 157` and `false: 0`.
2. `score_public.R chinook faers` shows Chinook recall above 81.8 percent and
   FAERS recall above 75.0 percent, with precision at or above 14.7 and 12.3
   respectively.
3. `customer.supportrepid -> employee.employeeid` appears in the Chinook run.
4. `ther24q1.dsg_drug_seq -> drug24q1.drug_seq` and
   `indi24q1.indi_drug_seq -> drug24q1.drug_seq` appear in the FAERS run.
5. A test asserting the junk shape stays out: a child column of small
   integers against a parent column that is **not** a key produces no
   candidate, even when every child value happens to appear in it.
6. A survival test for the one-to-one case: a child column that is itself
   unique and wholly contained in a parent key is detected, and its
   cardinality is one-to-one.
7. A test that a child with two distinct values wholly inside a parent key
   produces no containment signal at the default minimum of 3.
8. A test that the minimum is honoured when raised: at a minimum of 12, a
   child with 6 distinct values wholly inside a parent key produces no
   containment signal, and the same pair does at the default of 3. Run the
   public harness at a raised minimum as well, and report both lines, so the
   cost of a stricter setting is measured rather than assumed.
- The agent shows: the `dev/check.R` output verbatim; the `score_public.R`
  output verbatim, before and after; the test name behind each line above; the
  files it changed.
- The agent lists, in full wording, everything it deferred, every threshold it
  chose and why, and every claim it did not verify directly, each with the
  check that would settle it.

## Settled (Amelia, 2026-10-10)

- Minimum distinct values for containment: a parameter of the detection
  call, defaulting to 3, not a fixed constant. Amelia wants it adjustable
  per scan, and the preset work wires it to a control. This contract takes
  it as far as the parameter and its tests; the UI belongs to the presets
  contract.
- Threshold: strict 100 percent containment for the full signal, plus a
  weaker "nearly contained" tier at 99 percent or above, so orphan rows in a
  real extract do not lose the link.
- Weight: 0.92, above `overlap_high` (0.90) and below `cardinality_match`
  (0.95), because containment is stronger evidence than bare overlap.
- Containment is exempt from the chance-overlap discount when the parent is a
  key, since the discount exists for non-key parents.

## Open assumptions

None.
