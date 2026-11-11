<#
.SYNOPSIS
    Restaure une stratégie de groupe à partir d'un dossier de sauvegarde.

.DESCRIPTION
    Sans -Name : liste les GPO présentes dans le dossier de sauvegarde (inventaire.csv).
    Avec -Name : restaure cette GPO à l'état sauvegardé. La GPO doit encore exister dans le
    domaine ; pour une GPO supprimée, la recréer vide sous le même nom puis utiliser
    Import-GPO depuis la console. Les liens vers les OU ne sont pas restaurés.

.EXAMPLE
    .\Restore-GPOFromBackup.ps1 -BackupPath D:\Sauvegardes\GPO\2026-11-01_020000

.EXAMPLE
    .\Restore-GPOFromBackup.ps1 -BackupPath D:\Sauvegardes\GPO\2026-11-01_020000 -Name 'Postes - Verrouillage de session'
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$BackupPath,
    [string]$Name
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox -GroupPolicy

$inventory = Join-Path $BackupPath 'inventaire.csv'
if (-not (Test-Path -LiteralPath $inventory)) { throw "Inventaire introuvable : $inventory (le dossier doit provenir de Backup-AllGPO.ps1)." }
$entries = @(Import-Csv -LiteralPath $inventory -Delimiter ';' | Where-Object BackupId)

if (-not $Name) { return $entries | Select-Object DisplayName, Id, BackupId, ModificationTime }

$entry = @($entries | Where-Object DisplayName -eq $Name)
if ($entry.Count -ne 1) { throw "La GPO '$Name' figure $($entry.Count) fois dans cette sauvegarde." }
$status = 'Simulation'
if ($PSCmdlet.ShouldProcess($Name, "Restaurer la GPO depuis la sauvegarde $($entry[0].BackupId)")) {
    Restore-GPO -BackupId $entry[0].BackupId -Path $BackupPath -ErrorAction Stop | Out-Null
    $status = 'Restaurée'
}
[pscustomobject]@{ DisplayName = $Name; BackupId = $entry[0].BackupId; Status = $status }
