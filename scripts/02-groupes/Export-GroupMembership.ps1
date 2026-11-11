<#
.SYNOPSIS
    Exporte les membres des groupes, une ligne par couple groupe / membre.

.DESCRIPTION
    -Name accepte des jokers (« GG_* »). -Recursive développe les groupes imbriqués et
    ne renvoie que les membres finaux. Un groupe vide produit une ligne sans membre.

.EXAMPLE
    .\Export-GroupMembership.ps1 -Name 'GG_*' -Recursive -CsvPath C:\Temp\groupes.csv
#>
[CmdletBinding()]
param(
    [string]$Name = '*',
    [string]$SearchBase,
    [switch]$Recursive,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$query = @{ Filter = "Name -like '$(ConvertTo-FilterValue $Name)'"; Properties = 'Description' }
if ($SearchBase) { $query.SearchBase = $SearchBase }

Get-ADGroup @query | Sort-Object Name | ForEach-Object {
    $group = $_
    try { $members = @(Get-ADGroupMember -Identity $group.DistinguishedName -Recursive:$Recursive -ErrorAction Stop) }
    catch { Write-Warning "Groupe '$($group.Name)' illisible : $($_.Exception.Message)"; return }
    if ($members.Count -eq 0) {
        [pscustomobject]@{ Group = $group.Name; GroupScope = $group.GroupScope; GroupCategory = $group.GroupCategory; Member = ''; MemberName = ''; MemberClass = ''; GroupDescription = $group.Description }
    }
    foreach ($member in $members | Sort-Object SamAccountName) {
        [pscustomobject]@{ Group = $group.Name; GroupScope = $group.GroupScope; GroupCategory = $group.GroupCategory
                           Member = $member.SamAccountName; MemberName = $member.Name; MemberClass = $member.objectClass; GroupDescription = $group.Description }
    }
} | Export-Report -CsvPath $CsvPath
