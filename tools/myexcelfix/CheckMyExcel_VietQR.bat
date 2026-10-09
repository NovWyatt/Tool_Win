<# :
@echo off
rem ==========================================================================
rem  MyExcel VietQR - script kiem tra loi theo profile Windows (chi DOC, khong sua)
rem  Cach dung: copy file nay sang may bi loi, DOUBLE-CLICK trong profile bi loi.
rem  KHONG "Run as administrator" bang tai khoan khac (se doc sai HKCU).
rem  Ma thoat: 0 kiem tra xong, 1 khong ghi duoc bao cao, 2 chay sai tai khoan.
rem  Phien ban: 2026.10.1
rem ==========================================================================
chcp 65001 >nul
title MyExcel VietQR - Kiem tra loi (2026.10.1)
set "MYX_SELF=%~f0"
set "MYX_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "MYX_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%MYX_PS%" -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:MYX_SELF,[Text.Encoding]::UTF8); iex $s"
set "MYX_RC=%ERRORLEVEL%"
echo.
if "%MYX_RC%"=="0" echo Da xong. Bao cao da duoc mo bang Notepad va luu trong C:\Users\Public\Documents\MyExcelCheck
if not defined MYX_NOPAUSE pause
exit /b %MYX_RC%
#>

# ============================================================================
#  MyExcel VietQR - chẩn đoán lỗi theo profile Windows (chỉ ĐỌC, không sửa gì)
# ============================================================================
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch {}
function Remove-Diacritics([string]$Text) {
    if (-not $Text) { return $Text }
    $t = $Text.Replace([char]0x0110, 'D').Replace([char]0x0111, 'd')
    $sb = New-Object Text.StringBuilder
    foreach ($c in $t.Normalize([Text.NormalizationForm]::FormD).ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
    }
    return $sb.ToString()
}
function Test-VietConsole {
    # Console có hiện được chữ có dấu không: ghi thử rồi đọc lại ô chữ trên màn hình
    if ($env:MYX_KHONGDAU -eq '1') { return $false }
    if ($env:MYX_KHONGDAU -eq '0') { return $true }
    try { if ([Console]::IsOutputRedirected) { return $true } } catch {}
    try {
        $ui = $Host.UI.RawUI
        $probe = [string]([char]0x0110) + [char]0x1EC7 + [char]0x1EEF + [char]0x0103
        $pos = $ui.CursorPosition
        Write-Host $probe -NoNewline
        $rect = New-Object Management.Automation.Host.Rectangle $pos.X, $pos.Y, ($pos.X + $probe.Length - 1), $pos.Y
        $buf = $ui.GetBufferContents($rect)
        $got = ''
        for ($i = 0; $i -le $buf.GetUpperBound(1); $i++) { $got += $buf[0, $i].Character }
        $ui.CursorPosition = $pos
        Write-Host (' ' * $probe.Length) -NoNewline
        $ui.CursorPosition = $pos
        return ($got -ceq $probe)
    } catch { return $true }
}
function Txt([string]$Text) { if ($script:NoDau) { return (Remove-Diacritics $Text) }; return $Text }
$script:NoDau = -not (Test-VietConsole)
$script:Version  = '2026.10.1'   # build.ps1 thay bằng version trong tool.json
$script:Report   = New-Object System.Collections.Generic.List[string]
$script:Findings = New-Object System.Collections.Generic.List[object]
$script:Snap     = [ordered]@{}
$script:Started  = Get-Date
$script:MyxRoots = New-Object System.Collections.ArrayList
$script:QrFiles  = New-Object System.Collections.ArrayList
$script:AddinEntries = New-Object System.Collections.ArrayList
$script:OfficeVers = @()
$script:ExcelDir = $null
$script:OfficeIs32 = $false
$script:IsElevated = $false
$script:IsAdminMember = $false
$script:TlCoversRoot = $false
$script:TlCoversQr = $false
$script:QrAddinCount = 0
$script:ActiveRoots = @()

