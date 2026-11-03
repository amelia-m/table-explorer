# build_fixture.ps1 - build the trap fixture as .mdb (Jet 4) or .accdb (ACE 12).
#
#   pwsh -NoProfile -File build_fixture.ps1 -Target <path\access_fixture.mdb>
#
# The extension of -Target picks the format; the schema and rows are the same
# in both. Every value is invented. The file's bytes differ between runs (Jet
# stamps dates and GUIDs into its system tables), but tables, rows, indexes,
# relationships and queries do not: check_answer_key.R checks a build.
# Tool: DAO.DBEngine.120 and ADODB with the ACE OLEDB provider, 64-bit.

param([Parameter(Mandatory = $true)][string]$Target)

. (Join-Path $PSScriptRoot 'fixture_lib.ps1')

if (Test-Path -LiteralPath $Target) { throw "Target already exists: $Target" }
$ext = [IO.Path]::GetExtension($Target).ToLowerInvariant()
$opt = switch ($ext) {
  '.mdb' { $dbVersion40 }
  '.accdb' { $dbVersion120 }
  default { throw "Unsupported extension: $ext" }
}

# ---- Non-ASCII names, from code points --------------------------------
$cafeNo = 'Caf' + (U 0xE9) + ' N' + (U 0xBA)                 # Cafe No with accent and ordinal
$naive = 'Na' + (U 0xEF) + 've Field'
$cjkCol = U 0x65E5, 0x672C, 0x8A9E                           # three CJK characters
$cjkTbl = U 0x9867, 0x5BA2                                   # two CJK characters
$ubersicht = (U 0xDC) + 'bersicht B' + (U 0xFC) + 'cher'     # German with umlauts
$buero = 'B' + (U 0xFC) + 'ro Nr'
$apos = "Customer's Notes"
$longName = 'Long_Table_Name_' + ('x' * 48)                  # 64 characters, the Jet limit

# ---- Create the file --------------------------------------------------
$engine = New-Object -ComObject 'DAO.DBEngine.120'
$db = $engine.CreateDatabase($Target, $LangGeneral, $opt)
$db.Close()

