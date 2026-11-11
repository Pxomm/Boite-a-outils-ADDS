<#
.SYNOPSIS
    Liste les comptes autorisés à répliquer les secrets de l'annuaire (droit « DCSync »).

.DESCRIPTION
    Les droits étendus « Répliquer les changements de l'annuaire » et « … tous les
    changements » sur la racine du domaine permettent de demander à un contrôleur de domaine
    les condensés de mots de passe de n'importe quel compte, krbtgt compris. Seuls les
    contrôleurs de domaine et les groupes d'administration intégrés doivent les détenir ;
    toute autre entrée (colonne Expected = False) est à justifier : synchronisation Entra
    Connect, ou compromission.

.EXAMPLE
    .\Get-DCSyncRight.ps1 | Where-Object { -not $_.Expected }
#>
[CmdletBinding()]
param([string]$CsvPath)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$domain = Get-ADDomain
$sid = $domain.DomainSID.Value
$rights = @{
    '1131f6aa-9c07-11d1-f79f-00c04fc2dcd2' = 'Répliquer les changements de l''annuaire'
    '1131f6ad-9c07-11d1-f79f-00c04fc2dcd2' = 'Répliquer tous les changements de l''annuaire'
    '89e95b76-444d-4c62-991a-0facbeda640c' = 'Répliquer les changements dans un jeu filtré'
}
# Détenteurs attendus : Système, Administrateurs, contrôleurs de domaine (y compris d'entreprise et en lecture seule)
$expected = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-9', "$sid-516", "$sid-498", "$sid-512", "$sid-521")
$rootSid = (Get-ADDomain -Identity (Get-ADForest).RootDomain).DomainSID.Value
$expected += "$rootSid-519", "$rootSid-498"

$acl = Get-Acl -Path "AD:\$($domain.DistinguishedName)" -ErrorAction Stop
$rows = foreach ($ace in $acl.Access) {
    if ("$($ace.AccessControlType)" -ne 'Allow') { continue }
    $guid = "$($ace.ObjectType)".ToLowerInvariant()
    $isGenericAll = ("$($ace.ActiveDirectoryRights)" -match 'GenericAll')
    $isExtended   = ("$($ace.ActiveDirectoryRights)" -match 'ExtendedRight')
    $allRights    = ($guid -eq '00000000-0000-0000-0000-000000000000')
    if (-not ($isGenericAll -or ($isExtended -and ($rights.ContainsKey($guid) -or $allRights)))) { continue }
    $aceSid = try { $ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { "$($ace.IdentityReference)" }
    [pscustomobject]@{
        Identity = "$($ace.IdentityReference)"
        Right    = if ($isGenericAll) { 'Contrôle total' } elseif ($allRights) { 'Tous les droits étendus' } else { $rights[$guid] }
        Expected = ($aceSid -in $expected)
        Sid      = $aceSid
    }
}
$rows | Sort-Object Expected, Identity, Right -Unique | Export-Report -CsvPath $CsvPath
