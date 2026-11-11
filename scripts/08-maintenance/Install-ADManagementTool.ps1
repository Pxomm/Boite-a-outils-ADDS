<#
.SYNOPSIS
    Installe les outils d'administration Active Directory (RSAT) nécessaires aux scripts de ce dépôt.

.DESCRIPTION
    Sur un serveur : fonctionnalités RSAT-AD-PowerShell, RSAT-ADDS-Tools, GPMC et
    RSAT-DNS-Server. Sur un poste Windows 10 ou 11 : fonctionnalités à la demande
    correspondantes (connexion à Windows Update ou à la source de fonctionnalités requise).
    À lancer dans une console élevée. Sans -Install, le script affiche seulement ce qui manque.

.EXAMPLE
    .\Install-ADManagementTool.ps1

.EXAMPLE
    .\Install-ADManagementTool.ps1 -Install
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$Install)

$os = Get-CimInstance -ClassName Win32_OperatingSystem
$isServer = ($os.ProductType -ne 1)

if ($isServer) {
    $wanted = 'RSAT-AD-PowerShell', 'RSAT-ADDS-Tools', 'GPMC', 'RSAT-DNS-Server'
    foreach ($feature in Get-WindowsFeature -Name $wanted) {
        $status = if ($feature.Installed) { 'Installé' } else { 'Absent' }
        if (-not $feature.Installed -and $Install -and $PSCmdlet.ShouldProcess($feature.Name, 'Installer la fonctionnalité')) {
            $result = Install-WindowsFeature -Name $feature.Name -ErrorAction Stop
            $status = if ($result.Success) { 'Installé' } else { 'Échec' }
        }
        [pscustomobject]@{ Tool = $feature.Name; Status = $status }
    }
}
else {
    $wanted = 'Rsat.ActiveDirectory.DS-LDS.Tools', 'Rsat.GroupPolicy.Management.Tools', 'Rsat.Dns.Tools'
    foreach ($prefix in $wanted) {
        $capability = Get-WindowsCapability -Online -Name "$prefix*" | Select-Object -First 1
        if (-not $capability) { [pscustomobject]@{ Tool = $prefix; Status = 'Introuvable sur cette version de Windows' }; continue }
        $status = if ($capability.State -eq 'Installed') { 'Installé' } else { 'Absent' }
        if ($capability.State -ne 'Installed' -and $Install -and $PSCmdlet.ShouldProcess($capability.Name, 'Installer la fonctionnalité à la demande')) {
            Add-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop | Out-Null
            $status = 'Installé'
        }
        [pscustomobject]@{ Tool = $capability.Name; Status = $status }
    }
}
