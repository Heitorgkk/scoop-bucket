#Requires -Version 5.1
<#
.SYNOPSIS
    Installs one or more Heitorgkk tool groups: Scoop packages, npm packages,
    desktop apps (WinGet or the vendor's signed MSIX) and Claude Code plugins/skills.

.DESCRIPTION
    1. Validates the requested group(s) against groups.json.
    2. Runs bootstrap.ps1 to make sure Scoop, Git and the needed buckets are present.
    3. Installs every tool of the group(s), skipping those already installed
       (or upgrading them with -Update):
         - Scoop packages with 'scoop install bucket/app'
         - npm packages with 'npm install -g' (installs main/nodejs-lts first if npm is missing)
         - Claude Code skills by copying them to ~/.claude/skills
         - Claude Code plugins with 'claude plugin install' (adds the marketplace first)
         - desktop apps with 'winget install --exact --source winget'; when WinGet is missing,
           blocked, fails, or -NoWinGet is given, the vendor's signed MSIX is downloaded and
           installed per user with Add-AppxPackage
    4. Registers the Heitorgkk/<group> metapackage, so 'scoop update <group>' later
       picks up tools added to the group.
    5. Prints a summary and exits with 0 (all good), 1 (some tool failed) or 2
       (invalid input / missing prerequisite).

    No step requires administrator rights.

.PARAMETER Group
    One or more groups. See groups.json; currently: main, ai, terminal, utilities,
    claude-extensions, all.

.PARAMETER Update
    Upgrade tools that are already installed instead of skipping them.

.PARAMETER ScoopOnly
    Only handle Scoop packages; skip npm, desktop apps and Claude plugins/skills.

.PARAMETER NoWinGet
    Never use WinGet: install desktop apps from the vendor's official MSIX instead.

.PARAMETER DryRun
    Show what would be done without changing anything (no buckets added, nothing installed).

.PARAMETER BucketSource
    Passed to bootstrap.ps1: git URL or local path of the Heitorgkk bucket.

.EXAMPLE
    .\scripts\install.ps1 -Group main

.EXAMPLE
    .\scripts\install.ps1 -Group ai,terminal -DryRun

.EXAMPLE
    .\scripts\install.ps1 -Group all -Update
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Update', Justification = 'Read by the helper functions in script scope.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'NoWinGet', Justification = 'Read by the helper functions in script scope.')]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]] $Group,
    [switch] $Update,
    [switch] $ScoopOnly,
    [switch] $NoWinGet,
    [switch] $DryRun,
    [string] $BucketSource,
    [string] $CatalogPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
. (Join-Path $PSScriptRoot 'lib\Tools.ps1')

# WinGet exit codes that mean "nothing to do" rather than failure.
$WINGET_NO_UPDATE = -1978335189          # 0x8A15002B  no applicable upgrade
$WINGET_ALREADY_INSTALLED = -1978335135  # 0x8A150061  package already installed

$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string] $Name, [string] $Source, [string] $Status, [string] $Detail = '') {
    $results.Add([pscustomobject]@{ Tool = $Name; Source = $Source; Status = $Status; Detail = $Detail })
    switch ($Status) {
        'failed' { Write-Fail "$Name - $Detail" }
        { $_ -in 'installed', 'updated' } { Write-Ok "$Name $Status." }
        default { Write-Skip "$Name - $Status$(if ($Detail) { " ($Detail)" })" }
    }
}

# ---------------------------------------------------------------------------- Scoop

function Invoke-ScoopTool($Tool) {
    $ref = Split-ScoopReference $Tool.package
    $installed = Test-ScoopApp $ref.App
    if ($installed -and -not $Update) { Add-Result $Tool.name 'scoop' 'already installed' $Tool.package; return }
    if ($DryRun) { Add-Result $Tool.name 'scoop' $(if ($installed) { 'would update' } else { 'would install' }) $Tool.package; return }

    if ($installed) {
        Write-Info "scoop update $($ref.App)"
        & scoop update $ref.App | Out-Host
        if ($LASTEXITCODE -eq 0) { Add-Result $Tool.name 'scoop' 'updated' $Tool.package }
        else { Add-Result $Tool.name 'scoop' 'failed' "scoop update exited with $LASTEXITCODE" }
        return
    }
    Write-Info "scoop install $($Tool.package)"
    & scoop install $Tool.package | Out-Host
    # 'scoop install' exits 0 even when the app failed, so check what is on disk.
    if (Test-ScoopApp $ref.App) { Add-Result $Tool.name 'scoop' 'installed' $Tool.package }
    else { Add-Result $Tool.name 'scoop' 'failed' "scoop install $($Tool.package) did not complete" }
}

