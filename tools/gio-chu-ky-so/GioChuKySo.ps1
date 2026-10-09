<#
  Giờ máy và chữ ký số (USB token). Sai giờ hoặc sai múi giờ làm hỏng ký số thuế điện tử, hoá đơn điện tử, BHXH,
  HTTPS và kích hoạt; dịch vụ Smart Card bị "phần mềm tối ưu" tắt thì Windows không thấy USB token.

  Chế độ (-Mode):
    kiem-tra   chỉ đọc, không cần Admin: đo độ lệch giờ với máy chủ giờ (NTP, không được thì giờ trong tiêu đề HTTP),
               múi giờ, dịch vụ Windows Time và kiểu đồng bộ; dịch vụ Smart Card, Certificate Propagation, đầu đọc
               token Windows thấy, driver token lỗi, chứng thư ký số (hết hạn, sắp hết hạn, chưa tới ngày hiệu lực,
               thiếu chứng thư gốc), phần mềm ký số đã cài. Không hỏi PIN, không đọc khoá riêng.
    sua-gio    cần Admin: bật dịch vụ Windows Time, bật đồng bộ giờ tự động nếu đang tắt (time.windows.com), đặt múi
               giờ Việt Nam (-MuiGioVN), đồng bộ ngay; vẫn lệch thì đặt giờ theo máy chủ giờ vừa đo. Máy trong domain
               chỉ đồng bộ lại, không đổi cấu hình.
    sua-token  cần Admin: dịch vụ Smart Card, Certificate Propagation đang tắt thì đặt Thủ công (mặc định của Windows)
               và chạy; chạy lại Certificate Propagation để chứng thư trong token hiện lại.
    hoan-tac   cần Admin: trả kiểu khởi động dịch vụ, cấu hình đồng bộ giờ, múi giờ như trước lần sửa đầu tiên.
  Không có -Mode: menu (bấm đúp GIO_VA_CHU_KY_SO.bat); việc cần Admin mở cửa sổ Admin riêng (UAC).
  Trước khi đổi, giá trị cũ được lưu vào ket_qua\TrangThaiGoc_GioChuKySo_<máy>.json (giữ giá trị của lần sửa đầu).
  Mỗi lần chạy ghi ket_qua\KetQua_GioChuKySo_<máy>_<giờ>.json (chuẩn tramtool.ketqua/1) cho Trạm Tool.
  -ChayThu: chỉ in việc sẽ làm. -KhongDung: không chờ Enter khi xong.
  Mã thoát: 0 xong (kể cả khi Kiểm tra có cảnh báo), 1 lỗi, 2 thiếu điều kiện (quyền Admin, đã huỷ), 3 làm được một phần.
