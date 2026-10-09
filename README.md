# Table Relationship Explorer

An interactive tool for mapping primary keys, foreign keys, and inter-table relationships across tabular data. Upload files or connect to a database, get an interactive ERD, column-level metadata, and exportable reports.

The primary implementation is **R/Shiny**. A **Python/Streamlit** version also exists but has fewer features and is not actively maintained at this time.

---

## R/Shiny Version (primary)

### Features

| Category | Detail |
|---|---|
| **File support** | CSV, TSV, Excel (xlsx/xlsm/xls), ODS, Parquet, JSON, NDJSON, SPSS, SAS, Stata, RDS, RData, Access (.mdb/.accdb) |
| **Database connectors** | PostgreSQL, MySQL, SQL Server, SQLite, Snowflake, BigQuery, Redshift, Oracle |
| **Schema import** | JSON/YAML schema files: tables and columns, foreign keys (inline `foreign_key` or a `relationships` list) and primary keys (`primary_key: true` on a column, or a table-level `primary_key` list); and data-dict YAML files. Declared primary keys (also read from database connections) take precedence over detection and are saved with the session |
| **7-signal FK detection** | Naming conventions, fuzzy name similarity, value overlap, cardinality, format fingerprint, distribution similarity, null-pattern correlation |
| **Confidence scoring** | Noisy-OR composite scoring with low/medium/high confidence tiers; filter by minimum confidence |
| **Signal toggles** | Enable/disable individual signals; changes take effect on "Run Detection" button click |
| **Scan triage** | Estimates scan complexity for large schemas; lets you choose full scan, naming-only, or skip |
| **ERD** | Standard physical ERD: table cards with PK/FK/UK badges, types and nullable marks; lines run from the FK row to the PK row with crow's-foot ends (elkjs layout, orthogonal routing). Focus a table with a hops slider, detail levels (all columns / keys only / names only), subject-area filter, left→right or top→down layout, pan/zoom, click a line to confirm or suppress it, SVG/PNG download |
| **Network overview** | The force-directed visNetwork graph (drag, zoom, hover tooltips; force/hierarchical/circular layouts), good for spotting clusters |
| **Table Details** | Per-table column summary with type, non-null count, unique values, PK/FK flags, table size |
| **Data Dictionary tab** | One row per column: type, format (email, phone, ISO date, code, free text…), missing %, unique count, text lengths or value range, PK/FK/UK, what it references (and whether that link is declared, confirmed or detected), privacy and example values. Add a label, description, units, allowed values (`A = Active; I = Inactive`) and details per column, and a description per table. Edits are saved with the session. Descriptions also go into the dbt, DBML and Mermaid exports; labels, units, allowed values and details go into the CSV, Markdown and data-dict YAML. Download as CSV, Markdown or data-dict YAML (these follow "Hide empty tables") |
| **Privacy** | Columns whose name (`email`, `dob`, `mrn`, `zip5`…) or values (emails, phone numbers, SSNs) suggest personal data are flagged and treated as private until you review them: a banner and a review dialog (which never shows values) let you confirm or reject each flag. You can also mark columns private yourself (select rows → Private), give name patterns that are always private (`*_name, dob*, patients.notes`), hide examples without calling a column private, or turn examples off (hiding examples leaves the value range of a non-private number or date column visible; mark it private to hide that too). Private columns keep their type, format, counts and text lengths but show no example values or value range, and are exported as `display: restricted`. A "not private", "not personal" or "show examples" choice holds only for the data it was made for: if a table is replaced (overwrite, reload, new upload) that column goes back to private until you decide again; removing tables drops those choices. **A saved session holds all the loaded data, private columns included** |
| **data-dict YAML** | Export and import the [data-dict](https://data-dict.tidyverse.org/) format (spec 0.1.0, written in plain R; the data-dict tool isn't needed). Exports carry types, labels, descriptions, units, allowed values, constraints, examples, and declared/manual/confirmed relationships as joins; unconfirmed detected links, and links to a column that isn't a single-column key, go under `todo`. Import Schema reads data-dict files back: tables (with their column types), primary keys, joins (as declared links) and dictionary entries, without overwriting your own edits or privacy decisions |
| **Relationships tab** | Grouped by detection method with confidence scores, signal chips, suppress/restore controls |
| **Name cleaning** | Automatic table and column name cleaning via janitor conventions, with full rename log |
| **Manual overrides** | Add relationships auto-detection misses |
| **Exports** | Relationships CSV (with source and review status), dbt schema.yml (with descriptions; optional dbt 1.9+ constraints for PKs and declared/confirmed FKs, which turns on an enforced contract and adds a generic `data_type` per column to adjust for your warehouse), Mermaid ERD, DBML (dbdiagram.io / dbdocs), ELK graph JSON (elkjs), data dictionary (CSV / Markdown / data-dict YAML), session save/restore (JSON, including dictionary edits) |
| **Duplicate handling** | Detects re-uploads by file size/dimensions; offers overwrite, keep both, or skip |

### Architecture (R package)

The app is a plain R package with no app framework: `run_app()` builds the
Shiny app, and static files under `inst/app/www/` are served through
`addResourcePath()`. It used golem until 2026-10-02; why it was dropped, and
what would make it worth bringing back, is in
`docs/research/shiny-framework/decision.md`.

```
R/
  run_app.R              Entry point - tableexplorer::run_app()
  app_ui.R               Top-level UI (assembles modules)
  app_server.R           Top-level server (wires module reactive values)
  mod_upload.R           Upload panel + manual override
  mod_db_connect.R       Database connection panel
  mod_detection.R        Detection controls + scan triage
  mod_erd.R              ERD tab (drawn in the browser by www/erd.js)
  mod_network.R          Network overview tab (visNetwork)
  mod_table_details.R    Per-table column summary
  mod_relationships.R    Relationships tab
  mod_name_changes.R     Name changes / rename log tab
  mod_dictionary.R       Data Dictionary tab (edits, privacy review)
  mod_export.R           Export panel (CSV, dbt YAML, Mermaid, DBML, ELK, dictionary, session)
  utils_inference.R      7-signal PK/FK detection engine
  utils_file_readers.R   Multi-format file parser (18 formats)
  utils_db_connectors.R  Database connection, introspection, loading
  utils_erd_model.R      Shared ERD model: types, key badges, cardinality, roles
  utils_export.R         dbt YAML, Mermaid ERD, DBML, ELK JSON, data dictionary, data-dict YAML, session JSON
  utils_privacy.R        Personal-data flags, review state and name patterns
  utils_vis.R            ERD network builder (build_network)
  utils_helpers.R        Shared helpers (%||%)
inst/
  app/www/               Static assets (styles.css, app.js)
  extdata/               Sample data + schema.json
dev/
  01_start.R             One-time project setup
  02_dev.R               Development helpers
  03_deploy.R            Deployment helpers
tests/testthat/          Unit tests (~1,000 expectations across 7 suites)
docs/internals.md        Diagrams of privacy, data-dict, primary keys, data flow
docs/diagrams/           The diagram SVGs and generate.py that draws them
```

Diagrams of the privacy rules, the data-dict round trip, primary-key precedence and the data flow between modules: [docs/internals.md](docs/internals.md).

**Reactive data flow between modules:**

```
app_server.R
├─ all_tables_rv   ← mod_upload, mod_db_connect (mutate)
├─ schema_rels_rv  ← mod_upload, mod_db_connect (mutate)
├─ manual_rels_rv  ← mod_upload (returns)
├─ detection opts  ← mod_detection (returns)
├─ pk_map_rv, composite_pk_map_rv, auto_rels_rv  (computed)
├─ all_rels_rv     → mod_erd, mod_table_details, mod_relationships, mod_export
└─ false_positives_rv ← mod_relationships (mutated via observeEvents)
```

### Installation

```r
# Install from GitHub
remotes::install_github("amelia-m/table-explorer")
```

**Optional packages** (installed on demand for specific formats/databases):

```r
# File formats
install.packages(c("readxl", "arrow", "haven", "readODS", "jsonlite", "yaml"))

# Databases
install.packages(c("DBI", "RSQLite", "RPostgres", "RMariaDB", "odbc", "bigrquery"))

# Fuzzy name matching
install.packages("stringdist")

# Access databases (Java-based; rJava, which RJDBC installs, also reads the
# relationships declared in the file)
install.packages("RJDBC")
# Without Java, relationships can still be read if mdbtools is installed
# (macOS: brew install mdbtools; Debian/Ubuntu: apt install mdbtools)
```

### Run locally

```r
# After install:
library(tableexplorer)
run_app()

# Or during development (no install needed):
pkgload::load_all()
run_app()
```

### The 7 inference signals

| Signal | What it measures | Weight |
|---|---|---|
| **Naming** | FK column named for the target table's entity (see conventions below); 0.90 when role/source words precede it (`referring_provider_id`) | 0.90-1.00 |
| **Name similarity** | Jaro-Winkler fuzzy match between column/table names | 0.60 |
| **Value overlap** | Fraction of values in column A that exist in column B | 0.55-0.90 |
| **Cardinality** | Whether column A looks like an FK (many rows, few unique values) | 0.95 |
| **Format fingerprint** | Whether both columns share value format (UUID, ISO date, email, etc.) | 0.40 |
| **Distribution similarity** | KS-test on numeric value distributions | 0.30-0.50 |
| **Null-pattern correlation** | Pearson correlation of null positions across tables | 0.20 |

**Naming conventions recognised** (no setup needed):

- FK columns: `customer_id` (Rails/Django/Access), `CustomerID` (SQL Server; cleaned to `customer_id`), `id_customer`, `fk_customer`, `customer_key` / `customer_sk` (warehouses), `state_code` / `state_cd`, `order_no` / `_num` / `_nbr`, `customer_uuid` / `_guid`
- Role or source words before the entity: `referring_provider_id`, `trax_enrollment_status_id` (a single-word match like `provider` requires the target to be a lookup table)
- Table names: `tbl_` `tlk_` `tlu_` `lkp_` `lu_` `ref_` `dim_` `fact_` `stg_` `mst_` prefixes, `dbo.` / `public.` schemas, `_lookup` `_lkp` `_ref` `_dim` `_codes` `_types` suffixes, regular and common irregular plurals
- Lookup tables (named like one, or small with a unique `id`/code column) are preferred targets, their `id`/`code` column is chosen as the matched key, and they can be matched even when empty
- Key-named columns are always name-checked, even when they hold only one or two distinct values

Scores are combined via noisy-OR aggregation: `score = 1 - prod(1 - weights)`. The composite score maps to confidence tiers: high (>= 0.85), medium (>= 0.55), low (< 0.55).

**Choosing between candidate parents.** A column can fit several tables. In
Access databases, for example, every `tlk_*` lookup numbers its `id` 1..N, so
`service_id` fits `tlk_services`, `tlk_sites` and every other lookup. Values
alone can't choose between them, so names come first, as in SchemaSpy and
SchemaCrawler:

- If the column's name points to one of the tables, that link is kept.
  Value-only matches to the other tables drop to **low** ("name points to
  tlk_services").
- If the name points nowhere and the values fit two or more tables, all of them
  drop to **low** ("ambiguous: values fit 8 tables").
- A link whose values mostly aren't in the parent can't rest on format or
  loose name likeness alone.

Low links are hidden by default. Tick "Show low confidence" on the Relationships
tab, or "Show low-confidence links" in the ERD, to review them.

### Declared vs detected relationships

- **Declared** relationships come from a schema file, a database connection, or
  the relationships stored inside an Access file (read with Jackcess when rJava
  is installed, else with mdbtools' `mdb-export`).
- **Detected** ones are inferred from the data.

Declared links and detected ones are shown differently everywhere:

- **Relationships tab:** a sortable **Source** column (declared / manual /
  ✓ confirmed / ? to review) and a Source filter.
- **ERD:** declared lines have no chip; confirmed lines show ✓, manual
  lines show M, and unreviewed detected lines are grey with a ?.
- **Network overview:** declared edges are drawn thick.

In the sidebar, **Relationships to show** picks *Declared + detected* (the
default, useful when documentation is incomplete), *Declared only* or *Detected
only*. It applies to all views and exports.

**Hide detected links on columns that already have a declared one** keeps
documented columns clean while undocumented ones are still inferred. A detected
link that duplicates a declared one appears once, as declared ("also detected").

### ERD tab

The diagram is laid out in the browser by [elkjs](https://github.com/kieler/elkjs)
(EPL-2.0, run in a Web Worker so the page stays responsive) and drawn as SVG
by `inst/app/www/erd.js`, with pan/zoom from
[svg-pan-zoom](https://github.com/bumbu/svg-pan-zoom) (BSD-2). Both are
vendored in `inst/app/www/vendor/`.

- **Reading it**: solid lines are identifying (the FK is part of the
  child's PK), dashed are not. Inferred links that nobody has confirmed are
  grey with a `?` chip; confirmed, declared and manual ones are drawn in
  full ink. Low-confidence links are hidden unless "Show low-confidence
  links" is on. The legend under the diagram explains the ends and badges.
- **Lookup links**: "Labels" shows a link to a reference table as a tag on
  the FK row (`→ tlk_providers`) instead of a line, which removes most of the
  clutter in hub-and-lookup schemas.
  - Reference tables are found by shape and use, not only by `tlk_`-style
    names: a table other tables point at, with no FKs of its own, that is
    named like a lookup, is small (≤ 500 rows, ≤ 4 columns), or is referenced
    by 3+ tables and has ≤ 6 columns.
  - Clicking a tag opens the relationship, as a line would.
  - Tables left without lines are listed down the right-hand side, split
    into lookups and unlinked tables.
- **Large schemas**: over 40 tables it opens in "Keys only" with lookup
  labels, and suggests picking a focus table. Views with more than 600 relationships ask you to
  narrow them first (focus, subject area or minimum confidence), with a
  "Draw anyway" button.
- **Downloads**: the SVG / PNG buttons save the current view with its
  colours, at full size.

### ERD exports

Mermaid, DBML and ELK exports share one model (`R/utils_erd_model.R`) and
use crow's-foot notation:

- **Parent end**: `||` exactly one (FK never NULL) or `|o` zero-or-one
  (nullable FK). **Child end**: `o{` zero-or-many or `o|` zero-or-one
  (FK unique in the child, i.e. 1:1). The child minimum is always zero:
  a data snapshot can't prove every parent has a child.
- **Line**: always solid (`--`) in Mermaid. Mermaid draws each crow's-foot
  marker's centre line with the relationship line itself, so dashed (`..`)
  lines make the bars and feet look broken and detached from the entity
  (checked in Mermaid 10.9 and 12). Identifying relationships stay visible:
  their FK column is also marked `PK`. The ELK graph keeps an `identifying`
  flag, so renderers that draw complete markers can dash non-identifying
  lines.
- **Mermaid connects tables, not rows.** Its ER syntax has no column
  anchors, and the renderer spaces line ends evenly down a box side, so a
  line's height on a box doesn't mean anything. Labels therefore name both
  columns (`quantity → item_id`). Splitting tables into one box per
  column was tested and rejected. As ER entities the boxes scatter (0/7
  tables stayed together). As a flowchart with a node per column, the rows
  sit 60-435 px apart and differ in width, and no spacing setting closes
  the gaps. For row-accurate diagrams use the ELK graph export or the
  ERD tab's SVG/PNG download.
- **Keys**: `PK`, `FK`, `UK` markers; one primary key per table (a generic
  `id`, then the table's own `<entity>_id`, then other key-named columns),
  composite keys when detected.
- **Provenance**: inferred links are labelled with their confidence
  (`customer_id → customer_id (inferred 87%)`); declared, manual and
  confirmed ones are not. DBML colours inferred refs grey.
- Output is sorted, so exports diff cleanly in git.
- **ELK graph**: each column gets a port pinned to its row at the card
  border (`FIXED_POS`): `table.col:out` on the east side for FK sources,
  `table.col:in` on the west side for targets. Edge-node spacing keeps the
  last segment at each end longer than a marker. Check any export with
  `node dev/check_erd_geometry.js erd.elk.json --svg preview.svg` (needs
  `elkjs`). It verifies every line end sits on its row and the border,
  with a straight run into the marker.

### Schema file format

JSON or YAML with a `tables` array. Each table lists columns with optional `primary_key` and `foreign_key` annotations:

```json
{
  "tables": [
    {
      "name": "orders",
      "columns": [
        {"name": "order_id", "type": "integer", "primary_key": true},
        {"name": "customer_id", "type": "integer",
         "foreign_key": {"table": "customers", "column": "customer_id"}}
      ]
    }
  ]
}
```

A sample schema (`schema.json`) is included in the repository.

### Deploy to Posit Connect

See `dev/03_deploy.R` for deployment helpers.

**From VS Code / Positron:** Install the Posit Publisher extension, open the project folder, and deploy as a Shiny Application.

**From GitHub:** Push to a public repo, then in Posit Connect go to New Content > Import from Git.

> Free plan limits: 4 GB RAM, 1 CPU, 20 active hours/month, 5 apps max.

### Running tests

```r
# Recommended: uses devtools and loads the package properly
devtools::test()

# Or directly with testthat:
testthat::test_package("tableexplorer")
```

---

## Python/Streamlit Version

> **Note:** The Python version is in an earlier development phase and has fewer features than the R/Shiny version. It will be updated over time but is not the current development focus.

### Current Python features

- Multi-format file upload (CSV, TSV, Excel, ODS, Parquet, JSON, NDJSON)
- 7-signal FK inference engine with confidence scoring
- JSON/YAML schema input
- Interactive ERD via PyVis
- Dark/light mode toggle
- Manual relationship overrides
- Relationship caching (MD5-digested)

### Not yet in Python

- Database connectors
- Scan triage for large schemas
- Run Detection button (settings changes trigger immediately)
- Table name cleaning
- dbt YAML / Mermaid ERD / session save-restore exports
- Table size in exports
- Relationship suppress/restore UI

### Python setup

```bash
pip install -r requirements.txt
streamlit run app.py
```

Opens at `http://localhost:8501`.

### Python deployment

Deploys to Streamlit Community Cloud, Docker, Railway, Render, Fly.io, or any Python host:

```bash
streamlit run app.py --server.port=$PORT --server.address=0.0.0.0
```

---

## Sample data

The `sample_data/` directory contains a 4-table e-commerce dataset:

```
orders.csv          customers.csv        products.csv        order_items.csv
-----------         -------------        ------------        ---------------
order_id (PK)       customer_id (PK)     product_id (PK)     item_id (PK)
customer_id  -->    name                 name                 order_id     -->
product_id   -->    email                category             product_id   -->
amount              country              price                quantity
order_date                                                    unit_price
```

The app auto-detects `customer_id` in `orders` -> `customers`, `product_id` in `orders` -> `products`, etc.
