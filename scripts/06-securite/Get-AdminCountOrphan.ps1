<#
.SYNOPSIS
    Repère les comptes marqués adminCount = 1 qui ne sont plus membres d'un groupe protégé.

.DESCRIPTION
    Quand un compte entre dans un groupe protégé, AdminSDHolder lui pose adminCount = 1 et
    coupe l'héritage de ses droits. Quand il en sort, rien n'est remis en état : le compte
    garde une liste de contrôle d'accès figée et échappe aux délégations (réinitialisation
    de mot de passe par le support, par exemple). Le script liste ces reliquats.
    -Fix remet adminCount à vide et réactive l'héritage des droits.

.EXAMPLE
    .\Get-AdminCountOrphan.ps1

.EXAMPLE
    .\Get-AdminCountOrphan.ps1 -Fix -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Fix, [string]$CsvPath)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$domain = Get-ADDomain
$sid = $domain.DomainSID.Value
$rootSid = (Get-ADDomain -Identity (Get-ADForest).RootDomain).DomainSID.Value
# Groupes protégés par AdminSDHolder
$protectedGroups = 'S-1-5-32-544', 'S-1-5-32-548', 'S-1-5-32-549', 'S-1-5-32-550', 'S-1-5-32-551', 'S-1-5-32-552',
                   "$sid-512", "$sid-516", "$sid-521", "$rootSid-518", "$rootSid-519"
$stillProtected = New-Object System.Collections.Generic.HashSet[string]
foreach ($group in $protectedGroups) {
    try { Get-ADGroupMember -Identity $group -Recursive -ErrorAction Stop | ForEach-Object { [void]$stillProtected.Add($_.DistinguishedName) } }
    catch { Write-Verbose "Groupe $group absent ou illisible." }
}

$rows = Get-ADUser -Filter 'adminCount -eq 1' -Properties adminCount, whenChanged, Description |
    Where-Object { $_.SamAccountName -notin 'krbtgt' -and $_.SID.Value -notlike '*-500' -and -not $stillProtected.Contains($_.DistinguishedName) } |
    ForEach-Object {
        $user = $_
        $status = 'Reliquat'
        if ($Fix) {
            $status = 'Simulation'
            if ($PSCmdlet.ShouldProcess($user.DistinguishedName, 'Effacer adminCount et réactiver l''héritage des droits')) {
                try {
                    Set-ADUser -Identity $user.DistinguishedName -Clear adminCount -ErrorAction Stop
                    $path = "AD:\$($user.DistinguishedName)"
                    $acl = Get-Acl -Path $path
                    $acl.SetAccessRuleProtection($false, $false)
                    Set-Acl -Path $path -AclObject $acl
                    $status = 'Corrigé'
                }
                catch { $status = "Erreur : $($_.Exception.Message)" }
            }
        }
        [pscustomobject]@{ SamAccountName = $user.SamAccountName; Name = $user.Name; Enabled = $user.Enabled; WhenChanged = $user.whenChanged; Status = $status; DistinguishedName = $user.DistinguishedName }
    }
$rows | Export-Report -CsvPath $CsvPath
