<#
.SYNOPSIS
    Met à jour en masse les attributs des utilisateurs à partir d'un fichier CSV.

.DESCRIPTION
    Colonne obligatoire : Login. Colonnes reconnues (toutes facultatives) :
    Fonction, Service, Societe, Bureau, Telephone, Mobile, Responsable, Description,
    Adresse, Ville, CodePostal.
    Une cellule vide laisse l'attribut inchangé ; -ClearEmpty l'efface au contraire.
    Seules les valeurs réellement différentes sont écrites. Modèle : exemples/attributs.csv.

.EXAMPLE
    .\Update-UserAttributeFromCsv.ps1 -CsvPath .\attributs.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CsvPath,
    [string]$Delimiter = ';',
    [switch]$ClearEmpty
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

# Colonne du fichier -> paramètre de Set-ADUser / attribut LDAP
$map = [ordered]@{
    Fonction    = @{ Parameter = 'Title';         Ldap = 'title' }
    Service     = @{ Parameter = 'Department';    Ldap = 'department' }
    Societe     = @{ Parameter = 'Company';       Ldap = 'company' }
    Bureau      = @{ Parameter = 'Office';        Ldap = 'physicalDeliveryOfficeName' }
    Telephone   = @{ Parameter = 'OfficePhone';   Ldap = 'telephoneNumber' }
    Mobile      = @{ Parameter = 'MobilePhone';   Ldap = 'mobile' }
    Description = @{ Parameter = 'Description';   Ldap = 'description' }
    Adresse     = @{ Parameter = 'StreetAddress'; Ldap = 'streetAddress' }
    Ville       = @{ Parameter = 'City';          Ldap = 'l' }
    CodePostal  = @{ Parameter = 'PostalCode';    Ldap = 'postalCode' }
    Responsable = @{ Parameter = 'Manager';       Ldap = 'manager' }
}

if (-not (Test-Path -LiteralPath $CsvPath)) { throw "Fichier introuvable : $CsvPath" }
$rows = @(Import-Csv -LiteralPath $CsvPath -Delimiter $Delimiter)
if ($rows.Count -eq 0) { throw 'Le fichier ne contient aucune ligne.' }
$columns = $rows[0].PSObject.Properties.Name
if ('Login' -notin $columns) { throw "Colonne « Login » absente (séparateur attendu : « $Delimiter »)." }
$used = @($map.Keys | Where-Object { $_ -in $columns })
if ($used.Count -eq 0) { throw "Aucune colonne d'attribut reconnue. Colonnes possibles : $($map.Keys -join ', ')." }

foreach ($row in $rows) {
    $result = [pscustomobject]@{ SamAccountName = "$($row.Login)".Trim(); Status = 'Inchangé'; Changes = ''; Detail = '' }
    try {
        $user = Get-ADUser -Identity $result.SamAccountName -Properties ($used | ForEach-Object { $map[$_].Parameter }) -ErrorAction Stop
        $set = @{}; $clear = @(); $changes = @()
        foreach ($column in $used) {
            $value   = "$($row.$column)".Trim()
            $param   = $map[$column].Parameter
            $current = "$($user.$param)"
            if ($column -eq 'Responsable' -and $value) { $value = (Get-ADUser -Identity $value -ErrorAction Stop).DistinguishedName }
            if ($value -and $value -ne $current) { $set[$param] = $value; $changes += "$column : '$current' -> '$value'" }
            elseif (-not $value -and $ClearEmpty -and $current) { $clear += $map[$column].Ldap; $changes += "$column : '$current' -> (vide)" }
        }
        if ($changes.Count -gt 0) {
            $result.Changes = $changes -join ' | '
            $result.Status = 'Simulation'
            if ($PSCmdlet.ShouldProcess($user.DistinguishedName, "Modifier : $($result.Changes)")) {
                if ($clear.Count -gt 0) { $set.Clear = $clear }
                Set-ADUser -Identity $user.DistinguishedName @set -ErrorAction Stop
                $result.Status = 'Modifié'
            }
        }
    }
    catch { $result.Status = 'Erreur'; $result.Detail = $_.Exception.Message }
    $result
}
