<#
.SYNOPSIS
    Crée une stratégie de mot de passe affinée (PSO) renforcée et l'applique à un groupe.

.DESCRIPTION
    Sert à imposer aux comptes d'administration ou de service des règles plus strictes que
    celles du domaine, sans toucher à la stratégie par défaut. Valeurs par défaut :
    16 caractères, complexité, 24 mots de passe mémorisés, durée de vie de 180 jours,
    verrouillage après 5 échecs pendant 30 minutes. Une stratégie affinée ne s'applique
    qu'à des utilisateurs ou à des groupes globaux, jamais à une OU.

.EXAMPLE
    .\New-AdminPasswordPolicy.ps1 -Name PSO_Administrateurs -Group GG_Comptes_Admin -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Group,
    [ValidateRange(1, 1000)][int]$Precedence = 10,
    [ValidateRange(8, 255)][int]$MinPasswordLength = 16,
    [ValidateRange(0, 24)][int]$PasswordHistoryCount = 24,
    [ValidateRange(0, 999)][int]$MaxPasswordAgeDays = 180,
    [ValidateRange(0, 998)][int]$MinPasswordAgeDays = 1,
    [ValidateRange(0, 999)][int]$LockoutThreshold = 5,
    [ValidateRange(1, 99999)][int]$LockoutMinutes = 30
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$target = Get-ADGroup -Identity $Group -ErrorAction Stop
if ($target.GroupScope -ne 'Global' -or $target.GroupCategory -ne 'Security') { throw "Le groupe '$($target.Name)' doit être un groupe de sécurité global." }
if ($MaxPasswordAgeDays -ne 0 -and $MinPasswordAgeDays -ge $MaxPasswordAgeDays) { throw 'La durée de vie minimale doit être inférieure à la durée de vie maximale.' }
if (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$(ConvertTo-FilterValue $Name)'") { throw "Une stratégie nommée '$Name' existe déjà." }
$clash = @(Get-ADFineGrainedPasswordPolicy -Filter * | Where-Object { $_.Precedence -eq $Precedence })
if ($clash.Count -gt 0) { Write-Warning "La priorité $Precedence est déjà utilisée par '$($clash[0].Name)' : en cas de conflit, le résultat dépend de l'identifiant des objets." }

$new = @{
    Name                        = $Name
    Precedence                  = $Precedence
    MinPasswordLength           = $MinPasswordLength
    PasswordHistoryCount        = $PasswordHistoryCount
    ComplexityEnabled           = $true
    ReversibleEncryptionEnabled = $false
    MaxPasswordAge              = [TimeSpan]::FromDays($MaxPasswordAgeDays)
    MinPasswordAge              = [TimeSpan]::FromDays($MinPasswordAgeDays)
    LockoutThreshold            = $LockoutThreshold
    LockoutDuration             = [TimeSpan]::FromMinutes($LockoutMinutes)
    LockoutObservationWindow    = [TimeSpan]::FromMinutes($LockoutMinutes)
    ProtectedFromAccidentalDeletion = $true
}
$status = 'Simulation'
if ($PSCmdlet.ShouldProcess($Name, "Créer la stratégie de mot de passe affinée et l'appliquer à $($target.Name)")) {
    New-ADFineGrainedPasswordPolicy @new -ErrorAction Stop
    Add-ADFineGrainedPasswordPolicySubject -Identity $Name -Subjects $target.DistinguishedName -ErrorAction Stop
    $status = 'Créée'
}
[pscustomobject]@{ Name = $Name; AppliesTo = $target.Name; Precedence = $Precedence; MinPasswordLength = $MinPasswordLength; MaxPasswordAgeDays = $MaxPasswordAgeDays
                   LockoutThreshold = $LockoutThreshold; Status = $status }
