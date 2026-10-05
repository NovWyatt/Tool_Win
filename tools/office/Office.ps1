<#
  Gỡ sạch Office và cài Office theo mẫu (bộ cài Office Deployment Tool: setup.exe, file cấu hình .xml, thư mục Office).

  Không có -Mode: hiện menu (bấm đúp OFFICE.bat). -Mode <chế độ>: chạy thẳng (Trạm Tool dùng cách này).
  Chế độ: kiem-tra, go-va-cai, go-sach, cai-dat, kich-hoat, tra-lai.
  Mẫu: -Mau <thư mục>, không có thì tìm tools\office\mau rồi "<ổ>:\Program Files\Microsoft Office" có setup.exe.
  -ChayThu: chỉ xem sẽ làm gì, không thay đổi máy. Báo cáo, nhật ký, bản sao lưu nằm trong ket_qua\.
  Khoá sản phẩm trong file cấu hình không bao giờ được in, ghi báo cáo hay chép đi đâu: công cụ chạy file cấu hình tại chỗ.
  Khoá nhập ở bước kích hoạt chỉ gõ trong cửa sổ công cụ (không hiện khi gõ), không nhận qua tham số.
  Mã thoát: 0 xong, 1 lỗi, 2 thiếu điều kiện (mẫu hỏng, thiếu quyền Admin), 3 làm được một phần, 1223 người dùng huỷ.
#>
param(
    [string]$Mode = '',
    [string]$Mau = '',        # thư mục bộ cài mẫu (có setup.exe)
    [string]$CauHinh = '',    # file cấu hình trong mẫu (trống: Configuration.xml hoặc file duy nhất)
    [string]$SaoLuu = '',     # tra-lai: tên bản sao lưu (trống: chọn trong danh sách)
    [switch]$QuetSau,         # go-sach, go-va-cai: quét sâu bằng công cụ gỡ Office của Microsoft (GetHelpCmd)
    [switch]$XoaThietLap,     # go-sach, go-va-cai: xoá cả thiết lập Office của người dùng (sao lưu trước)
    [switch]$ChayThu,
    [switch]$KhongDung        # không chờ Enter khi xong (chạy tự động)
)

$ErrorActionPreference = 'Stop'
$script:ToolDir = $PSScriptRoot
$script:MainScript = $PSCommandPath
$script:ToolVersion = '1.0'
. (Join-Path $PSScriptRoot 'lib\Chung.ps1')
. (Join-Path $PSScriptRoot 'lib\DocOffice.ps1')
. (Join-Path $PSScriptRoot 'lib\SaoLuu.ps1')
. (Join-Path $PSScriptRoot 'lib\GoOffice.ps1')
. (Join-Path $PSScriptRoot 'lib\CaiOffice.ps1')
. (Join-Path $PSScriptRoot 'lib\KiemTra.ps1')
$script:NoPause = [bool]$KhongDung

# No: số trong menu. Admin: yes (cần), no (không cần). Log: tên đầu file nhật ký ('' = không ghi nhật ký).
$script:Modes = [ordered]@{
    'kiem-tra'  = @{ No = 1; Label = 'Kiểm tra Office trên máy và bộ cài mẫu'; Admin = 'no'; Log = '' }
    'go-va-cai' = @{ No = 2; Label = 'Gỡ sạch Office cũ rồi cài theo mẫu'; Admin = 'yes'; Log = 'NhatKy_Office' }
    'go-sach'   = @{ No = 3; Label = 'Chỉ gỡ sạch Office'; Admin = 'yes'; Log = 'NhatKy_Office' }
    'cai-dat'   = @{ No = 4; Label = 'Chỉ cài Office theo mẫu'; Admin = 'yes'; Log = 'NhatKy_Office' }
    'kich-hoat' = @{ No = 5; Label = 'Kích hoạt Office (kích hoạt lại, nhập khoá của bạn)'; Admin = 'yes'; Log = 'NhatKy_Office' }
    'tra-lai'   = @{ No = 6; Label = 'Trả lại mẫu Word, macro, chữ ký đã sao lưu'; Admin = 'no'; Log = 'NhatKy_Office' }
}

