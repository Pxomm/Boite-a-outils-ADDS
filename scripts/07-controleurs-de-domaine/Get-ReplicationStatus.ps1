<#
.SYNOPSIS
    Contrôle la réplication Active Directory entre contrôleurs de domaine.

.DESCRIPTION
    Pour chaque contrôleur et chaque partenaire entrant : partition, date de la dernière
    réplication réussie, code du dernier résultat (0 = succès), nombre d'échecs consécutifs.
    Un lien est signalé (Healthy = False) en cas d'échec ou si la dernière réussite date de
    plus de -MaxHours heures. -ProblemsOnly ne renvoie que ces liens.

.EXAMPLE
    .\Get-ReplicationStatus.ps1 -ProblemsOnly
#>
[CmdletBinding()]
param(
    [string[]]$Server,
    [ValidateRange(1, 720)][int]$MaxHours = 24,
    [switch]$ProblemsOnly,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

if (-not $Server) { $Server = @(Get-ADDomainController -Filter * | Sort-Object HostName | ForEach-Object HostName) }
$limit = (Get-Date).AddHours(-$MaxHours)

$rows = foreach ($dc in $Server) {
    try {
        Get-ADReplicationPartnerMetadata -Target $dc -Partition * -ErrorAction Stop | ForEach-Object {
            $partner = if ("$($_.Partner)" -match '^CN=NTDS Settings,CN=([^,]+),') { $Matches[1] } else { "$($_.Partner)" }
            $healthy = ($_.LastReplicationResult -eq 0 -and $_.ConsecutiveReplicationFailures -eq 0 -and $_.LastReplicationSuccess -and $_.LastReplicationSuccess -ge $limit)
            [pscustomobject]@{ Server = $dc; Partner = $partner; Partition = $_.Partition; LastSuccess = $_.LastReplicationSuccess; LastAttempt = $_.LastReplicationAttempt
                               LastResult = $_.LastReplicationResult; ConsecutiveFailures = $_.ConsecutiveReplicationFailures; Healthy = [bool]$healthy }
        }
    }
    catch {
        [pscustomobject]@{ Server = $dc; Partner = ''; Partition = ''; LastSuccess = $null; LastAttempt = $null; LastResult = $null; ConsecutiveFailures = $null; Healthy = $false }
        Write-Warning "Réplication de $dc illisible : $($_.Exception.Message)"
    }
}
$rows | Where-Object { -not $ProblemsOnly -or -not $_.Healthy } | Sort-Object Healthy, Server, Partner, Partition | Export-Report -CsvPath $CsvPath
