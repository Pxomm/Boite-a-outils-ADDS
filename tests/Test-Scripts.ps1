<#
.SYNOPSIS
    Tests automatiques de la boîte à outils. S'exécutent avec PowerShell 7 sous Windows comme
    sous Linux, sans Active Directory.

.DESCRIPTION
    1. Structure : syntaxe, encodage UTF-8 avec BOM, aide intégrée, catalogue à jour.
    2. Logique   : chaque script est exécuté contre un annuaire simulé (tests/FauxAD.ps1)
                   dont les commandes reprennent les paramètres des vraies commandes.
    Ces tests valident la logique des scripts et leur usage des commandes ; ils ne remplacent
    pas un essai sur un domaine de test.

.EXAMPLE
    pwsh -NoProfile -File tests/Test-Scripts.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$global:ConfirmPreference = 'None'
$Root    = Split-Path -Parent $PSScriptRoot
$Scripts = Join-Path $Root 'scripts'
$Work    = Join-Path ([IO.Path]::GetTempPath()) ('adds-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Work | Out-Null
. (Join-Path $PSScriptRoot 'FauxAD.ps1')

$script:Passed = 0; $script:Failed = 0
function Check {
    param([string]$Name, $Condition, [string]$Detail)
    if ($Condition) { $script:Passed++; Write-Host "  PASS $Name" }
    else { $script:Failed++; Write-Host "  FAIL $Name" -ForegroundColor Red; if ($Detail) { Write-Host "       $Detail" -ForegroundColor DarkGray } }
}
function Section([string]$Title) { Write-Host "`n== $Title ==" }
function Run {
    # Exécute un script du dépôt ; renvoie sorties, avertissements et erreur éventuelle
    param([string]$Script, [hashtable]$Params = @{}, [switch]$WhatIf, $Pipeline)
    $path = Join-Path $Scripts $Script
    $result = [pscustomobject]@{ Output = @(); Warnings = @(); Error = '' }
    $call = $Params.Clone(); if ($WhatIf) { $call.WhatIf = $true }
    try {
        $warnings = $null
        $result.Output = @(if ($PSBoundParameters.ContainsKey('Pipeline')) { $Pipeline | & $path @call -WarningVariable warnings -WarningAction SilentlyContinue 6>$null }
                           else { & $path @call -WarningVariable warnings -WarningAction SilentlyContinue 6>$null })
        $result.Warnings = @($warnings | ForEach-Object { "$_" })
    }
    catch { $result.Error = $_.Exception.Message }
    $result
}
function Days([int]$n) { (Get-Date).AddDays(-$n) }
function FileTime([int]$daysAgo) { (Get-Date).AddDays(-$daysAgo).ToFileTimeUtc() }

function Initialize-Directory {
    Reset-FakeAD
    $d = $global:FADomainDN
    foreach ($c in 'Users', 'Computers', 'Builtin') { $null = New-FakeObject container $c $d }
    $o = @{}
    foreach ($n in 'Utilisateurs', 'Postes', 'Serveurs', 'Groupes', 'Quarantaine', 'Desactives', 'Vide') { $o[$n] = (New-FakeObject organizationalUnit $n $d @{ ProtectedFromAccidentalDeletion = ($n -ne 'Vide'); gPLink = $null; gPOptions = 0 }).DistinguishedName }
    $o.Compta = (New-FakeObject organizationalUnit 'Compta' $o.Utilisateurs @{ ProtectedFromAccidentalDeletion = $true; gPLink = '[LDAP://cn={A},cn=policies;0][LDAP://cn={B},cn=policies;0]' }).DistinguishedName
    $u = { param($name, $sam, $path, $set = @{}) $base = @{ SamAccountName = $sam; UserPrincipalName = "$sam@corp.local"; GivenName = ($name -split ' ')[0]; Surname = ($name -split ' ')[1]
                LastLogonTimestamp = (FileTime 2); PasswordLastSet = (Days 20); pwdLastSet = (FileTime 20); PasswordNeverExpires = $false; LockedOut = $false
                'msDS-UserPasswordExpiryTimeComputed' = (Get-Date).AddDays(70).ToFileTime(); mail = "$sam@corp.local"; Title = 'Comptable'; Department = 'Compta'; Manager = $null }
            foreach ($k in $set.Keys) { $base[$k] = $set[$k] }; New-FakeObject user $name $path $base }
    $null = & $u 'Marie Martin'  'm.martin'   $o.Compta @{ Manager = "CN=Chef Service,$($o.Compta)" }
    $null = & $u 'Jean Dupont'   'j.dupont'   $o.Compta @{ 'msDS-UserPasswordExpiryTimeComputed' = (Get-Date).AddDays(3).AddHours(1).ToFileTime(); Manager = "CN=Chef Service,$($o.Compta)" }
    $null = & $u 'Chef Service'  'c.service'  $o.Compta @{ Manager = "CN=Chef Service,$($o.Compta)" }
    $null = & $u 'Albert Vieux'  'a.vieux'    $o.Utilisateurs @{ LastLogonTimestamp = (FileTime 200); mail = $null; Title = $null }
    $null = & $u 'Nina Jamais'   'n.jamais'   $o.Utilisateurs @{ LastLogonTimestamp = $null }
    $null = & $u 'Luc Bloque'    'l.bloque'   $o.Utilisateurs @{ LockedOut = $true }
    $null = & $u 'Denis Parti'   'd.parti'    $o.Desactives @{ Enabled = $false; LastLogonTimestamp = (FileTime 300) }
    $null = & $u 'Service SQL'   'svc.sql'    $o.Utilisateurs @{ ServicePrincipalName = @('MSSQLSvc/sql01.corp.local:1433'); PasswordNeverExpires = $true; PasswordLastSet = (Days 900); pwdLastSet = (FileTime 900); 'msDS-UserPasswordExpiryTimeComputed' = [long]::MaxValue }
    $null = & $u 'Sans Preauth'  's.preauth'  $o.Utilisateurs @{ DoesNotRequirePreAuth = $true; UacExtra = 2097152 }
    $null = & $u 'Admin Racine'  'adm.racine' $o.Utilisateurs @{ adminCount = 1; PasswordLastSet = (Days 400); pwdLastSet = (FileTime 400) }
    $null = & $u 'Ancien Admin'  'x.ancien'   $o.Utilisateurs @{ adminCount = 1 }
    $null = New-FakeObject user 'krbtgt' "CN=Users,$d" @{ PasswordLastSet = (Days 700); Enabled = $false; 'msDS-KeyVersionNumber' = 4 }
    $g = { param($name, $path, $set = @{}) $base = @{ GroupScope = 'Global'; GroupCategory = 'Security' }; foreach ($k in $set.Keys) { $base[$k] = $set[$k] }; New-FakeObject group $name $path $base }
    $da  = & $g 'Admins du domaine' "CN=Users,$d" @{ SID = [pscustomobject]@{ Value = "$global:FADomainSid-512" }; isCriticalSystemObject = $true }
    $adm = & $g 'Administrateurs' "CN=Builtin,$d" @{ SID = [pscustomobject]@{ Value = 'S-1-5-32-544' }; GroupScope = 'DomainLocal'; isCriticalSystemObject = $true }
    $null = & $g 'Protected Users' "CN=Users,$d" @{ SID = [pscustomobject]@{ Value = "$global:FADomainSid-525" }; isCriticalSystemObject = $true }
    $compta = & $g 'GG_Compta' $o.Groupes; $lecture = & $g 'GG_Lecture' $o.Groupes; $null = & $g 'GG_Vide' $o.Groupes; $null = & $g 'GG_Serveurs_SQL' $o.Groupes
    $l1 = & $g 'GG_Boucle1' $o.Groupes; $l2 = & $g 'GG_Boucle2' $o.Groupes; $null = & $g 'DL_Partage' $o.Groupes @{ GroupScope = 'DomainLocal' }
    $dn = { param($sam) ($global:FA.Objects | Where-Object SamAccountName -eq $sam).DistinguishedName }
    [void]$da.Members.Add((& $dn 'adm.racine')); [void]$adm.Members.Add($da.DistinguishedName)
    [void]$compta.Members.Add((& $dn 'm.martin')); [void]$compta.Members.Add((& $dn 'j.dupont')); [void]$lecture.Members.Add((& $dn 'm.martin')); [void]$lecture.Members.Add($compta.DistinguishedName)
    [void]$l1.Members.Add($l2.DistinguishedName); [void]$l2.Members.Add($l1.DistinguishedName)
    $c = { param($name, $path, $set = @{}) $base = @{ OperatingSystem = 'Windows 11 Professionnel'; OperatingSystemVersion = '10.0 (26100)'; LastLogonTimestamp = (FileTime 3); PasswordLastSet = (Days 10); PrimaryGroupID = 515; IPv4Address = '10.0.1.20'
                'msLAPS-PasswordExpirationTime' = (Get-Date).AddDays(20).ToFileTime() }; foreach ($k in $set.Keys) { $base[$k] = $set[$k] }; New-FakeObject computer $name $path $base }
    $null = & $c 'PC-001' $o.Postes
    $null = & $c 'PC-VIEUX' $o.Postes @{ OperatingSystem = 'Windows 7 Professionnel'; LastLogonTimestamp = (FileTime 200); 'msLAPS-PasswordExpirationTime' = $null; Description = 'Accueil' }
    $null = & $c 'SRV-VIEUX' $o.Serveurs @{ OperatingSystem = 'Windows Server 2012 R2 Standard'; LastLogonTimestamp = (FileTime 300); 'msLAPS-PasswordExpirationTime' = $null; TrustedForDelegation = $true }
    $null = & $c 'DC01' "OU=Serveurs,$d" @{ OperatingSystem = 'Windows Server 2022 Standard'; PrimaryGroupID = 516; TrustedForDelegation = $true; LastLogonTimestamp = (FileTime 400) }
    $null = & $c 'PC-COMPTA-07' "CN=Computers,$d"; $null = & $c 'PORTABLE-9' "CN=Computers,$d"
    return $o
}

# ============================================================================
Section '0. Structure du dépôt'
# ============================================================================
$files = @(Get-ChildItem -Path $Scripts, (Join-Path $Root 'lib'), $PSScriptRoot -Recurse -Filter *.ps1)
$scriptFiles = @($files | Where-Object { $_.FullName -like "$Scripts*" })
$syntax = foreach ($f in $files) { $e = $null; $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$e); $e | ForEach-Object { "$($f.Name):$($_.Extent.StartLineNumber) $($_.Message)" } }
Check 'syntaxe valide pour tous les fichiers PowerShell' (@($syntax).Count -eq 0) (@($syntax) -join ' | ')
$noBom = @($files | Where-Object { $b = [IO.File]::ReadAllBytes($_.FullName); -not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) } | ForEach-Object Name)
Check 'UTF-8 avec BOM sur tous les .ps1 (Windows PowerShell 5.1)' ($noBom.Count -eq 0) ($noBom -join ', ')
$noHelp = @($scriptFiles | Where-Object { $t = [IO.File]::ReadAllText($_.FullName); $t -notmatch '\.SYNOPSIS' -or $t -notmatch '\.DESCRIPTION|\.EXAMPLE' -or $t -notmatch '\.EXAMPLE' } | ForEach-Object Name)
Check 'aide intégrée (.SYNOPSIS et .EXAMPLE) dans chaque script' ($noHelp.Count -eq 0) ($noHelp -join ', ')
$writers = @($scriptFiles | Where-Object { $t = [IO.File]::ReadAllText($_.FullName)
    $t -match '(?m)^\s*[^#\r\n]*\b(New-AD\w+|Set-AD\w+|Remove-AD\w+|Move-AD\w+|Rename-AD\w+|Disable-ADAccount|Unlock-ADAccount|Add-ADGroupMember|Restore-ADObject|Enable-ADOptionalFeature|Restore-GPO|Clear-ADAccountExpiration) ' -and $t -notmatch 'SupportsShouldProcess' } | ForEach-Object Name)
