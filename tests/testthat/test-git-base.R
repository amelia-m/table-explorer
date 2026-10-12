# dev/git_base.R is development tooling, not part of the package, so it is
# sourced here rather than loaded with the package.
source(test_path("..", "..", "dev", "git_base.R"))

sha_a <- "1111111111111111111111111111111111111111"
sha_b <- "2222222222222222222222222222222222222222"

test_that("a local branch behind the remote is reported as behind, with the fix", {
  res <- git_base_status(sha_a, sha_b, behind = 75L, ahead = 0L)
  expect_identical(res$state, "behind")
  expect_match(res$message, "75 commits behind origin/main")
  expect_match(res$message, "dev/sync-main.sh", fixed = TRUE)
})

test_that("one commit behind says commit, not commits", {
  res <- git_base_status(sha_a, sha_b, behind = 1L, ahead = 0L)
  expect_match(res$message, "1 commit behind", fixed = TRUE)
})

test_that("matching shas are current, so the check does not cry wolf", {
  res <- git_base_status(sha_a, sha_a, behind = 0L, ahead = 0L)
  expect_identical(res$state, "current")
  expect_match(res$message, "main matches origin/main", fixed = TRUE)
})

test_that("a local branch ahead of the remote is not a stale base", {
  # Unpushed work on main is a different problem, and failing the check for it
  # would make the check useless on a branch that is merely unpushed.
  res <- git_base_status(sha_a, sha_b, behind = 0L, ahead = 3L)
  expect_identical(res$state, "ahead")
})

test_that("divergence is reported as a decision, not fast-forwarded away", {
  res <- git_base_status(sha_a, sha_b, behind = 4L, ahead = 2L)
  expect_identical(res$state, "diverged")
  expect_match(res$message, "4 behind, 2 ahead", fixed = TRUE)
})

test_that("an unreadable remote is unknown, not a failure", {
  res <- git_base_status(
    sha_a,
    NA_character_,
    behind = NA_integer_,
    ahead = NA_integer_
  )
  expect_identical(res$state, "unknown")
})

test_that("a missing local branch is unknown, which is the CI case", {
  # A GitHub Actions checkout has the pull request head, not refs/heads/main.
  res <- git_base_status(
    NA_character_,
    sha_b,
    behind = NA_integer_,
    ahead = NA_integer_
  )
  expect_identical(res$state, "unknown")
  expect_match(res$message, "no local main branch", fixed = TRUE)
})

test_that("differing shas with no counts fail, rather than passing as current", {
  # The remote tip has never been fetched, so rev-list cannot count. Not
  # knowing how far behind you are is not the same as being up to date.
  res <- git_base_status(
    sha_a,
    sha_b,
    behind = NA_integer_,
    ahead = NA_integer_
  )
  expect_identical(res$state, "differs")
  expect_match(res$message, "the distance is unknown", fixed = TRUE)
})

test_that("a clone whose main is behind its remote is caught end to end", {
  # The failure this guards against, reproduced: a checkout whose main is
  # behind the remote's main, with no network involved because the remote is
  # a local path. ls-remote reads it and writes nothing.
  skip_if_not(nzchar(Sys.which("git")), "git not on PATH")
  root <- tempfile("gitbase-e2e")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  far <- file.path(root, "far")
  near <- file.path(root, "near")

  run <- function(repo, ...) {
    system2("git", c("-C", shQuote(repo), ...), stdout = FALSE, stderr = FALSE)
  }
  dir.create(far)
  run(far, "init", "--quiet", "--initial-branch=main")
  run(far, "config", "user.email", "test@example.invalid")
  run(far, "config", "user.name", "Test")
  writeLines("one", file.path(far, "f.txt"))
  run(far, "add", "f.txt")
  run(far, "commit", "--quiet", "-m", "one")

  system2(
    "git",
    c("clone", "--quiet", shQuote(far), shQuote(near)),
    stdout = FALSE,
    stderr = FALSE
  )
  expect_identical(git_base_check(repo = near)$state, "current")

  # The remote moves, as a merge on the forge moves it, and nothing pulls.
  writeLines("two", file.path(far, "f.txt"))
  run(far, "commit", "--quiet", "-a", "-m", "two")

  # A clone that has never fetched cannot count the distance, so it reports
  # that the base differs rather than claiming to be current.
  res <- git_base_check(repo = near)
  expect_identical(res$state, "differs")
  expect_match(res$message, "the distance is unknown", fixed = TRUE)

  # Once the remote commit is in the clone, the distance is countable.
  run(near, "fetch", "--no-write-fetch-head", "--quiet", "origin", "main")
  res2 <- git_base_check(repo = near)
  expect_identical(res2$state, "behind")
  expect_match(res2$message, "1 commit behind", fixed = TRUE)
})

test_that("the counts come from a real repository", {
  skip_if_not(nzchar(Sys.which("git")), "git not on PATH")
  repo <- file.path(tempfile("gitbase"))
  dir.create(repo, recursive = TRUE)
  on.exit(unlink(repo, recursive = TRUE), add = TRUE)

  run <- function(...) {
    system2("git", c("-C", shQuote(repo), ...), stdout = FALSE, stderr = FALSE)
  }
  run("init", "--quiet", "--initial-branch=main")
  run("config", "user.email", "test@example.invalid")
  run("config", "user.name", "Test")
  writeLines("one", file.path(repo, "f.txt"))
  run("add", "f.txt")
  run("commit", "--quiet", "-m", "one")
  run("branch", "later")
  writeLines("two", file.path(repo, "f.txt"))
  run("commit", "--quiet", "-a", "-m", "two")
  writeLines("three", file.path(repo, "f.txt"))
  run("commit", "--quiet", "-a", "-m", "three")

  old <- git_local_sha("later", repo)
  new <- git_local_sha("main", repo)
  expect_false(is.na(old))
  expect_false(is.na(new))
  expect_identical(git_commits_between(old, new, repo), 2L)
  expect_identical(git_commits_between(new, old, repo), 0L)
  expect_identical(git_local_sha("no-such-branch", repo), NA_character_)
})
