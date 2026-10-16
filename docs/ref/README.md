# Reference data

## `usps-zip-locale.csv`: assigned USPS ZIP Codes

Every 5-digit ZIP Code in the USPS **ZIP Locale Detail** file, with its
classification, locale name and state. The app's ZIP checks use it as their
reference list.

| | |
|---|---|
| Source page | <https://postalpro.usps.com/ZIP_Locale_Detail> |
| Publisher | United States Postal Service, PostalPro |
| USPS "file updated" date | see `file_updated` in [`zip-locale-source.yml`](zip-locale-source.yml) |
| Date this copy was fetched and recorded | see `recorded_on` in the same file |
| Distinct ZIP Codes, range | see `distinct_zips`, `lowest_zip`, `highest_zip` |

The dates and counts live in `zip-locale-source.yml`, which the build script
writes, rather than here, so the two cannot disagree.

### Columns

| Column | Meaning |
|---|---|
| `zip` | 5-digit ZIP Code, leading zeros kept |
| `class` | USPS ZIP classification code: `M` military ZIP; `P` ZIP having only Post Office boxes; `U` unique ZIP, assigned to a single organisation; blank, a standard ZIP with many addresses |
| `locale_name` | the post office or locale USPS associates with the ZIP |
| `state` | the state of that post office |
| `sheet` | which sheet of the USPS file the row came from: `ZIP_Locale`, `Unique` or `Other` |

The classification codes are USPS's own, from the *Address Information System
Products Technical Guide*, "ZIP Classification Code", printed pages 77 to 78
(<https://postalpro.usps.com/storages/2016-04/AIS_0.PDF>).

A ZIP can appear on more than one row when USPS lists it under more than one
locale. The USPS file also holds each post office's street address and other
operational fields; they are not carried here.

### What it does not cover

- **Not complete.** The file lists 41,486 distinct ZIPs in the October 2026
  edition, against USPS's own published count of 41,554, so about 68 assigned
  ZIPs are missing. Which ones is not known: nothing published names them.
  This is why a ZIP absent from this list is reported as "not in the
  reference list" and never as invalid.
- **Retired ZIPs are absent, and look the same as missing ones.** The
  `zipcodeR` package's list, frozen in June 2021, holds 1,031 ZIPs that are
  not in this file (536 unique, 285 PO box, 210 standard), among them 22222
  in Arlington and the Young America, Minnesota rebate-processing ZIPs such
  as 55555. Most are probably retired since 2021, but the two lists alone
  cannot tell a retired ZIP from one of the 68 missing (compared 2026-10-16).
- **No ZIP+4 codes.** USPS does not publish assigned +4 codes as a free list.
  A ZIP+4 value can be checked here for its shape and its 5-digit part only.
- **No history.** A ZIP retired before this edition is simply absent.

### How it is built and kept current

The spreadsheet itself is not tracked: it is a 4 MB binary that USPS replaces
monthly, so tracking it would add another 4 MB to the history every month,
and a diff of it shows nothing. This CSV is derived from it instead, sorted,
so each update's diff shows exactly which ZIPs were added, retired or
reclassified (Amelia, 2026-10-16).

To update after USPS publishes a new edition:

1. Download the file from the source page into `docs/ref/Zip_Locale_Detail.xlsx`
   (ignored by git).
2. Run `Rscript dev/check_usps_zip_locale.R --record` from the repository root.
   It rebuilds this CSV and `zip-locale-source.yml` from the download, writing
   neither until every value has been read.
3. Commit both files.

A weekly GitHub workflow, `.github/workflows/usps-zip-locale.yml`, compares
the source page with `zip-locale-source.yml` and opens an issue when USPS has
published a newer edition. Run the same check locally with
`Rscript dev/check_usps_zip_locale.R`.

### Terms

The source page states no licence or terms of use. The list is a public USPS
publication of ZIP Codes, which are facts; the operational fields that make up
most of the original file are left out. If USPS terms are found that restrict
this, the CSV comes out of the repository and the app falls back to reading a
local copy.