function Out-Line([string]$Text = '', [string]$Color = 'Gray') {
    Write-Host (Txt $Text) -ForegroundColor $Color
    $script:Report.Add($Text)
}
function Section([string]$Title) {
    Out-Line ''
    Out-Line ('=' * 78) 'DarkCyan'
    Out-Line "  $Title" 'Cyan'
    Out-Line ('=' * 78) 'DarkCyan'
}
function Info([string]$Label, $Value) {
    $v = "$Value"
    if ($null -eq $Value -or $v -eq '') { $v = '(trống)' }
    Out-Line ('  {0,-36}: {1}' -f $Label, $v)
}
function Ok([string]$Text)   { Out-Line "  [OK]  $Text" 'Green' }
function Note([string]$Text) { Out-Line "        $Text" 'DarkGray' }
function Add-Finding([string]$Code, [string]$Level, [string]$Title, [string]$Fix) {
    # Code: mã ổn định cho Trạm Tool (không đổi khi sửa câu chữ; cùng một nguyên nhân có thể ở mức khác nhau)
    # Level: LOI (nhiều khả năng là nguyên nhân) | CANHBAO (có thể) | THONGTIN
    $script:Findings.Add([pscustomobject]@{ Code = $Code; Level = $Level; Title = $Title; Fix = $Fix; Idx = $script:Findings.Count })
    switch ($Level) {
        'LOI'     { Out-Line "  [LỖI] $Title" 'Red' }
        'CANHBAO' { Out-Line "  [!]   $Title" 'Yellow' }
        default   { Out-Line "  [i]   $Title" 'DarkYellow' }
    }
}
function Snap([string]$Key, $Value) {
    if ($null -eq $Value) { $Value = '' }
    $script:Snap[$Key] = [string]$Value
}
function Get-RegValue([string]$Path, [string]$Name) {
    try {
        $k = Get-Item -LiteralPath $Path -ErrorAction Stop
        return $k.GetValue($Name, $null)
    } catch { return $null }
}
function Get-RegValues([string]$Path) {
    $list = @()
    try {
        $k = Get-Item -LiteralPath $Path -ErrorAction Stop
        foreach ($n in $k.GetValueNames()) {
            $list += [pscustomobject]@{ Name = $n; Value = $k.GetValue($n, $null); Kind = [string]$k.GetValueKind($n) }
        }
    } catch {}
    return $list
}
function Format-RegData($Value) {
    if ($null -eq $Value) { return '' }
    if ($Value -is [byte[]]) { return ('(binary {0} byte)' -f $Value.Length) }
    if ($Value -is [array]) { return ($Value -join ' | ') }
    return [string]$Value
}
$script:AnsiEnc = [Text.Encoding]::Default
function Test-AnsiSafe([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return $true }
    return ($script:AnsiEnc.GetString($script:AnsiEnc.GetBytes($s)) -ceq $s)
}
function Hide-Digits([string]$s) {
    if ($null -eq $s) { return '' }
    $ev = [Text.RegularExpressions.MatchEvaluator] { param($m) ('*' * ($m.Value.Length - 4)) + $m.Value.Substring($m.Value.Length - 4) }
    return [regex]::Replace($s, '\d{7,}', $ev)
}
function Get-ZoneId([string]$File) {
    # $null = không bị chặn; số = ZoneId (3 = Internet)
    try {
        $z = Get-Content -LiteralPath $File -Stream 'Zone.Identifier' -ErrorAction Stop
        $line = $z | Where-Object { $_ -match '^ZoneId=' } | Select-Object -First 1
        if ($line) { return [int]($line -replace '^ZoneId=', '') }
        return -1
    } catch { return $null }
}
function Test-Writable([string]$Dir) {
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir -PathType Container)) { return $false }
    $p = Join-Path $Dir ('~myxcheck_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.tmp')
    try {
        [IO.File]::WriteAllText($p, 'x')
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        return $true
    } catch { return $false }
}
function Test-UnderPath([string]$Child, [string]$Parent) {
    if (-not $Child -or -not $Parent) { return $false }
    $c = ($Child -replace '/', '\').TrimEnd('\').ToLowerInvariant() + '\'
    $p = ($Parent -replace '/', '\').TrimEnd('\').ToLowerInvariant() + '\'
    return $c.StartsWith($p)
}
function Test-SamePath([string]$A, [string]$B) {
    if (-not $A -or -not $B) { return $false }
    return (($A -replace '/', '\').TrimEnd('\') -ieq ($B -replace '/', '\').TrimEnd('\'))
}
function Test-Related([string]$s) { return ($s -match '(?i)myexcel|qr.?code|vietqr|qrbank|mini.?tool') }
$script:TlLocs = @()
$script:TlAllDisabled = $false
function Get-MainOfficeVer {
    if ($script:OfficeVers -contains '16.0') { return '16.0' }
    if ($script:OfficeVers.Count -gt 0) { return $script:OfficeVers[-1] }
    return '16.0'
}
function Read-TrustedLocations {
    # Trusted Locations của Excel (user + policy), lưu vào $script:TlLocs để các mục sau dùng chung
    $ver = Get-MainOfficeVer
    $sec = "HKCU:\Software\Microsoft\Office\$ver\Excel\Security\Trusted Locations"
    $pol = "HKCU:\Software\Policies\Microsoft\Office\$ver\Excel\Security\Trusted Locations"
    $script:TlAllDisabled = ((Get-RegValue $sec 'AllLocationsDisabled') -eq 1) -or ((Get-RegValue $pol 'AllLocationsDisabled') -eq 1)
    $locs = @()
    foreach ($base in @($sec, $pol)) {
        foreach ($k in (Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
            $p = $k.GetValue('Path')
            if (-not $p) { continue }
            $locs += [pscustomobject]@{ Path = [Environment]::ExpandEnvironmentVariables([string]$p); Sub = ($k.GetValue('AllowSubfolders') -eq 1); Policy = ($base -eq $pol) }
        }
    }
    foreach ($t in @(if ($env:MYX_TEST_TL) { $env:MYX_TEST_TL -split ';' })) { if ($t) { $locs += [pscustomobject]@{ Path = $t; Sub = $true; Policy = $false } } }  # chỉ dùng khi test
    $script:TlLocs = $locs
}
function Test-TrustedDir([string]$Dir, [switch]$WithSubfolders) {
    # $true nếu macro trong $Dir (và cả thư mục con khi có -WithSubfolders) được Trusted Locations cho chạy
    if ($script:TlAllDisabled) { return $false }
    foreach ($l in $script:TlLocs) {
        if ((Test-UnderPath $Dir $l.Path) -and $l.Sub) { return $true }
        if (-not $WithSubfolders -and (Test-SamePath $Dir $l.Path)) { return $true }
    }
    return $false
}

# ----------------------------------------------------------------------------
Section '1. MÁY TÍNH & TÀI KHOẢN ĐANG CHẠY SCRIPT'
try {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent()
    $script:IsElevated = ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $script:IsAdminMember = [bool]((whoami /groups) -match 'S-1-5-32-544')
    Info 'Phiên bản công cụ' $script:Version
    Info 'Thời điểm chạy' ($script:Started.ToString('dd/MM/yyyy HH:mm:ss'))
    Info 'Tên máy' $env:COMPUTERNAME
    Info 'Tài khoản chạy script' $me.Name
    Info 'SID' $me.User.Value
    Info 'Thuộc nhóm Administrators' $script:IsAdminMember
    Info 'Đang chạy quyền admin (elevated)' $script:IsElevated
    try {
        $lu = Get-LocalUser -SID $me.User.Value -ErrorAction Stop
        Info 'Loại tài khoản' $lu.PrincipalSource
    } catch { Info 'Loại tài khoản' 'không xác định (domain/Azure AD?)' }
    Snap 'User.AdminMember' $script:IsAdminMember

    $sid = (Get-Process -Id $PID).SessionId
    $exp = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $sid } | Select-Object -First 1
    if ($exp) {
        $o = Invoke-CimMethod -InputObject $exp -MethodName GetOwner -ErrorAction SilentlyContinue
        if ($o -and $o.ReturnValue -eq 0) {
            $desk = "$($o.Domain)\$($o.User)"
            Info 'User đang đăng nhập màn hình' $desk
            if ($desk -ine $me.Name) {
                Add-Finding 'SAI_TAI_KHOAN' 'LOI' "Script đang chạy bằng '$($me.Name)' nhưng màn hình là của '$desk' => kết quả HKCU/AppData KHÔNG phải của profile bị lỗi" 'Chạy lại file .bat bằng cách double-click trong profile bị lỗi, không dùng Run as administrator bằng tài khoản khác.'
            }
        }
    }
    if ($env:USERPROFILE -match '\\TEMP(\.|$)') {
        Add-Finding 'PROFILE_TAM' 'LOI' "Windows đang dùng profile TẠM ($env:USERPROFILE) - mọi cài đặt sẽ mất khi đăng xuất" 'Profile gốc bị hỏng; cần sửa ProfileList trong registry hoặc chuyển dữ liệu sang profile mới.'
    }
} catch { Note "Lỗi khi đọc thông tin tài khoản: $($_.Exception.Message)" }

try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cv = Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    Info 'Windows' ("{0} {1} (build {2}.{3}, {4})" -f $os.Caption, $cv.GetValue('DisplayVersion'), $os.BuildNumber, $cv.GetValue('UBR'), $os.OSArchitecture)
    Info 'PowerShell' $PSVersionTable.PSVersion
    foreach ($d in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)) {
        $free = [math]::Round($d.FreeSpace / 1GB, 1)
        Info "Ổ đĩa $($d.DeviceID) còn trống" "$free GB / $([math]::Round($d.Size / 1GB, 0)) GB"
        if ($d.DeviceID -eq $env:SystemDrive -and $free -lt 3) {
            Add-Finding 'O_HE_THONG_DAY' 'CANHBAO' "Ổ $($d.DeviceID) chỉ còn $free GB trống" 'Dọn ổ C (Disk Cleanup, xóa TEMP) để Excel tạo được file tạm/ảnh QR.'
        }
    }
} catch { Note "Lỗi khi đọc thông tin Windows: $($_.Exception.Message)" }

# ----------------------------------------------------------------------------
Section '2. NGÔN NGỮ, ĐỊNH DẠNG SỐ & ĐƯỜNG DẪN CỦA PROFILE'
try {
    $cp = $script:AnsiEnc.CodePage
    $sysLoc = try { (Get-WinSystemLocale).Name } catch { '?' }
    Info 'Ngôn ngữ non-Unicode (system locale)' "$sysLoc (ANSI code page $cp)"
    $intl = 'HKCU:\Control Panel\International'
    $loc = Get-RegValue $intl 'LocaleName'
    $dec = Get-RegValue $intl 'sDecimal'
    $tho = Get-RegValue $intl 'sThousand'
    $lst = Get-RegValue $intl 'sList'
    $sd  = Get-RegValue $intl 'sShortDate'
    Info 'Định dạng vùng (Region format)' $loc
    Info 'Dấu thập phân / nhóm số / phân cách' ("'{0}'  /  '{1}'  /  '{2}'" -f $dec, $tho, $lst)
    Info 'Kiểu ngày ngắn' $sd
    Snap 'Region.LocaleName' $loc
    Snap 'Region.sDecimal' $dec
    Snap 'Region.sThousand' $tho
    Snap 'Region.sList' $lst
    Snap 'Region.sShortDate' $sd
    if ($dec -ne '.' -or $tho -ne ',') {
        Add-Finding 'DINH_DANG_SO' 'CANHBAO' ("Profile này dùng dấu thập phân '{0}' và nhóm số '{1}' (khác kiểu Mỹ '.' ','). Profile mới thường là mặc định => một số macro xử lý số tiền VietQR có thể lỗi" -f $dec, $tho) 'Thử: Settings > Time & language > Language & region > Regional format = English (United States), hoặc Control Panel > Region > Additional settings: Decimal = "."  Digit grouping = ","; sau đó mở lại Excel và thử tạo VietQR.'
    }
    if ($lst -ne ',' -and $lst -ne ';') {
        Add-Finding 'PHAN_CACH_DANH_SACH' 'CANHBAO' "Ký tự phân cách danh sách (List separator) lạ: '$lst'" 'Đặt lại List separator về "," (hoặc ";") trong Region > Additional settings.'
    }
} catch { Note "Lỗi khi đọc Region: $($_.Exception.Message)" }

try {
    $pathsToCheck = [ordered]@{
        'USERPROFILE'  = $env:USERPROFILE
        'TEMP'         = $env:TEMP
        'TMP'          = $env:TMP
        'APPDATA'      = $env:APPDATA
        'LOCALAPPDATA' = $env:LOCALAPPDATA
    }
    $badPath = @()
    foreach ($k in $pathsToCheck.Keys) {
        $v = $pathsToCheck[$k]
        $safe = Test-AnsiSafe $v
        $flag = if ($safe) { '' } else { '   <== có ký tự Unicode (VBA đọc sai)' }
        Info "%$k%" ("$v$flag")
        if (-not $safe) { $badPath += $k }
    }
    Snap 'Path.UnicodeVars' ($badPath -join ',')
    if ($badPath.Count -gt 0) {
        Add-Finding 'DUONG_DAN_UNICODE' 'LOI' ("Đường dẫn {0} chứa ký tự có dấu/Unicode mà code page {1} không biểu diễn được. VBA (MyExcel) dùng API ANSI nên không tạo/lưu được file ảnh QR tạm. Profile mới tên không dấu nên chạy được" -f ($badPath -join ', '), $script:AnsiEnc.CodePage) 'Cho riêng user này: tạo thư mục C:\Temp rồi chạy trong CMD:  setx TEMP C:\Temp  và  setx TMP C:\Temp  => đăng xuất/đăng nhập lại => thử VietQR. (Nếu chính USERPROFILE có dấu thì cách triệt để là dùng profile tên không dấu.)'
    }
    $userEnv = Get-RegValues 'HKCU:\Environment'
    foreach ($e in $userEnv) {
        if ($e.Name -match '^(TEMP|TMP)$') {
            $raw = (Get-Item 'HKCU:\Environment').GetValue($e.Name, $null, 'DoNotExpandEnvironmentNames')
            Info "HKCU\Environment\$($e.Name)" $raw
        }
    }
} catch { Note "Lỗi khi kiểm tra đường dẫn: $($_.Exception.Message)" }

# ----------------------------------------------------------------------------
Section '3. MICROSOFT EXCEL ĐÃ CÀI'
function Get-PeBitness([string]$File) {
    try {
        $fs = [IO.File]::Open($File, 'Open', 'Read', 'ReadWrite')
        $br = New-Object IO.BinaryReader($fs)
        $fs.Position = 0x3C; $pe = $br.ReadInt32()
        $fs.Position = $pe + 4; $m = $br.ReadUInt16()
        $fs.Close()
        switch ($m) { 0x8664 { return '64-bit' } 0x14c { return '32-bit' } 0xAA64 { return 'ARM64' } }
    } catch {}
    return 'không rõ'
}
try {
    $excel = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe' ''
    if (-not $excel -or -not (Test-Path -LiteralPath $excel)) {
        $excel = @(
            "$env:ProgramFiles\Microsoft Office\root\Office16\EXCEL.EXE",
            "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\EXCEL.EXE",
            "$env:ProgramFiles\Microsoft Office\Office16\EXCEL.EXE",
            "${env:ProgramFiles(x86)}\Microsoft Office\Office16\EXCEL.EXE",
            "$env:ProgramFiles\Microsoft Office\Office15\EXCEL.EXE",
            "${env:ProgramFiles(x86)}\Microsoft Office\Office15\EXCEL.EXE"
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    }
    if ($excel) {
        $script:ExcelDir = Split-Path $excel -Parent
        $bit = Get-PeBitness $excel
        $script:OfficeIs32 = ($bit -eq '32-bit')
        Info 'EXCEL.EXE' $excel
        Info 'Phiên bản / Kiến trúc' ("{0} / {1}" -f (Get-Item -LiteralPath $excel).VersionInfo.ProductVersion, $bit)
        Snap 'Office.ExcelVersion' (Get-Item -LiteralPath $excel).VersionInfo.ProductVersion
        Snap 'Office.Bitness' $bit
    } else {
        Add-Finding 'KHONG_CO_EXCEL' 'LOI' 'Không tìm thấy EXCEL.EXE' 'Kiểm tra lại bộ Office trên máy.'
    }
    $c2r = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (Test-Path $c2r) {
        Info 'Kiểu cài' 'Click-to-Run'
        Info 'Sản phẩm' (Get-RegValue $c2r 'ProductReleaseIds')
        Info 'Bản build Office' (Get-RegValue $c2r 'VersionToReport')
        $cdn = [string](Get-RegValue $c2r 'CDNBaseUrl')
        $chan = switch -Regex ($cdn) {
            '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' { 'Current Channel' }
            '55336b82-a18d-4dd6-b5f6-9e5095c314a6' { 'Monthly Enterprise' }
            '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' { 'Semi-Annual Enterprise' }
            default { $cdn }
        }
        Info 'Kênh cập nhật' $chan
    } else {
        foreach ($v in '16.0', '15.0', '14.0') {
            foreach ($base in 'HKLM:\SOFTWARE\Microsoft\Office', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office') {
                $ir = Get-RegValue "$base\$v\Common\InstallRoot" 'Path'
                if ($ir) { Info "Kiểu cài MSI (Office $v)" $ir }
            }
        }
    }
    $uninst = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $apps = Get-ItemProperty $uninst -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
    $offs = $apps | Where-Object { $_.DisplayName -match '(?i)^Microsoft (Office|365|Excel)' -and $_.DisplayName -notmatch '(?i)update|language|proofing|mui|tools|shared|click-to-run|\(KB' } |
        Sort-Object DisplayName -Unique
    foreach ($a in $offs) { Info 'Sản phẩm Office trong Programs' ("{0}  {1}" -f $a.DisplayName, $a.DisplayVersion) }
    if (@($offs).Count -gt 1) {
        Add-Finding 'NHIEU_BO_OFFICE' 'CANHBAO' 'Có nhiều bộ Office cùng cài trên máy' 'Nhiều phiên bản Office song song dễ làm add-in/đăng ký COM bị lẫn. Nên gỡ bộ không dùng.'
    }
    if (($apps | Where-Object { $_.DisplayName -match 'Office 2016|Excel 2016' }) -and -not (Test-Path $c2r)) {
        if (-not ($apps | Where-Object { $_.DisplayName -match 'KB4484305' })) {
            Add-Finding 'THIEU_KB4484305' 'CANHBAO' 'Office 2016 bản MSI chưa thấy bản vá KB4484305 (lỗi khởi động MyExcel do Windows Update)' 'Cài bản vá theo https://myexcel.vn/loi-khoi-dong-myexcel-do-window/ rồi khởi động lại máy.'
        }
    }
} catch { Note "Lỗi khi đọc thông tin Office: $($_.Exception.Message)" }

try {
    $xl = @(Get-CimInstance Win32_Process -Filter "Name='EXCEL.EXE'" -ErrorAction SilentlyContinue)
    Info 'Số tiến trình EXCEL.EXE đang chạy' $xl.Count
    foreach ($p in $xl) {
        Note ("PID {0} session {1}: {2}" -f $p.ProcessId, $p.SessionId, $p.CommandLine)
        if ($p.CommandLine -match '(?i)/safe') {
            Add-Finding 'EXCEL_SAFE_MODE' 'LOI' "Excel (PID $($p.ProcessId)) đang chạy ở chế độ /safe => add-in không được nạp" 'Đóng Excel, mở lại bình thường (không dùng /safe, không giữ Ctrl khi mở).'
        }
        if ($p.CommandLine -match '(?i)/automation|-embedding') {
            Add-Finding 'EXCEL_CHAY_AN' 'CANHBAO' "Có Excel chạy ẩn (PID $($p.ProcessId), /automation hoặc -Embedding)" 'Đóng hết Excel, mở Task Manager kết thúc mọi EXCEL.EXE còn sót rồi mới thử lại.'
        }
    }
    if ($xl.Count -gt 0) { Note 'Nên ĐÓNG Excel khi chạy script để kết quả chính xác nhất.' }
} catch {}

# Thu thập danh sách add-in Excel đăng ký trong HKCU (dùng cho mục 4 và 5)
function ConvertFrom-OpenValue([string]$Raw, [string]$LibDir) {
    # Giá trị OPEN dạng: /R "C:\MyExcel\MyExcel.xlam"  |  "D:\a b\x.xlam"  |  x.xlam (trong AddIns)  |  /A "ProgID"
    $isAuto = $Raw -match '^\s*/A\s'
    $p = ($Raw -replace '^\s*(/[A-Za-z]\s+)+', '').Trim().Trim('"')
    if (-not $isAuto -and $p -notmatch '\\') {
        $cand = @((Join-Path $env:APPDATA "Microsoft\AddIns\$p"))
        if ($LibDir) { $cand += (Join-Path $LibDir $p) }
        $hit = $cand | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        $p = if ($hit) { $hit } else { $cand[0] }
    }
    return [pscustomobject]@{ Path = $p; Automation = $isAuto }
}
try {
    $script:OfficeVers = @(Get-ChildItem 'HKCU:\Software\Microsoft\Office' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^\d+\.0$' -and (Test-Path (Join-Path $_.PSPath 'Excel')) } |
        ForEach-Object { $_.PSChildName })
    $libDir = if ($script:ExcelDir) { Join-Path $script:ExcelDir 'Library' } else { $null }
    foreach ($ver in $script:OfficeVers) {
        foreach ($v in (Get-RegValues "HKCU:\Software\Microsoft\Office\$ver\Excel\Options")) {
            if ($v.Name -notmatch '^OPEN\d*$') { continue }
            $parsed = ConvertFrom-OpenValue ([string]$v.Value) $libDir
            [void]$script:AddinEntries.Add([pscustomobject]@{ Ver = $ver; Source = 'OPEN'; Name = $v.Name; Raw = [string]$v.Value; Path = $parsed.Path; Automation = $parsed.Automation })
        }
        foreach ($v in (Get-RegValues "HKCU:\Software\Microsoft\Office\$ver\Excel\Add-in Manager")) {
            [void]$script:AddinEntries.Add([pscustomobject]@{ Ver = $ver; Source = 'Add-in Manager'; Name = $v.Name; Raw = $v.Name; Path = $v.Name; Automation = $false })
        }
    }
} catch { Note "Lỗi khi đọc danh sách add-in: $($_.Exception.Message)" }

# ----------------------------------------------------------------------------
Section '4. THƯ MỤC CÀI MYEXCEL, FILE QR CODE & TRẠNG THÁI BỊ CHẶN (Unblock)'
try {
    $cands = New-Object System.Collections.ArrayList
    foreach ($d in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)) {
        foreach ($p in "$($d.DeviceID)\MyExcel", "$($d.DeviceID)\MyExcelAddin") {
            if (Test-Path -LiteralPath $p -PathType Container) { [void]$cands.Add($p) }
        }
    }
    foreach ($a in $script:AddinEntries) {
        if ($a.Path -and $a.Path -match '(?i)^(.*?\\[^\\]*myexcel[^\\]*)\\') {
            $r = $Matches[1]
            if ((Test-Path -LiteralPath $r -PathType Container) -and -not ($cands -contains $r)) { [void]$cands.Add($r) }
        }
    }
    foreach ($x in @(if ($env:MYX_EXTRA_ROOT) { $env:MYX_EXTRA_ROOT -split ';' })) { if ($x -and (Test-Path -LiteralPath $x)) { [void]$cands.Add($x) } }  # chỉ dùng khi test
    foreach ($r in $cands) { if (-not ($script:MyxRoots -contains $r)) { [void]$script:MyxRoots.Add($r) } }
    Snap 'MyExcel.Roots' ($script:MyxRoots -join ' | ')
    Read-TrustedLocations
    # Bộ MyExcel mà profile này thật sự nạp (OPEN); chưa nạp bộ nào thì xét hết
    $script:ActiveRoots = @($script:MyxRoots | Where-Object { $r = $_; @($script:AddinEntries | Where-Object { $_.Source -eq 'OPEN' -and (Test-UnderPath $_.Path $r) }).Count -gt 0 })
    if ($script:ActiveRoots.Count -eq 0) { $script:ActiveRoots = @($script:MyxRoots) }

    $installs = @($script:MyxRoots | Where-Object { Get-ChildItem -LiteralPath $_ -Filter 'MyExcel*.xlam' -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1 })
    if ($installs.Count -gt 1) {
        $loaded = @($script:AddinEntries | Where-Object { $_.Source -eq 'OPEN' -and $_.Path -match '(?i)myexcel[^\\]*\.xlam$' } | ForEach-Object { $_.Path })
        $loadedTxt = if ($loaded.Count -gt 0) { $loaded -join ' ; ' } else { 'chưa nạp bộ nào' }
        $lv = if (@($loaded | Where-Object { -not (Test-UnderPath $_ 'C:\MyExcel') }).Count -gt 0) { 'LOI' } else { 'CANHBAO' }
        Add-Finding 'NHIEU_BO_MYEXCEL' $lv ("Máy có {0} bộ MyExcel ({1}); profile này đang nạp: {2}" -f $installs.Count, ($installs -join ', '), $loadedTxt) 'Chỉ dùng 1 bộ ở C:\MyExcel như hướng dẫn MyExcel. Chạy FixMyExcel_VietQR.bat trong profile này: tự chọn bộ chuẩn, hỏi trước khi cất bộ thừa, có sao lưu và file hoàn tác.'
    }

    if ($script:MyxRoots.Count -eq 0) {
        Add-Finding 'KHONG_CO_MYEXCEL' 'LOI' 'Không tìm thấy thư mục cài MyExcel (C:\MyExcel) và không có add-in MyExcel nào được đăng ký' 'Cài lại MyExcel theo https://myexcel.vn/download/ (giải nén, copy thư mục MyExcel vào ổ C:).'
    }
    if ($script:MyxRoots.Count -gt 0 -and -not ($script:MyxRoots | Where-Object { Test-SamePath $_ 'C:\MyExcel' })) {
        Add-Finding 'MYEXCEL_SAI_CHO' 'CANHBAO' ("MyExcel không nằm ở C:\MyExcel mà ở: {0}" -f ($script:MyxRoots -join ', ')) 'MyExcel khuyến nghị cài đúng C:\MyExcel, nếu không file tạo từ máy khác sẽ lỗi #NAME / lỗi nút bấm.'
    }

    $execExt = '(?i)\.(xlam|xla|xll|xlsm|xlsb|xls|xltm|dll|ocx|exe|tlb)$'
    foreach ($root in $script:MyxRoots) {
        Out-Line ''
        Out-Line "  >> Thư mục: $root" 'White'
        $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)
        $size = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 1)
        Info 'Số file / dung lượng' "$($files.Count) file / $size MB"
        $canWrite = Test-Writable $root
        Info 'User này ghi được vào thư mục' $canWrite
        Snap "MyExcel.Writable[$root]" $canWrite
        if (-not $canWrite) {
            Add-Finding 'THU_MUC_KHONG_GHI_DUOC' 'CANHBAO' "User này KHÔNG ghi được vào $root (nếu profile mới là tài khoản admin thì ghi được => khác biệt)" "Mở CMD bằng quyền Admin chạy:  icacls `"$root`" /grant *S-1-5-32-545:(OI)(CI)M /T  (cấp quyền Modify cho nhóm Users) rồi thử lại."
        }
        $blocked = @()
        $shown = 0
        foreach ($f in $files) {
            $zone = Get-ZoneId $f.FullName
            $isQr = $f.Name -match '(?i)qr'
            $isQrAddin = $isQr -and $f.Extension -match '(?i)^\.(xlam|xla|xll|dll)$'
            if ($isQr) { [void]$script:QrFiles.Add($f.FullName) }
            if ($isQrAddin) { $script:QrAddinCount++ }
            if ($null -ne $zone) { $blocked += $f }
            if ($isQrAddin -or ($f.Name -match $execExt -and $shown -lt 60)) {
                if (-not $isQrAddin) { $shown++ }
                $flag = if ($null -ne $zone) { "  <== BỊ CHẶN (ZoneId=$zone)" } else { '' }
                $ro = if ($f.IsReadOnly) { ' [ReadOnly]' } else { '' }
                $color = if ($null -ne $zone) { 'Red' } elseif ($isQrAddin) { 'White' } else { 'Gray' }
                Out-Line ('    {0}  {1,9:N0} KB  {2}{3}{4}' -f $f.LastWriteTime.ToString('dd/MM/yyyy'), ($f.Length / 1KB), $f.FullName.Substring($root.Length).TrimStart('\'), $ro, $flag) $color
            }
        }
        Info 'Số file đang bị Windows chặn (MOTW)' $blocked.Count
        Snap "MyExcel.BlockedCount[$root]" $blocked.Count
        $unblockCmd = "Get-ChildItem -LiteralPath '$root' -Recurse | Unblock-File"
        $blockedQr = @($blocked | Where-Object { $_.Name -match '(?i)qr' -and $_.Extension -match '(?i)^\.(xlam|xla|xll|dll)$' })
        $untrustedQr = @($blockedQr | Where-Object { -not (Test-TrustedDir $_.DirectoryName) })
        $isActive = @($script:ActiveRoots | Where-Object { Test-SamePath $_ $root }).Count -gt 0
        if ($untrustedQr.Count -gt 0) {
            $lv = if ($isActive) { 'LOI' } else { 'CANHBAO' }
            $note = if ($isActive) { '' } else { ' (bộ này profile không nạp)' }
            Add-Finding 'QR_BI_CHAN' $lv ("File QR Code trong {0} bị Windows chặn (Mark of the Web) và KHÔNG nằm trong Trusted Locations{1}: {2}" -f $root, $note, (($untrustedQr | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', ')) "Đúng lỗi MyExcel đã hướng dẫn: đóng Excel > chuột phải từng file QR Code > Properties > tích Unblock > OK. Hoặc mở PowerShell chạy:  $unblockCmd"
        } elseif ($blocked.Count -gt 0 -and (Test-TrustedDir $root -WithSubfolders)) {
            Add-Finding 'MOTW_DA_TIN_CAY' 'THONGTIN' ("{0} file trong {1} còn dấu chặn của Windows (MOTW) nhưng thư mục nằm trong Trusted Locations (có thư mục con) nên macro vẫn chạy - không phải nguyên nhân" -f $blocked.Count, $root) "Vẫn nên Unblock cho sạch: đóng Excel, mở PowerShell chạy:  $unblockCmd"
        } elseif ($blocked.Count -gt 0) {
            Add-Finding 'FILE_BI_CHAN' 'CANHBAO' "$($blocked.Count) file trong $root đang bị Windows chặn (MOTW) và thư mục chưa được tin cậy hết" "Đóng Excel, mở PowerShell chạy:  $unblockCmd  rồi thêm $root vào Trusted Locations (tích thư mục con)."
        }
        if (-not ($files | Where-Object { $_.Name -match '(?i)^myexcel.*\.xlam$' })) {
            Add-Finding 'THIEU_XLAM' 'LOI' "Không thấy file MyExcel*.xlam trong $root" 'File có thể bị phần mềm diệt virus xóa. Thêm thư mục MyExcel vào danh sách loại trừ rồi giải nén/copy lại bộ cài.'
        }
    }
    if ($script:MyxRoots.Count -gt 0 -and $script:QrAddinCount -eq 0) {
        Add-Finding 'THIEU_FILE_QR' 'LOI' 'Không thấy file nào tên QR Code trong thư mục MyExcel (Mini Tool)' 'Nhiều khả năng file QR Code đã bị antivirus xóa/cách ly. Kiểm tra lịch sử bảo vệ của Windows Security, thêm C:\MyExcel vào Exclusions, rồi copy lại thư mục MiniTool từ bộ cài.'
    }
    foreach ($q in $script:QrFiles) {
        $qd = Split-Path $q -Parent
        if (-not (Test-Writable $qd)) { Note "User này KHÔNG ghi được vào thư mục $qd" }
    }
    Snap 'MyExcel.QrFiles' (($script:QrFiles | ForEach-Object { Split-Path $_ -Leaf }) -join ' | ')
} catch { Note "Lỗi khi kiểm tra thư mục MyExcel: $($_.Exception.Message)" }

try {
    Out-Line ''
    Out-Line '  >> Tìm bản sao MyExcel / QR Code nằm lung tung trong profile (dễ bị nạp nhầm):' 'White'
    $dl = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' '{374DE290-123F-4565-9164-39C4925E467B}'
    if (-not $dl) { $dl = Join-Path $env:USERPROFILE 'Downloads' }
    $searchRoots = @(
        @{ P = [Environment]::GetFolderPath('Desktop'); D = 3 },
        @{ P = $dl; D = 3 },
        @{ P = [Environment]::GetFolderPath('MyDocuments'); D = 3 },
        @{ P = (Join-Path $env:APPDATA 'Microsoft\AddIns'); D = 1 },
        @{ P = (Join-Path $env:APPDATA 'Microsoft\Excel'); D = 2 },
        @{ P = (Join-Path $env:PUBLIC 'Desktop'); D = 2 }
    )
    $copies = @()
    foreach ($s in $searchRoots) {
        if (-not $s.P -or -not (Test-Path -LiteralPath $s.P)) { continue }
        $copies += Get-ChildItem -LiteralPath $s.P -Recurse -Depth $s.D -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)(myexcel|qr.?code|vietqr).*\.(xlam|xla|xll|xlsm|dll|zip|rar|7z)$' } |
            Where-Object { $f = $_.FullName; -not ($script:MyxRoots | Where-Object { Test-UnderPath $f $_ }) }
    }
    $copies = @($copies | Sort-Object FullName -Unique | Select-Object -First 40)
    if ($copies.Count -eq 0) { Ok 'Không thấy bản sao nào ngoài thư mục cài.' }
    foreach ($c in $copies) {
        $zone = Get-ZoneId $c.FullName
        $flag = if ($null -ne $zone) { "  (bị chặn ZoneId=$zone)" } else { '' }
        Out-Line ('    {0}  {1}{2}' -f $c.LastWriteTime.ToString('dd/MM/yyyy'), $c.FullName, $flag) 'Yellow'
    }
    $addinCopies = @($copies | Where-Object { $_.Extension -match '(?i)\.(xlam|xla|xll)$' })
    if ($addinCopies.Count -gt 0) {
        Add-Finding 'BAN_SAO_ADDIN' 'CANHBAO' ("Có {0} file add-in MyExcel/QR nằm ngoài thư mục cài (VD: {1})" -f $addinCopies.Count, $addinCopies[0].FullName) 'Nếu Excel đang nạp bản sao này (xem mục 5) thì bản sao thiếu các file đi kèm => chức năng QR lỗi. Gỡ tích bản sao trong Excel Add-ins, di chuyển file đó ra chỗ khác, rồi Browse lại đúng C:\MyExcel.'
    }
    Snap 'MyExcel.CopiesOutside' (($copies | ForEach-Object { $_.FullName }) -join ' | ')
} catch { Note "Lỗi khi tìm bản sao: $($_.Exception.Message)" }

# ----------------------------------------------------------------------------
Section '5. ADD-IN EXCEL CỦA PROFILE NÀY (HKCU) - bản nào đang được nạp?'
try {
    if ($script:OfficeVers.Count -eq 0) { Note 'Profile này chưa có cấu hình Excel trong HKCU (chưa mở Excel lần nào?).' }
    Info 'Các phiên bản Office có cấu hình' ($script:OfficeVers -join ', ')
    $openRelated = @()
    foreach ($a in $script:AddinEntries) {
        $exists = if ($a.Automation) { $true } else { Test-Path -LiteralPath $a.Path }
        $zone = if ($exists -and -not $a.Automation) { Get-ZoneId $a.Path } else { $null }
        $rel = Test-Related $a.Raw
        $tag = if ($a.Source -eq 'OPEN') { 'ĐANG BẬT ' } else { 'đang tắt ' }
        $flags = @()
        if (-not $exists) { $flags += 'FILE KHÔNG TỒN TẠI' }
        if ($null -ne $zone) { $flags += "bị chặn ZoneId=$zone" }
        $color = if ($flags.Count -gt 0 -and $rel) { 'Red' } elseif ($rel) { 'White' } else { 'Gray' }
        Out-Line ('    [{0}] {1} {2,-8} {3} {4}' -f $a.Ver, $tag, $a.Name, $a.Raw, ($flags -join ', ')) $color
        if ($a.Source -eq 'OPEN' -and $rel) { $openRelated += $a }
        if (-not $exists -and $a.Source -eq 'OPEN') {
            $lv = if ($rel) { 'LOI' } else { 'CANHBAO' }
            Add-Finding 'ADDIN_MAT_FILE' $lv "Excel đang cố nạp add-in không còn tồn tại: $($a.Raw)" 'Excel > File > Options > Add-ins > Manage: Excel Add-ins > Go > bỏ tích mục đó (Excel sẽ hỏi xóa khỏi danh sách => Yes).'
        }
    }
    Snap 'AddIns.OPEN' ((@($script:AddinEntries | Where-Object Source -eq 'OPEN') | ForEach-Object { $_.Raw }) -join ' | ')
    Snap 'AddIns.Manager' ((@($script:AddinEntries | Where-Object Source -ne 'OPEN') | ForEach-Object { $_.Raw }) -join ' | ')

    $main = @($openRelated | Where-Object { $_.Path -match '(?i)myexcel[^\\]*\.xlam$' })
    if ($script:MyxRoots.Count -gt 0 -and $main.Count -eq 0) {
        Add-Finding 'ADDIN_CHUA_BAT' 'LOI' 'Add-in MyExcel.xlam CHƯA được bật trong profile này' 'Excel > File > Options > Add-ins > Manage: Excel Add-ins > Go > Browse > C:\MyExcel > chọn MyExcel > OK. Nếu Excel hỏi "Copy to Addins folder?" thì chọn NO.'
    }
    foreach ($m in $openRelated) {
        if ($script:MyxRoots.Count -gt 0 -and -not ($script:MyxRoots | Where-Object { Test-UnderPath $m.Path $_ })) {
            Add-Finding 'ADDIN_SAI_CHO' 'LOI' "Excel đang nạp MyExcel/QR từ vị trí lạ (không phải thư mục cài): $($m.Path)" 'Đây là lỗi hay gặp ở profile cũ: bản sao add-in (thường trong AppData\Roaming\Microsoft\AddIns hoặc Downloads) thiếu file đi kèm. Bỏ tích bản đó trong Add-ins, di chuyển file sao chép đi nơi khác, rồi Browse lại C:\MyExcel\MyExcel.xlam (trả lời NO khi hỏi copy).'
        }
    }
    $byLeaf = $script:AddinEntries | Where-Object { -not $_.Automation } | Group-Object { (Split-Path $_.Path -Leaf).ToLowerInvariant() }
    foreach ($g in $byLeaf) {
        $paths = @($g.Group | ForEach-Object { $_.Path } | Sort-Object -Unique)
        if ($paths.Count -gt 1) {
            $lv = if (Test-Related $g.Name) { 'LOI' } else { 'CANHBAO' }
            Add-Finding 'ADDIN_TRUNG' $lv ("Add-in '{0}' được đăng ký từ {1} đường dẫn khác nhau: {2}" -f $g.Name, $paths.Count, ($paths -join ' ; ')) 'Chỉ giữ 1 bản đúng trong C:\MyExcel. Trong Excel Add-ins bỏ tích các bản còn lại, đổi tên/di chuyển file thừa rồi mở lại Excel.'
        }
    }
} catch { Note "Lỗi khi phân tích add-in: $($_.Exception.Message)" }

try {
    foreach ($ver in $script:OfficeVers) {
        $dk = "HKCU:\Software\Microsoft\Office\$ver\Excel\Resiliency\DisabledItems"
        $items = Get-RegValues $dk
        foreach ($it in $items) {
            $txt = ''
            if ($it.Value -is [byte[]] -and $it.Value.Length -gt 12) {
                $txt = [Text.Encoding]::Unicode.GetString($it.Value, 12, $it.Value.Length - 12) -replace '[\x00-\x1F]+', ' | '
            }
            $lv = if (Test-Related $txt) { 'LOI' } else { 'CANHBAO' }
            Add-Finding 'ADDIN_BI_VO_HIEU' $lv "Excel $ver đã VÔ HIỆU HÓA (Disabled Items): $txt" 'Excel > File > Options > Add-ins > Manage: Disabled Items > Go > chọn mục đó > Enable > đóng mở lại Excel.'
        }
        Snap "AddIns.DisabledItems[$ver]" @($items).Count
        if (@($items).Count -eq 0) { Ok "Excel $ver không có Disabled Items" }
        $st = @(Get-RegValues "HKCU:\Software\Microsoft\Office\$ver\Excel\Resiliency\StartupItems")
        if ($st.Count -gt 0) { Note "Excel $ver có $($st.Count) mục StartupItems (từng bị crash lúc khởi động)." }

        $opt = "HKCU:\Software\Microsoft\Office\$ver\Excel\Options"
        $use = Get-RegValue $opt 'UseSystemSeparators'
        $dsep = Get-RegValue $opt 'DecimalSeparator'
        $tsep = Get-RegValue $opt 'ThousandsSeparator'
        Info "Excel $ver - Use system separators" ($(if ($use -eq 0) { "TẮT (thập phân '$dsep', nghìn '$tsep')" } else { 'bật (theo Windows)' }))
        Snap "Excel.UseSystemSeparators[$ver]" ("$use|$dsep|$tsep")
        $alt = Get-RegValue $opt 'AltStartup'
        if ($alt) {
            Add-Finding 'ALT_STARTUP' 'CANHBAO' "Excel $ver có thư mục khởi động phụ (AltStartup): $alt" 'File trong thư mục này tự mở cùng Excel và có thể xung đột. Kiểm tra File > Options > Advanced > General > "At startup, open all files in".'
        }
    }
} catch { Note "Lỗi khi đọc Disabled Items: $($_.Exception.Message)" }

try {
    Out-Line ''
    Out-Line '  >> File tự mở cùng Excel (XLSTART) và thư mục AddIns của user:' 'White'
    $dirs = @((Join-Path $env:APPDATA 'Microsoft\Excel\XLSTART'), (Join-Path $env:APPDATA 'Microsoft\AddIns'))
    if ($script:ExcelDir) { $dirs += (Join-Path $script:ExcelDir 'XLSTART') }
    $startFiles = @()
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $d -File -Force -ErrorAction SilentlyContinue)) {
            Out-Line ('    {0}  {1}' -f $f.LastWriteTime.ToString('dd/MM/yyyy'), $f.FullName)
            if ($d -match 'XLSTART') { $startFiles += $f }
        }
    }
    Snap 'Excel.XLSTART' (($startFiles | ForEach-Object { $_.Name }) -join ' | ')
    if ($startFiles.Count -gt 0) {
        Add-Finding 'XLSTART_CO_FILE' 'CANHBAO' ("Có file tự mở cùng Excel trong XLSTART: {0}" -f (($startFiles | ForEach-Object { $_.Name }) -join ', ')) 'Profile mới không có các file này. PERSONAL.XLSB có thể đặt chế độ tính toán Manual (hàm VietQR không cập nhật) hoặc trùng tên macro. Thử: Formulas > Calculation Options = Automatic; hoặc tạm di chuyển file ra khỏi XLSTART rồi mở lại Excel.'
    }
    $xlb = @(Get-ChildItem -LiteralPath (Join-Path $env:APPDATA 'Microsoft\Excel') -Filter '*.xlb' -File -ErrorAction SilentlyContinue)
    foreach ($x in $xlb) { Note ("File thanh công cụ: {0} ({1:N0} KB)" -f $x.FullName, ($x.Length / 1KB)) }
    $ui = Join-Path $env:LOCALAPPDATA 'Microsoft\Office\Excel.officeUI'
    if (Test-Path -LiteralPath $ui) { Note "Có tùy biến Ribbon: $ui" }
} catch { Note "Lỗi khi đọc XLSTART: $($_.Exception.Message)" }

try {
    Out-Line ''
    Out-Line '  >> COM add-in của Excel (không phải MyExcel nhưng có thể xung đột):' 'White'
    $comRoots = @(
        'HKCU:\Software\Microsoft\Office\Excel\Addins',
        'HKLM:\SOFTWARE\Microsoft\Office\Excel\Addins',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Excel\Addins',
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\REGISTRY\MACHINE\Software\Microsoft\Office\Excel\Addins',
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\REGISTRY\MACHINE\Software\Wow6432Node\Microsoft\Office\Excel\Addins'
    )
    $comList = @()
    foreach ($r in $comRoots) {
        foreach ($k in (Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue)) {
            $lb = $k.GetValue('LoadBehavior')
            $state = if ($null -eq $lb) { '(không đặt LoadBehavior)' } else {
                switch ([int]$lb) { 0 { 'tắt' } 1 { 'đã nạp (không tự nạp)' } 2 { 'tự nạp nhưng chưa nạp được' } 3 { 'tự nạp khi mở Excel' } 8 { 'nạp khi cần' } 9 { 'nạp khi cần (đã nạp)' } 16 { 'nạp lần đầu' } default { "LoadBehavior=$lb" } }
            }
            $scope = if ($r -like 'HKCU*') { 'user' } else { 'máy' }
            Out-Line ('    [{0}] {1,-45} {2}' -f $scope, $k.PSChildName, $state)
            $comList += "$($k.PSChildName)=$lb"
        }
    }
    if ($comList.Count -eq 0) { Ok 'Không có COM add-in.' }
    Snap 'AddIns.COM' ($comList -join ' | ')
} catch { Note "Lỗi khi đọc COM add-in: $($_.Exception.Message)" }

# ----------------------------------------------------------------------------
Section '6. TRUST CENTER CỦA PROFILE NÀY (Macro, Protected View, ActiveX, Trusted Locations)'
try {
    $ver = if ($script:OfficeVers -contains '16.0') { '16.0' } elseif ($script:OfficeVers.Count -gt 0) { $script:OfficeVers[-1] } else { '16.0' }
    $sec = "HKCU:\Software\Microsoft\Office\$ver\Excel\Security"
    $pol = "HKCU:\Software\Policies\Microsoft\Office\$ver\Excel\Security"
    Info 'Đang đọc cấu hình Office' $ver
    Read-TrustedLocations
    # MyExcel nằm hết trong Trusted Locations (có thư mục con) thì Macro Settings / MOTW không chặn được add-in
    $myxTrusted = ($script:ActiveRoots.Count -gt 0) -and -not ($script:ActiveRoots | Where-Object { -not (Test-TrustedDir $_ -WithSubfolders) })

    # --- Macro settings
    $vw = Get-RegValue $sec 'VBAWarnings'; $vwp = Get-RegValue $pol 'VBAWarnings'
    $eff = if ($null -ne $vwp) { $vwp } elseif ($null -ne $vw) { $vw } else { 2 }
    $txt = switch ($eff) { 1 { 'Enable VBA macros (bật tất cả)' } 2 { 'Disable VBA macros with notification (mặc định)' } 3 { 'Disable except digitally signed' } 4 { 'Disable without notification' } default { "giá trị $eff" } }
    $src = if ($null -ne $vwp) { ' [bị Group Policy ép]' } else { '' }
    Info 'Macro Settings' "$txt$src"
    Snap 'Sec.VBAWarnings' "$eff$src"
    if ($eff -ne 1 -and $myxTrusted) {
        Add-Finding 'MACRO_DA_TIN_CAY' 'THONGTIN' "Macro Settings đang là '$txt' nhưng thư mục MyExcel nằm trong Trusted Locations nên macro MyExcel/QR vẫn chạy - không phải nguyên nhân" 'Chỉ file .xlsm nằm ngoài Trusted Locations mới phải bấm Enable Content. Muốn đúng hướng dẫn MyExcel: Trust Center > Macro Settings > "Enable VBA macros".'
    } elseif ($eff -ne 1) {
        Add-Finding 'MACRO_BI_CHAN' 'LOI' "Macro Settings đang là '$txt' và thư mục MyExcel chưa nằm hết trong Trusted Locations => macro MyExcel/QR bị chặn" 'Excel > File > Options > Trust Center > Trust Center Settings > Macro Settings > chọn "Enable VBA macros" (mục cuối), hoặc thêm C:\MyExcel vào Trusted Locations (tích thư mục con) > OK > đóng mở lại Excel.'
    } else { Ok 'Macro Settings = Enable VBA macros' }

    $vbom = Get-RegValue $sec 'AccessVBOM'; $vbomp = Get-RegValue $pol 'AccessVBOM'
    $vbomEff = if ($null -ne $vbomp) { $vbomp } else { $vbom }
    Info 'Trust access to VBA project object model' ($(if ($vbomEff -eq 1) { 'bật' } else { 'TẮT' }))
    Snap 'Sec.AccessVBOM' $vbomEff
    if ($vbomEff -ne 1) {
        Add-Finding 'VBA_OM_CHUA_BAT' 'THONGTIN' 'Chưa tích "Trust access to the VBA project object model" (mặc định, không cần cho VietQR)' 'Chỉ bật khi tính năng tạo nút/code của MyExcel báo lỗi: Trust Center > Macro Settings > tích "Trust access to the VBA project object model".'
    }

    # --- Protected View
    $pv = "$sec\ProtectedView"
    $pvNames = [ordered]@{ 'DisableInternetFilesInPV' = 'File từ Internet'; 'DisableUnsafeLocationsInPV' = 'File ở vị trí không an toàn'; 'DisableAttachementsInPV' = 'File đính kèm Outlook' }
    $pvOn = @(); $pvOnKeys = @()
    foreach ($n in $pvNames.Keys) {
        $val = Get-RegValue "$pol\ProtectedView" $n
        if ($null -eq $val) { $val = Get-RegValue $pv $n }
        $on = ($val -ne 1)
        Info "Protected View - $($pvNames[$n])" ($(if ($on) { 'ĐANG BẬT' } else { 'đã tắt' }))
        Snap "Sec.PV.$n" $val
        if ($on) { $pvOn += $pvNames[$n]; $pvOnKeys += $n }
    }
    if (@($pvOnKeys | Where-Object { $_ -ne 'DisableAttachementsInPV' }).Count -gt 0) {
        Add-Finding 'PROTECTED_VIEW' 'CANHBAO' ("Protected View còn bật: {0}. File Excel tải về (Zalo/Mail/Internet) mở ở chế độ bảo vệ, phải bấm Enable Editing thì hàm QR mới tính; không làm hỏng việc bật hàm QR" -f ($pvOn -join ', ')) 'Trust Center > Protected View > bỏ các dấu tích > OK (đúng hướng dẫn của MyExcel).'
    } elseif ($pvOn.Count -gt 0) {
        Add-Finding 'PROTECTED_VIEW_OUTLOOK' 'THONGTIN' 'Protected View chỉ còn bật cho file đính kèm Outlook - không liên quan VietQR' 'Không cần xử lý.'
    } else { Ok 'Protected View đã tắt cả 3 mục' }

    # --- ActiveX
    $ax = 'HKCU:\Software\Microsoft\Office\Common\Security'
    $axp = 'HKCU:\Software\Policies\Microsoft\Office\Common\Security'
    $dis = Get-RegValue $axp 'DisableAllActiveX'; if ($null -eq $dis) { $dis = Get-RegValue $ax 'DisableAllActiveX' }
    $ufi = Get-RegValue $axp 'UFIControls'; if ($null -eq $ufi) { $ufi = Get-RegValue $ax 'UFIControls' }
    $axTxt = if ($dis -eq 1) { 'Disable all controls without notification (CHẶN HẾT)' } elseif ($ufi -eq 1) { 'Enable all controls without restrictions' } elseif ($null -eq $ufi) { 'mặc định (Prompt me before enabling...)' } else { "giới hạn (UFIControls=$ufi)" }
    Info 'ActiveX Settings' $axTxt
    Snap 'Sec.ActiveX' "DisableAll=$dis;UFI=$ufi"
    if ($dis -eq 1) {
        Add-Finding 'ACTIVEX_CHAN_HET' 'LOI' 'ActiveX đang CHẶN tất cả control => form Khai báo/Tạo QR của MyExcel báo lỗi' 'Trust Center > ActiveX Settings > chọn "Enable all controls without restrictions and without prompting" > OK (https://myexcel.vn/loi-khai-bao-activex-setting-myexcel/).'
    } elseif ($ufi -ne 1) {
        Add-Finding 'ACTIVEX_CHUA_MO' 'CANHBAO' 'ActiveX chưa đặt "Enable all controls without restrictions" như hướng dẫn cài MyExcel' 'Trust Center > ActiveX Settings > chọn "Enable all controls without restrictions and without prompting" > OK.'
    } else { Ok 'ActiveX = Enable all controls' }

    # --- Trust Center > Add-ins
    $reqSig = Get-RegValue $pol 'RequireAddinSig'; if ($null -eq $reqSig) { $reqSig = Get-RegValue $sec 'RequireAddinSig' }
    $disAdd = Get-RegValue $pol 'DisableAllAddins'; if ($null -eq $disAdd) { $disAdd = Get-RegValue $sec 'DisableAllAddins' }
    Info 'Add-ins: bắt buộc chữ ký số' ($(if ($reqSig -eq 1) { 'CÓ' } else { 'không' }))
    Info 'Add-ins: Disable all Application Add-ins' ($(if ($disAdd -eq 1) { 'CÓ' } else { 'không' }))
    Snap 'Sec.AddinsPolicy' "RequireSig=$reqSig;DisableAll=$disAdd"
    if ($disAdd -eq 1) {
        Add-Finding 'ADDIN_TAT_HET' 'LOI' 'Trust Center đang bật "Disable all Application Add-ins" => mọi add-in (kể cả MyExcel/QR) bị tắt' 'Trust Center > Add-ins > bỏ tích "Disable all Application Add-ins" > OK > mở lại Excel.'
    }
    if ($reqSig -eq 1) {
        Add-Finding 'ADDIN_CAN_KY_SO' 'CANHBAO' 'Trust Center bắt buộc add-in phải có chữ ký số (MyExcel không ký số)' 'Trust Center > Add-ins > bỏ tích "Require Application Add-ins to be signed by Trusted Publisher".'
    }
} catch { Note "Lỗi khi đọc Macro/PV/ActiveX: $($_.Exception.Message)" }

try {
    # --- Trusted Locations
    $tlRoot = "$sec\Trusted Locations"
    $allDis = Get-RegValue $tlRoot 'AllLocationsDisabled'
    $allowNet = Get-RegValue $tlRoot 'AllowNetworkLocations'
    Info 'Disable all Trusted Locations' ($(if ($allDis -eq 1) { 'ĐANG BẬT (mọi vị trí tin cậy bị vô hiệu)' } else { 'không' }))
    Info 'Allow Trusted Locations on network' ($(if ($allowNet -eq 1) { 'có' } else { 'không' }))
    if ($allDis -eq 1) {
        Add-Finding 'TRUSTED_LOC_TAT' 'LOI' 'Đang tích "Disable all Trusted Locations" => C:\MyExcel không được tin cậy' 'Trust Center > Trusted Locations > bỏ tích "Disable all Trusted Locations".'
    }
    $locs = @($script:TlLocs)
    foreach ($l in $locs) {
        $mark = if ($script:MyxRoots | Where-Object { Test-UnderPath $_ $l.Path }) { '  <== MyExcel' } else { '' }
        Out-Line ('    {0}  [subfolders: {1}]{2}{3}' -f $l.Path, ($(if ($l.Sub) { 'có' } else { 'KHÔNG' })), ($(if ($l.Policy) { ' [policy]' } else { '' })), $mark)
    }
    Snap 'Sec.TrustedLocations' (($locs | ForEach-Object { "$($_.Path)[sub=$($_.Sub)]" }) -join ' | ')
    $polUserLoc = Get-RegValue "HKCU:\Software\Policies\Microsoft\Office\$ver\Common\Security\Trusted Locations" 'Allow User Locations'
    if (($locs | Where-Object Policy) -and $polUserLoc -ne 1) {
        Add-Finding 'TRUSTED_LOC_POLICY' 'CANHBAO' 'Group Policy đặt Trusted Locations riêng và có thể bỏ qua vị trí do user tự thêm' 'Cần admin/IT thêm C:\MyExcel vào policy Trusted Locations hoặc bật "Allow mix of policy and user locations".'
    }

    foreach ($root in $script:MyxRoots) {
        $cov = $locs | Where-Object { (Test-SamePath $root $_.Path) -or ((Test-UnderPath $root $_.Path) -and $_.Sub) }
        $covSub = $locs | Where-Object { (Test-UnderPath $root $_.Path) -and $_.Sub }
        if ($cov) { $script:TlCoversRoot = $true }
        $qrDirs = @($script:QrFiles | Where-Object { Test-UnderPath $_ $root } | ForEach-Object { Split-Path $_ -Parent } | Sort-Object -Unique)
        $qrOk = $true
        foreach ($qd in $qrDirs) {
            if (-not ($locs | Where-Object { (Test-SamePath $qd $_.Path) -or ((Test-UnderPath $qd $_.Path) -and $_.Sub) })) { $qrOk = $false }
        }
        if ($qrDirs.Count -gt 0 -and $qrOk) { $script:TlCoversQr = $true }
        if (-not $cov) {
            Add-Finding 'THU_MUC_CHUA_TIN_CAY' 'LOI' "Thư mục $root CHƯA nằm trong Trusted Locations của profile này (profile mới đã khai báo nên chạy được)" "Trust Center > Trusted Locations > Add new location > Browse chọn $root > TÍCH 'Subfolders of this location are also trusted' > OK."
        } elseif (-not $qrOk) {
            Add-Finding 'THU_MUC_CON_CHUA_TIN_CAY' 'LOI' "Đã khai báo $root nhưng KHÔNG tích 'Subfolders of this location are also trusted' => file QR Code trong thư mục con (Mini Tool) không được tin cậy" "Trust Center > Trusted Locations > chọn dòng $root > Modify > tích 'Subfolders of this location are also trusted' > OK."
        } elseif (-not $covSub) {
            Add-Finding 'THU_MUC_CON_CHUA_TIN_CAY' 'CANHBAO' "Đã khai báo $root nhưng không tích 'Subfolders of this location are also trusted'" "Trust Center > Trusted Locations > chọn dòng $root > Modify > tích 'Subfolders of this location are also trusted' > OK."
        } else { Ok "Trusted Locations đã gồm $root và thư mục con" }
    }
    Snap 'Sec.TL.CoversMyExcel' "$($script:TlCoversRoot)|QR=$($script:TlCoversQr)"
} catch { Note "Lỗi khi đọc Trusted Locations: $($_.Exception.Message)" }

try {
    # --- File Block, Trusted Documents, policy chặn macro Internet, Attachment Manager
    $fb = @(Get-RegValues "$sec\FileBlock") + @(Get-RegValues "$pol\FileBlock")
    $fbOn = @($fb | Where-Object { $_.Kind -eq 'DWord' -and $_.Name -ne 'OpenInProtectedView' -and [int]$_.Value -ge 1 })
    foreach ($f in $fbOn) { Note "File Block: $($f.Name) = $($f.Value)" }
    Snap 'Sec.FileBlock' (($fbOn | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' | ')
    if ($fbOn.Count -gt 0) {
        Add-Finding 'FILE_BLOCK' 'CANHBAO' ("Trust Center > File Block Settings đang chặn một số loại file: {0}" -f (($fbOn | ForEach-Object { $_.Name }) -join ', ')) 'Trust Center > File Block Settings > bỏ tích Open/Save của các loại Excel Add-in / Excel 97-2003 rồi OK.'
    }
    $blk = Get-RegValue $pol 'blockcontentexecutionfrominternet'
    Info 'Policy chặn macro file từ Internet' ($(if ($null -eq $blk) { 'không đặt (Office vẫn chặn file có MOTW)' } else { $blk }))
    Snap 'Sec.BlockInternetMacrosPolicy' $blk
    $td = "$sec\Trusted Documents"
    $disTd = Get-RegValue $td 'DisableTrustedDocuments'
    $tr = @(Get-RegValues "$td\TrustRecords")
    Info 'Trusted Documents' ("tắt={0}; số file đã tin cậy={1}" -f ($disTd -eq 1), $tr.Count)
    foreach ($t in ($tr | Where-Object { Test-Related $_.Name })) { Note "Tin cậy: $($t.Name)" }
    $sz = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments' 'SaveZoneInformation'
    Info 'Windows ghi dấu MOTW cho file tải về' ($(if ($sz -eq 1) { 'KHÔNG (policy tắt)' } else { 'có (mặc định)' }))
    Snap 'Win.SaveZoneInformation' $sz

    $polLines = @()
    foreach ($pr in 'HKCU:\Software\Policies\Microsoft\Office', 'HKLM:\SOFTWARE\Policies\Microsoft\Office') {
        if (-not (Test-Path $pr)) { continue }
        foreach ($k in @(Get-Item $pr) + @(Get-ChildItem -LiteralPath $pr -Recurse -ErrorAction SilentlyContinue)) {
            foreach ($n in $k.GetValueNames()) { $polLines += ('{0}\{1} = {2}' -f ($k.Name -replace '^HKEY_(CURRENT_USER|LOCAL_MACHINE)\\SOFTWARE\\Policies\\Microsoft\\Office', ''), $n, (Format-RegData $k.GetValue($n))) }
        }
    }
    if ($polLines.Count -gt 0) {
        Add-Finding 'GROUP_POLICY_OFFICE' 'THONGTIN' "Máy có $($polLines.Count) giá trị Group Policy cho Office (liệt kê bên dưới)" 'Policy có thể ghi đè cài đặt Trust Center; cần quyền admin để đổi.'
        foreach ($l in ($polLines | Select-Object -First 60)) { Note $l }
    }
    Snap 'Sec.OfficePolicies' ($polLines -join ' | ')
} catch { Note "Lỗi khi đọc File Block/Policy: $($_.Exception.Message)" }

try {
    # --- Dữ liệu MyExcel lưu bằng VBA SaveSetting (theo từng user)
    $vbRoot = if ($env:MYX_VBROOT) { $env:MYX_VBROOT } else { 'HKCU:\Software\VB and VBA Program Settings' }   # MYX_VBROOT chỉ dùng khi test
    Out-Line ''
    Out-Line '  >> Cài đặt VBA lưu theo user (HKCU\Software\VB and VBA Program Settings):' 'White'
    $apps = @(Get-ChildItem -LiteralPath $vbRoot -ErrorAction SilentlyContinue)
    if ($apps.Count -eq 0) { Note '(không có)' }
    $names = @()
    $bankRx = '(?i)myexcel|qr|bank|ngan.?hang|tai.?khoan|stk|mini.?tool|qlvb'
    foreach ($app in $apps) {
        $keys = @(Get-Item -LiteralPath $app.PSPath) + @(Get-ChildItem -LiteralPath $app.PSPath -Recurse -ErrorAction SilentlyContinue)
        foreach ($k in $keys) { $names += ($k.Name -replace '^.*VB and VBA Program Settings\\', '') }
        $rel = ($app.PSChildName -notmatch '(?i)ultraviewer|teamviewer|anydesk') -and
               [bool]($keys | Where-Object { $_.PSChildName -match $bankRx -or (@($_.GetValueNames()) -match $bankRx) })
        if (-not $rel) {
            Out-Line ("    [{0}] ({1} nhánh) - không liên quan" -f $app.PSChildName, $keys.Count)
            continue
        }
        foreach ($k in $keys) {
            $short = $k.Name -replace '^.*VB and VBA Program Settings\\', ''
            $vals = $k.GetValueNames()
            Out-Line ("    [{0}] ({1} giá trị)" -f $short, $vals.Count) 'White'
            foreach ($n in ($vals | Select-Object -First 25)) {
                $d = Hide-Digits (Format-RegData $k.GetValue($n))
                if ($d.Length -gt 80) { $d = $d.Substring(0, 80) + '...' }
                Note ("{0} = {1}" -f $n, $d)
            }
        }
        Add-Finding 'DU_LIEU_VBA_USER' 'THONGTIN' "Có dữ liệu VBA lưu theo user ở nhánh [$($app.PSChildName)] (có thể là tài khoản ngân hàng/cài đặt QR của MyExcel)" 'Profile mới chỉ có dữ liệu này sau khi dùng MyExcel. Nếu mọi mục LỖI đã xử lý mà vẫn lỗi: chạy FixMyExcel_VietQR.bat, ở bước 9 chọn đặt lại dữ liệu MyExcel (có sao lưu), rồi khai báo lại tài khoản ngân hàng.'
    }
    Snap 'VBA.SaveSettingKeys' ($names -join ' | ')

    # Dữ liệu MyExcel tạo từ bản cũ hơn bộ đang dùng: đúng kiểu lỗi "profile mới tạo được VietQR, profile cũ thì không"
    $dataDate = $null
    foreach ($app in ($apps | Where-Object { $_.PSChildName -cmatch '^[il]{12,}[a-z0-9]*$' } | Sort-Object { $_.PSChildName.Length })) {
        $v = [string](Get-RegValue (Join-Path $app.PSPath 'InVung') 'AndanInNgayCai')
        $d = [datetime]::MinValue
        if ($v -and [datetime]::TryParseExact($v.Trim(), [string[]]@('d.M.yyyy', 'd/M/yyyy', 'd-M-yyyy'), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { $dataDate = $d; break }
    }
    if ($dataDate) {
        $xlams = @($script:AddinEntries | Where-Object { $_.Source -eq 'OPEN' -and $_.Path -match '(?i)\\myexcel\.xlam$' -and (Test-Path -LiteralPath $_.Path) } | ForEach-Object { $_.Path }) +
                 @($script:ActiveRoots | ForEach-Object { Join-Path $_ 'MyExcel.xlam' } | Where-Object { Test-Path -LiteralPath $_ })
        Snap 'MyExcel.DataVersion' $dataDate.ToString('yyyy-MM-dd')
        if ($xlams.Count -gt 0) {
            $xlamDate = (Get-Item -LiteralPath $xlams[0] -Force).LastWriteTime
            Info 'Dữ liệu MyExcel tạo từ bản' ('{0} (bộ MyExcel đang dùng: {1})' -f $dataDate.ToString('dd/MM/yyyy'), $xlamDate.ToString('dd/MM/yyyy'))
            if (($xlamDate - $dataDate).TotalDays -gt 30) {
                Add-Finding 'DU_LIEU_MYEXCEL_CU' 'LOI' ('Dữ liệu MyExcel của profile tạo từ bản {0}, cũ hơn bộ MyExcel đang dùng ({1}) - đúng kiểu lỗi đã gặp: profile cũ không bật/tạo được VietQR, profile mới thì được' -f $dataDate.ToString('dd/MM/yyyy'), $xlamDate.ToString('dd/MM/yyyy')) 'Chạy FixMyExcel_VietQR.bat trong profile này, ở bước 9 chọn "Đặt lại dữ liệu MyExcel ngay" (có sao lưu và file hoàn tác), rồi khai báo lại tài khoản ngân hàng.'
            }
        }
    }
} catch { Note "Lỗi khi đọc VB and VBA Program Settings: $($_.Exception.Message)" }

# ----------------------------------------------------------------------------
Section '7. THƯ MỤC TẠM, CACHE ACTIVEX (.exd), ONEDRIVE, MÁY IN, BỘ GÕ'
try {
    $t = $env:TEMP
    $exists = Test-Path -LiteralPath $t -PathType Container
    $writable = Test-Writable $t
    Info 'TEMP tồn tại / ghi được' "$exists / $writable"
    Snap 'Temp.Writable' $writable
    if (-not $exists -or -not $writable) {
        Add-Finding 'TEMP_HONG' 'LOI' "Thư mục TEMP của user ($t) không tồn tại hoặc không ghi được => VBA không tạo được file ảnh QR tạm" 'Tạo lại thư mục TEMP hoặc đặt lại biến: setx TEMP "%USERPROFILE%\AppData\Local\Temp" và setx TMP "%USERPROFILE%\AppData\Local\Temp", đăng xuất/đăng nhập lại.'
    } else {
        $cnt = 0; $tmpCnt = 0
        foreach ($f in [IO.Directory]::EnumerateFiles($t)) {
            $cnt++
            if ($f.EndsWith('.tmp', [StringComparison]::OrdinalIgnoreCase)) { $tmpCnt++ }
            if ($cnt -ge 200000) { break }
        }
        Info 'Số file trong TEMP (cấp 1) / file .tmp' "$cnt / $tmpCnt"
        Snap 'Temp.FileCountBucket' ($(if ($cnt -gt 20000) { '>20000' } elseif ($cnt -gt 2000) { '>2000' } else { '<=2000' }))
        if ($tmpCnt -gt 30000) {
            Add-Finding 'TEMP_QUA_NHIEU_TMP' 'LOI' "TEMP có $tmpCnt file .tmp (Windows giới hạn 65535) => Excel/VBA có thể không tạo được file tạm" 'Đóng Excel, Win+R gõ %TEMP% > Ctrl+A > Delete (bỏ qua file đang dùng).'
        } elseif ($cnt -gt 5000) {
            Add-Finding 'TEMP_NHIEU_FILE' 'CANHBAO' "TEMP có $cnt file" 'Đóng Excel, Win+R gõ %TEMP% > xóa bớt file tạm.'
        }
    }

    $exdDirs = @("$env:TEMP\VBE", "$env:TEMP\Excel8.0", "$env:TEMP\Word8.0", "$env:APPDATA\Microsoft\Forms", "$env:LOCALAPPDATA\Temp\VBE", "$env:LOCALAPPDATA\Temp\Excel8.0")
    $exd = @()
    foreach ($d in ($exdDirs | Sort-Object -Unique)) {
        if (Test-Path -LiteralPath $d) { $exd += Get-ChildItem -LiteralPath $d -Filter '*.exd' -File -Force -ErrorAction SilentlyContinue }
    }
    $exd = @($exd | Sort-Object FullName -Unique)
    foreach ($e in $exd) { Note ("{0}  {1}" -f $e.LastWriteTime.ToString('dd/MM/yyyy'), $e.FullName) }
    Snap 'Temp.ExdCount' $exd.Count
    $exdFix = 'Đóng hết Excel/Word, mở CMD chạy:  del /s /q "%TEMP%\*.exd"  và  del /q "%APPDATA%\Microsoft\Forms\*.exd"  rồi mở lại Excel (Office tự tạo lại).'
    $exeTime = $null
    if ($script:ExcelDir -and (Test-Path -LiteralPath (Join-Path $script:ExcelDir 'EXCEL.EXE'))) { $exeTime = (Get-Item -LiteralPath (Join-Path $script:ExcelDir 'EXCEL.EXE')).LastWriteTime }
    $staleExd = @($exd | Where-Object { $exeTime -and $_.LastWriteTime -lt $exeTime })
    if ($staleExd.Count -gt 0) {
        Add-Finding 'EXD_CU' 'CANHBAO' ("Có {0} file cache ActiveX (.exd) cũ hơn bản Excel đang cài ({1}) - cache cũ có thể làm form/nút VBA lỗi sau khi Office cập nhật (Office tự tạo lại nên profile nào dùng lâu cũng có)" -f $staleExd.Count, $exeTime.ToString('dd/MM/yyyy')) $exdFix
    } elseif ($exd.Count -gt 0) {
        Add-Finding 'EXD_BINH_THUONG' 'THONGTIN' "Có $($exd.Count) file cache ActiveX (.exd), không cũ hơn bản Excel đang cài - bình thường" "Chỉ cần xóa nếu form/nút VBA báo lỗi. $exdFix"
    } else { Ok 'Không có file .exd' }
} catch { Note "Lỗi khi kiểm tra TEMP: $($_.Exception.Message)" }

try {
    $desk = [Environment]::GetFolderPath('Desktop')
    $docs = [Environment]::GetFolderPath('MyDocuments')
    Info 'Desktop' $desk
    Info 'Documents' $docs
    $od = @(Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue |
        Where-Object { $_.GetValue('UserFolder') } | ForEach-Object { "$($_.PSChildName): $($_.GetValue('UserFolder'))" })
    foreach ($o in $od) { Info 'OneDrive đăng nhập' $o }
    Snap 'OneDrive.KFM' (($desk -match '(?i)onedrive') -or ($docs -match '(?i)onedrive'))
    if ($desk -match '(?i)onedrive' -or $docs -match '(?i)onedrive') {
        Add-Finding 'ONEDRIVE_DONG_BO' 'CANHBAO' 'Desktop/Documents đang đồng bộ OneDrive: file Excel mở từ đó có đường dẫn dạng https:// nên macro lưu/chèn ảnh QR có thể lỗi' 'Copy file Excel cần tạo VietQR ra thư mục thường (VD C:\Data) rồi mở và thử lại. Nếu chạy được => tắt backup Desktop/Documents của OneDrive hoặc làm việc ngoài OneDrive.'
    }
} catch { Note "Lỗi khi kiểm tra OneDrive: $($_.Exception.Message)" }

try {
    $prn = @(Get-CimInstance Win32_Printer -OperationTimeoutSec 20 -ErrorAction Stop)
    $def = $prn | Where-Object { $_.Default } | Select-Object -First 1
    Info 'Số máy in' $prn.Count
    if ($def) {
        Info 'Máy in mặc định của user' ("{0} (offline: {1}, mạng: {2})" -f $def.Name, $def.WorkOffline, $def.Network)
        Snap 'Printer.Default' $def.Name
        if ($def.WorkOffline) {
            Add-Finding 'MAY_IN_OFFLINE' 'CANHBAO' "Máy in mặc định '$($def.Name)' đang offline - VBA đụng tới PageSetup/In sẽ treo hoặc báo lỗi" 'Đặt "Microsoft Print to PDF" làm máy in mặc định rồi thử lại.'
        }
    } else {
        Snap 'Printer.Default' ''
        Add-Finding 'KHONG_CO_MAY_IN' 'CANHBAO' 'User này không có máy in mặc định' 'Settings > Bluetooth & devices > Printers & scanners > tắt "Let Windows manage my default printer" > chọn Microsoft Print to PDF > Set as default.'
    }
} catch { Note "Không đọc được danh sách máy in: $($_.Exception.Message)" }

try {
    $pn = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
    $ime = @($pn | Where-Object { $_ -match '(?i)^(unikey|unikeynt|evkey|evkey64|evkey32|openkey|gotiengviet|vietkey)' })
    $rem = @($pn | Where-Object { $_ -match '(?i)^(ultraviewer|teamviewer|anydesk|rustdesk)' })
    Info 'Bộ gõ tiếng Việt đang chạy' ($ime -join ', ')
    Info 'Phần mềm điều khiển từ xa' ($rem -join ', ')
    Snap 'Proc.IME' ($ime -join ',')
    if ($ime.Count -gt 0) {
        Add-Finding 'BO_GO_DANG_CHAY' 'THONGTIN' "Bộ gõ $($ime -join ', ') đang chạy" 'Khi gõ công thức =QrBank_Sotien_Noidung(...) hoặc khai báo tài khoản, chuyển bộ gõ sang chế độ E (tiếng Anh) để tránh bị bỏ dấu/đổi ký tự.'
    }
    $clip = Get-RegValue 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory'
    Info 'Clipboard history (Win+V)' ($(if ($clip -eq 1) { 'bật' } else { 'tắt' }))
    Snap 'Win.ClipboardHistory' $clip
} catch {}

# ----------------------------------------------------------------------------
Section '8. THÀNH PHẦN COM MÀ MACRO VBA HAY DÙNG + ĐĂNG KÝ COM HỎNG TRONG HKCU'
try {
    $ids = "'Scripting.FileSystemObject','Scripting.Dictionary','VBScript.RegExp','Shell.Application','WIA.ImageFile','MSXML2.DOMDocument.6.0'"
    $code = "foreach (`$id in @($ids)) { try { `$o = New-Object -ComObject `$id -ErrorAction Stop; [void][Runtime.InteropServices.Marshal]::ReleaseComObject(`$o); 'OK|' + `$id } catch { 'FAIL|' + `$id + '|' + `$_.Exception.Message } }"
    $useWow = $script:OfficeIs32 -and [Environment]::Is64BitProcess
    $bitTxt = if ($useWow) { '32-bit (giống Excel)' } else { "$(if ([Environment]::Is64BitProcess) { '64' } else { '32' })-bit" }
    Info 'Kiểm tra COM ở chế độ' $bitTxt
    if ($useWow) {
        $ps32 = "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
        $res = $code | & $ps32 -NoProfile -NonInteractive -Command -
    } else {
        $res = & ([scriptblock]::Create($code))
    }
    $fails = @()
    foreach ($r in $res) {
        $parts = ([string]$r).Split('|')
        if ($parts[0] -eq 'OK') { Ok "COM $($parts[1])" }
        elseif ($parts[0] -eq 'FAIL') { $fails += $parts[1]; Out-Line "  [X]   COM $($parts[1]) : $($parts[2])" 'Red' }
    }
    Snap 'COM.Fail' ($fails -join ',')
    if ($fails.Count -gt 0) {
        Add-Finding 'COM_LOI' 'CANHBAO' ("Không tạo được đối tượng COM: {0}" -f ($fails -join ', ')) 'Nếu profile mới tạo được còn profile này thì không => đăng ký COM theo user bị hỏng (xem danh sách HKCU bên dưới). Nếu cả máy đều lỗi => mở CMD (Admin) chạy: regsvr32 scrrun.dll  /  regsvr32 vbscript.dll  /  regsvr32 wiaaut.dll.'
    }
} catch { Note "Lỗi khi thử COM: $($_.Exception.Message)" }

try {
    $broken = @()
    foreach ($k in (Get-ChildItem -LiteralPath 'HKCU:\Software\Classes\CLSID' -ErrorAction SilentlyContinue)) {
        foreach ($srv in 'InprocServer32', 'LocalServer32') {
            $sk = $k.OpenSubKey($srv)
            if (-not $sk) { continue }
            $val = [string]$sk.GetValue('')
            $sk.Close()
            if (-not $val) { continue }
            $file = [Environment]::ExpandEnvironmentVariables($val)
            if ($file -match '^"([^"]+)"') { $file = $Matches[1] } else { $file = ($file -split '\s+/')[0].Trim() }
            if ($file -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $file)) { $broken += "CLSID $($k.PSChildName) -> $file" }
        }
    }
    foreach ($k in (Get-ChildItem -LiteralPath 'HKCU:\Software\Classes\TypeLib' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^win(32|64)$' })) {
        $file = [Environment]::ExpandEnvironmentVariables([string]$k.GetValue('')) -replace '\\\d+$', ''
        if ($file -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $file)) { $broken += "TypeLib $($k.Name -replace '^.*\\TypeLib\\', '') -> $file" }
    }
    # TypeLib/COM mà VBA của Office hay tham chiếu: MSForms, Office, VBA, VBIDE, Excel, stdole, Scripting, MSComctl, WIA, MSXML
    $vbaRx = '(?i)0D452EE1-E08F-101A-852E-02608C4D0BB4|2DF8D04C-5BFA-101B-BDE5-00AA0044DE52|000204EF-0000-0000-C000-000000000046|0002E157-0000-0000-C000-000000000046|00020813-0000-0000-C000-000000000046|00020430-0000-0000-C000-000000000046|420B2830-E718-11CF-893D-00A0C9054228|831FDD16-0C5C-11D2-A9FC-0000F8754DA1|94A0E92D-43C0-494E-AC29-FD45948A5221|F5078F18-C551-11D3-89B9-0000F81FE221|fm20|mscomctl|vbe7|scrrun|wiaaut|msxml|Microsoft Office|Microsoft Shared'
    $vbaBroken = @($broken | Where-Object { $_ -match $vbaRx })
    Info 'Đăng ký COM/TypeLib hỏng trong HKCU' ("{0} (liên quan VBA/Office: {1})" -f $broken.Count, $vbaBroken.Count)
    foreach ($b in ($vbaBroken | Select-Object -First 20)) { Out-Line "    $b" 'Red' }
    Snap 'COM.HKCUBrokenVBA' $vbaBroken.Count
    if ($vbaBroken.Count -gt 0) {
        $coreRx = '(?i)0D452EE1-E08F-101A-852E-02608C4D0BB4|2DF8D04C-5BFA-101B-BDE5-00AA0044DE52|000204EF-0000-0000-C000-000000000046|0002E157-0000-0000-C000-000000000046|00020813-0000-0000-C000-000000000046|00020430-0000-0000-C000-000000000046|fm20|vbe7'
        $lv = if ($vbaBroken | Where-Object { $_ -match $coreRx }) { 'LOI' } else { 'CANHBAO' }
        Add-Finding 'COM_VBA_HONG' $lv "Có $($vbaBroken.Count) đăng ký COM/TypeLib của VBA/Office trong HKCU trỏ tới file không tồn tại (VBA báo lỗi thư viện/ActiveX, profile mới không bị)" 'Mở regedit, Export rồi xóa đúng các key GUID được liệt kê ở trên trong HKCU\Software\Classes (CLSID/TypeLib), sau đó mở lại Excel. Đăng ký ở cấp máy (HKLM) vẫn còn nên Excel dùng lại bản đúng.'
    }
} catch { Note "Lỗi khi quét HKCU\Software\Classes: $($_.Exception.Message)" }

# ----------------------------------------------------------------------------
Section '9. PHẦN MỀM DIỆT VIRUS / WINDOWS SECURITY (có xóa file MyExcel không?)'
try {
    $avs = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)
    foreach ($av in $avs) {
        $hex = '{0:X6}' -f [int]$av.productState
        $on = $hex.Substring(2, 2) -match '1[0-1]'
        Info 'Antivirus' ("{0} (đang bật: {1})" -f $av.displayName, $on)
    }
    $third = @($avs | Where-Object { $_.displayName -notmatch '(?i)windows defender|microsoft defender' })
    if ($third.Count -gt 0) {
        Add-Finding 'AV_BEN_THU_BA' 'THONGTIN' ("Có phần mềm diệt virus bên thứ 3: {0}" -f (($third | ForEach-Object { $_.displayName }) -join ', ')) 'Thêm C:\MyExcel vào danh sách loại trừ (Exclusions) của phần mềm này; kiểm tra khu cách ly (Quarantine) xem có file QR Code/xlam không.'
    }
} catch {}
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    Info 'Defender real-time protection' $mp.RealTimeProtectionEnabled
    $pref = Get-MpPreference -ErrorAction Stop
    $ex = @($pref.ExclusionPath)
    if ($ex.Count -eq 1 -and "$($ex[0])" -match 'N/A') {
        Info 'Defender Exclusions' 'cần chạy quyền admin mới xem được'
    } else {
        Info 'Defender Exclusions' ($ex -join ' | ')
        if ($mp.RealTimeProtectionEnabled -and -not ($ex | Where-Object { "$_" -match '(?i)myexcel' })) {
            Add-Finding 'CHUA_LOAI_TRU_DEFENDER' 'CANHBAO' 'Chưa thêm thư mục MyExcel vào Exclusions của Windows Security' 'Windows Security > Virus & threat protection > Manage settings > Exclusions > Add or remove exclusions > Add folder > C:\MyExcel (bước 7 hướng dẫn cài MyExcel).'
        }
    }
    Info 'Controlled folder access' ($(switch ($pref.EnableControlledFolderAccess) { 1 { 'BẬT' } 2 { 'audit' } default { 'tắt' } }))
    if ($pref.EnableControlledFolderAccess -eq 1) {
        Add-Finding 'CFA_BAT' 'CANHBAO' 'Controlled folder access đang bật: Excel có thể bị chặn ghi file vào Documents/Desktop' 'Windows Security > Ransomware protection > Allow an app through Controlled folder access > thêm EXCEL.EXE.'
    }
    $asrNames = @{
        '92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B' = 'Chặn macro Office gọi Win32 API'
        'D4F940AB-401B-4EFC-AADC-AD5F3C50688A' = 'Chặn Office tạo tiến trình con'
        '3B576869-A4EC-4529-8536-B80A7769E899' = 'Chặn Office tạo nội dung thực thi'
        '75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84' = 'Chặn Office chèn code vào tiến trình khác'
    }
    $ids = @($pref.AttackSurfaceReductionRules_Ids); $acts = @($pref.AttackSurfaceReductionRules_Actions)
    for ($i = 0; $i -lt $ids.Count; $i++) {
        $n = $asrNames[[string]$ids[$i]]
        if ($n -and $acts[$i] -eq 1) {
            Add-Finding 'ASR_BAT' 'CANHBAO' "Defender ASR đang bật luật: $n" 'Luật này có thể chặn macro MyExcel (áp dụng cả máy). Cần admin tắt/đặt Audit hoặc thêm loại trừ ASR cho C:\MyExcel.'
        }
    }
} catch { Note "Không đọc được Defender: $($_.Exception.Message)" }
try {
    $det = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object { ($_.Resources -join ';') -match '(?i)myexcel|qr.?code|\.xlam|\.xla\b' })
    foreach ($d in ($det | Select-Object -First 10)) { Note ("{0}  {1}" -f $d.InitialDetectionTime, ($d.Resources -join '; ')) }
    if ($det.Count -gt 0) {
        Add-Finding 'DEFENDER_DA_XU_LY' 'LOI' "Windows Defender từng phát hiện/xử lý $($det.Count) lần trên file MyExcel/add-in" 'Windows Security > Protection history > chọn mục MyExcel > Actions > Allow/Restore; thêm C:\MyExcel vào Exclusions; copy lại file bị xóa từ bộ cài.'
    } else { Ok 'Defender không ghi nhận phát hiện nào trên file MyExcel' }
} catch { Note 'Không đọc được lịch sử Defender (thường cần quyền admin).' }

