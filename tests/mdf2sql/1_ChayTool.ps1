# Bài thử Chay_tool.bat và CHAY_DONG_LENH.bat của mdf2sql với python.exe giả (biên dịch tại chỗ), PATH chỉ gồm
# thư mục python giả và System32: không chạy Python thật, không cài pyodbc, không mở giao diện.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$Src = Join-Path $ToolsDir 'mdf2sql'
if (-not (Test-Path -LiteralPath (Join-Path $Src 'Chay_tool.bat'))) { Skip-Test 'tools\mdf2sql trống (chưa lấy submodule)'; Complete-Test }

# Bản sao .bat trong thư mục tạm: "cd /d %~dp0" của .bat không vào thư mục công cụ thật
$tool = New-TestDir 'mdf2sql'
foreach ($f in 'Chay_tool.bat', 'CHAY_DONG_LENH.bat', 'requirements.txt') { Copy-Item -LiteralPath (Join-Path $Src $f) -Destination $tool }
$bin = New-TestDir 'bin'
$store = New-TestDir 'store'
$log = Join-Path $TestRoot 'python.log'

# python.exe giả: ghi tham số (ngăn bằng " | ") vào FAKE_PY_LOG, trả mã theo FAKE_PY_MODE:
#   store      mọi lệnh trả 9009 như lối tắt Microsoft Store khi chưa cài Python
#   old        Python quá cũ (kiểm phiên bản trả 1)
#   no-pyodbc  chưa có pyodbc, pip cài được;  pip-fail  chưa có pyodbc, pip lỗi
#   (trống)    đủ cả; "python -m mdf2sql ..." trả 7 để thử mã thoát đi ra ngoài .bat
$main = @'
string log = Environment.GetEnvironmentVariable("FAKE_PY_LOG");
if (!String.IsNullOrEmpty(log)) File.AppendAllText(log, String.Join(" | ", a) + Environment.NewLine);
string mode = Environment.GetEnvironmentVariable("FAKE_PY_MODE") ?? "";
if (mode == "store") return 9009;
if (a.Length > 1 && a[0] == "-c" && a[1].Contains("version_info")) return mode == "old" ? 1 : 0;
if (a.Length > 1 && a[0] == "-c" && a[1].Contains("import pyodbc")) return (mode == "no-pyodbc" || mode == "pip-fail") ? 1 : 0;
if (a.Length > 1 && a[0] == "-m" && a[1] == "pip") return mode == "pip-fail" ? 1 : 0;
if (String.Join(" ", a).Contains("-m mdf2sql")) return 7;
return 0;
'@
[void](New-FakeExe (Join-Path $bin 'python.exe') $main)
Copy-Item -LiteralPath (Join-Path $bin 'python.exe') -Destination $store
$sys = Join-Path $env:SystemRoot 'System32'

function Run-Bat([string]$Name, [string]$Mode, [string]$PathDir, [string[]]$BatArgs = @()) {
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $p = if ($PathDir) { "$PathDir;$sys" } else { $sys }
    $r = Invoke-Bat (Join-Path $tool $Name) -BatArgs $BatArgs -Env @{ PATH = $p; FAKE_PY_MODE = $Mode; FAKE_PY_LOG = $log } -TimeoutSec 60
    $calls = @(if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log })
    $r | Add-Member -NotePropertyName Calls -NotePropertyValue $calls -PassThru
}
function Has([object[]]$Calls, [string]$Pattern) { [bool]@($Calls | Where-Object { $_ -like $Pattern }).Count }

Write-KT '1. Chay_tool.bat' Cyan
$r = Run-Bat 'Chay_tool.bat' '' ''
Check ($r.Code -eq 2) "không có python trong PATH: mã 2 ($($r.Code))"
Check ($r.Out -match 'Chua co Python 3\.9') 'báo chưa có Python'

$r = Run-Bat 'Chay_tool.bat' 'store' $store
Check ($r.Code -eq 2) "python chỉ là lối tắt Microsoft Store: mã 2 ($($r.Code))"
Check ($r.Calls.Count -eq 1 -and $r.Calls[0] -like '-c | *version_info*') "chỉ chạy thử phiên bản rồi dừng, không pip ($($r.Calls -join ' / '))"

$r = Run-Bat 'Chay_tool.bat' 'old' $bin
Check ($r.Code -eq 2 -and -not (Has $r.Calls '-m | pip*')) "Python cũ hơn 3.9: mã 2, không pip ($($r.Code))"

$r = Run-Bat 'Chay_tool.bat' '' $bin
Check ($r.Code -eq 7) "đủ điều kiện: chạy giao diện, mã thoát của python đi ra ngoài ($($r.Code))"
Check (Has $r.Calls '-m | mdf2sql | gui') 'gọi python -m mdf2sql gui'
Check (-not (Has $r.Calls '-m | pip*')) 'đã có pyodbc: không pip'

$r = Run-Bat 'Chay_tool.bat' 'no-pyodbc' $bin
Check (Has $r.Calls '-m | pip | install | --user | --quiet | -r | requirements.txt') "cài pyodbc theo requirements.txt ($(@($r.Calls | Where-Object { $_ -like '-m | pip*' }) -join ' / '))"
Check ($r.Code -eq 7 -and (Has $r.Calls '-m | mdf2sql | gui')) "cài xong thì mở giao diện ($($r.Code))"

$r = Run-Bat 'Chay_tool.bat' 'pip-fail' $bin
Check ($r.Code -eq 1 -and -not (Has $r.Calls '-m | mdf2sql*')) "pip lỗi: mã 1, không mở giao diện ($($r.Code))"
Check ($r.Out -match 'Khong cai duoc pyodbc') 'báo không cài được pyodbc'

Write-KT '2. CHAY_DONG_LENH.bat' Cyan
$r = Run-Bat 'CHAY_DONG_LENH.bat' '' '' @('info', 'x.mdf')
Check ($r.Code -eq 2) "không có python: mã 2 ($($r.Code))"
$r = Run-Bat 'CHAY_DONG_LENH.bat' 'no-pyodbc' $bin @('info', 'D:\du lieu\x.mdf')
Check (-not (Has $r.Calls '*import pyodbc*') -and -not (Has $r.Calls '-m | pip*')) 'info: không cần pyodbc'
Check (Has $r.Calls '-u | -m | mdf2sql | info | D:\du lieu\x.mdf') "info: chuyển đúng tham số ($($r.Calls -join ' / '))"
$r = Run-Bat 'CHAY_DONG_LENH.bat' 'no-pyodbc' $bin @('convert', 'x.mdf')
Check (Has $r.Calls '-m | pip | install | --user | --quiet | -r | requirements.txt') 'convert thiếu pyodbc: cài theo requirements.txt'
Check ($r.Code -eq 7) "mã thoát của python đi ra ngoài ($($r.Code))"

Write-KT '3. requirements.txt' Cyan
$req = (Get-Content -LiteralPath (Join-Path $Src 'requirements.txt') | Where-Object { $_ -match 'pyodbc' }) -join ''
Check ($req -match '^pyodbc>=5\.0,<6$') "pyodbc giới hạn bản chính 5 ($req)"

Complete-Test
