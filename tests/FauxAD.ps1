<#
.SYNOPSIS
    Annuaire Active Directory simulé, en mémoire, pour exécuter les scripts sans domaine.

.DESCRIPTION
    Chaque commande simulée déclare les mêmes noms de paramètres que la vraie : un script
    qui passerait un paramètre inexistant échoue. L'état est dans $global:FA ; toute
    modification est aussi consignée dans $global:FA.Calls.
    Ce fichier ne sert qu'aux tests (tests/Test-Scripts.ps1).
#>

class ADIdentityNotFoundException : System.Exception { ADIdentityNotFoundException([string]$m) : base($m) {} }

$global:FADomainDN = 'DC=corp,DC=local'
$global:FADomainSid = 'S-1-5-21-1000-2000-3000'

function global:Reset-FakeAD {
    $global:FA = @{
        Objects = New-Object System.Collections.Generic.List[object]; Calls = New-Object System.Collections.Generic.List[object]
        RecycleBin = $true; Pso = New-Object System.Collections.Generic.List[object]; Events = @(); Gpo = @(); GpoLinks = @{}; KdsKeys = @()
        Fsmo = @{ PDCEmulator = 'dc01.corp.local'; RIDMaster = 'dc01.corp.local'; InfrastructureMaster = 'dc01.corp.local'; SchemaMaster = 'dc01.corp.local'; DomainNamingMaster = 'dc01.corp.local' }
        Replication = @(); Acl = @{}; Mail = New-Object System.Collections.Generic.List[object]; Tools = New-Object System.Collections.Generic.List[string]
        Cim = @{}; Dns = @{}; SchemaAttributes = @('msLAPS-PasswordExpirationTime'); SecureChannel = $true; Features = @{}
        ToolExit = @{}; ToolOutput = @{}; DownServers = @(); MissingShares = @(); LockedGroups = @(); Sites = @(); Subnets = @(); DnsRecords = @(); LastLogonByServer = $null
    }
    $global:FARid = 1100
}
function global:Add-FakeCall([string]$Name, $Data) { $global:FA.Calls.Add([pscustomobject]@{ Name = $Name; Data = $Data }) }
function global:Get-FakeCall([string]$Name) { @($global:FA.Calls | Where-Object Name -eq $Name) }

function global:New-FakeObject {
    param([string]$Class, [string]$Name, [string]$Path, [hashtable]$Set = @{})
    $global:FARid++
    $rdn = if ($Class -eq 'organizationalUnit') { 'OU' } else { 'CN' }
    $o = [pscustomobject]@{
        ObjectClass = $Class; Name = $Name; DistinguishedName = "$rdn=$Name,$Path"; ObjectGUID = [guid]::NewGuid()
        SamAccountName = $(if ($Class -eq 'organizationalUnit') { $null } elseif ($Class -eq 'computer') { "$Name`$" } else { $Name })
        SID = [pscustomobject]@{ Value = "$global:FADomainSid-$global:FARid" }; Enabled = $true; Description = $null
        whenCreated = (Get-Date).AddDays(-400); whenChanged = (Get-Date).AddDays(-10); isDeleted = $false; isCriticalSystemObject = $false
        Members = (New-Object System.Collections.ArrayList); UacExtra = 0
    }
    foreach ($key in $Set.Keys) { $o | Add-Member -NotePropertyName $key -NotePropertyValue $Set[$key] -Force }
    $o | Add-Member -MemberType ScriptProperty -Name MemberOf -Value { $dn = $this.DistinguishedName; @($global:FA.Objects | Where-Object { $_.ObjectClass -eq 'group' -and $_.Members -contains $dn } | ForEach-Object DistinguishedName) }
    $o | Add-Member -MemberType ScriptProperty -Name userAccountControl -Value { 512 + $(if ($this.Enabled) { 0 } else { 2 }) + [int]$this.UacExtra }
    $global:FA.Objects.Add($o)
    return $o
}

