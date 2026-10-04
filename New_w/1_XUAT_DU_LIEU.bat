<# : ===== Phan CMD: tu xin quyen Admin roi chay phan PowerShell ben duoi (khong sua) =====
@echo off
setlocal
title Xuat du lieu truoc khi cai lai Windows - Claude / Wi-Fi / May in
set "__BAT=%~f0"
set "__DIR=%~dp0"
fltmc >nul 2>&1 || (
  echo.
  echo   Can quyen Administrator. Hay bam YES khi Windows hoi...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $q=[char]34; Start-Process -FilePath $env:ComSpec -ArgumentList ('/d /c '+$q+$q+$env:__BAT+$q+$q) -Verb RunAs -ErrorAction Stop } catch { Write-Host '  Ban da tu choi quyen Administrator - khong the tiep tuc.' -ForegroundColor Red; pause }"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create([IO.File]::ReadAllText($env:__BAT, [Text.Encoding]::UTF8)))"
echo.
pause
exit /b
#>
# ============================================================================
#  XUẤT DỮ LIỆU TRƯỚC KHI CÀI LẠI WINDOWS
#  Sao lưu: Wi-Fi (kèm mật khẩu) - Máy in (driver, cổng, cấu hình) - Claude
#  Kết quả: thư mục "DuLieu_SaoLuu" nằm cạnh file .bat này
#  Dùng kèm: 2_NHAP_DU_LIEU.bat (chạy sau khi cài lại Windows)
# ============================================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Warnings  = New-Object System.Collections.ArrayList
$Stat      = @{ Wifi = 0; WifiNoKey = 0; Printers = 0; Drivers = 0; Claude = $false; Code = 0; CodeOk = 0; CodeHtml = 0 }

