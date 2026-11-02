# scrub_paths.ps1 - remove the build folder from files where Jet wrote it.
#
# Jet stores the absolute path of a linked table's source, and of a replica, even
# when given a relative one, and that path can carry a username. This overwrites
# the path in place with x characters of the same length, so nothing else in the
# file moves. A scrubbed link therefore points nowhere, which is also what the app
# meets, because an upload lands in a temp folder away from its source.
#
#   pwsh -NoProfile -File scrub_paths.ps1 -Dir <folder> -BuiltIn <folder at build time>
# Fails if the path, or the user's name, is still in any built file afterwards.

param([Parameter(Mandatory = $true)][string]$Dir, [Parameter(Mandatory = $true)][string]$BuiltIn)
$ErrorActionPreference = 'Stop'
$latin = [Text.Encoding]::Latin1
$uni = [Text.Encoding]::Unicode
# A replica also records the machine it was made on
$pairs = @(
  @($BuiltIn, ('C:\' + ('x' * ($BuiltIn.Length - 3)))),
  @($env:COMPUTERNAME, ('x' * $env:COMPUTERNAME.Length))
)
foreach ($f in 'trap_linked.mdb', 'trap_replica.mdb') {
  $p = Join-Path $Dir $f
  $s = $latin.GetString([IO.File]::ReadAllBytes($p))
  $n = 0
  foreach ($pair in $pairs) {
    $needle = $latin.GetString($uni.GetBytes($pair[0]))
    $n += ([regex]::Matches($s, [regex]::Escape($needle))).Count
    $s = $s.Replace($needle, $latin.GetString($uni.GetBytes($pair[1])))
  }
  [IO.File]::WriteAllBytes($p, $latin.GetBytes($s))
  "$f : $n occurrence(s) overwritten"
}
$terms = @($env:USERNAME, $env:COMPUTERNAME, 'Users\')
$bad = 0
foreach ($file in Get-ChildItem -LiteralPath $Dir -File | Where-Object { $_.Extension -in '.mdb', '.accdb' }) {
  $s = $latin.GetString([IO.File]::ReadAllBytes($file.FullName))
  foreach ($t in $terms) {
    foreach ($form in @($t, $latin.GetString($uni.GetBytes($t)))) {
      if ($s.Contains($form)) { "STILL PRESENT in $($file.Name): term $([array]::IndexOf($terms, $t))"; $bad++ }
    }
  }
}
if ($bad) { throw "$bad identifying string(s) left in built files" }
"No username, machine name or user path in any built file"
