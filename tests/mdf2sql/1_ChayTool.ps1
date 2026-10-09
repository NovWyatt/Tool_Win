# Bài thử Chay_tool.bat và CHAY_DONG_LENH.bat của mdf2sql với python.exe giả (biên dịch tại chỗ), PATH chỉ gồm
# thư mục python giả và System32: không chạy Python thật, không cài pyodbc, không mở giao diện.
# pyodbc nằm trong .venv riêng của công cụ (bản 2026.10.4): không bao giờ pip vào Python chung.
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
$venv = Join-Path $tool '.venv'

# python.exe giả: ghi "base" hoặc "venv" (chạy từ ...\.venv\Scripts) và tham số, ngăn bằng " | ", vào FAKE_PY_LOG.
# Python chung: "-m venv <thư mục>" chép chính nó vào <thư mục>\Scripts\python.exe. Python trong .venv: "-m pip install"
# ghi dấu pyodbc.ok, "import pyodbc" chỉ được khi có dấu đó. FAKE_PY_MODE:
#   store      mọi lệnh trả 9009 như lối tắt Microsoft Store khi chưa cài Python
#   old        Python quá cũ (kiểm phiên bản trả 1)
#   venv-fail  "-m venv" lỗi;  pip-fail  pip trong .venv lỗi
#   (trống)    chạy được; "python -m mdf2sql ..." trả 7 để thử mã thoát đi ra ngoài .bat
$main = @'
string self = System.Reflection.Assembly.GetEntryAssembly().Location;
string scripts = Path.GetDirectoryName(self);
bool inVenv = self.IndexOf("\\.venv\\", StringComparison.OrdinalIgnoreCase) >= 0;
string root = Path.GetDirectoryName(scripts);
string log = Environment.GetEnvironmentVariable("FAKE_PY_LOG");
if (!String.IsNullOrEmpty(log)) File.AppendAllText(log, (inVenv ? "venv | " : "base | ") + String.Join(" | ", a) + Environment.NewLine);
string mode = Environment.GetEnvironmentVariable("FAKE_PY_MODE") ?? "";
if (mode == "store" && !inVenv) return 9009;
string all = String.Join(" ", a);
if (a.Length > 1 && a[0] == "-c" && a[1].Contains("version_info")) return mode == "old" ? 1 : 0;
if (a.Length > 1 && a[0] == "-c" && a[1].Contains("pyodbc")) {
    if (!inVenv || !File.Exists(Path.Combine(root, "pyodbc.ok"))) return 1;
    if (a[1].Contains("print")) Console.WriteLine("  Python 3.12.10 - pyodbc 5.3.0 - trong " + root);
    return 0;
}
if (a.Length > 2 && a[0] == "-m" && a[1] == "venv") {
    if (mode == "venv-fail") return 1;
    string d = Path.Combine(Path.GetFullPath(a[2]), "Scripts");
    Directory.CreateDirectory(d);
    File.Copy(self, Path.Combine(d, "python.exe"), true);
    return 0;
}
if (a.Length > 1 && a[0] == "-m" && a[1] == "pip") {
    if (mode == "pip-fail") return 1;
    if (inVenv) File.WriteAllText(Path.Combine(root, "pyodbc.ok"), "5.3.0");
    return 0;
}
if (all.Contains("-m mdf2sql")) return 7;
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
function Reset-Venv { if (Test-Path -LiteralPath $venv) { Remove-Item -LiteralPath $venv -Recurse -Force } }
function Show([object[]]$Calls) { ($Calls -join ' / ') }
$pipVenv = 'venv | -m | pip | install | --disable-pip-version-check | --quiet | --only-binary=:all: | -r | requirements.txt'

Write-KT '1. Chay_tool.bat' Cyan
$r = Run-Bat 'Chay_tool.bat' '' ''
Check ($r.Code -eq 2) "không có python trong PATH, chưa có .venv: mã 2 ($($r.Code))"
Check ($r.Out -match 'Chua co Python 3\.9') 'báo chưa có Python'

