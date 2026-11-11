<#
.SYNOPSIS
    Passe en revue les stratégies de groupe : non liées, vides, désactivées, incohérentes.

.DESCRIPTION
    Pour chaque GPO, d'après son rapport XML :
      - Unlinked        : liée à aucun site, domaine ni OU ;
      - AllLinksDisabled: tous ses liens sont désactivés ;
      - Empty           : aucun paramètre, ni ordinateur ni utilisateur ;
      - AllSettingsDisabled : état « Tous les paramètres désactivés » ;
      - VersionMismatch : numéros de version différents entre l'annuaire et SYSVOL
                          (réplication incomplète ou modification en cours).
    -ProblemsOnly ne renvoie que les GPO présentant au moins un de ces constats.

.EXAMPLE
    .\Get-GPOHealthReport.ps1 -ProblemsOnly -CsvPath C:\Temp\gpo.csv
#>
[CmdletBinding()]
param([switch]$ProblemsOnly, [string]$CsvPath)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox -GroupPolicy

Get-GPO -All | Sort-Object DisplayName | ForEach-Object {
    $gpo = $_
    try { [xml]$report = Get-GPOReport -Guid $gpo.Id -ReportType Xml -ErrorAction Stop }
    catch { Write-Warning "Rapport illisible pour '$($gpo.DisplayName)' : $($_.Exception.Message)"; return }
    $links = @($report.GPO.LinksTo | Where-Object { $_ })
    $computerEmpty = -not $report.GPO.Computer.ExtensionData
    $userEmpty     = -not $report.GPO.User.ExtensionData
    $mismatch = ($report.GPO.Computer.VersionDirectory -ne $report.GPO.Computer.VersionSysvol) -or ($report.GPO.User.VersionDirectory -ne $report.GPO.User.VersionSysvol)
    $row = [pscustomobject]@{
        DisplayName         = $gpo.DisplayName
        GpoStatus           = "$($gpo.GpoStatus)"
        LinkCount           = $links.Count
        Unlinked            = ($links.Count -eq 0)
        AllLinksDisabled    = ($links.Count -gt 0 -and @($links | Where-Object { $_.Enabled -eq 'true' }).Count -eq 0)
        Empty               = ($computerEmpty -and $userEmpty)
        AllSettingsDisabled = ("$($gpo.GpoStatus)" -eq 'AllSettingsDisabled')
        VersionMismatch     = [bool]$mismatch
        ModificationTime    = $gpo.ModificationTime
        Links               = ($links | ForEach-Object { $_.SOMPath }) -join ' | '
        Id                  = $gpo.Id
    }
    if (-not $ProblemsOnly -or $row.Unlinked -or $row.AllLinksDisabled -or $row.Empty -or $row.AllSettingsDisabled -or $row.VersionMismatch) { $row }
} | Export-Report -CsvPath $CsvPath
