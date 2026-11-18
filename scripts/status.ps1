#Requires -Version 5.1
<#
.SYNOPSIS
    Shows which tools of the Heitorgkk catalog are installed. Changes nothing.

.PARAMETER Group
    Groups to show (default: every group except 'all', which only aggregates the others).

.PARAMETER MissingOnly
    Only list tools that are not installed.

.EXAMPLE
    .\scripts\status.ps1

.EXAMPLE
    .\scripts\status.ps1 -Group ai -MissingOnly

.NOTES
    Exit codes: 0 = everything shown is installed, 1 = something is missing, 2 = invalid input.
#>
[CmdletBinding()]
param(
    [string[]] $Group,
    [switch] $MissingOnly,
    [string] $CatalogPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
. (Join-Path $PSScriptRoot 'lib\Tools.ps1')

try {
    if ($CatalogPath) { $catalog = Get-Catalog -Path $CatalogPath } else { $catalog = Get-Catalog }
    $repoRoot = $script:RepoRoot
    if ($CatalogPath) { $repoRoot = Split-Path -Parent (Resolve-Path -LiteralPath $CatalogPath).ProviderPath }
    $valid = Get-GroupNames $catalog
    if (-not $Group) { $Group = @($valid | Where-Object { $_ -ne 'all' }) }
    $Group = @($Group | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    $invalid = @($Group | Where-Object { $valid -notcontains $_ })
    if ($invalid.Count) {
        Write-Fail "Invalid group(s): $($invalid -join ', '). Valid groups: $($valid -join ', ')."
        exit $EXIT_USAGE
    }

    $rows = foreach ($g in $Group) {
        foreach ($tool in (Get-GroupTools -Catalog $catalog -Group $g)) {
            $ok = $false
            try { $ok = Test-ToolInstalled $tool $repoRoot } catch { $ok = $false }
            [pscustomobject]@{ Group = $g; Tool = $tool.name; Source = $tool.source; Package = $tool.package; Installed = $(if ($ok) { 'yes' } else { 'NO' }) }
        }
        $meta = Test-ScoopApp $g
        [pscustomobject]@{ Group = $g; Tool = "$($catalog.bucket.name)/$g"; Source = 'scoop'; Package = 'metapackage'; Installed = $(if ($meta) { 'yes' } else { 'NO' }) }
    }
    $missing = @($rows | Where-Object { $_.Installed -eq 'NO' })
    $shown = if ($MissingOnly) { $missing } else { $rows }
    $shown | Format-Table -AutoSize Group, Tool, Source, Package, Installed | Out-Host
    Write-Host ("{0} of {1} installed." -f (@($rows).Count - $missing.Count), @($rows).Count)
    if ($missing.Count) {
        Write-Host "Install the missing ones with: .\scripts\install.ps1 -Group $($Group -join ',')"
        exit $EXIT_FAILURES
    }
    exit $EXIT_OK
} catch {
    Write-Fail $_.Exception.Message
    exit $EXIT_USAGE
}
