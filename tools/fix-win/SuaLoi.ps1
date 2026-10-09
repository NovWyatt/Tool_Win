<#
  Sửa lỗi Windows: DISM, SFC, đặt lại mạng, tường lửa (tách riêng, có sao lưu), quét và hẹn sửa ổ đĩa, kiểm tra RAM,
  đặt lại Windows Update. Bản 1.0 (fix_win.bat) không kiểm tra quyền Admin, báo "hoàn tất" cả khi lệnh lỗi, đặt lại
  tường lửa lẫn trong "Reset Network" và có "Registry Cleanup" xoá khoá Explorer cần; bản này kiểm tra kết quả từng
  lệnh, đọc kết quả có cấu trúc (Repair-WindowsImage, CBS.log, Repair-Volume) thay vì chữ đã dịch.

  Không có -Mode: hiện menu (bấm đúp SUA_LOI_WINDOWS.bat). -Mode <chế độ>: chạy thẳng (Trạm Tool dùng cách này).
  Chế độ: dism-quet, dism-sua, sfc, dism-sfc, mang, tuong-lua, tuong-lua-khoi-phuc, o-dia-quet, o-dia-sua, ram,
  windows-update. -ODia: chữ ổ cho o-dia-* (mặc định ổ Windows). -TepSaoLuu: file .wfw cho tuong-lua-khoi-phuc.
  -ChayThu: chỉ in việc sẽ làm, không đổi máy. -KhongDung: không chờ Enter khi xong.
  Mã thoát: 0 xong, 1 lỗi, 2 thiếu điều kiện (quyền Admin, chưa đồng ý), 3 làm được một phần.
