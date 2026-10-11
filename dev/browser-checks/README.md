# Browser checks

End-to-end checks of the Data Dictionary privacy review and the data-dict
YAML round trip, driven in headless Chromium with Playwright. They complement
`tests/testthat` (which covers the logic) by exercising the real UI: DT
tables, the review dialog, downloads and Import Schema.

Nothing runs them for you. `dev/check.R` and `.github/workflows/r-ci.yml`
run the test suite and the detection scorer, neither of which starts a
browser, and CI installs no Node or Playwright. These are a by-hand check to
run when the Data Dictionary tab, the privacy review or the data-dict
mapping changes.

Needs: R with the app's dependencies, Node, and Playwright
(`npm install playwright`, or point `PLAYWRIGHT_MODULE` at an existing
install and `CHROMIUM` at a browser executable).

Run from the repository root:

```sh
export OUT=_scratch/browser-checks           # so the diff below has a known path
Rscript dev/browser-checks/sample_app.R &    # sample_data/ preloaded, port 8771
Rscript dev/browser-checks/plain_app.R &     # empty app, port 8772
node dev/browser-checks/privacy_check.js     # writes ui_data_dict.yaml to OUT
node dev/browser-checks/import_check.js      # imports it, re-exports ui_data_dict_2.yaml
diff "$OUT/ui_data_dict.yaml" "$OUT/ui_data_dict_2.yaml"
```

`OUT` holds the downloads and screenshots. Both scripts default it to
`te-browser-checks` in the system temp directory, which is why the example
sets it: the temp path differs by platform.

Environment variables, all optional:

| Variable | Read by | Default |
|---|---|---|
| `REPO` | both R scripts | `.`; they `setwd()` to it and source `R/` directly |
| `PORT` | each R script and its checker | 8771 for the sample app, 8772 for the empty one |
| `MINCONF` | `sample_app.R` | `medium`, the minimum confidence the stubbed detection runs at |
| `OUT` | both checkers | `te-browser-checks` in the system temp directory |
| `PLAYWRIGHT_MODULE` | both checkers | `playwright` on `NODE_PATH` |
| `CHROMIUM` | both checkers | Playwright's own browser |

`sample_app.R` is not the app as a user meets it: it replaces the upload,
database and detection modules with stubs, so `sample_data/` is loaded at
start and one full scan runs immediately, with the null-pattern signal off.
That is what keeps the numbers below stable. `plain_app.R` is the real app
with nothing loaded.

## Expected output (sample data)

These values have not been re-run since the privacy review changed: the
flag notification now stays until dismissed instead of clearing after 8
seconds, and the review queue hides flagged columns that hold no values,
behind a "Hide N flagged columns with no values" box that appears only when
there is such a column. No column in `sample_data/` is empty (checked by
reading all seven files), so the counts below should be unaffected, but
that is reasoning, not a run. Re-run the block above and correct anything
that has moved.

`privacy_check.js`:

- 0: one notification, "6 columns were flagged as possibly personal".
- 1: 17 columns, ending Label, Description, Units, Allowed values, Details.
- 2: `customers.email` is "email address", private (auto, to review),
  examples "(private)"; `orders.amount` shows its range and examples.
- 3: the review queue lists street, the two `name` columns, email,
  `products.name` and `contact_email`; "modal leaks values: false".
- 4: after "Not personal" on `products.name` and "Private" on
  `customers.email`, the banner says 4 columns are left.
- 5–8: Private on selected rows hides the range; the `country` name pattern
  applies; the review filter shows 4 rows; a Label edit saves.
- 9: the YAML has `$version: 0.1.0`, the label, `display: restricted` and
  `units: USD` (`relationships:` is false: the sample has only detected
  links, which go under `todo`). The same step downloads the CSV and the
  Markdown: it prints the CSV header row, and for the Markdown that the
  private note reads `private (confirmed)` and that no real email address
  survived into it.
- 10: a restored session keeps the banner count and the pattern.

`import_check.js`: "Schema imported: 7 table(s)", 32 rows, restricted
columns shown as "private (from imported file)", then "re-exported".

The YAML diff should differ only in examples (none after import) and in
`number(id)` becoming `number` on foreign keys whose links were unconfirmed;
primary keys and relationships match.
