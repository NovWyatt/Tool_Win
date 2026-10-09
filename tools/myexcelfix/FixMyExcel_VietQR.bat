<# :
@echo off
rem ==========================================================================
rem  MyExcel VietQR - SUA LOI cho profile Windows bi loi (dung cho nhieu may)
rem  Loi: bat/tao VietQR khong duoc, tao profile Windows moi thi lai duoc.
rem  Double-click trong profile BI LOI. Luu va dong Excel truoc.
rem  Script tu tim bo MyExcel chuan, sao luu truoc khi sua, tao file hoan tac.
rem  Ban sao cua file nay ten HoanTac_FixMyExcel.bat trong thu muc sao luu
rem  se tu chay che do HOAN TAC.
rem  Ma thoat: 0 xong, 1 loi, 2 chua sua gi (sai tai khoan, khong dong y,
rem  Excel chua dong, het dau vao...), 3 lam duoc mot phan / VietQR van loi.
rem  Phien ban: 2026.10.1
rem ==========================================================================
chcp 65001 >nul
title MyExcel VietQR - Sua loi (2026.10.1)
set "MYX_SELF=%~f0"
set "MYX_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "MYX_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%MYX_PS%" -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:MYX_SELF,[Text.Encoding]::UTF8); iex $s"
set "MYX_RC=%ERRORLEVEL%"
echo.
if not defined MYX_NOPAUSE pause
exit /b %MYX_RC%
#>

