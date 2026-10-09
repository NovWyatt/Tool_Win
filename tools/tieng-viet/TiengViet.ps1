<#
  Gói tiếng Việt: bộ gõ, font VNI và TCVN3, định dạng số và ngày của Windows; chuyển tài liệu font cũ sang Unicode.

  Chế độ (-Mode):
    kiem-tra   chỉ đọc: bộ gõ tiếng Việt đang chạy (hai bộ cùng chạy, một bộ chạy hai lần, chạy bằng quyền gì), bộ gõ
               khởi động cùng Windows (trùng chỗ, trùng bộ), bàn phím tiếng Việt của Windows bật cùng bộ gõ ngoài, font
               VNI và TCVN3 (.Vn) đã cài, định dạng số và ngày (dấu thập phân trùng dấu nghìn, trùng dấu ngăn danh sách,
               ngày kiểu tháng trước), Excel dùng dấu riêng, ngôn ngữ cho chương trình không Unicode, chế độ UTF-8 (Beta).
    dinh-dang  đặt định dạng số và ngày cho tài khoản đang dùng (không cần Admin): -Mau vn (1.234,5; công thức Excel ngăn
               tham số bằng dấu ;) hoặc quoc-te (1,234.5; dấu ,); ngày dd/MM/yyyy. -ExcelTheoWindows: Excel đang dùng dấu
               riêng thì cho Excel dùng lại dấu của Windows (Excel phải đang tắt).
    tra-lai    trả định dạng và tuỳ chọn Excel về như trước lần đổi đầu tiên.
  Không có -Mode: menu (bấm đúp TIENG_VIET.bat), có thêm mục chuyển tài liệu .docx, .xlsx gõ bằng font VNI, TCVN3 sang
  Unicode (chuyen_unicode.py, cần Python 3.9 trở lên; chạy riêng bằng CHUYEN_UNICODE.bat).
  Trước khi đổi, giá trị cũ được lưu vào ket_qua\TrangThaiGoc_TiengViet_<máy>_<tài khoản>.json (giữ giá trị lần đổi đầu).
  Mỗi lần chạy ghi ket_qua\KetQua_TiengViet_<máy>_<giờ>.json (chuẩn tramtool.ketqua/1) cho Trạm Tool.
  -ChayThu: chỉ in việc sẽ làm. -KhongDung: không chờ Enter khi xong.
  Mã thoát: 0 xong (kể cả khi Kiểm tra có cảnh báo), 1 lỗi, 2 đã huỷ hoặc thiếu Python, 3 làm được một phần.