# ---------------------------------------------------------------------------- npm

function Invoke-NpmTool($Tool) {
    if (-not (Get-NpmCommand)) {
        if ($DryRun) {
            Add-Result $Tool.name 'npm' 'would install' "after: $((Get-MissingPrerequisite $Tool) -join ', ')"
            return
        }
        Install-Prerequisite $Tool
        if (-not (Get-NpmCommand)) { Add-Result $Tool.name 'npm' 'failed' "npm not found (prerequisite: $((Get-ToolProperty $Tool 'requires' @()) -join ', '))"; return }
    }
    $npm = Get-NpmCommand
    $installed = Test-NpmTool $Tool
    if ($installed -and -not $Update) { Add-Result $Tool.name 'npm' 'already installed' $Tool.package; return }
    if ($DryRun) { Add-Result $Tool.name 'npm' $(if ($installed) { 'would update' } else { 'would install' }) $Tool.package; return }

    # 'npm install -g pkg@latest' both installs and upgrades (npm update -g ignores major bumps).
    Write-Info "npm install --global $($Tool.package)@latest"
    & $npm install --global "$($Tool.package)@latest" | Out-Host
    $code = $LASTEXITCODE
    if ($code -eq 0 -and (Test-NpmTool $Tool)) {
        Add-Result $Tool.name 'npm' $(if ($installed) { 'updated' } else { 'installed' }) $Tool.package
    } else {
        Add-Result $Tool.name 'npm' 'failed' "npm exited with $code"
    }
}

# ---------------------------------------------------------------------------- desktop apps (WinGet / MSIX)

