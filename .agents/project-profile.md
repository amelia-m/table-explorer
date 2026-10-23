# Project profile: table-explorer

Claude Code loads this file through `CLAUDE.md` at the repository root. Other
agents working here should be told to read it.

## What agents do here

Agents write and test the R/Shiny app and its helpers, write documentation,
research notes and synthetic test fixtures, review code, and commit the
results. The Python version (`app.py`) is secondary and changes only when
asked.

## Correctness outweighs speed

Amelia, 2026-10-10. Where the two conflict, take the slower, complete
answer. This came from a measurement harness that read the first 20,000
rows of each file so a comparison would finish in seconds: a foreign key
is a claim about value containment, so reading part of each table broke
the property being measured and produced recall figures that were
artefacts of the cap. The numbers were reported before anyone noticed.

In practice:
- Measurement reads whole tables. If a cap is unavoidable, sample by key
  so related rows survive together, and print the cap on every line of
  output so a partial run cannot be read as a clean one.
- The app's own sampling (10,000-row profiles, the 20,000 column-pair
  cap, the 60-column trim) is a different trade, made for an interactive
  session, and stays. It belongs in the open list, not in silence: a
  count drawn from a sample says so where it is shown.
- A slow check that answers the question beats a fast one that answers a
  different question.
## Read identifiers from the data, not from documentation

Amelia asked why a particular mistake happened, 2026-10-11. A hand-written
ground-truth file for the CRAN `Lahman` package named the column
`homegames.parkkey`. The package calls it `park.key`, with a dot, because
the upstream CSV header does, while most of its other tables use camel case.
The name was written from the package documentation without opening the data.
Detection found the link correctly and the harness reported it as a miss for
a day, because a wrong line in a measuring instrument looks exactly like a
weakness in the thing being measured.

- **Any identifier that goes into a durable artifact is read from the thing
  itself.** A column name from `names(df)`, a branch tip from
  `git ls-remote`, a path from `ls`. Not from documentation, not from release
  notes, not from recall. The command that read it goes in the file header,
  the commit message or the report.
- **A measuring instrument validates itself.** A ground-truth file's loader
  asserts that every table and column it names exists in the loaded data and
  exits non-zero when one does not, so a typo fails loudly instead of
  scoring as a miss. The same holds for any file of expected values.
- **One anomaly means suspect the instrument first.** When a measurement
  shows exactly one miss, one outlier or one unexplained row, check the
  measuring file before concluding anything about the subject.

The same failure shape bit a task contract the same day: it told two agents
`main` was at c11748b, read from the local branch, while `origin/main` was
fifteen merged pull requests ahead. Both agents spent a full run documenting
a tree that no longer existed, and reported the brief's premises as false.
Before cutting a worktree or quoting a commit in a brief, compare
`git rev-parse main` with `git ls-remote origin refs/heads/main`. Pull
requests here are merged on GitHub and nothing pulls afterwards, so the local
`main` is routinely tens of commits stale.

## Public test data from R packages

Amelia, 2026-10-17, on the CRAN `fec16` package (Federal Election Commission data, 2015-2016 cycle, which includes individual contributors' ZIP codes): "we can use it to test and refer to it in docs (with the fec16 package as provenance) but don't commit copies of its data."

- **Use it, cite it, do not copy it.** Tests and measurements load it from the installed package (`utils::data(..., package = "fec16")`) and skip when it is not installed. Docs name the package and version as the source.
- **Nothing from it is committed**: no fixtures, extracts, CSVs, snapshots or printed rows. Counts and rates measured on it may be committed.
- Other R-package datasets follow the same rule until Amelia says otherwise for a given package.
- **EM 42 does not classify these datasets.** Amelia, 2026-10-17: "em 42 applies to work data". What decides it is where the data came from, not which project uses it: public data used in a work project is still not classified under EM 42; anything obtained through work counts as work data, even if it looks public; a public file joined to work data becomes work data. So do not raise EM 42 classification as a question about a public dataset. Her own data stays under the global rule.

## Open items written elsewhere

The rule now lives in the global rules, under "Keep open items alive": when open items have to be written somewhere other than `TODO.md` (a contract's file scope, a checkout in use, a pull request body, a subagent's hand-back), a one-line pointer goes into `TODO.md` in the same work block, naming the note's path and how many items it holds; a note under `_scratch/` with no pointer counts as not written; and a dispatching session carries every deferred item, not only the ones it acts on. It came from this repository (Amelia, 2026-10-19: eight open items found in three notes under `_scratch/`).

One addition kept here: **at the end of a work block, check `_scratch/` for open-item notes** and move or retire each one. That includes review reports a subagent hands back: their unapplied findings go into `TODO.md`, or a pointer to a saved copy, before replying to Amelia (2026-10-23, after a review's findings sat in the session unrecorded).

## Review, push and merge

Amelia, 2026-10-09, for this repository only. Her GitHub Copilot and Codex
review quotas are small, and Copilot has already declined a review here for
lack of quota.

- **Do not request Copilot or Codex review on GitHub.** Hosted bot review
  happens only when she asks for it by name.
- **Review locally before opening the pull request**, choosing the skill from
  the routing table in the global `CLAUDE.md` ("Which review skill for which
  job"). Put the findings and what was done about each in the pull request
  body.
- **After a clean local review, an agent may merge and push without asking
  her first.** This replaces the earlier "Amelia approves every push and
  merge" line for this repository. Branch deletion still needs her go-ahead,
  as does anything else the global rules gate (force pushes, resets,
  discarding work, changing remotes or settings).
- **Verification is a command whose result you quote, never the absence of
  output.** Run `Rscript dev/check.R`: it parses every R and JS file, runs
  the suite and reports the counts, runs the detection scorer, and exits
  non-zero on any failure. Quote its summary lines in the pull request. An
  empty grep, a missing "Failed" header or a silent command is not evidence
  that anything passed. Twice in one session an edit half-applied and the
  signal that should have caught it was silence.
- **Do not let a script write a file before all of its assertions have
  passed.** A multi-step edit that writes as it goes leaves the file half
  changed when a later step fails. Either use the editing tools, or build
  the whole new content in memory and write once at the end.
- CI runs on every pull request (`.github/workflows/r-ci.yml`, added in #45 on 2026-10-09: the test suite, then the detection scorer against the synthetic fixture), and its result belongs in the pull request body. Run `testthat::test_local()` and `Rscript dev/fixtures/score_detection.R` locally before pushing as well, and name the command with its output when CI has not run yet.
- A change that cannot be checked without her eyes (visual or interaction
  work on real data) says so in the pull request and waits for her, however
  clean the review.

## AI attribution

Allowed (Amelia, 2026-10-02). Commits and pull request text in this
repository may carry the harness's attribution lines: a `Co-Authored-By:`
trailer naming the agent, and the "Generated with Claude Code" footer on pull
requests. This answers the global rule "AI attribution in git and pull
requests is decided per project" for table-explorer only.
