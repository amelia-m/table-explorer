# Task contract: Shiny app framework options for table-explorer

Date: 2026-10-02 (revised from 2026-09-30)  Status: approved by Amelia 2026-10-02
Dispatch: 5 research agents in parallel (general-purpose, web access), then
synthesis by the dispatching session
Request as given: "dispatch agents to learn about the leprechaun alternative to
golem and weigh pros/cons of those and other approaches for managing shiny
applications."

## Intent and scope
Input for a decision Amelia is still weighing: how table-explorer should be
structured (keep golem, switch to leprechaun or rhino, or use no framework),
given the ways it might be shipped. Amelia decides; the report lays out the
trade-offs and recommends only where one option clearly wins.

The app may ship in several ways at once, from one codebase:
- an installable R package (a Shiny app shipped as a package);
- a Positron extension;
- a hosted app on Posit Connect Cloud.

None of these is a commitment or a priority. The question is which
structure keeps which of them, alone or together, open and cheap. A second
version of the app exists in Python and is not the priority, but a
structure that works across both languages would help.

- **Agent A, leprechaun:** in depth. What it generates, what it needs at
  runtime, maintenance status, and how it differs from golem function by
  function. Python counterpart, if any.
- **Agent B1, golem:** in depth, as the incumbent. Current version and what
  changed in 1.0; what `app_sys()`, `get_golem_config()` and an
  `R/app_config.R` would take to wire up here (see Context); what its
  generated structure costs or saves for each shipping route. Python
  counterpart, if any.
- **Agent B2, rhino:** in depth, including any Shiny for Python template
  from the same authors (Appsilon) as its Python counterpart. It is believed
  to be called Tapyr; confirm that it exists before describing it. Confirm from rhino's own docs
  whether a rhino app can be an R package, rather than assuming.
- **Agent B3, no framework:** a plain R package with Shiny inside, and a
  plain `app.R` with sourced files, as one report contrasting the two. The
  subject is what each leaves the project to maintain by hand: config, static
  assets, the entry point, tests. Sources: the official guidance (the
  R Packages and Mastering Shiny books, Shiny docs). Python counterpart: the
  plain Shiny for Python app layouts.
- **Agent C, shipping routes and Python:**
  1. Shipping a Shiny app inside an R package meant for release (CRAN or
     r-universe): what `R CMD check` and CRAN policy require.
  2. Whether and how a Shiny app can be shipped as or inside a Positron (or
     VS Code) extension: known examples, the mechanism, and whether the
     app's structure matters for it.
  3. Hosting on Posit Connect Cloud: what it needs to deploy an app that is
     structured as a package (entry point, manifest, dependency capture).
  4. Whether one codebase can serve routes 1 to 3 at the same time, and
     what that requires.
  5. How Shiny for Python structures a larger app (modules, packaging as a
     Python package).
- **Synthesis (the dispatching session, not an agent):** weigh every option
  against table-explorer's actual state (Context below) and write the
  report.

## Non-goals
- No edits to tracked files other than each agent's own output file, no
  branches, no commits, no package installs.
- Not a migration. No code is converted, not even as a trial.
- No recommendation on porting the Python app from Streamlit to Shiny for
  Python. Agents describe Python counterparts only; the synthesis may note
  what a choice would imply.
- No reading outside the working directory except the web.
- Each agent covers only its own subject: A leprechaun, B1 golem, B2 rhino
  and Tapyr, B3 the two no-framework layouts, C shipping routes and Shiny
  for Python structure. None compares frameworks; that is the synthesis.

## Context
- table-explorer is a Shiny app built as an R package (`tableexplorer`,
  `DESCRIPTION`), golem-structured: `R/app_ui.R`, `R/app_server.R`, 12
  `R/mod_*.R` modules, 8 `R/utils_*.R` files, `inst/app/www/`.
  (inferred: file listing)
- **golem's runtime footprint is one call.** `R/run_app.R:11` wraps
  `shinyApp()` in `golem::with_golem_options()`. Nothing else in `R/` calls
  golem. `R/tableexplorer-package.R:13` imports `get_golem_options`, which is
  never called. (inferred: `git grep golem:: -- R app.R`)
- **`inst/golem-config.yml` is inert.** There is no `R/app_config.R`, so no
  `app_sys()` and no `get_golem_config()`. As a result
  `shiny.maxRequestSize: 104857600` is never applied, and uploads fall back
  to Shiny's 5 MB default. (inferred: `git grep` for `app_sys`,
  `get_golem_config`, `maxRequestSize`)
- `dev/01_start.R`, `dev/02_dev.R` and `dev/03_deploy.R` are golem scaffold
  scripts, mostly commented out.
- `dev/code-review-backlog.md` (review of 2026-09-04, run against an older
  branch) lists golem-conformance findings C3, I5, I13, M9, M10, M11 and
  open decision D1 ("`inst/golem-config.yml`: wire it or delete it"). C3, I5
  and M9 still hold on current `main`. The others are unverified on `main`.
- There is no `.Rbuildignore` (backlog I6), which matters for any package
  release.
- The Python version is a single Streamlit file, `app.py` (1875 lines), not
  Shiny for Python.
