<#
.SYNOPSIS
    Fixe, repousse ou supprime la date d'expiration d'un compte (prestataires, stagiaires, CDD).

.DESCRIPTION
    -Date : le compte reste utilisable jusqu'à la fin de la journée indiquée.
    -Days : expiration dans N jours à compter d'aujourd'hui.
    -Never : supprime la date d'expiration.

.EXAMPLE
    .\Set-UserExpiration.ps1 -Identity ext.durand -Date 2026-12-31

.EXAMPLE
    Get-ADUser -Filter * -SearchBase 'OU=Prestataires,DC=corp,DC=local' | ForEach-Object SamAccountName | .\Set-UserExpiration.ps1 -Days 90
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, ValueFromPipeline)][string[]]$Identity,
    [Parameter(ParameterSetName = 'Date', Mandatory)][datetime]$Date,
    [Parameter(ParameterSetName = 'Days', Mandatory)][ValidateRange(1, 3650)][int]$Days,
    [Parameter(ParameterSetName = 'Never', Mandatory)][switch]$Never
)

begin {
    . "$PSScriptRoot/../../lib/Communs.ps1"
    Initialize-ADToolbox
    # Active Directory désactive le compte à l'instant indiqué : on vise le lendemain à 00 h 00
    $when = switch ($PSCmdlet.ParameterSetName) {
        'Date' { $Date.Date.AddDays(1) }
        'Days' { (Get-Date).Date.AddDays($Days + 1) }
        default { $null }
    }
    if ($Never) { Write-Verbose 'Suppression de la date d''expiration demandée.' }
    if ($when -and $when -le (Get-Date)) { throw 'La date d''expiration demandée est déjà passée.' }
}
process {
    foreach ($id in $Identity) {
        try {
            $user = Get-ADUser -Identity $id -Properties AccountExpirationDate -ErrorAction Stop
            $status = 'Simulation'
            $action = if ($when) { "Fixer l'expiration au $($when.AddDays(-1).ToString('dd/MM/yyyy')) inclus" } else { 'Supprimer la date d''expiration' }
            if ($PSCmdlet.ShouldProcess($user.DistinguishedName, $action)) {
                if ($when) { Set-ADAccountExpiration -Identity $user.DistinguishedName -DateTime $when -ErrorAction Stop }
                else       { Clear-ADAccountExpiration -Identity $user.DistinguishedName -ErrorAction Stop }
                $status = 'Modifié'
            }
            [pscustomobject]@{ SamAccountName = $user.SamAccountName; PreviousExpiration = $user.AccountExpirationDate; NewExpiration = $when; Status = $status }
        }
        catch { [pscustomobject]@{ SamAccountName = $id; PreviousExpiration = $null; NewExpiration = $null; Status = "Erreur : $($_.Exception.Message)" } }
    }
}
