<#
.SYNOPSIS
    Contrôle la topologie des sites : sous-réseaux, contrôleurs de domaine, anomalies.

.DESCRIPTION
    Une ligne par site : sous-réseaux rattachés, contrôleurs de domaine, catalogue global.
    Anomalies signalées : site sans sous-réseau (les postes ne peuvent pas s'y rattacher),
    site sans contrôleur de domaine, sous-réseau rattaché à aucun site.
    Un poste dont l'adresse n'appartient à aucun sous-réseau déclaré s'authentifie auprès
    d'un contrôleur quelconque, parfois distant : ces postes sont consignés dans
    %SystemRoot%\debug\netlogon.log de chaque contrôleur (lignes NO_CLIENT_SITE).

.EXAMPLE
    .\Get-SiteSubnetReport.ps1 | Format-Table -AutoSize
#>
[CmdletBinding()]
param([string]$CsvPath)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$subnets = @(Get-ADReplicationSubnet -Filter *)
$controllers = @(Get-ADDomainController -Filter *)

$rows = @(Get-ADReplicationSite -Filter * | Sort-Object Name | ForEach-Object {
    $site = $_
    $siteSubnets = @($subnets | Where-Object { $_.Site -eq $site.DistinguishedName } | ForEach-Object Name)
    $siteDcs = @($controllers | Where-Object { $_.Site -eq $site.Name })
    $issues = @()
    if ($siteSubnets.Count -eq 0) { $issues += 'aucun sous-réseau' }
    if ($siteDcs.Count -eq 0) { $issues += 'aucun contrôleur de domaine' }
    elseif (@($siteDcs | Where-Object IsGlobalCatalog).Count -eq 0) { $issues += 'aucun catalogue global' }
    [pscustomobject]@{ Site = $site.Name; Subnets = $siteSubnets -join ', '; DomainControllers = (@($siteDcs.Name) -join ', ')
                       GlobalCatalogs = @($siteDcs | Where-Object IsGlobalCatalog).Count; Issues = $issues -join ' ; ' }
})
$rows += @($subnets | Where-Object { -not $_.Site } | ForEach-Object {
    [pscustomobject]@{ Site = '(aucun)'; Subnets = $_.Name; DomainControllers = ''; GlobalCatalogs = 0; Issues = 'sous-réseau rattaché à aucun site' }
})
$rows | Export-Report -CsvPath $CsvPath