# ----------------------------------------------------------------------------
Section '10. THÔNG BÁO LỖI OFFICE & CRASH GẦN ĐÂY (30 ngày)'
try {
    $since = (Get-Date).AddDays(-30)
    $oaRx = '(?i)macro|visual basic|vba|add-?in|activex|trust|blocked|protected view|run-?time|compile|object library|project or library|myexcel|qr|\.xlam|\.xla\b|untrusted|security|không tin cậy|bị chặn|lỗi'
    $oa = @(Get-WinEvent -FilterHashtable @{ LogName = 'OAlerts'; StartTime = $since } -MaxEvents 500 -ErrorAction Stop |
        Where-Object { $_.Message -match $oaRx -and $_.Message -notmatch '(?i)^Compositor Type|want to save your changes' })
    Info 'Số hộp thoại lỗi Office (OAlerts) liên quan' $oa.Count
    $groups = $oa | Group-Object { (($_.Message -replace '\s+', ' ') -replace '\s*P1:.*$', '').Trim() }
    foreach ($g in ($groups | Select-Object -First 15)) {
        $m = $g.Name
        if ($m.Length -gt 260) { $m = $m.Substring(0, 260) + '...' }
        Out-Line ("    {0} (x{1})  {2}" -f $g.Group[0].TimeCreated.ToString('dd/MM HH:mm'), $g.Count, $m) 'Yellow'
    }
} catch { Note 'Không có/không đọc được nhật ký OAlerts.' }
try {
    $cr = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1002; StartTime = $since } -MaxEvents 500 -ErrorAction Stop |
        Where-Object { $_.Message -match '(?i)excel\.exe' })
    Info 'Số lần EXCEL.EXE crash/treo' $cr.Count
    foreach ($e in ($cr | Select-Object -First 5)) {
        $mod = if ($e.Message -match '(?i)Faulting module (name|path):\s*([^\r\n,]+)') { $Matches[2] } else { '' }
        Note ("{0}  Event {1}  {2}" -f $e.TimeCreated.ToString('dd/MM HH:mm'), $e.Id, $mod)
    }
    if ($cr.Count -ge 3) {
        Add-Finding 'EXCEL_CRASH' 'CANHBAO' "Excel bị crash/treo $($cr.Count) lần trong 30 ngày" 'Sửa Office: Settings > Apps > Microsoft 365/Office > Modify > Quick Repair (nếu vẫn lỗi thì Online Repair).'
    }
} catch { Note 'Không đọc được nhật ký Application.' }

