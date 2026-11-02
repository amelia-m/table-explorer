# Trap inventory for the Access fixture

Each row is a trap: what it exercises, where it sits in the fixture, what should happen, and what each reader did.

**These results are from one run, before T1 was fixed.** Rows that say "Lost to T1" or "Child lost to T1" describe that run: those tables load now, and `read_access_db()` returns 33 of 37 expected tables. Open bugs are in `TODO.md`. `run_readers.R` and the run logs named below are not committed, and neither are all the `trap_*` files: `build_all.ps1` builds them, and `tests/testthat/fixtures/README.md` lists the ones kept.

Measured 2026-10-30 and 31 with R 4.6.1, RJDBC 0.2.10, Java 21.0.12, UCanAccess 5.0.1, Jackcess 4.0.1, time zone America/Chicago.

Reader columns:

- **UCanAccess**: the app's `read_access_db()`. "hrn" marks a result from the bracket-quoted `SELECT` in `run_readers.R` (HARNESS). It is not app code. It exists because the app cannot reach most tables (T1), and uses the same driver and RJDBC fetch, so what it shows is what later code would meet, which is an inference.
- **Jackcess**: the app's `access_relationship_rows_jackcess()`.
- **mdbtools**: `mdb-export` was not installed for this run, so every row says "not run" and nothing is inferred. CI now runs it for relationships only (U7).
- **RODBC**: not installed, so not run. "ODBC" marks a stand-in, the ACE driver asked for type TABLE from `run_jet_readers.ps1`. It shows what the driver offers, not what RODBC does.

Format column: both = same in `access_fixture.mdb` and `access_fixture.accdb`. All reader results below were the same on both formats, by `run_readers_output.txt` sections B and C.

## Formats and file-level traps

