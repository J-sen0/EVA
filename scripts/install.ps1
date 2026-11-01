<#
  EVA 安装脚本：把一个技能包挂成「精选视图」，并生成 dsh 的 profile 补丁。

  最常用：
    .\install.ps1 -SkillsPack C:\path\to\skills-pack -Persona eva
    .\install.ps1 -SkillsPack C:\path\to\skills-pack -IncludeFile .\examples\curated.txt
    .\install.ps1 -SkillsPack C:\path\to\skills-pack -Include skill-a,skill-b
    .\install.ps1 -Uninstall

  说明：
  - 技能目录用「目录联接 / 符号链接」指向原包，不复制内容；
  - 生成 cordis.patch.yml（已被 .gitignore 忽略，含本机路径）；
  - 重复运行是安全的：会先清掉上次由本脚本创建的条目再重建。
#>
[CmdletBinding()]
param(
    [string]$SkillsPack = '',
    [string]$OutDir = '',
    [string]$Persona = 'eva',
    [string]$IncludeFile = '',
    [string[]]$Include = @(),
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $env:USERPROFILE '.eva\skills-core' }
$IndexPath = Join-Path (Split-Path -Parent $OutDir) 'SKILLS-INDEX.md'
$ManagedFile = Join-Path $OutDir '.managed.json'
$IsWindowsHost = ($env:OS -eq 'Windows_NT')

function Read-Managed {
    $names = @()
    if (Test-Path -LiteralPath $ManagedFile) {
        try { $names = @(Get-Content -LiteralPath $ManagedFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { $names = @() }
    }
    foreach ($x in $names) { if ($x) { $x } }   # 逐条输出，保证 foreach 拿到的是字符串
}

function Remove-Entry([string]$Path, [string]$Root) {
    $full = [IO.Path]::GetFullPath($Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "拒绝删除越界路径: $full"
    }
    if (-not (Test-Path -LiteralPath $full)) { return }
    $item = Get-Item -LiteralPath $full -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        [IO.Directory]::Delete($full, $false)
    } else {
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}

function New-Link([string]$Link, [string]$Target) {
    if ($IsWindowsHost) {
        New-Item -ItemType Junction -Path $Link -Target $Target | Out-Null
    } else {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target | Out-Null
    }
}

if ($Uninstall) {
    foreach ($n in Read-Managed) { Remove-Entry (Join-Path $OutDir $n) $OutDir }
    Remove-Entry (Join-Path $OutDir 'eva-protocol') $OutDir
    if (Test-Path -LiteralPath $ManagedFile) { Remove-Item -LiteralPath $ManagedFile -Force }
    if ((Test-Path -LiteralPath $OutDir) -and -not (Get-ChildItem -LiteralPath $OutDir -Force)) {
        [IO.Directory]::Delete($OutDir, $false)
    }
    if (Test-Path -LiteralPath $IndexPath) { Remove-Item -LiteralPath $IndexPath -Force }
    Write-Host '已移除技能视图。'
    Write-Host '下一步：从 profile 移除 dsh-eva 并重启 dsh。'
    return
}

if (-not $SkillsPack) { throw '缺少 -SkillsPack（技能包目录）' }
if (-not (Test-Path -LiteralPath $SkillsPack)) { throw "找不到技能包: $SkillsPack" }
$SkillsPack = (Resolve-Path -LiteralPath $SkillsPack).Path

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

# 清理上次留下的条目
foreach ($n in Read-Managed) { Remove-Entry (Join-Path $OutDir $n) $OutDir }

# 决定要挂哪些技能
$all = Get-ChildItem -LiteralPath $SkillsPack -Directory | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md')
} | Select-Object -ExpandProperty Name

$wanted = $all
if ($IncludeFile) {
    if (-not (Test-Path -LiteralPath $IncludeFile)) { throw "找不到清单文件: $IncludeFile" }
    $wanted = Get-Content -LiteralPath $IncludeFile -Encoding UTF8 |
        ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
}
if ($Include.Count) { $wanted = $Include }

$wanted = @($wanted | Sort-Object -Unique)
$linked = New-Object System.Collections.ArrayList
$missing = @()
foreach ($n in $wanted) {
    $target = Join-Path $SkillsPack $n
    if (-not (Test-Path -LiteralPath $target)) { $missing += $n; continue }
    $link = Join-Path $OutDir $n
    Remove-Entry $link $OutDir
    New-Link $link $target
    [void]$linked.Add($n)
}

# 拷贝协议入口技能，并把索引路径写进去
$protoSrc = Join-Path $RepoRoot 'skills\eva-protocol'
$protoDst = Join-Path $OutDir 'eva-protocol'
if (Test-Path -LiteralPath $protoSrc) {
    Remove-Entry $protoDst $OutDir
    Copy-Item -LiteralPath $protoSrc -Destination $protoDst -Recurse -Force
    $skillFile = Join-Path $protoDst 'SKILL.md'
    $txt = [IO.File]::ReadAllText($skillFile, [Text.Encoding]::UTF8)
    $txt = $txt.Replace('{{INDEX_PATH}}', $IndexPath)
    [IO.File]::WriteAllText($skillFile, $txt, (New-Object System.Text.UTF8Encoding($false)))
}

# 记录受管条目
$linked | ConvertTo-Json -Compress | Set-Content -LiteralPath $ManagedFile -Encoding UTF8

# 生成索引
& (Join-Path $PSScriptRoot 'make-index.ps1') -PackPath $SkillsPack -OutFile $IndexPath -Include $linked

# 渲染补丁
$personaFile = $Persona
if (-not (Test-Path -LiteralPath $personaFile)) {
    $personaFile = Join-Path $RepoRoot ("personas\{0}.md" -f $Persona)
}
if (-not (Test-Path -LiteralPath $personaFile)) { throw "找不到人格文件: $Persona" }
$personaText = [IO.File]::ReadAllText($personaFile, [Text.Encoding]::UTF8)
# 去掉 Markdown 标题行，正文缩进 6 空格塞进 YAML 块标量
$body = ($personaText -split "`r?`n" | Where-Object { $_ -notmatch '^#\s' }) -join "`n"
$body = $body.Trim()
$indented = ($body -split "`n" | ForEach-Object { if ($_.Trim()) { '      ' + $_ } else { '' } }) -join "`n"

$tpl = [IO.File]::ReadAllText((Join-Path $RepoRoot 'template\cordis.patch.tpl.yml'), [Text.Encoding]::UTF8)
$yaml = $tpl.Replace('{{INCLUDE_HARNESS_IDENTITY}}', 'false')
$yaml = $yaml.Replace('{{PERSONA_BLOCK}}', $indented)
$yaml = $yaml.Replace('{{SKILLS_DIR}}', $OutDir.Replace("'", "''"))
$outYml = Join-Path $RepoRoot 'cordis.patch.yml'
[IO.File]::WriteAllText($outYml, $yaml, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ""
Write-Host "技能视图: $OutDir（$($linked.Count) 个）" -ForegroundColor Green
Write-Host "技能索引: $IndexPath" -ForegroundColor Green
Write-Host "人格:     $personaFile" -ForegroundColor Green
Write-Host "补丁:     $outYml" -ForegroundColor Green
if ($missing.Count) { Write-Host ("跳过（不存在）: " + ($missing -join ', ')) -ForegroundColor Yellow }
Write-Host ""
Write-Host '下一步：把本仓库装进 dsh 的 profile，然后重启 dsh：' -ForegroundColor Cyan
Write-Host "  dsh plugin --profile desktop add file:$RepoRoot"