Check 'tout script qui modifie l''annuaire propose -WhatIf' ($writers.Count -eq 0) ($writers -join ', ')
$readme = Join-Path $Root 'README.md'
if (Test-Path $readme) {
    $catalog = [IO.File]::ReadAllText($readme)
    $undocumented = @($scriptFiles | Where-Object { $catalog -notmatch [regex]::Escape($_.Name) } | ForEach-Object Name)
    Check 'chaque script figure dans le README' ($undocumented.Count -eq 0) ($undocumented -join ', ')
    $phantom = @([regex]::Matches($catalog, '`([\w-]+\.ps1)`') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique | Where-Object { -not (Get-ChildItem -Path $Root -Recurse -Filter $_) })
    Check 'le README ne cite aucun script absent' ($phantom.Count -eq 0) ($phantom -join ', ')
}
$examples = Join-Path $Root 'exemples'
$citedCsv = @($scriptFiles | ForEach-Object { [regex]::Matches([IO.File]::ReadAllText($_.FullName), 'exemples/([\w-]+\.csv)') | ForEach-Object { $_.Groups[1].Value } } | Sort-Object -Unique)
Check 'chaque fichier d''exemple cité par un script existe' (@($citedCsv | Where-Object { -not (Test-Path (Join-Path $examples $_)) }).Count -eq 0) ($citedCsv -join ', ')

# ============================================================================
Section '1. Fonctions communes'
# ============================================================================
. (Join-Path $Root 'lib/Communs.ps1')
$passwords = 1..300 | ForEach-Object { Get-RandomPassword -Length 16 }
Check 'mot de passe : longueur et quatre classes de caractères à chaque tirage' (@($passwords | Where-Object { $_.Length -ne 16 -or $_ -cnotmatch '[A-Z]' -or $_ -cnotmatch '[a-z]' -or $_ -notmatch '\d' -or $_ -notmatch '[^A-Za-z0-9]' }).Count -eq 0)
Check 'mot de passe : tirages tous différents, aucun caractère ambigu' (@($passwords | Sort-Object -Unique).Count -eq 300 -and @($passwords | Where-Object { $_ -cmatch '[0O1lI]' }).Count -eq 0)
Check 'identifiant : accents, tirets et espaces neutralisés' ((ConvertTo-SamAccountName 'Jean-Noël' 'Du Pont-Aîné') -eq 'j.dupontaine' -and (ConvertTo-SamAccountName 'Éloïse' 'Lefèvre') -eq 'e.lefevre')
Check 'identifiant : 20 caractères au plus' ((ConvertTo-SamAccountName 'Anne' 'De La Rochefoucauld-Montmorency').Length -eq 20)
Check 'filtre : apostrophe doublée' ((ConvertTo-FilterValue "O'Brien") -eq "O''Brien")
Check 'horodatage : 0, vide et « jamais » donnent $null' ($null -eq (ConvertFrom-FileTime 0) -and $null -eq (ConvertFrom-FileTime $null) -and $null -eq (ConvertFrom-FileTime ([long]::MaxValue)) -and (ConvertFrom-FileTime (FileTime 1)) -is [datetime])
$csv = Join-Path $Work 'sous/rapport.csv'
$back = @([pscustomobject]@{ A = 'é'; B = 1 }, [pscustomobject]@{ A = 'x;y'; B = 2 } | Export-Report -CsvPath $csv)
Check 'export : objets renvoyés et CSV « ; » écrit dans un dossier créé au besoin' ($back.Count -eq 2 -and @(Import-Csv $csv -Delimiter ';').Count -eq 2 -and (Import-Csv $csv -Delimiter ';')[1].A -eq 'x;y')

# ============================================================================
Section '2. Utilisateurs'
# ============================================================================
$o = Initialize-Directory
$r = Run '01-utilisateurs/New-UserAccount.ps1' @{ GivenName = 'Jeanne'; Surname = 'Dupont'; Path = $o.Compta; CopyGroupsFrom = 'm.martin'; Title = 'Comptable' } -WhatIf
Check 'création en simulation : rien de créé, pas de mot de passe renvoyé' ($r.Output[0].Status -eq 'Simulation' -and -not $r.Output[0].InitialPassword -and (Get-FakeCall New-ADUser).Count -eq 0) $r.Error
$r = Run '01-utilisateurs/New-UserAccount.ps1' @{ GivenName = 'Jeanne'; Surname = 'Dupont'; Path = $o.Compta; CopyGroupsFrom = 'm.martin'; Title = 'Comptable' }
$new = $global:FA.Objects | Where-Object SamAccountName -eq 'j.dupont2'
Check 'création : identifiant rendu unique (j.dupont existe -> j.dupont2), UPN, changement de mot de passe imposé' ($new -and $new.UserPrincipalName -eq 'j.dupont2@corp.local' -and $new.ChangePasswordAtLogon -and $new.Password -eq $r.Output[0].InitialPassword) $r.Error
Check 'création : groupes du modèle recopiés' (@($new.MemberOf).Count -eq 2 -and $r.Output[0].GroupCount -eq 2)
$r = Run '01-utilisateurs/New-UserAccount.ps1' @{ GivenName = 'Paul'; Surname = 'Durand'; Path = 'OU=Inexistante,DC=corp,DC=local' }
Check 'création : OU inexistante refusée avant toute écriture' ($r.Error -and -not ($global:FA.Objects | Where-Object SamAccountName -eq 'p.durand'))
$r = Run '01-utilisateurs/New-UserAccount.ps1' @{ GivenName = 'Paul'; Surname = 'Durand'; Path = $o.Compta; Group = 'GG_Inconnu' }
Check 'création : groupe inexistant refusé avant la création du compte' ($r.Error -and -not ($global:FA.Objects | Where-Object SamAccountName -eq 'p.durand'))

$o = Initialize-Directory
$csvUsers = Join-Path $Work 'utilisateurs.csv'
@('Prenom;Nom;OU;Login;Groupes;Fonction;Service;Modele', "Zoé;Lambert;$($o.Compta);;GG_Compta, GG_Lecture;Assistante;Compta;", "Rémi;Faure;OU=Absente,DC=corp,DC=local;;;;;", ";Sansprenom;$($o.Compta);;;;;", "Yann;Morel;$($o.Compta);y.morel;;;;m.martin") | Set-Content $csvUsers -Encoding utf8
$r = Run '01-utilisateurs/Import-UsersFromCsv.ps1' @{ CsvPath = $csvUsers } -WhatIf
Check 'import en simulation : aucune création' ((Get-FakeCall New-ADUser).Count -eq 0 -and @($r.Output | Where-Object Status -eq 'Simulation').Count -eq 2) $r.Error
$out = Join-Path $Work 'crees.csv'
$r = Run '01-utilisateurs/Import-UsersFromCsv.ps1' @{ CsvPath = $csvUsers; OutputCsvPath = $out }
Check 'import : 2 comptes créés, 2 lignes en erreur avec leur numéro, sans arrêt du traitement' (@($r.Output | Where-Object Status -eq 'Créé').Count -eq 2 -and (@($r.Output | Where-Object Status -eq 'Erreur').Line -join ',') -eq '3,4') ($r.Error + ($r.Output | Out-String))
Check 'import : mots de passe dans le fichier dédié et absents de la sortie' (@(Import-Csv $out -Delimiter ';').Count -eq 2 -and (Import-Csv $out -Delimiter ';')[0].InitialPassword.Length -eq 16 -and 'InitialPassword' -notin $r.Output[0].PSObject.Properties.Name)
Check 'import : groupes de la colonne et du modèle appliqués' (@(($global:FA.Objects | Where-Object SamAccountName -eq 'z.lambert').MemberOf).Count -eq 2 -and @(($global:FA.Objects | Where-Object SamAccountName -eq 'y.morel').MemberOf).Count -eq 2)
$r = Run '01-utilisateurs/Import-UsersFromCsv.ps1' @{ CsvPath = $csvUsers; Delimiter = ',' }
Check 'import : mauvais séparateur détecté' ($r.Error -match 'Colonne')

$o = Initialize-Directory
$log = Join-Path $Work 'departs'
$r = Run '01-utilisateurs/Disable-DepartedUser.ps1' @{ Identity = 'm.martin'; DisabledOU = $o.Desactives; LogDirectory = $log; Reference = 'Ticket 42' } -WhatIf
$m = $global:FA.Objects | Where-Object SamAccountName -eq 'm.martin'
Check 'départ en simulation : compte intact' ($m.Enabled -and @($m.MemberOf).Count -eq 2 -and $r.Output[0].Status -eq 'Simulation') $r.Error
$r = Run '01-utilisateurs/Disable-DepartedUser.ps1' @{ Identity = 'm.martin'; DisabledOU = $o.Desactives; LogDirectory = $log; Reference = 'Ticket 42' }
Check 'départ : désactivé, groupes retirés, déplacé, description horodatée, responsable effacé' (-not $m.Enabled -and @($m.MemberOf).Count -eq 0 -and $m.DistinguishedName -like "*,$($o.Desactives)" -and $m.Description -match 'Désactivé le \d{4}-\d{2}-\d{2} \(Ticket 42\)' -and -not $m.Manager) ($r.Error + ($r.Output | Out-String))
Check 'départ : liste des groupes sauvegardée, mot de passe remplacé' ((Test-Path $r.Output[0].GroupBackup) -and @(Import-Csv $r.Output[0].GroupBackup -Delimiter ';').Count -eq 2 -and $m.Password.Length -eq 32)
$r = Run '01-utilisateurs/Disable-DepartedUser.ps1' @{ LogDirectory = $log } -Pipeline @('adm.racine', 'inconnu', 'j.dupont')
Check 'départ : compte protégé refusé sans -Force, compte inconnu en erreur, suivant traité' ($r.Output[0].Status -eq 'Erreur' -and $r.Output[0].Detail -match 'adminCount' -and $r.Output[1].Status -eq 'Erreur' -and $r.Output[2].Status -eq 'Traité') ($r.Output | Out-String)

$o = Initialize-Directory
$r = Run '01-utilisateurs/Reset-UserPassword.ps1' @{ Identity = 'l.bloque' }
$l = $global:FA.Objects | Where-Object SamAccountName -eq 'l.bloque'
Check 'réinitialisation : nouveau mot de passe appliqué, compte déverrouillé, changement imposé' ($l.Password -eq $r.Output[0].NewPassword -and -not $l.LockedOut -and $l.ChangePasswordAtLogon -eq $true) $r.Error
$r = Run '01-utilisateurs/Reset-UserPassword.ps1' @{ Identity = 'svc.sql' }
Check 'réinitialisation : compte « n''expire jamais » -> avertissement, changement non imposé' ($r.Warnings.Count -eq 1 -and -not $r.Output[0].MustChangeAtLogon)
$r = Run '01-utilisateurs/Reset-UserPassword.ps1' @{ Identity = 'j.dupont' } -WhatIf
Check 'réinitialisation en simulation : aucun mot de passe renvoyé ni appliqué' (-not $r.Output[0].NewPassword -and -not ($global:FA.Objects | Where-Object SamAccountName -eq 'j.dupont').Password)

$o = Initialize-Directory
$r = Run '01-utilisateurs/Unlock-UserAccount.ps1'
Check 'verrouillages : liste sans modification' ($r.Output.Count -eq 1 -and $r.Output[0].SamAccountName -eq 'l.bloque' -and (Get-FakeCall Unlock-ADAccount).Count -eq 0) $r.Error
$r = Run '01-utilisateurs/Unlock-UserAccount.ps1' @{ Identity = 'l.bloque', 'j.dupont' }
Check 'verrouillages : déverrouille le compte verrouillé, signale celui qui ne l''est pas' ($r.Output[0].Status -eq 'Déverrouillé' -and $r.Output[1].Status -eq 'Non verrouillé') ($r.Output | Out-String)
$global:FA.Events = @((New-FakeEvent 4740 ([ordered]@{ TargetUserName = 'l.bloque'; TargetDomainName = 'PC-001' })), (New-FakeEvent 4740 ([ordered]@{ TargetUserName = 'autre'; TargetDomainName = 'PC-002' })), (New-FakeEvent 4740 ([ordered]@{ TargetUserName = 'l.bloque'; TargetDomainName = 'ANCIEN' }) (Days 10)))
$r = Run '01-utilisateurs/Find-LockoutSource.ps1' @{ Identity = 'l.bloque' }
Check 'origine du verrouillage : poste appelant lu sur l''émulateur PDC, période respectée' ($r.Output.Count -eq 1 -and $r.Output[0].CallerComputer -eq 'PC-001' -and $r.Output[0].DomainController -eq 'dc01.corp.local') $r.Error
$global:FA.Events = @()
$r = Run '01-utilisateurs/Find-LockoutSource.ps1'
Check 'origine du verrouillage : aucun événement -> résultat vide, pas d''erreur' (-not $r.Error -and $r.Output.Count -eq 0) $r.Error

