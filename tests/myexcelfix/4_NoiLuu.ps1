# Nơi lưu dữ liệu khách (bản 2026.10.2): sửa, hoàn tác không dùng MYX_OUT; LOCALAPPDATA, PUBLIC, Desktop (MYX_DESKTOP)
# đều trỏ vào thư mục tạm. Sao lưu và kết quả phải vào thư mục riêng của tài khoản, không ra Desktop hay Public
# Documents; ThongTinKhaiBao.txt chỉ ghi khi thật sự đặt lại; HOAN_TAC.bat không kèm thư mục thì cho chọn bản sao lưu.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
. "$PSScriptRoot\_GiaLap.ps1"
if (Test-ExcelOpenHere) { Skip-Test 'Excel đang mở trong phiên này (bản sửa chờ đóng Excel): đóng Excel rồi chạy lại'; Complete-Test }
$root = Join-Path $TestRoot 'fx5'
$rb = 'Software\TramToolTest\Myx5\'
New-Fixture $root $rb
$envDir = New-TestDir 'fx5env'
$lad = Join-Path $envDir 'localappdata'; $pub = Join-Path $envDir 'public'; $desk = Join-Path $envDir 'desktop'
$shared = Join-Path $pub 'Documents\MyExcelCheck'
New-Item -ItemType Directory -Path $lad, $desk, $shared -Force | Out-Null
$c = $env:COMPUTERNAME; $u = $env:USERNAME -replace '[^\w\.-]', '_'
# Kết quả của bản cũ trong thư mục chung: của tài khoản này (phải được chuyển đi) và của tài khoản khác (để nguyên)
Set-Content (Join-Path $shared "BaoCao_MyExcel_$($c)_$($u)_20250101_000000.txt") 'bao cao cu' -Encoding UTF8
Set-Content (Join-Path $shared "KetQua_MyExcel_Sua_$($c)_$($u)_20250101_000000.json") '{}' -Encoding ASCII
Set-Content (Join-Path $shared "BaoCao_MyExcel_$($c)_nguoikhac_20250101_000000.txt") 'cua nguoi khac' -Encoding UTF8
Set-Content (Join-Path $shared "snapshot_$($c)_nguoikhac.json") '{ "_User": "nguoikhac", "_Time": "01/01/2025 00:00" }' -Encoding ASCII

function Get-PlaceEnv([hashtable]$Extra = @{}) {
    $e = Get-FixEnv $root $rb
    $e.MYX_OUT = ''                      # rỗng: Invoke-Bat xoá biến, công cụ dùng nơi lưu thật (đã trỏ vào thư mục tạm)
    $e.LOCALAPPDATA = $lad; $e.PUBLIC = $pub; $e.MYX_DESKTOP = $desk
    foreach ($k in $Extra.Keys) { $e[$k] = $Extra[$k] }
    return $e
}
$bakRoot = Join-Path $lad 'MyExcelFix\SaoLuu'
$resDir = Join-Path $lad 'MyExcelFix\BaoCao'

