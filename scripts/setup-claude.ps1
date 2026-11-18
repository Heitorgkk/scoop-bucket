#Requires -Version 5.1
<#
.SYNOPSIS
    Installs, configures and checks the Claude Code token/context pipeline (group 'claude-tools'):
    RTK, Graphify, Headroom MCP, Ponytail and Context Mode.

.DESCRIPTION
    A thin front end for the 'claude-tools' group of groups.json, so nothing is installed in two places:

        .\scripts\setup-claude.ps1           install/configure what is missing, then report
        .\scripts\setup-claude.ps1 -Update   also upgrade uv tools, plugins and the Scoop packages
        .\scripts\setup-claude.ps1 -Check    report only; changes nothing

    Installing is done by install.ps1 -Group claude-tools:
      1. Scoop: main/uv, main/rtk (plus main/claude-code and main/git when missing).
      2. uv tools: graphifyy, headroom-ai[mcp] (Python 3.13, downloaded by uv when missing).
         A graphify/headroom already on PATH from pip is left alone.
      3. Plugins (user scope): ponytail@ponytail, context-mode@context-mode; their marketplaces
         are added only when not registered yet.
      4. Integrations, each only when not configured yet:
           rtk init -g --auto-patch --no-trust-filters
           graphify install                       (also re-run with -Update; idempotent)
           headroom mcp install --agent claude    (MCP server only)

    Never done: starting 'headroom proxy' or rtk-proxy, setting ANTHROPIC_BASE_URL, scheduled tasks,
    background services, or removing anything that this pipeline did not create.

.PARAMETER Check
    Only verify and print the report. Nothing is installed or modified.

.PARAMETER Update
    Upgrade the tools and plugins managed by the pipeline (cannot be combined with -Check).

.PARAMETER BucketSource
    Passed to install.ps1 (git URL or local path of the Heitorgkk bucket).

.NOTES
    Exit codes: 0 = SUCCESS, 1 = PARTIAL/FAILED (see the report), 2 = invalid arguments.
    Live MCP connections and plugin health can only be checked inside Claude Code: /mcp, /ctx-doctor.
