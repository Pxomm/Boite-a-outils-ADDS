<#
.SYNOPSIS
    Mesure l'écart d'horloge de chaque contrôleur de domaine et indique la source de temps de l'émulateur PDC.

.DESCRIPTION
    Kerberos refuse les authentifications au-delà de 5 minutes d'écart. Dans un domaine,
    tous les contrôleurs se synchronisent sur l'émulateur PDC, qui doit lui-même suivre une
    source externe fiable (serveurs NTP) et non l'horloge de sa carte mère ou de son
    hyperviseur. L'écart est mesuré par « w32tm /stripchart » depuis le poste d'exécution,
    par rapport à l'émulateur PDC.

.EXAMPLE
    .\Get-TimeSyncStatus.ps1 -MaxOffsetSeconds 2
#>
[CmdletBinding()]
param(
    [ValidateRange(0.1, 300)][double]$MaxOffsetSeconds = 5,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox
if (-not (Get-Command w32tm.exe -ErrorAction SilentlyContinue)) { throw 'w32tm.exe introuvable : ce script s''exécute sous Windows.' }

$pdc = (Get-ADDomain).PDCEmulator
$source = (@(& w32tm.exe /query /source "/computer:$pdc" 2>&1 | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join ' ')
# Sources internes : l'émulateur PDC n'est alors synchronisé sur rien de fiable
$sourceOk = ($LASTEXITCODE -eq 0 -and $source -notmatch 'Local CMOS Clock|Free-running System Clock|VM IC Time Synchronization Provider')

$rows = foreach ($dc in Get-ADDomainController -Filter * | Sort-Object HostName) {
    $output = @(& w32tm.exe /stripchart "/computer:$($dc.HostName)" /samples:1 /dataonly 2>&1 | ForEach-Object { "$_" })
    $offset = $null
    foreach ($line in $output) { if ($line -match '([+-]\d+[.,]\d+)s\s*$') { $offset = [double]($Matches[1] -replace ',', '.') } }
    $isPdc = ($dc.HostName -eq $pdc)
    [pscustomobject]@{
        HostName      = $dc.HostName
        IsPDCEmulator = $isPdc
        OffsetSeconds = $offset
        TimeSource    = if ($isPdc) { $source } else { '(hiérarchie du domaine)' }
        Ok            = ($null -ne $offset -and [Math]::Abs($offset) -le $MaxOffsetSeconds -and (-not $isPdc -or $sourceOk))
        Detail        = if ($null -eq $offset) { 'mesure impossible' } elseif ([Math]::Abs($offset) -gt $MaxOffsetSeconds) { "écart supérieur à $MaxOffsetSeconds s" } elseif ($isPdc -and -not $sourceOk) { 'source de temps interne ou illisible : configurer des serveurs NTP externes' } else { '' }
    }
}
$rows | Export-Report -CsvPath $CsvPath
