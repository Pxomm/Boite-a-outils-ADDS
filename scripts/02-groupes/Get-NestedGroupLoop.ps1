<#
.SYNOPSIS
    Détecte les imbrications circulaires de groupes (A membre de B, B membre de A, directement ou non).

.DESCRIPTION
    Une boucle d'imbrication ne casse pas Active Directory mais perturbe certaines applications
    et rend les droits illisibles. Le script charge une fois le graphe « groupe -> groupes
    parents » puis recherche les cycles. Chaque boucle est renvoyée une seule fois.

.EXAMPLE
    .\Get-NestedGroupLoop.ps1
#>
[CmdletBinding()]
param([string]$SearchBase, [string]$CsvPath)

. "$PSScriptRoot/../../lib/Communs.ps1"
Initialize-ADToolbox

$query = @{ Filter = '*'; Properties = 'MemberOf' }
if ($SearchBase) { $query.SearchBase = $SearchBase }
$parents = @{}; $names = @{}
foreach ($group in Get-ADGroup @query) { $parents[$group.DistinguishedName] = @($group.MemberOf); $names[$group.DistinguishedName] = $group.Name }

$state = @{}                                   # 1 = en cours de visite, 2 = terminé
$seen  = New-Object System.Collections.Generic.HashSet[string]
$loops = New-Object System.Collections.Generic.List[object]
foreach ($start in $parents.Keys) {
    if ($state[$start]) { continue }
    # Parcours en profondeur itératif : pile de (nœud, index du prochain parent)
    $path  = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Stack
    $stack.Push(@($start, 0)); $path.Add($start); $state[$start] = 1
    while ($stack.Count -gt 0) {
        $frame = $stack.Pop(); $node = $frame[0]; $index = $frame[1]
        $next = @($parents[$node])
        if ($index -lt $next.Count) {
            $stack.Push(@($node, ($index + 1)))
            $parent = $next[$index]
            if (-not $parents.ContainsKey($parent)) { continue }          # hors périmètre
            if ($state[$parent] -eq 1) {
                $cycle = @($path.GetRange($path.IndexOf($parent), $path.Count - $path.IndexOf($parent)))
                $key = (@($cycle | Sort-Object) -join '|')
                if ($seen.Add($key)) { $loops.Add([pscustomobject]@{ GroupCount = $cycle.Count; Loop = (@($cycle | ForEach-Object { $names[$_] }) + $names[$parent]) -join ' -> ' }) }
            }
            elseif (-not $state[$parent]) { $state[$parent] = 1; $path.Add($parent); $stack.Push(@($parent, 0)) }
        }
        else { $state[$node] = 2; $path.RemoveAt($path.Count - 1) }
    }
}
$loops | Export-Report -CsvPath $CsvPath