#>
param(
    [string]$Mode = '',
    [string]$ODia = '',
    [string]$TepSaoLuu = '',
    [switch]$ChayThu,
    [switch]$KhongDung,
    [switch]$DaNangQuyen   # đánh dấu cửa sổ đã mở lại bằng quyền Admin, để không hỏi UAC lần nữa
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:WinDir = $env:SystemRoot
$script:OutDir = Join-Path $PSScriptRoot 'ket_qua'
$script:CbsLog = Join-Path $env:SystemRoot 'Logs\CBS\CBS.log'
$script:WuServices = @('wuauserv', 'bits', 'cryptsvc', 'msiserver')
$script:Modes = [ordered]@{
    'dism-quet'           = @{ No = 1; Label = 'Kiểm tra ảnh Windows (DISM ScanHealth, chỉ đọc)' }
    'dism-sua'            = @{ No = 2; Label = 'Sửa ảnh Windows (DISM RestoreHealth)' }
    'sfc'                 = @{ No = 3; Label = 'Kiểm tra và sửa file hệ thống (SFC)' }
    'dism-sfc'            = @{ No = 4; Label = 'Sửa ảnh Windows rồi file hệ thống (DISM rồi SFC, nên dùng)' }
    'mang'                = @{ No = 5; Label = 'Đặt lại mạng (DNS, Winsock, TCP/IP)' }
    'tuong-lua'           = @{ No = 6; Label = 'Đặt lại tường lửa Windows (sao lưu trước, hỏi lại)' }
    'tuong-lua-khoi-phuc' = @{ No = 7; Label = 'Khôi phục tường lửa từ bản sao lưu' }
    'o-dia-quet'          = @{ No = 8; Label = 'Quét lỗi ổ đĩa (không sửa, không cần khởi động lại)' }
    'o-dia-sua'           = @{ No = 9; Label = 'Sửa lỗi ổ đĩa (chkdsk /f, ổ Windows thì hẹn khi khởi động lại)' }
    'ram'                 = @{ No = 10; Label = 'Kiểm tra RAM (Windows Memory Diagnostic)' }
    'windows-update'      = @{ No = 11; Label = 'Đặt lại Windows Update' }
}

# ---------------------------------------------------------------- in ra, hỏi
function Write-Head { param([string]$Text) Write-Host ''; Write-Host ("== $Text " + ('=' * [Math]::Max(3, 68 - $Text.Length))) -ForegroundColor Cyan }
function Write-Line { param([string]$Text) Write-Host "  $Text" }
function Write-Sub { param([string]$Text) Write-Host "       $Text" -ForegroundColor Gray }
function Write-Ok { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Write-Bad { param([string]$Text) Write-Host "  [X]  $Text" -ForegroundColor Red }
function Write-Info { param([string]$Text) Write-Host "  [i]  $Text" -ForegroundColor Gray }
function Write-Plan { param([string]$Text) Write-Host "   ->  $Text" -ForegroundColor White }

function Read-Text {
    param([string]$Prompt, [string]$Default = '')
    if ([Console]::IsInputRedirected) { return $Default }
    $a = ([string](Read-Host "  $Prompt")).Trim()
    if (-not $a) { return $Default }
    return $a
}

function Read-YesNo {
    # Không có bàn phím (chạy tự động) thì trả mặc định thay vì treo.
    param([string]$Question, [bool]$Default = $false)
    if ([Console]::IsInputRedirected) { return $Default }
    $hint = if ($Default) { '[C/k]' } else { '[c/K]' }
    while ($true) {
        $a = ([string](Read-Host "  $Question $hint")).Trim().ToLowerInvariant()
        if (-not $a) { return $Default }
        if ($a -in 'c', 'co', 'có', 'y', 'yes') { return $true }
        if ($a -in 'k', 'khong', 'không', 'n', 'no') { return $false }
        Write-Host '  Gõ C (có) hoặc K (không).' -ForegroundColor Yellow
    }
}

function Wait-Close {
    param([string]$Text = 'Bấm Enter để đóng cửa sổ')
    if ($KhongDung -or [Console]::IsInputRedirected) { return }
    Write-Host ''
    [void](Read-Host "  $Text")
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-Err {
    param($Err)
    $e = $Err.Exception
    $hr = if ($e.HResult) { ' (0x{0:X8})' -f $e.HResult } else { '' }
    return ($e.Message.Trim() + $hr)
}

function Get-Stamp { return (Get-Date).ToString('yyyyMMdd_HHmmss') }

function Get-SysExe {
    # PowerShell 32 bit trên Windows 64 bit bị chuyển System32 sang SysWOW64 (sfc bản 32 bit không chạy được).
    param([string]$Name)
    $native = Join-Path $script:WinDir "Sysnative\$Name"
    if (Test-Path -LiteralPath $native) { return $native }
    return (Join-Path $script:WinDir "System32\$Name")
}

function Invoke-Native {
    # Chạy lệnh, lấy mã thoát và chữ in ra (in lại cho người dùng xem nếu -Show).
    param([string]$Exe, [string[]]$Arguments, [switch]$Show)
    $ErrorActionPreference = 'Continue'
    $out = & (Get-SysExe $Exe) @Arguments 2>&1
    $code = $LASTEXITCODE
    $lines = @($out | ForEach-Object { ([string]$_).TrimEnd() } | Where-Object { $_ })
    if ($Show) { foreach ($l in $lines) { Write-Sub $l } }
    return [pscustomobject]@{ Code = $code; Output = ($lines -join ' ') }
}

function Invoke-Visible {
    # Lệnh chạy lâu, in tiến độ thẳng ra cửa sổ (sfc ghi UTF-16, bắt lại sẽ vỡ chữ). Trả mã thoát.
    param([string]$Exe, [string]$ArgumentLine)
    $p = Start-Process -FilePath $Exe -ArgumentList $ArgumentLine -NoNewWindow -Wait -PassThru
    return [int]$p.ExitCode
}

function Confirm-Change {
    # Chung cho mọi chế độ đổi máy: chạy thử thì dừng, menu thì hỏi lại.
    param([switch]$DryRun, [switch]$Ask, [string]$Question = 'Làm các việc trên?')
    if ($DryRun) { Write-Info 'Chạy thử: không đổi gì.'; return $false }
    if ($Ask -and -not (Read-YesNo $Question $false)) { Write-Info 'Đã huỷ, chưa đổi gì.'; return $false }
    return $true
}

function Get-ResultCode {
    param([int]$Done, [int]$Fail)
    if ($Fail -and $Done) { Write-Warn 'Làm được một phần, xem các dòng [X] ở trên.'; return 3 }
    if ($Fail) { return 1 }
    return 0
}

# ---------------------------------------------------------------- DISM, SFC
function Invoke-DismScan {
    try { $r = Repair-WindowsImage -Online -ScanHealth -ErrorAction Stop; return [pscustomobject]@{ Ok = $true; State = [string]$r.ImageHealthState; Message = ''; HResult = 0 } }
    catch { return [pscustomobject]@{ Ok = $false; State = ''; Message = (Format-Err $_); HResult = $_.Exception.HResult } }
}

function Invoke-DismRestore {
    try { $r = Repair-WindowsImage -Online -RestoreHealth -ErrorAction Stop; return [pscustomobject]@{ Ok = $true; State = [string]$r.ImageHealthState; Message = ''; HResult = 0 } }
    catch { return [pscustomobject]@{ Ok = $false; State = ''; Message = (Format-Err $_); HResult = $_.Exception.HResult } }
}

function Write-DismHint {
    param([int]$HResult)
    $h = '0x{0:X8}' -f $HResult
    if ($h -in '0x800F081F', '0x800F0906', '0x800F0907', '0x800F0950') {
        Write-Sub 'DISM không lấy được file sửa từ Windows Update (mất mạng, WSUS hoặc chính sách chặn).'
        Write-Sub 'Thử lại khi có mạng, hoặc mở file ISO cùng phiên bản Windows rồi chạy:'
        Write-Sub 'DISM /Online /Cleanup-Image /RestoreHealth /Source:wim:<ổ ISO>:\sources\install.wim:1 /LimitAccess'
    } elseif ($h -eq '0x800F0915') {
        Write-Sub 'Không có gì để sửa: ảnh Windows không hỏng.'
    } else {
        Write-Sub "Chi tiết trong $script:WinDir\Logs\DISM\dism.log."
    }
}

function Invoke-DismQuet {
    param([switch]$DryRun)
    Write-Head $script:Modes['dism-quet'].Label
    Write-Line 'Chỉ đọc, không đổi máy. Thường mất 5-15 phút.'
    if ($DryRun) { Write-Plan 'Repair-WindowsImage -Online -ScanHealth'; Write-Info 'Chạy thử: không chạy.'; return 0 }
    $r = Invoke-DismScan
    if (-not $r.Ok) { Write-Bad "DISM không kiểm tra được: $($r.Message)"; Write-DismHint $r.HResult; return 1 }
    switch ($r.State) {
        'Healthy' { Write-Ok 'Ảnh Windows không hỏng.' }
        'Repairable' { Write-Warn 'Ảnh Windows có chỗ hỏng, sửa được: chạy "Sửa ảnh Windows" rồi "SFC" (hoặc mục DISM rồi SFC).' }
        'NonRepairable' { Write-Bad 'Ảnh Windows hỏng nặng, DISM không sửa được: nên cài lại Windows giữ dữ liệu (Repair install bằng ISO cùng phiên bản).' }
        default { Write-Warn "DISM trả trạng thái lạ: $($r.State)" }
    }
    return 0
}

function Invoke-DismSua {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head $script:Modes['dism-sua'].Label
    Write-Line 'Tải file sửa từ Windows Update, thường mất 15-30 phút; cần mạng.'
    Write-Plan 'Repair-WindowsImage -Online -RestoreHealth (như DISM /Online /Cleanup-Image /RestoreHealth)'
    if (-not (Confirm-Change -DryRun:$DryRun -Ask:$Ask)) { return 0 }
    $r = Invoke-DismRestore
    if (-not $r.Ok) { Write-Bad "DISM chưa sửa được: $($r.Message)"; Write-DismHint $r.HResult; return 1 }
    if ($r.State -eq 'Healthy') { Write-Ok 'DISM xong: ảnh Windows không còn hỏng.'; return 0 }
    Write-Bad "DISM chạy xong nhưng ảnh Windows vẫn ở trạng thái $($r.State)."
    return 1
}

function Get-SfcResult {
    # Đọc dòng [SR] trong CBS.log (luôn tiếng Anh) ghi từ lúc $Since: SFC chạy hết chưa, sửa được bao nhiêu file.
    param([datetime]$Since)
    $res = [pscustomobject]@{ Read = $false; Finished = $false; Repaired = 0; Unrepaired = 0 }
    try {
        $fs = New-Object IO.FileStream($script:CbsLog, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $sr = New-Object IO.StreamReader($fs)
        try {
            while ($null -ne ($line = $sr.ReadLine())) {
                if ($line.IndexOf('[SR]') -lt 0) { continue }
                if ($line -notmatch '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),') { continue }
                $t = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
                if ($t -lt $Since) { continue }
                if ($line -match 'Verify complete') { $res.Finished = $true }
                elseif ($line -match 'Cannot repair member file') { $res.Unrepaired++ }
                elseif ($line -match 'Repairing corrupted file') { $res.Repaired++ }
            }
        } finally { $sr.Dispose() }
        $res.Read = $true
    } catch { }
    return $res
}

function Invoke-SfcMode {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head $script:Modes['sfc'].Label
    Write-Line 'Thường mất 10-20 phút. Nên chạy "Sửa ảnh Windows" (DISM) trước để SFC có file gốc tốt mà thay.'
    Write-Plan 'sfc /scannow'
    if (-not (Confirm-Change -DryRun:$DryRun -Ask:$Ask)) { return 0 }
    $since = (Get-Date).AddSeconds(-5)
    $code = Invoke-Visible (Get-SysExe 'sfc.exe') '/scannow'
    $r = Get-SfcResult $since
    Write-Line ''
    if ($r.Read -and $r.Finished) {
        if ($r.Unrepaired) {
            Write-Warn "SFC còn $($r.Unrepaired) file không sửa được. Chạy ""Sửa ảnh Windows"" (DISM) rồi chạy SFC lại."
            Write-Sub "Danh sách trong $script:CbsLog (dòng có 'Cannot repair member file')."
            return 3
        }
        if ($r.Repaired) { Write-Ok "SFC đã sửa $($r.Repaired) file hệ thống hỏng. Khởi động lại máy để dùng file mới." }
        else { Write-Ok 'SFC không thấy file hệ thống nào hỏng.' }
        return 0
    }
    if (-not $r.Read) { Write-Warn "Không đọc được $script:CbsLog để xác nhận kết quả SFC." }
    else { Write-Bad "SFC dừng giữa chừng (mã $code)." }
    Write-Sub 'Thường gặp: máy đang chờ khởi động lại để cài cập nhật (khởi động lại rồi chạy lại), hoặc dịch vụ Windows Modules Installer (TrustedInstaller) bị tắt.'
    if (-not $r.Read -and $code -eq 0) { return 0 }
    return 1
}

function Invoke-DismSfc {
    param([switch]$DryRun, [switch]$Ask)
    if ($Ask -and -not $DryRun) {
        Write-Head $script:Modes['dism-sfc'].Label
        Write-Line 'DISM sửa ảnh Windows (15-30 phút, cần mạng), rồi SFC sửa file hệ thống từ ảnh đó (10-20 phút).'
        if (-not (Read-YesNo 'Chạy cả hai?' $false)) { Write-Info 'Đã huỷ, chưa đổi gì.'; return 0 }
    }
    $a = Invoke-DismSua -DryRun:$DryRun
    $b = Invoke-SfcMode -DryRun:$DryRun
    if ($a -eq 0 -and $b -eq 0) { return 0 }
    if ($a -eq 1 -and $b -eq 1) { return 1 }
    return 3
}

# ---------------------------------------------------------------- mạng, tường lửa
function Get-ManualIpConfig {
    # Card mạng thật đang cắm có IP tĩnh hoặc DNS gõ tay: 'netsh int ip reset' xoá các thiết lập này.
    $rows = @()
    foreach ($ad in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $ipIf = Get-NetIPInterface -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $static = $ipIf -and [string]$ipIf.Dhcp -eq 'Disabled'
        $key = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($ad.InterfaceGuid)"
        $ns = [string](Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).NameServer
        if (-not $static -and -not $ns.Trim()) { continue }
        $ip = @(Get-NetIPAddress -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }) -join ', '
        $gw = @(Get-NetRoute -InterfaceIndex $ad.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | ForEach-Object { $_.NextHop }) -join ', '
        $rows += [pscustomobject]@{ Card = $ad.Name; Static = [bool]$static; Ip = $ip; Gateway = $gw; Dns = ($ns -replace '[ ,]+', ', ').Trim(', ') }
    }
    return , $rows
}

function Save-Text {
    param([string]$Name, [string[]]$Lines)
    if (-not (Test-Path -LiteralPath $script:OutDir)) { New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null }
    $path = Join-Path $script:OutDir $Name
    [IO.File]::WriteAllLines($path, $Lines, (New-Object Text.UTF8Encoding $true))
    return $path
}

function Invoke-Mang {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head $script:Modes['mang'].Label
    Write-Line 'Dùng khi vào được Wi-Fi/mạng dây mà không vào được web, DNS lỗi, sau khi gỡ VPN hay phần mềm diệt virus.'
    Write-Line 'Không đụng tường lửa (đặt lại tường lửa là mục riêng).'
    $manual = Get-ManualIpConfig
    if ($manual.Count) {
        Write-Line ''
        Write-Warn 'Card mạng sau đang đặt tay; đặt lại TCP/IP sẽ xoá, phải gõ lại sau khi khởi động lại:'
        foreach ($m in $manual) { Write-Sub ('{0}: {1}IP {2}, cổng {3}, DNS {4}' -f $m.Card, $(if ($m.Static) { 'tĩnh, ' } else { 'DHCP, ' }), $m.Ip, $m.Gateway, $(if ($m.Dns) { $m.Dns } else { 'tự động' })) }
    }
    Write-Line ''
    Write-Line 'Sẽ làm:'
    if ($manual.Count) { Write-Plan 'Ghi thiết lập IP, DNS đặt tay ở trên ra ket_qua\Mang_<tên máy>_<thời gian>.txt' }
    Write-Plan 'ipconfig /flushdns'
    Write-Plan 'netsh winsock reset'
    Write-Plan 'netsh int ip reset'
    if ($DryRun) { Write-Info 'Chạy thử: không đổi gì.'; return 0 }
    if ($manual.Count) {
        if (-not (Read-YesNo 'Vẫn đặt lại (sẽ phải gõ lại IP/DNS ở trên)?' $false)) { Write-Info 'Chưa đổi gì.'; return 2 }
    } elseif ($Ask -and -not (Read-YesNo 'Làm các việc trên?' $false)) { Write-Info 'Đã huỷ, chưa đổi gì.'; return 0 }

    if ($manual.Count) {
        $lines = @("Thiết lập mạng đặt tay trước khi đặt lại TCP/IP, máy $env:COMPUTERNAME, $(Get-Date -Format 'dd/MM/yyyy HH:mm')", '')
        foreach ($m in $manual) { $lines += ('{0}: {1} IP {2}; cổng {3}; DNS {4}' -f $m.Card, $(if ($m.Static) { 'tĩnh' } else { 'DHCP' }), $m.Ip, $m.Gateway, $m.Dns) }
        try { $p = Save-Text ("Mang_{0}_{1}.txt" -f $env:COMPUTERNAME, (Get-Stamp)) $lines; Write-Ok "Đã ghi thiết lập cũ: $p" }
        catch { Write-Bad ('Không ghi được thiết lập cũ nên chưa đổi gì: {0}' -f $_.Exception.Message.Trim()); return 1 }
    }
    $done = 0; $fail = 0
    foreach ($step in @(@('ipconfig.exe', @('/flushdns')), @('netsh.exe', @('winsock', 'reset')), @('netsh.exe', @('int', 'ip', 'reset')))) {
        $label = ($step[0] -replace '\.exe$', '') + ' ' + ($step[1] -join ' ')
        $r = Invoke-Native $step[0] $step[1]
        if ($r.Code -eq 0) { Write-Ok $label; $done++ }
        else { Write-Bad ('{0}: mã {1}. {2}' -f $label, $r.Code, $r.Output); $fail++ }
    }
    Write-Line ''
    $code = Get-ResultCode $done $fail
    if ($done) { Write-Warn 'Khởi động lại máy để thiết lập mạng mới có hiệu lực.' }
    return $code
}

function Get-CustomFirewallRuleCount {
    # Luật không thuộc nhóm nào của Windows: thường do phần mềm hoặc người dùng thêm.
    try { return @(Get-NetFirewallRule -PolicyStore PersistentStore -ErrorAction Stop | Where-Object { -not $_.Group }).Count }
    catch { return -1 }
}

function Invoke-TuongLua {
    param([switch]$DryRun)
    Write-Head $script:Modes['tuong-lua'].Label
    Write-Line 'Trả tường lửa Windows về mặc định: XOÁ mọi luật tự thêm (VPN, phần mềm chấm công, SQL Server, chia sẻ'
    Write-Line 'máy in, game...). Chỉ dùng khi tường lửa chặn sai mà không tìm ra luật nào.'
    $n = Get-CustomFirewallRuleCount
    if ($n -ge 0) { Write-Info "Đang có $n luật không thuộc nhóm của Windows (sẽ mất khi đặt lại)." }
    $file = Join-Path $script:OutDir ("TuongLua_{0}_{1}.wfw" -f $env:COMPUTERNAME, (Get-Stamp))
    Write-Line ''
    Write-Line 'Sẽ làm:'
    Write-Plan "netsh advfirewall export ""$file""   (sao lưu, khôi phục được bằng mục Khôi phục tường lửa)"
    Write-Plan 'netsh advfirewall reset'
    if ($DryRun) { Write-Info 'Chạy thử: không đổi gì.'; return 0 }

    if (-not (Test-Path -LiteralPath $script:OutDir)) { New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null }
    $r = Invoke-Native 'netsh.exe' @('advfirewall', 'export', $file)
    if ($r.Code -ne 0 -or -not (Test-Path -LiteralPath $file)) { Write-Bad ('Không sao lưu được tường lửa (mã {0}) nên chưa đặt lại. {1}' -f $r.Code, $r.Output); return 1 }
    Write-Ok "Đã sao lưu tường lửa: $file"
    if (-not (Read-YesNo 'Đặt lại tường lửa về mặc định? Các luật tự thêm sẽ mất (đã sao lưu ở trên)' $false)) { Write-Info 'Chưa đặt lại tường lửa.'; return 2 }
    $r = Invoke-Native 'netsh.exe' @('advfirewall', 'reset')
    if ($r.Code -ne 0) { Write-Bad ('netsh advfirewall reset: mã {0}. {1}' -f $r.Code, $r.Output); return 1 }
    Write-Ok 'Đã đặt lại tường lửa về mặc định.'
    Write-Info 'Phần mềm nào bị chặn thì cho phép lại khi Windows hỏi, hoặc dùng mục Khôi phục tường lửa.'
    return 0
}

function Invoke-TuongLuaKhoiPhuc {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head $script:Modes['tuong-lua-khoi-phuc'].Label
    $file = $TepSaoLuu
    if (-not $file) {
        $f = Get-ChildItem -LiteralPath $script:OutDir -Filter 'TuongLua_*.wfw' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f) { $file = $f.FullName }
    }
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { Write-Bad 'Không thấy bản sao lưu tường lửa (.wfw) trong ket_qua; chọn file bằng -TepSaoLuu.'; return 2 }
    Write-Line "Bản sao lưu: $file ($((Get-Item -LiteralPath $file).LastWriteTime.ToString('dd/MM/yyyy HH:mm')))"
    Write-Line 'Toàn bộ luật tường lửa hiện tại sẽ được thay bằng luật trong bản sao lưu.'
    Write-Plan "netsh advfirewall import ""$file"""
    if (-not (Confirm-Change -DryRun:$DryRun -Ask:$Ask)) { return 0 }
    $r = Invoke-Native 'netsh.exe' @('advfirewall', 'import', $file)
    if ($r.Code -ne 0) { Write-Bad ('netsh advfirewall import: mã {0}. {1}' -f $r.Code, $r.Output); return 1 }
    Write-Ok 'Đã khôi phục tường lửa từ bản sao lưu.'
    return 0
}

# ---------------------------------------------------------------- ổ đĩa, RAM
function Get-TargetDrive {
    $d = ([string]$ODia).Trim().TrimEnd(':', '\').ToUpperInvariant()
    if (-not $d) { $d = $env:SystemDrive.TrimEnd(':') }
    return $d
}

function Get-DiskHealth {
    # Sức khoẻ ổ vật lý chứa ổ $Letter theo Windows (SMART tổng hợp).
    param([string]$Letter)
    try {
        $part = Get-Partition -DriveLetter $Letter -ErrorAction Stop
        $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.DeviceId -eq [string]$part.DiskNumber } | Select-Object -First 1
        if (-not $pd) { return [pscustomobject]@{ Known = $false; Healthy = $true; Text = 'không tìm thấy ổ vật lý' } }
        return [pscustomobject]@{ Known = $true; Healthy = ([string]$pd.HealthStatus -eq 'Healthy'); Text = ('{0} ({1}, sức khoẻ: {2})' -f $pd.FriendlyName, $pd.MediaType, $pd.HealthStatus) }
    } catch { return [pscustomobject]@{ Known = $false; Healthy = $true; Text = $_.Exception.Message.Trim() } }
}

function Invoke-VolumeScan {
    param([string]$Letter)
    try { $r = Repair-Volume -DriveLetter $Letter -Scan -ErrorAction Stop; return [pscustomobject]@{ Ok = $true; Result = [string]$r; Message = '' } }
    catch { return [pscustomobject]@{ Ok = $false; Result = ''; Message = (Format-Err $_) } }
}

function Test-ChkdskScheduled {
    # chkdsk /f trên ổ đang dùng ghi lịch 'autocheck autochk /p \??\C:' vào BootExecute.
    param([string]$Letter)
    $v = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name BootExecute -ErrorAction SilentlyContinue).BootExecute
    $pattern = 'autochk.*\\\?\?\\' + [regex]::Escape($Letter) + ':'
    return [bool](@($v) | Where-Object { [string]$_ -match $pattern })
}

function Write-DiskHealth {
    param($Health)
    if (-not $Health.Known) { Write-Info "Không đọc được sức khoẻ ổ vật lý: $($Health.Text)" }
    elseif ($Health.Healthy) { Write-Ok "Ổ vật lý: $($Health.Text)" }
    else { Write-Bad "Ổ vật lý: $($Health.Text)" }
}

function Invoke-ODiaQuet {
    param([switch]$DryRun)
    $d = Get-TargetDrive
    Write-Head "Quét lỗi ổ $d`: (không sửa)"
    $h = Get-DiskHealth $d
    Write-DiskHealth $h
    if ($DryRun) { Write-Plan "Repair-Volume -DriveLetter $d -Scan (như chkdsk $d`: /scan)"; Write-Info 'Chạy thử: không chạy.'; return 0 }
    $r = Invoke-VolumeScan $d
    if (-not $r.Ok) { Write-Bad "Không quét được ổ $d`: $($r.Message)"; return 1 }
    if ($r.Result -eq 'NoErrorsFound') { Write-Ok "Ổ $d`: không có lỗi hệ thống file." }
    else { Write-Warn "Ổ $d`: $($r.Result). Chạy ""Sửa lỗi ổ đĩa"" để sửa." }
    if (-not $h.Healthy) { Write-Warn 'Ổ vật lý báo không khoẻ: cứu dữ liệu trước (CheckWinFix, Cứu dữ liệu), rồi thay ổ.' }
    return 0
}

function Invoke-ODiaSua {
    param([switch]$DryRun, [switch]$Ask)
    $d = Get-TargetDrive
    $isSystem = ($d + ':') -ieq $env:SystemDrive
    Write-Head "Sửa lỗi ổ $d`: (chkdsk /f)"
    Write-Line 'Sửa lỗi hệ thống file. Không dùng /r (quét bề mặt hàng giờ): ổ hỏng bề mặt thì cứu dữ liệu và thay ổ.'
    $h = Get-DiskHealth $d
    Write-DiskHealth $h
    Write-Line ''
    Write-Line 'Sẽ làm:'
    if ($isSystem) { Write-Plan "chkdsk $d`: /f, trả lời Y để hẹn chạy ở lần khởi động lại tới (ổ Windows đang dùng)" }
    else { Write-Plan "chkdsk $d`: /f /x (tháo ổ ra khỏi chương trình đang mở file trên đó)" }
    if ($DryRun) { Write-Info 'Chạy thử: không đổi gì.'; return 0 }
    if (-not $h.Healthy) {
        Write-Warn 'Ổ vật lý báo không khoẻ: chkdsk có thể làm mất thêm dữ liệu. Nên cứu dữ liệu trước (CheckWinFix, Cứu dữ liệu).'
        if (-not (Read-YesNo 'Vẫn chạy chkdsk?' $false)) { Write-Info 'Chưa đổi gì.'; return 2 }
    } elseif ($Ask -and -not (Read-YesNo 'Làm việc trên?' $false)) { Write-Info 'Đã huỷ, chưa đổi gì.'; return 0 }

    if ($isSystem) {
        # cmd lấy từ Sysnative là bản 64 bit, tự tìm chkdsk trong System32 của nó.
        $code = Invoke-Visible (Get-SysExe 'cmd.exe') ("/c echo Y| chkdsk {0}: /f" -f $d)
        if (Test-ChkdskScheduled $d) { Write-Ok "Đã hẹn chkdsk cho ổ $d`: ở lần khởi động lại tới. Khởi động lại máy, đừng bấm phím khi màn hình kiểm tra ổ hiện."; return 0 }
        Write-Warn "chkdsk chạy xong (mã $code) nhưng chưa thấy lịch kiểm tra ổ $d`: trong BootExecute; khởi động lại và xem có màn hình kiểm tra ổ không."
        return 3
    }
    $code = Invoke-Visible (Get-SysExe 'chkdsk.exe') ("{0}: /f /x" -f $d)
    switch ($code) {
        0 { Write-Ok "chkdsk: ổ $d`: không có lỗi."; return 0 }
        1 { Write-Ok "chkdsk: đã sửa lỗi trên ổ $d`:."; return 0 }
        2 { Write-Ok "chkdsk: đã dọn ổ $d`:."; return 0 }
        default { Write-Bad "chkdsk không kiểm tra hoặc không sửa hết lỗi ổ $d`: (mã $code)."; return 1 }
    }
}

function Get-LastMemTest {
    try { return (Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } -MaxEvents 1 -ErrorAction Stop) }
    catch { return $null }
}

