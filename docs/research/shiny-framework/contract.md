# Task contract: Shiny app framework options for table-explorer

Date: 2026-09-30  Status: awaiting Amelia's approval
Dispatch: 3 research agents in parallel (general-purpose, web access), then
synthesis by the dispatching session
Request as given: "dispatch agents to learn about the leprechaun alternative to
golem and weigh pros/cons of those and other approaches for managing shiny
applications."

## Intent and scope
Decision input for table-explorer: keep golem, switch to leprechaun, move to
another approach, or drop the framework and stay a plain R package. Amelia
decides; the report recommends. The future is open. Amelia may release the
app as an R package (a Shiny app shipped as a package) and/or as a Positron
extension. A second version of the app exists in Python and is not the
priority, but a structure that works across both languages would help.

- **Agent A, leprechaun:** in depth. What it generates, what it needs at
  runtime, maintenance status, and how it differs from golem function by
  function. Is there a Python counterpart, or a structure it maps onto?
- **Agent B, other R options:** golem, rhino, a plain R package with no
  framework, and plain `app.R` plus sourced files. The same facts for each,
  side by side. For each, note any Python equivalent (for example a Shiny
  for Python template from the same authors), with a link.
- **Agent C, distribution and cross-language:**
  1. Shipping a Shiny app inside an R package meant for release (CRAN or
     r-universe): what `R CMD check` and CRAN policy require of such
     packages, and how each option helps or hinders that.
  2. Whether and how a Shiny app can be shipped as or inside a Positron (or
     VS Code) extension: known examples, the mechanism, and whether the app
     needs a framework at all for that.
  3. How Shiny for Python structures a larger app (modules, packaging as a
     Python package), so the synthesis can judge how close an R structure
     can sit to a Python one.
- **Synthesis (the dispatching session, not an agent):** weigh every option
  against table-explorer's actual state (Context below) and write the
  recommendation.

## Non-goals
- No edits to tracked files other than each agent's own output file, no
  branches, no commits, no package installs.
- Not a migration. No code is converted, not even as a trial.
- No recommendation on porting the Python app from Streamlit to Shiny for
  Python. Agent C describes Shiny for Python's structure only; the synthesis
  may note what the choice would imply.
- No reading outside the working directory except the web.
- Agent A researches only leprechaun. Agent B covers the four options above
  and not leprechaun. Agent C covers distribution and Python structure and
  no framework comparison.

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
- Deployment today: Posit Connect, via `rsconnect` or Git import (README,
  `dev/03_deploy.R`). There is no CI. renv is being considered (not adopted).
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
  policy, VS Code extension API). Blog posts and talks only for opinions,
  and labelled as opinion.
- Every factual claim gets a source URL. Version-dependent claims name the
  version. Anything taken from model memory without a source is marked
  `[unverified]`.
- Check function names and arguments against current docs. Do not trust
  memory for them.
- For each package (Agents A and B): current CRAN version and date, last
  GitHub commit date, open issue count, maintainer, and runtime Imports (what
  an installed or deployed app must install).
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
- An option that is really a philosophy, not a package (plain package, plain
  `app.R`): describe it through what it requires the project to maintain by
  hand.
- No Python equivalent exists: say "none found" and what was searched. Do
  not stretch a loose resemblance into an equivalent.
- Positron extension mechanism undocumented or only shown in demos: report
  what exists, labelled as demo or experimental, with dates.

## Output requirements
- Files, all in `docs/research/shiny-framework/`, Markdown, each at most
  about 1500 words:
  - Agent A: `leprechaun.md`
  - Agent B: `r-options.md`
  - Agent C: `distribution-and-python.md`
- Agents A and B use one section skeleton per package or option: what it
  is; status facts (the Constraints list); what it generates; runtime vs
  dev-time dependencies; config handling; testing story; fit with releasing
  as an R package; Python equivalent; deployment to Posit Connect; renv
  interplay; notable limits or open issues; sources.
- Agent C uses one section per question (1 to 3), each ending in sources.
- Synthesis: `docs/research/shiny-framework/decision.md`. It contains:
  - a comparison table;
  - the migration cost from table-explorer's current state for each option;
  - which backlog items (C3, I5, I13, M9, M10, M11, D1) each option resolves
    or makes moot;
  - a recommendation with reasons;
  - what is still weak.
- Summary in chat. Files stay uncommitted until Amelia says to commit.

## Acceptance and evidence
- Each package section has every status fact from Constraints, each with a
  URL, or an explicit "not found".
- Spot check: the dispatching session opens 3 cited URLs per agent and
  confirms that each one supports the claim it is attached to.
- Every leprechaun and golem function the reports name exists in the current
  reference index (checked by the dispatching session against the pkgdown
  or CRAN reference page).
- Every option has a Python-equivalent entry, either a link or "none found".
- The synthesis maps every backlog item listed to each option, with no
  blanks.
- Criteria, in priority order:
  1. Fit with releasing as an R package (Shiny app as package) and possibly
     as a Positron extension.
  2. Compatibility with the Python version (shared structure or a Python
     equivalent).
  3. Migration cost from the current state.
  4. Maintenance health of the package.
  5. Testability with testthat and shinytest2.
  6. How easily agents can work in the structure.
  7. Runtime dependency weight and deployment to Posit Connect.
- Each agent states what it could not find or verify, and how many
  `[unverified]` claims remain.

## Open assumptions
- None. (Resolved 2026-10-02: PRs #21 and #22 are merged, and both
  cloud sessions reported nothing pending.)
