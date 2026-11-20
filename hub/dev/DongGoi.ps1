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
    - runtime\bo-cai: bộ cài cho mọi nút Cài loại winget của các công cụ (vd ODBC Driver 18 và Visual C++ Redistributable
      mà nó cần) và SQL Server LocalDB, để máy dùng cài không cần mạng (hub\lib\BoCai.ps1).
  Gói thêm (giải nén chồng vào cùng thư mục TramTool; -DayDu làm cả ba):
    - -KemUngDung: bộ cài các ứng dụng của Bộ ứng dụng văn phòng (DanhSach.json), TramTool-UngDung-*.zip.
    - -KemOffice: bộ cài mẫu Office vào tools\office\mau (mẫu tìm như công cụ Office, hoặc -MauOffice), chỉ khi mẫu
      không có khoá riêng (chỉ khoá KMS chung hoặc không khoá), TramTool-Office-*.zip.
    - -KemGhiAm: Ghi âm sang Word, thư viện (khoảng 2 GB) và mô hình (khoảng 3 GB mỗi mô hình), TramTool-GhiAm-*.zip.
  Bộ cài tải bằng 'winget download' (winget đối chiếu mã SHA-256), giữ trong cache\bo-cai; lần sau dùng lại, -LamMoiBoCai
  để tải bản mới. Bộ cài không tải được (vd mã SHA-256 không khớp) thì bỏ qua, báo ở cuối.
  Tham số:
    -Ra <thư mục>  nơi để gói, thư mục dựng (dung\) và bộ nhớ tải về (cache\). Mặc định D:\Repo\TramTool-Portable.
    -DayDu         đủ mọi thứ: -KemUngDung -KemOffice -KemGhiAm. Thư mục dung\TramTool lúc đó là bản đầy đủ: chép cả
                   thư mục sang USB, máy dùng bấm TramTool.exe.
    -KemUngDung, -KemOffice, -MauOffice <thư mục>, -KemGhiAm, -LamMoiBoCai: như trên.
    -KhongNen      chỉ dựng thư mục dung\TramTool, không nén .zip.
    -ChayThu       chỉ in kế hoạch, không tải, không ghi gì.
    -PythonGoi <file .nupkg>  dùng gói Python có sẵn (bài thử: gói giả, bỏ kiểm SHA-256).
    -KhongCaiCongCu  không dựng .venv, không tải LibreDWG, không tải bộ cài (chỉ dùng cache\bo-cai) (bài thử).
  Cần mạng lần đầu (Python, thư viện, LibreDWG, bộ cài); các lần sau dùng lại cache\. Mã thoát: 0 xong, 1 lỗi.
