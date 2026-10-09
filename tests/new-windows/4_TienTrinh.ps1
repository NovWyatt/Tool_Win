# Bài thử 4: tiến trình thật của ChuyenDuLieu.ps1 và hai file .bat. Chỉ chạy thử (-DryRun) hoặc dừng trước khi đổi máy.
# Phần "chạy thử xuất" đọc máy thật (tên mạng Wi-Fi, máy in, ổ đĩa) nhưng không đọc mật khẩu, không ghi gì
# ngoài thư mục tạm của bài thử.
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Continue'
$Root = $TestRoot
$tool = "$ToolsDir\new-windows"
$ps1 = Join-Path $tool 'ChuyenDuLieu.ps1'
$env:CDL_KET_QUA = Join-Path $Root 'ket_qua'
$empty = Join-Path $Root 'empty.txt'; Set-Content -LiteralPath $empty -Value $null

# Bản sao lưu giả (không mã hoá, 2 mạng Wi-Fi giả) để thử nhập: tạo bằng _TaoBanSaoLuu.ps1 trong tiến trình riêng
$BackupParent = Join-Path $Root 'ban-sao-luu'
$keepRoot = $env:TRAMTOOL_TEST_ROOT
$env:TRAMTOOL_TEST_ROOT = Join-Path $Root 'tao-ban'
$p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $PSScriptRoot '_TaoBanSaoLuu.ps1') + '"'), '-Dich', ('"' + $BackupParent + '"')) `
    -RedirectStandardInput $empty -RedirectStandardOutput (Join-Path $Root 'tao-ban.txt') -RedirectStandardError (Join-Path $Root 'tao-ban.err') -NoNewWindow -Wait -PassThru
$env:TRAMTOOL_TEST_ROOT = $keepRoot
$BackupForImport = Join-Path $BackupParent 'DuLieu_SaoLuu'
Check ($p.ExitCode -eq 0 -and (Test-Path (Join-Path $BackupForImport 'manifest.json'))) "tạo bản sao lưu giả để thử nhập (mã $($p.ExitCode))"

function Run([string[]]$ArgList, [string]$Label, [string]$StdIn = $empty) {
    $log = Join-Path $Root ($Label + '.txt')
    $t0 = Get-Date
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass') + $ArgList) -RedirectStandardInput $StdIn -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -Wait -PassThru
    return [pscustomobject]@{ Code = $p.ExitCode; Out = ([IO.File]::ReadAllText($log) + [IO.File]::ReadAllText("$log.err")); Sec = ((Get-Date) - $t0).TotalSeconds }
}
function Q([string]$s) { '"' + $s + '"' }

Write-Host '== tham số sai -> 1'
foreach ($c in @(
        @{ A = @('-Mode', 'abc'); L = 'mode-sai' },
        @{ A = @('-Mode', 'xuat', '-Phan', 'wifi'); L = 'phan-khi-xuat' },
        @{ A = @('-Mode', 'nhap', '-MaHoa'); L = 'mahoa-khi-nhap' },
        @{ A = @('-Mode', 'xuat', '-Driver', 'xyz'); L = 'driver-sai' },
        @{ A = @('-Mode', 'nhap', '-Phan', 'abc'); L = 'phan-sai' })) {
    $r = Run (@('-File', (Q $ps1)) + $c.A + @('-NoPause')) $c.L
    Check ($r.Code -eq 1) "$($c.L): mã $($r.Code)"
}
$r = Run @('-File', (Q $ps1)) 'khong-mode'
Check ($r.Code -eq 1 -and $r.Out -like '*Cách dùng*') "không -Mode, đầu vào chuyển hướng: in cách dùng, mã $($r.Code)"

Write-Host '== chưa có quyền Admin, đã nâng quyền mà vẫn không có -> 2 (không hỏi UAC)'
$r = Run @('-File', (Q $ps1), '-Mode', 'xuat', '-DaNangQuyen', '-NoPause') 'da-nang-quyen'
Check ($r.Code -eq 2 -and $r.Out -like '*vẫn chưa có quyền Administrator*') "mã $($r.Code)"

Write-Host '== chạy thử xuất trên máy thật (chỉ đọc)'
$usb = Join-Path $Root 'usb'
New-Item -ItemType Directory -Force -Path $usb | Out-Null
$r = Run @('-File', (Q $ps1), '-Mode', 'xuat', '-ChayThu', '-Target', (Q $usb), '-KhongDung') 'chay-thu-xuat'
Check ($r.Code -eq 0) "mã $($r.Code) ($([int]$r.Sec) giây)"
Check (@(Get-ChildItem $usb -Force).Count -eq 0) 'không tạo gì ở nơi lưu'
Check ($r.Out -like '*CHẠY THỬ*' -and $r.Out -like '*Wi-Fi:*mạng đã lưu*') 'in kế hoạch'
$j = @(Get-ChildItem $env:CDL_KET_QUA -Filter 'KetQua_ChuyenDuLieu_xuat_*.json')
$k = if ($j.Count) { [IO.File]::ReadAllText($j[0].FullName) | ConvertFrom-Json } else { $null }
Check ($j.Count -eq 1 -and $k.chayThu -eq $true -and $k.maThoat -eq 0 -and $null -eq $k.thuMucSaoLuu -and $k.trangThai -eq 'xong') 'file kết quả: chạy thử, không ghi thuMucSaoLuu'
Check ($k.chuan -eq 'tramtool.ketqua/1' -and $k.congCu -eq 'new-windows' -and $k.thongDiep -and $null -ne $k.tomTat -and @($k.tep).Count -eq 0) 'file kết quả theo chuẩn tramtool.ketqua/1'

Write-Host '== kiểu Trạm Tool gọi (-Command, giá trị trong nháy đơn, có \ cuối)'
$cmd = "& '$ps1' -Mode xuat -DryRun -Target '$usb\' -NoPause; if (`$?) { exit 0 }; if (`$LASTEXITCODE) { exit `$LASTEXITCODE }; exit 1"
$r = Run @('-Command', (Q $cmd)) 'kieu-tram'
Check ($r.Code -eq 0 -and $r.Out -like "*$usb\DuLieu_SaoLuu*") "mã $($r.Code), nơi lưu đúng"
$cmd = "& '$ps1' -Mode nhap -Phan xyz -NoPause; if (`$?) { exit 0 }; if (`$LASTEXITCODE) { exit `$LASTEXITCODE }; exit 1"
$r = Run @('-Command', (Q $cmd)) 'kieu-tram-loi'
Check ($r.Code -eq 1) "mã lỗi chuyển ra ngoài: $($r.Code)"

