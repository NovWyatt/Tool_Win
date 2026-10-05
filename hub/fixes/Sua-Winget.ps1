<#
  Trạm Tool - sửa winget (các nút "Cài" của trạm đều dùng winget).
  Chạy bằng quyền thường: App Installer đăng ký theo từng tài khoản Windows, phải đăng ký đúng tài khoản đang dùng.
  Làm theo thứ tự trong hướng dẫn của Microsoft, bước nào cũng hỏi trước:
    1. Đăng ký lại App Installer (Add-AppxPackage -RegisterByFamilyName).
    2. Cập nhật nguồn (winget source update); vẫn lỗi thì đặt lại nguồn (winget source reset --force, cần Admin).
    3. Repair-WinGetPackageManager (module Microsoft.WinGet.Client từ PowerShell Gallery, cần mạng).
    4. Không được nữa: mở trang App Installer trên Microsoft Store.
  https://learn.microsoft.com/windows/package-manager/winget/ ,
  https://learn.microsoft.com/windows/package-manager/winget/troubleshooting
  Mã thoát: 0 = winget dùng được, 1 = vẫn lỗi, 1223 = người dùng dừng giữa chừng.
#>
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
. (Join-Path $PSScriptRoot '..\lib\Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\AnToan.ps1')
$Host.UI.RawUI.WindowTitle = 'Trạm Tool - sửa winget'

function Show-Status {
    param($S)
    if ($S.ok) { Write-AtOk "winget dùng được: $($S.version) (App Installer $($S.appInstaller))." }
    else { Write-AtWarn $S.problem }
}

function Confirm-Step {
    # [C] làm bước này, [B] bỏ qua bước này, [D] dừng hẳn.
    param([string]$Text)
    Write-Host ''
    Write-Host "  $Text" -ForegroundColor White
    $c = Read-AtChoice -Prompt '[C] Làm   [B] Bỏ qua bước này   [D] Dừng' -Keys @('C', 'B', 'D') -Fallback 'D'
    if ($c -eq 'D') { Write-AtInfo 'Đã dừng.'; Wait-AtClose; exit 1223 }
    return ($c -eq 'C')
}

function Invoke-Winget {
    # Chạy winget trong cửa sổ này để thấy tiến trình; trả mã thoát.
    param([string[]]$WingetArgs)
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { Write-AtBad 'Chưa có lệnh winget.'; return -1 }
    & $cmd.Source @WingetArgs
    $code = $LASTEXITCODE
    if ($code -ne 0) { Write-AtWarn "winget trả mã $(Format-ExitCode $code)." }
    return $code
}

Write-AtHead 'SỬA WINGET' 'Các nút "Cài" của Trạm Tool dùng winget để cài phần mềm còn thiếu.'
if (Test-IsAdmin) {
    Write-AtWarn 'Cửa sổ này đang có quyền Admin. Nếu UAC dùng tài khoản Admin khác, App Installer sẽ được đăng ký cho tài khoản đó.'
}
$s = Get-WingetStatus
Show-Status $s

if ($s.ok) {
    if (Confirm-Step 'Cập nhật danh sách gói của các nguồn (winget source update)?') {
        [void](Invoke-Winget @('source', 'update'))
    }
    Wait-AtClose
    exit 0
}

# 1. Đăng ký lại App Installer cho tài khoản này (chưa có lệnh winget, hoặc có mà chạy lỗi).
if ($s.stage -in 'install', 'run') {
    if (Confirm-Step 'Bước 1: đăng ký lại App Installer cho tài khoản Windows này (không cần mạng, không cần Admin).') {
        try {
            Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop
            Write-AtOk 'Đã đăng ký lại App Installer.'
            Start-Sleep -Seconds 2
        } catch { Write-AtBad "Không đăng ký được: $($_.Exception.Message.Trim())" }
        $s = Get-WingetStatus
        Show-Status $s
    }
}

# 2. Nguồn của winget (lệnh chạy được nhưng nguồn lỗi).
if ($s.stage -eq 'source') {
    if (Confirm-Step 'Bước 2: cập nhật nguồn của winget (winget source update, cần mạng).') {
        [void](Invoke-Winget @('source', 'update'))
        $s = Get-WingetStatus
        Show-Status $s
    }
    if ($s.stage -eq 'source' -and (Confirm-Step 'Vẫn lỗi. Đặt lại nguồn về mặc định (winget source reset --force)? Cần quyền Admin; nguồn tự thêm sẽ bị xoá.')) {
        # Gọi "winget" theo tên trong cửa sổ Admin: đường dẫn WindowsApps của tài khoản này có thể không dùng được ở đó.
        $cmd = 'winget source reset --force; winget source update; Write-Host ''''; Read-Host ''Xong. Bấm Enter để đóng cửa sổ này'''
        try {
            $p = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList ('-NoProfile -Command "' + $cmd + '"')
            Write-AtInfo "Cửa sổ Admin đã đóng (mã $(Format-ExitCode $p.ExitCode))."
        } catch { Write-AtBad "Không mở được cửa sổ Admin (có thể đã bấm No ở UAC): $($_.Exception.Message.Trim())" }
        $s = Get-WingetStatus
        Show-Status $s
    }
}

# 3. Repair-WinGetPackageManager.
if (-not $s.ok) {
    if (Confirm-Step 'Bước 3: cài module Microsoft.WinGet.Client (PowerShell Gallery) cho tài khoản này rồi chạy Repair-WinGetPackageManager. Cần mạng, mất vài phút.') {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]'2.8.5.201' })) {
                Write-AtInfo 'Cài NuGet provider...'
                [void](Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force)
            }
            Write-AtInfo 'Cài module Microsoft.WinGet.Client...'
            Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
            Import-Module Microsoft.WinGet.Client -Force
            Write-AtInfo 'Chạy Repair-WinGetPackageManager -Latest -Force...'
            Repair-WinGetPackageManager -Latest -Force
            Write-AtOk 'Repair-WinGetPackageManager đã chạy xong.'
        } catch { Write-AtBad "Không sửa được bằng Repair-WinGetPackageManager: $($_.Exception.Message.Trim())" }
        $s = Get-WingetStatus
        Show-Status $s
    }
}

# 4. Hết cách tự động: mở Microsoft Store.
if (-not $s.ok) {
    Write-Host ''
    Write-AtWarn 'winget vẫn chưa dùng được.'
    Write-AtInfo 'Cài hoặc cập nhật "App Installer" từ Microsoft Store (máy có Store), rồi bấm Đọc lại trong trạm.'
    Write-AtInfo 'Windows LTSC, Windows Server thường không có Store: xem https://learn.microsoft.com/windows/package-manager/winget/'
    if (Confirm-Step 'Mở trang App Installer trên Microsoft Store?') {
        try { Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' } catch { Write-AtBad "Không mở được Store: $($_.Exception.Message.Trim())" }
    }
    Wait-AtClose
    exit 1
}

Write-Host ''
Write-AtOk 'Xong. Quay lại Trạm Tool, bấm Đọc lại ở trang Máy này.'
Wait-AtClose
exit 0
