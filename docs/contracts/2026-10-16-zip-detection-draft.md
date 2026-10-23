# Task contract: ZIP and ZIP+4 detection, validation and documentation

Date: 2026-10-16  Dispatch: one agent
Request, paraphrased: flag invalid ZIPs such as `00000`, recognise and auto-flag ZIP+4 and note it in the documentation, and handle ZIPs stored as integer, double or text, with or without a hyphen or plus.

## Intent and scope

Today a column is "US ZIP code" when 80% of a 200-value sample matches `^\d{5}(-\d{4})?$` (`R/utils_inference.R:68`, `format_fingerprint()`). That pattern accepts `00000`, rejects a 9-digit ZIP+4 with no hyphen or with a plus sign, and never sees a ZIP stored as a number, because numeric columns are labelled before the patterns run (`dict_format()`, `R/utils_export.R`). ZIP+4 may arrive as text or as integers, with or without a separator.

In scope:

1. **Recognise every storage form** of a ZIP and a ZIP+4: integer, double, and text with a
   hyphen, a plus sign, a space, or no separator, including values that lost leading zeros.
2. **Validate** each value: hard-invalid, or valid shape but not found in a reference list, or
   found.
3. **Report** it in the Data Dictionary: the format names ZIP or ZIP+4 and says how it was
   stored, and the column carries counts of invalid and not-found values.
4. **Document** what is and is not checked, in the README and in `docs/internals.md`.

The audience is a reviewer documenting an extract that ships no schema.

## Non-goals

- **No online checks of any kind.** Nothing in the app sends a value off the machine. ZIP+4 is
  checked for shape and for its 5-digit part only, never against USPS.
- **No USPS data in the package.** Every USPS list found is paid and not redistributable, and the
  free PostalPro files carry terms forbidding reproduction (research,
  `_scratch/research/zip-validation-sources.md`).
- **Never rewrite the data.** Normalisation is for checking and labelling only; the loaded table is
  untouched.
- **Never weaken a privacy flag.** Labelling a column as ZIP or ZIP+4 must not clear, suppress or
  outrank a possible-SSN or any other privacy flag. ZIP columns are themselves flagged by name.
- No change to foreign key scoring beyond what follows from the format label already feeding
  `format_match`. No change to `weight_map`.
- No reformatting of untouched code. Do not merge.

## Context

- Research on file, both finished 2026-10-16 and both partly verified by me against the public
  USPS ZIP Locale Detail file (41,486 distinct ZIPs, lowest 00501, highest 99950):
  `_scratch/research/zip-repdigits.md` and `_scratch/research/zip-validation-sources.md`.
- Verified facts to rely on: assigned ZIPs run from 00501 to 99950; of the repeating-digit
  values only 44444 is assigned; 00000 appears in no list. ZCTAs are not ZIPs and omit PO-box-only
  and unique ZIPs. No R package validates against USPS. `zipcodeR` ships 41,877 ZIPs frozen at
  2021-06-08, PO-box and unique included, GPL-3. Census ZCTA files are public domain
  (17 U.S.C. 105) and may be bundled.
- The privacy detector already flags SSN-shaped values (`R/utils_privacy.R`). A bare 9-digit
  number is both SSN-shaped and ZIP+4-shaped.
- R is at "C:\Program Files\R\R-4.6.1\bin\Rscript.exe". Never run `Rscript -e` with inline code:
  spaced paths segfault. Put code in a file.
- Verification: `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" dev/check.R`
- `R/utils_export.R`, `R/utils_privacy.R` and `R/mod_dictionary.R` are Air-formatted on `main`;
  `R/utils_inference.R` is not, and must not be reformatted (open branches edit it).

## Constraints

- **Normalisation rules**, applied to a copy:
  - Text: trim; strip one separator between digit 5 and digit 6 (`-`, `+`, space); keep only
    values that are then all digits.
  - Integer and double: only whole, non-negative values. Convert with a function that never
    produces scientific notation (`as.character(100000)` is `"1e+05"` in R); test that case.
  - Length decides the form after leading zeros are restored: 1 to 5 digits is a ZIP, padded to 5;
    6 to 9 digits is a ZIP+4, padded to 9. Anything longer, or shorter than 3 digits for a stored
    number, is not a ZIP.
