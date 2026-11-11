<#
.SYNOPSIS
    Repère les comptes dont le paramétrage affaiblit la sécurité du domaine.

.DESCRIPTION
    Une ligne par compte et par constat :
      - Kerberoast          : compte utilisateur portant un SPN (ticket de service cassable hors ligne) ;
      - ASREPRoast          : pré-authentification Kerberos non exigée ;
      - PasswordNotRequired : le compte peut avoir un mot de passe vide ;
      - PasswordNeverExpires: mot de passe sans expiration (comptes actifs) ;
      - ReversibleEncryption: mot de passe stocké de façon réversible ;
      - DESOnly             : chiffrement Kerberos DES seulement ;
      - SIDHistory          : historique de SID présent (reliquat de migration, élévation possible) ;
      - OldPassword         : mot de passe inchangé depuis plus de -PasswordAgeDays jours.
    Les comptes désactivés sont ignorés, ainsi que krbtgt (voir Get-KrbtgtStatus.ps1).

.EXAMPLE
    .\Get-RiskyAccountSetting.ps1 -CsvPath C:\Temp\comptes-a-risque.csv

.EXAMPLE
    .\Get-RiskyAccountSetting.ps1 -Check Kerberoast, ASREPRoast
#>
[CmdletBinding()]
param(
    [ValidateSet('Kerberoast', 'ASREPRoast', 'PasswordNotRequired', 'PasswordNeverExpires', 'ReversibleEncryption', 'DESOnly', 'SIDHistory', 'OldPassword')]
    [string[]]$Check = @('Kerberoast', 'ASREPRoast', 'PasswordNotRequired', 'PasswordNeverExpires', 'ReversibleEncryption', 'DESOnly', 'SIDHistory', 'OldPassword'),
    [ValidateRange(30, 3650)][int]$PasswordAgeDays = 365,
    [string]$SearchBase,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

# Bits de userAccountControl : 2 = compte désactivé, 128 = chiffrement réversible, 2097152 = DES seulement
$active = '(!(userAccountControl:1.2.840.113556.1.4.803:=2))'
$queries = @{
    Kerberoast           = @{ Filter = "Enabled -eq `$true -and ServicePrincipalName -like '*'" }
    ASREPRoast           = @{ Filter = "Enabled -eq `$true -and DoesNotRequirePreAuth -eq `$true" }
    PasswordNotRequired  = @{ Filter = "Enabled -eq `$true -and PasswordNotRequired -eq `$true" }
    PasswordNeverExpires = @{ Filter = "Enabled -eq `$true -and PasswordNeverExpires -eq `$true" }
    ReversibleEncryption = @{ LDAPFilter = "(&$active(userAccountControl:1.2.840.113556.1.4.803:=128))" }
    DESOnly              = @{ LDAPFilter = "(&$active(userAccountControl:1.2.840.113556.1.4.803:=2097152))" }
    SIDHistory           = @{ Filter = "Enabled -eq `$true -and SIDHistory -like '*'" }
    OldPassword          = @{ Filter = "Enabled -eq `$true -and pwdLastSet -lt $((Get-Date).AddDays(-$PasswordAgeDays).ToFileTimeUtc()) -and pwdLastSet -gt 0" }
}
$properties = 'ServicePrincipalName', 'PasswordLastSet', 'LastLogonTimestamp', 'adminCount', 'Description'

$rows = foreach ($name in $Check) {
    $query = $queries[$name].Clone()
    $query.Properties = $properties
    if ($SearchBase) { $query.SearchBase = $SearchBase }
    Get-ADUser @query | Where-Object { $_.SamAccountName -ne 'krbtgt' } | ForEach-Object {
        [pscustomobject]@{
            Finding         = $name
            SamAccountName  = $_.SamAccountName
            Name            = $_.Name
            Privileged      = ($_.adminCount -eq 1)
            PasswordLastSet = $_.PasswordLastSet
            PasswordAgeDays = if ($_.PasswordLastSet) { [int]((Get-Date) - $_.PasswordLastSet).TotalDays } else { $null }
            LastLogon       = ConvertFrom-FileTime $_.LastLogonTimestamp
            Detail          = if ($name -eq 'Kerberoast') { @($_.ServicePrincipalName) -join ', ' } else { "$($_.Description)" }
        }
    }
}
$rows | Sort-Object @{ Expression = 'Privileged'; Descending = $true }, Finding, SamAccountName | Export-Report -CsvPath $CsvPath
