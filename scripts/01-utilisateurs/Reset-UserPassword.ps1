<#
.SYNOPSIS
    Réinitialise le mot de passe d'un utilisateur avec une valeur aléatoire et déverrouille le compte.

.DESCRIPTION
    Le nouveau mot de passe figure dans l'objet renvoyé. Par défaut l'utilisateur doit le changer
    à la prochaine ouverture de session (sauf -NoChangeAtLogon, ou si le compte porte
    « le mot de passe n'expire jamais », cas signalé par un avertissement).

.EXAMPLE
    .\Reset-UserPassword.ps1 -Identity j.dupont
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, ValueFromPipeline)][string[]]$Identity,
    [ValidateRange(12, 128)][int]$Length = 16,
    [switch]$NoChangeAtLogon
)

begin {
    . "$PSScriptRoot/../../lib/Communs.ps1"
    Initialize-ADToolbox
}
process {
    foreach ($id in $Identity) {
        try {
            $user = Get-ADUser -Identity $id -Properties PasswordNeverExpires, LockedOut -ErrorAction Stop
            $plain = Get-RandomPassword -Length $Length
            $status = 'Simulation'; $mustChange = $false
            if ($PSCmdlet.ShouldProcess($user.DistinguishedName, 'Réinitialiser le mot de passe')) {
                Set-ADAccountPassword -Identity $user.DistinguishedName -Reset -NewPassword (ConvertTo-SecureText -Text $plain) -ErrorAction Stop
                Unlock-ADAccount -Identity $user.DistinguishedName -ErrorAction Stop
                if (-not $NoChangeAtLogon) {
                    if ($user.PasswordNeverExpires) { Write-Warning "$($user.SamAccountName) : « le mot de passe n'expire jamais » est coché, changement à la prochaine session non imposé." }
                    else { Set-ADUser -Identity $user.DistinguishedName -ChangePasswordAtLogon $true -ErrorAction Stop; $mustChange = $true }
                }
                $status = 'Réinitialisé'
            }
            [pscustomobject]@{ SamAccountName = $user.SamAccountName; Status = $status; MustChangeAtLogon = $mustChange
                               NewPassword = $(if ($status -eq 'Réinitialisé') { $plain } else { '' }); Detail = '' }
        }
        catch { [pscustomobject]@{ SamAccountName = $id; Status = 'Erreur'; MustChangeAtLogon = $false; NewPassword = ''; Detail = $_.Exception.Message } }
    }
}
