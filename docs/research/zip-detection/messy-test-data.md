# TidyTuesday and Rdatasets files used in the messy-data ZIP measurement

Written 2026-10-20 from `zip-messy-data.md`, `messy_download_files.R` and
`messy_download_files.log`. Those, the other scripts named below and the downloads live in the
git-ignored `_scratch/research/` folder (paths such as `data/public/messy/` are relative to it), so
this file is the durable record of what was pulled, why, and what each file showed. None of the
data is committed, following the project profile's rule on public test data: counts, rates and
checksums only. TidyTuesday comes first; the Rdatasets files have their own section below.

## What they were for

The ZIP+4 detection draft (`_scratch/contracts/2026-10-16-zip-detection-draft.md`) proposes
confirming a column of 9-digit values as ZIP+4 when at least 90% of them have a first five digits
in the USPS list, with state agreement and "mixed forms" (5- and 9-digit values in one column) as
second signals. Those were first measured on federal files (IRS, FEC, CMS, DOL), which are probably
cleaner than a research extract. The messy-data run of 2026-10-17 tested them on ZIP columns typed
by people or merged from several systems: city and state open-data portals, Rdatasets and these
TidyTuesday files.

The TidyTuesday files supplied most of the run's **bare 9-digit** columns, the case that needs
confirming (EADA sports, NYC elevators, NSF terminations), its one **identifier control** (Petfinder
`id`), and several examples of literal `NA` text and lost leading zeros.

## How they were fetched

- Found by `messy_header_scan.R`, which read only the header line of 1,189 TidyTuesday CSV and TSV
  files (HTTP Range request) and listed ZIP-like column names (`data/public/messy/header_scan.csv`;
  the repository tree it scanned is `data/public/messy/tidytuesday_tree.json`).
- Downloaded by `messy_download_files.R` on 2026-10-17 at 23:28 UTC from
  `https://raw.githubusercontent.com/rfordatascience/tidytuesday/main/data/<path>`, saved as
  `data/public/messy/files/tt_<name>.csv`. **Whole files, every column**, unlike the portal tables,
  of which only the ZIP and state columns were downloaded.
- Only the ZIP, state and identifier columns were read. No row was printed, saved or reported.
- The TidyTuesday commit was not recorded, so a fetch from a later `main` could differ. The MD5s
  below pin what was measured.
- Licence: the TidyTuesday repository is CC0 1.0 (its `LICENSE` file, corroborated by WebFetch).
  The original publishers' own terms were **not read**. Publishers below are taken from folder and
  file names, not from each week's README (corroborated at best).
- Some files contain names (restaurant names, Petfinder animal names). They are public, and none
  of those columns was read.

## The files

Sizes in bytes. "n" is non-missing, non-blank ZIP values. "Found" is the share whose first five
digits are in the USPS list.

| Saved as | TidyTuesday path | Publisher | Size | MD5 | Columns used |
|---|---|---|---|---|---|
| `tt_nyc_restaurants.csv` | `2018/2018-12-11/nyc_restaurants.csv` | NYC DOHMH | 96,428,600 | `d384223ed419e21eca3d3ee45a0c02c3` | `zipcode` |
| `tt_phl_tickets.csv` | `2019/2019-12-03/tickets.csv` | OpenDataPhilly (parking violations) | 93,112,024 | `8b84d163bae1f390ca7de8faea13f535` | `zip_code` |
| `tt_dog_descriptions.csv` | `2019/2019-12-17/dog_descriptions.csv` | Petfinder, via The Pudding | 67,934,276 | `cac5847cf5e31953f385973c973d213f` | `contact_zip`, `contact_state`, `id` |
| `tt_sf_permits.csv` | `2022/2022-07-05/sf_permits.csv` | DataSF (building permits) | 42,941,336 | `99909aed2a71be6f8bf5015b82c3b796` | `zipcode` |
| `tt_eada_sports.csv` | `2022/2022-03-29/sports.csv` | US Dept of Education, EADA | 25,544,572 | `25698e6a7f677d9e9d0938fe93389991` | `zip_text`, `state_cd` |
| `tt_fuel_stations.csv` | `2022/2022-03-01/stations.csv` | US DOE Alternative Fuels Data Center | 24,451,676 | `59c6f365a7bfa1d28ec4f26d9eddd214` | `ZIP`, `STATE`, `PLUS4` |
| `tt_elevators.csv` | `2022/2022-12-06/elevators.csv` | NYC Dept of Buildings, via the `elevators` package | 13,586,064 | `19d2803e41d23c2b05f8b3f1f46f84aa` | `ZIP_CODE` |
| `tt_nsf_terminations.csv` | `2025/2025-05-06/nsf_terminations.csv` | NSF award terminations (Grant Watch) | 3,728,528 | `0878862678e3050d1ce75e7efc93c1fa` | `org_zip`, `org_state` |
| `tt_seattle_pets.csv` | `2019/2019-03-26/seattle_pets.csv` | City of Seattle | 3,367,591 | `e4e36c4606f011f9673a168c7f7b77d1` | `zip_code` |
| `tt_saferparks.csv` | `2019/2019-09-10/saferparks.csv` | Saferparks | 2,832,488 | `1c83c7f4706f850b6261d6513019afbd` | none |
| `tt_broadband_zip.csv` | `2021/2021-05-11/broadband_zip.csv` | Microsoft | 1,459,091 | `08e9d747c0fff27f59878748041a32c0` | `POSTAL CODE`, `ST` |
| `tt_nyc_squirrels.csv` | `2019/2019-10-29/nyc_squirrels.csv` | NYC Open Data (Squirrel Census) | 814,652 | `dcfcb850076c88f53686269a3bca70b9` | `zip_codes` |
| `tt_pizza_barstool.csv` | `2019/2019-10-01/pizza_barstool.csv` | Barstool Sports | 66,097 | `a5abef9802a56b7a72a0cc431afea3d1` | `zip` |