- **Recognising the column.** Once at least 80% of sampled non-missing values normalise, as now:
  - forms that cannot be an SSN (5 digits, or 9 digits with a separator) are ZIP / ZIP+4 by shape;
  - a bare 9-digit form, text or number, is ZIP+4 **only once its values are confirmed valid**
    (Amelia, 2026-10-16: "not without confirming that they are valid zip+4"): at least
    `zip4_valid_min_frac` (propose 0.90) of values must pass every offline check, meaning a
    valid shape, a first five digits inside 00501 to 99950 and found in the reference list.
    The column name is not enough on its own. An SSN column passes the reference check by
    chance at about 40 percent. Otherwise the column keeps no ZIP label.
  - **What "valid ZIP+4" can mean offline, stated wherever it is shown**: the shape and the
    5-digit ZIP are confirmed; the +4 itself is not, because no free or bundleable source lists
    assigned +4 codes. The dictionary says "ZIP valid, +4 not verified", never just "valid".
- **Validation tiers**, per value:
  - **invalid**: not normalisable; `00000`; first five digits below 00501 or above 99950; a +4 of
    `0000` is **not** invalid: the IRS writes `0000` as the +4 on 2.5% to 23.9% of its values
    (measured, 2026-10-16), so treating it as invalid would flag a large share of real data.
  - **may be a placeholder**: a repeating-digit ZIP inside the range and absent from the
    reference list (11111, 33333, 66666, 77777, 88888 today; 44444 is assigned and is found).
    Absent from USPS 2026, zipcodeR 2021, Census ZCTAs and GeoNames, but no USPS source says
    they are unassigned. Worded "not in the USPS list; may be a placeholder" (Amelia,
    2026-10-16: "may be" rather than "looks like"). Computed from the list, not a fixed set.
  - **possibly retired**: valid shape, first five digits absent from the reference list but in
    the retirement hint set. Worded as "not in the current USPS list; listed in 2021 data,
    possibly retired".
  - **not found**: valid shape, first five digits absent from the reference list. Worded as
    "not in the reference list", never "invalid", because the lists are known to be incomplete.
  - **found**: present in the reference list.
- **Reference list**: `docs/ref/usps-zip-locale.csv`, the derived USPS ZIP Locale Detail list
  tracked on branch `ci/usps-zip-locale-check` (PR #66, not yet merged; Amelia, 2026-10-16). 41,486 distinct ZIPs, 00501 to 99950,
  with USPS class codes (blank standard, P PO-box-only, U unique, M military). Read once per
  session; its edition comes from `docs/ref/zip-locale-source.yml` (`file_updated`). About 68
  assigned ZIPs are missing against USPS's own count of 41,554 and nothing names them, which is
  one reason "not found" is a soft tier. Census ZCTAs are no longer needed and are not used.
- **Retirement hint, not a validator** (Amelia, 2026-10-16): `zipcodeR`'s June 2021 list holds
  1,031 ZIPs absent from the USPS file (536 unique, 285 PO box, 210 standard), most probably
  retired since 2021, among them 22222 and 55555. A ZIP in that set is reported as "not in the
  current USPS list; listed in 2021 data, possibly retired", which tells a reviewer something
  different from a value that never existed. It never makes a value valid. Source of the set:
  either read from `zipcodeR` at run time when installed (Suggests only; the package pulls in
  `sf`, `terra`, `raster` and `tidycensus`), or a small tracked snapshot of just those 1,031 ZIPs
  with its source and date. Proposed: the snapshot, if zipcodeR's data licence allows it (the
  zipcodeR review in `_scratch/research/zipcoder-contribution.md` should say); otherwise the
  run-time read.
- The dictionary names the reference edition behind every result, so a "not found" can be read
  against the list that produced it.
- Every threshold is a named constant with its justification in a comment.
- Tests exercise behaviour, one per behaviour, each able to fail. Every rule that admits needs a
  test that keeps junk out (an SSN-shaped column not named ZIP stays unlabelled and stays
  flagged), and every rule that excludes needs a survival test (a real ZIP+4 integer column with
  lost leading zeros is recognised).
- Test data is invented, never copied from a real extract. Use made-up but valid-shaped ZIPs
  from the reference list and made-up SSN-shaped strings that are not real SSNs (900-xx-xxxx).
- No literal non-ASCII characters in R source: use `\u` escapes.
- No em dash anywhere.
- Stop and report rather than deciding alone when: a privacy flag would change on any existing
  test fixture, the detection scorer moves off `157 of 157` / `0 false`, or the reference list
  cannot be fetched or its licence is not the public-domain statement.

## Edge cases

- **Mixed column, mostly ZIP and some ZIP+4**: one label, "US ZIP or ZIP+4",
  with counts of each form.
- **A ZIP stored as an integer with its leading zero lost** (`2134`): recognised, padded, and the
  dictionary notes "stored as a number, leading zeros lost" so the reviewer knows the data needs
  care on export.