| ID | Trap | Exercises | Fixture | Format | Expected | UCanAccess | Jackcess | mdbtools | RODBC | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| F1 | Jet 4 with compressed Unicode | reader | `access_fixture.mdb`, Text Traps.Comp Text, Long Text | mdb | Opens, text intact | Opens; 0 of 87 text cells differ (hrn) | Opens, 26 of 26 rows | not run | ODBC opens | verified |
| F2 | ACE 12 file | reader | `access_fixture.accdb` | accdb | As F1 | As F1 | As F1 | not run | ODBC opens | verified |
| F3 | Jet 3 with cp1252 text | reader, text | `trap_jet3.mdb`, Item.Note | Jet 3 | `café naïve` | Opens; text corrupt with no notice, U+FFFD for both accents. With `...charset.VERSION_3=Cp1252` set it reads correctly | 1 row, right | not run | not run | verified, app bug |
| F4 | Jet 3 with cp1251 text | reader, text | `trap_jet3_cyrillic.mdb`, Item.Note | Jet 3 | Cyrillic word | Six `?`, no notice | 1 row, right | not run | not run | verified, app bug |
| F5 | Non-Latin sort order on Jet 4 | reader | `trap_cyrillic_sort.mdb` | mdb | Opens | Item read, text right; `tlk Kind` lost to T1 | 1 row | not run | not run | verified |
| F6 | Database password | error path | `trap_password.mdb` | mdb | A message that says it is password protected | Refused, `Password authentication failed`, then "is Java installed?" and "Install the RJDBC package" | Opens with no password, 1 row | not run | not run | verified, app bug in message |
| F7 | Password on accdb, real encryption | error path | `trap_password.accdb` | accdb | As F6 | `Decoding not supported`, same misleading text | NULL, quiet | not run | not run | verified, app bug in message |
| F8 | Encoded, no password | error path | `trap_encoded.mdb` | mdb | A message that it is encoded | `Decoding not supported`, same misleading text | NULL, quiet | not run | not run | verified, app bug in message |
| F9 | Text file named `.mdb` | error path | `trap_not_access.mdb` | n/a | "not an Access file" | `Empty database file`, same misleading text | NULL, quiet | not run | not run | verified, app bug in message |
| F10 | Zero bytes | error path | `trap_empty.mdb` | n/a | As F9 | `Empty database file`, same | NULL, quiet | not run | not run | verified |
| F11 | Truncated file | error path | `trap_truncated.mdb` | mdb | "damaged" | `invalid page number 2`, same | NULL, quiet | not run | not run | verified |
| F12 | accdb content named `.mdb` | dispatch | `trap_accdb_renamed.mdb` | both | Reads | Reads, content decides | 1 row | not run | not run | verified |
| F13 | mdb content named `.accdb` | dispatch | `trap_mdb_renamed.accdb` | both | Reads | Reads | 1 row | not run | not run | verified |
| F14 | Upper-case `.MDB` | dispatch | temporary copy | mdb | Reads | Reads, `tolower` at dispatch | 1 row | not run | not run | verified |
| F15 | Read-only attribute | reader | temporary copy | mdb | Reads, file unchanged | Reads, hash same | Reads, hash same | not run | not run | verified |
| F16 | Reading changes the file or leaves a lock | fixture safety | `access_fixture.*` | both | No change | Hash same, no new file | Hash same, no new file | not run | ODBC and read-only DAO: hash same; `.ldb`/`.laccdb` exists while open, gone after close | verified |
| F17 | Space in folder path | reader | temporary copy | mdb | Reads | Reads | Reads | not run | not run | verified |
| F18 | Semicolon in folder path | reader | temporary copy | mdb | Reads | `given file does not exist`, path cut at `;` | Reads | not run | not run | verified, minor app bug |
| F19 | Replicated database | reader | `trap_replica.mdb`, Replicated Table | mdb only | Rows read, replication columns noted | Table lost (T1); hrn: `BLOB to String` error, table lost | 0 rows, right | not run | not run | verified, app bug (T2) |
| F20 | Linked table, source missing, as after any upload | reader | `trap_linked.mdb`, Linked Item | both possible, built mdb | Warn that a link was skipped | Linked Item absent; Java warning on console only, nothing to `notify_fn` | 0 rows, right | not run | not run | verified, app bug |
| F21 | Linked table, source present | reader | unscrubbed build only | both possible | Reads | Connect fails, `object not found: PUBLIC.TLK KIND`. Rests on a file not kept here | 0 rows | not run | not run | verified once, not reproducible from this folder |
| F22 | accdb-only types: attachment, multi-value | reader | `trap_accdb_types.accdb`, Accdb Only | accdb only | Table read, or the column skipped with a note | Lost to T1; hrn: `OTHER to String` error, whole table lost | 0 rows | not run | not run | verified; columns are empty, no attachment was stored |

## Types

