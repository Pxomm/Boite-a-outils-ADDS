<#
.SYNOPSIS
    Repère les unités d'organisation non protégées contre la suppression accidentelle, et les protège.

.DESCRIPTION
    Sans -Fix : liste les OU non protégées. Avec -Fix : active la protection sur chacune.
    Une OU non protégée peut être supprimée ou déplacée d'un glisser-déposer, avec tout
    son contenu.

.EXAMPLE
    .\Set-OUDeletionProtection.ps1

.EXAMPLE
    .\Set-OUDeletionProtection.ps1 -Fix -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SearchBase,
    [switch]$Fix
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$query = @{ Filter = '*'; Properties = 'ProtectedFromAccidentalDeletion' }
if ($SearchBase) { $query.SearchBase = $SearchBase }
foreach ($ou in Get-ADOrganizationalUnit @query | Where-Object { -not $_.ProtectedFromAccidentalDeletion } | Sort-Object DistinguishedName) {
    $status = 'Non protégée'
    if ($Fix) {
        $status = 'Simulation'
        if ($PSCmdlet.ShouldProcess($ou.DistinguishedName, 'Protéger contre la suppression accidentelle')) {
            try { Set-ADOrganizationalUnit -Identity $ou.DistinguishedName -ProtectedFromAccidentalDeletion $true -ErrorAction Stop; $status = 'Protégée' }
            catch { $status = "Erreur : $($_.Exception.Message)" }
        }
    }
    [pscustomobject]@{ Name = $ou.Name; DistinguishedName = $ou.DistinguishedName; Status = $status }
}