# ---------------------------------------------------------------- tiện ích
function Head([string]$m) { Write-Host ''; Write-Host ('=' * 70) -ForegroundColor DarkCyan; Write-Host "  $m" -ForegroundColor Cyan; Write-Host ('=' * 70) -ForegroundColor DarkCyan }
function Ok([string]$m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Info([string]$m) { Write-Host "       $m" -ForegroundColor Gray }
function Warn([string]$m) { Write-Host "  [!]  $m" -ForegroundColor Yellow; [void]$Warnings.Add($m) }
function Fail([string]$m) { Write-Host "  [X]  $m" -ForegroundColor Red; [void]$Warnings.Add($m) }

function Ensure-Dir([string]$p) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Save-Text([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, $Utf8NoBom) }
function Save-Json($obj, [string]$path) { Save-Text $path (ConvertTo-Json -InputObject $obj -Depth 8) }
function Read-Json([string]$path) { [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json }
function Get-Size([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return [long]0 }
    $s = (Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if ($s) { return [long]$s } else { return [long]0 }
}
function Fmt-Size([long]$b) { if ($b -ge 1GB) { '{0:N2} GB' -f ($b / 1GB) } else { '{0:N1} MB' -f ($b / 1MB) } }

# Chép cả thư mục bằng robocopy (nhanh, giữ ngày giờ, chịu được đường dẫn dài). Trả về mã robocopy (<8 = thành công)
function Copy-Tree([string]$src, [string]$dst, [string[]]$xd = @(), [string[]]$xf = @(), [switch]$NewerOnly) {
    Ensure-Dir $dst
    $ra = @($src, $dst, '/E', '/COPY:DAT', '/DCOPY:T', '/R:1', '/W:1', '/XJ', '/MT:8', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($NewerOnly) { $ra += '/XO' }
    if ($xd.Count -gt 0) { $ra += '/XD'; $ra += $xd }
    if ($xf.Count -gt 0) { $ra += '/XF'; $ra += $xf }
    $o = & robocopy.exe @ra
    $rc = [int]$LASTEXITCODE
    if ($rc -ge 8) { foreach ($l in @($o | Where-Object { $_ -match '\(0x[0-9A-Fa-f]{8}\)' } | Select-Object -First 15)) { Write-Host "       $l" -ForegroundColor DarkYellow } }
    return $rc
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

# ============================================================================ 1. WI-FI
function Export-Wifi {
    Head '1/3  WI-FI'
    $wDir = Join-Path $Out 'WiFi'
    Ensure-Dir $wDir
    $svc = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
    if (-not $svc) { Info 'Máy không có Wi-Fi (không có dịch vụ WlanSvc) - bỏ qua.'; return }
    try { if ([string]$svc.StartType -eq 'Disabled') { Set-Service -Name WlanSvc -StartupType Manual -ErrorAction Stop } } catch {}
    if ($svc.Status -ne 'Running') { try { Start-Service -Name WlanSvc -ErrorAction Stop; Start-Sleep -Seconds 2 } catch {} }

    $items = New-Object System.Collections.ArrayList     # mỗi phần tử: @{Name; Flags; Xml}
    $seen  = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $apiOk = $false
    if (Load-WlanApi) {
        try {
            foreach ($pr in [WlanTool]::Export()) {
                if (($pr.Flags -band 1) -ne 0) { Info "Bỏ qua mạng do công ty quản lý (Group Policy): $($pr.Name)"; continue }
                if (-not $pr.Xml) { Warn "Không đọc được Wi-Fi '$($pr.Name)' (mã lỗi $($pr.Error))"; continue }
                if (-not $seen.Add($pr.Name + '|' + $pr.Flags)) { continue }    # trùng do có 2 card Wi-Fi
                [void]$items.Add(@{ Name = $pr.Name; Flags = [int]($pr.Flags -band 2); Xml = $pr.Xml })
            }
            $apiOk = $true
        } catch { Warn "WLAN API lỗi: $($_.Exception.Message) - chuyển sang dùng netsh." }
    }
    if (-not $apiOk) {
        # Dự phòng: netsh (thư mục tạm phải NGẮN vì netsh cắt đường dẫn dài ~128 ký tự)
        $tmp = Join-Path $env:SystemRoot ('Temp\wx' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            & netsh.exe wlan export profile key=clear folder="$tmp" | Out-Null
            foreach ($f in @(Get-ChildItem -LiteralPath $tmp -Filter '*.xml' -File -ErrorAction SilentlyContinue)) {
                $x = [IO.File]::ReadAllText($f.FullName)
                $nm = (Get-WifiInfo $x).Name
                if ($nm -and $seen.Add($nm + '|0')) { [void]$items.Add(@{ Name = $nm; Flags = 0; Xml = $x }) }
            }
        } finally { try { [IO.Directory]::Delete($tmp, $true) } catch {} }
    }

    # Không đọc được mạng nào nhưng Windows vẫn còn hồ sơ Wi-Fi -> card Wi-Fi đang tắt / thiếu driver: phải báo rõ
    if ($items.Count -eq 0) {
        $nIf = 0
        if ($apiOk) { try { $nIf = [WlanTool]::InterfaceCount() } catch {} }
        $stored = @(Get-ChildItem -LiteralPath (Join-Path $env:ProgramData 'Microsoft\Wlansvc\Profiles\Interfaces') -Recurse -Filter '*.xml' -File -ErrorAction SilentlyContinue).Count
        if ($nIf -eq 0 -and $stored -gt 0) {
            Fail "Máy còn $stored hồ sơ Wi-Fi nhưng KHÔNG đọc được (card Wi-Fi đang tắt / thiếu driver / dịch vụ WlanSvc bị tắt). Bật card Wi-Fi (ncpa.cpl) rồi chạy lại TRƯỚC khi cài Win."
        }
    }

    $index = New-Object System.Collections.ArrayList
    $lines = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($it in $items) {
        $i++
        $fn = '{0:D3}.xml' -f $i
        Save-Text (Join-Path $wDir $fn) $it.Xml
        $wi = Get-WifiInfo $it.Xml
        [void]$index.Add([pscustomobject]@{ File = $fn; Name = $it.Name; Flags = $it.Flags; Auth = $wi.Auth; HasPassword = $wi.HasKey; Encrypted = $wi.Encrypted })
        $tag = if ($wi.HasKey) { 'có mật khẩu' } elseif ($wi.Encrypted) { 'MẬT KHẨU BỊ MÃ HÓA - phải nhập lại' } elseif ($wi.Auth -eq 'open') { 'mạng mở' } else { $wi.Auth }
        [void]$lines.Add(('{0,3}. {1}   ({2})' -f $i, $it.Name, $tag))
        if ($wi.Encrypted) { $Stat.WifiNoKey++ }
    }
    Save-Json @($index) (Join-Path $wDir 'danh-sach.json')
    Save-Text (Join-Path $wDir 'DanhSachWiFi.txt') (($lines -join "`r`n") + "`r`n")
    $Stat.Wifi = $index.Count
    if ($index.Count -gt 0) { Ok "Đã lưu $($index.Count) mạng Wi-Fi" } else { Info 'Không có mạng Wi-Fi nào được lưu trên máy.' }
    if ($Stat.WifiNoKey -gt 0) { Warn "$($Stat.WifiNoKey) mạng Wi-Fi không lấy được mật khẩu (sau khi cài Win sẽ phải nhập lại)." }
}

# ============================================================================ 2. MÁY IN
$SkipPorts   = @('PORTPROMPT:', 'nul:', 'SHRFAX:', 'XPSPort:', 'FILE:')
$SkipDrivers = @('Microsoft Print To PDF', 'Microsoft XPS Document Writer', 'Microsoft XPS Document Writer v4', 'Microsoft Software Printer Driver', 'Microsoft Shared Fax Driver')
function Test-BuiltinPrinter($p) {
    return (($SkipPorts -contains $p.PortName) -or ($SkipDrivers -contains $p.DriverName) -or ($p.DriverName -like 'Send to Microsoft OneNote*') -or ($p.DriverName -like 'Send To OneNote*'))
}

$script:PnpCache = $null
function Get-WsdIp([string]$portName) {
    # Cổng WSD không tạo lại được -> tìm IP thật của máy in để bên nhập tạo cổng TCP/IP thay thế
    try {
        $k = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\WSD Port\Ports\$portName"
        $uuid = [string](Get-ItemProperty -LiteralPath $k -ErrorAction Stop).'Printer UUID'
        if (-not $uuid) { return $null }
        if ($null -eq $script:PnpCache) { $script:PnpCache = @(Get-PnpDevice -ErrorAction SilentlyContinue) }
        foreach ($d in @($script:PnpCache | Where-Object { $_.InstanceId -like "*$uuid*" })) {
            $loc = [string](Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_LocationInfo' -ErrorAction SilentlyContinue).Data
            if ($loc -match '(\d{1,3}(\.\d{1,3}){3})') { return $Matches[1] }
        }
    } catch {}
    return $null
}

function Export-Printers {
    Head '2/3  MÁY IN'
    $pDir   = Join-Path $Out 'MayIn'
    $drvDir = Join-Path $pDir 'Drivers'
    $tkDir  = Join-Path $pDir 'CauHinh'
    Ensure-Dir $drvDir; Ensure-Dir $tkDir

    $sp = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if (-not $sp) { Fail 'Không có dịch vụ Print Spooler - bỏ qua máy in.'; return }
    if ($sp.Status -ne 'Running') {
        try { Start-Service -Name Spooler -ErrorAction Stop; Start-Sleep -Seconds 2 } catch { Fail 'Không bật được Print Spooler - bỏ qua máy in.'; return }
    }

    $printers = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { -not (Test-BuiltinPrinter $_) })
    $portMap = @{}
    foreach ($pt in @(Get-PrinterPort -ErrorAction SilentlyContinue)) { $portMap[$pt.Name] = $pt }

    # Máy in mặc định
    $winKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'
    $wk = Get-ItemProperty -Path $winKey -ErrorAction SilentlyContinue
    # Giá trị Device có thể là "Tên,winspool,Ne01:" hoặc "Tên,Driver,Cổng" - tên máy in không bao giờ chứa dấu phẩy
    $defaultName = $null
    try { $defaultName = [string](Get-CimInstance -ClassName Win32_Printer -Filter 'Default=TRUE' -ErrorAction Stop | Select-Object -First 1).Name } catch {}
    if (-not $defaultName -and $wk -and $wk.Device) { $defaultName = ([string]$wk.Device).Split(',')[0].Trim() }
    if (-not $defaultName) { $defaultName = $null }
    $legacyMode = $null
    if ($wk -and $wk.PSObject.Properties['LegacyDefaultPrinterMode']) { $legacyMode = [int]$wk.LegacyDefaultPrinterMode }

    $recs = New-Object System.Collections.ArrayList
    $portRecs = [ordered]@{}
    $txt = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($p in $printers) {
        $i++
        $pt = $portMap[$p.PortName]
        $kind = 'OTHER'
        if ([string]$p.Type -eq 'Connection' -or $p.Name -like '\\*') { $kind = 'CONNECTION' }
        elseif ($pt -and $pt.CimClass.CimClassName -eq 'MSFT_TcpIpPrinterPort') { $kind = 'TCP' }
        elseif ($p.PortName -like 'WSD-*' -or ($pt -and [string]$pt.Description -eq 'WSD Port')) { $kind = 'WSD' }
        elseif ($p.PortName -like 'USB*' -or $p.PortName -like 'DOT4*') { $kind = 'USB' }
        elseif ($p.PortName -match '^(LPT|COM)\d+:$') { $kind = 'LOCAL' }

        $hostAddr = $null; $wsdIp = $null
        if ($kind -eq 'TCP') {
            $hostAddr = [string]$pt.PrinterHostAddress
            if (-not $hostAddr) { $hostAddr = [string]$pt.PrinterHostIP }
            if (-not $portRecs.Contains($pt.Name)) {
                $idx = [int]$pt.SNMPIndex; if ($idx -lt 1) { $idx = 1 }
                $portRecs[$pt.Name] = [pscustomobject]@{
                    Name = $pt.Name; Host = $hostAddr; PortNumber = [int]$pt.PortNumber
                    Protocol = $(if ([string]$pt.Protocol -match '^(2|LPR)$') { 'LPR' } else { 'RAW' })
                    LprQueueName = [string]$pt.LprQueueName; LprByteCounting = [bool]$pt.LprByteCounting
                    SNMPEnabled = [bool]$pt.SNMPEnabled; SNMPCommunity = [string]$pt.SNMPCommunity; SNMPIndex = $idx
                }
            }
        } elseif ($kind -eq 'WSD') {
            $wsdIp = Get-WsdIp $p.PortName
            $hostAddr = $wsdIp
            if (-not $wsdIp) { Warn "Máy in '$($p.Name)' dùng cổng WSD nhưng không tìm được IP - sau khi cài Win cần thêm lại bằng tay." }
        }

        # Cấu hình in (khổ giấy, in 2 mặt, màu...)
        $tf = $null
        if ($kind -ne 'CONNECTION') {
            try {
                $cfg = Get-PrintConfiguration -PrinterName $p.Name -ErrorAction Stop
                if ($cfg.PrintTicketXML) { $tf = '{0:D3}.xml' -f $i; Save-Text (Join-Path $tkDir $tf) $cfg.PrintTicketXML }
            } catch { Info "(không đọc được cấu hình in của '$($p.Name)' - sẽ dùng mặc định)" }
        }

        [void]$recs.Add([pscustomobject]@{
            Name = $p.Name; Type = [string]$p.Type; Kind = $kind
            DriverName = [string]$p.DriverName; PortName = [string]$p.PortName; Host = $hostAddr; WsdIp = $wsdIp
            Shared = [bool]$p.Shared; ShareName = [string]$p.ShareName
            Location = [string]$p.Location; Comment = [string]$p.Comment
            TicketFile = $tf; IsDefault = ($p.Name -eq $defaultName)
        })
        $where = if ($hostAddr) { $hostAddr } else { $p.PortName }
        [void]$txt.Add(('{0,3}. {1}  |  {2}  |  {3}{4}{5}' -f $i, $p.Name, $where, $p.DriverName, $(if ($p.Shared) { '  | chia sẻ' } else { '' }), $(if ($p.Name -eq $defaultName) { '  | MẶC ĐỊNH' } else { '' })))
        Ok ("{0}  ->  {1}" -f $p.Name, $where)
    }

    # Driver: chép nguyên gói driver (trừ driver có sẵn của Windows)
    $used = @{}
    foreach ($p in $printers) { if ($p.DriverName) { $used[[string]$p.DriverName] = $true } }
    $drvRecs = New-Object System.Collections.ArrayList
    $pkgMap = @{}
    foreach ($d in @(Get-PrinterDriver -ErrorAction SilentlyContinue)) {
        $inf = [string]$d.InfPath
        $infName = ''
        if ($inf) { $infName = [IO.Path]::GetFileName($inf) }
        $inbox = ([string]$d.Manufacturer -eq 'Microsoft') -or ($infName -match '^(ntprint4?|prnms\d+)\.inf$')
        $rec = [pscustomobject]@{
            Name = $d.Name; Environment = [string]$d.PrinterEnvironment; MajorVersion = [int]$d.MajorVersion
            Manufacturer = [string]$d.Manufacturer; Inbox = $inbox; Used = $used.ContainsKey([string]$d.Name); Folder = $null; Inf = $null
        }
        if (-not $inbox) {
            $key = $null
            if ($inf -and (Test-Path -LiteralPath $inf)) { $key = (Split-Path -Parent $inf).ToLowerInvariant() }
            if (-not $key) {
                if ($rec.Used) { Warn "Không tìm thấy bộ cài driver '$($d.Name)' - sau khi cài Win cần tải driver này từ trang của hãng." }
            } else {
                if (-not $pkgMap.ContainsKey($key)) {
                    $src = Split-Path -Parent $inf
                    $folder = $null
                    if ($src -like '*\DriverStore\FileRepository\*') {
                        $folder = Split-Path -Leaf $src
                        [void](Copy-Tree $src (Join-Path $drvDir $folder))
                    } elseif ($infName -match '^oem\d+\.inf$') {
                        $folder = [IO.Path]::GetFileNameWithoutExtension($infName)
                        Ensure-Dir (Join-Path $drvDir $folder)
                        & pnputil.exe /export-driver $infName (Join-Path $drvDir $folder) | Out-Null
                    }
                    $okInf = $null
                    if ($folder) {
                        $dst = Join-Path $drvDir $folder
                        if (Test-Path -LiteralPath (Join-Path $dst $infName)) { $okInf = $infName }
                        else { $f1 = @(Get-ChildItem -LiteralPath $dst -Filter '*.inf' -File -ErrorAction SilentlyContinue) | Select-Object -First 1; if ($f1) { $okInf = $f1.Name } }
                    }
                    if ($okInf) { $pkgMap[$key] = @($folder, $okInf) } else { $pkgMap[$key] = $null }
                }
                if ($pkgMap[$key]) {
                    $rec.Folder = $pkgMap[$key][0]; $rec.Inf = $pkgMap[$key][1]
                    Ok "Driver: $($d.Name)  [$($rec.Environment)]"
                    $Stat.Drivers++
                } elseif ($rec.Used) {
                    Fail "Không chép được driver '$($d.Name)' - sau khi cài Win cần tải từ trang của hãng."
                }
            }
        }
        [void]$drvRecs.Add($rec)
    }

    $data = [pscustomobject]@{
        DefaultPrinter = $defaultName; LegacyDefaultPrinterMode = $legacyMode
        Printers = @($recs); Ports = @($portRecs.Values); Drivers = @($drvRecs)
    }
    Save-Json $data (Join-Path $pDir 'may-in.json')
    $head = "DANH SÁCH MÁY IN  (Tên | IP hoặc cổng | Driver)`r`n" + ('-' * 60) + "`r`n"
    Save-Text (Join-Path $pDir 'DanhSachMayIn.txt') ($head + ($txt -join "`r`n") + "`r`n")
    $Stat.Printers = $recs.Count
    if ($defaultName) { Info "Máy in mặc định: $defaultName" }
}

# ============================================================================ 3. CLAUDE
# ---- Hội thoại tab Code: danh sách = claude-code-sessions\...\local_*.json ; nội dung = .claude\projects\...\<cliSessionId>.jsonl
function To-Local($ms) { try { return [DateTimeOffset]::FromUnixTimeMilliseconds([long]$ms).LocalDateTime } catch { return $null } }
function Html([string]$s) { return [System.Net.WebUtility]::HtmlEncode($s) }
function Safe-Name([string]$s) {
    $s = ($s -replace '[\\/:*?"<>|\x00-\x1F]', ' ' -replace '\s+', ' ').Trim().TrimEnd('.')
    if ($s.Length -gt 60) { $s = $s.Substring(0, 60).Trim() }
    if (-not $s) { $s = 'Khong-tieu-de' }
    return $s
}
function Clean-Text([string]$t) {
    if (-not $t) { return '' }
    $t = [regex]::Replace($t, '(?s)<system-reminder>.*?</system-reminder>', '')
    $t = [regex]::Replace($t, '(?s)<local-command-(stdout|stderr|caveat)>.*?</local-command-\1>', '')
    return $t.Trim()
}
function Tool-Brief($blk) {
    $d = ''
    $in = $blk['input']
    if ($in -is [System.Collections.IDictionary]) {
        foreach ($k in @('description', 'command', 'file_path', 'pattern', 'url', 'query', 'prompt')) { if ($in.ContainsKey($k) -and $in[$k]) { $d = [string]$in[$k]; break } }
    }
    $d = ($d -replace '\s+', ' ').Trim()
    if ($d.Length -gt 160) { $d = $d.Substring(0, 160) + '...' }
    if ($d) { return ([string]$blk['name'] + ': ' + $d) } else { return [string]$blk['name'] }
}
$HtmlCss = 'body{font-family:Segoe UI,Arial,sans-serif;max-width:920px;margin:24px auto;padding:0 16px;background:#f6f6f4;color:#222;line-height:1.5}' +
    'h1{font-size:22px}.meta{color:#666;font-size:13px;margin-bottom:18px}.m{border-radius:10px;padding:10px 14px;margin:10px 0}' +
    '.u{background:#dbeafe}.a{background:#fff;border:1px solid #e3e3e3}.h{font-size:12px;color:#666;margin-bottom:4px;font-weight:600}' +
    '.t{white-space:pre-wrap;word-wrap:break-word}.tool{font:12px Consolas,monospace;color:#777;margin:2px 0 2px 14px}' +
    'details{background:#fff7e0;border-radius:10px;padding:8px 14px;margin:10px 0}table{border-collapse:collapse;width:100%;background:#fff}' +
    'td,th{border-bottom:1px solid #e5e5e5;padding:6px 8px;text-align:left;font-size:14px;vertical-align:top}a{color:#1d4ed8}' +
    '@media(prefers-color-scheme:dark){body{background:#1c1c1c;color:#e6e6e6}.u{background:#1e3a5f}.a,table{background:#262626;border-color:#333}details{background:#3a3220}.meta,.h,.tool{color:#aaa}td,th{border-color:#333}a{color:#8ab4ff}}'

function Write-ConversationHtml($s, [string]$path, $ser) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>').Append((Html $s.Title)).Append('</title><style>').Append($HtmlCss).Append('</style></head><body>')
    [void]$sb.Append('<p><a href="index.html">&larr; Danh sách hội thoại</a></p><h1>').Append((Html $s.Title)).Append('</h1><div class="meta">Thư mục: ').Append((Html $s.Cwd))
    [void]$sb.Append(' &middot; Bắt đầu: ').Append($(if ($s.Created) { $s.Created.ToString('dd/MM/yyyy HH:mm') } else { '?' })).Append(' &middot; Lần cuối: ').Append($(if ($s.Last) { $s.Last.ToString('dd/MM/yyyy HH:mm') } else { '?' })).Append('</div>')
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $msgs = 0; $lastRole = ''
    $rd = New-Object System.IO.StreamReader($s.File.FullName, [Text.Encoding]::UTF8)
    try {
        while ($null -ne ($line = $rd.ReadLine())) {
            if ($line.IndexOf('"type":"user"') -lt 0 -and $line.IndexOf('"type":"assistant"') -lt 0) { continue }
            try { $o = $ser.DeserializeObject($line) } catch { continue }
            if (-not ($o -is [System.Collections.IDictionary])) { continue }
            $t = [string]$o['type']
            if ($t -ne 'user' -and $t -ne 'assistant') { continue }
            if ($o['isSidechain'] -or $o['isMeta']) { continue }
            $uuid = [string]$o['uuid']
            if ($uuid -and -not $seen.Add($uuid)) { continue }
            $m = $o['message']
            if (-not ($m -is [System.Collections.IDictionary])) { continue }
            $c = $m['content']
            $time = ''
            if ($o['timestamp']) { try { $time = ([DateTime]::Parse([string]$o['timestamp'])).ToLocalTime().ToString('dd/MM HH:mm') } catch {} }
            if ($t -eq 'user') {
                $txt = ''
                if ($c -is [string]) { $txt = Clean-Text $c }
                else {
                    $parts = New-Object System.Collections.ArrayList
                    foreach ($b in @($c)) {
                        if (-not ($b -is [System.Collections.IDictionary])) { continue }
                        if ($b['type'] -eq 'text') { $x = Clean-Text ([string]$b['text']); if ($x) { [void]$parts.Add($x) } }
                        elseif ($b['type'] -eq 'image') { [void]$parts.Add('[ảnh]') }
                    }
                    $txt = $parts -join "`n`n"
                }
                if (-not $txt) { continue }
                if ($txt -match '^\s*<task-notification>') { continue }          # thông báo tác vụ nền, không phải lời người dùng
                if ($txt -match '<command-name>\s*([^<]+?)\s*</command-name>') {  # lệnh /xxx -> hiện gọn
                    $cmdName = $Matches[1]
                    if (-not $cmdName.StartsWith('/')) { $cmdName = '/' + $cmdName }
                    $cmdArgs = ''
                    if ($txt -match '(?s)<command-args>(.*?)</command-args>') { $cmdArgs = $Matches[1].Trim() }
                    $txt = ($cmdName + ' ' + $cmdArgs).Trim()
                }
                if ($o['isCompactSummary']) {
                    [void]$sb.Append('<details><summary>Tóm tắt phần trước (hội thoại quá dài nên đã được rút gọn)</summary><div class="t">').Append((Html $txt)).Append('</div></details>')
                } else {
                    [void]$sb.Append('<div class="m u"><div class="h">Bạn &middot; ').Append($time).Append('</div><div class="t">').Append((Html $txt)).Append('</div></div>')
                    $msgs++
                }
                $lastRole = 'u'
            } else {
                $blocks = if ($c -is [string]) { @(@{ type = 'text'; text = $c }) } else { @($c) }
                foreach ($b in $blocks) {
                    if (-not ($b -is [System.Collections.IDictionary])) { continue }
                    $bt = [string]$b['type']
                    if ($bt -eq 'text') {
                        $x = ([string]$b['text']).Trim()
                        if (-not $x) { continue }
                        [void]$sb.Append('<div class="m a">')
                        if ($lastRole -ne 'a') { [void]$sb.Append('<div class="h">Claude &middot; ').Append($time).Append('</div>') }
                        [void]$sb.Append('<div class="t">').Append((Html $x)).Append('</div></div>')
                        $msgs++; $lastRole = 'a'
                    } elseif ($bt -eq 'tool_use') {
                        [void]$sb.Append('<div class="tool">&#128295; ').Append((Html (Tool-Brief $b))).Append('</div>')
                    }
                }
            }
        }
    } finally { $rd.Close() }
    [void]$sb.Append('</body></html>')
    [IO.File]::WriteAllText($path, $sb.ToString(), $Utf8NoBom)
    return $msgs
}

function Export-CodeConversations([string]$cOut) {
    $sessDir = Join-Path $cOut 'AppData-Claude\claude-code-sessions'
    $projDir = Join-Path $cOut 'dot-claude\projects'
    if (-not (Test-Path -LiteralPath $sessDir)) { return }
    $tx = @{}
    if (Test-Path -LiteralPath $projDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $projDir -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue)) {
            if (-not $tx.ContainsKey($f.BaseName) -or $f.Length -gt $tx[$f.BaseName].Length) { $tx[$f.BaseName] = $f }
        }
    }
    $list = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $sessDir -Recurse -File -Filter 'local_*.json' -ErrorAction SilentlyContinue)) {
        try { $j = Read-Json $f.FullName } catch { continue }
        $cli = [string]$j.cliSessionId
        $tf = $null
        if ($cli -and $tx.ContainsKey($cli)) { $tf = $tx[$cli] }
        [void]$list.Add([pscustomobject]@{
            Id = [string]$j.sessionId; Title = [string]$j.title; Cwd = [string]$j.cwd; Archived = [bool]$j.isArchived
            Created = (To-Local $j.createdAt); Last = (To-Local $j.lastActivityAt); File = $tf
        })
    }
    $Stat.Code = $list.Count
    $Stat.CodeOk = @($list | Where-Object { $_.File }).Count
    if ($list.Count -eq 0) { return }
    if ($Stat.CodeOk -eq $list.Count) { Ok "Hội thoại tab Code: đủ $($Stat.CodeOk)/$($list.Count) cuộc (cả danh sách lẫn nội dung)" }
    else { Warn ("Hội thoại tab Code: chỉ có nội dung của $($Stat.CodeOk)/$($list.Count) cuộc. Thiếu: " + ((@($list | Where-Object { -not $_.File } | ForEach-Object { $_.Title })) -join '; ')) }

    # Bản đọc được bằng trình duyệt - phòng khi sau này ứng dụng không hiện lại được
    Info 'Đang tạo bản đọc được của từng cuộc hội thoại (mở bằng trình duyệt)...'
    $hDir = Join-Path $cOut 'HoiThoai-Code'
    Ensure-Dir $hDir
    try {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        $ser.RecursionLimit = 1000
    } catch { Warn "Không tạo được bản đọc được: $($_.Exception.Message)"; return }
    $rows = New-Object System.Text.StringBuilder
    foreach ($s in @($list | Sort-Object -Property Last -Descending)) {
        if (-not $s.File) { continue }
        $short = ($s.Id -replace '^local_', '')
        if ($short.Length -gt 8) { $short = $short.Substring(0, 8) }
        $fn = '{0} {1} ({2}).html' -f $(if ($s.Last) { $s.Last.ToString('yyyy-MM-dd') } else { '0000-00-00' }), (Safe-Name $s.Title), $short
        try { $cnt = Write-ConversationHtml $s (Join-Path $hDir $fn) $ser }
        catch { Warn "Không tạo được bản đọc của '$($s.Title)': $($_.Exception.Message)"; continue }
        $Stat.CodeHtml++
        [void]$rows.Append('<tr><td>').Append($(if ($s.Last) { $s.Last.ToString('dd/MM/yyyy') } else { '' })).Append('</td><td><a href="').Append([Uri]::EscapeDataString($fn)).Append('">').Append((Html $s.Title)).Append('</a>')
        if ($s.Archived) { [void]$rows.Append(' <small>(đã lưu trữ)</small>') }
        [void]$rows.Append('</td><td>').Append((Html $s.Cwd)).Append('</td><td>').Append($cnt).Append('</td></tr>')
    }
    $idx = '<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Hội thoại Claude Code</title><style>' + $HtmlCss + '</style></head><body>' +
        '<h1>Hội thoại tab Code của Claude</h1><div class="meta">Sao lưu lúc ' + (Get-Date -Format 'dd/MM/yyyy HH:mm') + ' trên máy ' + (Html $env:COMPUTERNAME) + ' &middot; ' + $Stat.CodeHtml + ' cuộc hội thoại. Bản này chỉ để ĐỌC; để tiếp tục làm việc hãy dùng ứng dụng Claude sau khi khôi phục.</div>' +
        '<table><tr><th>Lần cuối</th><th>Tiêu đề</th><th>Thư mục</th><th>Tin nhắn</th></tr>' + $rows.ToString() + '</table></body></html>'
    [IO.File]::WriteAllText((Join-Path $hDir 'index.html'), $idx, $Utf8NoBom)
    Ok "Bản đọc được: Claude\HoiThoai-Code\index.html ($($Stat.CodeHtml) cuộc hội thoại)"
}

