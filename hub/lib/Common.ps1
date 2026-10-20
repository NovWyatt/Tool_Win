# Trạm Tool - hàm dùng chung (PowerShell 5.1+)
# File này phải lưu UTF-8 có BOM, nếu không PowerShell 5.1 đọc sai chữ tiếng Việt.

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-Prop {
    # Đọc thuộc tính an toàn từ PSCustomObject/hashtable, thiếu thì trả $Default.
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name) -and $null -ne $Object[$Name]) { return $Object[$Name] }
        return $Default
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p -and $null -ne $p.Value) { return $p.Value }
    return $Default
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    return ($text | ConvertFrom-Json)
}

function ConvertTo-HubJson {
    param($InputObject, [switch]$Compress)
    if ($Compress) { return (ConvertTo-Json -InputObject $InputObject -Depth 12 -Compress) }
    return (ConvertTo-Json -InputObject $InputObject -Depth 12)
}

function Write-JsonFile {
    param([Parameter(Mandatory)][string]$Path, $InputObject)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, (ConvertTo-HubJson $InputObject), $script:Utf8NoBom)
}

function Add-JsonLine {
    param([Parameter(Mandatory)][string]$Path, $InputObject)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::AppendAllText($Path, (ConvertTo-HubJson $InputObject -Compress) + "`n", $script:Utf8NoBom)
}

function Get-IsoTime {
    param([datetime]$Date = (Get-Date))
    return $Date.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Expand-HubPath {
    # Mở rộng %BIEN_MOI_TRUONG% và đường dẫn tương đối (tính từ $BaseDir).
    param([string]$Path, [string]$BaseDir)
    if (-not $Path) { return $BaseDir }
    $p = [Environment]::ExpandEnvironmentVariables($Path)
    if ($p -match '^\{Desktop\}') { $p = $p -replace '^\{Desktop\}', [Environment]::GetFolderPath('Desktop') }
    if ($p -match '^\{Documents\}') { $p = $p -replace '^\{Documents\}', [Environment]::GetFolderPath('MyDocuments') }
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $BaseDir $p }
    return [System.IO.Path]::GetFullPath($p)
}

function Test-PathInside {
    # Đúng khi $Path nằm trong $Root (chống ../ thoát ra ngoài).
    param([string]$Path, [string]$Root)
    if (-not $Path -or -not $Root) { return $false }
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    return ($full -eq $rootFull) -or $full.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Initialize-ShellLink {
    # Lối tắt .lnk qua IShellLinkW: WScript.Shell đổi ký tự có dấu trong tên file ("Trạm Tool.lnk") thành '?' rồi báo
    # "Unable to save shortcut".
    if ('TramToolLnk.Lnk' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices; using System.Runtime.InteropServices.ComTypes;
namespace TramToolLnk {
    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder f, int n, IntPtr fd, int flags);
        void GetIDList(out IntPtr p); void SetIDList(IntPtr p);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int n);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string s);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int n);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string s);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int n);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string s);
        void GetHotkey(out short k); void SetHotkey(short k);
        void GetShowCmd(out int c); void SetShowCmd(int c);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder s, int n, out int i);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string s, int i);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string s, int r);
        void Resolve(IntPtr hwnd, int flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string s);
    }
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")] class ShellLink { }
    public static class Lnk {
        public static void Save(string path, string target, string args, string dir, string desc, string icon, int iconIndex, int show) {
            IShellLinkW l = (IShellLinkW)new ShellLink();
            l.SetPath(target); l.SetArguments(args); l.SetWorkingDirectory(dir); l.SetDescription(desc); l.SetIconLocation(icon, iconIndex); l.SetShowCmd(show);
            ((IPersistFile)l).Save(path, true);
        }
        // Đọc lại: đích, tham số, thư mục làm việc, mô tả, biểu tượng (đường dẫn,số), kiểu cửa sổ.
        public static string[] Read(string path) {
            IShellLinkW l = (IShellLinkW)new ShellLink();
            ((IPersistFile)l).Load(path, 0);
            StringBuilder a = new StringBuilder(2048), b = new StringBuilder(8192), c = new StringBuilder(2048), d = new StringBuilder(2048), w = new StringBuilder(2048); int i, s;
            l.GetPath(a, a.Capacity, IntPtr.Zero, 0); l.GetArguments(b, b.Capacity); l.GetWorkingDirectory(w, w.Capacity);
            l.GetDescription(d, d.Capacity); l.GetIconLocation(c, c.Capacity, out i); l.GetShowCmd(out s);
            return new string[] { a.ToString(), b.ToString(), w.ToString(), d.ToString(), c.ToString() + "," + i, s.ToString() };
        }
    }
}
'@
}

