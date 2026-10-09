# Chạy thật BoUngDung.ps1 bằng quyền thường: Kiểm tra (chỉ đọc: winget export), Cài và Cập nhật ở chế độ chạy thử
# (-ChayThu nên không hỏi UAC, không cài gì), chế độ sai, cờ ứng dụng lạ, đã nâng quyền mà vẫn thiếu quyền. Kết quả vào
# thư mục tạm (BUD_KET_QUA). So danh sách phần mềm đã cài (Programs and Features) trước và sau.
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\KetQua.ps1"
$script = Join-Path $ToolsDir 'bo-ung-dung\BoUngDung.ps1'
$ps = Join-Path $PSHOME 'powershell.exe'
$out = New-TestDir 'bud_that'
$env:BUD_KET_QUA = $out
Remove-Item Env:TRAMTOOL_BOUNGDUNG_TEST -ErrorAction SilentlyContinue
if (Test-IsAdmin) { Skip-Test 'đang có quyền Admin: bài này chỉ chạy bằng quyền thường'; Complete-Test }
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Skip-Test 'máy chưa có winget'; Complete-Test }

function Get-Snapshot {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    return ((Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object { "$($_.DisplayName) $($_.DisplayVersion)" } | Sort-Object) -join '|')
}
function Run([string[]]$A) {
    $o = & $ps -NoProfile -ExecutionPolicy Bypass -File $script @A 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Latest { return @(Get-ChildItem -LiteralPath $out -Filter 'KetQua_BoUngDung_*.json' | Sort-Object LastWriteTime -Descending)[0] }
$before = Get-Snapshot

$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Run @('-Mode', 'kiem-tra', '-KhongDung')
$f = Latest
Check ($r.Code -eq 0 -and $f) "Kiểm tra thật: mã 0, có file kết quả ($($r.Code), $([int]$sw.Elapsed.TotalSeconds) giây)"
if ($f) {
    $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json
    $codes = @($j.phatHien | ForEach-Object { $_.ma })
    Check ($j.cheDo -eq 'kiem-tra' -and -not $j.chayThu -and @($codes | Where-Object { $_ -match '^UNG_DUNG_' }).Count -ge 1 -and $codes -notcontains 'WINGET_LOI') "đọc được danh sách đã cài ($($codes -join ', '))"
    $hr = Read-RunResult -Path $f.FullName
    Check ($hr -and @($hr.phatHien).Count -eq $codes.Count) 'trạm đọc được file kết quả'
    Remove-Item -LiteralPath $f.FullName
}

$r = Run @('-Mode', 'cai', '-ChayThu', '-KhongDung', '-Foxit', '-UniKey', '-EVKey')
$f = Latest
Check ($r.Code -eq 0 -and $r.Out -match 'Chạy thử: không cài gì|Không có ứng dụng nào cần cài') "Cài chạy thử (không hỏi UAC): mã 0 ($($r.Code))"
Check ($r.Out -match 'EVKey' -and $r.Out -notmatch 'winget install --id lamquangminh\.EVKey') 'chọn cả hai bộ gõ: không định cài EVKey'
if ($f) { $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json; Check ($j.cheDo -eq 'cai' -and $j.chayThu -eq $true) 'kết quả ghi đúng chế độ, chạy thử'; Remove-Item -LiteralPath $f.FullName }
else { Check $false 'Cài chạy thử ghi file kết quả' }
$r = Run @('-Mode', 'cap-nhat', '-ChayThu', '-KhongDung')
Check ($r.Code -eq 0) "Cập nhật chạy thử: mã 0 ($($r.Code))"

$r = Run @('-Mode', 'go', '-KhongDung')
Check ($r.Code -eq 1 -and $r.Out -match '"go"') "chế độ sai: mã 1 ($($r.Code))"
$r = Run @('-Mode', 'cai', '-ChayThu', '-KhongDung', '-KhongCo')
Check ($r.Code -eq 1 -and $r.Out -match 'KhongCo' -and $r.Out -match '-SevenZip') "cờ ứng dụng lạ: mã 1, kể các cờ chọn được ($($r.Code))"
$r = Run @('-Mode', 'cai', '-DaNangQuyen', '-KhongDung', '-Foxit')
Check ($r.Code -eq 2 -and $r.Out -match 'Admin') "đã mở lại mà chưa có quyền Admin: mã 2, không hỏi UAC lần nữa ($($r.Code))"

Check ((Get-Snapshot) -eq $before) 'danh sách phần mềm đã cài không đổi sau các lần chạy'
Remove-Item Env:BUD_KET_QUA
Complete-Test
