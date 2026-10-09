# Bài thử ghi-am-sang-word: tiến độ cho Trạm Tool (tramtool.tiendo/1), lưu các khúc đã xong để chạy lại làm tiếp,
# card đồ hoạ hết bộ nhớ thì thử lại khúc đó (lần ba beam 1), card lỗi thì CPU làm tiếp chứ không làm lại, --lam-lai
# và GHI_AM_CHAY_TIEP. Phần kiểm nằm trong _tien_do_lam_tiep.py, chạy bằng Python của máy với mô hình giả: không nạp
# mô hình, không cần .venv, không đụng ket_qua thật.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$py = Find-Python
if (-not $py) { Skip-Test 'không thấy Python'; Complete-Test }

$env:PYTHONDONTWRITEBYTECODE = '1'   # không để lại __pycache__ mới trong thư mục công cụ
$env:PYTHONIOENCODING = 'utf-8'
Remove-Item Env:\GHI_AM_CHAY_TIEP -ErrorAction SilentlyContinue
$ErrorActionPreference = 'Continue'   # dòng stderr của Python (traceback) thành ErrorRecord: in ra chứ không dừng
$out = & $py -X utf8 (Join-Path $PSScriptRoot '_tien_do_lam_tiep.py') $TestRoot (Join-Path $ToolsDir 'ghi-am-sang-word') 2>&1
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$n = 0; $xong = $false
foreach ($l in @($out | ForEach-Object { [string]$_ })) {
    if ($l -match '^KT ([01]) (.*)$') { $n++; Check ($Matches[1] -eq '1') $Matches[2] }
    elseif ($l -eq 'XONG') { $xong = $true }
    elseif ($l.Trim()) { Write-KT "  | $l" DarkGray }
}
Check ($code -eq 0 -and $xong) "phần Python chạy hết (mã $code)"
Check ($n -ge 25) "đủ các mục kiểm ($n)"

$tj = Get-Content (Join-Path $ToolsDir 'ghi-am-sang-word\tool.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$a = @($tj.actions | Where-Object { $_.id -eq 'chuyen-doi' })[0]
Check ($a.tienDo.flag -eq '--tien-do') 'tool.json: action chuyển đổi khai tienDo --tien-do'
$bat = [IO.File]::ReadAllText((Join-Path $ToolsDir 'ghi-am-sang-word\CHUYEN_DOI_GHI_AM.bat'))
Check ($bat -match '(?s)set "GHI_AM_CHAY_TIEP=1"\s*\r?\n\s*"\.venv\\Scripts\\python\.exe" -u "%~dp0chuyen_doi\.py" --cpu %\*') 'file .bat đặt GHI_AM_CHAY_TIEP trước khi chạy lại bằng CPU'

Complete-Test