function Start-MemTest {
    try { Start-Process -FilePath (Get-SysExe 'mdsched.exe') | Out-Null; return $true }
    catch { Write-Bad "Không mở được Windows Memory Diagnostic: $($_.Exception.Message.Trim())"; return $false }
}

function Invoke-Ram {
    param([switch]$DryRun)
    Write-Head $script:Modes['ram'].Label
    $e = Get-LastMemTest
    if ($e) {
        $msg = (([string]$e.Message) -split "`r?`n")[0]
        $text = 'Lần kiểm tra trước ({0}): {1}' -f $e.TimeCreated.ToString('dd/MM/yyyy HH:mm'), $msg
        if ($e.Level -le 3 -and $e.Level -gt 0) { Write-Warn $text } else { Write-Info $text }
    } else { Write-Info 'Chưa thấy kết quả kiểm tra RAM nào trong nhật ký Windows.' }
    Write-Plan 'Mở Windows Memory Diagnostic (mdsched.exe): chọn khởi động lại ngay hoặc lần sau; máy kiểm tra RAM khoảng 10-20 phút rồi vào Windows, kết quả hiện ở góc màn hình và trong nhật ký.'
    if ($DryRun) { Write-Info 'Chạy thử: không mở.'; return 0 }
    if (Start-MemTest) { Write-Ok 'Đã mở Windows Memory Diagnostic; chọn trong cửa sổ đó. Chạy lại mục này sau khi kiểm tra để xem kết quả.'; return 0 }
    return 1
}

