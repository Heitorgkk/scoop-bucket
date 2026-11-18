#Requires -Version 5.1
<#
.SYNOPSIS
    Per-source detection and installation helpers (Scoop, npm, WinGet, direct MSIX,
    Claude Code plugins and skills). Dot-source after Common.ps1.
.NOTES
    Test-* functions only read state and are shared by install.ps1 and status.ps1.
    Install functions return a status string: installed, updated, up to date, or throw.
#>

Set-StrictMode -Version 3.0

function Invoke-Native {
    <# Runs a native command and returns its exit code and stdout lines. Stderr is discarded.
       ErrorActionPreference is relaxed so Windows PowerShell 5.1 does not turn stderr into terminating errors. #>
    param([string] $FilePath, [string[]] $ArgumentList)
    $ErrorActionPreference = 'Continue'
    $out = & $FilePath @ArgumentList 2>$null
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = @($out | ForEach-Object { "$_" }) }
}

function ConvertFrom-JsonResult($Lines) {
    <# Parses the last JSON object line printed by 'claude ... --json'. #>
    $line = @($Lines | Where-Object { $_.TrimStart().StartsWith('{') }) | Select-Object -Last 1
    if (-not $line) { return $null }
    try { return $line | ConvertFrom-Json } catch { return $null }
}

# ---------------------------------------------------------------------------- prerequisites

function Get-MissingPrerequisite($Tool) {
    return @(@(Get-ToolProperty $Tool 'requires' @()) | Where-Object { -not (Test-ScoopApp (Split-ScoopReference $_).App) })
}

function Install-Prerequisite($Tool) {
    foreach ($req in (Get-MissingPrerequisite $Tool)) {
        Write-Info "Installing prerequisite $req"
        & scoop install $req | Out-Host
        if (-not (Test-ScoopApp (Split-ScoopReference $req).App)) { throw "prerequisite $req could not be installed" }
    }
    Update-SessionPath
}

# ---------------------------------------------------------------------------- npm

