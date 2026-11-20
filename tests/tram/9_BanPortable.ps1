# Bản portable (hub\dev\DongGoi.ps1): hàm của trạm trỏ lại .venv khi thư mục đổi chỗ (pyvenv.cfg UTF-8, đường dẫn có
# dấu), giữ Python mang theo đứng đầu PATH, bật UTF-8 cho Python, bỏ dấu tải từ Internet một lần; lối tắt
# "Trạm Tool.lnk" (WScript.Shell không lưu được tên có dấu); TramTool.exe dịch từ hub\dev\TramToolExe.cs chạy
# powershell.exe giả (tham số, lỗi khi mở, nhận máy chủ đã chạy); DongGoi.ps1 chạy thử và dựng gói với gói Python giả;
# bộ cài có sẵn (cache giả, gói phụ thuộc, sai mã SHA-256, khác bản ghim, LocalDB không chữ ký), gói ứng dụng, mẫu Office
# (khoá KMS chung thì đóng, khoá riêng giả thì không, khoá không bao giờ in ra); không tải, không dựng .venv thật.
# Không đụng Desktop, PATH hay registry thật.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. (Join-Path $HubDir 'lib\Common.ps1')
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$u8 = New-Object Text.UTF8Encoding $false
$envKeys = 'TRAMTOOL_PORTABLE', 'TRAMTOOL_PYTHON', 'PYTHONUTF8', 'PYTHONIOENCODING', 'Path'
$envOld = @{}; foreach ($k in $envKeys) { $envOld[$k] = [Environment]::GetEnvironmentVariable($k) }
function Restore-TestEnv { foreach ($k in $envKeys) { [Environment]::SetEnvironmentVariable($k, $envOld[$k]) }; $script:PortablePath = '' }
function Same([string]$A, [byte[]]$B) { return [Convert]::ToBase64String([IO.File]::ReadAllBytes($A)) -eq [Convert]::ToBase64String($B) }
function Set-Motw([string]$F) { Set-Content -LiteralPath $F -Stream 'Zone.Identifier' -Value "[ZoneTransfer]`r`nZoneId=3" }
function Test-Motw([string]$F) { return [bool](Get-Item -LiteralPath $F -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue) }

Write-KT '1. Trỏ lại .venv, PATH, biến môi trường' Cyan
$root = New-TestDir 'Trạm thử có dấu'
$py = Join-Path $root 'runtime\python'
New-Item -ItemType Directory -Path $py -Force | Out-Null
foreach ($n in 'python.exe', 'python312.dll', 'python3.dll') { [IO.File]::WriteAllBytes((Join-Path $py $n), [byte[]](0x4D, 0x5A)) }
function New-Venv([string]$Tool, [string]$Base, [string]$Ver) {
    $v = Join-Path $root "tools\$Tool\.venv"
    New-Item -ItemType Directory -Path $v -Force | Out-Null
    $t = "home = $Base`r`ninclude-system-site-packages = false`r`nversion = $Ver`r`nexecutable = $Base\python.exe`r`ncommand = $Base\python.exe -m venv $v`r`n"
    $cfg = Join-Path $v 'pyvenv.cfg'
    [IO.File]::WriteAllText($cfg, $t, $u8)
    return $cfg
}
$cA = New-Venv 'a' 'D:\Chỗ cũ\runtime\python' '3.12.10'
$cB = New-Venv 'b' $py '3.12.10'
$cC = New-Venv 'c' 'C:\Python313' '3.13.1'
New-Item -ItemType Directory -Path (Join-Path $root 'tools\d') -Force | Out-Null
$bB = [IO.File]::ReadAllBytes($cB); $bC = [IO.File]::ReadAllBytes($cC)
$hubF = Join-Path $root 'hub\TramTool.ps1'
New-Item -ItemType Directory -Path (Split-Path $hubF -Parent) -Force | Out-Null
[IO.File]::WriteAllText($hubF, '#', $u8)
Set-Motw $hubF
$venvF = Join-Path $root 'tools\a\.venv\x.txt'
[IO.File]::WriteAllText($venvF, 'x', $u8)
Set-Motw $venvF
$data = Join-Path $root 'hub\data'

