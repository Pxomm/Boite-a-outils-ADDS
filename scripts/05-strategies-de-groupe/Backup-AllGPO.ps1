<#
.SYNOPSIS
    Sauvegarde toutes les stratégies de groupe dans un dossier daté, avec inventaire et rapports.

.DESCRIPTION
    Crée <Path>\<AAAA-MM-JJ_HHmmss>\ contenant la sauvegarde de chaque GPO (format de la
    console GPMC, restaurable par Restore-GPOFromBackup.ps1), un inventaire CSV et, avec
    -IncludeReport, un rapport HTML par GPO. -KeepDays supprime les sauvegardes plus anciennes.
    Les liens des GPO vers les OU ne font pas partie d'une sauvegarde de GPO : ils figurent
    dans l'inventaire produit par Get-GPOLink.ps1.

.EXAMPLE
    .\Backup-AllGPO.ps1 -Path D:\Sauvegardes\GPO -IncludeReport -KeepDays 90
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$IncludeReport,
    [ValidateRange(0, 3650)][int]$KeepDays = 0
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox -GroupPolicy

$target = Join-Path $Path (Get-Date -Format 'yyyy-MM-dd_HHmmss')
$gpos = @(Get-GPO -All | Sort-Object DisplayName)
if (-not $PSCmdlet.ShouldProcess($target, "Sauvegarder $($gpos.Count) stratégie(s) de groupe")) {
    $gpos | ForEach-Object { [pscustomobject]@{ DisplayName = $_.DisplayName; Id = $_.Id; BackupId = ''; Status = 'Simulation' } }
    return
}
New-Item -ItemType Directory -Path $target -Force | Out-Null

$rows = foreach ($gpo in $gpos) {
    $row = [pscustomobject]@{ DisplayName = $gpo.DisplayName; Id = $gpo.Id; BackupId = ''; GpoStatus = "$($gpo.GpoStatus)"; ModificationTime = $gpo.ModificationTime; Status = '' }
    try {
        $backup = Backup-GPO -Guid $gpo.Id -Path $target -Comment "Sauvegarde automatique $(Get-Date -Format 'yyyy-MM-dd')" -ErrorAction Stop
        $row.BackupId = $backup.Id
        if ($IncludeReport) {
            $file = Join-Path $target (("{0}.html" -f $gpo.DisplayName) -replace '[\\/:*?"<>|]', '_')
            Get-GPOReport -Guid $gpo.Id -ReportType Html -Path $file -ErrorAction Stop
        }
        $row.Status = 'Sauvegardée'
    }
    catch { $row.Status = "Erreur : $($_.Exception.Message)" }
    $row
}
$rows | Export-Report -CsvPath (Join-Path $target 'inventaire.csv') | Out-Null

if ($KeepDays -gt 0) {
    $limit = (Get-Date).AddDays(-$KeepDays)
    Get-ChildItem -LiteralPath $Path -Directory | Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{6}$' -and $_.CreationTime -lt $limit } | ForEach-Object {
        Write-Verbose "Suppression de l'ancienne sauvegarde $($_.FullName)"
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
}
$rows
if (@($rows | Where-Object { $_.Status -ne 'Sauvegardée' }).Count -gt 0) { Write-Warning "Certaines GPO n'ont pas pu être sauvegardées : voir la colonne Status." }