$r = Run-Bat 'Chay_tool.bat' 'store' $store
Check ($r.Code -eq 2) "python chỉ là lối tắt Microsoft Store: mã 2 ($($r.Code))"
Check ($r.Calls.Count -eq 1 -and $r.Calls[0] -like 'base | -c | *version_info*') "chỉ chạy thử phiên bản rồi dừng ($(Show $r.Calls))"

$r = Run-Bat 'Chay_tool.bat' 'old' $bin
Check ($r.Code -eq 2 -and -not (Has $r.Calls '*venv*') -and -not (Has $r.Calls '*pip*')) "Python cũ hơn 3.9: mã 2, không tạo .venv ($($r.Code))"

$r = Run-Bat 'Chay_tool.bat' '' $bin
Check (Has $r.Calls 'base | -m | venv | .venv') "lần đầu: tạo .venv bằng Python chung ($(Show $r.Calls))"
Check (Has $r.Calls $pipVenv) 'cài pyodbc vào .venv theo requirements.txt, chỉ bản dựng sẵn'
Check (-not (Has $r.Calls 'base | -m | pip*') -and -not (Has $r.Calls '*--user*')) 'không pip vào Python chung, không --user'
Check ($r.Code -eq 7 -and (Has $r.Calls 'venv | -m | mdf2sql | gui')) "mở giao diện bằng Python của .venv, mã thoát đi ra ngoài ($($r.Code))"

$r = Run-Bat 'Chay_tool.bat' '' ''
Check ($r.Code -eq 7 -and -not (Has $r.Calls 'base*') -and -not (Has $r.Calls '*pip*')) "lần sau: dùng .venv có sẵn, không cần python trong PATH, không cài lại ($(Show $r.Calls))"

Remove-Item -LiteralPath (Join-Path $venv 'pyodbc.ok') -Force
Set-Content -LiteralPath (Join-Path $venv 'cu.txt') 'file cua .venv hong'
$r = Run-Bat 'Chay_tool.bat' '' $bin
Check ($r.Code -eq 7 -and (Has $r.Calls 'base | -m | venv | .venv') -and (Has $r.Calls $pipVenv)) ".venv hỏng (không import được pyodbc): dựng lại ($($r.Code))"
Check (-not (Test-Path -LiteralPath (Join-Path $venv 'cu.txt'))) 'dựng lại từ thư mục trống'

Reset-Venv
$r = Run-Bat 'Chay_tool.bat' 'venv-fail' $bin
Check ($r.Code -eq 1 -and $r.Out -match 'Khong tao duoc \.venv' -and -not (Has $r.Calls '*mdf2sql*')) "không tạo được .venv: mã 1, không mở giao diện ($($r.Code))"

Reset-Venv
$r = Run-Bat 'Chay_tool.bat' 'pip-fail' $bin
Check ($r.Code -eq 1 -and -not (Has $r.Calls '*-m | mdf2sql*')) "pip lỗi: mã 1, không mở giao diện ($($r.Code))"
Check ($r.Out -match 'Khong cai duoc pyodbc') 'báo không cài được pyodbc'