$r = Run '01-utilisateurs/Get-InactiveUser.ps1' @{ Days = 90 }
Check 'inactifs : seuls les comptes actifs au-delà du seuil' (($r.Output.SamAccountName -join ',') -eq 'a.vieux' -and $r.Output[0].DaysInactive -ge 199) ($r.Error + ($r.Output.SamAccountName -join ','))
$r = Run '01-utilisateurs/Get-InactiveUser.ps1' @{ Days = 90; IncludeNeverLoggedOn = $true }
Check 'inactifs : -IncludeNeverLoggedOn ajoute les comptes jamais utilisés' ('n.jamais' -in $r.Output.SamAccountName -and $r.Output.Count -eq 2)
$r = Run '01-utilisateurs/Get-PasswordExpiration.ps1' @{ Days = 7 }
Check 'expiration : seul le mot de passe qui expire sous 7 jours, « n''expire jamais » ignoré' ($r.Output.Count -eq 1 -and $r.Output[0].SamAccountName -eq 'j.dupont' -and $r.Output[0].DaysLeft -eq 3) ($r.Error + ($r.Output | Out-String))
$r = Run '01-utilisateurs/Get-PasswordExpiration.ps1' @{ Days = 7; Notify = $true; SmtpServer = 'smtp'; From = 'it@corp.local' }
Check 'expiration : rappel envoyé à l''utilisateur concerné' ($global:FA.Mail.Count -eq 1 -and $global:FA.Mail[0].To -eq 'j.dupont@corp.local' -and $r.Output[0].Notified)
$r = Run '01-utilisateurs/Get-PasswordExpiration.ps1' @{ Notify = $true }
Check 'expiration : -Notify sans serveur refusé' ($r.Error -match 'SmtpServer')

$r = Run '01-utilisateurs/Set-UserExpiration.ps1' @{ Identity = 'j.dupont'; Date = (Get-Date).Date.AddDays(30) }
$j = $global:FA.Objects | Where-Object SamAccountName -eq 'j.dupont'
Check 'date de fin : compte utilisable jusqu''à la fin du jour indiqué' ($j.AccountExpirationDate -eq (Get-Date).Date.AddDays(31)) $r.Error
$r = Run '01-utilisateurs/Set-UserExpiration.ps1' @{ Identity = 'j.dupont'; Never = $true }
Check 'date de fin : -Never la supprime' ($null -eq $j.AccountExpirationDate -and $r.Output[0].Status -eq 'Modifié')
$r = Run '01-utilisateurs/Set-UserExpiration.ps1' @{ Identity = 'j.dupont'; Date = (Days 3) }
Check 'date de fin : date passée refusée' ($r.Error -match 'passée')

$o = Initialize-Directory
$r = Run '01-utilisateurs/Copy-UserGroupMembership.ps1' @{ Source = 'm.martin'; Target = 'a.vieux' }
Check 'copie de groupes : groupes manquants ajoutés' (@(($global:FA.Objects | Where-Object SamAccountName -eq 'a.vieux').MemberOf).Count -eq 2 -and @($r.Output | Where-Object Status -eq 'Fait').Count -eq 2) $r.Error
$r = Run '01-utilisateurs/Copy-UserGroupMembership.ps1' @{ Source = 'c.service'; Target = 'a.vieux'; Replace = $true }
Check 'copie de groupes : -Replace retire les groupes en trop' (@(($global:FA.Objects | Where-Object SamAccountName -eq 'a.vieux').MemberOf).Count -eq 0 -and @($r.Output | Where-Object Action -eq 'Retrait').Count -eq 2)
$r = Run '01-utilisateurs/Copy-UserGroupMembership.ps1' @{ Source = 'm.martin'; Target = 'm.martin' }
Check 'copie de groupes : source = cible refusée' ($r.Error -match 'même compte')

$r = Run '01-utilisateurs/Export-UserInventory.ps1' @{ CsvPath = (Join-Path $Work 'inv.csv'); EnabledOnly = $true }
Check 'inventaire : comptes actifs exportés, responsable et OU lisibles' ('d.parti' -notin $r.Output.SamAccountName -and ($r.Output | Where-Object SamAccountName -eq 'm.martin').Manager -eq 'Chef Service' -and ($r.Output | Where-Object SamAccountName -eq 'm.martin').OU -eq $o.Compta -and (Test-Path (Join-Path $Work 'inv.csv'))) $r.Error

$csvAttr = Join-Path $Work 'attributs.csv'
@('Login;Fonction;Service;Responsable;Mobile', 'm.martin;Cheffe comptable;Compta;c.service;', 'a.vieux;;Compta;;06 00 00 00 00', 'inconnu;X;;;') | Set-Content $csvAttr -Encoding utf8
$r = Run '01-utilisateurs/Update-UserAttributeFromCsv.ps1' @{ CsvPath = $csvAttr } -WhatIf
Check 'attributs en simulation : changements listés, rien d''écrit' ((Get-FakeCall Set-ADUser).Count -eq 0 -and $r.Output[0].Changes -match "Fonction : 'Comptable' -> 'Cheffe comptable'") ($r.Error + ($r.Output | Out-String))
$r = Run '01-utilisateurs/Update-UserAttributeFromCsv.ps1' @{ CsvPath = $csvAttr }
$m = $global:FA.Objects | Where-Object SamAccountName -eq 'm.martin'
Check 'attributs : seules les valeurs différentes sont écrites (Service et Responsable de m.martin inchangés)' ($m.Title -eq 'Cheffe comptable' -and ((Get-FakeCall Set-ADUser)[0].Data.Bound -join ',') -notmatch 'Department|Manager') ((Get-FakeCall Set-ADUser)[0].Data.Bound -join ',')
Check 'attributs : cellule vide = inchangé ; compte inconnu en erreur sans bloquer' (($global:FA.Objects | Where-Object SamAccountName -eq 'a.vieux').MobilePhone -eq '06 00 00 00 00' -and $r.Output[2].Status -eq 'Erreur' -and $r.Output[1].Status -eq 'Modifié')
$r = Run '01-utilisateurs/Update-UserAttributeFromCsv.ps1' @{ CsvPath = $csvAttr }
Check 'attributs : seconde exécution sans effet (idempotent)' (@($r.Output | Where-Object Status -eq 'Modifié').Count -eq 0)
@('Login;Fonction', 'm.martin;') | Set-Content $csvAttr -Encoding utf8
$r = Run '01-utilisateurs/Update-UserAttributeFromCsv.ps1' @{ CsvPath = $csvAttr; ClearEmpty = $true }
Check 'attributs : -ClearEmpty efface la valeur' (-not $m.Title -and $r.Output[0].Status -eq 'Modifié') $r.Error

$o = Initialize-Directory
$r = Run '01-utilisateurs/Rename-UserAccount.ps1' @{ Identity = 'j.dupont'; Surname = 'Leroy'; UpdateLogon = $true }
$j = $global:FA.Objects | Where-Object SamAccountName -eq 'j.leroy'
Check 'renommage : nom, objet, identifiant et UPN mis à jour, appartenance aux groupes conservée' ($j -and $j.Name -eq 'Jean Leroy' -and $j.UserPrincipalName -eq 'j.leroy@corp.local' -and $j.DistinguishedName -eq "CN=Jean Leroy,$($o.Compta)" -and @($j.MemberOf).Count -eq 1) $r.Error
$r = Run '01-utilisateurs/Rename-UserAccount.ps1' @{ Identity = 'a.vieux'; GivenName = 'Marie'; Surname = 'Martin'; UpdateLogon = $true }
Check 'renommage : identifiant déjà pris refusé' ($r.Error -match 'déjà pris')

$global:FA.LastLogonByServer = @{ 'dc01.corp.local' = (FileTime 5); 'dc02.corp.local' = (FileTime 1) }
$r = Run '01-utilisateurs/Get-UserLastLogon.ps1' @{ Identity = 'm.martin' }
Check 'dernière connexion : date la plus récente parmi les contrôleurs' ($r.Output[0].DomainController -eq 'dc02.corp.local' -and $r.Output[0].Status -eq 'OK') $r.Error
$global:FA.DownServers = @('dc02.corp.local')
$r = Run '01-utilisateurs/Get-UserLastLogon.ps1' @{ Identity = 'm.martin' }
Check 'dernière connexion : contrôleur injoignable signalé' ($r.Output[0].Status -match 'Partiel.*dc02' -and $r.Output[0].DomainController -eq 'dc01.corp.local')
$global:FA.DownServers = @()
$r = Run '01-utilisateurs/Get-UserLastLogon.ps1' @{ Identity = 'inconnu' }
Check 'dernière connexion : compte inexistant' ($r.Output[0].Status -eq 'Compte introuvable')
$r = Run '01-utilisateurs/Get-IncompleteUser.ps1'
Check 'comptes incomplets : attributs manquants listés, comptes désactivés ignorés' (($r.Output | Where-Object SamAccountName -eq 'a.vieux').Missing -eq 'mail, Title, Manager' -and 'd.parti' -notin $r.Output.SamAccountName -and 'm.martin' -notin $r.Output.SamAccountName) ($r.Error + ($r.Output | Out-String))

