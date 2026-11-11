<#
.SYNOPSIS
    Liste les comptes actifs dont des attributs attendus sont vides (qualité de l'annuaire).

.DESCRIPTION
    Attributs contrôlés par défaut : adresse de messagerie, fonction, service, responsable.
    Utile avant une synchronisation Entra ID ou la mise en place de listes dynamiques.

.EXAMPLE
    .\Get-IncompleteUser.ps1 -Attribute mail, Manager -SearchBase 'OU=Utilisateurs,DC=corp,DC=local'
#>
[CmdletBinding()]
param(
    [ValidateSet('mail', 'Title', 'Department', 'Manager', 'Company', 'Office', 'OfficePhone', 'Description', 'GivenName', 'Surname')]
    [string[]]$Attribute = @('mail', 'Title', 'Department', 'Manager'),
    [string]$SearchBase,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$query = @{ Filter = "Enabled -eq `$true"; Properties = $Attribute }
if ($SearchBase) { $query.SearchBase = $SearchBase }
Get-ADUser @query | ForEach-Object {
    $user = $_
    $missing = @($Attribute | Where-Object { -not "$($user.$_)".Trim() })
    if ($missing.Count -gt 0) {
        [pscustomobject]@{ SamAccountName = $user.SamAccountName; Name = $user.Name; Missing = $missing -join ', '; MissingCount = $missing.Count
                           DistinguishedName = $user.DistinguishedName }
    }
} | Sort-Object MissingCount -Descending | Export-Report -CsvPath $CsvPath
