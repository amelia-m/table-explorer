# Is the local base branch still the base? Functions only, no side effects.
#
# Why this exists: pull requests here are merged on GitHub and nothing pulls
# afterwards, so the local `main` ref drifts behind `origin/main` silently. On
# 2026-10-11 it was 75 commits behind, and two agents each spent a full run
# documenting a tree that no longer existed, from worktrees cut off that stale
# tip. A worktree cut from a stale base looks exactly like a clean checkout.
#
# Everything here reads git state and writes none of it: `ls-remote` contacts
# the remote without fetching, and nothing touches FETCH_HEAD. Sourced by
# dev/check.R and by tests/testthat/test-git-base.R.

# Run git and return its stdout, or NULL when it fails or git is missing.
git_lines <- function(args, repo = ".") {
  if (!nzchar(Sys.which("git"))) {
    return(NULL)
  }
  out <- suppressWarnings(tryCatch(
    system2("git", c("-C", shQuote(repo), args), stdout = TRUE, stderr = FALSE),
    error = function(e) NULL
  ))
  if (is.null(out) || !is.null(attr(out, "status"))) {
    return(NULL)
  }
  out
}

# The remote's tip for one branch, without fetching anything.
git_remote_sha <- function(remote = "origin", branch = "main", repo = ".") {
  out <- git_lines(c("ls-remote", remote, paste0("refs/heads/", branch)), repo)
  if (length(out) != 1L) {
    return(NA_character_)
  }
  sha <- sub("[\t ].*$", "", trimws(out))
  if (grepl("^[0-9a-f]{40}$", sha)) sha else NA_character_
}

# The local branch's tip. NA when the branch does not exist here.
git_local_sha <- function(branch = "main", repo = ".") {
  out <- git_lines(
    c("rev-parse", "--verify", "--quiet", paste0("refs/heads/", branch)),
    repo
  )
  if (length(out) != 1L) {
    return(NA_character_)
  }
  sha <- trimws(out)
  if (grepl("^[0-9a-f]{40}$", sha)) sha else NA_character_
}

# How many commits `to` has that `from` does not. NA when either object is
# missing locally, which happens when the remote tip has never been fetched.
git_commits_between <- function(from, to, repo = ".") {
  if (is.na(from) || is.na(to)) {
    return(NA_integer_)
  }
  out <- git_lines(c("rev-list", "--count", paste0(from, "..", to)), repo)
  if (length(out) != 1L) {
    return(NA_integer_)
  }
  n <- suppressWarnings(as.integer(trimws(out)))
  if (is.na(n)) NA_integer_ else n
}

# Pure: turn two shas and two counts into a verdict. Separated from the git
# calls so it can be tested without a repo or a network.
#
# behind: commits on the remote tip that the local branch lacks.
# ahead: commits on the local branch that the remote tip lacks.
# Either may be NA when the remote object is not present locally.
git_base_status <- function(
  local_sha,
  remote_sha,
  behind,
  ahead,
  branch = "main",
  remote = "origin"
) {
  far <- paste0(remote, "/", branch)
  if (is.na(remote_sha)) {
    return(list(
      state = "unknown",
      message = sprintf(
        "could not read %s (no remote, no network, or no git)",
        far
      )
    ))
  }
  if (is.na(local_sha)) {
    return(list(
      state = "unknown",
      message = sprintf("no local %s branch in this repository", branch)
    ))
  }
  if (identical(local_sha, remote_sha)) {
    return(list(
      state = "current",
      message = sprintf(
        "%s matches %s (%s)",
        branch,
        far,
        substr(remote_sha, 1L, 7L)
      )
    ))
  }
  # Both shas are known and they differ, so the base is not current whatever
  # the counts say. A clone that has never fetched cannot count the distance,
  # and that is a reason to fail rather than to shrug: "I cannot tell how far
  # behind I am" is not "I am up to date".
  if (is.na(behind) || is.na(ahead)) {
    return(list(
      state = "differs",
      message = sprintf(
        "%s is %s and %s is %s; the remote commit is not in this clone, so the distance is unknown: run dev/sync-main.sh",
        branch,
        substr(local_sha, 1L, 7L),
        far,
        substr(remote_sha, 1L, 7L)
      )
    ))
  }
  if (behind > 0L && ahead == 0L) {
    return(list(
      state = "behind",
      message = sprintf(
        "%s is %d commit%s behind %s (%s vs %s): run dev/sync-main.sh",
        branch,
        behind,
        if (behind == 1L) "" else "s",
        far,
        substr(local_sha, 1L, 7L),
        substr(remote_sha, 1L, 7L)
      )
    ))
  }
  if (behind > 0L && ahead > 0L) {
    return(list(
      state = "diverged",
      message = sprintf(
        "%s has diverged from %s: %d behind, %d ahead. Amelia decides how to reconcile",
        branch,
        far,
        behind,
        ahead
      )
    ))
  }
  list(
    state = "ahead",
    message = sprintf(
      "%s is %d commit%s ahead of %s and nothing has been pushed",
      branch,
      ahead,
      if (ahead == 1L) "" else "s",
      far
    )
  )
}

# The whole check: read the state, then judge it.
git_base_check <- function(branch = "main", remote = "origin", repo = ".") {
  local_sha <- git_local_sha(branch, repo)
  remote_sha <- git_remote_sha(remote, branch, repo)
  behind <- git_commits_between(local_sha, remote_sha, repo)
  ahead <- git_commits_between(remote_sha, local_sha, repo)
  git_base_status(local_sha, remote_sha, behind, ahead, branch, remote)
}
