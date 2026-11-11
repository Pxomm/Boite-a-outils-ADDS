<#
.SYNOPSIS
    Liste les unités d'organisation qui ne contiennent aucun objet.

.DESCRIPTION
    Une OU est dite vide lorsqu'elle n'a aucun enfant direct (ni objet, ni sous-OU).
    La colonne LinkedGPO signale celles qui portent encore des stratégies de groupe.

.EXAMPLE
    .\Get-EmptyOU.ps1
#>
[CmdletBinding()]
param([string]$SearchBase, [string]$CsvPath)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$query = @{ Filter = '*'; Properties = 'gPLink', 'whenCreated', 'Description' }
if ($SearchBase) { $query.SearchBase = $SearchBase }
Get-ADOrganizationalUnit @query | ForEach-Object {
    if (-not (Get-ADObject -Filter * -SearchBase $_.DistinguishedName -SearchScope OneLevel -ResultSetSize 1)) {
        [pscustomobject]@{ Name = $_.Name; WhenCreated = $_.whenCreated; LinkedGPO = ([regex]::Matches("$($_.gPLink)", '\[LDAP://')).Count
                           Description = $_.Description; DistinguishedName = $_.DistinguishedName }
    }
} | Sort-Object DistinguishedName | Export-Report -CsvPath $CsvPath
