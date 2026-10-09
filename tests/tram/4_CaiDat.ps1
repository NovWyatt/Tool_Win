# Thử Get-EmptySubmodules, Install-Submodule (không có git, tải .zip giả) và Get-BlockedFiles của hub\CaiDat.ps1.
# Chỉ nạp các hàm của CaiDat.ps1 (không chạy phần chính), làm việc trong một thư mục gốc giả.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$here = $TestRoot
$src = "$HubDir\CaiDat.ps1"
. "$HubDir\lib\Common.ps1"
. "$HubDir\lib\AnToan.ps1"
$ast = [Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
foreach ($f in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($f.Extent.Text))
}
$script:SkipDirs = @('.venv', 'venv', 'models', '.git', 'node_modules', 'ket_qua', 'du-lieu', '__pycache__')

$RootDir = Join-Path $here 'goc'
New-Item -ItemType Directory -Force -Path (Join-Path $RootDir 'tools\mdf2sql') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RootDir 'tools\khac') | Out-Null
[IO.File]::WriteAllText((Join-Path $RootDir '.gitmodules'), "[submodule `"tools/mdf2sql`"]`n`tpath = tools/mdf2sql`n`turl = https://github.com/NovWyatt/mdf2sql.git`n")

# .zip giả giống GitHub: một thư mục gốc mdf2sql-<sha>\ chứa mã
$zipSrc = Join-Path $here 'zipsrc\mdf2sql-abc123'
New-Item -ItemType Directory -Force -Path $zipSrc | Out-Null
[IO.File]::WriteAllText((Join-Path $zipSrc 'tool.json'), '{ "id": "mdf2sql" }')
New-Item -ItemType Directory -Force -Path (Join-Path $zipSrc 'mdf2sql') | Out-Null
[IO.File]::WriteAllText((Join-Path $zipSrc 'mdf2sql\__init__.py'), '')
$fakeZip = Join-Path $here 'gia.zip'
Compress-Archive -Path $zipSrc -DestinationPath $fakeZip

$script:urls = @()
function Invoke-WebRequest { param($Uri, $OutFile, [switch]$UseBasicParsing) $script:urls += $Uri; Copy-Item -LiteralPath $fakeZip -Destination $OutFile }
function Get-Command { param($Name, $ErrorAction) if ($Name -eq 'git.exe') { return $null } Microsoft.PowerShell.Core\Get-Command $Name -ErrorAction $ErrorAction }

Write-Host '== submodule trống, tải .zip khi không có git'
$empty = @(Get-EmptySubmodules)
Check ($empty.Count -eq 1 -and $empty[0].path -eq 'tools/mdf2sql') "thấy 1 submodule trống: $($empty.Count) ($($empty | ForEach-Object { $_.path }))"
if ($empty.Count) {
    $ok = Install-Submodule $empty[0]
    Check ($ok -eq $true) 'Install-Submodule trả True'
    Check (@($script:urls).Count -eq 1 -and $script:urls[0] -like 'https://github.com/NovWyatt/mdf2sql/*.zip') "tải đúng nơi: $($script:urls -join ', ')"
    Check ((Test-Path (Join-Path $RootDir 'tools\mdf2sql\tool.json')) -and (Test-Path (Join-Path $RootDir 'tools\mdf2sql\mdf2sql\__init__.py'))) 'giải nén vào tools\mdf2sql, bỏ thư mục gốc mdf2sql-<sha>'
    Check (-not (Test-Path (Join-Path $RootDir 'tools\mdf2sql\mdf2sql-abc123'))) 'không để lại thư mục mdf2sql-<sha>'
}
Check (@(Get-EmptySubmodules).Count -eq 0) 'cài xong không còn submodule trống'

Write-Host '== dấu tải từ Internet (Zone.Identifier)'
$f1 = Join-Path $RootDir 'TramTool.bat'; [IO.File]::WriteAllText($f1, '@echo off')
$f2 = Join-Path $RootDir 'tools\khac\a.ps1'; [IO.File]::WriteAllText($f2, '1')
$f3 = Join-Path $RootDir 'tools\khac\.venv\Scripts\python.exe'; New-Item -ItemType Directory -Force -Path (Split-Path $f3) | Out-Null; [IO.File]::WriteAllText($f3, 'x')
foreach ($f in $f1, $f2, $f3) { Set-Content -LiteralPath $f -Stream 'Zone.Identifier' -Value "[ZoneTransfer]`r`nZoneId=3" }
$b = @(Get-BlockedFiles $RootDir)
$rel = @($b | ForEach-Object { $_.Substring($RootDir.Length) } | Sort-Object)
Check (($rel -join '|') -eq '\tools\khac\a.ps1|\TramTool.bat') "thấy 2 file bị đánh dấu, bỏ qua .venv: $($rel -join ', ')"
foreach ($f in $b) { Unblock-File -LiteralPath $f }
Check (@(Get-BlockedFiles $RootDir).Count -eq 0) 'sau Unblock-File không còn file bị đánh dấu'

Complete-Test
