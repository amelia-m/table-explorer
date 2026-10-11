# Project profile: table-explorer

Claude Code loads this file through `CLAUDE.md` at the repository root. Other
agents working here should be told to read it.

## What agents do here

Agents write and test the R/Shiny app and its helpers, write documentation,
research notes and synthetic test fixtures, review code, and commit the
results. The Python version (`app.py`) is secondary and changes only when
asked.

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
