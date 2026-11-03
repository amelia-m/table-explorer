# build_traps.ps1 - small files for traps that stop a reader, 64-bit part.
#
#   pwsh -NoProfile -File build_traps.ps1 -OutDir <folder>
#
# Tool: DAO.DBEngine.120. Run from build_all.ps1, which also runs the 32-bit
# part (build_traps32.ps1) for Jet 3 and replication.

param([Parameter(Mandatory = $true)][string]$OutDir)

. (Join-Path $PSScriptRoot 'fixture_lib.ps1')

$placeholderPwd = 'not-a-real-secret'
$engine = New-Object -ComObject 'DAO.DBEngine.120'

function Add-SmallSchema {
  param($Db)
  New-DaoTable $Db 'tlk Kind' @(
    @{ n = 'KindID'; t = $dbLong },
    @{ n = 'Label'; t = $dbText; s = 30 }
  ) -Pk 'KindID'
  Add-Rows $Db 'tlk Kind' @('KindID', 'Label') @(@(1, 'Alpha'), @(2, 'Beta'))
  New-DaoTable $Db 'Item' @(
    @{ n = 'ItemID'; t = $dbLong },
    @{ n = 'KindID'; t = $dbLong },
    @{ n = 'Note'; t = $dbText; s = 60 }
  ) -Pk 'ItemID'
  Add-Rows $Db 'Item' @('ItemID', 'KindID', 'Note') @(
    @(1, 1, ('caf' + (U 0xE9))), @(2, 2, (U 0x043F, 0x0440, 0x0438)), @(3, 1, 'plain')
  )
  Add-Rel $Db 'R_item_kind' 'tlk Kind' 'Item' @(, @('KindID', 'KindID'))
}

function New-Small {
  param([string]$File, [int]$Opt, [string]$Locale = $LangGeneral)
  $p = Join-Path $OutDir $File
  $db = $engine.CreateDatabase($p, $Locale, $Opt)
  Add-SmallSchema $db
  $db.Close()
  "Built $File ($((Get-Item -LiteralPath $p).Length) bytes)"
}

# Database password (mdb) and the same on an accdb, which is real encryption
New-Small 'trap_password.mdb' $dbVersion40 ($LangGeneral + ';pwd=' + $placeholderPwd)
New-Small 'trap_password.accdb' $dbVersion120 ($LangGeneral + ';pwd=' + $placeholderPwd)
# "Encoded" with no password
New-Small 'trap_encoded.mdb' ($dbVersion40 + $dbEncrypt)
# A non-Latin sort order and code page on Jet 4
New-Small 'trap_cyrillic_sort.mdb' $dbVersion40 $LangCyrillic

# Base for the files that follow, plus the source of the linked table
New-Small 'trap_linked_source.mdb' $dbVersion40

# Linked table, stored with a relative path so the build folder is not written
# into the file. Compare to the rule on usernames in written files.
[Environment]::CurrentDirectory = (Resolve-Path -LiteralPath $OutDir).Path
$p = Join-Path $OutDir 'trap_linked.mdb'
$db = $engine.CreateDatabase($p, $LangGeneral, $dbVersion40)
New-DaoTable $db 'Local Table' @(@{ n = 'LocalID'; t = $dbLong })
Add-Rows $db 'Local Table' @('LocalID') @(, @(1))
$td = $db.CreateTableDef('Linked Item')
$td.Connect = ';DATABASE=trap_linked_source.mdb'
$td.SourceTableName = 'Item'
$db.TableDefs.Append($td)
$stored = $db.TableDefs.Item('Linked Item').Connect
$db.Close()
"Built trap_linked.mdb; stored Connect is: $stored"

# accdb-only column types. They stay out of access_fixture, which must build
# the same schema in both formats.
$p = Join-Path $OutDir 'trap_accdb_types.accdb'
$db = $engine.CreateDatabase($p, $LangGeneral, $dbVersion120)
$td = $db.CreateTableDef('Accdb Only')
$td.Fields.Append($td.CreateField('RowID', $dbLong))
$td.Fields.Append($td.CreateField('Files', 101))    # dbAttachment
$td.Fields.Append($td.CreateField('Picks', 109))    # dbComplexText, multi-value
$db.TableDefs.Append($td)
Add-Rows $db 'Accdb Only' @('RowID') @(@(1), @(2))
$db.Close()
"Built trap_accdb_types.accdb ($((Get-Item -LiteralPath $p).Length) bytes)"

# Wrong content under the right extension
$src = Join-Path $OutDir 'trap_linked_source.mdb'
[IO.File]::WriteAllText((Join-Path $OutDir 'trap_not_access.mdb'), "this,is,a,csv`n1,2,3`n")
[IO.File]::WriteAllBytes((Join-Path $OutDir 'trap_empty.mdb'), [byte[]]@())
$bytes = [IO.File]::ReadAllBytes($src)
[IO.File]::WriteAllBytes((Join-Path $OutDir 'trap_truncated.mdb'), $bytes[0..8191])
# Right content under the wrong extension
Copy-Item -LiteralPath $src -Destination (Join-Path $OutDir 'trap_mdb_renamed.accdb')
$p = Join-Path $OutDir 'trap_accdb_renamed.mdb'
$tmp = Join-Path $OutDir 'trap_accdb_src.accdb'
$db = $engine.CreateDatabase($tmp, $LangGeneral, $dbVersion120)
Add-SmallSchema $db
$db.Close()
Move-Item -LiteralPath $tmp -Destination $p
"Built wrong-content and wrong-extension files"