| ID | Trap | Exercises | Fixture | Format | Expected | UCanAccess | Jackcess | mdbtools | RODBC | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | Name needing quotes: spaces, `-`, `/`, apostrophe, non-ASCII after a space | `read_access_db`, every later step | 22 tables, e.g. `tlk Status` | both | Every table read | 25 of 37 expected tables missing, 22 of those for this reason: `SELECT * FROM Audit Log` sent unquoted | Unaffected | not run | ODBC reads all 39 | verified, app bug |
| T2 | OLE Object | table load | Customer Photo.Photo | both | Table read, column skipped or marked | Lost to T1; hrn: `BLOB to String`, whole table lost. In the first build this column was in tblCustomer, and tblCustomer failed through the app itself | Unaffected | not run | ODBC reads | verified, app bug |
| T3 | Yes/No, never Null | profile, PK skip of logicals | tblCustomer.Is Member, tlk Status.Is Active? | both | Logical | Character `TRUE`/`FALSE` | n/a | not run | not run | verified, app bug |
| T4 | Currency | profile, dictionary range | tblCustomer.Balance, Number Traps.CurrV | both | Numeric, or text with no loss | Character, exact to 4 places; dictionary says `string`, `text`, no range | n/a | not run | not run | verified, app bug |
| T5 | Decimal(28,4) past double precision | as T4 | Number Traps.DecV | both | Digits kept | Character, digits kept | n/a | not run | not run | verified |
| T6 | Single | profile, format guess | tblCustomer.Score, Number Traps.SingleV | both | Numeric | Character `1.5000000`, zero as `0E-7`; dictionary calls `score` a phone number | n/a | not run | not run | verified, app bug |
| T7 | Double extremes | profile | tblCustomer.Ratio, Number Traps.DoubleV | both | Numeric | Numeric | n/a | not run | not run | verified |
| T8 | Long at R's NA_integer_, -2147483648 | NA handling | Number Traps.LongV | both | Value kept | Numeric double, kept. Dictionary min shows rounded `-2147480000` | n/a | not run | not run | verified, display rounding |
| T9 | Byte, Integer at limits | types | Number Traps | both | Numeric | Numeric | n/a | not run | not run | verified |
| T10 | Replication ID GUID | key values | tblCustomer.Row Guid, Device.DeviceGuid | both | Stable text | `{...}` upper case, consistent on both sides of R16 | Right | not run | not run | verified |
| T11 | Hyperlink stored as `display#address#anchor#` | text | tblCustomer.Homepage | both | Raw text, or address parsed | Raw text with `#` | n/a | not run | not run | verified |
| T12 | Memo over 255 and over 64 KB | text | tblCustomer.Notes, Text Traps.Long Text | both | Full length | 70,000 characters intact (hrn) | n/a | not run | not run | verified |
| T13 | Time-only value, epoch 1899-12-30 | dates | tblCustomer.Call Time, Date Traps id 2 | both | Time kept | POSIXct dated 1899-12-30, correct but shown as a date | n/a | not run | not run | verified |
| T14 | Dates before 1900, negative stored doubles | dates | tblCustomer.Birth Date, Date Traps ids 3 to 5 | both | Exact | Exact (hrn) | n/a | not run | not run | verified |
| T15 | Before the Gregorian cutover | dates | Date Traps ids 6, 7 | both | 1582-10-10, 0100-01-01 | 1582-09-30 and 0100-01-03, no notice. Java gives these strings, so the shift is before R (hrn). File holds the right doubles: `probe_dates_output.txt` | n/a | not run | ODBC gives 1582-08-29, 0098-11-26, a third answer | verified, driver limit |
| T16 | Wall-clock time in a US DST gap | dates | Date Traps id 9 | both | 2021-03-14 02:30 | NA in R, though Java returns the right string; counts as missing, 15.4% against a true 7.7%. Depends on time zone | n/a | not run | ODBC right | verified, app or RJDBC bug |
| T17 | Number held as text, Long against Text | FK detection | Orders.LegacyCustNo to tblCustomer.CustomerID | both | Found at some confidence, or left to the user | Not detected at medium, either path | n/a | not run | not run | verified; no declared link built, Jet's handling of one untried |
| T18 | Text key with leading zeros | types | tblCustomer.ZIP | both | Stays text | Text, dictionary says US ZIP code | n/a | not run | not run | verified |
| T19 | AutoNumber gap and explicit high value | PK | tblCustomer.CustomerID 7 missing, 1000 present | both | Values as stored | `1 2 3 4 5 6 8 9 10 11 12 1000` | n/a | not run | not run | verified |

## Text values

| ID | Trap | Exercises | Fixture | Format | Expected | UCanAccess | Jackcess | mdbtools | RODBC | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| X1 | Newlines, tab, comma, quotes, trailing and leading spaces, spaces only | text fidelity | Text Traps rows 1 to 10 | both | Byte-exact | 0 mismatches, each row checks itself by UTF-16 hex (hrn) | n/a | not run | not run | verified |
| X2 | Empty string against Null | blank handling | Text Traps rows 11, 27 | both | Distinct | Distinct: empty string stays empty, Null is NA (hrn). Later blank handling not examined | n/a | not run | not run | verified at the reader |
| X3 | Text `NA`, `NULL`, `TRUE`, `000123`, `1E5`, `=1+1` | type guess, exports | Text Traps rows 12 to 17 | both | Text unchanged | Unchanged (hrn). Export of `=1+1` not run | n/a | not run, and `read.csv` in the mdbtools path deserves a check on a table or column named `NA` | not run | verified at the reader |
| X4 | Non-ASCII: Latin-1, Cyrillic, CJK, Hebrew, smart quotes, NBSP, U+FFFD | text fidelity | Text Traps rows 19 to 22, 24 to 26 | both | Byte-exact | 0 mismatches (hrn) | n/a | not run | not run | verified |
| X5 | Emoji, a surrogate pair | text fidelity | Text Traps row 23 | both | Byte-exact | 0 mismatches (hrn) | n/a | not run | not run | verified |

