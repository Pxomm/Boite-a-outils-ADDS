<#
.SYNOPSIS
    Liste les comptes verrouillés et les déverrouille.

.DESCRIPTION
    Sans paramètre : liste les comptes verrouillés, sans rien modifier.
    -Identity déverrouille les comptes indiqués, -All tous les comptes verrouillés.
    Pour connaître l'origine d'un verrouillage : Find-LockoutSource.ps1.

.EXAMPLE
    .\Unlock-UserAccount.ps1

.EXAMPLE
    .\Unlock-UserAccount.ps1 -Identity j.dupont
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'List')]
param(
    [Parameter(ParameterSetName = 'Identity', Mandatory, ValueFromPipeline)][string[]]$Identity,
    [Parameter(ParameterSetName = 'All', Mandatory)][switch]$All
)

begin {
    . "$PSScriptRoot/../../lib/Communs.ps1"
    Initialize-ADToolbox
    $targets = New-Object System.Collections.Generic.List[string]
}
process { foreach ($id in $Identity) { $targets.Add($id) } }
end {
    $locked = @(Search-ADAccount -LockedOut -UsersOnly)
    if ($PSCmdlet.ParameterSetName -eq 'List') {
        $locked | ForEach-Object { [pscustomobject]@{ SamAccountName = $_.SamAccountName; Name = $_.Name; LockedOut = $true; LastLogonDate = $_.LastLogonDate; Status = 'Verrouillé' } }
        return
    }
    if ($All) { $locked | ForEach-Object { $targets.Add($_.SamAccountName) } }
    foreach ($id in $targets) {
        try {
            $user = Get-ADUser -Identity $id -Properties LockedOut -ErrorAction Stop
            $status = if (-not $user.LockedOut) { 'Non verrouillé' } else { 'Simulation' }
            if ($user.LockedOut -and $PSCmdlet.ShouldProcess($user.DistinguishedName, 'Déverrouiller le compte')) {
                Unlock-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop
                $status = 'Déverrouillé'
            }
            [pscustomobject]@{ SamAccountName = $user.SamAccountName; Name = $user.Name; LockedOut = [bool]$user.LockedOut; LastLogonDate = $null; Status = $status }
        }
        catch { [pscustomobject]@{ SamAccountName = $id; Name = ''; LockedOut = $null; LastLogonDate = $null; Status = "Erreur : $($_.Exception.Message)" } }
    }
}