# ============================================================================
Section '3. Groupes'
# ============================================================================
$o = Initialize-Directory
$r = Run '02-groupes/Export-GroupMembership.ps1' @{ Name = 'GG_Lecture' }
Check 'membres : appartenance directe, groupe imbriqué visible' (($r.Output.Member | Sort-Object) -join ',' -eq 'GG_Compta,m.martin') ($r.Error + ($r.Output | Out-String))
$r = Run '02-groupes/Export-GroupMembership.ps1' @{ Name = 'GG_*'; Recursive = $true }
Check 'membres : -Recursive développe les imbrications sans doublon, groupe vide listé' (((($r.Output | Where-Object Group -eq 'GG_Lecture').Member | Sort-Object) -join ',') -eq 'j.dupont,m.martin' -and ($r.Output | Where-Object { $_.Group -eq 'GG_Vide' -and -not $_.Member }))
$r = Run '02-groupes/Get-EmptyGroup.ps1'
Check 'groupes vides : groupes système exclus' ('GG_Vide' -in $r.Output.Name -and 'Protected Users' -notin $r.Output.Name -and 'GG_Compta' -notin $r.Output.Name) $r.Error
$csvM = Join-Path $Work 'membres.csv'
@('Groupe;Membre;Action', 'GG_Vide;a.vieux;Ajout', 'GG_Compta;m.martin;Ajout', 'GG_Compta;j.dupont;Retrait', 'GG_Vide;inconnu;Ajout', 'GG_Vide;a.vieux;Supprimer', 'GG_Vide;PC-001$;') | Set-Content $csvM -Encoding utf8
$r = Run '02-groupes/Set-GroupMemberFromCsv.ps1' @{ CsvPath = $csvM } -WhatIf
Check 'membres par CSV en simulation : rien de modifié' ((Get-FakeCall Add-ADGroupMember).Count -eq 0 -and $r.Output[0].Status -eq 'Simulation') $r.Error
$r = Run '02-groupes/Set-GroupMemberFromCsv.ps1' @{ CsvPath = $csvM }
Check 'membres par CSV : ajout, déjà membre, retrait, membre inconnu, action inconnue, ordinateur' (($r.Output.Status -join '|') -eq 'Fait|Déjà membre|Fait|Erreur|Erreur|Fait') (($r.Output | ForEach-Object { "$($_.Status) $($_.Detail)" }) -join ' | ')
$r = Run '02-groupes/Set-GroupMemberFromCsv.ps1' @{ CsvPath = $csvM }
Check 'membres par CSV : seconde exécution idempotente' (($r.Output.Status -join '|') -eq 'Déjà membre|Déjà membre|Déjà absent|Erreur|Erreur|Déjà membre')
$csvG = Join-Path $Work 'groupes.csv'
@('Nom;OU;Etendue;Type;Description', "GG_Nouveau;$($o.Groupes);;;Test", "DL_Nouveau;$($o.Groupes);DomainLocal;Security;", "GG_Compta;$($o.Groupes);;;", "GG_Faux;$($o.Groupes);Mondial;;", "GG_Perdu;OU=Absente,DC=corp,DC=local;;;") | Set-Content $csvG -Encoding utf8
$r = Run '02-groupes/New-GroupFromCsv.ps1' @{ CsvPath = $csvG }
Check 'création de groupes : valeurs par défaut, existant signalé, étendue et OU invalides en erreur' (($r.Output.Status -join '|') -eq 'Créé|Créé|Existe déjà|Erreur|Erreur' -and ($global:FA.Objects | Where-Object Name -eq 'DL_Nouveau').GroupScope -eq 'DomainLocal') (($r.Output | ForEach-Object { "$($_.Status) $($_.Detail)" }) -join ' | ')
$o = Initialize-Directory
$r = Run '02-groupes/Get-NestedGroupLoop.ps1'
Check 'boucles : la boucle Boucle1 <-> Boucle2 trouvée une seule fois, aucune fausse alerte' ($r.Output.Count -eq 1 -and $r.Output[0].GroupCount -eq 2 -and $r.Output[0].Loop -match 'GG_Boucle') ($r.Error + ($r.Output | Out-String))
$r = Run '02-groupes/Compare-GroupMembership.ps1' @{ ReferenceUser = 'm.martin'; DifferenceUser = 'j.dupont' }
Check 'comparaison d''utilisateurs : commun et propre à la référence' (($r.Output | Where-Object Item -eq 'GG_Compta').Side -eq 'Les deux' -and ($r.Output | Where-Object Item -eq 'GG_Lecture').Side -eq 'Référence seulement') $r.Error
$r = Run '02-groupes/Compare-GroupMembership.ps1' @{ ReferenceGroup = 'GG_Compta'; DifferenceGroup = 'GG_Lecture'; Recursive = $true; DifferencesOnly = $true }
Check 'comparaison de groupes : membres finaux identiques -> aucune différence' ($r.Output.Count -eq 0 -and -not $r.Error) ($r.Output | Out-String)
$r = Run '02-groupes/Get-UserGroupMembership.ps1' @{ Identity = 'j.dupont' }
Check 'groupes d''un utilisateur : direct et hérité distingués' (($r.Output | Where-Object Group -eq 'GG_Compta').Direct -eq $true -and ($r.Output | Where-Object Group -eq 'GG_Lecture').Direct -eq $false) ($r.Error + ($r.Output | Out-String))

# ============================================================================
Section '4. Ordinateurs'
# ============================================================================
$o = Initialize-Directory
$r = Run '03-ordinateurs/Get-InactiveComputer.ps1' @{ Days = 90 }
Check 'ordinateurs inactifs : contrôleur de domaine exclu' ((($r.Output.Name | Sort-Object) -join ',') -eq 'PC-VIEUX,SRV-VIEUX') ($r.Error + ($r.Output.Name -join ','))
$r = Run '03-ordinateurs/Disable-InactiveComputer.ps1' @{ Days = 90; QuarantineOU = $o.Quarantaine } -WhatIf
Check 'quarantaine en simulation : rien de modifié' ((Get-FakeCall Disable-ADAccount).Count -eq 0) $r.Error
$r = Run '03-ordinateurs/Disable-InactiveComputer.ps1' @{ Days = 90; QuarantineOU = $o.Quarantaine }
$pc = $global:FA.Objects | Where-Object Name -eq 'PC-VIEUX'
Check 'quarantaine : poste désactivé, daté, déplacé ; serveur ignoré par défaut' (-not $pc.Enabled -and $pc.Description -match '^Quarantaine \d{4}-\d{2}-\d{2} \| Accueil$' -and $pc.DistinguishedName -like "*,$($o.Quarantaine)" -and ($r.Output | Where-Object Name -eq 'SRV-VIEUX').Status -eq 'Ignoré (serveur)') ($r.Error + ($r.Output | Out-String))
$r = Run '03-ordinateurs/Remove-QuarantinedComputer.ps1' @{ QuarantineOU = $o.Quarantaine; KeepDays = 30 }
Check 'suppression : délai de garde respecté' ($r.Output[0].Status -match 'délai de garde' -and ($global:FA.Objects | Where-Object Name -eq 'PC-VIEUX')) ($r.Error + ($r.Output | Out-String))
$pc.Description = "Quarantaine $((Days 45).ToString('yyyy-MM-dd')) | Accueil"
$null = New-FakeObject computer 'PC-REACTIVE' $o.Quarantaine @{ Description = "Quarantaine $((Days 60).ToString('yyyy-MM-dd'))" }
$null = New-FakeObject computer 'PC-SANSDATE' $o.Quarantaine @{ Enabled = $false; Description = 'rangé ici à la main' }
$r = Run '03-ordinateurs/Remove-QuarantinedComputer.ps1' @{ QuarantineOU = $o.Quarantaine; KeepDays = 30 } -WhatIf
Check 'suppression en simulation : rien de supprimé' ((Get-FakeCall Remove-ADObject).Count -eq 0)
$r = Run '03-ordinateurs/Remove-QuarantinedComputer.ps1' @{ QuarantineOU = $o.Quarantaine; KeepDays = 30 }
Check 'suppression : seul le poste désactivé et daté au-delà du délai ; réactivé et sans date conservés' (((Get-FakeCall Remove-ADObject).Data -join ',') -eq 'PC-VIEUX' -and ($r.Output | Where-Object Name -eq 'PC-REACTIVE').Status -match 'réactivé' -and ($r.Output | Where-Object Name -eq 'PC-SANSDATE').Status -match 'date') ($r.Output | Out-String)

$o = Initialize-Directory
$r = Run '03-ordinateurs/Get-ComputerInventory.ps1' @{ Summary = $true }
Check 'inventaire : décompte par système et fin de support' (($r.Output | Where-Object OperatingSystem -eq 'Windows 7 Professionnel').EndOfSupport -and -not ($r.Output | Where-Object OperatingSystem -eq 'Windows 11 Professionnel').EndOfSupport -and ($r.Output | Where-Object OperatingSystem -eq 'Windows 11 Professionnel').Count -eq 3) ($r.Error + ($r.Output | Out-String))
$r = Run '03-ordinateurs/Get-ComputerInventory.ps1' @{ ServersOnly = $true }
Check 'inventaire : -ServersOnly ; Windows Server 2012 R2 en fin de support, 2022 non' ($r.Output.Count -eq 2 -and ($r.Output | Where-Object Name -eq 'SRV-VIEUX').EndOfSupport -and -not ($r.Output | Where-Object Name -eq 'DC01').EndOfSupport)
$pcDn = ($global:FA.Objects | Where-Object Name -eq 'PC-001').DistinguishedName
$null = New-FakeObject 'msFVE-RecoveryInformation' '2026-03-14T09:21:07-01:00{3F2A9C1B-1111-2222-3333-444455556666}' $pcDn @{ 'msFVE-RecoveryPassword' = '111111-222222'; whenCreated = (Days 5) }
$null = New-FakeObject 'msFVE-RecoveryInformation' '2025-01-01T00:00:00-01:00{AAAA0000-1111-2222-3333-444455556666}' $pcDn @{ 'msFVE-RecoveryPassword' = '999999-888888'; whenCreated = (Days 300) }
$r = Run '03-ordinateurs/Get-BitLockerRecoveryKey.ps1' @{ ComputerName = 'PC-001' }
Check 'BitLocker : clés de l''ordinateur, la plus récente d''abord' ($r.Output.Count -eq 2 -and $r.Output[0].RecoveryPassword -eq '111111-222222' -and $r.Output[0].KeyId -like '3F2A9C1B*') ($r.Error + ($r.Output | Out-String))
$r = Run '03-ordinateurs/Get-BitLockerRecoveryKey.ps1' @{ KeyId = 'aaaa0000' }
Check 'BitLocker : recherche par identifiant de clé -> ordinateur retrouvé' ($r.Output.Count -eq 1 -and $r.Output[0].ComputerName -eq 'PC-001' -and $r.Output[0].RecoveryPassword -eq '999999-888888') ($r.Error + ($r.Output | Out-String))
$r = Run '03-ordinateurs/Get-BitLockerRecoveryKey.ps1' @{ ComputerName = 'PC-VIEUX' }
Check 'BitLocker : aucune clé -> avertissement' ($r.Output.Count -eq 0 -and $r.Warnings.Count -eq 1)
$rules = Join-Path $Work 'regles.csv'
@('Motif;OU', "PC-COMPTA-*;$($o.Postes)", "SRV-*;$($o.Serveurs)") | Set-Content $rules -Encoding utf8
$r = Run '03-ordinateurs/Move-ComputerByNamePattern.ps1' @{ RulesCsv = $rules }
Check 'rangement : poste du conteneur Computers déplacé selon son nom, autres laissés' (($global:FA.Objects | Where-Object Name -eq 'PC-COMPTA-07').DistinguishedName -eq "CN=PC-COMPTA-07,$($o.Postes)" -and ($r.Output | Where-Object Name -eq 'PORTABLE-9').Status -eq 'Aucune règle' -and (Get-FakeCall Move-ADObject).Count -eq 1) ($r.Error + ($r.Output | Out-String))
@('Motif;OU', 'PC-*;OU=Absente,DC=corp,DC=local') | Set-Content $rules -Encoding utf8
$r = Run '03-ordinateurs/Move-ComputerByNamePattern.ps1' @{ RulesCsv = $rules }
Check 'rangement : OU de destination inexistante refusée avant tout déplacement' ($r.Error -and (Get-FakeCall Move-ADObject).Count -eq 1)
$r = Run '03-ordinateurs/New-PrestagedComputer.ps1' @{ Name = 'pc-0201', 'PC-001'; Path = $o.Postes }
Check 'pré-création : compte créé en majuscules avec nom DNS, existant signalé' ($r.Output[0].Status -eq 'Créé' -and ($global:FA.Objects | Where-Object Name -eq 'PC-0201').DNSHostName -eq 'pc-0201.corp.local' -and $r.Output[1].Status -eq 'Existe déjà') ($r.Error + ($r.Output | Out-String))
$global:FA.Cim.Win32_ComputerSystem = [pscustomobject]@{ PartOfDomain = $true; Domain = 'corp.local' }
$global:FA.SecureChannel = $false
$r = Run '03-ordinateurs/Repair-ComputerTrust.ps1'
Check 'approbation : canal rompu constaté sans réparation' ($r.Output[0].Status -eq 'Canal sécurisé rompu' -and -not $global:FA.SecureChannel) $r.Error
$r = Run '03-ordinateurs/Repair-ComputerTrust.ps1' @{ Repair = $true }
Check 'approbation : -Repair sans -Credential refusé' ($r.Error -match 'Credential')
$cred = New-Object System.Management.Automation.PSCredential ('CORP\adm', (ConvertTo-SecureText 'x'))
$r = Run '03-ordinateurs/Repair-ComputerTrust.ps1' @{ Repair = $true; Credential = $cred }
Check 'approbation : réparation effectuée' ($r.Output[0].Status -eq 'Réparé' -and $global:FA.SecureChannel) $r.Error

