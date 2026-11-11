<#
.SYNOPSIS
    Liste les membres des groupes à privilèges, imbrications comprises.

.DESCRIPTION
    Les groupes sont identifiés par leur SID et non par leur nom : le script fonctionne
    quelle que soit la langue du domaine (« Admins du domaine », « Domain Admins »…).
    Groupes couverts : Administrateurs, Admins du domaine, Administrateurs de l'entreprise,
    Administrateurs du schéma, Opérateurs de compte, de serveur, de sauvegarde, d'impression,
    Propriétaires créateurs de la stratégie de groupe, et DnsAdmins.
    Pour chaque membre : compte actif ou non, dernière connexion, âge du mot de passe,
    appartenance au groupe « Protected Users ».

.EXAMPLE
    .\Get-PrivilegedGroupMember.ps1 -CsvPath C:\Temp\privileges.csv
#>
[CmdletBinding()]
param([string]$CsvPath)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$domain = Get-ADDomain
$sid = $domain.DomainSID.Value
$rootSid = (Get-ADDomain -Identity (Get-ADForest).RootDomain).DomainSID.Value
$wellKnown = [ordered]@{
    'S-1-5-32-544' = 'Administrateurs (intégré)'
    "$sid-512"     = 'Admins du domaine'
    "$rootSid-519" = 'Administrateurs de l''entreprise'
    "$rootSid-518" = 'Administrateurs du schéma'
    'S-1-5-32-548' = 'Opérateurs de compte'
    'S-1-5-32-549' = 'Opérateurs de serveur'
    'S-1-5-32-551' = 'Opérateurs de sauvegarde'
    'S-1-5-32-550' = 'Opérateurs d''impression'
    "$sid-520"     = 'Propriétaires créateurs de la stratégie de groupe'
}
$groups = New-Object System.Collections.Generic.List[object]
foreach ($key in $wellKnown.Keys) {
    try { $groups.Add((Get-ADGroup -Identity $key -ErrorAction Stop | Add-Member -NotePropertyName Role -NotePropertyValue $wellKnown[$key] -PassThru)) }
    catch { Write-Verbose "Groupe $key ($($wellKnown[$key])) absent ou hors de portée." }
}
Get-ADGroup -Filter "SamAccountName -eq 'DnsAdmins'" | ForEach-Object { $groups.Add(($_ | Add-Member -NotePropertyName Role -NotePropertyValue 'DnsAdmins' -PassThru)) }

$protected = @()
try { $protected = @(Get-ADGroupMember -Identity "$sid-525" -Recursive -ErrorAction Stop | ForEach-Object DistinguishedName) }
catch { Write-Verbose 'Groupe Protected Users absent (niveau fonctionnel antérieur à 2012 R2).' }

$cache = @{}
$rows = foreach ($group in $groups) {
    try { $members = @(Get-ADGroupMember -Identity $group.DistinguishedName -Recursive -ErrorAction Stop) }
    catch { Write-Warning "Membres de '$($group.Name)' illisibles : $($_.Exception.Message)"; continue }
    foreach ($member in $members) {
        if (-not $cache.ContainsKey($member.DistinguishedName)) {
            $cache[$member.DistinguishedName] = try { Get-ADObject -Identity $member.DistinguishedName -Properties userAccountControl, lastLogonTimestamp, pwdLastSet -ErrorAction Stop } catch { $null }
        }
        $detail = $cache[$member.DistinguishedName]
        $pwdSet = if ($detail) { ConvertFrom-FileTime $detail.pwdLastSet } else { $null }
        [pscustomobject]@{
            Group            = $group.Name
            Role             = $group.Role
            SamAccountName   = $member.SamAccountName
            Name             = $member.Name
            ObjectClass      = $member.objectClass
            Enabled          = if ($detail -and $null -ne $detail.userAccountControl) { -not ([int]$detail.userAccountControl -band 2) } else { $null }
            LastLogon        = if ($detail) { ConvertFrom-FileTime $detail.lastLogonTimestamp } else { $null }
            PasswordLastSet  = $pwdSet
            PasswordAgeDays  = if ($pwdSet) { [int]((Get-Date) - $pwdSet).TotalDays } else { $null }
            InProtectedUsers = ($member.DistinguishedName -in $protected)
        }
    }
}
$rows | Sort-Object Group, SamAccountName | Export-Report -CsvPath $CsvPath
