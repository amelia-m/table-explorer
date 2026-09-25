# ERD redesign plan

Status: **approved; step 1 (relationship model + exports) in progress.**
It is based on the reference diagrams in
`docs/erd-examples/`, a web review of ERD best practices, and a map of the
current code (September 2026).

## Goal

The app should produce diagrams that look like, and can be read like, a
standard physical-database ERD. That means:

- tables drawn as cards with their columns and key badges;
- crow's-foot cardinality and optionality;
- lines that run from the FK row to the PK row.

It should also stay usable at 50+ tables, and export documentation that can
be diffed and kept up to date.

## Where we are today

- The ERD (`R/utils_vis.R::build_network`, `R/mod_erd.R`) uses visNetwork.
  - Each table is a plain-text box ("name / N rows | M cols"). Columns appear
    only in the hover tooltip.
  - Lines run table to table, point child → parent, are coloured by
    detection method, and are dashed only when confidence is low.
- visNetwork **cannot**:
  - draw crow's-foot ends;
  - attach a line to a specific column row;
  - route lines at right angles;
  - render rich HTML inside a node.
- Cardinality (1:1 vs 1:N), optionality (whether the FK is nullable),
  identifying vs non-identifying relationships, and junction tables are
  **not computed anywhere**.
- `generate_mermaid_erd` writes every relationship as `||--o{`, has no FK
  or UK markers, and doesn't quote names.
- Confirmed relationships look the same as unreviewed ones in the ERD.
  Tables with no relationships have no list of their own.

## Principles (from the research)

1. **Physical ERD, crow's-foot notation.** Show both cardinality (the
   maximum: one or many) and optionality (the minimum: zero or one) at each
   end. Avoid Chen diamonds and "1:N" text labels.
