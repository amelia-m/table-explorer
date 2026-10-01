# Table Explorer internals

Four mechanisms that are easy to get wrong when changing the code: how a
column's privacy is decided, what survives a data-dict round trip, where
primary keys come from, and how inputs reach the tabs. The images are drawn
by [`diagrams/generate.py`](diagrams/generate.py); edit it and run
`python3 docs/diagrams/generate.py` when one of these mechanisms changes.

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

Code: `dict_privacy()`, `privacy_holds()` and `privacy_review_set()` in
`R/utils_privacy.R`; the Dictionary tab's `write_flag()` in
`R/mod_dictionary.R` stamps the hash.

## data-dict round trip

![What a data-dict export and re-import carry across](diagrams/data-dict-round-trip.svg)

Export, then Import Schema into a fresh app. The first five rows come back;
the last three stop in the file. Imported labels and descriptions fill only
empty fields, and an import never overwrites your own Private / Not private
choice.

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

Inputs write shared reactive values; the tabs only read. Removing tables
resets the privacy choices that let values show, and restoring a session
replaces every piece of state at once, including the dictionary and declared
keys.

Code: `R/app_server.R`, which creates the shared values and passes them to
each module.
