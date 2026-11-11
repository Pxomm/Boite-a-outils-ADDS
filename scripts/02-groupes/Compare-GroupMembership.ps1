<#
.SYNOPSIS
    Compare les membres de deux groupes, ou les groupes de deux utilisateurs.

.DESCRIPTION
    -ReferenceGroup / -DifferenceGroup : compare les membres (avec -Recursive, les membres finaux).
    -ReferenceUser / -DifferenceUser : compare les groupes dont chaque utilisateur est membre direct.
    Colonne Side : « Les deux », « Référence seulement » ou « Différence seulement ».

.EXAMPLE
    .\Compare-GroupMembership.ps1 -ReferenceUser m.martin -DifferenceUser j.dupont

.EXAMPLE
    .\Compare-GroupMembership.ps1 -ReferenceGroup GG_Compta -DifferenceGroup GG_Compta_Lecture -Recursive
#>
[CmdletBinding(DefaultParameterSetName = 'Group')]
param(
    [Parameter(ParameterSetName = 'Group', Mandatory)][string]$ReferenceGroup,
    [Parameter(ParameterSetName = 'Group', Mandatory)][string]$DifferenceGroup,
    [Parameter(ParameterSetName = 'Group')][switch]$Recursive,
    [Parameter(ParameterSetName = 'User', Mandatory)][string]$ReferenceUser,
    [Parameter(ParameterSetName = 'User', Mandatory)][string]$DifferenceUser,
    [switch]$DifferencesOnly
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

if ($PSCmdlet.ParameterSetName -eq 'Group') {
    $left  = @(Get-ADGroupMember -Identity $ReferenceGroup -Recursive:$Recursive -ErrorAction Stop | ForEach-Object SamAccountName)
    $right = @(Get-ADGroupMember -Identity $DifferenceGroup -Recursive:$Recursive -ErrorAction Stop | ForEach-Object SamAccountName)
}
else {
    $toName = { param($dn) ($dn -split '(?<!\\),')[0] -replace '^CN=' }
    $left  = @((Get-ADUser -Identity $ReferenceUser -Properties MemberOf -ErrorAction Stop).MemberOf | ForEach-Object { & $toName $_ })
    $right = @((Get-ADUser -Identity $DifferenceUser -Properties MemberOf -ErrorAction Stop).MemberOf | ForEach-Object { & $toName $_ })
}

@($left) + @($right) | Sort-Object -Unique | ForEach-Object {
    $side = if ($_ -in $left -and $_ -in $right) { 'Les deux' } elseif ($_ -in $left) { 'Référence seulement' } else { 'Différence seulement' }
    if (-not $DifferencesOnly -or $side -ne 'Les deux') { [pscustomobject]@{ Item = $_; Side = $side } }
}
