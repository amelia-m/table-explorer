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

Current baseline, from a run on 2026-10-11:

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

**The script reports; the callers assert.** Run on its own,
`score_detection.R` prints the counts and exits 0 whatever they are, so its
own exit status is not a check: read the numbers, and the lists it prints
under `missed:` and `most common false links:`. What guards detection is the
two callers that parse the `medium+:` line and fail on it, both requiring
`real >= want` and `false == 0`: `dev/check.R` (check 4) and the "Score
detection against the fixture" step in `.github/workflows/r-ci.yml`. So a
scoring change that loses a link or invents one fails CI, but only if it goes
through one of those two. Do not add an exit code to this script without
looking at both.

To look at the schema in the app, source the file and pass
`access52_fixture()$tables` to the app the way
`dev/browser-checks/sample_app.R` passes the sample data.

## Real Access files

`access/` builds `access_fixture.mdb` and the `trap_*` files in `tests/testthat/fixtures/`, for testing the Access readers on real files. Rebuilding needs Windows, the Access Database Engine and the 32-bit DAO 3.6 that Windows ships, for Jet 3. The check needs rJava and the jars the app downloads on first use. Only some of what it builds is committed: `tests/testthat/fixtures/README.md` lists those files. `access/TRAPS.md` lists each trap, where it sits and what each reader did.

```sh
pwsh -NoProfile -File dev/fixtures/access/build_all.ps1 -OutDir <empty folder>
Rscript --vanilla dev/fixtures/access/check_answer_key.R <folder>/access_fixture.mdb
```

`check_answer_key.R` reads the built file with Jackcess, not through the app, and exits non-zero naming each entry that disagrees with `access_fixture_key.csv`. Edit the lists in `make_answer_key.R`, not the CSV, and run it from `dev/fixtures/access/`. Bytes differ between builds, because Jet stamps dates and GUIDs into its system tables.
