# TODO

## Open items from the ZIP, Excel and privacy work (2026-10-16 to 2026-10-17)

In full wording. Research behind these lives in `_scratch/research/` (local only):
`zip-repdigits.md`, `zip-validation-sources.md`, `zipcoder-contribution.md`,
`zip4-threshold-measurement.md`, `state-agreement-results.csv`, `zip-messy-data.md`. The
draft build contract is `_scratch/contracts/2026-10-16-zip-detection-draft.md`.

### Decisions waiting on Amelia

- [ ] **Second signal for bare 9-digit ZIP+4 columns.** Measured: on public data a bare
      9-digit column's first five digits hit the USPS list at 99.55% or better on real ZIP
      columns and at most about 75% on EIN columns, so 0.90 separates typical columns; but an
      identifier concentrated in one prefix can clear it (EINs with prefix 77 reach 98.3%; SSNs
      from one SSA area reach 99%). Two second signals measured well: **state agreement** (the
      ZIP's USPS state matches the row's state column: real columns 97.3% to 100%, EINs at most
      51.7%, Nebraska-area SSNs 0%), and **mixed forms** (every real column with bare 9-digit
      values also held 5-digit values; no identifier column did). Proposed rule: label ZIP+4 when
      the hit rate is at least 0.90 and either state agreement is at least 0.90 or 5- and
      9-digit forms are mixed; otherwise "probable ZIP+4", awaiting confirmation. **Amelia
      decides** whether to adopt it.
