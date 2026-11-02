# build_all.ps1 - rebuild every fixture file from source, one command:
#
#   pwsh -NoProfile -File build_all.ps1 -OutDir <empty folder>
#
# Takes 5 to 10 minutes on the work machine: each COM call is slow there.
# Refuses a folder that already holds a build, so it never overwrites.

param([Parameter(Mandatory = $true)][string]$OutDir)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
if (Test-Path -LiteralPath (Join-Path $OutDir 'access_fixture.mdb')) { throw "Already built in $OutDir" }

$here = $PSScriptRoot
"PowerShell $($PSVersionTable.PSVersion); DAO.DBEngine.120 version $((New-Object -ComObject 'DAO.DBEngine.120').Version)"

& (Join-Path $here 'build_fixture.ps1') -Target (Join-Path $OutDir 'access_fixture.mdb')
& (Join-Path $here 'build_fixture.ps1') -Target (Join-Path $OutDir 'access_fixture.accdb')
& (Join-Path $here 'build_traps.ps1') -OutDir $OutDir

$ps32 = 'C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
& $ps32 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'build_traps32.ps1') -OutDir $OutDir
if ($LASTEXITCODE -ne 0) { throw "32-bit part exited with $LASTEXITCODE" }
& (Join-Path $here 'scrub_paths.ps1') -Dir $OutDir -BuiltIn $OutDir

Get-ChildItem -LiteralPath $OutDir -File | Sort-Object Name | ForEach-Object { '{0,-30} {1,9}' -f $_.Name, $_.Length }
