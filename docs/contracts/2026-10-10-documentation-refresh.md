# Task contract: bring the repository's documentation back to the code

Date: 2026-10-10  Dispatch: two agents in parallel, disjoint file lists
Request as given: "Dispatch additional agents to update the documentation
throughout the repo and update any artifacts related to it"

## Intent and scope

The app has changed under its documentation. `README.md` still says the
package is built on golem, which was dropped in PR #23, and still advertises
"7-signal FK detection" when there are more signals than that. The internals
document and its generated diagrams describe mechanisms that have since
gained features. The measurement harness added in this session has no
documentation at all.

The work is to make every documentation file in the repository true of the
code on `main`, and to regenerate the artifacts that are built from a script
rather than written by hand. The audience is Amelia, a reader arriving at the
repository cold, and the agents who work here next.

Two agents, disjoint file lists, so neither waits for the other.

- **Agent A, the outward-facing documents**: `README.md`,
  `docs/erd-redesign-plan.md`, `dev/browser-checks/README.md`. Branch
  `docs/readme-refresh`, worktree
  `C:\Users\04291899\git\aam\table-explorer\_scratch\wt-docs-readme`.
- **Agent B, the internals and the development documents**:
  `docs/internals.md`, `docs/diagrams/generate.py` and the SVG files it
  produces, `dev/fixtures/README.md`, a new
  `dev/fixtures/public/README.md`, and `dev/code-review-backlog.md`. Branch
  `docs/internals-refresh`, worktree
  `C:\Users\04291899\git\aam\table-explorer\_scratch\wt-docs-internals`.

## Non-goals

- **Change no code.** Do not touch anything under `R/`, `tests/`,
  `inst/`, `dev/*.R`, `dev/*.js`, `app.R`, `app.py` or the root-level
  `.R` files. The one exception is Agent B's `docs/diagrams/generate.py`,
  which is a documentation artifact generator, not app code. If a document
  is wrong because the code is wrong, say so in the report and leave the
  code alone.
- **Do not document unmerged work.** Several branches are open, including a
  containment signal for foreign key detection and three detection rules in
  PR #54, and the decisions about them are Amelia's and not yet made.
  Document the behaviour of `main` only. Do not read those branches for
  content to document.
- Do not touch the other agent's files. Agent A does not open
  `docs/internals.md`; Agent B does not open `README.md`.
- Do not touch `TODO.md`, `CLAUDE.md`, `.agents/project-profile.md`,
  `docs/contracts/` or `docs/research/`. Those are handled outside this
  contract. If you find something that belongs on the open list, put it in
  your report instead and say it belongs in `TODO.md`.
- No new documents beyond the one named for Agent B.
- Do not rewrite a document that is already accurate for the sake of style.
  Fix what is false, fill what is missing, and leave the rest.
- No reformatting pass, no Air run, no renv operations. Do not merge, open a
  pull request, or delete branches.

## Context

- R package `tableexplorer`, a Shiny app for finding and documenting table
  relationships in files and databases. A secondary Python/Streamlit version
  lives in the root-level `app.py` and its helpers, and is not actively
  maintained.
- Your worktree is already created and checked out at the branch named for
  you, from `main` at commit c11748b. Work there and nowhere else.
