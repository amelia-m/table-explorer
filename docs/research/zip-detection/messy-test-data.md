# Public data used in the messy-data ZIP measurement

Written 2026-10-20 from `zip-messy-data.md`, `messy_download_files.R`, `messy_download.R` and
their logs. Those, the other scripts named below and the downloads live in the
git-ignored `_scratch/research/` folder (paths such as `data/public/messy/` are relative to it), so
this file is the durable record of what was pulled, why, and what each file showed. None of the
data is committed, following the project profile's rule on public test data: counts, rates and
checksums only. TidyTuesday comes first, then the Rdatasets files, then the open-data portal
tables. The TidyTuesday files were deleted locally on 2026-10-20; the rest are still in
`_scratch/research/data/public/messy/`.

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

## The open-data portal tables

Ten tables from city and state Socrata portals, chosen because their ZIPs were typed by people
(licences, inspections, business filings) and several hold ZIP+4 or a state column.

- Found by reading each portal's catalogue and each table's own schema, licence and update date
  (`messy_socrata_meta.R`; the schemas are saved in `data/public/messy/meta/<domain>_<id>.json`).
- Downloaded by `messy_download.R` from
  `https://<domain>/resource/<id>.csv?$select=<columns>&$order=:id&$limit=200000&$offset=<k>`
  (dataset page `https://<domain>/d/<id>`), saved as `data/public/messy/<domain>_<id>.csv`.
  **Only the ZIP and state columns were downloaded**, over the whole table, so no other field
  (names, addresses, licence numbers) ever reached this machine.
- Every table arrived complete: rows received equal the publisher's `count(*)` at download time
  (verified, `messy_download.log` and `messy_download2.log`). The first four were downloaded on
  2026-10-17 at about 00:31 UTC, the other six about 23 hours later.
- "Updated" is Socrata's `rowsUpdatedAt` (UTC), read on 2026-10-17 at about 00:30 UTC. The later
  six downloads may hold rows newer than that. Portal tables change daily, so a fresh download
  will not reproduce these counts; the MD5s pin what was measured. They were computed on
  2026-10-20 from the saved files, whose sizes match the download log byte for byte.

| Saved as | Publisher, dataset | Updated | Rows | Size | MD5 | Columns downloaded | Terms, as the publisher states them |
|---|---|---|---|---|---|---|---|
| `data.colorado.gov_4ykn-tg5h.csv` | Colorado Secretary of State, Business Entities in Colorado | 2026-10-16 | 3,124,420 | 68,753,198 | `a9169eaf842c2e69068a101cbb7f1064` | `principalzipcode`, `principalstate`, `mailingzipcode`, `mailingstate` | Public Domain (metadata, verified) |
| `data.ct.gov_n7gp-d28j.csv` | Connecticut Secretary of the State, Business Registry, Business Master | 2026-10-16 | 1,303,289 | 25,429,481 | `d6680f36297681017f4569af87373fb8` | `billingpostalcode`, `billingstate`, `records_address_zip_code`, `records_address_state` | Public Domain (metadata, verified) |
| `data.cityofchicago.org_r5kz-chrr.csv` | City of Chicago, Business Licenses | 2026-10-16 | 1,209,190 | 16,926,846 | `bf8574ccb918fb6cd53d8bbc496be22b` | `zip_code`, `state` | "See Terms of Use"; the terms pages returned HTTP 403, **not read** |
| `data.lacity.org_6rrh-rzua.csv` | City of Los Angeles Office of Finance, Listing of Active Businesses | 2026-10-15 | 632,799 | 13,807,481 | `9010122b33348cc23cc0c8026dcce889` | `zip_code`, `mailing_zip_code` | CC0 1.0 (metadata, verified) |
| `data.sfgov.org_g8m3-pdis.csv` | City and County of San Francisco, Registered Business Locations | 2026-10-16 | 368,422 | 8,522,790 | `ae04378cec74d39aff13897faa27a3ed` | `business_zip`, `state`, `mail_zipcode`, `mail_state` | ODC Public Domain Dedication and License (metadata, verified) |
| `data.cityofnewyork.us_nu7n-tubp.csv` | NYC DOHMH, NYC Dog Licensing Dataset | 2026-07-15 | 819,323 | 7,373,438 | `6074e1781cc0ea41afb7a02850dcd3c7` | `zipcode` | No licence in the metadata; nyc.gov's general terms reserve rights (corroborated); NYC Open Data's own terms **not read** |
| `data.cityofchicago.org_4ijn-s7e5.csv` | City of Chicago, Food Inspections | 2026-10-16 | 317,111 | 4,439,207 | `29601882186ec665a67d67d8e325cf10` | `zip`, `state` | As for Business Licenses, **not read** |
| `data.wa.gov_f6w7-q2d2.csv` | Washington State Dept of Licensing, Electric Vehicle Population Data | 2026-10-14 | 300,142 | 4,201,926 | `6f1cdc2ca4823adae1c6ddb30aeeeba3` | `zip_code`, `state` | ODC Open Database License (metadata, verified) |
| `data.cityofnewyork.us_43nn-pn8j.csv` | NYC DOHMH, Restaurant Inspection Results | 2026-10-16 | 296,819 | 2,655,677 | `b19b32526f70bc0f4cad850b38a443c2` | `zipcode` | As for Dog Licensing |
| `data.seattle.gov_jguv-t9rb.csv` | City of Seattle, Seattle Pet Licenses | 2026-10-06 | 38,413 | 345,116 | `f2826fca2b2bb30a4d5c7d3ad15b543c` | `zip_code` | Public Domain (metadata, verified) |

