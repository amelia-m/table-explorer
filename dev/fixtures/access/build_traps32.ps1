# build_traps32.ps1 - small files that only the 32-bit Jet 4.0 engine can write.
#
#   C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe -NoProfile -File build_traps32.ps1 -OutDir <folder>
#
# Tool: DAO.DBEngine.36 (dao360.dll, ships with Windows). The 64-bit ACE engine
# reports "Could not find installable ISAM" for Jet 3.

param([Parameter(Mandatory = $true)][string]$OutDir)

. (Join-Path $PSScriptRoot 'fixture_lib.ps1')

$engine = New-Object -ComObject 'DAO.DBEngine.36'
"PowerShell $($PSVersionTable.PSVersion); DAO.DBEngine.36 version $($engine.Version)"

function New-Jet3 {
  param([string]$File, [string]$Locale, [string]$Sample)
  $p = Join-Path $OutDir $File
  $db = $engine.CreateDatabase($p, $Locale, $dbVersion30)
  New-DaoTable $db 'tlk Kind' @(
    @{ n = 'KindID'; t = $dbLong },
    @{ n = 'Label'; t = $dbText; s = 30 }
  ) -Pk 'KindID'
  Add-Rows $db 'tlk Kind' @('KindID', 'Label') @(@(1, 'Alpha'), @(2, 'Beta'))
  New-DaoTable $db 'Item' @(
    @{ n = 'ItemID'; t = $dbLong },
    @{ n = 'KindID'; t = $dbLong },
    @{ n = 'Note'; t = $dbText; s = 60 },
    @{ n = 'Body'; t = $dbMemo },
    @{ n = 'Row Guid'; t = $dbGUID }
  ) -Pk 'ItemID'
  Add-Rows $db 'Item' @('ItemID', 'KindID', 'Note', 'Body', 'Row Guid') @(
    @(1, 1, $Sample, ($Sample + ' memo'), '{00000000-0000-4000-8000-000000000001}'),
    @(2, 2, 'plain', 'plain memo', $null),
    @(3, $null, $null, $null, $null)
  )
  Add-Rel $db 'R_item_kind' 'tlk Kind' 'Item' @(, @('KindID', 'KindID'))
  $v = $db.Version
  $db.Close()
  "Built $File, Jet version $v ($((Get-Item -LiteralPath $p).Length) bytes)"
}

# Text in Jet 3 is stored in the file's code page, not in Unicode
New-Jet3 'trap_jet3.mdb' $LangGeneral ('caf' + (U 0xE9) + ' na' + (U 0xEF) + 've')
New-Jet3 'trap_jet3_cyrillic.mdb' $LangCyrillic (U 0x043F, 0x0440, 0x0438, 0x0432, 0x0435, 0x0442)

# Replication, an mdb-only feature: Design Master of a Jet 4 file
$p = Join-Path $OutDir 'trap_replica.mdb'
$db = $engine.CreateDatabase($p, $LangGeneral, $dbVersion40)
New-DaoTable $db 'Replicated Table' @(
  @{ n = 'RowID'; t = $dbLong },
  @{ n = 'Label'; t = $dbText; s = 30 }
) -Pk 'RowID'
Add-Rows $db 'Replicated Table' @('RowID', 'Label') @(@(1, 'One'), @(2, 'Two'))
try {
  $db.Properties.Append($db.CreateProperty('Replicable', $dbText, 'T'))
  "Built trap_replica.mdb ($((Get-Item -LiteralPath $p).Length) bytes)"
} catch {
  "trap_replica.mdb: replication failed: $($_.Exception.Message)"
}
$db.Close()
