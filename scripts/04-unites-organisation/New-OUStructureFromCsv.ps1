<#
.SYNOPSIS
    Crée une arborescence d'unités d'organisation à partir d'un fichier CSV.

.DESCRIPTION
    Colonne obligatoire : Chemin, écrit de la racine vers la feuille avec « / » comme
    séparateur (« Societe/Utilisateurs/Comptabilite »). Colonne facultative : Description.
    Les niveaux intermédiaires manquants sont créés. Les OU existantes sont conservées.
    Toutes les OU créées sont protégées contre la suppression accidentelle.
    Modèle : exemples/arborescence-ou.csv.

.PARAMETER Root
    Nom distinctif sous lequel créer l'arborescence (par défaut : la racine du domaine).

.EXAMPLE
    .\New-OUStructureFromCsv.ps1 -CsvPath .\arborescence-ou.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CsvPath,
    [string]$Root,
    [string]$Delimiter = ';'
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

if (-not (Test-Path -LiteralPath $CsvPath)) { throw "Fichier introuvable : $CsvPath" }
$rows = @(Import-Csv -LiteralPath $CsvPath -Delimiter $Delimiter)
if ($rows.Count -eq 0 -or 'Chemin' -notin $rows[0].PSObject.Properties.Name) { throw "Le fichier doit contenir la colonne « Chemin » (séparateur attendu : « $Delimiter »)." }
if (-not $Root) { $Root = (Get-ADDomain).DistinguishedName }

$known = @{}        # OU déjà vérifiées ou (simulées comme) créées pendant cette exécution
foreach ($row in $rows) {
    $segments = @("$($row.Chemin)" -split '/' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($segments.Count -eq 0) { continue }
    $parent = $Root
    for ($i = 0; $i -lt $segments.Count; $i++) {
        $name = $segments[$i]
        # Échappement des caractères réservés d'un nom distinctif
        $dn = "OU=$($name -replace '([,+"\\<>;=])', '\$1'),$parent"
        if (-not $known.ContainsKey($dn)) {
            $status = 'Existe déjà'
            try {
                if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$(ConvertTo-FilterValue $name)'" -SearchBase $parent -SearchScope OneLevel -ErrorAction Stop)) {
                    $status = 'Simulation'
                    if ($PSCmdlet.ShouldProcess($dn, 'Créer l''unité d''organisation')) {
                        $new = @{ Name = $name; Path = $parent; ProtectedFromAccidentalDeletion = $true }
                        if ($i -eq $segments.Count - 1 -and "$($row.Description)".Trim()) { $new.Description = "$($row.Description)".Trim() }
                        New-ADOrganizationalUnit @new -ErrorAction Stop
                        $status = 'Créée'
                    }
                }
            }
            catch {
                # En simulation, le parent n'existe pas encore : la recherche échoue, c'est attendu
                if ($WhatIfPreference -and $known[$parent] -eq 'Simulation') { $status = 'Simulation' }
                else { $status = "Erreur : $($_.Exception.Message)" }
            }
            $known[$dn] = $status
            [pscustomobject]@{ DistinguishedName = $dn; Status = $status }
            if ($status -like 'Erreur*') { break }
        }
        $parent = $dn
    }
}
