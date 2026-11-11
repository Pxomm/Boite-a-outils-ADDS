<#
.SYNOPSIS
    Mesure la couverture de LAPS : quels ordinateurs ont un mot de passe administrateur local géré, et lesquels non.

.DESCRIPTION
    Reconnaît Windows LAPS (attribut msLAPS-PasswordExpirationTime) et l'ancien LAPS
    (ms-Mcs-AdmPwdExpirationTime). Le script ne lit que la date d'expiration, jamais le mot
    de passe. Si le schéma ne contient aucun de ces attributs, LAPS n'est pas déployé.
    Les contrôleurs de domaine sont ignorés. -MissingOnly ne renvoie que les postes sans LAPS
    ou dont le mot de passe est expiré.

.EXAMPLE
    .\Get-LapsCoverage.ps1 -MissingOnly -CsvPath C:\Temp\laps.csv
#>
[CmdletBinding()]
param(
    [string]$SearchBase,
    [switch]$MissingOnly,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

# Attributs réellement présents dans le schéma
$schema = (Get-ADRootDSE).schemaNamingContext
$attributes = @('msLAPS-PasswordExpirationTime', 'ms-Mcs-AdmPwdExpirationTime' | Where-Object {
    Get-ADObject -SearchBase $schema -Filter "lDAPDisplayName -eq '$_'" -ErrorAction SilentlyContinue })
if ($attributes.Count -eq 0) { Write-Warning 'Le schéma ne contient aucun attribut LAPS : LAPS n''est pas déployé dans cette forêt.' }

$query = @{ Filter = "Enabled -eq `$true"; Properties = @('OperatingSystem', 'PrimaryGroupID', 'LastLogonTimestamp') + $attributes }
if ($SearchBase) { $query.SearchBase = $SearchBase }
$now = Get-Date

Get-ADComputer @query | Where-Object { $_.PrimaryGroupID -notin 516, 521 } | ForEach-Object {
    $new = ConvertFrom-FileTime $_.'msLAPS-PasswordExpirationTime'
    $old = ConvertFrom-FileTime $_.'ms-Mcs-AdmPwdExpirationTime'
    $expires = if ($new) { $new } else { $old }
    $state = if (-not $expires) { 'Sans LAPS' } elseif ($expires -lt $now) { 'Mot de passe expiré' } else { 'Géré' }
    if (-not $MissingOnly -or $state -ne 'Géré') {
        [pscustomobject]@{ Name = $_.Name; OperatingSystem = $_.OperatingSystem; LapsKind = if ($new) { 'Windows LAPS' } elseif ($old) { 'LAPS hérité' } else { '' }
                           PasswordExpires = $expires; State = $state; LastLogon = ConvertFrom-FileTime $_.LastLogonTimestamp; DistinguishedName = $_.DistinguishedName }
    }
} | Sort-Object State, Name | Export-Report -CsvPath $CsvPath
