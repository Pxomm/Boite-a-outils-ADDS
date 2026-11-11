<#
.SYNOPSIS
    Vérifie l'état de la corbeille Active Directory et l'active.

.DESCRIPTION
    La corbeille permet de restaurer un objet supprimé avec tous ses attributs et ses
    appartenances aux groupes (voir Restore-DeletedObject.ps1). Elle exige un niveau
    fonctionnel de forêt Windows Server 2008 R2 au minimum et un compte administrateur de
    l'entreprise. L'activation est IRRÉVERSIBLE. Sans -Enable, le script affiche seulement l'état.

.EXAMPLE
    .\Enable-RecycleBin.ps1

.EXAMPLE
    .\Enable-RecycleBin.ps1 -Enable
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([switch]$Enable)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$forest = Get-ADForest
$feature = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'"
$enabled = [bool](@($feature.EnabledScopes).Count -gt 0)
$status = if ($enabled) { 'Déjà activée' } else { 'Désactivée' }

if ($Enable -and -not $enabled) {
    $status = 'Simulation'
    if ($PSCmdlet.ShouldProcess($forest.Name, 'Activer la corbeille Active Directory (irréversible)')) {
        Enable-ADOptionalFeature -Identity 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target $forest.Name -Confirm:$false -ErrorAction Stop
        $status = 'Activée'
    }
}
[pscustomobject]@{ Forest = $forest.Name; ForestMode = "$($forest.ForestMode)"; RecycleBin = $status }
