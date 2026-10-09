# Bài thử 3: xuất không mã hoá, đổi tên bản cũ, xuất lỗi giữa chừng, chọn bản _cu_, chạy thử, mã hoá hỏng, hết đầu vào.
# Đầu vào: 3_TrangThai.dauvao.txt
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$Root = $TestRoot
$h0 = Join-Path $Root 'home'
. "$PSScriptRoot\_GiaLap.ps1" -FakeHome $h0
New-FakeHome $h0 $h0
$script:ToolDir = Join-Path $Root 'tool'
New-Item -ItemType Directory -Force -Path $script:ToolDir | Out-Null
$global:FakeVols = @()
$usb = Join-Path $Root 'usb'
New-Item -ItemType Directory -Force -Path $usb | Out-Null
$bk = Join-Path $usb 'DuLieu_SaoLuu'
function Reset-Run {
    $script:Errors.Clear(); $script:Warnings.Clear(); $global:Calls.Clear()
    $script:Started = $false; $script:Secret = $null; $script:SecretIn = $null; $script:Out = $null; $script:In = $null
}
$Mode = 'xuat'
$script:Yes = $true

Write-Host '== A. xuất không mã hoá (-Yes)'
Reset-Run
$script:Opt = @{ Target = $usb; Phan = ''; Driver = 'khong'; MaHoa = $false; DryRun = $false }
$rc = @(Invoke-Xuat)[-1]
$m = Read-Json (Join-Path $bk 'manifest.json')
Check ($rc -eq 0 -and $m.TrangThai -eq 'xong' -and $m.MaHoa -eq $false -and $null -eq $m.TepMaHoa) "rc=$rc, $($m.TrangThai), MaHoa=$($m.MaHoa)"
Check (-not (Test-Path (Join-Path $bk 'BiMat.aes'))) 'không có BiMat.aes'
Check ([IO.File]::ReadAllText((Join-Path $bk 'WiFi\001.xml')).Contains('KhoaWifiGia_111')) 'không mã hoá: hồ sơ Wi-Fi nằm trên đĩa như bản cũ'
Check ((Test-Path (Join-Path $bk 'Claude\dot-claude\settings.json')) -and (Test-Path (Join-Path $bk 'Claude\AppData-Claude\claude_desktop_config.json'))) 'không mã hoá: cấu hình Claude nằm trên đĩa'
Check (-not (Test-Path (Join-Path $bk 'Driver'))) 'Driver khong: không có thư mục Driver'
Check ([IO.File]::ReadAllText((Join-Path $bk 'HUONG_DAN.txt')).Contains('thư mục WiFi chứa mật khẩu Wi-Fi dạng chữ thường')) 'hướng dẫn cảnh báo mật khẩu dạng chữ'

Write-Host '== B. xuất lần hai: đổi tên bản cũ'
Start-Sleep -Seconds 1
Reset-Run
$rc = @(Invoke-Xuat)[-1]
$cu = @(Get-ChildItem $usb -Directory -Filter 'DuLieu_SaoLuu_cu_*')
Check ($rc -eq 0 -and $cu.Count -eq 1 -and (Test-Path (Join-Path $bk 'manifest.json'))) "bản cũ đổi tên ($($cu.Name -join ', '))"

Write-Host '== C. xuất lỗi giữa chừng'
Start-Sleep -Seconds 1
Reset-Run
$orig = ${function:Export-Printers}
${function:Export-Printers} = { throw 'máy in giả hỏng' }
$rc = @(Invoke-Xuat)[-1]
${function:Export-Printers} = $orig
$m = Read-Json (Join-Path $bk 'manifest.json')
Check ($rc -eq 1 -and $m.TrangThai -eq 'loi' -and @($m.Loi | Where-Object { $_ -like '*máy in giả hỏng*' }).Count -eq 1) "rc=$rc, manifest $($m.TrangThai)"
Check (@(Get-ChildItem $usb -Directory -Filter 'DuLieu_SaoLuu_cu_*').Count -eq 2) 'giờ có 2 bản _cu_'

Write-Host '== C2. nhập -Yes, không -Target: bản mới bị lỗi, chỉ còn bản _cu_ -> không tự dùng'
New-Item -ItemType Directory -Force -Path $script:ResultDir | Out-Null
Save-Json @{ ThuMucSaoLuu = $bk } (Join-Path $script:ResultDir 'KetQua_ChuyenDuLieu_xuat_MAYGIA_20261009_090000.json')
Reset-Run
$Mode = 'nhap'
$script:Opt = @{ Target = ''; Phan = 'wifi'; Driver = ''; MaHoa = $false; DryRun = $false }
[WlanTool]::Existing.Clear(); [WlanTool]::Imported.Clear()
$rc = @(Invoke-Nhap)[-1]
Check ($rc -eq 2 -and [WlanTool]::Imported.Count -eq 0) "rc=$rc, không nhập gì"
Check (@($script:Warnings | Where-Object { $_ -like '*DỪNG VÌ LỖI*' }).Count -eq 1) 'báo bản lỗi bị bỏ qua'

