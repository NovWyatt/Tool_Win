# Chuyển dữ liệu khi cài lại Windows - phần dùng chung cho xuất và nhập: in ra, hỏi đáp, chép thư mục, manifest,
# mã hoá phần bí mật, chọn nơi lưu, WLAN API, đọc BitLocker.

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Warnings  = New-Object System.Collections.ArrayList   # lưu ý (không làm hỏng kết quả)
$script:Errors    = New-Object System.Collections.ArrayList   # việc không làm được -> kết quả "một phần", mã 3
$script:NextSteps = New-Object System.Collections.ArrayList   # gợi ý chạy công cụ khác (Add-NextStep)
$script:EndOfInput = 'CDL_HET_DAU_VAO'
$script:Secret    = $null    # xuất có mã hoá: đường dẫn tương đối -> byte[] của file bí mật, chỉ nằm trong bộ nhớ
$script:SecretIn  = $null    # nhập: nội dung đã giải mã của BiMat.aes
$script:SecretFile = 'BiMat.aes'

# ---------------------------------------------------------------- in ra màn hình
function Head([string]$m) { Write-Host ''; Write-Host ('=' * 70) -ForegroundColor DarkCyan; Write-Host "  $m" -ForegroundColor Cyan; Write-Host ('=' * 70) -ForegroundColor DarkCyan }
function Ok([string]$m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Info([string]$m) { Write-Host "       $m" -ForegroundColor Gray }
function Plan([string]$m) { Write-Host "   ->  $m" -ForegroundColor White }
function Warn([string]$m) { Write-Host "  [!]  $m" -ForegroundColor Yellow; [void]$script:Warnings.Add($m) }
function Fail([string]$m) { Write-Host "  [X]  $m" -ForegroundColor Red; [void]$script:Errors.Add($m) }
function Add-NextStep([string]$Level, [string]$Ma, [string]$Title, [string]$Fix, [string]$Next) {
    # Gợi ý chạy công cụ khác của Trạm (nút chạy tiếp, chuẩn tramtool.ketqua/1); không tính là lỗi.
    $mark = if ($Level -eq 'canh-bao') { '[!] ' } else { '[i] ' }
    Write-Host "  $mark $Title" -ForegroundColor $(if ($Level -eq 'canh-bao') { 'Yellow' } else { 'Gray' })
    if ($Fix) { Write-Host "       $Fix" -ForegroundColor Gray }
    $f = [ordered]@{ ma = $Ma; mucDo = $Level; tieuDe = $Title; cachSua = $Fix }
    if ($Next -match '^([a-z0-9-]+)/([A-Za-z0-9_-]+)$') { $f['chayTiep'] = [ordered]@{ congCu = $Matches[1]; action = $Matches[2] } }
    [void]$script:NextSteps.Add($f)
}

# ---------------------------------------------------------------- hỏi người dùng
# -Yes: nhận câu trả lời mặc định. Đầu vào bị chuyển hướng (chạy tự động): đọc từng dòng, hết dòng thì dừng hẳn
# (Read-Host khi đó trả về rỗng ngay, vòng hỏi lại sẽ chạy mãi).
function Read-Line([string]$Prompt) {
    $redirected = $false
    try { $redirected = [Console]::IsInputRedirected } catch {}
    if (-not $redirected) { return [string](Read-Host $Prompt) }
    Write-Host ($Prompt + ': ') -NoNewline
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { Write-Host ''; throw $script:EndOfInput }
    Write-Host $line
    return $line
}
function Read-Answer([string]$Prompt, [string]$Default = '') {
    if ($script:Yes) { Write-Host "  $Prompt`: $Default  [tự động]" -ForegroundColor Gray; return $Default }
    $a = (Read-Line "  $Prompt").Trim()
    if (-not $a) { return $Default }
    return $a
}
function Read-YesNo([string]$Question, [bool]$Default = $false) {
    $hint = if ($Default) { '[C/k]' } else { '[c/K]' }
    if ($script:Yes) { Write-Host ("  {0} {1}: {2}  [tự động]" -f $Question, $hint, $(if ($Default) { 'C' } else { 'K' })) -ForegroundColor Gray; return $Default }
    while ($true) {
        $a = (Read-Line "  $Question $hint").Trim().ToLowerInvariant()
        if (-not $a) { return $Default }
        if ($a -in 'c', 'co', 'có', 'y', 'yes', 't') { return $true }
        if ($a -in 'k', 'khong', 'không', 'n', 'no') { return $false }
        Write-Host '  Gõ C (có) hoặc K (không).' -ForegroundColor Yellow
    }
}
function Read-Secret([string]$Prompt) {
    # Mật khẩu: gõ trong cửa sổ này (không hiện chữ), không bao giờ nhận qua tham số hay biến môi trường.
    $redirected = $false
    try { $redirected = [Console]::IsInputRedirected } catch {}
    if ($redirected) {
        Write-Host ("  $Prompt" + ': ') -NoNewline
        $line = [Console]::In.ReadLine()
        if ($null -eq $line) { Write-Host ''; throw $script:EndOfInput }
        Write-Host '********'
        return $line
    }
    $ss = Read-Host "  $Prompt" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

# ---------------------------------------------------------------- file, thư mục
function Ensure-Dir([string]$p) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force -ErrorAction Stop | Out-Null } }
function Save-Text([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $script:Utf8NoBom) }
function Save-Json($obj, [string]$path) { Save-Text $path (ConvertTo-Json -InputObject $obj -Depth 8) }
function Save-JsonAtomic($obj, [string]$path) {
    # Ghi ra file tạm rồi thay: cửa sổ bị đóng giữa chừng không để lại file JSON dở dang
    $tmp = "$path.tmp"
    Save-Json $obj $tmp
    if (-not (Test-Path -LiteralPath $path)) { [IO.File]::Move($tmp, $path); return }
    try { [IO.File]::Replace($tmp, $path, $null) } catch { [IO.File]::Copy($tmp, $path, $true); [IO.File]::Delete($tmp) }
}
function Read-Json([string]$path) { [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json }
function Get-Size([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return [long]0 }
    $s = (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if ($s) { return [long]$s } else { return [long]0 }
}
function Fmt-Size([long]$b) { if ($b -ge 1GB) { '{0:N2} GB' -f ($b / 1GB) } else { '{0:N1} MB' -f ($b / 1MB) } }
function Get-ErrText($code) {
    try { return ('{0} (mã {1})' -f (New-Object System.ComponentModel.Win32Exception([int]$code)).Message, $code) } catch { return "mã $code" }
}
function Test-UnderPath([string]$Child, [string]$Parent) {
    if (-not $Child -or -not $Parent) { return $false }
    $c = ($Child -replace '/', '\').TrimEnd('\').ToLowerInvariant() + '\'
    $p = ($Parent -replace '/', '\').TrimEnd('\').ToLowerInvariant() + '\'
    return $c.StartsWith($p)
}

# Chép cả thư mục bằng robocopy (nhanh, giữ ngày giờ, chịu được đường dẫn dài). Trả về mã robocopy (<8 = thành công).
# -KeepNewer: file ở đích mới hơn thì giữ nguyên (robocopy /XO). $xd, $xf: đường dẫn đầy đủ hoặc tên cần bỏ qua.
function Copy-Tree([string]$src, [string]$dst, [string[]]$xd = @(), [string[]]$xf = @(), [switch]$KeepNewer) {
    Ensure-Dir $dst
    $ra = @($src, $dst, '/E', '/COPY:DAT', '/DCOPY:T', '/R:1', '/W:1', '/XJ', '/MT:8', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($KeepNewer) { $ra += '/XO' }
    if ($xd.Count -gt 0) { $ra += '/XD'; $ra += $xd }
    if ($xf.Count -gt 0) { $ra += '/XF'; $ra += $xf }
    $o = & robocopy.exe @ra
    $rc = [int]$LASTEXITCODE
    if ($rc -ge 8) { foreach ($l in @($o | Where-Object { $_ -match '\(0x[0-9A-Fa-f]{8}\)' } | Select-Object -First 15)) { Write-Host "       $l" -ForegroundColor DarkYellow } }
    return $rc
}

# ---------------------------------------------------------------- phần bí mật (mật khẩu Wi-Fi, cấu hình Claude)
# Xuất có mã hoá: file bí mật không bao giờ được ghi ra đĩa dạng chữ thường; gom trong bộ nhớ rồi ghi một lần vào
# BiMat.aes (zip, mã hoá AES-256-CBC, khoá từ mật khẩu bằng PBKDF2-SHA256, kiểm tra toàn vẹn HMAC-SHA256).
function Save-SecretBytes([string]$Rel, [byte[]]$Bytes) {
    if ($null -ne $script:Secret) { $script:Secret[$Rel] = $Bytes; return }
    $p = Join-Path $script:Out $Rel
    Ensure-Dir (Split-Path -Parent $p)
    [IO.File]::WriteAllBytes($p, $Bytes)
}
function Save-SecretText([string]$Rel, [string]$Text) { Save-SecretBytes $Rel ($script:Utf8NoBom.GetBytes($Text)) }
function Save-SecretFile([string]$Rel, [string]$Source) {
    # Trả $true khi đọc/chép được
    try { Save-SecretBytes $Rel ([IO.File]::ReadAllBytes($Source)); return $true }
    catch { Fail "Không chép được $Source : $($_.Exception.Message)"; return $false }
}
function Get-BackupBytes([string]$Rel) {
    # Nhập: lấy file của bản sao lưu, ưu tiên phần đã giải mã; $null khi không có
    if ($null -ne $script:SecretIn -and $script:SecretIn.Contains($Rel)) { return , ([byte[]]$script:SecretIn[$Rel]) }
    $p = Join-Path $script:In $Rel
    if (Test-Path -LiteralPath $p -PathType Leaf) { return , [IO.File]::ReadAllBytes($p) }
    return $null
}
function Get-SecretEntries([string]$Prefix) {
    # Các file đã giải mã nằm dưới $Prefix\ (đường dẫn tương đối phía sau $Prefix\)
    $res = [ordered]@{}
    if ($null -eq $script:SecretIn) { return $res }
    foreach ($k in $script:SecretIn.Keys) { if ($k.StartsWith($Prefix + '\', [StringComparison]::OrdinalIgnoreCase)) { $res[$k.Substring($Prefix.Length + 1)] = $script:SecretIn[$k] } }
    return $res
}
function Write-SecretEntries([string]$Prefix, [string]$Dest) {
    # Ghi các file đã giải mã dưới $Prefix\ vào thư mục $Dest (giữ cấu trúc). Trả số file lỗi.
    $bad = 0
    $entries = Get-SecretEntries $Prefix
    foreach ($rel in $entries.Keys) {
        $p = Join-Path $Dest $rel
        try { Ensure-Dir (Split-Path -Parent $p); [IO.File]::WriteAllBytes($p, [byte[]]$entries[$rel]) }
        catch { Fail "Không ghi được $p : $($_.Exception.Message)"; $bad++ }
    }
    return $bad
}

function New-ZipBytes([System.Collections.IDictionary]$Files) {
    Add-Type -AssemblyName System.IO.Compression
    $ms = New-Object IO.MemoryStream
    $za = New-Object IO.Compression.ZipArchive($ms, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($k in $Files.Keys) {
            $b = [byte[]]$Files[$k]
            $s = $za.CreateEntry(($k -replace '\\', '/'), [IO.Compression.CompressionLevel]::Optimal).Open()
            try { $s.Write($b, 0, $b.Length) } finally { $s.Dispose() }
        }
    } finally { $za.Dispose() }
    return , $ms.ToArray()
}
function Read-ZipBytes([byte[]]$Zip) {
    Add-Type -AssemblyName System.IO.Compression
    $res = [ordered]@{}
    $za = New-Object IO.Compression.ZipArchive((New-Object IO.MemoryStream(, $Zip)), [IO.Compression.ZipArchiveMode]::Read)
    try {
        foreach ($e in $za.Entries) {
            if ($e.FullName.EndsWith('/')) { continue }
            $ms = New-Object IO.MemoryStream
            $s = $e.Open(); try { $s.CopyTo($ms) } finally { $s.Dispose() }
            $res[($e.FullName -replace '/', '\')] = $ms.ToArray()
        }
    } finally { $za.Dispose() }
    return $res
}
function Get-CryptoKeys([string]$Password, [byte[]]$Salt, [int]$Iter) {
    $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($Password, $Salt, $Iter, [Security.Cryptography.HashAlgorithmName]::SHA256)
    try { $k = $kdf.GetBytes(64) } finally { $kdf.Dispose() }
    return [pscustomobject]@{ Enc = [byte[]]$k[0..31]; Mac = [byte[]]$k[32..63] }
}
$script:CryptoMagic = [Text.Encoding]::ASCII.GetBytes('TTDL1')   # Trạm Tool - Dữ liệu, định dạng 1
function Protect-Bytes([byte[]]$Data, [string]$Password, [int]$Iter = 200000) {
    # TTDL1 | salt 16 | số vòng PBKDF2 (int32) | IV 16 | dữ liệu mã hoá | HMAC-SHA256 32 (của mọi phần trước nó)
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $salt = New-Object byte[] 16; $rng.GetBytes($salt); $rng.Dispose()
    $keys = Get-CryptoKeys $Password $salt $Iter
    $ms = New-Object IO.MemoryStream
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $keys.Enc; $aes.GenerateIV()
        $enc = $aes.CreateEncryptor()
        try { $ct = $enc.TransformFinalBlock($Data, 0, $Data.Length) } finally { $enc.Dispose() }
        foreach ($part in @($script:CryptoMagic, $salt, [BitConverter]::GetBytes([int]$Iter), $aes.IV, $ct)) { $ms.Write($part, 0, $part.Length) }
    } finally { $aes.Dispose() }
    $h = New-Object Security.Cryptography.HMACSHA256 -ArgumentList (, $keys.Mac)
    try { $mac = $h.ComputeHash($ms.ToArray()) } finally { $h.Dispose() }
    $ms.Write($mac, 0, $mac.Length)
    return , $ms.ToArray()
}
function Unprotect-Bytes([byte[]]$Blob, [string]$Password) {
    $m = $script:CryptoMagic.Length
    if ($Blob.Length -lt ($m + 16 + 4 + 16 + 16 + 32)) { throw 'Tệp mã hoá bị hỏng (quá ngắn).' }
    for ($i = 0; $i -lt $m; $i++) { if ($Blob[$i] -ne $script:CryptoMagic[$i]) { throw 'Không phải tệp mã hoá của công cụ này.' } }
    $salt = [byte[]]$Blob[$m..($m + 15)]
    $iter = [BitConverter]::ToInt32($Blob, $m + 16)
    if ($iter -lt 10000 -or $iter -gt 10000000) { throw 'Tệp mã hoá bị hỏng (số vòng lạ).' }
    $iv = [byte[]]$Blob[($m + 20)..($m + 35)]
    $bodyLen = $Blob.Length - 32
    $keys = Get-CryptoKeys $Password $salt $iter
    $h = New-Object Security.Cryptography.HMACSHA256 -ArgumentList (, $keys.Mac)
    try { $mac = $h.ComputeHash($Blob, 0, $bodyLen) } finally { $h.Dispose() }
    $diff = 0
    for ($i = 0; $i -lt 32; $i++) { $diff = $diff -bor ($mac[$i] -bxor $Blob[$bodyLen + $i]) }
    if ($diff -ne 0) { throw 'Sai mật khẩu hoặc tệp mã hoá đã bị thay đổi.' }
    $aes = [Security.Cryptography.Aes]::Create()
    try {
        $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $keys.Enc; $aes.IV = $iv
        $dec = $aes.CreateDecryptor()
        try { return , $dec.TransformFinalBlock($Blob, $m + 36, $bodyLen - $m - 36) } finally { $dec.Dispose() }
    } finally { $aes.Dispose() }
}

# ---------------------------------------------------------------- manifest của bản sao lưu
# TrangThai: dang-lam (ghi lúc bắt đầu), xong, mot-phan (có việc không làm được), loi (dừng vì lỗi).
# Bước nhập chỉ dùng bản 'xong' hoặc 'mot-phan'.
function Get-BackupInfo([string]$Dir) {
    # Mô tả một thư mục sao lưu; $null nếu không phải thư mục sao lưu
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir -PathType Container)) { return $null }   # cả ổ chưa có
    $mf = Join-Path $Dir 'manifest.json'
    $ti = Join-Path $Dir 'thong-tin.json'
    $leaf = Split-Path -Leaf $Dir
    $r = [pscustomobject]@{ Path = $Dir; Name = $leaf; State = ''; Time = $null; Computer = ''; User = ''; Encrypted = $false; Old = ($leaf -like 'DuLieu_SaoLuu_cu_*'); Legacy = $false; Errors = @() }
    if (Test-Path -LiteralPath $mf -PathType Leaf) {
        try { $m = Read-Json $mf } catch { $r.State = 'hong'; return $r }
        $r.State = [string]$m.TrangThai; $r.Computer = [string]$m.May; $r.User = [string]$m.NguoiDung
        $r.Encrypted = [bool]$m.MaHoa; $r.Errors = @($m.Loi | Where-Object { $_ })
        try { $r.Time = [datetime]::Parse([string]$m.BatDau) } catch {}
        return $r
    }
    if (Test-Path -LiteralPath $ti -PathType Leaf) {
        # Bản tạo bởi bản cũ (chưa có manifest): thong-tin.json được ghi sau cùng nên có nghĩa là đã xuất xong
        $r.Legacy = $true; $r.State = 'xong'
        try { $t = Read-Json $ti; $r.Computer = [string]$t.Computer; $r.User = [string]$t.UserName; $r.Time = [datetime]::Parse([string]$t.Date) } catch {}
        return $r
    }
    return $null
}
function Format-BackupState([string]$State) {
    switch ($State) { 'xong' { 'đã xong' } 'mot-phan' { 'xong một phần' } 'dang-lam' { 'CHƯA XONG (bị ngắt giữa chừng)' } 'loi' { 'DỪNG VÌ LỖI' } 'hong' { 'manifest.json hỏng' } default { "không rõ ($State)" } }
}

# ---------------------------------------------------------------- nơi lưu, quyền
function Get-WifiName([string]$xml) { return (Get-WifiInfo $xml).Name }

function Get-StationDir {
    # Thư mục Trạm Tool (có TramTool.bat) chứa công cụ này; không có thì là thư mục công cụ nếu có tool.json
    $d = $script:ToolDir
    while ($d) {
        if (Test-Path -LiteralPath (Join-Path $d 'TramTool.bat')) { return $d }
        $p = Split-Path -Parent $d
        if (-not $p -or $p -eq $d) { break }
        $d = $p
    }
    if (Test-Path -LiteralPath (Join-Path $script:ToolDir 'tool.json')) { return $script:ToolDir }
    return $null
}
function Get-ConsoleUser {
    # Người đang dùng máy; khác tài khoản đang chạy khi UAC hỏi mật khẩu một Admin khác
    try { return [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName } catch { return '' }
}
function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-ClaudeDesktopProcess {
    # Chỉ ứng dụng Claude Desktop (bản cài thường hoặc Microsoft Store), không đụng claude.exe của Claude Code (CLI)
    @(Get-Process -Name 'claude' -ErrorAction SilentlyContinue | Where-Object {
        $p = $null; try { $p = [string]$_.Path } catch {}
        $p -and $p -match '(?i)\\AnthropicClaude\\|\\WindowsApps\\Claude_|\\Packages\\Claude_'
    })
}

# ---------------------------------------------------------------- WLAN API (đọc hồ sơ Wi-Fi chính xác, kể cả tên tiếng Việt / trùng hoa-thường)
$WlanCs = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class WlanTool {
    [DllImport("wlanapi.dll")] static extern uint WlanOpenHandle(uint ver, IntPtr res, out uint negVer, out IntPtr h);
    [DllImport("wlanapi.dll")] static extern uint WlanCloseHandle(IntPtr h, IntPtr res);
    [DllImport("wlanapi.dll")] static extern uint WlanEnumInterfaces(IntPtr h, IntPtr res, out IntPtr list);
    [DllImport("wlanapi.dll")] static extern uint WlanGetProfileList(IntPtr h, ref Guid g, IntPtr res, out IntPtr list);
    [DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] static extern uint WlanGetProfile(IntPtr h, ref Guid g, string name, IntPtr res, out IntPtr xml, ref uint flags, out uint access);
    [DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] static extern uint WlanSetProfile(IntPtr h, ref Guid g, uint flags, string xml, string sec, bool overwrite, IntPtr res, out uint reason);
    [DllImport("wlanapi.dll")] static extern void WlanFreeMemory(IntPtr p);

    public class Prof { public string Name; public uint Flags; public string Xml; public uint Error; public string Iface; }

    static IntPtr Open() {
        uint v; IntPtr h;
        uint r = WlanOpenHandle(2, IntPtr.Zero, out v, out h);
        if (r != 0) throw new Win32Exception((int)r);
        return h;
    }
    static List<KeyValuePair<Guid, string>> Ifaces(IntPtr h) {
        IntPtr p; uint r = WlanEnumInterfaces(h, IntPtr.Zero, out p);
        if (r != 0) throw new Win32Exception((int)r);
        var res = new List<KeyValuePair<Guid, string>>();
        try {
            int n = Marshal.ReadInt32(p, 0);
            for (int i = 0; i < n; i++) {
                IntPtr item = new IntPtr(p.ToInt64() + 8 + i * 532);   // WLAN_INTERFACE_INFO = GUID(16) + WCHAR[256] + DWORD
                byte[] gb = new byte[16]; Marshal.Copy(item, gb, 0, 16);
                res.Add(new KeyValuePair<Guid, string>(new Guid(gb), Marshal.PtrToStringUni(new IntPtr(item.ToInt64() + 16))));
            }
        } finally { WlanFreeMemory(p); }
        return res;
    }
    public static int InterfaceCount() {
        IntPtr h = Open();
        try { return Ifaces(h).Count; } finally { WlanCloseHandle(h, IntPtr.Zero); }
    }
    public static List<Prof> Export() {
        var res = new List<Prof>();
        IntPtr h = Open();
        try {
            foreach (var it in Ifaces(h)) {
                Guid g = it.Key; IntPtr pl;
                if (WlanGetProfileList(h, ref g, IntPtr.Zero, out pl) != 0) continue;
                try {
                    int n = Marshal.ReadInt32(pl, 0);
                    for (int i = 0; i < n; i++) {
                        IntPtr item = new IntPtr(pl.ToInt64() + 8 + i * 516);   // WLAN_PROFILE_INFO = WCHAR[256] + DWORD
                        var pr = new Prof();
                        pr.Name = Marshal.PtrToStringUni(item);
                        pr.Flags = (uint)Marshal.ReadInt32(item, 512);
                        pr.Iface = it.Value;
                        uint f = 4; IntPtr x; uint acc;                      // 4 = WLAN_PROFILE_GET_PLAINTEXT_KEY
                        uint e = WlanGetProfile(h, ref g, pr.Name, IntPtr.Zero, out x, ref f, out acc);
                        if (e == 0) { pr.Xml = Marshal.PtrToStringUni(x); WlanFreeMemory(x); } else { pr.Error = e; }
                        res.Add(pr);
                    }
                } finally { WlanFreeMemory(pl); }
            }
        } finally { WlanCloseHandle(h, IntPtr.Zero); }
        return res;
    }
    // Chỉ tên và cờ của hồ sơ, không đọc nội dung (không lấy mật khẩu): dùng cho chạy thử
    public static List<Prof> ListProfiles() {
        var res = new List<Prof>();
        IntPtr h = Open();
        try {
            foreach (var it in Ifaces(h)) {
                Guid g = it.Key; IntPtr pl;
                if (WlanGetProfileList(h, ref g, IntPtr.Zero, out pl) != 0) continue;
                try {
                    int n = Marshal.ReadInt32(pl, 0);
                    for (int i = 0; i < n; i++) {
                        IntPtr item = new IntPtr(pl.ToInt64() + 8 + i * 516);
                        var pr = new Prof();
                        pr.Name = Marshal.PtrToStringUni(item);
                        pr.Flags = (uint)Marshal.ReadInt32(item, 512);
                        pr.Iface = it.Value;
                        res.Add(pr);
                    }
                } finally { WlanFreeMemory(pl); }
            }
        } finally { WlanCloseHandle(h, IntPtr.Zero); }
        return res;
    }
    public static uint[] Import(string xml, uint flags, bool overwrite) {
        IntPtr h = Open();
        try {
            var ifs = Ifaces(h);
            var codes = new uint[ifs.Count];
            for (int i = 0; i < ifs.Count; i++) {
                Guid g = ifs[i].Key; uint reason;
                codes[i] = WlanSetProfile(h, ref g, flags, xml, null, overwrite, IntPtr.Zero, out reason);
            }
            return codes;
        } finally { WlanCloseHandle(h, IntPtr.Zero); }
    }
}
'@
function Load-WlanApi {
    if ('WlanTool' -as [type]) { return $true }
    try { Add-Type -TypeDefinition $WlanCs -Language CSharp -ErrorAction Stop; return $true }
    catch { Warn "Không nạp được WLAN API ($($_.Exception.Message)) - chuyển sang dùng netsh."; return $false }
}

# Lấy tên mạng / kiểu bảo mật / tình trạng mật khẩu từ XML hồ sơ Wi-Fi
function Get-WifiInfo([string]$xml) {
    $r = [pscustomobject]@{ Name = $null; Auth = ''; HasKey = $false; Encrypted = $false }
    try {
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml($xml)
        $r.Name = [string]$doc.WLANProfile.name
        $sec = $doc.WLANProfile.MSM.security
        if ($sec) {
            $r.Auth = [string]$sec.authEncryption.authentication
            $sk = $sec.sharedKey
            if ($sk -and $sk.keyMaterial) {
                if ([string]$sk.protected -eq 'true') { $r.Encrypted = $true } else { $r.HasKey = $true }
            }
        }
    } catch {}
    return $r
}

# ---------------------------------------------------------------- BitLocker (đọc trạng thái ổ, gọi phương thức WMI)
# Khoá khôi phục không bao giờ in ra màn hình: nhật ký xuất, nhập đang ghi lại mọi thứ hiện trên màn hình.
$BdeNs = 'root/cimv2/Security/MicrosoftVolumeEncryption'
function Invoke-Bde($vol, [string]$method, [hashtable]$arguments = $null) {
    $p = @{ InputObject = $vol; MethodName = $method; ErrorAction = 'Stop' }
    if ($arguments) { $p.Arguments = $arguments }
    $r = Invoke-CimMethod @p
    if ([int64]$r.ReturnValue -ne 0) { throw ('BitLocker báo lỗi 0x{0:X8}' -f [int64]$r.ReturnValue) }
    return $r
}
# Các ổ BitLocker; $null khi không đọc được (thiếu quyền Administrator).
function Get-BdeState {
    try { $vols = @(Get-CimInstance -Namespace $BdeNs -ClassName Win32_EncryptableVolume -ErrorAction Stop) } catch { return $null }
    $list = foreach ($v in $vols) {
        $s = [ordered]@{ Vol = $v; Letter = [string]$v.DriveLetter; Type = 1; Locked = $false; Conv = -1; Prot = -1; Ids = @(); Count = 0; Encrypted = $false }
        if ($null -ne $v.VolumeType) { $s.Type = [int]$v.VolumeType } elseif ($s.Letter -eq $env:SystemDrive) { $s.Type = 0 }
        try { $s.Locked = ([int](Invoke-Bde $v 'GetLockStatus').LockStatus -eq 1) } catch {}
        try { $s.Prot = [int](Invoke-Bde $v 'GetProtectionStatus').ProtectionStatus } catch {}
        if (-not $s.Locked) { try { $s.Conv = [int](Invoke-Bde $v 'GetConversionStatus').ConversionStatus } catch {} }
        try { $s.Count = @((Invoke-Bde $v 'GetKeyProtectors' @{ KeyProtectorType = [uint32]0 }).VolumeKeyProtectorID | Where-Object { $_ }).Count } catch {}
        try { $s.Ids = @((Invoke-Bde $v 'GetKeyProtectors' @{ KeyProtectorType = [uint32]3 }).VolumeKeyProtectorID | Where-Object { $_ } | ForEach-Object { '{' + ([string]$_).Trim('{', '}').ToUpperInvariant() + '}' }) } catch {}
        $s.Encrypted = ($s.Locked -or $s.Conv -gt 0)
        [pscustomobject]$s
    }
    return @($list)
}
function Get-BdeName($s) {
    $t = @{ 0 = 'ổ Windows'; 1 = 'ổ dữ liệu'; 2 = 'ổ rời' }[$s.Type]
    if ($s.Letter) { return "Ổ $($s.Letter) ($t)" } else { return "Ổ không có chữ ổ ($t)" }
}
function Get-BdeVolumeAt([string]$path, $state) {
    if ($path -notmatch '^([A-Za-z]:)') { return $null }
    $l = $Matches[1].ToUpperInvariant()
    return (@($state) | Where-Object { $_.Letter -and $_.Letter.ToUpperInvariant() -eq $l } | Select-Object -First 1)
}
