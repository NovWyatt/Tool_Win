# Bài thử 2: xuất có mã hoá trên "máy cũ" giả -> nhập trên "máy mới" giả (tên tài khoản khác).
# Đầu vào (chuyển hướng, mỗi dòng một lần hỏi) theo thứ tự: xem 2_XuatNhap.dauvao.txt
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$Root = $TestRoot
$oldHome = Join-Path $Root 'home_cu'
. "$PSScriptRoot\_GiaLap.ps1" -FakeHome $oldHome
New-FakeHome $oldHome $oldHome
$secrets = 'KhoaWifiGia_111', 'KhoaWifiGia_222', 'KhoaWifiGia_333', 'BiMatClaudeGia_444', 'KhongDuocSaoLuu_555', 'BiMatMcpGia_666', 'BiMatDesktopGia_777', 'BiMatExtGia_888', 'MatKhauThu123'

# máy in, driver, ổ BitLocker giả
$inf = Join-Path $Root 'DriverStore\FileRepository\gia.inf_amd64_1\gia.inf'
New-Item -ItemType Directory -Force -Path (Split-Path $inf) | Out-Null
Set-Content -LiteralPath $inf -Value '; driver máy in giả' -Encoding ASCII
$global:FakePrinters = @([pscustomobject]@{ Name = 'May In Gia'; PortName = 'IP_10.9.9.9'; DriverName = 'Driver Gia'; Type = 'Local'; Shared = $false; ShareName = ''; Location = 'Phong thu'; Comment = '' })
$global:FakeDrivers = @([pscustomobject]@{ Name = 'Driver Gia'; InfPath = $inf; Manufacturer = 'Hang Gia'; PrinterEnvironment = 'Windows x64'; MajorVersion = 3 })
$global:FakeVols = @([pscustomobject]@{ DriveLetter = 'E:'; VolumeType = 1; Locked = 0 })

Write-Host '== XUẤT (mã hoá)'
$usb = Join-Path $Root 'usb'
New-Item -ItemType Directory -Force -Path $usb | Out-Null
$script:Opt = @{ Target = $usb; Phan = ''; Driver = 'mang'; MaHoa = $true; DryRun = $false }
$script:Yes = $true
$Mode = 'xuat'
$rc = @(Invoke-Xuat)[-1]
$bkDir = Join-Path $usb 'DuLieu_SaoLuu'
Check ($rc -eq 0) "Invoke-Xuat trả 0 ($rc); lỗi: $($script:Errors -join ' | ')"
$m = Read-Json (Join-Path $bkDir 'manifest.json')
Check ($m.TrangThai -eq 'xong' -and $m.MaHoa -eq $true -and $m.TepMaHoa -eq 'BiMat.aes' -and $m.Phan.WiFi -eq 2 -and $m.Phan.FileMaHoa -eq 6) "manifest: $($m.TrangThai), MaHoa=$($m.MaHoa), WiFi=$($m.Phan.WiFi), FileMaHoa=$($m.Phan.FileMaHoa)"
Check ([WlanTool]::ExportCalls -eq 1) 'đọc Wi-Fi đúng 1 lần'
Check (Test-Path (Join-Path $bkDir 'BiMat.aes')) 'có BiMat.aes'
Check (@(Get-ChildItem (Join-Path $bkDir 'WiFi') -Filter '*.xml' -ErrorAction SilentlyContinue).Count -eq 0) 'không có hồ sơ Wi-Fi dạng chữ trên đĩa'
Check (@((Read-Json (Join-Path $bkDir 'WiFi\danh-sach.json')) | ForEach-Object { $_ }).Count -eq 2) 'danh-sach.json có 2 mạng (bỏ mạng công ty quản lý)'
foreach ($rel in 'Claude\dot-claude\settings.json', 'Claude\dot-claude\.credentials.json', 'Claude\dot-claude\cache', 'Claude\dot-claude.json', 'Claude\AppData-Claude\claude_desktop_config.json', 'Claude\AppData-Claude\Claude Extensions Settings') {
    Check (-not (Test-Path -LiteralPath (Join-Path $bkDir $rel))) "không có trên đĩa: $rel"
}
foreach ($rel in 'Claude\dot-claude\CLAUDE.md', 'Claude\AppData-Claude\claude-code-sessions\a\local_1.json', 'Claude\HoiThoai-Code\index.html', 'Claude\claude-info.json', 'Driver\oem12\oem12.inf', 'MayIn\Drivers\gia.inf_amd64_1\gia.inf', 'MayIn\may-in.json', 'thong-tin.json', 'HUONG_DAN.txt', 'nhat-ky-xuat.txt') {
    Check (Test-Path -LiteralPath (Join-Path $bkDir $rel)) "có: $rel"
}
foreach ($s in $secrets) { $h = @(Find-Text $bkDir $s); Check ($h.Count -eq 0) "không lọt '$s' ra đĩa ($($h -join ', '))" }
$h = @(Find-Text $bkDir $global:BdeKey)
Check ($h.Count -eq 1 -and $h[0] -like '*\BitLocker\BitLocker_KhoaKhoiPhuc_*.txt') "khoá BitLocker chỉ nằm trong file khoá ($($h.Count) file)"
$z = Read-ZipBytes (Unprotect-Bytes ([IO.File]::ReadAllBytes((Join-Path $bkDir 'BiMat.aes'))) 'MatKhauThu123')
$want = 'WiFi\001.xml', 'WiFi\002.xml', 'Claude\dot-claude\settings.json', 'Claude\dot-claude.json', 'Claude\AppData-Claude\claude_desktop_config.json', 'Claude\AppData-Claude\Claude Extensions Settings\ext.json'
Check (@($want | Where-Object { -not $z.Contains($_) }).Count -eq 0 -and $z.Count -eq 6) "BiMat.aes có đủ 6 file: $(@($z.Keys) -join '; ')"
Check ([Text.Encoding]::UTF8.GetString($z['WiFi\002.xml']).Contains('KhoaWifiGia_222')) 'hồ sơ Wi-Fi trong BiMat.aes còn mật khẩu'
Check ($script:Secret.Count -eq 0 -and $null -eq $script:Password) 'đã xoá bí mật, mật khẩu khỏi bộ nhớ'
Check ($script:Started) 'đánh dấu đã bắt đầu'

