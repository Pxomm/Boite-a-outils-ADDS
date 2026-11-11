<#
.SYNOPSIS
    Liste les délégations de droits posées explicitement sur les unités d'organisation.

.DESCRIPTION
    Lit la liste de contrôle d'accès de chaque OU et ne garde que les entrées explicites
    (non héritées) accordées à d'autres que les comptes système et les groupes
    d'administration intégrés. C'est la trace des « Délégation de contrôle » accordées au fil
    du temps. Nécessite le lecteur AD: fourni par le module ActiveDirectory.

.EXAMPLE
    .\Get-OUDelegation.ps1 -CsvPath C:\Temp\delegations.csv
#>
[CmdletBinding()]
param(
    [string]$SearchBase,
    [switch]$IncludeBuiltin,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$domainSid = (Get-ADDomain).DomainSID.Value
# Identités habituelles, ignorées sauf -IncludeBuiltin
$ignoredSid = @('S-1-5-18', 'S-1-5-10', 'S-1-5-9', 'S-1-5-11', 'S-1-3-0', 'S-1-1-0', 'S-1-5-32-544', 'S-1-5-32-548', 'S-1-5-32-550', 'S-1-5-32-554',
                "$domainSid-512", "$domainSid-519", "$domainSid-516", "$domainSid-498")
$query = @{ Filter = '*' }
if ($SearchBase) { $query.SearchBase = $SearchBase }

Get-ADOrganizationalUnit @query | Sort-Object DistinguishedName | ForEach-Object {
    $ou = $_
    try { $acl = Get-Acl -Path "AD:\$($ou.DistinguishedName)" -ErrorAction Stop }
    catch { Write-Warning "Droits illisibles sur $($ou.DistinguishedName) : $($_.Exception.Message)"; return }
    foreach ($ace in $acl.Access | Where-Object { -not $_.IsInherited }) {
        $sid = try { $ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { "$($ace.IdentityReference)" }
        if (-not $IncludeBuiltin -and $sid -in $ignoredSid) { continue }
        [pscustomobject]@{
            OU                    = $ou.DistinguishedName
            Identity              = "$($ace.IdentityReference)"
            AccessControlType     = "$($ace.AccessControlType)"
            ActiveDirectoryRights = "$($ace.ActiveDirectoryRights)"
            InheritanceType       = "$($ace.InheritanceType)"
            ObjectType            = "$($ace.ObjectType)"
            InheritedObjectType   = "$($ace.InheritedObjectType)"
        }
    }
} | Export-Report -CsvPath $CsvPath
