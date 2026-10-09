# Chạy thật Chẩn đoán của Máy in LAN bằng quyền thường (chỉ đọc: mạng, dịch vụ, tường lửa, SMB, máy in, ổ mạng, nhật
# ký; không gọi máy khác vì không nhập -MayChu). Báo cáo và file kết quả vào thư mục tạm (MIL_KET_QUA).
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\KetQua.ps1"
$out = New-TestDir 'mil_that'
$env:MIL_KET_QUA = $out
if (Test-IsAdmin) { Skip-Test 'đang có quyền Admin: bài này chỉ chạy bằng quyền thường'; Complete-Test }
$manifest = [IO.File]::ReadAllText("$ToolsDir\may-in-lan\tool.json", [Text.Encoding]::UTF8) | ConvertFrom-Json
$actionIds = @($manifest.actions | ForEach-Object { $_.id })

$sw = [Diagnostics.Stopwatch]::StartNew()
$o = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File "$ToolsDir\may-in-lan\MayInLan.ps1" -Mode chan-doan -KhongDung 2>&1 | Out-String
$code = $LASTEXITCODE
$json = @(Get-ChildItem -LiteralPath $out -Filter 'KetQua_MayIn_ChanDoan_*.json')
$txt = @(Get-ChildItem -LiteralPath $out -Filter 'BaoCao_MayIn_*.txt')
Check ($code -eq 0 -and $json.Count -eq 1 -and $txt.Count -eq 1) "Chẩn đoán thật: mã 0, một báo cáo, một file kết quả ($code, $($txt.Count), $($json.Count); $([int]$sw.Elapsed.TotalSeconds) giây)"
Check ($o -notmatch 'Lỗi không lường trước|Không đọc được phần này') 'các phần của báo cáo đều đọc được'
if ($json.Count) {
    $j = [IO.File]::ReadAllText($json[0].FullName) | ConvertFrom-Json
    $ph = @($j.phatHien)
    Check ($j.chuan -eq 'tramtool.ketqua/1' -and $j.cheDo -eq 'chan-doan' -and $ph.Count -ge 1 -and @($j.tep)[0].duongDan -eq $txt[0].FullName) "đầu file, có phát hiện, trỏ tới báo cáo ($(@($ph | ForEach-Object { $_.ma }) -join ', '))"
    Check (-not @($ph | Where-Object { $_.ma -notmatch '^[A-Z][A-Z0-9_]+$' -or $_.mucDo -notin 'loi', 'canh-bao', 'thong-tin', 'ok' }).Count) 'mã, mức hợp lệ'
    Check (-not @($ph | Where-Object { $_.chayTiep -and $actionIds -notcontains $_.chayTiep.action }).Count) 'nút sửa trỏ tới action có thật'
    $hr = Read-RunResult -Path $json[0].FullName
    Check ($hr -and @($hr.phatHien).Count -eq $ph.Count) 'trạm đọc được file kết quả'
}
Remove-Item Env:MIL_KET_QUA
Complete-Test
