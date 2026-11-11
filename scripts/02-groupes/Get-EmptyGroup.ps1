<#
.SYNOPSIS
    Liste les groupes sans aucun membre.

.DESCRIPTION
    Les groupes système (intégrés ou critiques) sont ignorés. Un groupe peut être vide et
    servir tout de même de groupe principal à des comptes (cas de « Utilisateurs du domaine ») :
    vérifier avant toute suppression. -NotMemberOfAny ne garde que les groupes qui ne sont
    eux-mêmes membres d'aucun groupe.

.EXAMPLE
    .\Get-EmptyGroup.ps1 -SearchBase 'OU=Groupes,DC=corp,DC=local' -CsvPath C:\Temp\groupes-vides.csv
#>
[CmdletBinding()]
param(
    [string]$SearchBase,
    [switch]$NotMemberOfAny,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$query = @{ Filter = "Members -notlike '*'"; Properties = 'isCriticalSystemObject', 'whenCreated', 'whenChanged', 'Description', 'MemberOf' }
if ($SearchBase) { $query.SearchBase = $SearchBase }

Get-ADGroup @query |
    Where-Object { -not $_.isCriticalSystemObject -and $_.DistinguishedName -notmatch ',CN=Builtin,' -and (-not $NotMemberOfAny -or @($_.MemberOf).Count -eq 0) } |
    ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; GroupScope = $_.GroupScope; GroupCategory = $_.GroupCategory; WhenCreated = $_.whenCreated; WhenChanged = $_.whenChanged
                           MemberOfCount = @($_.MemberOf).Count; Description = $_.Description; DistinguishedName = $_.DistinguishedName }
    } | Sort-Object Name | Export-Report -CsvPath $CsvPath
