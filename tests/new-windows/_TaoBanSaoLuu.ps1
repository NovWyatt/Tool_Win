# Tạo một bản sao lưu giả, không mã hoá, bằng ChuyenDuLieu.ps1 với hàm giả (_GiaLap.ps1) vào <Dich>\DuLieu_SaoLuu.
# 4_TienTrinh.ps1 gọi file này trong tiến trình riêng (với TRAMTOOL_TEST_ROOT riêng) để có bản thử nhập.
param([string]$Dich)
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$h = Join-Path $TestRoot 'home'
. "$PSScriptRoot\_GiaLap.ps1" -FakeHome $h
New-FakeHome $h $h
$global:FakeVols = @()
New-Item -ItemType Directory -Force -Path $Dich | Out-Null
$script:Opt = @{ Target = $Dich; Phan = ''; Driver = 'khong'; MaHoa = $false; DryRun = $false }
$script:Yes = $true
$Mode = 'xuat'
$rc = @(Invoke-Xuat)[-1]
if ($script:Errors.Count) { Write-Host ('Lỗi: ' + ($script:Errors -join ' | ')) }
exit $rc
