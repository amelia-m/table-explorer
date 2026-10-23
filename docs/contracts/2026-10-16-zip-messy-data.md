# Task contract: ZIP detection on messier public data

Date: 2026-10-16  Dispatch: one agent, read-only apart from new files in `_scratch/`
Request as given: "see if we can find any public data that is messier. there is a lot of data
bundled into R packages"

## Intent and scope

The ZIP+4 threshold (0.90 of 9-digit values with a first five digits in the USPS list) and the
"mixed forms" second signal were measured only on federal files (IRS, FEC, CMS, DOL), which are
probably cleaner than a research extract: the worst real column still reached 99.55%. Find
public ZIP columns typed by people, merged from sources, or otherwise untidy, and measure the
same things on them, so the threshold is tested where it is most likely to fail.

## Non-goals

- No changes to tracked files. No branches, commits, pushes, issues or comments.
- **Install nothing.** Where a dataset lives in an R package, reach it without installing the
  package: Rdatasets (https://vincentarelbundock.github.io/Rdatasets/) serves CSVs of datasets from
  many CRAN packages, and many packages keep their raw data on GitHub. A dataset that can only be
  had by installing a package is listed, with the package name and why it looks useful, for
  Amelia to approve, and is not measured.
- No API keys, accounts, click-through terms or cookie banners. No file over about 250 MB.
- **Never print, save or report a row.** Read only the ZIP, state and identifier columns, and
  report counts and rates. City open data carries business names and addresses; pet and permit
  data can carry owners' ZIPs. None of it goes into the repository.

## Context

- Where messy ZIPs are likely, unverified and to be confirmed: city open data portals with
  anonymous CSV export (Chicago, New York, Seattle, San Francisco, Los Angeles: food inspections,
  311 requests, business licences, pet licences, building permits); the TidyTuesday repository on
  GitHub (rfordatascience/tidytuesday), whose weekly datasets include several with ZIP or address
  columns; Rdatasets and R package data with a ZIP, `zip`, `zipcode` or postal column; state open
  data portals. Prefer columns where values were typed by people or merged from several systems.
- What counts as messy, and is worth reporting per column: leading zeros lost (four-digit values,
  ZIPs stored as numbers), ZIP+4 with and without separators in one column, placeholders (`00000`,
  `99999`, `0`, `N/A`, `UNKNOWN`), foreign postal codes, typos, ZIPs from the wrong state, and
  trailing `.0` from a spreadsheet round trip.
- Measures, the same as `_scratch/research/zip4-threshold-measurement.md` (script
  `_scratch/research/zip4_threshold_measure.R`, function `normalise()`): share that normalise;
  5-digit vs 9-digit shares; share in 00501 to 99950; share found in the USPS list; the 9-digit
  values' share found; `+4 = 0000` share; padded count; placeholder counts. Plus, where the file
  has a state column, **state agreement**, as computed in `_scratch/research/state_agreement.R`
  (function `measure()`): the share of values whose first five digits are a USPS ZIP and whose
  USPS state matches the row's state, overall and for 9-digit values.
- Reference list: `docs/ref/usps-zip-locale.csv` (on branch `ci/usps-zip-locale-check`, #66; read here from its worktree under `_scratch/wt-usps/`)
  (columns `zip, class, locale_name, state, sheet`; read as character).
- R is at "C:\Program Files\R\R-4.6.1\bin\Rscript.exe"; set RENV_CONFIG_AUTOLOADER_ENABLED=FALSE;
  never run `Rscript -e` with inline code on this machine. `data.table` is installed. Download with
  R or PowerShell; DNS on this machine fails intermittently, so retry before giving up.

## Constraints

- Each dataset reported with its URL, publisher, date or edition, size, the columns used, the
  number of non-missing values, and its terms as the publisher states them.
- Every claim marked verified (measured, or a primary source read), corroborated, or unverified.
- Downloads only to `_scratch/research/data/public/messy/`;
  scripts to `_scratch/research/`.
- No em dash (U+2014) anywhere.
- Stop and report rather than deciding alone when a dataset turns out not to be public, or a
  download needs more than an anonymous GET.

## Edge cases

- **A column that is mostly blank**: report it with its non-missing count; do not drop it.
- **Mixed text and numbers in one column** (a spreadsheet export): report how many values were
  numeric, and how many carried a trailing `.0`.
- **A ZIP column with no 9-digit values at all**: still measure it; it tests the 5-digit tiers
  (invalid, not found, may be a placeholder).
- **A column whose state disagrees often**: report the disagreement rate; say whether it looks like
  data quality (wrong ZIPs) or a mismatched state column (business address against mailing
  state), from the column names, labelled as an inference.

## Output requirements

- `_scratch/research/zip-messy-data.md`: a table, one row
  per column, with the measures above; then, in words, the lowest 9-digit hit rate on a real
  messy column, whether any real column with bare 9-digit values lacked 5-digit values (the
  "mixed forms" signal), how state agreement behaved, and what the messy data changes about the
  0.90 threshold and the proposed tiers.
- The script that produced every number.
- A separate list of R-package datasets that would need installing, for Amelia to approve.

## Acceptance and evidence

1. At least three messy real ZIP columns from at least two publishers, at least one of them
   holding 9-digit values.
2. Every number comes from the script, rerunnable.
3. No row of any dataset appears in the output or the report.
- The agent shows: the output path, the script path, the URLs used, and the table.
- The agent lists, in full wording, every dataset it skipped and why, every claim it could not
  verify, and anything it assumed.

## Settled (Amelia, 2026-10-16)

- Test the threshold on messier public data, R packages included.
