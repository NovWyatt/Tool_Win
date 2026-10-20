<#
  Đồng bộ phiên Claude giữa các tài khoản.

  Claude Desktop lưu danh sách phiên tab Code riêng cho từng tài khoản đăng nhập
  (%APPDATA%\Claude\claude-code-sessions\<mã tài khoản>\<mã tổ chức>\local_*.json), còn nội dung hội thoại nằm chung
  trong ~\.claude\projects\<thư mục dự án>\<mã phiên>.jsonl. Đăng nhập tài khoản khác thì thanh bên trống dù nội dung
  vẫn còn trên máy. Công cụ chép các mục danh sách sang tài khoản đang đăng nhập để mở lại và làm tiếp được, kèm tác vụ
  hẹn giờ, mẫu phiên, mục thanh bên của tài khoản cũ (và phiên Cowork khi có -KemCowork).

  Chế độ (-Mode):
    kiem-tra   chỉ đọc: tài khoản đang đăng nhập, các tài khoản từng dùng trên máy và số phiên của từng tài khoản, gói
               sao lưu có sẵn, số phiên và cài đặt tài khoản đang dùng chưa có, lần đồng bộ gần nhất Claude đã nhận chưa.
    sao-luu    gói danh sách phiên, nội dung hội thoại, trí nhớ dự án, tác vụ hẹn giờ của tài khoản đang đăng nhập vào
               du-lieu\Goi_<tài khoản> (hoặc -Den <thư mục>) để mang sang máy khác. Gói đã có thì chỉ chép phần đổi.
               -Nen: nén thành một file .zip vào -Den. -MaHoa: nén rồi mã hoá bằng mật khẩu gõ trong cửa sổ (.aes).
    dong-bo    thêm vào tài khoản đang đăng nhập các phiên nó chưa có, lấy từ các tài khoản khác trên máy và các gói sao
               lưu (trong du-lieu, hoặc -Tu <gói, thư mục chứa gói, goi.json, file .zip/.aes>). Phiên đã xoá ở tài khoản
               này thì không thêm lại. Claude Desktop phải tắt (-DongClaude: tự đóng; -MoClaude: xong thì mở lại).
    hoan-tac   bỏ các mục lần đồng bộ gần nhất đã thêm, trả lại các mục đã thay; mục nào đã dùng tiếp sau khi đồng bộ
               thì giữ.
    mo-claude  cho lối tắt "Mở Claude": Claude đang tắt thì đồng bộ trước rồi mở; đang mở thì chỉ đưa cửa sổ lên.
    loi-tat    tạo lối tắt "Mở Claude (đồng bộ phiên)" trên màn hình.
  Không có -Mode: menu (bấm đúp DONG_BO_CLAUDE.bat).
  -ChayThu: chỉ in việc sẽ làm, không ghi gì. -KhongDung: không chờ Enter khi xong.
  Mỗi lần chạy ghi ket_qua\KetQua_ClaudeDongBo_<máy>_<giờ>.json (chuẩn tramtool.ketqua/1) cho Trạm Tool.
  Mã thoát: 0 xong (kể cả khi không có gì để làm), 1 lỗi, 2 chưa làm (chưa cài Claude Desktop, chưa đăng nhập, Claude
  Desktop đang mở, đã huỷ, thiếu chỗ trống, cách lưu của Claude đã đổi, chưa có mật khẩu), 3 làm được một phần.
#>
param(
    [string]$Mode = '',
    [string]$Tu = '',
    [string]$Den = '',
    [switch]$DongClaude,
    [switch]$MoClaude,
    [switch]$Nen,
    [switch]$MaHoa,
    [switch]$KemCowork,
    [switch]$ChayThu,
    [switch]$KhongDung
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:Version = '1.1'
$script:SelfPath = $PSCommandPath
# Bài thử trỏ các biến CDB_* vào thư mục tạm để không đụng dữ liệu Claude thật.
$script:DataDir = if ($env:CDB_DU_LIEU) { $env:CDB_DU_LIEU } else { Join-Path $PSScriptRoot 'du-lieu' }
$script:ResultDir = if ($env:CDB_KET_QUA) { $env:CDB_KET_QUA } else { Join-Path $PSScriptRoot 'ket_qua' }
$script:UserDir = $(if ($env:CDB_NGUOI_DUNG) { $env:CDB_NGUOI_DUNG } else { $env:USERPROFILE }).TrimEnd('\')
$script:ProjectsDir = Join-Path $script:UserDir '.claude\projects'
$script:ClaudeJson = Join-Path $script:UserDir '.claude.json'
$script:UndoDir = Join-Path $script:DataDir 'HoanTac'
$script:LabelFile = Join-Path $script:DataDir 'tai-khoan.json'
$script:MemoFile = Join-Path $script:DataDir 'da-them.json'
# Tiến trình Claude Desktop nhận theo đường dẫn file chạy (bản cài thường hoặc Microsoft Store); claude.exe của Claude
# Code chạy trong cửa sổ lệnh không bị đụng tới.
$script:DesktopExe = if ($env:CDB_MAU_CLAUDE) { $env:CDB_MAU_CLAUDE } else { '(?i)\\AnthropicClaude\\|\\WindowsApps\\Claude_|\\Packages\\Claude_' }
$script:GuidMau = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
$script:GoiChuan = 'tramtool.claudedongbo.goi/1'
$script:NhatKyChuan = 'tramtool.claudedongbo.hoantac/1'
# Bản Claude Desktop đã xem cách lưu khi viết công cụ (so với phần đầu updaterLastSeenVersion trong config.json).
$script:DaXemTrenBan = @('2.42304')
# Trường gắn với tài khoản cũ: kết nối claude.ai (connector) của tài khoản đó, phiên Remote Control trên máy chủ.
$script:AccountFields = @('remoteMcpServersConfig', 'bridgeSessionIds')
# Mục có sẵn ở thanh bên tab Code; mục khác là mục người dùng tự tạo.
$script:BuiltInSections = @('pinned', 'routines', 'sessions')
$script:LinkName = 'Mở Claude (đồng bộ phiên).lnk'
# Gói mã hoá cùng định dạng BiMat.aes của new-windows (TTDL1: AES-256-CBC, PBKDF2-SHA256, HMAC-SHA256).
$script:MaHoaDau = [Text.Encoding]::ASCII.GetBytes('TTDL1')
$script:Modes = [ordered]@{
    'kiem-tra'  = @{ Label = 'Kiểm tra phiên của các tài khoản (chỉ đọc)' }
    'sao-luu'   = @{ Label = 'Sao lưu phiên của tài khoản đang đăng nhập' }
    'dong-bo'   = @{ Label = 'Đồng bộ phiên vào tài khoản đang đăng nhập' }
    'hoan-tac'  = @{ Label = 'Hoàn tác lần đồng bộ gần nhất' }
    'mo-claude' = @{ Label = 'Mở Claude (đồng bộ phiên trước)' }
    'loi-tat'   = @{ Label = 'Tạo lối tắt Mở Claude trên màn hình' }
}
$script:Levels = @{ 'loi' = 0; 'canh-bao' = 1; 'thong-tin' = 2; 'ok' = 3 }
$script:Findings = New-Object System.Collections.ArrayList
$script:Files = New-Object System.Collections.ArrayList
$script:Labels = @{}
$script:DictCache = @{}
$script:Invalid = @{}
$script:TempDirs = New-Object System.Collections.ArrayList
$script:DangGhi = New-Object System.Collections.ArrayList
$script:ClaudeVer = ''

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

function ConvertFrom-Secure {
    param([Security.SecureString]$Secure)
    $p = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p) }
}

function Read-MatKhau {
    # Mật khẩu gói chỉ gõ trong cửa sổ công cụ, không nhận qua tham số: không lọt vào lịch sử lệnh, file kết quả, Trạm.
    param([string]$Prompt = 'Mật khẩu của gói', [switch]$XacNhan)
    if ([Console]::IsInputRedirected) { return '' }
    $a = ConvertFrom-Secure (Read-Host "  $Prompt" -AsSecureString)
    if ($XacNhan -and $a) {
        $b = ConvertFrom-Secure (Read-Host '  Gõ lại mật khẩu' -AsSecureString)
        if ($a -cne $b) { Write-Bad 'Hai lần gõ không khớp.'; return '' }
    }
    return $a
}

function Wait-Close {
    param([string]$Text = 'Bấm Enter để đóng cửa sổ')
    if ($KhongDung -or [Console]::IsInputRedirected) { return }
    Write-Host ''
    [void](Read-Host "  $Text")
}

# ---------------------------------------------------------------- file, JSON
function Get-Serializer {
    # Mục danh sách phiên, cấu hình Claude đọc thành Dictionary và ghi lại bằng cùng bộ đọc: giữ đủ mọi trường kể cả
    # trường công cụ chưa biết, không vướng giới hạn độ sâu của ConvertTo-Json.
    if (-not $script:Ser) {
        Add-Type -AssemblyName System.Web.Extensions
        $script:Ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $script:Ser.MaxJsonLength = [int]::MaxValue
        $script:Ser.RecursionLimit = 1000
    }
    return $script:Ser
}

function Read-Dict {
    param([string]$Path)
    try { $o = (Get-Serializer).DeserializeObject([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)) } catch { return $null }
    if ($o -is [System.Collections.IDictionary]) { return $o }
    return $null
}

function Read-JsonIf {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) { return Read-Dict $Path }
    return $null
}

function Read-DictCached {
    # Một lần chạy đọc cùng mục danh sách phiên nhiều lần (Kiểm tra, các nguồn): file chưa đổi (cùng giờ sửa, cùng cỡ)
    # thì dùng bản đã đọc. Bản trong bộ nhớ dùng chung nên không sửa trực tiếp (Convert-ForTarget sửa trên bản chép).
    param([IO.FileInfo]$File)
    $sig = '{0}|{1}' -f $File.LastWriteTimeUtc.Ticks, $File.Length
    $c = $script:DictCache[$File.FullName]
    if ($c -and $c.Sig -eq $sig) { return $c.Data }
    $d = Read-Dict $File.FullName
    $script:DictCache[$File.FullName] = @{ Sig = $sig; Data = $d }
    return $d
}

# ::new() thay cho New-Object: New-Object trả đối tượng bọc PSObject, gán vào Dictionary vẫn còn vỏ và
# JavaScriptSerializer không ghi được.
function New-Dict { return [System.Collections.Generic.Dictionary[string, object]]::new() }

function Remove-PSWrapper {
    # Gỡ vỏ PSObject (New-Object, Where-Object bọc giá trị) trong cây Dictionary/mảng trước khi ghi JSON.
    param($Node)
    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($k in @($Node.Keys)) {
            if ($Node[$k] -is [System.Management.Automation.PSObject]) { $Node[$k] = $Node[$k].psobject.BaseObject }
            Remove-PSWrapper $Node[$k]
        }
    } elseif ($Node -is [object[]]) {
        for ($i = 0; $i -lt $Node.Length; $i++) {
            if ($Node[$i] -is [System.Management.Automation.PSObject]) { $Node[$i] = $Node[$i].psobject.BaseObject }
            Remove-PSWrapper $Node[$i]
        }
    }
}

function ConvertTo-JsonText { param($Value) Remove-PSWrapper $Value; return (Get-Serializer).Serialize($Value) }
function Copy-Dict { param($Dict) return (Get-Serializer).DeserializeObject((ConvertTo-JsonText $Dict)) }
function Get-Arr { param($Value) if ($null -eq $Value) { return @() } return @($Value) }

function Test-Key {
    param($Dict, [string]$Key)
    if ($Dict -is [System.Collections.Generic.IDictionary[string, object]]) { return $Dict.ContainsKey($Key) }
    if ($Dict -is [System.Collections.IDictionary]) { return $Dict.Contains($Key) }
    return $false
}

function Get-KeyNode {
    # Giá trị theo đường khoá (preferences > epitaxyPrefs > ...); Found = $false khi thiếu một bậc.
    param($Root, [string[]]$Path)
    $n = $Root
    foreach ($p in $Path) {
        if (-not (Test-Key $n $p)) { return [pscustomobject]@{ Found = $false; Value = $null } }
        $n = $n[$p]
    }
    return [pscustomobject]@{ Found = $true; Value = $n }
}

function Set-KeyValue {
    # Đặt (hoặc bỏ khi -Remove) giá trị theo đường khoá; bậc thiếu thì tạo. Khoá đã có giữ nguyên chỗ trong file.
    param($Root, [string[]]$Path, $Value, [switch]$Remove)
    $n = $Root
    for ($i = 0; $i -lt $Path.Count - 1; $i++) {
        if (-not ((Test-Key $n $Path[$i]) -and $n[$Path[$i]] -is [System.Collections.IDictionary])) { $n[$Path[$i]] = New-Dict }
        $n = $n[$Path[$i]]
    }
    if ($Remove) { [void]$n.Remove($Path[-1]) } else { $n[$Path[-1]] = $Value }
}

function Read-Obj {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return $null }
}

function Write-TextAtomic {
    # Ghi ra file tạm rồi đổi tên: đứt giữa chừng thì file cũ vẫn nguyên.
    param([string]$Path, [string]$Text)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = "$Path.cdb-tmp"
    [IO.File]::WriteAllText($tmp, $Text, (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Write-Dict { param([string]$Path, $Dict) Write-TextAtomic $Path (ConvertTo-JsonText $Dict) }
function Write-Obj { param([string]$Path, $Obj) Write-TextAtomic $Path ($Obj | ConvertTo-Json -Depth 10) }

function Get-Hash {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    return ''
}

function Get-Num { param($Value) try { return [long]$Value } catch { return [long]0 } }

function Get-DirSize {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [long]0 }
    $n = [long]0
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)) { $n += $f.Length }
    return $n
}

function Get-DirSig {
    # Dấu của một thư mục (số file, tổng cỡ): Hoàn tác chỉ xoá thư mục đã chép khi chưa ai đổi gì trong đó.
    param([string]$Path)
    $n = 0; $s = [long]0
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)) { $n++; $s += $f.Length }
    return "$n|$s"
}

function Remove-EmptyDirs {
    param([string]$Dir)
    foreach ($d in @(Get-ChildItem -LiteralPath $Dir -Recurse -Directory -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
        if (-not @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue).Count) { Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue }
    }
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f [Math]::Ceiling($Bytes / 1KB)
}

function Format-Time {
    param([long]$Ms)
    if ($Ms -le 0) { return '?' }
    try { return [DateTimeOffset]::FromUnixTimeMilliseconds($Ms).LocalDateTime.ToString('dd/MM/yyyy HH:mm') } catch { return '?' }
}

function Get-FreeName {
    # Đường dẫn chưa có: thêm _2, _3... (trước đuôi .zip, .aes) khi hai lần chạy trùng giây.
    param([string]$Path)
    $ext = [IO.Path]::GetExtension($Path)
    if ($ext -notin '.zip', '.aes') { $ext = '' }
    $stem = $Path.Substring(0, $Path.Length - $ext.Length)
    $p = $Path; $i = 2
    while (Test-Path -LiteralPath $p) { $p = "${stem}_$i$ext"; $i++ }
    return $p
}

function Get-FreeBytes {
    # Chỗ trống của ổ chứa $Path; không đọc được (đường mạng) thì trả -1.
    param([string]$Path)
    try { return (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path)))).AvailableFreeSpace } catch { return [long]-1 }
}

# ---------------------------------------------------------------- nén, mã hoá gói
function Read-Full {
    # Đọc đủ $Count byte (hoặc tới hết file) vào $Buf; trả số byte đã đọc.
    param($Stream, [byte[]]$Buf, [int]$Count)
    $t = 0
    while ($t -lt $Count) { $n = $Stream.Read($Buf, $t, $Count - $t); if ($n -le 0) { break }; $t += $n }
    return $t
}

function Get-CryptoKeys {
    param([string]$Password, [byte[]]$Salt, [int]$Iter)
    $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($Password, $Salt, $Iter, [Security.Cryptography.HashAlgorithmName]::SHA256)
    try { $k = $kdf.GetBytes(64) } finally { $kdf.Dispose() }
    return [pscustomobject]@{ Enc = [byte[]]$k[0..31]; Mac = [byte[]]$k[32..63] }
}

