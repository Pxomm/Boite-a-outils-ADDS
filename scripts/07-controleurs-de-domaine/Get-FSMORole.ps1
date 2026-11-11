<#
.SYNOPSIS
    Indique quel contrôleur de domaine détient chacun des cinq rôles FSMO et s'il répond.

.EXAMPLE
    .\Get-FSMORole.ps1 | Format-Table -AutoSize
#>
[CmdletBinding()]
param()

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$domain = Get-ADDomain
$forest = Get-ADForest
$roles = [ordered]@{
    'Contrôleur de schéma'            = @{ Scope = 'Forêt';   Holder = $forest.SchemaMaster }
    'Maître d''attribution de noms'   = @{ Scope = 'Forêt';   Holder = $forest.DomainNamingMaster }
    'Émulateur PDC'                   = @{ Scope = 'Domaine'; Holder = $domain.PDCEmulator }
    'Maître RID'                      = @{ Scope = 'Domaine'; Holder = $domain.RIDMaster }
    'Maître d''infrastructure'        = @{ Scope = 'Domaine'; Holder = $domain.InfrastructureMaster }
}
$reachable = @{}
foreach ($name in $roles.Keys) {
    $holder = $roles[$name].Holder
    if (-not $reachable.ContainsKey($holder)) { $reachable[$holder] = [bool](Test-Connection -ComputerName $holder -Count 1 -Quiet -ErrorAction SilentlyContinue) }
    [pscustomobject]@{ Role = $name; Scope = $roles[$name].Scope; Holder = $holder; Reachable = $reachable[$holder] }
}
