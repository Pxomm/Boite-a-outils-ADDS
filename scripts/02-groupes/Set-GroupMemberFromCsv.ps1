<#
.SYNOPSIS
    Ajoute ou retire des membres de groupes en masse à partir d'un fichier CSV.

.DESCRIPTION
    Colonnes (séparateur « ; ») : Groupe;Membre, et facultativement Action (Ajout ou Retrait,
    « Ajout » par défaut). Les opérations déjà en place sont signalées, pas rejouées.
    « Membre » est un identifiant (sAMAccountName) d'utilisateur, de groupe ou d'ordinateur ;
    pour un ordinateur, le terminer par « $ » (« PC-0142$ »).
    Modèle : exemples/membres-groupes.csv.

.EXAMPLE
    .\Set-GroupMemberFromCsv.ps1 -CsvPath .\membres-groupes.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$CsvPath,
    [string]$Delimiter = ';'
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

if (-not (Test-Path -LiteralPath $CsvPath)) { throw "Fichier introuvable : $CsvPath" }
$rows = @(Import-Csv -LiteralPath $CsvPath -Delimiter $Delimiter)
if ($rows.Count -eq 0) { throw 'Le fichier ne contient aucune ligne.' }
$missing = @('Groupe', 'Membre' | Where-Object { $_ -notin $rows[0].PSObject.Properties.Name })
if ($missing) { throw "Colonne(s) absente(s) : $($missing -join ', ') (séparateur attendu : « $Delimiter »)." }

$memberCache = @{}
foreach ($row in $rows) {
    $groupName = "$($row.Groupe)".Trim(); $memberName = "$($row.Membre)".Trim()
    $action = if ("$($row.Action)".Trim()) { "$($row.Action)".Trim() } else { 'Ajout' }
    $result = [pscustomobject]@{ Group = $groupName; Member = $memberName; Action = $action; Status = ''; Detail = '' }
    try {
        if ($action -notin 'Ajout', 'Retrait') { throw "Action inconnue '$action' (Ajout ou Retrait)." }
        $group = Get-ADGroup -Identity $groupName -ErrorAction Stop
        $member = Get-ADObject -Filter "SamAccountName -eq '$(ConvertTo-FilterValue $memberName)'" -ErrorAction Stop | Select-Object -First 1
        if (-not $member) { throw "Membre '$memberName' introuvable." }
        if (-not $memberCache.ContainsKey($group.DistinguishedName)) {
            $memberCache[$group.DistinguishedName] = New-Object System.Collections.Generic.HashSet[string] (, [string[]]@((Get-ADGroup -Identity $group.DistinguishedName -Properties Members).Members))
        }
        $current = $memberCache[$group.DistinguishedName]
        $isMember = $current.Contains($member.DistinguishedName)
        if ($action -eq 'Ajout' -and $isMember) { $result.Status = 'Déjà membre' }
        elseif ($action -eq 'Retrait' -and -not $isMember) { $result.Status = 'Déjà absent' }
        elseif ($PSCmdlet.ShouldProcess($group.Name, "$action de $memberName")) {
            if ($action -eq 'Ajout') { Add-ADGroupMember -Identity $group.DistinguishedName -Members $member.DistinguishedName -ErrorAction Stop; [void]$current.Add($member.DistinguishedName) }
            else { Remove-ADGroupMember -Identity $group.DistinguishedName -Members $member.DistinguishedName -Confirm:$false -ErrorAction Stop; [void]$current.Remove($member.DistinguishedName) }
            $result.Status = 'Fait'
        }
        else { $result.Status = 'Simulation' }
    }
    catch { $result.Status = 'Erreur'; $result.Detail = $_.Exception.Message }
    $result
}
