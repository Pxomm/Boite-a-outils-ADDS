<#
.SYNOPSIS
    Liste les enregistrements DNS dynamiques qui n'ont pas été rafraîchis depuis N jours.

.DESCRIPTION
    Dans une zone intégrée à Active Directory, les postes renouvellent leur enregistrement
    tous les 7 jours environ. Un enregistrement dynamique plus ancien correspond en général
    à une machine disparue. Les enregistrements statiques (sans horodatage) ne sont jamais
    renvoyés. Le script indique aussi si le nettoyage automatique (scavenging) est actif sur
    la zone : c'est lui qu'il faut activer plutôt que supprimer à la main.
    Nécessite le module DnsServer (outils RSAT DNS).

.EXAMPLE
    .\Get-StaleDnsRecord.ps1 -ZoneName corp.local -Days 30 -ComputerName dc01
#>
[CmdletBinding()]
param(
    [string]$ZoneName,
    [ValidateRange(8, 3650)][int]$Days = 30,
    [string]$ComputerName,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox -DnsServer

if (-not $ComputerName) { $ComputerName = (Get-ADDomain).PDCEmulator }
if (-not $ZoneName) { $ZoneName = (Get-ADDomain).DNSRoot }
$limit = (Get-Date).AddDays(-$Days)

$aging = Get-DnsServerZoneAging -Name $ZoneName -ComputerName $ComputerName -ErrorAction Stop
if (-not $aging.AgingEnabled) { Write-Warning "Le vieillissement n'est pas activé sur la zone $ZoneName : les enregistrements obsolètes ne sont jamais nettoyés automatiquement." }

Get-DnsServerResourceRecord -ZoneName $ZoneName -ComputerName $ComputerName -ErrorAction Stop |
    Where-Object { $_.Timestamp -and $_.Timestamp -lt $limit -and $_.RecordType -in 'A', 'AAAA', 'PTR', 'CNAME' } |
    ForEach-Object {
        $record = $_                                   # dans un switch, $_ désigne la valeur testée
        $data = switch ($record.RecordType) {
            'A'     { "$($record.RecordData.IPv4Address)" }
            'AAAA'  { "$($record.RecordData.IPv6Address)" }
            'PTR'   { "$($record.RecordData.PtrDomainName)" }
            'CNAME' { "$($record.RecordData.HostNameAlias)" }
        }
        [pscustomobject]@{ HostName = $record.HostName; RecordType = $record.RecordType; Data = $data; Timestamp = $record.Timestamp; AgeDays = [int]((Get-Date) - $record.Timestamp).TotalDays; Zone = $ZoneName }
    } | Sort-Object Timestamp | Export-Report -CsvPath $CsvPath
