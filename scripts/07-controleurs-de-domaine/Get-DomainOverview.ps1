<#
.SYNOPSIS
    Donne la fiche d'identité de la forêt et du domaine : niveaux fonctionnels, contrôleurs, rôles, volumétrie.

.DESCRIPTION
    Point de départ d'un audit ou d'une documentation : niveaux fonctionnels, détenteurs des
    rôles FSMO, sites, état de la corbeille Active Directory, durée de conservation des
    objets supprimés, nombre d'utilisateurs, d'ordinateurs, de groupes et d'OU.
    -DomainControllers renvoie à la place la liste détaillée des contrôleurs de domaine.

.EXAMPLE
    .\Get-DomainOverview.ps1 | Format-List

.EXAMPLE
    .\Get-DomainOverview.ps1 -DomainControllers | Format-Table
#>
[CmdletBinding()]
param([switch]$DomainControllers)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$domain = Get-ADDomain
$forest = Get-ADForest
$controllers = @(Get-ADDomainController -Filter *)

if ($DomainControllers) {
    $controllers | Sort-Object HostName | ForEach-Object {
        [pscustomobject]@{ HostName = $_.HostName; Site = $_.Site; IPv4Address = $_.IPv4Address; OperatingSystem = $_.OperatingSystem
                           IsGlobalCatalog = $_.IsGlobalCatalog; IsReadOnly = $_.IsReadOnly; Roles = (@($_.OperationMasterRoles) -join ', ') }
    }
    return
}

$recycleBin = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'"
$directoryService = Get-ADObject -Identity "CN=Directory Service,CN=Windows NT,CN=Services,$((Get-ADRootDSE).configurationNamingContext)" -Properties tombstoneLifetime, 'msDS-DeletedObjectLifetime'
$tombstone = if ($directoryService.tombstoneLifetime) { [int]$directoryService.tombstoneLifetime } else { 60 }     # valeur implicite historique

[pscustomobject]@{
    Forest                    = $forest.Name
    ForestMode                = "$($forest.ForestMode)"
    Domain                    = $domain.DNSRoot
    NetBIOSName               = $domain.NetBIOSName
    DomainMode                = "$($domain.DomainMode)"
    DomainsInForest           = @($forest.Domains).Count
    Sites                     = @($forest.Sites).Count
    DomainControllers         = $controllers.Count
    GlobalCatalogs            = @($controllers | Where-Object IsGlobalCatalog).Count
    ReadOnlyDomainControllers = @($controllers | Where-Object IsReadOnly).Count
    SchemaMaster              = $forest.SchemaMaster
    DomainNamingMaster        = $forest.DomainNamingMaster
    PDCEmulator               = $domain.PDCEmulator
    RIDMaster                 = $domain.RIDMaster
    InfrastructureMaster      = $domain.InfrastructureMaster
    RecycleBinEnabled         = [bool](@($recycleBin.EnabledScopes).Count -gt 0)
    TombstoneLifetimeDays     = $tombstone
    DeletedObjectLifetimeDays = if ($directoryService.'msDS-DeletedObjectLifetime') { [int]$directoryService.'msDS-DeletedObjectLifetime' } else { $tombstone }
    Users                     = @(Get-ADUser -Filter *).Count
    EnabledUsers              = @(Get-ADUser -Filter "Enabled -eq `$true").Count
    Computers                 = @(Get-ADComputer -Filter *).Count
    Groups                    = @(Get-ADGroup -Filter *).Count
    OrganizationalUnits       = @(Get-ADOrganizationalUnit -Filter *).Count
}
