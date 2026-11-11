<#
.SYNOPSIS
    Crée un compte utilisateur complet : identifiant, UPN, mot de passe initial, groupes.

.DESCRIPTION
    - L'identifiant est construit à partir du prénom et du nom (« j.dupont »), sans accent,
      et rendu unique par un suffixe numérique si nécessaire.
    - Le mot de passe initial est aléatoire et doit être changé à la première ouverture de session.
    - -CopyGroupsFrom recopie les groupes d'un compte modèle.
    Le mot de passe initial figure dans l'objet renvoyé : à transmettre par un canal sûr.

.PARAMETER Path
    Nom distinctif de l'unité d'organisation de destination.

.EXAMPLE
    .\New-UserAccount.ps1 -GivenName Jeanne -Surname Dupont -Path 'OU=Compta,OU=Utilisateurs,DC=corp,DC=local' -CopyGroupsFrom m.martin

.EXAMPLE
    .\New-UserAccount.ps1 -GivenName Jeanne -Surname Dupont -Path 'OU=Compta,DC=corp,DC=local' -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$GivenName,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Surname,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path,
    [ValidatePattern('^[A-Za-z0-9._-]{1,20}$')][string]$SamAccountName,
    [string]$UpnSuffix,
    [string]$CopyGroupsFrom,
    [string[]]$Group = @(),
    [string]$Title,
    [string]$Department,
    [string]$Description,
    [string]$Manager,
    [datetime]$ExpirationDate
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$GivenName = $GivenName.Trim(); $Surname = $Surname.Trim()
$null = Get-ADOrganizationalUnit -Identity $Path -ErrorAction Stop        # l'OU doit exister
if (-not $UpnSuffix) { $UpnSuffix = (Get-ADDomain).DNSRoot }

# Identifiant : fourni (doit être libre) ou généré (rendu unique)
if ($SamAccountName) {
    if (Get-ADUser -Filter "SamAccountName -eq '$(ConvertTo-FilterValue $SamAccountName)'") { throw "L'identifiant '$SamAccountName' existe déjà." }
}
else {
    $base = ConvertTo-SamAccountName -GivenName $GivenName -Surname $Surname
    $SamAccountName = $base; $n = 1
    while (Get-ADUser -Filter "SamAccountName -eq '$(ConvertTo-FilterValue $SamAccountName)'") {
        $n++
        $suffix = "$n"
        $SamAccountName = $base.Substring(0, [Math]::Min($base.Length, 20 - $suffix.Length)) + $suffix
    }
}

# Nom d'objet (CN) : unique dans l'OU
$name = "$GivenName $Surname"
if (Get-ADUser -Filter "Name -eq '$(ConvertTo-FilterValue $name)'" -SearchBase $Path -SearchScope OneLevel) { $name = "$GivenName $Surname ($SamAccountName)" }

# Groupes : ceux du modèle, plus ceux demandés
$groups = @($Group)
if ($CopyGroupsFrom) { $groups += @((Get-ADUser -Identity $CopyGroupsFrom -Properties MemberOf -ErrorAction Stop).MemberOf) }
$groups = @($groups | Where-Object { $_ } | Select-Object -Unique)
foreach ($g in $groups) { $null = Get-ADGroup -Identity $g -ErrorAction Stop }   # tout vérifier avant de créer

$plain = Get-RandomPassword -Length 16
$new = @{
    Name                  = $name
    DisplayName           = "$GivenName $Surname"
    GivenName             = $GivenName
    Surname               = $Surname
    SamAccountName        = $SamAccountName
    UserPrincipalName     = "$SamAccountName@$UpnSuffix"
    Path                  = $Path
    AccountPassword       = (ConvertTo-SecureText -Text $plain)
    Enabled               = $true
    ChangePasswordAtLogon = $true
}
if ($Title)       { $new.Title = $Title }
if ($Department)  { $new.Department = $Department }
if ($Description) { $new.Description = $Description }
if ($Manager)     { $new.Manager = (Get-ADUser -Identity $Manager -ErrorAction Stop).DistinguishedName }
if ($PSBoundParameters.ContainsKey('ExpirationDate')) { $new.AccountExpirationDate = $ExpirationDate }

$status = 'Simulation'; $added = @()
if ($PSCmdlet.ShouldProcess("$name ($SamAccountName) dans $Path", 'Créer le compte utilisateur')) {
    New-ADUser @new -ErrorAction Stop
    $status = 'Créé'
    foreach ($g in $groups) {
        try { Add-ADGroupMember -Identity $g -Members $SamAccountName -ErrorAction Stop; $added += $g }
        catch { Write-Warning "Ajout de $SamAccountName au groupe '$g' impossible : $($_.Exception.Message)"; $status = 'Créé (groupes incomplets)' }
    }
}

[pscustomobject]@{
    SamAccountName    = $SamAccountName
    UserPrincipalName = $new.UserPrincipalName
    Name              = $name
    Path              = $Path
    Status            = $status
    GroupCount        = $added.Count
    InitialPassword   = if ($status -eq 'Simulation') { '' } else { $plain }
}
