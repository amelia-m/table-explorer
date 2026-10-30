# Project profile: table-explorer

Claude Code loads this file through `CLAUDE.md` at the repository root. Other
agents working here should be told to read it.

## What agents do here

Agents write and test the R/Shiny app and its helpers, write documentation,
research notes and synthetic test fixtures, review code, and commit the
results. The Python version (`app.py`) is secondary and changes only when
asked.

## Project type

A work-adjacent personal project that does not contain work data (Amelia, 2026-10-28: "work-adjaccent [sic] personal project but does not contain work data"). Under the global rule "Notes in work projects" it counts as personal: one shared `TODO.md`, no `*.local.md` split and no findings log.

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

**What this rule covers, and what it does not** (Amelia, 2026-10-16). It is
"primarily aimed at app design and code habits": how agents measure, verify
and write code. It is not an instruction to make the app itself slow by
default. The app "should still have some speed prioritization but with
warnings and options to use more thorough/slower procedures." In practice,
for a user-facing default:

- Default to the fast path when the fast path is usually right.
- Say so whenever the fast path may not have been right for this data, at
  the moment it matters, in terms of what the user can do about it.
- Offer the thorough path as a setting, named for what it costs.

The worked case is Excel type guessing: readxl's 1000-row guess is the
default, a sheet longer than 1000 rows says so when it loads, and "Guess
from every row" is one setting away.

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
- There is no CI here yet, so the output of `testthat::test_local()` and
  `Rscript dev/fixtures/score_detection.R` stands in for it and belongs in the
  pull request body, named with the command that produced it. Pulling the
  Actions workflow out of draft PR #6 is on `TODO.md` and would change this.
- A change that cannot be checked without her eyes (visual or interaction
  work on real data) says so in the pull request and waits for her, however
  clean the review.

## AI attribution

Allowed (Amelia, 2026-10-02). Commits and pull request text in this
repository may carry the harness's attribution lines: a `Co-Authored-By:`
trailer naming the agent, and the "Generated with Claude Code" footer on pull
requests. This answers the global rule "AI attribution in git and pull
requests is decided per project" for table-explorer only.

## Describe Amelia's own data generically

Amelia, 2026-10-21: "update that note to be more generic and implement a rule to keep notes like that generic", after a tracked contract described her own extract, and "take real column names out of todo and force scrub from history", after real column names from it were found in `TODO.md`, a contract, code comments and tests. This repository is public, and a commit is where text stops being removable.

- **In anything tracked** (`TODO.md`, contracts, docs, code comments, tests, commit messages, pull request text), refer to her own data only generically: "her own data", "a real extract", "a count column wholly inside an unrelated measurement column".
- **Never write** its table or column names, its counts (tables, rows, links, flagged columns), what domain it comes from, how particular columns are stored, or quotes of her describing it. Those stay in chat.
- **Test fixtures and examples use invented names** that do not mirror hers. Public datasets (Chinook, FAERS, Lahman, fec16 and the like) may be named; how to use and cite them is in the section "Public test data from R packages", added by #68.
- **Check before committing.** When a change came out of work on her data, read the diff for anything that would identify it, and replace it in place before the commit, never after.

**History was scrubbed once, out of caution** (2026-10-21). Real names, counts and descriptions were replaced with invented ones in every file and commit message on every branch, and 49 of 58 branches were force-pushed (the other nine held nothing to change); commits from 2026-09-24 on have new ids, and the 46 earlier ones kept theirs. In Amelia's words the names "aren't confidential or proprietary", so it was caution, not a breach. The old commits stay reachable on GitHub through the refs and timelines of the pull requests opened before the rewrite, and she decided not to ask GitHub Support to purge them: "nothing is that important ... no need to get support involved" (2026-10-21). Two consequences for agents:

- **Merging old history into new brings the names back**, through the old commits and their messages, whether or not the files conflict. So pull with `git pull --ff-only`, which fails loudly when a branch and its `origin` tip have diverged instead of merging them. If a merge of a diverged branch has started anyway, abort it with `git merge --abort` and ask Amelia before going further: re-syncing means moving the branch to its `origin` tip, which is a reset, and any local commits not on `origin` are re-applied onto the new tip (cherry-picked), never discarded.
- **Never base new work on a pre-rewrite commit id**, including ids quoted in older pull request bodies, contracts or notes; read the current tip with `git ls-remote origin refs/heads/<branch>`.