#>
[CmdletBinding()]
param(
    [switch] $Check,
    [switch] $Update,
    [string] $BucketSource,
    [string] $CatalogPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')
. (Join-Path $PSScriptRoot 'lib\Tools.ps1')
. (Join-Path $PSScriptRoot 'lib\Integrations.ps1')

$GroupName = 'claude-tools'

function Write-ReportLine([string] $Status, [string] $Label, [string] $Detail) {
    $color = @{ OK = 'Green'; WARNING = 'Yellow'; FAILED = 'Red'; SKIPPED = 'DarkGray' }[$Status]
    $tag = '[{0}]' -f $Status
    Write-Host ('{0,-10} {1,-28} {2}' -f $tag, $Label, $Detail) -ForegroundColor $color
}

function Get-PipelineReport($Catalog, [string] $RepoRoot) {
    <# One row per component: CLI/plugin installed, then its integration. Read-only. #>
    $null = Get-ClaudePluginIds -Refresh
    $null = Get-UvToolNames -Refresh
    foreach ($tool in (Get-GroupTools -Catalog $Catalog -Group $GroupName)) {
        $kind = if ($tool.source -eq 'claude-plugin') { 'plugin' } else { 'CLI' }
        $installed = $false
        try { $installed = Test-ToolInstalled $tool $RepoRoot } catch { $installed = $false }
        $detail = $tool.package
        $status = if ($installed) { 'OK' } else { 'FAILED' }
        if ($tool.source -eq 'uv-tool' -and $installed -and (Get-UvToolState $tool) -eq 'external') {
            $status = 'WARNING'
            $detail = "on PATH but not managed by uv ($((Get-Command $tool.command -CommandType Application | Select-Object -First 1).Source))"
        }
        [pscustomobject]@{ Label = "$($tool.name) $kind"; Status = $status; Detail = $detail }

        if (Get-ToolProperty $tool 'integration') {
            $label = "$($tool.name) $(if ($tool.integration -eq 'headroom-mcp') { 'MCP configuration' } else { 'integration' })"
            if (-not $installed) { [pscustomobject]@{ Label = $label; Status = 'SKIPPED'; Detail = "needs $($tool.name)" }; continue }
            $state = try { Get-IntegrationState $tool } catch { New-IntegrationState 'missing' $_.Exception.Message }
            $s = switch ($state.State) { 'configured' { 'OK' } 'blocked' { 'SKIPPED' } default { 'FAILED' } }
            [pscustomobject]@{ Label = $label; Status = $s; Detail = $state.Detail }
        }
    }
}

try {
    if ($Check -and $Update) {
        Write-Fail '-Check and -Update cannot be combined (-Check never changes anything).'
        exit $EXIT_USAGE
    }
    if ($CatalogPath) { $catalog = Get-Catalog -Path $CatalogPath } else { $catalog = Get-Catalog }
    $repoRoot = $script:RepoRoot
    if ($CatalogPath) { $repoRoot = Split-Path -Parent (Resolve-Path -LiteralPath $CatalogPath).ProviderPath }
    if (-not $catalog.groups.PSObject.Properties[$GroupName]) { throw "group '$GroupName' not found in the catalog" }

    $tools = Get-GroupTools -Catalog $catalog -Group $GroupName
    Write-Section "Claude Code setup ($(if ($Check) { 'check only' } elseif ($Update) { 'install + update' } else { 'install missing' }))"
    Write-Info ("Components: {0}" -f (($tools | ForEach-Object { $_.name }) -join ', '))
    Write-Info 'Scope: user (works in every project). Headroom proxy and ANTHROPIC_BASE_URL are never touched.'

    # Prerequisites that this script cannot install itself.
    if (-not (Test-IsWindows)) { Write-Fail 'Windows only.'; exit $EXIT_USAGE }
    if (-not (Test-Command scoop)) {
        Write-Fail 'Scoop not found. Run .\scripts\bootstrap.ps1 -InstallScoop (or setup.ps1) first.'
        exit $EXIT_USAGE
    }
    Write-Info "PowerShell $($PSVersionTable.PSVersion); Claude Code: $(if (Get-ClaudeCommand) { (Invoke-Native (Get-ClaudeCommand) @('--version')).Out | Select-Object -First 1 } else { 'not installed yet (installed with main/claude-code)' })"

    $installCode = $EXIT_OK
    if (-not $Check) {
        $installArgs = @{ Group = @($GroupName); Update = $Update }
        if ($BucketSource) { $installArgs.BucketSource = $BucketSource }
        if ($CatalogPath) { $installArgs.CatalogPath = $CatalogPath }
        & (Join-Path $PSScriptRoot 'install.ps1') @installArgs
        $installCode = $LASTEXITCODE
        Update-SessionPath
        if ($installCode -eq $EXIT_USAGE) { Write-Warn 'install.ps1 stopped before installing anything (see above).' }
    } else {
        Update-SessionPath
    }

    # ------------------------------------------------------------------ report
    Write-Host ''
    Write-Host 'Claude Code Setup' -ForegroundColor Cyan
    Write-Host ''
    $rows = @(Get-PipelineReport $catalog $repoRoot)
    foreach ($r in $rows) { Write-ReportLine $r.Status $r.Label $r.Detail }

    $baseUrl = Get-AnthropicBaseUrl
    Write-Host ''
    Write-Info 'MCP live connection: verify inside Claude Code with /mcp (Context Mode: /ctx-doctor)'
    $proxy = 'not started (optional, by design)'
    if ((Format-AnthropicBaseUrl $baseUrl) -ne 'not set') {
        $proxy = "ANTHROPIC_BASE_URL is set ($(Format-AnthropicBaseUrl $baseUrl)); this pipeline did not set it"
        $rows += [pscustomobject]@{ Label = 'ANTHROPIC_BASE_URL'; Status = 'WARNING'; Detail = $proxy }
    }
    Write-Info "Headroom proxy: $proxy"
    Write-Info 'On demand inside Claude Code: /graphify .   /ctx-stats   /ctx-doctor   /mcp'
    Write-Info 'Restart Claude Code to load new hooks, plugins and MCP servers.'

    $failed = @($rows | Where-Object { $_.Status -eq 'FAILED' })
    $warned = @($rows | Where-Object { $_.Status -eq 'WARNING' })
    $okCount = @($rows | Where-Object { $_.Status -eq 'OK' }).Count
    $result = if (-not $failed.Count -and $installCode -eq $EXIT_OK) { 'SUCCESS' }
    elseif ($okCount -eq 0) { 'FAILED' }
    else { 'PARTIAL' }
    Write-Host ''
    $color = @{ SUCCESS = 'Green'; PARTIAL = 'Yellow'; FAILED = 'Red' }[$result]
    Write-Host "Result: $result$(if ($warned.Count) { " ($($warned.Count) warning(s))" })" -ForegroundColor $color
    if ($failed.Count -and $Check) { Write-Host 'Fix with: .\scripts\setup-claude.ps1' }
    if ($result -eq 'SUCCESS') { exit $EXIT_OK }
    exit $EXIT_FAILURES
} catch {
    Write-Fail $_.Exception.Message
    exit $EXIT_USAGE
}