#>
param(
    [string]$Mode = '',
    [string]$Mau = 'vn',
    [switch]$ExcelTheoWindows,
    [switch]$ChayThu,
    [switch]$KhongDung
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:Version = '1.0'
$script:ResultDir = if ($env:TV_KET_QUA) { $env:TV_KET_QUA } else { Join-Path $PSScriptRoot 'ket_qua' }
$script:StateFile = Join-Path $script:ResultDir ('TrangThaiGoc_TiengViet_{0}_{1}.json' -f $env:COMPUTERNAME, $env:USERNAME)
# Gốc registry của tài khoản. Bài thử đặt TV_REG_GOC (vd HKCU:\Software\TramToolTest\TiengViet) để không đụng cài đặt thật;
# khi đó định dạng được ghi thẳng vào registry thử thay vì qua SetLocaleInfo.
$script:RegRoot = if ($env:TV_REG_GOC) { $env:TV_REG_GOC.TrimEnd('\') } else { 'HKCU:' }
$script:IntlKey = "$script:RegRoot\Control Panel\International"
$script:OfficeKey = "$script:RegRoot\Software\Microsoft\Office"
$script:OfficeVers = @('16.0', '15.0', '14.0')
# Giá trị định dạng công cụ đổi được; Lc là mã LOCALE_* của SetLocaleInfo.
$script:IntlNames = [ordered]@{
    sDecimal        = @{ Ten = 'Dấu thập phân'; Lc = 0x0E }
    sThousand       = @{ Ten = 'Dấu phân cách nghìn'; Lc = 0x0F }
    sList           = @{ Ten = 'Dấu ngăn danh sách (ngăn tham số công thức Excel, cột CSV)'; Lc = 0x0C }
    sShortDate      = @{ Ten = 'Ngày dạng ngắn'; Lc = 0x1F }
    sMonDecimalSep  = @{ Ten = 'Dấu thập phân của tiền'; Lc = 0x16 }
    sMonThousandSep = @{ Ten = 'Dấu phân cách nghìn của tiền'; Lc = 0x17 }
}
$script:MauDinhDang = [ordered]@{
    'vn'      = @{ Ten = 'kiểu Việt Nam: 1.234.567,89; công thức Excel =SUM(A1;B1); ngày 31/12/2026'
        GiaTri = [ordered]@{ sDecimal = ','; sThousand = '.'; sList = ';'; sShortDate = 'dd/MM/yyyy'; sMonDecimalSep = ','; sMonThousandSep = '.' } }
    'quoc-te' = @{ Ten = 'kiểu quốc tế: 1,234,567.89; công thức Excel =SUM(A1,B1); ngày 31/12/2026'
        GiaTri = [ordered]@{ sDecimal = '.'; sThousand = ','; sList = ','; sShortDate = 'dd/MM/yyyy'; sMonDecimalSep = '.'; sMonThousandSep = ',' } }
}
# Bộ gõ tiếng Việt: tên hiển thị và mẫu tên file chạy (không đuôi .exe).
$script:BoGo = @(
    @{ Ten = 'UniKey'; Mau = '^(?i)unikey(nt)?$' }
    @{ Ten = 'EVKey'; Mau = '^(?i)evkey(32|64)?$' }
    @{ Ten = 'OpenKey'; Mau = '^(?i)openkey(32|64)?$' }
    @{ Ten = 'Vietkey'; Mau = '^(?i)(vietkey(2000|2007)?|vk20\d\d)$' }
    @{ Ten = 'GoTiengViet'; Mau = '^(?i)gotiengviet$' }
    @{ Ten = 'Laban Key'; Mau = '^(?i)labankey$' }
    @{ Ten = 'VPSKeys'; Mau = '^(?i)vpskeys?$' }
)
$script:Modes = [ordered]@{
    'kiem-tra'  = @{ Label = 'Kiểm tra bộ gõ, font, định dạng số và ngày (chỉ đọc)' }
    'dinh-dang' = @{ Label = 'Đặt định dạng số và ngày' }
    'tra-lai'   = @{ Label = 'Trả định dạng về như trước khi đổi' }
}
$script:Levels = @{ 'loi' = 0; 'canh-bao' = 1; 'thong-tin' = 2; 'ok' = 3 }
$script:Findings = New-Object System.Collections.ArrayList

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

function Initialize-Native {
    if ('TramToolTiengViet.Native' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace TramToolTiengViet {
    public static class Native {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool SetLocaleInfoW(uint locale, uint lcType, string data);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern IntPtr SendMessageTimeoutW(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true)] static extern bool GetTokenInformation(IntPtr token, int cls, out int info, int len, out int retLen);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
        // Bao cho cac cua so doc lai dinh dang so, ngay (WM_SETTINGCHANGE "intl").
        public static void BroadcastIntl() { UIntPtr r; SendMessageTimeoutW(new IntPtr(0xFFFF), 0x001A, UIntPtr.Zero, "intl", 0x0002, 3000, out r); }
        // 1: tien trinh chay bang quyen Admin, 0: quyen thuong, -1: khong doc duoc.
        public static int Elevated(int pid) {
            IntPtr p = OpenProcess(0x1000, false, pid);
            if (p == IntPtr.Zero) return -1;
            try {
                IntPtr t;
                if (!OpenProcessToken(p, 0x0008, out t)) return -1;
                try { int v, n; if (!GetTokenInformation(t, 20, out v, 4, out n)) return -1; return v != 0 ? 1 : 0; }
                finally { CloseHandle(t); }
            } finally { CloseHandle(p); }
        }
    }
}
'@
}

# ---------------------------------------------------------------- đọc máy (chỉ đọc)
function Get-ImeName {
    # Tên bộ gõ theo tên file chạy (không đuôi); không phải bộ gõ thì trả $null.
    param([string]$BaseName)
    foreach ($b in $script:BoGo) { if ($BaseName -match $b.Mau) { return $b.Ten } }
    return $null
}

function Get-CommandExe {
    # File chạy trong một dòng lệnh khởi động: "C:\a b\x.exe" -tham hoặc C:\x.exe -tham.
    param([string]$Cmd)
    $c = ([string]$Cmd).Trim()
    if ($c.StartsWith('"')) { $e = $c.IndexOf('"', 1); if ($e -gt 0) { return $c.Substring(1, $e - 1) } }
    if ($c -match '(?i)^(.*?\.exe)(\s|$)') { return $Matches[1] }
    return ($c -split '\s+')[0]
}

function Get-ProcElevation {
    param([int]$ProcessId)
    try { Initialize-Native; return [TramToolTiengViet.Native]::Elevated($ProcessId) } catch { return -1 }
}

function Get-ImeProcesses {
    foreach ($p in Get-Process) {
        $ten = Get-ImeName $p.Name
        if (-not $ten) { continue }
        $path = try { [string]$p.Path } catch { '' }
        [pscustomobject]@{ Ten = $ten; TienTrinh = $p.Name; Id = $p.Id; Path = $path; Quyen = (Get-ProcElevation $p.Id) }
    }
}

function Test-StartupApproved {
    # Task Manager > Startup apps ghi bật, tắt ở khoá StartupApproved: byte đầu lẻ là đã tắt; không có giá trị là đang bật.
    param([string]$Key, [string]$Name)
    try { $v = (Get-Item -LiteralPath $Key -ErrorAction Stop).GetValue($Name) } catch { return $true }
    if ($v -is [byte[]] -and $v.Length) { return (($v[0] -band 1) -eq 0) }
    return $true
}

function Get-ImeAutostart {
    # Bộ gõ đặt khởi động cùng Windows: khoá Run, thư mục Startup (đọc đích của lối tắt), Task Scheduler.
    $approved = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $runs = @(
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Noi = 'khoá Run của tài khoản'; Duyet = "HKCU:\$approved\Run" }
        @{ Key = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Noi = 'khoá Run của cả máy'; Duyet = "HKLM:\$approved\Run" }
        @{ Key = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Noi = 'khoá Run của cả máy (32-bit)'; Duyet = "HKLM:\$approved\Run32" }
    )
    foreach ($r in $runs) {
        $k = Get-Item -LiteralPath $r.Key -ErrorAction SilentlyContinue
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            $cmd = [string]$k.GetValue($n)
            $exe = Get-CommandExe $cmd
            $ten = Get-ImeName ([IO.Path]::GetFileNameWithoutExtension($exe))
            if ($ten) { [pscustomobject]@{ Ten = $ten; Noi = "$($r.Noi): $n"; Lenh = $cmd; Bat = (Test-StartupApproved $r.Duyet $n) } }
        }
    }
    $sh = $null
    $dirs = @(
        @{ Dir = [Environment]::GetFolderPath('Startup'); Noi = 'thư mục Startup của tài khoản'; Duyet = "HKCU:\$approved\StartupFolder" }
        @{ Dir = [Environment]::GetFolderPath('CommonStartup'); Noi = 'thư mục Startup của cả máy'; Duyet = "HKLM:\$approved\StartupFolder" }
    )
    foreach ($s in $dirs) {
        if (-not $s.Dir -or -not (Test-Path -LiteralPath $s.Dir)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $s.Dir -File -ErrorAction SilentlyContinue) {
            $target = $f.FullName
            if ($f.Extension -eq '.lnk') {
                try { if (-not $sh) { $sh = New-Object -ComObject WScript.Shell }; $t = [string]$sh.CreateShortcut($f.FullName).TargetPath; if ($t) { $target = $t } } catch { }
            }
            $ten = Get-ImeName ([IO.Path]::GetFileNameWithoutExtension($target))
            if (-not $ten) { $ten = Get-ImeName $f.BaseName }
            if ($ten) { [pscustomobject]@{ Ten = $ten; Noi = "$($s.Noi): $($f.Name)"; Lenh = $target; Bat = (Test-StartupApproved $s.Duyet $f.Name) } }
        }
    }
    try {
        foreach ($t in @(Get-ScheduledTask -ErrorAction Stop)) {
            foreach ($a in @($t.Actions)) {
                $exe = ([string]$a.Execute).Trim('"', ' ')
                if (-not $exe) { continue }
                $ten = Get-ImeName ([IO.Path]::GetFileNameWithoutExtension($exe))
                if ($ten) { [pscustomobject]@{ Ten = $ten; Noi = "Task Scheduler: $($t.TaskPath)$($t.TaskName)"; Lenh = $exe; Bat = ([string]$t.State -ne 'Disabled') }; break }
            }
        }
    } catch { }
}

function Get-WindowsViInput {
    # Bàn phím tiếng Việt của Windows (bố cục 0000042A) hoặc bộ gõ Telex của Windows 11 (TIP 042A:{...}) trong danh sách
    # ngôn ngữ của tài khoản. Tiếng Việt dùng bàn phím US (042A:00000409) thì không tính.
    $tips = @()
    try {
        foreach ($l in @(Get-WinUserLanguageList)) { foreach ($t in @($l.InputMethodTips)) { if ([string]$t -match '(?i)^042A:(0000042A|\{)') { $tips += [string]$t } } }
    } catch {
        $k = Get-Item -LiteralPath 'HKCU:\Keyboard Layout\Preload' -ErrorAction SilentlyContinue
        if ($k) { foreach ($n in $k.GetValueNames()) { if ([string]$k.GetValue($n) -match '(?i)^0000042A$') { $tips += '042A:0000042A' } } }
    }
    $ten = @($tips | ForEach-Object { if ($_ -match '(?i)0000042A$') { 'bàn phím Vietnamese' } else { 'bộ gõ tiếng Việt của Windows (Telex hoặc gõ số)' } } | Select-Object -Unique)
    return [pscustomobject]@{ Co = [bool]$tips.Count; Ten = $ten }
}

function Get-LegacyFonts {
    $names = @()
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts', 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts') {
        $i = Get-Item -LiteralPath $k -ErrorAction SilentlyContinue
        if ($i) { $names += @($i.GetValueNames() | ForEach-Object { $_ -replace '\s*\((TrueType|OpenType|Type 1)\)\s*$', '' }) }
    }
    return [pscustomobject]@{
        Vni  = @($names | Where-Object { $_ -match '^(?i)VNI[- ]' } | Sort-Object -Unique)
        Tcvn = @($names | Where-Object { $_ -match '^(?i)\.Vn' } | Sort-Object -Unique)
    }
}