- [ ] **Normaliser rules from the messy-data run** (city open data, TidyTuesday, Rdatasets),
      each a proposal: (2) in text columns, do not pad 6 to 8 digit values to 9, because there
      they are typos that hit the USPS list at about 1%; report them as invalid ("6 to 8 digits;
      a ZIP+4 has 9") and leave them out of the confirmation count, while numeric columns keep
      the padding, where it restores lost zeros correctly; (3) require exactly 4 digits after a
      separator and never pad a short +4; (4) accept `99999-` and a blank +4 as a 5-digit ZIP
      (Los Angeles writes 43,206 of them); (5) show "leading zeros lost" only when the loss is
      systematic, since an isolated 4-digit value in a text column is mostly a typo. **Amelia
      decides** which to adopt.
- [ ] **What "invalid" means.** Proposed: unreadable values, `00000`, and anything outside the
      USPS list's own range, taken from its minimum and maximum (today 00501 to 99950, which
      matches USPS's published range at facts.usps.com) rather than hard-coded. Repeating-digit
      ZIPs absent from the list are "not in the USPS list; may be a placeholder" (Amelia's
      wording, 2026-10-16); ZIPs in zipcodeR's 2021 list but not today's are "possibly
      retired"; a +4 of `0000` is valid (the IRS uses it on up to 24% of values). **Amelia
      decides** whether the definition stands.
- [ ] **Unformatted SSNs are not flagged by value.** The privacy value pattern requires hyphens
      (`R/utils_privacy.R`), so a column of bare 9-digit SSNs whose name says nothing is labelled
      "phone number" and treated as not personal. Proposed: flag a column that is at least 80%
      bare 9-digit values as "possibly SSN or ZIP+4" for review, which also sends ZIP+4 columns
      through review once. **Amelia decides.** The name additions in #67 are separate and do not
      cover this.
- [ ] **Bare 10-digit phone numbers are not flagged by value either.** Flagging them would also
      flag NPI provider numbers, which are 10 digits and public. **Amelia decides** whether the
      review cost is worth it.
- [ ] **Contributing the USPS list to zipcodeR.** zipcodeR has no contributing guide, freezes
      its bundled `zip_code_db` by policy, builds newer bundles from Census, GeoNames and
      uszipcode only, and never drops a ZIP. The maintainer's own unposted draft names
      "authoritative USPS validation" as the bar for adding ZIPs. Suggested route: settle the
      USPS licence question, then Amelia opens an issue offering the USPS edition as validation
      data, with the comparison numbers; a pull request only if he agrees. Opening it is
      Amelia's outward action. He has replied to such issues in 19 to 207 days.
- [ ] **The USPS licence question**, which also affects the CSV tracked in #66. The PostalPro
      page states no terms (read 2026-10-16); usps.com's site terms reportedly restrict
      reproduction, not re-read because the hosts were not resolving. Check: read
      https://about.usps.com/termsofuse.htm. **Amelia decides** what follows.
- [x] **`fec16`**: approved 2026-10-17 for tests and as a cited source, with no copies of its
      data committed (rule in `.agents/project-profile.md`). Measured the same day (fec16 0.1.6,
      six ZIP columns): every one mixes 5- and 9-digit values; the 9-digit values' first five
      digits hit the USPS list at 98.85% to 100%, and their USPS state matches the row's state at
      99.83% to 100%. All 9-digit values are bare, with no separator.
- [ ] **`campfin`** (a deliberately messy, made-up Vermont file, useful for the normaliser, not
      the threshold) would need installing and is not measured. **Amelia decides.**
- [ ] **Scratch downloads**: about 173 MB of federal files in `_scratch/research/data/public/`
      and the city, TidyTuesday and Rdatasets files in `.../public/messy/`. Keep or delete.
      Also six public USPS and Census documentation files that web tools auto-saved into the
      Claude session's own results folder. **Amelia decides.**

### Pull requests waiting on Amelia

- [ ] **#63** example values in the privacy review window, on request (interaction on real data).
- [ ] **#64** Excel column types: fast 1,000-row guess by default, a notice on longer sheets.
- [ ] **#65** ERD settings and key collapsible, settings on one row (visual).
- [ ] **#66** USPS ZIP list as a derived CSV plus the weekly update check. After merging, one
      manual run from the Actions tab shows whether USPS lets GitHub's runners in.
- [ ] **#67** privacy name additions (SSN spellings, tax ids, `bday`, `cell`).

### Work items, no decision needed

- [ ] **Build the ZIP detection itself** once the decisions above are made, from
      `_scratch/contracts/2026-10-16-zip-detection-draft.md`.
- [ ] **Literal non-ASCII characters in `R/mod_erd.R`** (nine of them: arrows, a download glyph,
      middle dots). They render today and would break the way the sidebar chevrons did (#62) if
      the file were ever re-encoded. Convert them to `\u` escapes.
- [ ] **Other disclosures lack a visible marker.** #65 fixed the ERD settings and key with a
      `te-disclosure` class; the dictionary's "Privacy and example settings", the Table Details
      column lists and the unconnected-tables list still show no triangle. One class per element.
- [ ] **The six files left out of the Air reformat** (#61) still need formatting once the
      detection chain lands: `R/utils_inference.R`, `tests/testthat/test-inference.R`,
      `tests/testthat/test-prose-parent.R`, `dev/fixtures/public/fetch.R`,
      `dev/fixtures/public/score_public.R`, `dev/fixtures/public/sweep_settings.R`.

### Assumptions recorded, not findings

- [ ] **SSA area-to-state assignments** used in the state-agreement check (Massachusetts 010 to
      034, New York 050 to 134, Nebraska 505 to 508 and others) were recalled, not read from an
      SSA source. An SSA table would settle them.
- [ ] **No real bare 9-digit ZIP+4 column without 5-digit values was found** in either public
      measurement, so the "mixed forms" signal has not been tested against one. Searching for
      such a column would settle whether it should ever reject.
- [ ] **The messy-data "read as number" rows** used `data.table::fread`'s type guess as a stand-in
      for the app's `read.csv()`; a column-by-column comparison would settle whether they match.

## Recovered from older scratch notes (2026-10-19)

These were in untracked notes under `_scratch/` and had not reached this file. Each is given as
the note had it; the date says how old it is, and none has been re-checked against the current
branches unless it says so.

From the containment-signal hand-back (2026-10-10, branch `feat/containment-signal`):

- [ ] **Ambiguity-demoted links are returned with the rest.** `resolve_fk_parents()` demotes a
      link to low confidence ("ambiguous: values fit 9 tables") but keeps it so it can be
      reviewed, and `score_public.R` counts every returned link. On Chinook, containment took the
      returned set from 29 found / 9 hit to 59 found / 10 hit, because a child with a handful of
      distinct values is contained in every unrelated 1..N primary key. The real
      `customer.supportrepid -> employee.employeeid` came back at low (0.486) among eight junk
      siblings. **Amelia decides** between: `detect_fks()` dropping ambiguity-demoted links whose
      only value evidence is containment; or the Relationships tab hiding demoted links by
      default, so the returned set and the reviewed set stop being the same list.
- [ ] **Self-references cannot be found on values.** `detect_fks()` skips `t2 == t1` in the
      content path, so only `self_ref_match()`'s naming path can find a self-reference, and it
      misses Chinook's `employee.reportsto -> employee.employeeid`. Containment adds eight junk
      links for `ReportsTo` instead (its three values sit inside eight unrelated keys). **Amelia
      decides** whether the content path should also run a table against its own `pk_map[[t1]]`.
- [ ] **Containment has no switch of its own.** It is gated behind
      `enable_flags[["value_overlap"]]` (still so on `feat/tentative-presets`, checked
      2026-10-19), because `app_server.R` passes an explicit flag list and a new key would read as
      `FALSE` there. If presets should switch containment on its own, the flag goes into
      `R/utils_inference.R` and both callers in the same change. Decide with the preset work.
- [ ] **The "nearly contained" tier can never carry a link by itself.** A child needs 100
      distinct values before one can be the missing 1%, and from 25 distinct values the chance
      discount stops applying, so `containment_near` (0.99) always arrives with `overlap_high`
      (0.98), and its weight (0.84, below the 0.85 high threshold) only adds to a link already at
      high. Written into the comment beside the weight. An orphan-tolerant tier that asserts a link
      alone would need one of those thresholds to move. **Amelia decides** whether that is wanted.
- [ ] **Assumed, not measured: containment above the sample cap.** `overlap_from_profiles()`
      compares the child's `uniq_sample` (at most 5,000 distinct values) with the parent's full
      distinct set, so "all N values present" is a claim about the values sampled. The reason text
      prints the sample count as the mitigation. A child with more than 5,000 distinct values, one
      outside the sample and absent from the parent, would settle whether the text reports the
      sample size rather than the column's distinct count.

From the follow-ups to #23, drop golem (2026-10-09), checked against `main` on 2026-10-19:

- [ ] **`withr` is used in tests but not declared.** `tests/testthat/test-run_app.R` calls
      `withr::local_options()` and `DESCRIPTION` does not list `withr` in Suggests, so
      `R CMD check` would warn. It works only because another package pulls it in. Add it to
      Suggests. (The same note's backlog item D3 is already marked done.)
- [ ] **A stale finding in `docs/research/shiny-framework/decision.md`** (around line 252) still
      says "`R/_disable_autoload.R` is missing". #23 added the file. Mark the finding resolved.

From #64's own "Not covered" list (2026-10-16):

- [ ] **Assumed, not checked: the Excel upload path and spaced paths.** On this machine readxl
      fails on `.xlsx` files whose path contains spaces. Uploads land in a temp directory without
      spaces, which probably avoids it. Uploading an `.xlsx` from a spaced folder through the app
      would settle it. (ODS files go through `readODS` and #64 does not touch them.)

## Detection measurement on public datasets (2026-10-10)

Harness: `dev/fixtures/public/fetch.R` then
`dev/fixtures/public/score_public.R chinook faers lahman`. It reads whole
tables, no row cap. Chinook's ground truth is read from its declared foreign
key constraints; FAERS and Lahman have none, so theirs are hand-written files
under `dev/fixtures/public/truth/`.

| dataset | truth links | `main` recall / precision | `feat/possible-key-names` recall / precision |
|---|---|---|---|
| chinook | 11 | 90.9 / 14.7 | 81.8 / 31.0 |
| faers | 4 | 100.0 / 12.3 | 75.0 / 50.0 |
| lahman | 21 | 71.4 / 0.9 | 95.2 / 90.9 |

Read these with their limits in mind:

- Lahman's ground truth is written from the CRAN package documentation, not
  read off database constraints. Only single-column links are listed, and
  links into `Teams` are composite on (yearID, teamID, lgID) with the
  `teamID` part alone listed, so Lahman precision inherits that.
- FAERS has no declared constraints either; its truth file is hand-written
  from the FDA's documented layout.
- Lahman's one miss on the rules branch is
  `homegames.parkkey -> parks.parkkey`.
- Lahman is the easy case: 31 tables but nearly every real link is
  `playerid` into `people.playerid`, which the naming rules already catch.
  It earns its place as a regression guard, because a signal that recovers
  unconventional links by admitting junk shows up there first.

Open items from this work:

- [ ] **Pagila is deferred** (Amelia, 2026-10-10). It needs a running Postgres
      instance, the only one of the four datasets that is not a file or a CRAN
      package. Chinook already covers the conventionally named,
      declared-constraint case, so nothing is blocked. Left open rather than
      closed because the harness still names Pagila in its dataset list and
      `score_public.R pagila` prints a SKIP line: either leave it as a known
      gap or say so in the harness README.
- [ ] **The Lahman package lives in the user library, not the project renv
      library.** It was installed with `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE`
      so that worktrees can see it. A clone on another machine, and CI, will
      not have it: `score_public.R lahman` prints a SKIP line there rather
      than failing, so a CI run that silently stops measuring Lahman is
      possible. Either add Lahman to the renv lockfile, or make the harness
      exit non-zero when a dataset named on the command line is unavailable.
- [ ] **`dev/check.R` runs only the synthetic scorer, not the public
      harness.** The public figures are therefore measured by hand and can
      drift from the branch they are quoted against. Decide whether
      `dev/check.R` (and CI) should run Chinook and Lahman, which take about
      a minute together, or whether the public harness stays a manual step.
- [ ] **Rule 4 (two-signal floor) from the detection work is still not
      done**: a single content signal cannot raise a candidate when the
      child column's distinct count is below a threshold (start at 5); it
      needs overlap plus cardinality, or a naming signal. It is listed in
      the 2026-10-09 block above and has not been built.
- [ ] **`detect_shared_columns()` has no `truncated` attribute**, so a
      shared-columns list cut short by a cap cannot be told from a complete
      one where it is shown. Assumed, not verified: the cap is reachable on
      a wide schema. Checking `attributes()` of the return value on the
      real extract would settle it.
- [ ] **The 1:1 relationship path draws from `pk_map` only**, so a pair whose
      parent is near-unique rather than strictly unique is never labelled
      one-to-one. Not verified against the real extract; reading the
      cardinality column for a known near-unique parent would settle it.
- [ ] **`dev/check.R` needs `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE` in a fresh
      worktree** and does not set it itself, so the first run in a new
      worktree fails on a missing library rather than saying why. Either set
      it inside the script or print the reason.
- [ ] **PR #54 (`feat/detection-rules-scoring`) merges behind settings**
      (Amelia, 2026-10-10). It holds three rules: the chance-overlap discount,
      the cardinality floor at 12 distinct values, and the requirement that a
      foreign key's parent be a key or near key. Together they roughly double
      precision on Chinook and FAERS and drop recall, and the lost links share
      a shape: the child name does not match the parent table, the values are
      small dense integers, the parent is a key. Since the hard-coded rules
      are becoming settings, the question is no longer whether to merge #54
      but which of its three rules are on by default. **That is decided from
      the sweep, not before it**, and nobody has yet measured the three rules
      separately: all three figures quoted anywhere are for all three applied
      at once. The sweep's per-rule rows will settle it.
- [ ] **Detection presets, now three pieces.** The hard-coded rules become
      settings and the preset list is chosen from measurement, not proposed
      (Amelia, 2026-10-10). So: the containment signal lands first (contract
      `docs/contracts/2026-10-10-containment-signal.md`, agent running); then
      the settings and sweep contract
      (`docs/contracts/2026-10-10-detection-settings-and-sweep.md`, approved,
      waiting on containment because both change `R/utils_inference.R`); then
      Amelia reads the sweep, picks candidate presets, checks them against her
      own real extract, and the preset UI contract
      (`docs/contracts/2026-10-10-detection-presets-draft.md`) is finished
      with that list and dispatched. Its one remaining open question is
      whether a chosen preset is remembered between sessions; proposed per
      session only, recorded in the export.

## Open items from the detection measurement work (2026-10-14)

Everything four agents deferred, plus this session's own deferrals, in full
wording. Written here rather than left in pull request bodies, because nobody
rereads those for open work. Decisions are marked **Amelia decides**.

### Decisions waiting on Amelia

- [ ] **Which combinations become presets, and what the defaults should be.**
      `dev/fixtures/public/sweep-2026-10-13.csv` on branch
      `feat/detection-settings-sweep` holds 117 measured rows over Chinook,
      Lahman and FAERS, covering 70 distinct settings combinations. Measured
      apart, only `prose_parent_guard = "refuse_target"` improves any figure
      at high confidence on any public schema: Chinook precision 90.0 to
      100.0 at unchanged 81.8 recall, nothing on Lahman or FAERS, which have
      no prose parent to refuse. Nothing beats the defaults on Lahman (37
      combinations tie at 95.7 / 100.0) or on FAERS. **Amelia decides** which
      combinations are worth naming as presets, after checking the candidates
      against her own data.
- [ ] **Whether `prose_parent_guard` should default to `"refuse_target"`.**
      It is the only switch with measured support, it costs no recall
      anywhere, and it scores a third fewer pairs on Chinook. The default is
      still `"allow"` because a sweep is not a licence to pick a default.
      **Amelia decides.**
- [ ] **PR #54 (`feat/detection-rules-scoring`): which of its three rules
      stay on.** The sweep answers the question that blocked it. Measured
      apart on the three public schemas: the cardinality floor
      (`cardinality_min_distinct`) and the possible-key-name tier change no
      reported link and no confidence level in any of the 117 rows, and the
      chance-overlap discount changes a figure only in the Chinook
      combinations where containment is switched off, so containment and the
      discount cover the same pairs. **This does not mean those three rules
      are useless.** The case the chance discount was written for,
      `episode.number_of_items` wholly inside `member.width_cm`, is
      in Amelia's own data, which is not in this harness. **Amelia
      decides**, ideally after one run against her extract.
- [ ] **Whether to relax the parent-key requirement, which the measurement
      says no to.** `parent_key_requirement = "composite"` is the only route
      to the two FAERS `drug_seq` links, but it buys them at low confidence
      while demoting three links that were high, so a reviewer sees fewer
      correct links, not more; and it takes Lahman precision from 100.0 to
      16.4 at high. Recommendation on the measurement: leave the default at
      `"key"`. **Amelia decides.**
- [ ] **Whether an exact-uniqueness-only composite setting is worth
      measuring as a fourth value.** The composite probe uses
      `parent_key_min_frac`'s tolerance rather than exact uniqueness, because
      exact uniqueness recovers nothing on FAERS (measured: 0 columns
      admitted). That tolerance is where most of the Lahman precision cost
      comes from: 86 of 107 high-confidence inventions attach to one near
      component, `pitching.BFP`, a count of batters faced. **Amelia decides.**
- [ ] **Whether `resolve_fk_parents()`' ambiguity rule should be revisited
      before the parent-key requirement is touched at all.** Relaxing the
      requirement demotes five of six real FAERS `primaryid` links from high
      to low, which is a larger loss than the two links it buys. The two
      changes interact, and measuring either alone understates the other.
      **Amelia decides** whether that is its own piece of work.
- [ ] **Pagila.** Identified as a fourth public dataset and deferred
      (Amelia, 2026-10-10): it needs a running PostgreSQL instance. Until it
      is in, the harness covers three schemas, two of them small and
      conventionally named and one (FAERS) large and barely named. The
      harness still names Pagila in its dataset list, so `score_public.R
      pagila` reports what it parsed and stops. **Amelia decides** whether to
      set up Postgres or to say in the harness README that Pagila is out.
- [ ] **The four root-level R files.** `db_connectors.R`, `export_utils.R`,
      `file_readers.R` and `inference.R` mirror the `R/utils_*.R` files and
      nothing sources them, but they are stale rather than identical:
      `inference.R` is 611 lines against `R/utils_inference.R`'s 1476,
      `export_utils.R` 166 against 1298. `tests/testthat/test-db_connectors.R:2`
      still names the old path in a header comment. **Amelia decides** whether
      they are legacy copies to delete.
- [ ] **`sample_data/` exists twice**: seven CSVs at the repository root
      against a four-table subset in `inst/extdata/sample_data/`, with
      `customer_addresses.csv`, `product_suppliers.csv` and `suppliers.csv`
      only at the root, and `dev/browser-checks/sample_app.R` reading the root
      copy. The two `schema.json` files also differ and have not been diffed.
      **Amelia decides** whether to move the three extra files into
      `inst/extdata/` or to keep the root copy as the browser-check input
      deliberately.
- [ ] **Whether the preset UI contract is ready to dispatch.**
      `docs/contracts/2026-10-10-detection-presets-draft.md` has one open
      question left: whether a chosen preset is remembered between sessions.
      Proposed per session only, recorded in the export. It also waits on the
      preset list above. **Amelia decides.**

### Work items, no decision needed

- [ ] **The six excluded files still need formatting.** The partial Air
      reformat deliberately leaves `R/utils_inference.R`,
      `tests/testthat/test-inference.R`, `tests/testthat/test-prose-parent.R`,
      `dev/fixtures/public/fetch.R`, `dev/fixtures/public/score_public.R` and
      `dev/fixtures/public/sweep_settings.R` unformatted, because open
      branches edit them and reformatting would mean resolving the same
      conflict six times. Format them in their own formatter-only commit once
      the detection chain has landed.
- [ ] **FAERS was measured at 8 of the 70 settings combinations**, and the
      two combinations handed over from the Chinook and Lahman frontiers both
      deduplicated onto rows already in its base set, so the frontier handoff
      contributed nothing. A combination that ties on Chinook need not tie on
      FAERS, and FAERS is the schema most like a real extract, so this is the
      gap that most affects a preset decision. What would close it: run the
      24 Chinook-frontier-tied combinations on FAERS, about an hour at 50 to
      150 seconds each.
- [ ] **The 31 Lahman combinations at `parent_key = "composite"` were not
      run.** Measured, Lahman at composite takes 122 seconds with the pair cap
      raised and scores 117,620 pairs, so 32 of them is about 65 minutes, past
      the contract's 30-minute-per-dataset stop line. At the default 50,000
      cap they finish in 81 seconds but are CAPPED, and the capped run reports
      60.9 percent recall where the uncapped run reports 95.7, so their recall
      would have been an artefact of where the scan stopped.
- [ ] **`parent_key_requirement = "any"` was measured on Chinook only**
      (high 81.8 / 50.0, overall 90.9 / 13.2). It is documented as a
      measurement bound rather than a setting to ship. What would settle its
      cost on the others: one run each of Lahman and FAERS at
      `parent_key=any` with `max_pairs` high enough not to truncate.
- [ ] **`parent_key_min_frac` (0.99) is still a constant**, not a setting.
      The original sweep contract named it as one of the constants to
      parameterise; the dispatch amendment's list of six switches does not
      include it, and the amendment won. What would settle its effect: one
      sweep axis over 0.95, 0.99 and 1.0 on the three public datasets.
- [ ] **The recall and precision arithmetic now exists twice**, in
      `score_public.R`'s `score_one()` and in `sweep_settings.R`'s
      `run_combo()`. They agree today, which the sweep's default rows
      reproducing the harness baselines proves, and nothing keeps them in
      step: a change to `score_one()`'s notion of `found` would make the
      sweep's rows silently incomparable with the harness's. A shared
      `metrics(rels, truth)` that both call would fix it.
- [ ] **`score_candidate()` takes its settings on trust.** `detect_fks()`
      validates them and every pair in a scan arrives through it, so a
      per-pair check would cost a comparison 1.9 million times over on FAERS
      to catch what the entry point already caught. A standalone caller
      passing a wrong type still switches a rule off silently. The reasoning
      is in a comment above the function; whether that is enough is open.
- [ ] **`dev/fixtures/public/fetch.R` prints `missing: parent_key=composite`
      and `unknown dataset: max_pairs=2000000` on stderr**, because it reads
      `commandArgs()` itself when `score_public.R` sources it. Cosmetic, and
      confusing in a log. One line in `fetch.R` fixes it.
- [ ] **Two sessions carry the same Lahman truth-file commit under different
      hashes.** The composite-parent branch cherry-picked `6ab4b0e` ("fix:
      write the Lahman ground truth from the data") because its stated base
      predated the fix. Either that cherry-pick stays, or the branch is
      rebased onto the `feat/containment-signal` tip that carries the
      original. Harmless until those branches merge, then it is a conflict to
      resolve by hand.
- [ ] **`composite_probe_max_pairs` (8) and `composite_probe_sample_rows`
      (100,000) were taken from the contract and never tuned against a
      measurement.** The reasoning is in comments beside them.
- [ ] **No review skill has been run on `feat/containment-composite-parent`.**
      Its contract asked for a push and no pull request, so it was pushed
      without one. A review is needed before a pull request is opened, if one
      ever is: the measurement's verdict was "do not relax", so the branch may
      exist only as evidence.
- [ ] **Lahman comes from the CRAN package in the user library**, installed
      with `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE` so that worktrees can see
      it. A clone on another machine, and CI, will not have it:
      `score_public.R lahman` prints a SKIP line there rather than failing, so
      a CI run that silently stops measuring Lahman is possible. Either add
      Lahman to the renv lockfile, or make the harness exit non-zero when a
      dataset named on the command line is unavailable.
- [ ] **`dev/check.R` runs only the synthetic scorer, not the public
      harness**, so the public figures are measured by hand and can drift from
      the branch they are quoted against. Chinook and Lahman together take
      about a minute. Decide whether `dev/check.R` and CI should run them.
- [ ] **`dev/check.R` cannot disable the renv autoloader for its own
      session.** It sets the variable, but `.Rprofile` has already run by
      then, so the setting only reaches the scorer it launches as a child
      process. A fresh worktree therefore needs
      `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE` on the command line, or every
      check fails with "there is no package called 'testthat'", which reads
      like a broken checkout. Documented in the README, not fixed.
- [ ] **A probable defect in session restore, flagged and not fixed.**
      `R/mod_export.R:250-271` writes manual links, declared links, confirmed
      reviews and suppressed links only when the restored file has some, so
      restoring a session that legitimately had none leaves the current
      session's in place and the result is a merge rather than a restore. The
      dictionary and declared keys are handled the other way on purpose, with
      a comment saying so.
- [ ] **Nothing gates the `R CMD check` findings.** `tests/testthat.R:5`
      uses `test_package()`, which runs nothing under `R CMD check`, and
      neither CI nor `dev/check.R` goes through `R CMD check`, so the review
      backlog's I6, I7 and C1 have no check at all.
- [ ] **A stale comment at `R/app_server.R:301-302`** says hiding empty
      tables "affects the ERD, Table Details and Relationships views only",
      but `visible_tables_rv` also reaches Network overview and the Data
      Dictionary.
- [ ] **The empty test at `tests/testthat/test-inference.R`** ("detect_composite_pks
      skips columns with NAs in the combo") is still empty and is now
      unblocked: C2, the fix it waited on, is done. It is the only
      self-inflicted skip in the suite.
- [ ] **Nothing writes `inst/BUILD`**, so the footer build stamp's file path
      is dead code today and an installed copy built without one shows the
      package version with no sha or date. Whether the deploy path should
      write one is a code decision.

### Assumptions recorded, not findings

Each of these was written down without being checked directly. The check that
would settle it is named.

- [ ] **"No Lahman table has a strictly unique width-2 pair other than the
      ones admitted."** The exhaustive width-2 search was run on FAERS
      `drug24q1` only. The Lahman admissions come from the capped per-column
      probe, which stops at the first pair it finds, so other unique pairs may
      exist. A per-table exhaustive width-2 search over Lahman would settle
      it, and would also say whether the 12 admitted columns are the whole set
      or only the first found.
- [ ] **"`pitching.BFP` is admitted because `(playerID, BFP)` is within the
      duplicate tolerance."** Inferred from the reason text, not measured.
      Printing the distinct-pair count for that pair against `nrow(Pitching)`
      would settle it.
- [ ] **"`parent_key = any` is the true upper bound on recall."** Both `any`
      runs reach the same recall as `composite`, so there is no case where
      `any` finds something `composite` does not. Assumed, not demonstrated.
- [ ] **"`cardinality_min_distinct` and `possible_key_names` change
      nothing"** means they change no reported link and no confidence level in
      any of the 117 sweep rows. A signal may still have been added or removed
      inside a row without changing which pairs were reported: the outcome key
      tested was (found, hit, high_found, high_hit). Comparing signal sets per
      pair, rather than per row, would settle the stronger claim.
- [ ] **The browser checks' expected output values** (step 0's "6 columns
      were flagged", step 1's 17 columns, steps 2 to 8, `import_check.js`'s
      "7 table(s)" and 32 rows) were never run: Playwright and a Chromium
      binary are not installed. The privacy review changed underneath them,
      and no column in `sample_data/` is empty so the new empty-column filter
      cannot fire, which is reasoning and not a run. Running the block with
      Playwright available would settle it.
- [ ] **Most of the README's feature table was not re-verified** in the
      documentation refresh and is recorded as an assumption rather than a
      finding: database connectors, schema import, confidence scoring, signal
      toggles, scan triage, Table Details, the Data Dictionary tab, privacy,
      data-dict YAML, name cleaning, manual overrides, exports, duplicate
      handling, and the whole Python section. Several of those modules changed
      in the 75 commits the refresh was re-based over. Reading each row
      against its module would settle it.
- [ ] **The `secs` column in the sweep file ranks cost coarsely and is not a
      benchmark.** It is one timing per row on a shared desktop, and the same
      combination varied about 50 percent between runs. The accuracy columns
      reproduced exactly across four independent runs of the grid; the
      timings did not and cannot.

## Open items from the 2026-10-09 session

- [ ] **Vendored JavaScript is watched by nothing.** `inst/app/www/vendor/`
      carries elkjs and svg-pan-zoom as checked-in files, so Dependabot
      cannot see them (it reads manifests, not vendored source) and no
      advisory will ever reach us for them. Check them by hand
      occasionally: compare the version in each file's header against the
      project's releases, and read its changelog for security fixes.
      Alternative, if the manual check keeps slipping: add a tiny
      `package.json` listing both as dependencies purely so Dependabot
      watches them, and keep vendoring the built files.


Decisions waiting on Amelia, in full wording so they can be answered later.

- [ ] **Contrast remediation**: plan written at `docs/contrast-plan.md`, measured
      with `_scratch/contrast_audit.R`. Amelia asked to hold implementation until
      other work lands. Its own open question: after step 1 the tokens
      `--text-faint`, `--text-secondary` and `--empty-text` all hold `#94a3b8` in
      dark mode. Collapse them into one token, or give `--text-faint` a distinct
      value that still clears 4.5:1?
- [ ] **Column semantic types**: task contract at
      `_scratch/contracts/2026-10-09-column-semantic-types.md`, covering validated
      type guesses (ZIP first), a type confirmation queue reusing the Data
      Dictionary review pattern, a privacy-respecting value preview, type-driven
      FK matching (veto mismatched confirmed types, boost matched ones), bulk
      approval of grouped links, and cross-table column-pair rules. Not approved,
      not dispatched. Its open assumption: where does the list of valid 3-digit
      SCF ZIP prefixes come from, and is a one-off fetch at build time (recorded
      in a `dev/` script, generated data committed) acceptable on this machine?
- [ ] **Commit hygiene on `feat/dict-review-and-scroll`** (branch unpushed): it
      carries an empty commit of mine titled "placeholder", and commit `49fbd36`
      sweeps both the DT scrollbar fix and the empty-flagged-column queue work
      under a scrollbar-only message. Proposed fix: `git reset --soft HEAD~2` and
      recommit as two honest commits. Needs Amelia's go-ahead, per the rule on
      resets.
- [ ] **Dictionary scrollbar height**: currently `scrollY = "62vh"` plus
      `scrollCollapse`. Recommended instead:
      `max-height: calc(100dvh - var(--dict-chrome, 360px))` in CSS, so the
      offset lives in one place and the cap bites on short windows. The JS
      measure-and-set alternative needs three listeners and a visibility guard
      and was judged more fragile. Amelia to choose.
- [ ] **Merge order and visual checks for the open PRs**: #23 drop golem, #24
      schema quoting and port validation, #25 `db_load_table` dialect and strict
      limit, #26 collapsible sidebar, #27 ERD chips off shared trunks, #28
      relationship panel grid, #29 Table Details collapse. #27, #28 and #29 were
      verified only on an empty app or not at all, and need a look on the real
      schema before merging.
- [ ] **Detection noise: value overlap on counts and low-cardinality integers**
      (Amelia, 2026-10-09: its own PR, after the current PRs land). A count
      column such as a `*_month_count` holding {0..12} overlaps any `tlk_*.id`
      holding a contiguous 1..N almost perfectly, so `overlap_high` (weight
      0.90) plus `format_match` (0.40, shape `int_code`) produces a 49% low
      candidate. On the real schema this is a large share of the
      low-confidence rows. The only guard today is
      `is_fk_candidate()` at `R/utils_inference.R:748`, which rejects a column
      only when `n_unique <= 2 && n > 10` and it is not key-named.
      Agreed approach, rules 1 and 4:
      1. Chance-overlap discount: estimate expected overlap from the parent's
         domain density (distinct values `m` over range `R`) and score only the
         excess, `max(0, observed - expected)`. Overlap on a dense integer
         domain then carries almost no weight.
      4. Two-signal floor: a single content signal cannot raise a candidate when
         the child column's distinct count is below a threshold (start at 5);
         it needs overlap plus cardinality, or a naming signal.
      Rule 3 (a measure-name guard for `*_count`, `*_qty`, `*_amount`, `*_age`,
      `*_days`, `*_month`, `*_year`, `*_total`) is held back: `is_key_name()`
      already treats `_num` and `_no` as key-like, so the two lists contradict
      and that has to be resolved first.
      Acceptance: `Rscript dev/fixtures/score_detection.R` still reports 157 of
      157 real links at medium+ with 0 false, and the low-confidence count on
      Amelia's schema drops measurably (only she can measure that).
- [ ] **`limit = 0` semantics** (`db_load_table`, PR #25): currently 0 means zero
      rows, following `DBI::dbFetch()`. Useful only once a caller can use an
      empty frame for a schema-only probe: `mod_db_connect.R` drops frames with
      `nrow(df) == 0`. Build that path, or leave the semantics unused?

- [x] Add a "Hide empty tables" toggle (0-row tables) to the sidebar that filters
      them out of the ERD, Table Details, and Relationships views.
- [ ] (Maybe later) User-defined naming patterns for FK detection: a settings
      box for lookup-table prefix (e.g. `tlk_`), lookup key column (e.g. `id`)
      and FK template (e.g. `{entity}_id`), saved with the session. Built-in
      conventions (Access, Rails/Django, SQL Server, warehouse `_key`/`_sk`,
      code lookups, role prefixes) are detected automatically already.

- [ ] ERD redesign: see `docs/erd-redesign-plan.md` (done: model, exports,
      ERD tab, data dictionary, dbt constraints; next: session diff,
      lints).
- [x] Detection noise on Access-style schemas (lookups sharing ids 1..N):
      names now choose between parents that values can't tell apart, and
      Access files' declared relationships are read.
- [ ] (Maybe later) Read Access lookup-field `RowSource` queries as a second
      declared source (the Lookup Wizard already stores a relationship).
- [ ] (Maybe later) ERD, large schemas: **use the width**. ELK layer
      wrapping (`elk.layered.wrapping.strategy = MULTI_EDGE`) with
      `elk.aspectRatio` from the canvas, so hub-and-spoke schemas aren't one
      tall column.
- [ ] (Maybe later) Validate exported data-dict YAML with the data-dict
      command-line tool (`datadict::dd_validate_data()`, Suggests only). It
      downloads a binary at run time and validates Parquet files only, and
      the spec is pre-1.0 (0.1.0), so it stays optional. The export is
      checked against the spec's rules by hand for now.
- [ ] Lints / data-quality panel (Phase 4 in `docs/erd-redesign-plan.md`):
      tables without a PK, orphan tables, FKs whose values are missing from
      the parent (share of orphaned rows), nullable PK-like columns, and
      duplicate links into the same parent.
- [ ] (Maybe later) ERD, large schemas: **open focused**. With more than 40
      tables, start focused on the most-connected table with 2 hops instead
      of drawing everything.
- [ ] **Shared columns (branch `feat/shared-columns-ui`), deferred decisions.**
      The section on the Relationships tab shows `detect_shared_columns()`
      results and nothing else consumes them yet.
      (a) Should shared columns reach the ERD, the exports and the data
      dictionary, and if so how are they drawn so nobody reads them as
      references? The brief called this a later decision, so the UI says in
      words that they are not included.
      (b) A scan with scope "new" (the incremental triage path) rescans every
      table pair for shared columns rather than only the pairs the new tables
      bring, because `detect_shared_columns()` has no focus argument and this
      branch must not touch `R/utils_inference.R`. Measured at 1.6 s for a
      synthetic 52-table, 1.7M-row schema, so it was left alone. Add a
      `focus_tables` argument there, or leave it?
      (c) `detect_shared_columns()` stops at its 20,000 column-pair cap and
      returns what it has with no signal that it stopped, so a very wide
      schema would silently show a partial list. `detect_fks()` sets a
      `truncated` attribute for exactly this and the app warns on it. Worth
      the same there? Question for whoever owns `R/utils_inference.R`.
      (d) Minimum confidence is mapped to the overlap threshold (low 0.3,
      medium 0.5, high 0.8) because a shared column has no score of its own.
      Invented mapping, not measured against anything. Is it the behaviour
      Amelia wants, or should the section have its own threshold control?

## Follow-ups from the data dictionary work (PR #20)

Found in review, not fixed there. How the pieces work: `docs/internals.md`.

- [ ] "Hide empty tables" also hides tables imported from a schema or
      data-dict file (they have no rows), so their labels and descriptions
      vanish from the Data Dictionary tab and its downloads while it's on.
      Consider exempting tables that came from a schema import.
- [ ] A manual link identical to a declared one shows twice in the app
      (`combine_relationships()` in `R/utils_helpers.R` only folds detected
      links into declared ones). The data-dict export already de-duplicates.
- [ ] "Not personal" reviews re-ask after any data refresh, because they are
      tied to a hash of the column. Safe, but noisy for regularly refreshed
      data; a name-based review could survive refreshes if the column's
      value pattern doesn't change.
- [ ] The automatic personal-data guess still flags generic `name` columns
      on non-person tables (`products.name`). The review clears them; a
      table-name heuristic (people-like tables) could cut the noise.
- [ ] A data-dict re-import loses `number(id)` on foreign keys whose links
      were unconfirmed (they're under `todo`, not `relationships`), and all
      examples (no rows). Expected, but worth a note if round trips matter.

## Repository housekeeping (logged 2026-09-30)

Baseline: on `main` at `6276a1e`, with the real packages (R 4.6.1),
`testthat::test_local()` gives 209 tests, 1035 expectations, 0 failed, 0
errors and 4 expected skips. `Rscript dev/fixtures/score_detection.R` gives
157 of 157 real links at medium+, 0 false.

- [x] **Framework decision (2026-10-02): golem dropped, plain package.**
      Why, what changed, and when golem would be worth bringing back are in
      `docs/research/shiny-framework/decision.md`. Rejected: leprechaun,
      rhino and a plain `app.R`. This also resolved backlog items C3 (the
      upload limit now applies, 100 MB), I5, I13, M9, M10, M11 and D1.
- [ ] **R version for Connect Cloud (deferred 2026-10-02).** Connect Cloud
      supports R 4.0.0 to 4.6.0 (its R platform docs). This machine has only
      R 4.6.1, so a `manifest.json` written here names an unsupported
      version, and what Connect Cloud does then is undocumented. Amelia chose
      to wait: deployment is not imminent and Connect Cloud may add 4.6.1.
      Before the first deploy, check its supported range again. If 4.6.1 is
      still missing, either `rig add 4.6.0` (alongside 4.6.1; packages share
      the 4.6 user library) and write the manifest from it, or test-deploy
      on 4.6.1.
- [x] **renv adopted 2026-10-02** (`31b89ae`, Amelia's instruction).
      Explicit snapshot: `renv.lock` holds DESCRIPTION's Imports and their
      dependencies (93 packages, R 4.6.1). renv 1.2.4 leaves Suggests out
      (`snapshot.dev: false`), so testthat, pkgload, RSQLite and the database
      drivers are installed in the project library but not locked.
- [ ] **Lock the test packages in `renv.lock`?** A fresh `renv::restore()`
      on another machine gets the app's Imports but not testthat, so tests
      can't run there until it is installed by hand. Options:
      1. set `snapshot.dev = TRUE`, which locks all of Suggests, the heavy
         database drivers (rJava, odbc, bigrquery and so on) included;
      2. keep it as is, and document `renv::install(c("testthat",
         "pkgload", "RSQLite"))` for contributors;
      3. move the test essentials into a separate setup step.

      Recommendation: 2, until there is CI.
- [ ] **`.Rbuildignore` is still minimal** (backlog I6). renv created it
      with `^renv$`, `^renv\.lock$` and `^requirements\.txt$` only. A
      package release also needs `app.R`, `app.py`, `dev/`, `docs/`,
      `_scratch/`, `sample_data/`, the legacy root `.R` files, `CLAUDE.md`,
      `TODO.md`, `.agents/` and `.vscode/`.
- [x] **Salvage two fixes from branch
      `copilot/review-codebase-and-make-edits`** (one Copilot commit,
      2026-08-06, never opened as a PR). Re-apply them by hand as a small PR
      on current `main`; the code has moved too far to cherry-pick.
      1. `db_introspect()` in `R/utils_db_connectors.R` pastes the schema
         name into SQL inside quotes, so a schema name containing an
         apostrophe breaks the query. Quote it with `DBI::dbQuoteString()`.
      2. `R/mod_db_connect.R` turns a non-numeric port into `NA` with only a
         warning. Reject non-numeric or non-positive ports with a message.

      Do not take the branch's `mod_upload.R` change (superseded). Its
      session-restore change (always replace state, even with empty lists)
      is a design choice, not a fix: leave it unless wanted. In the same
      PR, two leftovers from the `is_lookup_table()` cache fix (`bf1823e`):
      - the comment above `.lookup_cache` in `R/utils_inference.R` still
        says "Memoised per shape";
      - add a test that a same-shaped table with renamed columns
        (`foo`/`bar` instead of `id`/`label`) is re-checked.

      Then delete the branch. Do all this before the Air reformat.

      Done 2026-10-08 in PR #24 (`salvage/db-hardening`): both fixes, the
      stale comment and the renamed-columns test. Schema quoting turned out
      to be six query sites, not one. Tests 0 failures; detection scorer
      still 157 of 157 at medium+, 0 false. Still open from this item:
      - [ ] Delete branch `copilot/review-codebase-and-make-edits` (local
            and remote) once PR #24 is merged. Needs Amelia's go-ahead.
      - [ ] **Third fix in the same branch commit, not salvaged (deferred
            2026-10-08, decision for Amelia).** `db_load_table()` in
            `R/utils_db_connectors.R` builds SQL with hand-quoted
            identifiers (`"schema"."table"`) and a backtick fallback, and
            does not sanitise `limit`. The branch rewrites it with
            `DBI::Id()` and `DBI::dbQuoteIdentifier()`, coerces a bad limit
            back to 10000, and replaces the fallback with
            `DBI::dbReadTable()`, plus 2 tests (a table name containing a
            space and a hyphen; `limit = 0`). This is old backlog item P2
            (not portable to SQL Server, fails silently). Left out to keep
            PR #24 to the logged scope. Worth its own PR; say whether to
            take it, and whether the `dbReadTable()` fallback is wanted.
- [ ] **Close draft PR #6 but keep its branch**
      (`copilot/evaluate-current-status`, 7 Copilot commits, 2026-09-11,
      conflicts with `main`) as a reference for the Python work. Its unique
      content is about 1050 lines of Python features in `app.py`: database
      connections, export, run detection, name cleaning and scan triage,
      plus SQLAlchemy in `requirements.txt`. Whether to port that depends
      on the framework research. Take two pieces separately:
      - its GitHub Actions R CI workflow (`.github/workflows/r-ci.yml`,
        Ubuntu, `devtools::test()`). `main` has no CI.
      - `URL`, `BugReports` and a real `person("Amelia", "Miramonti", ...)`
        in `DESCRIPTION`.

      Do not take its committed `__pycache__/*.pyc` file.
- [ ] **Air reformat as its own commit.** Add an `air.toml`, run
      `air format .`, run the tests, and commit the reformat alone so it is
      never mixed with content changes. Then add the commit to a
      `.git-blame-ignore-revs` file in a follow-up commit. With default
      settings, `air format --check .` reports 30 of 40 tracked R files
      would change. Do it after the salvage PR above. The research outcome
      does not block it.
- [ ] **Stale remote branches.** These have no commits that are not on
      `main`, and can be deleted with Amelia's go-ahead:
      - `copilot/expand-sample-data-composite-keys`
      - `copilot/fix-shiny-app-errors`
      - `copilot/fix-source-file-path-error`
      - `copilot/update-repo-sidebar-description`
      - `fix/composite-pk-and-erd-dblclick`

      These have one unmerged commit each, and need a look first:
      - `chore/package-metadata`: author email and LICENSE holder, mostly
        already on `main`;
      - `copilot/add-open-source-license`: an MIT LICENSE.

## Reference: ERD design examples

Third-party example diagrams, kept for design reference only (a possible
future redesign of the ERD tab). Local copies live in `docs/erd-examples/`
so agents without web access can view them. Sources, in the order given:

- https://lset.uk/blog/entity-relationship-diagram-explained-with-real-database-examples/
- https://lucid.co/diagram/erd/tutorial
- https://www.impacttechnology.co.uk/example-entity-relationship-diagram

Examples (source matched by the order the links were given, so likely
rather than certain):

- [`erd-student-course-enrollment.png`](docs/erd-examples/erd-student-course-enrollment.png)
  (likely lset.uk): Student / Course / Enrollment. Table cards with a
  colored header, a PK/FK badge column beside each field (FK1 marks a
  numbered FK group), 1:N cardinality labels on edges, relationship
  diamonds ("Enrolled In"), and a PK/FK legend.
- [`erd-hockey-playoffs-crowsfoot.png`](docs/erd-examples/erd-hockey-playoffs-crowsfoot.png)
  (likely lucid.co): hockey playoff app. Header colors group related
  tables, every column is listed, crow's-foot notation (one, many,
  zero-or-one), edges leave from the specific FK row and arrive at the PK
  row, orthogonal (right-angle) routing.
- [`erd-access-tbl-equipment-hire.png`](docs/erd-examples/erd-access-tbl-equipment-hire.png)
  (likely impacttechnology.co.uk): equipment hire / projects in Access
  `tbl*` style. `tblCATEGORIES`-style names, PK/FK1/FK2 badges with a
  separator between key and non-key sections, dashed crow's-foot lines for
  optional relationships, junction tables (`tblCONTACT_CAT`,
  `tblEQUIP_CAT`) for many-to-many links.

Ideas these suggest for this app (notes only, not scheduled):
column-level edges (FK row → PK row); PK/FK badges on nodes; crow's-foot
cardinality inferred from uniqueness; dashed lines for optional or
low-confidence links; grouping by header color (e.g. `tbl_` vs `tlk_`);
distinct styling for junction tables; an optional legend.