# Decimal and compressed Unicode columns cannot be declared through DAO, so
# these two tables come first, through ADO DDL.
$ado = New-Object -ComObject 'ADODB.Connection'
$ado.Open("Provider=Microsoft.ACE.OLEDB.12.0;Data Source=$Target;")
[void]$ado.Execute(@'
CREATE TABLE [Number Traps] (
  [NumID] INTEGER CONSTRAINT pk_numtraps PRIMARY KEY,
  [Case Name] TEXT(60), [ByteV] BYTE, [IntV] SMALLINT, [LongV] INTEGER,
  [SingleV] REAL, [DoubleV] FLOAT, [CurrV] CURRENCY, [DecV] DECIMAL(28,4),
  [Expected] TEXT(120))
'@)
[void]$ado.Execute(@'
CREATE TABLE [Text Traps] (
  [TextID] INTEGER CONSTRAINT pk_texttraps PRIMARY KEY,
  [Case Name] TEXT(60),
  [Short Text] TEXT(255),
  [Comp Text] TEXT(255) WITH COMPRESSION,
  [Long Text] MEMO WITH COMPRESSION,
  [Expected Len] INTEGER,
  [Expected Hex] MEMO)
'@)
$ado.Close()

$db = $engine.OpenDatabase($Target)
foreach ($t in 'Text Traps') {
  foreach ($c in 'Short Text', 'Comp Text', 'Long Text') {
    $db.TableDefs.Item($t).Fields.Item($c).AllowZeroLength = $true
  }
}

# ---- Lookups ----------------------------------------------------------
New-DaoTable $db 'tlk Status' @(
  @{ n = 'StatusID'; t = $dbLong; auto = $true },
  @{ n = 'Status Label'; t = $dbText; s = 50; req = $true },
  @{ n = 'Sort#'; t = $dbByte },
  @{ n = 'Is Active?'; t = $dbBoolean }
) -Pk 'StatusID'
Add-Rows $db 'tlk Status' @('Status Label', 'Sort#', 'Is Active?') @(
  @('New', 1, $true), @('Open', 2, $true), @('Held', 3, $false),
  @('Closed', 4, $false), @('Unknown', 255, $false)
)

New-DaoTable $db 'tlk_Region' @(
  @{ n = 'Code'; t = $dbText; s = 3 },
  @{ n = 'Region/Area'; t = $dbText; s = 50 },
  @{ n = 'Rate %'; t = $dbSingle }
) -Pk 'Code'
Add-Rows $db 'tlk_Region' @('Code', 'Region/Area', 'Rate %') @(
  @('NE1', 'North East Test Area', 1.5), @('NW2', 'North West Test Area', 2.25),
  @('SE3', 'South East Test Area', 0.1), @('SW4', 'South West Test Area', 3)
)

New-DaoTable $db 'tlk Ship Method' @(
  @{ n = 'ID'; t = $dbLong; auto = $true },
  @{ n = 'Method'; t = $dbText; s = 30 }
) -Pk 'ID'
Add-Rows $db 'tlk Ship Method' @('Method') @(, @('Road'))
Add-Rows $db 'tlk Ship Method' @('Method') @(, @('Rail'))
Add-Rows $db 'tlk Ship Method' @('Method') @(, @('Air'))

# ---- Customer: nearly every Jet type in one table ---------------------
$noteLong = ('Synthetic note, more than 255 characters. ' * 12).TrimEnd()
$photoBig = [byte[]](0..4999 | ForEach-Object { $_ % 251 })
$photoSmall = [byte[]](0x15, 0x1C, 0x00, 0x00, 0xFF, 0xD8, 0xFF, 0xE0)
New-DaoTable $db 'tblCustomer' @(
  @{ n = 'CustomerID'; t = $dbLong; auto = $true },
  @{ n = 'Customer Name'; t = $dbText; s = 80; req = $true },
  @{ n = 'StatusID'; t = $dbLong },
  @{ n = 'RegionCode'; t = $dbText; s = 3 },
  @{ n = 'ReferredBy'; t = $dbLong },
  @{ n = 'Balance'; t = $dbCurrency },
  @{ n = 'Visits'; t = $dbInteger },
  @{ n = 'Score'; t = $dbSingle },
  @{ n = 'Ratio'; t = $dbDouble },
  @{ n = 'Is Member'; t = $dbBoolean },
  @{ n = 'Joined'; t = $dbDate },
  @{ n = 'Call Time'; t = $dbDate },
  @{ n = 'Birth Date'; t = $dbDate },
  @{ n = 'Homepage'; t = $dbMemo; hyper = $true },
  @{ n = 'Notes'; t = $dbMemo },
  @{ n = 'Row Guid'; t = $dbGUID },
  @{ n = 'ZIP'; t = $dbText; s = 5 }
) -Pk 'CustomerID'
$custCols = 'Customer Name', 'StatusID', 'RegionCode', 'ReferredBy', 'Balance', 'Visits', 'Score', 'Ratio', 'Is Member', 'Joined', 'Call Time', 'Birth Date', 'Homepage', 'Notes', 'Row Guid', 'ZIP'
$custRows = @(
  @('Test Person 01', 1, 'NE1', $null, [decimal]'1234.5678', 3, 1.5, 0.25, $true, (D '2019-01-02 00:00:00'), (D '1899-12-30 08:15:00'), (D '1880-03-04 00:00:00'), 'Example Site#https://example.invalid/one#anchor#', $noteLong, '{00000000-0000-4000-8000-000000000001}', '00501'),
  @('Test Person 02', 2, 'NW2', 1, [decimal]'-0.0001', 0, 0, 1E+300, $false, (D '2019-02-03 10:20:30'), (D '1899-12-30 23:59:59'), (D '1899-12-29 00:00:00'), '#mailto:person02@example.invalid#', 'Short note', '{00000000-0000-4000-8000-000000000002}', '10001'),
  @('Test Person 03', 2, 'ZZZ', 1, [decimal]'0', 7, 3.25, 1E-300, $true, (D '2020-02-29 00:00:00'), (D '1899-12-30 00:00:00'), (D '1900-01-01 00:00:00'), 'https://example.com/plain', '', '{00000000-0000-4000-8000-000000000003}', '02134'),
  @('Test Person 04', 3, $null, 2, $null, $null, $null, $null, $false, $null, $null, $null, $null, $null, $null, $null),
  @('Test Person 05', 3, 'SE3', 2, [decimal]'99.99', 1, 2.5, 3.5, $true, (D '2021-07-04 12:00:00'), (D '1899-12-30 12:00:00'), (D '1975-06-15 00:00:00'), $null, 'Note five', '{00000000-0000-4000-8000-000000000005}', '60601'),
  @('Test Person 06', 4, 'SW4', 5, [decimal]'10', 2, 1, 1, $false, (D '2021-07-05 00:00:00'), $null, $null, $null, $null, '{00000000-0000-4000-8000-000000000006}', $null),
  @('Test Person To Delete', 4, 'SW4', $null, [decimal]'0', 0, 0, 0, $false, $null, $null, $null, $null, $null, $null, $null),
  @('Test Person 08', 1, 'ZZZ', 5, [decimal]'2.5', 4, 1, 1, $true, $null, $null, $null, $null, $null, '{00000000-0000-4000-8000-000000000008}', '98101'),
  @('Test Person 09', 1, 'NE1', 8, [decimal]'3.5', 5, 1, 1, $true, $null, $null, $null, $null, $null, '{00000000-0000-4000-8000-000000000009}', '30301'),
  @('Test Person 10', 2, 'NE1', 8, [decimal]'4.5', 6, 1, 1, $true, $null, $null, $null, $null, $null, '{00000000-0000-4000-8000-00000000000A}', '80201'),
  @('Test Person 11', 5, 'SW4', $null, [decimal]'5.5', 7, 1, 1, $false, $null, $null, $null, $null, $null, '{00000000-0000-4000-8000-00000000000B}', '73301'),
  @('Test Person 12', 5, 'SW4', $null, [decimal]'6.5', 8, 1, 1, $false, $null, $null, $null, $null, $null, '{00000000-0000-4000-8000-00000000000C}', '94105')
)
Add-Rows $db 'tblCustomer' $custCols $custRows
# An AutoNumber gap, and an explicit high value
$db.Execute("DELETE FROM tblCustomer WHERE [CustomerID] = 7", 128)
$db.Execute("INSERT INTO tblCustomer ([CustomerID], [Customer Name], [StatusID]) VALUES (1000, 'Test Person 1000', 1)", 128)

# OLE Object lives in its own table: one such column stops the whole table
# loading (see TRAPS.md), and tblCustomer is the hub of the relationships.
New-DaoTable $db 'Customer Photo' @(
  @{ n = 'CustomerID'; t = $dbLong },
  @{ n = 'Caption'; t = $dbText; s = 40 },
  @{ n = 'Photo'; t = $dbLongBinary }
) -Pk 'CustomerID'
Add-Rows $db 'Customer Photo' @('CustomerID', 'Caption', 'Photo') @(
  @(1, 'large blob', $photoBig), @(2, 'small blob', $photoSmall), @(3, 'no blob', $null)
)

New-DaoTable $db 'Customer Profile' @(
  @{ n = 'CustomerID'; t = $dbLong },
  @{ n = 'Email'; t = $dbText; s = 120 },
  @{ n = 'Phone'; t = $dbText; s = 30 },
  @{ n = '2nd Phone'; t = $dbText; s = 30 }
) -Pk 'CustomerID'
Add-Rows $db 'Customer Profile' @('CustomerID', 'Email', 'Phone', '2nd Phone') @(
  @(1, 'person01@example.invalid', '402-555-0101', $null),
  @(2, 'person02@example.invalid', '402-555-0102', '402-555-0112'),
  @(3, 'person03@example.com', '402-555-0103', $null),
  @(5, 'person05@example.com', '402-555-0105', $null),
  @(1000, 'person1000@example.invalid', $null, $null)
)

# ---- Orders: reserved words, lookups, number held as text -------------
New-DaoTable $db 'Orders' @(
  @{ n = 'OrderNo'; t = $dbLong },
  @{ n = 'CustomerID'; t = $dbLong },
  @{ n = 'Select'; t = $dbText; s = 20 },
  @{ n = 'Order'; t = $dbInteger },
  @{ n = 'Date'; t = $dbDate },
  @{ n = 'Group'; t = $dbText; s = 20 },
  @{ n = 'ShipMethodID'; t = $dbLong },
  @{ n = 'Pay Type'; t = $dbText; s = 10 },
  @{ n = 'LegacyCustNo'; t = $dbText; s = 10 }
) -Pk 'OrderNo'
Add-Rows $db 'Orders' @('OrderNo', 'CustomerID', 'Select', 'Order', 'Date', 'Group', 'ShipMethodID', 'Pay Type', 'LegacyCustNo') @(
  @(1001, 1, 'A', 1, (D '2022-01-10 00:00:00'), 'G1', 1, 'Cash', '1'),
  @(1002, 1, 'B', 2, (D '2022-01-11 00:00:00'), 'G1', 2, 'Card', '1'),
  @(1003, 2, 'A', 3, (D '2022-02-12 00:00:00'), 'G2', 3, 'Cash', '2'),
  @(1004, 3, 'C', 4, (D '2022-02-13 00:00:00'), 'G2', $null, 'Cheque', '3'),
  @(1005, 5, 'A', 5, (D '2022-03-14 00:00:00'), 'G3', 1, 'Card', '5'),
  @(1006, 8, 'B', 6, (D '2022-03-15 00:00:00'), 'G3', 2, 'Cash', '8'),
  @(1007, 9, 'A', 7, (D '2022-04-16 00:00:00'), 'G3', 9, 'Card', '9'),
  @(1008, 1000, 'C', 8, (D '2022-04-17 00:00:00'), 'G3', 1, $null, '1000')
)
# Lookup Wizard field: what Access writes on a column it turns into a combo box
$ship = $db.TableDefs.Item('Orders').Fields.Item('ShipMethodID')
Set-IntProp $ship 'DisplayControl' 111
Set-TextProp $ship 'RowSourceType' 'Table/Query'
Set-TextProp $ship 'RowSource' 'SELECT [ID], [Method] FROM [tlk Ship Method] ORDER BY [Method];'
Set-IntProp $ship 'BoundColumn' 1
Set-IntProp $ship 'ColumnCount' 2
# A value-list lookup has no relationship behind it at all
$pay = $db.TableDefs.Item('Orders').Fields.Item('Pay Type')
Set-IntProp $pay 'DisplayControl' 111
Set-TextProp $pay 'RowSourceType' 'Value List'
Set-TextProp $pay 'RowSource' '"Cash";"Card";"Cheque"'
Set-TextProp $db.TableDefs.Item('Orders') 'Description' 'Synthetic orders. Table description held as a Jet property.'
Set-TextProp $db.TableDefs.Item('Orders').Fields.Item('OrderNo') 'Description' 'Synthetic column description held as a Jet property.'

New-DaoTable $db 'Order Line' @(
  @{ n = 'OrderNo'; t = $dbLong },
  @{ n = 'LineNo'; t = $dbLong },
  @{ n = 'Qty'; t = $dbInteger },
  @{ n = 'Unit Price'; t = $dbCurrency }
) -Pk 'OrderNo', 'LineNo'
Add-Rows $db 'Order Line' @('OrderNo', 'LineNo', 'Qty', 'Unit Price') @(
  @(1001, 1, 1, [decimal]'9.99'), @(1001, 2, 2, [decimal]'4.5'), @(1002, 1, 1, [decimal]'100'),
  @(1003, 1, 5, [decimal]'1'), @(1003, 2, 1, [decimal]'2'), @(1003, 3, 1, [decimal]'3'),
  @(1005, 1, 2, [decimal]'7.25'), @(1006, 1, 1, [decimal]'8'), @(1007, 1, 1, [decimal]'9'), @(1008, 1, 3, [decimal]'0.01')
)

New-DaoTable $db 'Line Note' @(
  @{ n = 'NoteID'; t = $dbLong; auto = $true },
  @{ n = 'Ref Order'; t = $dbLong },
  @{ n = 'Ref Line'; t = $dbLong },
  @{ n = 'Note'; t = $dbText; s = 60 }
) -Pk 'NoteID'
Add-Rows $db 'Line Note' @('Ref Order', 'Ref Line', 'Note') @(
  @(1001, 1, 'First'), @(1001, 2, 'Second'), @(1003, 2, 'Third'), @(1008, 1, 'Fourth')
)

# Child columns declared in the opposite order from the parent's key
New-DaoTable $db 'Line Alloc' @(
  @{ n = 'AllocID'; t = $dbLong; auto = $true },
  @{ n = 'Alloc Line'; t = $dbLong },
  @{ n = 'Alloc Order'; t = $dbLong },
  @{ n = 'Share'; t = $dbDouble }
) -Pk 'AllocID'
Add-Rows $db 'Line Alloc' @('Alloc Line', 'Alloc Order', 'Share') @(
  @(1, 1001, 0.5), @(2, 1001, 0.5), @(3, 1003, 1)
)

# ---- Two links to one parent; a link into an empty table --------------
New-DaoTable $db 'Warehouse' @(
  @{ n = 'WarehouseID'; t = $dbLong },
  @{ n = 'Name'; t = $dbText; s = 40 }
) -Pk 'WarehouseID'
Add-Rows $db 'Warehouse' @('WarehouseID', 'Name') @(
  @(1, 'Depot One'), @(2, 'Depot Two'), @(3, 'Depot Three')
)

New-DaoTable $db 'Empty Carrier' @(
  @{ n = 'CarrierID'; t = $dbLong },
  @{ n = 'Carrier Name'; t = $dbText; s = 40 },
  @{ n = 'Active'; t = $dbBoolean }
) -Pk 'CarrierID'

New-DaoTable $db 'Shipment' @(
  @{ n = 'ShipmentID'; t = $dbLong },
  @{ n = 'FromWarehouse'; t = $dbLong },
  @{ n = 'ToWarehouse'; t = $dbLong },
  @{ n = 'CarrierID'; t = $dbLong }
) -Pk 'ShipmentID'
Add-Rows $db 'Shipment' @('ShipmentID', 'FromWarehouse', 'ToWarehouse', 'CarrierID') @(
  @(1, 1, 2, $null), @(2, 2, 3, $null), @(3, 1, 3, $null), @(4, 3, 1, $null)
)

# ---- Jet compares text without case: an enforced link R will not see --
New-DaoTable $db 'Store' @(
  @{ n = 'StoreID'; t = $dbLong },
  @{ n = 'RegionCode'; t = $dbText; s = 3 },
  @{ n = 'HomeWarehouse'; t = $dbLong }
) -Pk 'StoreID'
Add-Rows $db 'Store' @('StoreID', 'RegionCode', 'HomeWarehouse') @(
  @(1, 'ne1', 1), @(2, 'nw2', 2), @(3, 'SE3', 9)
)

# ---- No primary key ---------------------------------------------------
New-DaoTable $db 'Legacy Code' @(
  @{ n = 'LegacyCode'; t = $dbText; s = 8 },
  @{ n = 'Meaning'; t = $dbText; s = 40 }
)
Add-UniqueIndex $db 'Legacy Code' 'ux_legacy' @('LegacyCode')
Add-Rows $db 'Legacy Code' @('LegacyCode', 'Meaning') @(
  @('L-01', 'Legacy one'), @('L-02', 'Legacy two'), @('L-03', 'Legacy three')
)
New-DaoTable $db 'Legacy Use' @(
  @{ n = 'LegacyCode'; t = $dbText; s = 8 },
  @{ n = 'Used On'; t = $dbDate }
)
Add-Rows $db 'Legacy Use' @('LegacyCode', 'Used On') @(
  @('L-01', (D '2020-05-01 00:00:00')), @('L-01', (D '2020-05-02 00:00:00')), @('L-03', $null)
)
New-DaoTable $db 'Audit Log' @(
  @{ n = 'CustomerID'; t = $dbLong },
  @{ n = 'Action'; t = $dbText; s = 20 }
)
Add-Rows $db 'Audit Log' @('CustomerID', 'Action') @(
  @(1, 'view'), @(1, 'view'), @(2, 'edit'), @(77777, 'view'), @($null, 'login'), @($null, 'login')
)

# ---- GUID key ---------------------------------------------------------
New-DaoTable $db 'Device' @(
  @{ n = 'DeviceGuid'; t = $dbGUID },
  @{ n = 'Label'; t = $dbText; s = 30 }
) -Pk 'DeviceGuid'
Add-Rows $db 'Device' @('DeviceGuid', 'Label') @(
  @('{11111111-1111-4111-8111-111111111111}', 'Device A'),
  @('{22222222-2222-4222-8222-222222222222}', 'Device B'),
  @('{33333333-3333-4333-8333-333333333333}', 'Device C')
)
New-DaoTable $db 'Device Log' @(
  @{ n = 'LogID'; t = $dbLong; auto = $true },
  @{ n = 'DeviceGuid'; t = $dbGUID },
  @{ n = 'Reading'; t = $dbDouble }
) -Pk 'LogID'
Add-Rows $db 'Device Log' @('DeviceGuid', 'Reading') @(
  @('{11111111-1111-4111-8111-111111111111}', 1.5),
  @('{11111111-1111-4111-8111-111111111111}', 2.5),
  @('{22222222-2222-4222-8222-222222222222}', 3.5),
  @($null, 4.5)
)

# ---- Value traps: each row carries its own expected value -------------
New-DaoTable $db 'Date Traps' @(
  @{ n = 'DateID'; t = $dbLong },
  @{ n = 'Case Name'; t = $dbText; s = 40 },
  @{ n = 'Value'; t = $dbDate },
  @{ n = 'Expected'; t = $dbText; s = 19 }
) -Pk 'DateID'
$dateCases = @(
  @('zero, the epoch', '1899-12-30 00:00:00'),
  @('time only, noon-ish', '1899-12-30 12:34:56'),
  @('one day before the epoch at 06:00', '1899-12-29 06:00:00'),
  @('before 1900', '1850-06-15 00:00:00'),
  @('before 1900 with a time', '1850-06-15 18:30:00'),
  @('Gregorian cutover gap', '1582-10-10 00:00:00'),
  @('earliest Access date', '0100-01-01 00:00:00'),
  @('latest Access date', '9999-12-31 23:59:59'),
  @('US spring-forward gap', '2021-03-14 02:30:00'),
  @('US fall-back overlap', '2021-11-07 01:30:00'),
  @('leap day', '2000-02-29 00:00:00'),
  @('ordinary date only', '2024-05-06 00:00:00')
)
$i = 0
foreach ($c in $dateCases) {
  $i++
  Add-Rows $db 'Date Traps' @('DateID', 'Case Name', 'Value', 'Expected') @(, @($i, $c[0], (D $c[1]), $c[1]))
}
Add-Rows $db 'Date Traps' @('DateID', 'Case Name', 'Value', 'Expected') @(, @(13, 'Null date', $null, $null))

Add-Rows $db 'Number Traps' @('NumID', 'Case Name', 'ByteV', 'IntV', 'LongV', 'SingleV', 'DoubleV', 'CurrV', 'DecV', 'Expected') @(
  @(1, 'minimums', 0, -32768, [int]::MinValue, -1.5, -1E+300, '-922337203685477.5808', '-999999999999999999999999.9999', 'LongV -2147483648; CurrV -922337203685477.5808; DecV -999999999999999999999999.9999'),
  @(2, 'maximums', 255, 32767, 2147483647, 1.5, 1E+300, '922337203685477.5807', '999999999999999999999999.9999', 'LongV 2147483647; CurrV 922337203685477.5807; DecV 999999999999999999999999.9999'),
  @(3, 'zeros', 0, 0, 0, 0, 0, [decimal]'0', [decimal]'0', 'all zero, not Null'),
  @(4, 'fractions', 1, 1, 1, 0.1, 0.1, [decimal]'0.1', [decimal]'0.1', 'SingleV is 0.1 in single precision'),
  @(5, 'nulls', $null, $null, $null, $null, $null, $null, $null, 'every value Null')
)

$long70k = ('0123456789' * 7000)
$textCases = @(
  @('plain ASCII', 'Plain synthetic value'),
  @('comma', 'one, two, three'),
  @('double quote', 'say "hello" twice'),
  @('single quote', "it's a test"),
  @('LF', "line one`nline two"),
  @('CRLF', "line one`r`nline two"),
  @('tab', "col one`tcol two"),
  @('trailing spaces', 'trailing   '),
  @('leading spaces', '   leading'),
  @('only spaces', '   '),
  @('empty string', ''),
  @('text NA', 'NA'),
  @('text NULL', 'NULL'),
  @('text TRUE', 'TRUE'),
  @('leading zeros', '000123'),
  @('sci notation', '1E5'),
  @('formula', '=1+1'),
  @('hash signs', 'a#b#c#'),
  @('Latin-1', ('caf' + (U 0xE9) + ' na' + (U 0xEF) + 've ' + (U 0xFC))),
  @('outside cp1252, Cyrillic', (U 0x043F, 0x0440, 0x0438, 0x0432, 0x0435, 0x0442)),
  @('outside cp1252, CJK', (U 0x6D4B, 0x8BD5)),
  @('RTL Hebrew', (U 0x05D1, 0x05D3, 0x05D9, 0x05E7, 0x05D4)),
  @('emoji, surrogate pair', ('ok ' + (U 0x1F600))),
  @('non-breaking space', ('a' + (U 0xA0) + 'b')),
  @('smart quotes and dash', ((U 0x201C) + 'x' + (U 0x201D) + ' ' + (U 0x2013) + ' y')),
  @('replacement character', ('x' + (U 0xFFFD)))
)
$i = 0
foreach ($c in $textCases) {
  $i++
  Add-Rows $db 'Text Traps' @('TextID', 'Case Name', 'Short Text', 'Comp Text', 'Long Text', 'Expected Len', 'Expected Hex') @(, @($i, $c[0], $c[1], $c[1], $c[1], $c[1].Length, (Hex16 $c[1])))
}
Add-Rows $db 'Text Traps' @('TextID', 'Case Name', 'Short Text', 'Comp Text', 'Long Text', 'Expected Len', 'Expected Hex') @(
  @(($i + 1), 'Null everywhere', $null, $null, $null, $null, $null),
  @(($i + 2), 'memo over 64 KB', 'long', 'long', $long70k, $long70k.Length, $null),
  @(($i + 3), 'memo of 300 characters', 'mid', 'mid', ('x' * 300), 300, $null)
)

# ---- Names ------------------------------------------------------------
New-DaoTable $db 'Collide Cols' @(
  @{ n = 'RowID'; t = $dbLong; auto = $true },
  @{ n = 'Item Code'; t = $dbText; s = 3 },
  @{ n = 'item_code'; t = $dbText; s = 3 },
  @{ n = 'ITEM-CODE'; t = $dbText; s = 3 },
  @{ n = 'ItemCode'; t = $dbText; s = 3 },
  @{ n = 'Item%'; t = $dbDouble },
  @{ n = $cafeNo; t = $dbText; s = 10 },
  @{ n = $naive; t = $dbText; s = 10 },
  @{ n = $cjkCol; t = $dbText; s = 10 },
  @{ n = '#'; t = $dbLong },
  @{ n = '%'; t = $dbDouble },
  @{ n = 'NA'; t = $dbText; s = 10 }
) -Pk 'RowID'
Add-Rows $db 'Collide Cols' @('Item Code', 'item_code', 'ITEM-CODE', 'ItemCode', 'Item%', $cafeNo, $naive, $cjkCol, '#', '%', 'NA') @(
  @('AAA', 'BBB', 'NE1', 'DDD', 0.5, 'c1', 'n1', 'j1', 1, 0.1, 'x'),
  @('AAB', 'BBC', 'NW2', 'DDE', 0.25, 'c2', 'n2', 'j2', 2, 0.2, $null)
)

New-DaoTable $db 'Order Detail' @(@{ n = 'OrderNo'; t = $dbLong }, @{ n = 'Qty'; t = $dbInteger })
Add-Rows $db 'Order Detail' @('OrderNo', 'Qty') @(@(1001, 1), @(1002, 2))
New-DaoTable $db 'order_detail' @(@{ n = 'Order No'; t = $dbLong }, @{ n = 'Comment'; t = $dbText; s = 20 })
Add-Rows $db 'order_detail' @('Order No', 'Comment') @(@(1001, 'x'), @(1002, 'y'), @(1003, 'z'))
New-DaoTable $db 'Order-Detail' @(@{ n = 'OrderNo'; t = $dbLong }, @{ n = 'Flag'; t = $dbBoolean })
Add-Rows $db 'Order-Detail' @('OrderNo', 'Flag') @(@(1001, $true), @(1002, $false), @(1003, $true), @(1004, $false))

New-DaoTable $db $apos @(@{ n = 'CustomerID'; t = $dbLong }, @{ n = "Author's Note"; t = $dbText; s = 40 })
Add-Rows $db $apos @('CustomerID', "Author's Note") @(, @(1, 'one row, apostrophes in both names'))
New-DaoTable $db 'Select' @(@{ n = 'From'; t = $dbText; s = 10 }, @{ n = 'Where'; t = $dbLong })
Add-Rows $db 'Select' @('From', 'Where') @(, @('reserved', 1))
New-DaoTable $db 'Reports/Monthly' @(@{ n = 'Month'; t = $dbLong }, @{ n = 'Total #'; t = $dbLong })
Add-Rows $db 'Reports/Monthly' @('Month', 'Total #') @(@(1, 10), @(2, 20))
New-DaoTable $db $ubersicht @(@{ n = $buero; t = $dbLong }, @{ n = 'Titel'; t = $dbText; s = 30 })
Add-Rows $db $ubersicht @($buero, 'Titel') @(@(1, 'Band Eins'), @(2, 'Band Zwei'))
New-DaoTable $db $cjkTbl @(@{ n = 'ID'; t = $dbLong }, @{ n = 'Label'; t = $dbText; s = 30 })
Add-Rows $db $cjkTbl @('ID', 'Label') @(, @(1, 'CJK table name'))
New-DaoTable $db $longName @(@{ n = 'ID'; t = $dbLong })
Add-Rows $db $longName @('ID') @(, @(1))

# ---- Tables that look like system tables, and tables flagged as such --
New-DaoTable $db 'MSystem Parts' @(@{ n = 'PartNo'; t = $dbLong }, @{ n = 'RegionCode'; t = $dbText; s = 3 })
Add-Rows $db 'MSystem Parts' @('PartNo', 'RegionCode') @(@(1, 'NE1'), @(2, 'NW2'))
New-DaoTable $db 'USystem Notes' @(@{ n = 'NoteNo'; t = $dbLong }, @{ n = 'Body'; t = $dbText; s = 30 })
Add-Rows $db 'USystem Notes' @('NoteNo', 'Body') @(, @(1, 'user table, USys-like name'))
New-DaoTable $db '~Draft Table' @(@{ n = 'DraftNo'; t = $dbLong })
Add-Rows $db '~Draft Table' @('DraftNo') @(, @(1))
New-DaoTable $db 'msys_lower' @(@{ n = 'LowerNo'; t = $dbLong })
Add-Rows $db 'msys_lower' @('LowerNo') @(, @(1))
New-DaoTable $db 'USysRibbons' @(@{ n = 'RibbonName'; t = $dbText; s = 30 }, @{ n = 'RibbonXML'; t = $dbMemo })
Add-Rows $db 'USysRibbons' @('RibbonName', 'RibbonXML') @(, @('Synthetic', '<customUI/>'))
New-DaoTable $db 'MSysUserMade' @(@{ n = 'MadeNo'; t = $dbLong })
Add-Rows $db 'MSysUserMade' @('MadeNo') @(, @(1))
New-DaoTable $db 'Hidden Table' @(@{ n = 'HiddenNo'; t = $dbLong }, @{ n = 'StatusID'; t = $dbLong })
Add-Rows $db 'Hidden Table' @('HiddenNo', 'StatusID') @(@(1, 1), @(2, 2))
New-DaoTable $db 'Flagged System' @(@{ n = 'FlagNo'; t = $dbLong })
Add-Rows $db 'Flagged System' @('FlagNo') @(, @(1))
# Flags go on after the rows: a system-flagged table refuses inserts
$h = $db.TableDefs.Item('Hidden Table'); $h.Attributes = $h.Attributes -bor $dbHiddenObject
$s = $db.TableDefs.Item('Flagged System'); $s.Attributes = [int]($s.Attributes -bor $dbSystemObject)

# ---- Relationships ----------------------------------------------------
Add-Rel $db 'R01_status' 'tlk Status' 'tblCustomer' @(, @('StatusID', 'StatusID'))
Add-Rel $db 'R02_region_unenforced' 'tlk_Region' 'tblCustomer' @(, @('Code', 'RegionCode')) $dbRelationDontEnforce
Add-Rel $db 'R03_self' 'tblCustomer' 'tblCustomer' @(, @('CustomerID', 'ReferredBy'))
Add-Rel $db 'R04_profile_1to1' 'tblCustomer' 'Customer Profile' @(, @('CustomerID', 'CustomerID')) $dbRelationUnique
Add-Rel $db 'R05_orders_cascade' 'tblCustomer' 'Orders' @(, @('CustomerID', 'CustomerID')) ($dbRelationUpdateCascade + $dbRelationDeleteCascade)
Add-Rel $db 'R06_lookup_ship' 'tlk Ship Method' 'Orders' @(, @('ID', 'ShipMethodID')) $dbRelationDontEnforce
Add-Rel $db 'R07_line_order' 'Orders' 'Order Line' @(, @('OrderNo', 'OrderNo')) $dbRelationDeleteCascade
Add-Rel $db 'R08_note_composite' 'Order Line' 'Line Note' @(@('OrderNo', 'Ref Order'), @('LineNo', 'Ref Line'))
# Jet refuses a relationship whose field order is not a unique index's order
# (error text: No unique index found for the referenced field of the primary
# table), so the pairs follow the key; the child's columns sit the other way
# round in the table.
Add-Rel $db 'R09_alloc_reversed' 'Order Line' 'Line Alloc' @(@('OrderNo', 'Alloc Order'), @('LineNo', 'Alloc Line'))
Add-Rel $db 'R10_ship_from' 'Warehouse' 'Shipment' @(, @('WarehouseID', 'FromWarehouse'))
Add-Rel $db 'R11_ship_to' 'Warehouse' 'Shipment' @(, @('WarehouseID', 'ToWarehouse'))
Add-Rel $db 'R12_ship_carrier_empty' 'Empty Carrier' 'Shipment' @(, @('CarrierID', 'CarrierID'))
Add-Rel $db 'R13_store_region_case' 'tlk_Region' 'Store' @(, @('Code', 'RegionCode'))
Add-Rel $db 'R14_legacy_unique' 'Legacy Code' 'Legacy Use' @(, @('LegacyCode', 'LegacyCode'))
Add-Rel $db 'R15_audit_nopk' 'tblCustomer' 'Audit Log' @(, @('CustomerID', 'CustomerID')) $dbRelationDontEnforce
Add-Rel $db 'R16_device_guid' 'Device' 'Device Log' @(, @('DeviceGuid', 'DeviceGuid'))
Add-Rel $db 'R17_msystem_like' 'tlk_Region' 'MSystem Parts' @(, @('Code', 'RegionCode')) $dbRelationDontEnforce
Add-Rel $db 'R18_collide_col' 'tlk_Region' 'Collide Cols' @(, @('Code', 'ITEM-CODE')) $dbRelationDontEnforce
Add-Rel $db 'R19_collide_table' 'Orders' 'Order-Detail' @(, @('OrderNo', 'OrderNo')) $dbRelationDontEnforce
Add-Rel $db 'R20_left_join' 'Warehouse' 'Store' @(, @('WarehouseID', 'HomeWarehouse')) ($dbRelationDontEnforce + $dbRelationLeft)
Add-Rel $db 'R21_hidden_child' 'tlk Status' 'Hidden Table' @(, @('StatusID', 'StatusID')) $dbRelationDontEnforce
Add-Rel $db 'R22_apostrophe' 'tblCustomer' $apos @(, @('CustomerID', 'CustomerID')) $dbRelationDontEnforce
Add-Rel $db 'R23_non_ascii' 'tblCustomer' $ubersicht @(, @('CustomerID', $buero)) $dbRelationDontEnforce
Add-Rel $db 'R24_photo' 'tblCustomer' 'Customer Photo' @(, @('CustomerID', 'CustomerID'))

# ---- Saved queries ----------------------------------------------------
[void]$db.CreateQueryDef('qryActiveCustomers', 'SELECT [CustomerID], [Customer Name] FROM tblCustomer WHERE [Is Member] = True;')
[void]$db.CreateQueryDef('qry Customer Param', 'PARAMETERS [pStatus] Long; SELECT * FROM tblCustomer WHERE [StatusID] = [pStatus];')
[void]$db.CreateQueryDef('qryUpdateNothing', 'UPDATE tblCustomer SET [Visits] = [Visits] WHERE 1 = 0;')
[void]$db.CreateQueryDef('qryUnion', 'SELECT [Code] FROM tlk_Region UNION SELECT [RegionCode] FROM Store;')
[void]$db.CreateQueryDef('qryCrosstab', 'TRANSFORM Count([OrderNo]) SELECT [CustomerID] FROM Orders GROUP BY [CustomerID] PIVOT [Pay Type];')
[void]$db.CreateQueryDef('qryWildIIf', 'SELECT [CustomerID], IIf([Is Member], "Y", "N") AS Member FROM tblCustomer WHERE [Customer Name] LIKE "Test*";')

$db.Close()
$size = (Get-Item -LiteralPath $Target).Length
"Built $([IO.Path]::GetFileName($Target)) with DAO.DBEngine.120 ($size bytes)"