function global:ConvertTo-FakeFilter([string]$Filter) {
    if ($Filter.Trim() -eq '*') { return { param($o) $true } }
    $text = $Filter -replace "\b([A-Za-z][\w-]*)\s+-notlike\s+'\*'", '(-not $$o.''$1'')'
    $text = $text   -replace "\b([A-Za-z][\w-]*)\s+-like\s+'\*'", '([bool]$$o.''$1'')'
    # Comme dans un annuaire réel, un attribut absent ne satisfait aucune comparaison d'ordre
    $text = $text   -replace '\b([A-Za-z][\w-]*)\s+(-lt|-le|-gt|-ge)\s', '$$null -ne $$o.''$1'' -and $$o.''$1'' $2 '
    $text = $text   -replace '(?<![$''.\w])\b([A-Za-z][\w-]*)\s+(-eq|-ne|-like|-notlike)\s', '$$o.''$1'' $2 '
    return [scriptblock]::Create("param(`$o) $text")
}
function global:Find-Fake {
    param([string[]]$Class, $Filter, [string]$LDAPFilter, $Identity, [string]$SearchBase, [string]$SearchScope, [switch]$IncludeDeleted)
    $pool = @($global:FA.Objects | Where-Object { (-not $Class -or $_.ObjectClass -in $Class) -and ($IncludeDeleted -or -not $_.isDeleted) })
    if ($null -ne $Identity) {
        $id = if ($Identity -is [string] -or $Identity -is [guid]) { "$Identity" } elseif ($Identity.DistinguishedName) { $Identity.DistinguishedName } else { "$Identity" }
        $hit = @($pool | Where-Object { $_.DistinguishedName -eq $id -or $_.SamAccountName -eq $id -or "$($_.ObjectGUID)" -eq $id -or $_.SID.Value -eq $id -or
                                        ($_.ObjectClass -eq 'computer' -and $_.Name -eq $id) -or ($_.ObjectClass -eq 'group' -and $_.Name -eq $id) })
        if ($hit.Count -eq 0) { throw [ADIdentityNotFoundException]::new("Cannot find an object with identity: '$id'") }
        return $hit[0]
    }
    if ($SearchBase) {
        if ($SearchBase -ne $global:FADomainDN -and -not ($global:FA.Objects | Where-Object DistinguishedName -eq $SearchBase)) { throw "Directory object not found: $SearchBase" }
        $pool = @($pool | Where-Object {
            $parent = ($_.DistinguishedName -split '(?<!\\),', 2)[1]
            if ($SearchScope -eq 'OneLevel') { $parent -eq $SearchBase } else { $_.DistinguishedName -eq $SearchBase -or $_.DistinguishedName -like "*,$SearchBase" } })
    }
    if ($LDAPFilter) {
        if ($LDAPFilter -match '^\(member:1\.2\.840\.113556\.1\.4\.1941:=(.+)\)$') {
            $seen = New-Object System.Collections.Generic.HashSet[string]; $queue = New-Object System.Collections.Queue; $queue.Enqueue($Matches[1])
            while ($queue.Count) { $dn = $queue.Dequeue(); foreach ($g in $global:FA.Objects | Where-Object { $_.ObjectClass -eq 'group' -and $_.Members -contains $dn }) { if ($seen.Add($g.DistinguishedName)) { $queue.Enqueue($g.DistinguishedName) } } }
            return @($pool | Where-Object { $seen.Contains($_.DistinguishedName) })
        }
        if ($LDAPFilter -match '^\(&\(!\(userAccountControl:1\.2\.840\.113556\.1\.4\.803:=2\)\)\(userAccountControl:1\.2\.840\.113556\.1\.4\.803:=(\d+)\)\)$') {
            $bit = [int]$Matches[1]; return @($pool | Where-Object { $_.Enabled -and ($_.userAccountControl -band $bit) })
        }
        throw "FauxAD : filtre LDAP non géré : $LDAPFilter"
    }
    if ($null -eq $Filter) { throw 'FauxAD : -Filter, -LDAPFilter ou -Identity requis.' }
    $test = ConvertTo-FakeFilter "$Filter"
    return @($pool | Where-Object { & $test $_ })
}
function global:Get-FakeTarget($Identity, [string[]]$Class) { Find-Fake -Class $Class -Identity $Identity }

# --- Lecture ---------------------------------------------------------------
function global:Import-Module {
    [CmdletBinding()] param([Parameter(Position = 0)][string[]]$Name, [Parameter(ValueFromRemainingArguments)]$Rest)
    if ($Name | Where-Object { $_ -notin 'ActiveDirectory', 'GroupPolicy', 'DnsServer' }) { Microsoft.PowerShell.Core\Import-Module @PSBoundParameters }
}
function global:Get-ADUser { [CmdletBinding()] param([Parameter(Position = 0)]$Identity, $Filter, [string]$LDAPFilter, [string[]]$Properties, [string]$SearchBase, [string]$SearchScope, [string]$Server)
    if ($Server -and $global:FA.DownServers -contains $Server) { throw "Unable to contact the server $Server" }
    $r = Find-Fake -Class user -Identity $Identity -Filter $Filter -LDAPFilter $LDAPFilter -SearchBase $SearchBase -SearchScope $SearchScope
    if ($Server -and $null -ne $Identity -and $global:FA.LastLogonByServer) { $r = $r.PSObject.Copy(); $r | Add-Member -NotePropertyName lastLogon -NotePropertyValue $global:FA.LastLogonByServer[$Server] -Force }
    $r }