function Install-WithWinGet($Tool, [bool] $IsInstalled) {
    $verb = if ($IsInstalled) { 'upgrade' } else { 'install' }
    $wingetArgs = @($verb, '--id', $Tool.package, '--exact', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity', '--silent')
    Write-Info "winget $($wingetArgs -join ' ')"
    & winget @wingetArgs | Out-Host
    $code = $LASTEXITCODE
    if ($code -eq 0) { if ($IsInstalled) { return 'updated' } else { return 'installed' } }
    if ($code -eq $WINGET_NO_UPDATE -or $code -eq $WINGET_ALREADY_INSTALLED) { return 'up to date' }
    throw ('winget exited with 0x{0:X8}' -f $code)
}

function Invoke-DesktopTool($Tool) {
    $direct = Get-ToolProperty $Tool 'direct'
    $useWinGet = (-not $NoWinGet) -and (Test-WinGetUsable)
    $route = if ($useWinGet) { 'winget' } elseif ($direct) { 'msix' } else { $null }
    $label = if ($route -eq 'msix') { "msix ($($direct.appxName))" } else { $Tool.package }

    $installed = Test-DesktopTool $Tool
    if ($installed -and -not $Update) { Add-Result $Tool.name $(if ($route) { $route } else { 'winget' }) 'already installed' $label; return }
    if (-not $route) {
        $why = if ($NoWinGet) { '-NoWinGet was given' } else { 'winget is not available' }
        $status = if ($DryRun) { 'blocked' } else { 'failed' }
        Add-Result $Tool.name 'winget' $status "$why and the tool has no direct download (see https://aka.ms/getwinget)"
        return
    }
    if ($DryRun) { Add-Result $Tool.name $route $(if ($installed) { 'would update' } else { 'would install' }) $label; return }

    if ($route -eq 'winget') {
        try {
            Add-Result $Tool.name 'winget' (Install-WithWinGet $Tool $installed) $Tool.package
            return
        } catch {
            if (-not $direct) { throw }
            Write-Warn "WinGet failed ($($_.Exception.Message)); falling back to the official MSIX."
        }
    }
    Add-Result $Tool.name 'msix' (Install-DirectMsix $Tool) "$($direct.appxName) from $((Get-ToolProperty $direct.url (Get-OSArchitecture)) -replace '^https://([^/]+)/.*$', '$1')"
}

# ---------------------------------------------------------------------------- Claude Code

function Invoke-ClaudePluginTool($Tool) {
    if (-not (Get-ClaudeCommand)) {
        if ($DryRun) { Add-Result $Tool.name 'claude-plugin' 'would install' "after: $((Get-MissingPrerequisite $Tool) -join ', ')"; return }
        Install-Prerequisite $Tool
        if (-not (Get-ClaudeCommand)) { Add-Result $Tool.name 'claude-plugin' 'failed' 'claude not found after installing main/claude-code'; return }
    }
    $installed = Test-ClaudePluginTool $Tool
    if ($installed -and -not $Update) { Add-Result $Tool.name 'claude-plugin' 'already installed' $Tool.package; return }
    if ($DryRun) { Add-Result $Tool.name 'claude-plugin' $(if ($installed) { 'would update' } else { 'would install' }) $Tool.package; return }
    Add-Result $Tool.name 'claude-plugin' (Install-ClaudePlugin $Tool $catalog $installed) $Tool.package
}

function Invoke-ClaudeSkillTool($Tool) {
    $state = Get-SkillState $Tool $repoRoot
    $dest = (Get-SkillPaths $Tool $repoRoot).Destination
    if ($state -eq 'current') { Add-Result $Tool.name 'claude-skill' $(if ($Update) { 'up to date' } else { 'already installed' }) $dest; return }
    if ($state -eq 'differs' -and -not $Update) { Add-Result $Tool.name 'claude-skill' 'already installed' 'local copy differs; -Update overwrites it'; return }
    if ($DryRun) { Add-Result $Tool.name 'claude-skill' $(if ($state -eq 'missing') { 'would install' } else { 'would update' }) $dest; return }
    Add-Result $Tool.name 'claude-skill' (Install-ClaudeSkill $Tool $repoRoot) $dest
}

# ---------------------------------------------------------------------------- metapackages

function Invoke-Metapackage([string] $Bucket, [string] $Name) {
    $label = "$Bucket/$Name"
    $installed = Test-ScoopApp $Name
    if ($DryRun) { Add-Result $label 'scoop' $(if ($installed) { 'registered' } else { 'would register' }) 'metapackage'; return }
    if ($installed) {
        if (-not $Update) { Add-Result $label 'scoop' 'already installed' 'metapackage'; return }
        & scoop update $Name | Out-Host
        if ($LASTEXITCODE -eq 0) { Add-Result $label 'scoop' 'updated' 'metapackage' }
        else { Add-Result $label 'scoop' 'failed' "scoop update exited with $LASTEXITCODE" }
        return
    }
    & scoop install $label | Out-Host
    if (Test-ScoopApp $Name) { Add-Result $label 'scoop' 'installed' 'metapackage' }
    else { Add-Result $label 'scoop' 'failed' 'metapackage could not be registered' }
}

# ---------------------------------------------------------------------------- main
try {
    if ($CatalogPath) { $catalog = Get-Catalog -Path $CatalogPath } else { $catalog = Get-Catalog }
    $repoRoot = $script:RepoRoot
    if ($CatalogPath) { $repoRoot = Split-Path -Parent (Resolve-Path -LiteralPath $CatalogPath).ProviderPath }
    $valid = Get-GroupNames $catalog
    $Group = @($Group | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { $_ } | Select-Object -Unique)
    $invalid = @($Group | Where-Object { $valid -notcontains $_ })
    if ($invalid.Count -or -not $Group.Count) {
        Write-Fail "Invalid group(s): $($invalid -join ', '). Valid groups: $($valid -join ', ')."
        exit $EXIT_USAGE
    }
    if (-not (Test-IsWindows) -and -not $DryRun) {
        Write-Fail 'This script installs Windows software; it only runs on Windows (use -DryRun elsewhere).'
        exit $EXIT_USAGE
    }

    $tools = Get-GroupTools -Catalog $catalog -Group $Group
    if ($ScoopOnly) { $tools = @($tools | Where-Object { $_.source -eq 'scoop' }) }
    $own = $catalog.bucket.name

    # Buckets needed by the Scoop packages (and npm prerequisites) of the selected groups.
    $buckets = @($tools | ForEach-Object {
            if ($_.source -eq 'scoop') { $_.package }
            Get-ToolProperty $_ 'requires' @()
        } | ForEach-Object { (Split-ScoopReference $_).Bucket } | Where-Object { $_ -ne $own } | Select-Object -Unique)

    Write-Section "Heitorgkk installer - group(s): $($Group -join ', ')$(if ($DryRun) { ' [dry run]' })"
    Write-Info ("{0} tool(s): {1}" -f $tools.Count, (($tools | ForEach-Object { $_.name }) -join ', '))
    Write-Info "Buckets needed: $((@($buckets) + $own) -join ', ')"
    if (Test-IsElevated) { Write-Warn 'Running elevated is not needed and not recommended for Scoop.' }

    if ($DryRun) {
        Write-Skip 'Dry run: buckets are not added.'
    } else {
        $bootstrapArgs = @{ Bucket = $buckets }
        if ($BucketSource) { $bootstrapArgs.BucketSource = $BucketSource }
        if ($CatalogPath) { $bootstrapArgs.CatalogPath = $CatalogPath }
        & (Join-Path $PSScriptRoot 'bootstrap.ps1') @bootstrapArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "bootstrap.ps1 failed (exit code $LASTEXITCODE); nothing was installed."
            exit $EXIT_USAGE
        }
    }

    # Scoop first (nodejs/claude-code must exist before npm tools and plugins), then the rest.
    $order = 'scoop', 'npm', 'claude-skill', 'claude-plugin', 'winget'
    $tools = @(foreach ($src in $order) { $tools | Where-Object { $_.source -eq $src } })
    $i = 0
    foreach ($tool in $tools) {
        $i++
        Write-Section ("[{0}/{1}] {2} ({3}: {4})" -f $i, $tools.Count, $tool.name, $tool.source, $tool.package)
        try {
            switch ($tool.source) {
                'scoop' { Invoke-ScoopTool $tool }
                'npm' { Invoke-NpmTool $tool }
                'winget' { Invoke-DesktopTool $tool }
                'claude-plugin' { Invoke-ClaudePluginTool $tool }
                'claude-skill' { Invoke-ClaudeSkillTool $tool }
                default { Add-Result $tool.name $tool.source 'failed' "unknown source '$($tool.source)'" }
            }
        } catch {
            Add-Result $tool.name $tool.source 'failed' $_.Exception.Message
        }
        if (-not $DryRun) { Update-SessionPath }
    }

    Write-Section 'Registering metapackages'
    $scoopFailures = @($results | Where-Object { $_.Status -eq 'failed' -and $_.Source -eq 'scoop' })
    foreach ($g in $Group) {
        if ($scoopFailures.Count) {
            Add-Result "$own/$g" 'scoop' 'skipped' 'a Scoop package of this run failed'
            continue
        }
        try { Invoke-Metapackage $own $g } catch { Add-Result "$own/$g" 'scoop' 'failed' $_.Exception.Message }
    }

    Write-Section 'Summary'
    $results | Format-Table -AutoSize Tool, Source, Status, Detail | Out-Host
    $failures = @($results | Where-Object { $_.Status -eq 'failed' })
    if ($failures.Count) {
        Write-Fail "$($failures.Count) item(s) failed: $(($failures | ForEach-Object { $_.Tool }) -join ', ')"
        exit $EXIT_FAILURES
    }
    Write-Ok 'All done. Open a new terminal so PATH changes take effect everywhere.'
    exit $EXIT_OK
} catch {
    Write-Fail $_.Exception.Message
    exit $EXIT_USAGE
}