# ============================================================================
Section '5. Unités d''organisation'
# ============================================================================
$o = Initialize-Directory
$csvOu = Join-Path $Work 'ou.csv'
@('Chemin;Description', 'Societe/Utilisateurs/Direction;Comité de direction', 'Societe/Utilisateurs/Compta;', 'Societe/Postes;', 'Utilisateurs/Compta;déjà là') | Set-Content $csvOu -Encoding utf8
$r = Run '04-unites-organisation/New-OUStructureFromCsv.ps1' @{ CsvPath = $csvOu } -WhatIf
Check 'arborescence en simulation : 5 OU annoncées, aucune créée, aucune erreur' ((Get-FakeCall New-ADOrganizationalUnit).Count -eq 0 -and @($r.Output | Where-Object Status -eq 'Simulation').Count -eq 5 -and @($r.Output | Where-Object Status -like 'Erreur*').Count -eq 0) ($r.Error + ($r.Output | Out-String))
$r = Run '04-unites-organisation/New-OUStructureFromCsv.ps1' @{ CsvPath = $csvOu }
$dir = $global:FA.Objects | Where-Object DistinguishedName -eq 'OU=Direction,OU=Utilisateurs,OU=Societe,DC=corp,DC=local'
Check 'arborescence : niveaux intermédiaires créés une fois, OU protégées, description sur la feuille' ((Get-FakeCall New-ADOrganizationalUnit).Count -eq 5 -and $dir.ProtectedFromAccidentalDeletion -and $dir.Description -eq 'Comité de direction' -and @($r.Output | Where-Object Status -eq 'Existe déjà').Count -eq 2) ($r.Error + ($r.Output | Out-String))
$r = Run '04-unites-organisation/New-OUStructureFromCsv.ps1' @{ CsvPath = $csvOu }
Check 'arborescence : seconde exécution sans création' ((Get-FakeCall New-ADOrganizationalUnit).Count -eq 5 -and @($r.Output | Where-Object Status -ne 'Existe déjà').Count -eq 0)
$r = Run '04-unites-organisation/Set-OUDeletionProtection.ps1'
Check 'protection : OU non protégée listée, sans correction' ($r.Output.Count -eq 1 -and $r.Output[0].Name -eq 'Vide' -and $r.Output[0].Status -eq 'Non protégée') ($r.Error + ($r.Output | Out-String))
$r = Run '04-unites-organisation/Set-OUDeletionProtection.ps1' @{ Fix = $true }
Check 'protection : -Fix protège l''OU' (($global:FA.Objects | Where-Object Name -eq 'Vide').ProtectedFromAccidentalDeletion -and $r.Output[0].Status -eq 'Protégée')
$r = Run '04-unites-organisation/Export-OUTree.ps1'
$compta = $r.Output | Where-Object DistinguishedName -eq $o.Compta
Check 'arbre : décompte direct par OU, GPO liées, profondeur' ($compta.Users -eq 3 -and $compta.LinkedGPO -eq 2 -and $compta.Depth -eq 2 -and ($r.Output | Where-Object Name -eq 'Postes' | Where-Object Depth -eq 1).Computers -eq 2) ($r.Error + ($compta | Out-String))
$r = Run '04-unites-organisation/Export-OUTree.ps1' @{ AsTree = $true }
Check 'arbre : rendu indenté, enfant sous son parent' ((($r.Output -join "`n") -match '(?m)^Utilisateurs  \[.*\n    Compta  \[utilisateurs : 3') -and -not $r.Error) ($r.Output -join "`n")
$global:FA.Acl[$o.Compta] = @((New-FakeAce 'CORP\GG_Support' "$global:FADomainSid-2001" 'ReadProperty, WriteProperty'), (New-FakeAce 'CORP\Admins du domaine' "$global:FADomainSid-512"), (New-FakeAce 'CORP\GG_Herite' "$global:FADomainSid-2002" 'GenericAll' '00000000-0000-0000-0000-000000000000' $true))
$r = Run '04-unites-organisation/Get-OUDelegation.ps1'
Check 'délégations : seule l''entrée explicite hors groupes d''administration' ($r.Output.Count -eq 1 -and $r.Output[0].Identity -eq 'CORP\GG_Support' -and $r.Output[0].OU -eq $o.Compta) ($r.Error + ($r.Output | Out-String))
$r = Run '04-unites-organisation/Get-EmptyOU.ps1'
Check 'OU vides : sans enfant seulement' ($o.Vide -in $r.Output.DistinguishedName -and $o.Utilisateurs -notin $r.Output.DistinguishedName -and $o.Compta -notin $r.Output.DistinguishedName) ($r.Error + ($r.Output.DistinguishedName -join ' | '))
$r = Run '04-unites-organisation/Set-DefaultContainer.ps1'
Check 'conteneurs par défaut : affichage seul, aucun outil lancé' ($r.Output.Count -eq 2 -and $global:FA.Tools.Count -eq 0 -and $r.Output[0].Current -eq 'CN=Computers,DC=corp,DC=local') $r.Error
$r = Run '04-unites-organisation/Set-DefaultContainer.ps1' @{ ComputersOU = $o.Postes }
Check 'conteneurs par défaut : redircmp lancé avec l''OU, redirusr non' (($global:FA.Tools -join '|') -eq "redircmp.exe $($o.Postes)" -and $r.Output[0].Status -eq 'Redirigé') ($global:FA.Tools -join '|')

# ============================================================================
Section '6. Stratégies de groupe'
# ============================================================================
$o = Initialize-Directory
$gpoXml = { param($links, $computerData, $vDir = 3, $vSys = 3) "<GPO><Computer><VersionDirectory>$vDir</VersionDirectory><VersionSysvol>$vSys</VersionSysvol><Enabled>true</Enabled>$computerData</Computer><User><VersionDirectory>0</VersionDirectory><VersionSysvol>0</VersionSysvol><Enabled>true</Enabled></User>$links</GPO>" }
$link = '<LinksTo><SOMName>Postes</SOMName><SOMPath>corp.local/Postes</SOMPath><Enabled>true</Enabled><NoOverride>false</NoOverride></LinksTo>'
$global:FA.Gpo = @(
    [pscustomobject]@{ DisplayName = 'Postes - Verrouillage de session'; Id = [guid]::NewGuid(); GpoStatus = 'AllSettingsEnabled'; ModificationTime = (Days 3); Xml = (& $gpoXml $link '<ExtensionData><Name>Délai de verrouillage : 600</Name></ExtensionData>') }
    [pscustomobject]@{ DisplayName = 'Ancienne / orpheline'; Id = [guid]::NewGuid(); GpoStatus = 'AllSettingsDisabled'; ModificationTime = (Days 900); Xml = (& $gpoXml '' '') }
    [pscustomobject]@{ DisplayName = 'Désynchronisée'; Id = [guid]::NewGuid(); GpoStatus = 'AllSettingsEnabled'; ModificationTime = (Days 1); Xml = (& $gpoXml ($link -replace '<Enabled>true', '<Enabled>false') '<ExtensionData><Name>Pare-feu</Name></ExtensionData>' 5 4); FailBackup = $true })
$bk = Join-Path $Work 'gpo'
$r = Run '05-strategies-de-groupe/Backup-AllGPO.ps1' @{ Path = $bk } -WhatIf
Check 'sauvegarde GPO en simulation : aucun dossier créé' (-not (Test-Path $bk) -and $r.Output.Count -eq 3) $r.Error
$r = Run '05-strategies-de-groupe/Backup-AllGPO.ps1' @{ Path = $bk; IncludeReport = $true }
$folder = @(Get-ChildItem $bk -Directory)[0]
Check 'sauvegarde GPO : inventaire, rapports (nom assaini), échec d''une GPO signalé sans bloquer les autres' ($folder -and (Test-Path (Join-Path $folder.FullName 'inventaire.csv')) -and (Test-Path (Join-Path $folder.FullName 'Ancienne _ orpheline.html')) -and @($r.Output | Where-Object Status -eq 'Sauvegardée').Count -eq 2 -and $r.Warnings.Count -eq 1) ($r.Error + ($r.Output | Out-String))
$old = New-Item -ItemType Directory -Path (Join-Path $bk '2020-01-01_020000'); $old.CreationTime = (Days 400); $keep = New-Item -ItemType Directory -Path (Join-Path $bk 'a-conserver'); $keep.CreationTime = (Days 400)
$r = Run '05-strategies-de-groupe/Backup-AllGPO.ps1' @{ Path = $bk; KeepDays = 90 }
Check 'sauvegarde GPO : rétention limitée aux dossiers de sauvegarde datés' (-not (Test-Path $old.FullName) -and (Test-Path $keep.FullName) -and (Test-Path $folder.FullName)) $r.Error
$r = Run '05-strategies-de-groupe/Restore-GPOFromBackup.ps1' @{ BackupPath = $folder.FullName }
Check 'restauration GPO : liste du contenu de la sauvegarde (GPO en échec absente)' ($r.Output.Count -eq 2 -and (Get-FakeCall Restore-GPO).Count -eq 0) $r.Error
$r = Run '05-strategies-de-groupe/Restore-GPOFromBackup.ps1' @{ BackupPath = $folder.FullName; Name = 'Postes - Verrouillage de session' }
Check 'restauration GPO : restaurée par son identifiant de sauvegarde' ($r.Output[0].Status -eq 'Restaurée' -and "$((Get-FakeCall Restore-GPO)[0].Data)" -eq $r.Output[0].BackupId) $r.Error
$r = Run '05-strategies-de-groupe/Restore-GPOFromBackup.ps1' @{ BackupPath = $folder.FullName; Name = 'Inconnue' }
Check 'restauration GPO : nom absent de la sauvegarde refusé' ($r.Error -match '0 fois')
$r = Run '05-strategies-de-groupe/Get-GPOHealthReport.ps1'
$h = @{}; $r.Output | ForEach-Object { $h[$_.DisplayName] = $_ }
Check 'santé GPO : non liée, vide et désactivée détectées' ($h['Ancienne / orpheline'].Unlinked -and $h['Ancienne / orpheline'].Empty -and $h['Ancienne / orpheline'].AllSettingsDisabled) ($r.Error + ($r.Output | Out-String))
Check 'santé GPO : liens tous désactivés et écart de version détectés ; GPO saine sans constat' ($h['Désynchronisée'].AllLinksDisabled -and $h['Désynchronisée'].VersionMismatch -and -not $h['Postes - Verrouillage de session'].Unlinked -and -not $h['Postes - Verrouillage de session'].Empty -and -not $h['Postes - Verrouillage de session'].VersionMismatch)
$r = Run '05-strategies-de-groupe/Get-GPOHealthReport.ps1' @{ ProblemsOnly = $true }
Check 'santé GPO : -ProblemsOnly écarte la GPO saine' ($r.Output.Count -eq 2)
$global:FA.GpoLinks[$global:FADomainDN] = @([pscustomobject]@{ DisplayName = 'Default Domain Policy'; Order = 1; Enabled = $true; Enforced = $false; GpoId = [guid]::NewGuid() })
$global:FA.GpoLinks[$o.Postes] = @([pscustomobject]@{ DisplayName = 'Postes - Verrouillage de session'; Order = 1; Enabled = $true; Enforced = $true; GpoId = [guid]::NewGuid() })
$r = Run '05-strategies-de-groupe/Get-GPOLink.ps1'
Check 'liens GPO : racine du domaine et OU parcourues' ($r.Output.Count -eq 2 -and ($r.Output | Where-Object Target -eq $o.Postes).Enforced -and ($r.Output | Where-Object Target -eq $global:FADomainDN)) ($r.Error + ($r.Output | Out-String))
$r = Run '05-strategies-de-groupe/Find-GPOSetting.ps1' @{ Pattern = 'verrouillage' }
Check 'recherche de paramètre : GPO trouvée avec extrait' ($r.Output.Count -eq 1 -and $r.Output[0].DisplayName -eq 'Postes - Verrouillage de session' -and $r.Output[0].Sample -match '600') ($r.Error + ($r.Output | Out-String))
$r = Run '05-strategies-de-groupe/Find-GPOSetting.ps1' @{ Pattern = 'a.b(' }
Check 'recherche de paramètre : texte avec caractères spéciaux pris littéralement' (-not $r.Error -and $r.Output.Count -eq 0) $r.Error

