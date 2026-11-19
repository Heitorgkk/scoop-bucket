#Requires -Version 5.1
<#
.SYNOPSIS
    Prepares Scoop for the Heitorgkk bucket: checks Scoop and Git, then adds the
    Heitorgkk bucket and the official buckets it depends on (extras, java, ...).

.DESCRIPTION
    Safe to run repeatedly: buckets that already exist are left untouched.
    Bucket names and URLs come from groups.json.
    Nothing here needs administrator rights.

.PARAMETER Bucket
    Official buckets to add (default: every bucket declared in groups.json).
    The Heitorgkk bucket itself is always added.

.PARAMETER BucketSource
    Where to clone the Heitorgkk bucket from (default: the GitHub URL in groups.json).
    Accepts any git URL or a local repository path, which is useful for testing changes.

.PARAMETER InstallScoop
    Install Scoop with the official installer (https://get.scoop.sh) when it is missing.
    Without this switch, a missing Scoop is reported and the script stops.

.EXAMPLE
    .\scripts\bootstrap.ps1

.EXAMPLE
    .\scripts\bootstrap.ps1 -InstallScoop

.NOTES
    Exit codes: 0 = ready, 1 = some bucket could not be added, 2 = prerequisite missing / invalid input.
#>
[CmdletBinding()]
param(
    [string[]] $Bucket,
    [string] $BucketSource,
    [switch] $InstallScoop,
    [string] $CatalogPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Common.ps1')

function Install-Scoop {
    if (Test-IsElevated) {
        Write-Fail 'Refusing to install Scoop from an elevated (administrator) shell.'
        Write-Info 'Scoop is a per-user installer. Open a normal PowerShell window and run again.'
        return $false
    }
    $policy = Get-ExecutionPolicy -Scope CurrentUser
    if ($policy -in @('Undefined', 'Restricted', 'AllSigned')) {
        Write-Info "Setting execution policy for CurrentUser to RemoteSigned (was $policy), as required by Scoop."
        # Throws "overridden by a policy defined at a more specific scope" when Process is already Bypass
        # (setup.ps1 sets it) even though the CurrentUser value was stored, so the error is not fatal.
        try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force } catch { Write-Warn $_.Exception.Message }
    }
    $installer = Join-Path ([IO.Path]::GetTempPath()) "install-scoop-$PID.ps1"
    try {
        Write-Info 'Downloading the official Scoop installer from https://get.scoop.sh ...'
        Invoke-RestMethod -Uri 'https://get.scoop.sh' -OutFile $installer -UseBasicParsing
        & $installer
    } finally {
        Remove-Item -LiteralPath $installer -ErrorAction SilentlyContinue
    }
    Update-SessionPath
    $shims = Join-Path (Get-ScoopRoot) 'shims'
    if ((Test-Path $shims) -and ($env:Path -notlike "*$shims*")) { $env:Path = "$shims;$env:Path" }
    return (Test-Command scoop)
}

function Add-Bucket([string] $Name, [string] $Source) {
    if (Test-ScoopBucket $Name) {
        $remote = Get-ScoopBucketRemote $Name
        if ($remote -and (ConvertTo-NormalizedRepo $remote) -ne (ConvertTo-NormalizedRepo $Source)) {
            Write-Warn "Bucket '$Name' already exists but points to '$remote' (expected '$Source'). Keeping it."
        } else {
            Write-Skip "Bucket '$Name' already added."
        }
        return $true
    }

    # Scoop refuses to add the same repository twice under another name; references such as
    # 'extras/lazygit' or 'Heitorgkk/main' only work with the expected bucket name.
    $bucketsDir = Join-Path (Get-ScoopRoot) 'buckets'
    if (Test-Path -LiteralPath $bucketsDir) {
        foreach ($dir in Get-ChildItem -LiteralPath $bucketsDir -Directory) {
            $remote = Get-ScoopBucketRemote $dir.Name
            if ($remote -and (ConvertTo-NormalizedRepo $remote) -eq (ConvertTo-NormalizedRepo $Source)) {
                Write-Fail "'$Source' is already added as bucket '$($dir.Name)', but this catalog needs it named '$Name'."
                Write-Info "Fix: scoop bucket rm $($dir.Name); scoop bucket add $Name $Source"
                return $false
            }
        }
    }

    Write-Info "Adding bucket '$Name' from $Source ..."
    & scoop bucket add $Name $Source | Out-Host
    if (Test-ScoopBucket $Name) {
        Write-Ok "Bucket '$Name' added."
        return $true
    }
    Write-Fail "Could not add bucket '$Name' (scoop exit code $LASTEXITCODE)."
    return $false
}

# ---------------------------------------------------------------------------- main
try {
    if (-not (Test-IsWindows)) {
        Write-Fail 'Scoop only runs on Windows.'
        exit $EXIT_USAGE
    }

    if ($CatalogPath) { $catalog = Get-Catalog -Path $CatalogPath } else { $catalog = Get-Catalog }
    $own = $catalog.bucket.name
    if (-not $BucketSource) { $BucketSource = $catalog.bucket.url }
    elseif (Test-Path -LiteralPath $BucketSource -PathType Container) {
        # 'scoop bucket add' only accepts git URLs; turn a local checkout into a file:/// URL.
        $full = (Resolve-Path -LiteralPath $BucketSource).ProviderPath
        $BucketSource = 'file:///' + ($full -replace '\\', '/').TrimStart('/')
    }
    $known = @($catalog.buckets.PSObject.Properties | ForEach-Object { $_.Name })

    if (-not $Bucket) { $Bucket = $known }
    $unknown = @($Bucket | Where-Object { $known -notcontains $_ })
    if ($unknown.Count) {
        Write-Fail "Unknown bucket(s): $($unknown -join ', '). Declared in groups.json: $($known -join ', ')."
        exit $EXIT_USAGE
    }

    Write-Section 'Checking Scoop'
    if (Test-Command scoop) {
        Write-Ok "Scoop found ($((Get-Command scoop).Source))."
    } elseif ($InstallScoop) {
        if (-not (Install-Scoop)) {
            Write-Fail 'Scoop installation failed. See https://scoop.sh for manual instructions.'
            exit $EXIT_USAGE
        }
        Write-Ok 'Scoop installed.'
    } else {
        Write-Fail 'Scoop is not installed (or not on PATH).'
        Write-Info 'Install it from a normal (non-admin) PowerShell window:'
        Write-Info '  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser'
        Write-Info '  Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression'
        Write-Info 'or re-run this script with -InstallScoop.'
        exit $EXIT_USAGE
    }
    if (Test-IsElevated) {
        Write-Warn 'Running elevated. Scoop installs per user; a normal shell is recommended.'
    }

    Write-Section 'Checking Git (required to add buckets)'
    if (Test-Command git) {
        Write-Ok 'Git found.'
    } else {
        Write-Info 'Installing main/git ...'
        & scoop install main/git | Out-Host
        Update-SessionPath
        if (-not (Test-Command git)) {
            Write-Fail "Git could not be installed. Run 'scoop install git' and try again."
            exit $EXIT_USAGE
        }
        Write-Ok 'Git installed.'
    }

    Write-Section 'Adding buckets'
    $failed = @()
    # 'main' ships with Scoop, but may have been removed; the rest are optional per group.
    foreach ($name in $Bucket) {
        if (-not (Add-Bucket $name $catalog.buckets.$name)) { $failed += $name }
    }
    if (-not (Add-Bucket $own $BucketSource)) { $failed += $own }

    Write-Section 'Summary'
    if ($failed.Count) {
        Write-Fail "Bucket(s) not available: $($failed -join ', ')"
        exit $EXIT_FAILURES
    }
    Write-Ok "Ready. Buckets: $((@($Bucket) + $own) -join ', ')."
    Write-Info "Next: scoop install $own/<group>   or   .\scripts\install.ps1 -Group <group>"
    exit $EXIT_OK
} catch {
    Write-Fail $_.Exception.Message
    exit $EXIT_USAGE
}
