<#
.SYNOPSIS
    Retrace les modifications récentes de comptes et de groupes : qui a fait quoi, quand.

.DESCRIPTION
    Lit le journal Sécurité des contrôleurs de domaine pour les événements de gestion des
    comptes : création, activation, désactivation, suppression, réinitialisation de mot de
    passe, verrouillage, et ajouts ou retraits de membres dans les groupes de sécurité.
    Exige l'audit « Gestion des comptes » et le droit de lire le journal Sécurité.

.PARAMETER Target
    Ne garde que les événements concernant ce compte ou ce groupe (jokers acceptés).

.EXAMPLE
    .\Get-ADChangeAudit.ps1 -Hours 72 -Target 'Admins du domaine'
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 2160)][int]$Hours = 24,
    [string]$Target = '*',
    [string[]]$Server,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$labels = @{
    4720 = 'Compte utilisateur créé';          4722 = 'Compte utilisateur activé';     4725 = 'Compte utilisateur désactivé'
    4726 = 'Compte utilisateur supprimé';      4724 = 'Mot de passe réinitialisé';     4738 = 'Compte utilisateur modifié'
    4740 = 'Compte verrouillé';                4767 = 'Compte déverrouillé';           4741 = 'Compte d''ordinateur créé'
    4743 = 'Compte d''ordinateur supprimé';    4727 = 'Groupe global créé';            4730 = 'Groupe global supprimé'
    4728 = 'Membre ajouté (groupe global)';    4729 = 'Membre retiré (groupe global)'
    4732 = 'Membre ajouté (groupe local)';     4733 = 'Membre retiré (groupe local)'
    4756 = 'Membre ajouté (groupe universel)'; 4757 = 'Membre retiré (groupe universel)'
}
if (-not $Server) { $Server = @(Get-ADDomainController -Filter * | ForEach-Object HostName) }
$start = (Get-Date).AddHours(-$Hours)

$rows = foreach ($dc in $Server) {
    try {
        Get-WinEvent -ComputerName $dc -FilterHashtable @{ LogName = 'Security'; Id = [int[]]@($labels.Keys); StartTime = $start } -ErrorAction Stop | ForEach-Object {
            $data = @{}
            foreach ($node in ([xml]$_.ToXml()).Event.EventData.Data) { $data[$node.Name] = $node.'#text' }
            [pscustomobject]@{
                TimeCreated      = $_.TimeCreated
                EventId          = $_.Id
                Action           = $labels[[int]$_.Id]
                Target           = "$($data.TargetUserName)"
                Member           = if ($data.MemberName -and $data.MemberName -ne '-') { "$($data.MemberName)" } else { "$($data.MemberSid)" }
                By               = "$($data.SubjectUserName)"
                DomainController = $dc
            }
        }
    }
    catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*' -and $_.Exception.Message -notmatch 'No events were found|Aucun événement') {
            Write-Warning "Journal Sécurité de $dc illisible : $($_.Exception.Message)"
        }
    }
}
$rows | Where-Object { $_.Target -like $Target } | Sort-Object TimeCreated -Descending | Export-Report -CsvPath $CsvPath