Thirteen files, 376,266,995 bytes (about 359 MiB) in all.

## What each one showed

- **NYC restaurants, `zipcode`** (295,386 values): every value 5 digits and found. A clean
  5-digit baseline.
- **Philadelphia parking tickets, `zip_code`** (1,260,891 values as text): 173,588 (13.77%) are the
  literal text `NA`; every other value is 5 digits and found. The app's `read.csv()` turns `NA`
  into missing by default, so the app would see them as missing rather than as failures.
- **Petfinder dog descriptions:** `contact_zip` (58,180 values) 99.8% found, and its USPS state
  matches `contact_state` 100% of the time. **`id` is the run's identifier control:** every value
  is 9 bare digits, only 29.45% have a first five digits in the USPS list, and state agrees on
  0.95%. So both the 0.90 threshold and state agreement reject it.
- **SF building permits, `zipcode`** (86,103 values): all 5 digits and found; 26 literal `NA`.
- **EADA sports, `zip_text`** (132,327 values): 9.3% bare 9-digit (12,371), found at 99.96%, mixed
  with 5-digit values. State agreement 99.90% overall and 99.84% on the 9-digit values. 45 literal
  `NA`. A typical real bare ZIP+4 column.
- **Alternative fuel stations, `ZIP`** (59,927 values): 99.9% found, state agreement 99.90%, one
  `00000`. Its `PLUS4` column holds no non-blank value, so no ZIP+4 could be built from it.
- **NYC elevators, `ZIP_CODE`** (76,081 values): 82.2% bare 9-digit (62,521), all found, and every
  one ends in `0000` (a ZIP with `0000` appended, or a zero-filled +4; inference). That supports
  the draft's choice not to treat a `0000` +4 as invalid. 8,389 values are a lone `0`, which
  becomes `00000` and is invalid either way.
- **NSF terminations, `org_zip`** (1,041 values): 95.8% bare 9-digit (997), all found, and only
  4.2% 5-digit. The thinnest "mixed forms" case measured.
- **Seattle pets, `zip_code`** (52,519 values): 99.1% 5-digit; 71 separated ZIP+4s, all found; 397
  literal `NA`.
- **Broadband by ZIP, `POSTAL CODE`** (32,735 values): 2,406 values had lost their leading zero
  and are padded back correctly; 99.9% found; state agreement 99.92%.
- **NYC squirrels, `zip_codes`** (3,023 values): 3,014 are the literal `NA`; the other 9 are
  probably a Socrata region code, not ZIPs (inference). Reported, not used in any conclusion.
- **Barstool pizza, `zip`** (463 values): 64 four-digit values (leading zero already lost in the
  file), padded back and found.
- **Saferparks:** no ZIP column. Downloaded only because the header scan could not read its first
  line. Not used.

## The Rdatasets files