#>
param(
    [string]$Mode = '',
    [switch]$MuiGioVN,
    [switch]$ChayThu,
    [switch]$KhongDung,
    [switch]$DaNangQuyen   # đánh dấu cửa sổ đã mở lại bằng quyền Admin, để không hỏi UAC lần nữa
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:Version = '1.0'
$script:ResultDir = if ($env:GCK_KET_QUA) { $env:GCK_KET_QUA } else { Join-Path $PSScriptRoot 'ket_qua' }
$script:StateFile = Join-Path $script:ResultDir ("TrangThaiGoc_GioChuKySo_{0}.json" -f $env:COMPUTERNAME)
$script:ServicesKey = 'HKLM:\SYSTEM\CurrentControlSet\Services'
$script:W32Key = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'
$script:VnZone = 'SE Asia Standard Time'
$script:NtpServers = @('time.windows.com', 'time.google.com', 'pool.ntp.org')
$script:HttpTimeUrls = @('http://www.msftconnecttest.com/connecttest.txt', 'http://www.google.com/generate_204')
$script:PeerList = 'time.windows.com,0x9'
$script:LechCanhBao = 30     # giây: lệch hơn thì cảnh báo
$script:LechLoi = 120        # giây: lệch hơn thì là lỗi (ký số, đăng nhập, HTTPS dễ hỏng)
$script:LechDatGio = 60      # giây: đồng bộ xong vẫn lệch hơn thì đặt giờ theo máy chủ giờ
$script:SapHetHanNgay = 30
$script:TokenServices = [ordered]@{
    SCardSvr    = @{ Label = 'Smart Card (đọc USB token, thẻ thông minh)'; Code = 'DICH_VU_SMART_CARD_TAT'; Muc = 'loi' }
    CertPropSvc = @{ Label = 'Certificate Propagation (đưa chứng thư trong token vào Windows)'; Code = 'DICH_VU_CERTPROP_TAT'; Muc = 'canh-bao' }
}
# Tên phần mềm ký số, phần mềm của nhà cung cấp chứng thư số Việt Nam (đọc tên trong danh sách phần mềm đã cài).
$script:SigningAppPattern = '(?i)esigner|vnpt[- ]?ca|viettel[- ]?ca|fpt[- ]?ca|bkav[- ]?ca|\bca2\b|newtel[- ]?ca|efy[- ]?ca|misa[^|]*esign|itaxviewer|\bhtkk\b|token ?manager|epass|safenet authentication|bit4id|nacencomm|vina[- ]?ca|trust[- ]?ca|easy[- ]?ca|fast[- ]?ca|safe[- ]?ca|smartsign|ky so|ký số'
$script:Modes = [ordered]@{
    'kiem-tra'  = @{ No = 1; Label = 'Kiểm tra giờ máy và chữ ký số (chỉ đọc)'; Admin = $false }
    'sua-gio'   = @{ No = 2; Label = 'Sửa giờ máy: đồng bộ giờ, múi giờ Việt Nam'; Admin = $true }
    'sua-token' = @{ No = 3; Label = 'Sửa dịch vụ đọc USB token'; Admin = $true }
    'hoan-tac'  = @{ No = 4; Label = 'Trả lại như trước khi sửa'; Admin = $true }
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

function Format-Lech {
    # Độ lệch (giây, dương = máy chậm hơn máy chủ giờ) thành chữ.
    param([double]$Seconds)
    $a = [Math]::Abs($Seconds)
    $huong = if ($Seconds -gt 0) { 'chậm' } else { 'nhanh' }
    if ($a -lt 1) { return 'lệch dưới 1 giây' }
    if ($a -lt 120) { return ('{0} {1:0.#} giây' -f $huong, $a) }
    if ($a -lt 7200) { return ('{0} {1:0} phút' -f $huong, ($a / 60)) }
    if ($a -lt 172800) { return ('{0} {1:0.#} giờ' -f $huong, ($a / 3600)) }
    return ('{0} {1:0} ngày' -f $huong, ($a / 86400))
}

# ---------------------------------------------------------------- đọc máy (chỉ đọc)
function ConvertFrom-NtpStamp {
    # Mốc thời gian NTP (8 byte: giây từ 1900 + phần lẻ) trong gói tin, đổi sang giờ UTC.
    param([byte[]]$Bytes, [int]$Offset)
    $sec = [double]0; $frac = [double]0
    for ($k = 0; $k -lt 4; $k++) { $sec = $sec * 256 + $Bytes[$Offset + $k] }
    for ($k = 4; $k -lt 8; $k++) { $frac = $frac * 256 + $Bytes[$Offset + $k] }
    if ($sec -lt 2147483648) { $sec += 4294967296 }   # sau 07/02/2036 bộ đếm giây quay vòng
    return (New-Object DateTime 1900, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)).AddSeconds($sec + $frac / 4294967296)
}

function Get-HttpDateOffset {
    # Giờ trong tiêu đề Date của một trang http (không https: giờ máy sai thì kiểm chứng chỉ hỏng). Độ chính xác 1 giây.
    param([string]$Url)
    $resp = $null
    try {
        $req = [Net.HttpWebRequest]::Create($Url)
        $req.Method = 'HEAD'; $req.Timeout = 4000; $req.AllowAutoRedirect = $false
        $t1 = [DateTime]::UtcNow
        try { $resp = $req.GetResponse() } catch [Net.WebException] { $resp = $_.Exception.Response }
        $t4 = [DateTime]::UtcNow
        if (-not $resp -or -not $resp.Headers['Date']) { return $null }
        $server = [DateTime]::ParseExact($resp.Headers['Date'], 'r', [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
        $mid = $t1.AddTicks([long](($t4 - $t1).Ticks / 2))
        return (($server - $mid).TotalSeconds + 0.5)   # tiêu đề bỏ phần lẻ của giây
    } catch { return $null }
    finally { if ($resp) { $resp.Close() } }
}

function Get-NtpOffset {
    # Độ lệch giờ máy so với máy chủ giờ (giây, dương = máy chậm hơn). Hỏi NTP (UDP 123); mạng chặn NTP thì đọc giờ
    # trong tiêu đề HTTP. Trả Ok = $false khi không hỏi được máy nào (không có mạng).
    foreach ($h in $script:NtpServers) {
        $udp = $null
        try {
            $udp = New-Object Net.Sockets.UdpClient
            $udp.Client.ReceiveTimeout = 2500
            $udp.Connect($h, 123)
            $req = New-Object byte[] 48
            $req[0] = 0x1B   # LI 0, phiên bản 3, chế độ khách
            $t1 = [DateTime]::UtcNow
            [void]$udp.Send($req, 48)
            $ep = New-Object Net.IPEndPoint ([Net.IPAddress]::Any), 0
            $resp = $udp.Receive([ref]$ep)
            $t4 = [DateTime]::UtcNow
            if ($resp.Length -lt 48) { continue }
            $t2 = ConvertFrom-NtpStamp $resp 32
            $t3 = ConvertFrom-NtpStamp $resp 40
            $off = (($t2 - $t1).TotalSeconds + ($t3 - $t4).TotalSeconds) / 2
            return [pscustomobject]@{ Ok = $true; Offset = $off; Source = "$h (NTP)" }
        } catch { } finally { if ($udp) { $udp.Dispose() } }
    }
    foreach ($u in $script:HttpTimeUrls) {
        $off = Get-HttpDateOffset $u
        if ($null -ne $off) { return [pscustomobject]@{ Ok = $true; Offset = $off; Source = ('{0} (giờ trong tiêu đề HTTP)' -f ([Uri]$u).Host) } }
    }
    return [pscustomobject]@{ Ok = $false; Offset = 0; Source = '' }
}

function Get-ZoneInfo {
    $z = [TimeZoneInfo]::Local
    return [pscustomobject]@{ Id = $z.Id; Name = $z.DisplayName; Offset = $z.BaseUtcOffset.TotalHours }
}

function Get-SvcConfig {
    # Kiểu khởi động đọc từ registry (người dùng thường đọc được), trạng thái chạy từ Get-Service.
    param([string]$Name)
    $item = Get-ItemProperty -LiteralPath (Join-Path $script:ServicesKey $Name) -ErrorAction SilentlyContinue
    if (-not $item -or $null -eq $item.PSObject.Properties['Start']) { return [pscustomobject]@{ Exists = $false; Start = -1; Running = $false } }
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Exists = $true; Start = [int]$item.Start; Running = [bool]($svc -and $svc.Status -eq 'Running') }
}

function Format-Start {
    param([int]$Start)
    switch ($Start) { 2 { 'Tự động' } 3 { 'Thủ công' } 4 { 'Đã tắt' } -1 { 'không có' } default { "kiểu $Start" } }
}

function Get-W32Params {
    # Kiểu đồng bộ của Windows Time: NTP (máy chủ giờ trên Internet), NT5DS (máy chủ domain), NoSync (không đồng bộ).
    $p = Get-ItemProperty -LiteralPath $script:W32Key -ErrorAction SilentlyContinue
    $type = if ($p -and $p.PSObject.Properties['Type']) { [string]$p.Type } else { '' }
    $srv = if ($p -and $p.PSObject.Properties['NtpServer']) { [string]$p.NtpServer } else { '' }
    return [pscustomobject]@{ Type = $type; NtpServer = $srv }
}

function Get-SmartCardReaders {
    # Đầu đọc thẻ, USB token mà dịch vụ Smart Card thấy. Không mở kết nối tới thẻ, không hỏi PIN.
    # Error: '' (đọc được), 'KHONG_CO' (không có đầu đọc nào), 'DICH_VU' (dịch vụ chưa chạy), mã lỗi khác.
    if (-not ('TramTool.WinSCard' -as [type])) {
        Add-Type -Namespace TramTool -Name WinSCard -MemberDefinition @'
[DllImport("winscard.dll")] public static extern int SCardEstablishContext(uint dwScope, IntPtr r1, IntPtr r2, out IntPtr phContext);
[DllImport("winscard.dll")] public static extern int SCardReleaseContext(IntPtr hContext);
[DllImport("winscard.dll", CharSet = CharSet.Unicode, EntryPoint = "SCardListReadersW")] public static extern int SCardListReaders(IntPtr hContext, string mszGroups, char[] mszReaders, ref uint pcchReaders);
'@
    }
    $ctx = [IntPtr]::Zero
    $rc = [TramTool.WinSCard]::SCardEstablishContext(2, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$ctx)
    if ($rc -in 0x8010001D, 0x8010001E) { return [pscustomobject]@{ Readers = @(); Error = 'DICH_VU' } }
    if ($rc -ne 0) { return [pscustomobject]@{ Readers = @(); Error = ('0x{0:X8}' -f $rc) } }
    try {
        $len = [uint32]0
        $rc = [TramTool.WinSCard]::SCardListReaders($ctx, $null, $null, [ref]$len)
        if ($rc -eq 0x8010002E) { return [pscustomobject]@{ Readers = @(); Error = 'KHONG_CO' } }
        if ($rc -ne 0) { return [pscustomobject]@{ Readers = @(); Error = ('0x{0:X8}' -f $rc) } }
        $buf = New-Object char[] ([int]$len)
        $rc = [TramTool.WinSCard]::SCardListReaders($ctx, $null, $buf, [ref]$len)
        if ($rc -ne 0) { return [pscustomobject]@{ Readers = @(); Error = ('0x{0:X8}' -f $rc) } }
        $names = @((New-Object string ($buf, 0, [int]$len)).Split([char]0) | Where-Object { $_ })
        return [pscustomobject]@{ Readers = $names; Error = '' }
    } finally { [void][TramTool.WinSCard]::SCardReleaseContext($ctx) }
}

function Get-TokenDevices {
    # Thiết bị đầu đọc thẻ, token đang cắm (Device Manager), kèm trạng thái driver.
    $list = @()
    foreach ($cls in 'SmartCardReader', 'SmartCard') {
        try { $list += @(Get-PnpDevice -Class $cls -PresentOnly -ErrorAction Stop) } catch { }
    }
    return , @($list | ForEach-Object { [pscustomobject]@{ Name = [string]$_.FriendlyName; Status = [string]$_.Status; Class = [string]$_.Class } })
}

function Test-SigningCert {
    # Chứng thư dùng để ký số: có khoá riêng, do nhà cung cấp cấp (không tự ký), của nhà cung cấp Việt Nam (C=VN)
    # hoặc khai mục đích chống chối bỏ (Non-Repudiation).
    param($Cert)
    if (-not $Cert.HasPrivateKey -or $Cert.Subject -eq $Cert.Issuer) { return $false }
    if ($Cert.Issuer -match '(^|,\s*)C=VN(\s*,|$)') { return $true }
    foreach ($e in $Cert.Extensions) {
        if ($e -is [Security.Cryptography.X509Certificates.X509KeyUsageExtension] -and
            ($e.KeyUsages -band [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::NonRepudiation)) { return $true }
    }
    return $false
}

function Get-SigningCerts {
    # Chứng thư ký số trong kho của tài khoản (Cert:\CurrentUser\My). Chỉ đọc thông tin chứng thư (HasPrivateKey không
    # mở khoá, không hỏi PIN); dựng chuỗi tới chứng thư gốc không kiểm tra thu hồi.
    $out = @()
    foreach ($c in @(Get-ChildItem -LiteralPath 'Cert:\CurrentUser\My' -ErrorAction SilentlyContinue)) {
        if (-not (Test-SigningCert $c)) { continue }
        $ok = $true; $st = @()
        $ch = New-Object Security.Cryptography.X509Certificates.X509Chain
        try {
            $ch.ChainPolicy.RevocationMode = [Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
            $ch.ChainPolicy.UrlRetrievalTimeout = [TimeSpan]::FromSeconds(5)
            $ch.ChainPolicy.VerificationFlags = [Security.Cryptography.X509Certificates.X509VerificationFlags]::IgnoreNotTimeValid
            $ok = $ch.Build($c)
            $st = @($ch.ChainStatus | ForEach-Object { [string]$_.Status })
        } catch { $ok = $false; $st = @('Loi') } finally { $ch.Reset() }
        $out += [pscustomobject]@{
            Ten = $c.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
            NhaCungCap = $c.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $true)
            TuNgay = $c.NotBefore; DenNgay = $c.NotAfter; Thumbprint = $c.Thumbprint
            ChuoiOk = [bool]$ok; ChuoiLoi = $st
        }
    }
    return , $out
}

function Get-SigningApps {
    # Phần mềm ký số, phần mềm của nhà cung cấp chứng thư số đã cài (tên trong danh sách gỡ cài đặt).
    $names = @()
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        $names += @(Get-ItemProperty -Path $k -ErrorAction SilentlyContinue | ForEach-Object { if ($_.PSObject.Properties['DisplayName']) { [string]$_.DisplayName } })
    }
    return , @($names | Where-Object { $_ -and $_ -match $script:SigningAppPattern } | Sort-Object -Unique)
}

# ---------------------------------------------------------------- đổi máy (cần Admin)
function Invoke-Sc {
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $out = & (Join-Path $env:SystemRoot 'System32\sc.exe') @Arguments 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = ((@($out) | ForEach-Object { [string]$_ }) -join ' ').Trim() }
}

function Invoke-W32tm {
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $out = & (Join-Path $env:SystemRoot 'System32\w32tm.exe') @Arguments 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = ((@($out) | ForEach-Object { [string]$_ }) -join ' ').Trim() }
}

