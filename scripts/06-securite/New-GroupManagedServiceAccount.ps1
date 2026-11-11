<#
.SYNOPSIS
    Crée un compte de service administré de groupe (gMSA), dont le mot de passe est géré par Active Directory.

.DESCRIPTION
    Un gMSA remplace un compte de service classique à mot de passe fixe : son mot de passe
    (240 octets aléatoires) est renouvelé automatiquement et seuls les ordinateurs autorisés
    peuvent le récupérer. Le script :
      1. vérifie qu'une clé racine KDS existe (et la crée avec -CreateKdsRootKey ; elle
         n'est utilisable qu'après 10 heures, délai de réplication imposé par Microsoft) ;
      2. crée le gMSA ;
      3. autorise le groupe d'ordinateurs indiqué à récupérer son mot de passe.
    Sur chaque serveur : Install-ADServiceAccount, puis configurer le service avec le compte
    « DOMAINE\nom$ » et un mot de passe vide.

.EXAMPLE
    .\New-GroupManagedServiceAccount.ps1 -Name gmsa-sql01 -AllowedGroup GG_Serveurs_SQL -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]{1,15}$')][string]$Name,
    [Parameter(Mandatory)][string]$AllowedGroup,
    [string]$Description,
    [string[]]$ServicePrincipalName,
    [switch]$CreateKdsRootKey
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$domain = Get-ADDomain
$group = Get-ADGroup -Identity $AllowedGroup -ErrorAction Stop
if (Get-ADServiceAccount -Filter "Name -eq '$Name'") { throw "Un compte de service nommé '$Name' existe déjà." }

$key = @(Get-KdsRootKey)
if ($key.Count -eq 0) {
    if (-not $CreateKdsRootKey) { throw 'Aucune clé racine KDS dans la forêt : relancer avec -CreateKdsRootKey (une seule fois par forêt), puis attendre 10 heures.' }
    if ($PSCmdlet.ShouldProcess($domain.Forest, 'Créer la clé racine KDS')) {
        Add-KdsRootKey -EffectiveImmediately | Out-Null
        Write-Warning 'Clé racine KDS créée. Attendre 10 heures (réplication) avant de créer le compte : relancer ce script ensuite.'
        return [pscustomobject]@{ Name = $Name; DNSHostName = ''; AllowedGroup = $group.Name; Status = 'Clé KDS créée, compte à créer dans 10 heures' }
    }
}
elseif (@($key | Where-Object { $_.EffectiveTime -le (Get-Date) }).Count -eq 0) {
    throw "La clé racine KDS n'est pas encore utilisable (effective le $(($key | Sort-Object EffectiveTime)[0].EffectiveTime))."
}

$new = @{ Name = $Name; DNSHostName = "$Name.$($domain.DNSRoot)".ToLowerInvariant(); PrincipalsAllowedToRetrieveManagedPassword = $group.DistinguishedName; Enabled = $true }
if ($Description) { $new.Description = $Description }
if ($ServicePrincipalName) { $new.ServicePrincipalNames = $ServicePrincipalName }
$status = 'Simulation'
if ($PSCmdlet.ShouldProcess($Name, "Créer le compte de service administré de groupe (récupérable par $($group.Name))")) {
    New-ADServiceAccount @new -ErrorAction Stop
    $status = 'Créé'
}
[pscustomobject]@{ Name = $Name; DNSHostName = $new.DNSHostName; AllowedGroup = $group.Name; Status = $status }
