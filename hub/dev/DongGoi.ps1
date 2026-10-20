<#
  Đóng gói Trạm Tool bản portable: một file .zip, giải nén ra là chạy (bấm TramTool.exe), không cài Python, thư viện
  hay LibreDWG trên máy dùng.
  Trong gói:
    - mọi file git đang theo dõi (kể cả submodule mdf2sql), trừ bài thử, hub\dev, bản lưu cũ (LuuTru); docs\ giữ lại
      (trang lộ trình của trạm đọc docs\PHAN-TICH-NANG-CAP.md);
    - runtime\python: Python 3.12.10 (gói NuGet chính thức của Python Software Foundation, không cần cài; mã SHA-256
      ghim dưới đây) kèm tkinter lấy từ Python 3.12.10 đã cài trên máy dựng (hộp thoại chọn file của mdf2sql);
    - .venv dựng sẵn của DWG sang PDF (ezdxf, PyMuPDF) và Khôi phục .mdf (pyodbc), LibreDWG 0.14;
    - TramTool.exe (dịch từ hub\dev\TramToolExe.cs bằng csc.exe của Windows), HUONG-DAN-PORTABLE.txt, portable.json.
  Không có trong gói chính:
    - Ghi âm sang Word: thư viện (khoảng 2 GB) và mô hình (khoảng 3 GB). Nút Cài trong trạm tải về lần đầu (đã dùng
      Python mang theo, không cần winget); -KemGhiAm làm thêm gói riêng TramTool-GhiAm-*.zip để giải nén chồng lên.
    - SQL Server và ODBC Driver của Khôi phục .mdf: phải cài vào Windows (cần quyền Admin), trạm có nút Cài.
  Tham số:
    -Ra <thư mục>  nơi để gói, thư mục dựng (dung\) và bộ nhớ tải về (cache\). Mặc định D:\Repo\TramTool-Portable.
    -KemGhiAm      làm thêm gói Ghi âm sang Word (thư viện + mô hình faster-whisper-large-v3).
    -KhongNen      chỉ dựng thư mục dung\TramTool, không nén .zip.
    -ChayThu       chỉ in kế hoạch, không tải, không ghi gì.
    -PythonGoi <file .nupkg>  dùng gói Python có sẵn (bài thử: gói giả, bỏ kiểm SHA-256).
    -KhongCaiCongCu  không dựng .venv, không tải LibreDWG (bài thử).
  Cần mạng lần đầu (Python, thư viện, LibreDWG); các lần sau dùng lại cache\. Mã thoát: 0 xong, 1 lỗi.
