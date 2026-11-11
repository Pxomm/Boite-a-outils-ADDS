<#
.SYNOPSIS
    Redirige les conteneurs par défaut des nouveaux ordinateurs et utilisateurs vers des unités d'organisation.

.DESCRIPTION
    Par défaut, un poste joint au domaine arrive dans « CN=Computers » et un compte créé
    sans emplacement dans « CN=Users » : deux conteneurs sur lesquels aucune stratégie de
    groupe ne peut être liée. Le script lance redircmp.exe et redirusr.exe, à exécuter sur
    un contrôleur de domaine avec un compte administrateur du domaine.
    Sans paramètre de destination, il affiche seulement la configuration actuelle.

.EXAMPLE
    .\Set-DefaultContainer.ps1

.EXAMPLE
    .\Set-DefaultContainer.ps1 -ComputersOU 'OU=Arrivee,OU=Postes,DC=corp,DC=local' -UsersOU 'OU=Arrivee,OU=Utilisateurs,DC=corp,DC=local'
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ComputersOU,
    [string]$UsersOU
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

foreach ($item in @(@{ Kind = 'Ordinateurs'; Target = $ComputersOU; Tool = 'redircmp.exe' }, @{ Kind = 'Utilisateurs'; Target = $UsersOU; Tool = 'redirusr.exe' })) {
    $domain = Get-ADDomain
    $current = if ($item.Kind -eq 'Ordinateurs') { $domain.ComputersContainer } else { $domain.UsersContainer }
    $status = 'Inchangé'
    if ($item.Target) {
        $null = Get-ADOrganizationalUnit -Identity $item.Target -ErrorAction Stop
        if ($item.Target -eq $current) { $status = 'Déjà en place' }
        elseif ($PSCmdlet.ShouldProcess($item.Target, "Rediriger le conteneur par défaut des $($item.Kind.ToLower()) ($($item.Tool))")) {
            $output = & $item.Tool $item.Target 2>&1
            $status = if ($LASTEXITCODE -eq 0) { 'Redirigé' } else { "Erreur ($($item.Tool), code $LASTEXITCODE) : $($output -join ' ')" }
        }
        else { $status = 'Simulation' }
    }
    [pscustomobject]@{ Kind = $item.Kind; Current = $current; Requested = "$($item.Target)"; Status = $status }
}
