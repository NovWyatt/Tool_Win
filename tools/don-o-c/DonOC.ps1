<#
  Dọn ổ C an toàn: xem trước rồi mới dọn, chỉ xoá thứ Windows hay ứng dụng tự sinh lại.

  Không có -Mode: hiện menu (bấm đúp DON_O_C.bat). -Mode <chế độ>: chạy thẳng (Trạm Tool dùng cách này).
  Chế độ: kiem-tra (chỉ đọc), don-cua-toi (rác của bạn), don-he-thong (rác của Windows, Admin), don-winsxs (Admin).
  -SoNgay: chỉ xoá file tạm cũ hơn số ngày này (mặc định 7). -DumpLoi: don-he-thong xoá cả MEMORY.DMP, LiveKernelReports.
  -ChayThu: chỉ đo và in những gì sẽ dọn, không xoá. Báo cáo, nhật ký nằm trong ket_qua\.
  Không bao giờ xoá: thùng rác, Windows.old, Downloads, dữ liệu cá nhân, mật khẩu, lịch sử, cookie trình duyệt.
  Mã thoát: 0 xong, 1 lỗi, 2 thiếu điều kiện (thiếu quyền Admin, sai tài khoản), 3 làm được một phần, 1223 người dùng thôi.
#>
param(
    [string]$Mode = '',
    [ValidateRange(1, 365)][int]$SoNgay = 7,
    [switch]$DumpLoi,
    [switch]$ChayThu,
    [switch]$KhongDung        # không chờ Enter khi xong (chạy tự động)
)

$ErrorActionPreference = 'Stop'
$script:ToolDir = $PSScriptRoot
$script:MainScript = $PSCommandPath
$script:ToolVersion = '1.0'
. (Join-Path $PSScriptRoot 'lib\Chung.ps1')
. (Join-Path $PSScriptRoot 'lib\Muc.ps1')
. (Join-Path $PSScriptRoot 'lib\Don.ps1')
. (Join-Path $PSScriptRoot 'lib\KiemTra.ps1')
$script:NoPause = [bool]$KhongDung

# No: số trong menu. Admin: yes (cần), no (không cần). Log: tên đầu file nhật ký ('' = không ghi nhật ký).
$script:Modes = [ordered]@{
    'kiem-tra'     = @{ No = 1; Label = 'Xem ổ C đang đầy vì đâu (chỉ đọc)'; Admin = 'no'; Log = '' }
    'don-cua-toi'  = @{ No = 2; Label = 'Dọn rác của bạn (file tạm, bộ nhớ đệm trình duyệt)'; Admin = 'no'; Log = 'NhatKy_DonOC' }
    'don-he-thong' = @{ No = 3; Label = 'Dọn rác của Windows (file tạm, bản cập nhật đã cài)'; Admin = 'yes'; Log = 'NhatKy_DonOC' }
    'don-winsxs'   = @{ No = 4; Label = 'Dọn kho thành phần Windows (WinSxS)'; Admin = 'yes'; Log = 'NhatKy_DonOC' }
}

function Invoke-Mode {
    param([string]$Id, [hashtable]$O)
    $dry = [bool]$O.ChayThu
    switch ($Id) {
        'kiem-tra' { return (Invoke-KiemTra -SoNgay $O.SoNgay) }
        'don-cua-toi' { return (Invoke-DonCuaToi -SoNgay $O.SoNgay -DryRun:$dry) }
        'don-he-thong' { return (Invoke-DonHeThong -SoNgay $O.SoNgay -DumpLoi:([bool]$O.DumpLoi) -DryRun:$dry) }
        'don-winsxs' { return (Invoke-DonWinSxS -DryRun:$dry) }
    }
    return 1
}