$r = Initialize-PortableRuntime -RootDir $root -DataDir $data
Check ($r -and $r.Version -eq '3.12' -and $r.Python -eq (Join-Path $py 'python.exe')) "nhận bản portable, Python 3.12 ($($r.Version))"
Check ((@($r.Fixed) -join ',') -eq 'a') "chỉ trỏ lại .venv đang ở chỗ cũ ($(@($r.Fixed) -join ','))"
$t = [IO.File]::ReadAllText($cA, [Text.Encoding]::UTF8)
Check ($t.Contains("home = $py`r`n") -and $t.Contains("executable = $py\python.exe`r`n") -and $t.Contains('version = 3.12.10') -and $t.Contains('command = D:\Chỗ cũ\runtime\python\python.exe -m venv')) 'pyvenv.cfg: home, executable trỏ chỗ mới (đường dẫn có dấu), dòng khác giữ nguyên'
Check ([IO.File]::ReadAllBytes($cA)[0] -ne 0xEF) 'pyvenv.cfg ghi UTF-8 không BOM (Python đọc được)'
Check ((Same $cB $bB) -and (Same $cC $bC)) '.venv đã đúng chỗ: không ghi lại; .venv của Python khác (3.13): không đụng'
Check ($env:TRAMTOOL_PYTHON -eq (Join-Path $py 'python.exe') -and $env:TRAMTOOL_PORTABLE -eq $root -and $env:PYTHONUTF8 -eq '1' -and $env:PYTHONIOENCODING -eq 'utf-8') 'đặt TRAMTOOL_PYTHON, PYTHONUTF8, PYTHONIOENCODING cho công cụ'
Check ($env:Path.StartsWith("$py;$py\Scripts;")) 'Python mang theo đứng đầu PATH'
Update-EnvPath
Check ($env:Path.StartsWith("$py;$py\Scripts;")) 'nạp lại PATH từ registry (sau khi cài gì đó) vẫn giữ Python mang theo'
Check ($r.Unblocked -eq 1 -and -not (Test-Motw $hubF) -and (Test-Motw $venvF) -and (Test-Path -LiteralPath (Join-Path $data 'da-bo-chan.txt'))) "bỏ dấu tải từ Internet ($($r.Unblocked) file), bỏ qua .venv, ghi dấu đã làm"
Set-Motw $hubF
$r2 = Initialize-PortableRuntime -RootDir $root -DataDir $data
Check ($r2.Unblocked -eq 0 -and -not @($r2.Fixed).Count -and (Test-Motw $hubF)) 'lần mở sau: không dò lại dấu tải, không sửa gì'
Restore-TestEnv
$env:TRAMTOOL_PYTHON = 'cu'
$plain = New-TestDir 'ban-git'
Check ($null -eq (Initialize-PortableRuntime -RootDir $plain) -and $env:TRAMTOOL_PYTHON -eq 'cu' -and -not $env:Path.StartsWith("$py;")) 'không có runtime\python (bản lấy bằng git): không làm gì'
Restore-TestEnv

Write-KT '2. Lối tắt Trạm Tool' Cyan
$desk = New-TestDir 'Màn hình'
[IO.File]::WriteAllText((Join-Path $root 'TramTool.bat'), '@echo off', $u8)
$lnk = New-DesktopShortcut -RootDir $root -HubDir (Join-Path $root 'hub') -Desktop $desk
Check ((Split-Path $lnk -Leaf) -eq 'Trạm Tool.lnk' -and (Test-Path -LiteralPath $lnk)) 'lưu được "Trạm Tool.lnk" (tên có dấu)'
$l = Read-ShellLink -Path $lnk
Check ($l.Target -eq (Join-Path $root 'TramTool.bat') -and $l.ShowCmd -eq 7 -and $l.WorkingDirectory -eq $root -and $l.Description -eq 'Trạm Tool - chọn và chạy công cụ Windows' -and $l.Icon -match 'imageres\.dll,109$') "bản git: trỏ TramTool.bat, thu nhỏ cửa sổ máy chủ ($($l.Target), $($l.ShowCmd), $($l.Icon))"
[IO.File]::WriteAllBytes((Join-Path $root 'TramTool.exe'), [byte[]](0x4D, 0x5A))
$l = Read-ShellLink -Path (New-DesktopShortcut -RootDir $root -HubDir (Join-Path $root 'hub') -Desktop $desk)
Check ($l.Target -eq (Join-Path $root 'TramTool.exe') -and $l.ShowCmd -eq 1) "bản portable: trỏ TramTool.exe ($($l.Target))"

