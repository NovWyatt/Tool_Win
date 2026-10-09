<#
  BitLocker và khoá khôi phục: kiểm tra, lưu khoá ra file, tạm dừng trước khi cập nhật BIOS hay thay phần cứng,
  bật lại, mở khoá ổ bị khoá, giải mã ổ dữ liệu, hoàn tác.

  Không có -Mode: hiện menu (bấm đúp BITLOCKER.bat). -Mode <chế độ>: chạy thẳng (Trạm Tool dùng cách này).
  Chế độ: kiem-tra, luu-khoa, tam-dung, bat-lai, mo-khoa, giai-ma, hoan-tac.
  -ChayThu: chỉ xem sẽ làm gì, không thay đổi máy. Báo cáo, file khoá, nhật ký hoàn tác nằm trong ket_qua\.
  Khoá khôi phục không bao giờ vào báo cáo hay nhật ký; khoá gõ tay chỉ gõ trong cửa sổ này, không nhận qua tham số.
  Mã thoát: 0 xong, 1 lỗi, 2 thiếu điều kiện (quyền Admin, không có khoá), 3 làm được một phần.
#>
param(
    [string]$Mode = '',
    [string]$NoiLuu = '',      # luu-khoa: thư mục lưu file khoá (trống: ket_qua\khoa-bitlocker)
    [string]$SoLan = '',       # tam-dung: số lần khởi động, 0 = đến khi bật lại bằng tay (trống: hỏi, mặc định 1)
    [string]$ODia = '',        # mo-khoa, giai-ma: chữ ổ (trống: mọi ổ bị khoá / chọn trong danh sách)
    [string]$ThuMucKhoa = '',  # kiem-tra, mo-khoa: thư mục có file khoá khôi phục, tìm thêm ở đó
    [string]$NhatKy = '',      # hoan-tac: tên file nhật ký (trống: chọn trong danh sách)
    [switch]$ChayThu,
    [switch]$KhongDung         # không chờ Enter khi xong (chạy tự động)
)

$ErrorActionPreference = 'Stop'
$script:ToolDir = $PSScriptRoot
$script:MainScript = $PSCommandPath
$script:ToolVersion = '1.1'
. (Join-Path $PSScriptRoot 'lib\Chung.ps1')
. (Join-Path $PSScriptRoot 'lib\NhatKy.ps1')
. (Join-Path $PSScriptRoot 'lib\DocBitLocker.ps1')
. (Join-Path $PSScriptRoot 'lib\ChanDoan.ps1')
. (Join-Path $PSScriptRoot 'lib\ThaoTac.ps1')
$script:NoPause = [bool]$KhongDung

# No: số trong menu. Admin: yes (cần), prefer (nên có, thiếu vẫn chạy được).
$script:Modes = [ordered]@{
    'kiem-tra' = @{ No = 1; Label = 'Kiểm tra BitLocker và khoá khôi phục'; Admin = 'prefer' }
    'luu-khoa' = @{ No = 2; Label = 'Lưu khoá khôi phục ra file'; Admin = 'yes' }
    'tam-dung' = @{ No = 3; Label = 'Tạm dừng BitLocker (trước khi cập nhật BIOS, thay phần cứng)'; Admin = 'yes' }
    'bat-lai'  = @{ No = 4; Label = 'Bật lại BitLocker'; Admin = 'yes' }
    'mo-khoa'  = @{ No = 5; Label = 'Mở khoá ổ bị BitLocker khoá'; Admin = 'yes' }
    'giai-ma'  = @{ No = 6; Label = 'Giải mã ổ dữ liệu, USB (tắt BitLocker)'; Admin = 'yes' }
    'hoan-tac' = @{ No = 7; Label = 'Hoàn tác lần thay đổi trước'; Admin = 'yes' }
}

