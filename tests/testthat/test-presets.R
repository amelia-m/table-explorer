# Detection presets are tentative bundles of detect_fks() settings, chosen
# from the public-dataset sweep. These tests pin behaviour, not the choice of
# settings: which settings a preset holds is a decision, recorded in
# R/utils_presets.R with the sweep rows behind it.

pair_keys <- function(rels) {
  vapply(
    rels,
    function(r) {
      sprintf(
        "%s.%s -> %s.%s",
        r$from_table, r$from_col, r$to_table, r$to_col %||% ""
      )
    },
    ""
  )
}

# Two small tables in the Chinook shape that every preset can scan.
preset_tables <- function() {
  list(
    staff = data.frame(employeeid = 1:8, surname = paste0("s", 1:8)),
    customers = data.frame(
      custid = 1:59,
      supportrepid = rep(c(3, 4, 5), length.out = 59)
    )
  )
}

test_that("every preset runs through detect_fks without error", {
  # A preset naming an argument detect_fks() does not take, or giving one a
  # value it refuses, fails here rather than in front of a user.
  for (nm in names(detection_presets)) {
    expect_no_error(
      detect_fks_preset(preset_tables(), nm, min_confidence = "low")
    )
  }
})

test_that("every preset is marked tentative until it is finalised", {
  # Amelia, 2026-10-14: finalised only after comparisons on her own data and
  # more public data. A preset that loses the flag without that has been
  # promoted by accident.
  for (nm in names(detection_presets)) {
    expect_true(isTRUE(detection_presets[[nm]]$tentative), info = nm)
  }
})

test_that("the recommended preset refuses a prose parent the defaults accept", {
  addresses <- paste(1:40, c("Oak Lane", "Elm Street", "High Road", "Mill Way"))
  tabs <- list(
    customer = data.frame(
      customer_id = 1:40,
      address = addresses,
      stringsAsFactors = FALSE
    ),
    invoice = data.frame(
      invoice_id = 1:120,
      billing_address = rep(addresses, 3L),
      stringsAsFactors = FALSE
    )
  )
  pair <- "invoice.billing_address -> customer.address"
  expect_true(pair %in% pair_keys(detect_fks(tabs, min_confidence = "low")))
  expect_false(
    pair %in% pair_keys(detect_fks_preset(tabs, "recommended", min_confidence = "low"))
  )
})

test_that("the fewer-candidates preset drops a link only containment found", {
  # customers.supportrepid has three values inside staff's eight ids and
  # nothing but containment connects them. Measured: high at 0.952 with
  # containment, low at 0.400 on a shared integer format alone without it.
  # So the link leaves the list a reviewer sees at the default minimum
  # confidence, which is what "fewer candidates" promises; it is still there
  # at "low", carried by the format signal.
  pair <- "customers.supportrepid -> staff.employeeid"
  expect_true(
    pair %in% pair_keys(detect_fks_preset(preset_tables(), "recommended"))
  )
  expect_false(
    pair %in% pair_keys(detect_fks_preset(preset_tables(), "fewer_candidates"))
  )
})

test_that("an argument passed alongside a preset overrides it", {
  # This is what Custom will mean in the UI: start from a preset, change one
  # setting. Here the containment floor is put back to its default.
  pair <- "customers.supportrepid -> staff.employeeid"
  rels <- detect_fks_preset(
    preset_tables(),
    "fewer_candidates",
    containment_min_distinct = containment_min_distinct_default
  )
  expect_true(pair %in% pair_keys(rels))
})

test_that("an unknown preset is refused and the known ones are named", {
  expect_error(detection_preset_settings("strict"), "Known presets: recommended")
  expect_error(detection_preset_settings(c("a", "b")), "single string")
})