Write-KT '3. TramTool.exe' Cyan
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$exeDir = New-TestDir 'exe có dấu cách'
$exe = Join-Path $exeDir 'TramTool.exe'
$o = & $csc /nologo /target:winexe /codepage:65001 "/out:$exe" (Join-Path $HubDir 'dev\TramToolExe.cs') 2>&1 | Out-String
Check ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $exe)) "dịch TramToolExe.cs bằng csc.exe của Windows ($o)"
$log = Join-Path $exeDir 'log.txt'
$fake = New-FakeExe (Join-Path (New-TestDir 'gia') 'psgia.exe') 'File.AppendAllText(Environment.GetEnvironmentVariable("TRAMTOOL_EXE_LOG"), "ARGS:" + string.Join("|", a) + "\r\n"); string c = Environment.GetEnvironmentVariable("PSGIA_MA"); if (c == "pid") { File.WriteAllText(Path.Combine(Path.GetDirectoryName(a[4]), "data\\runtime.json"), "{\r\n    \"port\":  47899,\r\n    \"pid\":  " + System.Diagnostics.Process.GetCurrentProcess().Id + "\r\n}"); System.Threading.Thread.Sleep(30000); return 0; } return c == null ? 0 : int.Parse(c);'
function Invoke-Exe([string[]]$A, [string]$Ma = '') {
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $env:TRAMTOOL_EXE_POWERSHELL = $fake; $env:TRAMTOOL_EXE_LOG = $log; $env:TRAMTOOL_EXE_KHONG_HOI = '1'
    if ($Ma) { $env:PSGIA_MA = $Ma } else { Remove-Item Env:PSGIA_MA -ErrorAction SilentlyContinue }
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo($exe, (($A | ForEach-Object { '"' + $_ + '"' }) -join ' '))
        $psi.UseShellExecute = $false
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $p = [Diagnostics.Process]::Start($psi)
        if (-not $p.WaitForExit(40000)) { $p.Kill(); return [pscustomobject]@{ Code = -1; Log = ''; Sec = 40 } }
        $txt = if (Test-Path -LiteralPath $log) { [IO.File]::ReadAllText($log, [Text.Encoding]::UTF8) } else { '' }
        return [pscustomobject]@{ Code = $p.ExitCode; Log = $txt; Sec = $sw.Elapsed.TotalSeconds }
    } finally { Remove-Item Env:TRAMTOOL_EXE_POWERSHELL, Env:TRAMTOOL_EXE_LOG, Env:TRAMTOOL_EXE_KHONG_HOI, Env:PSGIA_MA -ErrorAction SilentlyContinue }
}
$r = Invoke-Exe @()
Check ($r.Code -eq 1 -and $r.Log -match 'BAO: Không tìm thấy hub\\TramTool\.ps1' -and $r.Log -notmatch 'CHAY:') "thiếu thư mục hub: báo giải nén đủ, không chạy gì ($($r.Code))"
$hubE = Join-Path $exeDir 'hub\TramTool.ps1'
New-Item -ItemType Directory -Path (Split-Path $hubE -Parent) -Force | Out-Null
[IO.File]::WriteAllText($hubE, '#', $u8)
$r = Invoke-Exe @('-Browser', 'edge', 'có dấu cách')
$want = "ARGS:-NoProfile|-ExecutionPolicy|Bypass|-File|$hubE|-Browser|edge|có dấu cách"
Check ($r.Code -eq 0 -and $r.Log.Contains($want) -and $r.Log -notmatch 'BAO:') "chạy máy chủ của trạm, chuyển nguyên tham số (cả tham số có dấu cách) ($($r.Code))"
$r = Invoke-Exe @() '3'
Check ($r.Code -eq 3 -and $r.Log -match 'BAO: Trạm Tool không mở được \(mã 3\)' -and $r.Log -match 'TramTool\.bat') "máy chủ thoát mã 3: báo lỗi, chỉ TramTool.bat để xem ($($r.Code))"
New-Item -ItemType Directory -Path (Join-Path $exeDir 'hub\data') -Force | Out-Null
$r = Invoke-Exe @() 'pid'
Check ($r.Code -eq 0 -and $r.Sec -lt 20) ("máy chủ ghi runtime.json có pid của nó: TramTool.exe thoát luôn, máy chủ chạy tiếp ({0:N1} giây)" -f $r.Sec)
Get-Process -Name 'psgia' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $fake } | Stop-Process -Force

