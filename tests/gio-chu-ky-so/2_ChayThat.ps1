# Chạy thật GioChuKySo.ps1 bằng quyền thường: Kiểm tra (chỉ đọc: hỏi máy chủ giờ, đọc dịch vụ, đầu đọc thẻ, kho chứng
# thư của tài khoản, danh sách phần mềm), Sửa giờ và Sửa token ở chế độ chạy thử (-ChayThu nên không hỏi UAC), chế độ
# sai, đã nâng quyền mà vẫn thiếu quyền. Kết quả vào thư mục tạm (GCK_KET_QUA). So cấu hình giờ, dịch vụ trước và sau.
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\KetQua.ps1"
$script = Join-Path $ToolsDir 'gio-chu-ky-so\GioChuKySo.ps1'
$ps = Join-Path $PSHOME 'powershell.exe'
$out = New-TestDir 'gck_that'
$env:GCK_KET_QUA = $out
Remove-Item Env:TRAMTOOL_GIOCHUKYSO_TEST -ErrorAction SilentlyContinue
if (Test-IsAdmin) { Skip-Test 'đang có quyền Admin: bài này chỉ chạy bằng quyền thường'; Complete-Test }

function Get-Snapshot {
    $p = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -ErrorAction SilentlyContinue
    $svc = foreach ($n in 'W32Time', 'SCardSvr', 'CertPropSvc') { "$n=" + (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$n" -ErrorAction SilentlyContinue).Start }
    return ('{0}|{1}|{2}|{3}' -f $p.Type, $p.NtpServer, [TimeZoneInfo]::Local.Id, ($svc -join ','))
}
function Run([string[]]$A) {
    $o = & $ps -NoProfile -ExecutionPolicy Bypass -File $script @A 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Latest { return @(Get-ChildItem -LiteralPath $out -Filter 'KetQua_GioChuKySo_*.json' | Sort-Object LastWriteTime -Descending)[0] }
$before = Get-Snapshot

$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Run @('-Mode', 'kiem-tra', '-KhongDung')
$f = Latest
Check ($r.Code -eq 0 -and $f) "Kiểm tra thật: mã 0, có file kết quả ($($r.Code), $([int]$sw.Elapsed.TotalSeconds) giây)"
if ($f) {
    $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json
    $codes = @($j.phatHien | ForEach-Object { $_.ma })
    Check ($j.cheDo -eq 'kiem-tra' -and -not $j.chayThu -and $codes.Count -ge 5) "đủ các nhóm phát hiện ($($codes -join ', '))"
    Check (@($codes | Where-Object { $_ -match '^(GIO_|KHONG_DO_DUOC_GIO)' }).Count -eq 1 -and @($codes | Where-Object { $_ -match '^MUI_GIO' }).Count -eq 1) 'đúng một phát hiện về độ lệch giờ, một về múi giờ'
    $hr = Read-RunResult -Path $f.FullName
    Check ($hr -and @($hr.phatHien).Count -eq $codes.Count) 'trạm đọc được file kết quả'
    Remove-Item -LiteralPath $f.FullName
}

$r = Run @('-Mode', 'sua-gio', '-MuiGioVN', '-ChayThu', '-KhongDung')
$f = Latest
Check ($r.Code -eq 0 -and $r.Out -match 'w32tm /resync /force') "Sửa giờ chạy thử (không hỏi UAC): mã 0, in việc sẽ làm ($($r.Code))"
if ($f) { $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json; Check ($j.cheDo -eq 'sua-gio' -and $j.chayThu -eq $true) 'kết quả ghi đúng chế độ, chạy thử'; Remove-Item -LiteralPath $f.FullName }
else { Check $false 'Sửa giờ chạy thử ghi file kết quả' }
$r = Run @('-Mode', 'sua-token', '-ChayThu', '-KhongDung')
Check ($r.Code -in 0, 1) "Sửa token chạy thử: không văng ($($r.Code))"
$r = Run @('-Mode', 'hoan-tac', '-ChayThu', '-KhongDung')
Check ($r.Code -eq 0) "Trả lại chạy thử khi chưa lưu gì: mã 0 ($($r.Code))"
Check (-not (Test-Path -LiteralPath (Join-Path $out "TrangThaiGoc_GioChuKySo_$env:COMPUTERNAME.json"))) 'chạy thử không lưu file giá trị cũ'

$r = Run @('-Mode', 'sua', '-KhongDung')
Check ($r.Code -eq 1 -and $r.Out -match '"sua"') "chế độ sai: mã 1 ($($r.Code))"
$r = Run @('-Mode', 'sua-token', '-DaNangQuyen', '-KhongDung')
Check ($r.Code -eq 2 -and $r.Out -match 'Admin') "đã mở lại mà chưa có quyền Admin: mã 2, không hỏi UAC lần nữa ($($r.Code))"

Check ((Get-Snapshot) -eq $before) 'cấu hình giờ, múi giờ, dịch vụ không đổi sau các lần chạy'
Remove-Item Env:GCK_KET_QUA
Complete-Test