function Export-Claude {
    Head '3/3  CLAUDE'
    $cOut = Join-Path $Out 'Claude'
    Ensure-Dir $cOut
    $UP = $env:USERPROFILE

    # (a) Claude Code: ~\.claude (cài đặt, memory, lịch sử phiên, skills, plugins, tác vụ hẹn giờ)
    #     Bỏ: cache/log tạm và .credentials.json (token đăng nhập - không nên để trên USB, chỉ cần đăng nhập lại)
    $dc = Join-Path $UP '.claude'
    if (Test-Path -LiteralPath $dc) {
        $xd = @('cache', 'telemetry', 'shell-snapshots', 'session-env', 'ide', 'sessions', 'statsig', 'debug') | ForEach-Object { Join-Path $dc $_ }
        $rc = Copy-Tree $dc (Join-Path $cOut 'dot-claude') $xd @('.credentials.json', 'mcp-needs-auth-cache.json')
        if ($rc -lt 8) { Ok 'Claude Code (~\.claude): cài đặt, memory, lịch sử phiên, skills, plugins, tác vụ hẹn giờ'; $Stat.Claude = $true }
        else { Fail "Chép ~\.claude bị lỗi (robocopy mã $rc)" }
    } else { Info 'Không có thư mục ~\.claude' }

    # (b) ~\.claude.json (cấu hình chung của Claude Code, MCP theo dự án...)
    $cj = Join-Path $UP '.claude.json'
    if (Test-Path -LiteralPath $cj) {
        Copy-Item -LiteralPath $cj -Destination (Join-Path $cOut 'dot-claude.json') -Force
        Ok 'Cấu hình chung Claude Code (~\.claude.json)'; $Stat.Claude = $true
    }

    # (c) Claude Desktop. Bản cài MSIX lưu thật ở %LOCALAPPDATA%\Packages\Claude_xxx\LocalCache\Roaming\Claude
    $srcs = New-Object System.Collections.ArrayList
    $real = Join-Path $env:APPDATA 'Claude'
    if (Test-Path -LiteralPath $real) { [void]$srcs.Add($real) }
    foreach ($d in @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue)) {
        $v = Join-Path $d.FullName 'LocalCache\Roaming\Claude'
        if (Test-Path -LiteralPath $v) { [void]$srcs.Add($v) }
    }
    $aOut = Join-Path $cOut 'AppData-Claude'
    $first = $true
    foreach ($s in $srcs) {
        $f = Join-Path $s 'claude_desktop_config.json'
        if (Test-Path -LiteralPath $f) {
            Ensure-Dir $aOut
            $t = Join-Path $aOut 'claude_desktop_config.json'
            if ($first -or -not (Test-Path -LiteralPath $t) -or ((Get-Item -LiteralPath $f).LastWriteTimeUtc -gt (Get-Item -LiteralPath $t).LastWriteTimeUtc)) {
                Copy-Item -LiteralPath $f -Destination $t -Force
            }
        }
        foreach ($sub in @('claude-code-sessions', 'local-agent-mode-sessions', 'Claude Extensions', 'Claude Extensions Settings')) {
            $sd = Join-Path $s $sub
            if (Test-Path -LiteralPath $sd) {
                $rc = Copy-Tree $sd (Join-Path $aOut $sub) -NewerOnly:(-not $first)
                if ($rc -ge 8) { Warn "Chép '$sub' của Claude Desktop có lỗi (robocopy mã $rc)" }
            }
        }
        $first = $false
    }
    if (Test-Path -LiteralPath $aOut) { Ok 'Claude Desktop: cấu hình, danh sách phiên Code/Cowork, tác vụ hẹn giờ, extension'; $Stat.Claude = $true }
    elseif ($srcs.Count -eq 0) { Info 'Không thấy dữ liệu Claude Desktop trên máy.' }

    # (d) Thư mục file của Cowork (nếu nằm trên ổ C thì mới cần chép)
    $cowork = $null; $coworkSaved = $false
    $cfgFile = Join-Path $aOut 'claude_desktop_config.json'
    if (Test-Path -LiteralPath $cfgFile) { try { $cowork = [string](Read-Json $cfgFile).coworkUserFilesPath } catch {} }
    if ($cowork -and (Test-Path -LiteralPath $cowork)) {
        if ($cowork.Length -ge 2 -and $cowork.Substring(0, 2) -ieq $env:SystemDrive) {
            $rc = Copy-Tree $cowork (Join-Path $cOut 'Cowork-Files')
            if ($rc -lt 8) { $coworkSaved = $true; Ok "Thư mục file Cowork: $cowork" } else { Warn "Chép thư mục Cowork lỗi (robocopy mã $rc)" }
        } else { Info "Thư mục file Cowork ở ổ khác ($cowork) - không bị xóa khi cài Win, không cần chép." }
    }

    # (đ) Kiểm đếm hội thoại tab Code + tạo bản đọc được
    Export-CodeConversations $cOut

    # (e) Thư mục dự án (code, tài liệu) mà Claude đã làm việc - KHÔNG chép (có thể rất lớn) nhưng phải nhắc,
    #     vì nằm trên ổ C sẽ mất khi cài Win, lịch sử phiên Claude khôi phục xong sẽ trỏ vào thư mục không còn
    $top = @()
    if (Test-Path -LiteralPath $cj) {
        try {
            $UPt = $UP.TrimEnd('\')
            $proj = New-Object 'System.Collections.Generic.List[string]'
            $seenP = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($k in @((Read-Json $cj).projects.PSObject.Properties | ForEach-Object { $_.Name })) {
                $p = ([string]$k).Replace('/', '\').TrimEnd('\')
                if ($p.Length -le 3 -or $p.Substring(0, 2) -ine $env:SystemDrive) { continue }
                if ($p -ieq $UPt -or $p -like "$UPt\AppData\*" -or $p -like '*\.claude\*') { continue }
                if ((Test-Path -LiteralPath $p) -and $seenP.Add($p)) { $proj.Add($p) }
            }
            $top = @($proj | Sort-Object | Where-Object { $x = $_; @($proj | Where-Object { $x.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0 })
        } catch {}
    }
    if ($top.Count -gt 0) {
        Save-Text (Join-Path $cOut 'thu-muc-du-an.txt') ("CÁC THƯ MỤC DỰ ÁN CLAUDE TRÊN Ổ $($env:SystemDrive) - TỰ CHÉP SANG USB/Ổ D TRƯỚC KHI CÀI WIN,`r`nCÀI XONG CHÉP VỀ ĐÚNG CHỖ CŨ:`r`n`r`n" + ($top -join "`r`n") + "`r`n")
        Warn "$($top.Count) thư mục dự án Claude (Desktop, Documents...) nằm trên ổ $($env:SystemDrive) KHÔNG nằm trong bản sao lưu này - tự chép chúng trước khi cài Win (danh sách: Claude\thu-muc-du-an.txt)."
    }

    Save-Json ([pscustomobject]@{ UserProfile = $UP; UserName = $env:USERNAME; CoworkPath = $cowork; CoworkSaved = $coworkSaved; ProjectFolders = @($top); AppDataSources = @($srcs) }) (Join-Path $cOut 'claude-info.json')
    Info 'Lưu ý: cuộc trò chuyện, Projects, skills trên tài khoản claude.ai nằm trên mây - đăng nhập lại là có.'
}

# ============================================================================ CHƯƠNG TRÌNH CHÍNH
$Root = ([string]$env:__DIR).TrimEnd('\')
if (-not $Root) { $Root = (Get-Location).Path }
$Out = Join-Path $Root 'DuLieu_SaoLuu'

Clear-Host
Write-Host ''
Write-Host '  ==================================================================' -ForegroundColor Cyan
Write-Host '     XUẤT DỮ LIỆU TRƯỚC KHI CÀI LẠI WINDOWS' -ForegroundColor White
Write-Host '     Wi-Fi (kèm mật khẩu)  -  Máy in  -  Claude' -ForegroundColor White
Write-Host '  ==================================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "  Dữ liệu sẽ được lưu vào:  $Out" -ForegroundColor White

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Warn 'Không chạy với quyền Administrator - có thể thiếu mật khẩu Wi-Fi / driver máy in.' }

if ($Out.Length -ge 2 -and $Out.Substring(0, 2) -ieq $env:SystemDrive) {
    Write-Host ''
    Write-Host "  [!] CHÚ Ý: thư mục sao lưu đang nằm trên ổ $($env:SystemDrive) - ổ này SẼ BỊ XÓA khi cài lại Win." -ForegroundColor Yellow
    Write-Host '      Làm xong phải chép cả thư mục DuLieu_SaoLuu + 2 file .bat sang USB hoặc ổ D.' -ForegroundColor Yellow
    Write-Host '      (Tốt nhất: chép 2 file .bat vào USB/ổ D rồi chạy từ đó.)' -ForegroundColor Yellow
}

# Ước lượng dung lượng cần
if ($Out -match '^([A-Za-z]):') {
    try {
        $need = (Get-Size (Join-Path $env:USERPROFILE '.claude')) + 300MB
        $free = (New-Object System.IO.DriveInfo($Matches[1])).AvailableFreeSpace
        Info ("Cần khoảng {0}, ổ đích còn trống {1}" -f (Fmt-Size $need), (Fmt-Size $free))
        if ($free -lt $need) { Warn 'Ổ đích có thể KHÔNG ĐỦ CHỖ.' }
    } catch {}
}

if (@(Get-Process -Name 'claude' -ErrorAction SilentlyContinue).Count -gt 0) {
    Write-Host ''
    Write-Host '  [!] Claude đang mở. Nên thoát hẳn Claude để sao lưu đầy đủ nhất.' -ForegroundColor Yellow
    $a = Read-Host '      Gõ T rồi Enter để TỰ ĐÓNG Claude, hoặc chỉ nhấn Enter để chép luôn'
    if ($a -match '^\s*[Tt]') { Get-Process -Name 'claude' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3 }
}

Write-Host ''
[void](Read-Host '  Nhấn Enter để BẮT ĐẦU sao lưu (đóng cửa sổ này nếu muốn hủy)')

if (Test-Path -LiteralPath $Out) {
    $old = $Out + '_cu_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
    try { Rename-Item -LiteralPath $Out -NewName (Split-Path -Leaf $old) -ErrorAction Stop; Info "Bản sao lưu cũ được đổi tên thành: $(Split-Path -Leaf $old)" }
    catch { Fail "Không đổi tên được thư mục sao lưu cũ ($($_.Exception.Message)). Hãy đóng các cửa sổ đang mở thư mục đó rồi chạy lại."; return }
}
Ensure-Dir $Out
try { Start-Transcript -Path (Join-Path $Out 'nhat-ky-xuat.txt') -Force | Out-Null } catch {}

Export-Wifi
Export-Printers
Export-Claude

$osName = ''
try { $osName = (Get-CimInstance Win32_OperatingSystem).Caption } catch {}
Save-Json ([pscustomobject]@{
    Version = 1; Date = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Computer = $env:COMPUTERNAME
    UserName = $env:USERNAME; UserProfile = $env:USERPROFILE; Windows = $osName
    Wifi = $Stat.Wifi; Printers = $Stat.Printers; Drivers = $Stat.Drivers; Claude = $Stat.Claude
}) (Join-Path $Out 'thong-tin.json')

$guide = @"
HƯỚNG DẪN KHÔI PHỤC SAU KHI CÀI LẠI WINDOWS
==========================================
Sao lưu lúc: $(Get-Date -Format 'dd/MM/yyyy HH:mm') - máy: $env:COMPUTERNAME - người dùng: $env:USERNAME

0. TRƯỚC khi cài Win: tự chép các thư mục dự án/tài liệu của bạn trên ổ C (Desktop, Documents...;
   danh sách thư mục Claude từng làm việc nằm trong Claude\thu-muc-du-an.txt) sang USB/ổ D.
   Cài xong chép về ĐÚNG chỗ cũ để lịch sử phiên Claude mở lại được.
1. Để thư mục DuLieu_SaoLuu nằm CÙNG CHỖ với file 2_NHAP_DU_LIEU.bat (ví dụ cùng trong USB).
2. Cài Windows xong, nên đặt tên tài khoản giống cũ ($env:USERNAME) - nếu khác, script tự sửa đường dẫn cho Claude.
3. Cài driver Wi-Fi (thường Windows tự cài).
4. (Nên làm) Cài Claude Desktop từ https://claude.ai/download -> mở, đăng nhập -> THOÁT HẲN
   (chuột phải biểu tượng Claude ở khay đồng hồ -> Quit).
5. Nhấp đúp 2_NHAP_DU_LIEU.bat -> bấm Yes -> chọn [1] Khôi phục tất cả.
   Nếu lúc đó chưa cài Claude: cứ chạy, sau khi cài Claude chạy lại và chọn [4].
6. Máy in USB: cắm cáp vào, Windows tự nhận (driver đã được cài sẵn).

HỘI THOẠI TAB CODE CỦA CLAUDE: được khôi phục vào ứng dụng ở bước 5 (chép thư mục dự án về đúng
chỗ cũ TRƯỚC khi mở Claude). Ngoài ra còn có bản đọc được của từng cuộc hội thoại:
Claude\HoiThoai-Code\index.html (nhấp đúp mở bằng trình duyệt, không cần cài gì).

BẢO MẬT: thư mục WiFi chứa mật khẩu Wi-Fi dạng chữ thường. Khôi phục xong nên xóa bản sao lưu
hoặc cất USB cẩn thận. Token đăng nhập Claude KHÔNG được sao lưu (chỉ cần đăng nhập lại).
"@
Save-Text (Join-Path $Out 'HUONG_DAN.txt') ($guide -replace "(?<!`r)`n", "`r`n")

Head 'HOÀN TẤT'
$total = Get-Size $Out
Write-Host ("  Wi-Fi     : {0} mạng" -f $Stat.Wifi) -ForegroundColor White
Write-Host ("  Máy in    : {0} máy in, {1} driver" -f $Stat.Printers, $Stat.Drivers) -ForegroundColor White
Write-Host ("  Claude    : {0}" -f $(if ($Stat.Claude) { 'đã sao lưu' } else { 'không có dữ liệu' })) -ForegroundColor White
if ($Stat.Code -gt 0) { Write-Host ("  Hội thoại Code: {0}/{1} cuộc (bản đọc được: Claude\HoiThoai-Code\index.html)" -f $Stat.CodeOk, $Stat.Code) -ForegroundColor White }
Write-Host ("  Dung lượng: {0}" -f (Fmt-Size $total)) -ForegroundColor White
Write-Host ("  Thư mục   : {0}" -f $Out) -ForegroundColor White
if ($Warnings.Count -gt 0) {
    Write-Host ''
    Write-Host "  Có $($Warnings.Count) lưu ý:" -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "   - $w" -ForegroundColor Yellow }
}
Write-Host ''
Write-Host '  BƯỚC TIẾP THEO:' -ForegroundColor Cyan
if ($Out.Length -ge 2 -and $Out.Substring(0, 2) -ieq $env:SystemDrive) {
    Write-Host "   * CHÉP thư mục DuLieu_SaoLuu + 2 file .bat sang USB/ổ D NGAY (ổ $($env:SystemDrive) sẽ bị xóa)!" -ForegroundColor Red
}
Write-Host '   * Đọc file HUONG_DAN.txt trong thư mục sao lưu.' -ForegroundColor Cyan
Write-Host '   * Sau khi cài lại Win: chạy 2_NHAP_DU_LIEU.bat (để cạnh thư mục DuLieu_SaoLuu).' -ForegroundColor Cyan
try { Stop-Transcript | Out-Null } catch {}