Write-Host '== T5a: sửa, thử QR trước và chạy được (không đặt lại dữ liệu) ==' -ForegroundColor Cyan
$r = Invoke-Bat "$Tool\FixMyExcel_VietQR.bat" -Env (Get-PlaceEnv @{ MYX_RESET_NOW = '0'; MYX_QR_OK = '1' })
$r.Out | Set-Content (Join-Path $envDir 'fix_a.txt') -Encoding UTF8
Check ($r.Code -eq 0) "mã thoát 0 ($($r.Code), $($r.Sec)s)"
$bks = @(Get-ChildItem $bakRoot -Directory -Filter 'MyExcelFix_SaoLuu_*' -ErrorAction SilentlyContinue)
Check ($bks.Count -eq 1 -and (Test-Path (Join-Path $bks[0].FullName 'manifest.json'))) "sao lưu nằm trong %LOCALAPPDATA%\MyExcelFix\SaoLuu ($($bks.Count))"
$bkA = $bks[0].FullName
Check (@(Get-ChildItem $desk -Force -ErrorAction SilentlyContinue).Count -eq 0) 'không ghi gì ra Desktop'
Check (-not (Test-Path (Join-Path $bkA 'ThongTinKhaiBao.txt'))) 'không đặt lại thì không ghi ThongTinKhaiBao.txt (lỗi của bản 2026.10.1)'
Check ((Get-RegVal ($rb + 'Software\VB and VBA Program Settings\liliiliiliiiliilli\GridLight') 'SoTKQRG') -eq '000011112222') 'dữ liệu MyExcel còn nguyên'
$res = @(Get-ChildItem $resDir -Filter "KetQua_MyExcel_Sua_$($c)_$($u)_*.json" -ErrorAction SilentlyContinue)
Check ($res.Count -eq 2) "JSON kết quả trong thư mục riêng: lần này + bản cũ chuyển sang ($($res.Count))"
Check (Test-Path (Join-Path $resDir "BaoCao_MyExcel_$($c)_$($u)_20250101_000000.txt")) 'báo cáo cũ của tài khoản này được chuyển sang thư mục riêng'
$left = @(Get-ChildItem $shared -File | ForEach-Object { $_.Name } | Sort-Object)
Check (($left -join '|') -eq ((@("BaoCao_MyExcel_$($c)_nguoikhac_20250101_000000.txt", "snapshot_$($c)_nguoikhac.json") | Sort-Object) -join '|')) "thư mục chung chỉ còn file của tài khoản khác và snapshot ($($left -join ', '))"
$jNew =@($res | ForEach-Object { Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } | Where-Object { $_.thuMucSaoLuu })
Check ($jNew.Count -eq 1 -and $jNew[0].thuMucSaoLuu -eq $bkA) 'JSON chỉ tới thư mục sao lưu mới'
Check ($r.Out -match 'HOAN_TAC\.bat') 'cuối lần sửa chỉ cách hoàn tác bằng HOAN_TAC.bat'

Start-Sleep -Seconds 1   # tên thư mục sao lưu theo giây
Write-Host '== T5b: sửa, đặt lại dữ liệu MyExcel ngay ==' -ForegroundColor Cyan
$r = Invoke-Bat "$Tool\FixMyExcel_VietQR.bat" -Env (Get-PlaceEnv @{ MYX_RESET_NOW = '1'; MYX_QR_OK = '1' })
$r.Out | Set-Content (Join-Path $envDir 'fix_b.txt') -Encoding UTF8
Check ($r.Code -eq 0) "mã thoát 0 ($($r.Code), $($r.Sec)s)"
$bkB = @(Get-ChildItem $bakRoot -Directory -Filter 'MyExcelFix_SaoLuu_*' | Where-Object { $_.FullName -ne $bkA })[0].FullName
$info = Join-Path $bkB 'ThongTinKhaiBao.txt'
Check (Test-Path $info) 'đặt lại thì ghi ThongTinKhaiBao.txt trong thư mục sao lưu riêng'
Check ((Get-Content $info -Raw -Encoding UTF8) -match '000011112222') 'ThongTinKhaiBao.txt có đủ số tài khoản để khai báo lại'
Check ($null -eq (Get-RegVal ($rb + 'Software\VB and VBA Program Settings\liliiliiliiiliilli\GridLight') 'SoTKQRG')) 'dữ liệu MyExcel đã đặt lại'
Check ($r.Out -notmatch '000011112222' -and $r.Out -match '\*{8}2222') 'màn hình chỉ hiện số tài khoản đã che'
Check (-not ((Get-Content (Join-Path $bkB 'NhatKy_Sua.txt') -Raw -Encoding UTF8) -match '000011112222')) 'nhật ký không có số tài khoản đầy đủ'
Check ($r.Out -match [regex]::Escape($info)) 'chỉ rõ đường dẫn ThongTinKhaiBao.txt để khai báo lại'
Check (@(Get-ChildItem $desk -Force -ErrorAction SilentlyContinue).Count -eq 0) 'vẫn không ghi gì ra Desktop'

