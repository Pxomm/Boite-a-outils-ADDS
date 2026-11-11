<#
.SYNOPSIS
    Transfère des rôles FSMO vers un autre contrôleur de domaine.

.DESCRIPTION
    Transfert normal : l'ancien détenteur doit être en ligne. À faire avant de rétrograder
    ou d'arrêter durablement un contrôleur de domaine.
    -Seize force la prise de rôle lorsque l'ancien détenteur est définitivement perdu : il
    ne devra jamais être remis en service (le réinstaller après nettoyage des métadonnées).
    Les rôles de forêt exigent un compte administrateur de l'entreprise (et du schéma pour
    le contrôleur de schéma).

.EXAMPLE
    .\Move-FSMORole.ps1 -Target DC02 -Role PDCEmulator, RIDMaster, InfrastructureMaster -WhatIf

.EXAMPLE
    .\Move-FSMORole.ps1 -Target DC02 -Role All
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$Target,
    [Parameter(Mandatory)][ValidateSet('All', 'PDCEmulator', 'RIDMaster', 'InfrastructureMaster', 'SchemaMaster', 'DomainNamingMaster')][string[]]$Role,
    [switch]$Seize
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$dc = Get-ADDomainController -Identity $Target -ErrorAction Stop
if ($dc.IsReadOnly) { throw "$($dc.HostName) est un contrôleur de domaine en lecture seule : il ne peut détenir aucun rôle." }
if ('All' -in $Role) { $Role = 'PDCEmulator', 'RIDMaster', 'InfrastructureMaster', 'SchemaMaster', 'DomainNamingMaster' }
$domain = Get-ADDomain; $forest = Get-ADForest
$current = @{ PDCEmulator = $domain.PDCEmulator; RIDMaster = $domain.RIDMaster; InfrastructureMaster = $domain.InfrastructureMaster
              SchemaMaster = $forest.SchemaMaster; DomainNamingMaster = $forest.DomainNamingMaster }

foreach ($name in $Role | Select-Object -Unique) {
    $status = 'Simulation'
    if ($current[$name] -eq $dc.HostName) { $status = 'Déjà détenu' }
    elseif ($PSCmdlet.ShouldProcess($dc.HostName, "$(if ($Seize) { 'Forcer la prise' } else { 'Transférer' }) du rôle $name (actuellement sur $($current[$name]))")) {
        try {
            Move-ADDirectoryServerOperationMasterRole -Identity $dc.HostName -OperationMasterRole $name -Force:$Seize -Confirm:$false -ErrorAction Stop
            $status = if ($Seize) { 'Pris de force' } else { 'Transféré' }
        }
        catch { $status = "Erreur : $($_.Exception.Message)" }
    }
    [pscustomobject]@{ Role = $name; PreviousHolder = $current[$name]; NewHolder = $dc.HostName; Status = $status }
}