function Reset-Run {
    $script:Errors.Clear(); $script:Warnings.Clear(); $global:Calls.Clear()
    $script:Started = $false; $script:Secret = $null; $script:SecretIn = $null; $script:Out = $null; $script:In = $null
    foreach ($v in $global:FakeVols) { $v.Locked = 1 }
    $global:FakePrinters = @(); $global:FakeDrivers = @()
}

Write-Host '== NHẬP trên máy mới (sai mật khẩu 1 lần rồi đúng)'
$newHome = Join-Path $Root 'home_moi'
$env:USERPROFILE = $newHome; $env:APPDATA = Join-Path $newHome 'AppData\Roaming'; $env:LOCALAPPDATA = Join-Path $newHome 'AppData\Local'
$deskNew = Join-Path $newHome 'AppData\Local\Packages\Claude_gia123\LocalCache\Roaming\Claude'
New-Item -ItemType Directory -Force -Path $deskNew, (Join-Path $newHome '.claude') | Out-Null
Set-Content -LiteralPath (Join-Path $newHome '.claude\settings.json') -Value '{"cu":"may moi"}' -Encoding UTF8
[WlanTool]::Existing.Clear(); [WlanTool]::Existing.Add('Nha Gia 5G'); [WlanTool]::Imported.Clear()
$global:FakePrinters = @(); $global:FakeDrivers = @()
Reset-Run
$script:Opt = @{ Target = $usb; Phan = 'tat-ca'; Driver = ''; MaHoa = $false; DryRun = $false }
$Mode = 'nhap'
$rc = @(Invoke-Nhap)[-1]
Check ($rc -eq 0) "Invoke-Nhap trả 0 ($rc); lỗi: $($script:Errors -join ' | ')"
Check ([WlanTool]::Imported.Count -eq 1 -and [WlanTool]::Imported[0].Contains('KhoaWifiGia_222')) 'thêm 1 mạng Wi-Fi mới kèm mật khẩu'
Check ($Stat.WifiHave -eq 1 -and $Stat.WifiBad -eq 0) 'mạng đã có được bỏ qua'
foreach ($c in 'Bde:Unlock E:', 'Add-PrinterDriver Driver Gia', 'Add-Printer May In Gia', 'Set-PrintConfiguration May In Gia') { Check ($global:Calls -contains $c) "đã gọi: $c" }
Check (@($global:Calls | Where-Object { $_ -like 'pnputil /add-driver *\Driver\*.inf /subdirs /install' }).Count -eq 1) 'nạp driver đã sao lưu bằng pnputil'
$st = [IO.File]::ReadAllText((Join-Path $newHome '.claude\settings.json'))
Check ($st.Contains('BiMatClaudeGia_444') -and $st.Contains($newHome.Replace('\', '\\')) -and -not $st.Contains($oldHome.Replace('\', '\\'))) 'settings.json từ BiMat.aes, đã sửa đường dẫn sang tài khoản mới'
Check (@(Get-ChildItem (Join-Path $newHome '.claude') -Filter 'settings.json.truoc-khoi-phuc-*').Count -eq 1) 'giữ settings.json cũ của máy mới'
Check ([IO.File]::ReadAllText((Join-Path $newHome '.claude.json')).Contains('BiMatMcpGia_666')) '.claude.json từ BiMat.aes'
Check ([IO.File]::ReadAllText((Join-Path $deskNew 'claude_desktop_config.json')).Contains('BiMatDesktopGia_777')) 'claude_desktop_config.json từ BiMat.aes'
Check ([IO.File]::ReadAllText((Join-Path $deskNew 'Claude Extensions Settings\ext.json')).Contains('BiMatExtGia_888')) 'Claude Extensions Settings từ BiMat.aes'
Check (Test-Path (Join-Path $deskNew 'claude-code-sessions\a\local_1.json')) 'danh sách phiên Code'
$pn = ($newHome -replace '[^A-Za-z0-9]', '-') + '-DuAn'
Check (Test-Path (Join-Path $newHome ".claude\projects\$pn\phien-1.jsonl")) 'thư mục dự án đổi tên theo tài khoản mới'
Check ([IO.File]::ReadAllText((Join-Path $newHome '.claude\CLAUDE.md')).Contains("$newHome\DuAn")) 'CLAUDE.md sửa đường dẫn'
Check (-not (Test-Path (Join-Path $newHome '.claude\.credentials.json'))) 'không có token đăng nhập'
Check ($null -eq $script:SecretIn) 'đã xoá phần giải mã khỏi bộ nhớ'
foreach ($s in $secrets) { $h = @(Find-Text $bkDir $s); Check ($h.Count -eq 0) "sau khi nhập vẫn không lọt '$s' vào bản sao lưu" }
Check (Test-Path (Join-Path $bkDir 'nhat-ky-nhap.txt')) 'có nhật ký nhập'

Write-Host '== NHẬP, sai mật khẩu 3 lần, -Yes'
Reset-Run
[WlanTool]::Imported.Clear()
$rc = @(Invoke-Nhap)[-1]
Check ($rc -eq 2) "trả 2 ($rc)"
Check ($global:Calls.Count -eq 0 -and [WlanTool]::Imported.Count -eq 0 -and -not $script:Started) 'không đổi gì trên máy'

Write-Host '== NHẬP, sai mật khẩu 3 lần, đồng ý bỏ qua phần mã hoá'
Reset-Run
$script:Yes = $false
Remove-Item -LiteralPath (Join-Path $newHome '.claude.json') -Force
$rc = @(Invoke-Nhap)[-1]
Check ($rc -eq 3) "trả 3 ($rc)"
Check (@($script:Errors | Where-Object { $_ -like 'Bỏ qua 2 mạng Wi-Fi*' }).Count -eq 1) 'báo bỏ qua Wi-Fi'
Check (@($script:Errors | Where-Object { $_ -like 'Cấu hình Claude*BiMat.aes*' }).Count -eq 1) 'báo chưa khôi phục cấu hình Claude'
Check ($global:Calls -contains 'Bde:Unlock E:' -and $global:Calls -contains 'Add-Printer May In Gia') 'các phần không mã hoá vẫn nhập'
Check (-not (Test-Path (Join-Path $newHome '.claude.json'))) 'không ghi .claude.json khi chưa giải mã'

Complete-Test
