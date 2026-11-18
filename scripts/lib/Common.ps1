#Requires -Version 5.1
<#
.SYNOPSIS
    Shared helpers for bootstrap.ps1 and install.ps1. Dot-source this file.
.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
    The group/tool data lives in ..\..\groups.json (single source of truth).
#>

Set-StrictMode -Version 3.0

# Exit codes shared by every script in this folder.
$script:EXIT_OK = 0           # everything succeeded
$script:EXIT_FAILURES = 1     # ran, but at least one item failed
$script:EXIT_USAGE = 2        # invalid arguments or missing prerequisite; nothing was changed

# Common.ps1 lives in scripts\lib; the catalog lives in the repository root.
$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:DefaultCatalogPath = Join-Path $script:RepoRoot 'groups.json'

function Write-Section([string] $Text) {
    Write-Host ''
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Info([string] $Text) { Write-Host "    $Text" }
function Write-Ok([string] $Text) { Write-Host "    [ OK ] $Text" -ForegroundColor Green }
function Write-Skip([string] $Text) { Write-Host "    [SKIP] $Text" -ForegroundColor DarkGray }
function Write-Warn([string] $Text) { Write-Host "    [WARN] $Text" -ForegroundColor Yellow }
function Write-Fail([string] $Text) { Write-Host "    [FAIL] $Text" -ForegroundColor Red }

function Test-IsWindows {
    # $IsWindows does not exist in Windows PowerShell 5.1 (which only runs on Windows).
    if ($PSVersionTable.PSVersion.Major -lt 6) { return $true }
    return [bool] $IsWindows
}

function Test-IsElevated {
    if (-not (Test-IsWindows)) { return $false }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Command([string] $Name) {
    return [bool] (Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Get-Catalog {
    param([string] $Path = $script:DefaultCatalogPath)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Catalog not found: $Path"
    }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "Catalog '$Path' is not valid JSON: $($_.Exception.Message)"
    }
}

function Get-GroupNames($Catalog) {
    return @($Catalog.groups.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-GroupTools {
    <# Returns the tools of one or more groups, expanding 'includes' and removing duplicates (first wins). #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Catalog', Justification = 'Used inside the $visit script block.')]
    param($Catalog, [string[]] $Group)
    $seen = @{}
    $result = New-Object System.Collections.Generic.List[object]
    $visit = {
        param([string] $Name, [string[]] $Path)
        if ($Path -contains $Name) { throw "Circular group include: $(($Path + $Name) -join ' -> ')" }
        $g = $Catalog.groups.$Name
        $groupRequires = @()
        if ($g.PSObject.Properties['requires']) { $groupRequires = @($g.requires) }
        if ($g.PSObject.Properties['tools']) {
            foreach ($t in $g.tools) {
                if (-not $seen.ContainsKey($t.name)) {
                    $seen[$t.name] = $true
                    # Tools inherit their group's prerequisites (e.g. plugins need main/claude-code).
                    if ($groupRequires.Count) {
                        $own = @()
                        if ($t.PSObject.Properties['requires']) { $own = @($t.requires) }
                        $t = $t.PSObject.Copy()
                        $t | Add-Member -NotePropertyName requires -NotePropertyValue @(@($own) + $groupRequires | Select-Object -Unique) -Force
                    }
                    $result.Add($t)
                }
            }
        }
        if ($g.PSObject.Properties['includes']) {
            foreach ($inc in $g.includes) { & $visit $inc ($Path + $Name) }
        }
    }
    foreach ($name in $Group) { & $visit $name @() }
    return , $result.ToArray()
}

function Get-ClaudeConfigDir {
    if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR }
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    return Join-Path $userHome '.claude'
}

function Get-OSArchitecture {
    <# 'x64' or 'arm64' for the OS (not the current process). #>
    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    if ($arch -eq 'ARM64') { return 'arm64' }
    return 'x64'
}

function Get-ToolProperty($Tool, [string] $Name, $Default = $null) {
    if ($Tool.PSObject.Properties[$Name]) { return $Tool.$Name }
    return $Default
}

function Get-ScoopRoot {
    if ($env:SCOOP) { return $env:SCOOP }
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    return Join-Path $userHome 'scoop'
}

function Get-ScoopGlobalRoot {
    if ($env:SCOOP_GLOBAL) { return $env:SCOOP_GLOBAL }
    if ($env:ProgramData) { return Join-Path $env:ProgramData 'scoop' }
    return $null
}

function Split-ScoopReference([string] $Reference) {
    $parts = $Reference.Split('/')
    if ($parts.Count -ne 2) { throw "Invalid Scoop reference '$Reference' (expected bucket/package)" }
    return [pscustomobject]@{ Bucket = $parts[0]; App = $parts[1] }
}

function Test-ScoopApp([string] $App) {
    <# True when a Scoop app is installed (user or global scope). Uses the files Scoop writes on success. #>
    # Scoop writes scoop-install.json (install.json before v0.6.0) as the last step of a successful install.
    foreach ($root in @((Get-ScoopRoot), (Get-ScoopGlobalRoot))) {
        if (-not $root) { continue }
        $current = Join-Path $root "apps\$App\current"
        foreach ($file in 'scoop-install.json', 'install.json') {
            if (Test-Path -LiteralPath (Join-Path $current $file)) { return $true }
        }
    }
    return $false
}

function Test-ScoopBucket([string] $Name) {
    return Test-Path -LiteralPath (Join-Path (Get-ScoopRoot) "buckets\$Name")
}

function Get-ScoopBucketRemote([string] $Name) {
    $dir = Join-Path (Get-ScoopRoot) "buckets\$Name"
    if (-not (Test-Path -LiteralPath (Join-Path $dir '.git'))) { return $null }
    if (-not (Test-Command git)) { return $null }
    $url = & git -C $dir config --get remote.origin.url 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return "$url".Trim()
}

function ConvertTo-NormalizedRepo([string] $Uri) {
    if (-not $Uri) { return '' }
    $u = $Uri.Trim().TrimEnd('/')
    if ($u -match '\.git$') { $u = $u.Substring(0, $u.Length - 4) }
    $u = $u -replace '^git@github\.com:', 'https://github.com/'
    return $u.ToLowerInvariant()
}

function Update-SessionPath {
    <# Scoop/npm/WinGet change the user PATH in the registry; make new commands visible in this session. #>
    if (-not (Test-IsWindows)) { return }
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = New-Object System.Collections.Generic.List[string]
    foreach ($p in (@($machine, $user, $env:Path) -join ';').Split(';')) {
        $p = $p.Trim()
        if ($p -and -not $entries.Contains($p)) { $entries.Add($p) }
    }
    $env:Path = $entries -join ';'
    # main/uv points its tool/Python dirs into ~\scoop\persist\uv; without these a fresh session
    # would install uv tools into ~\.local\bin, which is not on PATH.
    foreach ($name in 'JAVA_HOME', 'CARGO_HOME', 'RUSTUP_HOME', 'UV_TOOL_DIR', 'UV_TOOL_BIN_DIR', 'UV_PYTHON_INSTALL_DIR', 'UV_PYTHON_BIN_DIR', 'UV_CACHE_DIR') {
        $value = [Environment]::GetEnvironmentVariable($name, 'User')
        if ($value) { Set-Item -Path "Env:$name" -Value $value }
    }
}
