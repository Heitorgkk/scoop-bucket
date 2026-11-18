@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # The scripts are interactive installers: coloured console output is the point.
        'PSAvoidUsingWriteHost',
        # Helper names such as Get-GroupTools/Get-GroupNames return collections on purpose.
        'PSUseSingularNouns',
        # Internal helpers (Update-SessionPath, Add-Bucket, ...) are not user-facing cmdlets.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