## Names

| ID | Trap | Exercises | Fixture | Format | Expected | UCanAccess | Jackcess | mdbtools | RODBC | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| N1 | `#`, `%`, `?`, `/` in column names | name cleaning | Sort#, Is Active?, Rate %, Region/Area, Item%, `#`, `%` | both | Stable clean names | Cleaned to `sort_number`, `is_active`, `rate_percent`, `region_area`, `item_percent`, `number`, `percent`; RJDBC keeps raw names | Right | not run | not run | verified |
| N2 | Reserved words | reader | table `Select`, columns From, Where, Order, Date, Group | both | Read | Read, RJDBC leaves them unquoted and UCanAccess accepts it | Right | not run | not run | verified |
| N3 | Columns colliding after cleaning | declared links | Collide Cols: Item Code, item_code, ITEM-CODE, ItemCode | both | R18 on `item_code_3`, where the region codes are | Table lost to T1; `access_relationship_rels` gives `item_code`, a column of `AAA`, `AAB` (hrn confirms the data) | Raw names right | not run | not run | verified, app bug |
| N4 | Tables colliding after cleaning | upload, declared links | Order Detail, order_detail, Order-Detail | both | All three kept, or a warning | App reads only `order_detail`; R19 belongs to `Order-Detail` and lands on it anyway. hrn: 3 tables to 1, 41 of 43 objects kept, the loop in `run_readers.R` mimics `mod_upload.R:250` | Raw names right | not run | not run | verified, app bug; the three-way loss not seen through the module, because T1 stops two tables first |
| N5 | Non-ASCII column and table names | cleaning | Übersicht Bücher, Büro Nr, 顧客, 日本語, Café Nº, Naïve Field | both | Same clean name on all paths | Cleaned to `ubersicht_bucher`, `buro_nr`, `gu_ke`, `ri_ben_yu`, `cafe_no`, `naive_field`; 顧客 read by the app, the table with a space not | Right | not run | not run | verified |
| N6 | Apostrophe in table and column | quoting | Customer's Notes.Author's Note | both | Read | Lost to T1, error names `CUSTOMER`; hrn reads | Right | not run | not run | verified |
| N7 | Table name of 64 characters | reader | Long_Table_Name_ plus 48 x | both | Read | Read | n/a | not run | not run | verified |
| N8 | Leading digit in a column | cleaning | Customer Profile.2nd Phone | both | Stable | `x2nd_phone` by key; table lost to T1 | n/a | not run | not run | verified at janitor only |

## Objects

