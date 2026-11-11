<#
.SYNOPSIS
    Lance dcdiag et repadmin sur chaque contrôleur de domaine et archive les résultats.

.DESCRIPTION
    Pour chaque contrôleur : « dcdiag /s:<dc> /q », qui n'affiche que les erreurs — une
    sortie vide signifie donc que tous les tests passent. Puis, une fois pour le domaine,
    « repadmin /replsummary » et « repadmin /showrepl * /csv ». Tous les résultats sont
    enregistrés dans un dossier daté. À exécuter sur un contrôleur de domaine ou un poste
    disposant des outils RSAT, avec un compte administrateur du domaine.

.EXAMPLE
    .\Invoke-DCDiagnostic.ps1 -OutputDirectory D:\Journaux\Diagnostics
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string[]]$Server,
    [switch]$IncludeDns
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

foreach ($tool in 'dcdiag.exe', 'repadmin.exe') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool introuvable : exécuter ce script sur un contrôleur de domaine ou installer les outils RSAT AD DS." }
}
if (-not $Server) { $Server = @(Get-ADDomainController -Filter * | Sort-Object HostName | ForEach-Object HostName) }
$folder = Join-Path $OutputDirectory (Get-Date -Format 'yyyy-MM-dd_HHmmss')
New-Item -ItemType Directory -Path $folder -Force | Out-Null

foreach ($dc in $Server) {
    $arguments = @("/s:$dc", '/q')
    if ($IncludeDns) { $arguments += '/test:dns' }
    $output = @(& dcdiag.exe @arguments 2>&1 | ForEach-Object { "$_" })
    $file = Join-Path $folder "dcdiag_$dc.txt"
    $errors = @($output | Where-Object { $_.Trim() })
    $(if ($errors.Count -gt 0) { $output } else { 'Aucune erreur signalée par dcdiag /q.' }) | Set-Content -LiteralPath $file -Encoding UTF8
    [pscustomobject]@{ Server = $dc; Test = 'dcdiag'; Passed = ($errors.Count -eq 0); ErrorLines = $errors.Count; File = $file }
}

$summary = Join-Path $folder 'repadmin_replsummary.txt'
& repadmin.exe /replsummary 2>&1 | ForEach-Object { "$_" } | Set-Content -LiteralPath $summary -Encoding UTF8
$showrepl = Join-Path $folder 'repadmin_showrepl.csv'
$csv = @(& repadmin.exe /showrepl * /csv 2>&1 | ForEach-Object { "$_" })
$csv | Set-Content -LiteralPath $showrepl -Encoding UTF8
# Colonne « Number of Failures » : libellé invariant de la sortie CSV de repadmin
$failures = @($csv | ConvertFrom-Csv -ErrorAction SilentlyContinue | Where-Object { $_.'Number of Failures' -and [int]$_.'Number of Failures' -gt 0 })
[pscustomobject]@{ Server = '(domaine)'; Test = 'repadmin'; Passed = ($failures.Count -eq 0); ErrorLines = $failures.Count; File = $showrepl }
