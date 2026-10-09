<#
  Chuyển dữ liệu khi cài lại Windows: xuất Wi-Fi (kèm mật khẩu), máy in, khoá BitLocker, driver mạng, dữ liệu Claude
  trước khi cài lại; nhập lại sau khi cài xong.

  Không có -Mode: hiện menu. -Mode xuat | nhap: chạy thẳng (1_XUAT_DU_LIEU.bat, 2_NHAP_DU_LIEU.bat, Trạm Tool).
  -Target <thư mục>  xuất: nơi lưu (tạo <thư mục>\DuLieu_SaoLuu; mặc định hỏi, gợi ý USB hoặc ổ dữ liệu);
                     nhập: thư mục bản sao lưu (mặc định tự tìm DuLieu_SaoLuu ở gốc các ổ, USB, cạnh công cụ).
  -Phan tat-ca|driver|bitlocker|wifi|may-in|claude   (nhập) phần cần khôi phục; mặc định hỏi.
  -Driver mang|tat-ca|khong                          (xuất) sao lưu driver nào; mặc định hỏi.
  -MaHoa       (xuất) mã hoá mật khẩu Wi-Fi và cấu hình Claude vào BiMat.aes; mật khẩu luôn gõ trong cửa sổ.
  -DryRun (-ChayThu): chỉ in việc sẽ làm, không ghi file, không đổi máy, không đọc mật khẩu Wi-Fi hay khoá BitLocker.
  -Yes: nhận câu trả lời mặc định cho mọi câu hỏi (không tự đóng Claude, không tự dùng bản sao lưu _cu_).
  -NoPause (-KhongDung): không chờ Enter khi xong.
  Mã thoát: 0 xong, 1 lỗi, 2 chưa làm (thiếu điều kiện, người dùng huỷ, không có bản sao lưu dùng được),
  3 làm được một phần. Kết quả ghi ở ket_qua\KetQua_ChuyenDuLieu_<chế độ>_<máy>_<giờ>.json (không có bí mật).
#>
param(
    [string]$Mode = '',
    [string]$Target = '',
    [string]$Phan = '',
    [string]$Driver = '',
    [switch]$MaHoa,
    [Alias('ChayThu')][switch]$DryRun,
    [switch]$Yes,
    [Alias('KhongDung')][switch]$NoPause,
    [switch]$DaNangQuyen   # đánh dấu cửa sổ đã mở lại bằng quyền Admin, để không hỏi UAC lần nữa
)

$ErrorActionPreference = 'Continue'   # từng bước tự báo lỗi, một lệnh lỗi không dừng cả bản sao lưu
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$script:ToolDir = $PSScriptRoot
$script:MainScript = $PSCommandPath
$script:Version = '2.0'
$script:ResultDir = if ($env:CDL_KET_QUA) { $env:CDL_KET_QUA } else { Join-Path $PSScriptRoot 'ket_qua' }
$script:Started = $false   # đã bắt đầu ghi bản sao lưu / đổi máy
$script:Out = $null        # xuất: thư mục DuLieu_SaoLuu đang ghi
$script:In = $null         # nhập: thư mục bản sao lưu đang đọc
$script:Password = $null
. (Join-Path $PSScriptRoot 'lib\Chung.ps1')
. (Join-Path $PSScriptRoot 'lib\Xuat.ps1')
. (Join-Path $PSScriptRoot 'lib\Nhap.ps1')

$script:Modes = [ordered]@{ xuat = 'Xuất dữ liệu (TRƯỚC khi cài lại Windows)'; nhap = 'Nhập dữ liệu (SAU khi cài lại Windows)' }
$script:DriverModes = @('mang', 'tat-ca', 'khong')