| ID | Trap | Exercises | Fixture | Format | Expected | UCanAccess | Jackcess | mdbtools | RODBC | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| O1 | Negative case: user table named like MSys | system filter | MSystem Parts, 2 rows | both | Stays | Dropped by `^MSys`, no notice; R17 dropped too | Row present | not run | ODBC offers it | verified, app bug |
| O2 | Negative case: user table named like USys | system filter | USystem Notes, 1 row | both | Stays | Dropped by `^USys`, no notice | n/a | not run | ODBC offers it | verified, app bug |
| O3 | Negative case: tilde name | system filter | ~Draft Table, 1 row | both | Stays | Dropped by `^~`, no notice | n/a | not run | ODBC offers it | verified, app bug if Amelia agrees the expectation |
| O4 | Negative case: lower case | system filter | msys_lower, 1 row | both | Stays | Stays: the filter is case sensitive | n/a | not run | ODBC offers it | verified |
| O5 | True MSys prefix made by a user | system filter | MSysUserMade | both | Dropped | Dropped | n/a | not run | ODBC offers it as a plain TABLE, so the RODBC path may keep it | verified |
| O6 | USys convention table | system filter | USysRibbons | both | Dropped | Dropped | n/a | not run | ODBC offers it | verified |
| O7 | Hidden table | listing | Hidden Table | both | Stays | Listed; lost to T1; hrn reads | R21 present | not run | ODBC reads | verified |
| O8 | System-flagged table | listing | Flagged System | both | Dropped | Not listed by the driver | n/a | not run | ODBC types it SYSTEM TABLE | verified |
| O9 | Saved select queries | listing, FK detection | qryActiveCustomers, qryUnion, qryCrosstab, qryWildIIf | both | Not loaded as tables, or marked | Four loaded as tables; 16 of 32 detected links touch one | n/a | not run | ODBC offers tables only | verified, app bug |
| O10 | Parameter query | listing | qry Customer Param | both | Not a table | Fails on T1, one error notice; hrn: 0 rows | n/a | not run | not run | verified |
| O11 | Action query | listing | qryUpdateNothing | both | Ignored, never run | Not listed | n/a | not run | not run | verified |
| O12 | Empty table | profile, detection | Empty Carrier | both | 0 rows, columns kept | Lost to T1; hrn: 0 rows, 3 columns, later code runs | n/a | not run | ODBC reads | verified |
| O13 | One-row tables | profile | Customer's Notes, Select, 顧客 | both | Read | `is_lookup_table` TRUE for 顧客 | n/a | not run | not run | verified |
| O14 | No primary key, unique index only | PK detection | Legacy Code, Legacy Use, Audit Log | both | No PK claimed on Audit Log; `legacy_code` a candidate | hrn: as expected | n/a | not run | not run | verified |
| O15 | Declared primary keys | PK | key column `pk` | both | Read from the file | Never read for Access: all guessed. Composite Order Line found by guess (hrn) | Available through `getPrimaryKeyIndex` | not run | not run | verified, gap |
| O16 | Column and table descriptions | dictionary | Orders, Orders.OrderNo | both | Could seed the dictionary | Not read | n/a | not run | not run | gap, by reading the code |

## Relationships

Each relationship is in `access_fixture_key.csv`. `grbit_native` is what `MSysRelationships` holds, read directly with Jackcess and matched by DAO `Attributes`. `grbit_app` is what `access_relationship_rows_jackcess()` rebuilds, bits 1 and 2 only. 26 of 26 rows came back with names and `grbit_app` right, on both formats.