# ---------------------------------------------------------------- Windows Update
function Get-SvcRunning { param([string]$Name) $s = Get-Service -Name $Name -ErrorAction SilentlyContinue; return [bool]($s -and $s.Status -eq 'Running') }

function Stop-Svc {
    param([string]$Name)
    if (-not (Get-SvcRunning $Name)) { return $true }
    [void](Invoke-Native 'sc.exe' @('stop', $Name))
    try { (Get-Service -Name $Name).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30)); return $true } catch { return $false }
}

function Start-Svc {
    param([string]$Name)
    try { Start-Service -Name $Name -ErrorAction Stop; return $true } catch { return $false }
}

function Invoke-WindowsUpdate {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head $script:Modes['windows-update'].Label
    Write-Line 'Dùng khi Windows Update báo lỗi mãi, kẹt ở 0% hay tải lại hoài. Lịch sử cập nhật trong Settings sẽ trống.'
    $stamp = Get-Stamp
    $dirs = @(
        @{ Path = (Join-Path $script:WinDir 'SoftwareDistribution'); New = "SoftwareDistribution.old_$stamp" },
        @{ Path = (Join-Path $script:WinDir 'System32\catroot2'); New = "catroot2.old_$stamp" }
    )
    Write-Line ''
    Write-Line 'Sẽ làm:'
    Write-Plan ('Dừng dịch vụ {0}' -f ($script:WuServices -join ', '))
    foreach ($d in $dirs) { Write-Plan ('Đổi tên {0} thành {1} (giữ lại để quay về nếu cần)' -f $d.Path, $d.New) }
    Write-Plan 'Chạy lại các dịch vụ đã chạy trước đó'
    if (-not (Confirm-Change -DryRun:$DryRun -Ask:$Ask)) { return 0 }

    $wasRunning = @($script:WuServices | Where-Object { Get-SvcRunning $_ })
    $done = 0; $fail = 0
    try {
        $stopped = $true
        foreach ($s in $script:WuServices) {
            if (Stop-Svc $s) { continue }
            Write-Bad "Không dừng được dịch vụ $s."; $stopped = $false
        }
        if (-not $stopped) { Write-Bad 'Chưa đổi tên thư mục nào vì còn dịch vụ đang chạy.'; return 1 }
        Write-Ok 'Đã dừng các dịch vụ Windows Update.'
        foreach ($d in $dirs) {
            if (-not (Test-Path -LiteralPath $d.Path)) { Write-Info "Không có $($d.Path), bỏ qua."; continue }
            try { Rename-Item -LiteralPath $d.Path -NewName $d.New -ErrorAction Stop; Write-Ok "Đã đổi tên $($d.Path) thành $($d.New)."; $done++ }
            catch { Write-Bad ('Không đổi tên được {0}: {1}' -f $d.Path, $_.Exception.Message.Trim()); $fail++ }
        }
    } finally {
        foreach ($s in $wasRunning) {
            if (Get-SvcRunning $s) { continue }
            if (Start-Svc $s) { Write-Ok "Đã chạy lại dịch vụ $s." } else { Write-Warn "Chưa chạy lại được dịch vụ $s; Windows sẽ chạy khi cần hoặc sau khi khởi động lại." }
        }
    }
    Write-Line ''
    $code = Get-ResultCode $done $fail
    if ($done) { Write-Info 'Mở Settings > Windows Update > Check for updates. Chạy tốt rồi thì xoá các thư mục .old_ cho nhẹ ổ.' }
    return $code
}