function global:Get-ADComputer { [CmdletBinding()] param([Parameter(Position = 0)]$Identity, $Filter, [string]$LDAPFilter, [string[]]$Properties, [string]$SearchBase, [string]$SearchScope)
    Find-Fake -Class computer -Identity $Identity -Filter $Filter -LDAPFilter $LDAPFilter -SearchBase $SearchBase -SearchScope $SearchScope }
function global:Get-ADGroup { [CmdletBinding()] param([Parameter(Position = 0)]$Identity, $Filter, [string]$LDAPFilter, [string[]]$Properties, [string]$SearchBase, [string]$SearchScope)
    Find-Fake -Class group -Identity $Identity -Filter $Filter -LDAPFilter $LDAPFilter -SearchBase $SearchBase -SearchScope $SearchScope }
function global:Get-ADOrganizationalUnit { [CmdletBinding()] param([Parameter(Position = 0)]$Identity, $Filter, [string]$LDAPFilter, [string[]]$Properties, [string]$SearchBase, [string]$SearchScope)
    Find-Fake -Class organizationalUnit -Identity $Identity -Filter $Filter -LDAPFilter $LDAPFilter -SearchBase $SearchBase -SearchScope $SearchScope }
function global:Get-ADServiceAccount { [CmdletBinding()] param([Parameter(Position = 0)]$Identity, $Filter, [string[]]$Properties)
    Find-Fake -Class 'msDS-GroupManagedServiceAccount' -Identity $Identity -Filter $Filter }
function global:Get-ADObject { [CmdletBinding()] param([Parameter(Position = 0)]$Identity, $Filter, [string]$LDAPFilter, [string[]]$Properties, [string]$SearchBase, [string]$SearchScope, [switch]$IncludeDeletedObjects, [int]$ResultSetSize)
    if ("$Identity" -like 'CN=Directory Service,*') { return [pscustomobject]@{ tombstoneLifetime = 180; 'msDS-DeletedObjectLifetime' = $null } }
    if ($SearchBase -eq 'CN=Schema,CN=Configuration,DC=corp,DC=local') { if ("$Filter" -match "'(.+)'" -and $Matches[1] -in $global:FA.SchemaAttributes) { return [pscustomobject]@{ Name = $Matches[1] } } else { return } }
    if ($SearchBase -like 'CN=Deleted Objects,*') { $SearchBase = '' }
    $r = @(Find-Fake -Identity $Identity -Filter $Filter -LDAPFilter $LDAPFilter -SearchBase $SearchBase -SearchScope $SearchScope -IncludeDeleted:$IncludeDeletedObjects)
    if ($ResultSetSize) { $r | Select-Object -First $ResultSetSize } else { $r } }
function global:Get-ADGroupMember { [CmdletBinding()] param([Parameter(Position = 0)]$Identity, [switch]$Recursive)
    $group = Get-FakeTarget $Identity group
    $out = New-Object System.Collections.Generic.List[object]; $seen = New-Object System.Collections.Generic.HashSet[string]
    $walk = { param($g) foreach ($dn in $g.Members) { $m = $global:FA.Objects | Where-Object DistinguishedName -eq $dn; if (-not $m) { continue }
                if ($Recursive -and $m.ObjectClass -eq 'group') { if ($seen.Add($dn)) { & $walk $m } } elseif ($seen.Add($dn)) { $out.Add($m) } } }
    & $walk $group; $out }
function global:Search-ADAccount { [CmdletBinding()] param([switch]$LockedOut, [switch]$UsersOnly, [switch]$ComputersOnly, [string]$SearchBase)
    @($global:FA.Objects | Where-Object { $_.ObjectClass -eq 'user' -and $_.LockedOut }) }
