<#
  生成技能索引：扫描技能包，输出一份紧凑的 Markdown 目录。
  用法：
    .\make-index.ps1 -PackPath C:\path\to\skills-pack -OutFile .\SKILLS-INDEX.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PackPath,
    [string]$OutFile = 'SKILLS-INDEX.md',
    [string[]]$Include = @()
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PackPath)) { throw "找不到技能包: $PackPath" }

function Get-FrontmatterField([string[]]$lines, [string]$field) {
    $value = ''
    $capture = $false
    foreach ($line in $lines) {
        if (-not $capture) {
            if ($line -match ('^' + [regex]::Escape($field) + ':\s*(.*)$')) {
                $rest = $matches[1].Trim()
                if ($rest -match '^[>|][+-]?$') { $capture = $true; continue }
                $value = $rest
                $capture = $true
                continue
            }
        } else {
            if ($line -match '^\S') { break }
            if ($line -match '^---') { break }
            $trim = $line.Trim()
            if ($trim) { $value = ($value + ' ' + $trim).Trim() }
        }
    }
    if ($value.StartsWith('"') -and $value.EndsWith('"') -and $value.Length -gt 1) { $value = $value.Substring(1, $value.Length - 2) }
    if ($value.StartsWith("'") -and $value.EndsWith("'") -and $value.Length -gt 1) { $value = $value.Substring(1, $value.Length - 2) }
    return $value
}

$dirs = Get-ChildItem -LiteralPath $PackPath -Directory | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')
}
if ($Include.Count) { $dirs = $dirs | Where-Object { $Include -contains $_.Name } }

$rows = foreach ($d in ($dirs | Sort-Object Name)) {
    $file = Join-Path $d.FullName 'SKILL.md'
    $lines = Get-Content -LiteralPath $file -TotalCount 60 -Encoding UTF8
    $name = Get-FrontmatterField $lines 'name'
    $desc = Get-FrontmatterField $lines 'description'
    if (-not $name) { $name = $d.Name }
    $desc = $desc -replace '\|', '／'
    if ($desc.Length -gt 200) { $desc = $desc.Substring(0, 197) + '...' }
    [pscustomobject]@{ Name = $name; Desc = $desc; Path = $file }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# 技能索引')
[void]$sb.AppendLine()
[void]$sb.AppendLine("> 由 ``make-index.ps1`` 生成 · 共 $($rows.Count) 条 · 生成时间 $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
[void]$sb.AppendLine('> 格式：`- **技能名** | 一句话描述 | SKILL.md 绝对路径`')
[void]$sb.AppendLine('> 用法：先按关键词定位，再打开对应 SKILL.md 读正文；不要一次全部加载。')
[void]$sb.AppendLine()
foreach ($r in $rows) {
    [void]$sb.AppendLine("- **$($r.Name)** | $($r.Desc) | ``$($r.Path)``")
}

if ([IO.Path]::IsPathRooted($OutFile)) { $full = [IO.Path]::GetFullPath($OutFile) }
else { $full = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutFile)) }
[IO.File]::WriteAllText($full, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "索引已生成: $full（$($rows.Count) 条）"