# ---------------------------------------------------------------- menu, nâng quyền
function Invoke-Mode {
    param([string]$Id, [switch]$Ask)
    try {
        switch ($Id) {
            'dism-quet' { return (Invoke-DismQuet -DryRun:$ChayThu) }
            'dism-sua' { return (Invoke-DismSua -DryRun:$ChayThu -Ask:$Ask) }
            'sfc' { return (Invoke-SfcMode -DryRun:$ChayThu -Ask:$Ask) }
            'dism-sfc' { return (Invoke-DismSfc -DryRun:$ChayThu -Ask:$Ask) }
            'mang' { return (Invoke-Mang -DryRun:$ChayThu -Ask:$Ask) }
            'tuong-lua' { return (Invoke-TuongLua -DryRun:$ChayThu) }
            'tuong-lua-khoi-phuc' { return (Invoke-TuongLuaKhoiPhuc -DryRun:$ChayThu -Ask:$Ask) }
            'o-dia-quet' { return (Invoke-ODiaQuet -DryRun:$ChayThu) }
            'o-dia-sua' { return (Invoke-ODiaSua -DryRun:$ChayThu -Ask:$Ask) }
            'ram' { return (Invoke-Ram -DryRun:$ChayThu) }
            'windows-update' { return (Invoke-WindowsUpdate -DryRun:$ChayThu -Ask:$Ask) }
        }
    } catch {
        Write-Bad ('Lỗi không lường trước: {0}' -f $_.Exception.Message.Trim())
        return 1
    }
}

