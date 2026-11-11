<#
.SYNOPSIS
    Recopie les groupes d'un utilisateur vers un autre (changement de poste, « mêmes droits que »).

.DESCRIPTION
    Ajoute à la cible les groupes de la source qu'elle n'a pas encore.
    -Replace retire en plus de la cible les groupes que la source n'a pas.

.EXAMPLE
    .\Copy-UserGroupMembership.ps1 -Source m.martin -Target j.dupont -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Target,
    [switch]$Replace
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$from = Get-ADUser -Identity $Source -Properties MemberOf -ErrorAction Stop
$to   = Get-ADUser -Identity $Target -Properties MemberOf -ErrorAction Stop
if ($from.DistinguishedName -eq $to.DistinguishedName) { throw 'La source et la cible sont le même compte.' }

$toAdd    = @($from.MemberOf | Where-Object { $_ -notin $to.MemberOf })
$toRemove = if ($Replace) { @($to.MemberOf | Where-Object { $_ -notin $from.MemberOf }) } else { @() }

foreach ($item in @($toAdd | ForEach-Object { @{ Group = $_; Action = 'Ajout' } }) + @($toRemove | ForEach-Object { @{ Group = $_; Action = 'Retrait' } })) {
    $status = 'Simulation'
    try {
        if ($PSCmdlet.ShouldProcess($item.Group, "$($item.Action) de $($to.SamAccountName)")) {
            if ($item.Action -eq 'Ajout') { Add-ADGroupMember -Identity $item.Group -Members $to.DistinguishedName -ErrorAction Stop }
            else { Remove-ADGroupMember -Identity $item.Group -Members $to.DistinguishedName -Confirm:$false -ErrorAction Stop }
            $status = 'Fait'
        }
    }
    catch { $status = "Erreur : $($_.Exception.Message)" }
    [pscustomobject]@{ Target = $to.SamAccountName; Action = $item.Action; Group = $item.Group; Status = $status }
}
