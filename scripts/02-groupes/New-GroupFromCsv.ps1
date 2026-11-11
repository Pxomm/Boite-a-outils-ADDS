<#
.SYNOPSIS
    Crée des groupes en masse à partir d'un fichier CSV.

.DESCRIPTION
    Colonnes (séparateur « ; ») : Nom;OU, et facultativement Etendue (Global, DomainLocal,
    Universal ; Global par défaut), Type (Security ou Distribution ; Security par défaut),
    Description. Un groupe déjà existant est signalé, pas modifié.
    Modèle : exemples/groupes.csv.

.EXAMPLE
    .\New-GroupFromCsv.ps1 -CsvPath .\groupes.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CsvPath,
    [string]$Delimiter = ';'
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

if (-not (Test-Path -LiteralPath $CsvPath)) { throw "Fichier introuvable : $CsvPath" }
$rows = @(Import-Csv -LiteralPath $CsvPath -Delimiter $Delimiter)
if ($rows.Count -eq 0) { throw 'Le fichier ne contient aucune ligne.' }
$missing = @('Nom', 'OU' | Where-Object { $_ -notin $rows[0].PSObject.Properties.Name })
if ($missing) { throw "Colonne(s) absente(s) : $($missing -join ', ') (séparateur attendu : « $Delimiter »)." }

foreach ($row in $rows) {
    $name = "$($row.Nom)".Trim(); $path = "$($row.OU)".Trim()
    $scope = if ("$($row.Etendue)".Trim()) { "$($row.Etendue)".Trim() } else { 'Global' }
    $category = if ("$($row.Type)".Trim()) { "$($row.Type)".Trim() } else { 'Security' }
    $result = [pscustomobject]@{ Name = $name; GroupScope = $scope; GroupCategory = $category; Path = $path; Status = ''; Detail = '' }
    try {
        if (-not $name -or -not $path) { throw 'Nom et OU sont obligatoires.' }
        if ($name.Length -gt 64) { throw 'Nom de plus de 64 caractères.' }
        if ($scope -notin 'Global', 'DomainLocal', 'Universal') { throw "Etendue inconnue '$scope'." }
        if ($category -notin 'Security', 'Distribution') { throw "Type inconnu '$category'." }
        if (Get-ADGroup -Filter "SamAccountName -eq '$(ConvertTo-FilterValue $name)'") { $result.Status = 'Existe déjà' }
        else {
            $null = Get-ADOrganizationalUnit -Identity $path -ErrorAction Stop
            $new = @{ Name = $name; SamAccountName = $name; GroupScope = $scope; GroupCategory = $category; Path = $path }
            if ("$($row.Description)".Trim()) { $new.Description = "$($row.Description)".Trim() }
            if ($PSCmdlet.ShouldProcess("$name dans $path", "Créer le groupe ($scope, $category)")) { New-ADGroup @new -ErrorAction Stop; $result.Status = 'Créé' }
            else { $result.Status = 'Simulation' }
        }
    }
    catch { $result.Status = 'Erreur'; $result.Detail = $_.Exception.Message }
    $result
}