2. **Standard line meaning.** Solid = identifying (the FK is part of the
   child's PK). Dashed = non-identifying. How a relationship was found
   (declared, inferred or confirmed) is shown with colour or a badge, not
   by line style, so the standard meaning isn't overloaded.
3. **Key badges in a left gutter** (PK, FK1..n, UK), with the PK columns
   first and a rule under them. Show the data type, and mark nullable
   columns.
4. **Scale by focusing:** a neighbourhood view (N hops), detail levels (all
   columns / keys only / names only), subject-area grouping with header
   colours, and a separate list of orphan tables.
5. **Parent → child flow** (parents to the left of or above children),
   right-angle lines with few crossings, and one compact legend.
6. **Documentation as code:** deterministic Mermaid and DBML exports, a
   data dictionary, and diffs between sessions.

## Phase 1: Relationship semantics (data layer, no UI change)

Add `R/utils_erd_model.R`, which builds an `erd_model(tables, rels, pk_map,
composite_pk_map)`. From it, every view and export draws the same facts.

- **Per column:** type (a readable class such as int, decimal, text, date,
  bool), whether it is nullable (`anyNA`), whether it is unique, and its
  key roles (PK, CPK, FK*n*, UK). FK numbers follow column order.
- **Per relationship:**
  - `child_max`: `"one"` if the FK column is unique in the child (1:1),
    otherwise `"many"`.
  - `parent_min`: `"zero"` if the FK column has NAs (optional), otherwise
    `"one"`.
  - `child_min`: `"one"` only if every parent key appears in the child;
    usually `"zero"`.
  - `identifying`: TRUE when `from_col` is part of the child's PK or
    composite PK.
  - `provenance`: `declared` (schema or database), `manual`, `confirmed`
    or `inferred`, plus the score and reasons.
- **Per table:**
  - `role`: `junction` (a composite PK of two or more FKs, or two or more
    FKs plus only a few non-key columns), `lookup` (`is_lookup_table`),
    `orphan` (no relationships) or `entity`.
  - `subject_area`: to start with, the connected component, split by
    prefix (`tlk_` lookups get their own group). The user can edit it
    later.
- **Self-references:** allow `t2 == t1` in `detect_fks` for key-named
  columns that don't match the table's own PK (`parent_id`, `manager_id`).
  This is behind the same naming rules and has tests.
- Empty tables have no data to measure, so their cardinality is `unknown`.
  They are drawn with neutral ends and a "?" in the tooltip.
- **Tests:** unit tests for every derivation, plus golden tests on the
  sample data and a synthetic Access-style schema.

## Phase 2: A new "Diagram" view (standard ERD rendering)

**Renderer:** vendor **elkjs** (layered layout with ports and right-angle
line routing; EPL-2.0) and draw SVG ourselves in
`inst/app/www/erd.js`. The server sends the Phase 1 model as JSON
(`session$sendCustomMessage`). This is the only option here that supports
row-anchored lines and right-angle routing together.

- Graphviz through DiagrammeR has crow and tee arrowheads, but it ignores
  ports when routing at right angles.
- Mermaid's renderer can't anchor lines to column rows.

**Drawing:**

- **Table card:**
  - The header shows the name and a row count. Its colour comes from the
    subject area, with a distinct style for junction and lookup tables.
  - A key gutter holds PK / FK*n* / UK badges.
  - Each column row shows the name, the type, and a "∅" when nullable.
  - The PK section sits at the top with a rule under it.
- **Lines:**
  - Ports sit on the FK row (child side) and the PK row (parent side).
  - Lines are drawn at right angles.
  - The ends carry crow's-foot SVG markers: `||`, `|o`, `}|` and `}o`.
  - Solid means identifying; dashed means non-identifying.
- **Provenance styling:**
  - Confirmed or declared: full-strength ink.
  - Inferred and unreviewed: muted colour with a small "?" chip at the
    middle of the line.
  - Low confidence: hidden unless a "show low-confidence" switch is on.
- A **legend** covering the crow's-foot ends, solid vs dashed lines, key
  badges and provenance colours.

**Interaction:**

- Pan and zoom (vendored `svg-pan-zoom`, BSD).
- Search for a table.
- Click a table to **focus** it, with a hops slider (1–3). The rest of the
  diagram fades or hides.
- Hover highlights a table's lines.
- A **detail level** switch: all columns / keys only / names only.
- A **subject area** filter.
- An **orphans panel** listing tables with no relationships.
- Clicking a line opens its details (evidence) with Confirm and Suppress
  buttons, reusing `mod_relationships` actions and `confirmed_rels_rv`.
- **Layout options:** direction (left→right or top→down) and density.
  ELK's layered algorithm places parents before children.
- **Default for large schemas:** with more than 40 visible tables, open in
  "keys only", grouped by subject area, and prompt the user to focus a
  table.

**Keep** the current visNetwork force view as a "Network overview" tab. It
works well for spotting clusters, so it stays alongside the new view. Its
fixes are small:

- Node ids become table names.
- The duplicated circular-layout code is removed.
- Confirmed edges are drawn solid.
- The legend's "cardinality" entry is renamed "identical values", so it
  isn't mistaken for ERD cardinality.

## Phase 3: Exports as documentation

- **Mermaid** (`generate_mermaid_erd`):
  - real cardinality markers from Phase 1;
  - `--` for identifying lines and `..` for non-identifying;
  - `PK`/`FK`/`UK` markers;
  - quoted or aliased names;
  - comments carrying nullability and provenance;
  - `direction LR`, subject-area `classDef`s;
  - a stable sort order, so git diffs stay meaningful.
- **New DBML export:**
  - `pk`, `unique`, `not null` and `note` settings;
  - `?` for nullable FKs;
  - composite refs;
  - `TableGroup` and `headerColor` for subject areas;
  - inferred refs coloured.

  DBML keeps more than Mermaid can express.
- **SVG and PNG** export of the current Diagram view (focused or full).
- **dbt:**
  - keep every FK on a column (today one overwrites another);
  - optionally emit dbt 1.9 `constraints` (`foreign_key`, `to`,
    `to_columns`);
  - add column `description`s from the data dictionary.
- **Data dictionary** export (CSV and Markdown): table, column, type,
  nullable, keys, unique count, example values, and editable `description`
  and `business_name` fields, saved in the session.

## Phase 4: Maintenance

- **Session diff:** compare the current tables and relationships with a
  saved session and report added, removed and changed tables, columns and
  relationships. Also offer "Export changes".
- **Review metadata:** record who reviewed each relationship and when,
  alongside confirmed and suppressed, in the session.
- **Lints panel:**
  - tables without a PK;
  - orphan tables;
  - FKs whose values are missing from the parent (share of orphaned rows);
  - nullable PK-like columns;
  - duplicate relationships into the same parent.
- (Maybe later) User-defined naming patterns (see `TODO.md`) and a static
  HTML documentation site.

## Suggested order and size

| Step | Scope | Size |
|---|---|---|
| 1 | Phase 1 model + tests | M |
| 2 | Mermaid/DBML exports on the model (quick visible win, easy to test) | S–M |
| 3 | Diagram view: cards, ports, crow's-foot, legend, pan/zoom | L |
| 4 | Focus, detail levels, subject areas, orphans, line actions | M |
| 5 | Network-overview fixes; SVG/PNG export; data dictionary | M |
| 6 | Session diff, lints, review metadata | M |

Each step is its own PR, with tests. For the UI steps that means a
headless-Chromium check on the sample data and a synthetic 50-table
Access-style schema.

## Decisions (September 2026)

- **Renderer:** elkjs + custom SVG in the app. Users can also export
  Mermaid, DBML and ELK graph JSON, and render them in other tools.
- **Placement:** the new diagram replaces the ERD tab. The current
  visNetwork view becomes "Network overview".
- **Unconfirmed inferred links:** muted, with a "?" mark. Low confidence is
  hidden behind a switch.
- **Order:** Phase 1 + exports first (step 1), then the Diagram view.
- **Step 1 notes:**
  - `child_min` is always zero, because it comes from a data snapshot.
  - The model picks one primary key per table from the candidate keys
    (`id`, then `<entity>_id`, then key-named). A table with several FKs
    and no key-named candidate gets its composite key or none.

## Open questions (resolved above, kept for context)

- Is the renderer choice acceptable? It means vendoring elkjs (~1.5 MB)
  and writing custom SVG, rather than only improving visNetwork.
- Should the new Diagram view replace the ERD tab as the default, with the
  current view as "Network overview"?
- How to show an inferred but unconfirmed relationship: as proposed
  (muted + "?"), or hidden until reviewed?
- Should subject areas be editable in the app (drag a table into a group),
  or only derived automatically at first?

## Sources

- Reference diagrams: `docs/erd-examples/`. The lset.uk, lucid.co and
  impacttechnology pages couldn't be fetched from the sandbox.
- Crow's foot: https://www.drawio.com/docs/tutorials/crows-foot-notation/ ,
  https://www.relationaldbdesign.com/database-design/module7/crows-foot-notation.php
- Identifying vs non-identifying:
  https://bookshelf.erwin.com/bookshelf/public_html/12.5/Content/References/Data%20Modeling%20Overview/Identifying_Relationships.html
- Large schemas: https://github.com/k1LoW/tbls ,
  https://dataedo.com/blog/do-you-really-need-a-huge-er-diagram-for-the-entire-database ,
  https://community.dbdiagram.io/t/new-feature-diagram-detail-levels/2265
- Inferred relationships: https://www.schemacrawler.com/weak-associations.html ,
  https://www.jetbrains.com/help/datagrip/virtual-foreign-keys.html ,
  https://schemaspy.readthedocs.io/en/master/configuration/commandline.html
- Data dictionaries: https://www.ovaledge.com/blog/data-dictionary-best-practices
- Mermaid erDiagram:
  https://github.com/mermaid-js/mermaid/blob/develop/packages/mermaid/src/docs/syntax/entityRelationshipDiagram.md
- DBML: https://github.com/holistics/dbml
- dbt tests and constraints:
  https://docs.getdbt.com/reference/resource-properties/data-tests ,
  https://docs.getdbt.com/reference/resource-properties/constraints
