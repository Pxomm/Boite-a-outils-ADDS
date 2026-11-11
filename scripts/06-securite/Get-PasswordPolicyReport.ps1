<#
.SYNOPSIS
    Présente la stratégie de mot de passe du domaine et les stratégies affinées (PSO), avec leurs cibles.

.DESCRIPTION
    Une ligne pour la stratégie par défaut du domaine, puis une par stratégie affinée, triées
    par priorité (la plus petite valeur l'emporte). La colonne Remarks signale les réglages
    faibles : moins de 12 caractères, complexité désactivée, verrouillage absent, chiffrement
    réversible.

.EXAMPLE
    .\Get-PasswordPolicyReport.ps1 | Format-List
#>
[CmdletBinding()]
param([string]$CsvPath)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

function Get-PolicyRemark {
    param($Policy)
    $remarks = @()
    if ($Policy.MinPasswordLength -lt 12) { $remarks += 'longueur minimale inférieure à 12' }
    if (-not $Policy.ComplexityEnabled) { $remarks += 'complexité désactivée' }
    if ($Policy.LockoutThreshold -eq 0) { $remarks += 'aucun verrouillage de compte' }
    if ($Policy.ReversibleEncryptionEnabled) { $remarks += 'chiffrement réversible activé' }
    if ($Policy.PasswordHistoryCount -lt 10) { $remarks += 'historique inférieur à 10' }
    return $remarks -join ' ; '
}
function ConvertTo-PolicyRow {
    param($Policy, [string]$Name, $Precedence, [string]$AppliesTo)
    [pscustomobject]@{
        Name                    = $Name
        Precedence              = $Precedence
        AppliesTo               = $AppliesTo
        MinPasswordLength       = $Policy.MinPasswordLength
        ComplexityEnabled       = $Policy.ComplexityEnabled
        PasswordHistoryCount    = $Policy.PasswordHistoryCount
        MaxPasswordAgeDays      = [int]$Policy.MaxPasswordAge.TotalDays
        MinPasswordAgeDays      = [int]$Policy.MinPasswordAge.TotalDays
        LockoutThreshold        = $Policy.LockoutThreshold
        LockoutDurationMinutes  = [int]$Policy.LockoutDuration.TotalMinutes
        LockoutWindowMinutes    = [int]$Policy.LockoutObservationWindow.TotalMinutes
        ReversibleEncryption    = $Policy.ReversibleEncryptionEnabled
        Remarks                 = Get-PolicyRemark -Policy $Policy
    }
}

$rows = @(ConvertTo-PolicyRow -Policy (Get-ADDefaultDomainPasswordPolicy) -Name 'Stratégie par défaut du domaine' -Precedence $null -AppliesTo 'Tous les comptes sans stratégie affinée')
$rows += @(Get-ADFineGrainedPasswordPolicy -Filter * -Properties AppliesTo | Sort-Object Precedence | ForEach-Object {
    $targets = @($_.AppliesTo | ForEach-Object { ("$_" -split '(?<!\\),')[0] -replace '^CN=' }) -join ', '
    ConvertTo-PolicyRow -Policy $_ -Name $_.Name -Precedence $_.Precedence -AppliesTo $(if ($targets) { $targets } else { '(aucune cible : sans effet)' })
})
$rows | Export-Report -CsvPath $CsvPath
