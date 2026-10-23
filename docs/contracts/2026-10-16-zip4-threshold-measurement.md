# Task contract: measure the ZIP+4 confirmation threshold on public data

Date: 2026-10-16  Dispatch: one agent, read-only apart from new files in `_scratch/`
Request as given: "are there any publicly available datasets with zip codes that we can test this
default on?" then "dispatch the public dataset agent"

## Intent and scope

The ZIP detection contract (`docs/contracts/2026-10-16-zip-detection-draft.md`) labels a bare
9-digit column as ZIP+4 only once at least 90% of its values pass every offline check: the first
five digits, after restoring leading zeros, fall in 00501 to 99950 and appear in the USPS list. The
90% is a proposal nobody has measured. It has to separate two kinds of column:

- **real ZIP+4 columns**, which carry typos, placeholders and retired ZIPs, so a strict threshold
  could reject them;
- **9-digit identifiers that are not ZIPs** (an SSN, an IRS EIN, a bank routing number), whose
  first five digits hit the USPS list only by chance, estimated at about 40% and never measured.

Measure the hit rate for both kinds on real public data, and report the distribution, so the
threshold can be set from it.

## Non-goals

- No changes to the repository's tracked files. No branches, commits, pushes, issues or comments.
- **Install nothing.** Use base R, and packages already installed (`readxl`, `data.table` if
  present, `zipcodeR` is installed). Do not call `install.packages`.
- Do not register for anything, request an API key, or accept terms of use, a click-through
  licence or a cookie banner. A dataset behind any of those is reported as such and skipped.
- No dataset over about 250 MB compressed. Report larger ones with their size and skip them; a
  smaller official extract of the same source is fine.
- **Never print, save or report a row.** Some of these files carry names and addresses (FEC
  committee treasurers, nonprofit officers). Read only the ZIP and identifier columns, and report
  only counts and rates. Do not copy any dataset into the repository.

## Context

- The reference list: `docs/ref/usps-zip-locale.csv` (on branch `ci/usps-zip-locale-check`, #66; read here from its worktree under `_scratch/wt-usps/`),
  columns `zip, class, locale_name, state, sheet`. 41,486 distinct 5-digit ZIPs, October 2026
  USPS edition. Read its `zip` column as character.
- The optional 2021 list: `zipcodeR::zip_code_db$zipcode` (installed). Report hits against it as
  a second column, to show how much retired ZIPs matter.
- Candidate datasets, from memory and **not yet checked**; confirm each one's real URL, columns,
  format and terms before using it:
  - IRS Exempt Organizations Business Master File (EO BMF), per-state CSVs: a `ZIP` column mixing
    5-digit and ZIP+4, and `EIN`, a 9-digit identifier that is not a ZIP. Use several states,
    including at least one whose ZIPs start with 0 (New England, New Jersey, Puerto Rico).
  - FEC bulk data: the committee master and candidate master files carry a ZIP field reportedly
    stored as 9 digits with no hyphen, mixed with 5-digit. Use the small master files, not the
    multi-gigabyte individual contributions.
  - Federal Reserve FedACH or Fedwire routing directory: 9-digit routing numbers, never ZIPs. Skip
    if it needs a click-through agreement.
  - CMS NPPES (NPI registry): postal codes stored as unhyphenated 5- and 9-digit values. The full
    file is gigabytes; use it only if an official extract under the size limit exists.
  - Others you find that hold a real ZIP+4 column or a 9-digit non-ZIP identifier.
- Two synthetic controls, generated in your script, never from real data: uniformly random 9-digit
  numbers; and SSN-shaped numbers following the SSA's public rules (area 001 to 899 excluding 666,
  group 01 to 99, serial 0001 to 9999). These give the chance baseline.
- Normalisation to apply, as the detection contract specifies: text trimmed, one separator (`-`,
  `+`, space) between digit 5 and digit 6 removed; numbers converted without scientific notation;
  1 to 5 digits padded to 5 and read as ZIP, 6 to 9 digits padded to 9 and read as ZIP+4; anything
  else not a ZIP. The hit test uses the first five digits.
- R is at "C:\Program Files\R\R-4.6.1\bin\Rscript.exe". Set RENV_CONFIG_AUTOLOADER_ENABLED=FALSE.
  Never run `Rscript -e` with inline code on this machine: put code in a file. Downloads from R or
  PowerShell; the Bash tool's curl has failed DNS here before.

## Constraints

- Every dataset reported with its URL, the publisher's stated date or edition, file size, the
  column used, the number of non-missing values, and its terms as stated by the publisher.
- Per column, report: share that normalise; share 5-digit vs 9-digit after normalisation; share
  whose first five digits are in 00501 to 99950; share found in the USPS list; share found in the
  zipcodeR 2021 list; and the share found in either. For a real ZIP column, also report the hit
  rate on its 9-digit values alone, since the threshold applies to those.
- Every claim marked verified (you measured it or a primary source states it), corroborated, or
  unverified. A dataset you could not reach is reported with the error, not left out.
- Downloads go only to `_scratch/research/data/public/`.
  Scripts go to `_scratch/research/`.
- No em dash (U+2014) anywhere.
- Stop and report rather than deciding alone when a dataset turns out to hold data that is not
  public, or a download needs anything beyond an anonymous GET.

## Edge cases

- **A ZIP column that is mostly 5-digit with a few 9-digit values**: report both shares; the
  threshold question is about the 9-digit part.
- **Placeholder values** (`00000`, `99999`, `000000000`): count them and report them separately;
  they are exactly what the validity tiers are for.
- **Foreign postal codes in a US file**: count as not normalising.
- **An identifier column with leading zeros lost** (EINs and routing numbers can start with 0):
  pad as the normalisation says, and report how many were padded.

## Output requirements

- `_scratch/research/zip4-threshold-measurement.md`: one
  table with a row per column measured (dataset, column, kind: real ZIP / non-ZIP identifier /
  synthetic, n, and the shares above), then the distribution in words: the lowest hit rate seen
  on a real ZIP+4 column, the highest seen on a non-ZIP column, and the gap between them.
- A recommended threshold with the margin it leaves on each side, and how sensitive it is to
  retired ZIPs (USPS list alone vs USPS or zipcodeR).
- The script that produced every number, so it can be rerun.

## Acceptance and evidence

1. At least two real ZIP columns that hold 9-digit values, from different publishers.
2. At least one real 9-digit non-ZIP identifier column, plus both synthetic controls.
3. Every number in the table comes from the committed-to-scratch script, rerunnable.
4. No row of any dataset appears in the output or the report.
- The agent shows: the output file path, the script path, the URLs used, and the table.
- The agent lists, in full wording, every dataset it skipped and why, every claim it could not
  verify, and anything it assumed.

## Settled (Amelia, 2026-10-16)

- Measure the threshold on public data before it is fixed. "dispatch the public dataset agent".
