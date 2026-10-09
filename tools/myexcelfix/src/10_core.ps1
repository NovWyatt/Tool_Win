
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
$script:Version  = '__MYX_VERSION__'   # build.ps1 thay bằng version trong tool.json
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