Write-Host '== thư mục công cụ bị từ chối làm nơi lưu'
$r = Run @('-File', (Q $ps1), '-Mode', 'xuat', '-DryRun', '-Target', (Q $tool), '-NoPause') 'trong-cong-cu'
Check ($r.Code -eq 2 -and $r.Out -like '*thư mục Trạm Tool*') "mã $($r.Code)"
Check (-not (Test-Path (Join-Path $tool 'DuLieu_SaoLuu'))) 'không tạo DuLieu_SaoLuu trong công cụ'

Write-Host '== chạy thử nhập (chỉ đọc)'
$before = @(Get-ChildItem $BackupForImport -Recurse -Force).Count
$r = Run @('-File', (Q $ps1), '-Mode', 'nhap', '-DryRun', '-Yes', '-Target', (Q $BackupForImport), '-NoPause') 'chay-thu-nhap'
Check ($r.Code -eq 0 -and $r.Out -like '*CHẠY THỬ*' -and $r.Out -like '*Wi-Fi: 2 mạng*') "mã $($r.Code)"
Check (@(Get-ChildItem $BackupForImport -Recurse -Force).Count -eq $before) 'không ghi vào bản sao lưu'

Write-Host '== nhập không có bản sao lưu nào'
Remove-Item -LiteralPath $env:CDL_KET_QUA -Recurse -Force
$r = Run @('-File', (Q $ps1), '-Mode', 'nhap', '-DryRun', '-Yes', '-NoPause') 'khong-co-ban'
Check ($r.Code -eq 2) "-Yes: mã $($r.Code)"
$r = Run @('-File', (Q $ps1), '-Mode', 'nhap', '-DryRun', '-NoPause') 'het-dau-vao'
Check ($r.Code -eq 2 -and $r.Out -like '*Hết dữ liệu vào*' -and $r.Sec -lt 60) "hết đầu vào: mã $($r.Code), $([int]$r.Sec) giây"

Write-Host '== hai file .bat'
$r = Run @('-Command', (Q ("cmd /d /c '" + (Join-Path $tool '1_XUAT_DU_LIEU.bat') + "' -DryRun -Target '$usb' -NoPause; exit `$LASTEXITCODE"))) 'bat-xuat'
Check ($r.Code -eq 0 -and $r.Out -like '*CHẠY THỬ*') "1_XUAT_DU_LIEU.bat -DryRun: mã $($r.Code)"
$r = Run @('-Command', (Q ("cmd /d /c '" + (Join-Path $tool '2_NHAP_DU_LIEU.bat') + "' -Phan xyz -NoPause; exit `$LASTEXITCODE"))) 'bat-nhap'
Check ($r.Code -eq 1) "2_NHAP_DU_LIEU.bat tham số sai: mã $($r.Code)"
$r = Run @('-Command', (Q ("cmd /d /c '" + (Join-Path $tool '2_NHAP_DU_LIEU.bat') + "' -DryRun -Target '$BackupForImport' -Phan wifi -NoPause; exit `$LASTEXITCODE"))) 'bat-nhap-thu'
Check ($r.Code -eq 0 -and $r.Out -like '*Wi-Fi: 2 mạng*') "2_NHAP_DU_LIEU.bat -DryRun -Phan wifi: mã $($r.Code)"

Complete-Test
