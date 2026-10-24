# Chạy thật TiengViet.ps1 bằng quyền thường: Kiểm tra (chỉ đọc: tiến trình bộ gõ, khởi động cùng Windows, danh sách
# ngôn ngữ, font, định dạng, Excel, bảng mã); Đặt định dạng, Trả lại ở chế độ chạy thử trên cài đặt thật; Đặt định dạng
# rồi Trả lại thật trên registry thử (TV_REG_GOC, bản chép định dạng thật); chế độ sai, kiểu sai, TIENG_VIET.bat không
# có bàn phím. Kết quả vào thư mục tạm (TV_KET_QUA). So định dạng thật trước và sau.
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\KetQua.ps1"
$toolDir = Join-Path $ToolsDir 'tieng-viet'
$script = Join-Path $toolDir 'TiengViet.ps1'
$ps = Join-Path $PSHOME 'powershell.exe'
$out = New-TestDir 'tv_that'
$env:TV_KET_QUA = $out
Remove-Item Env:TRAMTOOL_TIENGVIET_TEST, Env:TV_REG_GOC -ErrorAction SilentlyContinue
if (Test-IsAdmin) { Skip-Test 'đang có quyền Admin: bài này chỉ chạy bằng quyền thường'; Complete-Test }

$names = 'sDecimal', 'sThousand', 'sList', 'sShortDate', 'sMonDecimalSep', 'sMonThousandSep'
function Get-Snapshot([string]$Key = 'HKCU:\Control Panel\International') {
    $p = Get-ItemProperty -LiteralPath $Key
    $x = foreach ($v in '16.0', '15.0', '14.0') { "$v=" + (Get-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Office\$v\Excel\Options" -ErrorAction SilentlyContinue).UseSystemSeparators }
    return ((@($names | ForEach-Object { "$_=$($p.$_)" }) + $x) -join '|')
}
function Run([string[]]$A) {
    $o = & $ps -NoProfile -ExecutionPolicy Bypass -File $script @A 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}
function Latest { return @(Get-ChildItem -LiteralPath $out -Filter 'KetQua_TiengViet_*.json' | Sort-Object LastWriteTime -Descending)[0] }
$state = Join-Path $out ('TrangThaiGoc_TiengViet_{0}_{1}.json' -f $env:COMPUTERNAME, $env:USERNAME)
$before = Get-Snapshot

$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Run @('-Mode', 'kiem-tra', '-KhongDung')
$f = Latest
Check ($r.Code -eq 0 -and $f) "Kiểm tra thật: mã 0, có file kết quả ($($r.Code), $([int]$sw.Elapsed.TotalSeconds) giây)"
if ($f) {
    $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json
    $codes = @($j.phatHien | ForEach-Object { $_.ma })
    Check ($j.cheDo -eq 'kiem-tra' -and $j.congCu -eq 'tieng-viet' -and -not $j.chayThu) "đúng chế độ ($($codes -join ', '))"
    Check (@($codes | Where-Object { $_ -match '^(BO_GO_(DANG_CHAY|TRUNG|CHUA_CHAY)|BAN_PHIM_WINDOWS|KHONG_CO_BO_GO)$' }).Count -eq 1) 'đúng một kết luận về bộ gõ đang dùng'
    Check (@($codes | Where-Object { $_ -match '^FONT_CU_' }).Count -eq 1 -and @($codes | Where-Object { $_ -match '^NGAY_' }).Count -eq 1) 'một phát hiện về font cũ, một về mẫu ngày'
    Check (@($codes | Where-Object { $_ -match '^(SO_DINH_DANG|SO_DINH_DANG_KHAC|SO_TRUNG_DAU|DANH_SACH_TRUNG_THAP_PHAN|DINH_DANG_KHONG_DOC_DUOC)$' }).Count -eq 1) 'một kết luận về định dạng số'
    $hr = Read-RunResult -Path $f.FullName
    Check ($hr -and @($hr.phatHien).Count -eq $codes.Count) 'trạm đọc được file kết quả'
    Remove-Item -LiteralPath $f.FullName
}

foreach ($m in 'vn', 'quoc-te') {
    $r = Run @('-Mode', 'dinh-dang', '-Mau', $m, '-ExcelTheoWindows', '-ChayThu', '-KhongDung')
    Check ($r.Code -eq 0 -and $r.Out -match 'Chạy thử: không đổi gì|đã đúng như chọn') "Đặt định dạng $m chạy thử trên cài đặt thật: mã 0, chỉ in việc sẽ làm ($($r.Code))"
}
$f = Latest
if ($f) { $j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json; Check ($j.cheDo -eq 'dinh-dang' -and $j.chayThu -eq $true) 'kết quả ghi đúng chế độ, chạy thử' }
$r = Run @('-Mode', 'tra-lai', '-ChayThu', '-KhongDung')
Check ($r.Code -eq 0 -and $r.Out -match 'Chưa có giá trị cũ') "Trả lại chạy thử khi chưa lưu gì: mã 0 ($($r.Code))"
Check (-not (Test-Path -LiteralPath $state)) 'chạy thử không lưu file giá trị cũ'

# Đổi thật trên registry thử: chép định dạng thật vào khoá thử, Excel giả đang dùng dấu riêng.
Clear-TestRegistry
$root = 'HKCU:\Software\TramToolTest\TiengViet'
$k = "$root\Control Panel\International"
New-Item -Path $k -Force | Out-Null
$real = Get-ItemProperty 'HKCU:\Control Panel\International'
foreach ($n in $names + 'LocaleName') { Set-ItemProperty -LiteralPath $k -Name $n -Value ([string]$real.$n) }
$xk = "$root\Software\Microsoft\Office\16.0\Excel\Options"
New-Item -Path $xk -Force | Out-Null
Set-ItemProperty -LiteralPath $xk -Name UseSystemSeparators -Value 0 -Type DWord
$goc = (@($names | ForEach-Object { [string](Get-ItemProperty -LiteralPath $k).$_ }) -join '|')
$m = if ($real.sDecimal -eq ',') { 'quoc-te' } else { 'vn' }
$env:TV_REG_GOC = $root
# Excel đang mở (ở bất kỳ phiên nào) thì công cụ cố ý để nguyên tuỳ chọn Excel, trả mã 3.
$excelMo = [bool](Get-Process -Name 'EXCEL' -ErrorAction SilentlyContinue)
$r = Run @('-Mode', 'dinh-dang', '-Mau', $m, '-ExcelTheoWindows', '-KhongDung')
$p = Get-ItemProperty -LiteralPath $k
$want = if ($m -eq 'vn') { ',|.|;|dd/MM/yyyy|,|.' } else { '.|,|,|dd/MM/yyyy|.|,' }
$doiDu = (@($names | ForEach-Object { [string]$p.$_ }) -join '|') -eq $want
$xs = (Get-ItemProperty -LiteralPath $xk).UseSystemSeparators
if ($excelMo) {
    Check ($r.Code -eq 3 -and $doiDu -and $xs -eq 0 -and $r.Out -match 'Excel đang mở') "Đặt định dạng $m thật trên registry thử khi Excel đang mở: mã 3, đổi định dạng Windows, để nguyên tuỳ chọn Excel ($($r.Code))"
} else {
    Check ($r.Code -eq 0 -and $doiDu -and $xs -eq 1) "Đặt định dạng $m thật trên registry thử: mã 0, đổi đủ, Excel dùng dấu Windows ($($r.Code))"
}
Check ((Test-Path -LiteralPath $state) -and ([IO.File]::ReadAllText($state) | ConvertFrom-Json).dinhDang.sDecimal -eq $real.sDecimal) 'lưu giá trị cũ trước khi đổi'
$r = Run @('-Mode', 'tra-lai', '-KhongDung')
$p = Get-ItemProperty -LiteralPath $k
Check ($r.Code -eq 0 -and (@($names | ForEach-Object { [string]$p.$_ }) -join '|') -eq $goc -and (Get-ItemProperty -LiteralPath $xk).UseSystemSeparators -eq 0 -and -not (Test-Path -LiteralPath $state)) "Trả lại thật trên registry thử: như lúc đầu, xoá file giá trị cũ ($($r.Code))"
Remove-Item Env:TV_REG_GOC
Clear-TestRegistry

$r = Run @('-Mode', 'sua', '-KhongDung')
Check ($r.Code -eq 1 -and $r.Out -match '"sua"') "chế độ sai: mã 1 ($($r.Code))"
$r = Run @('-Mode', 'dinh-dang', '-Mau', 'my', '-KhongDung')
Check ($r.Code -eq 1 -and $r.Out -match '"my"') "kiểu định dạng sai: mã 1 ($($r.Code))"
$r = Invoke-Bat (Join-Path $toolDir 'TIENG_VIET.bat') @() -Env @{ TV_KET_QUA = $out }
Check ($r.Code -eq 1 -and $r.Out -match 'Cách dùng') "TIENG_VIET.bat không có bàn phím (chạy tự động): in cách dùng, mã 1, không treo ($($r.Code))"

Check ((Get-Snapshot) -eq $before) 'định dạng thật của tài khoản, tuỳ chọn Excel không đổi sau các lần chạy'
Remove-Item Env:TV_KET_QUA
Complete-Test
