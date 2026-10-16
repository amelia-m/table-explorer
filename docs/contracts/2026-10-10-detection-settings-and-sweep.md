# Task contract: detection rules as settings, and a measured sweep

Date: 2026-10-10  Dispatch: one agent, after the containment signal lands
Request as given: "yes to the hard-coded rules becoming settings and presets
will be determined based on testing across several different public data sets
and then I'll follow up with some of my own"

## Intent and scope

The rules that decide which foreign keys are reported are currently constants
in `R/utils_inference.R`. A preset cannot select among them while they are
constants, and nobody can say which combination suits which kind of schema
because no combination other than the shipped one has been measured.

This contract does two things and stops. First, it turns the hard-coded rules
into parameters of `detect_fks()`, with defaults equal to today's constants, so
the default call behaves exactly as it does now. Second, it adds a sweep script
that runs a grid of those parameters across every public dataset in the harness
and writes the results to a file, so the preset list can be chosen from measured
numbers.

The audience for the sweep output is Amelia, choosing which combinations are
worth naming as presets. She will then check the candidates against her own
52-table extract before the preset UI is built.

## Non-goals

- **No UI.** Do not touch `R/mod_*.R`, `R/app_ui.R`, `R/app_server.R` or
  `inst/app/www/`. The sidebar controls, the preset selector and recording
  which preset produced a scan belong to the presets contract, which comes
  after this one and is written from this one's results.
- **No new detection rules and no new signals.** No change to `weight_map`,
  `label_map`, the 0.85 and 0.55 confidence thresholds, or the noisy-OR
  aggregation. The containment signal is a separate contract and lands first.
- **Do not change any default.** Every new parameter defaults to the value the
  constant has on the base branch. A sweep is not a licence to pick a new
  default: that decision is Amelia's, taken from the sweep output.
- Do not expose the similarity thresholds (`overlap_high`, `overlap_medium`,
  `name_sim_high`, `name_sim_med`, `dist_sim_high`, `dist_sim_med`) as
  settings. They are continuous knobs on signal strength rather than rules
  that switch on and off, and a grid over them does not finish. Say so in the
  report if the sweep suggests one of them matters.
- No change to `detect_shared_columns()`.
- No reformatting, no Air run. Do not merge, open a pull request, or delete
  branches.

## Context

- R package `tableexplorer`, a Shiny app for finding and documenting table
  relationships. Branch from `feat/containment-signal` once that has landed,
  since both change `R/utils_inference.R`.
- `detect_fks()` is at `R/utils_inference.R:1139` and currently takes
  `tables`, `method`, `min_confidence`, `enable_flags`, `progress_fn`,
  `max_pairs`, `focus_tables`, `existing`. The containment contract adds a
  minimum distinct count for containment as a parameter defaulting to 3.
- The constants to parameterise, with their current values and line numbers on
  `feat/possible-key-names`:
  - `parent_key_min_frac <- 0.99` (line 24), the distinct fraction at which a
    parent column counts as a near key.
  - `cardinality_min_distinct <- 12L` (line 32), below which a child column's
    cardinality match carries no weight.
  - `overlap_chance_max_distinct <- 25L` (line 39), the child distinct count
    above which the chance-overlap discount is skipped.
  - `is_possible_key_name()` (line 315), the tier that admits any column
    starting or ending with `id` that is not a common word. Its switch is
    whether the tier runs at all.
  - The parent-must-be-a-key fallback, whose switch is whether a candidate
    whose parent is neither in `pk_map` nor `near_pk_map` can be reported.
  - The chance-overlap discount itself (`overlap_expected_by_chance`), whose
    switch is whether the discount is applied at all.
- Measurement harness: `dev/fixtures/public/fetch.R`, then
  `dev/fixtures/public/score_public.R chinook faers lahman`. It reads whole
  tables, no row cap, and prints tables, truth, found, hit, recall, precision
  and seconds per dataset. Chinook and FAERS are in the user cache; Lahman is
  read from the CRAN `Lahman` package in the user library.
- Measured on `feat/possible-key-names` at commit a795492, which is what the
  defaults must reproduce: Chinook 81.8 recall / 31.0 precision, FAERS 75.0 /
  50.0, Lahman 95.2 / 90.9. On `main` for contrast: 90.9 / 14.7, 100.0 / 12.3,
  71.4 / 0.9. The containment work will move these, so take the base branch's
  own figures as the target, measured on the branch, not the numbers here.