#>
[CmdletBinding()]
param(
    [string]$Ra = 'D:\Repo\TramTool-Portable',
    [switch]$KemGhiAm,
    [switch]$KhongNen,
    [switch]$ChayThu,
    [string]$PythonGoi = '',
    [switch]$KhongCaiCongCu
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$RepoDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$PyVersion = '3.12.10'
$PyUrl = "https://www.nuget.org/api/v2/package/python/$PyVersion"
$PySha256 = '0EB85C2DFCCCCF1B17352DE4C397F69194035B7D37149EACC16F1147D93DE3B8'   # khớp SHA-512 trong danh mục NuGet
$Utf8Bom = New-Object Text.UTF8Encoding $true
$Utf8 = New-Object Text.UTF8Encoding $false

function Buoc([string]$t) { Write-Host ''; Write-Host "== $t" -ForegroundColor Cyan }
function Ok([string]$t) { Write-Host "  [OK] $t" -ForegroundColor Green }
function Info([string]$t) { Write-Host "  [i] $t" -ForegroundColor Gray }
function Canh([string]$t) { Write-Host "  [!] $t" -ForegroundColor Yellow }
function Loi([string]$t) { Write-Host "  [LOI] $t" -ForegroundColor Red; exit 1 }
function Format-MB([double]$b) { return ('{0:N0} MB' -f ($b / 1MB)) }
function Get-DirSize([string]$d) { return [double](@(Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) }

# Đường dẫn git (dấu /) nào không vào gói.
function Test-BoQua([string]$p) {
    foreach ($pre in 'tests/', 'hub/dev/', 'tools/mdf2sql/tests/') { if ($p.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    if ($p -in '.gitattributes', '.gitignore', '.gitmodules') { return $true }
    if ($p -match '(^|/)LuuTru/' -or $p -match '(^|/)\.git') { return $true }
    return $false
}

function Invoke-Native([string]$Exe, [string[]]$Argv, [string]$Viec) {
    & $Exe @Argv
    if ($LASTEXITCODE -ne 0) { Loi "$Viec không thành công (mã $LASTEXITCODE)." }
}

$hubText = [IO.File]::ReadAllText((Join-Path $RepoDir 'hub\TramTool.ps1'), [Text.Encoding]::UTF8)
$hubVer = if ($hubText -match "\`$HubVersion = '([^']+)'") { $Matches[1] } else { '0' }
$Ten = "TramTool-Portable-$hubVer-$(Get-Date -Format 'yyyyMMdd')"
$Ra = [IO.Path]::GetFullPath($Ra)
$Dung = Join-Path $Ra 'dung'
$Stage = Join-Path $Dung 'TramTool'
$Cache = Join-Path $Ra 'cache'
$Zip = Join-Path $Ra "$Ten.zip"
$ZipGhiAm = Join-Path $Ra "TramTool-GhiAm-$hubVer-$(Get-Date -Format 'yyyyMMdd').zip"

Write-Host "Trạm Tool: đóng gói bản portable $Ten" -ForegroundColor Cyan
Info "Từ: $RepoDir"
Info "Ra: $Ra"
if ($Ra.StartsWith($RepoDir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or $Ra -ieq $RepoDir) { Loi 'Thư mục -Ra nằm trong repo: gói sẽ lẫn vào git. Chọn chỗ khác.' }
if ([IO.Path]::GetPathRoot($Ra).TrimEnd('\') -ieq $Ra.TrimEnd('\')) { Loi 'Thư mục -Ra không được là gốc ổ đĩa.' }

$git = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $git) { Loi 'Cần git để lấy danh sách file của repo.' }
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { Loi "Không thấy $csc (.NET Framework 4) để dịch TramTool.exe." }

$files = @((& $git.Source -C $RepoDir -c core.quotepath=false ls-files -z --recurse-submodules) -split "`0" | Where-Object { $_ -and -not (Test-BoQua $_) })
if ($LASTEXITCODE -ne 0 -or -not $files.Count) { Loi 'git ls-files không trả danh sách file.' }
$dirty = @(& $git.Source -C $RepoDir status --porcelain --untracked-files=no)
if ($dirty.Count) { Canh "Repo có $($dirty.Count) file sửa chưa commit: gói lấy bản đang có trên đĩa." }

# Python đã cài trên máy dựng, đúng bản $PyVersion, để lấy tkinter.
$tkSrc = ''
foreach ($c in @((Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312'), "$env:ProgramFiles\Python312")) {
    if (@('_tkinter.pyd', 'tcl86t.dll', 'tk86t.dll', 'zlib1.dll' | Where-Object { -not (Test-Path -LiteralPath (Join-Path $c "DLLs\$_")) }).Count) { continue }
    $v = & (Join-Path $c 'python.exe') -c 'import platform; print(platform.python_version())' 2>$null
    if ("$v".Trim() -eq $PyVersion) { $tkSrc = $c; break }
}

Buoc 'Kế hoạch'
Info "$($files.Count) file của repo (bỏ tests\, hub\dev\, LuuTru\)"
Info "Python $PyVersion từ $(if ($PythonGoi) { $PythonGoi } else { $PyUrl })"
if ($tkSrc) { Info "tkinter từ $tkSrc" } else { Canh "Không có Python $PyVersion cài sẵn có tkinter: hộp thoại chọn file của mdf2sql sẽ không mở được (vẫn gõ đường dẫn được)." }
if ($KhongCaiCongCu) { Info 'Không dựng .venv, không tải LibreDWG (-KhongCaiCongCu).' }
else { Info '.venv: DWG sang PDF, Khôi phục .mdf; LibreDWG 0.14' }
if ($KemGhiAm) { Info "Gói thêm Ghi âm sang Word: $ZipGhiAm" }
Info $(if ($KhongNen) { "Thư mục: $Stage (không nén)" } else { "Gói: $Zip" })
if ($ChayThu) { Write-Host ''; Info 'Chạy thử: dừng ở đây, chưa tải, chưa ghi gì.'; exit 0 }

# ------------------------------------------------------------------ chép file của repo
Buoc 'Chép file của repo'
if (Test-Path -LiteralPath $Dung) { Remove-Item -LiteralPath $Dung -Recurse -Force }
New-Item -ItemType Directory -Path $Stage -Force | Out-Null
New-Item -ItemType Directory -Path $Cache -Force | Out-Null
foreach ($f in $files) {
    $src = Join-Path $RepoDir ($f -replace '/', '\')
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }   # file đã xoá trên đĩa mà chưa commit
    $dst = Join-Path $Stage ($f -replace '/', '\')
    $dd = Split-Path $dst -Parent
    if (-not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
    [IO.File]::Copy($src, $dst, $true)
}
Ok "$($files.Count) file, $(Format-MB (Get-DirSize $Stage))"

# ------------------------------------------------------------------ Python mang theo
Buoc "Python $PyVersion"
$nupkg = $PythonGoi
if (-not $nupkg) {
    $nupkg = Join-Path $Cache "python.$PyVersion.nupkg"
    if (-not (Test-Path -LiteralPath $nupkg)) {
        Info "Tải $PyUrl"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $PyUrl -OutFile "$nupkg.tai" -UseBasicParsing
        Move-Item -LiteralPath "$nupkg.tai" -Destination $nupkg -Force
    }
    $h = (Get-FileHash -LiteralPath $nupkg -Algorithm SHA256).Hash
    if ($h -ne $PySha256) { Remove-Item -LiteralPath $nupkg -Force; Loi "Gói Python sai mã kiểm tra (SHA-256 $h), đã xoá." }
}
$pyDir = Join-Path $Stage 'runtime\python'
$z = [IO.Compression.ZipFile]::OpenRead($nupkg)
try {
    foreach ($e in $z.Entries) {
        if (-not $e.FullName.StartsWith('tools/') -or -not $e.Name) { continue }
        $rel = $e.FullName.Substring(6) -replace '/', '\'
        if ($rel -match '(^|\\)\.\.(\\|$)') { Loi "Gói Python có đường dẫn lạ: $($e.FullName)" }
        $d = Join-Path $pyDir $rel
        New-Item -ItemType Directory -Path (Split-Path $d -Parent) -Force | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $d, $true)
    }
} finally { $z.Dispose() }
$py = Join-Path $pyDir 'python.exe'
if (-not (Test-Path -LiteralPath $py)) { Loi 'Gói Python không có python.exe.' }
if ($tkSrc) {
    foreach ($d in 'DLLs', 'Lib') { New-Item -ItemType Directory -Path (Join-Path $pyDir $d) -Force | Out-Null }
    # tcl86t.dll cần zlib1.dll (gói NuGet không có).
    foreach ($n in '_tkinter.pyd', 'tcl86t.dll', 'tk86t.dll', 'zlib1.dll') { Copy-Item -LiteralPath (Join-Path $tkSrc "DLLs\$n") -Destination (Join-Path $pyDir 'DLLs') -Force }
    Copy-Item -LiteralPath (Join-Path $tkSrc 'tcl') -Destination $pyDir -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $tkSrc 'Lib\tkinter') -Destination (Join-Path $pyDir 'Lib') -Recurse -Force
    Get-ChildItem -LiteralPath $pyDir -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force
}
if (-not $PythonGoi) {
    $out = & $py -c 'import sys, venv, ensurepip; print(sys.version.split()[0])'
    if ($LASTEXITCODE -ne 0 -or "$out".Trim() -ne $PyVersion) { Loi "Python mang theo không chạy được ($out)." }
    if ($tkSrc) { & $py -c 'import tkinter, _tkinter' ; if ($LASTEXITCODE -ne 0) { Loi 'tkinter chép sang không nạp được.' } }
}
Ok "runtime\python: $(Format-MB (Get-DirSize $pyDir))$(if ($tkSrc) { ', có tkinter' })"

# ------------------------------------------------------------------ môi trường của từng công cụ
$envBak = @{}
foreach ($k in 'TRAMTOOL_PYTHON', 'PATH', 'PIP_CACHE_DIR', 'PYTHONUTF8', 'PIP_DISABLE_PIP_VERSION_CHECK') { $envBak[$k] = [Environment]::GetEnvironmentVariable($k) }
function Restore-Env { foreach ($k in $envBak.Keys) { [Environment]::SetEnvironmentVariable($k, $envBak[$k]) } }

function Test-Venv([string]$ToolDir, [string[]]$Modules) {
    $vp = Join-Path $ToolDir '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $vp)) { return $false }
    foreach ($m in $Modules) { & $vp -c "import $m" 2>$null; if ($LASTEXITCODE -ne 0) { return $false } }
    $base = & $vp -c 'import sys; print(sys.base_prefix)'
    return ([IO.Path]::GetFullPath("$base".Trim()) -ieq [IO.Path]::GetFullPath($pyDir))
}

if (-not $KhongCaiCongCu) {
    $env:TRAMTOOL_PYTHON = $py
    $env:PATH = "$pyDir;$pyDir\Scripts;$($envBak['PATH'])"
    $env:PIP_CACHE_DIR = Join-Path $Cache 'pip'
    $env:PYTHONUTF8 = '1'
    $env:PIP_DISABLE_PIP_VERSION_CHECK = '1'
    try {
        Buoc 'DWG sang PDF: .venv và LibreDWG'
        $dwg = Join-Path $Stage 'tools\dwg2pdf'
        $libCache = Join-Path $Cache 'libredwg'
        if (Test-Path -LiteralPath (Join-Path $libCache 'dwg2dxf.exe')) {
            New-Item -ItemType Directory -Path (Join-Path $dwg 'bin') -Force | Out-Null
            Copy-Item -LiteralPath $libCache -Destination (Join-Path $dwg 'bin') -Recurse -Force
            Info 'LibreDWG lấy từ cache\libredwg.'
        }
        Invoke-Native 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $dwg 'CAI_DAT.ps1')) 'Cài DWG sang PDF'
        if (-not (Test-Venv $dwg @('ezdxf', 'pymupdf', 'olefile', 'PIL'))) { Loi '.venv của DWG sang PDF không nạp được thư viện hoặc không dùng Python mang theo.' }
        if (-not (Test-Path -LiteralPath (Join-Path $libCache 'dwg2dxf.exe'))) { Copy-Item -LiteralPath (Join-Path $dwg 'bin\libredwg') -Destination $libCache -Recurse -Force }
        Ok "DWG sang PDF: $(Format-MB ((Get-DirSize (Join-Path $dwg '.venv')) + (Get-DirSize (Join-Path $dwg 'bin'))))"

        Buoc 'Khôi phục .mdf: .venv có pyodbc'
        $mdf = Join-Path $Stage 'tools\mdf2sql'
        Invoke-Native $py @('-m', 'venv', (Join-Path $mdf '.venv')) 'Tạo .venv của mdf2sql'
        Invoke-Native (Join-Path $mdf '.venv\Scripts\python.exe') @('-m', 'pip', 'install', '--quiet', '--only-binary=:all:', '-r', (Join-Path $mdf 'requirements.txt')) 'Cài pyodbc'
        if (-not (Test-Venv $mdf @('pyodbc'))) { Loi '.venv của mdf2sql không nạp được pyodbc.' }
        Ok "Khôi phục .mdf: $(Format-MB (Get-DirSize (Join-Path $mdf '.venv')))"

        if ($KemGhiAm) {
            Buoc 'Ghi âm sang Word: thư viện và mô hình (lâu, vài GB)'
            $ga = Join-Path $Stage 'tools\ghi-am-sang-word'
            $mSrc = Join-Path $RepoDir 'tools\ghi-am-sang-word\models\faster-whisper-large-v3'
            if ((Test-Path -LiteralPath (Join-Path $mSrc 'model.bin')) -and (Get-Item -LiteralPath (Join-Path $mSrc 'model.bin')).Length -gt 2.5GB) {
                New-Item -ItemType Directory -Path (Join-Path $ga 'models') -Force | Out-Null
                Copy-Item -LiteralPath $mSrc -Destination (Join-Path $ga 'models') -Recurse -Force
                Get-ChildItem -LiteralPath (Join-Path $ga 'models') -Recurse -Directory -Force -Filter '.cache' | Remove-Item -Recurse -Force
                Info 'Mô hình chép từ repo trên máy này (không tải lại).'
            }
            Invoke-Native 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $ga 'CAI_DAT.ps1')) 'Cài Ghi âm sang Word'
            if (-not (Test-Venv $ga @('faster_whisper', 'ctranslate2', 'docx'))) { Loi '.venv của Ghi âm sang Word không nạp được thư viện.' }
            Ok "Ghi âm sang Word: $(Format-MB ((Get-DirSize (Join-Path $ga '.venv')) + (Get-DirSize (Join-Path $ga 'models'))))"
        }
    } finally { Restore-Env }
}

# ------------------------------------------------------------------ TramTool.exe và hướng dẫn
Buoc 'TramTool.exe'
$exe = Join-Path $Stage 'TramTool.exe'
Invoke-Native $csc @('/nologo', '/target:winexe', '/codepage:65001', '/optimize+', "/out:$exe", "/win32icon:$(Join-Path $RepoDir 'hub\web\tramtool.ico')", (Join-Path $PSScriptRoot 'TramToolExe.cs')) 'Dịch TramTool.exe'
Ok "TramTool.exe ($('{0:N0}' -f (Get-Item -LiteralPath $exe).Length) byte)"

$gitRev = (& $git.Source -C $RepoDir rev-parse --short HEAD).Trim()
$info = [ordered]@{
    ten = $Ten; phienBanTram = $hubVer; git = $gitRev; dungLuc = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    python = $PyVersion; tkinter = [bool]$tkSrc; venv = @(Get-ChildItem -LiteralPath (Join-Path $Stage 'tools') -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.venv') } | ForEach-Object { $_.Name })
    ghiAm = [bool]$KemGhiAm
}
[IO.File]::WriteAllText((Join-Path $Stage 'portable.json'), ($info | ConvertTo-Json -Depth 4), $Utf8)
$huongDan = @"
TRẠM TOOL - BẢN PORTABLE ($Ten)
==============================================================================

Không cần cài. Giải nén cả thư mục TramTool vào chỗ nào cũng được (ổ D, USB...), rồi bấm đúp TramTool.exe.
Giao diện mở trong trình duyệt (Brave nếu có, không thì Edge). Trạm tự tắt sau 10 phút không mở giao diện, hoặc vào
Cài đặt > Tắt trạm.

Lần đầu bấm TramTool.exe, Windows có thể hiện "Windows protected your PC" (file chưa có chữ ký số): bấm
"More info" (Thông tin thêm) rồi "Run anyway" (Vẫn chạy).

Đã có sẵn trong gói:
  - Python $PyVersion (runtime\python) và thư viện của DWG sang PDF, Khôi phục .mdf.
  - LibreDWG để đọc bản vẽ .dwg.
  Chuyển thư mục đi chỗ khác thì bấm TramTool.exe một lần để trạm tự trỏ lại đường dẫn.

Còn phải cài thêm (trạm có nút Cài ở trang của công cụ):
  - Ghi âm sang Word: thư viện và mô hình nhận dạng tiếng nói (khoảng 5 GB, tải một lần). Có gói
    TramTool-GhiAm-*.zip thì giải nén chồng vào thư mục TramTool này là xong, không phải tải.
  - Khôi phục .mdf sang .sql: SQL Server LocalDB và ODBC Driver for SQL Server (cài vào Windows, cần quyền Admin).

Có lỗi khi mở: bấm đúp TramTool.bat để xem cửa sổ máy chủ của trạm.
"@
[IO.File]::WriteAllText((Join-Path $Stage 'HUONG-DAN-PORTABLE.txt'), ($huongDan -replace "`r?`n", "`r`n"), $Utf8Bom)

# Gói không được có dữ liệu chạy (lịch sử, kết quả, dữ liệu khách).
$bad = @(Get-ChildItem -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue | Where-Object {
        $r = $_.FullName.Substring($Stage.Length + 1)
        ($r -match '^hub\\data\\.') -or ($r -match '(^|\\)(du-lieu|ket_qua)\\.') -or ($_.Name -like 'KetQua_*.json') -or ($r -match '(^|\\)DuLieu_SaoLuu')
    })
if ($bad.Count) { Loi "Thư mục dựng có dữ liệu chạy, không đóng gói: $(($bad | Select-Object -First 3 | ForEach-Object { $_.FullName }) -join '; ')" }
Ok "Thư mục dựng: $(Format-MB (Get-DirSize $Stage)) ($Stage)"

# ------------------------------------------------------------------ nén
function New-Zip([string]$Path, [string]$Base, [scriptblock]$Chon) {
    # Tên mục dùng '/' (ZipFile.CreateFromDirectory của PowerShell 5.1 ghi '\', nhiều chương trình giải nén sai).
    $tmp = "$Path.tam"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    $fs = [IO.File]::Open($tmp, [IO.FileMode]::CreateNew)
    $n = 0
    try {
        $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create, $false, [Text.Encoding]::UTF8)
        try {
            foreach ($f in [IO.Directory]::EnumerateFiles($Base, '*', [IO.SearchOption]::AllDirectories)) {
                $rel = $f.Substring($Base.Length + 1)
                if (-not (& $Chon $rel)) { continue }
                $name = 'TramTool/' + ($rel -replace '\\', '/')
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, $f, $name, [IO.Compression.CompressionLevel]::Optimal)
                $n++
            }
        } finally { $za.Dispose() }
    } finally { $fs.Dispose() }
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    Move-Item -LiteralPath $tmp -Destination $Path
    return $n
}

if ($KhongNen) { Write-Host ''; Ok "Xong (không nén): $Stage"; exit 0 }
Buoc 'Nén'
$ghiAmRe = '^tools\\ghi-am-sang-word\\(\.venv|models)\\'
$n = New-Zip $Zip $Stage { param($r) $r -notmatch $ghiAmRe }
$hash = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash
[IO.File]::WriteAllText("$Zip.sha256.txt", "$hash  $(Split-Path $Zip -Leaf)`r`n", $Utf8)
Ok "$(Split-Path $Zip -Leaf): $n file, $(Format-MB (Get-Item -LiteralPath $Zip).Length), SHA-256 $hash"
if ($KemGhiAm) {
    $n2 = New-Zip $ZipGhiAm $Stage { param($r) $r -match $ghiAmRe }
    Ok "$(Split-Path $ZipGhiAm -Leaf): $n2 file, $(Format-MB (Get-Item -LiteralPath $ZipGhiAm).Length)"
}
Write-Host ''
Ok "Xong. Gửi file $(Split-Path $Zip -Leaf): giải nén, bấm TramTool.exe."
exit 0
