<#
.SYNOPSIS
    Résume les échecs d'authentification relevés sur les contrôleurs de domaine.

.DESCRIPTION
    Lit dans le journal Sécurité de chaque contrôleur de domaine les événements
    4771 (échec de pré-authentification Kerberos) et 4776 (échec de validation NTLM),
    puis les regroupe par compte et par source. De nombreux échecs sur un compte signalent
    un mot de passe mémorisé obsolète ; de nombreux comptes depuis une même source, une
    tentative de pulvérisation de mots de passe.
    Exige l'audit des échecs d'authentification et le droit de lire le journal Sécurité.

.EXAMPLE
    .\Get-FailedLogon.ps1 -Hours 24 -MinimumCount 10
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 720)][int]$Hours = 24,
    [ValidateRange(1, 100000)][int]$MinimumCount = 5,
    [string[]]$Server,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

if (-not $Server) { $Server = @(Get-ADDomainController -Filter * | ForEach-Object HostName) }
$start = (Get-Date).AddHours(-$Hours)

$events = foreach ($dc in $Server) {
    try {
        Get-WinEvent -ComputerName $dc -FilterHashtable @{ LogName = 'Security'; Id = 4771, 4776; StartTime = $start } -ErrorAction Stop | ForEach-Object {
            $data = @{}
            foreach ($node in ([xml]$_.ToXml()).Event.EventData.Data) { $data[$node.Name] = $node.'#text' }
            if ($_.Id -eq 4776 -and "$($data.Status)" -eq '0x0') { return }        # 4776 en succès
            [pscustomobject]@{
                Account = "$($data.TargetUserName)"
                Source  = if ($_.Id -eq 4771) { "$($data.IpAddress)" -replace '^::ffff:' } else { "$($data.Workstation)" }
                Kind    = if ($_.Id -eq 4771) { 'Kerberos' } else { 'NTLM' }
                Code    = "$($data.Status)"
                Time    = $_.TimeCreated
            }
        }
    }
    catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*' -and $_.Exception.Message -notmatch 'No events were found|Aucun événement') {
            Write-Warning "Journal Sécurité de $dc illisible : $($_.Exception.Message)"
        }
    }
}

$events | Where-Object { $_.Account -and $_.Account -notlike '*$' } | Group-Object Account, Source, Kind | Where-Object { $_.Count -ge $MinimumCount } | ForEach-Object {
    $first = $_.Group[0]
    [pscustomobject]@{ Account = $first.Account; Source = $first.Source; Kind = $first.Kind; Count = $_.Count
                       First = ($_.Group | Sort-Object Time | Select-Object -First 1).Time; Last = ($_.Group | Sort-Object Time | Select-Object -Last 1).Time
                       Codes = (@($_.Group.Code | Sort-Object -Unique) -join ', ') }
} | Sort-Object Count -Descending | Export-Report -CsvPath $CsvPath