# ----------------------------------------------------------------------------
Section '11. MẠNG (kích hoạt bản quyền / tải dữ liệu ngân hàng nếu có)'
try {
    $is = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $pe = Get-RegValue $is 'ProxyEnable'; $ps = Get-RegValue $is 'ProxyServer'; $pac = Get-RegValue $is 'AutoConfigURL'
    Info 'Proxy của user' ("bật={0} server={1} pac={2}" -f ($pe -eq 1), $ps, $pac)
    Snap 'Net.Proxy' "$pe|$ps|$pac"
    if ($pe -eq 1 -or $pac) {
        Add-Finding 'PROXY_BAT' 'CANHBAO' "Profile này đặt proxy ($ps$pac) - profile mới thì không" 'Settings > Network & internet > Proxy > tắt "Use a proxy server"/"Use setup script" nếu không cần.'
    }
    $sp = Get-RegValue $is 'SecureProtocols'
    if ($null -ne $sp) {
        $tls12 = (([int]$sp) -band 0x800) -ne 0
        Info 'TLS 1.2 trong Internet Options' $tls12
        Snap 'Net.SecureProtocols' $sp
        if (-not $tls12) {
            Add-Finding 'TLS12_TAT' 'CANHBAO' 'Internet Options của user đang tắt TLS 1.2' 'Control Panel > Internet Options > Advanced > tích Use TLS 1.2 (và 1.3) > OK.'
        }
    }
    $wh = (netsh winhttp show proxy) -join ' '
    Info 'WinHTTP proxy' (($wh -replace '\s+', ' ').Trim())
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    foreach ($u in 'https://myexcel.vn/', 'https://api.vietqr.io/v2/banks') {
        try {
            $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 12 -ErrorAction Stop
            Ok "$u -> HTTP $($r.StatusCode)"
        } catch {
            if ($_.Exception.Response) { Ok "$u -> HTTP $([int]$_.Exception.Response.StatusCode) (có kết nối)" }
            else {
                Add-Finding 'KHONG_KET_NOI' 'CANHBAO' "Không kết nối được $u : $($_.Exception.Message)" 'Kiểm tra mạng/tường lửa/proxy (chỉ ảnh hưởng chức năng cần Internet như kích hoạt bản quyền).'
            }
        }
    }
} catch { Note "Lỗi khi kiểm tra mạng: $($_.Exception.Message)" }