# ============================================================================
Section '7. Sécurité'
# ============================================================================
$o = Initialize-Directory
$r = Run '06-securite/Get-PrivilegedGroupMember.ps1'
Check 'privilèges : membre trouvé directement et par imbrication, groupes identifiés par SID' ((($r.Output | Where-Object SamAccountName -eq 'adm.racine').Group | Sort-Object) -join ',' -eq 'Administrateurs,Admins du domaine' -and @($r.Output | Where-Object SamAccountName -ne 'adm.racine').Count -eq 0) ($r.Error + ($r.Output | Out-String))
Check 'privilèges : âge du mot de passe, état du compte, absence de Protected Users' ($r.Output[0].PasswordAgeDays -ge 399 -and $r.Output[0].Enabled -eq $true -and $r.Output[0].InProtectedUsers -eq $false)
$r = Run '06-securite/Get-RiskyAccountSetting.ps1'
$f = { param($finding) @($r.Output | Where-Object Finding -eq $finding | ForEach-Object SamAccountName) -join ',' }
Check 'comptes à risque : Kerberoast, AS-REP, sans expiration, DES seulement' ((& $f 'Kerberoast') -eq 'svc.sql' -and (& $f 'ASREPRoast') -eq 's.preauth' -and (& $f 'PasswordNeverExpires') -eq 'svc.sql' -and (& $f 'DESOnly') -eq 's.preauth') ($r.Error + ($r.Output | Format-Table Finding, SamAccountName | Out-String))
Check 'comptes à risque : mot de passe ancien ; comptes à privilèges en tête ; krbtgt et désactivés exclus' ((& $f 'OldPassword') -eq 'adm.racine,svc.sql' -and $r.Output[0].Privileged -and 'krbtgt' -notin $r.Output.SamAccountName -and 'd.parti' -notin $r.Output.SamAccountName)
$r = Run '06-securite/Get-RiskyAccountSetting.ps1' @{ Check = 'Kerberoast' }
Check 'comptes à risque : -Check restreint les contrôles, SPN en détail' ($r.Output.Count -eq 1 -and $r.Output[0].Detail -match 'MSSQLSvc')
($global:FA.Objects | Where-Object SamAccountName -eq 'svc.sql') | Add-Member -NotePropertyName 'msDS-AllowedToDelegateTo' -NotePropertyValue @('cifs/srv01.corp.local') -Force
$r = Run '06-securite/Get-DelegationReport.ps1'
Check 'délégations Kerberos : non contrainte hors contrôleur de domaine, contrainte' (($r.Output | Where-Object DelegationType -eq 'Non contrainte').SamAccountName -eq 'SRV-VIEUX$' -and ($r.Output | Where-Object DelegationType -eq 'Contrainte').Target -eq 'cifs/srv01.corp.local' -and 'DC01$' -notin $r.Output.SamAccountName) ($r.Error + ($r.Output | Out-String))
$r = Run '06-securite/Get-AdminCountOrphan.ps1'
Check 'adminCount : seul l''ancien administrateur, pas le membre actuel' (($r.Output.SamAccountName -join ',') -eq 'x.ancien' -and $r.Output[0].Status -eq 'Reliquat') ($r.Error + ($r.Output | Out-String))
$r = Run '06-securite/Get-AdminCountOrphan.ps1' @{ Fix = $true } -WhatIf
Check 'adminCount en simulation : rien de modifié' ((Get-FakeCall Set-ADUser).Count -eq 0 -and (Get-FakeCall Set-Acl).Count -eq 0)
$r = Run '06-securite/Get-AdminCountOrphan.ps1' @{ Fix = $true }
Check 'adminCount : -Fix efface l''attribut et réactive l''héritage' ($null -eq ($global:FA.Objects | Where-Object SamAccountName -eq 'x.ancien').adminCount -and (Get-FakeCall Set-Acl)[0].Data.Protected -eq $false -and $r.Output[0].Status -eq 'Corrigé') ($r.Error + ($r.Output | Out-String))
$r = Run '06-securite/Get-KrbtgtStatus.ps1'
Check 'krbtgt : mot de passe ancien signalé' ($r.Output[0].PasswordAgeDays -ge 699 -and $r.Output[0].Status -match 'renouveler') $r.Error
$r = Run '06-securite/Get-KrbtgtStatus.ps1' @{ MaxAgeDays = 1000 }
Check 'krbtgt : seuil paramétrable' ($r.Output[0].Status -eq 'OK')
$r = Run '06-securite/Get-PasswordPolicyReport.ps1'
Check 'stratégie de mot de passe : faiblesses de la stratégie par défaut relevées' ($r.Output[0].Remarks -match 'inférieure à 12' -and $r.Output[0].Remarks -match 'aucun verrouillage' -and $r.Output[0].MaxPasswordAgeDays -eq 90) ($r.Error + ($r.Output | Out-String))
$r = Run '06-securite/New-AdminPasswordPolicy.ps1' @{ Name = 'PSO_Admins'; Group = 'GG_Compta' } -WhatIf
Check 'PSO en simulation : rien de créé' ($global:FA.Pso.Count -eq 0 -and $r.Output[0].Status -eq 'Simulation') $r.Error
$r = Run '06-securite/New-AdminPasswordPolicy.ps1' @{ Name = 'PSO_Admins'; Group = 'GG_Compta' }
Check 'PSO : créée avec les valeurs renforcées et appliquée au groupe' ($global:FA.Pso.Count -eq 1 -and $global:FA.Pso[0].MinPasswordLength -eq 16 -and $global:FA.Pso[0].MaxPasswordAge.TotalDays -eq 180 -and $global:FA.Pso[0].AppliesTo[0] -like 'CN=GG_Compta,*') $r.Error
$r = Run '06-securite/New-AdminPasswordPolicy.ps1' @{ Name = 'PSO_Admins'; Group = 'GG_Compta' }
Check 'PSO : nom déjà pris refusé' ($r.Error -match 'existe déjà')
$r = Run '06-securite/New-AdminPasswordPolicy.ps1' @{ Name = 'PSO_2'; Group = 'DL_Partage' }
Check 'PSO : groupe non global refusé' ($r.Error -match 'global')
$r = Run '06-securite/Get-PasswordPolicyReport.ps1'
Check 'stratégie de mot de passe : PSO listée avec sa cible, sans remarque' ($r.Output.Count -eq 2 -and $r.Output[1].AppliesTo -eq 'GG_Compta' -and -not $r.Output[1].Remarks) ($r.Output | Out-String)
$global:FA.Events = @(1..6 | ForEach-Object { New-FakeEvent 4771 ([ordered]@{ TargetUserName = 'j.dupont'; Status = '0x18'; IpAddress = '::ffff:10.0.1.50' }) (Get-Date).AddMinutes(-$_) 'dc01.corp.local' })
$global:FA.Events += @(1..2 | ForEach-Object { New-FakeEvent 4776 ([ordered]@{ TargetUserName = 'm.martin'; Workstation = 'PC-001'; Status = '0xC000006A' }) (Get-Date).AddMinutes(-$_) 'dc02.corp.local' })
$global:FA.Events += @(New-FakeEvent 4776 ([ordered]@{ TargetUserName = 'm.martin'; Workstation = 'PC-001'; Status = '0x0' }) (Get-Date).AddMinutes(-3) 'dc02.corp.local')
$global:FA.Events += @(1..9 | ForEach-Object { New-FakeEvent 4771 ([ordered]@{ TargetUserName = 'PC-001$'; Status = '0x18'; IpAddress = '10.0.1.20' }) (Get-Date).AddMinutes(-$_) 'dc01.corp.local' })
$r = Run '06-securite/Get-FailedLogon.ps1' @{ MinimumCount = 5 }
Check 'échecs d''authentification : regroupés par compte et source, seuil appliqué, comptes d''ordinateurs exclus' ($r.Output.Count -eq 1 -and $r.Output[0].Account -eq 'j.dupont' -and $r.Output[0].Count -eq 6 -and $r.Output[0].Source -eq '10.0.1.50') ($r.Error + ($r.Output | Out-String))
$r = Run '06-securite/Get-FailedLogon.ps1' @{ MinimumCount = 1 }
Check 'échecs d''authentification : NTLM en succès (0x0) non compté' (($r.Output | Where-Object Account -eq 'm.martin').Count -eq 2)
$global:FA.Events = @((New-FakeEvent 4728 ([ordered]@{ MemberName = 'CN=Jean Dupont,OU=Compta,DC=corp,DC=local'; MemberSid = 'S-1-5-21-1'; TargetUserName = 'Admins du domaine'; SubjectUserName = 'adm.racine' }) (Get-Date).AddHours(-2) 'dc01.corp.local'),
                      (New-FakeEvent 4725 ([ordered]@{ TargetUserName = 'a.vieux'; SubjectUserName = 'adm.racine' }) (Get-Date).AddHours(-1) 'dc02.corp.local'))
$r = Run '06-securite/Get-ADChangeAudit.ps1'
Check 'audit : événements des deux contrôleurs, du plus récent au plus ancien, action lisible' ($r.Output.Count -eq 2 -and $r.Output[0].Action -eq 'Compte utilisateur désactivé' -and $r.Output[1].Member -match 'Jean Dupont' -and $r.Output[1].By -eq 'adm.racine') ($r.Error + ($r.Output | Out-String))
$r = Run '06-securite/Get-ADChangeAudit.ps1' @{ Target = 'Admins*' }
Check 'audit : filtre sur la cible' ($r.Output.Count -eq 1 -and $r.Output[0].EventId -eq 4728)
$global:FA.Acl[$global:FADomainDN] = @(
    (New-FakeAce 'CORP\Contrôleurs de domaine' "$global:FADomainSid-516" 'ExtendedRight' '1131f6ad-9c07-11d1-f79f-00c04fc2dcd2'),
    (New-FakeAce 'CORP\svc.sql' "$global:FADomainSid-3001" 'ExtendedRight' '1131F6AD-9C07-11D1-F79F-00C04FC2DCD2'),
    (New-FakeAce 'CORP\GG_Lecture' "$global:FADomainSid-3002" 'ReadProperty' '00000000-0000-0000-0000-000000000000'),
    (New-FakeAce 'CORP\GG_Support' "$global:FADomainSid-3003" 'ExtendedRight' '00299570-246d-11d0-a768-00aa006e0529'))
$r = Run '06-securite/Get-DCSyncRight.ps1'
Check 'DCSync : détenteur inattendu repéré, contrôleurs de domaine attendus, autres droits ignorés' ($r.Output.Count -eq 2 -and ($r.Output | Where-Object { -not $_.Expected }).Identity -eq 'CORP\svc.sql' -and ($r.Output | Where-Object Expected).Identity -eq 'CORP\Contrôleurs de domaine') ($r.Error + ($r.Output | Out-String))
$r = Run '06-securite/Get-LapsCoverage.ps1' @{ MissingOnly = $true }
Check 'LAPS : postes sans mot de passe géré, contrôleur de domaine exclu' ((($r.Output.Name | Sort-Object) -join ',') -eq 'PC-VIEUX,SRV-VIEUX' -and $r.Output[0].State -eq 'Sans LAPS') ($r.Error + ($r.Output | Out-String))
$global:FA.SchemaAttributes = @()
$r = Run '06-securite/Get-LapsCoverage.ps1'
Check 'LAPS : schéma sans attribut LAPS -> avertissement, tous les postes « Sans LAPS »' ($r.Warnings.Count -eq 1 -and -not $r.Error) $r.Error
$r = Run '06-securite/New-GroupManagedServiceAccount.ps1' @{ Name = 'gmsa-sql01'; AllowedGroup = 'GG_Serveurs_SQL' }
Check 'gMSA : sans clé racine KDS, arrêt avec la marche à suivre' ($r.Error -match 'CreateKdsRootKey' -and (Get-FakeCall New-ADServiceAccount).Count -eq 0)
$r = Run '06-securite/New-GroupManagedServiceAccount.ps1' @{ Name = 'gmsa-sql01'; AllowedGroup = 'GG_Serveurs_SQL'; CreateKdsRootKey = $true }
Check 'gMSA : clé KDS créée, compte différé de 10 heures' ($r.Output[0].Status -match '10 heures' -and (Get-FakeCall New-ADServiceAccount).Count -eq 0 -and $r.Warnings.Count -eq 1) $r.Error
$r = Run '06-securite/New-GroupManagedServiceAccount.ps1' @{ Name = 'gmsa-sql01'; AllowedGroup = 'GG_Serveurs_SQL' }
Check 'gMSA : clé pas encore utilisable -> refus' ($r.Error -match 'pas encore utilisable')
$global:FA.KdsKeys = @([pscustomobject]@{ EffectiveTime = (Days 30) })
$r = Run '06-securite/New-GroupManagedServiceAccount.ps1' @{ Name = 'gmsa-sql01'; AllowedGroup = 'GG_Serveurs_SQL' }
Check 'gMSA : compte créé, récupérable par le groupe indiqué' ($r.Output[0].Status -eq 'Créé' -and ($global:FA.Objects | Where-Object Name -eq 'gmsa-sql01').Allowed -like 'CN=GG_Serveurs_SQL,*' -and $r.Output[0].DNSHostName -eq 'gmsa-sql01.corp.local') $r.Error