function Save-ShellLink {
    # ShowCmd: 1 cửa sổ thường, 7 thu nhỏ.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Target, [string]$Arguments = '', [string]$WorkingDirectory = '',
        [string]$Description = '', [string]$Icon = '', [int]$IconIndex = 0, [int]$ShowCmd = 1)
    Initialize-ShellLink
    [TramToolLnk.Lnk]::Save($Path, $Target, $Arguments, $WorkingDirectory, $Description, $Icon, $IconIndex, $ShowCmd)
}

function Read-ShellLink {
    param([Parameter(Mandatory)][string]$Path)
    Initialize-ShellLink
    $r = [TramToolLnk.Lnk]::Read($Path)
    return [pscustomobject]@{ Target = $r[0]; Arguments = $r[1]; WorkingDirectory = $r[2]; Description = $r[3]; Icon = $r[4]; ShowCmd = [int]$r[5] }
}

function New-DesktopShortcut {
    # Lối tắt "Trạm Tool" trên Desktop (trang Cài đặt và CAI_DAT.bat): bản portable trỏ TramTool.exe (máy chủ chạy ẩn),
    # bản lấy bằng git trỏ TramTool.bat (cửa sổ máy chủ thu nhỏ). -Desktop: thư mục khác (bài thử).
    param([Parameter(Mandatory)][string]$RootDir, [Parameter(Mandatory)][string]$HubDir, [string]$Desktop = '')
    if (-not $Desktop) { $Desktop = [Environment]::GetFolderPath('Desktop') }
    $lnk = Join-Path $Desktop 'Trạm Tool.lnk'
    $exe = Join-Path $RootDir 'TramTool.exe'
    if (Test-Path -LiteralPath $exe -PathType Leaf) { $target = $exe; $show = 1 } else { $target = Join-Path $RootDir 'TramTool.bat'; $show = 7 }
    $ico = Join-Path $HubDir 'web\tramtool.ico'
    $idx = 0
    if (-not (Test-Path -LiteralPath $ico)) { $ico = "$env:SystemRoot\System32\imageres.dll"; $idx = 109 }
    Save-ShellLink -Path $lnk -Target $target -WorkingDirectory $RootDir -Description 'Trạm Tool - chọn và chạy công cụ Windows' -Icon $ico -IconIndex $idx -ShowCmd $show
    return $lnk
}

