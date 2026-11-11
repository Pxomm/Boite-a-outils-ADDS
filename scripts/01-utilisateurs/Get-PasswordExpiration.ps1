<#
.SYNOPSIS
    Liste les utilisateurs dont le mot de passe expire dans les N prochains jours, et peut les prévenir par courriel.

.DESCRIPTION
    La date d'expiration est celle calculée par Active Directory
    (msDS-UserPasswordExpiryTimeComputed) : elle tient compte des stratégies de mot de passe
    affinées. -IncludeExpired ajoute les mots de passe déjà expirés.
    -Notify envoie un message à chaque utilisateur disposant d'une adresse.

.EXAMPLE
    .\Get-PasswordExpiration.ps1 -Days 10

.EXAMPLE
    .\Get-PasswordExpiration.ps1 -Days 7 -Notify -SmtpServer smtp.corp.local -From support@corp.local
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateRange(1, 365)][int]$Days = 14,
    [string]$SearchBase,
    [switch]$IncludeExpired,
    [switch]$Notify,
    [string]$SmtpServer,
    [string]$From,
    [string]$CsvPath
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox
if ($Notify -and (-not $SmtpServer -or -not $From)) { throw '-Notify exige -SmtpServer et -From.' }

$query = @{ Filter = "Enabled -eq `$true -and PasswordNeverExpires -eq `$false"
            Properties = 'msDS-UserPasswordExpiryTimeComputed', 'mail', 'PasswordLastSet' }
if ($SearchBase) { $query.SearchBase = $SearchBase }
$now = Get-Date

$rows = Get-ADUser @query | ForEach-Object {
    $expires = ConvertFrom-FileTime $_.'msDS-UserPasswordExpiryTimeComputed'
    if ($expires) {
        $left = [int][Math]::Floor(($expires - $now).TotalDays)
        if (($left -ge 0 -and $left -le $Days) -or ($IncludeExpired -and $left -lt 0)) {
            [pscustomobject]@{ SamAccountName = $_.SamAccountName; Name = $_.Name; Mail = $_.mail; PasswordLastSet = $_.PasswordLastSet
                               ExpiresOn = $expires; DaysLeft = $left; Notified = $false }
        }
    }
} | Sort-Object ExpiresOn

if ($Notify) {
    foreach ($row in $rows | Where-Object { $_.Mail -and $_.DaysLeft -ge 0 }) {
        $body = "Bonjour $($row.Name),`r`n`r`nVotre mot de passe expire le $($row.ExpiresOn.ToString('dd/MM/yyyy à HH:mm')) (dans $($row.DaysLeft) jour(s)).`r`n" +
                "Merci de le changer avant cette date : Ctrl+Alt+Suppr, puis « Modifier un mot de passe ».`r`n`r`nLe service informatique"
        if ($PSCmdlet.ShouldProcess($row.Mail, 'Envoyer le rappel d''expiration')) {
            try {
                Send-MailMessage -SmtpServer $SmtpServer -From $From -To $row.Mail -Subject "Votre mot de passe expire dans $($row.DaysLeft) jour(s)" -Body $body -Encoding ([Text.Encoding]::UTF8) -ErrorAction Stop
                $row.Notified = $true
            }
            catch { Write-Warning "Envoi à $($row.Mail) impossible : $($_.Exception.Message)" }
        }
    }
}
$rows | Export-Report -CsvPath $CsvPath
