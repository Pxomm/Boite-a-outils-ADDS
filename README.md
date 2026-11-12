# Boîte à outils Active Directory

Soixante-neuf scripts PowerShell pour administrer un domaine Active Directory (AD DS) au quotidien : comptes, groupes, ordinateurs, unités d'organisation, stratégies de groupe, audit de sécurité, santé des contrôleurs de domaine et maintenance.

Chaque script fait une seule chose, porte son aide intégrée et renvoie des objets exploitables (`Format-Table`, `Out-GridView`, `Export-Csv`). Tout script qui modifie quelque chose accepte `-WhatIf` pour montrer ce qu'il ferait sans rien toucher.

> **Avant toute utilisation en production.** Ces scripts ont été vérifiés par analyse statique et par exécution contre un annuaire simulé, pas sur un domaine réel (voir [Vérifications et limites](#vérifications-et-limites)). Les essayer d'abord sur un domaine de test, et toujours commencer par `-WhatIf`.

## Démarrage rapide

```powershell
# 1. Récupérer le dépôt (les scripts dépendent du dossier lib/, garder l'arborescence)
git clone https://github.com/Pxomm/WINDOWS_SERVER-Scripts-Boite-a-outils-ADDS.git
cd WINDOWS_SERVER-Scripts-Boite-a-outils-ADDS

# 2. Vérifier les outils d'administration (console élevée), puis les installer si besoin
.\scripts\08-maintenance\Install-ADManagementTool.ps1
.\scripts\08-maintenance\Install-ADManagementTool.ps1 -Install

# 3. Premier tour d'horizon, sans aucune modification
.\scripts\07-controleurs-de-domaine\Get-DomainOverview.ps1 | Format-List
.\scripts\07-controleurs-de-domaine\Get-DCHealth.ps1 | Format-Table HostName, Healthy, Issues -AutoSize

# 4. Aide détaillée d'un script
Get-Help .\scripts\01-utilisateurs\New-UserAccount.ps1 -Full
```

Si l'exécution des scripts est bloquée sur le poste : `Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned`, puis `Get-ChildItem -Recurse -Filter *.ps1 | Unblock-File` après un téléchargement en archive ZIP.

## Prérequis

| Élément | Détail |
|---|---|
| PowerShell | Windows PowerShell 5.1 ou PowerShell 7. `Repair-ComputerTrust.ps1` exige Windows PowerShell 5.1 |
| Modules | `ActiveDirectory` pour tous les scripts d'annuaire ; `GroupPolicy` pour le dossier 05 ; `DnsServer` pour `Get-StaleDnsRecord.ps1` |
| Poste d'exécution | Contrôleur de domaine, serveur membre ou poste d'administration avec les outils RSAT |
| Droits | Lecture de l'annuaire pour les rapports ; délégation adaptée ou compte d'administration pour les modifications. Les scripts lisant le journal Sécurité exigent le droit correspondant sur les contrôleurs de domaine |
| Réseau | WinRM vers les contrôleurs de domaine pour `Get-DCHealth.ps1` ; services Web Active Directory (port 9389) pour le module |

## Conventions

- **Simulation d'abord.** `-WhatIf` sur tout script qui modifie l'annuaire, des fichiers ou le système. Les opérations lourdes (départ, quarantaine, suppression, rôles FSMO, corbeille) demandent en plus une confirmation, que `-Confirm:$false` supprime dans une tâche planifiée.
- **Résultats en objets.** La plupart des rapports acceptent `-CsvPath` : fichier CSV en UTF-8, séparateur « ; », lisible directement par Excel en français.
- **Une ligne par élément, une colonne `Status`.** Dans les traitements par lots, une erreur sur un élément est consignée dans le résultat et n'interrompt pas les suivants.
- **Fichiers CSV en entrée** : séparateur « ; » (modifiable par `-Delimiter`), en-têtes en français. Un modèle de chaque fichier se trouve dans [`exemples/`](exemples/).
- **Aucun mot de passe en dur.** Les mots de passe initiaux sont tirés au hasard par un générateur cryptographique et renvoyés une seule fois dans le résultat.
- **Indépendance de la langue.** Les groupes intégrés sont identifiés par leur SID, jamais par leur nom : les scripts fonctionnent sur un domaine installé en français comme en anglais.

## Quel script pour quelle situation

| Situation | Script |
|---|---|
| Un collaborateur arrive | `New-UserAccount.ps1`, ou `Import-UsersFromCsv.ps1` pour une vague d'arrivées |
| Un collaborateur part | `Disable-DepartedUser.ps1` |
| Un collaborateur change de poste | `Copy-UserGroupMembership.ps1`, `Update-UserAttributeFromCsv.ps1` |
| Un collaborateur change de nom | `Rename-UserAccount.ps1` |
| Mot de passe oublié | `Reset-UserPassword.ps1` |
| Compte verrouillé, encore et encore | `Unlock-UserAccount.ps1`, puis `Find-LockoutSource.ps1` et `Get-FailedLogon.ps1` |
| Prévenir avant l'expiration des mots de passe | `Get-PasswordExpiration.ps1 -Notify` |
| Un prestataire a besoin d'un compte temporaire | `New-UserAccount.ps1 -ExpirationDate`, `Set-UserExpiration.ps1` |
| « Quels sont les droits de cette personne ? » | `Get-UserGroupMembership.ps1`, `Compare-GroupMembership.ps1` |
| « Qui a accès à ce groupe ? » | `Export-GroupMembership.ps1 -Recursive` |
| Un objet a été supprimé par erreur | `Get-DeletedObject.ps1`, `Restore-DeletedObject.ps1` |
| Un poste a perdu sa relation d'approbation | `Repair-ComputerTrust.ps1` |
| Un disque chiffré demande sa clé de récupération | `Get-BitLockerRecoveryKey.ps1` |
| Faire le ménage dans les comptes et les postes | `Get-InactiveUser.ps1`, `Disable-InactiveComputer.ps1`, `Remove-QuarantinedComputer.ps1`, `Get-EmptyGroup.ps1`, `Get-EmptyOU.ps1` |
| Bâtir ou documenter l'arborescence | `New-OUStructureFromCsv.ps1`, `Export-OUTree.ps1`, `Set-DefaultContainer.ps1` |
| « Quelle GPO fait ça ? » | `Find-GPOSetting.ps1`, `Get-GPOLink.ps1` |
| Une GPO a été cassée | `Restore-GPOFromBackup.ps1` (après `Backup-AllGPO.ps1` planifié) |
| Préparer un audit de sécurité | `Get-PrivilegedGroupMember.ps1`, `Get-RiskyAccountSetting.ps1`, `Get-DelegationReport.ps1`, `Get-DCSyncRight.ps1`, `Get-PasswordPolicyReport.ps1`, `Get-LapsCoverage.ps1` |
| « Qui a modifié ce compte ou ce groupe ? » | `Get-ADChangeAudit.ps1` |
| Remplacer un compte de service à mot de passe fixe | `New-GroupManagedServiceAccount.ps1` |
| Un contrôleur de domaine se comporte mal | `Get-DCHealth.ps1`, `Get-ReplicationStatus.ps1`, `Test-DCDnsRecord.ps1`, `Get-TimeSyncStatus.ps1`, `Invoke-DCDiagnostic.ps1` |
| Retirer ou remplacer un contrôleur de domaine | `Get-FSMORole.ps1`, `Move-FSMORole.ps1` |
| Pouvoir restaurer l'annuaire | `Backup-SystemState.ps1`, `Enable-RecycleBin.ps1` |
| Surveiller l'annuaire chaque matin | `New-DailyReport.ps1` |

## Catalogue

### Utilisateurs — `scripts/01-utilisateurs/`

| Script | Rôle | `-WhatIf` |
|---|---|---|
| `Copy-UserGroupMembership.ps1` | Recopie les groupes d'un utilisateur vers un autre (changement de poste, « mêmes droits que ») | oui |
| `Disable-DepartedUser.ps1` | Traite le départ d'un collaborateur : désactivation, retrait des groupes, déplacement | oui |
| `Export-UserInventory.ps1` | Exporte l'inventaire des comptes utilisateurs avec leurs principaux attributs | — |
| `Find-LockoutSource.ps1` | Indique depuis quel poste un compte a été verrouillé (événements 4740) | — |
| `Get-InactiveUser.ps1` | Liste les comptes utilisateurs actifs qui ne se sont pas connectés depuis N jours | — |
| `Get-IncompleteUser.ps1` | Liste les comptes actifs dont des attributs attendus sont vides (qualité de l'annuaire) | — |
| `Get-PasswordExpiration.ps1` | Liste les utilisateurs dont le mot de passe expire dans les N prochains jours, et peut les prévenir par courriel | oui |
| `Get-UserLastLogon.ps1` | Donne la date exacte de dernière ouverture de session d'un utilisateur en interrogeant chaque contrôleur de domaine | — |
| `Import-UsersFromCsv.ps1` | Crée des comptes utilisateurs en masse à partir d'un fichier CSV | oui |
| `New-UserAccount.ps1` | Crée un compte utilisateur complet : identifiant, UPN, mot de passe initial, groupes | oui |
| `Rename-UserAccount.ps1` | Renomme un utilisateur (changement de nom d'usage) : nom affiché, nom d'objet, identifiant et UPN | oui |
| `Reset-UserPassword.ps1` | Réinitialise le mot de passe d'un utilisateur avec une valeur aléatoire et déverrouille le compte | oui |
| `Set-UserExpiration.ps1` | Fixe, repousse ou supprime la date d'expiration d'un compte (prestataires, stagiaires, CDD) | oui |
| `Unlock-UserAccount.ps1` | Liste les comptes verrouillés et les déverrouille | oui |
| `Update-UserAttributeFromCsv.ps1` | Met à jour en masse les attributs des utilisateurs à partir d'un fichier CSV | oui |

### Groupes — `scripts/02-groupes/`

| Script | Rôle | `-WhatIf` |
|---|---|---|
| `Compare-GroupMembership.ps1` | Compare les membres de deux groupes, ou les groupes de deux utilisateurs | — |
| `Export-GroupMembership.ps1` | Exporte les membres des groupes, une ligne par couple groupe / membre | — |
| `Get-EmptyGroup.ps1` | Liste les groupes sans aucun membre | — |
| `Get-NestedGroupLoop.ps1` | Détecte les imbrications circulaires de groupes (A membre de B, B membre de A, directement ou non) | — |
| `Get-UserGroupMembership.ps1` | Liste tous les groupes d'un utilisateur, y compris ceux hérités par imbrication | — |
| `New-GroupFromCsv.ps1` | Crée des groupes en masse à partir d'un fichier CSV | oui |
| `Set-GroupMemberFromCsv.ps1` | Ajoute ou retire des membres de groupes en masse à partir d'un fichier CSV | oui |

### Ordinateurs — `scripts/03-ordinateurs/`

| Script | Rôle | `-WhatIf` |
|---|---|---|
| `Disable-InactiveComputer.ps1` | Désactive les ordinateurs inactifs et les place en quarantaine | oui |
| `Get-BitLockerRecoveryKey.ps1` | Retrouve les mots de passe de récupération BitLocker enregistrés dans Active Directory pour un ordinateur | — |
| `Get-ComputerInventory.ps1` | Inventorie les ordinateurs du domaine par système d'exploitation et signale les systèmes en fin de support | — |
| `Get-InactiveComputer.ps1` | Liste les comptes d'ordinateurs actifs qui ne se sont pas authentifiés depuis N jours | — |
| `Move-ComputerByNamePattern.ps1` | Range les ordinateurs dans leur unité d'organisation d'après leur nom | oui |
| `New-PrestagedComputer.ps1` | Crée à l'avance des comptes d'ordinateurs dans la bonne unité d'organisation | oui |
| `Remove-QuarantinedComputer.ps1` | Supprime les ordinateurs restés en quarantaine au-delà du délai de garde | oui |
| `Repair-ComputerTrust.ps1` | Vérifie et répare la relation d'approbation entre un poste et le domaine, sans le sortir du domaine | oui |

### Unités d'organisation — `scripts/04-unites-organisation/`

| Script | Rôle | `-WhatIf` |
|---|---|---|
| `Export-OUTree.ps1` | Exporte l'arborescence des unités d'organisation avec le nombre d'objets et de stratégies liées | — |
| `Get-EmptyOU.ps1` | Liste les unités d'organisation qui ne contiennent aucun objet | — |
| `Get-OUDelegation.ps1` | Liste les délégations de droits posées explicitement sur les unités d'organisation | — |
| `New-OUStructureFromCsv.ps1` | Crée une arborescence d'unités d'organisation à partir d'un fichier CSV | oui |
| `Set-DefaultContainer.ps1` | Redirige les conteneurs par défaut des nouveaux ordinateurs et utilisateurs vers des unités d'organisation | oui |
| `Set-OUDeletionProtection.ps1` | Repère les unités d'organisation non protégées contre la suppression accidentelle, et les protège | oui |

### Stratégies de groupe — `scripts/05-strategies-de-groupe/`

| Script | Rôle | `-WhatIf` |
|---|---|---|
| `Backup-AllGPO.ps1` | Sauvegarde toutes les stratégies de groupe dans un dossier daté, avec inventaire et rapports | oui |
| `Find-GPOSetting.ps1` | Recherche un texte dans les paramètres de toutes les stratégies de groupe | — |
| `Get-GPOHealthReport.ps1` | Passe en revue les stratégies de groupe : non liées, vides, désactivées, incohérentes | — |
| `Get-GPOLink.ps1` | Inventorie les liens de stratégies de groupe : quelle GPO s'applique où, dans quel ordre | — |
| `Restore-GPOFromBackup.ps1` | Restaure une stratégie de groupe à partir d'un dossier de sauvegarde | oui |

### Sécurité et audit — `scripts/06-securite/`

| Script | Rôle | `-WhatIf` |
|---|---|---|
| `Get-ADChangeAudit.ps1` | Retrace les modifications récentes de comptes et de groupes : qui a fait quoi, quand | — |
| `Get-AdminCountOrphan.ps1` | Repère les comptes marqués adminCount = 1 qui ne sont plus membres d'un groupe protégé | oui |
| `Get-DCSyncRight.ps1` | Liste les comptes autorisés à répliquer les secrets de l'annuaire (droit « DCSync ») | — |
| `Get-DelegationReport.ps1` | Inventorie les délégations Kerberos : non contrainte, contrainte, basée sur les ressources | — |
| `Get-FailedLogon.ps1` | Résume les échecs d'authentification relevés sur les contrôleurs de domaine | — |
| `Get-KrbtgtStatus.ps1` | Indique l'âge du mot de passe du compte krbtgt | — |
| `Get-LapsCoverage.ps1` | Mesure la couverture de LAPS : quels ordinateurs ont un mot de passe administrateur local géré, et lesquels non | — |
| `Get-PasswordPolicyReport.ps1` | Présente la stratégie de mot de passe du domaine et les stratégies affinées (PSO), avec leurs cibles | — |
| `Get-PrivilegedGroupMember.ps1` | Liste les membres des groupes à privilèges, imbrications comprises | — |
| `Get-RiskyAccountSetting.ps1` | Repère les comptes dont le paramétrage affaiblit la sécurité du domaine | — |
| `New-AdminPasswordPolicy.ps1` | Crée une stratégie de mot de passe affinée (PSO) renforcée et l'applique à un groupe | oui |
| `New-GroupManagedServiceAccount.ps1` | Crée un compte de service administré de groupe (gMSA), dont le mot de passe est géré par Active Directory | oui |

### Contrôleurs de domaine — `scripts/07-controleurs-de-domaine/`

| Script | Rôle | `-WhatIf` |
|---|---|---|
| `Backup-SystemState.ps1` | Sauvegarde l'état du système d'un contrôleur de domaine (annuaire, SYSVOL, registre) avec Sauvegarde Windows Server | oui |
| `Get-DCHealth.ps1` | Contrôle l'état de chaque contrôleur de domaine : réponse réseau, services, partages, disque, démarrage | — |
| `Get-DomainOverview.ps1` | Donne la fiche d'identité de la forêt et du domaine : niveaux fonctionnels, contrôleurs, rôles, volumétrie | — |
| `Get-FSMORole.ps1` | Indique quel contrôleur de domaine détient chacun des cinq rôles FSMO et s'il répond | — |
| `Get-ReplicationStatus.ps1` | Contrôle la réplication Active Directory entre contrôleurs de domaine | — |
| `Get-SiteSubnetReport.ps1` | Contrôle la topologie des sites : sous-réseaux, contrôleurs de domaine, anomalies | — |
| `Get-TimeSyncStatus.ps1` | Mesure l'écart d'horloge de chaque contrôleur de domaine et indique la source de temps de l'émulateur PDC | — |
| `Invoke-DCDiagnostic.ps1` | Lance dcdiag et repadmin sur chaque contrôleur de domaine et archive les résultats | — |
| `Move-FSMORole.ps1` | Transfère des rôles FSMO vers un autre contrôleur de domaine | oui |
| `Test-DCDnsRecord.ps1` | Vérifie que les enregistrements DNS indispensables à Active Directory existent et désignent les bons contrôleurs | — |

### Maintenance — `scripts/08-maintenance/`

| Script | Rôle | `-WhatIf` |
|---|---|---|
| `Enable-RecycleBin.ps1` | Vérifie l'état de la corbeille Active Directory et l'active | oui |
| `Get-DeletedObject.ps1` | Liste les objets supprimés encore présents dans la corbeille Active Directory | — |
| `Get-StaleDnsRecord.ps1` | Liste les enregistrements DNS dynamiques qui n'ont pas été rafraîchis depuis N jours | — |
| `Install-ADManagementTool.ps1` | Installe les outils d'administration Active Directory (RSAT) nécessaires aux scripts de ce dépôt | oui |
| `New-DailyReport.ps1` | Produit le rapport quotidien de l'annuaire en HTML et peut l'envoyer par courriel | — |
| `Restore-DeletedObject.ps1` | Restaure un objet supprimé depuis la corbeille Active Directory | oui |

## Exemples d'enchaînements

**Arrivée d'un collaborateur**

```powershell
.\scripts\01-utilisateurs\New-UserAccount.ps1 -GivenName Jeanne -Surname Dupont `
    -Path 'OU=Comptabilite,OU=Utilisateurs,DC=corp,DC=local' -CopyGroupsFrom m.martin -Title Comptable -WhatIf
# Vérifier la simulation, puis relancer sans -WhatIf : le mot de passe initial figure dans le résultat
```

**Départ d'un collaborateur**

```powershell
.\scripts\01-utilisateurs\Disable-DepartedUser.ps1 -Identity j.dupont `
    -DisabledOU 'OU=Comptes desactives,DC=corp,DC=local' -LogDirectory D:\Journaux\Departs -Reference 'Ticket 4521' -WhatIf
```

**Nettoyage des postes en deux temps**

```powershell
# Chaque mois : mise en quarantaine des postes inactifs depuis 120 jours
.\scripts\03-ordinateurs\Disable-InactiveComputer.ps1 -Days 120 -QuarantineOU 'OU=Quarantaine,DC=corp,DC=local' -WhatIf
# Trente jours plus tard : suppression de ceux que personne n'a réclamés
.\scripts\03-ordinateurs\Remove-QuarantinedComputer.ps1 -QuarantineOU 'OU=Quarantaine,DC=corp,DC=local' -KeepDays 30 -WhatIf
```

**Tâches à planifier** (compte de service dédié, `-Confirm:$false` là où une confirmation est demandée)

| Fréquence | Commande |
|---|---|
| Chaque matin | `New-DailyReport.ps1 -Path D:\Rapports\AD -SmtpServer … -From … -To …` |
| Chaque matin | `Get-PasswordExpiration.ps1 -Days 7 -Notify -SmtpServer … -From …` |
| Chaque nuit | `Backup-AllGPO.ps1 -Path D:\Sauvegardes\GPO -IncludeReport -KeepDays 90`, puis `Get-GPOLink.ps1 -CsvPath …` |
| Chaque semaine | `Backup-SystemState.ps1 -Target E:` sur au moins deux contrôleurs de domaine |
| Chaque mois | `Get-PrivilegedGroupMember.ps1`, `Get-RiskyAccountSetting.ps1`, `Get-DCSyncRight.ps1` avec `-CsvPath` daté, à comparer d'un mois sur l'autre |

## Organisation du dépôt

```
.
├── scripts/                 Les scripts, classés par domaine (01 à 08)
├── lib/Communs.ps1          Fonctions partagées : mot de passe aléatoire, identifiant, export CSV…
├── exemples/                Modèles des fichiers CSV attendus en entrée
├── tests/                   Tests automatiques et annuaire simulé
└── .github/workflows/       Intégration continue : analyse statique et tests
```

Chaque script charge `lib/Communs.ps1` par un chemin relatif : copier un script seul hors du dépôt ne fonctionne pas, il faut conserver les dossiers `scripts/` et `lib/`.

## Vérifications et limites

```powershell
pwsh -NoProfile -File tests/Test-Scripts.ps1
```

| Vérifié | Comment |
|---|---|
| Syntaxe, encodage UTF-8 avec BOM, aide intégrée, catalogue à jour, `-WhatIf` présent sur tout script qui modifie l'annuaire | Contrôles de structure |
| Qualité du code | PSScriptAnalyzer : aucun avertissement sur `scripts/` et `lib/` |
| Compatibilité Windows PowerShell 5.1 | Règles de compatibilité de PSScriptAnalyzer (profil Windows Server 2019) |
| Logique des 69 scripts : cas nominal, simulation, erreurs, traitements par lots, rejouabilité | 181 contrôles, dont 167 exécutent les scripts contre un annuaire simulé en mémoire ([`tests/FauxAD.ps1`](tests/FauxAD.ps1)) dont les commandes n'acceptent que les paramètres des vraies commandes |

**Ce que ces tests ne prouvent pas.** L'annuaire simulé a été écrit à partir de la documentation des modules Microsoft, pas à partir d'un domaine réel. Aucun script n'a été exécuté sur un vrai contrôleur de domaine. Restent donc à valider sur un domaine de test, en particulier :

- les scripts qui s'appuient sur des outils externes dont la sortie est analysée : `Get-TimeSyncStatus.ps1` (w32tm), `Invoke-DCDiagnostic.ps1` (dcdiag, repadmin), `Backup-SystemState.ps1` (wbadmin), `Set-DefaultContainer.ps1` (redircmp, redirusr) ;
- les scripts qui lisent ou modifient des listes de contrôle d'accès par le lecteur `AD:` : `Get-OUDelegation.ps1`, `Get-DCSyncRight.ps1`, `Get-AdminCountOrphan.ps1 -Fix`, `New-PrestagedComputer.ps1 -JoinGroup` (cette dernière option n'est couverte par aucun test) ;
- les scripts qui lisent le journal Sécurité, dont le contenu dépend de la stratégie d'audit en place ;
- le comportement sur un annuaire volumineux : `Get-ADGroupMember` échoue au-delà de 5 000 membres, et les rapports portant sur tous les objets peuvent être longs.

## Licence et responsabilité

Scripts fournis à titre d'exemple, sans garantie. Leur utilisation sur un annuaire de production relève de la responsabilité de l'administrateur qui les exécute.
