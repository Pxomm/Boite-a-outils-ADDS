<#
.SYNOPSIS
    Renomme un utilisateur (changement de nom d'usage) : nom affiché, nom d'objet, identifiant et UPN.

.DESCRIPTION
    Met à jour le nom, le prénom, le nom affiché et le nom de l'objet. Avec -UpdateLogon,
    l'identifiant (sAMAccountName) et l'UPN sont régénérés sur le modèle « j.dupont ».
    Le profil Windows, l'adresse de messagerie et les applications qui référencent l'ancien
    identifiant ne sont pas modifiés : à traiter séparément.

.EXAMPLE
    .\Rename-UserAccount.ps1 -Identity j.dupont -Surname Martin -UpdateLogon -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Identity,
    [string]$GivenName,
    [string]$Surname,
    [switch]$UpdateLogon
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox
if (-not $GivenName -and -not $Surname) { throw 'Indiquer -GivenName et/ou -Surname.' }

$user = Get-ADUser -Identity $Identity -ErrorAction Stop
$newGiven   = if ($GivenName) { $GivenName.Trim() } else { $user.GivenName }
$newSurname = if ($Surname)   { $Surname.Trim() }   else { $user.Surname }
$newName    = "$newGiven $newSurname"
$newSam     = $user.SamAccountName
$newUpn     = $user.UserPrincipalName

if ($UpdateLogon) {
    $newSam = ConvertTo-SamAccountName -GivenName $newGiven -Surname $newSurname
    if ($newSam -ne $user.SamAccountName -and (Get-ADUser -Filter "SamAccountName -eq '$(ConvertTo-FilterValue $newSam)'")) { throw "L'identifiant '$newSam' est déjà pris : choisir un autre identifiant manuellement." }
    $suffix = if ($user.UserPrincipalName -match '@(.+)$') { $Matches[1] } else { (Get-ADDomain).DNSRoot }
    $newUpn = "$newSam@$suffix"
}
$parent = ($user.DistinguishedName -split '(?<!\\),', 2)[1]
if ($newName -ne $user.Name -and (Get-ADObject -Filter "Name -eq '$(ConvertTo-FilterValue $newName)'" -SearchBase $parent -SearchScope OneLevel)) {
    throw "Un objet nommé '$newName' existe déjà dans $parent."
}

$status = 'Simulation'
if ($PSCmdlet.ShouldProcess($user.DistinguishedName, "Renommer en '$newName' (identifiant : $newSam)")) {
    Set-ADUser -Identity $user.ObjectGUID -GivenName $newGiven -Surname $newSurname -DisplayName $newName -SamAccountName $newSam -UserPrincipalName $newUpn -ErrorAction Stop
    if ($newName -ne $user.Name) { Rename-ADObject -Identity $user.ObjectGUID -NewName $newName -ErrorAction Stop }
    $status = 'Renommé'
}
[pscustomobject]@{ OldName = $user.Name; NewName = $newName; OldSamAccountName = $user.SamAccountName; NewSamAccountName = $newSam
                   NewUserPrincipalName = $newUpn; Status = $status }