# Thư mục nặng (môi trường Python, mô hình, kết quả): không cần dò dấu tải từ Internet.
$script:BlockScanSkip = @('.venv', 'venv', 'models', 'runtime', '.git', 'node_modules', 'ket_qua', 'du-lieu', '__pycache__')
function Get-BlockedFiles {
    # File còn dấu "tải từ Internet" (Zone.Identifier) sau khi giải nén .zip tải về: Windows hỏi lại hoặc chặn khi mở.
    param([Parameter(Mandatory)][string]$Dir)
    $out = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -File -Force -ErrorAction SilentlyContinue)) {
        if (Get-Item -LiteralPath $f.FullName -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue) { [void]$out.Add($f.FullName) }
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $Dir -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($script:BlockScanSkip -contains $d.Name -or ($d.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        foreach ($x in (Get-BlockedFiles $d.FullName)) { [void]$out.Add($x) }
    }
    return $out.ToArray()
}

# ---------------------------------------------------------------- bản portable
# hub\dev\DongGoi.ps1 dựng bản chạy không cần cài: Python mang theo ở runtime\python, .venv của công cụ dựng sẵn.
# pyvenv.cfg của .venv chỉ nhận đường dẫn tuyệt đối tới Python gốc (dòng home), nên giải nén chỗ khác hoặc chạy từ
# USB thì mỗi lần mở trạm ghi lại cho đúng chỗ mới.
$script:PortablePath = ''

function Get-PortablePython {
    param([Parameter(Mandatory)][string]$RootDir)
    $py = Join-Path $RootDir 'runtime\python\python.exe'
    if (Test-Path -LiteralPath $py -PathType Leaf) { return $py }
    return ''
}

function Repair-VenvHome {
    # Trỏ .venv về Python mang theo. Chỉ sửa .venv cùng phiên bản (3.x) với Python đó. Trả $true khi đã ghi lại.
    param([Parameter(Mandatory)][string]$VenvDir, [Parameter(Mandatory)][string]$PythonDir, [string]$Version = '')
    $cfg = Join-Path $VenvDir 'pyvenv.cfg'
    if (-not (Test-Path -LiteralPath $cfg -PathType Leaf)) { return $false }
    $lines = @([IO.File]::ReadAllLines($cfg, [Text.Encoding]::UTF8))
    $venvHome = ''; $ver = ''
    foreach ($l in $lines) {
        if ($l -match '^\s*home\s*=\s*(.*?)\s*$') { $venvHome = $Matches[1] }
        elseif ($l -match '^\s*version(_info)?\s*=\s*(\d+\.\d+)') { $ver = $Matches[2] }
    }
    if ($Version -and $ver -and $ver -ne $Version) { return $false }
    $want = $PythonDir.TrimEnd('\')
    if ($venvHome.TrimEnd('\') -ieq $want) { return $false }
    $out = foreach ($l in $lines) {
        if ($l -match '^\s*home\s*=') { "home = $want" }
        elseif ($l -match '^\s*executable\s*=') { "executable = $want\python.exe" }
        else { $l }
    }
    [IO.File]::WriteAllText($cfg, (($out -join "`r`n") + "`r`n"), $script:Utf8NoBom)
    return $true
}

function Initialize-PortableRuntime {
    # Bản portable: thêm Python mang theo vào PATH (Update-EnvPath giữ lại), bật chế độ UTF-8 của Python cho mọi công
    # cụ chạy từ trạm, sửa .venv sau khi đổi thư mục, bỏ dấu "tải từ Internet" một lần (đánh dấu trong $DataDir).
    # Không phải bản portable (không có runtime\python) thì không làm gì, trả $null.
    param([Parameter(Mandatory)][string]$RootDir, [string]$ToolsDir = '', [string]$DataDir = '')
    $py = Get-PortablePython -RootDir $RootDir
    if (-not $py) { return $null }
    $pyDir = Split-Path $py -Parent
    $script:PortablePath = $pyDir + ';' + (Join-Path $pyDir 'Scripts')
    $env:TRAMTOOL_PORTABLE = $RootDir
    $env:TRAMTOOL_PYTHON = $py
    $env:PYTHONUTF8 = '1'
    $env:PYTHONIOENCODING = 'utf-8'
    Update-EnvPath
    $ver = ''
    foreach ($dll in @(Get-ChildItem -LiteralPath $pyDir -Filter 'python3*.dll' -File -ErrorAction SilentlyContinue)) {
        if ($dll.Name -match '^python3(\d+)\.dll$') { $ver = "3.$($Matches[1])" }
    }
    if (-not $ToolsDir) { $ToolsDir = Join-Path $RootDir 'tools' }
    $fixed = New-Object System.Collections.ArrayList
    foreach ($d in @(Get-ChildItem -LiteralPath $ToolsDir -Directory -ErrorAction SilentlyContinue)) {
        $v = Join-Path $d.FullName '.venv'
        if ((Test-Path -LiteralPath $v) -and (Repair-VenvHome -VenvDir $v -PythonDir $pyDir -Version $ver)) { [void]$fixed.Add($d.Name) }
    }
    $unblocked = 0
    if ($DataDir) {
        $mark = Join-Path $DataDir 'da-bo-chan.txt'
        if (-not (Test-Path -LiteralPath $mark)) {
            foreach ($f in @(Get-BlockedFiles $RootDir)) { try { Unblock-File -LiteralPath $f -ErrorAction Stop; $unblocked++ } catch { } }
            if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
            [IO.File]::WriteAllText($mark, "Đã bỏ dấu tải từ Internet cho $unblocked file lúc $(Get-IsoTime).`r`n", (New-Object Text.UTF8Encoding $true))
        }
    }
    return [pscustomobject]@{ Python = $py; Version = $ver; Fixed = $fixed.ToArray(); Unblocked = $unblocked }
}

function Update-EnvPath {
    # Nạp lại PATH từ registry để thấy Python/winget vừa cài trong lúc trạm đang chạy. Bản portable: Python mang theo
    # đứng đầu.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($script:PortablePath, $machine, $user) | Where-Object { $_ }) -join ';'
}

function Write-HubLog {
    param([string]$Message, [ValidateSet('info', 'ok', 'warn', 'error')][string]$Level = 'info')
    $color = @{ info = 'Gray'; ok = 'Green'; warn = 'Yellow'; error = 'Red' }[$Level]
    Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message) -ForegroundColor $color
}

function New-HubToken {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function ConvertTo-Slug {
    param([string]$Text)
    $n = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $n.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    $s = $sb.ToString().Replace('đ', 'd').Replace('Đ', 'D').ToLowerInvariant()
    $s = [regex]::Replace($s, '[^a-z0-9]+', '-').Trim('-')
    if (-not $s) { $s = 'tool' }
    return $s
}
