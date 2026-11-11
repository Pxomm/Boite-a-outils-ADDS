<#
.SYNOPSIS
    Traite le départ d'un collaborateur : désactivation, retrait des groupes, déplacement.

.DESCRIPTION
    Pour chaque compte :
      1. sauvegarde de la liste de ses groupes dans un fichier CSV (retour arrière possible) ;
      2. désactivation et description horodatée ;
      3. remplacement du mot de passe par une valeur aléatoire non conservée ;
      4. retrait de tous les groupes (sauf -KeepGroups) et du responsable hiérarchique ;
      5. déplacement vers l'OU des comptes désactivés si -DisabledOU est fourni.
    Les comptes protégés (adminCount = 1) sont refusés sans -Force.

.EXAMPLE
    .\Disable-DepartedUser.ps1 -Identity j.dupont -DisabledOU 'OU=Comptes desactives,DC=corp,DC=local' -Reference 'Ticket 4521' -WhatIf

.EXAMPLE
    'j.dupont', 'p.martin' | .\Disable-DepartedUser.ps1 -LogDirectory D:\Journaux\Departs
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, ValueFromPipeline)][string[]]$Identity,
    [string]$DisabledOU,
    [string]$LogDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'ADDS-Departs'),
    [string]$Reference,
    [switch]$KeepGroups,
    [switch]$Force
)

begin {
    . "$PSScriptRoot/../../lib/Communs.ps1"
    Initialize-ADToolbox
    if ($DisabledOU) { $null = Get-ADOrganizationalUnit -Identity $DisabledOU -ErrorAction Stop }
    $stamp = Get-Date -Format 'yyyy-MM-dd'
}
process {
    foreach ($id in $Identity) {
        $result = [pscustomobject]@{ SamAccountName = $id; Status = 'Simulation'; GroupsRemoved = 0; GroupBackup = ''; Detail = '' }
        try {
            $user = Get-ADUser -Identity $id -Properties MemberOf, Description, adminCount -ErrorAction Stop
            $result.SamAccountName = $user.SamAccountName
            if ($user.adminCount -eq 1 -and -not $Force) { throw 'Compte protégé (adminCount = 1) : relancer avec -Force après vérification.' }
            $groups = @($user.MemberOf)
            if ($PSCmdlet.ShouldProcess($user.DistinguishedName, 'Désactiver le compte, retirer ses groupes et le déplacer')) {
                if ($groups.Count -gt 0) {
                    $backup = Join-Path $LogDirectory ("{0}_{1}_groupes.csv" -f $user.SamAccountName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
                    $groups | ForEach-Object { [pscustomobject]@{ SamAccountName = $user.SamAccountName; Group = $_ } } | Export-Report -CsvPath $backup | Out-Null
                    $result.GroupBackup = $backup
                }
                Disable-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop
                $note = "Désactivé le $stamp" + $(if ($Reference) { " ($Reference)" }) + $(if ($user.Description) { " | $($user.Description)" })
                Set-ADUser -Identity $user.DistinguishedName -Description $note -Manager $null -ErrorAction Stop
                Set-ADAccountPassword -Identity $user.DistinguishedName -Reset -NewPassword (ConvertTo-SecureText -Text (Get-RandomPassword -Length 32)) -ErrorAction Stop
                $errors = 0
                if (-not $KeepGroups) {
                    foreach ($g in $groups) {
                        try { Remove-ADGroupMember -Identity $g -Members $user.DistinguishedName -Confirm:$false -ErrorAction Stop; $result.GroupsRemoved++ }
                        catch { $errors++; Write-Warning "Retrait de '$g' impossible : $($_.Exception.Message)" }
                    }
                }
                if ($DisabledOU) { Move-ADObject -Identity $user.DistinguishedName -TargetPath $DisabledOU -ErrorAction Stop }
                $result.Status = if ($errors) { 'Traité (groupes incomplets)' } else { 'Traité' }
            }
            else { $result.Detail = "$($groups.Count) groupe(s) seraient retirés" }
        }
        catch { $result.Status = 'Erreur'; $result.Detail = $_.Exception.Message }
        $result
    }
}
