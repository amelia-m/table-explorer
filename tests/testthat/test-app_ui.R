# Tests for app_ui.R - page shell

test_that("app_ui renders both sidebar collapse controls", {
  html <- as.character(app_ui(NULL))

  # The rail is the only way back once the sidebar is hidden
  expect_match(html, 'id="sidebar-rail"', fixed = TRUE)
  expect_match(html, 'id="sidebar-collapse"', fixed = TRUE)
  # Both drive the same region, for screen readers
  expect_equal(
    length(gregexpr('aria-controls="sidebar-col"', html, fixed = TRUE)[[1]]),
    2
  )
  expect_match(html, 'id="sidebar-col"', fixed = TRUE)
  expect_match(html, 'id="app-body"', fixed = TRUE)
})

test_that("app_build_stamp names the version, and the build when it can", {
  stamp <- app_build_stamp()
  expect_type(stamp, "character")
  expect_length(stamp, 1)
  expect_match(stamp, "^tableexplorer [0-9]")
  # In a git checkout it also carries a short sha and a date
  if (nzchar(Sys.which("git")) && dir.exists(".git")) {
    expect_match(stamp, "[0-9a-f]{7}")
    expect_match(stamp, "[0-9]{4}-[0-9]{2}-[0-9]{2}")
  }
})

test_that("app_ui renders the build stamp in the footer", {
  html <- as.character(app_ui(NULL))
  expect_match(html, 'class="app-footer"', fixed = TRUE)
  expect_match(html, "tableexplorer ", fixed = TRUE)
})