- **A double with a fractional part** (`68101.5`): not a ZIP value; counts against the 80%.
- **Placeholder values** (`00000`, `99999`, `0`): counted as invalid, named in the reason.
- **An empty or all-missing column**: no label, as now.
- **A US-style ZIP column with some foreign postal codes**: those values fail normalisation and
  count against the 80%; if the column still passes, they are reported as invalid with that
  reason, not silently dropped.
- **The `dict_placeholder_examples()` stand-in for a withheld ZIP is `00000`**, which this work
  defines as invalid. Change the stand-in to a value that is a valid shape and obviously not real,
  and say which in the commit.

## Output requirements

- Code in `R/`; data in `R/sysdata.rda` or `inst/extdata/`, with the build script under `dev/`.
- The Data Dictionary shows the format and a short validity note per ZIP column; the CSV,
  Markdown and data-dict exports carry the same counts.
- README feature table and `docs/internals.md` say exactly what is checked and what is not,
  including that ZIP+4 is checked for shape and its 5-digit part only.
- Logical commits; push the branch; open a pull request; do not merge.

## Acceptance and evidence

1. `dev/check.R` ALL CHECKS PASSED, scorer `157 of 157`, `0 false`.
2. A test per storage form recognising the same ZIP+4: `"68101-1234"`, `"68101+1234"`,
   `"681011234"`, integer `681011234`, double `681011234`, and a leading-zero case stored as
   integer `21345678` read as `02134-5678`.
3. A test that a numeric value R would print in scientific notation (a double such as
   `681000000`, and `100000`, which `as.character()` gives as `"1e+05"`) normalises to its plain
   digits, so no value is ever compared or shown in scientific notation.
4. A test that an SSN-shaped column of invented `900-xx-xxxx`-style values, not named ZIP, gets no
   ZIP label **and** keeps its privacy flag.
5. A test that a bare 9-digit column whose values are 90% confirmed is labelled ZIP+4 whatever
   it is named, and that one named `zip` but only 50% confirmed is **not** labelled.
6. A test that `00000`, `00499` and `99951` are invalid with their reasons, and a valid-shape ZIP
   absent from the reference list is "not in the reference list", not invalid.
7. The reference-list build script runs, and the committed data's header names its source URL,
   date and row count.
- The agent shows: `dev/check.R` output verbatim; the test name behind each line above; the
  files changed; a screenshot or description of the dictionary row for a ZIP+4 column, made from
  invented data.
- The agent lists, in full wording, everything it deferred, every threshold it chose and why, and
  every claim it did not verify directly, each with the check that would settle it.

## Open assumptions (each needs Amelia's yes or a change)

- The confirmation threshold for bare 9-digit values is **90%** of values passing every offline
  check, counted against the USPS list alone. Settled that confirmation is required (Amelia,
  2026-10-16). **Measured** (`_scratch/research/zip4-threshold-measurement.md`, 2026-10-16): real
  ZIP+4 columns from IRS, FEC, CMS and DOL hit 99.55% to 99.99% on their 9-digit values; real EIN
  columns 29.1% to 74.96%; random 9-digit numbers and SSA-rule SSNs about 41.6%. 0.90 leaves 9.6
  points below the lowest real column and 15.0 above the highest identifier. Counting zipcodeR's
  2021 list as a hit raises identifier rates more than real ones, so it is not counted.
  **What 0.90 cannot stop**: an identifier column concentrated in one prefix. An SSN column
  drawn from a single SSA area reaches 99% in some areas (eight areas are at or above 90%), and
  EINs from one 2-digit prefix reach 98%. Many single-state groups of areas do not, and how
  far they reach varies by state (computed exactly from the USPS list). Whether a second
  signal is required as well is open below.
- **Open: a second signal for bare 9-digit columns.** The first five digits alone cannot tell a
  ZIP+4 column from an identifier column concentrated in one prefix. Candidates: agreement with a
  companion state or city column in the same table; the distribution of the +4 part (real +4
  codes cluster, an SSN serial is uniform); the column name. Until one is chosen, a column that
  passes 0.90 is labelled "probable ZIP+4", and its privacy flag is computed independently and
  never cleared by the label (already a constraint).
- **Invalid** means: not normalisable, `00000`, outside 00501 to 99950. The other absent
  repeating-digit values (11111 and so on) are **not found**, not invalid, because "absent from
  three lists" is not a USPS statement.
- ~~Whether the USPS list is committed~~: settled, a derived CSV is tracked and the
  spreadsheet is ignored (Amelia, 2026-10-16; PR #66).
- USPS's free 3-digit prefix file is **not** used: the full ZIP list makes it unnecessary.