Rdatasets (https://vincentarelbundock.github.io/Rdatasets/) serves CSV copies of datasets bundled
in CRAN packages, which let the run use package data without installing the packages.

- Found by the same header scan, over all 3,648 Rdatasets CSVs, using its index
  (`data/public/messy/rdatasets_index.csv`).
- Downloaded by `messy_download_files.R` on 2026-10-17 at 23:28 UTC from
  `https://vincentarelbundock.github.io/Rdatasets/csv/<package>/<item>.csv`, saved as
  `data/public/messy/files/rd_<package>_<item>.csv`. Whole files, every column. Only the ZIP and
  state columns were read.
- Licence: Rdatasets says its code is GPL-3 and that it found no definitive licence for the
  datasets, which it believes are free to redistribute (corroborated, WebFetch of the site's front
  page). The packages' own licences were **not read**. Each file's provenance is its package, which
  is the citation to use in docs.
- Rdatasets does not state an edition for these files, so the MD5s are the only pin.

| Saved as | Package and dataset | Original source (corroborated) | Size | MD5 | Columns used |
|---|---|---|---|---|---|
| `rd_openintro_seattlepets.csv` | `openintro::seattlepets` | City of Seattle pet licences | 3,391,216 | `909ce73399ec743bba10fa368e40b662` | `zip_code` |
| `rd_collegeScorecard_school.csv` | `collegeScorecard::school` | US Dept of Education College Scorecard | 1,961,388 | `cd3ef487c719fe3ccb53f1b3aaf746e7` | `zip`, `state` |
| `rd_modeldata_Sacramento.csv` | `modeldata::Sacramento` | Sacramento real estate sales | 66,293 | `ce5149258a5463b959516b388f8605ff` | `zip` |
| `rd_wooldridge_meapsingle.csv` | `wooldridge::meapsingle` | Michigan schools | 25,412 | `2a8acf72da51f2ee24a19148fab8dc62` | `zipcode` |
| `rd_Stat2Data_RailsTrails.csv` | `Stat2Data::RailsTrails` | Massachusetts house sales near rail trails | 21,208 | `e007c9ef3364e588abed587430390bc8` | `Zip` |
| `rd_openintro_nyc.csv` | `openintro::nyc` | not recorded | 4,864 | `6fd4507c699780d4881cde4ca2091c8a` | none |

Six files, 5,470,381 bytes (about 5.2 MiB) in all.

What each one showed:

- **College Scorecard, `zip`** (11,300 values): the richest of the six. 56.0% 5-digit and 43.9%
  9-digit (4,966: 608 bare, 4,358 separated), found at 99.66% (the bare ones at 100%). State
  agreement 99.76% overall and 99.56% on 9-digit values. 4.0% of the 9-digit values have a `0000`
  +4. A real mixed column, with both bare and separated ZIP+4s.
- **Seattle pets via openintro, `zip_code`** (52,122 values): the same City of Seattle data as the
  TidyTuesday copy, but the 397 literal `NA` values arrive as missing here, presumably because the
  package stored them as `NA` (inference). 71 separated ZIP+4s, all found.
- **Sacramento, `zip`** (932 values): every value is shaped `A99999`, a letter before five digits,
  so none normalises and the column is never recognised as a ZIP. That it is a factor-level prefix
  added by the package is an inference, not checked against the package source. A useful example
  of a ZIP column the detection will miss by design.
- **RailsTrails, `Zip`** (104 values): every value is 4 digits, Massachusetts ZIPs whose leading
  zero was lost before the package stored them, padded back and all found. Systematic loss, the
  case the "leading zeros lost" note is for.
- **Michigan schools, `zipcode`** (229 values): all 5 digits and found. A clean small column.
- **`openintro::nyc`:** no ZIP column. Downloaded only because the header scan could not read its
  first line. Not used.

## What the run concluded, with these files in it

Over all 30 real columns in the run (portals, Rdatasets and these files), bare 9-digit values were
found at 99.80% or better on every column with at least 100 of them, so 0.90 keeps a margin of
about 10 points. Every real column with bare 9-digit values also held 5-digit values. State
agreement separated real columns (99.31% to 100% on 9-digit values) from the Petfinder identifier
(0.95%). The full tables are in `zip-messy-data.md`; the numbers here are copied from it.

## To fetch them again

Run `messy_download_files.R` from the repository root, which fetches all nineteen, or fetch each
path above with its URL pattern, then compare MD5s against these tables. A mismatch means the file
changed upstream since 2026-10-17 (TidyTuesday's `main`, or an Rdatasets rebuild), and the
measurement would need re-running rather than quoting. The Rdatasets files can also be read from
the packages themselves, which is the provenance to cite either way.