- Known staleness, found by inspection and not exhaustive. Verify each
  against the code before you write anything, including these:
  - `README.md` has a section headed "Architecture (golem package)" and
    describes the app as structured with golem. PR #23 dropped golem; the
    app is a plain R package. `inst/golem-config.yml` may still exist on
    `main`: say what you find rather than assuming either way.
  - `README.md` says "7-signal FK detection". Count the signals in
    `weight_map` in `R/utils_inference.R` and name them from `label_map`.
  - `README.md` calls the tab "ERD Diagram". The app dropped the redundant
    word and calls it "ERD" (PR #37, `R/app_ui.R`).
  - The sidebar is collapsible with a labelled edge rail (PR #26), there is
    a busy indicator and a build stamp in the footer (PR #41), the
    relationships table has an evidence column with child rows, parent rows
    and overlap percent and a "to review only" filter (PR #32, #38), and
    shared columns that are not foreign keys are reported as their own class
    (PR #39 area). Check each in the code before describing it.
  - `docs/internals.md` describes four mechanisms and says to run
    `python3 docs/diagrams/generate.py` when one changes. Check whether the
    diagrams still match the code they describe.
  - `dev/fixtures/README.md` documents the synthetic fixture and scorer.
    The public-dataset harness (`dev/fixtures/public/fetch.R`,
    `score_public.R`, `truth/`) has no README.
- The measurement harness, for Agent B's new README: `fetch.R` downloads or
  locates each public dataset into the user cache; `score_public.R <names>`
  loads whole tables, runs `detect_fks()`, compares the result against ground
  truth and prints tables, truth, found, hit, recall, precision and seconds.
  Ground truth is read from declared constraints where a dataset has them
  (Chinook, SQLite) and from a hand-written file under `truth/` where it does
  not (FAERS, Lahman). Lahman comes from the CRAN `Lahman` package rather
  than a download. Pagila is named in the harness but deferred, because it
  needs a running Postgres instance (Amelia, 2026-10-10), so
  `score_public.R pagila` reports what it parsed and stops. The harness reads
  whole tables on purpose: a foreign key is a claim about value containment,
  so an earlier 20,000-row cap produced recall figures that were artefacts of
  the cap. Say that in the README, because the next person to find it slow
  will want to add the cap back.
- Verification, from your worktree root, with the environment variable set
  because a fresh worktree has no renv library:
  `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" dev/check.R`
  It parses every R and JS file, runs the test suite with counts, runs the
  synthetic detection scorer, and exits non-zero on any failure. A
  documentation-only change must leave it passing, which is also how you
  confirm you changed no code by accident.
- R is at "C:\Program Files\R\R-4.6.1\bin\Rscript.exe". Never run
  `Rscript -e` with inline code on this machine: paths with spaces make it
  segfault. Put code in a file and run the file.
- Agent B needs Python for the diagrams. Check whether `python3` or `python`
  resolves before planning on it. If neither does, or the script's
  dependencies are missing, leave the SVG files alone, say so in the report,
  and still fix the prose.

## Constraints

- **Every statement you write must be checked against the code**, and your
  report says where. A feature table that lists something the code does not
  do is worse than a table that omits it, because a reader has no way to
  tell which rows were checked.
- **Anything you could not verify is written as an assumption**, in the
  document if it belongs there and in the report either way, together with
  the check that would settle it. Her standing rule: a claim that something
  is absent, empty or not implemented, made without checking it directly, is
  written as an assumption with the check beside it.
- Keep each document's existing shape and voice. `README.md` keeps its
  feature table; `docs/internals.md` keeps its four-mechanism structure and
  its colour convention.
- No em dash (U+2014) anywhere, including commit messages. Use a spaced
  hyphen, a comma, a colon, or two sentences.
- No infrastructure identifiers anywhere: no hostnames, database names,
  connection strings, credentials, internal URLs, account identifiers, or
  the full local path of a confidential project. Name an environment
  variable or a file to look at instead. The worktree paths in this contract
  are fine; a server name is not.
- A script must not write a file before all its assertions have passed.
- Dates come from the system (`Sys.Date()`, `date`), never from memory or
  from a timestamp in someone else's output.
- Commits may carry `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`;
  attribution is allowed in this repository (Amelia, 2026-10-02).
- Stop and report rather than deciding alone when: a document's claim is
  false in a way that looks like a code defect rather than stale prose, a
  feature's behaviour cannot be determined from the code without running the
  app against real data, or fixing a document would need a change under
  `R/`.

## Edge cases

- **A feature that exists but is unreachable from the UI**: describe it as
  the code has it and flag the gap in the report. Do not quietly drop it.
- **A feature whose behaviour depends on data you do not have** (an Access
  file, a database connection, a real extract): describe what the code
  does, say the behaviour was read from the code and not observed, and put
  it in the report's unverified list.
- **A document that describes a plan rather than the code**
  (`docs/erd-redesign-plan.md` is a plan): do not rewrite it as if it were
  reference documentation. Mark which steps are done, from the code, and
  leave the rest as plan.
- **A diagram whose source script will not run**: leave the SVG untouched,
  fix the prose around it, and say in the report exactly what failed.
- **A README section about the Python version**: it is not actively
  maintained. Correct anything plainly false, do not expand it, and do not
  go hunting through `app.py` for features to add.
- **Two documents that contradict each other** on the same mechanism: the
  code decides, and the report names the pair so the loser can be checked.
- **A link to an external site**: leave it. Do not fetch anything to verify
  a third-party URL.

## Output requirements

- Only the files listed for your agent, changed in place.
- Agent B's new `dev/fixtures/public/README.md` says: what each dataset is,
  where it comes from and roughly how big it is, how to fetch it, how to run
  the scorer, how to read each column of its output, where ground truth
  comes from for each dataset and how trustworthy it is, that Pagila is
  deferred and why, and that whole tables are read on purpose.
- Logical commits, one per document or per coherent group, with messages
  saying what was wrong and why the new text is right. Push the branch. No
  pull request.
- A report listing, per document, what you changed and the file and line in
  the code that justifies each substantive claim.

## Acceptance and evidence

1. `dev/check.R` prints ALL CHECKS PASSED in your worktree, both before you
   start and after your last commit, and `git status` is clean. Quote both
   runs' summary lines.
2. `git diff --stat main..<your branch>` touches only the files listed for
   your agent, shown verbatim.
3. For Agent A: the golem claim is gone from `README.md`, the signal count
   matches `weight_map`, and the tab is called "ERD". For each, the report
   names the file and line in the code it was checked against.
4. For Agent B: `dev/fixtures/public/README.md` exists and covers every item
   listed in Output requirements, and the report says for each dataset
   whether its ground truth is declared or hand-written.
5. For Agent B: either the SVG files are regenerated and `git diff --stat`
   shows them changed, or the report says which command failed and what it
   printed.
6. A list of every claim in your documents that you could not verify from
   the code, each with the check that would settle it. An empty list is only
   acceptable if you genuinely verified everything, and then you say so.
- The agent shows: both `dev/check.R` summaries; the `git diff --stat`;
  the commit subjects; for each acceptance line above, the command or file
  and line that proves it.
- The agent lists, in full wording and not only in a commit message,
  everything it deferred or left out of scope with who decides it, and every
  claim it did not check directly, each with the check that would settle it.

## Settled (Amelia, 2026-10-10)

- Documentation is refreshed against `main`, not against the open branches.
  The detection work in PR #54 and the containment branch is undecided, so
  documenting it now would document something that may not ship.
- Two agents, split as above. The split is by file so that neither can
  conflict with the other, and both avoid `R/`, which the containment work
  is still changing.