function Start-Svc {
    # Chạy dịch vụ, trả $true khi đang chạy.
    param([string]$Name, [switch]$Restart)
    try {
        if ($Restart) { Restart-Service -Name $Name -Force -ErrorAction Stop } else { Start-Service -Name $Name -ErrorAction Stop }
        (Get-Service -Name $Name).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
        return $true
    } catch { return $false }
}

function Set-ZoneId {
    param([string]$Id)
    $ErrorActionPreference = 'Continue'
    $out = & (Join-Path $env:SystemRoot 'System32\tzutil.exe') /s $Id 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = ((@($out) | ForEach-Object { [string]$_ }) -join ' ').Trim() }
}

function Set-ClockAdjust {
    # Chỉnh giờ máy thêm $Seconds giây (dương = vặn tới). Trả $true khi đặt được.
    param([double]$Seconds)
    try { [void](Set-Date -Adjust ([TimeSpan]::FromSeconds($Seconds)) -ErrorAction Stop); return $true } catch { return $false }
}

function Set-W32Params {
    # Ghi lại kiểu đồng bộ và máy chủ giờ (dùng khi trả lại như cũ), rồi báo Windows Time đọc lại cấu hình.
    param([string]$Type, [string]$NtpServer)
    try {
        if ($Type) { Set-ItemProperty -LiteralPath $script:W32Key -Name Type -Value $Type -ErrorAction Stop }
        if ($NtpServer) { Set-ItemProperty -LiteralPath $script:W32Key -Name NtpServer -Value $NtpServer -ErrorAction Stop }
    } catch { return $false }
    if ((Get-SvcConfig 'W32Time').Running) { [void](Invoke-W32tm @('/config', '/update')) }
    return $true
}

# ---------------------------------------------------------------- trạng thái gốc
function Read-SavedState {
    if (-not (Test-Path -LiteralPath $script:StateFile)) { return $null }
    try { return ([IO.File]::ReadAllText($script:StateFile) | ConvertFrom-Json) }
    catch { throw "File trạng thái gốc bị hỏng: $script:StateFile. Đổi tên hoặc chép file đó đi chỗ khác rồi chạy lại." }
}

