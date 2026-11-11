<#
.SYNOPSIS
    Sauvegarde l'état du système d'un contrôleur de domaine (annuaire, SYSVOL, registre) avec Sauvegarde Windows Server.

.DESCRIPTION
    L'état du système est la sauvegarde qui permet de restaurer Active Directory. À lancer
    sur le contrôleur de domaine lui-même, en administrateur, vers un volume local distinct
    du volume système ou vers un partage réseau. Le script vérifie la fonctionnalité
    « Sauvegarde Windows Server », la cible et l'espace libre, puis lance wbadmin.
    Une sauvegarde plus ancienne que la durée de conservation des objets supprimés
    (180 jours par défaut) n'est plus restaurable : planifier ce script au moins chaque semaine.

.EXAMPLE
    .\Backup-SystemState.ps1 -Target E: -WhatIf

.EXAMPLE
    .\Backup-SystemState.ps1 -Target \\srv-sauvegarde\dc01
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^([A-Za-z]:|\\\\[^\\]+\\[^\\]+.*)$')][string]$Target,
    [ValidateRange(5, 2000)][int]$MinFreeGB = 30
)

if (-not (Get-Command wbadmin.exe -ErrorAction SilentlyContinue)) { throw 'wbadmin.exe introuvable : ce script s''exécute sur un serveur Windows.' }
$feature = Get-WindowsFeature -Name Windows-Server-Backup -ErrorAction Stop
if (-not $feature.Installed) { throw 'Fonctionnalité « Sauvegarde Windows Server » absente : Install-WindowsFeature Windows-Server-Backup' }

if ($Target -match '^[A-Za-z]:$') {
    if ($Target -eq $env:SystemDrive) { throw 'La cible ne peut pas être le volume système.' }
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($Target.ToUpper())'"
    if (-not $disk) { throw "Volume $Target introuvable." }
    $freeGB = [Math]::Round($disk.FreeSpace / 1GB, 1)
    if ($freeGB -lt $MinFreeGB) { throw "Espace libre insuffisant sur $Target : $freeGB Go (minimum demandé : $MinFreeGB Go)." }
}
elseif (-not (Test-Path -LiteralPath $Target)) { throw "Partage inaccessible : $Target" }

$status = 'Simulation'; $code = $null
$started = Get-Date
if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Sauvegarder l'état du système vers $Target")) {
    & wbadmin.exe start systemstatebackup "-backupTarget:$Target" -quiet | ForEach-Object { Write-Verbose "$_" }
    $code = $LASTEXITCODE
    $status = if ($code -eq 0) { 'Réussie' } else { "Échec (wbadmin, code $code) : voir le journal Microsoft-Windows-Backup" }
}
[pscustomobject]@{ ComputerName = $env:COMPUTERNAME; Target = $Target; Started = $started; DurationMinutes = [Math]::Round(((Get-Date) - $started).TotalMinutes, 1); Status = $status }
if ($null -ne $code -and $code -ne 0) { exit $code }