Write-Host '== T5c: HOAN_TAC.bat không kèm thư mục: liệt kê cả bản cũ trên Desktop, chọn bản mới nhất ==' -ForegroundColor Cyan
$legacy = Join-Path $desk 'MyExcelFix_SaoLuu_20250101_000000'
Copy-Item -LiteralPath $bkA -Destination $legacy -Recurse
$r = Invoke-Bat "$Tool\HOAN_TAC.bat" -Env (Get-PlaceEnv)
$r.Out | Set-Content (Join-Path $envDir 'undo_c.txt') -Encoding UTF8
Check ($r.Code -eq 0) "mã thoát 0 ($($r.Code), $($r.Sec)s)"
$listed = @([regex]::Matches($r.Out, '(?m)^\s+\d\) ')).Count
Check ($listed -eq 3) "liệt kê 3 bản sao lưu ($listed)"
Check ($r.Out -match '\[Desktop\]') 'bản cũ trên Desktop có đánh dấu [Desktop]'
$iB = $r.Out.IndexOf($bkB); $iA = $r.Out.IndexOf($bkA); $iL = $r.Out.IndexOf($legacy)
Check ($iB -ge 0 -and $iB -lt $iA -and $iA -lt $iL) "mới nhất trước, bản trên Desktop (cũ nhất) sau cùng ($iB < $iA < $iL)"
Check ((Get-RegVal ($rb + 'Software\VB and VBA Program Settings\liliiliiliiiliilli\GridLight') 'SoTKQRG') -eq '000011112222') 'hoàn tác bản mới nhất: dữ liệu MyExcel trở lại'
Check (@(Get-ChildItem $bkB -Directory -Filter 'TruocHoanTac_*').Count -eq 1) 'lưu cấu hình trước khi hoàn tác vào đúng bản đã chọn'
$ju = @(Get-ChildItem $resDir -Filter 'KetQua_MyExcel_HoanTac_*.json' | ForEach-Object { Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json })
Check ($ju.Count -eq 1 -and $ju[0].thuMucSaoLuu -eq $bkB -and $ju[0].maThoat -eq 0) "JSON hoàn tác trong thư mục riêng, đúng bản đã chọn ($($ju[0].thuMucSaoLuu))"

Write-Host '== T5d: không có bản sao lưu nào của tài khoản này ==' -ForegroundColor Cyan
$lad2 = Join-Path $envDir 'localappdata2'; $desk2 = Join-Path $envDir 'desktop2'
$otherBk = Join-Path $lad2 'MyExcelFix\SaoLuu\MyExcelFix_SaoLuu_20250101_000000'
New-Item -ItemType Directory -Path $otherBk, $desk2 -Force | Out-Null
Set-Content (Join-Path $otherBk 'manifest.json') '{ "Format": 2, "User": "nguoikhac", "Time": "01/01/2025 00:00:00" }' -Encoding ASCII
$r = Invoke-Bat "$Tool\HOAN_TAC.bat" -Env (Get-PlaceEnv @{ LOCALAPPDATA = $lad2; MYX_DESKTOP = $desk2 })
Check ($r.Code -eq 2) "mã thoát 2 ($($r.Code))"
Check ($r.Out -match 'Không thấy bản sao lưu nào' -and $r.Out -match 'tài khoản khác') 'báo không có bản nào, có 1 bản của tài khoản khác'
$jn = @(Get-ChildItem (Join-Path $lad2 'MyExcelFix\BaoCao') -Filter 'KetQua_MyExcel_HoanTac_*.json' -ErrorAction SilentlyContinue | ForEach-Object { Get-Content $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json })
Check ($jn.Count -eq 1 -and $jn[0].ma -eq 'KHONG_CO_SAO_LUU') "JSON: $($jn[0].ma)"
Check (Test-Path (Join-Path $otherBk 'manifest.json')) 'không đụng bản sao lưu của tài khoản khác'

Write-Host '== T5e: HOAN_TAC.bat thiếu FixMyExcel_VietQR.bat cạnh nó ==' -ForegroundColor Cyan
$lone = New-TestDir 'chi co hoan tac'
Copy-Item -LiteralPath "$Tool\HOAN_TAC.bat" -Destination $lone
$r = Invoke-Bat (Join-Path $lone 'HOAN_TAC.bat') -Env @{ MYX_NOPAUSE = '1' } -TimeoutSec 30
Check ($r.Code -eq 2 -and $r.Out -match 'Khong thay FixMyExcel_VietQR\.bat') "mã 2, chỉ cách khác ($($r.Code))"

Assert-RealUntouched
Clear-TestRegistry
Complete-Test
