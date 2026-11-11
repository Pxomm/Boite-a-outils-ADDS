<#
.SYNOPSIS
    Crée à l'avance des comptes d'ordinateurs dans la bonne unité d'organisation.

.DESCRIPTION
    Un poste dont le compte existe déjà rejoint le domaine directement dans son OU et reçoit
    ses stratégies dès le premier démarrage. -JoinGroup désigne le groupe autorisé à joindre
    ces postes au domaine (à défaut : les administrateurs du domaine).

.EXAMPLE
    .\New-PrestagedComputer.ps1 -Name PC-0201, PC-0202 -Path 'OU=Postes,DC=corp,DC=local' -JoinGroup GG_Support_Jonction
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, ValueFromPipeline)][ValidatePattern('^[A-Za-z0-9-]{1,15}$')][string[]]$Name,
    [Parameter(Mandatory)][string]$Path,
    [string]$JoinGroup,
    [string]$Description
)

begin {
    . "$PSScriptRoot/../../lib/Communs.ps1"
    Initialize-ADToolbox
    $null = Get-ADOrganizationalUnit -Identity $Path -ErrorAction Stop
    $domain = Get-ADDomain
    $joiner = if ($JoinGroup) { Get-ADGroup -Identity $JoinGroup -ErrorAction Stop } else { $null }
}
process {
    foreach ($computerName in $Name) {
        $computerName = $computerName.ToUpperInvariant()
        $status = 'Simulation'
        try {
            if (Get-ADComputer -Filter "Name -eq '$computerName'") { $status = 'Existe déjà' }
            elseif ($PSCmdlet.ShouldProcess("$computerName dans $Path", 'Créer le compte d''ordinateur')) {
                $new = @{ Name = $computerName; SamAccountName = "$computerName`$"; Path = $Path; DNSHostName = "$computerName.$($domain.DNSRoot)".ToLowerInvariant(); Enabled = $true }
                if ($Description) { $new.Description = $Description }
                New-ADComputer @new -ErrorAction Stop
                if ($joiner) {
                    # Droit de jonction : contrôle total du groupe sur ce seul objet
                    $adPath = "AD:\CN=$computerName,$Path"
                    $acl = Get-Acl -Path $adPath
                    $rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule ($joiner.SID, [System.DirectoryServices.ActiveDirectoryRights]::GenericAll, [System.Security.AccessControl.AccessControlType]::Allow)
                    $acl.AddAccessRule($rule)
                    Set-Acl -Path $adPath -AclObject $acl
                }
                $status = 'Créé'
            }
        }
        catch { $status = "Erreur : $($_.Exception.Message)" }
        [pscustomobject]@{ Name = $computerName; Path = $Path; JoinGroup = "$JoinGroup"; Status = $status }
    }
}
