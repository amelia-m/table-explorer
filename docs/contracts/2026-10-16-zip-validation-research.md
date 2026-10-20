# Task contract: ZIP and ZIP+4 validation research

Date: 2026-10-16  Dispatch: two agents in parallel, read-only, disjoint output files
Request as given: "dispatch agents to confirm the above. did we already pull in any way to verify
that zips are valid? if not, let's see if there's a database we can run auto-checks against.
better yet is there an r package that does this? ... I'd like to see if we can verify the zip+4
values are valid"

## Intent and scope

The app recognises a ZIP column by shape only (`^\d{5}(-\d{4})?$` over 80% of a sample), so
`00000` reads as a ZIP and a 9-digit ZIP+4 without its hyphen does not read as one at all. Amelia
wants invalid ZIPs flagged and ZIP+4 values recognised and checked. Before anything is built, two
facts are needed: whether a pasted table of repeating-digit ZIPs is true, and what can be checked
against, offline, under a licence the package can ship.

- **Agent A, verify the repeating-digit claims.** For each of 00000, 11111, 22222, ... 99999, say
  whether it is an assigned USPS ZIP and, if so, where and of what kind, with a primary source.
  Also confirm the lowest and highest assigned ZIPs (the claim is 00501 and 99950).
  Output: `_scratch/research/zip-repdigits.md`.
- **Agent B, survey what ZIPs and ZIP+4s can be validated against.** R packages first, then
  databases. Output: `_scratch/research/zip-validation-sources.md`.

## Non-goals

- No code changes in the repository. No branches, commits or pushes.
- **Do not install anything**, R packages included. Read package documentation, CRAN pages,
  reference manuals and source on GitHub or CRAN instead.
- Do not register for, or call, any API that needs an account or a key. Read its documentation.
- Do not send any ZIP value to any service. There is no data of Amelia's in this task and none
  must be invented that looks like it.
- Each agent writes only its own output file. Agent A does not survey sources; Agent B does not
  verify the repdigit table beyond noting where a source would.

## Context

- The claims to verify are this table, from an AI-assisted web search Amelia ran. Treat every row
  as unverified until a primary source confirms it:

  | ZIP | Claim |
  |---|---|
  | 00000 | Unassigned; common null or placeholder value in forms |
  | 11111 | Unassigned |
  | 22222 | Arlington, VA; unique ZIP for the Marine Corps Institute |
  | 33333 | Unassigned |
  | 44444 | Newton Falls, OH; standard delivery |
  | 55555 | Young America, MN; unique or PO Box, rebate processing |
  | 66666 | Unassigned |
  | 77777 | Unassigned |
  | 88888 | Unassigned |
  | 99999 | Unassigned; highest active is 99950, Ketchikan AK; common default placeholder |

- Primary sources, in order of authority: USPS publications and tools (the ZIP Code lookup, the
  Postal Bulletin, Publication 65 and the City State product documentation); then the Census
  Bureau, noting that ZCTAs are not ZIP codes and omit PO-box-only and unique ZIPs; then data
  products that cite USPS as their source. Wikipedia and AI summaries are leads, not sources.
- What the repository already has: format-only detection at `R/utils_inference.R:68`; a draft
  contract that proposed range 00501 to 99950 plus a bundled list of valid 3-digit SCF prefixes,
  stalled on where that list comes from (`docs/contracts/2026-10-09-column-semantic-types.md`,
  Open assumptions).
- The package is MIT-licensed R and runs offline on Amelia's machine. A data source is only useful
  if it can be bundled with the package or fetched once by a `dev/` script, and its licence allows
  that.
- Data the app is pointed at includes records above low risk. **Any check that sends values off the
  machine is ruled out for that data**, however convenient. Say plainly which sources are offline
  and which are not.

## Constraints

- Every claim in the output carries its source as a link, and is marked **verified** (a primary
  source says so directly), **corroborated** (two independent secondary sources agree) or
  **unverified**. A claim of absence ("unassigned", "no such package") is written as an
  assumption with the check that would settle it, unless a source states the absence directly.
- Quote at most one short passage per source, under 15 words. Summarise otherwise.
- Dates come from the system, never typed from memory. Say when each source was last updated where
  it says.
- No em dash (U+2014) anywhere in the output.
- Stop and report rather than deciding alone when a source contradicts the pasted table on a row.

## Edge cases

- **A ZIP assigned once and since retired**: report it as retired, with dates where a source has
  them, not as unassigned.
- **A unique ZIP with no residential delivery** (one organisation, a PO box block): it is still a
  valid ZIP. Say which kind it is.
- **ZCTA and ZIP disagree**: report both and say which governs validity (USPS).
- **ZIP+4**: the +4 is assigned at USPS's delivery-segment level and is not published as a free
  list. Agent B says what can be checked offline (format; the 5-digit part; anything else?) and
  what only an online, address-based service can check, and what such a check would send.
- **A package that is archived on CRAN or unmaintained**: report it with its archive date and the
  date of the data it ships, because a stale ZIP list rejects new ZIPs.

## Output requirements

- Agent A: one Markdown file, a table with one row per repdigit ZIP (claim, finding, kind, source,
  status), then the lowest and highest assigned ZIP with sources, then everything left unverified.
- Agent B: one Markdown file covering, for each candidate (R packages such as `zipcodeR`, and
  databases such as USPS City State, Census ZCTA, HUD-USPS crosswalks, GeoNames, free commercial
  lists): what it covers (5-digit, ZIP+4, unique and PO-box ZIPs or not), how current, offline or
  online, size, licence and whether it may be bundled, and how it would be used here. Then a
  recommendation for 5-digit validation and a separate one for ZIP+4, each with its cost.
- Both list, in full wording, anything they could not settle and the check that would settle it.

## Acceptance and evidence

1. Agent A's table has all ten repdigit rows, each with a source link and a status.
2. Agent A states the lowest and highest assigned ZIP, each with a source.
3. Agent B covers at least three R packages or states that fewer exist, with the search it ran.
4. Agent B states, for ZIP+4, whether any offline validation beyond format and the 5-digit part
   exists, with sources, and what an online check would send off the machine.
5. Agent B names a licence for every source it recommends, from the source's own terms page.
- Each agent shows: the file it wrote and the list of URLs it relied on.
- Each agent lists, in full wording, every claim it could not verify and the check that would
  settle it.

## Settled (Amelia, 2026-10-16)

- Research only: confirm the claims and find what ZIPs and ZIP+4s can be checked against, an R
  package preferred.
- Implementation (auto-flagging invalid ZIPs, recognising and documenting ZIP+4) follows from the
  findings and gets its own contract.
