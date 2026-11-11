<#
.SYNOPSIS
    Indique depuis quel poste un compte a été verrouillé (événements 4740).

.DESCRIPTION
    Les verrouillages sont consignés sur le contrôleur de domaine qui détient le rôle
    Émulateur PDC. Le script y lit le journal Sécurité (droit de lecture du journal requis,
    et audit « Gestion des comptes d'utilisateurs » actif).

.PARAMETER Identity
    Identifiant à rechercher. Sans ce paramètre, tous les verrouillages de la période sont listés.

.EXAMPLE
    .\Find-LockoutSource.ps1 -Identity j.dupont -Hours 48
#>
[CmdletBinding()]
param(
    [string]$Identity,
    [ValidateRange(1, 720)][int]$Hours = 24,
    [string]$Server,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

if (-not $Server) { $Server = (Get-ADDomain).PDCEmulator }
$filter = @{ LogName = 'Security'; Id = 4740; StartTime = (Get-Date).AddHours(-$Hours) }
try { $events = @(Get-WinEvent -ComputerName $Server -FilterHashtable $filter -ErrorAction Stop) }
catch {
    if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*' -or $_.Exception.Message -match 'No events were found|Aucun événement') { $events = @() }
    else { throw "Lecture du journal Sécurité de $Server impossible : $($_.Exception.Message)" }
}

$events | ForEach-Object {
    # 4740 : Properties[0] = compte verrouillé, Properties[1] = poste à l'origine
    [pscustomobject]@{
        TimeCreated      = $_.TimeCreated
        SamAccountName   = "$($_.Properties[0].Value)"
        CallerComputer   = "$($_.Properties[1].Value)"
        DomainController = $Server
    }
} | Where-Object { -not $Identity -or $_.SamAccountName -eq $Identity } | Sort-Object TimeCreated -Descending | Export-Report -CsvPath $CsvPath