function Format-TargetArg([string]$Path) {
    # 'E:' 'E:\' 'E:\.' -> 'E:\'; thư mục khác bỏ '\' cuối và dấu ngoặc kép
    $p = ([string]$Path).Trim().Trim('"')
    if (-not $p) { return '' }
    if ($p -match '^([A-Za-z]):(\\\.?)?$') { return ($Matches[1].ToUpperInvariant() + ':\') }
    return $p.TrimEnd('\')
}

function Wait-Close([string]$Text = 'Bấm Enter để đóng cửa sổ') {
    $redirected = $false
    try { $redirected = [Console]::IsInputRedirected } catch {}
    if ($NoPause -or $redirected) { return }
    Write-Host ''
    [void](Read-Host "  $Text")
}

function Invoke-Elevated {
    # Mở lại chính script này bằng quyền Admin (Windows hỏi UAC) với cùng tuỳ chọn, chờ xong, trả mã thoát.
    $q = { param([string]$s) $s = $s.Replace('"', ''); if ($s.EndsWith('\')) { $s += '.' }; '"' + $s + '"' }   # "E:\" sẽ nuốt dấu ngoặc
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (& $q $script:MainScript), '-DaNangQuyen', '-Mode', $Mode)
    if ($script:Opt.Target) { $parts += @('-Target', (& $q $script:Opt.Target)) }
    if ($script:Opt.Phan) { $parts += @('-Phan', $script:Opt.Phan) }
    if ($script:Opt.Driver) { $parts += @('-Driver', $script:Opt.Driver) }
    if ($script:Opt.MaHoa) { $parts += '-MaHoa' }
    if ($Yes) { $parts += '-Yes' }
    if ($NoPause) { $parts += '-NoPause' }
    try { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList ($parts -join ' ') -Verb RunAs -Wait -PassThru }
    catch {
        $e = $_.Exception; $native = 0
        while ($e) { if ($e -is [ComponentModel.Win32Exception]) { $native = $e.NativeErrorCode; break }; $e = $e.InnerException }
        if ($native -eq 1223) { Write-Host '  [!]  Bạn đã chọn "Không" ở hộp thoại quyền Admin nên chưa chạy.' -ForegroundColor Yellow; Wait-Close; return 2 }
        Write-Host "  [X]  Không mở được bằng quyền Admin: $($_.Exception.Message.Trim())" -ForegroundColor Red
        Wait-Close
        return 1
    }
    try { return [int]$p.ExitCode } catch { return 0 }
}

function Show-Menu {
    # Trả $true khi đã chọn chế độ (đặt $script:Mode, $script:Opt.DryRun); $false khi thoát
    Write-Host ''
    Write-Host '  CHUYỂN DỮ LIỆU KHI CÀI LẠI WINDOWS' -ForegroundColor Cyan
    Write-Host '  Wi-Fi (kèm mật khẩu), máy in, khoá BitLocker, driver mạng, dữ liệu Claude.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '   1. Xuất dữ liệu (TRƯỚC khi cài lại Windows)'
    Write-Host '   2. Nhập dữ liệu (SAU khi cài lại Windows)'
    Write-Host '   3. Chạy thử xuất: chỉ xem sẽ làm gì'
    Write-Host '   4. Chạy thử nhập: chỉ xem sẽ làm gì'
    Write-Host '   0. Thoát'
    while ($true) {
        $c = Read-Answer 'Chọn số' '0'
        switch ($c) {
            '0' { return $false }
            '1' { $script:Mode = 'xuat'; return $true }
            '2' { $script:Mode = 'nhap'; return $true }
            '3' { $script:Mode = 'xuat'; $script:Opt.DryRun = $true; return $true }
            '4' { $script:Mode = 'nhap'; $script:Opt.DryRun = $true; return $true }
        }
        Write-Host '  Gõ một số từ 0 đến 4.' -ForegroundColor Yellow
    }
}

function Save-RunResult([int]$Code) {
    # Tóm tắt lần chạy cho Trạm Tool; không có mật khẩu, khoá hay nội dung bản sao lưu
    try {
        Ensure-Dir $script:ResultDir
        $dir = if ($Mode -eq 'xuat') { $script:Out } else { $script:In }
        $r = [ordered]@{
            CongCu = 'new-windows'; PhienBan = $script:Version; CheDo = $Mode; ChayThu = [bool]$script:Opt.DryRun
            MaThoat = $Code; KetQua = @{ 0 = 'xong'; 1 = 'loi'; 2 = 'chua-lam'; 3 = 'mot-phan' }[$Code]
            ThuMucSaoLuu = $(if ($script:Started -or ($Mode -eq 'nhap' -and $dir)) { $dir } else { $null })
            May = $env:COMPUTERNAME; NguoiDung = $env:USERNAME
            BatDau = $script:RunStart.ToString('s'); KetThuc = (Get-Date).ToString('s')
            Loi = @($script:Errors); LuuY = @($script:Warnings)
        }
        $f = Join-Path $script:ResultDir ('KetQua_ChuyenDuLieu_{0}_{1}_{2:yyyyMMdd_HHmmss}.json' -f $Mode, $env:COMPUTERNAME, $script:RunStart)
        Save-JsonAtomic $r $f
        Write-Host "  Kết quả: $f" -ForegroundColor Gray
    } catch { Write-Host "  [!]  Không ghi được file kết quả: $($_.Exception.Message)" -ForegroundColor Yellow }
}

function Clear-Secrets {
    $script:Password = $null
    if ($null -ne $script:Secret) { $script:Secret.Clear() }
    if ($null -ne $script:SecretIn) { $script:SecretIn.Clear(); $script:SecretIn = $null }
}

# ---------------------------------------------------------------- tham số
$Mode = ([string]$Mode).Trim().ToLowerInvariant()
$Phan = ([string]$Phan).Trim().ToLowerInvariant()
$Driver = ([string]$Driver).Trim().ToLowerInvariant()
$script:Yes = [bool]$Yes
$script:Opt = @{ Target = (Format-TargetArg $Target); Phan = $Phan; Driver = $Driver; MaHoa = [bool]$MaHoa; DryRun = [bool]$DryRun }
$script:RunStart = Get-Date

if ($env:TRAMTOOL_CHUYENDULIEU_TEST) { return }   # bài thử nạp các hàm rồi tự gọi

$bad = @()
if ($Mode -and -not $script:Modes.Contains($Mode)) { $bad += ('không có chế độ "{0}" (xuat, nhap)' -f $Mode) }
if ($Phan -and -not $script:ImportParts.Contains($Phan)) { $bad += ('-Phan "{0}" không hợp lệ ({1})' -f $Phan, (@($script:ImportParts.Keys) -join ', ')) }
if ($Driver -and $script:DriverModes -notcontains $Driver) { $bad += ('-Driver "{0}" không hợp lệ ({1})' -f $Driver, ($script:DriverModes -join ', ')) }
if ($Mode -eq 'xuat' -and $Phan) { $bad += '-Phan chỉ dùng khi nhập' }
if ($Mode -eq 'nhap' -and ($Driver -or $MaHoa)) { $bad += '-Driver, -MaHoa chỉ dùng khi xuất' }
if ($Target -and -not $script:Opt.Target) { $bad += '-Target rỗng' }
if ($bad.Count) {
    foreach ($b in $bad) { Write-Host "  [X]  $b." -ForegroundColor Red }
    Write-Host '  Cách dùng: ChuyenDuLieu.ps1 -Mode xuat|nhap [-Target <thư mục>] [-Phan ...] [-Driver ...] [-MaHoa] [-DryRun] [-Yes] [-NoPause]'
    Wait-Close
    exit 1
}

try { $Host.UI.RawUI.WindowTitle = 'Chuyển dữ liệu khi cài lại Windows' } catch {}
if (-not $Mode) {
    $redirected = $false
    try { $redirected = [Console]::IsInputRedirected } catch {}
    if ($redirected -or $Yes) { Write-Host 'Cách dùng: ChuyenDuLieu.ps1 -Mode xuat|nhap [-Target <thư mục>] [-DryRun] [-Yes] [-NoPause]'; exit 1 }
    $picked = $false
    try { $picked = Show-Menu } catch { $picked = $false }
    if (-not $picked) { exit 0 }
    $Mode = $script:Mode
}

if (-not $script:Opt.DryRun -and -not (Test-IsAdmin)) {
    if ($DaNangQuyen) { Write-Host '  [X]  Đã mở lại mà vẫn chưa có quyền Administrator.' -ForegroundColor Red; Wait-Close; exit 2 }
    Write-Host '  [i]  Cần quyền Administrator (mật khẩu Wi-Fi, driver, BitLocker): Windows sẽ hỏi (UAC), chọn "Có".' -ForegroundColor Gray
    exit (Invoke-Elevated)
}

# ---------------------------------------------------------------- chạy
$code = 1
try {
    $r = if ($Mode -eq 'xuat') { @(Invoke-Xuat) } else { @(Invoke-Nhap) }
    $code = [int]$r[-1]
} catch {
    if ([string]$_.Exception.Message -eq $script:EndOfInput) {
        Write-Host '  [!]  Hết dữ liệu vào (đang chạy tự động) nên dừng ở câu hỏi trên.' -ForegroundColor Yellow
        # Chưa làm gì: 2. Nhập dở: máy đã đổi một phần (3). Xuất dở: bản sao lưu không dùng được (1).
        $code = if (-not $script:Started) { 2 } elseif ($Mode -eq 'nhap') { 3 } else { 1 }
    } else {
        Fail ('Lỗi không lường trước: {0}' -f $_.Exception.Message)
        $code = 1
    }
    if ($Mode -eq 'xuat' -and $script:Started -and $script:Out) { try { Write-ExportManifest 'loi' } catch {} }
    try { Stop-Transcript | Out-Null } catch {}
} finally {
    Clear-Secrets
}
Save-RunResult $code
Wait-Close
exit $code
