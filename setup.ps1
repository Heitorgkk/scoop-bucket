<#
.SYNOPSIS
    One-line installer for a fresh Windows machine: no Scoop, Git or WinGet required.

.DESCRIPTION
    Downloads this repository as a ZIP (no Git needed), installs Scoop if it is missing,
    adds the buckets and installs the requested groups with scripts/install.ps1.
    Run it from a normal (non-administrator) PowerShell window:

        irm https://raw.githubusercontent.com/Heitorgkk/scoop-bucket/main/setup.ps1 | iex

    With options:

        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Heitorgkk/scoop-bucket/main/setup.ps1))) -Group main,ai -NoWinGet

    It never calls 'exit', so it is safe to run inside your current shell.

.PARAMETER Group
    Groups to install (default: all).

.PARAMETER NoWinGet
    Install desktop apps from the vendor's official MSIX instead of WinGet.

.PARAMETER Update
    Also upgrade tools that are already installed.

.PARAMETER Branch
    Branch of the repository to use (default: main).

.PARAMETER SourcePath
    Use a local checkout instead of downloading the ZIP (for testing).

.PARAMETER BucketSource
    Passed to install.ps1/bootstrap.ps1 (git URL or local path of the Heitorgkk bucket).

.PARAMETER NoBrowser
    Do not open the post-install guide (docs/post-install.md) in the browser at the end.

.NOTES
    No '#Requires' or [CmdletBinding()] here: the file must also work through Invoke-Expression.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Report the result to the calling shell without exit.')]
param(
    [string[]] $Group = @('all'),
    [switch] $NoWinGet,
    [switch] $Update,
    [string] $Branch = 'main',
    [string] $SourcePath,
    [string] $BucketSource,
    [switch] $NoBrowser
)

$ErrorActionPreference = 'Stop'
$repo = 'Heitorgkk/scoop-bucket'

function Write-SetupStep([string] $Text) { Write-Host "==> $Text" -ForegroundColor Cyan }

$setupResult = 2
$workDir = $null
try {
    if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) { throw 'This installer only runs on Windows.' }

    # Allow the downloaded scripts to run in this process only (Scoop later sets RemoteSigned for the user).
    # Set-ExecutionPolicy throws a SecurityException when a Group Policy overrides the scope even though
    # the value was stored; the check below decides whether scripts can actually run.
    try { Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force } catch { Write-Verbose $_.Exception.Message }
    $effective = Get-ExecutionPolicy
    if ($effective -in 'Restricted', 'AllSigned') {
        throw "The execution policy is '$effective' (set by Group Policy) and blocks the installer scripts. Ask your administrator to allow RemoteSigned."
    }
    # Windows PowerShell 5.1 may default to TLS 1.0/1.1, which GitHub refuses.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    if ($SourcePath) {
        $root = (Resolve-Path -LiteralPath $SourcePath).ProviderPath
        Write-SetupStep "Using local checkout $root"
    } else {
        $workDir = Join-Path ([IO.Path]::GetTempPath()) "heitorgkk-setup-$PID"
        $null = New-Item -ItemType Directory -Path $workDir -Force
        $zip = Join-Path $workDir 'repo.zip'
        $url = "https://github.com/$repo/archive/refs/heads/$Branch.zip"
        Write-SetupStep "Downloading $url"
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        Expand-Archive -LiteralPath $zip -DestinationPath $workDir -Force
        $root = Get-ChildItem -LiteralPath $workDir -Directory | Select-Object -First 1 -ExpandProperty FullName
        if (-not $root -or -not (Test-Path (Join-Path $root 'groups.json'))) { throw 'Downloaded archive does not look like the scoop-bucket repository.' }
        # Drop any Mark of the Web, so a RemoteSigned policy treats the extracted scripts as local.
        Get-ChildItem -LiteralPath $root -Recurse -File | Unblock-File
    }

    $common = @{}
    if ($BucketSource) { $common.BucketSource = $BucketSource }

    Write-SetupStep 'Preparing Scoop and buckets'
    & (Join-Path $root 'scripts\bootstrap.ps1') -InstallScoop @common
    if ($LASTEXITCODE -ne 0) { throw "bootstrap.ps1 failed with exit code $LASTEXITCODE" }

    Write-SetupStep "Installing group(s): $($Group -join ', ')"
    $installArgs = @{ Group = $Group; NoWinGet = $NoWinGet; Update = $Update }
    & (Join-Path $root 'scripts\install.ps1') @installArgs @common
    $setupResult = $LASTEXITCODE
} catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    $setupResult = 2
} finally {
    if ($workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($setupResult -eq 0) {
    Write-Host 'Setup finished. Open a new terminal to use the installed tools.' -ForegroundColor Green
} else {
    Write-Host "Setup finished with errors (code $setupResult). Re-run the same command to retry; installed tools are skipped." -ForegroundColor Yellow
}
# Exit code 2 means nothing (or almost nothing) was installed, so there is nothing to configure yet.
if ($setupResult -ne 2) {
    $guide = "https://github.com/$repo/blob/$Branch/docs/post-install.md"
    Write-Host "Next steps (Oh My Posh, Everything, sign-ins, ...): $guide" -ForegroundColor Cyan
    if (-not $NoBrowser -and -not $env:CI) {
        try { Start-Process $guide } catch { Write-Verbose "Could not open a browser: $($_.Exception.Message)" }
    }
}
$global:LASTEXITCODE = $setupResult