- Pagila is identified as a fourth dataset but is deferred (Amelia,
  2026-10-10): it needs a running Postgres instance. Do not set one up and do
  not include it in the sweep.
- R is at "C:\Program Files\R\R-4.6.1\bin\Rscript.exe". Never run `Rscript -e`
  with inline code on this machine: spaced paths make it segfault. Put code in
  a file and run the file.
- Verification, from the worktree root, with the environment variable set
  because a fresh worktree has no renv library:
  `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" dev/check.R`

## Constraints

- Every parameter defaults to its current constant value, and
  `score_public.R chinook faers lahman` with defaults reproduces the base
  branch's figures to one decimal place on all three datasets. If any figure
  moves, stop and report: the parameterisation has changed a rule's meaning.
- The synthetic scorer must still report `real: 157 of 157` with `false: 0`
  at the defaults.
- Parameters are passed, not read from global state. No `options()`, no
  package-level mutable state, no environment variables: a sweep that mutates
  globals cannot be trusted across runs in one session.
- The constants stay at the top of the file as the documented defaults, each
  with its justification in a comment. The parameter's default refers to the
  constant rather than repeating its value.
- The sweep writes one file and prints a summary. It must not write the file
  before every run in the grid has completed, so a partial sweep cannot be
  read as a whole one. If a run fails, the file is not written and the failure
  is reported.
- Every sweep row carries the dataset, the full settings combination, found,
  hit, recall, precision, seconds, the git commit, and the date from the
  system (`Sys.Date()`), never typed by hand.
- Tests exercise behaviour, one per behaviour, each able to fail. Every
  parameter needs a test on an invented fixture showing that changing it
  changes the result, and that its default matches the constant.
- Test data is invented, or taken from the public datasets in the harness.
  Never copied from Amelia's extract.
- No em dash (U+2014) anywhere, including comments and commit messages.
- Stop and report rather than deciding alone when: a default moves any
  measured figure, a parameter cannot be threaded without changing a rule's
  meaning, or the full grid would take longer than about 30 minutes per
  dataset.

## Edge cases

- **A parameter combination that reports nothing at all** (every rule at its
  strictest): record the row with zero found and precision reported as `NA`
  rather than 0, since precision is undefined with no candidates. Do not drop
  the row: a combination that finds nothing is a result.
- **A combination that finds more candidates than the pair cap allows**
  (`max_pairs`): record it and flag the row as capped, so its recall is not
  read as a clean figure.
- **A dataset missing from the cache** (Lahman package absent, FAERS not
  fetched): the sweep exits non-zero and writes nothing, naming the dataset.
  A silent SKIP in a sweep is worse than a failure, because the output file
  then under-reports.
- **The chance discount switched off while `overlap_chance_max_distinct` is
  also set**: the threshold is inert. Record the combination once, not twice,
  and say in the report which combinations collapse onto each other.
- **A run that errors on one dataset but not others**: the whole sweep fails
  and writes nothing. Report the error and the combination that caused it.
- **Timing**: if the full grid does not finish in reasonable time, reduce the
  grid rather than capping rows, and say exactly which combinations were
  dropped and why. Never reintroduce a row cap into the harness.

## Output requirements

- Changes confined to `R/utils_inference.R`, `tests/testthat/test-inference.R`,
  and new files under `dev/fixtures/public/`.
- A sweep script, `dev/fixtures/public/sweep_settings.R`, taking the dataset
  names as arguments and defaulting to all three.
- A results file, `dev/fixtures/public/sweep-<date>.csv`, one row per
  combination and dataset, with the columns named in Constraints.
- A short written summary in the agent's report, not a new document: for each
  dataset, the combinations on the recall-precision frontier, meaning those
  that no other combination beats on both measures at once. Name the settings
  in words, not as a row number.
- Logical commits with messages saying what changed and why; push the branch;
  no pull request.

## Acceptance and evidence

1. `dev/check.R` prints ALL CHECKS PASSED with the scorer line showing
   `real: 157 of 157` and `false: 0`.
2. `score_public.R chinook faers lahman` at the defaults reproduces the base
   branch's three lines to one decimal place, with both runs shown.
3. `sweep_settings.R` completes and writes a results file whose row count
   equals the number of combinations times three datasets, stated as a number.
4. Six tests, one per parameter, each showing that changing the parameter
   changes the candidate set on an invented fixture, and that the default
   reproduces the constant's behaviour.
