<#
.SYNOPSIS
    Indique l'âge du mot de passe du compte krbtgt.

.DESCRIPTION
    Le compte krbtgt signe tous les tickets Kerberos du domaine. Si son secret a été volé,
    l'attaquant fabrique des tickets valides (« golden ticket ») tant que le mot de passe
    n'a pas été changé deux fois. Il est recommandé de le renouveler régulièrement
    (-MaxAgeDays, 180 jours par défaut), en deux changements espacés d'au moins la durée
    de vie maximale d'un ticket (10 heures par défaut), avec le script New-KrbtgtKeys de
    Microsoft. Ce script-ci ne modifie rien.

.EXAMPLE
    .\Get-KrbtgtStatus.ps1
#>
[CmdletBinding()]
param([ValidateRange(1, 3650)][int]$MaxAgeDays = 180)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

Get-ADUser -Filter "SamAccountName -like 'krbtgt*'" -Properties PasswordLastSet, 'msDS-KeyVersionNumber', 'msDS-KrbTgtLinkBl' | ForEach-Object {
    $age = if ($_.PasswordLastSet) { [int]((Get-Date) - $_.PasswordLastSet).TotalDays } else { $null }
    [pscustomobject]@{
        SamAccountName   = $_.SamAccountName
        Kind             = if ($_.SamAccountName -eq 'krbtgt') { 'Domaine' } else { 'Contrôleur en lecture seule' }
        PasswordLastSet  = $_.PasswordLastSet
        PasswordAgeDays  = $age
        KeyVersionNumber = $_.'msDS-KeyVersionNumber'
        Status           = if ($null -eq $age) { 'Inconnu' } elseif ($age -gt $MaxAgeDays) { "À renouveler (plus de $MaxAgeDays jours)" } else { 'OK' }
    }
}
