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
| Date this copy was downloaded and recorded | see `fetched_on` in the same file |
| Distinct ZIP Codes, range | see `distinct_zips`, `lowest_zip`, `highest_zip` |

The current dates and counts live in `zip-locale-source.yml`, which the build
script writes. Figures quoted below are dated and describe the edition they
name.

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

A ZIP can appear on more than one row: when USPS lists it under more than one
locale, when it appears on more than one sheet (in the October 2026 edition,
247 ZIPs are on both `Unique` and `Other` with the same locale), or when the
same ZIP and locale carry two states (24605, Bluefield, is listed under both
VA and WV). One row in that edition, 05076 TOPSHAM DPOBU, has no state.

The USPS file also holds each post office's street address and other
operational fields; they are not carried here.

### What it does not cover

- **Not complete.** The October 2026 edition lists 41,486 distinct ZIPs,
  against USPS's own published count of 41,554
  (<https://facts.usps.com/42000-zip-codes/>, read 2026-10-16), so about 68
  assigned ZIPs are missing. Which ones is not known: nothing published names them.
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

1. Run `Rscript dev/check_usps_zip_locale.R --record` from the repository root.
   It downloads the edition the source page links to (it does not use any copy
   already on disk, so the record cannot name one edition and hold another),
   rebuilds this CSV and `zip-locale-source.yml` from it, and writes both or
   neither. It refuses an edition whose ZIP count moves by more than five
   percent from the last one; check the file, then add `--force`. The download
   is kept at `docs/ref/Zip_Locale_Detail.xlsx`, which git ignores.
2. Commit both files.

A weekly GitHub workflow, `.github/workflows/usps-zip-locale.yml`, compares
the source page with `zip-locale-source.yml` and opens an issue when USPS has
published a newer edition. When the page cannot be reached or read, or the
check itself fails, the run fails, so GitHub sends its failure email rather
than leaving a warning on a green run. Run the same check locally with
`Rscript dev/check_usps_zip_locale.R`.

"Current" means the page shows the recorded edition date and download link.
The check reads the page, not the file, so a file USPS replaced at the same
address without changing the page would still read as current.

GitHub disables scheduled workflows in public repositories after 60 days with
no activity. If the weekly runs stop, re-enable the workflow from the Actions
tab.

### Terms

The source page states no licence or terms of use. The list is a public USPS
publication of ZIP Codes, which are facts; the operational fields that make up
most of the original file are left out. If USPS terms are found that restrict
this, the CSV comes out of the repository and the app falls back to reading a
local copy.
