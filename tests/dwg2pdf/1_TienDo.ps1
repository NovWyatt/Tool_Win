# Bài thử dwg2pdf: tiến độ cho Trạm Tool (tramtool.tiendo/1): đọc bước từ nhật ký convert.py, gộp phần trăm cả lô,
# chạy main() với 2 bản vẽ giả (đổi DXF và convert.py được thay bằng bản giả), bản vẽ đã có PDF vẫn tính là xong.
# Phần kiểm nằm trong _tien_do.py, chạy bằng Python của máy: không cần .venv, LibreDWG; mọi file trong thư mục tạm.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$py = Find-Python
if (-not $py) { Skip-Test 'không thấy Python'; Complete-Test }

$env:PYTHONDONTWRITEBYTECODE = '1'   # không để lại __pycache__ mới trong thư mục công cụ
$env:PYTHONIOENCODING = 'utf-8'
$ErrorActionPreference = 'Continue'   # dòng stderr của Python (traceback) thành ErrorRecord: in ra chứ không dừng
$out = & $py -X utf8 (Join-Path $PSScriptRoot '_tien_do.py') $TestRoot (Join-Path $ToolsDir 'dwg2pdf') 2>&1
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
$n = 0; $xong = $false
foreach ($l in @($out | ForEach-Object { [string]$_ })) {
    if ($l -match '^KT ([01]) (.*)$') { $n++; Check ($Matches[1] -eq '1') $Matches[2] }
    elseif ($l -eq 'XONG') { $xong = $true }
    elseif ($l.Trim()) { Write-KT "  | $l" DarkGray }
}
Check ($code -eq 0 -and $xong) "phần Python chạy hết (mã $code)"
Check ($n -ge 12) "đủ các mục kiểm ($n)"

$tj = Get-Content (Join-Path $ToolsDir 'dwg2pdf\tool.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($id in 'chuyen-thu-muc', 'chuyen-file') {
    $a = @($tj.actions | Where-Object { $_.id -eq $id })[0]
    Check ($a.tienDo.flag -eq '--tien-do') "tool.json: action $id khai tienDo --tien-do"
}
$bat = [IO.File]::ReadAllText((Join-Path $ToolsDir 'dwg2pdf\CHUYEN_DWG_SANG_PDF.bat'))
Check ($bat -match 'chuyen_dwg_sang_pdf\.py" %\*') 'file .bat chuyển mọi tham số (cả --tien-do) cho Python'

Complete-Test