function Get-NpmCommand {
    # Prefer npm.cmd: npm.ps1 may be blocked by the execution policy.
    foreach ($name in 'npm.cmd', 'npm') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Test-NpmTool($Tool) {
    $npm = Get-NpmCommand
    if (-not $npm) { return $false }
    return ((Invoke-Native $npm @('ls', '--global', '--depth=0', $Tool.package)).Code -eq 0)
}

# ---------------------------------------------------------------------------- WinGet

$script:WinGetUsable = $null
function Test-WinGetUsable {
    <# winget can exist but be blocked by policy (AppLocker, disabled App Installer); check that it runs. #>
    if ($null -eq $script:WinGetUsable) {
        $script:WinGetUsable = $false
        if (Test-Command winget) {
            try { $script:WinGetUsable = ((Invoke-Native 'winget' @('--version')).Code -eq 0) } catch { $script:WinGetUsable = $false }
        }
    }
    return $script:WinGetUsable
}

function Test-WinGetPackage([string] $Id) {
    if (-not (Test-WinGetUsable)) { return $false }
    return ((Invoke-Native 'winget' @('list', '--id', $Id, '--exact', '--accept-source-agreements', '--disable-interactivity')).Code -eq 0)
}

# ---------------------------------------------------------------------------- MSIX / AppX

$script:AppxReady = $false
function Get-AppxPackageSafe([string] $Name) {
    <# Get-AppxPackage, loading the Appx module through Windows PowerShell compatibility on PowerShell 7. #>
    if (-not (Test-IsWindows)) { return $null }
    if (-not $script:AppxReady) {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            Import-Module Appx -UseWindowsPowerShell -WarningAction SilentlyContinue -ErrorAction Stop
        }
        $script:AppxReady = $true
    }
    return Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Get-DesktopAppVersion($Tool) {
    <# Version of a desktop app installed by any route (MSIX or classic installer), or $null. #>
    $direct = Get-ToolProperty $Tool 'direct'
    if ($direct) {
        $pkg = Get-AppxPackageSafe $direct.appxName
        if ($pkg) { return "$($pkg.Version)" }
        $key = Get-ToolProperty $direct 'uninstallKey'
        if ($key) {
            foreach ($hive in 'HKCU:', 'HKLM:') {
                $path = "$hive\Software\Microsoft\Windows\CurrentVersion\Uninstall\$key"
                if (Test-Path -LiteralPath $path) {
                    $v = (Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue).DisplayVersion
                    if ($v) { return "$v" } else { return 'unknown' }
                }
            }
        }
    }
    if (Test-WinGetPackage $Tool.package) { return 'unknown' }
    return $null
}

function Test-DesktopTool($Tool) { return [bool] (Get-DesktopAppVersion $Tool) }

function Read-MsixIdentity([string] $Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry('AppxManifest.xml')
        if (-not $entry) { throw 'AppxManifest.xml not found: not an MSIX package' }
        $reader = New-Object IO.StreamReader($entry.Open())
        try { [xml] $xml = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $id = $xml.Package.Identity
        return [pscustomobject]@{ Name = $id.Name; Version = $id.Version; Publisher = $id.Publisher }
    } finally { $zip.Dispose() }
}

function Install-DirectMsix($Tool) {
    <# Downloads the vendor's signed MSIX and installs it per user with Add-AppxPackage (no WinGet, no admin). #>
    $direct = $Tool.direct
    $arch = Get-OSArchitecture
    $url = Get-ToolProperty $direct.url $arch
    if (-not $url) { $url = $direct.url.x64 }   # Windows 11 on ARM runs x64 packages
    $file = Join-Path ([IO.Path]::GetTempPath()) ("{0}-{1}-{2}.msix" -f $Tool.name, $arch, $PID)
    try {
        Write-Info "Downloading $url"
        $oldProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with a progress bar on 5.1
        try { Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing } finally { $ProgressPreference = $oldProgress }

        $identity = Read-MsixIdentity $file
        if ($identity.Name -ne $direct.appxName) { throw "downloaded package is '$($identity.Name)', expected '$($direct.appxName)'" }
        # Windows only installs an MSIX whose signing certificate subject equals the manifest Publisher,
        # so pinning the publisher pins the signer. Store-signed packages use a GUID publisher.
        $publisher = Get-ToolProperty $direct 'publisher'
        $signer = Get-ToolProperty $direct 'signer'
        if ($publisher -and $identity.Publisher -ne $publisher) { throw "unexpected publisher '$($identity.Publisher)' (expected '$publisher')" }
        if ($signer -and $identity.Publisher -notmatch [regex]::Escape($signer)) { throw "unexpected publisher '$($identity.Publisher)'" }
        $sig = Get-AuthenticodeSignature -LiteralPath $file
        if ($sig.Status -eq 'Valid') {
            $subject = $sig.SignerCertificate.Subject
            if (($publisher -and $subject -ne $publisher) -or ($signer -and $subject -notmatch [regex]::Escape($signer))) { throw "unexpected signer '$subject'" }
            Write-Info "Signature valid: $($sig.SignerCertificate.Subject)"
        } elseif ($sig.Status -in 'NotSigned', 'HashMismatch', 'NotTrusted') {
            throw "signature check failed: $($sig.Status)"
        } else {
            Write-Info "Signature status '$($sig.Status)'; Add-AppxPackage will verify the package signature."
        }

        $current = Get-AppxPackageSafe $direct.appxName
        if ($current -and ([version] "$($current.Version)" -ge [version] $identity.Version)) { return 'up to date' }
        Write-Info "Add-AppxPackage $($identity.Name) $($identity.Version)"
        if ($current) { Add-AppxPackage -Path $file -ForceApplicationShutdown -ErrorAction Stop }
        else { Add-AppxPackage -Path $file -ErrorAction Stop }
        if (-not (Get-AppxPackageSafe $direct.appxName)) { throw 'package not registered after Add-AppxPackage' }
        if ($current) { return 'updated' } else { return 'installed' }
    } finally {
        Remove-Item -LiteralPath $file -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------- Claude Code

function Get-ClaudeCommand {
    foreach ($name in 'claude.exe', 'claude') {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

$script:ClaudePlugins = $null
function Get-ClaudePluginIds([switch] $Refresh) {
    if ($Refresh -or $null -eq $script:ClaudePlugins) {
        $claude = Get-ClaudeCommand
        $script:ClaudePlugins = @()
        if ($claude) {
            $r = Invoke-Native $claude @('plugin', 'list', '--json')
            if ($r.Code -eq 0 -and $r.Out) {
                try { $script:ClaudePlugins = @(($r.Out -join "`n") | ConvertFrom-Json | ForEach-Object { $_.id }) } catch { $script:ClaudePlugins = @() }
            }
        }
    }
    return $script:ClaudePlugins
}

function Test-ClaudePluginTool($Tool) { return ((Get-ClaudePluginIds) -contains $Tool.package) }

$script:ClaudeMarketplacesReady = @{}
function Confirm-ClaudeMarketplace([string] $Claude, [string] $Name, [string] $Repo, [switch] $Refresh) {
    if ($script:ClaudeMarketplacesReady.ContainsKey($Name)) { return }
    $list = Invoke-Native $Claude @('plugin', 'marketplace', 'list', '--json')
    $names = @()
    if ($list.Code -eq 0 -and $list.Out) { try { $names = @(($list.Out -join "`n") | ConvertFrom-Json | ForEach-Object { $_.name }) } catch { $names = @() } }
    if ($names -notcontains $Name) {
        Write-Info "claude plugin marketplace add $Repo"
        $r = ConvertFrom-JsonResult (Invoke-Native $Claude @('plugin', 'marketplace', 'add', $Repo, '--json')).Out
        if (-not $r -or $r.outcome -ne 'ok') { throw "could not add marketplace $Repo$(if ($r) { ": $($r.message)" })" }
    } elseif ($Refresh) {
        Write-Info "claude plugin marketplace update $Name"
        $null = Invoke-Native $Claude @('plugin', 'marketplace', 'update', $Name, '--json')
    }
    $script:ClaudeMarketplacesReady[$Name] = $true
}

function Install-ClaudePlugin($Tool, $Catalog, [bool] $IsInstalled) {
    $claude = Get-ClaudeCommand
    if (-not $claude) { throw 'claude not found (install main/claude-code)' }
    $marketplace = $Tool.package.Split('@')[1]
    Confirm-ClaudeMarketplace $claude $marketplace $Catalog.claudeMarketplaces.$marketplace -Refresh:$IsInstalled
    if ($IsInstalled) {
        Write-Info "claude plugin update $($Tool.package)"
        $r = ConvertFrom-JsonResult (Invoke-Native $claude @('plugin', 'update', $Tool.package, '--json')).Out
        if (-not $r -or $r.outcome -ne 'ok') { throw "plugin update failed$(if ($r) { ": $($r.message)" })" }
        if ((Get-ToolProperty $r 'updateOutcome') -eq 'up_to_date') { return 'up to date' }
        return 'updated'
    }
    Write-Info "claude plugin install $($Tool.package) --scope user"
    $r = ConvertFrom-JsonResult (Invoke-Native $claude @('plugin', 'install', $Tool.package, '--scope', 'user', '--json')).Out
    if (-not $r -or $r.outcome -ne 'ok') { throw "plugin install failed$(if ($r) { ": $($r.message)" })" }
    $null = Get-ClaudePluginIds -Refresh
    return 'installed'
}

function Get-SkillPaths($Tool, [string] $RepoRoot) {
    $src = Join-Path $RepoRoot ($Tool.package -replace '/', '\')
    $dest = Join-Path (Join-Path (Get-ClaudeConfigDir) 'skills') (Split-Path -Leaf $src)
    return [pscustomobject]@{ Source = $src; Destination = $dest }
}

function Get-DirectoryHash([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $root = (Resolve-Path -LiteralPath $Path).ProviderPath
    $lines = Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
        "$rel $((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
    }
    return ($lines -join "`n")
}

function Get-SkillState($Tool, [string] $RepoRoot) {
    <# 'missing', 'current' or 'differs'. #>
    $p = Get-SkillPaths $Tool $RepoRoot
    if (-not (Test-Path -LiteralPath (Join-Path $p.Destination 'SKILL.md'))) { return 'missing' }
    if ((Get-DirectoryHash $p.Source) -eq (Get-DirectoryHash $p.Destination)) { return 'current' }
    return 'differs'
}

function Install-ClaudeSkill($Tool, [string] $RepoRoot) {
    $p = Get-SkillPaths $Tool $RepoRoot
    if (-not (Test-Path -LiteralPath (Join-Path $p.Source 'SKILL.md'))) { throw "skill source not found: $($p.Source)" }
    $existed = Test-Path -LiteralPath $p.Destination
    if ($existed) { Remove-Item -LiteralPath $p.Destination -Recurse -Force }
    $parent = Split-Path -Parent $p.Destination
    if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent }
    Copy-Item -LiteralPath $p.Source -Destination $p.Destination -Recurse
    Write-Info "Copied to $($p.Destination)"
    if ($existed) { return 'updated' } else { return 'installed' }
}

# ---------------------------------------------------------------------------- generic

function Test-ToolInstalled($Tool, [string] $RepoRoot) {
    switch ($Tool.source) {
        'scoop' { return (Test-ScoopApp (Split-ScoopReference $Tool.package).App) }
        'npm' { return (Test-NpmTool $Tool) }
        'winget' { return (Test-DesktopTool $Tool) }
        'claude-plugin' { return (Test-ClaudePluginTool $Tool) }
        'claude-skill' { return ((Get-SkillState $Tool $RepoRoot) -ne 'missing') }
    }
    return $false
}