function Save-OriginalState {
    # Lưu giá trị trước khi đổi; mục đã lưu từ lần sửa trước thì giữ nguyên (để Trả lại về đúng lúc đầu).
    param([string[]]$Services = @(), [switch]$Clock)
    $old = Read-SavedState
    $svc = [ordered]@{}
    if ($old -and $old.dichVu) { foreach ($p in $old.dichVu.PSObject.Properties) { $svc[$p.Name] = [ordered]@{ start = [int]$p.Value.start } } }
    foreach ($n in $Services) { if (-not $svc.Contains($n)) { $c = Get-SvcConfig $n; if ($c.Exists) { $svc[$n] = [ordered]@{ start = $c.Start } } } }
    $gio = if ($old -and $old.dongBoGio) { [ordered]@{ type = [string]$old.dongBoGio.type; ntpServer = [string]$old.dongBoGio.ntpServer } } else { $null }
    $zone = if ($old -and $old.muiGio) { [string]$old.muiGio } else { '' }
    if ($Clock) {
        if (-not $gio) { $p = Get-W32Params; $gio = [ordered]@{ type = $p.Type; ntpServer = $p.NtpServer } }
        if (-not $zone) { $zone = (Get-ZoneInfo).Id }
    }
    $doc = [ordered]@{
        may = $env:COMPUTERNAME; luuLuc = $(if ($old -and $old.luuLuc) { [string]$old.luuLuc } else { (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') })
        ghiChu = 'Giá trị trước lần sửa đầu tiên của công cụ Giờ máy và chữ ký số; "Trả lại như trước khi sửa" dùng file này.'
        dichVu = $svc; dongBoGio = $gio; muiGio = $zone
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

function Invoke-ClockCheck {
    Write-Head 'Giờ máy'
    $z = Get-ZoneInfo
    $now = Get-Date
    Write-Line ('Giờ máy: {0:dd/MM/yyyy HH:mm:ss}, múi giờ {1}' -f $now, $z.Name)
    $m = Get-NtpOffset
    $suaGio = 'Chạy "Sửa giờ máy" (cần quyền Admin).'
    if (-not $m.Ok) {
        Add-Finding 'KHONG_DO_DUOC_GIO' 'thong-tin' 'Không đo được độ lệch giờ: không hỏi được máy chủ giờ nào' 'Máy chưa có mạng, hoặc mạng chặn cả NTP (cổng UDP 123) lẫn http.' 'Có mạng rồi chạy lại Kiểm tra.'
    } else {
        $a = [Math]::Abs($m.Offset)
        $txt = 'Giờ máy {0} so với {1}' -f (Format-Lech $m.Offset), $m.Source
        if ($a -gt $script:LechLoi) {
            Add-Finding 'GIO_LECH_NHIEU' 'loi' $txt 'Lệch quá 2 phút: ký số thuế, hoá đơn điện tử, BHXH và đăng nhập dễ báo lỗi; lệch nhiều ngày thì trang https báo chứng chỉ không hợp lệ. Máy hay sai giờ sau khi tắt hẳn thường do pin CMOS trên bo mạch chủ đã yếu.' $suaGio 'gio-chu-ky-so/sua-gio'
        } elseif ($a -gt $script:LechCanhBao) {
            Add-Finding 'GIO_LECH' 'canh-bao' $txt 'Nên đồng bộ lại để ký số không bị từ chối vì sai giờ.' $suaGio 'gio-chu-ky-so/sua-gio'
        } else {
            Add-Finding 'GIO_DUNG' 'ok' $txt
        }
    }
    if ($z.Id -eq $script:VnZone) {
        Add-Finding 'MUI_GIO_VN' 'ok' "Múi giờ Việt Nam: $($z.Name)"
    } elseif ($z.Offset -eq 7) {
        Add-Finding 'MUI_GIO_KHAC_TEN' 'thong-tin' "Múi giờ $($z.Name): cùng UTC+07:00 nhưng không phải múi giờ Việt Nam" 'Giờ vẫn đúng; một số phần mềm đọc tên múi giờ.' 'Có thể đổi sang SE Asia Standard Time bằng "Sửa giờ máy" (đánh dấu Đặt múi giờ Việt Nam).'
    } else {
        Add-Finding 'MUI_GIO_KHAC' 'canh-bao' "Múi giờ không phải giờ Việt Nam: $($z.Name)" 'Đồng hồ hiện giờ sai so với giờ Việt Nam dù giờ quốc tế (UTC) đúng; giờ ký trên chứng từ cũng sai.' 'Chạy "Sửa giờ máy", đánh dấu Đặt múi giờ Việt Nam.' 'gio-chu-ky-so/sua-gio'
    }
    $svc = Get-SvcConfig 'W32Time'
    $p = Get-W32Params
    if (-not $svc.Exists) {
        Add-Finding 'DICH_VU_GIO_KHONG_CO' 'loi' 'Máy không có dịch vụ Windows Time (W32Time)' 'Windows không tự đồng bộ giờ được.' 'Chạy "Sửa lỗi Windows > DISM rồi SFC" để khôi phục thành phần của Windows.' 'fix-win/dism-sfc'
    } elseif ($svc.Start -eq 4) {
        Add-Finding 'DICH_VU_GIO_TAT' 'canh-bao' 'Dịch vụ Windows Time đang bị tắt' 'Windows không tự đồng bộ giờ; thường do phần mềm "tối ưu" tắt.' $suaGio 'gio-chu-ky-so/sua-gio'
    }
    switch ($p.Type) {
        'NoSync' { Add-Finding 'DONG_BO_GIO_TAT' 'canh-bao' 'Đặt giờ tự động đang tắt (Windows Time không đồng bộ)' 'Giờ máy trôi dần theo đồng hồ trên bo mạch.' $suaGio 'gio-chu-ky-so/sua-gio' }
        'NT5DS' { Add-Finding 'MAY_TRONG_DOMAIN' 'thong-tin' 'Máy lấy giờ từ máy chủ domain (NT5DS)' 'Công cụ chỉ đồng bộ lại, không đổi cấu hình; giờ sai thì kiểm tra giờ của máy chủ domain.' }
        default { if ($svc.Exists -and $svc.Start -ne 4) { Write-Ok ('Đồng bộ giờ tự động: {0} ({1})' -f $(if ($p.Type) { $p.Type } else { 'mặc định' }), ($p.NtpServer -replace ',0x[0-9a-fA-F]+', '')) } }
    }
}

function Invoke-TokenCheck {
    Write-Head 'USB token và chứng thư ký số'
    $suaToken = 'Chạy "Sửa dịch vụ đọc USB token" (cần quyền Admin).'
    foreach ($n in $script:TokenServices.Keys) {
        $s = $script:TokenServices[$n]; $c = Get-SvcConfig $n
        if (-not $c.Exists) { Add-Finding 'DICH_VU_TOKEN_KHONG_CO' 'loi' "Máy không có dịch vụ $($s.Label)" '' 'Chạy "Sửa lỗi Windows > DISM rồi SFC".' 'fix-win/dism-sfc'; continue }
        if ($c.Start -eq 4) {
            $why = if ($n -eq 'SCardSvr') { 'Windows không đọc được USB token, phần mềm ký số báo không thấy thiết bị.' } else { 'Cắm token vào, chứng thư không tự hiện trong Windows nên trình duyệt, phần mềm ký không thấy.' }
            Add-Finding $s.Code $s.Muc "Dịch vụ $($s.Label) đang bị tắt" "$why Thường do phần mềm tối ưu tắt." $suaToken 'gio-chu-ky-so/sua-token'
        } else { Write-Ok ('Dịch vụ {0}: {1}, {2}' -f $s.Label, (Format-Start $c.Start), $(if ($c.Running) { 'đang chạy' } else { 'tự chạy khi cắm token' })) }
    }
    $dev = Get-TokenDevices
    foreach ($d in @($dev | Where-Object { $_.Status -and $_.Status -ne 'OK' })) {
        Add-Finding 'TOKEN_LOI_DRIVER' 'canh-bao' "Driver của thiết bị $($d.Name) đang lỗi ($($d.Status))" 'Windows thấy token nhưng driver chưa chạy được.' 'Rút token, cài lại phần mềm, driver của nhà cung cấp chữ ký số rồi cắm lại.'
    }
    $r = Get-SmartCardReaders
    if ($r.Readers.Count) {
        Add-Finding 'TOKEN_DANG_CAM' 'ok' ('Windows thấy {0} đầu đọc, token: {1}' -f $r.Readers.Count, ($r.Readers -join '; '))
    } elseif ($r.Error -in 'KHONG_CO', 'DICH_VU') {
        $chiTiet = if (@($dev).Count) { 'Device Manager có thiết bị token nhưng dịch vụ Smart Card chưa thấy.' } else { 'Chưa cắm token, hoặc token dùng driver riêng của nhà cung cấp (không qua dịch vụ Smart Card).' }
        Add-Finding 'KHONG_THAY_TOKEN' 'thong-tin' 'Không thấy USB token nào qua dịch vụ Smart Card' $chiTiet 'Cắm token rồi chạy lại Kiểm tra; vẫn không thấy thì cài phần mềm, driver của nhà cung cấp chữ ký số.'
    } else {
        Add-Finding 'KHONG_DOC_DUOC_TOKEN' 'thong-tin' "Không đọc được danh sách đầu đọc thẻ (mã $($r.Error))"
    }

    $certs = Get-SigningCerts
    $now = Get-Date
    if (-not $certs.Count) {
        Add-Finding 'KHONG_CO_CHUNG_THU' 'thong-tin' 'Kho chứng thư của tài khoản này chưa có chứng thư ký số nào' 'Chứng thư trong token thường tự hiện khi cắm token (dịch vụ Certificate Propagation) hoặc khi mở phần mềm của nhà cung cấp.'
    }
    $valid = @($certs | Where-Object { $_.TuNgay -le $now -and $_.DenNgay -gt $now })
    foreach ($c in $certs) {
        $ten = '{0} (cấp bởi {1})' -f $c.Ten, $c.NhaCungCap
        $han = 'Hiệu lực {0:dd/MM/yyyy} đến {1:dd/MM/yyyy}.' -f $c.TuNgay, $c.DenNgay
        if ($c.TuNgay -gt $now) {
            Add-Finding 'CHUNG_THU_CHUA_HIEU_LUC' 'loi' "Chứng thư $ten chưa tới ngày hiệu lực theo giờ máy" "$han Thường do giờ máy chậm: ký số sẽ báo chứng thư không hợp lệ." 'Chạy "Sửa giờ máy".' 'gio-chu-ky-so/sua-gio'
        } elseif ($c.DenNgay -le $now) {
            $moi = @($valid | Where-Object { $_.Ten -eq $c.Ten }).Count
            if ($moi) { Add-Finding 'CHUNG_THU_CU_HET_HAN' 'thong-tin' "Chứng thư cũ $ten đã hết hạn, đã có chứng thư mới cùng tên" $han 'Khi ký, chọn chứng thư còn hạn.' }
            else { Add-Finding 'CHUNG_THU_HET_HAN' 'canh-bao' "Chứng thư $ten đã hết hạn" $han 'Gia hạn với nhà cung cấp chữ ký số. Giờ máy sai (nhanh) cũng làm chứng thư còn hạn bị coi là hết hạn: xem mục giờ máy.' }
        } elseif (($c.DenNgay - $now).TotalDays -le $script:SapHetHanNgay) {
            Add-Finding 'CHUNG_THU_SAP_HET_HAN' 'canh-bao' ('Chứng thư {0} hết hạn sau {1} ngày' -f $ten, [Math]::Ceiling(($c.DenNgay - $now).TotalDays)) $han 'Liên hệ nhà cung cấp chữ ký số để gia hạn trước ngày hết hạn.'
        } else {
            Add-Finding 'CHUNG_THU_CON_HAN' 'ok' "Chứng thư $ten còn hạn" $han
        }
        if (-not $c.ChuoiOk -and @($c.ChuoiLoi | Where-Object { $_ -in 'UntrustedRoot', 'PartialChain' }).Count) {
            Add-Finding 'CHUNG_THU_THIEU_GOC' 'canh-bao' "Windows chưa tin chứng thư gốc của $($c.NhaCungCap)" ('Chuỗi chứng thư: {0}. Phần mềm ký, trình duyệt có thể báo chữ ký không hợp lệ.' -f ($c.ChuoiLoi -join ', ')) 'Cài lại phần mềm token của nhà cung cấp (bộ cài kèm chứng thư gốc của nhà cung cấp và Root CA quốc gia).'
        }
    }
    $apps = Get-SigningApps
    if ($apps.Count) { Add-Finding 'PHAN_MEM_KY_SO' 'thong-tin' ('Phần mềm ký số, thuế đã cài: {0}' -f ($apps -join '; ')) }
    else { Add-Finding 'KHONG_THAY_PHAN_MEM_KY_SO' 'thong-tin' 'Không thấy phần mềm ký số quen thuộc nào trong danh sách phần mềm đã cài' 'Công cụ chỉ nhận ra tên phổ biến (eSigner, VNPT-CA, Viettel-CA, FPT-CA, BKAV-CA, iTaxViewer, HTKK...).' }
}

function Invoke-AllChecks {
    $script:Findings.Clear()
    Invoke-ClockCheck
    Invoke-TokenCheck
}

function Save-RunResult {
    # Ghi kết quả lần chạy cho Trạm Tool (chuẩn tramtool.ketqua/1). Không có PIN, khoá, nội dung chứng thư.
    param([string]$CheDo, [int]$Code, [datetime]$Start, [string]$Message = '')
    $i = 0
    $sorted = @($script:Findings | ForEach-Object { [pscustomobject]@{ F = $_; L = $script:Levels[[string]$_.mucDo]; I = $i++ } } | Sort-Object L, I | ForEach-Object { $_.F })
    $nLoi = @($sorted | Where-Object { $_.mucDo -eq 'loi' }).Count
    $nCanh = @($sorted | Where-Object { $_.mucDo -eq 'canh-bao' }).Count
    $nTin = @($sorted | Where-Object { $_.mucDo -eq 'thong-tin' }).Count
    if (-not $Message) {
        $Message = if ($nLoi + $nCanh) { 'Có {0} lỗi, {1} cảnh báo về giờ máy hoặc chữ ký số; xem gợi ý sửa.' -f $nLoi, $nCanh } else { 'Giờ máy và chữ ký số không có gì cần sửa.' }
    }
    $tep = @()
    if (Test-Path -LiteralPath $script:StateFile) { $tep += [ordered]@{ nhan = 'Trạng thái gốc để trả lại'; duongDan = $script:StateFile } }
    $r = [ordered]@{
        chuan = 'tramtool.ketqua/1'; congCu = 'gio-chu-ky-so'; cheDo = $CheDo; phienBan = $script:Version
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
        $f = Join-Path $script:ResultDir ('KetQua_GioChuKySo_{0}_{1:yyyyMMdd_HHmmss}.json' -f $env:COMPUTERNAME, $Start)
        $tmp = "$f.tmp"
        [IO.File]::WriteAllText($tmp, ($r | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding $false))
        Move-Item -LiteralPath $tmp -Destination $f -Force
        Write-Info "Kết quả cho Trạm Tool: $f"
    } catch { Write-Warn "Không ghi được file kết quả: $($_.Exception.Message.Trim())" }
}

# ---------------------------------------------------------------- chế độ
function Invoke-SuaGio {
    param([switch]$DryRun, [switch]$Ask, [bool]$SetZone = $false)
    Write-Head 'Sửa giờ máy'
    $svc = Get-SvcConfig 'W32Time'
    if (-not $svc.Exists) { Write-Bad 'Máy không có dịch vụ Windows Time: chạy "Sửa lỗi Windows > DISM rồi SFC" trước.'; return 1 }
    $p = Get-W32Params; $z = Get-ZoneInfo; $m = Get-NtpOffset
    $domain = $p.Type -eq 'NT5DS'
    Write-Line ('Dịch vụ Windows Time: {0}, {1}; đồng bộ: {2}; múi giờ: {3}' -f (Format-Start $svc.Start), $(if ($svc.Running) { 'đang chạy' } else { 'đang dừng' }), $(if ($p.Type) { $p.Type } else { 'mặc định' }), $z.Name)
    if ($m.Ok) { Write-Line ('Giờ máy {0} so với {1}.' -f (Format-Lech $m.Offset), $m.Source) } else { Write-Warn 'Chưa đo được độ lệch giờ (không hỏi được máy chủ giờ).' }

    $zoneChange = $SetZone -and $z.Id -ne $script:VnZone
    Write-Line ''
    Write-Line 'Sẽ làm:'
    if ($svc.Start -eq 4) { Write-Plan 'sc config W32Time start= demand   (Thủ công, mặc định của Windows)' }
    if (-not $svc.Running) { Write-Plan 'Chạy dịch vụ Windows Time' }
    if ($p.Type -eq 'NoSync') { Write-Plan "w32tm /config /manualpeerlist:$script:PeerList /syncfromflags:manual /update   (bật đặt giờ tự động)" }
    if ($domain) { Write-Info 'Máy trong domain: chỉ đồng bộ lại với máy chủ domain, không đổi cấu hình, không tự đặt giờ.' }
    if ($zoneChange) { Write-Plan "Đặt múi giờ $script:VnZone (UTC+07:00, giờ Việt Nam)" }
    Write-Plan 'w32tm /resync /force   (đồng bộ ngay)'
    if (-not $domain) { Write-Plan ('Đo lại; còn lệch quá {0} giây thì đặt giờ theo máy chủ giờ' -f $script:LechDatGio) }
    if ($DryRun) { Write-Info 'Chạy thử: không đổi gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo 'Làm các việc trên?' $false)) { Write-Info 'Đã huỷ, chưa đổi gì.'; return 2 }

    if ($svc.Start -eq 4 -or $p.Type -eq 'NoSync' -or $zoneChange) {   # chỉ đồng bộ lại thì không đổi cấu hình nào
        try { Save-OriginalState -Services @('W32Time') -Clock; Write-Ok "Đã lưu giá trị cũ vào $script:StateFile" }
        catch { Write-Bad ('Không lưu được giá trị cũ nên chưa đổi gì: {0}' -f $_.Exception.Message.Trim()); return 1 }
    }

    $fail = 0; $done = 0
    if ($svc.Start -eq 4) {
        $r = Invoke-Sc @('config', 'W32Time', 'start=', 'demand')
        if ($r.Code -eq 0 -and (Get-SvcConfig 'W32Time').Start -eq 3) { Write-Ok 'Dịch vụ Windows Time: Thủ công.'; $done++ }
        else { Write-Bad ('Chưa bật được dịch vụ Windows Time (sc mã {0}). {1}' -f $r.Code, $r.Output); return 1 }
    }
    if (-not (Get-SvcConfig 'W32Time').Running) {
        if (Start-Svc 'W32Time') { Write-Ok 'Dịch vụ Windows Time đang chạy.'; $done++ } else { Write-Bad 'Không chạy được dịch vụ Windows Time.'; return 1 }
    }
    if ($p.Type -eq 'NoSync') {
        $r = Invoke-W32tm @('/config', "/manualpeerlist:$script:PeerList", '/syncfromflags:manual', '/update')
        if ($r.Code -eq 0 -and (Get-W32Params).Type -eq 'NTP') { Write-Ok 'Đã bật đặt giờ tự động (time.windows.com).'; $done++ }
        else { Write-Bad ('Chưa bật được đặt giờ tự động (w32tm mã {0}). {1}' -f $r.Code, $r.Output); $fail++ }
    }
    if ($zoneChange) {
        $r = Set-ZoneId $script:VnZone
        if ($r.Code -eq 0 -and (Get-ZoneInfo).Id -eq $script:VnZone) { Write-Ok 'Đã đặt múi giờ Việt Nam.'; $done++ }
        else { Write-Bad ('Chưa đặt được múi giờ (tzutil mã {0}). {1}' -f $r.Code, $r.Output); $fail++ }
    }
    $r = Invoke-W32tm @('/resync', '/force')
    if ($r.Code -eq 0) { Write-Ok 'Đã đồng bộ giờ.' } else { Write-Warn ('w32tm /resync báo mã {0}: {1}' -f $r.Code, $r.Output) }
    Start-Sleep -Milliseconds 1500
    $after = Get-NtpOffset
    if ($after.Ok -and [Math]::Abs($after.Offset) -gt $script:LechDatGio -and -not $domain) {
        Write-Warn ('Vẫn {0}: đặt giờ theo {1}.' -f (Format-Lech $after.Offset), $after.Source)
        if (Set-ClockAdjust $after.Offset) { [void](Invoke-W32tm @('/resync', '/force')); $after = Get-NtpOffset }
        else { Write-Bad 'Không đặt được giờ máy.' }
    }
    Write-Line ''
    if (-not $after.Ok) { Write-Warn 'Không đo lại được giờ (không hỏi được máy chủ giờ) nên chưa chắc đã đúng.'; return 3 }
    if ([Math]::Abs($after.Offset) -le $script:LechCanhBao) {
        Write-Ok ('Giờ máy bây giờ {0}.' -f (Format-Lech $after.Offset))
        if ($fail) { return 3 }
        return 0
    }
    Write-Bad ('Giờ máy vẫn {0}.' -f (Format-Lech $after.Offset))
    if ($domain) { Write-Sub 'Máy trong domain: kiểm tra giờ của máy chủ domain.' }
    return $(if ($done) { 3 } else { 1 })
}

function Invoke-SuaToken {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head 'Sửa dịch vụ đọc USB token'
    $plan = @()
    foreach ($n in $script:TokenServices.Keys) {
        $c = Get-SvcConfig $n
        if (-not $c.Exists) { Write-Bad "Máy không có dịch vụ $n`: chạy ""Sửa lỗi Windows > DISM rồi SFC"" trước."; continue }
        $plan += [pscustomobject]@{ Name = $n; Config = $c; Label = $script:TokenServices[$n].Label }
        Write-Line ('{0}: {1}, {2}' -f $script:TokenServices[$n].Label, (Format-Start $c.Start), $(if ($c.Running) { 'đang chạy' } else { 'đang dừng' }))
    }
    if (-not $plan.Count) { return 1 }
    Write-Line ''
    Write-Line 'Sẽ làm:'
    foreach ($it in $plan) {
        if ($it.Config.Start -eq 4) { Write-Plan "sc config $($it.Name) start= demand   (Thủ công, mặc định của Windows)" }
        if ($it.Name -eq 'CertPropSvc') { Write-Plan $(if ($it.Config.Running) { 'Chạy lại Certificate Propagation để chứng thư trong token hiện lại' } else { 'Chạy Certificate Propagation' }) }
        elseif (-not $it.Config.Running) { Write-Plan "Chạy dịch vụ $($it.Name)" }
    }
    if ($DryRun) { Write-Info 'Chạy thử: không đổi gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo 'Làm các việc trên?' $false)) { Write-Info 'Đã huỷ, chưa đổi gì.'; return 2 }
    $disabled = @($plan | Where-Object { $_.Config.Start -eq 4 } | ForEach-Object { $_.Name })
    if ($disabled.Count) {
        try { Save-OriginalState -Services $disabled; Write-Ok "Đã lưu giá trị cũ vào $script:StateFile" }
        catch { Write-Bad ('Không lưu được giá trị cũ nên chưa đổi gì: {0}' -f $_.Exception.Message.Trim()); return 1 }
    }
    $fail = 0; $done = 0
    foreach ($it in $plan) {
        $n = $it.Name
        if ($it.Config.Start -eq 4) {
            $r = Invoke-Sc @('config', $n, 'start=', 'demand')
            if ($r.Code -ne 0 -or (Get-SvcConfig $n).Start -ne 3) { Write-Bad ('{0}: chưa bật được (sc mã {1}). {2}' -f $n, $r.Code, $r.Output); $fail++; continue }
            Write-Ok "$n`: Thủ công."; $done++
        }
        $running = (Get-SvcConfig $n).Running
        if (Start-Svc $n -Restart:($n -eq 'CertPropSvc' -and $running)) { Write-Ok "$n`: đang chạy."; $done++ }
        elseif ($n -eq 'SCardSvr') { Write-Info 'Smart Card: chưa chạy ngay (bình thường khi chưa cắm token; Windows tự chạy khi cắm).' }
        else { Write-Bad "$n`: không chạy được."; $fail++ }
    }
    Write-Line ''
    if ($fail -and $done) { return 3 }
    if ($fail) { return 1 }
    Write-Info 'Rút token ra cắm lại, rồi mở lại phần mềm ký số hoặc trình duyệt.'
    return 0
}

function Invoke-HoanTac {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head 'Trả lại như trước khi sửa'
    try { $s = Read-SavedState } catch { Write-Bad $_.Exception.Message; return 1 }
    if (-not $s) { Write-Info 'Chưa có giá trị cũ nào được lưu (công cụ chưa đổi gì trên máy này).'; return 0 }
    Write-Line "Giá trị lưu lúc $($s.luuLuc):"
    $ops = @()
    if ($s.dichVu) {
        foreach ($p in $s.dichVu.PSObject.Properties) {
            $c = Get-SvcConfig $p.Name
            if ($c.Exists -and $c.Start -ne [int]$p.Value.start) { $ops += [pscustomobject]@{ Kind = 'svc'; Name = $p.Name; Value = [int]$p.Value.start; Text = ('{0}: {1} -> {2}' -f $p.Name, (Format-Start $c.Start), (Format-Start ([int]$p.Value.start))) } }
        }
    }
    if ($s.dongBoGio) {
        $now = Get-W32Params
        if ([string]$s.dongBoGio.type -ne $now.Type -or [string]$s.dongBoGio.ntpServer -ne $now.NtpServer) {
            $ops += [pscustomobject]@{ Kind = 'w32'; Name = 'W32Time'; Value = $s.dongBoGio; Text = ('Đồng bộ giờ: {0} {1} -> {2} {3}' -f $now.Type, $now.NtpServer, $s.dongBoGio.type, $s.dongBoGio.ntpServer) }
        }
    }
    if ($s.muiGio -and [string]$s.muiGio -ne (Get-ZoneInfo).Id) { $ops += [pscustomobject]@{ Kind = 'zone'; Name = 'muiGio'; Value = [string]$s.muiGio; Text = "Múi giờ -> $($s.muiGio)" } }
    if (-not $ops.Count) {
        Write-Ok 'Máy đang đúng như giá trị đã lưu, không cần đổi.'
        if (-not $DryRun) { Remove-Item -LiteralPath $script:StateFile -Force -ErrorAction SilentlyContinue }
        return 0
    }
    Write-Line 'Sẽ làm:'
    foreach ($o in $ops) { Write-Plan $o.Text }
    if ($DryRun) { Write-Info 'Chạy thử: không đổi gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo 'Làm các việc trên?' $false)) { Write-Info 'Đã huỷ, chưa đổi gì.'; return 2 }
    $fail = 0
    foreach ($o in $ops) {
        switch ($o.Kind) {
            'svc' {
                $sc = @{ 2 = 'auto'; 3 = 'demand'; 4 = 'disabled' }[$o.Value]
                if (-not $sc) { Write-Bad "$($o.Name): kiểu khởi động đã lưu không hợp lệ ($($o.Value))."; $fail++; continue }
                $r = Invoke-Sc @('config', $o.Name, 'start=', $sc)
                if ($r.Code -eq 0 -and (Get-SvcConfig $o.Name).Start -eq $o.Value) { Write-Ok $o.Text } else { Write-Bad ('{0} (sc mã {1}). {2}' -f $o.Text, $r.Code, $r.Output); $fail++ }
            }
            'w32' {
                if (Set-W32Params ([string]$o.Value.type) ([string]$o.Value.ntpServer)) { Write-Ok $o.Text } else { Write-Bad "Chưa trả được: $($o.Text)"; $fail++ }
            }
            'zone' {
                $r = Set-ZoneId $o.Value
                if ($r.Code -eq 0 -and (Get-ZoneInfo).Id -eq $o.Value) { Write-Ok $o.Text } else { Write-Bad ('{0} (tzutil mã {1}). {2}' -f $o.Text, $r.Code, $r.Output); $fail++ }
            }
        }
    }
    if ($fail) { Write-Warn 'Còn mục chưa trả được; giữ file giá trị cũ để chạy lại.'; return $(if ($fail -lt $ops.Count) { 3 } else { 1 }) }
    Remove-Item -LiteralPath $script:StateFile -Force -ErrorAction SilentlyContinue
    Write-Ok 'Đã trả lại hết; xoá file giá trị cũ.'
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
            'sua-gio' {
                $zone = $MuiGioVN -or ($Ask -and (Get-ZoneInfo).Id -ne $script:VnZone -and (Read-YesNo ('Múi giờ đang là {0}. Đặt múi giờ Việt Nam (UTC+07:00)?' -f (Get-ZoneInfo).Name) $true))
                $code = Invoke-SuaGio -DryRun:$ChayThu -Ask:$Ask -SetZone $zone
            }
            'sua-token' { $code = Invoke-SuaToken -DryRun:$ChayThu -Ask:$Ask }
            'hoan-tac' { $code = Invoke-HoanTac -DryRun:$ChayThu -Ask:$Ask }
        }
    } catch {
        Write-Bad ('Lỗi không lường trước: {0}' -f $_.Exception.Message.Trim())
        $code = 1
    }
    if ($Id -ne 'kiem-tra') {
        $msg = switch ($code) {
            0 { if ($ChayThu) { 'Chạy thử: chỉ xem việc sẽ làm, máy không bị đổi.' } else { '{0}: xong.' -f $script:Modes[$Id].Label } }
            2 { 'Chưa làm: thiếu quyền Admin hoặc đã huỷ.' }
            3 { '{0}: làm được một phần.' -f $script:Modes[$Id].Label }
            default { '{0}: lỗi, xem cửa sổ công cụ.' -f $script:Modes[$Id].Label }
        }
    }
    Invoke-AllChecks   # kiểm tra (lại) sau khi sửa: kết quả ghi cho trạm là trạng thái máy lúc này
    Save-RunResult -CheDo $Id -Code $code -Start $start -Message $msg
    return $code
}

function Invoke-ElevatedMode {
    # Mở một chế độ trong cửa sổ Admin riêng (Windows hỏi UAC), chờ xong, trả mã thoát. Dùng cho menu.
    param([string]$Id)
    $argText = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -DaNangQuyen -Mode {1}{2}' -f $PSCommandPath, $Id, $(if ($Id -eq 'sua-gio' -and $MuiGioVN) { ' -MuiGioVN' })
    try { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argText -Verb RunAs -Wait -PassThru; return [int]$p.ExitCode }
    catch {
        $e = $_.Exception; $native = 0
        while ($e) { if ($e -is [ComponentModel.Win32Exception]) { $native = $e.NativeErrorCode; break }; $e = $e.InnerException }
        if ($native -eq 1223) { Write-Warn 'Bạn đã chọn "Không" ở hộp thoại quyền Admin nên chưa chạy.'; return 2 }
        Write-Bad "Không mở được bằng quyền Admin: $($_.Exception.Message.Trim())"
        return 1
    }
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '  GIỜ MÁY VÀ CHỮ KÝ SỐ (USB TOKEN)' -ForegroundColor Cyan
        Write-Host '  Ký số thuế, hoá đơn điện tử, BHXH báo lỗi: kiểm tra trước, sửa sau. Mọi thay đổi trả lại được.' -ForegroundColor Gray
        Write-Host ''
        foreach ($id in $script:Modes.Keys) { Write-Host ('   {0}. {1}' -f $script:Modes[$id].No, $script:Modes[$id].Label) }
        Write-Host '   0. Thoát'
        Write-Host ''
        $c = Read-Text 'Chọn số' '0'
        if ($c -eq '0') { return 0 }
        $id = $null
        foreach ($k in $script:Modes.Keys) { if ([string]$script:Modes[$k].No -eq $c) { $id = $k } }
        if (-not $id) { continue }
        if ($script:Modes[$id].Admin -and -not (Test-IsAdmin)) { [void](Invoke-ElevatedMode $id); continue }
        [void](Invoke-Mode $id -Ask)
        Wait-Close 'Bấm Enter để về menu'
    }
}

# ---------------------------------------------------------------- bắt đầu
if ($env:TRAMTOOL_GIOCHUKYSO_TEST) { return }   # bài thử nạp các hàm rồi tự gọi
try { $Host.UI.RawUI.WindowTitle = 'Giờ máy và chữ ký số' } catch { }
if ($Mode -and -not $script:Modes.Contains($Mode)) {
    Write-Bad ('Không có chế độ "{0}". Các chế độ: {1}.' -f $Mode, (@($script:Modes.Keys) -join ', '))
    Wait-Close
    exit 1
}
if ($Mode -and $script:Modes[$Mode].Admin -and -not $ChayThu -and -not (Test-IsAdmin)) {
    if ($DaNangQuyen) { Write-Bad 'Đã mở lại mà vẫn chưa có quyền Admin.'; Wait-Close; exit 2 }
    Write-Info 'Việc này đổi cài đặt của Windows nên cần quyền Admin: Windows sẽ hỏi (UAC), chọn "Có".'
    $argText = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -DaNangQuyen -Mode {1}{2}{3}' -f $PSCommandPath, $Mode, $(if ($MuiGioVN) { ' -MuiGioVN' }), $(if ($KhongDung) { ' -KhongDung' })
    try { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argText -Verb RunAs -Wait -PassThru }
    catch {
        $e = $_.Exception; $native = 0
        while ($e) { if ($e -is [ComponentModel.Win32Exception]) { $native = $e.NativeErrorCode; break }; $e = $e.InnerException }
        if ($native -eq 1223) { Write-Warn 'Bạn đã chọn "Không" ở hộp thoại quyền Admin nên chưa chạy.'; exit 2 }
        Write-Bad "Không mở được bằng quyền Admin: $($_.Exception.Message.Trim())"
        exit 1
    }
    exit $p.ExitCode
}
if (-not $Mode) {
    if ([Console]::IsInputRedirected) { Write-Host 'Cách dùng: GioChuKySo.ps1 -Mode kiem-tra|sua-gio|sua-token|hoan-tac [-MuiGioVN] [-ChayThu] [-KhongDung]'; exit 1 }
    exit (Show-Menu)
}
$code = Invoke-Mode $Mode
Wait-Close
exit $code
