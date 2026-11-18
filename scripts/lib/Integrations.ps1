#Requires -Version 5.1
<#
.SYNOPSIS
    Post-install configuration steps ("integrations") referenced by the 'integration' field of a
    tool in groups.json: rtk, graphify, headroom-mcp and msys2-rust. Dot-source after Tools.ps1.
.NOTES
    Get-IntegrationState only reads state (shared by install.ps1, status.ps1 and setup-claude.ps1).
    Invoke-Integration changes the system and returns a status string or throws.

    Safety rules for every integration:
      - never overwrite Claude Code config files; only the tools' own idempotent installers touch them;
      - never start the Headroom or RTK proxy, never set ANTHROPIC_BASE_URL;
      - commands that are not known to be idempotent only run when the state check says 'missing'.
#>

Set-StrictMode -Version 3.0

$script:GnuToolchain = 'stable-x86_64-pc-windows-gnu'
$script:Msys2Packages = @('mingw-w64-x86_64-gcc', 'mingw-w64-x86_64-pkgconf')

function New-IntegrationState([string] $State, [string] $Detail) {
    <# State: 'configured', 'missing' or 'blocked' (the tool it configures is not installed). #>
    return [pscustomobject]@{ State = $State; Detail = $Detail }
}

function Invoke-PythonCli([string] $Command, [string[]] $ArgumentList) {
    <# Runs a Python CLI with UTF-8 output: their status glyphs crash on a legacy console code page. #>
    $saved = $env:PYTHONIOENCODING, $env:PYTHONUTF8
    $env:PYTHONIOENCODING = 'utf-8'; $env:PYTHONUTF8 = '1'
    try {
        & $Command @ArgumentList | Out-Host
        return $LASTEXITCODE
    } finally { $env:PYTHONIOENCODING, $env:PYTHONUTF8 = $saved }
}

# ---------------------------------------------------------------------------- Claude Code config (read-only)

