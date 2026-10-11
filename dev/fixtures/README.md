# Detection fixtures

`access52.R` builds a synthetic 52-table Access-style schema whose real
links are known, and `score_detection.R` scores FK detection against it.

The schema is the case that used to swamp detection with false links: eight
lookup tables that all use ids 1..8, so values alone can't tell which lookup
a column points at. Names have to decide, which is what PR #19's
names-first parent resolution does.

```sh
Rscript dev/fixtures/score_detection.R          # medium confidence and up
Rscript dev/fixtures/score_detection.R high
```

Current baseline, from a run on 2026-10-10:

```
reported: 749 (high 157, low 592)
medium+: 157   real: 157 of 157   false: 0
```

157 of 157 real links found at medium+, 0 false, plus 592 low-confidence
candidates, which the app hides by default (`min_confidence` starts at
"medium", `R/mod_detection.R:26`). Run it before and after any change to
`R/utils_inference.R` and compare.

The fixture is deterministic (`set.seed(7)` in `access52.R`), so those
numbers are exact rather than approximate: any difference is a real change
in detection, not sampling noise.

**It reports, it does not fail.** The script prints the counts and exits 0
whatever they are, so its exit status is not a check. Read the numbers, or
compare them against the block above. The same goes for the lists it prints
under `missed:` and `most common false links:` when there are any.

To look at the schema in the app, source the file and pass
`access52_fixture()$tables` to the app the way
`dev/browser-checks/sample_app.R` passes the sample data.