function global:Get-ADDomain { [CmdletBinding()] param([Parameter(Position = 0)]$Identity)
    [pscustomobject]@{ DistinguishedName = $global:FADomainDN; DNSRoot = 'corp.local'; NetBIOSName = 'CORP'; Forest = 'corp.local'; DomainMode = 'Windows2016Domain'
        DomainSID = [pscustomobject]@{ Value = $global:FADomainSid }; PDCEmulator = $global:FA.Fsmo.PDCEmulator; RIDMaster = $global:FA.Fsmo.RIDMaster; InfrastructureMaster = $global:FA.Fsmo.InfrastructureMaster
        ComputersContainer = "CN=Computers,$global:FADomainDN"; UsersContainer = "CN=Users,$global:FADomainDN"; DeletedObjectsContainer = "CN=Deleted Objects,$global:FADomainDN" } }
function global:Get-ADForest { [CmdletBinding()] param()
    [pscustomobject]@{ Name = 'corp.local'; RootDomain = 'corp.local'; ForestMode = 'Windows2016Forest'; Domains = @('corp.local'); Sites = @('Lyon', 'Paris')
        SchemaMaster = $global:FA.Fsmo.SchemaMaster; DomainNamingMaster = $global:FA.Fsmo.DomainNamingMaster } }
function global:Get-ADRootDSE { [CmdletBinding()] param() [pscustomobject]@{ configurationNamingContext = 'CN=Configuration,DC=corp,DC=local'; schemaNamingContext = 'CN=Schema,CN=Configuration,DC=corp,DC=local' } }
function global:Get-ADDomainController { [CmdletBinding()] param([Parameter(Position = 0)]$Identity, $Filter)
    $all = @(
        [pscustomobject]@{ Name = 'DC01'; HostName = 'dc01.corp.local'; Site = 'Lyon'; IPv4Address = '10.0.0.10'; OperatingSystem = 'Windows Server 2022 Standard'; IsGlobalCatalog = $true; IsReadOnly = $false; OperationMasterRoles = @('PDCEmulator') }
        [pscustomobject]@{ Name = 'DC02'; HostName = 'dc02.corp.local'; Site = 'Paris'; IPv4Address = '10.1.0.10'; OperatingSystem = 'Windows Server 2022 Standard'; IsGlobalCatalog = $true; IsReadOnly = $false; OperationMasterRoles = @() })
    if ($Identity) { $hit = $all | Where-Object { $_.Name -eq $Identity -or $_.HostName -eq $Identity }; if (-not $hit) { throw "Cannot find directory server with identity: '$Identity'" }; return $hit }
    $all }
function global:Get-ADOptionalFeature { [CmdletBinding()] param($Filter) [pscustomobject]@{ Name = 'Recycle Bin Feature'; EnabledScopes = $(if ($global:FA.RecycleBin) { @('CN=Partitions') } else { @() }) } }
function global:Get-ADDefaultDomainPasswordPolicy { [CmdletBinding()] param()
    [pscustomobject]@{ MinPasswordLength = 8; ComplexityEnabled = $true; PasswordHistoryCount = 24; MaxPasswordAge = [TimeSpan]::FromDays(90); MinPasswordAge = [TimeSpan]::FromDays(1)
        LockoutThreshold = 0; LockoutDuration = [TimeSpan]::FromMinutes(30); LockoutObservationWindow = [TimeSpan]::FromMinutes(30); ReversibleEncryptionEnabled = $false } }
function global:Get-ADFineGrainedPasswordPolicy { [CmdletBinding()] param($Filter, [string[]]$Properties) $test = ConvertTo-FakeFilter "$Filter"; @($global:FA.Pso | Where-Object { & $test $_ }) }
function global:Get-ADReplicationPartnerMetadata { [CmdletBinding()] param([Parameter(Mandatory)]$Target, $Partition, $Scope)
    if ($global:FA.DownServers -contains $Target) { throw "The server is not operational ($Target)" }
    @($global:FA.Replication | Where-Object Server -eq $Target) }
function global:Get-ADReplicationSite { [CmdletBinding()] param($Filter) $global:FA.Sites }
function global:Get-ADReplicationSubnet { [CmdletBinding()] param($Filter) $global:FA.Subnets }
function global:Get-KdsRootKey { [CmdletBinding()] param() $global:FA.KdsKeys }