function Invoke-Elevated {
    # Mở lại chính script này bằng quyền Admin (Windows hỏi UAC), chờ xong, trả mã thoát. Chỉ một lần.
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-DaNangQuyen')
    if ($Mode) { $parts += @('-Mode', $Mode) }
    if ($ODia) { $parts += @('-ODia', $ODia) }
    if ($TepSaoLuu) { $parts += @('-TepSaoLuu', ('"' + $TepSaoLuu + '"')) }
    if ($KhongDung) { $parts += '-KhongDung' }
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

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '  SỬA LỖI WINDOWS' -ForegroundColor Cyan
        Write-Host '  Mỗi mục in việc sẽ làm và hỏi lại trước khi đổi máy.' -ForegroundColor Gray
        Write-Host ''
        foreach ($id in $script:Modes.Keys) { Write-Host ('  {0,3}. {1}' -f $script:Modes[$id].No, $script:Modes[$id].Label) }
        Write-Host '    0. Thoát'
        Write-Host ''
        Write-Host '  Dọn file tạm: dùng công cụ "Dọn ổ C an toàn" (xem trước rồi mới xoá).' -ForegroundColor Gray
        Write-Host ''
        $c = Read-Text 'Chọn số' '0'
        if ($c -eq '0') { return 0 }
        $id = $null
        foreach ($k in $script:Modes.Keys) { if ([string]$script:Modes[$k].No -eq $c) { $id = $k } }
        if (-not $id) { continue }
        [void](Invoke-Mode $id -Ask)
        Wait-Close 'Bấm Enter để về menu'
    }
}

