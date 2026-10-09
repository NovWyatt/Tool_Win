# Chạy thật Office.ps1 bằng quyền thường: Kiểm tra (chỉ đọc) và Gỡ sạch ở chế độ chạy thử (-ChayThu: không hỏi UAC,
# không đổi máy). Thư mục mẫu là một thư mục rỗng trong tests\.tam: không đọc tới bộ cài mẫu thật (file cấu hình có
# khoá sản phẩm). Báo cáo, file kết quả vào thư mục tạm (OFFICE_KET_QUA).
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\KetQua.ps1"
if (Test-IsAdmin) { Skip-Test 'đang có quyền Admin: bài này chỉ chạy bằng quyền thường'; Complete-Test }
$out = New-TestDir 'office_that'
$mau = New-TestDir 'office_mau_rong'
$env:OFFICE_KET_QUA = $out
$script = "$ToolsDir\office\Office.ps1"
$ps = Join-Path $PSHOME 'powershell.exe'
$keyRe = '(?i)\b[A-Z0-9]{5}(-[A-Z0-9]{5}){4}\b'
function Run([string[]]$A) {
    $o = & $ps -NoProfile -ExecutionPolicy Bypass -File $script @A 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}

$r = Run @('-Mode', 'kiem-tra', '-Mau', $mau, '-KhongDung')
$f = @(Get-ChildItem -LiteralPath $out -Filter 'KetQua_Office_KiemTra_*.json')
Check ($r.Code -eq 0 -and $f.Count -eq 1) "kiểm tra: mã $($r.Code), một file kết quả"
if ($f.Count) {
    $txt = [IO.File]::ReadAllText($f[0].FullName)
    $j = $txt | ConvertFrom-Json
    $hr = Read-RunResult -Path $f[0].FullName
    $ma = @($j.phatHien | ForEach-Object { $_.ma })
    Check ($j.cheDo -eq 'kiem-tra' -and $j.phienBan -eq '1.1' -and $j.trangThai -eq 'xong' -and $j.chayThu -eq $false -and $hr) "kiểm tra: đúng chế độ, phiên bản, trạm đọc được ($($ma -join ', '))"
    Check ($ma -contains 'MAU_HONG' -and $ma -notcontains 'KHONG_CO_VAN_DE' -and $j.ma -eq 'CO_LOI') 'mẫu rỗng: báo MAU_HONG, không kết luận ổn'
    $tep = @($j.tep)
    Check ($tep.Count -eq 1 -and $tep[0].duongDan -like "$out\BaoCao_Office_*.txt" -and (Test-Path -LiteralPath $tep[0].duongDan)) 'kèm báo cáo .txt trong thư mục tạm'
    $rep = if ($tep.Count -and (Test-Path -LiteralPath $tep[0].duongDan)) { [IO.File]::ReadAllText($tep[0].duongDan) } else { '' }
    Check ($txt -notmatch $keyRe -and $rep -notmatch $keyRe -and $txt -notmatch 'PIDKEY') 'không có chuỗi dạng khoá sản phẩm trong JSON, báo cáo'
}

$r = Run @('-Mode', 'go-sach', '-Mau', $mau, '-ChayThu', '-KhongDung')
$f = @(Get-ChildItem -LiteralPath $out -Filter 'KetQua_Office_GoSach_*.json')
Check ($r.Code -eq 0 -and $f.Count -eq 1 -and $r.Out -notmatch 'UAC') "gỡ sạch chạy thử: mã $($r.Code), một file kết quả, không hỏi UAC"
if ($f.Count) {
    $txt = [IO.File]::ReadAllText($f[0].FullName)
    $j = $txt | ConvertFrom-Json
    Check ($j.cheDo -eq 'go-sach' -and $j.chayThu -eq $true -and $j.trangThai -eq 'xong' -and -not @($j.tep).Count -and (Read-RunResult -Path $f[0].FullName)) "gỡ sạch chạy thử: chayThu, không nhật ký ($($j.thongDiep))"
    Check ($txt -notmatch $keyRe) 'gỡ sạch chạy thử: không có chuỗi dạng khoá sản phẩm'
}
Check (-not @(Get-ChildItem -LiteralPath $out -Filter 'NhatKy_Office_*').Count) 'chạy thử không ghi nhật ký'

$r = Run @('-Mode', 'go-het', '-KhongDung')
Check ($r.Code -eq 1 -and $r.Out -match '"go-het"' -and @(Get-ChildItem -LiteralPath $out -Filter 'KetQua_Office_*.json').Count -eq 2) "chế độ sai: mã 1, không ghi kết quả ($($r.Code))"
Remove-Item Env:OFFICE_KET_QUA
Complete-Test