# ============================================================================
Section '8. Contrôleurs de domaine'
# ============================================================================
$o = Initialize-Directory
$r = Run '07-controleurs-de-domaine/Get-DomainOverview.ps1'
Check 'fiche du domaine : niveaux, rôles, corbeille, volumétrie' ($r.Output[0].Domain -eq 'corp.local' -and $r.Output[0].PDCEmulator -eq 'dc01.corp.local' -and $r.Output[0].RecycleBinEnabled -and $r.Output[0].TombstoneLifetimeDays -eq 180 -and $r.Output[0].Users -eq 12 -and $r.Output[0].EnabledUsers -eq 10 -and $r.Output[0].DomainControllers -eq 2) ($r.Error + ($r.Output | Format-List | Out-String))
$r = Run '07-controleurs-de-domaine/Get-DomainOverview.ps1' @{ DomainControllers = $true }
Check 'fiche du domaine : liste des contrôleurs' ($r.Output.Count -eq 2 -and $r.Output[0].Roles -eq 'PDCEmulator')
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $listener.Start(); $port = $listener.LocalEndpoint.Port
$global:FA.Cim.Win32_Service = @('NTDS', 'Netlogon', 'Kdc', 'DNS', 'DFSR', 'W32Time' | ForEach-Object { [pscustomobject]@{ Name = $_; State = 'Running' } })
$global:FA.Cim.Win32_OperatingSystem = [pscustomobject]@{ LastBootUpTime = (Days 12); SystemDrive = 'C:' }
$global:FA.Cim.Win32_LogicalDisk = [pscustomobject]@{ Size = 100GB; FreeSpace = 40GB }
$r = Run '07-controleurs-de-domaine/Get-DCHealth.ps1' @{ Server = '127.0.0.1'; LdapPort = $port }
Check 'santé des contrôleurs : tout est nominal' ($r.Output[0].Healthy -and $r.Output[0].Services -eq 'OK' -and $r.Output[0].SystemFreePercent -eq 40) ($r.Error + ($r.Output | Format-List | Out-String))
($global:FA.Cim.Win32_Service | Where-Object Name -eq 'Netlogon').State = 'Stopped'; $global:FA.Cim.Win32_LogicalDisk.FreeSpace = 5GB; $global:FA.MissingShares = @('\\127.0.0.1\SYSVOL')
$r = Run '07-controleurs-de-domaine/Get-DCHealth.ps1' @{ Server = '127.0.0.1'; LdapPort = $port }
Check 'santé des contrôleurs : service arrêté, disque plein et SYSVOL absent signalés' (-not $r.Output[0].Healthy -and $r.Output[0].Issues -match 'Netlogon' -and $r.Output[0].Issues -match '5 % libre' -and $r.Output[0].Issues -match 'SYSVOL') $r.Output[0].Issues
$listener.Stop()
$r = Run '07-controleurs-de-domaine/Get-DCHealth.ps1' @{ Server = '127.0.0.1'; LdapPort = $port }
Check 'santé des contrôleurs : port LDAP fermé signalé' (-not $r.Output[0].Healthy -and $r.Output[0].Issues -match "port LDAP $port fermé") $r.Output[0].Issues
$meta = { param($server, $partner, $result, $failures, $hoursAgo) [pscustomobject]@{ Server = $server; Partner = "CN=NTDS Settings,CN=$partner,CN=Servers,CN=Lyon,CN=Sites,CN=Configuration,DC=corp,DC=local"; Partition = 'DC=corp,DC=local'
        LastReplicationSuccess = (Get-Date).AddHours(-$hoursAgo); LastReplicationAttempt = (Get-Date).AddMinutes(-5); LastReplicationResult = $result; ConsecutiveReplicationFailures = $failures } }
$global:FA.Replication = @((& $meta 'dc01.corp.local' 'DC02' 0 0 1), (& $meta 'dc02.corp.local' 'DC01' 1722 14, 60))
$r = Run '07-controleurs-de-domaine/Get-ReplicationStatus.ps1'
Check 'réplication : lien sain et lien en échec distingués, partenaire lisible, défauts en tête' ($r.Output.Count -eq 2 -and -not $r.Output[0].Healthy -and $r.Output[0].Partner -eq 'DC01' -and $r.Output[0].LastResult -eq 1722 -and $r.Output[1].Healthy) ($r.Error + ($r.Output | Out-String))
$global:FA.DownServers = @('dc02.corp.local')
$r = Run '07-controleurs-de-domaine/Get-ReplicationStatus.ps1' @{ ProblemsOnly = $true }
Check 'réplication : contrôleur injoignable compté comme défaut' ($r.Output.Count -eq 1 -and $r.Output[0].Server -eq 'dc02.corp.local' -and $r.Warnings.Count -eq 1)
$r = Run '07-controleurs-de-domaine/Get-FSMORole.ps1'
Check 'rôles FSMO : cinq rôles, détenteur injoignable signalé' ($r.Output.Count -eq 5 -and @($r.Output | Where-Object Reachable).Count -eq 5) ($r.Error + ($r.Output | Out-String))
$global:FA.DownServers = @()
$r = Run '07-controleurs-de-domaine/Move-FSMORole.ps1' @{ Target = 'DC02'; Role = 'PDCEmulator', 'RIDMaster' } -WhatIf
Check 'transfert FSMO en simulation : rien de transféré' ($global:FA.Fsmo.PDCEmulator -eq 'dc01.corp.local' -and $r.Output[0].Status -eq 'Simulation') $r.Error
$r = Run '07-controleurs-de-domaine/Move-FSMORole.ps1' @{ Target = 'DC02'; Role = 'PDCEmulator', 'RIDMaster' }
Check 'transfert FSMO : rôles demandés transférés, sans prise de force' ($global:FA.Fsmo.PDCEmulator -eq 'dc02.corp.local' -and $global:FA.Fsmo.SchemaMaster -eq 'dc01.corp.local' -and -not (Get-FakeCall Move-FSMO)[0].Data.Force -and $r.Output[0].PreviousHolder -eq 'dc01.corp.local') ($r.Error + ($r.Output | Out-String))
$r = Run '07-controleurs-de-domaine/Move-FSMORole.ps1' @{ Target = 'DC02'; Role = 'All'; Seize = $true }
Check 'transfert FSMO : « All » couvre les cinq rôles, déjà détenus non rejoués, -Seize transmis' (@($r.Output | Where-Object Status -eq 'Déjà détenu').Count -eq 2 -and @($r.Output | Where-Object Status -eq 'Pris de force').Count -eq 3 -and (Get-FakeCall Move-FSMO)[-1].Data.Force) ($r.Output | Out-String)
$r = Run '07-controleurs-de-domaine/Move-FSMORole.ps1' @{ Target = 'DC99'; Role = 'All' }
Check 'transfert FSMO : cible inconnue refusée' ([bool]$r.Error)
$global:FA.Sites = @([pscustomobject]@{ Name = 'Lyon'; DistinguishedName = 'CN=Lyon,CN=Sites,CN=Configuration,DC=corp,DC=local' }, [pscustomobject]@{ Name = 'Paris'; DistinguishedName = 'CN=Paris,CN=Sites,CN=Configuration,DC=corp,DC=local' }, [pscustomobject]@{ Name = 'Nantes'; DistinguishedName = 'CN=Nantes,CN=Sites,CN=Configuration,DC=corp,DC=local' })
$global:FA.Subnets = @([pscustomobject]@{ Name = '10.0.0.0/16'; Site = 'CN=Lyon,CN=Sites,CN=Configuration,DC=corp,DC=local' }, [pscustomobject]@{ Name = '10.9.0.0/16'; Site = $null })
$r = Run '07-controleurs-de-domaine/Get-SiteSubnetReport.ps1'
$s = @{}; $r.Output | ForEach-Object { $s[$_.Site] = $_ }
Check 'sites : site sain, site sans sous-réseau, site sans contrôleur, sous-réseau orphelin' (-not $s['Lyon'].Issues -and $s['Paris'].Issues -eq 'aucun sous-réseau' -and $s['Nantes'].Issues -match 'aucun contrôleur' -and $s['(aucun)'].Subnets -eq '10.9.0.0/16') ($r.Error + ($r.Output | Out-String))
$srv = { param($names) $names | ForEach-Object { [pscustomobject]@{ Type = 'SRV'; NameTarget = $_ } } }
$global:FA.Dns = @{ '_ldap._tcp.dc._msdcs.corp.local' = (& $srv @('dc01.corp.local', 'dc02.corp.local')); '_kerberos._tcp.dc._msdcs.corp.local' = (& $srv @('dc01.corp.local', 'vieuxdc.corp.local'))
                    '_ldap._tcp.pdc._msdcs.corp.local' = (& $srv @('dc02.corp.local')); 'dc01.corp.local' = [pscustomobject]@{ Type = 'A'; IPAddress = '10.0.0.10' }; 'dc02.corp.local' = [pscustomobject]@{ Type = 'A'; IPAddress = '10.1.0.99' } }
