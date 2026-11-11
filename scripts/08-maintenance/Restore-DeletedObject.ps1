<#
.SYNOPSIS
    Restaure un objet supprimé depuis la corbeille Active Directory.

.DESCRIPTION
    L'objet est désigné par son nom d'origine ou son identifiant (colonne ObjectGuid de
    Get-DeletedObject.ps1). Il retrouve son emplacement d'origine, ses attributs et ses
    groupes. Si son OU d'origine a elle-même été supprimée, la restaurer d'abord, ou
    indiquer -TargetPath. Si plusieurs objets supprimés portent le même nom, le script
    s'arrête et demande de préciser l'identifiant.

.EXAMPLE
    .\Restore-DeletedObject.ps1 -Name 'Jeanne Dupont' -WhatIf

.EXAMPLE
    .\Restore-DeletedObject.ps1 -ObjectGuid 6f1c2d3e-0a1b-4c5d-8e9f-001122334455 -TargetPath 'OU=Utilisateurs,DC=corp,DC=local'
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Name')]
param(
    [Parameter(ParameterSetName = 'Name', Mandatory)][string]$Name,
    [Parameter(ParameterSetName = 'Guid', Mandatory)][guid]$ObjectGuid,
    [string]$TargetPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$feature = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'"
if (@($feature.EnabledScopes).Count -eq 0) { Write-Warning 'La corbeille Active Directory n''est pas activée : l''objet restauré aura perdu la plupart de ses attributs et ses groupes.' }

$found = @(Get-ADObject -Filter "isDeleted -eq `$true" -IncludeDeletedObjects -SearchBase (Get-ADDomain).DeletedObjectsContainer -Properties 'msDS-LastKnownRDN', lastKnownParent, whenChanged |
    Where-Object { if ($PSCmdlet.ParameterSetName -eq 'Guid') { $_.ObjectGUID -eq $ObjectGuid } else { "$($_.'msDS-LastKnownRDN')" -eq $Name } })
if ($found.Count -eq 0) { throw 'Aucun objet supprimé ne correspond (déjà purgé, ou jamais supprimé).' }
if ($found.Count -gt 1) { throw "$($found.Count) objets supprimés portent ce nom : relancer avec -ObjectGuid (voir Get-DeletedObject.ps1)." }

$object = $found[0]
$destination = if ($TargetPath) { $TargetPath } else { "$($object.lastKnownParent)" }
if ($destination -match '\\0ADEL:') { throw "L'emplacement d'origine ($destination) a lui-même été supprimé : le restaurer d'abord, ou indiquer -TargetPath." }
$status = 'Simulation'
if ($PSCmdlet.ShouldProcess("$($object.'msDS-LastKnownRDN') ($($object.ObjectGUID))", "Restaurer vers $destination")) {
    $restore = @{ Identity = $object.ObjectGUID; ErrorAction = 'Stop' }
    if ($TargetPath) { $restore.TargetPath = $TargetPath }
    Restore-ADObject @restore
    $status = 'Restauré'
}
[pscustomobject]@{ Name = $object.'msDS-LastKnownRDN'; DeletedOn = $object.whenChanged; RestoredTo = $destination; ObjectGuid = $object.ObjectGUID; Status = $status }
