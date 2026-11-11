<#
.SYNOPSIS
    Liste les objets supprimés encore présents dans la corbeille Active Directory.

.DESCRIPTION
    -Name filtre sur le nom d'origine (jokers acceptés), -ObjectClass sur le type,
    -Days sur l'ancienneté de la suppression. La colonne ObjectGuid sert à
    Restore-DeletedObject.ps1.

.EXAMPLE
    .\Get-DeletedObject.ps1 -Name 'Dupont*' -ObjectClass user

.EXAMPLE
    .\Get-DeletedObject.ps1 -Days 7
#>
[CmdletBinding()]
param(
    [string]$Name = '*',
    [ValidateSet('user', 'computer', 'group', 'organizationalUnit', 'any')][string]$ObjectClass = 'any',
    [ValidateRange(1, 3650)][int]$Days,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$deletedContainer = (Get-ADDomain).DeletedObjectsContainer
$limit = if ($Days) { (Get-Date).AddDays(-$Days) } else { $null }
Get-ADObject -Filter "isDeleted -eq `$true" -IncludeDeletedObjects -SearchBase $deletedContainer -Properties 'msDS-LastKnownRDN', lastKnownParent, whenChanged, sAMAccountName, objectClass |
    Where-Object { $_.DistinguishedName -ne $deletedContainer -and "$($_.'msDS-LastKnownRDN')" -like $Name -and
                   ($ObjectClass -eq 'any' -or $_.objectClass -eq $ObjectClass) -and (-not $limit -or $_.whenChanged -ge $limit) } |
    ForEach-Object {
        [pscustomobject]@{ Name = $_.'msDS-LastKnownRDN'; SamAccountName = $_.sAMAccountName; ObjectClass = $_.objectClass; DeletedOn = $_.whenChanged
                           LastKnownParent = $_.lastKnownParent; ObjectGuid = $_.ObjectGUID }
    } | Sort-Object DeletedOn -Descending | Export-Report -CsvPath $CsvPath
