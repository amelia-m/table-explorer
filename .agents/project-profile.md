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