function Invoke-ModeSafe {
    # Chạy một chế độ; lỗi không lường trước thì in ra và trả mã 1 thay vì đóng cửa sổ.
    # Dọn thật (không phải chạy thử): ghi nhật ký ket_qua\NhatKy_DonOC_<máy>_<thời gian>.txt kể cả khi lỗi.
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
        if ($log -and -not $O.ChayThu -and $code -ne 1223 -and $script:Report.Count) {
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
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $script:MainScript.Replace('"', '') + '"'), '-Mode', $Id, '-SoNgay', [string][int]$O.SoNgay)
    if ($O.DumpLoi) { $parts += '-DumpLoi' }
    if ($O.ChayThu) { $parts += '-ChayThu' }
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
    # Hỏi các giá trị một chế độ cần.
    param([string]$Id)
    $o = @{ SoNgay = 7 }
    if ($Id -in 'kiem-tra', 'don-cua-toi', 'don-he-thong') {
        $d = Read-Text 'Chỉ xoá file tạm cũ hơn bao nhiêu ngày (Enter = 7)' '7'
        $n = 0
        if (-not [int]::TryParse($d, [ref]$n) -or $n -lt 1 -or $n -gt 365) { Write-Bad 'Số ngày phải từ 1 đến 365.'; return $null }
        $o.SoNgay = $n
    }
    if ($Id -eq 'don-he-thong') { $o.DumpLoi = Read-YesNo 'Xoá cả bản ghi lỗi màn hình xanh (MEMORY.DMP, LiveKernelReports)?' $false }
    if ($Id -ne 'kiem-tra') { $o.ChayThu = Read-YesNo 'Chạy thử (chỉ xem sẽ dọn gì, không xoá)?' $false }
    return $o
}

function Show-Menu {
    while ($true) {
        try { $Host.UI.RawUI.WindowTitle = 'Dọn ổ C an toàn' } catch { }
        Write-Host ''
        Write-Host '  DỌN Ổ C AN TOÀN' -ForegroundColor Cyan
        Write-Host '  Xem trước rồi mới dọn. Chỉ xoá file tạm, bộ nhớ đệm; không đụng dữ liệu, thùng rác, mật khẩu.' -ForegroundColor Gray
        Write-Host ''
        foreach ($id in $script:Modes.Keys) {
            $m = $script:Modes[$id]
            Write-Host ('   {0}. {1}' -f $m.No, $m.Label)
        }
        Write-Host '   5. Mở Storage Sense (Windows tự dọn định kỳ)'
        Write-Host '   0. Thoát'
        Write-Host ''
        $c = Read-Text 'Chọn số'
        if ($c -eq '0') { return 0 }
        if ($c -eq '5') { Start-Process 'ms-settings:storagesense'; continue }
        $id = $null
        foreach ($k in $script:Modes.Keys) { if ([string]$script:Modes[$k].No -eq $c) { $id = $k } }
        if (-not $id) { continue }
        $o = Read-MenuOptions $id
        if ($null -eq $o) { continue }
        if ($script:Modes[$id].Admin -eq 'yes' -and -not (Test-IsAdmin)) {
            # Cửa sổ Admin tự dừng chờ Enter khi xong; menu này chờ nó đóng rồi hiện lại.
            Write-Info 'Windows sẽ hỏi quyền Admin, chọn "Có". Việc dọn chạy trong cửa sổ mới.'
            [void](Invoke-Elevated $id $o)
        } else {
            [void](Invoke-ModeSafe $id $o)
            Wait-Close 'Bấm Enter để về menu'
        }
    }
}

# ---------------------------------------------------------------- bắt đầu
try { $Host.UI.RawUI.WindowTitle = 'Dọn ổ C an toàn' } catch { }
$opts = @{ SoNgay = $SoNgay; DumpLoi = [bool]$DumpLoi; ChayThu = [bool]$ChayThu }

if (-not $Mode) {
    if ([Console]::IsInputRedirected) {
        Write-Host ('Cách dùng: DonOC.ps1 -Mode <chế độ> [-SoNgay 7] [-ChayThu]. Chế độ: {0}.' -f (@($script:Modes.Keys) -join ', '))
        exit 1
    }
    exit (Show-Menu)
}
if (-not $script:Modes.Contains($Mode)) {
    Write-Bad ('Không có chế độ "{0}". Các chế độ: {1}.' -f $Mode, (@($script:Modes.Keys) -join ', '))
    Wait-Close
    exit 1
}

$def = $script:Modes[$Mode]
try { $Host.UI.RawUI.WindowTitle = 'Dọn ổ C - ' + $def.Label } catch { }
if ($def.Admin -eq 'yes' -and -not (Test-IsAdmin) -and -not $ChayThu) {
    # Chạy thử thì không xin quyền: chỉ đo phần đọc được và in kế hoạch.
    Write-Info 'Chế độ này cần quyền Admin: Windows sẽ hỏi (UAC), chọn "Có".'
    exit (Invoke-Elevated $Mode $opts)
}
$code = Invoke-ModeSafe $Mode $opts
Wait-Close
exit $code