# ----------------------------------------------------------------------------
Section '12. SO SÁNH VỚI PROFILE KHÁC TRÊN CÙNG MÁY'
$outDir = if ($env:MYX_OUT) { $env:MYX_OUT } else { Join-Path $env:PUBLIC 'Documents\MyExcelCheck' }
$stamp = $script:Started.ToString('yyyyMMdd_HHmmss')
$safeUser = ($env:USERNAME -replace '[^\w\.-]', '_')
try {
    if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $snapFile = Join-Path $outDir ("snapshot_{0}_{1}.json" -f $env:COMPUTERNAME, $safeUser)
    $others = @(Get-ChildItem -LiteralPath $outDir -Filter ("snapshot_{0}_*.json" -f $env:COMPUTERNAME) -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $snapFile })
    if ($others.Count -eq 0) {
        Note 'Chưa có kết quả của profile nào khác.'
        Note '=> Hãy chạy file .bat này thêm 1 lần trong PROFILE MỚI (profile tạo VietQR được).'
        Note '   Lần chạy thứ 2 sẽ tự in ra bảng khác biệt giữa 2 profile tại mục này.'
    }
    foreach ($of in $others) {
        # Một snapshot hỏng (ghi dở, sửa tay) chỉ bỏ qua file đó, không chặn so sánh và lưu snapshot của lần này
        try { $o = Get-Content -LiteralPath $of.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        catch { Note "Bỏ qua snapshot hỏng $($of.Name): $($_.Exception.Message)"; continue }
        if (-not $o) { Note "Bỏ qua snapshot rỗng $($of.Name)"; continue }
        $oName = $o.'_User'
        Out-Line ''
        Out-Line ("  >> Khác biệt: profile NÀY ({0})  vs  profile '{1}' (chạy lúc {2})" -f $env:USERNAME, $oName, $o.'_Time') 'White'
        $keys = @($script:Snap.Keys) + @($o.PSObject.Properties.Name | Where-Object { $_ -notlike '_*' }) | Sort-Object -Unique
        $diff = 0
        foreach ($k in $keys) {
            $a = if ($script:Snap.Contains($k)) { [string]$script:Snap[$k] } else { '(không có)' }
            $bp = $o.PSObject.Properties[$k]
            $b = if ($bp) { [string]$bp.Value } else { '(không có)' }
            if ($a -cne $b) {
                $diff++
                Out-Line ("    {0}" -f $k) 'Yellow'
                Out-Line ("        profile này : {0}" -f $a)
                Out-Line ("        '{0}' : {1}" -f $oName, $b)
            }
        }
        if ($diff -eq 0) { Ok 'Không có khác biệt ở các mục đã đo.' }
        else { Note "=> $diff mục khác nhau. Các mục Sec.*, AddIns.*, Temp.*, Path.*, Region.* khác nhau chính là nghi phạm hàng đầu." }
    }
    $script:Snap['_User'] = $env:USERNAME
    $script:Snap['_Time'] = $script:Started.ToString('dd/MM/yyyy HH:mm')
    [IO.File]::WriteAllText("$snapFile.tmp", ($script:Snap | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath "$snapFile.tmp" -Destination $snapFile -Force -ErrorAction Stop
} catch { Note "Lỗi khi so sánh profile: $($_.Exception.Message)" }

# ----------------------------------------------------------------------------
Section 'KẾT LUẬN & HƯỚNG GIẢI QUYẾT'
$order = @{ 'LOI' = 0; 'CANHBAO' = 1; 'THONGTIN' = 2 }
$sorted = @($script:Findings | Sort-Object @{ Expression = { $order[$_.Level] } }, Idx)
$nLoi = @($sorted | Where-Object Level -eq 'LOI').Count
$nWarn = @($sorted | Where-Object Level -eq 'CANHBAO').Count
Info 'Số mục LỖI (nhiều khả năng là nguyên nhân)' $nLoi
Info 'Số mục CẢNH BÁO (có thể liên quan)' $nWarn
$i = 0
foreach ($f in $sorted) {
    $i++
    $label = switch ($f.Level) { 'LOI' { '[LỖI]' } 'CANHBAO' { '[CẢNH BÁO]' } default { '[THÔNG TIN]' } }
    $color = switch ($f.Level) { 'LOI' { 'Red' } 'CANHBAO' { 'Yellow' } default { 'DarkYellow' } }
    Out-Line ''
    Out-Line ("  {0}. {1} {2}  ({3})" -f $i, $label, $f.Title, $f.Code) $color
    Out-Line ("     => Cách xử lý: {0}" -f $f.Fix) 'Green'
}
if ($sorted.Count -eq 0) { Ok 'Không phát hiện bất thường ở các mục đã kiểm tra.' }

Out-Line ''
Out-Line '  CÁCH NHANH: chạy FixMyExcel_VietQR.bat trong profile lỗi. Script tự làm phần lớn các bước dưới (không đổi' 'Green'
Out-Line '  Macro/Protected View/ActiveX) và hỏi để đặt lại dữ liệu MyExcel; có sao lưu và file hoàn tác.' 'Green'
Out-Line ''
Out-Line '  QUY TRÌNH XỬ LÝ BẰNG TAY (làm theo thứ tự, thử VietQR sau mỗi bước):' 'Cyan'
$steps = @(
    '1) Đóng hết Excel (kể cả EXCEL.EXE chạy ẩn trong Task Manager).',
    '2) Unblock toàn bộ C:\MyExcel: mở PowerShell gõ  Get-ChildItem -LiteralPath C:\MyExcel -Recurse | Unblock-File',
    '3) Mở Excel > File > Options > Trust Center > Trust Center Settings:',
    '     - Trusted Locations: có C:\MyExcel và TÍCH "Subfolders of this location are also trusted".',
    '     - Macro Settings: chọn "Enable VBA macros" + tích "Trust access to the VBA project object model".',
    '     - Protected View: bỏ cả 3 dấu tích.   - ActiveX Settings: "Enable all controls without restrictions".',
    '4) File > Options > Add-ins > Manage: Disabled Items > Go: Enable mọi mục MyExcel/QR nếu có.',
    '5) Manage: Excel Add-ins > Go: chỉ để 1 MyExcel trỏ tới C:\MyExcel (bỏ tích bản sao ở nơi khác).',
    '6) Mini Tool > Tạo QR Code: TẮT rồi BẬT lại hàm QR, đóng mở lại Excel.',
    '7) Nếu vẫn lỗi: đóng Excel, xóa cache  del /s /q "%TEMP%\*.exd"  và dọn thư mục %TEMP%.',
    '8) Vẫn lỗi => đặt lại dữ liệu MyExcel của profile (cách đã sửa được lỗi "profile mới chạy, profile cũ không"):',
    '     reg export "HKCU\Software\VB and VBA Program Settings" "%USERPROFILE%\Desktop\MyExcel_data_backup.reg"',
    '     rồi trong regedit xóa các nhánh tên chỉ gồm chữ i/l (vd liliiliiliiiliilli, liliiliiliiiliill) dưới key đó,',
    '     mở Excel, TẮT/BẬT hàm QR và khai báo lại tài khoản ngân hàng.',
    '9) Vẫn lỗi => reset riêng cấu hình Excel của profile (giống profile mới, không cần tạo user mới):',
    '     reg export "HKCU\Software\Microsoft\Office\16.0\Excel" "%USERPROFILE%\Desktop\Excel_backup.reg"',
    '     rồi đổi tên key HKCU\Software\Microsoft\Office\16.0\Excel thành Excel_old (bằng regedit),',
    '     mở Excel và làm lại các bước cài MyExcel (Trust Center + Add-in). Có thể khôi phục bằng file .reg.'
)
foreach ($s in $steps) { Out-Line "  $s" }

# ----------------------------------------------------------------------------
# Mã thoát: 0 kiểm tra xong (kể cả khi có phát hiện), 1 không ghi được báo cáo, 2 chạy sai tài khoản (kết quả không dùng được)
$exitCode = 0
$reason = 'XONG'; $reasonText = 'Đã kiểm tra xong.'
if (@($script:Findings | Where-Object Code -eq 'SAI_TAI_KHOAN').Count -gt 0) {
    $exitCode = 2; $reason = 'SAI_TAI_KHOAN'; $reasonText = 'Chạy sai tài khoản Windows nên kết quả không phải của profile bị lỗi.'
}
$reportPath = $null
try {
    $elapsed = [math]::Round(((Get-Date) - $script:Started).TotalSeconds, 0)
    Out-Line ''
    Out-Line "  (Thời gian kiểm tra: $elapsed giây)" 'DarkGray'
    if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop | Out-Null }
    $reportName = "BaoCao_MyExcel_{0}_{1}_{2}.txt" -f $env:COMPUTERNAME, $safeUser, $stamp
    $reportPath = Join-Path $outDir $reportName
    $utf8Bom = New-Object Text.UTF8Encoding $true
    [IO.File]::WriteAllLines($reportPath, $script:Report.ToArray(), $utf8Bom)
    $deskCopy = $null
    if (-not $env:MYX_OUT) {
        try {
            $deskCopy = Join-Path ([Environment]::GetFolderPath('Desktop')) $reportName
            [IO.File]::WriteAllLines($deskCopy, $script:Report.ToArray(), $utf8Bom)
        } catch { $deskCopy = $null }
    }
    Write-Host ''
    Write-Host (Txt "  Đã lưu báo cáo: $reportPath") -ForegroundColor Cyan
    if ($deskCopy) { Write-Host (Txt "  Bản sao trên Desktop: $deskCopy") -ForegroundColor Cyan }
    Write-Host (Txt '  => Gửi file báo cáo này (của CẢ profile lỗi và profile mới nếu có) cho kỹ thuật.') -ForegroundColor Cyan
    Write-Host '  (Chu tieng Viet tren man hinh bi loi font? Mo file bao cao bang Notepad - file luon dung chinh ta.)' -ForegroundColor DarkGray
    if (-not $env:MYX_NO_NOTEPAD) { Start-Process notepad.exe -ArgumentList "`"$reportPath`"" }
} catch {
    Write-Host (Txt "Không ghi được báo cáo: $($_.Exception.Message)") -ForegroundColor Red
    $exitCode = 1; $reason = 'BAO_CAO_LOI'; $reasonText = "Không ghi được báo cáo: $($_.Exception.Message)"
    $reportPath = $null
}

# Kết quả máy đọc được cho Trạm Tool: mỗi phát hiện có mã ổn định, mức độ, cách sửa
$levelMap = @{ 'LOI' = 'loi'; 'CANHBAO' = 'canh-bao'; 'THONGTIN' = 'thong-tin' }
$result = [ordered]@{
    congCu = 'myexcelfix'; cheDo = 'kiem-tra'; phienBan = $script:Version
    may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
    batDau = $script:Started.ToString('s'); ketThuc = (Get-Date).ToString('s')
    maThoat = $exitCode; trangThai = $(switch ($exitCode) { 0 { 'xong' } 2 { 'thieu-dieu-kien' } default { 'loi' } })
    ma = $reason; thongDiep = $reasonText
    tomTat = [ordered]@{ loi = $nLoi; canhBao = $nWarn; thongTin = ($sorted.Count - $nLoi - $nWarn) }
    phatHien = @($sorted | ForEach-Object { [ordered]@{ ma = $_.Code; mucDo = $levelMap[$_.Level]; tieuDe = $_.Title; cachSua = $_.Fix } })
    baoCao = $reportPath
}
try {
    if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop | Out-Null }
    $jsonPath = Join-Path $outDir ("KetQua_MyExcel_KiemTra_{0}_{1}_{2}.json" -f $env:COMPUTERNAME, $safeUser, $stamp)
    [IO.File]::WriteAllText($jsonPath, ($result | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
    Write-Host (Txt "  Kết quả (JSON): $jsonPath") -ForegroundColor DarkGray
} catch { Write-Host (Txt "  Không ghi được file kết quả JSON: $($_.Exception.Message)") -ForegroundColor DarkGray }
if ($exitCode -eq 2) { Write-Host (Txt '  => Kết quả này KHÔNG dùng được: chạy lại bằng double-click trong đúng profile bị lỗi.') -ForegroundColor Red }
exit $exitCode