Ten tables, 152,455,160 bytes (about 145 MiB), plus ten small schema files in `meta/`. The
Washington table is under the ODbL. This file publishes only counts and rates from it; whether
the ODbL's share-alike terms reach summary figures like these was not checked.

What each one showed:

- **Colorado business entities** (3,031,769 principal ZIPs, 897,214 mailing): the largest and
  messiest. 2.9% and 4.3% 9-digit, mostly separated (85,392 and 37,547) with a few thousand bare.
  Found at 97.99% and 97.35%. Held 6 to 8 digit typos that front-padding turns into fake ZIP+4s
  (1,648 and 963 of them, found at 1.46% and 1.25%), which is why proposal 2 says not to pad 6 to
  8 digit text values. Counted with those, the bare 9-digit subset falls to 31.84% and 34.62%;
  without them, exactly-9-digit bare values are found at 99.86% and 99.80%. Also 1,075 `00000`,
  Canadian and UK postcodes, `99999-` and `99999-____` shapes, and 4-digit values that are typos,
  not lost zeros (their state agrees only 5.42% of the time). State agreement 99.75% and 99.52%
  overall, 99.62% and 99.31% on 9-digit values.
- **Connecticut business registry, `billingpostalcode`** (1,059,887 values): 19.8% 9-digit, almost
  all separated (209,791), found at 99.94%; state agreement 99.87% overall and 99.97% on 9-digit
  values. `records_address_zip_code` has only 415 values.
- **Los Angeles active businesses:** in `zip_code` (632,799 values) every value that normalises is
  a separated ZIP+4 (589,232), found at 100%, and none is 5-digit: a real column with no 5-digit
  values at all. 43,206 values are
  `99999-` (a trailing separator, empty +4), which `normalise()` rejects, so the column normalises
  at only 93.1%. `mailing_zip_code` (341,602) is 88.8% 9-digit, also separated.
- **Chicago business licences, `zip_code`** (1,208,861 values): all 5-digit, 99.9% found; 128
  `00000` and 139 text placeholders. State agreement 99.97%.
- **San Francisco registered businesses:** `business_zip` (367,702 values) all 5-digit, 99.8% found,
  93 `99999`, state agreement 99.94%. `mail_zipcode` (165,810) holds 5,711 `99999` values (3.4%),
  apparently a placeholder (inference), which the draft's range rule already makes invalid.
- **NYC dog licences, `zipcode`** (819,314 values): all 5-digit and found once 421 values shorter
  than 5 digits are padded (92% of those padded values are then found).
- **Chicago food inspections, `zip`** (317,069 values): all 5-digit and found; state agreement 100%.
- **Washington electric vehicles, `zip_code`** (300,127 values): all 5-digit and found; state
  agreement 100%.
- **NYC restaurant inspections, `zipcode`** (293,678 values): all 5-digit and found.
- **Seattle pet licences, `zip_code`** (38,291 values): all 5-digit and found.

The portals supplied the run's only typed separated ZIP+4 columns at scale (Colorado, Connecticut,
Los Angeles), and the only real column found with no 5-digit values (Los Angeles, separated). That
matters for "mixed forms": it can only add evidence for bare 9-digit columns, never reject a
column, because a real ZIP+4 column without 5-digit values exists.

## What the run concluded, with these files in it

Over all 30 real columns in the run (portals, Rdatasets and these files), bare 9-digit values were
found at 99.80% or better on every column with at least 100 of them, so 0.90 keeps a margin of
about 10 points. Every real column with bare 9-digit values also held 5-digit values. State
agreement separated real columns (99.31% to 100% on 9-digit values) from the Petfinder identifier
(0.95%). The full tables are in `zip-messy-data.md`; the numbers here are copied from it.

## To fetch them again

Run `messy_download_files.R` from the repository root, which fetches the nineteen TidyTuesday and
Rdatasets files, and `messy_download.R` for the ten portal tables; or fetch each path above with
its URL pattern. Then compare MD5s against these tables. Portal tables will not match, because
they change daily: re-measure them rather than comparing. A mismatch means the file
changed upstream since 2026-10-17 (TidyTuesday's `main`, or an Rdatasets rebuild), and the
measurement would need re-running rather than quoting. The Rdatasets files can also be read from
the packages themselves, which is the provenance to cite either way.