Write-Host '== C3. nhập hỏi: Enter chọn bản đầu, c đồng ý dùng bản _cu_'
Reset-Run
$script:Yes = $false
$rc = @(Invoke-Nhap)[-1]
Check ($rc -eq 0 -and [WlanTool]::Imported.Count -eq 2) "rc=$rc, thêm $([WlanTool]::Imported.Count) mạng"
Check ($script:In -like '*DuLieu_SaoLuu_cu_*') "dùng bản cũ mới nhất ($(Split-Path -Leaf $script:In))"
$script:Yes = $true

Write-Host '== D. chạy thử xuất: không ghi gì, không đọc mật khẩu Wi-Fi'
Reset-Run
$Mode = 'xuat'
$calls0 = [WlanTool]::ExportCalls
$usb2 = Join-Path $Root 'usb2'
New-Item -ItemType Directory -Force -Path $usb2 | Out-Null
$script:Opt = @{ Target = $usb2; Phan = ''; Driver = ''; MaHoa = $true; DryRun = $true }
$rc = @(Invoke-Xuat)[-1]
Check ($rc -eq 0) "rc=$rc"
Check (@(Get-ChildItem $usb2 -Force).Count -eq 0) 'không tạo file, thư mục nào'
Check ([WlanTool]::ExportCalls -eq $calls0) 'không gọi WlanTool.Export (không đọc mật khẩu)'
Check ($global:Calls.Count -eq 0 -and -not $script:Started) 'không gọi lệnh đổi máy'
Check (@($global:Calls | Where-Object { $_ -like 'Bde:GetKey*' }).Count -eq 0) 'không đọc khoá BitLocker'

Write-Host '== E. chạy thử nhập'
Reset-Run
$Mode = 'nhap'
$script:Opt = @{ Target = (@(Get-ChildItem $usb -Directory -Filter 'DuLieu_SaoLuu_cu_*' | Sort-Object Name)[0].FullName); Phan = ''; Driver = ''; MaHoa = $false; DryRun = $true }
[WlanTool]::Imported.Clear(); [WlanTool]::Existing.Clear(); [WlanTool]::Existing.Add('Nha Gia 5G')
$before = @(Get-ChildItem $script:Opt.Target -Recurse -Force).Count
$rc = @(Invoke-Nhap)[-1]
Check ($rc -eq 0 -and $global:Calls.Count -eq 0 -and [WlanTool]::Imported.Count -eq 0 -and -not $script:Started) "rc=$rc, không đổi máy"
Check (@(Get-ChildItem $script:Opt.Target -Recurse -Force).Count -eq $before) 'không ghi gì vào bản sao lưu (kể cả nhật ký)'

Write-Host '== G. mã hoá hỏng giữa chừng'
Reset-Run
$Mode = 'xuat'
$usb3 = Join-Path $Root 'usb3'
New-Item -ItemType Directory -Force -Path $usb3 | Out-Null
$script:Opt = @{ Target = $usb3; Phan = ''; Driver = 'khong'; MaHoa = $true; DryRun = $false }
$origP = ${function:Protect-Bytes}
${function:Protect-Bytes} = { throw 'AES giả hỏng' }
$rc = @(Invoke-Xuat)[-1]
${function:Protect-Bytes} = $origP
$b3 = Join-Path $usb3 'DuLieu_SaoLuu'
$m = Read-Json (Join-Path $b3 'manifest.json')
Check ($rc -eq 3 -and $m.TrangThai -eq 'mot-phan' -and $m.MaHoa -eq $false) "rc=$rc, $($m.TrangThai), MaHoa=$($m.MaHoa)"
Check (@($m.Loi | Where-Object { $_ -like 'Không mã hoá được*' }).Count -eq 1) 'lỗi ghi rõ không mã hoá được'
Check (-not (Test-Path (Join-Path $b3 'BiMat.aes')) -and @(Get-ChildItem (Join-Path $b3 'WiFi') -Filter '*.xml').Count -eq 0) 'không để lại mật khẩu dạng chữ khi mã hoá hỏng'
Check ($script:Secret.Count -eq 0 -and $null -eq $script:Password) 'xoá bí mật khỏi bộ nhớ'

Write-Host '== H. hết đầu vào khi đang hỏi'
Reset-Run
$script:Yes = $false
$script:Opt = @{ Target = ''; Phan = ''; Driver = ''; MaHoa = $false; DryRun = $false }
$e = $null
$t0 = Get-Date
try { [void](Invoke-Xuat) } catch { $e = $_.Exception.Message }
Check ($e -eq $script:EndOfInput -and ((Get-Date) - $t0).TotalSeconds -lt 20) "dừng ngay khi hết đầu vào ($e)"
Check (-not $script:Started) 'chưa bắt đầu ghi'

Complete-Test