| ID | Trap | Exercises | Fixture | Format | Expected | UCanAccess | Jackcess | mdbtools | RODBC | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| R01 | Enforced | declared link | tblCustomer.StatusID to tlk Status | both | grbit 0 | Target lost to T1 | 0 | not run | not run | verified |
| R02 | Unenforced, orphans `ZZZ`, Nulls | declared, detection | tblCustomer.RegionCode to tlk_Region.Code | both | grbit 2 | Detected too | 2 | not run | not run | verified |
| R03 | Self-reference, Nulls | declared, detection | tblCustomer.ReferredBy | both | grbit 0 | Not detected at medium; declared link kept | 0 | not run | not run | verified |
| R04 | One-to-one | declared | Customer Profile.CustomerID | both | grbit 1, `one_to_one` TRUE | Child lost to T1 | 1 | not run | not run | verified |
| R05 | Cascade update and delete | declared | Orders.CustomerID | both | native 4352 | n/a | 0: cascade bits not rebuilt; mdbtools path would pass 4352, same links out (H section) | not run | not run | verified, gap |
| R06 | Lookup Wizard style field | declared, RowSource | Orders.ShipMethodID, properties written through DAO | both | grbit 2 | Parent lost to T1 | 2 | not run | not run | verified; imitation, Access's wizard not used |
| R07 | Cascade delete only | declared | Order Line.OrderNo | both | native 4096 | Child lost to T1 | 0 | not run | not run | verified |
| R08 | Composite, different column names | declared, ERD | Line Note (Ref Order, Ref Line) to Order Line | both | One relationship over two columns | Two separate links | 2 rows, order right | not run | not run | verified, gap |
| R09 | FK column order differs from parent | declared | Line Alloc: columns Alloc Line then Alloc Order | both | Pairs by icolumn | Pairs right | 2 rows, right | not run | not run | verified. Jet refuses field order that matches no unique index, so the difference is in the child's layout, not the relationship |
| R10, R11 | Two tables linked twice | ERD | Shipment.FromWarehouse, ToWarehouse to Warehouse | both | Two links | Two links | 2 rows | not run | not run | verified |
| R12 | Link into an empty table | declared, detection | Shipment.CarrierID, all Null, to Empty Carrier | both | Declared link kept | Parent lost to T1; hrn keeps it; not detected, as nothing supports it | 0 | not run | not run | verified |
| R13 | Enforced link Jet matches without case | detection | Store.RegionCode `ne1`, `nw2` to `NE1`, `NW2` | both | Declared link kept; detection may miss | Jet accepted it; detection missed it; declared link resolves | 0 | not run | not run | verified |
| R14 | Parent has a unique index, no PK | declared | Legacy Use to Legacy Code | both | Declared | Both lost to T1; hrn keeps | 0 | not run | not run | verified |
| R15 | Child has no PK, orphan 77777, Nulls | declared | Audit Log.CustomerID | both | grbit 2 | Child lost to T1 | 2 | not run | not run | verified |
| R16 | GUID key | declared, detection | Device Log.DeviceGuid to Device | both | grbit 0 | Child lost to T1; hrn detects it | 0 | not run | not run | verified |
| R17 | Child named like MSys | system filter | MSystem Parts.RegionCode | both | Kept | Dropped at `access_relationship_rels` | Row present | not run | not run | verified, app bug |
| R18 | Child column collides | see N3 | Collide Cols.ITEM-CODE | both | `item_code_3` | `item_code` | Raw right | not run | not run | verified, app bug |
| R19 | Child table collides | see N4 | Order-Detail.OrderNo | both | Own table | Attached to `order_detail` | Raw right | not run | not run | verified, app bug |
| R20 | Left join flag, high bit | bit handling | Store.HomeWarehouse, orphan 9 | both | native 16777218 | Link right | 2 | not run | not run | verified |
| R21 | Hidden child | declared | Hidden Table.StatusID | both | Present | Both ends lost to T1 | 2 | not run | not run | verified |
| R22 | Apostrophe in child name | declared | Customer's Notes | both | Present | Child lost to T1 | 2 | not run | not run | verified |
| R23 | Non-ASCII child table and column | declared | Übersicht Bücher.Büro Nr | both | Present, names survive Java to R | Names right | 2 | not run | not run | verified |
| R24 | Attr 0 on a unique child | declared | Customer Photo.CustomerID | both | grbit 0 | Child lost to T1 | 0 | not run | not run | verified |

## Not built, or unverified

| ID | Trap | Status | Why, and what would settle it |
|---|---|---|---|
| U1 | Forms, reports, macros, VBA modules | not built, needs Amelia | No DAO route, Access itself is needed. Steps: open `access_fixture.mdb` in Access, create one form on tblCustomer, one macro and one module, save, compact, close. Then rerun `run_readers.R` |
| U2 | User-level security, a workgroup `.mdw` | not built, needs Amelia | mdb only. Steps: in Access 2003 or earlier, or with a workgroup file, secure a copy of the small schema and remove Admin's read permission on `MSysRelationships`. Then see whether Jackcess still reads it |
| U3 | Access 2.0, Jet 2 | not built | No tool here. Would need a file made by an old Access |
| U4 | Attachment and multi-value fields holding data | not built | Columns exist in `trap_accdb_types.accdb`, empty. DAO needs child recordsets to fill them; not attempted |
| U5 | Large Number, calculated, Rich Text fields | not built | accdb only, not tried |
| U6 | Long declared against Text in a relationship | unverified | Not attempted. `Add-Rel` with mismatched types would show whether Jet refuses it |
| U7 | mdbtools path | relationships checked on CI, the rest unverified | CI compares `access_relationship_rows_mdbtools()` on `access_fixture.mdb` with the key, including `grbit`. Still to check: Jet 3, and a name such as `NA` through `read.csv` |
| U8 | RODBC path | unverified | Install RODBC and run `read_access_db()` with UCanAccess unavailable |
| U9 | Export of odd values (`=1+1`, newlines) to CSV, Markdown, DBML | unverified | Not run. `erd_model` and `build_data_dictionary` were run; the file exports were not |
