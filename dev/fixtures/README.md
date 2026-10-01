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

Current baseline: 157 of 157 real links found at medium+, 0 false (plus
about 590 low-confidence candidates, which the app hides by default). Run it
before and after any change to `R/utils_inference.R` and compare.

To look at the schema in the app, source the file and pass
`access52_fixture()$tables` to the app the way
`dev/browser-checks/sample_app.R` passes the sample data.