function Read-JsonFile([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

function Get-ClaudeSettingsPath { return Join-Path (Get-ClaudeConfigDir) 'settings.json' }

function Get-ClaudeStatePath {
    <# ~/.claude.json holds user-scope MCP servers; with CLAUDE_CONFIG_DIR it lives inside that dir. #>
    if ($env:CLAUDE_CONFIG_DIR) { return Join-Path $env:CLAUDE_CONFIG_DIR '.claude.json' }
    $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
    return Join-Path $userHome '.claude.json'
}

function Test-ClaudeUserMcpServer([string] $Name) {
    $state = Read-JsonFile (Get-ClaudeStatePath)
    if (-not $state) { return $false }
    $servers = Get-ToolProperty $state 'mcpServers'
    return [bool] ($servers -and $servers.PSObject.Properties[$Name])
}

function Get-AnthropicBaseUrl {
    <# Every place ANTHROPIC_BASE_URL can be set for Claude Code; used to prove the pipeline left it alone. #>
    $settings = Read-JsonFile (Get-ClaudeSettingsPath)
    $fromSettings = ''
    if ($settings) {
        $envBlock = Get-ToolProperty $settings 'env'
        if ($envBlock) { $fromSettings = "$(Get-ToolProperty $envBlock 'ANTHROPIC_BASE_URL' '')" }
    }
    $user = ''
    if (Test-IsWindows) { $user = "$([Environment]::GetEnvironmentVariable('ANTHROPIC_BASE_URL', 'User'))" }
    return [pscustomobject]@{ User = $user; Process = "$env:ANTHROPIC_BASE_URL"; Settings = $fromSettings }
}

function Format-AnthropicBaseUrl($Snapshot) {
    $set = @(foreach ($p in 'User', 'Process', 'Settings') { if ($Snapshot.$p) { "$p=$($Snapshot.$p)" } })
    if ($set.Count) { return $set -join '; ' }
    return 'not set'
}

# ---------------------------------------------------------------------------- user PATH

function Add-UserPathEntry([string] $Directory) {
    <# Appends a directory to the user PATH (registry, REG_EXPAND_SZ kept) and to this session. Returns $true if added. #>
    $key = Get-Item -LiteralPath 'HKCU:\Environment'
    $raw = "$($key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))"
    $entries = @($raw.Split(';') | Where-Object { $_ })
    $wanted = $Directory.TrimEnd('\')
    $present = @($entries | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ieq $wanted })
    if (-not $present.Count) {
        $new = (@($entries) + $wanted) -join ';'
        Set-ItemProperty -LiteralPath 'HKCU:\Environment' -Name 'Path' -Value $new -Type ExpandString
        Send-EnvironmentChange
    }
    if (-not (@($env:Path.Split(';')) | Where-Object { $_.TrimEnd('\') -ieq $wanted })) { $env:Path = "$env:Path;$wanted" }
    return (-not $present.Count)
}

function Test-UserPathEntry([string] $Directory) {
    $user = "$([Environment]::GetEnvironmentVariable('Path', 'User'))"
    $wanted = $Directory.TrimEnd('\')
    return [bool] (@($user.Split(';')) | Where-Object { $_.TrimEnd('\') -ieq $wanted })
}

function Send-EnvironmentChange {
    <# Tells Explorer (and terminals it starts) that the environment changed, like 'setx' does. #>
    if (-not ('Heitorgkk.NativeMethods' -as [type])) {
        Add-Type -Namespace Heitorgkk -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    $null = [Heitorgkk.NativeMethods]::SendMessageTimeout([IntPtr] 0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref] $result)
}

# ---------------------------------------------------------------------------- rtk

function Get-RtkState {
    if (-not (Test-Command rtk)) { return New-IntegrationState 'blocked' 'rtk is not installed' }
    $settings = Get-ClaudeSettingsPath
    $text = if (Test-Path -LiteralPath $settings) { Get-Content -LiteralPath $settings -Raw -Encoding UTF8 } else { '' }
    if ($text -match 'rtk(\.exe)?\\?"?\s+hook\s+claude') { return New-IntegrationState 'configured' "PreToolUse hook in $settings" }
    return New-IntegrationState 'missing' 'global Claude Code hook not registered'
}

function Install-RtkIntegration {
    # --auto-patch: patch settings.json without prompting; --no-trust-filters: never enable custom filters silently.
    Write-Info 'rtk init -g --auto-patch --no-trust-filters'
    & rtk init -g --auto-patch --no-trust-filters | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "rtk init exited with $LASTEXITCODE" }
    if ((Get-RtkState).State -ne 'configured') { throw "rtk init finished but no 'rtk hook claude' entry was found in $(Get-ClaudeSettingsPath)" }
    return 'configured'
}

# ---------------------------------------------------------------------------- graphify

function Get-GraphifySkillPath { return Join-Path (Join-Path (Join-Path (Get-ClaudeConfigDir) 'skills') 'graphify') 'SKILL.md' }

function Get-GraphifyState {
    if (-not (Test-Command graphify)) { return New-IntegrationState 'blocked' 'graphify is not installed' }
    $skill = Get-GraphifySkillPath
    if (Test-Path -LiteralPath $skill) { return New-IntegrationState 'configured' "skill at $skill" }
    return New-IntegrationState 'missing' 'Claude Code skill not installed'
}

function Install-GraphifyIntegration([bool] $Refresh) {
    # 'graphify install' is idempotent (it refreshes the skill and skips an existing CLAUDE.md registration),
    # so -Update re-runs it to match the skill to the upgraded CLI. The graph itself is built on demand (/graphify .).
    $before = (Get-GraphifyState).State
    Write-Info 'graphify install'
    $code = Invoke-PythonCli 'graphify' @('install')
    if ($code -ne 0) { throw "graphify install exited with $code" }
    if ((Get-GraphifyState).State -ne 'configured') { throw "graphify install finished but $(Get-GraphifySkillPath) is missing" }
    if ($before -eq 'configured') { if ($Refresh) { return 'updated' } else { return 'up to date' } }
    return 'configured'
}

# ---------------------------------------------------------------------------- headroom MCP

function Get-HeadroomMcpState {
    if (-not (Test-Command headroom)) { return New-IntegrationState 'blocked' 'headroom is not installed' }
    if (Test-ClaudeUserMcpServer 'headroom') {
        return New-IntegrationState 'configured' 'MCP server in user config; live connection: /mcp in Claude Code'
    }
    return New-IntegrationState 'missing' 'MCP server not registered in Claude Code'
}

function Install-HeadroomMcpIntegration {
    # Claude Code only (the default would also edit Codex/OpenCode configs). No --force: an existing,
    # user-edited 'headroom' entry is never overwritten. The proxy is not started.
    Write-Info 'headroom mcp install --agent claude'
    $code = Invoke-PythonCli 'headroom' @('mcp', 'install', '--agent', 'claude')
    if ($code -ne 0) { throw "headroom mcp install exited with $code" }
    if ((Get-HeadroomMcpState).State -ne 'configured') { throw "headroom mcp install finished but no 'headroom' server is in $(Get-ClaudeStatePath)" }
    return 'configured'
}

# ---------------------------------------------------------------------------- MSYS2 + Rust GNU toolchain

function Get-Msys2Root {
    foreach ($root in @((Get-ScoopRoot), (Get-ScoopGlobalRoot))) {
        if (-not $root) { continue }
        $dir = Join-Path $root 'apps\msys2\current'
        if (Test-Path -LiteralPath (Join-Path $dir 'usr\bin\bash.exe')) { return $dir }
    }
    return $null
}

function Get-RustupCommand {
    $cmd = Get-Command 'rustup.exe', 'rustup' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-RustupToolchains([string] $Rustup) {
    $r = Invoke-Native $Rustup @('toolchain', 'list')
    return @($r.Out | Where-Object { $_ } | ForEach-Object { ($_ -split '\s+')[0] })
}

function Get-RustupDefault([string] $Rustup) {
    $r = Invoke-Native $Rustup @('default')
    if ($r.Code -ne 0 -or -not $r.Out) { return '' }
    $first = ($r.Out | Select-Object -First 1)
    if ($first -match '^(\S+-(msvc|gnu|gnullvm))\b') { return $Matches[1] }
    return ''
}

function Test-MsvcBuildTools {
    <# True when Visual Studio / Build Tools with the C++ x64 tools are installed (what the MSVC Rust host needs). #>
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return $false }
    $r = Invoke-Native $vswhere @('-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath')
    return [bool] ($r.Code -eq 0 -and $r.Out)
}

function Get-Msys2RustState {
    if ((Get-OSArchitecture) -ne 'x64') { return New-IntegrationState 'blocked' 'MSYS2 MINGW64 + windows-gnu is set up on x64 only' }
    $root = Get-Msys2Root
    if (-not $root) { return New-IntegrationState 'blocked' 'msys2 is not installed' }
    $bin = Join-Path $root 'mingw64\bin'
    $missing = @()
    if (-not (Test-Path -LiteralPath (Join-Path $bin 'gcc.exe'))) { $missing += 'mingw64 gcc' }
    if (-not (Test-UserPathEntry $bin)) { $missing += 'mingw64\bin on user PATH' }
    $rustup = Get-RustupCommand
    $rust = 'rustup not installed'
    if ($rustup) {
        if ((Get-RustupToolchains $rustup) -notcontains $script:GnuToolchain) { $missing += $script:GnuToolchain }
        $rust = "rust default: $(Get-RustupDefault $rustup)"
    }
    if ($missing.Count) { return New-IntegrationState 'missing' "missing: $($missing -join ', ')" }
    return New-IntegrationState 'configured' "gcc in $bin; $rust"
}

function Invoke-Msys2Shell([string] $Root, [string] $Command) {
    <# Runs a command in an MSYS2 MINGW64 login shell (the first login also initialises the pacman keyring). #>
    $saved = $env:MSYSTEM, $env:CHERE_INVOKING, $env:MSYS2_PATH_TYPE
    $env:MSYSTEM = 'MINGW64'; $env:CHERE_INVOKING = '1'; $env:MSYS2_PATH_TYPE = 'minimal'
    try {
        Write-Info "msys2 (MINGW64): $Command"
        & (Join-Path $Root 'usr\bin\bash.exe') -lc $Command | Out-Host
        return $LASTEXITCODE
    } finally { $env:MSYSTEM, $env:CHERE_INVOKING, $env:MSYS2_PATH_TYPE = $saved }
}

function Install-Msys2RustIntegration([bool] $Refresh) {
    $root = Get-Msys2Root
    if (-not $root) { throw 'msys2 not found (install main/msys2)' }
    $bin = Join-Path $root 'mingw64\bin'
    $done = @()

    if ($Refresh -or -not (Test-Path -LiteralPath (Join-Path $bin 'gcc.exe'))) {
        # A core update may end the first pass ("terminate MSYS2"); the second pass finishes the upgrade.
        $null = Invoke-Msys2Shell $root 'pacman -Syuu --noconfirm'
        $code = Invoke-Msys2Shell $root 'pacman -Syuu --noconfirm'
        if ($code -ne 0) { throw "pacman -Syuu exited with $code" }
        $code = Invoke-Msys2Shell $root "pacman -S --needed --noconfirm $($script:Msys2Packages -join ' ')"
        if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $bin 'gcc.exe'))) { throw "pacman could not install $($script:Msys2Packages -join ', ') (exit $code)" }
        $done += 'mingw64 gcc'
    }
    if (Add-UserPathEntry $bin) { $done += 'PATH' }

    $rustup = Get-RustupCommand
    if (-not $rustup) {
        Write-Warn 'rustup not found: install main/rustup, then re-run to add the GNU toolchain.'
    } else {
        if ($Refresh -or (Get-RustupToolchains $rustup) -notcontains $script:GnuToolchain) {
            Write-Info "rustup toolchain install $($script:GnuToolchain)"
            & $rustup toolchain install $script:GnuToolchain | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "rustup toolchain install exited with $LASTEXITCODE" }
            $done += $script:GnuToolchain
        }
        # Only switch the default when the current one cannot link: no default, or MSVC without Build Tools.
        $default = Get-RustupDefault $rustup
        if (-not $default -or ($default -like '*-msvc' -and -not (Test-MsvcBuildTools))) {
            Write-Info "rustup default $($script:GnuToolchain) (was: $(if ($default) { $default } else { 'none' }); MSVC Build Tools not found)"
            & $rustup default $script:GnuToolchain | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "rustup default exited with $LASTEXITCODE" }
            $done += 'rust default'
        } elseif ($default -ne $script:GnuToolchain) {
            Write-Info "Rust default stays $default. Use the GNU toolchain with: rustup default $($script:GnuToolchain)"
        }
    }
    if (-not $done.Count) { return 'up to date' }
    if ($Refresh) { return 'updated' }
    return 'configured'
}

# ---------------------------------------------------------------------------- dispatch

function Get-IntegrationState($Tool) {
    switch (Get-ToolProperty $Tool 'integration') {
        'rtk' { return Get-RtkState }
        'graphify' { return Get-GraphifyState }
        'headroom-mcp' { return Get-HeadroomMcpState }
        'msys2-rust' { return Get-Msys2RustState }
    }
    throw "unknown integration '$(Get-ToolProperty $Tool 'integration')'"
}

function Invoke-Integration($Tool, [bool] $Refresh) {
    switch (Get-ToolProperty $Tool 'integration') {
        'rtk' { return Install-RtkIntegration }
        'graphify' { return Install-GraphifyIntegration $Refresh }
        'headroom-mcp' { return Install-HeadroomMcpIntegration }
        'msys2-rust' { return Install-Msys2RustIntegration $Refresh }
    }
    throw "unknown integration '$(Get-ToolProperty $Tool 'integration')'"
}

function Test-IntegrationRerunOnUpdate($Tool) {
    <# Integrations whose installer is known to be idempotent and benefit from re-running after an upgrade. #>
    return ((Get-ToolProperty $Tool 'integration') -in 'graphify', 'msys2-rust')
}
