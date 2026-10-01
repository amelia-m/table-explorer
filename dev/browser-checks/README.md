# Browser checks

End-to-end checks of the Data Dictionary privacy review and the data-dict
YAML round trip, driven in headless Chromium with Playwright. They complement
`tests/testthat` (which covers the logic) by exercising the real UI: DT
tables, the review dialog, downloads and Import Schema.

Needs: R with the app's dependencies, Node, and Playwright
(`npm install playwright`, or point `PLAYWRIGHT_MODULE` at an existing
install and `CHROMIUM` at a browser executable).

Run from the repository root:

```sh
Rscript dev/browser-checks/sample_app.R &   # sample_data/ preloaded, port 8771
Rscript dev/browser-checks/plain_app.R &    # empty app, port 8772
node dev/browser-checks/privacy_check.js    # writes ui_data_dict.yaml to OUT
node dev/browser-checks/import_check.js     # imports it, re-exports ui_data_dict_2.yaml
diff "$TMPDIR/te-browser-checks/ui_data_dict.yaml" "$TMPDIR/te-browser-checks/ui_data_dict_2.yaml"
```

`OUT` defaults to `te-browser-checks` in the system temp directory; set it to
keep the downloads and screenshots elsewhere.

## Expected output (sample data)

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
  links, which go under `todo`).
- 10: a restored session keeps the banner count and the pattern.

`import_check.js`: "Schema imported: 7 table(s)", 32 rows, restricted
columns shown as "private (from imported file)", then "re-exported".

The YAML diff should differ only in examples (none after import) and in
`number(id)` becoming `number` on foreign keys whose links were unconfirmed;
primary keys and relationships match.
