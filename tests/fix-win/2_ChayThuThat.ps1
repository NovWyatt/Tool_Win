# Chạy thật SuaLoi.ps1 bằng quyền thường ở chế độ chạy thử (-ChayThu: không hỏi UAC, không đổi máy): quét ổ đĩa (đọc
# sức khoẻ ổ vật lý), đặt lại mạng (đọc IP, DNS đặt tay), Windows Update; chế độ sai; đã nâng quyền mà vẫn thiếu
# quyền. File kết quả vào thư mục tạm (FIX_KET_QUA).
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\KetQua.ps1"
$out = New-TestDir 'fix_that'
$env:FIX_KET_QUA = $out
Remove-Item Env:TRAMTOOL_SUALOI_TEST -ErrorAction SilentlyContinue
if (Test-IsAdmin) { Skip-Test 'đang có quyền Admin: bài này chỉ chạy bằng quyền thường'; Complete-Test }
$script = "$ToolsDir\fix-win\SuaLoi.ps1"
$ps = Join-Path $PSHOME 'powershell.exe'
function Run([string[]]$A) {
    $o = & $ps -NoProfile -ExecutionPolicy Bypass -File $script @A 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}

foreach ($m in @(@('o-dia-quet', 'ODiaQuet'), @('mang', 'Mang'), @('windows-update', 'WindowsUpdate'))) {
    $r = Run @('-Mode', $m[0], '-ChayThu', '-KhongDung')
    $f = @(Get-ChildItem -LiteralPath $out -Filter "KetQua_SuaLoi_$($m[1])_*.json")
    Check ($r.Code -eq 0 -and $f.Count -eq 1 -and $r.Out -match 'Chạy thử') "$($m[0]) chạy thử: mã $($r.Code), một file kết quả"
    if ($f.Count) {
        $j = [IO.File]::ReadAllText($f[0].FullName) | ConvertFrom-Json
        $hr = Read-RunResult -Path $f[0].FullName
        Check ($j.cheDo -eq $m[0] -and $j.chayThu -eq $true -and $j.trangThai -eq 'xong' -and $hr) "$($m[0]): đúng chế độ, chạy thử, trạm đọc được ($(@($j.phatHien | ForEach-Object { $_.ma }) -join ', '))"
    }
}
$r = Run @('-Mode', 'sua-het', '-KhongDung')
Check ($r.Code -eq 1 -and $r.Out -match '"sua-het"') "chế độ sai: mã 1 ($($r.Code))"
$r = Run @('-Mode', 'sfc', '-DaNangQuyen', '-KhongDung')
Check ($r.Code -eq 2 -and $r.Out -match 'Admin') "đã mở lại mà chưa có quyền Admin: mã 2, không hỏi UAC lần nữa ($($r.Code))"
Remove-Item Env:FIX_KET_QUA
Complete-Test
