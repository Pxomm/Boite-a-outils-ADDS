<#
.SYNOPSIS
    Produit le rapport quotidien de l'annuaire en HTML et peut l'envoyer par courriel.

.DESCRIPTION
    Assemble les contrôles de la boîte à outils en une page : état des contrôleurs de
    domaine, réplication, comptes verrouillés, mots de passe expirant sous 7 jours,
    membres des groupes à privilèges, comptes et ordinateurs inactifs, âge du mot de passe
    krbtgt. Une section qui échoue est signalée dans le rapport sans interrompre les autres.
    À planifier chaque matin par une tâche planifiée, avec un compte de service en lecture.

.EXAMPLE
    .\New-DailyReport.ps1 -Path D:\Rapports\AD

.EXAMPLE
    .\New-DailyReport.ps1 -Path D:\Rapports\AD -SmtpServer smtp.corp.local -From ad@corp.local -To infra@corp.local
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [ValidateRange(15, 3650)][int]$InactiveDays = 90,
    [string]$SmtpServer,
    [string]$From,
    [string[]]$To
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox
if ($SmtpServer -and (-not $From -or -not $To)) { throw '-SmtpServer exige -From et -To.' }
$root = Split-Path -Parent $PSScriptRoot
$encode = { param($text) [System.Net.WebUtility]::HtmlEncode("$text") }

# Chaque section : titre, script à lancer, colonnes affichées, règle d'alerte
$sections = @(
    @{ Title = 'Contrôleurs de domaine';                   Script = '07-controleurs-de-domaine/Get-DCHealth.ps1';          Params = @{}
       Columns = 'HostName', 'Healthy', 'Issues', 'SystemFreePercent', 'LastBoot';                                      Alert = { param($r) @($r | Where-Object { -not $_.Healthy }).Count } }
    @{ Title = 'Réplication en défaut';                    Script = '07-controleurs-de-domaine/Get-ReplicationStatus.ps1';  Params = @{ ProblemsOnly = $true }
       Columns = 'Server', 'Partner', 'Partition', 'LastSuccess', 'LastResult', 'ConsecutiveFailures';                 Alert = { param($r) @($r).Count } }
    @{ Title = 'Comptes verrouillés';                      Script = '01-utilisateurs/Unlock-UserAccount.ps1';               Params = @{}
       Columns = 'SamAccountName', 'Name', 'LastLogonDate';                                                              Alert = { 0 } }
    @{ Title = 'Mots de passe expirant sous 7 jours';      Script = '01-utilisateurs/Get-PasswordExpiration.ps1';           Params = @{ Days = 7 }
       Columns = 'SamAccountName', 'Name', 'ExpiresOn', 'DaysLeft';                                                      Alert = { 0 } }
    @{ Title = 'Membres des groupes à privilèges';         Script = '06-securite/Get-PrivilegedGroupMember.ps1';            Params = @{}
       Columns = 'Group', 'SamAccountName', 'Enabled', 'LastLogon', 'PasswordAgeDays', 'InProtectedUsers';              Alert = { 0 } }
    @{ Title = 'Mot de passe krbtgt';                      Script = '06-securite/Get-KrbtgtStatus.ps1';                     Params = @{}
       Columns = 'SamAccountName', 'PasswordLastSet', 'PasswordAgeDays', 'Status';                                       Alert = { param($r) @($r | Where-Object { $_.Status -ne 'OK' }).Count } }
    @{ Title = "Utilisateurs inactifs depuis $InactiveDays jours";  Script = '01-utilisateurs/Get-InactiveUser.ps1';       Params = @{ Days = $InactiveDays }
       Columns = 'SamAccountName', 'Name', 'LastLogon', 'DaysInactive';                                                  Alert = { 0 } }
    @{ Title = "Ordinateurs inactifs depuis $InactiveDays jours";   Script = '03-ordinateurs/Get-InactiveComputer.ps1';    Params = @{ Days = $InactiveDays }
       Columns = 'Name', 'OperatingSystem', 'LastLogon', 'DaysInactive';                                                 Alert = { 0 } }
)

$body = New-Object System.Text.StringBuilder
$summary = New-Object System.Collections.Generic.List[object]
foreach ($section in $sections) {
    $rows = @(); $failure = ''
    try { $sectionParams = $section.Params; $rows = @(& (Join-Path $root $section.Script) @sectionParams -WarningAction SilentlyContinue) }
    catch { $failure = $_.Exception.Message }
    $alerts = if ($failure) { 1 } else { [int](& $section.Alert $rows) }
    $summary.Add([pscustomobject]@{ Section = $section.Title; Rows = $rows.Count; Alerts = $alerts; Error = $failure })

    [void]$body.AppendLine("<h2 class=""$(if ($alerts) { 'alert' } else { 'ok' })"">$(& $encode $section.Title) <small>($($rows.Count))</small></h2>")
    if ($failure) { [void]$body.AppendLine("<p class=""alert"">Section indisponible : $(& $encode $failure)</p>") }
    elseif ($rows.Count -eq 0) { [void]$body.AppendLine('<p>Rien à signaler.</p>') }
    else {
        [void]$body.AppendLine('<table><tr>' + (($section.Columns | ForEach-Object { "<th>$(& $encode $_)</th>" }) -join '') + '</tr>')
        foreach ($row in $rows | Select-Object -First 200) {
            [void]$body.AppendLine('<tr>' + (($section.Columns | ForEach-Object { "<td>$(& $encode $row.$_)</td>" }) -join '') + '</tr>')
        }
        [void]$body.AppendLine('</table>')
        if ($rows.Count -gt 200) { [void]$body.AppendLine("<p>… $($rows.Count - 200) ligne(s) supplémentaire(s) non affichée(s).</p>") }
    }
}

$domain = (Get-ADDomain).DNSRoot
$totalAlerts = ($summary | Measure-Object Alerts -Sum).Sum
$html = @"
<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><title>Rapport Active Directory - $domain</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; font-size: 13px; color: #222; margin: 24px; }
h1 { font-size: 20px; } h2 { font-size: 15px; margin-top: 22px; padding: 4px 8px; border-left: 4px solid #2e7d32; }
h2.alert { border-left-color: #c62828; } p.alert { color: #c62828; }
table { border-collapse: collapse; } th, td { border: 1px solid #ccc; padding: 3px 8px; text-align: left; } th { background: #f0f0f0; }
small { color: #666; font-weight: normal; }
</style></head><body>
<h1>Rapport Active Directory — $(& $encode $domain)</h1>
<p>Généré le $(Get-Date -Format 'dd/MM/yyyy à HH:mm') sur $(& $encode $env:COMPUTERNAME). Points d'attention : <strong>$totalAlerts</strong>.</p>
$($body.ToString())
</body></html>
"@

if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
$file = Join-Path $Path ("Rapport-AD_{0}.html" -f (Get-Date -Format 'yyyy-MM-dd'))
[IO.File]::WriteAllText($file, $html, (New-Object System.Text.UTF8Encoding $true))

if ($SmtpServer) {
    try { Send-MailMessage -SmtpServer $SmtpServer -From $From -To $To -Subject "Rapport Active Directory $domain : $totalAlerts point(s) d'attention" -Body $html -BodyAsHtml -Encoding ([Text.Encoding]::UTF8) -ErrorAction Stop }
    catch { Write-Warning "Envoi du rapport impossible : $($_.Exception.Message)" }
}
[pscustomobject]@{ File = $file; Alerts = $totalAlerts; Sections = $summary.ToArray() }
