# Detection presets: named bundles of detect_fks() settings.
#
# TENTATIVE (Amelia, 2026-10-14): "tentatively set the best-performing
# options as presets. they'll be finalized after we run some comparisons on
# some of my data and some more public data". These are chosen from the
# measured sweep, dev/fixtures/public/sweep-2026-10-13.csv, over three public
# schemas only: Chinook, Lahman and FAERS. None has been run against a real
# extract, and the three rules the sweep found inert on public data (the
# chance-overlap discount, the cardinality floor and the possible-key-name
# tier) were written for cases that live in Amelia's own data. Do not read a
# preset here as settled.
#
# A preset only sets parameters detect_fks() already takes, so any preset is
# reproducible by passing the same arguments by hand. detect_fks()'s own
# defaults are deliberately unchanged: a caller that names no preset gets
# today's behaviour, and the choice of which preset a user starts on belongs
# to the preset UI, which is not built.
#
# The measured figures behind each preset are not repeated here. Numbers
# typed into code drift from the measurement they came from, so the source is
# the sweep file, and each preset names the rows it rests on.

detection_presets <- list(
  recommended = list(
    label = "Recommended",
    description = paste(
      "Best or tied-best on every public schema measured. The shipped",
      "settings, except that a column that reads as prose (an address, a",
      "name) is never offered as a parent: such a column is unique by",
      "accident, not by design."
    ),
    tentative = TRUE,
    # Sweep rows: prose_parent_guard = refuse_target with every other switch
    # at its default, on chinook, lahman and faers. Chinook precision at high
    # confidence 90.0 -> 100.0 at unchanged recall; lahman and faers
    # identical to the defaults, because neither has a prose parent.
    measured_on = c("chinook", "lahman", "faers"),
    settings = list(
      prose_parent_guard = "refuse_target"
    )
  ),
  fewer_candidates = list(
    label = "Fewer candidates",
    description = paste(
      "Recommended, without the containment signal. Roughly halves the",
      "list to review on a conventionally named schema, at the cost of",
      "links whose only evidence is that their values sit inside a key.",
      "High-confidence links are unchanged."
    ),
    tentative = TRUE,
    # Sweep rows: prose_parent_guard = refuse_target with containment off.
    # Chinook found 58 -> 28, overall recall 90.9 -> 81.8, high confidence
    # unchanged; lahman identical. NOT measured on faers: the run budget did
    # not reach this combination there.
    measured_on = c("chinook", "lahman"),
    settings = list(
      prose_parent_guard = "refuse_target",
      # Containment is switched off by asking for more distinct values than
      # any column has. The same value the sweep used, so the preset and the
      # rows it rests on are the same setting.
      containment_min_distinct = 10000000L
    )
  ),
  find_more = list(
    label = "Find more",
    description = paste(
      "For an extract with no declared keys and unconventional names, where",
      "missing a link costs more than reviewing a false one. Also accepts a",
      "parent that is one column of a two-column key. Finds links nothing",
      "else does, and reports far more that are wrong."
    ),
    tentative = TRUE,
    # Sweep rows: parent_key_requirement = composite. The only setting that
    # reaches FAERS' two drug_seq links (overall recall 75.0 -> 100.0), but
    # they arrive at low confidence and three high links are demoted, and
    # Lahman precision at high falls 100.0 -> 16.4. Measured with
    # refuse_target on chinook only; the faers and lahman rows are with the
    # prose guard at its default.
    measured_on = c("chinook"),
    settings = list(
      prose_parent_guard = "refuse_target",
      parent_key_requirement = "composite"
    )
  )
)

# The detect_fks() arguments a preset sets, for passing with do.call().
detection_preset_settings <- function(name) {
  if (!is.character(name) || length(name) != 1L || is.na(name)) {
    stop("A preset is named by a single string.", call. = FALSE)
  }
  preset <- detection_presets[[name]]
  if (is.null(preset)) {
    stop(
      sprintf(
        "No detection preset called '%s'. Known presets: %s.",
        name,
        paste(names(detection_presets), collapse = ", ")
      ),
      call. = FALSE
    )
  }
  preset$settings
}

# detect_fks() with a preset's settings applied. Arguments in ... are passed
# through and override the preset, so a caller can start from a preset and
# change one setting, which is what "Custom" will mean in the UI.
detect_fks_preset <- function(tables, preset, ...) {
  args <- utils::modifyList(detection_preset_settings(preset), list(...))
  do.call(detect_fks, c(list(tables), args))
}
