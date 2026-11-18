#Requires -Version 5.1
<#
.SYNOPSIS
    Asserts that every tool of the given group(s) is installed, plus the matching
    Heitorgkk metapackages. With -External, npm, desktop apps and Claude plugins/skills are checked too.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string[]] $Group,
    [switch] $External
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path (Join-Path $repo 'scripts') (Join-Path 'lib' 'Common.ps1'))
. (Join-Path (Join-Path $repo 'scripts') (Join-Path 'lib' 'Tools.ps1'))

$catalog = Get-Catalog
$Group = @($Group | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
Update-SessionPath
$failed = @()

function Test-Item([string] $Label, [bool] $Ok) {
    if ($Ok) { Write-Host "ok      $Label" -ForegroundColor Green }
    else { Write-Host "MISSING $Label" -ForegroundColor Red; $script:failed += $Label }
}

# Metapackages: the requested groups and everything they include.
$metas = New-Object System.Collections.Generic.List[string]
$queue = New-Object System.Collections.Queue
$Group | ForEach-Object { $queue.Enqueue($_) }
while ($queue.Count) {
    $g = $queue.Dequeue()
    if ($metas.Contains($g)) { continue }
    $metas.Add($g)
    $def = $catalog.groups.$g
    if ($def.PSObject.Properties['includes']) { $def.includes | ForEach-Object { $queue.Enqueue($_) } }
}
foreach ($m in $metas) { Test-Item "metapackage $($catalog.bucket.name)/$m" (Test-ScoopApp $m) }

foreach ($tool in (Get-GroupTools -Catalog $catalog -Group $Group)) {
    if ($tool.source -ne 'scoop' -and -not $External) { continue }
    Test-Item ("{0,-13} {1}" -f $tool.source, $tool.package) (Test-ToolInstalled $tool $repo)
    $cmd = Get-ToolProperty $tool 'command'
    if ($cmd) { Test-Item "  command '$cmd'" ([bool](Get-Command $cmd -ErrorAction SilentlyContinue)) }
}

if ($failed.Count) { Write-Host "$($failed.Count) missing: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host 'everything installed' -ForegroundColor Green