Write-KT '2. CHAY_DONG_LENH.bat' Cyan
Reset-Venv
$r = Run-Bat 'CHAY_DONG_LENH.bat' '' '' @('info', 'x.mdf')
Check ($r.Code -eq 2) "không có python, chưa có .venv: mã 2 ($($r.Code))"
$r = Run-Bat 'CHAY_DONG_LENH.bat' '' $bin @('info', 'D:\du lieu\x.mdf')
Check (Has $r.Calls 'base | -u | -m | mdf2sql | info | D:\du lieu\x.mdf') "info chưa có .venv: Python chung, đúng tham số ($(Show $r.Calls))"
Check (-not (Has $r.Calls '*-m | venv*') -and -not (Has $r.Calls '*pip*') -and -not (Test-Path -LiteralPath $venv)) 'info: không tạo .venv, không cài pyodbc'
$r = Run-Bat 'CHAY_DONG_LENH.bat' '' $bin @('doctor', '--ket-qua')
Check ((Has $r.Calls 'base | -u | -m | mdf2sql | doctor | --ket-qua') -and -not (Test-Path -LiteralPath $venv)) 'doctor chưa có .venv: chỉ báo thiếu, không tự cài'
$r = Run-Bat 'CHAY_DONG_LENH.bat' '' $bin @('convert', 'x.mdf')
Check ((Has $r.Calls 'base | -m | venv | .venv') -and (Has $r.Calls $pipVenv)) 'convert chưa có .venv: tạo .venv, cài pyodbc'
Check ($r.Code -eq 7 -and (Has $r.Calls 'venv | -u | -m | mdf2sql | convert | x.mdf')) "convert chạy bằng .venv, mã thoát đi ra ngoài ($($r.Code))"
$r = Run-Bat 'CHAY_DONG_LENH.bat' '' $bin @('info', 'x.mdf')
Check (Has $r.Calls 'venv | -u | -m | mdf2sql | info | x.mdf') 'có .venv: info cũng chạy bằng .venv'

Write-KT '3. CHAY_DONG_LENH.bat cai-dat (nút Cài của Trạm Tool)' Cyan
Reset-Venv
$r = Run-Bat 'CHAY_DONG_LENH.bat' '' $bin @('cai-dat')
Check ($r.Code -eq 0 -and (Has $r.Calls $pipVenv) -and -not (Has $r.Calls '*mdf2sql*')) "tạo .venv, cài pyodbc, không chạy mdf2sql ($($r.Code))"
Check ($r.Out -match 'pyodbc 5\.3\.0' -and $r.Out -match 'XONG') 'in phiên bản Python, pyodbc trong .venv'
$r = Run-Bat 'CHAY_DONG_LENH.bat' '' $bin @('cai-dat')
Check ($r.Code -eq 0 -and -not (Has $r.Calls 'base*')) "đã có thì bỏ qua ($(Show $r.Calls))"
$r = Run-Bat 'CHAY_DONG_LENH.bat' '' $bin @('cai-dat', '--lam-lai')
Check ($r.Code -eq 0 -and (Has $r.Calls 'base | -m | venv | .venv') -and (Has $r.Calls $pipVenv)) '--lam-lai: dựng lại dù .venv đang chạy được'
Reset-Venv
$r = Run-Bat 'CHAY_DONG_LENH.bat' 'pip-fail' $bin @('cai-dat')
Check ($r.Code -eq 1 -and $r.Out -notmatch 'XONG') "pip lỗi: mã 1 ($($r.Code))"

Write-KT '4. requirements.txt, tool.json' Cyan
$req = @(Get-Content -LiteralPath (Join-Path $Src 'requirements.txt') | Where-Object { $_ -match '^\s*[^#\s]' })
Check ($req.Count -eq 1 -and $req[0] -eq 'pyodbc==5.3.0') "chỉ pyodbc, ghim đúng bản ($($req -join ', '))"
$bats = (Get-Content -LiteralPath (Join-Path $Src 'Chay_tool.bat') -Raw) + (Get-Content -LiteralPath (Join-Path $Src 'CHAY_DONG_LENH.bat') -Raw)
Check ($bats -notmatch '--user' -and $bats -notmatch 'python -m pip') 'hai .bat không pip vào Python chung'
$tj = Get-Content -LiteralPath (Join-Path $Src 'tool.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$cai = @($tj.actions | Where-Object { $_.id -eq 'cai-dat' })[0]
$rq = @($tj.requires | Where-Object { $_.type -eq 'venv' })[0]
Check ($cai -and @($cai.fixedArgs) -contains 'cai-dat' -and $rq -and @($rq.modules) -contains 'pyodbc' -and $rq.fix.action -eq 'cai-dat') 'tool.json: yêu cầu .venv có pyodbc, nút Cài trỏ tới action cai-dat'

Complete-Test
