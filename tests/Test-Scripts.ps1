#Requires -Version 5.1
<#
.SYNOPSIS
    Non-destructive tests for scripts/bootstrap.ps1 and scripts/install.ps1:
    argument validation, exit codes and dry runs. Nothing is installed.

.PARAMETER Shell
    PowerShell executable used to run the scripts under test ('pwsh' or 'powershell').

.EXAMPLE
    .\tests\Test-Scripts.ps1
    .\tests\Test-Scripts.ps1 -Shell powershell
#>
[CmdletBinding()]
param([string] $Shell = $(if ($PSVersionTable.PSVersion.Major -ge 6) { 'pwsh' } else { 'powershell' }))

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$install = Join-Path $root 'scripts\install.ps1'
$bootstrap = Join-Path $root 'scripts\bootstrap.ps1'
$status = Join-Path $root 'scripts\status.ps1'
$setup = Join-Path $root 'setup.ps1'
$failures = 0

function Invoke-Case([string] $Name, [int] $ExpectedExit, [string[]] $Arguments, [string] $ExpectOutput) {
    $output = & $Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ok = ($code -eq $ExpectedExit)
    if ($ok -and $ExpectOutput -and ($output -notmatch $ExpectOutput)) { $ok = $false }
    if ($ok) {
        Write-Host "PASS  $Name (exit $code)" -ForegroundColor Green
    } else {
        Write-Host "FAIL  $Name (exit $code, expected $ExpectedExit$(if ($ExpectOutput) { ", output matching '$ExpectOutput'" }))" -ForegroundColor Red
        Write-Host ($output -split "`n" | ForEach-Object { "      $_" } | Out-String)
        $script:failures++
    }
}

Write-Host "Testing with: $Shell"

# --- invalid input -> exit 2, nothing changed
Invoke-Case 'install: unknown group' 2 @($install, '-Group', 'nope') 'Invalid group\(s\): nope'
Invoke-Case 'install: one unknown among valid' 2 @($install, '-Group', 'main,bogus') 'Invalid group\(s\): bogus'
Invoke-Case 'install: empty group' 2 @($install, '-Group', ',') 'Valid groups: main, ai, terminal, utilities, claude-extensions, all'
Invoke-Case 'install: missing catalog' 2 @($install, '-Group', 'main', '-DryRun', '-CatalogPath', 'C:\does\not\exist.json') 'Catalog not found'
Invoke-Case 'bootstrap: unknown bucket' 2 @($bootstrap, '-Bucket', 'nope') 'Unknown bucket'
Invoke-Case 'status: unknown group' 2 @($status, '-Group', 'nope') 'Invalid group\(s\): nope'

# --- missing mandatory parameter -> PowerShell refuses in non-interactive mode
$null = & $Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $install 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host "PASS  install: -Group is mandatory (exit $LASTEXITCODE)" -ForegroundColor Green }
else { Write-Host 'FAIL  install: -Group is mandatory (exit 0)' -ForegroundColor Red; $failures++ }

# --- dry runs -> exit 0 and list the expected tools
Invoke-Case 'dry run: main' 0 @($install, '-Group', 'main', '-DryRun') '6 tool\(s\): gh, git, nodejs, jdk, rustup, docker'
Invoke-Case 'dry run: ai' 0 @($install, '-Group', 'ai', '-DryRun') 'claude-gui.*gemini-cli|gemini-cli'
Invoke-Case 'dry run: case-insensitive + comma list' 0 @($install, '-Group', 'TERMINAL,utilities', '-DryRun') '12 tool\(s\)'
Invoke-Case 'dry run: all = every tool once' 0 @($install, '-Group', 'all', '-DryRun') '34 tool\(s\)'
Invoke-Case 'dry run: all + main does not duplicate' 0 @($install, '-Group', 'all,main', '-DryRun') '34 tool\(s\)'
Invoke-Case 'dry run: claude-extensions' 0 @($install, '-Group', 'claude-extensions', '-DryRun') '10 tool\(s\): commit-commands'
Invoke-Case 'dry run: claude-extensions needs main/claude-code' 0 @($install, '-Group', 'claude-extensions', '-DryRun') 'Buckets needed: main, Heitorgkk'
Invoke-Case 'dry run: -NoWinGet uses the MSIX route' 0 @($install, '-Group', 'ai', '-DryRun', '-NoWinGet') 'chatgpt-gui\s+msix'
Invoke-Case 'dry run: -ScoopOnly drops npm/winget' 0 @($install, '-Group', 'ai', '-DryRun', '-ScoopOnly') '3 tool\(s\): claude-code, codex, opencode'

# --- status.ps1 runs and only reports (0 = all installed, 1 = something missing)
$null = & $Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $status -Group terminal 2>&1
if ($LASTEXITCODE -in 0, 1) { Write-Host "PASS  status: reports (exit $LASTEXITCODE)" -ForegroundColor Green }
else { Write-Host "FAIL  status: exit $LASTEXITCODE" -ForegroundColor Red; $failures++ }

# --- setup.ps1 must parse as a script block (that is how 'irm ... | iex' runs it)
try {
    $null = [scriptblock]::Create((Get-Content -LiteralPath $setup -Raw))
    Write-Host 'PASS  setup: parses as a script block' -ForegroundColor Green
} catch { Write-Host "FAIL  setup: $($_.Exception.Message)" -ForegroundColor Red; $failures++ }

if ($failures) {
    Write-Host "$failures test(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'All script tests passed' -ForegroundColor Green
exit 0
