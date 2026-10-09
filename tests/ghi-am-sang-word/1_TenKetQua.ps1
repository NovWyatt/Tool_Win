# Bài thử ghi-am-sang-word: tên kết quả giữ đuôi file gốc ("hop.m4a" và "hop.mp4" không ghi đè nhau), nhận ra kết
# quả bản cũ (tên bỏ đuôi) để không làm lại, tham số --ra. Phần kiểm nằm trong _ten_ket_qua.py, chạy bằng Python của
# máy với thư mục tạm; không nạp mô hình, không cần .venv, không đụng ket_qua thật.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$py = Find-Python
if (-not $py) { Skip-Test 'không thấy Python'; Complete-Test }

$env:PYTHONDONTWRITEBYTECODE = '1'   # không để lại __pycache__ mới trong thư mục công cụ
$env:PYTHONIOENCODING = 'utf-8'
$ErrorActionPreference = 'Continue'   # dòng stderr của Python (traceback) thành ErrorRecord: in ra chứ không dừng
$out = & $py -X utf8 (Join-Path $PSScriptRoot '_ten_ket_qua.py') $TestRoot (Join-Path $ToolsDir 'ghi-am-sang-word') 2>&1
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$n = 0
foreach ($l in @($out | ForEach-Object { [string]$_ })) {
    if ($l -match '^KT ([01]) (.*)$') { $n++; Check ($Matches[1] -eq '1') $Matches[2] }
    elseif ($l.Trim()) { Write-KT "  | $l" DarkGray }
}
Check ($code -eq 0) "phần Python chạy hết (mã $code)"
Check ($n -ge 20) "đủ các mục kiểm ($n)"

Complete-Test
