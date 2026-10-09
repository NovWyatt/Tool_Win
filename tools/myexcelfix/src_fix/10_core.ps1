
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
$script:Version    = '__MYX_VERSION__'   # build.ps1 thay bằng version trong tool.json
$script:Log        = New-Object System.Collections.Generic.List[string]
$script:Started    = Get-Date
$script:Stamp      = $script:Started.ToString('yyyyMMdd_HHmmss')
$script:Preferred  = if ($env:MYX_PREFERRED) { $env:MYX_PREFERRED.TrimEnd('\') } else { 'C:\MyExcel' }   # thư mục MyExcel khuyên dùng
$script:RegBase    = if ($env:MYX_REGBASE) { $env:MYX_REGBASE.Trim('\') + '\' } else { '' }          # chỉ dùng khi test
$script:Auto       = [bool]$env:MYX_AUTO                                                            # chỉ dùng khi test
$script:QrAnswers  = @(if ($env:MYX_QR_OK) { $env:MYX_QR_OK -split ',' })                           # chỉ dùng khi test
$script:QrAsked    = 0
# Hoàn tác: bản HoanTac_FixMyExcel.bat trong thư mục sao lưu, hoặc HOAN_TAC.bat đặt MYX_UNDO_DIR rồi gọi bản mới nhất;
# HOAN_TAC.bat không có thư mục thì đặt MYX_UNDO_CHON=1: liệt kê bản sao lưu của tài khoản này để chọn
$script:UndoDir    = if ($env:MYX_UNDO_DIR) { $env:MYX_UNDO_DIR.TrimEnd('\') } elseif ((Split-Path $env:MYX_SELF -Leaf) -like 'HoanTac*') { Split-Path $env:MYX_SELF -Parent } else { $null }
$script:UndoMode   = [bool]$script:UndoDir -or ($env:MYX_UNDO_CHON -eq '1')
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
# Nơi lưu. Sao lưu (có số tài khoản ngân hàng, bản sao file Excel), nhật ký, JSON kết quả: thư mục riêng của tài khoản
# %LOCALAPPDATA%\MyExcelFix - không đồng bộ OneDrive như Desktop, tài khoản khác không đọc được như Public Documents.
# MYX_OUT, MYX_DESKTOP chỉ dùng khi test.
function Get-MyxDataDir([string]$Sub) {
    if ($env:MYX_OUT) { return $env:MYX_OUT }
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
    return (Join-Path (Join-Path $base 'MyExcelFix') $Sub)
}
function Get-DesktopDir {
    if ($env:MYX_DESKTOP) { return $env:MYX_DESKTOP }
    return [Environment]::GetFolderPath('Desktop')
}
function Get-ResultDir { return (Get-MyxDataDir 'BaoCao') }
function Move-OldResults([string]$To) {
    # Bản trước 2026.10.2 ghi báo cáo, JSON kết quả vào thư mục chung: chuyển các file của tài khoản này sang thư mục
    # riêng. File của tài khoản khác để nguyên (chuyển khi tài khoản đó chạy bản mới), snapshot để nguyên.
    $from = Join-Path $env:PUBLIC 'Documents\MyExcelCheck'
    if ($env:MYX_OUT -or -not (Test-Path -LiteralPath $from)) { return }
    $u = ($env:USERNAME -replace '[^\w\.-]', '_'); $c = $env:COMPUTERNAME
    $mine = @(Get-ChildItem -LiteralPath $from -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like "BaoCao_MyExcel_$($c)_$($u)_*.txt" -or $_.Name -like "KetQua_MyExcel_*_$($c)_$($u)_*.json" })
    if ($mine.Count -eq 0) { return }
    $n = 0
    try {
        if (-not (Test-Path -LiteralPath $To)) { New-Item -ItemType Directory -Path $To -Force -ErrorAction Stop | Out-Null }
        foreach ($f in $mine) {
            $dest = Join-Path $To $f.Name
            if (Test-Path -LiteralPath $dest) { continue }
            try { Move-Item -LiteralPath $f.FullName -Destination $dest -ErrorAction Stop; $n++ } catch {}
        }
    } catch {}
    if ($n) { Say "  Đã chuyển $n báo cáo cũ của tài khoản này từ $from (mọi tài khoản đọc được) sang $To" 'DarkGray' }
}
function Get-BackupList {
    # Bản sao lưu có manifest.json, mới nhất trước: thư mục riêng (từ 2026.10.2) và Desktop (bản cũ hơn)
    $roots = @(Get-MyxDataDir 'SaoLuu')
    if (-not $env:MYX_OUT -or $env:MYX_DESKTOP) { $roots += Get-DesktopDir }
    $seen = @{}
    $list = foreach ($r in $roots) {
        if (-not $r -or -not (Test-Path -LiteralPath $r -PathType Container)) { continue }
        foreach ($d in @(Get-ChildItem -LiteralPath $r -Directory -Filter 'MyExcelFix_SaoLuu_*' -ErrorAction SilentlyContinue)) {
            if ($seen.ContainsKey($d.FullName) -or -not (Test-Path -LiteralPath (Join-Path $d.FullName 'manifest.json'))) { continue }
            $seen[$d.FullName] = $true
            $m = $null
            try { $m = Get-Content -LiteralPath (Join-Path $d.FullName 'manifest.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch {}
            [pscustomobject]@{
                Dir = $d.FullName; Name = $d.Name; Manifest = $m
                User = $(if ($m) { [string]$m.User } else { '' }); Time = $(if ($m) { [string]$m.Time } else { '' })
                OnDesktop = (Test-SamePath $r (Get-DesktopDir))
            }
        }
    }
    return @($list | Sort-Object Name -Descending)   # tên có giờ yyyyMMdd_HHmmss
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
        Move-OldResults $dir
        $path = Join-Path $dir $name
        [IO.File]::WriteAllText($path, ($r | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
        Say "  Kết quả (JSON): $path" 'DarkGray'
    } catch { Say "  Không ghi được file kết quả JSON: $($_.Exception.Message)" 'DarkGray' }
}