function Get-IntlValues {
    $p = Get-ItemProperty -LiteralPath $script:IntlKey -ErrorAction SilentlyContinue
    $r = [ordered]@{}
    foreach ($n in @($script:IntlNames.Keys) + @('LocaleName', 'sDate', 'iDate')) {
        $r[$n] = if ($p -and $null -ne $p.PSObject.Properties[$n]) { [string]$p.$n } else { $null }
    }
    return $r
}

function Get-ExcelSeparators {
    # Excel > Options > Advanced > Use system separators: UseSystemSeparators = 0 là Excel dùng dấu riêng của nó.
    foreach ($v in $script:OfficeVers) {
        $k = "$script:OfficeKey\$v\Excel\Options"
        if (-not (Test-Path -LiteralPath $k)) { continue }
        $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
        $use = if ($p -and $null -ne $p.PSObject.Properties['UseSystemSeparators']) { [int]$p.UseSystemSeparators } else { $null }
        $dec = if ($p -and $null -ne $p.PSObject.Properties['DecimalSeparator']) { [string]$p.DecimalSeparator } else { '' }
        $th = if ($p -and $null -ne $p.PSObject.Properties['ThousandsSeparator']) { [string]$p.ThousandsSeparator } else { '' }
        [pscustomobject]@{ Ver = $v; Use = $use; Dec = $dec; Th = $th }
    }
}

function Get-CodePage {
    $p = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -ErrorAction SilentlyContinue
    $loc = try { Get-WinSystemLocale } catch { $null }
    return [pscustomobject]@{ Acp = $(if ($p) { [string]$p.ACP } else { '' }); Locale = [string]$loc.Name; LocaleTen = [string]$loc.DisplayName }
}

function Test-AppRunning { param([string]$Name) return [bool](Get-Process -Name $Name -ErrorAction SilentlyContinue) }

function Find-PythonCmd {
    # Python 3.9 trở lên: python trong PATH, không có thì py -3.
    foreach ($c in @(@{ Exe = 'python'; Pre = @() }, @{ Exe = 'py'; Pre = @('-3') })) {
        $cmd = Get-Command $c.Exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { continue }
        $pre = @($c.Pre)
        $ErrorActionPreference = 'Continue'
        $v = & $cmd.Source @pre -c 'import sys; print(sys.version_info[0] * 100 + sys.version_info[1])' 2>$null
        $ok = $LASTEXITCODE -eq 0
        $ErrorActionPreference = 'Stop'
        if ($ok -and ([string]($v | Select-Object -Last 1)) -match '^\d+$' -and [int]($v | Select-Object -Last 1) -ge 309) {
            return [pscustomobject]@{ Exe = $cmd.Source; Pre = $c.Pre }
        }
    }
    return $null
}

function Format-OfficeVer { param([string]$Ver) switch ($Ver) { '16.0' { 'Office 2016 trở về sau, Microsoft 365' } '15.0' { 'Office 2013' } '14.0' { 'Office 2010' } default { "Office $Ver" } } }

function Format-Quyen {
    param([int]$Q)
    switch ($Q) { 1 { 'quyền Admin' } 0 { 'quyền thường' } default { if (Test-IsAdmin) { 'không đọc được quyền' } else { 'có lẽ quyền Admin' } } }
}

function Get-MatchingPreset {
    param($Values)
    foreach ($k in $script:MauDinhDang.Keys) {
        $g = $script:MauDinhDang[$k].GiaTri
        if ($Values.sDecimal -ceq $g.sDecimal -and $Values.sThousand -ceq $g.sThousand -and $Values.sList -ceq $g.sList) { return $k }
    }
    return ''
}

function Get-DateOrder {
    # Thứ tự ngày, tháng, năm trong mẫu ngày ngắn: chữ cái đầu tiên trong d, M, y.
    param([string]$Pattern)
    $m = [regex]::Match([string]$Pattern, '[dMy]')
    if ($m.Success) { return $m.Value }
    return ''
}

# ---------------------------------------------------------------- đổi máy (tài khoản đang dùng, không cần Admin)
function Set-IntlValue {
    param([string]$Name, [string]$Value)
    if ($script:RegRoot -ne 'HKCU:') {
        if (-not (Test-Path -LiteralPath $script:IntlKey)) { New-Item -Path $script:IntlKey -Force | Out-Null }
        Set-ItemProperty -LiteralPath $script:IntlKey -Name $Name -Value $Value -Type String
        return $true
    }
    Initialize-Native
    return [TramToolTiengViet.Native]::SetLocaleInfoW(0x400, [uint32]$script:IntlNames[$Name].Lc, $Value)
}

function Send-IntlChange {
    if ($script:RegRoot -ne 'HKCU:') { return }
    try { Initialize-Native; [TramToolTiengViet.Native]::BroadcastIntl() } catch { }
}

function Set-ExcelUseSystem {
    # $Value $null: xoá giá trị (Excel mặc định dùng dấu của Windows).
    param([string]$Ver, $Value)
    $k = "$script:OfficeKey\$Ver\Excel\Options"
    if ($null -eq $Value) { Remove-ItemProperty -LiteralPath $k -Name 'UseSystemSeparators' -ErrorAction SilentlyContinue }
    else { Set-ItemProperty -LiteralPath $k -Name 'UseSystemSeparators' -Value ([int]$Value) -Type DWord }
    return $true
}

# ---------------------------------------------------------------- trạng thái gốc
function Read-SavedState {
    if (-not (Test-Path -LiteralPath $script:StateFile)) { return $null }
    try { return ([IO.File]::ReadAllText($script:StateFile) | ConvertFrom-Json) }
    catch { throw "File trạng thái gốc bị hỏng: $script:StateFile. Đổi tên hoặc chép file đó đi chỗ khác rồi chạy lại." }
}

