<#
.SYNOPSIS
    Inventorie les liens de stratégies de groupe : quelle GPO s'applique où, dans quel ordre.

.DESCRIPTION
    Parcourt la racine du domaine et chaque unité d'organisation, et renvoie une ligne par
    lien : ordre, lien activé ou non, « Appliqué » (Enforced), héritage bloqué sur la cible.
    À conserver avec les sauvegardes : les liens ne sont pas inclus dans une sauvegarde de GPO.

.EXAMPLE
    .\Get-GPOLink.ps1 -CsvPath D:\Sauvegardes\GPO\liens.csv
#>
[CmdletBinding()]
param([string]$SearchBase, [string]$CsvPath)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox -GroupPolicy

$domainDn = (Get-ADDomain).DistinguishedName
$query = @{ Filter = '*' }
if ($SearchBase) { $query.SearchBase = $SearchBase }
$targets = @()
if (-not $SearchBase -or $SearchBase -eq $domainDn) { $targets += $domainDn }
$targets += @(Get-ADOrganizationalUnit @query | Sort-Object DistinguishedName | ForEach-Object DistinguishedName)

$rows = foreach ($target in $targets) {
    try { $inheritance = Get-GPInheritance -Target $target -ErrorAction Stop }
    catch { Write-Warning "Liens illisibles sur $target : $($_.Exception.Message)"; continue }
    foreach ($link in $inheritance.GpoLinks) {
        [pscustomobject]@{ Target = $target; Order = $link.Order; DisplayName = $link.DisplayName; LinkEnabled = $link.Enabled; Enforced = $link.Enforced
                           InheritanceBlocked = [bool]$inheritance.GpoInheritanceBlocked; GpoId = $link.GpoId }
    }
}
$rows | Export-Report -CsvPath $CsvPath
