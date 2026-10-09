# Kiểm tra (chỉ đọc) không dùng MYX_OUT: báo cáo, JSON vào thư mục riêng của tài khoản, bản sao để gửi trên Desktop,
# chỉ snapshot ở thư mục chung; số và tên chủ tài khoản đã che trong báo cáo. LOCALAPPDATA, PUBLIC, Desktop trỏ vào
# thư mục tạm; dữ liệu MyExcel đọc từ nhánh thử (MYX_VBROOT) có tài khoản ngân hàng giả.
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
. "$PSScriptRoot\_GiaLap.ps1"
$root = Join-Path $TestRoot 'fx6'
$rb = 'Software\TramToolTest\Myx6\'
New-Fixture $root $rb
$envDir = New-TestDir 'fx6env'
$lad = Join-Path $envDir 'localappdata'; $pub = Join-Path $envDir 'public'; $desk = Join-Path $envDir 'desktop'
$shared = Join-Path $pub 'Documents\MyExcelCheck'
New-Item -ItemType Directory -Path $lad, $desk, $shared -Force | Out-Null
$c = $env:COMPUTERNAME; $u = $env:USERNAME -replace '[^\w\.-]', '_'
Set-Content (Join-Path $shared "BaoCao_MyExcel_$($c)_$($u)_20250101_000000.txt") 'bao cao cu' -Encoding UTF8
Set-Content (Join-Path $shared "snapshot_$($c)_nguoikhac.json") '{ "_User": "nguoikhac", "_Time": "01/01/2025 00:00", "Sec.VBAWarnings": "khac" }' -Encoding ASCII

$envChk = @{
    LOCALAPPDATA = $lad; PUBLIC = $pub; MYX_DESKTOP = $desk; MYX_NO_NOTEPAD = '1'; MYX_NOPAUSE = '1'
    MYX_VBROOT = "HKCU:\$($rb)Software\VB and VBA Program Settings"
}
Write-Host '== T6a: kiểm tra, nơi lưu mới ==' -ForegroundColor Cyan
$r = Invoke-Bat "$Tool\CheckMyExcel_VietQR.bat" -Env $envChk -TimeoutSec 300
$r.Out | Set-Content (Join-Path $envDir 'check_out.txt') -Encoding UTF8
Check ($r.Code -eq 0) "mã thoát 0 ($($r.Code), $($r.Sec)s)"
$resDir = Join-Path $lad 'MyExcelFix\BaoCao'
$rep = @(Get-ChildItem $resDir -Filter "BaoCao_MyExcel_$($c)_$($u)_*.txt" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*_20250101_000000.txt' })
Check ($rep.Count -eq 1) 'báo cáo trong %LOCALAPPDATA%\MyExcelFix\BaoCao'
Check (@(Get-ChildItem $resDir -Filter 'KetQua_MyExcel_KiemTra_*.json' -ErrorAction SilentlyContinue).Count -eq 1) 'JSON kết quả trong thư mục riêng'
Check (Test-Path (Join-Path $resDir "BaoCao_MyExcel_$($c)_$($u)_20250101_000000.txt")) 'báo cáo cũ của tài khoản này được chuyển sang thư mục riêng'
$deskCopy = @(Get-ChildItem $desk -Filter 'BaoCao_MyExcel_*.txt')
Check ($deskCopy.Count -eq 1 -and $rep.Count -eq 1 -and $deskCopy[0].Name -eq $rep[0].Name) 'bản sao để gửi trên Desktop'
$sharedNow = @(Get-ChildItem $shared -File | ForEach-Object { $_.Name } | Sort-Object)
Check (($sharedNow -join '|') -eq ((@("snapshot_$($c)_$($u).json", "snapshot_$($c)_nguoikhac.json") | Sort-Object) -join '|')) "thư mục chung chỉ có snapshot ($($sharedNow -join ', '))"
Check ($r.Out -match "profile 'nguoikhac'") 'vẫn so sánh được với profile khác qua snapshot ở thư mục chung'
$snap = Get-Content (Join-Path $shared "snapshot_$($c)_$($u).json") -Raw -Encoding UTF8
Check ($snap -notmatch '000011112222' -and $snap -notmatch 'NGUOI THU NGHIEM') 'snapshot không có số, tên chủ tài khoản'
if ($rep.Count -eq 1) {
    $txt = Get-Content $rep[0].FullName -Raw -Encoding UTF8
    Check ($txt -match 'TenTKQRG = N\*{4} T\*{2} N\*{5}') 'tên chủ tài khoản đã che (NGUOI THU NGHIEM -> N**** T** N*****)'
    Check ($txt -notmatch 'NGUOI THU NGHIEM' -and $txt -notmatch '000011112222') 'báo cáo không có tên, số tài khoản đầy đủ'
    Check ($txt -match 'MyExcelFix\\MyExcel_data_backup\.reg' -and $txt -notmatch 'Desktop\\MyExcel_data_backup') 'hướng dẫn tay xuất .reg vào thư mục riêng, không ra Desktop'
}

Assert-RealUntouched
Clear-TestRegistry
Complete-Test