function Protect-File {
    # TTDL1 | salt 16 | số vòng PBKDF2 (int32) | IV 16 | dữ liệu mã hoá AES-256-CBC | HMAC-SHA256 32 của mọi phần trước.
    # Đọc, ghi từng khúc 1 MB nên gói lớn không phải nằm hết trong bộ nhớ; ghi ra file tạm rồi đổi tên.
    param([string]$In, [string]$Out, [string]$Password, [int]$Iter = 200000)
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $salt = New-Object byte[] 16; $rng.GetBytes($salt); $rng.Dispose()
    $keys = Get-CryptoKeys $Password $salt $Iter
    $tmp = "$Out.cdb-tmp"
    $aes = [Security.Cryptography.Aes]::Create()
    $h = New-Object Security.Cryptography.HMACSHA256 -ArgumentList (, $keys.Mac)
    $fi = $null; $fo = $null; $enc = $null
    try {
        $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $keys.Enc; $aes.GenerateIV()
        $fi = [IO.File]::OpenRead($In)
        $fo = [IO.File]::Create($tmp)
        foreach ($part in @($script:MaHoaDau, $salt, [BitConverter]::GetBytes([int]$Iter), $aes.IV)) {
            $fo.Write($part, 0, $part.Length); [void]$h.TransformBlock($part, 0, $part.Length, $null, 0)
        }
        $enc = $aes.CreateEncryptor()
        $buf = New-Object byte[] 1048576
        $outb = New-Object byte[] (1048576 + 32)
        while ($true) {
            $n = Read-Full $fi $buf $buf.Length
            if ($n -eq $buf.Length) {
                $m = $enc.TransformBlock($buf, 0, $n, $outb, 0)
                $fo.Write($outb, 0, $m); [void]$h.TransformBlock($outb, 0, $m, $null, 0)
                continue
            }
            $last = $enc.TransformFinalBlock($buf, 0, $n)
            $fo.Write($last, 0, $last.Length); [void]$h.TransformBlock($last, 0, $last.Length, $null, 0)
            break
        }
        [void]$h.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        $fo.Write($h.Hash, 0, 32)
        $fo.Dispose(); $fo = $null
        Move-Item -LiteralPath $tmp -Destination $Out -Force
    } finally {
        foreach ($x in @($enc, $fi, $fo, $h, $aes)) { if ($null -ne $x) { $x.Dispose() } }
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Unprotect-File {
    # Kiểm toàn vẹn (HMAC) trước, giải mã sau: sai mật khẩu hay tệp bị sửa thì không ghi ra gì.
    param([string]$In, [string]$Out, [string]$Password)
    $m = $script:MaHoaDau.Length; $hd = $m + 36
    $fi = [IO.File]::OpenRead($In)
    $fo = $null; $h = $null; $aes = $null; $dec = $null
    try {
        $len = $fi.Length
        if ($len -lt $hd + 16 + 32 -or (($len - $hd - 32) % 16) -ne 0) { throw 'Tệp mã hoá bị hỏng (độ dài sai).' }
        $head = New-Object byte[] $hd
        [void](Read-Full $fi $head $hd)
        for ($i = 0; $i -lt $m; $i++) { if ($head[$i] -ne $script:MaHoaDau[$i]) { throw 'Không phải gói mã hoá của công cụ này.' } }
        $salt = [byte[]]$head[$m..($m + 15)]
        $iter = [BitConverter]::ToInt32($head, $m + 16)
        $iv = [byte[]]$head[($m + 20)..($m + 35)]
        if ($iter -lt 10000 -or $iter -gt 10000000) { throw 'Tệp mã hoá bị hỏng (số vòng lạ).' }
        $keys = Get-CryptoKeys $Password $salt $iter
        $h = New-Object Security.Cryptography.HMACSHA256 -ArgumentList (, $keys.Mac)
        [void]$h.TransformBlock($head, 0, $hd, $null, 0)
        $buf = New-Object byte[] 1048576
        $left = $len - 32 - $hd
        while ($left -gt 0) {
            $n = $fi.Read($buf, 0, [int][Math]::Min([long]$buf.Length, $left))
            if ($n -le 0) { throw 'Tệp mã hoá bị hỏng (đọc thiếu).' }
            [void]$h.TransformBlock($buf, 0, $n, $null, 0); $left -= $n
        }
        [void]$h.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        $mac = New-Object byte[] 32
        [void](Read-Full $fi $mac 32)
        $hv = $h.Hash; $diff = 0
        for ($i = 0; $i -lt 32; $i++) { $diff = $diff -bor ($hv[$i] -bxor $mac[$i]) }
        if ($diff -ne 0) { throw 'Sai mật khẩu hoặc gói đã bị sửa.' }
        $aes = [Security.Cryptography.Aes]::Create()
        $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $keys.Enc; $aes.IV = $iv
        $dec = $aes.CreateDecryptor()
        [void]$fi.Seek($hd, [IO.SeekOrigin]::Begin)
        $fo = [IO.File]::Create($Out)
        $outb = New-Object byte[] ($buf.Length + 32)
        $left = $len - 32 - $hd
        while ($left -gt $buf.Length) {
            $n = Read-Full $fi $buf $buf.Length
            $k = $dec.TransformBlock($buf, 0, $n, $outb, 0)
            $fo.Write($outb, 0, $k); $left -= $n
        }
        $n = Read-Full $fi $buf ([int]$left)
        $last = $dec.TransformFinalBlock($buf, 0, $n)
        $fo.Write($last, 0, $last.Length)
    } finally {
        foreach ($x in @($dec, $fi, $fo, $h, $aes)) { if ($null -ne $x) { $x.Dispose() } }
    }
}

function New-PackageZip {
    # Nén cả thư mục gói (kèm tên thư mục) thành một file. Không dùng ZipFile.CreateFromDirectory: chạy trong PowerShell
    # 5.1 nó ghi tên mục bằng dấu \ (sai chuẩn zip, công cụ giải nén khác đọc thành tên file có dấu \).
    param([string]$Dir, [string]$Zip)
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $tmp = "$Zip.cdb-tmp"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    $base = (Get-Item -LiteralPath $Dir -Force).FullName.TrimEnd('\')
    $top = Split-Path $base -Leaf
    $fs = [IO.File]::Create($tmp)
    try {
        $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($f in @(Get-ChildItem -LiteralPath $base -Recurse -File -Force)) {
                $name = $top + '/' + ($f.FullName.Substring($base.Length + 1) -replace '\\', '/')
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($za, $f.FullName, $name, [IO.Compression.CompressionLevel]::Optimal)
            }
        } finally { $za.Dispose() }
    } finally { $fs.Dispose() }
    Move-Item -LiteralPath $tmp -Destination $Zip -Force
}

function Expand-ZipSafe {
    # Giải nén; tên file trong tệp nén trỏ ra ngoài thư mục đích (..\, ổ đĩa khác) thì dừng (zip slip).
    param([string]$Zip, [string]$Dest)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $root = [IO.Path]::GetFullPath($Dest).TrimEnd('\') + '\'
    $za = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        foreach ($e in $za.Entries) {
            $p = [IO.Path]::GetFullPath([IO.Path]::Combine($root, ($e.FullName -replace '/', '\')))
            if (-not $p.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw "tệp nén có đường dẫn trỏ ra ngoài thư mục: $($e.FullName)" }
            if ($e.FullName.EndsWith('/') -or $e.FullName.EndsWith('\')) { New-Item -ItemType Directory -Path $p -Force | Out-Null; continue }
            $pd = Split-Path $p -Parent
            if (-not (Test-Path -LiteralPath $pd)) { New-Item -ItemType Directory -Path $pd -Force | Out-Null }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $p, $true)
        }
    } finally { $za.Dispose() }
}

function Resolve-From {
    # -Tu: thư mục gói, thư mục chứa gói, goi.json trong gói, hoặc file .zip/.aes do Sao lưu tạo (giải ra thư mục tạm
    # trong du-lieu, xoá khi xong). Trả thư mục để đọc gói; '' khi bỏ trống; $null khi không dùng được (đã báo).
    param([string]$Path)
    if (-not $Path) { return '' }
    if (Test-Path -LiteralPath $Path -PathType Container) { return $Path }
    $hint = 'Chọn thư mục Goi_... (hoặc goi.json trong đó), thư mục chứa các gói, hoặc file .zip/.aes do Sao lưu tạo.'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Add-Finding 'KHONG_THAY_GOI' 'loi' ('Không thấy {0}' -f $Path) '' $hint; return $null }
    $name = Split-Path $Path -Leaf
    if ($name -ieq 'goi.json') { return (Split-Path $Path -Parent) }
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -notin '.zip', '.aes') { Add-Finding 'KHONG_THAY_GOI' 'loi' ('{0} không phải gói sao lưu' -f $name) '' $hint; return $null }
    $tmp = Get-FreeName (Join-Path $script:DataDir ('GiaiNen_{0:yyyyMMdd_HHmmss}' -f (Get-Date)))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    [void]$script:TempDirs.Add($tmp)
    $zip = $Path
    try {
        if ($ext -eq '.aes') {
            $pw = Read-MatKhau
            if (-not $pw) { Add-Finding 'CHUA_CO_MAT_KHAU' 'loi' 'Gói đã mã hoá nhưng chưa có mật khẩu' '' 'Chạy trong cửa sổ có bàn phím, gõ mật khẩu đã đặt khi Sao lưu.'; return $null }
            $zip = Join-Path $tmp 'goi.zip'
            Unprotect-File $Path $zip $pw
        }
        Expand-ZipSafe $zip (Join-Path $tmp 'goi')
    } catch {
        Add-Finding 'MO_GOI_LOI' 'loi' ('Không mở được gói {0}' -f $name) $_.Exception.Message.Trim() 'Sai mật khẩu thì chạy lại và gõ đúng; tệp hỏng thì Sao lưu lại ở máy cũ.'
        return $null
    } finally {
        if ($zip -ne $Path -and (Test-Path -LiteralPath $zip)) { Remove-Item -LiteralPath $zip -Force }
    }
    Write-Info ('Đã mở gói {0}' -f $name)
    return (Join-Path $tmp 'goi')
}

function Remove-TempDirs {
    foreach ($d in @($script:TempDirs)) {
        try { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } } catch { Write-Warn "Không xoá được thư mục tạm $d" }
    }
    $script:TempDirs.Clear()
}

# ---------------------------------------------------------------- Claude Desktop
function Get-ClaudeAppDir {
    # Thư mục dữ liệu Claude Desktop. Bản Microsoft Store có thể lưu trong Packages\Claude_*\LocalCache\Roaming\Claude;
    # lấy nơi có config.json mới nhất.
    if ($env:CDB_CLAUDE_APPDATA) { return $env:CDB_CLAUDE_APPDATA }
    $cands = @(Join-Path $env:APPDATA 'Claude')
    $cands += @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'LocalCache\Roaming\Claude' })
    $best = $null; $t = [datetime]::MinValue
    foreach ($d in $cands) {
        $f = Join-Path $d 'config.json'
        if (Test-Path -LiteralPath $f -PathType Leaf) {
            $w = (Get-Item -LiteralPath $f).LastWriteTimeUtc
            if ($w -gt $t) { $t = $w; $best = $d }
        }
    }
    return $best
}

function Get-ClaudeDesktopProcess {
    @(Get-Process -Name 'claude' -ErrorAction SilentlyContinue | Where-Object {
            $p = $null; try { $p = [string]$_.Path } catch { }
            $p -and $p -match $script:DesktopExe
        })
}

function Confirm-DesktopClosed {
    # Claude Desktop đọc danh sách phiên lúc mở và giữ trong bộ nhớ: phải tắt trước khi ghi, mở lại mới thấy.
    if (-not @(Get-ClaudeDesktopProcess).Count) { return $true }
    Write-Warn 'Claude Desktop đang mở. Phải thoát hẳn Claude (chuột phải biểu tượng Claude ở khay đồng hồ, chọn Quit) trước khi ghi.'
    $close = [bool]$DongClaude
    if (-not $close) { $close = Read-YesNo 'Tự đóng Claude Desktop ngay (mọi cửa sổ Claude, kể cả phiên đang chạy)?' $false }
    if (-not $close) { return $false }
    Get-ClaudeDesktopProcess | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20 -and @(Get-ClaudeDesktopProcess).Count; $i++) { Start-Sleep -Milliseconds 500 }
    if (@(Get-ClaudeDesktopProcess).Count) { Write-Bad 'Chưa đóng được Claude Desktop.'; return $false }
    Write-Ok 'Đã đóng Claude Desktop.'
    return $true
}

function Get-ClaudeVersion {
    $cfg = Read-Obj (Join-Path $script:AppDir 'config.json')
    if ($cfg -and $cfg.updaterLastSeenVersion) { return [string]$cfg.updaterLastSeenVersion }
    return ''
}

function Test-VersionSeen {
    param([string]$Ver)
    foreach ($p in $script:DaXemTrenBan) { if ($Ver -eq $p -or $Ver.StartsWith("$p.")) { return $true } }
    return $false
}

function Get-ClaudePackage {
    # Bản Microsoft Store (MSIX) của Claude Desktop; $null khi không có.
    try { return @(Get-AppxPackage -Name 'Claude' -ErrorAction Stop | Where-Object { $_.PackageFamilyName -like 'Claude_*' })[0] } catch { return $null }
}

function Get-ClaudeAppId {
    # Mã ứng dụng để mở bản Microsoft Store qua shell:AppsFolder (không chạy thẳng file trong WindowsApps được).
    $p = Get-ClaudePackage
    if (-not $p) { return '' }
    $id = 'Claude'
    try {
        $apps = @((Get-AppxPackageManifest -Package $p.PackageFullName -ErrorAction Stop).Package.Applications.Application)
        $a = @($apps | Where-Object { [string]$_.Executable -like '*\Claude.exe' })[0]
        if (-not $a) { $a = $apps[0] }
        if ($a -and $a.Id) { $id = [string]$a.Id }
    } catch { }
    return '{0}!{1}' -f $p.PackageFamilyName, $id
}

function Get-ClaudeExe {
    # File chạy của Claude Desktop (lấy biểu tượng cho lối tắt): bản cài thường rồi bản Microsoft Store.
    if ($env:CDB_LENH_MO_CLAUDE) { return $env:CDB_LENH_MO_CLAUDE }
    $e = Join-Path $env:LOCALAPPDATA 'AnthropicClaude\claude.exe'
    if (Test-Path -LiteralPath $e -PathType Leaf) { return $e }
    $p = Get-ClaudePackage
    if ($p) { $e = Join-Path $p.InstallLocation 'app\Claude.exe'; if (Test-Path -LiteralPath $e -PathType Leaf) { return $e } }
    return ''
}

