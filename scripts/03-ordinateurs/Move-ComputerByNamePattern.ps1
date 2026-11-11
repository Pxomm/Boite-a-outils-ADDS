<#
.SYNOPSIS
    Range les ordinateurs dans leur unité d'organisation d'après leur nom.

.DESCRIPTION
    Traite par défaut le conteneur « Computers », où arrivent les postes joints au domaine
    sans préparation et où aucune stratégie de groupe ne peut être liée.
    Le fichier de règles (séparateur « ; ») contient les colonnes Motif;OU ; le motif accepte
    les jokers (« PC-COMPTA-* »). La première règle qui correspond s'applique.
    Modèle : exemples/regles-ordinateurs.csv.

.EXAMPLE
    .\Move-ComputerByNamePattern.ps1 -RulesCsv .\regles-ordinateurs.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$RulesCsv,
    [string]$SearchBase,
    [string]$Delimiter = ';'
)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

if (-not (Test-Path -LiteralPath $RulesCsv)) { throw "Fichier introuvable : $RulesCsv" }
$rules = @(Import-Csv -LiteralPath $RulesCsv -Delimiter $Delimiter)
if ($rules.Count -eq 0 -or 'Motif' -notin $rules[0].PSObject.Properties.Name -or 'OU' -notin $rules[0].PSObject.Properties.Name) { throw "Le fichier de règles doit contenir les colonnes Motif;OU." }
foreach ($ou in $rules.OU | Select-Object -Unique) { $null = Get-ADOrganizationalUnit -Identity $ou -ErrorAction Stop }
if (-not $SearchBase) { $SearchBase = (Get-ADDomain).ComputersContainer }

foreach ($computer in Get-ADComputer -Filter * -SearchBase $SearchBase -SearchScope OneLevel) {
    $rule = $rules | Where-Object { $computer.Name -like $_.Motif } | Select-Object -First 1
    $status = if (-not $rule) { 'Aucune règle' } else { 'Simulation' }
    if ($rule -and $PSCmdlet.ShouldProcess($computer.Name, "Déplacer vers $($rule.OU)")) {
        try { Move-ADObject -Identity $computer.DistinguishedName -TargetPath $rule.OU -ErrorAction Stop; $status = 'Déplacé' }
        catch { $status = "Erreur : $($_.Exception.Message)" }
    }
    [pscustomobject]@{ Name = $computer.Name; Rule = "$($rule.Motif)"; TargetOU = "$($rule.OU)"; Status = $status }
}