function Format-FolderArg {
    # 'E:', 'E:\', 'E:\.' → 'E:\.' để truyền qua dòng lệnh không vỡ dấu ngoặc ("E:\" thành E:"); bỏ '\' cuối của thư mục khác.
    param([string]$Path)
    $p = ([string]$Path).Trim().Trim('"')
    if (-not $p) { return '' }
    if ($p -match '^([A-Za-z]):(\\\.?)?$') { return ($Matches[1].ToUpperInvariant() + ':\.') }
    return $p.TrimEnd('\')
}

function Test-ModeOptions {
    # Kiểm tra giá trị nhập trước khi xin quyền Admin. Trả câu báo lỗi, hoặc '' khi hợp lệ.
    param([hashtable]$O)
    if ($O.ODia -and -not (Format-DriveLetter $O.ODia)) { return "Chữ ổ '$($O.ODia)' không hợp lệ (vd E)." }
    if ([string]$O.SoLan) {
        $n = 0
        if (-not [int]::TryParse([string]$O.SoLan, [ref]$n) -or $n -lt 0 -or $n -gt 15) { return "Số lần khởi động '$($O.SoLan)' không hợp lệ (0 đến 15)." }
    }
    foreach ($k in 'NoiLuu', 'ThuMucKhoa') {
        $p = [string]$O[$k]
        if (-not $p) { continue }
        if ($p -match '[*?"<>|]' -or $p.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0) { return "Đường dẫn '$p' có ký tự không hợp lệ." }
        if ($p -notmatch '^([A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)') { return "Đường dẫn '$p' phải là đường dẫn đầy đủ (vd E:\ hoặc D:\KhoaBitLocker)." }
        try { [void][IO.Path]::GetFullPath($p) } catch { return "Đường dẫn '$p' không hợp lệ." }
    }
    if ($O.ThuMucKhoa -and -not (Test-Path -LiteralPath ([string]$O.ThuMucKhoa) -PathType Container)) { return "Không thấy thư mục '$($O.ThuMucKhoa)'." }
    if ($O.NhatKy -and $O.NhatKy -notmatch '^HoanTac_[\w-]+(\.json)?$') { return "Tên nhật ký '$($O.NhatKy)' không hợp lệ." }
    return ''
}

function Invoke-Mode {
    param([string]$Id, [hashtable]$O)
    $dry = [bool]$O.ChayThu
    switch ($Id) {
        'kiem-tra' { return (Invoke-KiemTra -ThuMucKhoa ([string]$O.ThuMucKhoa)) }
        'luu-khoa' { return (Invoke-LuuKhoa -NoiLuu ([string]$O.NoiLuu) -DryRun:$dry) }
        'tam-dung' { return (Invoke-TamDung -SoLan ([string]$O.SoLan) -DryRun:$dry) }
        'bat-lai' { return (Invoke-BatLai -DryRun:$dry) }
        'mo-khoa' { return (Invoke-MoKhoa -ODia (Format-DriveLetter $O.ODia) -ThuMucKhoa ([string]$O.ThuMucKhoa) -DryRun:$dry) }
        'giai-ma' { return (Invoke-GiaiMa -ODia (Format-DriveLetter $O.ODia) -DryRun:$dry) }
        'hoan-tac' { return (Invoke-HoanTac -NhatKy ([string]$O.NhatKy) -DryRun:$dry) }
    }
    return 1
}

function Invoke-ModeSafe {
    # Chạy một chế độ; lỗi không lường trước thì in ra và trả mã 1 thay vì đóng cửa sổ.
    param([string]$Id, [hashtable]$O)
    try {
        $out = @(Invoke-Mode $Id $O)
        if ($out.Count -and $out[-1] -is [int]) { return $out[-1] }
        return 0
    } catch {
        Write-Bad ('Lỗi không lường trước: {0}' -f $_.Exception.Message.Trim())
        Write-Sub (([string]$_.InvocationInfo.PositionMessage).Split("`n")[0])
        return 1
    }
}

function Invoke-Elevated {
    # Mở lại chính script này bằng quyền Admin (Windows hỏi UAC) với cùng chế độ, chờ xong, trả mã thoát.
    param([string]$Id, [hashtable]$O)
    $q = { param([string]$s) '"' + $s.Replace('"', '').TrimEnd('\') + '"' }
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (& $q $script:MainScript), '-Mode', $Id)
    foreach ($k in @($O.Keys)) {
        $v = $O[$k]
        if ($v -is [bool]) { if ($v) { $parts += "-$k" } }
        elseif ([string]$v) { $parts += "-$k"; $parts += (& $q ([string]$v)) }
    }
    try { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList ($parts -join ' ') -Verb RunAs -Wait -PassThru }
    catch {
        $e = $_.Exception; $native = 0
        while ($e) { if ($e -is [ComponentModel.Win32Exception]) { $native = $e.NativeErrorCode; break }; $e = $e.InnerException }
        if ($native -eq 1223) { Write-Warn 'Bạn đã chọn "Không" ở hộp thoại quyền Admin nên chưa chạy.'; return 2 }
        Write-Bad "Không mở được bằng quyền Admin: $($_.Exception.Message.Trim())"
        return 1
    }
    try { return [int]$p.ExitCode } catch { return 0 }
}

function Read-MenuOptions {
    # Hỏi các giá trị một chế độ cần. Trả $null khi giá trị nhập không hợp lệ.
    param([string]$Id)
    $o = @{}
    switch ($Id) {
        'luu-khoa' { $o.NoiLuu = Format-FolderArg (Read-Text 'Lưu vào thư mục nào? (vd E:\ là USB; Enter = thư mục ket_qua\khoa-bitlocker của công cụ)') }
        'tam-dung' { $o.SoLan = [string](Read-Number 'Tạm dừng trong mấy lần khởi động? 1-15, 0 = đến khi bật lại bằng tay (Enter = 1)' 0 15 1) }
        'mo-khoa' {
            $o.ODia = Read-Text 'Chữ ổ cần mở (Enter = mọi ổ đang bị khoá)'
            $o.ThuMucKhoa = Format-FolderArg (Read-Text 'Thư mục có file khoá khôi phục (Enter = công cụ tự tìm)')
        }
        'giai-ma' { $o.ODia = Read-Text 'Chữ ổ cần giải mã (Enter = chọn trong danh sách)' }
    }
    $err = Test-ModeOptions $o
    if ($err) { Write-Bad $err; return $null }
    return $o
}

function Show-Menu {
    while ($true) {
        try { $Host.UI.RawUI.WindowTitle = 'BitLocker' } catch { }
        Write-Host ''
        Write-Host '  BITLOCKER VÀ KHOÁ KHÔI PHỤC' -ForegroundColor Cyan
        Write-Host '  Kiểm tra trước. Khoá khôi phục chỉ ghi vào file bạn chọn, không bao giờ vào báo cáo.' -ForegroundColor Gray
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
        $def = $script:Modes[$id]
        $admin = Test-IsAdmin
        $elevate = $false
        if (-not $admin -and $def.Admin -eq 'yes') { $elevate = $true }
        elseif (-not $admin -and $def.Admin -eq 'prefer') { $elevate = Read-YesNo 'Chạy bằng quyền Admin để đọc được từng ổ?' $true }
        if ($elevate) {
            # Cửa sổ Admin tự dừng chờ Enter khi xong; menu này chờ nó đóng rồi hiện lại.
            Write-Info 'Windows sẽ hỏi quyền Admin, chọn "Có". Kết quả hiện trong cửa sổ mới.'
            [void](Invoke-Elevated $id $o)
        } else {
            [void](Invoke-ModeSafe $id $o)
            Wait-Close 'Bấm Enter để về menu'
        }
    }
}

# ---------------------------------------------------------------- bắt đầu
try { $Host.UI.RawUI.WindowTitle = 'BitLocker' } catch { }
$opts = @{
    NoiLuu = (Format-FolderArg $NoiLuu); SoLan = $SoLan; ODia = $ODia; ThuMucKhoa = (Format-FolderArg $ThuMucKhoa)
    NhatKy = $NhatKy; ChayThu = [bool]$ChayThu
}

if (-not $Mode) {
    if ([Console]::IsInputRedirected) {
        Write-Host ('Cách dùng: BitLocker.ps1 -Mode <chế độ> [-ChayThu]. Chế độ: {0}.' -f (@($script:Modes.Keys) -join ', '))
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
try { $Host.UI.RawUI.WindowTitle = 'BitLocker - ' + $def.Label } catch { }
if ($def.Admin -eq 'yes' -and -not (Test-IsAdmin) -and -not $ChayThu) {
    # Chạy thử thì không xin quyền: từng chế độ tự in các bước chung khi không đọc được ổ.
    Write-Info 'Chế độ này cần quyền Admin: Windows sẽ hỏi (UAC), chọn "Có".'
    exit (Invoke-Elevated $Mode $opts)
}
$code = Invoke-ModeSafe $Mode $opts
Wait-Close
exit $code
