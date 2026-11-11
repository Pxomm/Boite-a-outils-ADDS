<#
.SYNOPSIS
    Crée des comptes utilisateurs en masse à partir d'un fichier CSV.

.DESCRIPTION
    Colonnes attendues (séparateur « ; ») : Prenom;Nom;OU, et facultativement
    Login;Groupes;Fonction;Service;Description;Modele.
    « Groupes » contient plusieurs groupes séparés par une virgule ; « Modele » est un compte
    dont les groupes sont recopiés. Chaque ligne est traitée indépendamment : une erreur
    n'arrête pas les suivantes. Modèle de fichier : exemples/utilisateurs.csv.

.PARAMETER OutputCsvPath
    Fichier recevant les identifiants et mots de passe initiaux. À protéger puis supprimer
    après remise des comptes.

.EXAMPLE
    .\Import-UsersFromCsv.ps1 -CsvPath .\utilisateurs.csv -WhatIf

.EXAMPLE
    .\Import-UsersFromCsv.ps1 -CsvPath .\utilisateurs.csv -OutputCsvPath C:\Temp\comptes-crees.csv
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CsvPath,
    [string]$Delimiter = ';',
    [string]$OutputCsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

if (-not (Test-Path -LiteralPath $CsvPath)) { throw "Fichier introuvable : $CsvPath" }
$rows = @(Import-Csv -LiteralPath $CsvPath -Delimiter $Delimiter)
if ($rows.Count -eq 0) { throw 'Le fichier ne contient aucune ligne.' }
$missing = @('Prenom', 'Nom', 'OU' | Where-Object { $_ -notin $rows[0].PSObject.Properties.Name })
if ($missing) { throw "Colonne(s) obligatoire(s) absente(s) : $($missing -join ', ') (séparateur attendu : « $Delimiter »)." }

$line = 1
$results = foreach ($row in $rows) {
    $line++
    try {
        if (-not "$($row.Prenom)".Trim() -or -not "$($row.Nom)".Trim() -or -not "$($row.OU)".Trim()) { throw 'Prenom, Nom et OU sont obligatoires.' }
        $p = @{ GivenName = $row.Prenom; Surname = $row.Nom; Path = "$($row.OU)".Trim() }
        if ("$($row.Login)".Trim())       { $p.SamAccountName = "$($row.Login)".Trim() }
        if ("$($row.Groupes)".Trim())     { $p.Group = @("$($row.Groupes)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
        if ("$($row.Fonction)".Trim())    { $p.Title = "$($row.Fonction)".Trim() }
        if ("$($row.Service)".Trim())     { $p.Department = "$($row.Service)".Trim() }
        if ("$($row.Description)".Trim()) { $p.Description = "$($row.Description)".Trim() }
        if ("$($row.Modele)".Trim())      { $p.CopyGroupsFrom = "$($row.Modele)".Trim() }
        $created = & "$PSScriptRoot/New-UserAccount.ps1" @p -WhatIf:$WhatIfPreference -ErrorAction Stop
        $created | Add-Member -NotePropertyName Line -NotePropertyValue $line -PassThru |
            Add-Member -NotePropertyName Detail -NotePropertyValue '' -PassThru
    }
    catch {
        [pscustomobject]@{ SamAccountName = "$($row.Login)"; UserPrincipalName = ''; Name = "$($row.Prenom) $($row.Nom)"; Path = "$($row.OU)"
                           Status = 'Erreur'; GroupCount = 0; InitialPassword = ''; Line = $line; Detail = $_.Exception.Message }
    }
}

if ($OutputCsvPath -and -not $WhatIfPreference) {
    $results | Where-Object InitialPassword | Select-Object SamAccountName, UserPrincipalName, Name, InitialPassword | Export-Report -CsvPath $OutputCsvPath | Out-Null
    Write-Warning "Mots de passe initiaux écrits dans $OutputCsvPath : fichier à protéger, puis à supprimer."
    $results | Select-Object Line, SamAccountName, Name, Path, Status, GroupCount, Detail
}
else { $results | Select-Object Line, SamAccountName, Name, Path, Status, GroupCount, InitialPassword, Detail }
