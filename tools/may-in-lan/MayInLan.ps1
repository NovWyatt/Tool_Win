<#
  Máy in mạng LAN và thư mục chia sẻ: chẩn đoán, sửa từng bước, có hoàn tác.

  Không có -Mode: hiện menu (bấm đúp MAY_IN_LAN.bat). -Mode <chế độ>: chạy thẳng (Trạm Tool dùng cách này).
  Chế độ: chan-doan, sua-hang-doi, xoa-may-in-trung, bat-chia-se, ket-noi-may-in, them-may-in-ip,
          ket-noi-thu-muc, noi-bao-mat, hoan-tac.
  -ChayThu: chỉ xem sẽ làm gì, không thay đổi máy. Kết quả, nhật ký hoàn tác nằm trong ket_qua\.
  Mã thoát: 0 xong, 1 lỗi, 2 thiếu điều kiện (quyền Admin, driver, máy kia không kết nối được), 3 làm được một phần.
#>
param(
    [string]$Mode = '',
    [string]$MayChu = '',      # chan-doan: máy cần kiểm tra thêm; ket-noi-may-in: máy chia sẻ máy in (hoặc \\may\may-in)
    [string]$TenChiaSe = '',   # ket-noi-may-in: tên chia sẻ của máy in
    [switch]$ChoMoiNguoi,      # ket-noi-may-in: thêm cho mọi tài khoản trên máy
    [string]$DiaChi = '',      # them-may-in-ip: IP máy in
    [string]$TenMayIn = '',    # them-may-in-ip: tên đặt cho máy in
    [string]$Kieu = 'tu-dong', # them-may-in-ip: tu-dong, ipp, raw
    [string]$DuongDan = '',    # ket-noi-thu-muc: \\may\thu-muc
    [string]$ODia = '',        # ket-noi-thu-muc: chữ ổ đĩa
    [string]$TaiKhoan = '',    # ket-noi-thu-muc: tài khoản trên máy chia sẻ; mật khẩu gõ trong cửa sổ này, không đi qua trạm
    [switch]$Ngat,             # ket-noi-thu-muc: ngắt ổ mạng thay vì kết nối
    [string]$Muc = '',         # noi-bao-mat: rpc-named-pipe, rpc-privacy-off, smb-guest, smb-signing-off
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
. (Join-Path $PSScriptRoot 'lib\ChanDoan.ps1')
. (Join-Path $PSScriptRoot 'lib\SuaLoi.ps1')
$script:NoPause = [bool]$KhongDung

# No: số trong menu. Admin: yes (cần), prefer (nên có, thiếu vẫn chạy được), no (phải chạy quyền thường).
$script:Modes = [ordered]@{
    'chan-doan'        = @{ No = 1; Label = 'Chẩn đoán máy in và chia sẻ mạng'; Admin = 'prefer' }
    'sua-hang-doi'     = @{ No = 2; Label = 'Sửa hàng đợi in bị kẹt'; Admin = 'yes' }
    'xoa-may-in-trung' = @{ No = 3; Label = 'Xoá máy in trùng (Copy 1)'; Admin = 'yes' }
    'bat-chia-se'      = @{ No = 4; Label = 'Bật chia sẻ file và máy in trên máy này'; Admin = 'yes' }
    'ket-noi-may-in'   = @{ No = 5; Label = 'Kết nối máy in chia sẻ từ máy khác'; Admin = 'yes' }
    'them-may-in-ip'   = @{ No = 6; Label = 'Thêm máy in mạng bằng địa chỉ IP'; Admin = 'yes' }
    'ket-noi-thu-muc'  = @{ No = 7; Label = 'Kết nối hoặc ngắt thư mục chia sẻ (ổ mạng)'; Admin = 'no' }
    'noi-bao-mat'      = @{ No = 8; Label = 'Nới bảo mật cho thiết bị cũ'; Admin = 'yes' }
    'hoan-tac'         = @{ No = 9; Label = 'Hoàn tác lần sửa trước'; Admin = 'yes' }
}

function Test-ModeOptions {
    # Kiểm tra giá trị nhập trước khi xin quyền Admin. Trả câu báo lỗi, hoặc '' khi hợp lệ.
    param([hashtable]$O)
    $h = ([string]$O.MayChu).Trim()
    if ($h -and -not (Split-UncPath $h) -and -not (Test-HostName $h.TrimStart('\'))) { return "Tên máy '$h' không hợp lệ (chỉ chữ, số, dấu chấm, gạch ngang)." }
    if ($O.DiaChi -and -not (Test-HostName ([string]$O.DiaChi).Trim())) { return "Địa chỉ '$($O.DiaChi)' không hợp lệ." }
    if ($O.DuongDan -and -not (Split-UncPath $O.DuongDan)) { return "Đường dẫn '$($O.DuongDan)' không đúng dạng \\tên-máy\thư-mục." }
    if ($O.ODia -and ([string]$O.ODia).Trim() -notmatch '^[A-Za-z]:?$') { return "Chữ ổ '$($O.ODia)' không hợp lệ (vd Z)." }
    if ($O.TenMayIn -and $O.TenMayIn -match '[\\,"]') { return 'Tên máy in không được có dấu \ , hoặc ".' }
    if ($O.TenChiaSe -and $O.TenChiaSe -match '[\\/:*?"<>|]') { return 'Tên chia sẻ có ký tự không hợp lệ.' }
    if ($O.TaiKhoan -and $O.TaiKhoan -match '["/\[\]:;|=,+*?<>]') { return 'Tài khoản có ký tự không hợp lệ.' }
    if ($O.Kieu -and $O.Kieu -notin 'tu-dong', 'ipp', 'raw') { return "Kiểu kết nối '$($O.Kieu)' không hợp lệ (tu-dong, ipp, raw)." }
    if ($O.Muc -and -not $script:SecurityOptions.Contains([string]$O.Muc)) { return "Mục '$($O.Muc)' không hợp lệ." }
    if ($O.NhatKy -and $O.NhatKy -notmatch '^HoanTac_[\w-]+(\.json)?$') { return "Tên nhật ký '$($O.NhatKy)' không hợp lệ." }
    return ''
}

function Invoke-Mode {
    param([string]$Id, [hashtable]$O)
    $dry = [bool]$O.ChayThu
    switch ($Id) {
        'chan-doan' { return (Invoke-ChanDoan -MayChu ([string]$O.MayChu)) }
        'sua-hang-doi' { return (Invoke-SuaHangDoi -DryRun:$dry) }
        'xoa-may-in-trung' { return (Invoke-XoaMayInTrung -DryRun:$dry) }
        'bat-chia-se' { return (Invoke-BatChiaSe -DryRun:$dry) }
        'ket-noi-may-in' { return (Invoke-KetNoiMayIn -MayChu ([string]$O.MayChu) -TenChiaSe ([string]$O.TenChiaSe) -ChoMoiNguoi:([bool]$O.ChoMoiNguoi) -DryRun:$dry) }
        'them-may-in-ip' { return (Invoke-ThemMayInIp -DiaChi ([string]$O.DiaChi) -TenMayIn ([string]$O.TenMayIn) -Kieu $(if ($O.Kieu) { [string]$O.Kieu } else { 'tu-dong' }) -DryRun:$dry) }
        'ket-noi-thu-muc' { return (Invoke-KetNoiThuMuc -DuongDan ([string]$O.DuongDan) -ODia ([string]$O.ODia) -TaiKhoan ([string]$O.TaiKhoan) -Ngat:([bool]$O.Ngat) -DryRun:$dry) }
        'noi-bao-mat' { return (Invoke-NoiBaoMat -Muc ([string]$O.Muc) -DryRun:$dry) }
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
    # Hỏi các giá trị một chế độ cần. Trả $null khi người dùng bỏ trống ô bắt buộc.
    param([string]$Id)
    $o = @{}
    switch ($Id) {
        'chan-doan' { $o.MayChu = Read-Text 'Tên hoặc IP một máy cần kiểm tra thêm (máy chia sẻ, máy in, NAS); Enter để bỏ qua' }
        'ket-noi-may-in' {
            $o.MayChu = Read-Text 'Tên hoặc IP máy đang chia sẻ máy in (vd PC-KETOAN)'
            if (-not $o.MayChu) { return $null }
        }
        'them-may-in-ip' {
            $o.DiaChi = Read-Text 'Địa chỉ IP của máy in (vd 192.168.1.50)'
            if (-not $o.DiaChi) { return $null }
            $o.TenMayIn = Read-Text 'Đặt tên cho máy in (Enter để tự đặt)'
        }
        'ket-noi-thu-muc' {
            if ((Read-Number '1 = kết nối thư mục, 2 = ngắt ổ mạng (Enter = 1)' 1 2 1) -eq 2) { $o.Ngat = $true }
            else {
                $o.DuongDan = Read-Text 'Đường dẫn thư mục chia sẻ (vd \\PC-KETOAN\TaiLieu)'
                if (-not $o.DuongDan) { return $null }
                $o.ODia = Read-Text 'Chữ ổ đĩa (Enter để tự chọn)'
                $o.TaiKhoan = Read-Text 'Tài khoản trên máy chia sẻ, vd PC-KETOAN\ketoan (Enter nếu không cần hoặc đã lưu)'
            }
        }
    }
    $err = Test-ModeOptions $o
    if ($err) { Write-Bad $err; return $null }
    return $o
}

function Show-Menu {
    while ($true) {
        try { $Host.UI.RawUI.WindowTitle = 'Máy in mạng LAN' } catch { }
        Write-Host ''
        Write-Host '  MÁY IN MẠNG LAN VÀ THƯ MỤC CHIA SẺ' -ForegroundColor Cyan
        Write-Host '  Chẩn đoán trước, sửa sau. Mọi thay đổi đều hỏi trước và hoàn tác được (mục 9).' -ForegroundColor Gray
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
        elseif (-not $admin -and $def.Admin -eq 'prefer') { $elevate = Read-YesNo 'Chạy bằng quyền Admin để xem đủ thông tin?' $true }
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
try { $Host.UI.RawUI.WindowTitle = 'Máy in mạng LAN' } catch { }
$opts = @{
    MayChu = $MayChu; TenChiaSe = $TenChiaSe; ChoMoiNguoi = [bool]$ChoMoiNguoi; DiaChi = $DiaChi; TenMayIn = $TenMayIn; Kieu = $Kieu
    DuongDan = $DuongDan; ODia = $ODia; TaiKhoan = $TaiKhoan; Ngat = [bool]$Ngat; Muc = $Muc; NhatKy = $NhatKy; ChayThu = [bool]$ChayThu
}

if (-not $Mode) {
    if ([Console]::IsInputRedirected) {
        Write-Host ('Cách dùng: MayInLan.ps1 -Mode <chế độ> [-ChayThu]. Chế độ: {0}.' -f (@($script:Modes.Keys) -join ', '))
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
try { $Host.UI.RawUI.WindowTitle = 'Máy in mạng LAN - ' + $def.Label } catch { }
if ($def.Admin -eq 'yes' -and -not (Test-IsAdmin)) {
    if ($ChayThu) { Write-Info 'Chạy thử không có quyền Admin: vài thông tin có thể thiếu.' }
    else {
        Write-Info 'Chế độ này cần quyền Admin: Windows sẽ hỏi (UAC), chọn "Có".'
        exit (Invoke-Elevated $Mode $opts)
    }
}
$code = Invoke-ModeSafe $Mode $opts
Wait-Close
exit $code
