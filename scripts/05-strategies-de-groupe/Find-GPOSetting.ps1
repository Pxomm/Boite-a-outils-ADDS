<#
.SYNOPSIS
    Recherche un texte dans les paramètres de toutes les stratégies de groupe.

.DESCRIPTION
    Répond à « quelle GPO configure ceci ? » : le texte (expression régulière acceptée) est
    recherché dans le rapport XML de chaque GPO — noms de paramètres, valeurs, chemins,
    scripts, clés de registre. Le libellé des paramètres dépend de la langue du poste
    d'administration.

.EXAMPLE
    .\Find-GPOSetting.ps1 -Pattern 'verrouillage'

.EXAMPLE
    .\Find-GPOSetting.ps1 -Pattern '\\\\srv-fichiers\\' -SimpleMatch:$false
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Pattern,
    [bool]$SimpleMatch = $true,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox -GroupPolicy

$regex = if ($SimpleMatch) { [regex]::Escape($Pattern) } else { $Pattern }
Get-GPO -All | Sort-Object DisplayName | ForEach-Object {
    $gpo = $_
    try { $xml = Get-GPOReport -Guid $gpo.Id -ReportType Xml -ErrorAction Stop }
    catch { Write-Warning "Rapport illisible pour '$($gpo.DisplayName)' : $($_.Exception.Message)"; return }
    $found = [regex]::Matches($xml, "[^<>\r\n]*$regex[^<>\r\n]*", 'IgnoreCase')
    if ($found.Count -gt 0) {
        [pscustomobject]@{ DisplayName = $gpo.DisplayName; MatchCount = $found.Count
                           Sample = (@($found | ForEach-Object { $_.Value.Trim() } | Select-Object -Unique -First 3) -join ' | '); Id = $gpo.Id }
    }
} | Export-Report -CsvPath $CsvPath