# --- Écriture --------------------------------------------------------------
function global:New-ADUser { [CmdletBinding()] param([Parameter(Mandatory)][string]$Name, [string]$DisplayName, [string]$GivenName, [string]$Surname, [string]$SamAccountName, [string]$UserPrincipalName, [string]$Path,
        [securestring]$AccountPassword, [bool]$Enabled, [bool]$ChangePasswordAtLogon, [string]$Title, [string]$Department, [string]$Description, [string]$Manager, [datetime]$AccountExpirationDate)
    if (-not (Find-Fake -Class organizationalUnit -Filter "DistinguishedName -eq '$Path'")) { throw "Directory object not found: $Path" }
    if ($global:FA.Objects | Where-Object SamAccountName -eq $SamAccountName) { throw 'The specified account already exists' }
    if ($null -eq $AccountPassword -or $AccountPassword.Length -lt 12) { throw 'The password does not meet the length, complexity, or history requirement of the domain.' }
    $set = @{}; foreach ($k in $PSBoundParameters.Keys | Where-Object { $_ -notin 'Name', 'Path', 'AccountPassword' }) { $set[$k] = $PSBoundParameters[$k] }
    $set.Password = [System.Net.NetworkCredential]::new('', $AccountPassword).Password
    $null = New-FakeObject -Class user -Name $Name -Path $Path -Set $set; Add-FakeCall New-ADUser $SamAccountName }
function global:Set-ADUser { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, $Description, $Manager, $ChangePasswordAtLogon, [string]$GivenName, [string]$Surname, [string]$DisplayName, [string]$SamAccountName,
        [string]$UserPrincipalName, [string]$Title, [string]$Department, [string]$Company, [string]$Office, [string]$OfficePhone, [string]$MobilePhone, [string]$StreetAddress, [string]$City, [string]$PostalCode, [string[]]$Clear, [hashtable]$Replace)
    $u = Get-FakeTarget $Identity user
    foreach ($k in $PSBoundParameters.Keys | Where-Object { $_ -notin 'Identity', 'Clear', 'Replace' }) { $u | Add-Member -NotePropertyName $k -NotePropertyValue $PSBoundParameters[$k] -Force }
    $ldap = @{ title = 'Title'; department = 'Department'; company = 'Company'; physicalDeliveryOfficeName = 'Office'; telephoneNumber = 'OfficePhone'; mobile = 'MobilePhone'; description = 'Description'; streetAddress = 'StreetAddress'; l = 'City'; postalCode = 'PostalCode'; manager = 'Manager'; adminCount = 'adminCount' }
    foreach ($a in $Clear) { if (-not $ldap.ContainsKey($a)) { throw "FauxAD : attribut LDAP inconnu '$a'" }; $u | Add-Member -NotePropertyName $ldap[$a] -NotePropertyValue $null -Force }
    Add-FakeCall Set-ADUser @{ Identity = $u.SamAccountName; Bound = @($PSBoundParameters.Keys) } }
function global:Set-ADComputer { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, [string]$Description) (Get-FakeTarget $Identity computer).Description = $Description; Add-FakeCall Set-ADComputer $Identity }
function global:Disable-ADAccount { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity) (Get-FakeTarget $Identity).Enabled = $false; Add-FakeCall Disable-ADAccount $Identity }
function global:Unlock-ADAccount { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity) (Get-FakeTarget $Identity user) | Add-Member -NotePropertyName LockedOut -NotePropertyValue $false -Force; Add-FakeCall Unlock-ADAccount $Identity }
function global:Set-ADAccountPassword { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, [switch]$Reset, [securestring]$NewPassword)
    if (-not $Reset) { throw 'FauxAD : -Reset attendu' }
    (Get-FakeTarget $Identity user) | Add-Member -NotePropertyName Password -NotePropertyValue ([System.Net.NetworkCredential]::new('', $NewPassword).Password) -Force; Add-FakeCall Set-ADAccountPassword $Identity }
function global:Set-ADAccountExpiration { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, [datetime]$DateTime) (Get-FakeTarget $Identity user) | Add-Member -NotePropertyName AccountExpirationDate -NotePropertyValue $DateTime -Force }
function global:Clear-ADAccountExpiration { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity) (Get-FakeTarget $Identity user) | Add-Member -NotePropertyName AccountExpirationDate -NotePropertyValue $null -Force }
function global:Add-ADGroupMember { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, [Parameter(Mandatory)]$Members)
    $g = Get-FakeTarget $Identity group
    foreach ($m in @($Members)) { $o = Get-FakeTarget $m; if ($g.Members -contains $o.DistinguishedName) { throw 'The specified account name is already a member of the group' }; [void]$g.Members.Add($o.DistinguishedName) }
    Add-FakeCall Add-ADGroupMember @{ Group = $g.Name; Members = $Members } }
