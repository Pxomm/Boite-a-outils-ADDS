<#
.SYNOPSIS
    Liste les comptes utilisateurs actifs qui ne se sont pas connectés depuis N jours.

.DESCRIPTION
    S'appuie sur lastLogonTimestamp, répliqué entre contrôleurs de domaine avec une précision
    d'environ 14 jours : utiliser un seuil nettement supérieur (90 jours par défaut).
    -IncludeNeverLoggedOn ajoute les comptes jamais utilisés, créés avant le seuil.

.EXAMPLE
    .\Get-InactiveUser.ps1 -Days 120 -SearchBase 'OU=Utilisateurs,DC=corp,DC=local' -CsvPath C:\Temp\inactifs.csv
#>
[CmdletBinding()]
param(
    [ValidateRange(15, 3650)][int]$Days = 90,
    [string]$SearchBase,
    [switch]$IncludeNeverLoggedOn,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$limit = (Get-Date).AddDays(-$Days)
$query = @{ Filter = "Enabled -eq `$true -and LastLogonTimestamp -lt $($limit.ToFileTimeUtc())"
            Properties = 'LastLogonTimestamp', 'whenCreated', 'PasswordLastSet', 'Description', 'Department' }
if ($SearchBase) { $query.SearchBase = $SearchBase }
$users = @(Get-ADUser @query)
if ($IncludeNeverLoggedOn) {
    $query.Filter = "Enabled -eq `$true -and LastLogonTimestamp -notlike '*'"
    $users += @(Get-ADUser @query | Where-Object { $_.whenCreated -lt $limit })
}

$users | ForEach-Object {
    $last = ConvertFrom-FileTime $_.LastLogonTimestamp
    [pscustomobject]@{
        SamAccountName    = $_.SamAccountName
        Name              = $_.Name
        LastLogon         = $last
        DaysInactive      = if ($last) { [int]((Get-Date) - $last).TotalDays } else { $null }
        WhenCreated       = $_.whenCreated
        PasswordLastSet   = $_.PasswordLastSet
        Department        = $_.Department
        Description       = $_.Description
        DistinguishedName = $_.DistinguishedName
    }
} | Sort-Object LastLogon | Export-Report -CsvPath $CsvPath