function Save-OriginalState {
    # Lưu giá trị trước khi đổi; mục đã lưu từ lần đổi trước thì giữ nguyên (để Trả lại về đúng lúc đầu).
    param([string[]]$Intl = @(), [string[]]$Excel = @())
    $old = Read-SavedState
    $dd = [ordered]@{}
    if ($old -and $old.dinhDang) { foreach ($p in $old.dinhDang.PSObject.Properties) { $dd[$p.Name] = $p.Value } }
    $now = Get-IntlValues
    foreach ($n in $Intl) { if (-not $dd.Contains($n)) { $dd[$n] = $now[$n] } }
    $ex = [ordered]@{}
    if ($old -and $old.excel) { foreach ($p in $old.excel.PSObject.Properties) { $ex[$p.Name] = [ordered]@{ co = [bool]$p.Value.co; gia = $p.Value.gia } } }
    $cur = @(Get-ExcelSeparators)
    foreach ($v in $Excel) {
        if ($ex.Contains($v)) { continue }
        $e = @($cur | Where-Object { $_.Ver -eq $v })[0]
        $ex[$v] = [ordered]@{ co = [bool]($e -and $null -ne $e.Use); gia = $(if ($e) { $e.Use } else { $null }) }
    }
    $doc = [ordered]@{
        may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
        luuLuc = $(if ($old -and $old.luuLuc) { [string]$old.luuLuc } else { (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') })
        ghiChu = 'Định dạng số, ngày và tuỳ chọn Excel trước lần đổi đầu tiên của Gói tiếng Việt; "Trả lại" dùng file này.'
        dinhDang = $dd; excel = $ex
    }
    if (-not (Test-Path -LiteralPath $script:ResultDir)) { New-Item -ItemType Directory -Path $script:ResultDir -Force | Out-Null }
    $tmp = "$script:StateFile.tmp"
    [IO.File]::WriteAllText($tmp, ($doc | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $script:StateFile -Force
}

# ---------------------------------------------------------------- phát hiện
function Add-Finding {
    # Một phát hiện theo chuẩn tramtool.ketqua/1; $Tiep 'cong-cu/action' là nút gợi ý chạy tiếp trong Trạm.
    param([string]$Ma, [string]$Muc, [string]$TieuDe, [string]$ChiTiet = '', [string]$CachSua = '', [string]$Tiep = '')
    $f = [ordered]@{ ma = $Ma; mucDo = $Muc; tieuDe = $TieuDe; chiTiet = $ChiTiet; cachSua = $CachSua }
    if ($Tiep -match '^([a-z0-9-]+)/([A-Za-z0-9_-]+)$') { $f['chayTiep'] = [ordered]@{ congCu = $Matches[1]; action = $Matches[2] } }
    [void]$script:Findings.Add($f)
    switch ($Muc) { 'loi' { Write-Bad $TieuDe } 'canh-bao' { Write-Warn $TieuDe } 'thong-tin' { Write-Info $TieuDe } default { Write-Ok $TieuDe } }
    if ($ChiTiet) { Write-Sub $ChiTiet }
}

function Invoke-BoGoCheck {
    Write-Head 'Bộ gõ tiếng Việt'
    $procs = @(Get-ImeProcesses)
    $auto = @(Get-ImeAutostart)
    $win = Get-WindowsViInput
    $names = @($procs | ForEach-Object { $_.Ten } | Select-Object -Unique)
    $sua2 = 'Thoát bớt một bộ (chuột phải biểu tượng bộ gõ ở góc màn hình, chọn Thoát) và bỏ nó khỏi khởi động cùng Windows (Task Manager > Startup apps); muốn gỡ hẳn thì vào Cài đặt > Ứng dụng.'
    if ($names.Count -ge 2) {
        Add-Finding 'BO_GO_TRUNG' 'loi' ('{0} bộ gõ đang chạy cùng lúc: {1}' -f $names.Count, ($names -join ', ')) 'Hai bộ gõ cùng bắt phím nên gõ ra dấu lặp, mất dấu hoặc chữ nhảy lung tung.' $sua2
    } elseif ($names.Count -eq 1) {
        $p = $procs[0]
        Add-Finding 'BO_GO_DANG_CHAY' 'ok' ('Bộ gõ {0} đang chạy ({1})' -f $p.Ten, (Format-Quyen $p.Quyen)) $p.Path
    }
    foreach ($g in @($procs | Group-Object Ten | Where-Object { $_.Count -gt 1 })) {
        Add-Finding 'BO_GO_CHAY_HAI_LAN' 'canh-bao' ('{0} đang chạy {1} lần' -f $g.Name, $g.Count) ('Tiến trình: {0}. Hai bản của cùng một bộ gõ cũng làm gõ sai dấu.' -f (($g.Group | ForEach-Object { '{0} ({1})' -f $_.TienTrinh, $_.Id }) -join ', ')) 'Thoát hết rồi mở lại một lần; bỏ chỗ khởi động thừa.'
    }
    if ($procs.Count -and -not @($procs | Where-Object { $_.Quyen -ne 0 }).Count) {
        Add-Finding 'BO_GO_QUYEN_THUONG' 'thong-tin' 'Bộ gõ chạy bằng quyền thường: phần mềm mở bằng quyền Admin sẽ không gõ được dấu' 'Windows không cho chương trình quyền thường gửi phím vào cửa sổ quyền Admin (phần mềm kế toán, quản lý cài đặt chạy bằng Admin).' 'Gặp phần mềm như vậy thì cho bộ gõ chạy bằng quyền Admin (EVKey, OpenKey có sẵn tuỳ chọn này trong bảng cài đặt).'
    }

    $on = @($auto | Where-Object { $_.Bat })
    $autoNames = @($on | ForEach-Object { $_.Ten } | Select-Object -Unique)
    if ($autoNames.Count -ge 2) {
        Add-Finding 'BO_GO_KHOI_DONG_TRUNG' 'canh-bao' ('{0} bộ gõ cùng khởi động với Windows: {1}' -f $autoNames.Count, ($autoNames -join ', ')) (($on | ForEach-Object { '{0} ({1})' -f $_.Ten, $_.Noi }) -join '; ') 'Tắt bớt một bộ trong Task Manager (Ctrl+Shift+Esc) > Startup apps.'
    }
    foreach ($g in @($on | Group-Object Ten | Where-Object { $_.Count -gt 1 })) {
        Add-Finding 'BO_GO_KHOI_DONG_HAI_LAN' 'canh-bao' ('{0} được đặt khởi động ở {1} chỗ' -f $g.Name, $g.Count) (($g.Group | ForEach-Object { $_.Noi }) -join '; ') 'Mỗi lần mở máy bộ gõ chạy hai bản. Giữ một chỗ: tắt bớt trong Task Manager > Startup apps.'
    }
    if (-not $procs.Count) {
        if ($on.Count) {
            Add-Finding 'BO_GO_CHUA_CHAY' 'canh-bao' ('{0} có khởi động cùng Windows nhưng đang không chạy' -f ($autoNames -join ', ')) (($on | ForEach-Object { $_.Noi }) -join '; ') 'Mở lại bộ gõ từ menu Start. Mở máy lần sau vẫn không tự chạy thì cài lại bộ gõ (công cụ Bộ ứng dụng).' 'bo-ung-dung/kiem-tra'
        } elseif ($win.Co) {
            Add-Finding 'BAN_PHIM_WINDOWS' 'ok' ('Gõ tiếng Việt bằng {0}' -f ($win.Ten -join ', ')) 'Không có bộ gõ ngoài (UniKey, EVKey...). Đổi bàn phím bằng Windows + Space.'
        } else {
            Add-Finding 'KHONG_CO_BO_GO' 'canh-bao' 'Không thấy bộ gõ tiếng Việt nào' 'Không có UniKey, EVKey, OpenKey... đang chạy, cũng không có bàn phím tiếng Việt của Windows.' 'Cài UniKey hoặc EVKey bằng công cụ Bộ ứng dụng; hoặc thêm bàn phím tiếng Việt ở Cài đặt > Thời gian và ngôn ngữ > Ngôn ngữ và vùng.' 'bo-ung-dung/cai'
        }
    } elseif ($win.Co) {
        Add-Finding 'BAN_PHIM_WINDOWS_TRUNG' 'canh-bao' ('Bàn phím tiếng Việt của Windows bật cùng {0}' -f ($names -join ', ')) ('Có {0}. Lỡ chuyển sang nó (Windows + Space) thì phím số, phím chữ ra dấu theo kiểu của Windows chồng lên bộ gõ: gõ ra dấu lặp, chữ lạ.' -f ($win.Ten -join ', ')) 'Cài đặt > Thời gian và ngôn ngữ > Ngôn ngữ và vùng: ở Tiếng Việt chọn Tuỳ chọn ngôn ngữ, xoá bàn phím Vietnamese (hoặc bỏ cả ngôn ngữ Tiếng Việt nếu không cần).'
    }
}

function Invoke-FontCheck {
    Write-Head 'Font VNI, TCVN3'
    $f = Get-LegacyFonts
    $n = $f.Vni.Count + $f.Tcvn.Count
    if ($n) {
        $mau = @(@($f.Vni) + @($f.Tcvn) | Select-Object -First 8) -join ', '
        Add-Finding 'FONT_CU_CO' 'thong-tin' ('Máy có {0} font VNI, {1} font TCVN3 (.Vn)' -f $f.Vni.Count, $f.Tcvn.Count) $mau 'Tài liệu gõ bằng font này đọc được trên máy này nhưng sai dấu trên máy không có font. Gửi đi thì chuyển bản sao sang Unicode trước.' 'tieng-viet/chuyen'
    } else {
        Add-Finding 'FONT_CU_KHONG' 'thong-tin' 'Máy không có font VNI, TCVN3 (.Vn)' 'Tài liệu cũ gõ bằng VNI-Times, .VnTime... sẽ hiện sai dấu (kiểu "Coäng hoøa", "Céng hoµ").' 'Chuyển bản sao tài liệu sang Unicode bằng nút Chuyển tài liệu sang Unicode, không cần cài font cũ.' 'tieng-viet/chuyen'
    }
}

function Invoke-DinhDangCheck {
    Write-Head 'Định dạng số và ngày'
    $v = Get-IntlValues
    $dec = $v.sDecimal; $th = $v.sThousand; $li = $v.sList
    $tiep = 'tieng-viet/dinh-dang'
    $sua = 'Bấm Đặt định dạng số và ngày, chọn kiểu Việt Nam hoặc quốc tế.'
    if ($null -eq $dec -or $null -eq $th) {
        Add-Finding 'DINH_DANG_KHONG_DOC_DUOC' 'canh-bao' 'Không đọc được định dạng số của tài khoản' $script:IntlKey
    } elseif ($dec -ceq $th) {
        Add-Finding 'SO_TRUNG_DAU' 'loi' ('Dấu thập phân và dấu phân cách nghìn cùng là "{0}"' -f $dec) 'Excel, phần mềm kế toán đọc sai số: 1.500 có thể thành 1,5 hoặc 1500.' $sua $tiep
    } elseif ($null -ne $li -and $li -ceq $dec) {
        Add-Finding 'DANH_SACH_TRUNG_THAP_PHAN' 'loi' ('Dấu ngăn danh sách trùng dấu thập phân ("{0}")' -f $dec) 'Công thức Excel có số lẻ bị hiểu sai tham số; file CSV mở ra lệch cột.' $sua $tiep
    } else {
        $m = Get-MatchingPreset $v
        if ($m) {
            Add-Finding 'SO_DINH_DANG' 'ok' ('Số {0}' -f ($script:MauDinhDang[$m].Ten -replace '; ngày.*$', '')) ('Thập phân "{0}", nghìn "{1}", ngăn danh sách "{2}".' -f $dec, $th, $li)
        } else {
            Add-Finding 'SO_DINH_DANG_KHAC' 'thong-tin' ('Định dạng số riêng: thập phân "{0}", nghìn "{1}", ngăn danh sách "{2}"' -f $dec, $th, $li) 'Không giống kiểu Việt Nam hay kiểu quốc tế thường dùng; file Excel, CSV gửi qua lại dễ lệch số.' $sua $tiep
        }
        if (($null -ne $v.sMonDecimalSep -and $v.sMonDecimalSep -cne $dec) -or ($null -ne $v.sMonThousandSep -and $v.sMonThousandSep -cne $th)) {
            Add-Finding 'SO_TIEN_KHAC' 'canh-bao' 'Định dạng tiền khác định dạng số' ('Tiền: thập phân "{0}", nghìn "{1}"; số: "{2}", "{3}". Phần mềm kế toán theo định dạng tiền sẽ hiện, nhận số khác Excel.' -f $v.sMonDecimalSep, $v.sMonThousandSep, $dec, $th) $sua $tiep
        }
    }
    $sd = $v.sShortDate
    switch (Get-DateOrder $sd) {
        'M' { Add-Finding 'NGAY_THANG_TRUOC' 'canh-bao' ('Ngày dạng tháng trước ({0}): 05/10/2026 là ngày 10 tháng 5' -f $sd) 'Gõ ngày kiểu Việt Nam (ngày/tháng/năm) vào Excel bị hiểu sai hoặc thành chữ; phần mềm kế toán, hoá đơn lệch ngày.' $sua $tiep }
        'y' { Add-Finding 'NGAY_NAM_TRUOC' 'thong-tin' ('Ngày dạng năm trước ({0})' -f $sd) 'Đúng chuẩn quốc tế; người quen ngày/tháng/năm dễ đọc nhầm.' }
        'd' {
            if ($sd -cnotmatch 'yyyy') { Add-Finding 'NGAY_NAM_HAI_SO' 'thong-tin' ('Năm trong ngày chỉ có 2 số ({0})' -f $sd) 'Ngày năm 1999 và 2099 trông như nhau.' $sua $tiep }
            else { Add-Finding 'NGAY_DINH_DANG' 'ok' ('Ngày dạng {0}' -f $sd) }
        }
        default { Add-Finding 'NGAY_KHONG_DOC_DUOC' 'canh-bao' 'Không đọc được mẫu ngày ngắn của tài khoản' ([string]$sd) }
    }

    foreach ($e in @(Get-ExcelSeparators)) {
        if ($e.Use -ne 0) { continue }
        $muc = if ($e.Dec -and $e.Dec -ceq $e.Th) { 'loi' } else { 'canh-bao' }
        Add-Finding 'EXCEL_DAU_RIENG' $muc ('Excel ({0}) dùng dấu riêng: thập phân "{1}", nghìn "{2}"' -f (Format-OfficeVer $e.Ver), $e.Dec, $e.Th) 'Tuỳ chọn Use system separators của Excel đang tắt: đổi định dạng của Windows không có tác dụng trong Excel.' 'Bấm Đặt định dạng số và ngày (để dấu chọn Excel dùng dấu của Windows), hoặc bật lại Use system separators ở File > Options > Advanced của Excel.' $tiep
    }

    $s = $null
    try { $s = Read-SavedState } catch { Add-Finding 'TRANG_THAI_GOC_HONG' 'canh-bao' 'File giá trị cũ để trả lại bị hỏng' $_.Exception.Message }
    if ($s) { Add-Finding 'DA_DOI_DINH_DANG' 'thong-tin' ('Công cụ đã đổi định dạng lúc {0}' -f $s.luuLuc) 'Giá trị cũ còn lưu, trả lại được.' 'Muốn về như cũ thì bấm Trả định dạng về như trước khi đổi.' 'tieng-viet/tra-lai' }
}

function Invoke-NgonNguCheck {
    Write-Head 'Chương trình cũ không dùng Unicode'
    $cp = Get-CodePage
    if ($cp.Acp -eq '65001') {
        Add-Finding 'UTF8_BETA' 'canh-bao' 'Đang bật "Beta: Use Unicode UTF-8 for worldwide language support"' 'Phần mềm cũ (kế toán, quản lý viết lâu năm, phần mềm dùng font VNI, TCVN3) có thể hiện sai chữ hoặc báo lỗi.' 'Chỉ khi có phần mềm bị lỗi: Cài đặt > Thời gian và ngôn ngữ > Ngôn ngữ và vùng > Cài đặt ngôn ngữ quản trị > Thay đổi ngôn ngữ hệ thống, bỏ dấu Beta, khởi động lại máy (cần quyền Admin).'
    }
    if ($cp.Locale -like 'vi*') {
        Add-Finding 'NGON_NGU_HE_THONG' 'ok' ('Ngôn ngữ cho chương trình không Unicode: {0}' -f $cp.LocaleTen)
    } elseif ($cp.Locale) {
        Add-Finding 'NGON_NGU_HE_THONG' 'thong-tin' ('Ngôn ngữ cho chương trình không Unicode: {0} (bảng mã {1})' -f $cp.LocaleTen, $cp.Acp) 'Phần mềm mới không cần đổi. Phần mềm cũ không dùng Unicode mà hiện tiếng Việt sai thì đổi mục này sang Vietnamese (Vietnam).' 'Cài đặt > Thời gian và ngôn ngữ > Ngôn ngữ và vùng > Cài đặt ngôn ngữ quản trị > Thay đổi ngôn ngữ hệ thống (cần quyền Admin, khởi động lại máy).'
    }
}

function Invoke-AllChecks {
    $script:Findings.Clear()
    Invoke-BoGoCheck
    Invoke-FontCheck
    Invoke-DinhDangCheck
    Invoke-NgonNguCheck
}

function Save-RunResult {
    # Ghi kết quả lần chạy cho Trạm Tool (chuẩn tramtool.ketqua/1).
    param([string]$CheDo, [int]$Code, [datetime]$Start, [string]$Message = '')
    $i = 0
    $sorted = @($script:Findings | ForEach-Object { [pscustomobject]@{ F = $_; L = $script:Levels[[string]$_.mucDo]; I = $i++ } } | Sort-Object L, I | ForEach-Object { $_.F })
    $nLoi = @($sorted | Where-Object { $_.mucDo -eq 'loi' }).Count
    $nCanh = @($sorted | Where-Object { $_.mucDo -eq 'canh-bao' }).Count
    $nTin = @($sorted | Where-Object { $_.mucDo -eq 'thong-tin' }).Count
    if (-not $Message) {
        $Message = if ($nLoi + $nCanh) { 'Có {0} lỗi, {1} cảnh báo về bộ gõ, font hoặc định dạng số, ngày; xem gợi ý sửa.' -f $nLoi, $nCanh } else { 'Bộ gõ, font và định dạng số, ngày không có gì cần sửa.' }
    }
    $tep = @()
    if (Test-Path -LiteralPath $script:StateFile) { $tep += [ordered]@{ nhan = 'Giá trị cũ để trả lại'; duongDan = $script:StateFile } }
    $r = [ordered]@{
        chuan = 'tramtool.ketqua/1'; congCu = 'tieng-viet'; cheDo = $CheDo; phienBan = $script:Version
        may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
        batDau = $Start.ToString('s'); ketThuc = (Get-Date).ToString('s')
        maThoat = $Code; trangThai = @{ 0 = 'xong'; 1 = 'loi'; 2 = 'thieu-dieu-kien'; 3 = 'mot-phan' }[$Code]
        chayThu = [bool]$ChayThu
        ma = $(if ($nLoi + $nCanh) { 'CO_CANH_BAO' } else { 'KHONG_CO_CANH_BAO' })
        thongDiep = $Message
        tomTat = [ordered]@{ loi = $nLoi; canhBao = $nCanh; thongTin = $nTin }
        phatHien = $sorted
        tep = $tep
    }
    try {
        if (-not (Test-Path -LiteralPath $script:ResultDir)) { New-Item -ItemType Directory -Path $script:ResultDir -Force | Out-Null }
        $f = Join-Path $script:ResultDir ('KetQua_TiengViet_{0}_{1:yyyyMMdd_HHmmss}.json' -f $env:COMPUTERNAME, $Start)
        $tmp = "$f.tmp"
        [IO.File]::WriteAllText($tmp, ($r | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding $false))
        Move-Item -LiteralPath $tmp -Destination $f -Force
        Write-Info "Kết quả cho Trạm Tool: $f"
    } catch { Write-Warn "Không ghi được file kết quả: $($_.Exception.Message.Trim())" }
}

# ---------------------------------------------------------------- chế độ
function Invoke-Ops {
    # Làm từng việc, đọc lại để chắc đã đổi. Trả @{ Fail; Intl } (Intl: có đổi định dạng Windows).
    param($Ops)
    $fail = 0; $intl = $false
    foreach ($o in $Ops) {
        $ok = $false
        try {
            if ($o.Kind -eq 'intl') {
                $ok = (Set-IntlValue $o.Name $o.New) -and ((Get-IntlValues)[$o.Name] -ceq $o.New)
                $intl = $true
            } else {
                $ok = Set-ExcelUseSystem $o.Name $o.New
                $e = @(@(Get-ExcelSeparators) | Where-Object { $_.Ver -eq $o.Name })[0]
                $ok = $ok -and $e -and ((($null -eq $o.New) -and ($null -eq $e.Use)) -or ($null -ne $o.New -and $e.Use -eq [int]$o.New))
            }
        } catch { $ok = $false; Write-Sub $_.Exception.Message.Trim() }
        if ($ok) { Write-Ok $o.Text } else { Write-Bad "Chưa đổi được: $($o.Text)"; $fail++ }
    }
    if ($intl) { Send-IntlChange }
    return [pscustomobject]@{ Fail = $fail }
}

function Remove-ExcelOpsIfRunning {
    # Excel ghi đè tuỳ chọn của nó khi đóng: đang mở thì bỏ việc đổi tuỳ chọn Excel, báo đóng Excel rồi chạy lại.
    param($Ops)
    if (-not @($Ops | Where-Object { $_.Kind -eq 'excel' }).Count -or -not (Test-AppRunning 'EXCEL')) { return [pscustomobject]@{ Ops = @($Ops); Skip = 0 } }
    Write-Warn 'Excel đang mở nên chưa đổi tuỳ chọn của Excel (Excel ghi đè khi đóng). Đóng Excel rồi chạy lại.'
    $keep = @($Ops | Where-Object { $_.Kind -ne 'excel' })
    return [pscustomobject]@{ Ops = $keep; Skip = @($Ops).Count - $keep.Count }
}

function Invoke-DinhDang {
    param([string]$Preset, [bool]$Excel, [switch]$DryRun, [switch]$Ask)
    $m = $script:MauDinhDang[$Preset]
    Write-Head ('Đặt định dạng {0}' -f ($m.Ten -replace ':.*$', ''))
    Write-Line $m.Ten
    $now = Get-IntlValues
    $ops = @()
    foreach ($k in $m.GiaTri.Keys) {
        if ([string]$now[$k] -cne $m.GiaTri[$k]) { $ops += [pscustomobject]@{ Kind = 'intl'; Name = $k; New = $m.GiaTri[$k]; Text = ('{0}: "{1}" -> "{2}"' -f $script:IntlNames[$k].Ten, $now[$k], $m.GiaTri[$k]) } }
    }
    if ($Excel) {
        foreach ($e in @(Get-ExcelSeparators)) {
            if ($e.Use -eq 0) { $ops += [pscustomobject]@{ Kind = 'excel'; Name = $e.Ver; New = 1; Text = ('Excel ({0}): dùng dấu của Windows thay cho dấu riêng "{1}", "{2}"' -f (Format-OfficeVer $e.Ver), $e.Dec, $e.Th) } }
        }
    }
    if (-not $ops.Count) { Write-Ok 'Định dạng đã đúng như chọn, không cần đổi.'; return 0 }
    Write-Line 'Sẽ làm (chỉ cho tài khoản đang dùng, không cần quyền Admin):'
    foreach ($o in $ops) { Write-Plan $o.Text }
    if ($DryRun) { Write-Info 'Chạy thử: không đổi gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo 'Làm các việc trên?' $true)) { Write-Info 'Đã huỷ, chưa đổi gì.'; return 2 }
    $r = Remove-ExcelOpsIfRunning $ops
    if (-not $r.Ops.Count) { return 3 }
    Save-OriginalState -Intl @($r.Ops | Where-Object { $_.Kind -eq 'intl' } | ForEach-Object { $_.Name }) -Excel @($r.Ops | Where-Object { $_.Kind -eq 'excel' } | ForEach-Object { $_.Name })
    Write-Info ('Đã lưu giá trị cũ vào {0}' -f $script:StateFile)
    $x = Invoke-Ops $r.Ops
    Write-Info 'Excel, Word, phần mềm kế toán đang mở cần mở lại mới nhận định dạng mới.'
    if ($x.Fail -eq $r.Ops.Count) { return 1 }
    if ($x.Fail -or $r.Skip) { return 3 }
    return 0
}

function Invoke-TraLai {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head 'Trả định dạng về như trước khi đổi'
    try { $s = Read-SavedState } catch { Write-Bad $_.Exception.Message; return 1 }
    if (-not $s) { Write-Info 'Chưa có giá trị cũ nào được lưu (công cụ chưa đổi định dạng của tài khoản này trên máy này).'; return 0 }
    Write-Line "Giá trị lưu lúc $($s.luuLuc):"
    $ops = @()
    $now = Get-IntlValues
    if ($s.dinhDang) {
        foreach ($p in $s.dinhDang.PSObject.Properties) {
            if ($null -eq $p.Value -or -not $script:IntlNames.Contains($p.Name)) { continue }
            if ([string]$now[$p.Name] -cne [string]$p.Value) { $ops += [pscustomobject]@{ Kind = 'intl'; Name = $p.Name; New = [string]$p.Value; Text = ('{0}: "{1}" -> "{2}"' -f $script:IntlNames[$p.Name].Ten, $now[$p.Name], $p.Value) } }
        }
    }
    if ($s.excel) {
        $cur = @(Get-ExcelSeparators)
        foreach ($p in $s.excel.PSObject.Properties) {
            $e = @($cur | Where-Object { $_.Ver -eq $p.Name })[0]
            if (-not $e) { continue }
            $want = if ($p.Value.co) { [int]$p.Value.gia } else { $null }
            if (($null -eq $want -and $null -ne $e.Use) -or ($null -ne $want -and $e.Use -ne $want)) {
                $txt = if ($null -eq $want) { 'bỏ giá trị UseSystemSeparators (như lúc chưa đặt)' } elseif ($want -eq 0) { 'dùng lại dấu riêng của Excel' } else { "UseSystemSeparators = $want" }
                $ops += [pscustomobject]@{ Kind = 'excel'; Name = $p.Name; New = $want; Text = ('Excel ({0}): {1}' -f (Format-OfficeVer $p.Name), $txt) }
            }
        }
    }
    if (-not $ops.Count) {
        Write-Ok 'Định dạng đang đúng như giá trị đã lưu, không cần đổi.'
        if (-not $DryRun) { Remove-Item -LiteralPath $script:StateFile -Force -ErrorAction SilentlyContinue }
        return 0
    }
    Write-Line 'Sẽ làm:'
    foreach ($o in $ops) { Write-Plan $o.Text }
    if ($DryRun) { Write-Info 'Chạy thử: không đổi gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo 'Làm các việc trên?' $true)) { Write-Info 'Đã huỷ, chưa đổi gì.'; return 2 }
    $r = Remove-ExcelOpsIfRunning $ops
    if (-not $r.Ops.Count) { return 3 }
    $x = Invoke-Ops $r.Ops
    if ($x.Fail -or $r.Skip) {
        Write-Warn 'Còn mục chưa trả được; giữ file giá trị cũ để chạy lại.'
        return $(if ($x.Fail -eq $r.Ops.Count) { 1 } else { 3 })
    }
    Remove-Item -LiteralPath $script:StateFile -Force -ErrorAction SilentlyContinue
    Write-Ok 'Đã trả lại hết; xoá file giá trị cũ.'
    Write-Info 'Excel, Word, phần mềm kế toán đang mở cần mở lại mới nhận định dạng cũ.'
    return 0
}

function Invoke-Mode {
    # Chạy một chế độ, kiểm tra lại máy và ghi file kết quả. Trả mã thoát.
    param([string]$Id, [switch]$Ask)
    $start = Get-Date
    $code = 0; $msg = ''
    try {
        switch ($Id) {
            'kiem-tra' { $code = 0 }
            'dinh-dang' { $code = Invoke-DinhDang -Preset $Mau -Excel ([bool]$ExcelTheoWindows) -DryRun:$ChayThu -Ask:$Ask }
            'tra-lai' { $code = Invoke-TraLai -DryRun:$ChayThu -Ask:$Ask }
        }
    } catch {
        Write-Bad ('Lỗi không lường trước: {0}' -f $_.Exception.Message.Trim())
        $code = 1
    }
    if ($Id -ne 'kiem-tra') {
        $msg = switch ($code) {
            0 { if ($ChayThu) { 'Chạy thử: chỉ xem việc sẽ làm, máy không bị đổi.' } else { '{0}: xong.' -f $script:Modes[$Id].Label } }
            2 { 'Chưa làm: đã huỷ.' }
            3 { '{0}: làm được một phần.' -f $script:Modes[$Id].Label }
            default { '{0}: lỗi, xem cửa sổ công cụ.' -f $script:Modes[$Id].Label }
        }
    }
    Invoke-AllChecks   # kiểm tra (lại) sau khi đổi: kết quả ghi cho trạm là trạng thái máy lúc này
    Save-RunResult -CheDo $Id -Code $code -Start $start -Message $msg
    return $code
}

function Invoke-ChuyenMenu {
    Write-Head 'Chuyển tài liệu font VNI, TCVN3 sang Unicode'
    Write-Line 'Tạo bản sao <tên>_Unicode cạnh file gốc (.docx, .docm, .xlsx, .xlsm); file gốc không bị đổi.'
    $py = Find-PythonCmd
    if (-not $py) {
        Write-Bad 'Cần Python 3.9 trở lên mà máy chưa có.'
        Write-Sub 'Cài bằng nút Cài trong Trạm Tool, hoặc gõ: winget install -e --id Python.Python.3.12 --scope user'
        return 2
    }
    Write-Line 'Kéo thả file hoặc thư mục vào cửa sổ này rồi bấm Enter (bỏ trống để quay lại).'
    $s = Read-Text 'File hoặc thư mục' ''
    if (-not $s) { return 0 }
    $paths = @([regex]::Matches($s, '"([^"]+)"|(\S+)') | ForEach-Object { if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } })
    $a = @($py.Pre) + @('-X', 'utf8', (Join-Path $PSScriptRoot 'chuyen_unicode.py')) + $paths
    if (@($paths | Where-Object { Test-Path -LiteralPath $_ -PathType Container }).Count -and (Read-YesNo 'Tìm cả trong thư mục con?' $false)) { $a += '--de-quy' }
    $env:PYTHONDONTWRITEBYTECODE = '1'
    & $py.Exe @a | Out-Host
    return $LASTEXITCODE
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '  GÓI TIẾNG VIỆT' -ForegroundColor Cyan
        Write-Host '  Bộ gõ, font VNI và TCVN3, định dạng số và ngày; chuyển tài liệu font cũ sang Unicode.' -ForegroundColor Gray
        Write-Host ''
        Write-Host '   1. Kiểm tra bộ gõ, font, định dạng số và ngày (chỉ đọc)'
        Write-Host '   2. Đặt định dạng kiểu Việt Nam: 1.234,5; công thức Excel =SUM(A1;B1); ngày 31/12/2026'
        Write-Host '   3. Đặt định dạng kiểu quốc tế: 1,234.5; công thức Excel =SUM(A1,B1); ngày 31/12/2026'
        Write-Host '   4. Chuyển tài liệu font VNI, TCVN3 sang Unicode (tạo bản sao)'
        Write-Host '   5. Trả định dạng về như trước khi đổi'
        Write-Host '   0. Thoát'
        Write-Host ''
        $c = Read-Text 'Chọn số' '0'
        switch ($c) {
            '0' { return 0 }
            '1' { [void](Invoke-Mode 'kiem-tra' -Ask) }
            '2' { $script:Mau = 'vn'; $script:ExcelTheoWindows = [switch]$true; [void](Invoke-Mode 'dinh-dang' -Ask) }
            '3' { $script:Mau = 'quoc-te'; $script:ExcelTheoWindows = [switch]$true; [void](Invoke-Mode 'dinh-dang' -Ask) }
            '4' { [void](Invoke-ChuyenMenu) }
            '5' { [void](Invoke-Mode 'tra-lai' -Ask) }
            default { continue }
        }
        Wait-Close 'Bấm Enter để về menu'
    }
}

# ---------------------------------------------------------------- bắt đầu
if ($env:TRAMTOOL_TIENGVIET_TEST) { return }   # bài thử nạp các hàm rồi tự gọi
try { $Host.UI.RawUI.WindowTitle = 'Gói tiếng Việt' } catch { }
if ($Mode -and -not $script:Modes.Contains($Mode)) {
    Write-Bad ('Không có chế độ "{0}". Các chế độ: {1}.' -f $Mode, (@($script:Modes.Keys) -join ', '))
    Wait-Close
    exit 1
}
if (-not $script:MauDinhDang.Contains($Mau)) {
    Write-Bad ('Không có kiểu định dạng "{0}". Các kiểu: {1}.' -f $Mau, (@($script:MauDinhDang.Keys) -join ', '))
    Wait-Close
    exit 1
}
if (-not $Mode) {
    if ([Console]::IsInputRedirected) { Write-Host 'Cách dùng: TiengViet.ps1 -Mode kiem-tra|dinh-dang|tra-lai [-Mau vn|quoc-te] [-ExcelTheoWindows] [-ChayThu] [-KhongDung]'; exit 1 }
    exit (Show-Menu)
}
$code = Invoke-Mode $Mode
Wait-Close
exit $code