# ---------------------------------------------------------------- bắt đầu
if ($env:TRAMTOOL_SUALOI_TEST) { return }   # bài thử nạp các hàm rồi tự gọi
try { $Host.UI.RawUI.WindowTitle = 'Sửa lỗi Windows' } catch { }
if ($Mode -and -not $script:Modes.Contains($Mode)) {
    Write-Bad ('Không có chế độ "{0}". Các chế độ: {1}.' -f $Mode, (@($script:Modes.Keys) -join ', '))
    Wait-Close
    exit 1
}
if (-not $ChayThu -and -not (Test-IsAdmin)) {
    if ($DaNangQuyen) { Write-Bad 'Đã mở lại mà vẫn chưa có quyền Admin.'; Wait-Close; exit 2 }
    Write-Info 'Sửa lỗi Windows cần quyền Admin: Windows sẽ hỏi (UAC), chọn "Có".'
    exit (Invoke-Elevated)
}
if (-not $Mode) {
    if ([Console]::IsInputRedirected) { Write-Host ('Cách dùng: SuaLoi.ps1 -Mode {0} [-ODia C] [-TepSaoLuu file.wfw] [-ChayThu]' -f (@($script:Modes.Keys) -join '|')); exit 1 }
    exit (Show-Menu)
}
$code = Invoke-Mode $Mode
Wait-Close
exit $code
