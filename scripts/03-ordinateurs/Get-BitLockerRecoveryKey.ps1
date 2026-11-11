<#
.SYNOPSIS
    Retrouve les mots de passe de récupération BitLocker enregistrés dans Active Directory pour un ordinateur.

.DESCRIPTION
    Les clés sont des objets enfants du compte d'ordinateur (msFVE-RecoveryInformation),
    lisibles uniquement par les comptes qui en ont reçu le droit. -KeyId permet de retrouver
    un ordinateur à partir des 8 premiers caractères de l'identifiant affiché sur l'écran
    de récupération. La sortie contient un secret : ne pas la journaliser.

.EXAMPLE
    .\Get-BitLockerRecoveryKey.ps1 -ComputerName PC-0142

.EXAMPLE
    .\Get-BitLockerRecoveryKey.ps1 -KeyId 3F2A9C1B
#>
[CmdletBinding(DefaultParameterSetName = 'Computer')]
param(
    [Parameter(ParameterSetName = 'Computer', Mandatory)][string]$ComputerName,
    [Parameter(ParameterSetName = 'KeyId', Mandatory)][ValidatePattern('^[0-9A-Fa-f]{8}')][string]$KeyId
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$query = @{ Filter = "objectClass -eq 'msFVE-RecoveryInformation'"; Properties = 'msFVE-RecoveryPassword', 'whenCreated' }
if ($PSCmdlet.ParameterSetName -eq 'Computer') {
    $computer = Get-ADComputer -Identity $ComputerName -ErrorAction Stop
    $query.SearchBase = $computer.DistinguishedName
}
$keys = @(Get-ADObject @query)
# Nom de l'objet : « 2026-03-14T09:21:07-01:00{3F2A9C1B-....} »
if ($KeyId) { $keys = @($keys | Where-Object { $_.Name -match "\{$([regex]::Escape($KeyId.Substring(0, 8)))" }) }
if ($keys.Count -eq 0) { Write-Warning 'Aucune clé de récupération trouvée (clé non sauvegardée dans l''annuaire, ou droits de lecture insuffisants).' }

$keys | Sort-Object whenCreated -Descending | ForEach-Object {
    [pscustomobject]@{
        ComputerName     = (($_.DistinguishedName -split '(?<!\\),')[1]) -replace '^CN='
        KeyId            = if ($_.Name -match '\{([0-9A-Fa-f-]+)\}') { $Matches[1] } else { '' }
        WhenCreated      = $_.whenCreated
        RecoveryPassword = $_.'msFVE-RecoveryPassword'
    }
}