function Start-ClaudeDesktop {
    # Mở Claude Desktop; đang mở thì Windows đưa cửa sổ Claude lên trước. Trả $true khi đã gọi mở.
    # CDB_LENH_MO_CLAUDE: bài thử thay Claude bằng chương trình giả.
    if ($env:CDB_LENH_MO_CLAUDE) { Start-Process -FilePath $env:CDB_LENH_MO_CLAUDE; return $true }
    $e = Join-Path $env:LOCALAPPDATA 'AnthropicClaude\claude.exe'
    if (Test-Path -LiteralPath $e -PathType Leaf) { Start-Process -FilePath $e; return $true }
    $id = Get-ClaudeAppId
    if ($id) { Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$id"; return $true }
    return $false
}

function Save-ClaudeIcon {
    # Biểu tượng cho lối tắt, chép vào du-lieu: đường dẫn bản Microsoft Store đổi theo mỗi lần Claude cập nhật.
    $ico = Join-Path $script:DataDir 'claude.ico'
    $exe = Get-ClaudeExe
    if ($exe) {
        try {
            Add-Type -AssemblyName System.Drawing
            $i = [Drawing.Icon]::ExtractAssociatedIcon($exe)
            if (-not (Test-Path -LiteralPath $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null }
            $fs = [IO.File]::Create($ico)
            try { $i.Save($fs) } finally { $fs.Dispose(); $i.Dispose() }
        } catch { }
    }
    if (Test-Path -LiteralPath $ico -PathType Leaf) { return $ico }
    return ''
}

function Get-CurrentAccount {
    # Tài khoản Claude Desktop đang đăng nhập: lastKnownAccountUuid trong config.json. Mã tổ chức: thư mục danh sách phiên
    # của tài khoản đó (ưu tiên tổ chức ghi trong ~\.claude.json, rồi thư mục mới nhất); chưa có thư mục thì lấy từ
    # ~\.claude.json (cùng tài khoản) hoặc remote-control-state.json.
    $cfg = Read-Obj (Join-Path $script:AppDir 'config.json')
    $acct = if ($cfg) { [string]$cfg.lastKnownAccountUuid } else { '' }
    if ($acct -notmatch $script:GuidMau) { return $null }
    $cj = Read-Obj $script:ClaudeJson
    $cjOrg = ''
    if ($cj -and $cj.oauthAccount -and [string]$cj.oauthAccount.accountUuid -eq $acct) { $cjOrg = [string]$cj.oauthAccount.organizationUuid }
    $dirs = @(Get-ChildItem -LiteralPath (Join-Path $script:SessRoot $acct) -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $script:GuidMau } | Sort-Object LastWriteTimeUtc -Descending)
    $org = ''
    if ($cjOrg -and @($dirs | Where-Object { $_.Name -eq $cjOrg }).Count) { $org = $cjOrg }
    elseif ($dirs.Count) { $org = $dirs[0].Name }
    elseif ($cjOrg) { $org = $cjOrg }
    else {
        $rc = Read-Obj (Join-Path $script:AppDir 'remote-control-state.json')
        if ($rc -and $rc.identities) {
            foreach ($k in @($rc.identities.PSObject.Properties | ForEach-Object { $_.Name })) {
                if ($k -match ('^([0-9a-f-]{36}):' + [regex]::Escape($acct) + '$')) { $org = $Matches[1]; break }
            }
        }
    }
    if ($org -notmatch $script:GuidMau) { $org = '' }
    return [pscustomobject]@{ Acct = $acct; Org = $org; Dir = $(if ($org) { Join-Path (Join-Path $script:SessRoot $acct) $org } else { '' }) }
}

function Test-BypassAllowed {
    # Tài khoản đã tự bật chế độ không hỏi quyền (bypass permissions) trong Claude Desktop chưa.
    param([string]$Acct)
    $c = Read-Obj (Join-Path $script:AppDir 'claude_desktop_config.json')
    if (-not $c -or -not $c.preferences -or -not $c.preferences.bypassPermissionsOptInByAccount) { return $false }
    return ($c.preferences.bypassPermissionsOptInByAccount.$Acct -eq $true)
}

function Update-Labels {
    # Email của tài khoản (từ ~\.claude.json) để hiện tên dễ hiểu thay cho mã; chỉ lưu trong du-lieu của công cụ.
    $script:Labels = @{}
    $old = Read-Obj $script:LabelFile
    if ($old) { foreach ($p in $old.PSObject.Properties) { if ($p.Value.email) { $script:Labels[$p.Name] = [string]$p.Value.email } } }
    $cj = Read-Obj $script:ClaudeJson
    if (-not $cj -or -not $cj.oauthAccount) { return }
    $a = [string]$cj.oauthAccount.accountUuid
    $e = [string]$cj.oauthAccount.emailAddress
    if ($a -notmatch $script:GuidMau -or -not $e -or $script:Labels[$a] -eq $e) { return }
    $script:Labels[$a] = $e
    if ($ChayThu) { return }
    $o = [ordered]@{}
    foreach ($k in @($script:Labels.Keys | Sort-Object)) { $o[$k] = [ordered]@{ email = $script:Labels[$k] } }
    try { Write-Obj $script:LabelFile $o } catch { }
}

function Get-Label {
    param([string]$Acct)
    $short = if ($Acct.Length -ge 8) { $Acct.Substring(0, 8) } else { $Acct }
    if ($script:Labels[$Acct]) { return '{0} ({1})' -f $script:Labels[$Acct], $short }
    return "tài khoản $short"
}

function Get-StoreLabel {
    param($Store)
    if ($Store.Kind -eq 'goi') { return 'gói {0} của {1}' -f $Store.Ten, (Get-Label $Store.Acct) }
    return Get-Label $Store.Acct
}

# ---------------------------------------------------------------- mục đã thêm (da-them.json)
# Tác vụ hẹn giờ, mẫu phiên, mục thanh bên, Cowork, file trí nhớ không có dấu đã xoá như danh sách phiên: công cụ nhớ
# những gì đã thêm vào tài khoản (theo máy) để mục người dùng đã xoá không bị thêm lại ở lần đồng bộ sau.
function Get-MemoKey { param([string]$Scope) return '{0}|{1}' -f $env:COMPUTERNAME, $Scope }

function Read-Memo {
    $h = @{}
    $o = Read-Obj $script:MemoFile
    if ($o) {
        foreach ($p in $o.PSObject.Properties) {
            $g = @{}
            foreach ($q in $p.Value.PSObject.Properties) { $g[$q.Name] = @($q.Value | Where-Object { $_ } | ForEach-Object { [string]$_ }) }
            $h[$p.Name] = $g
        }
    }
    return $h
}

function Test-Memo {
    param($Memo, [string]$Key, [string]$Group, [string]$Id)
    $g = $Memo[$Key]
    if (-not $g) { return $false }
    return (@($g[$Group]) -contains $Id)
}

function Update-Memo {
    # $Items: các @{ khoa; nhom; ma } cần nhớ (hoặc quên khi -Bo, lúc Hoàn tác).
    param($Items, [switch]$Bo)
    $list = @($Items | Where-Object { $_ })
    if (-not $list.Count) { return }
    $m = Read-Memo
    foreach ($it in $list) {
        $k = [string]$it.khoa; $n = [string]$it.nhom; $id = [string]$it.ma
        if (-not $m[$k]) { $m[$k] = @{} }
        $cur = @($m[$k][$n] | Where-Object { $_ -and $_ -ne $id })
        if (-not $Bo) { $cur += $id }
        $m[$k][$n] = $cur
    }
    $o = [ordered]@{}
    foreach ($k in @($m.Keys | Sort-Object)) {
        $g = [ordered]@{}
        foreach ($n in @($m[$k].Keys | Sort-Object)) { $g[$n] = @($m[$k][$n]) }
        $o[$k] = $g
    }
    Write-Obj $script:MemoFile $o
}

# ---------------------------------------------------------------- danh sách phiên, nội dung
function New-Store {
    param([string]$Kind, [string]$Acct, [string]$Org, [string]$Dir)
    return [pscustomobject]@{
        Kind = $Kind; Acct = $Acct; Org = $Org; Dir = $Dir; NoiDung = ''; UserDir = $script:UserDir; Ten = ''; Goc = ''; Luc = ''; May = ''
        NguoiDung = ''; Cowork = $(if ($Kind -eq 'may' -and $Acct -and $Org) { Join-Path $script:AppDir "local-agent-mode-sessions\$Acct\$Org" } else { '' }); CungMay = $true
    }
}

function Get-MachineStores {
    # Danh sách phiên của từng tài khoản đã đăng nhập trên máy: claude-code-sessions\<tài khoản>\<tổ chức>.
    $list = @()
    foreach ($a in @(Get-ChildItem -LiteralPath $script:SessRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $script:GuidMau })) {
        foreach ($o in @(Get-ChildItem -LiteralPath $a.FullName -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $script:GuidMau })) {
            $list += New-Store 'may' $a.Name $o.Name $o.FullName
        }
    }
    return $list
}

function Get-PackageStores {
    # Gói sao lưu: thư mục có goi.json. $From là một gói hoặc thư mục chứa các gói (mặc định du-lieu của công cụ). Gói
    # đang ghi dở (dangGhi, Sao lưu bị ngắt) thì bỏ qua.
    param([string]$From)
    $roots = if ($From) { @($From) } else { @($script:DataDir) }
    $dirs = @()
    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r -PathType Container)) { continue }
        if (Test-Path -LiteralPath (Join-Path $r 'goi.json') -PathType Leaf) { $dirs += (Get-Item -LiteralPath $r).FullName; continue }
        $dirs += @(Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'goi.json') -PathType Leaf } | ForEach-Object { $_.FullName })
    }
    $list = @()
    foreach ($d in $dirs) {
        $g = Read-Obj (Join-Path $d 'goi.json')
        if (-not $g -or $g.chuan -ne $script:GoiChuan -or -not $g.taiKhoan -or [string]$g.taiKhoan.acct -notmatch $script:GuidMau) { continue }
        if ($g.dangGhi -eq $true) { if ($script:DangGhi -notcontains $d) { [void]$script:DangGhi.Add($d) }; continue }
        $acct = [string]$g.taiKhoan.acct
        if ($g.taiKhoan.email -and -not $script:Labels[$acct]) { $script:Labels[$acct] = [string]$g.taiKhoan.email }
        $s = New-Store 'goi' $acct ([string]$g.taiKhoan.org) (Join-Path $d 'phien')
        $s.NoiDung = Join-Path $d 'noi-dung'; $s.NguoiDung = Join-Path $d 'nguoi-dung'; $s.Cowork = Join-Path $d 'cowork'
        $s.UserDir = ([string]$g.thuMucNguoiDung).TrimEnd('\'); $s.Ten = (Split-Path $d -Leaf); $s.Goc = $d; $s.Luc = [string]$g.luc; $s.May = [string]$g.may
        $s.CungMay = ($s.May -ieq $env:COMPUTERNAME -and $s.UserDir -ieq $script:UserDir)
        $list += $s
    }
    return $list
}

function Test-SessionEntry {
    # '' khi mục danh sách phiên đúng cấu trúc công cụ biết, ngược lại là lý do. Claude bản mới đổi cách lưu thì phần
    # lớn mục sẽ sai ở đây và công cụ dừng thay vì ghi bừa (CACH_LUU_DA_DOI).
    param($Data, [string]$Uuid)
    if ($null -eq $Data) { return 'không đọc được JSON' }
    if ([string]$Data['sessionId'] -ne "local_$Uuid") { return 'sessionId khác tên file' }
    if ([string]$Data['cliSessionId'] -and [string]$Data['cliSessionId'] -notmatch $script:GuidMau) { return 'cliSessionId lạ' }
    if (-not [string]$Data['cwd']) { return 'thiếu cwd' }
    $l = $Data['lastActivityAt']
    if (-not ($l -is [int] -or $l -is [long] -or $l -is [decimal] -or $l -is [double]) -or $l -le 0) { return 'lastActivityAt không phải số' }
    return ''
}

function Read-Sessions {
    # Các mục local_<mã>.json của một nơi. Data: Dictionary đủ mọi trường để ghi lại nguyên vẹn. Mục sai cấu trúc ghi vào
    # $script:Invalid[<thư mục>] và bỏ qua.
    param($Store)
    $list = @()
    $bad = New-Object System.Collections.ArrayList
    if ($Store.Dir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $Store.Dir -File -Filter 'local_*.json' -ErrorAction SilentlyContinue)) {
            $m = [regex]::Match($f.Name, '^local_([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.json$')
            if (-not $m.Success) { continue }
            $d = Read-DictCached $f
            $why = Test-SessionEntry $d $m.Groups[1].Value
            if ($why) { [void]$bad.Add(('{0}: {1}' -f $f.Name, $why)); continue }
            $list += [pscustomobject]@{
                Id = [string]$d['sessionId']; Uuid = $m.Groups[1].Value; File = $f.FullName; Data = $d; Store = $Store
                Last = (Get-Num $d['lastActivityAt']); Cli = [string]$d['cliSessionId']; Cwd = [string]$d['cwd']
                Title = [string]$d['title']; Archived = [bool]$d['isArchived']
            }
        }
    }
    $script:Invalid[[string]$Store.Dir] = $bad
    return $list
}

function Get-Invalid { param([string]$Dir) $b = $script:Invalid[$Dir]; if ($b) { return @($b) } return @() }

function Test-ShapeBad {
    # Quá nửa số mục không đúng cấu trúc: coi như Claude đã đổi cách lưu.
    param([int]$Bad, [int]$Good)
    return ($Bad -gt 0 -and $Bad * 2 -gt $Bad + $Good)
}

function Add-ShapeFinding {
    param($Reasons)
    $v = if ($script:ClaudeVer) { " (Claude Desktop $script:ClaudeVer)" } else { '' }
    Add-Finding 'CACH_LUU_DA_DOI' 'loi' "Danh sách phiên của Claude không đúng cấu trúc công cụ biết$v" (@($Reasons | Select-Object -First 4) -join '; ') ('Có thể Claude bản mới đã đổi cách lưu. Công cụ dừng, không ghi gì để khỏi làm hỏng danh sách phiên; báo lại để sửa công cụ (đã viết theo bản {0}).' -f ($script:DaXemTrenBan -join ', '))
}

function Get-TranscriptIndex {
    # Nội dung hội thoại: projects\<thư mục dự án>\<mã phiên>.jsonl; trùng mã thì lấy file lớn nhất.
    param([string]$ProjDir)
    $ix = @{}
    foreach ($p in @(Get-ChildItem -LiteralPath $ProjDir -Directory -Force -ErrorAction SilentlyContinue)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $p.FullName -File -Filter '*.jsonl' -Force -ErrorAction SilentlyContinue)) {
            if (-not $ix.ContainsKey($f.BaseName) -or $f.Length -gt $ix[$f.BaseName].Length) { $ix[$f.BaseName] = $f }
        }
    }
    return $ix
}

# Claude Code đặt tên thư mục dự án theo đường dẫn, ký tự không phải chữ, số thành '-' (C:\Users\A\x -> C--Users-A-x).
function Convert-ProjectName { param([string]$Path) return ($Path -replace '[^A-Za-z0-9]', '-') }

