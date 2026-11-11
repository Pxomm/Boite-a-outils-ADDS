<#
.SYNOPSIS
    Inventorie les ordinateurs du domaine par système d'exploitation et signale les systèmes en fin de support.

.DESCRIPTION
    -Summary renvoie le décompte par système. La colonne EndOfSupport repère les systèmes
    que Microsoft ne maintient plus (Windows XP à 8.1, Windows Server 2000 à 2012 R2) ;
    pour Windows 10 et 11, vérifier la version (OperatingSystemVersion) auprès de Microsoft.

.EXAMPLE
    .\Get-ComputerInventory.ps1 -Summary

.EXAMPLE
    .\Get-ComputerInventory.ps1 -ServersOnly -CsvPath C:\Temp\serveurs.csv
#>
[CmdletBinding()]
param(
    [string]$SearchBase,
    [switch]$ServersOnly,
    [switch]$Summary,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$query = @{ Filter = '*'; Properties = 'OperatingSystem', 'OperatingSystemVersion', 'LastLogonTimestamp', 'IPv4Address', 'whenCreated', 'Description' }
if ($SearchBase) { $query.SearchBase = $SearchBase }
$obsolete = 'Windows (XP|Vista|7|8|8\.1)\b|Windows 2000|Server (2000|2003|2008|2012)'

$rows = Get-ADComputer @query | Where-Object { -not $ServersOnly -or $_.OperatingSystem -match 'Server' } | ForEach-Object {
    [pscustomobject]@{
        Name                   = $_.Name
        Enabled                = $_.Enabled
        OperatingSystem        = $_.OperatingSystem
        OperatingSystemVersion = $_.OperatingSystemVersion
        EndOfSupport           = [bool]("$($_.OperatingSystem)" -match $obsolete)
        IPv4Address            = $_.IPv4Address
        LastLogon              = ConvertFrom-FileTime $_.LastLogonTimestamp
        WhenCreated            = $_.whenCreated
        Description            = $_.Description
        OU                     = ($_.DistinguishedName -split '(?<!\\),', 2)[1]
    }
}

if ($Summary) {
    $rows | Group-Object OperatingSystem | ForEach-Object {
        [pscustomobject]@{ OperatingSystem = if ($_.Name) { $_.Name } else { '(non renseigné)' }; Count = $_.Count
                           Enabled = @($_.Group | Where-Object Enabled).Count; EndOfSupport = [bool]($_.Group[0].EndOfSupport) }
    } | Sort-Object Count -Descending | Export-Report -CsvPath $CsvPath
}
else { $rows | Sort-Object Name | Export-Report -CsvPath $CsvPath }
