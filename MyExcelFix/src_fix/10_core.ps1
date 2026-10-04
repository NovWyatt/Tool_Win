
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
$script:Log        = New-Object System.Collections.Generic.List[string]
$script:Stamp      = (Get-Date).ToString('yyyyMMdd_HHmmss')
$script:Preferred  = if ($env:MYX_PREFERRED) { $env:MYX_PREFERRED.TrimEnd('\') } else { 'C:\MyExcel' }   # thư mục MyExcel khuyên dùng
$script:RegBase    = if ($env:MYX_REGBASE) { $env:MYX_REGBASE.Trim('\') + '\' } else { '' }          # chỉ dùng khi test
$script:Auto       = [bool]$env:MYX_AUTO                                                            # chỉ dùng khi test
$script:QrAnswers  = @(if ($env:MYX_QR_OK) { $env:MYX_QR_OK -split ',' })                           # chỉ dùng khi test
$script:QrAsked    = 0
$script:UndoMode   = ((Split-Path $env:MYX_SELF -Leaf) -like 'HoanTac*')
$script:Changes    = 0
$script:Problems   = 0
$script:BackupDir  = $null
$script:Target     = $null   # thư mục bộ MyExcel chuẩn được chọn
$script:Installs   = @()     # mọi thư mục có MyExcel.xlam tìm thấy (kể cả bản sao lẻ)
$script:AddinMap   = @{}     # tên file .xlam (chữ thường) -> đường dẫn trong bộ chuẩn
$script:Manifest   = [ordered]@{
    Time = (Get-Date).ToString('dd/MM/yyyy HH:mm:ss'); User = $env:USERNAME; Computer = $env:COMPUTERNAME
    Target = $null; RegBase = $script:RegBase
    RegExcel = @(); RegVB = $null; NewKeys = @(); ResetKeys = @(); Folders = @(); Workbooks = @()
}

function Say([string]$Text = '', [string]$Color = 'Gray') { Write-Host (Txt $Text) -ForegroundColor $Color; $script:Log.Add($Text) }
function Step([string]$Title) { Say ''; Say ('=' * 74) 'DarkCyan'; Say "  $Title" 'Cyan'; Say ('=' * 74) 'DarkCyan' }
function Done([string]$Text) { Say "  [ĐÃ SỬA]  $Text" 'Green'; $script:Changes++ }
function Skip([string]$Text) { Say "  [BỎ QUA]  $Text" 'DarkGray' }
function Warn([string]$Text) { Say "  [!]       $Text" 'Yellow'; $script:Problems++ }
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
function Ask([string]$Question) {
    if ($script:Auto) { Say "  $Question (Y/N): Y  [tự động]" 'White'; return $true }
    while ($true) {
        $a = Read-Host (Txt "  $Question (Y/N)")
        if ($a -match '^\s*kd') { Set-NoDau; continue }
        if ($a -match '^\s*[YC]') { $script:Log.Add("  $Question => Y"); return $true }
        if ($a -match '^\s*[NK]') { $script:Log.Add("  $Question => N"); return $false }
    }
}
function Choose([string]$Question, [string[]]$Options, [int]$Default = 1) {
    for ($i = 0; $i -lt $Options.Count; $i++) { Say ("    {0}) {1}" -f ($i + 1), $Options[$i]) 'White' }
    if ($script:Auto) { Say "  $Question $Default  [tự động]" 'White'; return $Default }
    while ($true) {
        $a = Read-Host (Txt "  $Question (1-$($Options.Count), Enter = $Default)")
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
        $a = Read-Host (Txt '  Nhấn Enter khi đã đóng Excel (gõ Q để thoát)')
        if ($a -match '^\s*[Qq]') { return $false }
    }
}
function Save-Manifest {
    if (-not $script:BackupDir) { return }
    $json = $script:Manifest | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $script:BackupDir 'manifest.json'), $json, (New-Object Text.UTF8Encoding $false))
}