#>
[CmdletBinding()]
param(
    [string]$Ra = 'D:\Repo\TramTool-Portable',
    [switch]$DayDu,
    [switch]$KemUngDung,
    [switch]$KemOffice,
    [string]$MauOffice = '',
    [switch]$KemGhiAm,
    [switch]$LamMoiBoCai,
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
$ZipUngDung = Join-Path $Ra "TramTool-UngDung-$hubVer-$(Get-Date -Format 'yyyyMMdd').zip"
$ZipOffice = Join-Path $Ra "TramTool-Office-$hubVer-$(Get-Date -Format 'yyyyMMdd').zip"
if ($DayDu) { $KemUngDung = $true; $KemOffice = $true; $KemGhiAm = $true }
if ($MauOffice) { $KemOffice = $true }
$CacheBoCai = Join-Path $Cache 'bo-cai'
. (Join-Path $RepoDir 'hub\lib\BoCai.ps1')

# ------------------------------------------------------------------ bộ cài có sẵn (runtime\bo-cai)
# Mã gói winget mà các nút Cài của công cụ dùng (trừ Python: bản portable đã có Python mang theo).
$fixIds = @(foreach ($tj in @(Get-ChildItem -LiteralPath (Join-Path $RepoDir 'tools') -Filter 'tool.json' -Recurse -Depth 1 -File)) {
        try { $tm = [IO.File]::ReadAllText($tj.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { continue }
        foreach ($q in @($tm.requires)) { $w = [string]$q.fix.winget; if ($w -and $w -notmatch '^Python\.') { $w } }
    }) | Select-Object -Unique
$apps = @()
if ($KemUngDung) { $apps = @(([IO.File]::ReadAllText((Join-Path $RepoDir 'tools\bo-ung-dung\DanhSach.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json).ungDung) }
$appIds = @($apps | ForEach-Object { [string]$_.id })
$LocalDbUrl = if ([IO.File]::ReadAllText((Join-Path $RepoDir 'hub\fixes\Cai-SqlLocalDB.ps1'), [Text.Encoding]::UTF8) -match "\`$url = '(https://[^']+\.msi)'") { $Matches[1] } else { '' }

function Get-CachedDownload([string]$Id, [string]$Pin) {
    # Thư mục 'winget download' trong cache còn dùng được: một file kê khai, một bộ cài đúng mã SHA-256, đúng bản ghim.
    $d = Join-Path $CacheBoCai $Id
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { return $null }
    $y = @(Get-ChildItem -LiteralPath $d -Filter '*.yaml' -File)
    $f = @(Get-ChildItem -LiteralPath $d -File | Where-Object { $_.Extension -ne '.yaml' })
    if ($y.Count -ne 1 -or $f.Count -ne 1) { return $null }
    try { $i = ConvertFrom-WingetManifest $y[0].FullName } catch { return $null }
    if ($i.id -ne $Id -or ($Pin -and $i.phienBan -ne $Pin)) { return $null }
    if ((Get-FileHash -LiteralPath $f[0].FullName -Algorithm SHA256).Hash -ne $i.sha256) { return $null }
    $i | Add-Member -NotePropertyName Dir -NotePropertyValue $d -Force
    $i | Add-Member -NotePropertyName Ngay -NotePropertyValue $f[0].LastWriteTime -Force
    return $i
}

function Save-WingetDownload([string]$Id, [string]$Pin) {
    # winget download vào thư mục tạm rồi mới thay thư mục trong cache (lỗi giữa chừng không làm hỏng bản cũ). Ưu tiên
    # bộ cài cho cả máy (--scope machine), gói không có thì lấy bộ cài mặc định. Trả '' khi xong, không thì câu báo lỗi.
    $wg = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $wg) { return 'máy dựng không có winget' }
    $tmp = Join-Path $CacheBoCai "$Id.tai"
    $base = @('download', '--id', $Id, '-e', '--source', 'winget', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    if ($Pin) { $base += @('--version', $Pin) }
    $out = @(); $code = 1
    foreach ($scope in @(@('--scope', 'machine'), @())) {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $out = @(& $wg.Source @($base + @('-d', $tmp) + $scope) 2>&1 | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
        if ($code -eq 0) { break }
    }
    if ($code -ne 0) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        $why = @($out | Where-Object { $_.Trim() -and $_ -notmatch 'not responsible|█|▒|^\s*[-\\|/]\s*$' } | Select-Object -Last 1)
        return ('winget download mã {0}: {1}' -f $code, ($why -join ' ').Trim())
    }
    $d = Join-Path $CacheBoCai $Id
    if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
    Move-Item -LiteralPath $tmp -Destination $d
    return ''
}

function Get-OfficeMauInfo([string]$Given) {
    # Đọc mẫu Office bằng chính thư viện của công cụ Office, trong tiến trình riêng (thư viện đó có hàm trùng tên với
    # script này). Trả thư mục mẫu, từng file cấu hình (loại khoá: '' không khoá, gvlk khoá KMS chung, key khoá riêng;
    # khoá không bao giờ ra khỏi tiến trình đó), lỗi của mẫu, file khác trong thư mục gốc của mẫu.
    $code = @'
param([string]$ToolDir, [string]$Given)
$ErrorActionPreference = 'Stop'
. (Join-Path $ToolDir 'lib\Chung.ps1'); . (Join-Path $ToolDir 'lib\DocOffice.ps1')
$script:ToolDir = $ToolDir
$dir = Find-TemplateDir $Given
$o = [ordered]@{ dir = $dir; ok = $false; problems = @(); configs = @(); other = @() }
if ($dir -and (Test-Path -LiteralPath (Join-Path $dir 'setup.exe') -PathType Leaf)) {
    $o.ok = $true
    $main = Read-OfficeTemplate $dir ''
    $o.problems = @($main.Problems)
    foreach ($x in @(Get-ChildItem -LiteralPath $dir -Filter '*.xml' -File)) {
        $isCfg = $false
        try { $isCfg = (Read-OdtXml $x.FullName).DocumentElement.Name -eq 'Configuration' } catch { }
        if (-not $isCfg) { $o.other += $x.Name; continue }
        $t = Read-OfficeTemplate $dir $x.Name
        $o.configs += [ordered]@{ name = $x.Name; keyKind = [string]$t.KeyKind; products = @($t.Products | ForEach-Object { $_.Id }) }
    }
    $o.other += @(Get-ChildItem -LiteralPath $dir -Force | Where-Object { $_.Name -ne 'setup.exe' -and $_.Name -ne 'Office' -and $_.Extension -ne '.xml' } | ForEach-Object { $_.Name })
}
$o | ConvertTo-Json -Depth 4 -Compress
'@
    $f = Join-Path ([IO.Path]::GetTempPath()) ("TramTool_MauOffice_{0}.ps1" -f [guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($f, $code, $Utf8Bom)
    try {
        # PowerShell 5.1 bỏ tham số chuỗi rỗng khi gọi chương trình ngoài: chỉ truyền -Given khi có.
        $pa = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $f, '-ToolDir', (Join-Path $RepoDir 'tools\office'))
        if ($Given) { $pa += @('-Given', $Given) }
        $j = & powershell.exe @pa 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return (($j -join '') | ConvertFrom-Json)
    } catch { return $null } finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}

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
$needIds = @($fixIds) + @($apps | ForEach-Object { $_.id })
foreach ($id in $needIds) {
    $pin = [string](@($apps | Where-Object { $_.id -eq $id } | ForEach-Object { $_.phienBan }) | Select-Object -First 1)
    $c = if ($LamMoiBoCai) { $null } else { Get-CachedDownload $id $pin }
    $what = if ($c) { 'có trong cache: bản {0}, tải ngày {1:dd/MM/yyyy}' -f $c.phienBan, $c.Ngay } elseif ($KhongCaiCongCu) { 'không có trong cache, bỏ qua (-KhongCaiCongCu)' } else { 'tải bằng winget download' + $(if ($pin) { " (bản ghim $pin)" }) }
    Info "Bộ cài $id`: $what"
    if ($c -and ((Get-Date) - $c.Ngay).TotalDays -gt 30) { Canh "Bộ cài $id tải từ hơn 30 ngày trước: thêm -LamMoiBoCai để lấy bản mới." }
}
Info "Bộ cài SQL Server LocalDB: $(if (Test-Path -LiteralPath (Join-Path $CacheBoCai 'SqlLocalDB\SqlLocalDB.msi')) { 'có trong cache' } elseif ($KhongCaiCongCu) { 'bỏ qua (-KhongCaiCongCu)' } else { "tải từ $LocalDbUrl" })"
$mau = $null
if ($KemOffice) {
    $mau = Get-OfficeMauInfo $MauOffice
    if (-not $mau -or -not $mau.ok) { Canh "Không thấy bộ cài mẫu Office$(if ($MauOffice) { " ở $MauOffice" } else { ' (tools\office\mau hoặc <ổ>:\Program Files\Microsoft Office)' }): gói không có mẫu Office." }
    else {
        $priv = @($mau.configs | Where-Object { $_.keyKind -eq 'key' })
        Info "Mẫu Office: $($mau.dir) ($(Format-MB (Get-DirSize $mau.dir))), file cấu hình: $(($mau.configs | ForEach-Object { "$($_.name) ($(if ($_.keyKind -eq 'gvlk') { 'khoá KMS chung' } elseif ($_.keyKind) { 'KHOÁ RIÊNG' } else { 'không khoá' }))" }) -join ', ')"
        if ($priv.Count) { Canh "Mẫu có khoá riêng (MAK, bán lẻ) trong $(($priv | ForEach-Object { $_.name }) -join ', '): không đóng mẫu vào gói để khoá không đi theo gói. Dùng mẫu chỉ có khoá KMS chung hoặc không khoá, hoặc chép mẫu tay sang máy dùng." }
        foreach ($p in @($mau.problems)) { Canh "Mẫu Office: $p" }
        if (@($mau.other).Count) { Info "Không đóng vào gói (chỉ lấy setup.exe, file cấu hình, thư mục Office): $(@($mau.other) -join ', ')" }
    }
}
if ($KemUngDung) { Info "Gói thêm ứng dụng: $ZipUngDung" }
if ($KemOffice) { Info "Gói thêm mẫu Office: $ZipOffice" }
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
            # PhoWhisper (không bắt buộc, chỉ có khi máy dựng đã tạo): đi kèm để chọn được ngay trên máy dùng.
            $pSrc = Join-Path $RepoDir 'tools\ghi-am-sang-word\models\phowhisper-large-ct2'
            if (Test-Path -LiteralPath (Join-Path $pSrc 'model.bin')) {
                New-Item -ItemType Directory -Path (Join-Path $ga 'models') -Force | Out-Null
                Copy-Item -LiteralPath $pSrc -Destination (Join-Path $ga 'models') -Recurse -Force
                Get-ChildItem -LiteralPath (Join-Path $ga 'models') -Recurse -Directory -Force -Filter '.cache' | Remove-Item -Recurse -Force
                Info 'Mô hình PhoWhisper chép từ repo trên máy này.'
            }
            Invoke-Native 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $ga 'CAI_DAT.ps1')) 'Cài Ghi âm sang Word'
            if (-not (Test-Venv $ga @('faster_whisper', 'ctranslate2', 'docx'))) { Loi '.venv của Ghi âm sang Word không nạp được thư viện.' }
            Ok "Ghi âm sang Word: $(Format-MB ((Get-DirSize (Join-Path $ga '.venv')) + (Get-DirSize (Join-Path $ga 'models'))))"
        }
    } finally { Restore-Env }
}

# ------------------------------------------------------------------ bộ cài có sẵn (runtime\bo-cai)
Buoc 'Bộ cài có sẵn (runtime\bo-cai)'
$boCaiDir = Join-Path $Stage 'runtime\bo-cai'
New-Item -ItemType Directory -Path $CacheBoCai -Force | Out-Null
$queue = New-Object System.Collections.Queue
foreach ($id in $needIds) { $queue.Enqueue($id) }
$done = @{}; $loiBoCai = @(); $coBoCai = @()
while ($queue.Count) {
    $id = [string]$queue.Dequeue()
    if ($done.ContainsKey($id)) { continue }
    $done[$id] = $true
    $pin = [string](@($apps | Where-Object { $_.id -eq $id } | ForEach-Object { $_.phienBan }) | Select-Object -First 1)
    $c = if ($LamMoiBoCai) { $null } else { Get-CachedDownload $id $pin }
    if (-not $c -and -not $KhongCaiCongCu) {
        Info "Tải $id$(if ($pin) { " bản $pin" })..."
        $err = Save-WingetDownload $id $pin
        if (-not $err) { $c = Get-CachedDownload $id $pin; if (-not $c) { $err = 'bộ cài tải về không khớp file kê khai' } }
        if ($err) { $loiBoCai += "$id`: $err"; Canh "Không tải được $id`: $err"; continue }
    }
    if (-not $c) { Info "Bỏ qua $id (không có trong cache)."; continue }
    try { $g = New-BoCaiPackage -SourceDir $c.Dir -DestRoot $boCaiDir -Id $id }
    catch { $loiBoCai += "$id`: $($_.Exception.Message)"; Canh "Không đóng được $id`: $($_.Exception.Message)"; continue }
    $coBoCai += $id
    Ok ('{0} bản {1} ({2}{3}, {4})' -f $g.ten, $g.phienBan, $g.loai, $(if ($g.loaiTrong) { "/$($g.loaiTrong)" }), (Format-MB $g.kichThuoc))
    foreach ($d in @($g.phuThuoc)) { if (-not $done.ContainsKey($d)) { $queue.Enqueue($d) } }
}
# SQL Server LocalDB: .msi của Microsoft (không có trên winget), cùng địa chỉ với hub\fixes\Cai-SqlLocalDB.ps1.
$ldb = Join-Path $CacheBoCai 'SqlLocalDB\SqlLocalDB.msi'
if (-not (Test-Path -LiteralPath $ldb) -and -not $KhongCaiCongCu -and $LocalDbUrl) {
    Info "Tải SQL Server LocalDB: $LocalDbUrl"
    New-Item -ItemType Directory -Path (Split-Path $ldb -Parent) -Force | Out-Null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $LocalDbUrl -OutFile "$ldb.tai" -UseBasicParsing
        Move-Item -LiteralPath "$ldb.tai" -Destination $ldb -Force
    } catch { Remove-Item -LiteralPath "$ldb.tai" -Force -ErrorAction SilentlyContinue; $loiBoCai += "SqlLocalDB: $($_.Exception.Message)" }
}
if (Test-Path -LiteralPath $ldb) {
    $sig = Get-AuthenticodeSignature -LiteralPath $ldb
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        Remove-Item -LiteralPath $ldb -Force
        $loiBoCai += 'SqlLocalDB: bộ cài không có chữ ký hợp lệ của Microsoft, đã xoá khỏi cache'
    } else {
        $g = New-BoCaiFilePackage -File $ldb -DestRoot $boCaiDir -Info @{ id = 'SqlLocalDB'; ten = 'SQL Server Express LocalDB'; phienBan = '2022'; nhaPhatHanh = 'Microsoft Corporation'; loai = 'msi'; lenhIm = '/qb IACCEPTSQLLOCALDBLICENSETERMS=YES'; phamVi = 'machine'; tenCaiDat = @('Microsoft SQL Server 2022 Express LocalDB') }
        $coBoCai += 'SqlLocalDB'
        Ok "$($g.ten) ($(Format-MB $g.kichThuoc))"
    }
}
if ($coBoCai.Count) { Ok "runtime\bo-cai: $($coBoCai.Count) bộ cài, $(Format-MB (Get-DirSize $boCaiDir))" } else { Info 'Không có bộ cài nào.' }
$coUngDung = @($apps | Where-Object { $coBoCai -contains $_.id })
$coGhiAm = $KemGhiAm -and -not $KhongCaiCongCu

# ------------------------------------------------------------------ mẫu Office
$coOffice = $false
if ($KemOffice -and $mau -and $mau.ok -and -not @($mau.configs | Where-Object { $_.keyKind -eq 'key' }).Count) {
    Buoc 'Mẫu Office (tools\office\mau)'
    $md = Join-Path $Stage 'tools\office\mau'
    New-Item -ItemType Directory -Path $md -Force | Out-Null
    # Chỉ setup.exe, file cấu hình (đã kiểm không có khoá riêng) và bộ cài Office\: file khác trong mẫu có thể là ghi chú.
    Copy-Item -LiteralPath (Join-Path $mau.dir 'setup.exe') -Destination $md
    foreach ($x in @($mau.configs)) { Copy-Item -LiteralPath (Join-Path $mau.dir $x.name) -Destination $md }
    if (Test-Path -LiteralPath (Join-Path $mau.dir 'Office') -PathType Container) { Copy-Item -LiteralPath (Join-Path $mau.dir 'Office') -Destination $md -Recurse }
    $coOffice = $true
    Ok "Mẫu Office: $(Format-MB (Get-DirSize $md)), file cấu hình $(($mau.configs | ForEach-Object { $_.name }) -join ', ')"
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
    ghiAm = [bool]$coGhiAm; boCai = @($coBoCai); ungDung = @($coUngDung | ForEach-Object { $_.khoa }); officeMau = $coOffice
}
[IO.File]::WriteAllText((Join-Path $Stage 'portable.json'), ($info | ConvertTo-Json -Depth 4), $Utf8)
# Hướng dẫn theo đúng thứ có trong bản này.
$coSan = @("  - Python $PyVersion (runtime\python) và thư viện của DWG sang PDF, Khôi phục .mdf.", '  - LibreDWG để đọc bản vẽ .dwg.')
$fixPkgs = @($coBoCai | Where-Object { $appIds -notcontains $_ })
if ($fixPkgs.Count) { $coSan += "  - Bộ cài cho nút Cài của các công cụ (không cần mạng): $(($fixPkgs | ForEach-Object { (Get-BoCaiPackage $boCaiDir $_).ten }) -join ', ')." }
if ($coUngDung.Count) { $coSan += "  - Bộ cài ứng dụng cho Bộ ứng dụng văn phòng: $(($coUngDung | ForEach-Object { $_.ten }) -join ', ')." }
if ($coOffice) { $coSan += '  - Bộ cài mẫu Office (tools\office\mau): công cụ Office tự tìm thấy, không phải chép mẫu.' }
if ($coGhiAm) { $coSan += '  - Ghi âm sang Word: thư viện và mô hình nhận dạng tiếng nói.' }
$conThieu = @()
if (-not $coGhiAm) { $conThieu += '  - Ghi âm sang Word: thư viện và mô hình nhận dạng tiếng nói (khoảng 5 GB, tải một lần). Có gói', '    TramTool-GhiAm-*.zip thì giải nén chồng vào thư mục TramTool này là xong, không phải tải.' }
if (-not ($coBoCai -contains 'SqlLocalDB' -and $coBoCai -contains 'Microsoft.msodbcsql.18')) { $conThieu +='  - Khôi phục .mdf sang .sql: SQL Server LocalDB và ODBC Driver for SQL Server (cài vào Windows, cần quyền Admin).' }
if (-not $coUngDung.Count) { $conThieu += '  - Bộ ứng dụng văn phòng: cài qua winget (cần mạng). Có gói TramTool-UngDung-*.zip thì giải nén chồng vào đây.' }
if (-not $coOffice) { $conThieu += '  - Gỡ sạch và cài Office: chép bộ cài mẫu vào tools\office\mau (hoặc chọn ở ô Thư mục bộ cài mẫu). Có gói', '    TramTool-Office-*.zip thì giải nén chồng vào đây.' }
$huongDan = @"
TRẠM TOOL - BẢN PORTABLE ($Ten)
==============================================================================

Không cần cài. Giải nén cả thư mục TramTool vào chỗ nào cũng được (ổ D, USB...), rồi bấm đúp TramTool.exe.
Giao diện mở trong trình duyệt (Brave nếu có, không thì Edge). Trạm tự tắt sau 10 phút không mở giao diện, hoặc vào
Cài đặt > Tắt trạm.

Lần đầu bấm TramTool.exe, Windows có thể hiện "Windows protected your PC" (file chưa có chữ ký số): bấm
"More info" (Thông tin thêm) rồi "Run anyway" (Vẫn chạy).

Đã có sẵn trong gói:
$($coSan -join "`n")
  Chuyển thư mục đi chỗ khác thì bấm TramTool.exe một lần để trạm tự trỏ lại đường dẫn.
$(if ($conThieu.Count) { "`nCòn phải cài thêm (trạm có nút Cài ở trang của công cụ):`n" + ($conThieu -join "`n") + "`n" })
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

function Show-Done {
    foreach ($l in $loiBoCai) { Canh "Thiếu bộ cài $l" }
    if ($loiBoCai.Count) { Info 'Công cụ vẫn cài các ứng dụng này qua winget khi máy dùng có mạng.' }
    if ($DayDu) { Ok "Bản đầy đủ: thư mục $Stage ($(Format-MB (Get-DirSize $Stage))). Chép cả thư mục TramTool sang USB, máy dùng bấm TramTool.exe." }
}
if ($KhongNen) { Write-Host ''; Show-Done; Ok "Xong (không nén): $Stage"; exit 0 }
Buoc 'Nén'
function Save-Zip([string]$Path, [scriptblock]$Chon) {
    # Gói và file .sha256.txt; GitHub Releases không nhận file từ 2 GB trở lên.
    $n = New-Zip $Path $Stage $Chon
    $len = (Get-Item -LiteralPath $Path).Length
    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    [IO.File]::WriteAllText("$Path.sha256.txt", "$hash  $(Split-Path $Path -Leaf)`r`n", $Utf8)
    Ok "$(Split-Path $Path -Leaf): $n file, $(Format-MB $len), SHA-256 $hash"
    if ($len -ge 2GB) { Canh "$(Split-Path $Path -Leaf) từ 2 GB trở lên: GitHub Releases không nhận, chép bằng USB." }
}
$ghiAmRe = '^tools\\ghi-am-sang-word\\(\.venv|models)\\'
$officeRe = '^tools\\office\\mau\\'
# Bộ cài của ứng dụng vào gói ứng dụng, trừ gói mà nút Cài của công cụ cũng dùng (gói đó ở lại gói chính).
$appOnly = @($appIds | Where-Object { $fixIds -notcontains $_ })
$appRe = if ($appOnly.Count) { '^runtime\\bo-cai\\(' + (($appOnly | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\\' } else { '(?!)' }
Save-Zip $Zip { param($r) $r -notmatch $ghiAmRe -and $r -notmatch $officeRe -and $r -notmatch $appRe }
if (@($coUngDung | Where-Object { $appOnly -contains $_.id }).Count) { Save-Zip $ZipUngDung { param($r) $r -match $appRe } }
if ($coOffice) { Save-Zip $ZipOffice { param($r) $r -match $officeRe } }
if ($coGhiAm) { Save-Zip $ZipGhiAm { param($r) $r -match $ghiAmRe } }
Write-Host ''
Show-Done
Ok "Xong. Gửi file $(Split-Path $Zip -Leaf): giải nén, bấm TramTool.exe.$(if ($coUngDung.Count -or $coOffice -or $coGhiAm) { ' Gói thêm giải nén chồng vào cùng thư mục TramTool.' })"
exit 0
