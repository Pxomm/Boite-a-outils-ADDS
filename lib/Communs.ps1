<#
.SYNOPSIS
    Fonctions partagées par les scripts de la boîte à outils AD DS.

.DESCRIPTION
    Fichier chargé par chaque script (« dot-sourcing »). Il ne modifie rien par
    lui-même. Compatible Windows PowerShell 5.1 et PowerShell 7.
#>

function Initialize-ADToolbox {
    <# Charge les modules nécessaires avec un message clair s'ils sont absents. #>
    [CmdletBinding()]
    param([switch]$GroupPolicy, [switch]$DnsServer)
    $wanted = @('ActiveDirectory')
    if ($GroupPolicy) { $wanted += 'GroupPolicy' }
    if ($DnsServer)   { $wanted += 'DnsServer' }
    foreach ($name in $wanted) {
        try { Import-Module $name -ErrorAction Stop -Verbose:$false }
        catch { throw "Module PowerShell '$name' introuvable : installer les outils RSAT (voir scripts/08-maintenance/Install-ADManagementTool.ps1). Détail : $($_.Exception.Message)" }
    }
}

function Get-RandomIndex {
    <# Entier aléatoire sans biais dans [0, Max[ (Max <= 256), générateur cryptographique. #>
    param([Parameter(Mandatory)][System.Security.Cryptography.RandomNumberGenerator]$Rng,
          [Parameter(Mandatory)][ValidateRange(1, 256)][int]$Max)
    $limit = 256 - (256 % $Max)
    $byte  = New-Object byte[] 1
    do { $Rng.GetBytes($byte) } while ($byte[0] -ge $limit)
    return [int]($byte[0] % $Max)
}

function Get-RandomPassword {
    <# Mot de passe aléatoire : au moins une majuscule, une minuscule, un chiffre et un symbole,
       sans caractère ambigu (0/O, 1/l/I). #>
    [CmdletBinding()]
    [OutputType([string])]
    param([ValidateRange(12, 128)][int]$Length = 16)
    $sets = 'ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnpqrstuvwxyz', '23456789', '!#%*+-=?@_'
    $all  = -join $sets
    $rng  = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $chars = New-Object System.Collections.Generic.List[char]
        foreach ($set in $sets) { $chars.Add($set[(Get-RandomIndex -Rng $rng -Max $set.Length)]) }
        while ($chars.Count -lt $Length) { $chars.Add($all[(Get-RandomIndex -Rng $rng -Max $all.Length)]) }
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {          # mélange de Fisher-Yates
            $j = Get-RandomIndex -Rng $rng -Max ($i + 1)
            $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
        }
        return -join $chars
    }
    finally { $rng.Dispose() }
}

function ConvertTo-SecureText {
    <# Chaîne -> SecureString, sans ConvertTo-SecureString -AsPlainText. #>
    [OutputType([securestring])]
    param([Parameter(Mandatory)][string]$Text)
    $secure = New-Object System.Security.SecureString
    foreach ($char in $Text.ToCharArray()) { $secure.AppendChar($char) }
    $secure.MakeReadOnly()
    return $secure
}

function ConvertTo-PlainAscii {
    <# Retire les accents et tout caractère hors a-z, 0-9, point et tiret. #>
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder
    foreach ($char in $normalized.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$builder.Append($char) }
    }
    return ($builder.ToString().ToLowerInvariant() -replace 'œ', 'oe' -replace 'æ', 'ae' -replace '[^a-z0-9.-]', '')
}

function ConvertTo-SamAccountName {
    <# « Jean-Noël », « Du Pont » -> « j.dupont » (20 caractères au plus). #>
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$GivenName, [Parameter(Mandatory)][string]$Surname)
    $first = ConvertTo-PlainAscii -Text $GivenName
    $last  = (ConvertTo-PlainAscii -Text $Surname) -replace '[.-]', ''
    if (-not $first -or -not $last) { throw "Impossible de construire un identifiant à partir de '$GivenName' '$Surname'." }
    $sam = '{0}.{1}' -f $first.Substring(0, 1), $last
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0, 20) }
    return $sam
}

function ConvertTo-FilterValue {
    <# Échappe une valeur placée entre apostrophes dans un filtre Active Directory. #>
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return $Value.Replace("'", "''")
}

function ConvertFrom-FileTime {
    <# Horodatage AD (FILETIME) -> date locale ; $null pour 0, vide ou « jamais ». #>
    param($Value)
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    $ticks = [long]$Value
    if ($ticks -le 0 -or $ticks -eq [long]::MaxValue) { return $null }
    return [datetime]::FromFileTime($ticks)
}

function Export-Report {
    <# Renvoie les objets reçus et, si -CsvPath est fourni, les écrit aussi en CSV
       (séparateur « ; », UTF-8, lisible directement par Excel en français). #>
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline)]$InputObject, [string]$CsvPath)
    begin   { $all = New-Object System.Collections.Generic.List[object] }
    process { if ($null -ne $InputObject) { $all.Add($InputObject) } }
    end {
        if ($CsvPath) {
            $dir = Split-Path -Parent $CsvPath
            if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false -Confirm:$false | Out-Null }
            $all | Export-Csv -LiteralPath $CsvPath -NoTypeInformation -Encoding UTF8 -Delimiter ';' -WhatIf:$false -Confirm:$false
            Write-Verbose "$($all.Count) ligne(s) écrite(s) dans $CsvPath"
        }
        $all
    }
}
