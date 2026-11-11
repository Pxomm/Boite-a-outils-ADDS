<#
.SYNOPSIS
    Vérifie que les enregistrements DNS indispensables à Active Directory existent et désignent les bons contrôleurs.

.DESCRIPTION
    Contrôle les enregistrements SRV de localisation (LDAP, Kerberos, catalogue global,
    émulateur PDC) puis, pour chaque contrôleur de domaine, sa présence dans ces
    enregistrements et la résolution de son nom vers son adresse. Un contrôleur absent du
    DNS n'est plus trouvé par les postes, même s'il fonctionne.

.EXAMPLE
    .\Test-DCDnsRecord.ps1 | Where-Object { -not $_.Ok }
#>
[CmdletBinding()]
param([string]$DnsServer, [string]$CsvPath)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$domain = Get-ADDomain
$forest = Get-ADForest
$controllers = @(Get-ADDomainController -Filter *)
$resolve = @{ ErrorAction = 'Stop' }
if ($DnsServer) { $resolve.Server = $DnsServer }

$records = @(
    @{ Name = "_ldap._tcp.dc._msdcs.$($domain.DNSRoot)";     Expected = @($controllers.HostName);                                  Label = 'Contrôleurs de domaine (LDAP)' }
    @{ Name = "_kerberos._tcp.dc._msdcs.$($domain.DNSRoot)"; Expected = @($controllers | Where-Object { -not $_.IsReadOnly } | ForEach-Object HostName); Label = 'Centres de distribution de clés (Kerberos)' }
    @{ Name = "_ldap._tcp.pdc._msdcs.$($domain.DNSRoot)";    Expected = @($domain.PDCEmulator);                                    Label = 'Émulateur PDC' }
    @{ Name = "_ldap._tcp.gc._msdcs.$($forest.RootDomain)";  Expected = @($controllers | Where-Object IsGlobalCatalog | ForEach-Object HostName); Label = 'Catalogues globaux' }
)
$rows = foreach ($record in $records) {
    try {
        $targets = @(Resolve-DnsName -Name $record.Name -Type SRV @resolve | Where-Object { $_.Type -eq 'SRV' } | ForEach-Object { "$($_.NameTarget)".TrimEnd('.') })
        $missing = @($record.Expected | Where-Object { $_ -and $_ -notin $targets })
        $extra   = @($targets | Where-Object { $_ -notin $controllers.HostName })
        $detail  = @()
        if ($missing) { $detail += "absent(s) : $($missing -join ', ')" }
        if ($extra)   { $detail += "inconnu(s) : $($extra -join ', ')" }
        [pscustomobject]@{ Check = $record.Label; Name = $record.Name; Ok = (-not $missing -and -not $extra); Detail = $detail -join ' ; ' }
    }
    catch { [pscustomobject]@{ Check = $record.Label; Name = $record.Name; Ok = $false; Detail = "Résolution impossible : $($_.Exception.Message)" } }
}
$rows += foreach ($dc in $controllers) {
    try {
        $addresses = @(Resolve-DnsName -Name $dc.HostName -Type A @resolve | Where-Object { $_.Type -eq 'A' } | ForEach-Object IPAddress)
        $ok = ($dc.IPv4Address -in $addresses)
        [pscustomobject]@{ Check = 'Enregistrement d''hôte'; Name = $dc.HostName; Ok = $ok; Detail = if ($ok) { '' } else { "attendu $($dc.IPv4Address), obtenu $($addresses -join ', ')" } }
    }
    catch { [pscustomobject]@{ Check = 'Enregistrement d''hôte'; Name = $dc.HostName; Ok = $false; Detail = "Résolution impossible : $($_.Exception.Message)" } }
}
$rows | Export-Report -CsvPath $CsvPath
