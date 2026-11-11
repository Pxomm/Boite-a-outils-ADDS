<#
.SYNOPSIS
    Exporte l'arborescence des unités d'organisation avec le nombre d'objets et de stratégies liées.

.DESCRIPTION
    Pour chaque OU : profondeur, nombre d'utilisateurs, d'ordinateurs et de groupes placés
    directement dedans, nombre de GPO liées, héritage bloqué ou non, protection contre la
    suppression. -AsTree renvoie une représentation indentée, prête à coller dans une
    documentation.

.EXAMPLE
    .\Export-OUTree.ps1 -AsTree

.EXAMPLE
    .\Export-OUTree.ps1 -CsvPath C:\Temp\arborescence.csv
#>
[CmdletBinding()]
param(
    [string]$SearchBase,
    [switch]$AsTree,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

if (-not $SearchBase) { $SearchBase = (Get-ADDomain).DistinguishedName }
$parentOf = { param($dn) ($dn -split '(?<!\\),', 2)[1] }

# Un seul parcours par type d'objet, puis décompte par conteneur parent
$count = @{ user = @{}; computer = @{}; group = @{} }
Get-ADUser     -Filter * -SearchBase $SearchBase | ForEach-Object { $p = & $parentOf $_.DistinguishedName; $count.user[$p]     = 1 + [int]$count.user[$p] }
Get-ADComputer -Filter * -SearchBase $SearchBase | ForEach-Object { $p = & $parentOf $_.DistinguishedName; $count.computer[$p] = 1 + [int]$count.computer[$p] }
Get-ADGroup    -Filter * -SearchBase $SearchBase | ForEach-Object { $p = & $parentOf $_.DistinguishedName; $count.group[$p]    = 1 + [int]$count.group[$p] }

$baseDepth = @($SearchBase -split '(?<!\\),').Count
$rows = Get-ADOrganizationalUnit -Filter * -SearchBase $SearchBase -Properties gPLink, gPOptions, ProtectedFromAccidentalDeletion, Description | ForEach-Object {
    $parts = @($_.DistinguishedName -split '(?<!\\),')
    [pscustomobject]@{
        Name               = $_.Name
        Depth              = $parts.Count - $baseDepth
        Users              = [int]$count.user[$_.DistinguishedName]
        Computers          = [int]$count.computer[$_.DistinguishedName]
        Groups             = [int]$count.group[$_.DistinguishedName]
        LinkedGPO          = ([regex]::Matches("$($_.gPLink)", '\[LDAP://')).Count
        InheritanceBlocked = ($_.gPOptions -eq 1)
        Protected          = [bool]$_.ProtectedFromAccidentalDeletion
        Description        = $_.Description
        DistinguishedName  = $_.DistinguishedName
        # Clé de tri : chemin de la racine vers la feuille
        SortKey            = ($parts[($parts.Count - 1)..0] -join '/')
    }
} | Sort-Object SortKey

if ($AsTree) {
    $rows | ForEach-Object { '{0}{1}  [utilisateurs : {2}, ordinateurs : {3}, groupes : {4}, GPO : {5}]' -f ('    ' * [Math]::Max(0, $_.Depth - 1)), $_.Name, $_.Users, $_.Computers, $_.Groups, $_.LinkedGPO }
}
else { $rows | Select-Object * -ExcludeProperty SortKey | Export-Report -CsvPath $CsvPath }