function Convert-UserPath {
    # Gói làm ở thư mục người dùng khác (máy khác, tên tài khoản Windows khác): đổi phần đầu đường dẫn.
    param([string]$Path, [string]$Old, [string]$New)
    if (-not $Path -or -not $Old -or $Old -ieq $New) { return $Path }
    if ($Path -ieq $Old) { return $New }
    if ($Path.StartsWith($Old + '\', [StringComparison]::OrdinalIgnoreCase)) { return $New + $Path.Substring($Old.Length) }
    return $Path
}

function Convert-ProjectSlug {
    param([string]$Slug, [string]$Old, [string]$New)
    if (-not $Old -or $Old -ieq $New) { return $Slug }
    $o = Convert-ProjectName $Old; $n = Convert-ProjectName $New
    if ($Slug -ieq $o) { return $n }
    if ($Slug.StartsWith($o + '-', [StringComparison]::OrdinalIgnoreCase)) { return $n + $Slug.Substring($o.Length) }
    return $Slug
}

function Convert-UserText {
    # Văn bản (trí nhớ dự án .md, file tác vụ hẹn giờ) có đường dẫn trong thư mục người dùng cũ: dạng JSON C:\\Users\\A,
    # dạng C:/Users/A, dạng thường C:\Users\A. Giống Remap-Text của new-windows.
    param([string]$Text, [string]$Old, [string]$New)
    if (-not $Old -or $Old -ieq $New) { return $Text }
    foreach ($f in @(@($Old.Replace('\', '\\'), $New.Replace('\', '\\')), @($Old.Replace('\', '/'), $New.Replace('\', '/')), @($Old, $New))) {
        $Text = [regex]::Replace($Text, [regex]::Escape($f[0]) + '(?=[\\/"''`\s)\]>,;*]|$)', $f[1].Replace('$', '$$'), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    return $Text
}

function Convert-PackagePath {
    # File trong nguoi-dung\ của gói -> đường dẫn trên máy này (thư mục dự án đổi tên theo thư mục người dùng mới).
    param([string]$Rel, [string]$OldUser)
    $parts = @($Rel -split '\\')
    if ($parts.Count -ge 3 -and $parts[0] -ieq '.claude' -and $parts[1] -ieq 'projects') { $parts[2] = Convert-ProjectSlug $parts[2] $OldUser $script:UserDir }
    return Join-Path $script:UserDir ($parts -join '\')
}

function Get-UserFileLabel {
    param([string]$Path)
    $rel = if ($Path.StartsWith($script:UserDir + '\', [StringComparison]::OrdinalIgnoreCase)) { $Path.Substring($script:UserDir.Length + 1) } else { $Path }
    $p = @($rel -split '\\')
    if ($p.Count -ge 5 -and $p[0] -ieq '.claude' -and $p[1] -ieq 'projects' -and $p[3] -ieq 'memory') { return 'trí nhớ dự án {0}: {1}' -f $p[2], ($p[4..($p.Count - 1)] -join '\') }
    if ($p.Count -ge 3 -and $p[0] -ieq '.claude' -and $p[1] -ieq 'scheduled-tasks') { return 'file tác vụ hẹn giờ {0}' -f ($p[2..($p.Count - 1)] -join '\') }
    return $rel
}

function Find-Transcript {
    # Nội dung của một phiên. Có sẵn trên máy (cùng mã) thì dùng luôn. Phiên trong gói: bản trong gói lớn hơn bản trên máy
    # (hoặc máy chưa có) thì chép vào ~\.claude\projects, kèm thư mục <mã phiên> (hội thoại của tác tử con, kết quả lệnh).
    param($S, $Ix)
    if (-not $S.Cli) { return $null }
    $local = if ($Ix.ContainsKey($S.Cli)) { $Ix[$S.Cli] } else { $null }
    if ($S.Store.Kind -eq 'goi') {
        $pf = $null
        foreach ($p in @(Get-ChildItem -LiteralPath $S.Store.NoiDung -Directory -ErrorAction SilentlyContinue)) {
            $c = Join-Path $p.FullName "$($S.Cli).jsonl"
            if (Test-Path -LiteralPath $c -PathType Leaf) { $pf = Get-Item -LiteralPath $c; break }
        }
        if ($pf -and (-not $local -or $pf.Length -gt $local.Length)) {
            $dest = if ($local) { $local.FullName } else {
                Join-Path (Join-Path $script:ProjectsDir (Convert-ProjectSlug $pf.Directory.Name $S.Store.UserDir $script:UserDir)) $pf.Name
            }
            $side = Join-Path $pf.DirectoryName $S.Cli
            return [pscustomobject]@{
                Copy = $true; Src = $pf.FullName; Dest = $dest; Size = ($pf.Length + (Get-DirSize $side))
                Side = $side; SideDest = (Join-Path (Split-Path $dest -Parent) $S.Cli)
            }
        }
    }
    if ($local) { return [pscustomobject]@{ Copy = $false; Src = $local.FullName; Dest = $local.FullName; Size = [long]0; Side = ''; SideDest = '' } }
    return $null
}

function Convert-ForTarget {
    # Bản mục danh sách cho tài khoản đang dùng: bỏ trường gắn với tài khoản cũ; tài khoản này chưa tự bật chế độ không
    # hỏi quyền thì phiên mở lại ở chế độ hỏi trước; gói làm ở thư mục người dùng khác thì đổi đường dẫn.
    param($Data, [bool]$BypassOk, [string]$OldUser, [string]$NewUser)
    $d = Copy-Dict $Data
    foreach ($k in $script:AccountFields) { [void]$d.Remove($k) }
    if (-not $BypassOk -and [string]$d['permissionMode'] -eq 'bypassPermissions') {
        $d['permissionMode'] = 'default'
        if ($d.ContainsKey('bypassChosenInApp')) { $d['bypassChosenInApp'] = $false }
    }
    if ($OldUser -and $OldUser -ine $NewUser) {
        foreach ($k in 'cwd', 'originCwd') { if ($d.ContainsKey($k)) { $d[$k] = Convert-UserPath ([string]$d[$k]) $OldUser $NewUser } }
        if ($d['gitAnchors'] -is [array]) {
            foreach ($g in $d['gitAnchors']) {
                if ($g -isnot [System.Collections.Generic.IDictionary[string, object]]) { continue }
                foreach ($k in 'gitRoot', 'commonDir') { if ($g.ContainsKey($k)) { $g[$k] = Convert-UserPath ([string]$g[$k]) $OldUser $NewUser } }
            }
        }
        if ($d['writtenBranches'] -is [array]) {
            # "đường dẫn repo\0tên nhánh"
            $d['writtenBranches'] = @($d['writtenBranches'] | ForEach-Object {
                    $p = [string]$_; $i = $p.IndexOf([char]0)
                    if ($i -gt 0) { (Convert-UserPath $p.Substring(0, $i) $OldUser $NewUser) + $p.Substring($i) } else { Convert-UserPath $p $OldUser $NewUser }
                })
        }
    }
    return $d
}

function Test-NenThay {
    # Tài khoản đang dùng đã có phiên này (cùng mã) nhưng khác bản ở nơi khác: bản có lần dùng cuối (lastActivityAt) mới
    # hơn thắng, hợp với kiểu dùng xoay vòng A, B, A. Bằng nhau thì giữ bản đang có để chạy nhiều lần không thay qua lại.
    # Thay thì bản đang có được cất vào du-lieu\HoanTac, Hoàn tác trả lại được.
    param($Dich, $Nguon)
    return ((Get-Num $Nguon['lastActivityAt']) -gt (Get-Num $Dich['lastActivityAt']))
}

function Get-SyncPlan {
    # So danh sách phiên của tài khoản đang dùng với các nguồn (tài khoản khác trên máy, gói sao lưu). Mỗi mã phiên lấy
    # bản mới nhất trong các nguồn; cùng lúc thì ưu tiên bản trên máy (nội dung đã nằm sẵn). Kèm phần ngoài danh sách
    # phiên (Get-ExtraPlan).
    param([string]$From)
    $tgt = New-Store 'may' $script:Cur.Acct $script:Cur.Org $script:Cur.Dir
    $mine = @(Read-Sessions $tgt)
    $badTgt = @(Get-Invalid $tgt.Dir)
    $have = @{}
    foreach ($s in $mine) { $have[$s.Id] = $s }
    $tomb = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @(Get-ChildItem -LiteralPath $script:Cur.Dir -File -Filter 'deleted_*' -ErrorAction SilentlyContinue)) {
        [void]$tomb.Add(($f.Name -replace '^deleted_', '' -replace '\.json$', ''))
    }
    $sources = @(Get-MachineStores | Where-Object { -not ($_.Acct -eq $script:Cur.Acct -and $_.Org -eq $script:Cur.Org) })
    $sources += @(Get-PackageStores $From)
    $best = @{}
    $bad = New-Object System.Collections.ArrayList
    $nMay = 0; $badMay = 0
    foreach ($src in $sources) {
        $ss = @(Read-Sessions $src)
        $b = @(Get-Invalid $src.Dir)
        foreach ($x in $b) { [void]$bad.Add(('{0}, {1}' -f (Get-StoreLabel $src), $x)) }
        if ($src.Kind -eq 'may') { $nMay += $ss.Count; $badMay += $b.Count }
        foreach ($s in $ss) {
            $o = $best[$s.Id]
            if (-not $o -or $s.Last -gt $o.Last -or ($s.Last -eq $o.Last -and $s.Store.Kind -eq 'may' -and $o.Store.Kind -ne 'may')) { $best[$s.Id] = $s }
        }
    }
    foreach ($x in $badTgt) { [void]$bad.Add(('{0}, {1}' -f (Get-Label $script:Cur.Acct), $x)) }
    $ix = Get-TranscriptIndex $script:ProjectsDir
    $plan = [pscustomobject]@{
        Nguon = $sources; Co = $have.Count; Giong = 0; Mine = $mine
        Them = (New-Object System.Collections.ArrayList); Thay = (New-Object System.Collections.ArrayList)
        Giu = (New-Object System.Collections.ArrayList); DaXoa = (New-Object System.Collections.ArrayList)
        ThieuNoiDung = (New-Object System.Collections.ArrayList); KhongHopLe = $bad
        CauTrucLa = ((Test-ShapeBad $badTgt.Count $mine.Count) -or (Test-ShapeBad $badMay $nMay)); Extra = $null
    }
    foreach ($s in @($best.Values | Sort-Object Last -Descending)) {
        if ($tomb.Contains($s.Uuid)) { [void]$plan.DaXoa.Add($s); continue }
        $h = $have[$s.Id]
        if ($h -and $h.Last -eq $s.Last -and $h.Title -ceq $s.Title -and $h.Archived -eq $s.Archived) { $plan.Giong++; continue }
        $tx = Find-Transcript $s $ix
        if (-not $tx) { [void]$plan.ThieuNoiDung.Add($s); continue }
        $item = [pscustomobject]@{ S = $s; Tx = $tx; Cu = $h }
        if (-not $h) { [void]$plan.Them.Add($item) }
        elseif (Test-NenThay $h.Data $s.Data) { [void]$plan.Thay.Add($item) }
        else { [void]$plan.Giu.Add($item) }
    }
    $plan.Extra = Get-ExtraPlan $sources
    return $plan
}

# ---------------------------------------------------------------- phần ngoài danh sách phiên
function Add-TaskPlan {
    # Thêm tác vụ hẹn giờ của các nguồn vào file của tài khoản đang dùng: trùng mã, trùng file nhắc việc (filePath) hoặc
    # đã thêm một lần rồi (người dùng xoá) thì bỏ qua; file nhắc việc chưa có trên máy (và gói không mang theo) thì báo.
    param($X, [string]$File, $Sources, $Planned, $Memo, [string]$MemoKey, [string]$Group, [string]$Label)
    if (-not @($Sources).Count) { return }
    $t = Read-JsonIf $File
    $tasks = New-Object System.Collections.ArrayList
    if ($t) { foreach ($k in @(Get-Arr $t['scheduledTasks'])) { [void]$tasks.Add($k) } }
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $fps = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $tasks) { if ($k -is [System.Collections.IDictionary]) { [void]$ids.Add([string]$k['id']); if ($k['filePath']) { [void]$fps.Add([string]$k['filePath']) } } }
    $added = @(); $names = @()
    foreach ($src in $Sources) {
        foreach ($k in @(Get-Arr $src.Dict['scheduledTasks'])) {
            if ($k -isnot [System.Collections.IDictionary]) { continue }
            $id = [string]$k['id']
            if (-not $id -or $ids.Contains($id) -or (Test-Memo $Memo $MemoKey $Group $id)) { continue }
            $c = Copy-Dict $k
            foreach ($f in 'filePath', 'cwd') { if (Test-Key $c $f) { $c[$f] = Convert-UserPath ([string]$c[$f]) $src.UserDir $script:UserDir } }
            if ($c['userSelectedFolders'] -is [array]) { $c['userSelectedFolders'] = @($c['userSelectedFolders'] | ForEach-Object { Convert-UserPath ([string]$_) $src.UserDir $script:UserDir }) }
            $fp = [string]$c['filePath']
            $name = if ($c['displayName']) { [string]$c['displayName'] } else { $id }
            if ($fp -and $fps.Contains($fp)) { continue }
            if ($fp -and -not (Test-Path -LiteralPath $fp) -and -not $Planned.Contains($fp)) { [void]$X.BoQua.Add(('{0} "{1}": thiếu {2}' -f $Label, $name, $fp)); continue }
            [void]$tasks.Add($c); [void]$ids.Add($id); if ($fp) { [void]$fps.Add($fp) }
            $added += @{ khoa = $MemoKey; nhom = $Group; ma = $id }; $names += $name
        }
    }
    if (-not $added.Count) { return }
    if ($t) { $new = Copy-Dict $t } else { $new = New-Dict; $new['recordedSkips'] = New-Dict }
    $new['scheduledTasks'] = $tasks.ToArray()
    [void]$X.Json.Add([pscustomobject]@{ Dest = $File; Dict = $new; Nhan = ('{0}: {1}' -f $Label, ($names -join ', ')); Memo = $added })
}

function Get-ExtraPlan {
    # Ngoài danh sách phiên: file người dùng trong gói làm ở máy khác (trí nhớ dự án, file tác vụ hẹn giờ), tác vụ hẹn giờ
    # tab Code, mẫu phiên, mục thanh bên tab Code, và (-KemCowork) phiên, tác vụ hẹn giờ Cowork. Chỉ thêm cái tài khoản
    # đang dùng chưa có; mục đã thêm một lần mà người dùng xoá đi thì không thêm lại (da-them.json).
    param($Sources)
    $x = [pscustomobject]@{
        Tep = (New-Object System.Collections.ArrayList); Json = (New-Object System.Collections.ArrayList)
        Khoa = (New-Object System.Collections.ArrayList); Cowork = (New-Object System.Collections.ArrayList)
        BoQua = (New-Object System.Collections.ArrayList); Size = [long]0
    }
    $memo = Read-Memo
    $kAcct = Get-MemoKey $script:Cur.Acct
    $kUser = Get-MemoKey $script:UserDir
    $planned = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    # (1) File người dùng: cùng máy thì ~\.claude đã dùng chung, chỉ lấy từ gói làm ở máy (hoặc thư mục người dùng) khác.
    # Nhiều gói cùng có một file thì lấy bản sửa sau cùng; máy đã có bản mới hơn thì giữ.
    $best = @{}
    foreach ($src in @($Sources | Where-Object { $_.Kind -eq 'goi' -and -not $_.CungMay -and $_.NguoiDung -and (Test-Path -LiteralPath $_.NguoiDung -PathType Container) })) {
        $base = (Get-Item -LiteralPath $src.NguoiDung).FullName.TrimEnd('\')
        foreach ($f in @(Get-ChildItem -LiteralPath $base -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            $dest = Convert-PackagePath $f.FullName.Substring($base.Length + 1) $src.UserDir
            $o = $best[$dest]
            if ($o -and $o.Info.LastWriteTimeUtc -ge $f.LastWriteTimeUtc) { continue }
            $best[$dest] = [pscustomobject]@{ Info = $f; Store = $src }
        }
    }
    foreach ($dest in @($best.Keys | Sort-Object)) {
        $b = $best[$dest]
        $text = $null
        if ($b.Info.Extension -in '.md', '.txt', '.json') { $text = Convert-UserText ([IO.File]::ReadAllText($b.Info.FullName, [Text.Encoding]::UTF8)) $b.Store.UserDir $script:UserDir }
        $loai = 'them-tep'
        if (Test-Path -LiteralPath $dest -PathType Leaf) {
            if ($b.Info.LastWriteTimeUtc -le (Get-Item -LiteralPath $dest -Force).LastWriteTimeUtc) { continue }
            if ($null -ne $text) { $same = ([IO.File]::ReadAllText($dest, [Text.Encoding]::UTF8) -ceq $text) } else { $same = ((Get-Hash $dest) -eq (Get-Hash $b.Info.FullName)) }
            if ($same) { continue }
            $loai = 'thay-tep'
        } elseif (Test-Memo $memo $kUser 'tep' $dest) { continue }
        [void]$x.Tep.Add([pscustomobject]@{ Loai = $loai; Src = $b.Info.FullName; Dest = $dest; Text = $text; Nhan = (Get-UserFileLabel $dest); Size = $b.Info.Length; Memo = @(@{ khoa = $kUser; nhom = 'tep'; ma = $dest }) })
        [void]$planned.Add($dest); $x.Size += $b.Info.Length
    }

    # (2) Tác vụ hẹn giờ tab Code: claude-code-sessions\<tài khoản>\<tổ chức>\scheduled-tasks.json (gói: phien\).
    $ts = @()
    foreach ($src in $Sources) {
        $d = Read-JsonIf (Join-Path $src.Dir 'scheduled-tasks.json')
        if ($d -and @(Get-Arr $d['scheduledTasks']).Count) { $ts += [pscustomobject]@{ Dict = $d; UserDir = $src.UserDir } }
    }
    Add-TaskPlan $x (Join-Path $script:Cur.Dir 'scheduled-tasks.json') $ts $planned $memo $kAcct 'henGio' 'tác vụ hẹn giờ tab Code'

    # (3) Mẫu phiên (preset ở ô tạo phiên mới): ccd-session-presets.json, byAccount[<tài khoản>] (gói: phien\mau-phien.json).
    $pf = Join-Path $script:AppDir 'ccd-session-presets.json'
    $all = Read-JsonIf $pf
    $ps = @()
    foreach ($src in $Sources) {
        $o = $null
        if ($src.Kind -eq 'goi') { $o = Read-JsonIf (Join-Path $src.Dir 'mau-phien.json') }
        elseif ($all -and (Test-Key $all['byAccount'] $src.Acct)) { $o = $all['byAccount'][$src.Acct] }
        if ($o -is [System.Collections.IDictionary] -and @(Get-Arr $o['presets']).Count) { $ps += [pscustomobject]@{ Obj = $o; UserDir = $src.UserDir } }
    }
    if ($ps.Count) {
        $new = if ($all) { Copy-Dict $all } else { New-Dict }
        if ($new['byAccount'] -isnot [System.Collections.IDictionary]) { $new['byAccount'] = New-Dict }
        $cur = $new['byAccount'][$script:Cur.Acct]
        $list = New-Object System.Collections.ArrayList
        $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        if ($cur -is [System.Collections.IDictionary]) { foreach ($p in @(Get-Arr $cur['presets'])) { [void]$list.Add($p); [void]$ids.Add([string]$p['id']) } }
        $added = @(); $names = @()
        foreach ($src in $ps) {
            foreach ($p in @(Get-Arr $src.Obj['presets'])) {
                if ($p -isnot [System.Collections.IDictionary]) { continue }
                $id = [string]$p['id']
                if (-not $id -or $ids.Contains($id) -or (Test-Memo $memo $kAcct 'mauPhien' $id)) { continue }
                $c = Copy-Dict $p
                if ($c['target'] -is [System.Collections.IDictionary] -and (Test-Key $c['target'] 'cwd')) { $c['target']['cwd'] = Convert-UserPath ([string]$c['target']['cwd']) $src.UserDir $script:UserDir }
                [void]$list.Add($c); [void]$ids.Add($id)
                $added += @{ khoa = $kAcct; nhom = 'mauPhien'; ma = $id }; $names += [string]$c['name']
            }
        }
        if ($added.Count) {
            if ($cur -isnot [System.Collections.IDictionary]) {
                $cur = Copy-Dict $ps[0].Obj
                $new['byAccount'][$script:Cur.Acct] = $cur
            }
            $cur['presets'] = $list.ToArray()
            [void]$x.Json.Add([pscustomobject]@{ Dest = $pf; Dict = $new; Nhan = ('mẫu phiên: {0}' -f ($names -join ', ')); Memo = $added })
        }
    }

    # (4) Mục thanh bên tab Code: claude_desktop_config.json, preferences.epitaxyPrefs["dframe-code-sections"]
    # ["<tài khoản>/<tổ chức>"] (gói: phien\thanh-ben.json). Tài khoản chưa có thì lấy cả cách sắp xếp của tài khoản kia;
    # đã có thì chỉ thêm mục tự tạo còn thiếu. Ghim (starred-local-code-sessions) dùng chung cho mọi tài khoản trên máy.
    $cfgF = Join-Path $script:AppDir 'claude_desktop_config.json'
    $cfg = Read-JsonIf $cfgF
    if ($cfg) {
        $path = @('preferences', 'epitaxyPrefs', 'dframe-code-sections')
        $secs = Get-KeyNode $cfg $path
        $all2 = if ($secs.Found -and $secs.Value -is [System.Collections.IDictionary]) { $secs.Value } else { $null }
        $myKey = '{0}/{1}' -f $script:Cur.Acct, $script:Cur.Org
        $vals = @()
        foreach ($src in $Sources) {
            $v = $null
            if ($src.Kind -eq 'goi') { $v = Read-JsonIf (Join-Path $src.Dir 'thanh-ben.json') }
            elseif ($all2) { $v = $all2['{0}/{1}' -f $src.Acct, $src.Org] }
            if ($v -is [System.Collections.IDictionary] -and @(Get-Arr $v['sections']).Count) { $vals += , $v }
        }
        if ($vals.Count) {
            $cur = if ($all2) { $all2[$myKey] } else { $null }
            $fresh = ($cur -isnot [System.Collections.IDictionary])
            $newV = if ($fresh) { Copy-Dict $vals[0] } else { Copy-Dict $cur }
            $list = New-Object System.Collections.ArrayList
            $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            $order = 0
            $added = @(); $names = @()
            foreach ($s in @(Get-Arr $newV['sections'])) {
                [void]$list.Add($s); [void]$ids.Add([string]$s['id']); $order = [long][Math]::Max([long]$order, [long](Get-Num $s['order']))
                if ($fresh -and $script:BuiltInSections -notcontains [string]$s['kind']) { $added += @{ khoa = $kAcct; nhom = 'thanhBen'; ma = [string]$s['id'] }; $names += $(if ($s['name']) { [string]$s['name'] } else { [string]$s['id'] }) }
            }
            foreach ($v in $vals) {
                foreach ($s in @(Get-Arr $v['sections'])) {
                    $id = [string]$s['id']
                    if (-not $id -or $ids.Contains($id) -or $script:BuiltInSections -contains [string]$s['kind'] -or (Test-Memo $memo $kAcct 'thanhBen' $id)) { continue }
                    $c = Copy-Dict $s; $order++; $c['order'] = $order
                    [void]$list.Add($c); [void]$ids.Add($id)
                    $added += @{ khoa = $kAcct; nhom = 'thanhBen'; ma = $id }; $names += $(if ($c['name']) { [string]$c['name'] } else { $id })
                }
            }
            if ($fresh -or $added.Count) {
                $newV['sections'] = $list.ToArray()
                if ($fresh) {
                    $nhan = 'thanh bên tab Code: lấy cách sắp xếp của tài khoản khác'
                    if ($names.Count) { $nhan += ', có mục ' + ($names -join ', ') }
                } else { $nhan = 'thanh bên tab Code: thêm mục ' + ($names -join ', ') }
                [void]$x.Khoa.Add([pscustomobject]@{ Dest = $cfgF; Path = @($path + $myKey); Value = $newV; Nhan = $nhan; Memo = $added })
            }
        }
    }

    # (5) Cowork (-KemCowork, thử nghiệm): local-agent-mode-sessions\<tài khoản>\<tổ chức>, mục chưa có thì chép nguyên.
    if ($KemCowork) {
        $cwT = Join-Path $script:AppDir ('local-agent-mode-sessions\{0}\{1}' -f $script:Cur.Acct, $script:Cur.Org)
        $seen = @{}; $cts = @()
        foreach ($src in $Sources) {
            $dir = $src.Cowork
            if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
            foreach ($it in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
                if ($it.Name -in 'scheduled-tasks.json', 'remote-session-spaces.json') { continue }
                $dest = Join-Path $cwT $it.Name
                if ($seen[$it.Name] -or (Test-Path -LiteralPath $dest) -or (Test-Memo $memo $kAcct 'cowork' $it.Name)) { continue }
                $seen[$it.Name] = $true
                $sz = if ($it.PSIsContainer) { Get-DirSize $it.FullName } else { $it.Length }
                [void]$x.Cowork.Add([pscustomobject]@{ Src = $it.FullName; Dest = $dest; Dir = [bool]$it.PSIsContainer; Size = $sz; Nhan = ('Cowork: {0}' -f $it.Name); Memo = @(@{ khoa = $kAcct; nhom = 'cowork'; ma = $it.Name }) })
                $x.Size += $sz
            }
            $d = Read-JsonIf (Join-Path $dir 'scheduled-tasks.json')
            if ($d -and @(Get-Arr $d['scheduledTasks']).Count) { $cts += [pscustomobject]@{ Dict = $d; UserDir = $src.UserDir } }
        }
        Add-TaskPlan $x (Join-Path $cwT 'scheduled-tasks.json') $cts $planned $memo $kAcct 'henGioCowork' 'tác vụ hẹn giờ Cowork'
    }
    return $x
}

function Get-ExtraCount { param($X) return ($X.Tep.Count + $X.Json.Count + $X.Khoa.Count + $X.Cowork.Count) }

function Get-ExtraSummary {
    param($X)
    $p = @()
    if ($X.Tep.Count) { $p += '{0} file trí nhớ dự án, tác vụ hẹn giờ' -f $X.Tep.Count }
    foreach ($j in $X.Json) { $p += $j.Nhan }
    foreach ($k in $X.Khoa) { $p += $k.Nhan }
    if ($X.Cowork.Count) { $p += '{0} mục Cowork' -f $X.Cowork.Count }
    return ($p -join '; ')
}

function Show-ExtraItems {
    param($X)
    foreach ($t in $X.Tep) { Write-Plan ('{0} {1}' -f $(if ($t.Loai -eq 'thay-tep') { '[~]' } else { '[+]' }), $t.Nhan) }
    foreach ($j in $X.Json) { Write-Plan "[+] $($j.Nhan)" }
    foreach ($k in $X.Khoa) { Write-Plan "[~] $($k.Nhan)" }
    foreach ($c in $X.Cowork) { Write-Plan ('[+] {0} ({1})' -f $c.Nhan, (Format-Size $c.Size)) }
}

# ---------------------------------------------------------------- nhật ký hoàn tác
function Save-JournaledFile {
    # Ghi một file có nhật ký: đã có thì cất bản cũ vào thư mục nhật ký (Hoàn tác trả lại), chưa có thì Hoàn tác xoá.
    # Nguồn: -Dict (JSON), -Text, hoặc -Src (chép nguyên, giữ giờ sửa).
    param([string]$Jd, [string]$Key, [string]$Path, [string]$Label, [string]$Src = '', $Text = $null, $Dict = $null)
    $v = [ordered]@{ loai = 'them-tep'; tep = $Path; banCu = ''; hash = ''; tieuDe = $Label }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $v.loai = 'thay-tep'; $v.banCu = "tep\$Key$([IO.Path]::GetExtension($Path))"
        New-Item -ItemType Directory -Path (Join-Path $Jd 'tep') -Force | Out-Null
        Copy-Item -LiteralPath $Path -Destination (Join-Path $Jd $v.banCu) -Force
    }
    $dd = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
    if ($null -ne $Dict) { Write-Dict $Path $Dict }
    elseif ($null -ne $Text) { Write-TextAtomic $Path ([string]$Text) }
    else { Copy-Item -LiteralPath $Src -Destination $Path -Force }
    $v.hash = Get-Hash $Path
    return $v
}

function Save-JournaledKey {
    # Đổi một khoá trong file cấu hình (claude_desktop_config.json có thể chứa khoá bí mật của máy chủ MCP): nhật ký chỉ
    # giữ giá trị cũ, mới của khoá đó, không chép cả file.
    param([string]$Path, [string[]]$Keys, $Value, [string]$Label)
    $c = Read-Dict $Path
    if ($null -eq $c) { throw "không đọc được $Path" }
    $old = Get-KeyNode $c $Keys
    $cu = if ($old.Found) { ConvertTo-JsonText $old.Value } else { '' }
    Set-KeyValue $c $Keys $Value
    Write-Dict $Path $c
    return [ordered]@{ loai = 'doi-khoa'; tep = $Path; khoa = @($Keys); coCu = [bool]$old.Found; cu = $cu; moi = (ConvertTo-JsonText $Value); tieuDe = $Label }
}

function Find-LastJournal {
    # Lần đồng bộ gần nhất trên máy này chưa hoàn tác ($Acct: chỉ lần vào tài khoản đó).
    param([string]$Acct = '')
    foreach ($d in @(Get-ChildItem -LiteralPath $script:UndoDir -Directory -Filter 'DongBo_*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
        $f = Join-Path $d.FullName 'nhat-ky.json'
        $o = Read-Obj $f
        if (-not $o -or $o.chuan -ne $script:NhatKyChuan -or $o.hoanTacLuc) { continue }
        if ($o.may -and [string]$o.may -ne $env:COMPUTERNAME) { continue }
        if ($Acct -and [string]$o.taiKhoan -ne $Acct) { continue }
        return [pscustomobject]@{ Data = $o; File = $f; Dir = $d.FullName }
    }
    return $null
}

function Get-UndoState {
    # 'lam': hoàn tác được; 'giu': đã đổi sau khi đồng bộ (dùng tiếp) nên giữ; 'het': không còn gì để bỏ.
    param($V)
    switch ([string]$V.loai) {
        'them-thu-muc' {
            if (-not (Test-Path -LiteralPath ([string]$V.tep))) { return 'het' }
            if ((Get-DirSig ([string]$V.tep)) -ne [string]$V.ky) { return 'giu' }
            return 'lam'
        }
        'doi-khoa' {
            $c = Read-JsonIf ([string]$V.tep)
            if ($null -eq $c) { return 'het' }
            $n = Get-KeyNode $c @($V.khoa)
            if (-not $n.Found) { return 'het' }
            if ((ConvertTo-JsonText $n.Value) -cne [string]$V.moi) { return 'giu' }
            return 'lam'
        }
        default {
            $now = Get-Hash ([string]$V.tep)
            if (-not $now) { return 'het' }
            if ($now -ne [string]$V.hash) { return 'giu' }
            return 'lam'
        }
    }
}

# ---------------------------------------------------------------- phát hiện, kết quả
function Add-Finding {
    # Một phát hiện theo chuẩn tramtool.ketqua/1; $Tiep 'cong-cu/action' là nút gợi ý chạy tiếp trong Trạm.
    param([string]$Ma, [string]$Muc, [string]$TieuDe, [string]$ChiTiet = '', [string]$CachSua = '', [string]$Tiep = '')
    $f = [ordered]@{ ma = $Ma; mucDo = $Muc; tieuDe = $TieuDe; chiTiet = $ChiTiet; cachSua = $CachSua }
    if ($Tiep -match '^([a-z0-9-]+)/([A-Za-z0-9_-]+)$') { $f['chayTiep'] = [ordered]@{ congCu = $Matches[1]; action = $Matches[2] } }
    [void]$script:Findings.Add($f)
    switch ($Muc) { 'loi' { Write-Bad $TieuDe } 'canh-bao' { Write-Warn $TieuDe } 'thong-tin' { Write-Info $TieuDe } default { Write-Ok $TieuDe } }
    if ($ChiTiet) { Write-Sub $ChiTiet }
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
        $Message = if ($nLoi + $nCanh) { 'Có {0} lỗi, {1} cảnh báo; xem gợi ý.' -f $nLoi, $nCanh } else { 'Không có gì cần làm.' }
    }
    $r = [ordered]@{
        chuan = 'tramtool.ketqua/1'; congCu = 'claude-dong-bo'; cheDo = $CheDo; phienBan = $script:Version
        may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
        batDau = $Start.ToString('s'); ketThuc = (Get-Date).ToString('s')
        maThoat = $Code; trangThai = @{ 0 = 'xong'; 1 = 'loi'; 2 = 'thieu-dieu-kien'; 3 = 'mot-phan' }[$Code]
        chayThu = [bool]$ChayThu; banClaude = $script:ClaudeVer
        ma = $(if ($nLoi + $nCanh) { 'CO_CANH_BAO' } else { 'KHONG_CO_CANH_BAO' })
        thongDiep = $Message
        tomTat = [ordered]@{ loi = $nLoi; canhBao = $nCanh; thongTin = $nTin }
        phatHien = $sorted
        tep = @($script:Files)
    }
    try {
        if (-not (Test-Path -LiteralPath $script:ResultDir)) { New-Item -ItemType Directory -Path $script:ResultDir -Force | Out-Null }
        $f = Join-Path $script:ResultDir ('KetQua_ClaudeDongBo_{0}_{1:yyyyMMdd_HHmmss}.json' -f $env:COMPUTERNAME, $Start)
        Write-TextAtomic $f ($r | ConvertTo-Json -Depth 8)
        Write-Info "Kết quả cho Trạm Tool: $f"
    } catch { Write-Warn "Không ghi được file kết quả: $($_.Exception.Message.Trim())" }
}

function Initialize-Claude {
    # Thư mục dữ liệu Claude Desktop, bản Claude, tài khoản đang đăng nhập. Trả 0 khi dùng được, 2 khi thiếu điều kiện.
    $script:ClaudeVer = ''
    $script:AppDir = Get-ClaudeAppDir
    if (-not $script:AppDir -or -not (Test-Path -LiteralPath $script:AppDir -PathType Container)) {
        Add-Finding 'CHUA_CAI_CLAUDE' 'loi' 'Không thấy dữ liệu Claude Desktop trên máy' '' 'Cài Claude Desktop (https://claude.ai/download), đăng nhập, mở tab Code một lần rồi chạy lại.'
        return 2
    }
    $script:SessRoot = Join-Path $script:AppDir 'claude-code-sessions'
    $script:ClaudeVer = Get-ClaudeVersion
    Update-Labels
    [void](Get-PackageStores '')   # lấy thêm email ghi trong các gói
    $script:DangGhi.Clear()
    $script:Cur = Get-CurrentAccount
    if (-not $script:Cur) {
        Add-Finding 'CHUA_DANG_NHAP' 'loi' 'Không biết Claude Desktop đang đăng nhập tài khoản nào' '' 'Mở Claude Desktop, đăng nhập rồi chạy lại.'
        return 2
    }
    if (-not $script:Cur.Org) {
        $hint = 'Mở tab Code bằng tài khoản này một lần (tạo một phiên bất kỳ), thoát Claude rồi chạy lại.'
        if ($script:ClaudeVer -and -not (Test-VersionSeen $script:ClaudeVer)) { $hint += (' Đã mở tab Code mà vẫn báo thế này thì có thể Claude {0} đã đổi nơi lưu danh sách phiên.' -f $script:ClaudeVer) }
        Add-Finding 'CHUA_MO_TAB_CODE' 'loi' ('{0} chưa có danh sách phiên tab Code trên máy này' -f (Get-Label $script:Cur.Acct)) '' $hint
        return 2
    }
    return 0
}

function Show-PlanItems {
    param($Items, [string]$Mark, [int]$Max = 40)
    $n = 0
    foreach ($x in $Items) {
        if ($n -ge $Max) { Write-Sub ('... và {0} phiên khác' -f ($Items.Count - $Max)); break }
        $s = $x.S
        Write-Plan ('{0} {1}  {2}{3}' -f $Mark, (Format-Time $s.Last), $s.Title, $(if ($s.Archived) { ' (đã lưu trữ)' } else { '' }))
        Write-Sub ('{0}; từ {1}' -f $s.Cwd, (Get-StoreLabel $s.Store))
        $n++
    }
}

function Show-LastSync {
    # Lần đồng bộ gần nhất vào tài khoản đang dùng: Claude đã mở, ghi lại bao nhiêu phiên; phiên nào biến mất mà không có
    # dấu đã xoá thì có thể bản Claude này không nhận mục chép sang.
    $j = Find-LastJournal $script:Cur.Acct
    if (-not $j) { return }
    $items = @($j.Data.viec | Where-Object { $_.loai -in 'them', 'thay' })
    if (-not $items.Count) { return }
    $same = 0; $used = 0; $del = 0; $lost = @()
    foreach ($v in $items) {
        $p = [string]$v.tep
        $h = Get-Hash $p
        if ($h -eq [string]$v.hash) { $same++; continue }
        if ($h) { $used++; continue }
        $u = [IO.Path]::GetFileNameWithoutExtension($p) -replace '^local_', ''
        $dd = Split-Path $p -Parent
        if ((Test-Path -LiteralPath (Join-Path $dd "deleted_$u")) -or (Test-Path -LiteralPath (Join-Path $dd "deleted_$u.json"))) { $del++ } else { $lost += [string]$v.tieuDe }
    }
    Add-Finding 'LAN_DONG_BO_GAN_NHAT' 'thong-tin' ('Lần đồng bộ lúc {0}: {1} phiên; Claude đã mở hoặc ghi lại {2}, chưa đụng tới {3}, đã xoá {4}' -f $j.Data.luc, $items.Count, $used, $same, $del) $j.Dir
    if ($lost.Count) {
        Add-Finding 'PHIEN_DONG_BO_MAT' 'canh-bao' ('{0} phiên đã đồng bộ không còn trong danh sách mà không có dấu đã xoá' -f $lost.Count) (@($lost | Select-Object -First 8) -join '; ') 'Có thể bản Claude này không nhận mục chép sang. Mở Claude, xem thanh bên rồi chạy Kiểm tra lại; vẫn mất thì báo để sửa công cụ.'
    }
}

# ---------------------------------------------------------------- chế độ
function Invoke-KiemTra {
    param([string]$From)
    Write-Head 'Tài khoản Claude trên máy'
    $plan = Get-SyncPlan $From
    $mine = @($plan.Mine)
    Add-Finding 'TAI_KHOAN_DANG_DUNG' 'ok' ('Đang đăng nhập {0}: {1} phiên ({2} đã lưu trữ)' -f (Get-Label $script:Cur.Acct), $mine.Count, @($mine | Where-Object { $_.Archived }).Count) $script:Cur.Dir
    if ($script:ClaudeVer -and -not (Test-VersionSeen $script:ClaudeVer)) {
        Add-Finding 'BAN_CLAUDE_MOI' 'thong-tin' ('Claude Desktop bản {0}; công cụ viết theo cách lưu của bản {1}' -f $script:ClaudeVer, ($script:DaXemTrenBan -join ', ')) 'Trước khi ghi, công cụ tự kiểm cấu trúc danh sách phiên; lạ thì dừng, không ghi gì.'
    }
    if ($plan.CauTrucLa) { Add-ShapeFinding $plan.KhongHopLe }
    elseif ($plan.KhongHopLe.Count) { Add-Finding 'MUC_KHONG_HOP_LE' 'canh-bao' ('{0} mục danh sách phiên không đúng cấu trúc nên bỏ qua' -f $plan.KhongHopLe.Count) (@($plan.KhongHopLe | Select-Object -First 5) -join '; ') }
    foreach ($src in $plan.Nguon) {
        $ss = @(Read-Sessions $src)
        $last = ($ss | Measure-Object -Property Last -Maximum).Maximum
        if ($src.Kind -eq 'goi') {
            Add-Finding 'GOI_SAO_LUU' 'thong-tin' ('Gói sao lưu {0}: {1} phiên, làm lúc {2} trên máy {3}' -f $src.Ten, $ss.Count, $src.Luc, $src.May) $src.Goc
        } else {
            Add-Finding 'TAI_KHOAN_KHAC' 'thong-tin' ('{0}: {1} phiên, lần cuối {2}' -f (Get-Label $src.Acct), $ss.Count, (Format-Time ([long]$last))) $src.Dir
        }
    }
    foreach ($d in @($script:DangGhi)) { Add-Finding 'GOI_CHUA_XONG' 'canh-bao' ('Gói {0} đang ghi dở (Sao lưu bị ngắt) nên bỏ qua' -f (Split-Path $d -Leaf)) $d 'Chạy lại Sao lưu ở máy đã tạo gói.' }
    if (-not $plan.Nguon.Count) {
        Add-Finding 'KHONG_CO_NGUON' 'thong-tin' 'Máy chưa có tài khoản Claude nào khác và chưa có gói sao lưu' '' 'Đăng nhập tài khoản cũ, chạy Sao lưu (hoặc chỉ cần đăng nhập rồi thoát), sau đó đăng nhập lại tài khoản này và chạy Đồng bộ.'
    }
    $n = $plan.Them.Count + $plan.Thay.Count
    $ex = Get-ExtraCount $plan.Extra
    if ($n) {
        Add-Finding 'THIEU_PHIEN' 'canh-bao' ('Tài khoản đang dùng chưa có {0} phiên, có bản mới hơn của {1} phiên' -f $plan.Them.Count, $plan.Thay.Count) (@($plan.Them + $plan.Thay | Select-Object -First 8 | ForEach-Object { $_.S.Title }) -join '; ') 'Thoát Claude Desktop rồi chạy Đồng bộ.' 'claude-dong-bo/dong-bo'
    }
    if ($ex) {
        Add-Finding 'THIEU_CAI_DAT' 'canh-bao' ('Có thể đồng bộ thêm {0} mục ngoài danh sách phiên' -f $ex) (Get-ExtraSummary $plan.Extra) 'Thoát Claude Desktop rồi chạy Đồng bộ.' 'claude-dong-bo/dong-bo'
    }
    if (-not $n -and -not $ex -and $plan.Nguon.Count) {
        Add-Finding 'DU_PHIEN' 'ok' 'Tài khoản đang dùng đã có đủ phiên của các tài khoản khác và các gói'
    }
    if ($plan.Extra.BoQua.Count) { Add-Finding 'HEN_GIO_THIEU_TEP' 'canh-bao' ('{0} tác vụ hẹn giờ thiếu file nhắc việc nên không thêm' -f $plan.Extra.BoQua.Count) (@($plan.Extra.BoQua) -join '; ') 'Chép file đó về đúng chỗ (hoặc Sao lưu lại ở máy cũ để gói mang theo) rồi Đồng bộ.' }
    if ($plan.Giu.Count) { Add-Finding 'GIU_BAN_DANG_CO' 'thong-tin' ('{0} phiên tài khoản này đã có, bản ở nơi khác khác bản đang có nhưng không thay' -f $plan.Giu.Count) }
    if ($plan.DaXoa.Count) { Add-Finding 'DA_XOA_O_DAY' 'thong-tin' ('{0} phiên đã xoá ở tài khoản này nên không thêm lại' -f $plan.DaXoa.Count) (@($plan.DaXoa | Select-Object -First 8 | ForEach-Object { $_.Title }) -join '; ') }
    if ($plan.ThieuNoiDung.Count) {
        Add-Finding 'PHIEN_THIEU_NOI_DUNG' 'canh-bao' ('{0} phiên không có nội dung hội thoại trên máy nên không đồng bộ được' -f $plan.ThieuNoiDung.Count) (@($plan.ThieuNoiDung | Select-Object -First 8 | ForEach-Object { $_.Title }) -join '; ') 'Nội dung nằm trong ~\.claude\projects; phiên làm ở máy khác thì sao lưu ở máy đó rồi đồng bộ từ gói.'
    }
    Show-LastSync
    if (@(Get-ClaudeDesktopProcess).Count) { Add-Finding 'CLAUDE_DANG_MO' 'thong-tin' 'Claude Desktop đang mở: Đồng bộ, Hoàn tác cần thoát Claude trước' }
    return 0
}

function Get-PackageDir {
    # Gói của tài khoản đang dùng trong $Root: Goi_<8 ký tự đầu mã tài khoản>, mỗi lần Sao lưu chỉ chép phần đổi.
    param([string]$Root)
    $p = Join-Path $Root ('Goi_{0}' -f $script:Cur.Acct.Substring(0, 8))
    $g = Read-Obj (Join-Path $p 'goi.json')
    if ($g -and $g.taiKhoan -and [string]$g.taiKhoan.acct -ne $script:Cur.Acct) { $p = Get-FreeName ('{0}_{1}' -f $p, $script:Cur.Acct.Substring(9, 4)) }
    return $p
}

function Add-Entry { param($E, [string]$Rel, [IO.FileInfo]$Info) $E[$Rel] = [pscustomobject]@{ Rel = $Rel; Info = $Info; Text = $null; Size = $Info.Length } }
function Add-TextEntry { param($E, [string]$Rel, [string]$Text) $E[$Rel] = [pscustomobject]@{ Rel = $Rel; Info = $null; Text = $Text; Size = [long][Text.Encoding]::UTF8.GetByteCount($Text) } }

function Add-DirEntries {
    param($E, [string]$Dir, [string]$Prefix, [string[]]$Skip = @())
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return }
    $base = (Get-Item -LiteralPath $Dir -Force).FullName.TrimEnd('\')
    foreach ($f in @(Get-ChildItem -LiteralPath $base -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($base.Length + 1)
        if ($Skip -contains $rel) { continue }
        Add-Entry $E "$Prefix\$rel" $f
    }
}

function Add-TaskFiles {
    # File nhắc việc của tác vụ hẹn giờ nằm trong thư mục người dùng (thường ~\.claude\scheduled-tasks\<tên>\SKILL.md, lấy
    # cả thư mục tác vụ). File ngoài thư mục người dùng (D:\...) thì máy khác có cùng đường dẫn, không mang theo.
    param($E, $Tasks)
    $st = Join-Path $script:UserDir '.claude\scheduled-tasks'
    foreach ($t in $Tasks) {
        $fp = [string]$t['filePath']
        if (-not $fp -or -not (Test-Path -LiteralPath $fp -PathType Leaf)) { continue }
        if (-not $fp.StartsWith($script:UserDir + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        $parent = Split-Path $fp -Parent
        if ((Split-Path $parent -Parent) -ieq $st) { Add-DirEntries $E $parent ('nguoi-dung\' + $parent.Substring($script:UserDir.Length + 1)) }
        else { Add-Entry $E ('nguoi-dung\' + $fp.Substring($script:UserDir.Length + 1)) (Get-Item -LiteralPath $fp -Force) }
    }
}

function Get-BackupEntries {
    # Các file của gói: danh sách phiên (phien\), nội dung hội thoại kèm thư mục tác tử con (noi-dung\), trí nhớ của các dự
    # án có phiên và file nhắc việc của tác vụ hẹn giờ (nguoi-dung\, theo đường dẫn trong thư mục người dùng), tác vụ hẹn
    # giờ, mẫu phiên, mục thanh bên của tài khoản (phien\), -KemCowork: thư mục Cowork của tài khoản (cowork\).
    param($Sessions, $Ix)
    $e = [ordered]@{}
    $miss = @(); $n = 0
    $slugs = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($s in $Sessions) {
        if (-not ($s.Cli -and $Ix.ContainsKey($s.Cli))) { $miss += $s; continue }
        $tx = $Ix[$s.Cli]; $slug = $tx.Directory.Name
        Add-Entry $e ('phien\' + (Split-Path $s.File -Leaf)) (Get-Item -LiteralPath $s.File -Force)
        Add-Entry $e "noi-dung\$slug\$($tx.Name)" $tx
        Add-DirEntries $e (Join-Path $tx.DirectoryName $s.Cli) "noi-dung\$slug\$($s.Cli)"
        [void]$slugs.Add($slug); $n++
    }
    foreach ($slug in $slugs) { Add-DirEntries $e (Join-Path $script:ProjectsDir "$slug\memory") "nguoi-dung\.claude\projects\$slug\memory" }
    $tf = Join-Path $script:Cur.Dir 'scheduled-tasks.json'
    $td = Read-JsonIf $tf
    if ($td -and @(Get-Arr $td['scheduledTasks']).Count) {
        Add-Entry $e 'phien\scheduled-tasks.json' (Get-Item -LiteralPath $tf -Force)
        Add-TaskFiles $e @(Get-Arr $td['scheduledTasks'])
    }
    $ser = Get-Serializer
    $all = Read-JsonIf (Join-Path $script:AppDir 'ccd-session-presets.json')
    if ($all -and (Test-Key $all['byAccount'] $script:Cur.Acct)) { Add-TextEntry $e 'phien\mau-phien.json' $ser.Serialize($all['byAccount'][$script:Cur.Acct]) }
    $cfg = Read-JsonIf (Join-Path $script:AppDir 'claude_desktop_config.json')
    if ($cfg) {
        $node = Get-KeyNode $cfg @('preferences', 'epitaxyPrefs', 'dframe-code-sections', ('{0}/{1}' -f $script:Cur.Acct, $script:Cur.Org))
        if ($node.Found -and $node.Value -is [System.Collections.IDictionary]) { Add-TextEntry $e 'phien\thanh-ben.json' $ser.Serialize($node.Value) }
    }
    if ($KemCowork) {
        Add-DirEntries $e (Join-Path $script:AppDir ('local-agent-mode-sessions\{0}\{1}' -f $script:Cur.Acct, $script:Cur.Org)) 'cowork' @('remote-session-spaces.json')
    }
    return [pscustomobject]@{ Entries = $e; Miss = $miss; So = $n }
}

function Get-MirrorDelta {
    # So gói đang có với các file cần có: chép file mới hoặc đổi (khác cỡ hay giờ sửa; file tạo ra thì so nội dung), bỏ
    # file không còn (phiên đã xoá ở tài khoản).
    param([string]$Dest, $Entries)
    $want = @{}
    $copy = New-Object System.Collections.ArrayList
    $same = 0; $bytes = [long]0
    foreach ($e in $Entries) {
        $want[$e.Rel] = $true
        $d = Join-Path $Dest $e.Rel
        if (Test-Path -LiteralPath $d -PathType Leaf) {
            if ($null -ne $e.Text) {
                if ([IO.File]::ReadAllText($d, [Text.Encoding]::UTF8) -ceq $e.Text) { $same++; continue }
            } else {
                $df = Get-Item -LiteralPath $d -Force
                if ($df.Length -eq $e.Info.Length -and $df.LastWriteTimeUtc -eq $e.Info.LastWriteTimeUtc) { $same++; continue }
            }
        }
        [void]$copy.Add($e); $bytes += $e.Size
    }
    $remove = @()
    if (Test-Path -LiteralPath $Dest -PathType Container) {
        $base = (Get-Item -LiteralPath $Dest -Force).FullName.TrimEnd('\')
        foreach ($f in @(Get-ChildItem -LiteralPath $base -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            $rel = $f.FullName.Substring($base.Length + 1)
            if ($rel -ine 'goi.json' -and -not $want.ContainsKey($rel)) { $remove += $f.FullName }
        }
    }
    return [pscustomobject]@{ Copy = $copy; Remove = $remove; Same = $same; Bytes = $bytes }
}

function Invoke-SaoLuu {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head $script:Modes['sao-luu'].Label
    $src = New-Store 'may' $script:Cur.Acct $script:Cur.Org $script:Cur.Dir
    $ss = @(Read-Sessions $src)
    $bad = @(Get-Invalid $src.Dir)
    if (Test-ShapeBad $bad.Count $ss.Count) { Add-ShapeFinding $bad; return 2 }
    if ($bad.Count) { Add-Finding 'MUC_KHONG_HOP_LE' 'canh-bao' ('{0} mục danh sách phiên không đúng cấu trúc nên không đưa vào gói' -f $bad.Count) (@($bad | Select-Object -First 5) -join '; ') }
    if (-not $ss.Count) { Add-Finding 'KHONG_CO_PHIEN' 'thong-tin' ('{0} chưa có phiên nào để sao lưu' -f (Get-Label $script:Cur.Acct)); return 0 }
    $b = Get-BackupEntries $ss (Get-TranscriptIndex $script:ProjectsDir)
    if ($b.Miss.Count) { Add-Finding 'PHIEN_THIEU_NOI_DUNG' 'canh-bao' ('{0} phiên không có nội dung hội thoại trên máy nên không đưa vào gói' -f $b.Miss.Count) (@($b.Miss | Select-Object -First 8 | ForEach-Object { $_.Title }) -join '; ') }
    if (-not $b.So) { return 0 }
    $zipOut = [bool]($Nen -or $MaHoa)
    $root = if ($Den) { $Den } else { $script:DataDir }
    $mirrorRoot = if ($zipOut) { $script:DataDir } else { $root }
    $pkg = Get-PackageDir $mirrorRoot
    $entries = @($b.Entries.Values)
    $delta = Get-MirrorDelta $pkg $entries
    $total = [long](($entries | Measure-Object -Property Size -Sum).Sum)
    Write-Line ('Tài khoản: {0}' -f (Get-Label $script:Cur.Acct))
    Write-Line ('{0} phiên có nội dung, gói khoảng {1}: {2}' -f $b.So, (Format-Size $total), $pkg)
    $hasPkg = Test-Path -LiteralPath (Join-Path $pkg 'goi.json') -PathType Leaf
    if ($hasPkg) { Write-Line ('Gói đã có: chép {0} file mới hoặc đổi ({1}), bỏ {2} file không còn, giữ {3} file' -f $delta.Copy.Count, (Format-Size $delta.Bytes), @($delta.Remove).Count, $delta.Same) }
    $outFile = ''
    if ($zipOut) {
        $outFile = Get-FreeName (Join-Path $root ('Goi_{0}_{1:yyyyMMdd_HHmmss}{2}' -f $script:Cur.Acct.Substring(0, 8), (Get-Date), $(if ($MaHoa) { '.aes' } else { '.zip' })))
        Write-Line ('{0} thành: {1}' -f $(if ($MaHoa) { 'Nén, mã hoá' } else { 'Nén' }), $outFile)
    }
    $free = Get-FreeBytes $mirrorRoot
    $need = $delta.Bytes + 50MB + $(if ($MaHoa) { $total } else { 0 })
    if ($free -ge 0 -and $free -lt $need) {
        Add-Finding 'THIEU_CHO_TRONG' 'loi' ('Ổ chứa {0} còn {1}, cần khoảng {2}' -f $mirrorRoot, (Format-Size $free), (Format-Size $need)) '' 'Chọn nơi lưu khác (USB, ổ khác) ở ô Lưu vào.'
        return 2
    }
    if ($zipOut) {
        $free2 = Get-FreeBytes $root
        if ($free2 -ge 0 -and $free2 -lt $total + 50MB) {
            Add-Finding 'THIEU_CHO_TRONG' 'loi' ('Ổ chứa {0} còn {1}, cần khoảng {2}' -f $root, (Format-Size $free2), (Format-Size ($total + 50MB))) '' 'Chọn nơi lưu khác (USB, ổ khác) ở ô Lưu vào.'
            return 2
        }
    }
    if ($DryRun) { Write-Info 'Chạy thử: chưa chép gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo 'Sao lưu bây giờ?' $true)) { return 2 }
    $pw = ''
    if ($MaHoa) {
        $pw = Read-MatKhau 'Đặt mật khẩu cho gói (ít nhất 8 ký tự)' -XacNhan
        if (-not $pw) { Add-Finding 'CHUA_CO_MAT_KHAU' 'loi' 'Chưa sao lưu: cần mật khẩu để mã hoá gói' '' 'Chạy trong cửa sổ có bàn phím, gõ mật khẩu hai lần giống nhau. Mật khẩu không nhận qua tham số.'; return 2 }
        if ($pw.Length -lt 8) { Add-Finding 'MAT_KHAU_NGAN' 'loi' 'Chưa sao lưu: mật khẩu ngắn hơn 8 ký tự'; return 2 }
    }

    # Gói đang có: đánh dấu đang ghi trước, Đồng bộ bỏ qua gói bị ngắt giữa chừng. Gói mới: goi.json ghi sau cùng.
    $gf = Join-Path $pkg 'goi.json'
    if ($hasPkg) { $g0 = Read-Dict $gf; if ($g0) { $g0['dangGhi'] = $true; Write-Dict $gf $g0 } }
    $fail = 0; $errs = @()
    foreach ($en in $delta.Copy) {
        try {
            $d = Join-Path $pkg $en.Rel
            $dd = Split-Path $d -Parent
            if (-not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
            if ($null -ne $en.Text) { Write-TextAtomic $d $en.Text } else { Copy-Item -LiteralPath $en.Info.FullName -Destination $d -Force }
        } catch { $fail++; $errs += ('{0}: {1}' -f $en.Rel, $_.Exception.Message.Trim()); Write-Bad "Không chép được $($errs[-1])" }
    }
    foreach ($f in @($delta.Remove)) { try { Remove-Item -LiteralPath $f -Force } catch { } }
    if (Test-Path -LiteralPath $pkg) { Remove-EmptyDirs $pkg }
    $cj = Read-Obj $script:ClaudeJson
    $email = if ($cj -and $cj.oauthAccount -and [string]$cj.oauthAccount.accountUuid -eq $script:Cur.Acct) { [string]$cj.oauthAccount.emailAddress } else { '' }
    Write-Obj $gf ([ordered]@{
            chuan = $script:GoiChuan; phienBan = $script:Version; luc = (Get-Date).ToString('s'); may = $env:COMPUTERNAME
            thuMucNguoiDung = $script:UserDir; taiKhoan = [ordered]@{ acct = $script:Cur.Acct; org = $script:Cur.Org; email = $email }
            soPhien = $b.So; banClaude = $script:ClaudeVer; coCowork = [bool]$KemCowork; dangGhi = $false
        })
    [void]$script:Files.Add([ordered]@{ nhan = 'Gói sao lưu phiên Claude'; duongDan = $pkg })
    if ($zipOut) {
        try {
            if ($MaHoa) {
                $tz = Join-Path $script:DataDir ('goi-tam-{0}.zip' -f [guid]::NewGuid().ToString('N'))
                try { New-PackageZip $pkg $tz; Protect-File $tz $outFile $pw } finally { if (Test-Path -LiteralPath $tz) { Remove-Item -LiteralPath $tz -Force } }
            } else { New-PackageZip $pkg $outFile }
            [void]$script:Files.Add([ordered]@{ nhan = $(if ($MaHoa) { 'Gói đã nén, mã hoá' } else { 'Gói đã nén' }); duongDan = $outFile })
        } catch { $fail++; $errs += ('nén gói: {0}' -f $_.Exception.Message.Trim()); Write-Bad "Không tạo được $outFile : $($errs[-1])" }
    }
    $pw = $null
    if ($fail) {
        Add-Finding 'SAO_LUU_MOT_PHAN' 'canh-bao' ('Sao lưu vào {0} có {1} file lỗi' -f $pkg, $fail) (@($errs | Select-Object -First 5) -join '; ')
        return 3
    }
    $where = if ($zipOut) { $outFile } else { $pkg }
    $what = if ($hasPkg) { 'cập nhật {0} file' -f $delta.Copy.Count } else { Format-Size $total }
    Add-Finding 'DA_SAO_LUU' 'ok' ('Đã sao lưu {0} phiên ({1}) vào {2}' -f $b.So, $what, $where) '' $(if ($MaHoa) { 'Mang file .aes sang máy kia, Đồng bộ chọn file đó ở ô Gói sao lưu và gõ mật khẩu.' } else { 'Đăng nhập tài khoản khác (máy này hoặc máy khác, chép gói sang), thoát Claude rồi chạy Đồng bộ.' })
    return 0
}

function Invoke-DongBo {
    param([string]$From, [switch]$DryRun, [switch]$Ask)
    Write-Head $script:Modes['dong-bo'].Label
    if ($From -and -not @(Get-PackageStores $From).Count) {
        Add-Finding 'KHONG_THAY_GOI' 'loi' ('Không thấy gói sao lưu trong {0}' -f $Tu) '' 'Chọn thư mục Goi_... (có goi.json) hoặc thư mục chứa nó, hay file .zip/.aes do Sao lưu tạo.'
        return 2
    }
    $plan = Get-SyncPlan $From
    $x = $plan.Extra
    Write-Line ('Vào tài khoản: {0} (đang có {1} phiên)' -f (Get-Label $script:Cur.Acct), $plan.Co)
    Write-Line ('Nguồn: {0}' -f $(if ($plan.Nguon.Count) { (@($plan.Nguon | ForEach-Object { Get-StoreLabel $_ }) -join '; ') } else { 'không có' }))
    if ($plan.CauTrucLa) { Add-ShapeFinding $plan.KhongHopLe; return 2 }
    if ($plan.KhongHopLe.Count) { Add-Finding 'MUC_KHONG_HOP_LE' 'canh-bao' ('{0} mục danh sách phiên không đúng cấu trúc nên bỏ qua' -f $plan.KhongHopLe.Count) (@($plan.KhongHopLe | Select-Object -First 5) -join '; ') }
    if ($plan.DaXoa.Count) { Add-Finding 'DA_XOA_O_DAY' 'thong-tin' ('{0} phiên đã xoá ở tài khoản này nên không thêm lại' -f $plan.DaXoa.Count) (@($plan.DaXoa | Select-Object -First 8 | ForEach-Object { $_.Title }) -join '; ') }
    if ($plan.ThieuNoiDung.Count) { Add-Finding 'PHIEN_THIEU_NOI_DUNG' 'canh-bao' ('{0} phiên không có nội dung hội thoại trên máy nên không đồng bộ được' -f $plan.ThieuNoiDung.Count) (@($plan.ThieuNoiDung | Select-Object -First 8 | ForEach-Object { $_.Title }) -join '; ') 'Phiên làm ở máy khác: sao lưu ở máy đó rồi đồng bộ từ gói.' }
    if ($plan.Giu.Count) { Add-Finding 'GIU_BAN_DANG_CO' 'thong-tin' ('{0} phiên tài khoản này đã có, giữ bản đang có' -f $plan.Giu.Count) }
    if ($x.BoQua.Count) { Add-Finding 'HEN_GIO_THIEU_TEP' 'canh-bao' ('{0} tác vụ hẹn giờ thiếu file nhắc việc nên không thêm' -f $x.BoQua.Count) (@($x.BoQua) -join '; ') 'Chép file đó về đúng chỗ (hoặc Sao lưu lại ở máy cũ để gói mang theo) rồi Đồng bộ.' }
    $work = @($plan.Them) + @($plan.Thay)
    $nx = Get-ExtraCount $x
    if (-not $work.Count -and -not $nx) {
        Add-Finding 'KHONG_CAN_DONG_BO' 'ok' $(if ($plan.Nguon.Count) { 'Tài khoản đang dùng đã có đủ phiên, không cần đồng bộ' } else { 'Máy chưa có tài khoản Claude nào khác và chưa có gói sao lưu' })
        return 0
    }
    Show-PlanItems @($plan.Them) '[+]'
    Show-PlanItems @($plan.Thay) '[~]'
    Show-ExtraItems $x
    $copy = [long](($work | ForEach-Object { $_.Tx.Size } | Measure-Object -Sum).Sum) + $x.Size
    if ($copy) {
        Write-Line ('Chép thêm nội dung từ gói, Cowork: {0}' -f (Format-Size $copy))
        $free = Get-FreeBytes $script:UserDir
        if ($free -ge 0 -and $free -lt $copy + 50MB) {
            Add-Finding 'THIEU_CHO_TRONG' 'loi' ('Ổ chứa {0} còn {1}, cần khoảng {2}' -f $script:UserDir, (Format-Size $free), (Format-Size ($copy + 50MB)))
            return 2
        }
    }
    $bypassOk = Test-BypassAllowed $script:Cur.Acct
    if (-not $bypassOk -and @($work | Where-Object { [string]$_.S.Data['permissionMode'] -eq 'bypassPermissions' }).Count) {
        Write-Info 'Tài khoản này chưa bật chế độ không hỏi quyền: các phiên đang ở chế độ đó sẽ mở lại ở chế độ hỏi trước.'
    }
    if ($DryRun) { Write-Info 'Chạy thử: chưa ghi gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo ('Thêm {0}, thay {1} phiên, {2} mục khác vào tài khoản này?' -f $plan.Them.Count, $plan.Thay.Count, $nx) $true)) { return 2 }
    if (-not (Confirm-DesktopClosed)) {
        Add-Finding 'CLAUDE_DANG_MO' 'loi' 'Chưa đồng bộ vì Claude Desktop đang mở' '' 'Thoát hẳn Claude (chuột phải biểu tượng ở khay đồng hồ, Quit) rồi chạy lại, hoặc đánh dấu Tự đóng Claude.'
        return 2
    }

    # Nhật ký để Hoàn tác: mỗi việc ghi file đích và mã băm sau khi ghi; bản bị thay cất trong thư mục nhật ký.
    $jd = Get-FreeName (Join-Path $script:UndoDir ('DongBo_{0:yyyyMMdd_HHmmss}' -f (Get-Date)))
    New-Item -ItemType Directory -Path $jd -Force | Out-Null
    $viec = New-Object System.Collections.ArrayList
    $journal = [ordered]@{ chuan = $script:NhatKyChuan; luc = (Get-Date).ToString('s'); may = $env:COMPUTERNAME; taiKhoan = $script:Cur.Acct; thuMuc = $script:Cur.Dir; banClaude = $script:ClaudeVer; viec = $viec }
    $ok = 0; $okX = 0; $fail = 0; $k = 0; $errs = @()
    $memo = New-Object System.Collections.ArrayList
    try {
        # File người dùng trước (tác vụ hẹn giờ cần file nhắc việc), rồi phiên, rồi các cài đặt của tài khoản.
        foreach ($t in $x.Tep) {
            $k++
            try {
                $v = Save-JournaledFile $jd "$k" $t.Dest $t.Nhan -Src $t.Src -Text $t.Text
                $v['nho'] = @($t.Memo); [void]$viec.Add($v); foreach ($m in $t.Memo) { [void]$memo.Add($m) }; $okX++
            } catch { $fail++; $errs += ('{0}: {1}' -f $t.Nhan, $_.Exception.Message.Trim()); Write-Bad "Không chép được $($errs[-1])" }
        }
        foreach ($it in $work) {
            $k++
            $s = $it.S
            try {
                # Nội dung trước, mục danh sách sau: mục mới không bao giờ trỏ vào nội dung chưa có.
                if ($it.Tx.Copy) {
                    $v = [ordered]@{ loai = 'them-noi-dung'; tep = $it.Tx.Dest; banCu = ''; hash = ''; thuMuc = '' }
                    if (Test-Path -LiteralPath $it.Tx.Dest -PathType Leaf) {
                        $v.loai = 'thay-noi-dung'; $v.banCu = "noi-dung\$k.jsonl"
                        New-Item -ItemType Directory -Path (Join-Path $jd 'noi-dung') -Force | Out-Null
                        Copy-Item -LiteralPath $it.Tx.Dest -Destination (Join-Path $jd $v.banCu) -Force
                    }
                    $dd = Split-Path $it.Tx.Dest -Parent
                    if (-not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
                    Copy-Item -LiteralPath $it.Tx.Src -Destination $it.Tx.Dest -Force
                    $v.hash = Get-Hash $it.Tx.Dest
                    if ((Test-Path -LiteralPath $it.Tx.Side -PathType Container) -and -not (Test-Path -LiteralPath $it.Tx.SideDest)) {
                        Copy-Item -LiteralPath $it.Tx.Side -Destination $it.Tx.SideDest -Recurse -Force
                        $v.thuMuc = $it.Tx.SideDest
                    }
                    [void]$viec.Add($v)
                }
                $dest = Join-Path $script:Cur.Dir "$($s.Id).json"
                $v = [ordered]@{ loai = 'them'; tep = $dest; banCu = ''; hash = ''; tieuDe = $s.Title }
                if (Test-Path -LiteralPath $dest -PathType Leaf) {
                    $v.loai = 'thay'; $v.banCu = "phien\$($s.Id).json"
                    New-Item -ItemType Directory -Path (Join-Path $jd 'phien') -Force | Out-Null
                    Copy-Item -LiteralPath $dest -Destination (Join-Path $jd $v.banCu) -Force
                }
                Write-Dict $dest (Convert-ForTarget $s.Data $bypassOk $s.Store.UserDir $script:UserDir)
                $v.hash = Get-Hash $dest
                [void]$viec.Add($v)
                $ok++
            } catch { $fail++; $errs += ('{0}: {1}' -f $s.Title, $_.Exception.Message.Trim()); Write-Bad "Không đồng bộ được $($errs[-1])" }
        }
        foreach ($j in $x.Json) {
            $k++
            try {
                $v = Save-JournaledFile $jd "$k" $j.Dest $j.Nhan -Dict $j.Dict
                $v['nho'] = @($j.Memo); [void]$viec.Add($v); foreach ($m in $j.Memo) { [void]$memo.Add($m) }; $okX++
            } catch { $fail++; $errs += ('{0}: {1}' -f $j.Nhan, $_.Exception.Message.Trim()); Write-Bad "Không ghi được $($errs[-1])" }
        }
        foreach ($c in $x.Khoa) {
            try {
                $v = Save-JournaledKey $c.Dest $c.Path $c.Value $c.Nhan
                $v['nho'] = @($c.Memo); [void]$viec.Add($v); foreach ($m in $c.Memo) { [void]$memo.Add($m) }; $okX++
            } catch { $fail++; $errs += ('{0}: {1}' -f $c.Nhan, $_.Exception.Message.Trim()); Write-Bad "Không ghi được $($errs[-1])" }
        }
        foreach ($c in $x.Cowork) {
            $k++
            try {
                if ($c.Dir) {
                    $dd = Split-Path $c.Dest -Parent
                    if (-not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
                    Copy-Item -LiteralPath $c.Src -Destination $c.Dest -Recurse -Force
                    $v = [ordered]@{ loai = 'them-thu-muc'; tep = $c.Dest; ky = (Get-DirSig $c.Dest); tieuDe = $c.Nhan }
                } else { $v = Save-JournaledFile $jd "$k" $c.Dest $c.Nhan -Src $c.Src }
                $v['nho'] = @($c.Memo); [void]$viec.Add($v); foreach ($m in $c.Memo) { [void]$memo.Add($m) }; $okX++
            } catch { $fail++; $errs += ('{0}: {1}' -f $c.Nhan, $_.Exception.Message.Trim()); Write-Bad "Không chép được $($errs[-1])" }
        }
    } finally {
        $journal['xong'] = (Get-Date).ToString('s')
        Write-Obj (Join-Path $jd 'nhat-ky.json') $journal
        try { Update-Memo $memo } catch { Write-Warn "Không ghi được $script:MemoFile : $($_.Exception.Message.Trim())" }
    }
    [void]$script:Files.Add([ordered]@{ nhan = 'Nhật ký để hoàn tác'; duongDan = (Join-Path $jd 'nhat-ky.json') })
    if ($ok -or $okX) {
        $more = if ($okX) { ', {0} mục khác (trí nhớ, tác vụ hẹn giờ, mẫu phiên, thanh bên, Cowork)' -f $okX } else { '' }
        Add-Finding 'DA_DONG_BO' 'ok' ('Đã thêm {0}, thay {1} phiên{2} vào {3}' -f @($viec | Where-Object { $_.loai -eq 'them' }).Count, @($viec | Where-Object { $_.loai -eq 'thay' }).Count, $more, (Get-Label $script:Cur.Acct)) '' 'Mở lại Claude Desktop, các phiên hiện ở thanh bên tab Code. Phiên có thư mục dự án chưa có trên máy thì chép thư mục đó về đúng chỗ trước khi mở.'
    }
    if ($fail) {
        Add-Finding 'DONG_BO_LOI' 'loi' ('{0} mục không đồng bộ được' -f $fail) (@($errs | Select-Object -First 5) -join '; ')
        if ($ok -or $okX) { return 3 } else { return 1 }
    }
    return 0
}

function Invoke-HoanTac {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head $script:Modes['hoan-tac'].Label
    $lj = Find-LastJournal
    if (-not $lj) { Add-Finding 'KHONG_CO_GI_DE_HOAN_TAC' 'thong-tin' 'Không có lần đồng bộ nào chưa hoàn tác'; return 0 }
    $j = $lj.Data; $jf = $lj.File; $jd = $lj.Dir
    $viec = @($j.viec)
    [array]::Reverse($viec)
    Write-Line ('Lần đồng bộ lúc {0} vào {1}: {2} việc' -f $j.luc, (Get-Label ([string]$j.taiKhoan)), $viec.Count)
    $todo = @(); $keep = @()
    foreach ($v in $viec) {
        switch (Get-UndoState $v) { 'lam' { $todo += $v } 'giu' { $keep += $v } }
    }
    foreach ($v in $todo) { Write-Plan ('{0} {1}' -f $(if ($v.loai -like 'them*') { 'Bỏ' } else { 'Trả lại bản cũ' }), $(if ($v.tieuDe) { $v.tieuDe } else { $v.tep })) }
    if ($keep.Count) {
        Add-Finding 'GIU_VI_DA_DOI' 'canh-bao' ('Giữ {0} mục vì đã dùng tiếp sau khi đồng bộ' -f $keep.Count) (@($keep | ForEach-Object { if ($_.tieuDe) { $_.tieuDe } else { $_.tep } }) -join '; ')
    }
    if ($DryRun) { Write-Info 'Chạy thử: chưa đổi gì.'; return 0 }
    if ($todo.Count) {
        if ($Ask -and -not (Read-YesNo 'Hoàn tác bây giờ?' $true)) { return 2 }
        if (-not (Confirm-DesktopClosed)) {
            Add-Finding 'CLAUDE_DANG_MO' 'loi' 'Chưa hoàn tác vì Claude Desktop đang mở' '' 'Thoát hẳn Claude rồi chạy lại, hoặc đánh dấu Tự đóng Claude.'
            return 2
        }
    }
    $fail = 0; $errs = @(); $forget = @()
    foreach ($v in $todo) {
        try {
            $p = [string]$v.tep
            # switch -Wildcard chạy mọi nhánh khớp ('them-thu-muc' khớp cả 'them*'): mỗi nhánh dừng bằng break.
            switch -Wildcard ([string]$v.loai) {
                'them-thu-muc' { Remove-Item -LiteralPath $p -Recurse -Force; break }
                'doi-khoa' {
                    $c = Read-Dict $p
                    if ($v.coCu) { Set-KeyValue $c @($v.khoa) ((Get-Serializer).DeserializeObject([string]$v.cu)) } else { Set-KeyValue $c @($v.khoa) $null -Remove }
                    Write-Dict $p $c
                    break
                }
                'them*' {
                    Remove-Item -LiteralPath $p -Force
                    if ($v.thuMuc -and (Test-Path -LiteralPath ([string]$v.thuMuc))) { Remove-Item -LiteralPath ([string]$v.thuMuc) -Recurse -Force }
                    break
                }
                default { Copy-Item -LiteralPath (Join-Path $jd ([string]$v.banCu)) -Destination $p -Force }
            }
            $forget += @($v.nho | Where-Object { $_ })
        } catch { $fail++; $errs += ('{0}: {1}' -f $v.tep, $_.Exception.Message.Trim()); Write-Bad "Không hoàn tác được $($errs[-1])" }
    }
    try { Update-Memo $forget -Bo } catch { Write-Warn "Không ghi được $script:MemoFile" }
    $o = [IO.File]::ReadAllText($jf, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $o | Add-Member -NotePropertyName hoanTacLuc -NotePropertyValue (Get-Date).ToString('s') -Force
    Write-Obj $jf $o
    if ($fail) { Add-Finding 'HOAN_TAC_LOI' 'loi' ('{0} mục không hoàn tác được' -f $fail) (@($errs | Select-Object -First 5) -join '; '); return 3 }
    Add-Finding 'DA_HOAN_TAC' 'ok' ('Đã hoàn tác {0} mục của lần đồng bộ lúc {1}' -f $todo.Count, $j.luc) '' 'Mở lại Claude Desktop.'
    if ($keep.Count) { return 3 }
    return 0
}

function Invoke-MoClaude {
    # Cho lối tắt "Mở Claude": Claude đang tắt thì đồng bộ (không hỏi) rồi mở; đang mở thì không đồng bộ được (Claude
    # giữ danh sách trong bộ nhớ), chỉ đưa cửa sổ lên. Thiếu điều kiện đồng bộ vẫn mở Claude.
    param([string]$From, [switch]$DryRun)
    $code = 0
    if (@(Get-ClaudeDesktopProcess).Count) {
        Write-Head $script:Modes['mo-claude'].Label
        Add-Finding 'CLAUDE_DANG_MO' 'thong-tin' 'Claude Desktop đang mở nên chưa đồng bộ, chỉ đưa cửa sổ Claude lên' '' 'Muốn đồng bộ: thoát hẳn Claude (Quit ở khay đồng hồ) rồi bấm lối tắt lại.'
    } else {
        $code = Invoke-DongBo -From $From -DryRun:$DryRun
    }
    if ($DryRun) { Write-Info 'Chạy thử: không mở Claude.'; return $code }
    if (Start-ClaudeDesktop) { Write-Ok 'Đã mở Claude Desktop.' }
    else {
        Add-Finding 'KHONG_MO_DUOC_CLAUDE' 'loi' 'Không tìm thấy Claude Desktop để mở' '' 'Mở Claude từ menu Start; chưa cài thì tải ở https://claude.ai/download.'
        if ($code -eq 0) { $code = 1 }
    }
    return $code
}

function Initialize-ShellLink {
    # Lối tắt .lnk qua IShellLinkW: WScript.Shell đổi ký tự có dấu trong tên file thành '?' rồi không lưu được.
    if ('CdbLoiTat.Lnk' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices; using System.Runtime.InteropServices.ComTypes;
namespace CdbLoiTat {
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
        public static void Save(string path, string target, string args, string dir, string desc, string icon, int iconIndex) {
            IShellLinkW l = (IShellLinkW)new ShellLink();
            l.SetPath(target); l.SetArguments(args); l.SetWorkingDirectory(dir); l.SetDescription(desc); l.SetIconLocation(icon, iconIndex);
            ((IPersistFile)l).Save(path, true);
        }
        // Đọc lại: đích, tham số, biểu tượng (đường dẫn,số), mô tả.
        public static string[] Read(string path) {
            IShellLinkW l = (IShellLinkW)new ShellLink();
            ((IPersistFile)l).Load(path, 0);
            StringBuilder a = new StringBuilder(2048), b = new StringBuilder(8192), c = new StringBuilder(2048), d = new StringBuilder(2048); int i;
            l.GetPath(a, a.Capacity, IntPtr.Zero, 0); l.GetArguments(b, b.Capacity); l.GetIconLocation(c, c.Capacity, out i); l.GetDescription(d, d.Capacity);
            return new string[] { a.ToString(), b.ToString(), c.ToString() + "," + i, d.ToString() };
        }
    }
}
'@
}

function Invoke-LoiTat {
    param([switch]$DryRun)
    Write-Head $script:Modes['loi-tat'].Label
    $desk = if ($env:CDB_DESKTOP) { $env:CDB_DESKTOP } else { [Environment]::GetFolderPath('Desktop') }
    if (-not $desk -or -not (Test-Path -LiteralPath $desk -PathType Container)) { Add-Finding 'KHONG_THAY_MAN_HINH' 'loi' 'Không thấy thư mục màn hình (Desktop) của tài khoản Windows này'; return 2 }
    $lnk = Join-Path $desk $script:LinkName
    $ps = Join-Path $PSHOME 'powershell.exe'
    $arg = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode mo-claude' -f $script:SelfPath
    Write-Line ('Lối tắt: {0}{1}' -f $lnk, $(if (Test-Path -LiteralPath $lnk) { ' (đã có, ghi đè)' } else { '' }))
    Write-Sub ('Chạy: powershell.exe {0}' -f $arg)
    if ($DryRun) { Write-Info 'Chạy thử: chưa tạo lối tắt.'; return 0 }
    $ico = Save-ClaudeIcon
    Initialize-ShellLink
    [CdbLoiTat.Lnk]::Save($lnk, $ps, $arg, (Split-Path $script:SelfPath -Parent), 'Đồng bộ phiên tab Code sang tài khoản đang đăng nhập rồi mở Claude Desktop', $(if ($ico) { $ico } else { $ps }), 0)
    [void]$script:Files.Add([ordered]@{ nhan = 'Lối tắt Mở Claude'; duongDan = $lnk })
    Add-Finding 'DA_TAO_LOI_TAT' 'ok' ('Đã tạo lối tắt "{0}" trên màn hình' -f [IO.Path]::GetFileNameWithoutExtension($lnk)) $lnk 'Từ nay mở Claude bằng lối tắt này: Claude đang tắt thì phiên được đồng bộ trước rồi mới mở. Chuyển thư mục Trạm Tool đi nơi khác thì tạo lại lối tắt.'
    return 0
}

function Invoke-Mode {
    # Chạy một chế độ và ghi file kết quả. Trả mã thoát.
    param([string]$Id, [switch]$Ask)
    $start = Get-Date
    $script:Findings.Clear(); $script:Files.Clear(); $script:Invalid = @{}; $script:DangGhi.Clear()
    $code = 0; $msg = ''
    try {
        if ($Id -eq 'loi-tat') { $code = Invoke-LoiTat -DryRun:$ChayThu }
        else {
            $code = Initialize-Claude
            $from = ''
            if ($code -eq 0 -and $Id -in 'kiem-tra', 'dong-bo', 'mo-claude') {
                $from = Resolve-From $Tu
                if ($null -eq $from) { $code = 2 }
            }
            if ($code -eq 0) {
                switch ($Id) {
                    'kiem-tra' { $code = Invoke-KiemTra $from }
                    'sao-luu' { $code = Invoke-SaoLuu -DryRun:$ChayThu -Ask:$Ask }
                    'dong-bo' {
                        $code = Invoke-DongBo -From $from -DryRun:$ChayThu -Ask:$Ask
                        if ($MoClaude -and -not $ChayThu -and $code -in 0, 3) { if (Start-ClaudeDesktop) { Write-Ok 'Đã mở Claude Desktop.' } }
                    }
                    'hoan-tac' { $code = Invoke-HoanTac -DryRun:$ChayThu -Ask:$Ask }
                    'mo-claude' { $code = Invoke-MoClaude -From $from -DryRun:$ChayThu }
                }
            } elseif ($Id -eq 'mo-claude' -and -not $ChayThu) {
                # Lối tắt là để mở Claude: chưa đăng nhập, chưa mở tab Code... vẫn mở Claude.
                [void](Start-ClaudeDesktop)
            }
        }
    } catch {
        Write-Bad ('Lỗi không lường trước: {0}' -f $_.Exception.Message.Trim())
        $code = 1
    } finally { Remove-TempDirs }
    if ($Id -ne 'kiem-tra') {
        $msg = switch ($code) {
            0 { if ($ChayThu) { 'Chạy thử: chỉ xem việc sẽ làm, chưa ghi gì.' } else { '{0}: xong.' -f $script:Modes[$Id].Label } }
            2 { 'Chưa làm: thiếu điều kiện hoặc đã huỷ, xem chi tiết.' }
            3 { '{0}: làm được một phần.' -f $script:Modes[$Id].Label }
            default { '{0}: lỗi, xem cửa sổ công cụ.' -f $script:Modes[$Id].Label }
        }
    }
    Save-RunResult -CheDo $Id -Code $code -Start $start -Message $msg
    return $code
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '  ĐỒNG BỘ PHIÊN CLAUDE' -ForegroundColor Cyan
        Write-Host '  Đưa các phiên tab Code của tài khoản Claude khác sang tài khoản đang đăng nhập.' -ForegroundColor Gray
        Write-Host ''
        Write-Host '   1. Kiểm tra (chỉ đọc)'
        Write-Host '   2. Sao lưu phiên của tài khoản đang đăng nhập (để mang sang máy khác)'
        Write-Host '   3. Đồng bộ phiên vào tài khoản đang đăng nhập'
        Write-Host '   4. Hoàn tác lần đồng bộ gần nhất'
        Write-Host '   5. Mở Claude (đồng bộ trước)'
        Write-Host '   6. Tạo lối tắt Mở Claude trên màn hình'
        Write-Host '   0. Thoát'
        Write-Host ''
        $c = Read-Text 'Chọn số' '0'
        switch ($c) {
            '0' { return 0 }
            '1' { [void](Invoke-Mode 'kiem-tra' -Ask) }
            '2' {
                $old = $script:MaHoa
                if (-not $MaHoa) { $script:MaHoa = [switch](Read-YesNo 'Mã hoá gói bằng mật khẩu (nên làm khi mang qua USB)?' $false) }
                [void](Invoke-Mode 'sao-luu' -Ask)
                $script:MaHoa = $old
            }
            '3' { [void](Invoke-Mode 'dong-bo' -Ask) }
            '4' { [void](Invoke-Mode 'hoan-tac' -Ask) }
            '5' { [void](Invoke-Mode 'mo-claude') }
            '6' { [void](Invoke-Mode 'loi-tat') }
            default { continue }
        }
        Wait-Close 'Bấm Enter để về menu'
    }
}

# ---------------------------------------------------------------- bắt đầu
if ($env:TRAMTOOL_CLAUDEDONGBO_TEST) { return }   # bài thử nạp các hàm rồi tự gọi
try { $Host.UI.RawUI.WindowTitle = 'Đồng bộ phiên Claude' } catch { }
if ($Mode -and -not $script:Modes.Contains($Mode)) {
    Write-Bad ('Không có chế độ "{0}". Các chế độ: {1}.' -f $Mode, (@($script:Modes.Keys) -join ', '))
    Wait-Close
    exit 1
}
if (-not $Mode) {
    if ([Console]::IsInputRedirected) { Write-Host 'Cách dùng: DongBoClaude.ps1 -Mode kiem-tra|sao-luu|dong-bo|hoan-tac|mo-claude|loi-tat [-Tu <gói>] [-Den <thư mục>] [-Nen] [-MaHoa] [-KemCowork] [-DongClaude] [-MoClaude] [-ChayThu] [-KhongDung]'; exit 1 }
    exit (Show-Menu)
}
$code = Invoke-Mode $Mode
# Lối tắt Mở Claude: xong êm thì đóng cửa sổ ngay, có lỗi, cảnh báo thì để người dùng đọc.
if ($Mode -ne 'mo-claude' -or $code -ne 0) { Wait-Close }
exit $code