function Test-ModeOptions {
    # Kiểm tra giá trị nhập trước khi xin quyền Admin. Trả câu báo lỗi, hoặc '' khi hợp lệ.
    param([hashtable]$O)
    $m = [string]$O.Mau
    if ($m) {
        if ($m -match '[*?"<>|]' -or $m.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0) { return "Đường dẫn mẫu '$m' có ký tự không hợp lệ." }
        if ($m -notmatch '^([A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)') { return "Đường dẫn mẫu '$m' phải là đường dẫn đầy đủ (vd D:\MauOffice)." }
        if (-not (Test-Path -LiteralPath $m)) { return "Không thấy thư mục mẫu '$m'." }
    }
    $c = [string]$O.CauHinh
    if ($c) {
        if ($c -match '[*?"<>|]' -or $c.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0) { return "Tên file cấu hình '$c' có ký tự không hợp lệ." }
        if ($c -notmatch '(?i)\.xml$') { return "File cấu hình '$c' phải là file .xml." }
    }
    if ($O.SaoLuu -and $O.SaoLuu -notmatch '^SaoLuu_[\w-]+$') { return "Tên bản sao lưu '$($O.SaoLuu)' không hợp lệ." }
    return ''
}

function Invoke-Mode {
    param([string]$Id, [hashtable]$O)
    $dry = [bool]$O.ChayThu
    switch ($Id) {
        'kiem-tra' { return (Invoke-KiemTra -Mau $O.Mau -CauHinh $O.CauHinh) }
        'go-va-cai' { return (Invoke-GoVaCai -Mau $O.Mau -CauHinh $O.CauHinh -QuetSau:([bool]$O.QuetSau) -XoaThietLap:([bool]$O.XoaThietLap) -DryRun:$dry) }
        'go-sach' { return (Invoke-GoSach -Mau $O.Mau -QuetSau:([bool]$O.QuetSau) -XoaThietLap:([bool]$O.XoaThietLap) -DryRun:$dry) }
        'cai-dat' { return (Invoke-CaiDat -Mau $O.Mau -CauHinh $O.CauHinh -DryRun:$dry) }
        'kich-hoat' { return (Invoke-KichHoat -DryRun:$dry) }
        'tra-lai' { return (Invoke-TraLai -SaoLuu $O.SaoLuu -DryRun:$dry) }
    }
    return 1
}

function Invoke-ModeSafe {
    # Chạy một chế độ; lỗi không lường trước thì in ra và trả mã 1 thay vì đóng cửa sổ.
    # Chế độ có thay đổi (không phải chạy thử): ghi nhật ký ket_qua\NhatKy_Office_<máy>_<thời gian>.txt kể cả khi lỗi.
    param([string]$Id, [hashtable]$O)
    $script:Report.Clear(); $script:Findings.Clear()
    $started = Get-Date
    $code = 1
    try {
        $out = @(Invoke-Mode $Id $O)
        $code = if ($out.Count -and $out[-1] -is [int]) { $out[-1] } else { 0 }
    } catch {
        Write-Bad ('Lỗi không lường trước: {0}' -f $_.Exception.Message.Trim())
        Write-Sub (([string]$_.InvocationInfo.PositionMessage).Split("`n")[0])
        $code = 1
    } finally {
        $log = $script:Modes[$Id].Log
        if ($log -and -not $O.ChayThu -and $script:Report.Count) {
            Write-Out ''
            Write-Out ('Kết thúc {0:dd/MM/yyyy HH:mm}, mã {1}.' -f (Get-Date), $code)
            [void](Save-Report $log $started)
        }
    }
    return $code
}

function Invoke-Elevated {
    # Mở lại chính script này bằng quyền Admin (Windows hỏi UAC) với cùng chế độ, chờ xong, trả mã thoát.
    param([string]$Id, [hashtable]$O)
    $q = { param([string]$s) '"' + $s.Replace('"', '') + '"' }
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (& $q $script:MainScript), '-Mode', $Id)
    foreach ($k in @($O.Keys)) {
        $v = $O[$k]
        if ($v -is [bool]) { if ($v) { $parts += "-$k" } }
        elseif ([string]$v) { $parts += "-$k"; $parts += (& $q (Format-FolderArg ([string]$v))) }
    }
    try { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList ($parts -join ' ') -Verb RunAs -Wait -PassThru }
    catch {
        $e = $_.Exception; $native = 0
        while ($e) { if ($e -is [ComponentModel.Win32Exception]) { $native = $e.NativeErrorCode; break }; $e = $e.InnerException }
        if ($native -eq 1223) { Write-Warn 'Bạn đã chọn "Không" ở hộp thoại quyền Admin nên chưa chạy.'; return 1223 }
        Write-Bad "Không mở được bằng quyền Admin: $($_.Exception.Message.Trim())"
        return 1
    }
    try { return [int]$p.ExitCode } catch { return 0 }
}