- Hosting today: the README describes deploying to Posit Connect via the
  Posit Publisher extension or Git import. Its free-plan limits match Posit
  Connect Cloud's Free plan (4 GB RAM, 20 active hours, 5 apps), except that
  it says 1 CPU where Posit's December 2024 announcement says 2. Checked
  2026-10-02. `dev/03_deploy.R` holds a commented
  `rsconnect::deployApp()`. There is no CI. renv is being considered (not
  adopted).
- Agents and Amelia both work on the code; Air (formatter) and testthat
  edition 3 are in use.
- Build and test (for reference only; agents do not run them):
  `Rscript.bat -e "testthat::test_local()"` in PowerShell, R 4.6.1, with
  the real packages installed. Baseline on `main` at `6276a1e`: 209 tests,
  1035 expectations, 0 failed, 4 expected skips.
  `Rscript dev/fixtures/score_detection.R` gives 157 of 157 real links, 0
  false.

## Constraints
- Primary sources first: CRAN package pages, the package's GitHub repo
  (README, NEWS, issues, commit history), official docs (Posit, CRAN
  policy, VS Code and Positron extension docs). Blog posts and talks only
  for opinions, and labelled as opinion.
- Every factual claim gets a source URL. Version-dependent claims name the
  version. Anything taken from model memory without a source is marked
  `[unverified]`.
- Check function names and arguments against current docs. Do not trust
  memory for them.
- For each package (A, B1, B2, and Tapyr in B2): current release version and
  date, last GitHub commit date, open issue count, maintainer, and runtime
  dependencies (what an installed or deployed app must install).
- No em dashes. No hostnames, credentials or local paths in output.
- Stop and report rather than guess when: web access fails; a package
  appears archived or renamed; sources contradict each other on a point that
  matters to the comparison.

## Edge cases
- Package archived on CRAN or GitHub repo archived: flag it prominently, and
  still describe the package.
- Source older than 2 years: may be used, labelled with its date.
- Feature present in GitHub dev version but not on CRAN: report both, and
  label which is which.
- Claims of "zero runtime dependency" or "lighter": verify against
  `DESCRIPTION` Imports, not against marketing text.
- No Python counterpart exists: say "none found" and what was searched. Do
  not stretch a loose resemblance into a counterpart.
- Positron extension mechanism undocumented or only shown in demos: report
  what exists, labelled as demo or experimental, with dates.
- Posit Connect Cloud (hosting and publishing) is not Posit Cloud (hosted
  IDE workspaces), nor self-hosted Posit Connect, nor shinyapps.io. Sources
  mix them up. Use only material about Connect Cloud for route 3, and say so
  when a source is unclear about which service it means.
- A shipping route that works with any structure: say so plainly. It then
  does not separate the options, and the synthesis should not count it as
  if it did.

## Output requirements
- Files, all in `docs/research/shiny-framework/`, Markdown, each at most
  about 1500 words:
  - Agent A: `leprechaun.md`
  - Agent B1: `golem.md`
  - Agent B2: `rhino.md`
  - Agent B3: `no-framework.md`
  - Agent C: `shipping-and-python.md`
- Agents A, B1, B2 and B3 use one section skeleton per option: what it is;
  status facts (the Constraints list, or "not a package" for B3); what it
  generates or requires; runtime vs dev-time dependencies; config handling;
  testing story; fit with each shipping route (R package, Positron
  extension, Posit Connect Cloud); Python counterpart; renv
  interplay; notable limits or open issues; what could not be verified;
  sources.
- Agent C uses one section per question (1 to 5), each ending in sources.
- Synthesis: `docs/research/shiny-framework/decision.md`. It contains:
  - a matrix of options (rows) against shipping routes (columns), with each
    cell saying whether the route is supported, at what cost, and why;
  - which combinations of routes each option allows from one codebase;
  - a comparison on the ranked criteria below;
  - the migration cost from table-explorer's current state for each option;
  - which backlog items (C3, I5, I13, M9, M10, M11, D1) each option resolves
    or makes moot;
  - trade-offs to weigh, with a recommendation only where one option clearly
    wins for a given combination of routes;
  - what is still weak.
- Summary in chat. Files stay uncommitted until Amelia says to commit.

## Acceptance and evidence
- Each package section has every status fact from Constraints, each with a
  URL, or an explicit "not found".
- Spot check: the dispatching session opens 2 cited URLs per agent (10 in
  all) and confirms that each one supports the claim it is attached to.
- Every leprechaun, golem and rhino function the reports name exists in the
  current reference index (checked by the dispatching session against the
  pkgdown or CRAN reference page).
- Every option has a Python counterpart entry, either a link or "none
  found".
- The synthesis matrix has no blank cells, and maps every backlog item
  listed to each option.
- Shipping routes are not ranked; each option is judged against each of
  them. Ranked criteria, in this order:
  1. Compatibility with the Python version (shared structure or a Python
     counterpart).
  2. Migration cost from the current state.
  3. Maintenance health of the package.
  4. Testability with testthat and shinytest2.
  5. How easily agents can work in the structure.
  6. Runtime dependency weight.
- Each agent states what it could not find or verify, and how many
  `[unverified]` claims remain.

## Open assumptions
- None. (Resolved 2026-10-02: PRs #21 and #22 are merged, and both cloud
  sessions reported nothing pending.)
