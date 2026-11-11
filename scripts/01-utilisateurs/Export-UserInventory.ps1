<#
.SYNOPSIS
    Exporte l'inventaire des comptes utilisateurs avec leurs principaux attributs.

.EXAMPLE
    .\Export-UserInventory.ps1 -CsvPath C:\Temp\utilisateurs.csv

.EXAMPLE
    .\Export-UserInventory.ps1 -SearchBase 'OU=Utilisateurs,DC=corp,DC=local' -EnabledOnly | Out-GridView
#>
[CmdletBinding()]
param(
    [string]$SearchBase,
    [switch]$EnabledOnly,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$query = @{ Filter = if ($EnabledOnly) { "Enabled -eq `$true" } else { '*' }
            Properties = 'DisplayName', 'mail', 'Title', 'Department', 'Company', 'Office', 'OfficePhone', 'Manager', 'Description',
                         'whenCreated', 'LastLogonTimestamp', 'PasswordLastSet', 'PasswordNeverExpires', 'AccountExpirationDate', 'LockedOut' }
if ($SearchBase) { $query.SearchBase = $SearchBase }

Get-ADUser @query | ForEach-Object {
    [pscustomobject]@{
        SamAccountName        = $_.SamAccountName
        UserPrincipalName     = $_.UserPrincipalName
        DisplayName           = $_.DisplayName
        GivenName             = $_.GivenName
        Surname               = $_.Surname
        Enabled               = $_.Enabled
        Mail                  = $_.mail
        Title                 = $_.Title
        Department            = $_.Department
        Company               = $_.Company
        Office                = $_.Office
        OfficePhone           = $_.OfficePhone
        Manager               = if ($_.Manager) { ($_.Manager -split '(?<!\\),')[0] -replace '^CN=' } else { '' }
        Description           = $_.Description
        WhenCreated           = $_.whenCreated
        LastLogon             = ConvertFrom-FileTime $_.LastLogonTimestamp
        PasswordLastSet       = $_.PasswordLastSet
        PasswordNeverExpires  = $_.PasswordNeverExpires
        AccountExpirationDate = $_.AccountExpirationDate
        LockedOut             = $_.LockedOut
        OU                    = ($_.DistinguishedName -split '(?<!\\),', 2)[1]
    }
} | Sort-Object SamAccountName | Export-Report -CsvPath $CsvPath
