<#
.SYNOPSIS
    Liste les comptes d'ordinateurs actifs qui ne se sont pas authentifiés depuis N jours.

.DESCRIPTION
    S'appuie sur lastLogonTimestamp (précision d'environ 14 jours). Un poste change le mot de
    passe de son compte tous les 30 jours par défaut : PasswordLastSet recoupe l'information.
    Les contrôleurs de domaine sont toujours exclus.

.EXAMPLE
    .\Get-InactiveComputer.ps1 -Days 120 -CsvPath C:\Temp\postes-inactifs.csv
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
            Properties = 'LastLogonTimestamp', 'whenCreated', 'PasswordLastSet', 'OperatingSystem', 'Description', 'PrimaryGroupID' }
if ($SearchBase) { $query.SearchBase = $SearchBase }
$computers = @(Get-ADComputer @query)
if ($IncludeNeverLoggedOn) {
    $query.Filter = "Enabled -eq `$true -and LastLogonTimestamp -notlike '*'"
    $computers += @(Get-ADComputer @query | Where-Object { $_.whenCreated -lt $limit })
}

$computers | Where-Object { $_.PrimaryGroupID -notin 516, 521 } | ForEach-Object {      # 516 / 521 : contrôleurs de domaine
    $last = ConvertFrom-FileTime $_.LastLogonTimestamp
    [pscustomobject]@{
        Name              = $_.Name
        OperatingSystem   = $_.OperatingSystem
        LastLogon         = $last
        DaysInactive      = if ($last) { [int]((Get-Date) - $last).TotalDays } else { $null }
        PasswordLastSet   = $_.PasswordLastSet
        WhenCreated       = $_.whenCreated
        Description       = $_.Description
        DistinguishedName = $_.DistinguishedName
    }
} | Sort-Object LastLogon | Export-Report -CsvPath $CsvPath