function Read-MenuOptions {
    # Hỏi các giá trị một chế độ cần. Trả $null khi giá trị nhập không hợp lệ.
    param([string]$Id)
    $o = @{}
    if ($Id -in 'kiem-tra', 'go-va-cai', 'cai-dat') {
        $found = Find-TemplateDir ''
        $hint = if ($found) { "Enter = $found" } else { 'chưa tìm thấy mẫu, Enter = bỏ qua' }
        $o.Mau = Format-FolderArg (Read-Text "Thư mục bộ cài mẫu ($hint)")
    }
    if ($Id -in 'go-va-cai', 'go-sach') {
        $o.QuetSau = Read-YesNo 'Quét sâu thêm bằng công cụ gỡ Office của Microsoft (tải về, lâu hơn)?' $false
        $o.XoaThietLap = Read-YesNo 'Xoá cả thiết lập Office của người dùng (đã sao lưu trước, xoá cả hồ sơ Outlook)?' $false
    }
    if ($Id -ne 'kiem-tra') { $o.ChayThu = Read-YesNo 'Chạy thử (chỉ xem sẽ làm gì, không đổi máy)?' $false }
    $err = Test-ModeOptions $o
    if ($err) { Write-Bad $err; return $null }
    return $o
}

function Show-Menu {
    while ($true) {
        try { $Host.UI.RawUI.WindowTitle = 'Gỡ sạch và cài Office theo mẫu' } catch { }
        Write-Host ''
        Write-Host '  GỠ SẠCH VÀ CÀI OFFICE THEO MẪU' -ForegroundColor Cyan
        Write-Host '  Kiểm tra trước. Gỡ xong mới cài; mẫu hỏng thì không gỡ gì. Khoá sản phẩm không bao giờ hiện ra.' -ForegroundColor Gray
        Write-Host ''
        foreach ($id in $script:Modes.Keys) {
            $m = $script:Modes[$id]
            Write-Host ('   {0}. {1}' -f $m.No, $m.Label)
        }
        Write-Host '   0. Thoát'
        Write-Host ''
        $c = Read-Text 'Chọn số'
        if ($c -eq '0') { return 0 }
        $id = $null
        foreach ($k in $script:Modes.Keys) { if ([string]$script:Modes[$k].No -eq $c) { $id = $k } }
        if (-not $id) { continue }
        $o = Read-MenuOptions $id
        if ($null -eq $o) { continue }
        if ($script:Modes[$id].Admin -eq 'yes' -and -not (Test-IsAdmin) -and -not $o.ChayThu) {
            # Cửa sổ Admin tự dừng chờ Enter khi xong; menu này chờ nó đóng rồi hiện lại.
            Write-Info 'Windows sẽ hỏi quyền Admin, chọn "Có". Việc gỡ, cài chạy trong cửa sổ mới.'
            [void](Invoke-Elevated $id $o)
        } else {
            [void](Invoke-ModeSafe $id $o)
            Wait-Close 'Bấm Enter để về menu'
        }
    }
}

# ---------------------------------------------------------------- bắt đầu
try { $Host.UI.RawUI.WindowTitle = 'Gỡ sạch và cài Office theo mẫu' } catch { }
$opts = @{
    Mau = (Format-FolderArg $Mau); CauHinh = $CauHinh.Trim().Trim('"'); SaoLuu = $SaoLuu.Trim()
    QuetSau = [bool]$QuetSau; XoaThietLap = [bool]$XoaThietLap; ChayThu = [bool]$ChayThu
}
if ($opts.Mau -match '^[A-Za-z]:\\\.$') { $opts.Mau = $opts.Mau.Substring(0, 3) }

if (-not $Mode) {
    if ([Console]::IsInputRedirected) {
        Write-Host ('Cách dùng: Office.ps1 -Mode <chế độ> [-Mau <thư mục>] [-ChayThu]. Chế độ: {0}.' -f (@($script:Modes.Keys) -join ', '))
        exit 1
    }
    exit (Show-Menu)
}
if (-not $script:Modes.Contains($Mode)) {
    Write-Bad ('Không có chế độ "{0}". Các chế độ: {1}.' -f $Mode, (@($script:Modes.Keys) -join ', '))
    Wait-Close
    exit 1
}
$problem = Test-ModeOptions $opts
if ($problem) { Write-Bad $problem; Wait-Close; exit 1 }

$def = $script:Modes[$Mode]
try { $Host.UI.RawUI.WindowTitle = 'Office - ' + $def.Label } catch { }
if ($def.Admin -eq 'yes' -and -not (Test-IsAdmin) -and -not $ChayThu) {
    # Chạy thử thì không xin quyền: chỉ đọc và in kế hoạch.
    Write-Info 'Chế độ này cần quyền Admin: Windows sẽ hỏi (UAC), chọn "Có".'
    exit (Invoke-Elevated $Mode $opts)
}
$code = Invoke-ModeSafe $Mode $opts
Wait-Close
exit $code
