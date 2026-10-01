# TODO

- [x] Add a "Hide empty tables" toggle (0-row tables) to the sidebar that filters
      them out of the ERD, Table Details, and Relationships views.
- [ ] (Maybe later) User-defined naming patterns for FK detection: a settings
      box for lookup-table prefix (e.g. `tlk_`), lookup key column (e.g. `id`)
      and FK template (e.g. `{entity}_id`), saved with the session. Built-in
      conventions (Access, Rails/Django, SQL Server, warehouse `_key`/`_sk`,
      code lookups, role prefixes) are detected automatically already.

- [ ] ERD redesign: see `docs/erd-redesign-plan.md` (done: model, exports,
      ERD Diagram tab, data dictionary, dbt constraints; next: session diff,
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