function global:Remove-ADGroupMember { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, [Parameter(Mandatory)]$Members, [switch]$Confirm)
    $g = Get-FakeTarget $Identity group
    if ($global:FA.LockedGroups -contains $g.Name) { throw 'Insufficient access rights to perform the operation' }
    foreach ($m in @($Members)) { $o = Get-FakeTarget $m; if ($g.Members -notcontains $o.DistinguishedName) { throw 'The specified account name is not a member of the group' }; $g.Members.Remove($o.DistinguishedName) }
    Add-FakeCall Remove-ADGroupMember @{ Group = $g.Name; Members = $Members } }
function global:Move-ADObject { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, [Parameter(Mandatory)][string]$TargetPath)
    $o = Get-FakeTarget $Identity; $old = $o.DistinguishedName; $new = (($old -split '(?<!\\),', 2)[0]) + ",$TargetPath"
    foreach ($g in $global:FA.Objects | Where-Object { $_.Members -contains $old }) { $g.Members.Remove($old); [void]$g.Members.Add($new) }
    $o.DistinguishedName = $new; Add-FakeCall Move-ADObject @{ From = $old; To = $new } }
function global:Rename-ADObject { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, [Parameter(Mandatory)][string]$NewName)
    $o = Get-FakeTarget $Identity; $old = $o.DistinguishedName; $new = "CN=$NewName," + ($old -split '(?<!\\),', 2)[1]
    foreach ($g in $global:FA.Objects | Where-Object { $_.Members -contains $old }) { $g.Members.Remove($old); [void]$g.Members.Add($new) }
    $o.Name = $NewName; $o.DistinguishedName = $new; Add-FakeCall Rename-ADObject $NewName }
function global:Remove-ADObject { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, [switch]$Recursive, [switch]$Confirm) $o = Get-FakeTarget $Identity; [void]$global:FA.Objects.Remove($o); Add-FakeCall Remove-ADObject $o.Name }
function global:Restore-ADObject { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, [string]$TargetPath, [string]$NewName)
    $o = Find-Fake -Identity $Identity -IncludeDeleted; $o.isDeleted = $false; Add-FakeCall Restore-ADObject @{ Name = $o.'msDS-LastKnownRDN'; TargetPath = $TargetPath } }
function global:New-ADGroup { [CmdletBinding()] param([Parameter(Mandatory)][string]$Name, [string]$SamAccountName, [Parameter(Mandatory)][string]$GroupScope, [string]$GroupCategory, [string]$Path, [string]$Description)
    $null = New-FakeObject -Class group -Name $Name -Path $Path -Set @{ GroupScope = $GroupScope; GroupCategory = $GroupCategory; Description = $Description }; Add-FakeCall New-ADGroup $Name }
function global:New-ADOrganizationalUnit { [CmdletBinding()] param([Parameter(Mandatory)][string]$Name, [string]$Path, [bool]$ProtectedFromAccidentalDeletion, [string]$Description)
    if ($Path -ne $global:FADomainDN -and -not ($global:FA.Objects | Where-Object DistinguishedName -eq $Path)) { throw "Directory object not found: $Path" }
    $null = New-FakeObject -Class organizationalUnit -Name $Name -Path $Path -Set @{ ProtectedFromAccidentalDeletion = $ProtectedFromAccidentalDeletion; Description = $Description }; Add-FakeCall New-ADOrganizationalUnit $Name }
function global:Set-ADOrganizationalUnit { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, [bool]$ProtectedFromAccidentalDeletion) (Get-FakeTarget $Identity organizationalUnit).ProtectedFromAccidentalDeletion = $ProtectedFromAccidentalDeletion }
function global:New-ADComputer { [CmdletBinding()] param([Parameter(Mandatory)][string]$Name, [string]$SamAccountName, [string]$Path, [string]$DNSHostName, [bool]$Enabled, [string]$Description)
    $null = New-FakeObject -Class computer -Name $Name -Path $Path -Set @{ DNSHostName = $DNSHostName; Description = $Description }; Add-FakeCall New-ADComputer $Name }
function global:New-ADServiceAccount { [CmdletBinding()] param([Parameter(Mandatory)][string]$Name, [string]$DNSHostName, $PrincipalsAllowedToRetrieveManagedPassword, [bool]$Enabled, [string]$Description, [string[]]$ServicePrincipalNames)
    $null = New-FakeObject -Class 'msDS-GroupManagedServiceAccount' -Name $Name -Path "CN=Managed Service Accounts,$global:FADomainDN" -Set @{ Allowed = $PrincipalsAllowedToRetrieveManagedPassword }; Add-FakeCall New-ADServiceAccount $Name }
