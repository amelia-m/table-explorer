# Contrast remediation plan

Logged 2026-10-09. Not implemented: Amelia asked to hold until other work lands.

Target: WCAG 2.2 AA. Body text 4.5:1, large text (18.66px bold or 24px) and
non-text UI parts 3:1.

## What was measured

`dev/contrast_audit.R` (currently `_scratch/contrast_audit.R`, see step 4) parses
the `:root` and `body.light-mode` blocks out of `inst/app/www/styles.css`, computes
relative luminance per WCAG, and reports every foreground token against every
background token. Full table: `_scratch/contrast_audit.csv`.

Failures below 4.5:1 today:

| Theme | Foreground | Background | Ratio | 3:1 |
| --- | --- | --- | --- | --- |
| dark | `--text-faint` `#475569` | `--bg-surface` `#1e293b` | 1.93 | fails |
| dark | `--text-faint` | `--bg-base` / `--bg-inset` `#0f172a` | 2.36 | fails |
| dark | `--empty-text` `#475569` | same as above | 1.93 / 2.36 | fails |
| dark | `--text-muted` `#64748b` | `--bg-surface` | 3.07 | passes |
| dark | `--text-muted` | `--bg-base` / `--bg-inset` | 3.75 | passes |
| light | `--text-faint` `#94a3b8` | `--bg-base` `#f1f5f9` | 2.34 | fails |
| light | `--text-faint` | `--bg-inset` `#f8fafc` | 2.45 | fails |
| light | `--text-faint` | `--bg-surface` `#ffffff` | 2.56 | fails |
| light | `--empty-text` `#94a3b8` | the three above | 2.34 - 2.56 | fails |
| light | `--text-muted` `#64748b` | `--bg-base` | 4.34 | passes |
| light | `--danger` `#dc2626` | `--bg-base` | 4.41 | passes |
| light | `--warn` `#a16207` | `--bg-base` | 4.49 | passes |

`--text-faint` carries the sidebar's per-table row and column counts
(`.loaded-table-item .tbl-meta`), the loaded-table count, the empty-list text,
the ERD hint, DataTables' "showing n entries" line and the relationships section
headers: 9 uses. `--text-muted` carries the header subtitle, legend items, the
ERD empty state and pagination: 6 uses.

## Steps

1. **Retire `--text-faint` as a text colour.** At 1.93:1 nothing but a new value
   fixes it, and every use is real text, not decoration. Dark: `#94a3b8`
   (5.8:1 on `--bg-surface`), which is today's `--text-secondary`. Light:
   `#64748b`. Keep the token name so all 9 uses move together. `--empty-text`
   takes the same values. This alone fixes the sidebar screenshot.
2. **Lift `--text-muted`.** Dark `#8595ab` (about 4.6:1 on `--bg-surface`),
   light `#5b6879` (about 5.0:1). Re-measure rather than trusting these numbers:
   they were computed by hand from the formula, not by the script.
3. **Fix the two light-theme status colours.** `--danger` `#dc2626` to `#b91c1c`
   (about 5.9:1), `--warn` `#a16207` to `#854d0e` (about 6.4:1). Check the pill
   backgrounds at `styles.css:224-228` after the change: those set their own
   foreground and background pairs and are not in the token table.
4. **Keep the audit honest.** Move the script to `dev/contrast_audit.R` and add a
   test that every foreground token clears 4.5:1 against every background token
   it is actually used with, so a palette edit fails the suite instead of the
   eye. The pairing list is hand-maintained; a token used on a surface not in the
   list is not checked, and that limitation belongs in a comment.

## Open questions

- After step 1, `--text-faint`, `--text-secondary` and `--empty-text` hold the
  same value in dark mode. Either collapse them into one token, or give
  `--text-faint` a distinct value that still clears 4.5:1. Collapsing loses the
  hierarchy the names imply; keeping three names with two meanings is worse.
  Amelia decides.
- Pill, badge and status colours (`.pill-*`, `.rel-status-*`, `.erd-*`) set their
  own pairs and were not audited. They need the same treatment, and the pairing
  list in step 4 should grow to cover them.
- `--accent` on `--accent-bg` is used for chips and highlighted cells; it passes,
  but the new relationship-panel highlight (PR #28) adds another pairing worth
  adding to the list.
