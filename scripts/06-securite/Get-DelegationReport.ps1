<#
.SYNOPSIS
    Inventorie les délégations Kerberos : non contrainte, contrainte, basée sur les ressources.

.DESCRIPTION
      - Non contrainte : le compte peut emprunter l'identité de tout utilisateur qui s'y
        authentifie, vers n'importe quel service. À proscrire hors contrôleurs de domaine
        (ignorés ici) ;
      - Contrainte : délégation limitée aux services listés (msDS-AllowedToDelegateTo) ;
        « avec transition de protocole » si le compte peut s'authentifier pour le compte
        d'autrui sans ticket initial ;
      - Basée sur les ressources (RBCD) : la ressource désigne qui peut déléguer vers elle.

.EXAMPLE
    .\Get-DelegationReport.ps1 -CsvPath C:\Temp\delegations-kerberos.csv
#>
[CmdletBinding()]
param([string]$CsvPath)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$properties = 'TrustedForDelegation', 'TrustedToAuthForDelegation', 'msDS-AllowedToDelegateTo', 'PrincipalsAllowedToDelegateToAccount', 'PrimaryGroupID', 'userAccountControl'
$objects = @(Get-ADComputer -Filter * -Properties $properties) + @(Get-ADUser -Filter * -Properties $properties)

$rows = foreach ($object in $objects) {
    if ($object.PrimaryGroupID -in 516, 521) { continue }                 # contrôleurs de domaine
    $enabled = -not ([int]$object.userAccountControl -band 2)
    if ($object.TrustedForDelegation) {
        [pscustomobject]@{ SamAccountName = $object.SamAccountName; ObjectClass = $object.objectClass; Enabled = $enabled; DelegationType = 'Non contrainte'; Target = '(tous les services)' }
    }
    $allowed = @($object.'msDS-AllowedToDelegateTo' | Where-Object { $_ })
    if ($allowed.Count -gt 0) {
        $kind = if ($object.TrustedToAuthForDelegation) { 'Contrainte avec transition de protocole' } else { 'Contrainte' }
        [pscustomobject]@{ SamAccountName = $object.SamAccountName; ObjectClass = $object.objectClass; Enabled = $enabled; DelegationType = $kind; Target = $allowed -join ', ' }
    }
    $principals = @($object.PrincipalsAllowedToDelegateToAccount | Where-Object { $_ })
    if ($principals.Count -gt 0) {
        [pscustomobject]@{ SamAccountName = $object.SamAccountName; ObjectClass = $object.objectClass; Enabled = $enabled; DelegationType = 'Basée sur les ressources (vers ce compte)'
                           Target = (@($principals | ForEach-Object { ("$_" -split '(?<!\\),')[0] -replace '^CN=' }) -join ', ') }
    }
}
$rows | Sort-Object DelegationType, SamAccountName | Export-Report -CsvPath $CsvPath
