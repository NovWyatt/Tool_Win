# Cài SQL Server Express LocalDB (miễn phí, khoảng 50 MB) cho công cụ mdf2sql.
# Bản portable đầy đủ có sẵn bộ cài (runtime\bo-cai\SqlLocalDB, đúng mã SHA-256 lúc đóng gói): dùng file đó, không cần
# mạng. Không có thì tải bộ cài .msi từ máy chủ của Microsoft. Kiểm tra chữ ký số của Microsoft rồi mới cài. Cần quyền Admin.
# Trạm Tool gọi script này khi bấm nút "Cài LocalDB" ở mục Yêu cầu của mdf2sql.
#   -ChiKiemTra : chỉ tải và kiểm tra chữ ký, không cài (dùng để thử script).
param([switch]$ChiKiemTra)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$Host.UI.RawUI.WindowTitle = 'Tram Tool - cai SQL Server LocalDB'
# Cùng đường dẫn với README của mdf2sql (SQL Server 2022 Express LocalDB).
$url = 'https://download.microsoft.com/download/3/8/d/38de7036-2433-4207-8eae-06e247e17b25/SqlLocalDB.msi'
$msi = Join-Path $env:TEMP 'TramTool_SqlLocalDB.msi'
$key = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server Local DB\Installed Versions'

function Loi([string]$text) { Write-Host "LOI: $text" -ForegroundColor Red; exit 1 }

if ((Test-Path $key) -and -not $ChiKiemTra) {
    $v = (Get-ChildItem $key | ForEach-Object { $_.PSChildName }) -join ', '
    Write-Host "Máy đã có LocalDB (phiên bản $v), không cần cài." -ForegroundColor Green
    exit 0
}

. (Join-Path (Split-Path $PSScriptRoot -Parent) 'lib\BoCai.ps1')
$pkg = Get-BoCaiPackage (Get-HubBoCaiRoot) 'SqlLocalDB'
$coSan = [bool]$pkg   # bộ cài của bản portable: không xoá sau khi cài
if ($coSan) {
    if (-not (Test-BoCaiHash $pkg)) { Loi "Bộ cài có sẵn $($pkg.Path) sai mã SHA-256 (file hỏng hoặc bị sửa): không cài." }
    $msi = $pkg.Path
    Write-Host "Dùng bộ cài có sẵn trong bản này (không cần mạng): $msi"
} else {
    Write-Host "Tải bộ cài từ Microsoft: $url"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing
}
$sig = Get-AuthenticodeSignature -LiteralPath $msi
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    if (-not $coSan) { Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue }
    Loi "Bộ cài không có chữ ký hợp lệ của Microsoft (trạng thái: $($sig.Status)). Không cài."
}
Write-Host "Chữ ký số hợp lệ: $($sig.SignerCertificate.Subject)"
if ($ChiKiemTra) {
    if (-not $coSan) { Remove-Item -LiteralPath $msi -Force }
    Write-Host 'Chế độ kiểm tra: không cài.'
    exit 0
}

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Loi 'Cần chạy với quyền Admin (trong Trạm Tool bấm nút Cài, Windows sẽ hỏi UAC).' }

Write-Host 'Đang cài LocalDB (khoảng 1 phút)...'
$p = Start-Process msiexec.exe -ArgumentList @('/i', ('"' + $msi + '"'), '/qb', 'IACCEPTSQLLOCALDBLICENSETERMS=YES') -Wait -PassThru
if (-not $coSan) { Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue }
if ($p.ExitCode -notin 0, 3010) { Loi "Bộ cài báo lỗi (mã $($p.ExitCode))." }
if (-not (Test-Path $key)) { Loi 'Cài xong nhưng chưa thấy LocalDB trong registry.' }
$v = (Get-ChildItem $key | ForEach-Object { $_.PSChildName }) -join ', '
Write-Host ''
Write-Host "XONG: đã cài LocalDB phiên bản $v. Quay lại Trạm Tool, bấm Kiểm tra lại." -ForegroundColor Green
if ($p.ExitCode -eq 3010) { Write-Host 'Windows đề nghị khởi động lại máy để hoàn tất.' -ForegroundColor Yellow }
exit 0
