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
