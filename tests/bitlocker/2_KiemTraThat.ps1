# Chạy thật Kiểm tra của BitLocker bằng quyền thường (chỉ đọc: TPM, nhật ký BitLocker, tìm file khoá theo Mã khoá;
# không đọc được từng ổ vì thiếu quyền Admin). Báo cáo và file kết quả vào thư mục tạm (BDE_KET_QUA).
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\KetQua.ps1"
$out = New-TestDir 'bde_that'
$env:BDE_KET_QUA = $out
if (Test-IsAdmin) { Skip-Test 'đang có quyền Admin: bài này chỉ chạy bằng quyền thường'; Complete-Test }
$manifest = [IO.File]::ReadAllText("$ToolsDir\bitlocker\tool.json", [Text.Encoding]::UTF8) | ConvertFrom-Json
$actionIds = @($manifest.actions | ForEach-Object { $_.id })

$sw = [Diagnostics.Stopwatch]::StartNew()
$o = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File "$ToolsDir\bitlocker\BitLocker.ps1" -Mode kiem-tra -KhongDung 2>&1 | Out-String
$code = $LASTEXITCODE
$json = @(Get-ChildItem -LiteralPath $out -Filter 'KetQua_BitLocker_KiemTra_*.json')
$txt = @(Get-ChildItem -LiteralPath $out -Filter 'BaoCao_BitLocker_*.txt')
Check ($code -eq 0 -and $json.Count -eq 1 -and $txt.Count -eq 1) "Kiểm tra thật: mã 0, một báo cáo, một file kết quả ($code, $($txt.Count), $($json.Count); $([int]$sw.Elapsed.TotalSeconds) giây)"
Check ($o -notmatch 'Lỗi không lường trước|Không đọc được phần này') 'các phần của báo cáo đều đọc được'
if ($json.Count) {
    $j = [IO.File]::ReadAllText($json[0].FullName) | ConvertFrom-Json
    $ph = @($j.phatHien)
    Check ($j.chuan -eq 'tramtool.ketqua/1' -and $j.cheDo -eq 'kiem-tra' -and @($ph | ForEach-Object { $_.ma }) -contains 'CHAY_QUYEN_THUONG' -and @($ph | ForEach-Object { $_.ma }) -notcontains 'KHONG_CO_VAN_DE' -and $j.thongDiep -match 'quyền Admin' -and @($j.tep)[0].duongDan -eq $txt[0].FullName) "đầu file, báo chạy quyền thường (không kết luận ổn), trỏ tới báo cáo ($(@($ph | ForEach-Object { $_.ma }) -join ', '))"
    Check (-not @($ph | Where-Object { $_.ma -notmatch '^[A-Z][A-Z0-9_]+$' -or ($_.chayTiep -and $actionIds -notcontains $_.chayTiep.action) }).Count) 'mã hợp lệ, nút trỏ tới action có thật'
    Check ([IO.File]::ReadAllText($json[0].FullName) -notmatch '\d{6}-\d{6}-\d{6}-\d{6}-\d{6}-\d{6}-\d{6}-\d{6}') 'file kết quả không có chuỗi dạng khoá khôi phục'
    $hr = Read-RunResult -Path $json[0].FullName
    Check ($hr -and @($hr.phatHien).Count -eq $ph.Count) 'trạm đọc được file kết quả'
}
Remove-Item Env:BDE_KET_QUA
Complete-Test
