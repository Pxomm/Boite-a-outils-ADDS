<#
.SYNOPSIS
    Donne la date exacte de dernière ouverture de session d'un utilisateur en interrogeant chaque contrôleur de domaine.

.DESCRIPTION
    L'attribut lastLogon est exact mais n'est pas répliqué : chaque contrôleur de domaine ne
    connaît que les ouvertures de session qu'il a lui-même traitées. Le script les interroge
    tous et retient la date la plus récente. Un contrôleur injoignable est signalé.

.EXAMPLE
    .\Get-UserLastLogon.ps1 -Identity j.dupont
#>
[CmdletBinding()]
param([Parameter(Mandatory, ValueFromPipeline)][string[]]$Identity)

begin {
    . "$PSScriptRoot/../../lib/Communs.ps1"
    Initialize-ADToolbox
    $controllers = @(Get-ADDomainController -Filter *)
}
process {
    foreach ($id in $Identity) {
        $best = $null; $bestDc = ''; $unreachable = @(); $sam = $id; $found = $false
        foreach ($dc in $controllers) {
            try {
                $user = Get-ADUser -Identity $id -Server $dc.HostName -Properties lastLogon -ErrorAction Stop
                $found = $true; $sam = $user.SamAccountName
                $date = ConvertFrom-FileTime $user.lastLogon
                if ($date -and (-not $best -or $date -gt $best)) { $best = $date; $bestDc = $dc.HostName }
            }
            catch {
                if ($_.Exception.GetType().Name -eq 'ADIdentityNotFoundException') { break }   # compte inexistant : inutile de poursuivre
                $unreachable += $dc.HostName
            }
        }
        [pscustomobject]@{
            SamAccountName   = $sam
            LastLogon        = $best
            DomainController = $bestDc
            Status           = if (-not $found -and $unreachable.Count -lt $controllers.Count) { 'Compte introuvable' } elseif ($unreachable) { "Partiel : $($unreachable -join ', ') injoignable(s)" } elseif ($best) { 'OK' } else { 'Jamais connecté' }
        }
    }
}