function global:Add-KdsRootKey { [CmdletBinding()] param([switch]$EffectiveImmediately, [datetime]$EffectiveTime) $global:FA.KdsKeys = @([pscustomobject]@{ EffectiveTime = (Get-Date).AddHours(10) }); [guid]::NewGuid() }
function global:New-ADFineGrainedPasswordPolicy { [CmdletBinding()] param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][int]$Precedence, [int]$MinPasswordLength, [int]$PasswordHistoryCount, [bool]$ComplexityEnabled,
        [bool]$ReversibleEncryptionEnabled, [TimeSpan]$MaxPasswordAge, [TimeSpan]$MinPasswordAge, [int]$LockoutThreshold, [TimeSpan]$LockoutDuration, [TimeSpan]$LockoutObservationWindow, [bool]$ProtectedFromAccidentalDeletion)
    $p = [pscustomobject]@{ AppliesTo = (New-Object System.Collections.ArrayList) }; foreach ($k in $PSBoundParameters.Keys) { $p | Add-Member -NotePropertyName $k -NotePropertyValue $PSBoundParameters[$k] }; $global:FA.Pso.Add($p) }
function global:Add-ADFineGrainedPasswordPolicySubject { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, [Parameter(Mandatory)]$Subjects) [void]($global:FA.Pso | Where-Object Name -eq $Identity).AppliesTo.Add($Subjects) }
function global:Enable-ADOptionalFeature { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, [Parameter(Mandatory)]$Scope, [Parameter(Mandatory)]$Target, [switch]$Confirm) $global:FA.RecycleBin = $true; Add-FakeCall Enable-ADOptionalFeature $Target }
function global:Move-ADDirectoryServerOperationMasterRole { [CmdletBinding()] param([Parameter(Mandatory, Position = 0)]$Identity, [Parameter(Mandatory)]$OperationMasterRole, [switch]$Force, [switch]$Confirm)
    foreach ($r in @($OperationMasterRole)) { $global:FA.Fsmo[$r] = $Identity }; Add-FakeCall Move-FSMO @{ Role = $OperationMasterRole; Force = [bool]$Force } }

# --- Stratégies de groupe ---------------------------------------------------
function global:Get-GPO { [CmdletBinding()] param([switch]$All, [guid]$Guid, [string]$Name) $global:FA.Gpo }
function global:Get-GPOReport { [CmdletBinding()] param([guid]$Guid, [Parameter(Mandatory)][string]$ReportType, [string]$Path)
    $g = $global:FA.Gpo | Where-Object Id -eq $Guid; if ($Path) { "<html>$($g.DisplayName)</html>" | Set-Content -LiteralPath $Path } else { $g.Xml } }
function global:Backup-GPO { [CmdletBinding()] param([guid]$Guid, [Parameter(Mandatory)][string]$Path, [string]$Comment)
    $g = $global:FA.Gpo | Where-Object Id -eq $Guid; if ($g.FailBackup) { throw 'Access is denied.' }; [pscustomobject]@{ Id = [guid]::NewGuid(); DisplayName = $g.DisplayName } }
function global:Restore-GPO { [CmdletBinding()] param([guid]$BackupId, [Parameter(Mandatory)][string]$Path, [string]$Name) Add-FakeCall Restore-GPO $BackupId; [pscustomobject]@{ Id = $BackupId } }
function global:Get-GPInheritance { [CmdletBinding()] param([Parameter(Mandatory)][string]$Target) [pscustomobject]@{ GpoLinks = @($global:FA.GpoLinks[$Target] | Where-Object { $_ }); GpoInheritanceBlocked = $false } }

# --- Système, journaux, réseau ---------------------------------------------
function global:Get-WinEvent { [CmdletBinding()] param([string]$ComputerName, [hashtable]$FilterHashtable, [int]$MaxEvents)
    $hit = @($global:FA.Events | Where-Object { $_.Id -in @($FilterHashtable.Id) -and $_.TimeCreated -ge $FilterHashtable.StartTime -and (-not $_.Server -or $_.Server -eq $ComputerName) })
    if ($hit.Count -eq 0) { Write-Error -Message 'No events were found that match the specified selection criteria.' -ErrorId 'NoMatchingEventsFound,Microsoft.PowerShell.Commands.GetWinEventCommand'; return }
    $hit }
function global:New-FakeEvent([int]$Id, [System.Collections.IDictionary]$Data, [datetime]$Time = (Get-Date).AddHours(-1), [string]$Server) {
    $xml = '<Event><EventData>' + (($Data.Keys | ForEach-Object { "<Data Name=""$_"">$($Data[$_])</Data>" }) -join '') + '</EventData></Event>'
    $e = [pscustomobject]@{ Id = $Id; TimeCreated = $Time; Server = $Server; Properties = @($Data.Values | ForEach-Object { [pscustomobject]@{ Value = $_ } }); Xml = $xml }
    $e | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.Xml } -PassThru }