5. A test that the sweep script writes nothing when a dataset is unavailable:
   call its loading step with a dataset name that does not exist and assert it
   stops without creating a file.
6. At least one combination in the results file beats the defaults on recall
   at equal or better precision for FAERS, or the report says plainly that no
   combination does and gives the frontier rows that come closest.
- The agent shows: `dev/check.R` output verbatim; the `score_public.R` output
  at the defaults, before and after the change; the sweep's printed summary;
  the frontier rows for each dataset; the test name behind each line above;
  the files it changed.
- The agent lists, in full wording, everything it deferred, every combination
  it dropped from the grid and why, every threshold it chose, and every claim
  it did not verify directly, each with the check that would settle it.

## Amendment (2026-10-13): base, grid and run budget

Written when the contract was dispatched. It supersedes the Context and
Acceptance lines it contradicts.

**The base is `feat/prose-parent-guard` at b318c5e**, not
`feat/containment-signal`. The chain has moved: that branch carries PR #54's
three rules, the possible-key-name tier, the containment signal, the
composite-parent measurement, the prose-parent guard, and the harness fixes
that make a sweep readable (per-confidence reporting, ground-truth
validation, a `max_pairs=` argument, and the corrected Lahman truth file with
23 links). Nothing below has landed on `main`, so the sweep runs on the
branch and reports; it does not merge.

**Three of the six switches are already parameters** on that base, with
these defaults, and need no new plumbing:

- `parent_key_requirement` = `"key"`, with `"composite"` and `"any"`. `"any"`
  is how the parent-must-be-a-key rule is switched off.
- `prose_parent_guard` = `"allow"`, with `"refuse"` and `"refuse_target"`.
- `containment_min_distinct` = `3L`. A very large value is how the
  containment signal is switched off.

**Three still need parameterising**, and that is the code half of this task:

- The chance-overlap discount (`overlap_expected_by_chance`,
  `overlap_chance_max_distinct <- 25L`): on or off, plus the threshold.
- The cardinality floor (`cardinality_min_distinct <- 12L`): a value.
- The possible-key-name tier (`is_possible_key_name()`): on or off.

**The run budget, because the full grid does not fit.** Six switches at two
values each is 64 combinations. Chinook takes about 1 second and Lahman about
20, so 64 runs of each is about 22 minutes: run the **full grid** on those
two. FAERS takes 55 to 150 seconds, so 64 runs is over an hour and the
contract's stop line forbids it. On FAERS run a **reduced set**: every
single-switch flip from the default, the default itself, the full stack, and
every combination on the Chinook or Lahman frontier. Name in the report
exactly which FAERS combinations were not run.

**Single-switch rows are the point, not a by-product.** The reason this task
exists is that PR #54's three rules have never been measured apart: every
figure quoted anywhere is all three applied at once. So the report must give,
for each of the six switches, the one-flip row against the default, on all
three datasets where the budget allows, and say which single rule earns its
place and which does not.

**Report precision and recall at high confidence as well as overall.** The
overall figure mixes high rows with ambiguity-demoted low rows, so a
precision number for the whole set is not the number a reviewer experiences.
Chinook on this base at the defaults is 16.9 percent overall and 90.0
percent at high.

**Measured baselines on the base branch, to reproduce at the defaults**,
all at high confidence, with `prose_parent_guard` at its default of
`"allow"`: Chinook recall 81.8, precision 90.0; Lahman recall 95.7, precision
100.0; FAERS recall 75.0, precision 50.0. Chinook reaches 100.0 precision at
high only with `prose_parent_guard = "refuse_target"`, which is not the
default and is one of the switches being swept. Synthetic scorer
`real: 157 of 157`, `false: 0`. If any of these moves at the default
settings, stop and report: the parameterisation has changed a rule's meaning.

## Settled (Amelia, 2026-10-10)

- The hard-coded rules become settings. "Yes to the hard-coated rules becoming
  settings."
- The preset list is not decided in advance. It is chosen from the sweep
  output across several public datasets, and then checked against Amelia's own
  extract before the preset UI is built. This contract therefore produces the
  measurements and no UI.
- Pagila is deferred. It needs a Postgres instance and is out of the sweep.
- The grid: the six switches named in Context, each at its default and at one
  or two alternatives chosen by the agent and justified in the report. The
  agent decides the alternatives, because only it will know which values the
  code can take without changing a rule's meaning.
