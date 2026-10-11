# Table Explorer internals

Four mechanisms that are easy to get wrong when changing the code: how a
column's privacy is decided, what survives a data-dict round trip, where
primary keys come from, and how inputs reach the tabs. The images are drawn
by [`diagrams/generate.py`](diagrams/generate.py); edit it and run
`python docs/diagrams/generate.py` when one of these mechanisms changes. On
macOS and Linux that is `python3`; on this Windows machine `python3` is the
Microsoft Store alias and answers "Python was not found", so use `python`.

Colours mean the same thing in every diagram: red is private (no examples or
range), green is shown or used, and orange marks where a choice lapses or
data stops.

## Privacy for one column

![Decision path for one column's privacy](diagrams/privacy-decision.svg)

Checked top to bottom; the first "yes" decides. A "not private" or "not
personal" choice carries a hash of the column's data, so replacing the data
(overwrite, reload, new upload) sends the column back down the orange path to
private. Private columns still show type, format, % missing, unique count and
text lengths.

Privacy is not the only gate on example values, so a public column can still
have none. The order the exports apply is: private, then `hide_examples` on
that column ("hidden by you"), then the dictionary-wide `examples` setting
("auto" or "off"), which a per-column "show examples" choice overrides. That
choice carries its own hash of the data (`examples_for`) exactly as "not
private" carries `public_for`, so it lapses the same way.

Code: `dict_privacy()`, `privacy_holds()` and `privacy_review_set()` in
`R/utils_privacy.R`, with `dict_examples_forced()` and `dict_settings()` there
for the examples gate and the gate itself in `build_data_dictionary()` in
`R/utils_export.R`; the Dictionary tab's `write_flag()` in
`R/mod_dictionary.R` stamps both hashes.

## data-dict round trip

![What a data-dict export and re-import carry across](diagrams/data-dict-round-trip.svg)

Export, then Import Schema into a fresh app. The first five rows come back;
the last three stop in the file. Imported text fields fill only empty ones,
and an import never overwrites your own Private / Not private choice.

The fourth row carries `details` and the allowed-values list as well as the
three fields it names, and two of them change shape on the way out. The spec
allows `units` on a quantity only, so a unit on any other type is written into
`details` as "Units: ..." and comes back as description text, not as a unit;
allowed values on a column that is not text go the same way, as "Allowed
values: ...". Both survive the trip, neither returns to the field it left.

Code: `generate_data_dict_yaml()` in `R/utils_export.R`;
`parse_data_dict_schema()` and `merge_dictionary()` in
`R/utils_file_readers.R`.

## Where primary keys come from

![Declared primary keys override detection unless the data contradicts them](diagrams/primary-keys.svg)

A declared key replaces detection's candidates and composite keys, whatever
its type. If the loaded data has duplicates or missing values in it,
detection decides instead, so a stale declaration can't mark a non-unique
column as the key.

Code: `merge_declared_pks()`, `apply_declared_pks()` and
`apply_declared_composite_pks()` in `R/utils_helpers.R`; the declared-key
check at the top of `erd_model()` in `R/utils_erd_model.R`.

## From inputs to tabs

![How inputs write shared state and how the tabs read it](diagrams/app-data-flow.svg)

Inputs write the shared reactive values, and so do three of the tabs: the ERD
Diagram tab and the Relationships tab write `confirmed_rels_rv` and
`false_positives_rv` through `review_confirm()` and `review_suppress()`, and
the Data Dictionary tab writes `dictionary_rv` on every edit. A change made in
one tab is therefore visible in the others at once, which is the point, but it
also means a tab is not a read-only view of state. Network overview is the
exception: it is passed no writable review state and only reads.

The tabs do not read the shared values directly. `visible_tables_rv` and
`visible_rels_rv` sit in between and apply two view-only filters: "hide empty
tables" from the sidebar, and the relationship-source filter. Both reach the
ERD Diagram, Network overview, Table Details, Relationships and Data
Dictionary tabs. Detection and the Export tab deliberately bypass them and
work from every loaded table, so an export can contain tables and links the
diagram is not showing.

Removing tables resets the privacy choices that let values show, for the
tables removed, or for all of them on Clear all. Restoring a session replaces
the tables and, with them, the dictionary and the declared keys, even when
the saved file's copies are empty, so an older session's privacy choices
never apply to restored data. The other pieces are different: manual links,
declared links, confirmed reviews and suppressed links are written only when
the file has some, so a restore adds to what is loaded rather than clearing
it.

Code: `R/app_server.R`, which creates the shared values, derives the visible
ones and passes them to each module; `review_confirm()` and
`review_suppress()` in `R/utils_helpers.R`; the restore handler in
`R/mod_export.R`.
