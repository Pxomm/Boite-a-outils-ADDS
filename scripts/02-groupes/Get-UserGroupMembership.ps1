<#
.SYNOPSIS
    Liste tous les groupes d'un utilisateur, y compris ceux hérités par imbrication.

.DESCRIPTION
    Utilise la règle de correspondance LDAP « en chaîne » (1.2.840.113556.1.4.1941), évaluée
    par le contrôleur de domaine : une seule requête, quelle que soit la profondeur.
    La colonne Direct distingue l'appartenance directe de l'appartenance héritée.
    Le groupe principal (en général « Utilisateurs du domaine ») n'apparaît pas dans memberOf.

.EXAMPLE
    .\Get-UserGroupMembership.ps1 -Identity j.dupont
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline)][string[]]$Identity,
    [string]$CsvPath
)

begin {
    . "$PSScriptRoot/../../lib/Communs.ps1"
    Initialize-ADToolbox
    $rows = New-Object System.Collections.Generic.List[object]
}
process {
    foreach ($id in $Identity) {
        $user = Get-ADUser -Identity $id -Properties MemberOf -ErrorAction Stop
        # Échappement des caractères réservés d'un filtre LDAP dans le nom distinctif
        $dn = $user.DistinguishedName.Replace('\', '\5c').Replace('(', '\28').Replace(')', '\29').Replace('*', '\2a')
        Get-ADGroup -LDAPFilter "(member:1.2.840.113556.1.4.1941:=$dn)" -Properties Description | ForEach-Object {
            $rows.Add([pscustomobject]@{ SamAccountName = $user.SamAccountName; Group = $_.Name; Direct = ($_.DistinguishedName -in $user.MemberOf)
                                        GroupScope = $_.GroupScope; GroupCategory = $_.GroupCategory; Description = $_.Description })
        }
    }
}
end { $rows | Sort-Object SamAccountName, @{ Expression = 'Direct'; Descending = $true }, Group | Export-Report -CsvPath $CsvPath }
