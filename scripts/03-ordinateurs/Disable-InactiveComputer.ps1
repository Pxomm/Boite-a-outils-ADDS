<#
.SYNOPSIS
    Désactive les ordinateurs inactifs et les place en quarantaine.

.DESCRIPTION
    Première étape d'un nettoyage en deux temps : les comptes inactifs depuis N jours sont
    désactivés, marqués « Quarantaine AAAA-MM-JJ » dans leur description et déplacés dans
    l'OU de quarantaine. Remove-QuarantinedComputer.ps1 les supprime après un délai de garde.
    Les contrôleurs de domaine et les serveurs (sauf -IncludeServers) sont exclus.

.EXAMPLE
    .\Disable-InactiveComputer.ps1 -Days 120 -QuarantineOU 'OU=Quarantaine,DC=corp,DC=local' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateRange(30, 3650)][int]$Days = 120,
    [Parameter(Mandatory)][string]$QuarantineOU,
    [string]$SearchBase,
    [string[]]$Exclude = @(),
    [switch]$IncludeServers
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox
$null = Get-ADOrganizationalUnit -Identity $QuarantineOU -ErrorAction Stop

$inactiveParams = @{ Days = $Days }
if ($SearchBase) { $inactiveParams.SearchBase = $SearchBase }
$candidates = @(& "$PSScriptRoot/Get-InactiveComputer.ps1" @inactiveParams)
$stamp = Get-Date -Format 'yyyy-MM-dd'

foreach ($computer in $candidates) {
    $status = 'Simulation'
    if ($computer.Name -in $Exclude) { $status = 'Exclu' }
    elseif ($computer.OperatingSystem -match 'Server' -and -not $IncludeServers) { $status = 'Ignoré (serveur)' }
    elseif ($computer.DistinguishedName -like "*,$QuarantineOU") { $status = 'Déjà en quarantaine' }
    elseif ($PSCmdlet.ShouldProcess($computer.DistinguishedName, "Désactiver et déplacer en quarantaine ($($computer.DaysInactive) jours d'inactivité)")) {
        try {
            Disable-ADAccount -Identity $computer.DistinguishedName -ErrorAction Stop
            $note = "Quarantaine $stamp" + $(if ($computer.Description) { " | $($computer.Description)" })
            Set-ADComputer -Identity $computer.DistinguishedName -Description $note -ErrorAction Stop
            Move-ADObject -Identity $computer.DistinguishedName -TargetPath $QuarantineOU -ErrorAction Stop
            $status = 'Mis en quarantaine'
        }
        catch { $status = "Erreur : $($_.Exception.Message)" }
    }
    [pscustomobject]@{ Name = $computer.Name; OperatingSystem = $computer.OperatingSystem; LastLogon = $computer.LastLogon; DaysInactive = $computer.DaysInactive; Status = $status }
}
