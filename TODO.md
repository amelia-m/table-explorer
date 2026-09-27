# TODO

- [x] Add a "Hide empty tables" toggle (0-row tables) to the sidebar that filters
      them out of the ERD, Table Details, and Relationships views.
- [ ] (Maybe later) User-defined naming patterns for FK detection: a settings
      box for lookup-table prefix (e.g. `tlk_`), lookup key column (e.g. `id`)
      and FK template (e.g. `{entity}_id`), saved with the session. Built-in
      conventions (Access, Rails/Django, SQL Server, warehouse `_key`/`_sk`,
      code lookups, role prefixes) are detected automatically already.

- [ ] ERD redesign: see `docs/erd-redesign-plan.md` (steps 1-2 done: model,
      exports, ERD Diagram tab; next: data dictionary, dbt constraints,
      session diff, lints).
- [ ] Detection noise on Access-style schemas: when every `tlk_*` lookup
      numbers its `id` 1..N, value-only signals (identical values) match a
      lookup FK such as `service_id` to *every* lookup, not just
      `tlk_services`. Consider: when a column has a naming match, don't also
      propose value-only matches to other targets (or rank them lower).

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