Write-KT '4. DongGoi.ps1' Cyan
$dg = Join-Path $HubDir 'dev\DongGoi.ps1'
$ps = Join-Path $PSHOME 'powershell.exe'
function Invoke-DongGoi([string[]]$A) {
    $o = & $ps -NoProfile -ExecutionPolicy Bypass -File $dg @A 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
$ra = New-TestDir 'goi ra'
$r = Invoke-DongGoi @('-ChayThu', '-Ra', $ra)
Check ($r.Code -eq 0 -and $r.Out -match 'Kế hoạch' -and $r.Out -match 'Chạy thử: dừng ở đây' -and -not @(Get-ChildItem -LiteralPath $ra -Force).Count) "chạy thử: in kế hoạch, không ghi gì ($($r.Code))"
$r = Invoke-DongGoi @('-ChayThu', '-Ra', (Join-Path $RepoRoot 'goi-thu'))
Check ($r.Code -eq 1 -and $r.Out -match 'nằm trong repo') "không cho để gói trong repo ($($r.Code))"
$nupkg = Join-Path $ra 'python.gia.nupkg'
$zs = [IO.File]::Open($nupkg, [IO.FileMode]::CreateNew)
$za = New-Object IO.Compression.ZipArchive($zs, [IO.Compression.ZipArchiveMode]::Create)
foreach ($n in 'python.nuspec', 'tools/python.exe', 'tools/python312.dll', 'tools/Lib/os.py', 'tools/DLLs/_ctypes.pyd') {
    $w = New-Object IO.StreamWriter($za.CreateEntry($n).Open()); $w.Write('gia'); $w.Dispose()
}
$za.Dispose(); $zs.Dispose()
$r = Invoke-DongGoi @('-Ra', $ra, '-PythonGoi', $nupkg, '-KhongCaiCongCu')
$zip = @(Get-ChildItem -LiteralPath $ra -Filter 'TramTool-Portable-*.zip')[0]
Check ($r.Code -eq 0 -and $zip) "dựng gói với gói Python giả: mã 0 ($($r.Code))"
if ($zip) {
    $z = [IO.Compression.ZipFile]::OpenRead($zip.FullName)
    $names = @($z.Entries | ForEach-Object { $_.FullName })
    $z.Dispose()
    $need = 'TramTool/TramTool.exe', 'TramTool/TramTool.bat', 'TramTool/CAI_DAT.bat', 'TramTool/HUONG-DAN-PORTABLE.txt', 'TramTool/portable.json', 'TramTool/hub/TramTool.ps1', 'TramTool/hub/lib/Common.ps1', 'TramTool/hub/web/index.html', 'TramTool/runtime/python/python.exe', 'TramTool/runtime/python/Lib/os.py', 'TramTool/tools/dwg2pdf/tool.json', 'TramTool/tools/mdf2sql/mdf2sql/cli.py'
    $miss = @($need | Where-Object { $names -notcontains $_ })
    Check (-not $miss.Count) "gói có TramTool.exe, trạm, công cụ (cả submodule mdf2sql), Python mang theo (thiếu: $($miss -join ', '))"
    Check (-not @($names | Where-Object { -not $_.StartsWith('TramTool/') -or $_.Contains('\') }).Count) 'mọi mục nằm trong thư mục TramTool/, tên dùng dấu /'
    $lead = @($names | Where-Object { $_ -match '^TramTool/(tests|hub/dev|hub/data)/' -or $_ -match '/LuuTru/' -or $_ -match '/(du-lieu|ket_qua)/' -or $_ -match '(^|/)\.git' -or $_ -match 'KetQua_[^/]*\.json$' })
    Check (-not $lead.Count -and $names -contains 'TramTool/docs/PHAN-TICH-NANG-CAP.md') "không có bài thử, hub\dev, dữ liệu chạy, bản lưu cũ; có docs\ cho trang lộ trình ($($lead | Select-Object -First 3))"
    $tracked = @((& git -C $RepoRoot ls-files --recurse-submodules) | Where-Object { $_ -match '^tools/[^/]+/tool\.json$' }).Count
    Check (@($names | Where-Object { $_ -match '^TramTool/tools/[^/]+/tool\.json$' }).Count -eq $tracked) "đủ $tracked công cụ"
    $st = Join-Path $ra 'dung\TramTool'
    $pj = [IO.File]::ReadAllText((Join-Path $st 'portable.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    Check ($pj.python -eq '3.12.10' -and $pj.ten -eq $zip.BaseName -and -not $pj.ghiAm -and -not @($pj.venv).Count) "portable.json ghi phiên bản, Python, chưa có .venv ($($pj.ten))"
    Check ([IO.File]::ReadAllBytes((Join-Path $st 'HUONG-DAN-PORTABLE.txt'))[0] -eq 0xEF -and [IO.File]::ReadAllText((Join-Path $st 'HUONG-DAN-PORTABLE.txt'), [Text.Encoding]::UTF8) -match 'bấm đúp TramTool\.exe') 'HUONG-DAN-PORTABLE.txt có BOM (Notepad hiện đúng dấu)'
    $sha = [IO.File]::ReadAllText("$($zip.FullName).sha256.txt").Split(' ')[0]
    Check ($sha -eq (Get-FileHash -LiteralPath $zip.FullName -Algorithm SHA256).Hash) 'file .sha256.txt khớp gói'
    Check ((Get-Item -LiteralPath (Join-Path $st 'TramTool.exe')).VersionInfo.ProductName -eq 'Trạm Tool (bản portable)') 'TramTool.exe có tên sản phẩm tiếng Việt'
}

Write-KT '5. DongGoi.ps1: bộ cài có sẵn, gói ứng dụng, mẫu Office' Cyan
# cache\bo-cai giả như 'winget download' để lại (file kê khai + bộ cài là file chữ); không tải gì (-KhongCaiCongCu).
$ra2 = New-TestDir 'goi ra bo cai'
$cb = Join-Path $ra2 'cache\bo-cai'
function New-CachedDownload([string]$Id, [string]$File, [string]$Extra = '', [switch]$BadSha) {
    $d = Join-Path $cb $Id
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    $f = Join-Path $d $File
    [IO.File]::WriteAllText($f, "bo cai gia $Id")
    $h = if ($BadSha) { '0' * 64 } else { (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash }
    $y = "PackageIdentifier: $Id`nPackageVersion: 1.0`nPackageName: Gia $Id`nPublisher: Thu`nInstallers:`n- Architecture: x64`n  InstallerType: burn`n  InstallerSha256: $h`n$Extra" + "ManifestType: merged`n"
    [IO.File]::WriteAllText((Join-Path $d "$Id.yaml"), $y, (New-Object Text.UTF8Encoding $false))
}
$vc = 'Microsoft.VCRedist.2015+.x64'
New-CachedDownload 'Microsoft.msodbcsql.18' 'msodbcsql.msi' "  Dependencies:`n    PackageDependencies:`n    - PackageIdentifier: $vc`n"
New-CachedDownload $vc 'vc_redist.x64.exe'
New-CachedDownload '7zip.7zip' '7z-x64.exe'
New-CachedDownload 'VideoLAN.VLC' 'vlc.exe' -BadSha
New-CachedDownload 'UniKey.UniKey' 'unikey.zip'   # bản 1.0, không phải bản ghim trong DanhSach.json
New-Item -ItemType Directory -Path (Join-Path $cb 'SqlLocalDB') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $cb 'SqlLocalDB\SqlLocalDB.msi'), 'khong co chu ky')
function New-FakeMau([string]$Name, [string]$Key) {
    $m = New-TestDir $Name
    New-Item -ItemType Directory -Path (Join-Path $m 'Office\Data') -Force | Out-Null
    foreach ($p in @(@('setup.exe', 'gia'), @('Office\Data\v64.cab', 'gia'), @('ghi-chu.txt', 'ghi chu cua tho'), @('khac.xml', '<GhiChu>x</GhiChu>'))) { [IO.File]::WriteAllText((Join-Path $m $p[0]), $p[1]) }
    [IO.File]::WriteAllText((Join-Path $m 'Configuration.xml'), "<Configuration>`r`n  <!-- khoá MAK cũ: ZZZZZ-YYYYY-XXXXX-WWWWW-VVVVV; muốn tự kích hoạt thì thêm <Property Name=""AUTOACTIVATE"" Value=""1"" /> -->`r`n  <Add OfficeClientEdition=""64"" Channel=""PerpetualVL2019"">`r`n    <Product ID=""ProPlus2019Volume"" PIDKEY=""$Key""><Language ID=""en-us"" /></Product>`r`n  </Add>`r`n  <Property Name=""AUTOACTIVATE"" Value=""1"" />`r`n  <Property Name=""KMSSERVICENAME"" Value=""kms.thu.local"" />`r`n  <Property Name=""FORCEAPPSHUTDOWN"" Value=""TRUE"" />`r`n</Configuration>")
    return $m
}
$mauKms = New-FakeMau 'mau kms' 'NMMKJ-6RK4F-KMJVX-8D9MJ-6MWKP'     # GVLK Microsoft công bố (Office 2019)
$mauRieng = New-FakeMau 'mau rieng' 'TESTA-BBBBB-CCCCC-DDDDD-QWXYZ'  # khoá giả
function Get-ZipNames($F) { $z = [IO.Compression.ZipFile]::OpenRead($F.FullName); try { return , @($z.Entries | ForEach-Object { $_.FullName }) } finally { $z.Dispose() } }

$r = Invoke-DongGoi @('-Ra', $ra2, '-PythonGoi', $nupkg, '-KhongCaiCongCu', '-KemUngDung', '-MauOffice', $mauKms)
$zb = @(Get-ChildItem -LiteralPath $ra2 -Filter 'TramTool-Portable-*.zip')[0]
$zu = @(Get-ChildItem -LiteralPath $ra2 -Filter 'TramTool-UngDung-*.zip')[0]
$zo = @(Get-ChildItem -LiteralPath $ra2 -Filter 'TramTool-Office-*.zip')[0]
Check ($r.Code -eq 0 -and $zb -and $zu -and $zo -and -not @(Get-ChildItem -LiteralPath $ra2 -Filter 'TramTool-GhiAm-*.zip').Count) "kèm ứng dụng và mẫu Office: gói chính, gói ứng dụng, gói Office ($($r.Code))"
if ($zb -and $zu -and $zo) {
    $nb = Get-ZipNames $zb; $nu = Get-ZipNames $zu; $no = Get-ZipNames $zo
    $bc = 'TramTool/runtime/bo-cai/'
    Check ($nb -contains "${bc}Microsoft.msodbcsql.18/msodbcsql.msi" -and $nb -contains "${bc}Microsoft.msodbcsql.18/goi.json" -and $nb -contains "$bc$vc/vc_redist.x64.exe") 'gói chính có bộ cài của nút Cài (ODBC 18) và gói nó cần (Visual C++ Redistributable)'
    Check (-not @($nb | Where-Object { $_ -match '^TramTool/runtime/bo-cai/(7zip|VideoLAN|UniKey|SqlLocalDB)' -or $_ -match '^TramTool/tools/office/mau/' -or $_ -match '\.yaml$' }).Count) 'gói chính không có bộ cài ứng dụng, mẫu Office, file kê khai'
    Check ((@($nu | Sort-Object) -join ',') -eq "${bc}7zip.7zip/7z-x64.exe,${bc}7zip.7zip/goi.json") "gói ứng dụng: chỉ bộ cài đúng mã SHA-256 và đúng bản ghim ($($nu -join ', '))"
    Check ((@($no | Sort-Object) -join ',') -eq 'TramTool/tools/office/mau/Configuration.xml,TramTool/tools/office/mau/Office/Data/v64.cab,TramTool/tools/office/mau/setup.exe') "gói Office: setup.exe, file cấu hình, thư mục Office; không ghi chú, không xml khác ($($no -join ', '))"
    Check (-not @($zb, $zu, $zo | Where-Object { [IO.File]::ReadAllText("$($_.FullName).sha256.txt").Split(' ')[0] -ne (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }).Count) 'mỗi gói có file .sha256.txt khớp'
    $z = [IO.Compression.ZipFile]::OpenRead($zo.FullName)
    try { $sr = New-Object IO.StreamReader($z.GetEntry('TramTool/tools/office/mau/Configuration.xml').Open()); $cfg = $sr.ReadToEnd(); $sr.Dispose() } finally { $z.Dispose() }
    $xc = [xml]$cfg
    Check ($cfg -notmatch '(?i)PIDKEY|AUTOACTIVATE|KMSSERVICE|6MWKP|VVVVV|<!--' -and $xc.Configuration.Add.Product.ID -eq 'ProPlus2019Volume' -and $xc.Configuration.Add.Product.Language.ID -eq 'en-us' -and @($xc.Configuration.Property | Where-Object { $_.Name -eq 'FORCEAPPSHUTDOWN' }).Count -eq 1) 'file cấu hình trong gói: bỏ khoá, AUTOACTIVATE, KMS, chú thích (có thể ghi khoá); giữ sản phẩm, ngôn ngữ, thẻ khác'
    Check ([IO.File]::ReadAllText((Join-Path $mauKms 'Configuration.xml')) -match 'PIDKEY="NMMKJ' -and [IO.File]::ReadAllText((Join-Path $mauKms 'Configuration.xml')) -match 'AUTOACTIVATE') 'mẫu gốc giữ nguyên'
}
$st2 = Join-Path $ra2 'dung\TramTool'
$pj = [IO.File]::ReadAllText((Join-Path $st2 'portable.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$want = (@('7zip.7zip', 'Microsoft.msodbcsql.18', $vc) | Sort-Object) -join ','
Check (((@($pj.boCai) | Sort-Object) -join ',') -eq $want -and (@($pj.ungDung) -join ',') -eq 'SevenZip' -and $pj.officeMau -eq $true -and $pj.ghiAm -eq $false) "portable.json: bộ cài, ứng dụng, mẫu Office ($(@($pj.boCai) -join ', '))"
Check ($r.Out -match 'Bỏ qua VideoLAN\.VLC' -and $r.Out -match 'Bỏ qua UniKey\.UniKey' -and -not (Test-Path -LiteralPath (Join-Path $st2 'runtime\bo-cai\UniKey.UniKey'))) 'cache sai mã SHA-256 hoặc khác bản ghim: không dùng'
Check (-not (Test-Path -LiteralPath (Join-Path $cb 'SqlLocalDB\SqlLocalDB.msi')) -and -not (Test-Path -LiteralPath (Join-Path $st2 'runtime\bo-cai\SqlLocalDB')) -and $r.Out -match 'SqlLocalDB: bộ cài không có chữ ký hợp lệ của Microsoft') 'bộ cài SQL LocalDB không có chữ ký Microsoft: xoá khỏi cache, không đóng'
$hd = [IO.File]::ReadAllText((Join-Path $st2 'HUONG-DAN-PORTABLE.txt'), [Text.Encoding]::UTF8)
Check ($hd -match 'nút Cài của các công cụ \(không cần mạng\): Gia Microsoft\.msodbcsql\.18' -and $hd -match 'Bộ ứng dụng văn phòng: 7-Zip' -and $hd -match 'Bộ cài mẫu Office' -and $hd -match 'SQL Server LocalDB' -and $hd -notmatch 'cài qua winget \(cần mạng\)' -and $hd -notmatch 'Gỡ sạch và cài Office') 'hướng dẫn ghi đúng thứ có sẵn và thứ còn thiếu'
Check ($r.Out -notmatch '6MWKP|NMMKJ|kms\.thu|VVVVV' -and $r.Out -match 'khoá KMS chung' -and $r.Out -match 'bỏ khoá và tự kích hoạt') 'kế hoạch ghi loại khoá của mẫu và việc bỏ khoá, không in khoá'
Check ($hd -match 'không tự kích hoạt: cài xong kích hoạt thủ công') 'hướng dẫn nhắc kích hoạt thủ công'

$ra3 = New-TestDir 'goi ra khoa rieng'
$r = Invoke-DongGoi @('-Ra', $ra3, '-PythonGoi', $nupkg, '-KhongCaiCongCu', '-KhongNen', '-MauOffice', $mauRieng)
$st3 = Join-Path $ra3 'dung\TramTool'
$pj3 = [IO.File]::ReadAllText((Join-Path $st3 'portable.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
Check ($r.Code -eq 0 -and $r.Out -match 'KHOÁ RIÊNG' -and $r.Out -match 'không đóng mẫu vào gói' -and -not (Test-Path -LiteralPath (Join-Path $st3 'tools\office\mau')) -and $pj3.officeMau -eq $false -and -not @(Get-ChildItem -LiteralPath $ra3 -Filter '*.zip').Count) "mẫu có khoá riêng: không đóng vào gói ($($r.Code))"
$leak = @(Get-ChildItem -LiteralPath $st3 -File | Where-Object { $_.Extension -in '.json', '.txt' } | Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'QWXYZ|TESTA' })
Check ($r.Out -notmatch 'QWXYZ|TESTA' -and -not $leak.Count) 'khoá riêng không hiện trong lời in, portable.json, hướng dẫn'
Complete-Test