function global:Get-CimInstance { [CmdletBinding()] param([string]$ClassName, [string]$ComputerName, [string]$Filter) $global:FA.Cim[$ClassName] }
function global:Test-Connection { [CmdletBinding()] param([string[]]$ComputerName, [int]$Count, [switch]$Quiet) -not ($global:FA.DownServers -contains $ComputerName[0]) }
function global:Test-Path { [CmdletBinding()] param([Parameter(Position = 0)][string]$Path, [string]$LiteralPath)
    $p = if ($LiteralPath) { $LiteralPath } else { $Path }
    if ($p -like '\\*') { return -not ($global:FA.MissingShares -contains $p) }
    Microsoft.PowerShell.Management\Test-Path @PSBoundParameters }
function global:Resolve-DnsName { [CmdletBinding()] param([Parameter(Mandatory)][string]$Name, [string]$Type, [string]$Server)
    if (-not $global:FA.Dns.ContainsKey($Name)) { throw "DNS name does not exist: $Name" }; $global:FA.Dns[$Name] }
function global:Send-MailMessage { [CmdletBinding()] param([string]$SmtpServer, [string]$From, [string[]]$To, [string]$Subject, [string]$Body, [switch]$BodyAsHtml, $Encoding) $global:FA.Mail.Add([pscustomobject]@{ To = $To; Subject = $Subject; Body = $Body }) }
function global:New-FakeAce([string]$Identity, [string]$Sid, [string]$Rights = 'GenericAll', [string]$ObjectType = '00000000-0000-0000-0000-000000000000', [bool]$Inherited = $false) {
    $ref = [pscustomobject]@{ Value = $Identity; Sid = $Sid }
    $ref | Add-Member -MemberType ScriptMethod -Name Translate -Value { param($type) [pscustomobject]@{ Value = $this.Sid } }
    $ref | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.Value } -Force
    [pscustomobject]@{ IdentityReference = $ref; AccessControlType = 'Allow'; ActiveDirectoryRights = $Rights; ObjectType = $ObjectType; InheritedObjectType = '00000000-0000-0000-0000-000000000000'; InheritanceType = 'All'; IsInherited = $Inherited } }
function global:Get-Acl { [CmdletBinding()] param([string]$Path)
    $dn = $Path -replace '^AD:\\'
    $acl = [pscustomobject]@{ Dn = $dn; Access = @($global:FA.Acl[$dn] | Where-Object { $_ }); Protected = $true }
    $acl | Add-Member -MemberType ScriptMethod -Name SetAccessRuleProtection -Value { param($protected, $preserve) $this.Protected = $protected } -PassThru }
function global:Set-Acl { [CmdletBinding()] param([string]$Path, $AclObject) Add-FakeCall Set-Acl @{ Path = $Path; Protected = $AclObject.Protected } }
function global:Get-DnsServerZoneAging { [CmdletBinding()] param([string]$Name, [string]$ComputerName) [pscustomobject]@{ AgingEnabled = $false } }
function global:Get-DnsServerResourceRecord { [CmdletBinding()] param([string]$ZoneName, [string]$ComputerName) $global:FA.DnsRecords }
function global:Get-WindowsFeature { [CmdletBinding()] param([string[]]$Name) foreach ($n in $Name) { [pscustomobject]@{ Name = $n; Installed = [bool]$global:FA.Features[$n] } } }
function global:Install-WindowsFeature { [CmdletBinding()] param([string[]]$Name) $global:FA.Features[$Name[0]] = $true; [pscustomobject]@{ Success = $true } }
function global:Test-ComputerSecureChannel { [CmdletBinding()] param([switch]$Repair, $Credential) if ($Repair) { $global:FA.SecureChannel = $true }; $global:FA.SecureChannel }
foreach ($tool in 'dcdiag.exe', 'repadmin.exe', 'w32tm.exe', 'wbadmin.exe', 'redircmp.exe', 'redirusr.exe') {
    Set-Item -Path "function:global:$tool" -Value ([scriptblock]::Create("`$global:FA.Tools.Add('$tool ' + (`$args -join ' ')); `$global:LASTEXITCODE = [int]`$global:FA.ToolExit['$tool']; `$global:FA.ToolOutput['$tool']"))
}
