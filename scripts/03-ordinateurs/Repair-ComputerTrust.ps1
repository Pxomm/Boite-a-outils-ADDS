<#
.SYNOPSIS
    Vérifie et répare la relation d'approbation entre un poste et le domaine, sans le sortir du domaine.

.DESCRIPTION
    À exécuter sur le poste concerné, dans une console élevée, lorsque l'ouverture de session
    échoue avec « la relation d'approbation entre cette station de travail et le domaine
    principal a échoué ». La réparation exige un compte du domaine autorisé à réinitialiser
    le mot de passe du compte d'ordinateur.

.EXAMPLE
    .\Repair-ComputerTrust.ps1

.EXAMPLE
    .\Repair-ComputerTrust.ps1 -Repair -Credential (Get-Credential CORP\adm.dupont)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Repair,
    [System.Management.Automation.PSCredential]$Credential
)

if (-not (Get-Command Test-ComputerSecureChannel -ErrorAction SilentlyContinue)) {
    throw 'Test-ComputerSecureChannel est absent de PowerShell 7 : lancer ce script dans Windows PowerShell 5.1 (powershell.exe).'
}
$system = Get-CimInstance -ClassName Win32_ComputerSystem
if (-not $system.PartOfDomain) { throw 'Ce poste n''est pas membre d''un domaine.' }

$healthy = [bool](Test-ComputerSecureChannel -ErrorAction SilentlyContinue)
$status = if ($healthy) { 'Canal sécurisé valide' } else { 'Canal sécurisé rompu' }
if (-not $healthy -and $Repair) {
    if (-not $Credential) { throw '-Repair exige -Credential (compte du domaine).' }
    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Réparer le canal sécurisé avec le domaine')) {
        $healthy = [bool](Test-ComputerSecureChannel -Repair -Credential $Credential -ErrorAction Stop)
        $status = if ($healthy) { 'Réparé' } else { 'Réparation en échec : sortir puis rejoindre le domaine' }
    }
}
[pscustomobject]@{ ComputerName = $env:COMPUTERNAME; Domain = $system.Domain; SecureChannel = $healthy; Status = $status }