$r = Run '07-controleurs-de-domaine/Test-DCDnsRecord.ps1'
$dns = @{}; $r.Output | ForEach-Object { $dns[$_.Name] = $_ }
Check 'DNS : enregistrement complet valide ; contrôleur absent et contrôleur fantôme détectés' ($dns['_ldap._tcp.dc._msdcs.corp.local'].Ok -and $dns['_kerberos._tcp.dc._msdcs.corp.local'].Detail -match 'absent\(s\) : dc02' -and $dns['_kerberos._tcp.dc._msdcs.corp.local'].Detail -match 'inconnu\(s\) : vieuxdc') ($r.Error + ($r.Output | Out-String))
Check 'DNS : enregistrement manquant et mauvaise adresse d''hôte signalés' (-not $dns['_ldap._tcp.gc._msdcs.corp.local'].Ok -and $dns['dc01.corp.local'].Ok -and $dns['dc02.corp.local'].Detail -match 'attendu 10.1.0.10')
$diag = Join-Path $Work 'diag'
$global:FA.ToolOutput['repadmin.exe'] = @('showrepl_COLUMNS,Destination DSA Site,Destination DSA,Naming Context,Source DSA Site,Source DSA,Transport Type,Number of Failures,Last Failure Time,Last Success Time,Last Failure Status', 'showrepl_INFO,Lyon,DC01,"DC=corp,DC=local",Paris,DC02,RPC,0,0,2026-11-11 10:00:00,0', 'showrepl_INFO,Paris,DC02,"DC=corp,DC=local",Lyon,DC01,RPC,3,2026-11-11 09:00:00,2026-11-10 10:00:00,1722')
$global:FA.ToolOutput['dcdiag.exe'] = @('')
$r = Run '07-controleurs-de-domaine/Invoke-DCDiagnostic.ps1' @{ OutputDirectory = $diag }
Check 'diagnostic : dcdiag /s /q par contrôleur, sortie vide = réussite, résultats archivés' (@($r.Output | Where-Object { $_.Test -eq 'dcdiag' -and $_.Passed }).Count -eq 2 -and ($global:FA.Tools -contains 'dcdiag.exe /s:dc01.corp.local /q') -and (Test-Path $r.Output[0].File)) ($r.Error + ($global:FA.Tools -join ' | '))
Check 'diagnostic : échecs de réplication comptés depuis la sortie CSV de repadmin' (($r.Output | Where-Object Test -eq 'repadmin').ErrorLines -eq 1 -and -not ($r.Output | Where-Object Test -eq 'repadmin').Passed)
$global:FA.ToolOutput['dcdiag.exe'] = @('   ......................... DC01 failed test Replications')
$r = Run '07-controleurs-de-domaine/Invoke-DCDiagnostic.ps1' @{ OutputDirectory = $diag; Server = 'dc01.corp.local'; IncludeDns = $true }
Check 'diagnostic : erreur dcdiag détectée, test DNS ajouté sur demande' (-not $r.Output[0].Passed -and $r.Output[0].ErrorLines -eq 1 -and ($global:FA.Tools -contains 'dcdiag.exe /s:dc01.corp.local /q /test:dns')) ($global:FA.Tools -join ' | ')
$global:FA.ToolOutput['w32tm.exe'] = @('Tracking dc01.corp.local [10.0.0.10:123].', '10:00:00, +00.0123456s')
$r = Run '07-controleurs-de-domaine/Get-TimeSyncStatus.ps1'
Check 'temps : écart mesuré pour chaque contrôleur' ($r.Output.Count -eq 2 -and $r.Output[0].OffsetSeconds -eq 0.0123456) ($r.Error + ($r.Output | Out-String))
$global:FA.ToolOutput['w32tm.exe'] = @('Local CMOS Clock', '10:00:00, -07,5000000s')
$r = Run '07-controleurs-de-domaine/Get-TimeSyncStatus.ps1'
Check 'temps : écart excessif (virgule décimale acceptée) et source interne de l''émulateur PDC signalés' (@($r.Output | Where-Object Ok).Count -eq 0 -and $r.Output[0].OffsetSeconds -eq -7.5 -and $r.Output[0].Detail -match 'écart') ($r.Output | Out-String)
$global:FA.Cim.Win32_LogicalDisk = [pscustomobject]@{ Size = 200GB; FreeSpace = 120GB }
$env:SystemDrive = 'C:'; $env:COMPUTERNAME = 'DC01'
$r = Run '07-controleurs-de-domaine/Backup-SystemState.ps1' @{ Target = 'E:' }
Check 'sauvegarde : fonctionnalité Sauvegarde Windows Server absente -> refus' ($r.Error -match 'Windows-Server-Backup')
$global:FA.Features['Windows-Server-Backup'] = $true
$r = Run '07-controleurs-de-domaine/Backup-SystemState.ps1' @{ Target = 'C:' }
Check 'sauvegarde : volume système refusé comme cible' ($r.Error -match 'volume système')
$r = Run '07-controleurs-de-domaine/Backup-SystemState.ps1' @{ Target = 'E:'; MinFreeGB = 500 }
Check 'sauvegarde : espace libre insuffisant refusé' ($r.Error -match 'insuffisant')
$r = Run '07-controleurs-de-domaine/Backup-SystemState.ps1' @{ Target = 'E:' } -WhatIf
Check 'sauvegarde en simulation : wbadmin non lancé' (@($global:FA.Tools | Where-Object { $_ -like 'wbadmin*' }).Count -eq 0 -and $r.Output[0].Status -eq 'Simulation') $r.Error
$r = Run '07-controleurs-de-domaine/Backup-SystemState.ps1' @{ Target = 'E:' }
Check 'sauvegarde : wbadmin lancé avec la cible' (($global:FA.Tools | Where-Object { $_ -like 'wbadmin*' }) -eq 'wbadmin.exe start systemstatebackup -backupTarget:E: -quiet' -and $r.Output[0].Status -eq 'Réussie') ($r.Error + ($global:FA.Tools -join ' | '))

# ============================================================================
Section '9. Maintenance'
# ============================================================================
$o = Initialize-Directory
$global:FA.RecycleBin = $false
$r = Run '08-maintenance/Enable-RecycleBin.ps1'
Check 'corbeille : état affiché sans activation' ($r.Output[0].RecycleBin -eq 'Désactivée' -and -not $global:FA.RecycleBin) $r.Error
$r = Run '08-maintenance/Enable-RecycleBin.ps1' @{ Enable = $true } -WhatIf
Check 'corbeille en simulation : non activée' (-not $global:FA.RecycleBin -and $r.Output[0].RecycleBin -eq 'Simulation')
$r = Run '08-maintenance/Enable-RecycleBin.ps1' @{ Enable = $true }
Check 'corbeille : activée sur la forêt' ($global:FA.RecycleBin -and (Get-FakeCall Enable-ADOptionalFeature)[0].Data -eq 'corp.local' -and $r.Output[0].RecycleBin -eq 'Activée') $r.Error
$r = Run '08-maintenance/Enable-RecycleBin.ps1' @{ Enable = $true }
Check 'corbeille : déjà activée -> aucune nouvelle action' ($r.Output[0].RecycleBin -eq 'Déjà activée' -and (Get-FakeCall Enable-ADOptionalFeature).Count -eq 1)
$del = { param($name, $class, $days, $parent = $o.Compta) New-FakeObject $class "$name\0ADEL:$([guid]::NewGuid())" "CN=Deleted Objects,$global:FADomainDN" @{ isDeleted = $true; 'msDS-LastKnownRDN' = $name; lastKnownParent = $parent; whenChanged = (Days $days) } }
$d1 = & $del 'Jeanne Dupont' 'user' 2; $null = & $del 'PC-PERDU' 'computer' 40; $null = & $del 'Paul Homonyme' 'user' 5; $null = & $del 'Paul Homonyme' 'user' 6
$d5 = & $del 'Orphelin Parent' 'user' 3 'OU=Ancienne\0ADEL:1234,CN=Deleted Objects,DC=corp,DC=local'
$r = Run '08-maintenance/Get-DeletedObject.ps1' @{ ObjectClass = 'user'; Days = 30 }
Check 'objets supprimés : filtre par type et ancienneté, du plus récent au plus ancien' ($r.Output.Count -eq 4 -and $r.Output[0].Name -eq 'Jeanne Dupont' -and $r.Output[0].LastKnownParent -eq $o.Compta) ($r.Error + ($r.Output | Out-String))
$r = Run '08-maintenance/Get-DeletedObject.ps1' @{ Name = 'PC-*' }
Check 'objets supprimés : filtre par nom d''origine' ($r.Output.Count -eq 1 -and $r.Output[0].ObjectClass -eq 'computer')
$r = Run '08-maintenance/Restore-DeletedObject.ps1' @{ Name = 'Jeanne Dupont' } -WhatIf
Check 'restauration en simulation : objet toujours supprimé' ($d1.isDeleted -and $r.Output[0].Status -eq 'Simulation') $r.Error
$r = Run '08-maintenance/Restore-DeletedObject.ps1' @{ Name = 'Jeanne Dupont' }
Check 'restauration : objet restauré à son emplacement d''origine' (-not $d1.isDeleted -and $r.Output[0].RestoredTo -eq $o.Compta -and -not (Get-FakeCall Restore-ADObject)[0].Data.TargetPath) $r.Error
$r = Run '08-maintenance/Restore-DeletedObject.ps1' @{ Name = 'Paul Homonyme' }
Check 'restauration : homonymes -> arrêt, identifiant demandé' ($r.Error -match '2 objets')
$r = Run '08-maintenance/Restore-DeletedObject.ps1' @{ Name = 'Orphelin Parent' }
Check 'restauration : OU d''origine supprimée -> arrêt explicite' ($r.Error -match 'lui-même été supprimé' -and $d5.isDeleted)
$r = Run '08-maintenance/Restore-DeletedObject.ps1' @{ ObjectGuid = $d5.ObjectGUID; TargetPath = $o.Utilisateurs }
Check 'restauration : par identifiant, vers un autre emplacement' (-not $d5.isDeleted -and (Get-FakeCall Restore-ADObject)[-1].Data.TargetPath -eq $o.Utilisateurs) $r.Error
$r = Run '08-maintenance/Restore-DeletedObject.ps1' @{ Name = 'Jamais Existé' }
Check 'restauration : objet introuvable' ($r.Error -match 'Aucun objet')

$o = Initialize-Directory
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $listener.Start(); $listener.Stop()   # port fermé : les contrôleurs simulés ne répondent pas en LDAP
$report = Join-Path $Work 'rapports'
$r = Run '08-maintenance/New-DailyReport.ps1' @{ Path = $report; SmtpServer = 'smtp'; From = 'ad@corp.local'; To = 'infra@corp.local' }
$html = if ($r.Output[0].File -and (Test-Path $r.Output[0].File)) { [IO.File]::ReadAllText($r.Output[0].File) } else { '' }
Check 'rapport quotidien : fichier HTML produit avec toutes les sections' ($html -match 'Comptes verrouill' -and $html -match 'l\.bloque' -and $html -match 'a\.vieux' -and $html -match 'adm\.racine' -and $html -match 'PC-VIEUX' -and $r.Output[0].Sections.Count -eq 8) $r.Error
Check 'rapport quotidien : points d''attention comptés (contrôleurs injoignables, krbtgt), courriel envoyé' ($r.Output[0].Alerts -ge 3 -and $global:FA.Mail.Count -eq 1 -and $global:FA.Mail[0].Subject -match "point\(s\) d'attention") "alertes : $($r.Output[0].Alerts)"
($global:FA.Objects | Where-Object SamAccountName -eq 'a.vieux').Name = '<script>alert(1)</script>'
$r = Run '08-maintenance/New-DailyReport.ps1' @{ Path = $report }
Check 'rapport quotidien : valeurs de l''annuaire encodées en HTML' ([IO.File]::ReadAllText($r.Output[0].File) -notmatch '<script>alert' -and [IO.File]::ReadAllText($r.Output[0].File) -match '&lt;script&gt;')
$r = Run '08-maintenance/New-DailyReport.ps1' @{ Path = $report; SmtpServer = 'smtp' }
Check 'rapport quotidien : envoi sans expéditeur ni destinataire refusé' ($r.Error -match 'From')
$rec = { param($name, $type, $days, $data) [pscustomobject]@{ HostName = $name; RecordType = $type; Timestamp = $(if ($null -ne $days) { Days $days }); RecordData = [pscustomobject]$data } }
$global:FA.DnsRecords = @((& $rec 'pc-disparu' 'A' 120 @{ IPv4Address = '10.0.1.77' }), (& $rec 'pc-001' 'A' 2 @{ IPv4Address = '10.0.1.20' }), (& $rec 'srv-statique' 'A' $null @{ IPv4Address = '10.0.0.5' }), (& $rec '@' 'NS' 300 @{}))
$r = Run '08-maintenance/Get-StaleDnsRecord.ps1' @{ Days = 30 }
Check 'DNS obsolète : enregistrement dynamique ancien seulement ; statiques ignorés ; vieillissement inactif signalé' ($r.Output.Count -eq 1 -and $r.Output[0].HostName -eq 'pc-disparu' -and $r.Output[0].Data -eq '10.0.1.77' -and $r.Warnings.Count -eq 1) ($r.Error + ($r.Output | Out-String))
$global:FA.Cim.Win32_OperatingSystem = [pscustomobject]@{ ProductType = 3 }
$global:FA.Features = @{ 'GPMC' = $true }
$r = Run '08-maintenance/Install-ADManagementTool.ps1'
Check 'outils RSAT : état affiché sans installation' (($r.Output | Where-Object Tool -eq 'GPMC').Status -eq 'Installé' -and ($r.Output | Where-Object Tool -eq 'RSAT-AD-PowerShell').Status -eq 'Absent' -and -not $global:FA.Features['RSAT-AD-PowerShell']) $r.Error
$r = Run '08-maintenance/Install-ADManagementTool.ps1' @{ Install = $true }
Check 'outils RSAT : -Install installe ce qui manque' ($global:FA.Features['RSAT-AD-PowerShell'] -and @($r.Output | Where-Object Status -eq 'Installé').Count -eq 4) ($r.Error + ($r.Output | Out-String))

# ============================================================================
Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "`n$script:Passed contrôle(s) réussi(s), $script:Failed en échec."
if ($script:Failed -gt 0) { exit 1 }
