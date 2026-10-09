# run_app(): the launcher, now without golem

test_that("run_app applies the upload size limit when the app starts (backlog C3: limit was never applied)", {
  withr::local_options(shiny.maxRequestSize = NULL)
  app <- run_app()
  expect_s3_class(app, "shiny.appobj")
  app$onStart()
  expect_equal(getOption("shiny.maxRequestSize"), 100 * 1024^2)
})

test_that("run_app's upload limit can be changed by the caller", {
  withr::local_options(shiny.maxRequestSize = NULL)
  app <- run_app(max_request_size = 5 * 1024^2)
  app$onStart()
  expect_equal(getOption("shiny.maxRequestSize"), 5 * 1024^2)
})

test_that("run_app passes shinyApp arguments through (backlog M10: it took only ...)", {
  ran <- FALSE
  app <- run_app(onStart = function() ran <<- TRUE, options = list(port = 4321))
  expect_equal(app$options$port, 4321)
  withr::local_options(shiny.maxRequestSize = NULL)
  app$onStart()
  expect_true(ran)
})
