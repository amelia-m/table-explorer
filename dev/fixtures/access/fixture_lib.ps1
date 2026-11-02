# fixture_lib.ps1 - DAO helpers shared by the fixture generators.
# ASCII only on purpose: every non-ASCII value is built from code points, so the
# result does not depend on how a PowerShell version decodes this file.
# Runs under PowerShell 7 (64-bit, DAO.DBEngine.120) and Windows PowerShell 5.1
# (32-bit, DAO.DBEngine.36).

$ErrorActionPreference = 'Stop'

# DAO constants, numeric because late-bound COM has no enums here
$dbBoolean = 1; $dbByte = 2; $dbInteger = 3; $dbLong = 4; $dbCurrency = 5
$dbSingle = 6; $dbDouble = 7; $dbDate = 8; $dbText = 10; $dbLongBinary = 11
$dbMemo = 12; $dbGUID = 15; $dbDecimal = 20
$dbAutoIncrField = 16; $dbHyperlinkField = 32768
$dbHiddenObject = 1; $dbSystemObject = -2147483648
$dbRelationUnique = 1; $dbRelationDontEnforce = 2
$dbRelationUpdateCascade = 256; $dbRelationDeleteCascade = 4096
$dbRelationLeft = 16777216
$dbVersion30 = 32; $dbVersion40 = 64; $dbVersion120 = 128; $dbEncrypt = 2
$LangGeneral = ';LANGID=0x0409;CP=1252;COUNTRY=0'
$LangCyrillic = ';LANGID=0x0419;CP=1251;COUNTRY=0'

# A column spec is a hashtable:
#  n  name, t  DAO type, s  size for Text, auto  AutoNumber, hyper  Hyperlink,
#  req  Required, zero  AllowZeroLength (defaults to true for Text and Memo)
function New-DaoTable {
  param($Db, [string]$Name, [object[]]$Cols, [string[]]$Pk = @(), [int]$Attr = 0)
  $td = $Db.CreateTableDef($Name)
  foreach ($c in $Cols) {
    $f = if ($c.ContainsKey('s')) { $td.CreateField($c.n, $c.t, $c.s) } else { $td.CreateField($c.n, $c.t) }
    if ($c.auto) { $f.Attributes = $dbAutoIncrField }
    if ($c.hyper) { $f.Attributes = $dbHyperlinkField }
    if ($c.req) { $f.Required = $true }
    if ($c.t -eq $dbText -or $c.t -eq $dbMemo) { $f.AllowZeroLength = $true }
    $td.Fields.Append($f)
  }
  if ($Pk.Count -gt 0) {
    $ix = $td.CreateIndex('PrimaryKey')
    $ix.Primary = $true
    $ix.Unique = $true
    foreach ($p in $Pk) { $ix.Fields.Append($ix.CreateField($p)) }
    $td.Indexes.Append($ix)
  }
  $Db.TableDefs.Append($td)
  if ($Attr -ne 0) {
    $t2 = $Db.TableDefs.Item($Name)
    $t2.Attributes = $t2.Attributes -bor $Attr
  }
}

function Add-UniqueIndex {
  param($Db, [string]$Table, [string]$IndexName, [string[]]$Fields)
  $td = $Db.TableDefs.Item($Table)
  $ix = $td.CreateIndex($IndexName)
  $ix.Unique = $true
  foreach ($p in $Fields) { $ix.Fields.Append($ix.CreateField($p)) }
  $td.Indexes.Append($ix)
}

# Rows go in as arrays parallel to $Cols. $null leaves the field Null.
function Add-Rows {
  param($Db, [string]$Table, [string[]]$Cols, [object[]]$Rows)
  $rs = $Db.OpenRecordset($Table, 2)
  foreach ($r in $Rows) {
    $rs.AddNew()
    for ($i = 0; $i -lt $Cols.Count; $i++) {
      if ($null -ne $r[$i]) {
        # InvokeMember, because the COM adapter's own setter caches the first
        # Variant type it sees and then fails on the next column's type
        $f = $rs.Fields.Item($Cols[$i])
        [void][System.__ComObject].InvokeMember('Value', [Reflection.BindingFlags]::SetProperty, $null, $f, @(, $r[$i]))
      }
    }
    $rs.Update()
  }
  $rs.Close()
}

# $Pairs is a list of parent,child column pairs in relationship order
function Add-Rel {
  param($Db, [string]$Name, [string]$Parent, [string]$Child, [object[]]$Pairs, [int]$Attr = 0)
  $rel = $Db.CreateRelation($Name, $Parent, $Child, $Attr)
  foreach ($p in $Pairs) {
    $f = $rel.CreateField($p[0])
    $f.ForeignName = $p[1]
    $rel.Fields.Append($f)
  }
  $Db.Relations.Append($rel)
}

function Set-TextProp {
  param($Obj, [string]$Name, [string]$Value)
  $Obj.Properties.Append($Obj.CreateProperty($Name, $dbText, $Value))
}

function Set-IntProp {
  param($Obj, [string]$Name, [int]$Value)
  $Obj.Properties.Append($Obj.CreateProperty($Name, $dbInteger, $Value))
}

function D {
  param([string]$s)
  [datetime]::ParseExact($s, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
}

function U {
  param([int[]]$Points)
  -join ($Points | ForEach-Object { [char]::ConvertFromUtf32($_) })
}

function Hex16 {
  param([string]$s)
  ([BitConverter]::ToString([Text.Encoding]::Unicode.GetBytes($s))) -replace '-', ''
}
