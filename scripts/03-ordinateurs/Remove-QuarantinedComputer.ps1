<#
.SYNOPSIS
    Supprime les ordinateurs restés en quarantaine au-delà du délai de garde.

.DESCRIPTION
    Seconde étape du nettoyage : ne sont supprimés que les comptes situés dans l'OU de
    quarantaine, toujours désactivés, et dont la description porte une date
    « Quarantaine AAAA-MM-JJ » antérieure au délai de garde. Un compte réactivé entre-temps
    est conservé. La suppression emporte les objets enfants (clés BitLocker, etc.) ; avec la
    corbeille Active Directory, elle reste réversible pendant la durée de conservation.

.EXAMPLE
    .\Remove-QuarantinedComputer.ps1 -QuarantineOU 'OU=Quarantaine,DC=corp,DC=local' -KeepDays 30 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$QuarantineOU,
    [ValidateRange(7, 3650)][int]$KeepDays = 30
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox
$null = Get-ADOrganizationalUnit -Identity $QuarantineOU -ErrorAction Stop
$limit = (Get-Date).Date.AddDays(-$KeepDays)

foreach ($computer in Get-ADComputer -Filter * -SearchBase $QuarantineOU -Properties Description) {
    $since = $null
    if ("$($computer.Description)" -match 'Quarantaine (\d{4}-\d{2}-\d{2})') { $since = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) }
    $status = if ($computer.Enabled) { 'Conservé (réactivé)' }
              elseif (-not $since) { 'Conservé (date de quarantaine absente)' }
              elseif ($since -gt $limit) { 'Conservé (délai de garde en cours)' }
              else { 'Simulation' }
    if ($status -eq 'Simulation' -and $PSCmdlet.ShouldProcess($computer.DistinguishedName, "Supprimer (en quarantaine depuis le $($since.ToString('dd/MM/yyyy')))")) {
        try { Remove-ADObject -Identity $computer.DistinguishedName -Recursive -Confirm:$false -ErrorAction Stop; $status = 'Supprimé' }
        catch { $status = "Erreur : $($_.Exception.Message)" }
    }
    [pscustomobject]@{ Name = $computer.Name; QuarantinedOn = $since; Enabled = $computer.Enabled; Status = $status }
}
