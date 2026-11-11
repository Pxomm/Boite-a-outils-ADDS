<#
.SYNOPSIS
    Contrôle l'état de chaque contrôleur de domaine : réponse réseau, services, partages, disque, démarrage.

.DESCRIPTION
    Pour chaque contrôleur : réponse au ping, port LDAP (389, ou -LdapPort 636 pour LDAPS), services indispensables
    (NTDS, Netlogon, KDC, DNS, DFSR, W32Time), présence des partages SYSVOL et NETLOGON,
    espace libre du disque système, date du dernier démarrage. La colonne Healthy résume ;
    Issues détaille les anomalies. Les services et le disque sont lus par WinRM (CIM).

.EXAMPLE
    .\Get-DCHealth.ps1 | Format-Table HostName, Healthy, Issues -AutoSize
#>
[CmdletBinding()]
param(
    [string[]]$Server,
    [ValidateRange(1, 65535)][int]$LdapPort = 389,
    [ValidateRange(1, 90)][int]$MinFreePercent = 15,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

if (-not $Server) { $Server = @(Get-ADDomainController -Filter * | Sort-Object HostName | ForEach-Object HostName) }
$services = 'NTDS', 'Netlogon', 'Kdc', 'DNS', 'DFSR', 'W32Time'

$rows = foreach ($dc in $Server) {
    $issues = @()
    $row = [ordered]@{ HostName = $dc; Ping = $false; Ldap = $false; Services = ''; Sysvol = $false; Netlogon = $false; SystemFreePercent = $null; LastBoot = $null }
    $row.Ping = [bool](Test-Connection -ComputerName $dc -Count 1 -Quiet -ErrorAction SilentlyContinue)
    if (-not $row.Ping) { $issues += 'ne répond pas au ping' }

    $client = New-Object System.Net.Sockets.TcpClient
    try { $row.Ldap = $client.ConnectAsync($dc, $LdapPort).Wait(3000) -and $client.Connected }
    catch { $row.Ldap = $false }
    finally { $client.Close() }
    if (-not $row.Ldap) { $issues += "port LDAP $LdapPort fermé" }

    if ($row.Ldap) {
        $row.Sysvol   = Test-Path -LiteralPath "\\$dc\SYSVOL"
        $row.Netlogon = Test-Path -LiteralPath "\\$dc\NETLOGON"
        if (-not $row.Sysvol)   { $issues += 'partage SYSVOL absent' }
        if (-not $row.Netlogon) { $issues += 'partage NETLOGON absent' }
        try {
            $found = @(Get-CimInstance -ComputerName $dc -ClassName Win32_Service -Filter ("Name='" + ($services -join "' OR Name='") + "'") -ErrorAction Stop)
            $stopped = @($found | Where-Object { $_.State -ne 'Running' } | ForEach-Object Name)
            $absent  = @($services | Where-Object { $_ -notin $found.Name -and $_ -ne 'DNS' })       # DNS peut être hébergé ailleurs
            $row.Services = if ($stopped -or $absent) { "Arrêtés : $(@($stopped + $absent) -join ', ')" } else { 'OK' }
            if ($stopped -or $absent) { $issues += "service(s) arrêté(s) : $(@($stopped + $absent) -join ', ')" }

            $os = Get-CimInstance -ComputerName $dc -ClassName Win32_OperatingSystem -ErrorAction Stop
            $row.LastBoot = $os.LastBootUpTime
            $disk = Get-CimInstance -ComputerName $dc -ClassName Win32_LogicalDisk -Filter "DeviceID='$($os.SystemDrive)'" -ErrorAction Stop
            if ($disk.Size) {
                $row.SystemFreePercent = [Math]::Round(100 * $disk.FreeSpace / $disk.Size, 1)
                if ($row.SystemFreePercent -lt $MinFreePercent) { $issues += "disque système à $($row.SystemFreePercent) % libre" }
            }
        }
        catch { $row.Services = 'Illisible'; $issues += "interrogation WinRM impossible ($($_.Exception.Message))" }
    }
    $row.Healthy = ($issues.Count -eq 0)
    $row.Issues  = $issues -join ' ; '
    [pscustomobject]$row
}
$rows | Export-Report -CsvPath $CsvPath
