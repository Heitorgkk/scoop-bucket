#Requires -Version 5.1
<#
.SYNOPSIS
    CI only: installs Scoop on a GitHub-hosted Windows runner.
    Runners execute as administrator, so the official installer needs -RunAsAdmin.
    Do not use this on a workstation; use scripts/bootstrap.ps1 -InstallScoop instead.
#>
$ErrorActionPreference = 'Stop'
$installer = Join-Path $env:RUNNER_TEMP 'install-scoop.ps1'
Invoke-RestMethod -Uri 'https://get.scoop.sh' -OutFile $installer
& $installer -RunAsAdmin
$shims = Join-Path $env:USERPROFILE 'scoop\shims'
Add-Content -Path $env:GITHUB_PATH -Value $shims
$env:Path = "$shims;$env:Path"
scoop --version
scoop config aria2-enabled false