# ============================================================================
#  MyExcel VietQR - sửa lỗi theo profile Windows (dùng cho nhiều máy)
#  Cách đã sửa được: nạp đúng 1 bộ MyExcel chuẩn + đặt lại dữ liệu MyExcel cũ lưu theo user
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
$script:Version    = '2026.10.1'   # build.ps1 thay bằng version trong tool.json
$script:Log        = New-Object System.Collections.Generic.List[string]
$script:Started    = Get-Date
$script:Stamp      = $script:Started.ToString('yyyyMMdd_HHmmss')
$script:Preferred  = if ($env:MYX_PREFERRED) { $env:MYX_PREFERRED.TrimEnd('\') } else { 'C:\MyExcel' }   # thư mục MyExcel khuyên dùng
$script:RegBase    = if ($env:MYX_REGBASE) { $env:MYX_REGBASE.Trim('\') + '\' } else { '' }          # chỉ dùng khi test
$script:Auto       = [bool]$env:MYX_AUTO                                                            # chỉ dùng khi test
$script:QrAnswers  = @(if ($env:MYX_QR_OK) { $env:MYX_QR_OK -split ',' })                           # chỉ dùng khi test
$script:QrAsked    = 0
# Hoàn tác: bản HoanTac_FixMyExcel.bat trong thư mục sao lưu, hoặc HOAN_TAC.bat đặt MYX_UNDO_DIR rồi gọi bản mới nhất
$script:UndoDir    = if ($env:MYX_UNDO_DIR) { $env:MYX_UNDO_DIR.TrimEnd('\') } elseif ((Split-Path $env:MYX_SELF -Leaf) -like 'HoanTac*') { Split-Path $env:MYX_SELF -Parent } else { $null }
$script:UndoMode   = [bool]$script:UndoDir
$script:Changes    = 0
$script:Problems   = 0
$script:Warnings   = New-Object System.Collections.Generic.List[string]
$script:ChangesAtBackup = $null   # số Done lúc sao lưu xong: Done sau mốc này mới là thay đổi thật
$script:StillBroken = $false
$script:ExitCode   = $null       # 0 xong, 1 lỗi, 2 thiếu điều kiện / không đồng ý, 3 làm được một phần
$script:Reason     = ''
$script:ReasonText = ''
$script:KeptFiles  = New-Object System.Collections.Generic.List[string]
$script:EndOfInput = 'MYX_HET_DAU_VAO'
$script:BackupDir  = $null
$script:Target     = $null   # thư mục bộ MyExcel chuẩn được chọn
$script:Installs   = @()     # mọi thư mục có MyExcel.xlam tìm thấy (kể cả bản sao lẻ)
$script:AddinMap   = @{}     # tên file .xlam (chữ thường) -> đường dẫn trong bộ chuẩn
$script:Manifest   = [ordered]@{
    Format = 2; Version = $script:Version
    Time = (Get-Date).ToString('dd/MM/yyyy HH:mm:ss'); User = $env:USERNAME; Computer = $env:COMPUTERNAME
    Target = $null; RegBase = $script:RegBase
    RegExcel = @(); RegVB = $null; NewKeys = @(); ResetKeys = @(); Folders = @(); Workbooks = @()
}

function Say([string]$Text = '', [string]$Color = 'Gray') { Write-Host (Txt $Text) -ForegroundColor $Color; $script:Log.Add($Text) }
function Step([string]$Title) { Say ''; Say ('=' * 74) 'DarkCyan'; Say "  $Title" 'Cyan'; Say ('=' * 74) 'DarkCyan' }
function Done([string]$Text) { Say "  [ĐÃ SỬA]  $Text" 'Green'; $script:Changes++ }
function Skip([string]$Text) { Say "  [BỎ QUA]  $Text" 'DarkGray' }
function Warn([string]$Text) { Say "  [!]       $Text" 'Yellow'; $script:Problems++; $script:Warnings.Add($Text) }
function Set-Result([int]$Code, [string]$Reason, [string]$Text) { $script:ExitCode = $Code; $script:Reason = $Reason; $script:ReasonText = $Text }
function Note([string]$Text) { Say "            $Text" 'Gray' }
function Set-NoDau {
    $script:NoDau = -not $script:NoDau
    $m = '  => Che do KHONG DAU (khong dau tieng Viet tren man hinh): ' + $(if ($script:NoDau) { 'BAT' } else { 'TAT' })
    Write-Host $m -ForegroundColor Yellow
    $script:Log.Add($m)
}
function Show-FontHint {
    if ($script:NoDau) {
        Say '  Man hinh dang o che do KHONG DAU. Go KD roi Enter de bat lai chu co dau.' 'DarkGray'
    } else {
        Write-Host '  Neu dong duoi day bi loi font / hien sai, go  KD  roi Enter de chuyen sang che do khong dau:' -ForegroundColor DarkGray
        Write-Host '  >>> Tiếng Việt đủ dấu: ăn, ộ, ữ, Đ, ế, ợ <<<' -ForegroundColor White
    }
    Say '  (Nhật ký và file .txt luôn ghi tiếng Việt đầy đủ, không bị ảnh hưởng.)' 'DarkGray'
}
function Read-Line([string]$Prompt) {
    # Không có cửa sổ dòng lệnh thật (đầu vào bị chuyển hướng): Read-Host trả về rỗng ngay nên vòng hỏi chạy mãi,
    # ăn 100% CPU. Khi đó đọc thẳng từng dòng; hết dòng thì dừng hẳn (main bắt $script:EndOfInput, mã thoát 2/3).
    $redirected = $false
    try { $redirected = [Console]::IsInputRedirected } catch {}
    if (-not $redirected) { return (Read-Host (Txt $Prompt)) }
    Write-Host ((Txt $Prompt) + ': ') -NoNewline
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { Write-Host ''; throw $script:EndOfInput }
    Write-Host $line
    return $line
}
function Ask([string]$Question) {
    if ($script:Auto) { Say "  $Question (Y/N): Y  [tự động]" 'White'; return $true }
    while ($true) {
        $a = Read-Line "  $Question (Y/N)"
        if ($a -match '^\s*kd') { Set-NoDau; continue }
        if ($a -match '^\s*[YC]') { $script:Log.Add("  $Question => Y"); return $true }
        if ($a -match '^\s*[NK]') { $script:Log.Add("  $Question => N"); return $false }
    }
}
function Choose([string]$Question, [string[]]$Options, [int]$Default = 1) {
    for ($i = 0; $i -lt $Options.Count; $i++) { Say ("    {0}) {1}" -f ($i + 1), $Options[$i]) 'White' }
    if ($script:Auto) { Say "  $Question $Default  [tự động]" 'White'; return $Default }
    while ($true) {
        $a = Read-Line "  $Question (1-$($Options.Count), Enter = $Default)"
        if ($a -match '^\s*$') { $script:Log.Add("  $Question => $Default"); return $Default }
        if ($a -match '^\s*kd') { Set-NoDau; for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host (Txt ("    {0}) {1}" -f ($i + 1), $Options[$i])) -ForegroundColor White }; continue }
        if ($a -match '^\s*(\d+)\s*$') {
            $n = [int]$Matches[1]
            if ($n -ge 1 -and $n -le $Options.Count) { $script:Log.Add("  $Question => $n"); return $n }
        }
    }
}
function Test-QrWorks([string]$Question) {
    if ($script:Auto) {
        $i = [Math]::Min($script:QrAsked, [Math]::Max(0, $script:QrAnswers.Count - 1))
        $ok = -not ($script:QrAnswers.Count -gt 0 -and $script:QrAnswers[$i] -eq '0')
        $script:QrAsked++
        Say ("  {0} (Y/N): {1}  [tự động]" -f $Question, $(if ($ok) { 'Y' } else { 'N' })) 'White'
        return $ok
    }
    return (Ask $Question)
}
function Test-SamePath([string]$A, [string]$B) {
    if (-not $A -or -not $B) { return $false }
    return (($A -replace '/', '\').TrimEnd('\') -ieq ($B -replace '/', '\').TrimEnd('\'))
}
function Test-UnderPath([string]$Child, [string]$Parent) {
    if (-not $Child -or -not $Parent) { return $false }
    $c = ($Child -replace '/', '\').TrimEnd('\').ToLowerInvariant() + '\'
    $p = ($Parent -replace '/', '\').TrimEnd('\').ToLowerInvariant() + '\'
    return $c.StartsWith($p)
}
function Get-OpenPath([string]$Raw) { return ($Raw -replace '^\s*(/[A-Za-z]\s+)+', '').Trim().Trim('"') }
function Get-OpenFlags([string]$Raw) { if ($Raw -match '^\s*((?:/[A-Za-z]\s+)+)') { return $Matches[1] }; return '' }
function Open-UserKey([string]$Sub, [bool]$Write = $false) {
    return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:RegBase + $Sub, $Write)
}
function Get-ExcelVersions {
    $k = Open-UserKey 'Software\Microsoft\Office'
    if (-not $k) { return @() }
    $vers = @($k.GetSubKeyNames() | Where-Object { $_ -match '^\d+\.0$' -and $k.OpenSubKey("$_\Excel") })
    $k.Close()
    return $vers
}
function Get-ExcelMainVersion {
    try {
        $exe = (Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe').GetValue('')
        if ($exe -and (Test-Path -LiteralPath $exe)) { return ('{0}.0' -f (Get-Item -LiteralPath $exe).VersionInfo.FileMajorPart) }
    } catch {}
    return '16.0'
}
function Get-MyExcelStateKeys {
    # MyExcel lưu SaveSetting dưới các tên bị làm rối chỉ gồm chữ i/l (liliiliiliiiliilli, liliiliiliiiliill, ...)
    $vb = Open-UserKey 'Software\VB and VBA Program Settings'
    if (-not $vb) { return @() }
    $names = @($vb.GetSubKeyNames() | Where-Object { $_ -cmatch '^[il]{12,}[a-z0-9]*$' } | Sort-Object Length)
    $vb.Close()
    return $names
}
function Get-MyExcelDataDate {
    # Ngày phiên bản MyExcel đã tạo dữ liệu của profile (InVung\AndanInNgayCai, vd 30.5.2025)
    foreach ($n in (Get-MyExcelStateKeys)) {
        $k = Open-UserKey "Software\VB and VBA Program Settings\$n\InVung"
        if (-not $k) { continue }
        $v = [string]$k.GetValue('AndanInNgayCai'); $k.Close()
        $d = [datetime]::MinValue
        if ($v -and [datetime]::TryParseExact($v.Trim(), [string[]]@('d.M.yyyy', 'd/M/yyyy', 'd-M-yyyy'), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    }
    return $null
}
function Test-RightUser {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $sid = (Get-Process -Id $PID).SessionId
    $exp = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sid } | Select-Object -First 1
    if ($exp) {
        $o = Invoke-CimMethod -InputObject $exp -MethodName GetOwner -ErrorAction SilentlyContinue
        if ($o -and $o.ReturnValue -eq 0 -and "$($o.Domain)\$($o.User)" -ine $me) {
            Warn "Script đang chạy bằng '$me' nhưng màn hình là của '$($o.Domain)\$($o.User)'. Hãy double-click file .bat trong đúng profile bị lỗi."
            return $false
        }
    }
    return $true
}
function Wait-ExcelClosed {
    $mySid = (Get-Process -Id $PID).SessionId
    while ($true) {
        $all = @(Get-Process -Name 'EXCEL' -ErrorAction SilentlyContinue)
        $mine = @($all | Where-Object { $_.SessionId -eq $mySid })
        if ($mine.Count -eq 0) {
            if ($all.Count -gt 0) { Note "Có Excel đang mở ở profile khác ($($all.Count) tiến trình) - nên đóng nếu profile đó dùng chung bộ MyExcel." }
            return $true
        }
        Say "  Excel đang mở trong profile này ($($mine.Count) tiến trình). Hãy LƯU và ĐÓNG hết Excel." 'Yellow'
        if ($script:Auto) { return $false }
        $a = Read-Line '  Nhấn Enter khi đã đóng Excel (gõ Q để thoát)'
        if ($a -match '^\s*[Qq]') { return $false }
    }
}
function Save-Manifest {
    if (-not $script:BackupDir) { return }
    $json = $script:Manifest | ConvertTo-Json -Depth 5
    # Ghi ra file tạm rồi thay: cửa sổ bị đóng giữa chừng không để lại manifest.json dở dang
    $path = Join-Path $script:BackupDir 'manifest.json'
    $tmp = "$path.tmp"
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding $false))
    if (-not (Test-Path -LiteralPath $path)) { [IO.File]::Move($tmp, $path); return }
    try { [IO.File]::Replace($tmp, $path, $null) } catch { [IO.File]::Copy($tmp, $path, $true); [IO.File]::Delete($tmp) }   # ổ mạng/FAT không hỗ trợ Replace
}
function Get-Sha256([string]$Path) {
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash } catch { return $null }
}
function Get-ResultDir {
    if ($env:MYX_OUT) { return $env:MYX_OUT }
    return (Join-Path $env:PUBLIC 'Documents\MyExcelCheck')
}
function Save-ResultJson([string]$LogPath) {
    # Kết quả máy đọc được cho Trạm Tool: trạng thái, mã lý do ổn định, cảnh báo, nơi sao lưu
    $mode = if ($script:UndoMode) { 'hoan-tac' } else { 'sua' }
    $state = switch ($script:ExitCode) { 0 { 'xong' } 2 { 'thieu-dieu-kien' } 3 { 'mot-phan' } default { 'loi' } }
    $real = if ($null -ne $script:ChangesAtBackup) { $script:Changes - $script:ChangesAtBackup } else { 0 }
    $r = [ordered]@{
        congCu = 'myexcelfix'; cheDo = $mode; phienBan = $script:Version
        may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
        batDau = $script:Started.ToString('s'); ketThuc = (Get-Date).ToString('s')
        maThoat = $script:ExitCode; trangThai = $state; ma = $script:Reason; thongDiep = $script:ReasonText
        soThayDoi = $real; soCanhBao = $script:Problems; canhBao = @($script:Warnings)
        giuLai = @($script:KeptFiles)
        thuMucSaoLuu = $(if ($script:UndoMode) { $script:UndoDir } else { $script:BackupDir })
        nhatKy = $LogPath
    }
    $name = 'KetQua_MyExcel_{0}_{1}_{2}_{3}.json' -f $(if ($script:UndoMode) { 'HoanTac' } else { 'Sua' }), $env:COMPUTERNAME, ($env:USERNAME -replace '[^\w\.-]', '_'), $script:Stamp
    try {
        $dir = Get-ResultDir
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
        $path = Join-Path $dir $name
        [IO.File]::WriteAllText($path, ($r | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
        Say "  Kết quả (JSON): $path" 'DarkGray'
    } catch { Say "  Không ghi được file kết quả JSON: $($_.Exception.Message)" 'DarkGray' }
}

# ----------------------------------------------------------------------------
function Invoke-Backup {
    Step 'BƯỚC 2 - SAO LƯU (registry + file hoàn tác)'
    $root = if ($env:MYX_OUT) { $env:MYX_OUT } else { [Environment]::GetFolderPath('Desktop') }
    $script:BackupDir = Join-Path $root "MyExcelFix_SaoLuu_$($script:Stamp)"
    try {
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    } catch {
        Warn "Không tạo được thư mục sao lưu $($script:BackupDir): $($_.Exception.Message)"
        return $false
    }
    Note "Thư mục sao lưu: $($script:BackupDir)"

    $regRoot = 'HKCU\' + $script:RegBase
    foreach ($ver in (Get-ExcelVersions)) {
        $file = "Excel_$ver.reg"
        & reg.exe export "$($regRoot)Software\Microsoft\Office\$ver\Excel" (Join-Path $script:BackupDir $file) /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Warn "Không sao lưu được HKCU\...\Office\$ver\Excel (mã lỗi $LASTEXITCODE)"; return $false }
        $script:Manifest.RegExcel += [ordered]@{ Ver = $ver; File = $file }
        Done "Đã sao lưu cấu hình Excel $ver -> $file"
    }
    if (Open-UserKey 'Software\VB and VBA Program Settings') {
        & reg.exe export "$($regRoot)Software\VB and VBA Program Settings" (Join-Path $script:BackupDir 'VBA_Settings.reg') /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Warn "Không sao lưu được dữ liệu MyExcel trong VB and VBA Program Settings (mã lỗi $LASTEXITCODE)"; return $false }
        $script:Manifest.RegVB = 'VBA_Settings.reg'
        Done 'Đã sao lưu dữ liệu MyExcel (VB and VBA Program Settings) -> VBA_Settings.reg'
    }
    try {
        Copy-Item -LiteralPath $env:MYX_SELF -Destination (Join-Path $script:BackupDir 'HoanTac_FixMyExcel.bat') -Force -ErrorAction Stop
        Done 'Đã tạo file hoàn tác HoanTac_FixMyExcel.bat trong thư mục sao lưu'
    } catch {
        Warn "Không tạo được file hoàn tác: $($_.Exception.Message)"
        return $false
    }
    Save-Manifest
    return $true
}

# ----------------------------------------------------------------------------
function Get-OtherProfiles {
    $names = @()
    foreach ($p in (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue)) {
        if ($p.PSChildName -notmatch '^S-1-5-21-') { continue }
        $path = [Environment]::ExpandEnvironmentVariables([string]$p.GetValue('ProfileImagePath'))
        if ($path -and -not (Test-SamePath $path $env:USERPROFILE)) { $names += (Split-Path $path -Leaf) }
    }
    return $names
}

function Find-MyExcelInstalls {
    # Mọi thư mục có MyExcel.xlam: X:\MyExcel* ở gốc ổ đĩa + nơi Excel/MyExcel của profile này đang trỏ tới
    $cands = New-Object System.Collections.Generic.List[object]
    $openMain = @()
    $scan = if ($env:MYX_CANDIDATES) { @($env:MYX_CANDIDATES -split ';') } else {   # MYX_CANDIDATES chỉ dùng khi test
        @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | ForEach-Object {
            Get-ChildItem -LiteralPath "$($_.DeviceID)\" -Directory -Filter 'MyExcel*' -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
        })
    }
    foreach ($d in $scan) {
        if ($d -and $d.TrimEnd('\') -notmatch '(?i)_cu(_\d{8}_\d{6})?$') { $cands.Add(@($d, $true)) }   # bỏ qua thư mục đã cất (_cu)
    }
    foreach ($ver in (Get-ExcelVersions)) {
        $k = Open-UserKey "Software\Microsoft\Office\$ver\Excel\Options"
        if ($k) {
            foreach ($n in @($k.GetValueNames() | Where-Object { $_ -match '^OPEN\d*$' })) {
                $p = Get-OpenPath ([string]$k.GetValue($n))
                if ($p -and (Split-Path $p -Leaf) -ieq 'MyExcel.xlam') { $openMain += $p; $cands.Add(@((Split-Path $p -Parent), $false)) }
            }
            $k.Close()
        }
        $am = Open-UserKey "Software\Microsoft\Office\$ver\Excel\Add-in Manager"
        if ($am) {
            foreach ($n in $am.GetValueNames()) { if ($n -and (Split-Path $n -Leaf) -ieq 'MyExcel.xlam') { $cands.Add(@((Split-Path $n -Parent), $false)) } }
            $am.Close()
        }
    }
    foreach ($s in (Get-MyExcelStateKeys)) {
        $stack = New-Object System.Collections.Stack
        $root = Open-UserKey "Software\VB and VBA Program Settings\$s"
        if ($root) { $stack.Push($root) }
        while ($stack.Count -gt 0) {
            $key = $stack.Pop()
            $dd = ([string]$key.GetValue('DuongDanADDin')).TrimEnd('\')
            if ($dd) { $cands.Add(@($dd, $false)); $cands.Add(@((Split-Path $dd -Parent), $false)) }
            foreach ($sn in $key.GetSubKeyNames()) { $sk = $key.OpenSubKey($sn); if ($sk) { $stack.Push($sk) } }
            $key.Close()
        }
    }
    $found = [ordered]@{}
    foreach ($c in $cands) {
        $dir = ([string]$c[0]).TrimEnd('\')
        if (-not $dir -or -not (Test-Path -LiteralPath (Join-Path $dir 'MyExcel.xlam') -PathType Leaf)) { continue }
        $key = $dir.ToLowerInvariant()
        if ($found.Contains($key)) { if ($c[1]) { $found[$key].Scanned = $true }; continue }
        $mini = Join-Path $dir 'MiniTool'
        $found[$key] = [pscustomobject]@{
            Path      = $dir
            Scanned   = [bool]$c[1]
            Date      = (Get-Item -LiteralPath (Join-Path $dir 'MyExcel.xlam') -Force).LastWriteTime
            IsInstall = (Test-Path -LiteralPath $mini -PathType Container)
            HasQr     = [bool](Get-ChildItem -LiteralPath $mini -Filter '*qr*.xlam' -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
            Loaded    = [bool]($openMain | Where-Object { Test-SamePath (Split-Path $_ -Parent) $dir })
        }
    }
    return @($found.Values)
}

function Select-MyExcelTarget {
    Step 'BƯỚC 1 - TÌM BỘ MYEXCEL CHUẨN TRÊN MÁY'
    $script:Installs = @(Find-MyExcelInstalls)
    if ($script:Installs.Count -eq 0) {
        Warn "Không thấy MyExcel.xlam ở $($script:Preferred) hay nơi nào khác. Tải bộ cài ở https://myexcel.vn/download/, giải nén vào $($script:Preferred) rồi chạy lại."
        return $false
    }
    foreach ($i in $script:Installs) {
        $tags = @("MyExcel.xlam ngày $($i.Date.ToString('dd/MM/yyyy'))")
        $tags += $(if ($i.HasQr) { 'có file QR' } elseif ($i.IsInstall) { 'THIẾU file QR trong MiniTool' } elseif ($i.Scanned) { 'THIẾU thư mục MiniTool' } else { 'bản sao lẻ, không có MiniTool' })
        if ($i.Loaded) { $tags += 'profile này đang nạp' }
        Note ('{0}  ({1})' -f $i.Path, ($tags -join ', '))
    }
    $valid = @($script:Installs | Where-Object HasQr)
    if ($valid.Count -eq 0) {
        Warn "Không bộ nào có đủ file QR (MiniTool\QRCodeLib.xlam...). Cài lại MyExcel vào $($script:Preferred) theo https://myexcel.vn/download/ rồi chạy lại."
        return $false
    }
    # Ưu tiên: đúng thư mục khuyên dùng > bộ profile đang nạp > bộ mới nhất
    $pick = @(@($valid | Where-Object { Test-SamePath $_.Path $script:Preferred }) + @($valid | Where-Object Loaded) + @($valid | Sort-Object Date -Descending))[0]
    if ($valid.Count -gt 1) {
        $opts = @($valid | ForEach-Object { '{0}  (ngày {1}){2}' -f $_.Path, $_.Date.ToString('dd/MM/yyyy'), $(if ($_ -eq $pick) { '  <- khuyên dùng' } else { '' }) })
        $pick = $valid[(Choose 'Chọn bộ MyExcel chuẩn cho profile này' $opts ([Array]::IndexOf($valid, $pick) + 1)) - 1]
    }
    $newest = @($valid | Sort-Object Date -Descending)[0]
    if (($newest.Date - $pick.Date).TotalDays -gt 7) {
        Warn ('Bộ đã chọn ({0}, ngày {1}) cũ hơn bộ {2} (ngày {3}) - nên cài bản mới vào {0}.' -f $pick.Path, $pick.Date.ToString('dd/MM/yyyy'), $newest.Path, $newest.Date.ToString('dd/MM/yyyy'))
    }
    if (-not (Test-SamePath $pick.Path $script:Preferred)) {
        Note "MyExcel khuyên cài đúng $($script:Preferred), nếu không file tạo từ máy khác dễ lỗi #NAME."
    }
    $script:Target = $pick.Path
    $script:Manifest.Target = $pick.Path
    $script:AddinMap = @{}
    $files = @(Get-ChildItem -LiteralPath $pick.Path -Filter '*.xlam' -File -Force -ErrorAction SilentlyContinue) +
             @(Get-ChildItem -LiteralPath (Join-Path $pick.Path 'MiniTool') -Filter '*.xlam' -File -Force -ErrorAction SilentlyContinue)
    foreach ($f in $files) { $l = $f.Name.ToLowerInvariant(); if (-not $script:AddinMap.ContainsKey($l)) { $script:AddinMap[$l] = $f.FullName } }
    Say "  Bộ MyExcel chuẩn: $($pick.Path)" 'Green'
    return $true
}

function Get-OtherInstalls { return @($script:Installs | Where-Object { -not (Test-SamePath $_.Path $script:Target) }) }

function Resolve-AddinPath([string]$Path) {
    # Đường dẫn mới trong bộ chuẩn; '' = nên bỏ; $null = giữ nguyên
    if (-not $Path -or -not $script:Target) { return $null }
    $leaf = (Split-Path $Path -Leaf).ToLowerInvariant()
    foreach ($i in (Get-OtherInstalls)) {
        if (-not $i.IsInstall -or -not (Test-UnderPath $Path $i.Path)) { continue }
        $alt = Join-Path $script:Target ($Path.Substring($i.Path.Length).TrimStart('\', '/'))
        if (Test-Path -LiteralPath $alt) { return $alt }
        if ($script:AddinMap.ContainsKey($leaf)) { return $script:AddinMap[$leaf] }
        return ''
    }
    # Bản sao lẻ / file từ máy khác: chỉ trỏ lại add-in của MyExcel (MyExcel*.xlam, *QR*.xlam), không đụng add-in khác
    if ($leaf -match '^myexcel.*\.xlam$|qr.*\.xlam$' -and $script:AddinMap.ContainsKey($leaf) -and -not (Test-UnderPath $Path $script:Target)) {
        return $script:AddinMap[$leaf]
    }
    return $null
}

# ----------------------------------------------------------------------------
function Invoke-FolderFix {
    Step 'BƯỚC 3 - CẤT BỘ CÀI MYEXCEL THỪA (đổi tên, không xóa)'
    $extra = @(Get-OtherInstalls | Where-Object { $_.Scanned -and $_.IsInstall })
    if ($extra.Count -eq 0) { Skip 'Không có bộ cài MyExcel thừa ở gốc ổ đĩa'; return }
    $others = @(Get-OtherProfiles)
    if ($others.Count -gt 0) {
        Note ('Máy còn các profile: {0}. Profile nào đang dùng bộ bị cất thì chạy file sửa này ở profile đó để trỏ về bộ chuẩn.' -f ($others -join ', '))
    }
    foreach ($i in $extra) {
        if (-not (Ask "Đổi tên $($i.Path) thành $($i.Path)_cu?")) { Skip "Giữ nguyên $($i.Path)"; continue }
        $to = "$($i.Path)_cu"
        if (Test-Path -LiteralPath $to) { $to = "$($i.Path)_cu_$($script:Stamp)" }
        try {
            Rename-Item -LiteralPath $i.Path -NewName (Split-Path $to -Leaf) -ErrorAction Stop
            $script:Manifest.Folders += [ordered]@{ From = $i.Path; To = $to }
            Save-Manifest
            Done "Đổi tên $($i.Path) -> $to"
        } catch {
            Warn "Không đổi tên được $($i.Path): $($_.Exception.Message)"
            Note 'Đóng mọi cửa sổ/ứng dụng đang mở file trong thư mục đó. Các bước còn lại vẫn được thực hiện.'
        }
    }
}

function Invoke-AddinFix {
    Step 'BƯỚC 4 - NẠP MYEXCEL TỪ BỘ CHUẨN (Excel Add-ins, Trusted Locations, Disabled Items)'
    $mainVer = Get-ExcelMainVersion
    $mainPath = Join-Path $script:Target 'MyExcel.xlam'
    $vers = @(Get-ExcelVersions)
    if ($vers -notcontains $mainVer) { $vers += $mainVer }
    foreach ($ver in $vers) {
        $k = Open-UserKey "Software\Microsoft\Office\$ver\Excel\Options" $true
        if (-not $k -and $ver -eq $mainVer) {
            if (-not (Open-UserKey "Software\Microsoft\Office\$ver\Excel")) {
                $script:Manifest.NewKeys += "Software\Microsoft\Office\$ver\Excel"   # profile chưa từng mở Excel
                Save-Manifest
            }
            $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:RegBase + "Software\Microsoft\Office\$ver\Excel\Options")
        }
        if (-not $k) { continue }
        $entries = @($k.GetValueNames() | Where-Object { $_ -match '^OPEN(\d*)$' } | ForEach-Object {
            $idx = if ($_ -eq 'OPEN') { 0 } else { [int]$_.Substring(4) }
            [pscustomobject]@{ Name = $_; Index = $idx; Value = [string]$k.GetValue($_) }
        } | Sort-Object Index)
        $new = New-Object System.Collections.Generic.List[string]
        $seen = New-Object System.Collections.Generic.HashSet[string]
        $hasMain = $false
        foreach ($e in $entries) {
            $p = Get-OpenPath $e.Value
            $res = Resolve-AddinPath $p
            if ($null -eq $res) { $val = $e.Value; $path = $p }
            elseif ($res -eq '') { continue }
            else { $val = (Get-OpenFlags $e.Value) + '"' + $res + '"'; $path = $res }
            if ($path -and -not $seen.Add($path.ToLowerInvariant())) { continue }   # bỏ mục trùng
            if (Test-SamePath $path $mainPath) { $hasMain = $true }
            $new.Add($val)
        }
        if (-not $hasMain -and $ver -eq $mainVer) { $new.Insert(0, '"' + $mainPath + '"') }
        $old = @($entries | ForEach-Object { $_.Value })
        if (($old -join '|') -ceq ($new -join '|')) {
            Skip ('Excel {0} - danh sách add-in đã đúng: {1}' -f $ver, $(if ($old.Count) { $old -join ' ; ' } else { 'không có' }))
        } else {
            foreach ($e in $entries) { $k.DeleteValue($e.Name, $false) }
            for ($i = 0; $i -lt $new.Count; $i++) {
                $n = if ($i -eq 0) { 'OPEN' } else { "OPEN$i" }
                $k.SetValue($n, $new[$i], [Microsoft.Win32.RegistryValueKind]::String)
            }
            Done ('Excel {0} - add-in đang bật: {1}   (trước đây: {2})' -f $ver, ($new -join ' ; '), $(if ($old.Count) { $old -join ' ; ' } else { 'không có' }))
        }
        $k.Close()

        $am = Open-UserKey "Software\Microsoft\Office\$ver\Excel\Add-in Manager" $true
        if ($am) {
            foreach ($n in $am.GetValueNames()) {
                if (-not $n) { continue }
                $res = Resolve-AddinPath $n
                if ($null -ne $res -and -not (Test-SamePath $res $n)) {
                    $am.DeleteValue($n, $false)
                    Done "Excel $ver - xóa mục cũ khỏi hộp thoại Add-ins: $n"
                }
            }
            $am.Close()
        }
        if ($ver -eq $mainVer) { Set-TrustedLocation $ver }
        Clear-DisabledItems $ver
    }
}

# ----------------------------------------------------------------------------
function Set-TrustedLocation([string]$Ver) {
    $sub = $script:RegBase + "Software\Microsoft\Office\$Ver\Excel\Security\Trusted Locations"
    $tl = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($sub)
    if ($tl.GetValue('AllLocationsDisabled') -eq 1) {
        $tl.SetValue('AllLocationsDisabled', 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        Done 'Bỏ tích "Disable all Trusted Locations"'
    }
    $found = $null; $max = -1
    foreach ($s in $tl.GetSubKeyNames()) {
        if ($s -match '^Location(\d+)$') { $max = [Math]::Max($max, [int]$Matches[1]) }
        $lk = $tl.OpenSubKey($s, $true)
        $p = [Environment]::ExpandEnvironmentVariables([string]$lk.GetValue('Path'))
        if (-not $found -and (Test-SamePath $p $script:Target)) { $found = $lk } else { $lk.Close() }
    }
    if ($found) {
        if ($found.GetValue('AllowSubfolders') -ne 1) {
            $found.SetValue('AllowSubfolders', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
            Done "Trusted Location $($script:Target): tích thêm 'Subfolders of this location are also trusted'"
        } else {
            Skip "Trusted Location $($script:Target)\ (có thư mục con) đã có sẵn"
        }
        $found.Close()
    } else {
        $nk = $tl.CreateSubKey("Location$($max + 1)")
        $nk.SetValue('Path', $script:Target + '\', [Microsoft.Win32.RegistryValueKind]::String)
        $nk.SetValue('AllowSubfolders', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
        $nk.SetValue('Description', 'MyExcel', [Microsoft.Win32.RegistryValueKind]::String)
        $nk.SetValue('Date', (Get-Date).ToString('M/d/yyyy h:mm tt', [Globalization.CultureInfo]::InvariantCulture), [Microsoft.Win32.RegistryValueKind]::String)
        $nk.Close()
        $script:Manifest.NewKeys += "Software\Microsoft\Office\$Ver\Excel\Security\Trusted Locations\Location$($max + 1)"
        Save-Manifest
        Done "Thêm Trusted Location $($script:Target)\ (có thư mục con)"
    }
    $tl.Close()
}

function Clear-DisabledItems([string]$Ver) {
    $dk = Open-UserKey "Software\Microsoft\Office\$Ver\Excel\Resiliency\DisabledItems" $true
    if (-not $dk) { return }
    foreach ($n in $dk.GetValueNames()) {
        $v = $dk.GetValue($n)
        $txt = ''
        if ($v -is [byte[]] -and $v.Length -gt 12) { $txt = [Text.Encoding]::Unicode.GetString($v, 12, $v.Length - 12) -replace '[\x00-\x1F]+', ' ' }
        if ($txt -match '(?i)myexcel|qr.?code|vietqr|minitool') {
            $dk.DeleteValue($n, $false)
            Done "Excel $Ver - bật lại add-in bị vô hiệu hóa: $($txt.Trim())"
        }
    }
    $dk.Close()
}

# ----------------------------------------------------------------------------
function Invoke-VbaPathFix {
    Step 'BƯỚC 5 - SỬA ĐƯỜNG DẪN MYEXCEL TỰ GHI NHỚ (DuongDanADDin...)'
    $names = @(Get-MyExcelStateKeys)
    if ($names.Count -eq 0) { Skip 'Profile này chưa có dữ liệu MyExcel'; return }
    $others = @(Get-OtherInstalls | ForEach-Object { $_.Path } | Sort-Object Length -Descending)
    if ($others.Count -eq 0) { Skip 'Không có thư mục MyExcel nào khác để trỏ lại'; return }
    $good = $script:Target
    $count = 0
    foreach ($name in $names) {
        $root = Open-UserKey "Software\VB and VBA Program Settings\$name" $true
        if (-not $root) { continue }
        $stack = New-Object System.Collections.Stack
        $stack.Push(@($root, $name))
        while ($stack.Count -gt 0) {
            $item = $stack.Pop(); $key = $item[0]; $path = $item[1]
            foreach ($vn in $key.GetValueNames()) {
                $kind = $key.GetValueKind($vn)
                if ($kind -ne [Microsoft.Win32.RegistryValueKind]::String -and $kind -ne [Microsoft.Win32.RegistryValueKind]::ExpandString) { continue }
                $val = [string]$key.GetValue($vn, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if (Test-UnderPath $val $good) { continue }   # đã trỏ đúng bộ chuẩn
                $newVal = $val
                foreach ($o in $others) {
                    $rx = '(?i)' + [regex]::Escape($o) + '(?=[\\/]|$)'
                    $newVal = [regex]::Replace($newVal, $rx, [Text.RegularExpressions.MatchEvaluator] { param($m) $good })
                }
                if ($newVal -ceq $val) { continue }
                $key.SetValue($vn, $newVal, $kind)
                $count++
                Done ('{0}\{1}: {2} -> {3}' -f $path, $vn, $val, $newVal)
            }
            foreach ($sn in $key.GetSubKeyNames()) {
                $sk = $key.OpenSubKey($sn, $true)
                if ($sk) { $stack.Push(@($sk, "$path\$sn")) }
            }
            $key.Close()
        }
    }
    if ($count -eq 0) { Skip 'Dữ liệu MyExcel không còn trỏ tới thư mục MyExcel khác' }
}

function Invoke-CacheCleanup {
    Step 'BƯỚC 6 - DỌN CACHE ACTIVEX (.exd) VÀ FILE KHÓA CŨ'
    $dirs = @("$env:TEMP\VBE", "$env:TEMP\Excel8.0", "$env:TEMP\Word8.0", "$env:APPDATA\Microsoft\Forms")
    $n = 0
    foreach ($d in ($dirs | Sort-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $d -Filter '*.exd' -File -Force -ErrorAction SilentlyContinue)) {
            try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $n++ }
            catch { Warn "Không xóa được $($f.FullName) (Word/Excel còn mở?)" }
        }
    }
    if ($n -gt 0) { Done "Xóa $n file cache .exd (Office sẽ tự tạo lại)" } else { Skip 'Không có file .exd' }
    foreach ($f in (Get-ChildItem -LiteralPath $script:Target -Recurse -Depth 1 -Filter '~$*' -File -Force -ErrorAction SilentlyContinue)) {
        if ($f.Length -lt 1KB) {
            try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; Done "Xóa file khóa cũ $($f.FullName)" }
            catch { Warn "Không xóa được file khóa $($f.FullName)" }
        }
    }
}

function Invoke-Unblock {
    Step "BƯỚC 7 - BỎ CHẶN (Unblock) CÁC FILE TRONG $($script:Target)"
    $files = @(Get-ChildItem -LiteralPath $script:Target -Recurse -File -Force -ErrorAction SilentlyContinue)
    $done = 0; $fail = 0
    foreach ($f in $files) {
        if (-not (Get-Item -LiteralPath $f.FullName -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue)) { continue }
        try { Unblock-File -LiteralPath $f.FullName -ErrorAction Stop; $done++ } catch { $fail++ }
    }
    if ($done -gt 0) { Done "Bỏ chặn $done / $($files.Count) file" } else { Skip "Không có file nào bị chặn trong $($files.Count) file" }
    if ($fail -gt 0) { Warn "$fail file không bỏ chặn được (thiếu quyền ghi?)" }
}

# ----------------------------------------------------------------------------
function Get-ScanRoots {
    if ($env:MYX_SCANROOT) { return @($env:MYX_SCANROOT) }
    $cand = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'))
    try { $cand += (Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders').GetValue('{374DE290-123F-4565-9164-39C4925E467B}') } catch {}
    foreach ($a in (Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue)) {
        $uf = $a.GetValue('UserFolder')
        if ($uf) { $cand += [Environment]::ExpandEnvironmentVariables([string]$uf) }
    }
    $roots = @()
    foreach ($c in ($cand | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object Length)) {
        if (-not ($roots | Where-Object { Test-UnderPath $c $_ })) { $roots += $c }
    }
    return $roots
}

function Resolve-LinkTarget([string]$Target, [string]$WbDir) {
    # Target của liên kết ngoài (file:///C:\..., /Thu/Muc/..., ../../...) -> đường dẫn tuyệt đối
    $t = $Target -replace '^(?i)file:/*', ''
    try { $t = [Uri]::UnescapeDataString($t) } catch {}
    $t = $t -replace '/', '\'
    $abs = if ($t -match '^[A-Za-z]:\\' -or $t -match '^\\\\') { $t }
           elseif ($t -match '^\\') { try { (Split-Path $WbDir -Qualifier -ErrorAction Stop) + $t } catch { $t } }
           else { Join-Path $WbDir $t }
    try { return [IO.Path]::GetFullPath($abs) } catch { return $abs }
}

function Get-NewLinkTarget([string]$Target, [string]$WbDir) {
    # '' = giữ nguyên; ngược lại là Target mới trỏ tới bộ chuẩn
    $abs = Resolve-LinkTarget $Target $WbDir
    $res = Resolve-AddinPath $abs
    if (-not $res -or (Test-SamePath $res $abs)) { return '' }
    return 'file:///' + $res
}

function Get-LinkChanges([string]$Path) {
    $hits = @()
    $wbDir = Split-Path $Path -Parent
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($Path)
        try {
            foreach ($e in $zip.Entries) {
                if ($e.FullName -notmatch '^xl/externalLinks/_rels/[^/]+\.rels$') { continue }
                $sr = New-Object IO.StreamReader($e.Open())
                $txt = $sr.ReadToEnd(); $sr.Close()
                foreach ($m in [regex]::Matches($txt, 'Target="([^"]*)"')) {
                    if (Get-NewLinkTarget ([Net.WebUtility]::HtmlDecode($m.Groups[1].Value)) $wbDir) { $hits += $e.FullName; break }
                }
            }
        } finally { $zip.Dispose() }
    } catch {}
    return ,$hits
}

function Update-LinkedEntries([string]$Path, [string[]]$Entries) {
    $wbDir = Split-Path $Path -Parent
    $utf8 = New-Object Text.UTF8Encoding $false
    $evaluator = [Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $new = Get-NewLinkTarget ([Net.WebUtility]::HtmlDecode($m.Groups[1].Value)) $wbDir
        if ($new) { 'Target="' + [Security.SecurityElement]::Escape($new) + '"' } else { $m.Value }
    }
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Update)
        try {
            foreach ($name in $Entries) {
                $entry = $za.GetEntry($name)
                if (-not $entry) { continue }
                $s = $entry.Open()
                try {
                    $sr = New-Object IO.StreamReader($s, $utf8, $true, 4096, $true)
                    $txt = $sr.ReadToEnd(); $sr.Dispose()
                    $bytes = $utf8.GetBytes([regex]::Replace($txt, 'Target="([^"]*)"', $evaluator))
                    $s.SetLength(0); $s.Position = 0
                    $s.Write($bytes, 0, $bytes.Length)
                } finally { $s.Dispose() }
            }
        } finally { $za.Dispose() }
    } finally { $fs.Dispose() }
}

function Invoke-WorkbookRelink {
    Step 'BƯỚC 8 - NỐI LẠI FILE EXCEL CÒN LIÊN KẾT TỚI MYEXCEL Ở CHỖ KHÁC'
    try { Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem -ErrorAction Stop }
    catch { Warn "Không nạp được thư viện ZIP: $($_.Exception.Message)"; return }
    $roots = @(Get-ScanRoots)
    Note ('Đang quét: {0}' -f ($roots -join ' ; '))
    # .xls dạng cũ chỉ tìm được theo tên thư mục cài khác (BIFF lưu dấu \ thành ký tự 0x03)
    $needles = @(Get-OtherInstalls | Where-Object IsInstall | ForEach-Object { $l = Split-Path $_.Path -Leaf; "$l\"; "$l/"; "$l$([char]3)" })
    $ooxml = @(); $binary = @(); $cloud = 0
    foreach ($r in $roots) {
        $files = Get-ChildItem -LiteralPath $r -Recurse -Depth 5 -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(xlsx|xlsm|xltx|xltm|xlsb|xls)$' -and $_.Name -notlike '~$*' -and $_.Length -lt 60MB }
        foreach ($f in $files) {
            if (([int]$f.Attributes -band 0x401000) -ne 0) { $cloud++; continue }   # OneDrive "chỉ có trên mạng": đọc vào sẽ tải cả file về
            if ($f.Extension -ieq '.xls') {
                if ($needles.Count -eq 0 -or $f.Length -ge 15MB) { continue }
                try {
                    $bytes = [IO.File]::ReadAllBytes($f.FullName)
                    $a = [Text.Encoding]::ASCII.GetString($bytes); $u = [Text.Encoding]::Unicode.GetString($bytes)
                    if (@($needles | Where-Object { $a.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or $u.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0) { $binary += $f }
                } catch {}
            } else {
                $entries = Get-LinkChanges $f.FullName
                if ($entries.Count -gt 0) { $ooxml += [pscustomobject]@{ File = $f; Entries = $entries } }
            }
        }
    }
    if ($cloud -gt 0) { Note "Bỏ qua $cloud file OneDrive chưa tải về máy. File nào báo lỗi liên kết thì sửa bằng Data > Edit Links > Change Source." }
    if ($ooxml.Count -eq 0 -and $binary.Count -eq 0) { Skip 'Không có file Excel nào liên kết tới MyExcel ở chỗ khác'; return }
    foreach ($o in $ooxml) { Note "Liên kết cũ: $($o.File.FullName)" }
    if ($ooxml.Count -gt 0 -and (Ask "Sửa liên kết trong $($ooxml.Count) file trên (mỗi file được sao lưu trước)?")) {
        $wbDir = Join-Path $script:BackupDir 'Workbooks'
        New-Item -ItemType Directory -Path $wbDir -Force | Out-Null
        $i = 0
        foreach ($o in $ooxml) {
            $i++
            $leaf = '{0:000}_{1}' -f $i, $o.File.Name
            $dest = Join-Path $wbDir $leaf
            try {
                Copy-Item -LiteralPath $o.File.FullName -Destination $dest -Force -ErrorAction Stop
                $hashBackup = Get-Sha256 $dest
                Update-LinkedEntries $o.File.FullName $o.Entries
                # Backup tương đối với thư mục sao lưu (chép thư mục đi chỗ khác vẫn hoàn tác được);
                # HashAfter để hoàn tác biết file có bị sửa tiếp sau lần sửa này không
                $script:Manifest.Workbooks += [ordered]@{ Original = $o.File.FullName; Backup = "Workbooks\$leaf"; HashBackup = $hashBackup; HashAfter = (Get-Sha256 $o.File.FullName) }
                Save-Manifest
                Done "Nối lại liên kết: $($o.File.FullName)"
            } catch {
                if (Test-Path -LiteralPath $dest) { Copy-Item -LiteralPath $dest -Destination $o.File.FullName -Force -ErrorAction SilentlyContinue }
                Warn "Không sửa được $($o.File.FullName) (file đang mở?): $($_.Exception.Message)"
            }
        }
    }
    if ($binary.Count -gt 0) {
        Warn ('{0} file .xls dạng cũ còn liên kết tới bộ MyExcel khác, cần sửa tay: mở file > Data > Edit Links > Change Source > chọn {1}' -f $binary.Count, (Join-Path $script:Target 'MyExcel.xlam'))
        foreach ($b in ($binary | Select-Object -First 30)) { Note $b.FullName }
    }
}

# ----------------------------------------------------------------------------
$script:BankBins = @{
    '970436' = 'Vietcombank'; '970415' = 'VietinBank'; '970418' = 'BIDV'; '970405' = 'Agribank'; '970422' = 'MB Bank'
    '970407' = 'Techcombank'; '970416' = 'ACB'; '970432' = 'VPBank'; '970423' = 'TPBank'; '970403' = 'Sacombank'
    '970437' = 'HDBank'; '970441' = 'VIB'; '970443' = 'SHB'; '970431' = 'Eximbank'; '970426' = 'MSB'
    '970448' = 'OCB'; '970440' = 'SeABank'; '970449' = 'LPBank'; '970454' = 'BVBank'; '970429' = 'SCB'
    '970428' = 'Nam A Bank'; '970409' = 'Bac A Bank'; '970412' = 'PVcomBank'; '970425' = 'ABBANK'; '970427' = 'VietABank'
    '970452' = 'KienlongBank'; '970419' = 'NCB'; '970433' = 'VietBank'; '970438' = 'BaoViet Bank'; '970400' = 'Saigonbank'
    '970430' = 'PGBank'; '970424' = 'Shinhan Bank'
}

function Get-DeclaredBank {
    foreach ($n in (Get-MyExcelStateKeys)) {
        $k = Open-UserKey "Software\VB and VBA Program Settings\$n\GridLight"
        if (-not $k) { continue }
        $name = [string]$k.GetValue('TenTKQRG'); $acct = [string]$k.GetValue('SoTKQRG'); $emv = [string]$k.GetValue('MaNganhangDongDauQR1')
        $k.Close()
        if (-not $name -and -not $acct) { continue }
        $bin = if ($emv -match 'A000000727\d{4}0006(\d{6})') { $Matches[1] } else { '' }
        $bank = if ($bin -and $script:BankBins.ContainsKey($bin)) { $script:BankBins[$bin] } elseif ($bin) { "mã BIN $bin" } else { '(không rõ ngân hàng)' }
        return [pscustomobject]@{ Name = $name; Account = $acct; Bin = $bin; Bank = $bank }
    }
    return $null
}

function Save-DeclaredBank {
    # Ghi thông tin tài khoản ra thư mục sao lưu để khai báo lại; màn hình và nhật ký chỉ hiện số đã che
    $b = Get-DeclaredBank
    if (-not $b) { Note 'Profile này chưa khai báo tài khoản ngân hàng trong MyExcel.'; return }
    $masked = if ($b.Account.Length -gt 4) { ('*' * ($b.Account.Length - 4)) + $b.Account.Substring($b.Account.Length - 4) } else { $b.Account }
    Note "Tài khoản đang khai báo: $($b.Bank) - số TK $masked - $($b.Name)"
    $file = Join-Path $script:BackupDir 'ThongTinKhaiBao.txt'
    $lines = @(
        'THÔNG TIN TÀI KHOẢN ĐÃ KHAI BÁO TRONG MYEXCEL (để khai báo lại sau khi đặt lại dữ liệu)'
        "Máy: $env:COMPUTERNAME   User: $env:USERNAME   Lúc: $((Get-Date).ToString('dd/MM/yyyy HH:mm'))"
        ''
        "Ngân hàng    : $($b.Bank)$(if ($b.Bin) { " (BIN $($b.Bin))" })"
        "Số tài khoản : $($b.Account)"
        "Tên tài khoản: $($b.Name)"
        ''
        'Khai báo lại: Excel > Mini Tool > Tạo QR Code > Tạo QR Code tài khoản ngân hàng > Khai báo.'
        'Các cài đặt MyExcel cũ khác (In vùng, QR hàng loạt...) xem trong VBA_Settings.reg (mở bằng Notepad).'
    )
    try {
        [IO.File]::WriteAllLines($file, [string[]]$lines, (New-Object Text.UTF8Encoding $true))
        Note "Đã lưu thông tin để khai báo lại: $file"
    } catch { Warn "Không ghi được $file : $($_.Exception.Message)" }
}

function Invoke-MyExcelReset([bool]$Confirm = $true) {
    Step 'ĐẶT LẠI DỮ LIỆU MYEXCEL CỦA PROFILE NÀY (giống profile mới)'
    $names = @(Get-MyExcelStateKeys)
    if ($names.Count -eq 0) { Skip 'Profile này không có dữ liệu MyExcel để đặt lại'; return $false }
    if (-not $script:Manifest.RegVB) { Warn 'Chưa sao lưu được dữ liệu MyExcel nên không đặt lại.'; return $false }
    Note ('Sẽ xóa: ' + (($names | ForEach-Object { "HKCU\Software\VB and VBA Program Settings\$_" }) -join ' ; '))
    Save-DeclaredBank
    Note 'Sau khi đặt lại, mọi tùy chọn MyExcel của profile (tài khoản ngân hàng, In vùng, QR hàng loạt...) về mặc định.'
    Note 'Nếu MyExcel đòi kích hoạt bản quyền: nhập lại key hoặc liên hệ MyExcel. HoanTac sẽ đưa dữ liệu cũ (và lỗi cũ) trở lại.'
    if ($Confirm -and -not (Ask 'Đặt lại dữ liệu MyExcel ngay bây giờ?')) { Skip 'Không đặt lại dữ liệu MyExcel'; return $false }
    if (-not (Wait-ExcelClosed)) { Warn 'Excel chưa đóng nên chưa đặt lại.'; return $false }
    $root = Open-UserKey 'Software\VB and VBA Program Settings' $true
    $ok = $false
    foreach ($n in $names) {
        try {
            $root.DeleteSubKeyTree($n, $false)
            $script:Manifest.ResetKeys += "Software\VB and VBA Program Settings\$n"
            $ok = $true
            Done "Xóa dữ liệu MyExcel: $n"
        } catch { Warn "Không xóa được $n : $($_.Exception.Message)" }
    }
    $root.Close()
    Save-Manifest
    return $ok
}

# ----------------------------------------------------------------------------
function Show-Verification {
    Step 'KIỂM TRA SAU KHI SỬA'
    $ver = Get-ExcelMainVersion
    $k = Open-UserKey "Software\Microsoft\Office\$ver\Excel\Options"
    $opens = if ($k) { @($k.GetValueNames() | Where-Object { $_ -match '^OPEN\d*$' } | ForEach-Object { "$_ = $($k.GetValue($_))" }) } else { @() }
    Note ('Add-in đang bật (Excel {0}): {1}' -f $ver, $(if ($opens.Count) { $opens -join ' ; ' } else { 'không có' }))
    foreach ($f in @($script:Manifest.Folders)) { Note ('Đã cất: {0} -> {1}' -f $f.From, $f.To) }
    foreach ($n in (Get-MyExcelStateKeys)) {
        $stack = New-Object System.Collections.Stack
        $root = Open-UserKey "Software\VB and VBA Program Settings\$n"
        if ($root) { $stack.Push($root) }
        while ($stack.Count -gt 0) {
            $key = $stack.Pop()
            if ($key.GetValueNames() -contains 'DuongDanADDin') { Note "DuongDanADDin = $($key.GetValue('DuongDanADDin'))" }
            foreach ($sn in $key.GetSubKeyNames()) { $sk = $key.OpenSubKey($sn); if ($sk) { $stack.Push($sk) } }
            $key.Close()
        }
    }
    Say ''
    Say ('  Tổng: {0} thay đổi, {1} cảnh báo.' -f $script:Changes, $script:Problems) $(if ($script:Problems) { 'Yellow' } else { 'Green' })
}

function Show-QrSteps([bool]$AfterReset) {
    $sep = (Get-Culture).TextInfo.ListSeparator
    Say '  Làm trong Excel:' 'White'
    Say '   - Có thông báo không tìm thấy file MyExcel cũ thì bấm OK.'
    if ($AfterReset) { Say '   - MyExcel hiện màn hình chạy lần đầu thì làm theo như lúc mới cài.' }
    Say '   - Tab Mini Tool > Tạo QR Code: TẮT rồi BẬT lại hàm QR, phải thấy "Bạn đã có thể dùng Hàm QR".'
    if ($AfterReset) {
        $hint = if ($script:BackupDir -and (Test-Path -LiteralPath (Join-Path $script:BackupDir 'ThongTinKhaiBao.txt'))) { ' (thông tin cũ trong ThongTinKhaiBao.txt ở thư mục sao lưu)' } else { '' }
        Say "   - Khai báo lại tài khoản: Mini Tool > Tạo QR Code > Tạo QR Code tài khoản ngân hàng > Khai báo$hint."
    }
    Say ('   - Thử tạo mã VietQR như mọi khi, hoặc gõ =QrBank_Sotien_Noidung(10000{0}"THU NGHIEM") vào một ô trống.' -f $sep)
}

function Show-StillBroken {
    $script:StillBroken = $true
    Step 'VẪN CHƯA ĐƯỢC - VIỆC CẦN LÀM TIẾP'
    Say '  1) Chạy CheckMyExcel_VietQR.bat trong profile lỗi, rồi chạy thêm 1 lần trong một profile mới (tạo QR được).'
    Say '     Báo cáo lần 2 có mục 12 so sánh 2 profile - gửi cả 2 báo cáo.'
    Say '  2) Thiết lập Windows theo user hay gây khác biệt: định dạng ngày/số (Region), Clipboard history (Win+V).'
}

function Invoke-Trial([bool]$AfterReset, [bool]$CanReset) {
    Step 'BƯỚC 10 - THỬ VIETQR TRONG EXCEL'
    if (-not $script:Auto) {
        if (-not (Ask 'Mở Excel để thử ngay bây giờ?')) {
            Show-QrSteps $AfterReset
            if ($CanReset) { Say '  Nếu thử sau mà vẫn lỗi: chạy lại file sửa này và chọn đặt lại dữ liệu MyExcel.' 'Yellow' }
            return
        }
        Start-Process 'excel.exe' -ErrorAction SilentlyContinue
    }
    Show-QrSteps $AfterReset
    if (Test-QrWorks 'Đã tạo được VietQR chưa?') { Say '  VietQR đã chạy được. Xong.' 'Green'; return }
    if (-not $CanReset) { Show-StillBroken; return }
    Say ''
    Say '  Chưa được: bước tiếp theo là đặt lại dữ liệu MyExcel của profile này về như profile mới.' 'Yellow'
    if (-not (Invoke-MyExcelReset $true)) { Show-StillBroken; return }
    if (-not $script:Auto -and (Ask 'Mở Excel để thử lại?')) { Start-Process 'excel.exe' -ErrorAction SilentlyContinue }
    Show-QrSteps $true
    if (Test-QrWorks 'Đã tạo được VietQR chưa?') { Say '  VietQR đã chạy được sau khi đặt lại dữ liệu MyExcel. Xong.' 'Green'; return }
    Show-StillBroken
}

function Invoke-DataStep {
    Step 'BƯỚC 9 - DỮ LIỆU MYEXCEL LƯU THEO USER'
    $names = @(Get-MyExcelStateKeys)
    if ($names.Count -eq 0) { Skip 'Profile này chưa có dữ liệu MyExcel (giống profile mới)'; Invoke-Trial $false $false; return }
    $dataDate = Get-MyExcelDataDate
    $xlamDate = (Get-Item -LiteralPath (Join-Path $script:Target 'MyExcel.xlam') -Force).LastWriteTime
    $stale = [bool]($dataDate -and ($xlamDate - $dataDate).TotalDays -gt 30)
    if ($dataDate) {
        Note ('Dữ liệu MyExcel của profile tạo từ bản ngày {0}, bộ đang dùng là bản ngày {1}{2}' -f $dataDate.ToString('dd/MM/yyyy'), $xlamDate.ToString('dd/MM/yyyy'), $(if ($stale) { ' => DỮ LIỆU CŨ' } else { '' }))
    }
    Say '  Lỗi "profile mới tạo được VietQR, profile cũ thì không" đã sửa được bằng cách đặt lại dữ liệu này.' 'White'
    $opts = @('Đặt lại dữ liệu MyExcel ngay rồi mới thử (nhanh; phải khai báo lại tài khoản ngân hàng)', 'Thử trong Excel trước, vẫn lỗi mới đặt lại')
    $def = if ($env:MYX_RESET_NOW) { if ($env:MYX_RESET_NOW -eq '1') { 1 } else { 2 } } elseif ($stale) { 1 } else { 2 }   # MYX_RESET_NOW chỉ dùng khi test
    $opts[$def - 1] += '  <- khuyên dùng'
    if ((Choose 'Chọn cách làm' $opts $def) -eq 1) {
        $ok = Invoke-MyExcelReset $false
        Invoke-Trial $ok (-not $ok)
    } else {
        Invoke-Trial $false $true
    }
}

function Invoke-Fix {
    Say ''
    Say "  SỬA LỖI VIETQR CỦA MYEXCEL CHO PROFILE NÀY (bản $($script:Version))" 'Cyan'
    Say "  Tài khoản: $env:USERNAME   Máy: $env:COMPUTERNAME"
    Say '  Script sẽ: tìm bộ MyExcel chuẩn -> sao lưu -> cất bộ thừa -> nạp lại add-in -> sửa đường dẫn MyExcel tự lưu'
    Say '  -> dọn cache .exd -> bỏ chặn file -> nối lại file Excel cũ -> đặt lại dữ liệu MyExcel (hỏi trước) -> thử trong Excel.'
    Say '  Không đổi Macro Settings / Protected View / ActiveX. Mọi thay đổi đều có sao lưu và file hoàn tác.'
    Say ''
    Show-FontHint
    if (-not (Test-RightUser)) { Set-Result 2 'SAI_TAI_KHOAN' 'Chạy sai tài khoản Windows, chưa thay đổi gì.'; return }
    if (-not (Ask 'Bắt đầu sửa?')) { Say '  Đã hủy, chưa thay đổi gì.' 'Yellow'; Set-Result 2 'NGUOI_DUNG_HUY' 'Người dùng chọn không sửa.'; return }
    if (-not (Wait-ExcelClosed)) { Say '  Đã dừng, chưa thay đổi gì.' 'Yellow'; Set-Result 2 'EXCEL_CHUA_DONG' 'Excel chưa đóng, chưa thay đổi gì.'; return }
    if (-not (Select-MyExcelTarget)) { Say '  Đã dừng, chưa thay đổi gì.' 'Yellow'; Set-Result 2 'KHONG_CO_BO_MYEXCEL' 'Không thấy bộ MyExcel đủ file QR trên máy.'; return }
    if (-not (Invoke-Backup)) { Warn 'Sao lưu thất bại nên DỪNG LẠI, chưa sửa gì.'; Set-Result 1 'SAO_LUU_LOI' 'Không sao lưu được nên chưa sửa gì.'; return }
    $script:ChangesAtBackup = $script:Changes
    Invoke-FolderFix
    Invoke-AddinFix
    Invoke-VbaPathFix
    Invoke-CacheCleanup
    Invoke-Unblock
    Invoke-WorkbookRelink
    Save-Manifest
    Show-Verification
    Invoke-DataStep
    Save-Manifest
    Say ''
    Say "  Sao lưu: $($script:BackupDir)" 'White'
    Say '  HoanTac_FixMyExcel.bat trong đó trả lại mọi thứ như trước khi sửa (kể cả lỗi cũ) - chỉ chạy khi thật cần.' 'White'
    if ($script:StillBroken) { Set-Result 3 'VIETQR_VAN_LOI' 'Đã sửa nhưng VietQR vẫn chưa chạy được.' }
    elseif ($script:Problems -gt 0) { Set-Result 3 'CO_CANH_BAO' "Đã sửa, còn $($script:Problems) cảnh báo cần xem." }
    else { Set-Result 0 'XONG' 'Đã sửa xong.' }
}

function Resolve-BackupFile([string]$Dir, [string]$Path) {
    # Bản sao lưu cũ ghi đường dẫn tuyệt đối; từ bản 2 ghi tương đối với thư mục sao lưu
    if (-not $Path) { return $null }
    if ([IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $Dir $Path)
}

function Get-KeepPath([string]$Path) {
    # SoQuy.xlsx -> SoQuy.truoc_hoantac.xlsx (đã có thì thêm giờ), vẫn mở được bằng Excel
    $dir = Split-Path $Path -Parent
    $base = [IO.Path]::GetFileNameWithoutExtension($Path); $ext = [IO.Path]::GetExtension($Path)
    $p = Join-Path $dir "$base.truoc_hoantac$ext"
    if (Test-Path -LiteralPath $p) { $p = Join-Path $dir "$base.truoc_hoantac_$($script:Stamp)$ext" }
    return $p
}

function Get-WorkbookPlan($Workbooks, [string]$Dir) {
    # Action: Restore = chưa đổi sau lần sửa, chép lại bản cũ | Keep = đã đổi (hoặc không biết), giữ bản hiện tại rồi mới chép | Skip
    foreach ($w in @($Workbooks | Where-Object { $_ })) {
        $orig = [string]$w.Original
        $bak = Resolve-BackupFile $Dir ([string]$w.Backup)
        $p = [pscustomobject]@{ Original = $orig; Backup = $bak; Action = 'Restore'; Why = '' }
        if (-not $bak -or -not (Test-Path -LiteralPath $bak -PathType Leaf)) { $p.Action = 'Skip'; $p.Why = "thiếu bản sao lưu $bak" }
        elseif ($w.HashBackup -and (Get-Sha256 $bak) -ne [string]$w.HashBackup) { $p.Action = 'Skip'; $p.Why = "bản sao lưu $bak đã bị thay đổi hoặc hỏng" }
        elseif (-not (Test-Path -LiteralPath $orig -PathType Leaf)) { $p.Action = 'Skip'; $p.Why = "file không còn ở chỗ cũ (đã chuyển hoặc xoá), bản trước khi sửa: $bak" }
        elseif (-not $w.HashAfter) { $p.Action = 'Keep'; $p.Why = 'bản sao lưu cũ không ghi dấu file nên không biết đã sửa tiếp chưa' }
        elseif ((Get-Sha256 $orig) -ne [string]$w.HashAfter) { $p.Action = 'Keep'; $p.Why = 'đã được sửa tiếp sau lần sửa' }
        $p
    }
}

function Restore-Workbook($P) {
    if ($P.Action -eq 'Skip') { Warn "Không khôi phục $($P.Original): $($P.Why)"; return }
    $keep = $null
    if ($P.Action -eq 'Keep') {
        $keep = Get-KeepPath $P.Original
        try { Copy-Item -LiteralPath $P.Original -Destination $keep -ErrorAction Stop }
        catch { Warn "Không giữ được bản hiện tại của $($P.Original) nên không chép đè: $($_.Exception.Message)"; return }
    }
    try { Copy-Item -LiteralPath $P.Backup -Destination $P.Original -Force -ErrorAction Stop }
    catch { Warn "Không khôi phục được $($P.Original) (file đang mở?): $($_.Exception.Message)"; return }
    if ($keep) {
        $script:KeptFiles.Add($keep)
        Done "Khôi phục file $($P.Original); bản hiện tại ($($P.Why)) giữ ở $keep"
    } else {
        Done "Khôi phục file $($P.Original)"
    }
}

function Save-PreUndoState([string]$Dir) {
    # Cấu hình ngay trước khi hoàn tác: hoàn tác nhầm thì nạp lại các file .reg này
    $pre = Join-Path $Dir "TruocHoanTac_$($script:Stamp)"
    try { New-Item -ItemType Directory -Path $pre -Force -ErrorAction Stop | Out-Null }
    catch { Warn "Không tạo được thư mục $pre : $($_.Exception.Message)"; return $false }
    $regRoot = 'HKCU\' + $script:RegBase
    foreach ($ver in (Get-ExcelVersions)) {
        & reg.exe export "$($regRoot)Software\Microsoft\Office\$ver\Excel" (Join-Path $pre "Excel_$ver.reg") /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Warn "Không lưu được cấu hình Excel $ver hiện tại (mã lỗi $LASTEXITCODE)"; return $false }
    }
    $vb = Open-UserKey 'Software\VB and VBA Program Settings'
    if ($vb) {
        $vb.Close()
        & reg.exe export "$($regRoot)Software\VB and VBA Program Settings" (Join-Path $pre 'VBA_Settings.reg') /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Warn "Không lưu được dữ liệu MyExcel hiện tại (mã lỗi $LASTEXITCODE)"; return $false }
    }
    Note "Đã lưu cấu hình hiện tại (trước khi hoàn tác) vào $pre"
    return $true
}

function Invoke-Undo {
    $dir = $script:UndoDir
    $script:BackupDir = $null
    $mf = Join-Path $dir 'manifest.json'
    Say ''
    Say "  HOÀN TÁC SỬA LỖI MYEXCEL (bản $($script:Version))" 'Cyan'
    Show-FontHint
    if (-not (Test-Path -LiteralPath $mf)) { Warn "Không thấy manifest.json trong $dir"; Set-Result 2 'THIEU_MANIFEST' 'Thư mục sao lưu thiếu manifest.json.'; return }
    try { $m = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { Warn "manifest.json hỏng, không đọc được: $($_.Exception.Message)"; Set-Result 1 'MANIFEST_HONG' 'manifest.json hỏng nên không hoàn tác được.'; return }
    $script:RegBase = [string]$m.RegBase
    Say "  Bản sao lưu lúc $($m.Time) của user $($m.User) trên máy $($m.Computer)"
    if ($m.User -ne $env:USERNAME) { Warn "Đang chạy bằng user $env:USERNAME - phải chạy bằng đúng user $($m.User)."; Set-Result 2 'SAI_TAI_KHOAN' "Phải chạy bằng đúng user $($m.User)."; return }
    if (-not (Test-RightUser)) { Set-Result 2 'SAI_TAI_KHOAN' 'Chạy sai tài khoản Windows, chưa hoàn tác gì.'; return }
    foreach ($p in @(Get-WorkbookPlan $m.Workbooks $dir)) {
        switch ($p.Action) {
            'Restore' { Note "Chép lại bản trước khi sửa: $($p.Original)" }
            'Keep'    { Say ('  {0}: {1}, bản hiện tại sẽ được giữ thành {2} rồi mới chép bản trước khi sửa.' -f $p.Original, $p.Why, (Split-Path (Get-KeepPath $p.Original) -Leaf)) 'Yellow' }
            default   { Say "  Bỏ qua $($p.Original): $($p.Why)" 'Yellow' }
        }
    }
    Say '  Lưu ý: hoàn tác đưa dữ liệu MyExcel cũ trở lại, lỗi VietQR cũ có thể quay lại.' 'Yellow'
    if (-not (Ask 'Khôi phục cấu hình Excel, dữ liệu MyExcel, thư mục và các file đã sửa?')) { Say '  Đã hủy.' 'Yellow'; Set-Result 2 'NGUOI_DUNG_HUY' 'Người dùng chọn không hoàn tác.'; return }
    if (-not (Wait-ExcelClosed)) { Set-Result 2 'EXCEL_CHUA_DONG' 'Excel chưa đóng, chưa hoàn tác gì.'; return }
    if (-not (Save-PreUndoState $dir)) { Set-Result 1 'SAO_LUU_LOI' 'Không lưu được cấu hình hiện tại nên chưa hoàn tác gì.'; return }
    $script:ChangesAtBackup = $script:Changes
    foreach ($nk in @(@($m.NewKeys) + @($m.ResetKeys) | Where-Object { $_ })) {
        # Xóa khóa do script thêm, và dữ liệu MyExcel tạo mới sau khi đặt lại, trước khi nạp bản sao lưu
        try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($script:RegBase + $nk, $false); Done "Xóa khóa tạo sau khi sửa: $nk" }
        catch { Warn "Không xóa được $nk : $($_.Exception.Message)" }
    }
    foreach ($r in @($m.RegExcel)) {
        $k = Open-UserKey "Software\Microsoft\Office\$($r.Ver)\Excel\Options" $true
        if ($k) { foreach ($n in @($k.GetValueNames() | Where-Object { $_ -match '^OPEN\d*$' })) { $k.DeleteValue($n, $false) }; $k.Close() }
        & reg.exe import (Join-Path $dir $r.File) 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Done "Khôi phục cấu hình Excel $($r.Ver)" } else { Warn "Không nhập được $($r.File) (mã lỗi $LASTEXITCODE)" }
    }
    if ($m.RegVB) {
        & reg.exe import (Join-Path $dir $m.RegVB) 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Done 'Khôi phục dữ liệu MyExcel (VB and VBA Program Settings)' } else { Warn "Không nhập được $($m.RegVB)" }
    }
    foreach ($f in @(@($m.Folders) + @($m.Folder) | Where-Object { $_ })) {
        if ((Test-Path -LiteralPath $f.To) -and -not (Test-Path -LiteralPath $f.From)) {
            try { Rename-Item -LiteralPath $f.To -NewName (Split-Path $f.From -Leaf) -ErrorAction Stop; Done "Đổi tên lại $($f.To) -> $($f.From)" }
            catch { Warn "Không đổi tên lại được $($f.To): $($_.Exception.Message)" }
        }
    }
    # Tính lại ngay trước khi chép: file có thể vừa được lưu trong lúc chờ đóng Excel
    foreach ($p in @(Get-WorkbookPlan $m.Workbooks $dir)) { Restore-Workbook $p }
    Say ('  Xong: {0} mục đã khôi phục, {1} cảnh báo. (File .exd đã xóa và dấu chặn file không cần khôi phục.)' -f ($script:Changes - $script:ChangesAtBackup), $script:Problems) $(if ($script:Problems) { 'Yellow' } else { 'Green' })
    foreach ($k in $script:KeptFiles) { Say "  Bản file Excel ngay trước khi hoàn tác được giữ ở: $k (dữ liệu nhập thêm sau lần sửa nằm trong file này)" 'Yellow' }
    if ($script:Problems -gt 0) { Set-Result 3 'CO_CANH_BAO' "Hoàn tác xong, còn $($script:Problems) cảnh báo cần xem." }
    else { Set-Result 0 'XONG' 'Đã hoàn tác xong.' }
}

# ----------------------------------------------------------------------------
try {
    if ($script:UndoMode) { Invoke-Undo } else { Invoke-Fix }
} catch {
    $real = if ($null -ne $script:ChangesAtBackup) { $script:Changes - $script:ChangesAtBackup } else { 0 }
    if ("$($_.Exception.Message)" -eq $script:EndOfInput) {
        Say ''
        Say '  Hết đầu vào: không có ai trả lời câu hỏi (chạy không có cửa sổ dòng lệnh?) nên dừng lại.' 'Yellow'
        if ($real -gt 0) {
            $more = if ($script:UndoMode) { 'chạy lại hoàn tác để làm nốt.' } else { 'mọi thay đổi đều có sao lưu, chạy HoanTac_FixMyExcel.bat trong thư mục sao lưu nếu cần trả lại.' }
            Say "  Đã làm $real thay đổi trước khi dừng: $more" 'Yellow'
            Set-Result 3 'HET_DAU_VAO' "Hết đầu vào sau $real thay đổi."
        } else {
            Say '  Chưa thay đổi gì.' 'Yellow'
            Set-Result 2 'HET_DAU_VAO' 'Hết đầu vào, chưa thay đổi gì.'
        }
    } else {
        Warn "Lỗi không mong muốn: $($_.Exception.Message)"
        Set-Result 1 'LOI_BAT_NGO' "Lỗi không mong muốn: $($_.Exception.Message)"
    }
} finally {
    if ($null -eq $script:ExitCode) { Set-Result 1 'LOI_BAT_NGO' 'Dừng giữa chừng.' }
    $logDir = if ($script:UndoMode) { $script:UndoDir } elseif ($script:BackupDir) { $script:BackupDir } else { $null }
    $logPath = if ($logDir) { Join-Path $logDir $(if ($script:UndoMode) { "NhatKy_HoanTac_$($script:Stamp).txt" } else { 'NhatKy_Sua.txt' }) } else { $null }
    Save-ResultJson $logPath
    if ($logPath) {
        try { [IO.File]::WriteAllLines($logPath, $script:Log.ToArray(), (New-Object Text.UTF8Encoding $true)); Say "  Nhật ký: $logPath" 'DarkGray' } catch {}
    }
}
exit $script:ExitCode
