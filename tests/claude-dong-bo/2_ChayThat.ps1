# Chạy thật DongBoClaude.ps1 trên dữ liệu Claude Desktop của máy, chỉ các chế độ không ghi: Kiểm tra (đọc danh sách
# phiên, nội dung hội thoại), Sao lưu và Đồng bộ ở chế độ chạy thử. Kết quả, nhãn tài khoản vào thư mục tạm
# (CDB_KET_QUA, CDB_DU_LIEU). So tên file trong claude-code-sessions trước và sau: công cụ không thêm, không xoá gì.
# Máy chưa cài Claude Desktop thì bỏ qua.
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\KetQua.ps1"
$toolDir = Join-Path $ToolsDir 'claude-dong-bo'
$script = Join-Path $toolDir 'DongBoClaude.ps1'
$ps = Join-Path $PSHOME 'powershell.exe'
Remove-Item Env:TRAMTOOL_CLAUDEDONGBO_TEST, Env:CDB_CLAUDE_APPDATA, Env:CDB_NGUOI_DUNG, Env:CDB_MAU_CLAUDE -ErrorAction SilentlyContinue
$env:CDB_KET_QUA = New-TestDir 'ket_qua'
$env:CDB_DU_LIEU = New-TestDir 'du-lieu'

$app = Join-Path $env:APPDATA 'Claude'
if (-not (Test-Path -LiteralPath (Join-Path $app 'config.json'))) { Skip-Test 'máy chưa cài Claude Desktop'; Complete-Test }
$sess = Join-Path $app 'claude-code-sessions'
# Chỉ so mục danh sách và dấu đã xoá: Claude Desktop đang chạy có thể ghi file tạm của chính nó trong lúc thử.
function Get-Names { return (@(Get-ChildItem -LiteralPath $sess -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(local_.*\.json|deleted_.*)$' } | ForEach-Object { $_.FullName }) | Sort-Object) -join '|' }
function Get-ToolData { return @(Get-ChildItem -LiteralPath (Join-Path $toolDir 'du-lieu'), (Join-Path $toolDir 'ket_qua') -Recurse -File -Force -ErrorAction SilentlyContinue).Count }
function Run([string[]]$A) {
    $o = & $ps -NoProfile -ExecutionPolicy Bypass -File $script @A 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Latest { return @(Get-ChildItem -LiteralPath $env:CDB_KET_QUA -Filter 'KetQua_ClaudeDongBo_*.json' | Sort-Object LastWriteTime, Name -Descending)[0] }
$before = Get-Names
$toolBefore = Get-ToolData

$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Run @('-Mode', 'kiem-tra', '-KhongDung')
$f = Latest
Check ($r.Code -eq 0 -and $f) "Kiểm tra thật: mã 0, có file kết quả ($($r.Code), $([int]$sw.Elapsed.TotalSeconds) giây)"
if ($f) {
    $hr = Read-RunResult -Path $f.FullName
    $codes = @($hr.phatHien | ForEach-Object { $_.ma })
    Check ($codes -contains 'TAI_KHOAN_DANG_DUNG') "thấy tài khoản đang đăng nhập ($($codes -join ', '))"
    $t = @($hr.phatHien | Where-Object { $_.ma -eq 'TAI_KHOAN_DANG_DUNG' })[0].tieuDe
    Check ($t -match ': (\d+) phiên' -and [int]$Matches[1] -ge 1) "đọc được danh sách phiên thật: $($t -replace '^.*: ', '')"
    Check (-not @($codes | Where-Object { $_ -match '^(CHUA_|DONG_BO_LOI)' }).Count) 'không báo thiếu điều kiện'
    Check (-not @($codes | Where-Object { $_ -in 'CACH_LUU_DA_DOI', 'MUC_KHONG_HOP_LE' }).Count) "danh sách phiên thật đúng cấu trúc công cụ biết (bản Claude $(([IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json).banClaude))"
}
$r = Run @('-Mode', 'sao-luu', '-ChayThu', '-KhongDung')
Check ($r.Code -eq 0 -and $r.Out -match 'phiên có nội dung, gói khoảng' -and -not @(Get-ChildItem -LiteralPath $env:CDB_DU_LIEU -Directory -Filter 'Goi_*').Count) "Sao lưu chạy thử: mã 0, tính được dung lượng, không tạo gói ($($r.Code))"
$r = Run @('-Mode', 'sao-luu', '-ChayThu', '-MaHoa', '-KhongDung')
Check ($r.Code -eq 0 -and $r.Out -match 'Nén, mã hoá thành' -and -not @(Get-ChildItem -LiteralPath $env:CDB_DU_LIEU -Recurse -File -Filter '*.aes').Count) "Sao lưu chạy thử -MaHoa: không hỏi mật khẩu, không tạo file ($($r.Code))"
$desk = [Environment]::GetFolderPath('Desktop')
$lnkBefore = Test-Path -LiteralPath (Join-Path $desk 'Mở Claude (đồng bộ phiên).lnk')
$r = Run @('-Mode', 'loi-tat', '-ChayThu', '-KhongDung')
Check ($r.Code -eq 0 -and (Test-Path -LiteralPath (Join-Path $desk 'Mở Claude (đồng bộ phiên).lnk')) -eq $lnkBefore) "Tạo lối tắt chạy thử: mã 0, màn hình thật không đổi ($($r.Code))"
$r = Run @('-Mode', 'mo-claude', '-ChayThu', '-KhongDung')
Check ($r.Code -eq 0 -and $r.Out -match 'không mở Claude') "Mở Claude chạy thử: mã 0, không đồng bộ, không mở Claude ($($r.Code))"
$env:TRAMTOOL_CLAUDEDONGBO_TEST = '1'
. $script
Remove-Item Env:TRAMTOOL_CLAUDEDONGBO_TEST
$id = Get-ClaudeAppId
$exe = if (Get-ClaudePackage) { $id -match '^Claude_[a-z0-9]+!\w+$' } else { $true }
Check $exe "mã ứng dụng để mở Claude bản Microsoft Store: $(if ($id) { $id } else { 'không phải bản Store' })"
$r = Run @('-Mode', 'dong-bo', '-ChayThu', '-KhongDung')
Check ($r.Code -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $env:CDB_DU_LIEU 'HoanTac'))) "Đồng bộ chạy thử: mã 0, không tạo nhật ký ($($r.Code))"
$r = Run @('-Mode', 'hoan-tac', '-ChayThu', '-KhongDung')
Check ($r.Code -eq 0 -and $r.Out -match 'Không có lần đồng bộ nào') "Hoàn tác chạy thử khi chưa đồng bộ: mã 0 ($($r.Code))"

Check ((Get-Names) -eq $before) 'claude-code-sessions thật: không thêm, không xoá file nào'
Check ((Get-ToolData) -eq $toolBefore) 'không ghi vào du-lieu, ket_qua của công cụ'
Remove-Item Env:CDB_KET_QUA, Env:CDB_DU_LIEU
Complete-Test
