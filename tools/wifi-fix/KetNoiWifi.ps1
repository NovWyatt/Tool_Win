<#
  Kết nối Wi-Fi: sửa lỗi "Can't connect to this network" khi vào mạng Wi-Fi mới.

  Không có -Mode: hiện menu (bấm đúp KET_NOI_WIFI.bat). -Mode <chế độ>: chạy thẳng (Trạm Tool dùng cách này).
  Chế độ: ket-noi, chan-doan (chỉ đọc), khoi-dong-lai, cap-nhat-driver.
  -TenMang: tên mạng (SSID) cần vào; trống thì chọn trong danh sách. Mật khẩu luôn gõ trong cửa sổ này, không đi qua Trạm.
  -ChayThu: chỉ xem sẽ làm gì, không đổi máy. Báo cáo chẩn đoán nằm trong ket_qua\.
  Mã thoát: 0 xong, 1 lỗi, 2 thiếu điều kiện (quyền Admin, không có card Wi-Fi), 3 làm được một phần.

  Lỗi hay gặp: sau khi máy thức dậy từ chế độ ngủ, Windows tự kết nối bị treo (chưa kịp bắt tay với router). Bấm vào
  mạng khác lúc đó thì vào được nhưng bị ngắt ngay để quay lại lần tự kết nối đang treo, nên hiện "Can't connect to this
  network". Đang có mạng sẵn rồi chuyển sang mạng mới thì không bị. Nút Kết nối Wi-Fi tạm dừng tự kết nối trong lúc
  kết nối, khởi động lại card nếu đang kẹt, rồi bật lại tự kết nối.
#>
param(
    [string]$Mode = '',
    [string]$TenMang = '',   # ket-noi: tên mạng Wi-Fi (SSID)
    [switch]$ChayThu,
    [switch]$KhongDung       # không chờ Enter khi xong (chạy tự động)
)

$ErrorActionPreference = 'Stop'
$script:ToolDir = $PSScriptRoot
$script:MainScript = $PSCommandPath
$script:ToolVersion = '1.1'
$script:NoPause = [bool]$KhongDung
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Report = New-Object System.Collections.Generic.List[string]
$script:Findings = New-Object System.Collections.ArrayList
$script:WlanLog = 'Microsoft-Windows-WLAN-AutoConfig/Operational'
$script:IntelUrl = 'https://www.intel.com/content/www/us/en/download/19351/intel-wireless-wi-fi-drivers-for-windows-10-and-windows-11.html'

# No: số trong menu. Admin: yes (cần), no (không cần).
$script:Modes = [ordered]@{
    'ket-noi'         = @{ No = 1; Label = 'Kết nối Wi-Fi (sửa lỗi Can''t connect to this network)'; Admin = 'yes' }
    'chan-doan'       = @{ No = 2; Label = 'Xem vì sao không kết nối được (chỉ đọc)'; Admin = 'no' }
    'khoi-dong-lai'   = @{ No = 3; Label = 'Khởi động lại Wi-Fi'; Admin = 'yes' }
    'cap-nhat-driver' = @{ No = 4; Label = 'Cập nhật driver Wi-Fi (sửa tận gốc)'; Admin = 'no' }
}

# ---------------------------------------------------------------- API Wi-Fi của Windows (wlanapi.dll)
# Gọi thẳng API thay vì đọc chữ của netsh: chạy đúng trên Windows mọi ngôn ngữ, và hồ sơ Wi-Fi (có mật khẩu) đi từ bộ
# nhớ vào Windows, không ghi ra file tạm.
if (-not ('TramTool.Wlan' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace TramTool
{
    public class WlanNetwork
    {
        public string Profile; public string Ssid; public int Signal; public bool Secure;
        public int Auth; public int Cipher; public bool Connected; public bool HasProfile;
    }

    public class WlanInterface { public Guid Id; public string Description; public int State; }

    public static class Wlan
    {
        [DllImport("wlanapi.dll")] static extern int WlanOpenHandle(int clientVersion, IntPtr reserved, out int negotiatedVersion, out IntPtr handle);
        [DllImport("wlanapi.dll")] static extern int WlanCloseHandle(IntPtr handle, IntPtr reserved);
        [DllImport("wlanapi.dll")] static extern void WlanFreeMemory(IntPtr memory);
        [DllImport("wlanapi.dll")] static extern int WlanEnumInterfaces(IntPtr handle, IntPtr reserved, out IntPtr list);
        [DllImport("wlanapi.dll")] static extern int WlanScan(IntPtr handle, ref Guid iface, IntPtr ssid, IntPtr ie, IntPtr reserved);
        [DllImport("wlanapi.dll")] static extern int WlanGetAvailableNetworkList(IntPtr handle, ref Guid iface, int flags, IntPtr reserved, out IntPtr list);
        [DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] static extern int WlanSetProfile(IntPtr handle, ref Guid iface, int flags, string xml, string security, bool overwrite, IntPtr reserved, out int reason);
        [DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] static extern int WlanDeleteProfile(IntPtr handle, ref Guid iface, string name, IntPtr reserved);
        [DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] static extern int WlanConnect(IntPtr handle, ref Guid iface, ref ConnectionParameters parameters, IntPtr reserved);
        [DllImport("wlanapi.dll")] static extern int WlanDisconnect(IntPtr handle, ref Guid iface, IntPtr reserved);
        [DllImport("wlanapi.dll")] static extern int WlanQueryInterface(IntPtr handle, ref Guid iface, int opcode, IntPtr reserved, out int size, out IntPtr data, out int valueType);
        [DllImport("wlanapi.dll")] static extern int WlanSetInterface(IntPtr handle, ref Guid iface, int opcode, int size, IntPtr data, IntPtr reserved);
        [DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] static extern int WlanReasonCodeToString(int reason, int size, StringBuilder text, IntPtr reserved);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct ConnectionParameters
        {
            public int Mode;
            [MarshalAs(UnmanagedType.LPWStr)] public string Profile;
            public IntPtr Ssid;
            public IntPtr Bssids;
            public int BssType;
            public int Flags;
        }

        static IntPtr Open()
        {
            int version; IntPtr handle;
            Check(WlanOpenHandle(2, IntPtr.Zero, out version, out handle));
            return handle;
        }

        static void Check(int r) { if (r != 0) throw new Win32Exception(r); }

        static string ReadSsid(IntPtr p, int offset)
        {
            int len = Marshal.ReadInt32(p, offset);
            if (len <= 0 || len > 32) return "";
            byte[] b = new byte[len];
            Marshal.Copy(new IntPtr(p.ToInt64() + offset + 4), b, 0, len);
            try { return new UTF8Encoding(false, true).GetString(b); }
            catch (ArgumentException) { return Encoding.Default.GetString(b); }
        }

        // WLAN_INTERFACE_INFO: GUID (16) + mô tả WCHAR[256] (512) + trạng thái (4) = 532 byte.
        public static List<WlanInterface> Interfaces()
        {
            IntPtr h = Open(); IntPtr list = IntPtr.Zero;
            try
            {
                Check(WlanEnumInterfaces(h, IntPtr.Zero, out list));
                int n = Marshal.ReadInt32(list, 0);
                List<WlanInterface> result = new List<WlanInterface>();
                for (int i = 0; i < n; i++)
                {
                    IntPtr p = new IntPtr(list.ToInt64() + 8 + (long)i * 532);
                    WlanInterface w = new WlanInterface();
                    w.Id = (Guid)Marshal.PtrToStructure(p, typeof(Guid));
                    w.Description = Marshal.PtrToStringUni(new IntPtr(p.ToInt64() + 16));
                    w.State = Marshal.ReadInt32(p, 528);
                    result.Add(w);
                }
                return result;
            }
            finally { if (list != IntPtr.Zero) WlanFreeMemory(list); WlanCloseHandle(h, IntPtr.Zero); }
        }

        public static void Scan(Guid iface)
        {
            IntPtr h = Open();
            try { Check(WlanScan(h, ref iface, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero)); }
            finally { WlanCloseHandle(h, IntPtr.Zero); }
        }

        // WLAN_AVAILABLE_NETWORK: 628 byte; tên hồ sơ ở 0, SSID ở 512, tín hiệu 604, bảo mật 608/612/616, cờ 620.
        public static List<WlanNetwork> Networks(Guid iface)
        {
            IntPtr h = Open(); IntPtr list = IntPtr.Zero;
            try
            {
                Check(WlanGetAvailableNetworkList(h, ref iface, 0, IntPtr.Zero, out list));
                int n = Marshal.ReadInt32(list, 0);
                List<WlanNetwork> result = new List<WlanNetwork>();
                for (int i = 0; i < n; i++)
                {
                    IntPtr p = new IntPtr(list.ToInt64() + 8 + (long)i * 628);
                    WlanNetwork w = new WlanNetwork();
                    w.Profile = Marshal.PtrToStringUni(p);
                    w.Ssid = ReadSsid(p, 512);
                    w.Signal = Marshal.ReadInt32(p, 604);
                    w.Secure = Marshal.ReadInt32(p, 608) != 0;
                    w.Auth = Marshal.ReadInt32(p, 612);
                    w.Cipher = Marshal.ReadInt32(p, 616);
                    int flags = Marshal.ReadInt32(p, 620);
                    w.Connected = (flags & 1) != 0;
                    w.HasProfile = (flags & 2) != 0;
                    result.Add(w);
                }
                return result;
            }
            finally { if (list != IntPtr.Zero) WlanFreeMemory(list); WlanCloseHandle(h, IntPtr.Zero); }
        }

        static int QueryInt(Guid iface, int opcode)
        {
            IntPtr h = Open(); IntPtr data = IntPtr.Zero;
            try
            {
                int size, type;
                Check(WlanQueryInterface(h, ref iface, opcode, IntPtr.Zero, out size, out data, out type));
                return Marshal.ReadInt32(data);
            }
            finally { if (data != IntPtr.Zero) WlanFreeMemory(data); WlanCloseHandle(h, IntPtr.Zero); }
        }

        // 1 đã kết nối, 4 chưa kết nối, 5 đang liên kết, 6 đang dò, 7 đang xác thực, 0 chưa sẵn sàng.
        public static int State(Guid iface) { return QueryInt(iface, 6); }

        // Tự kết nối (WLAN AutoConfig) của card đang bật hay tắt.
        public static bool GetAutoConfig(Guid iface) { return QueryInt(iface, 1) != 0; }

        public static void SetAutoConfig(Guid iface, bool enabled)
        {
            IntPtr h = Open(); IntPtr p = Marshal.AllocHGlobal(4);
            try { Marshal.WriteInt32(p, enabled ? 1 : 0); Check(WlanSetInterface(h, ref iface, 1, 4, p, IntPtr.Zero)); }
            finally { Marshal.FreeHGlobal(p); WlanCloseHandle(h, IntPtr.Zero); }
        }

        // Tên mạng đang kết nối, null khi chưa kết nối. WLAN_CONNECTION_ATTRIBUTES: SSID ở byte 520.
        public static string CurrentSsid(Guid iface)
        {
            IntPtr h = Open(); IntPtr data = IntPtr.Zero;
            try
            {
                int size, type;
                int r = WlanQueryInterface(h, ref iface, 7, IntPtr.Zero, out size, out data, out type);
                if (r == 5) throw new Win32Exception(r);
                if (r != 0 || Marshal.ReadInt32(data, 0) != 1) return null;
                return ReadSsid(data, 520);
            }
            finally { if (data != IntPtr.Zero) WlanFreeMemory(data); WlanCloseHandle(h, IntPtr.Zero); }
        }

        public static void SetProfile(Guid iface, string xml)
        {
            IntPtr h = Open();
            try
            {
                int reason;
                int r = WlanSetProfile(h, ref iface, 0, xml, null, true, IntPtr.Zero, out reason);
                if (r != 0)
                {
                    string why = ReasonText(reason);
                    string msg = new Win32Exception(r).Message;
                    throw new Win32Exception(r, string.IsNullOrEmpty(why) ? msg : why + " (" + msg + ")");
                }
            }
            finally { WlanCloseHandle(h, IntPtr.Zero); }
        }

        public static void DeleteProfile(Guid iface, string name)
        {
            IntPtr h = Open();
            try { Check(WlanDeleteProfile(h, ref iface, name, IntPtr.Zero)); }
            finally { WlanCloseHandle(h, IntPtr.Zero); }
        }

        public static string ReasonText(int reason)
        {
            StringBuilder sb = new StringBuilder(1024);
            if (WlanReasonCodeToString(reason, sb.Capacity, sb, IntPtr.Zero) == 0) return sb.ToString();
            return null;
        }

        public static void Connect(Guid iface, string profile)
        {
            IntPtr h = Open();
            try
            {
                ConnectionParameters p = new ConnectionParameters();
                p.Mode = 0; p.Profile = profile; p.Ssid = IntPtr.Zero; p.Bssids = IntPtr.Zero; p.BssType = 1; p.Flags = 0;
                Check(WlanConnect(h, ref iface, ref p, IntPtr.Zero));
            }
            finally { WlanCloseHandle(h, IntPtr.Zero); }
        }

        public static void Disconnect(Guid iface)
        {
            IntPtr h = Open();
            try { Check(WlanDisconnect(h, ref iface, IntPtr.Zero)); }
            finally { WlanCloseHandle(h, IntPtr.Zero); }
        }
    }
}
'@
}

# ---------------------------------------------------------------- in ra màn hình (và báo cáo)
function Write-Out {
    param([string]$Text = '', [string]$Color = '')
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
    [void]$script:Report.Add($Text)
}
function Write-Head { param([string]$Text) Write-Out ''; Write-Out ("== $Text " + ('=' * [Math]::Max(3, 68 - $Text.Length))) 'Cyan' }
function Write-Line { param([string]$Text) Write-Out "  $Text" }
function Write-Sub { param([string]$Text) Write-Out "       $Text" 'Gray' }
function Write-Ok { param([string]$Text) Write-Out "  [OK] $Text" 'Green' }
function Write-Warn { param([string]$Text) Write-Out "  [!]  $Text" 'Yellow' }
function Write-Bad { param([string]$Text) Write-Out "  [X]  $Text" 'Red' }
function Write-Info { param([string]$Text) Write-Out "  [i]  $Text" 'Gray' }
function Write-Plan { param([string]$Text) Write-Out "   ->  $Text" 'White' }

function Add-Finding {
    param([ValidateSet('bad', 'warn', 'info')][string]$Level, [string]$Text, [string]$Fix = '', [string]$Hint = '')
    [void]$script:Findings.Add([pscustomobject]@{ Level = $Level; Text = $Text; Fix = $Fix; Hint = $Hint })
    switch ($Level) { 'bad' { Write-Bad $Text } 'warn' { Write-Warn $Text } default { Write-Info $Text } }
    if ($Hint) { Write-Sub $Hint }
}

# ---------------------------------------------------------------- hỏi người dùng
function Read-Text {
    param([string]$Prompt, [string]$Default = '')
    if ([Console]::IsInputRedirected) { return $Default }
    $a = ([string](Read-Host "  $Prompt")).Trim()
    if (-not $a) { return $Default }
    return $a
}

function Read-YesNo {
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

function Read-Number {
    param([string]$Prompt, [int]$Min, [int]$Max, $Default = $null)
    if ([Console]::IsInputRedirected) { return $Default }
    while ($true) {
        $a = ([string](Read-Host "  $Prompt")).Trim()
        if (-not $a) { return $Default }
        $n = 0
        if ([int]::TryParse($a, [ref]$n) -and $n -ge $Min -and $n -le $Max) { return $n }
        Write-Host "  Gõ một số từ $Min đến $Max." -ForegroundColor Yellow
    }
}

function Wait-Close {
    param([string]$Text = 'Bấm Enter để đóng cửa sổ')
    if ($script:NoPause -or [Console]::IsInputRedirected) { return }
    Write-Host ''
    [void](Read-Host "  $Text")
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ResultDir {
    $d = Join-Path $script:ToolDir 'ket_qua'
    try {
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -ErrorAction Stop) }
        return $d
    } catch {
        $d = Join-Path ([Environment]::GetFolderPath('Desktop')) 'WiFi_ket_qua'
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d) }
        return $d
    }
}

function Get-WinErrorCode {
    param($ErrorRecord)
    $e = $ErrorRecord.Exception
    while ($e) { if ($e -is [ComponentModel.Win32Exception]) { return $e.NativeErrorCode }; $e = $e.InnerException }
    return 0
}

# ---------------------------------------------------------------- card Wi-Fi
$script:StateText = @{ '0' = 'chưa sẵn sàng'; '1' = 'đã kết nối'; '3' = 'đang ngắt'; '4' = 'chưa kết nối'; '5' = 'đang kết nối'; '6' = 'đang dò mạng'; '7' = 'đang xác thực' }

function Get-WifiAdapter {
    # Card Wi-Fi thật (không lấy card ảo Wi-Fi Direct). Nhiều card thì ưu tiên card Windows đang quản lý, đang kết nối.
    $wl = @()
    try { $wl = @([TramTool.Wlan]::Interfaces()) } catch { }
    $nics = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.NdisPhysicalMedium -eq 9 })
    $pick = $null
    foreach ($n in $nics) {
        $g = [Guid]$n.InterfaceGuid
        $date = $null
        try { $date = [datetime]$n.DriverDate } catch { }
        $o = [pscustomobject]@{
            Name = $n.Name; Guid = $g; Description = $n.InterfaceDescription; Status = [string]$n.Status
            DriverVersion = [string]$n.DriverVersion; DriverDate = $date; IfIndex = $n.ifIndex
            Wlan = [bool](@($wl | Where-Object { $_.Id -eq $g }).Count)
        }
        if (-not $pick -or ($o.Wlan -and -not $pick.Wlan) -or ($o.Status -eq 'Up' -and $pick.Status -ne 'Up')) { $pick = $o }
    }
    return $pick
}

function Get-DriverAgeMonths {
    param($Adapter)
    if (-not $Adapter.DriverDate) { return $null }
    $d = (Get-Date) - $Adapter.DriverDate
    return [int][Math]::Floor($d.TotalDays / 30.4)
}

function Get-WifiState {
    # Trạng thái và tên mạng đang kết nối. Ssid $null: chưa kết nối hoặc không đọc được (quyền thường khi tắt Location).
    param([Guid]$Id)
    $s = [ordered]@{ State = -1; Ssid = $null; Readable = $true }
    try { $s.State = [TramTool.Wlan]::State($Id) } catch { }
    try { $s.Ssid = [TramTool.Wlan]::CurrentSsid($Id) } catch { $s.Readable = $false }
    return [pscustomobject]$s
}

function Confirm-AutoConfig {
    # Tự kết nối Wi-Fi phải đang bật: lần trước lỡ đóng cửa sổ giữa lúc công cụ tạm tắt thì bật lại ở đây.
    param([Guid]$Id, [switch]$DryRun)
    try { $on = [TramTool.Wlan]::GetAutoConfig($Id) } catch { Write-Info "Không đọc được trạng thái tự kết nối: $($_.Exception.Message)"; return $true }
    if ($on) { return $true }
    Write-Warn 'Tự kết nối Wi-Fi (WLAN AutoConfig) đang tắt: Windows không tự vào mạng đã lưu.'
    if ($DryRun) { Write-Plan 'Bật lại tự kết nối Wi-Fi'; return $true }
    try { [TramTool.Wlan]::SetAutoConfig($Id, $true); Write-Ok 'Đã bật lại tự kết nối Wi-Fi.'; return $true }
    catch { Write-Bad "Không bật lại được tự kết nối: $($_.Exception.Message)"; return $false }
}

function Restart-WifiAdapter {
    # Tắt rồi bật card: driver khởi tạo lại như lúc mới mở máy, xoá trạng thái kẹt sau khi máy thức dậy.
    param($Adapter, [switch]$DryRun)
    $t = "Khởi động lại card Wi-Fi '$($Adapter.Name)' (mất mạng vài giây)"
    if ($DryRun) { Write-Plan $t; return $true }
    Write-Info "$t..."
    try {
        if ($Adapter.Status -eq 'Disabled') { Enable-NetAdapter -Name $Adapter.Name -Confirm:$false -ErrorAction Stop }
        else { Restart-NetAdapter -Name $Adapter.Name -Confirm:$false -ErrorAction Stop }
    } catch { Write-Bad "Không khởi động lại được card: $($_.Exception.Message.Trim())"; return $false }
    if (Wait-WlanReady $Adapter.Guid 25) { Write-Ok 'Đã khởi động lại card Wi-Fi.'; return $true }
    # Card đã bật mà dịch vụ Wi-Fi không thấy: khởi động lại dịch vụ WLAN AutoConfig.
    Write-Warn 'Dịch vụ Wi-Fi chưa thấy lại card: khởi động lại dịch vụ WLAN AutoConfig.'
    try { Restart-Service -Name WlanSvc -Force -ErrorAction Stop } catch { Write-Bad "Không khởi động lại được dịch vụ: $($_.Exception.Message.Trim())"; return $false }
    if (Wait-WlanReady $Adapter.Guid 25) { Write-Ok 'Đã khởi động lại dịch vụ Wi-Fi.'; return $true }
    Write-Bad 'Card Wi-Fi chưa sẵn sàng sau khi khởi động lại. Khởi động lại máy (Restart, không phải Shut down).'
    return $false
}

function Wait-WlanReady {
    param([Guid]$Id, [int]$Seconds = 25)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
        Start-Sleep -Milliseconds 700
        try {
            $i = @([TramTool.Wlan]::Interfaces() | Where-Object { $_.Id -eq $Id })
            if ($i.Count -and $i[0].State -ne 0) { return $true }
        } catch { }
    }
    return $false
}

# ---------------------------------------------------------------- mạng xung quanh, hồ sơ Wi-Fi
function Get-SecurityInfo {
    # Kiểu bảo mật của mạng → cách ghi trong hồ sơ Wi-Fi của Windows. Supported $false: công cụ không tự tạo hồ sơ được.
    # Auth: 1 mở, 4 WPA-PSK, 7 WPA2-PSK, 9 WPA3-SAE, 10 OWE, 3/6/8/11 doanh nghiệp. Cipher: 0 không, 2 TKIP, 4 CCMP.
    param([int]$Auth, [int]$Cipher)
    $enc = if ($Cipher -eq 2) { 'TKIP' } else { 'AES' }
    switch ($Auth) {
        1 {
            if ($Cipher -eq 0) { return @{ Text = 'mở, không mật khẩu'; Auth = 'open'; Enc = 'none'; Key = $false; Supported = $true } }
            return @{ Text = 'WEP (rất cũ)'; Supported = $false }
        }
        4 { return @{ Text = 'WPA'; Auth = 'WPAPSK'; Enc = $enc; Key = $true; Supported = $true } }
        7 { return @{ Text = 'WPA2'; Auth = 'WPA2PSK'; Enc = $enc; Key = $true; Supported = $true } }
        9 { return @{ Text = 'WPA3'; Auth = 'WPA3SAE'; Enc = 'AES'; Key = $true; Supported = $true } }
        10 { return @{ Text = 'mở, có mã hoá (OWE)'; Auth = 'OWE'; Enc = 'AES'; Key = $false; Supported = $true } }
        { $_ -in 3, 6, 8, 11 } { return @{ Text = 'doanh nghiệp (tài khoản, chứng chỉ)'; Supported = $false } }
    }
    return @{ Text = "loại $Auth"; Supported = $false }
}

function Get-VisibleNetworks {
    # Mạng quanh đây, mỗi tên một dòng: đang kết nối trước, rồi theo độ mạnh. Quét mới rồi chờ vài giây.
    param([Guid]$Id, [int]$WaitSeconds = 4)
    try { [TramTool.Wlan]::Scan($Id) } catch { }
    Start-Sleep -Seconds $WaitSeconds
    $by = @{}
    $order = New-Object System.Collections.Generic.List[string]
    foreach ($n in @([TramTool.Wlan]::Networks($Id))) {
        if (-not $n.Ssid) { continue }   # mạng ẩn: người dùng gõ tên
        if (-not $by.ContainsKey($n.Ssid)) {
            $by[$n.Ssid] = [pscustomobject]@{ Ssid = $n.Ssid; Signal = $n.Signal; Auth = $n.Auth; Cipher = $n.Cipher; Profile = ''; Connected = $false; Hidden = $false }
            $order.Add($n.Ssid)
        }
        $e = $by[$n.Ssid]
        if ($n.Signal -gt $e.Signal) { $e.Signal = $n.Signal }
        if ($n.HasProfile -and -not $e.Profile) { $e.Profile = $n.Profile }
        if ($n.Connected) { $e.Connected = $true }
    }
    $list = foreach ($k in $order) { $by[$k] }
    return @($list | Sort-Object @{ Expression = 'Connected'; Descending = $true }, @{ Expression = 'Signal'; Descending = $true })
}

function New-HiddenNetwork {
    param([string]$Ssid)
    $c = Read-Number 'Kiểu bảo mật: 1 = WPA2 (thường gặp), 2 = WPA3, 3 = không mật khẩu (Enter = 1)' 1 3 1
    $auth = @{ 1 = 7; 2 = 9; 3 = 1 }[[int]$c]
    return [pscustomobject]@{ Ssid = $Ssid; Signal = 0; Auth = $auth; Cipher = $(if ($auth -eq 1) { 0 } else { 4 }); Profile = ''; Connected = $false; Hidden = $true }
}

function Select-WifiNetwork {
    param($Networks, [string]$TenMang)
    $nets = @($Networks)
    if ($TenMang) {
        $m = @($nets | Where-Object { $_.Ssid -ceq $TenMang })
        if (-not $m) { $m = @($nets | Where-Object { $_.Ssid -eq $TenMang }) }
        if ($m) { return $m[0] }
        Write-Warn "Không thấy mạng '$TenMang' quanh đây (sai tên, ở xa, hoặc mạng ẩn)."
        if (-not (Read-YesNo 'Vẫn thử kết nối như mạng ẩn (không phát tên)?' $false)) { return $null }
        return (New-HiddenNetwork $TenMang)
    }
    $show = @($nets | Select-Object -First 25)
    if ($show.Count) {
        Write-Line 'Mạng Wi-Fi quanh đây:'
        for ($i = 0; $i -lt $show.Count; $i++) {
            $n = $show[$i]
            $s = Get-SecurityInfo $n.Auth $n.Cipher
            $tag = if ($n.Connected) { '  (đang kết nối)' } elseif ($n.Profile) { '  (đã lưu)' } else { '' }
            Write-Host ('   {0,2}. {1,-30} {2,3}%  {3}{4}' -f ($i + 1), $n.Ssid, $n.Signal, $s.Text, $tag)
        }
    } else {
        Write-Warn 'Không thấy mạng Wi-Fi nào quanh đây.'
    }
    $c = Read-Text 'Chọn số mạng (hoặc gõ tên nếu là mạng ẩn; Enter để thoát)'
    if (-not $c) { return $null }
    $k = 0
    if ([int]::TryParse($c, [ref]$k) -and $k -ge 1 -and $k -le $show.Count) { return $show[$k - 1] }
    $m = @($nets | Where-Object { $_.Ssid -eq $c })
    if ($m) { return $m[0] }
    if ([Text.Encoding]::UTF8.GetByteCount($c) -gt 32) { Write-Bad 'Tên mạng Wi-Fi dài tối đa 32 byte.'; return $null }
    return (New-HiddenNetwork $c)
}

function New-WifiProfileXml {
    # Hồ sơ Wi-Fi giống hồ sơ Windows tạo khi bấm "Connect automatically". Mật khẩu ghi dạng chữ trong XML (protected =
    # false), Windows mã hoá khi lưu.
    param([string]$Ssid, $Security, [string]$Key, [bool]$Hidden)
    $name = [Security.SecurityElement]::Escape($Ssid)
    $hex = -join ([Text.Encoding]::UTF8.GetBytes($Ssid) | ForEach-Object { $_.ToString('X2') })
    $auth = '<authEncryption><authentication>{0}</authentication><encryption>{1}</encryption><useOneX>false</useOneX></authEncryption>' -f $Security.Auth, $Security.Enc
    $shared = ''
    if ($Security.Key) {
        $type = if ($Key -match '^[0-9A-Fa-f]{64}$') { 'networkKey' } else { 'passPhrase' }
        $shared = '<sharedKey><keyType>{0}</keyType><protected>false</protected><keyMaterial>{1}</keyMaterial></sharedKey>' -f $type, [Security.SecurityElement]::Escape($Key)
    }
    $nonBroadcast = if ($Hidden) { '<nonBroadcast>true</nonBroadcast>' } else { '' }
    return ('<?xml version="1.0"?><WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"><name>{0}</name>' +
        '<SSIDConfig><SSID><hex>{1}</hex><name>{0}</name></SSID>{2}</SSIDConfig><connectionType>ESS</connectionType>' +
        '<connectionMode>auto</connectionMode><MSM><security>{3}{4}</security></MSM></WLANProfile>') -f $name, $hex, $nonBroadcast, $auth, $shared
}

function Read-WifiKey {
    # Mật khẩu gõ trong cửa sổ này, không hiện chữ. Trả $null khi huỷ.
    param([string]$Ssid)
    for ($t = 1; $t -le 3; $t++) {
        if ([Console]::IsInputRedirected) { return $null }
        $sec = Read-Host ("  Mật khẩu Wi-Fi '{0}' (gõ không hiện chữ; Enter để huỷ)" -f $Ssid) -AsSecureString
        $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { $k = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
        if (-not $k) { return $null }
        if (($k.Length -ge 8 -and $k.Length -le 63) -or $k -match '^[0-9A-Fa-f]{64}$') {
            Write-Info ('Đã nhận mật khẩu {0} ký tự.' -f $k.Length)
            return $k
        }
        Write-Warn ('Mật khẩu Wi-Fi dài 8 đến 63 ký tự; vừa gõ {0} ký tự.' -f $k.Length)
    }
    return $null
}

function Wait-WifiConnected {
    # Chờ vào được mạng $Ssid. Thấy đang thử rồi về "chưa kết nối" thì dừng sớm.
    param([Guid]$Id, [string]$Ssid, [int]$Seconds = 30)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $trying = $false
    while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
        Start-Sleep -Milliseconds 500
        $s = Get-WifiState $Id
        if ($s.State -eq 1 -and $s.Ssid -eq $Ssid) { return $true }
        if ($s.State -in 5, 6, 7) { $trying = $true }
        elseif ($trying -and $s.State -eq 4 -and $sw.Elapsed.TotalSeconds -gt 3) { return $false }
    }
    return $false
}

function Test-StaysConnected {
    param([Guid]$Id, [string]$Ssid, [int]$Seconds = 10)
    for ($i = 0; $i -lt $Seconds; $i++) {
        Start-Sleep -Seconds 1
        $s = Get-WifiState $Id
        if ($s.State -ne 1 -or $s.Ssid -ne $Ssid) { return $false }
    }
    return $true
}

function Get-EventFields {
    param($Record)
    $x = [xml]$Record.ToXml()
    $d = @{}
    foreach ($n in $x.Event.EventData.Data) { $d[[string]$n.Name] = [string]$n.'#text' }
    return $d
}

function Get-FailureReason {
    # Lý do lần kết nối vừa rồi không được, theo nhật ký WLAN từ $Since: 'sai-mat-khau', 'khong-thay-mang' hoặc ''.
    param([datetime]$Since, [string]$Ssid)
    $ev = @()
    try { $ev = @(Get-WinEvent -FilterHashtable @{ LogName = $script:WlanLog; StartTime = $Since; Id = 8002, 11006 } -ErrorAction Stop) } catch { }
    foreach ($e in $ev) { if ($e.Id -eq 11006 -and (Get-EventFields $e)['SSID'] -eq $Ssid) { return 'sai-mat-khau' } }
    foreach ($e in $ev) { $d = Get-EventFields $e; if ($d['SSID'] -eq $Ssid -and $d['ReasonCode'] -eq '163851') { return 'khong-thay-mang' } }
    return ''
}

function Test-Internet {
    # Có IP (DHCP) chưa, có phân giải tên miền, ra Internet được không.
    param($Adapter)
    $ip = $null
    for ($i = 0; $i -lt 30 -and -not $ip; $i++) {
        $ip = Get-NetIPAddress -InterfaceIndex $Adapter.IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
        if (-not $ip) { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ip) { return 'khong-ip' }
    try { [void](Resolve-DnsName -Name 'www.msftconnecttest.com' -Type A -QuickTimeout -ErrorAction Stop); return 'ok' } catch { }
    if (Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue) { return 'khong-dns' }
    return 'khong-internet'
}

# ---------------------------------------------------------------- chế độ: kết nối Wi-Fi
function Invoke-KetNoi {
    param([string]$TenMang, [switch]$DryRun)
    Write-Head 'Kết nối Wi-Fi'
    $a = Get-WifiAdapter
    if (-not $a) { Write-Bad 'Không thấy card Wi-Fi (chưa cài driver, hoặc card đang tắt trong Device Manager).'; return 2 }
    Write-Line ('Card: {0} ({1}), driver {2}' -f $a.Description, $a.Name, $a.DriverVersion)
    $id = $a.Guid
    if (-not (Confirm-AutoConfig $id -DryRun:$DryRun)) { return 1 }

    # 1. Chưa vào được mạng nào: khởi động lại card để xoá lần tự kết nối đang treo. Đang có mạng thì không cần.
    $now = Get-WifiState $id
    if ($now.State -eq 1) { Write-Info ('Đang kết nối {0}.' -f $(if ($now.Ssid) { "'$($now.Ssid)'" } else { 'một mạng' })) }
    elseif (-not (Restart-WifiAdapter $a -DryRun:$DryRun)) { return 1 }

    # 2. Chọn mạng.
    $nets = @()
    try { $nets = @(Get-VisibleNetworks $id) }
    catch {
        if ((Get-WinErrorCode $_) -eq 5) { Write-Info 'Không đọc được danh sách mạng khi chạy quyền thường (Location đang tắt). Chạy thật có quyền Admin sẽ đọc được.' }
        else { Write-Warn "Không đọc được danh sách mạng: $($_.Exception.Message.Trim())" }
    }
    if ($DryRun -and -not $nets.Count) {
        Write-Plan $(if ($TenMang) { "Kết nối mạng '$TenMang', hỏi mật khẩu nếu là mạng mới" } else { 'Hiện danh sách mạng để chọn, hỏi mật khẩu nếu là mạng mới' })
        Write-Plan 'Tạm tắt tự kết nối Wi-Fi, kết nối mạng đã chọn, rồi bật lại tự kết nối'
        Write-Plan 'Kiểm tra mạng giữ được kết nối và ra được Internet'
        return 0
    }
    $net = Select-WifiNetwork $nets $TenMang
    if (-not $net) { Write-Info 'Chưa chọn mạng nào.'; return 0 }
    $sec = Get-SecurityInfo $net.Auth $net.Cipher
    if (-not $sec.Supported) {
        Write-Bad "Mạng '$($net.Ssid)' dùng bảo mật $($sec.Text): công cụ không tự tạo được."
        Write-Sub 'Kết nối bằng biểu tượng Wi-Fi trên thanh tác vụ, hoặc Settings > Network & internet > Wi-Fi.'
        return 2
    }
    if ($net.Connected) { Write-Ok "Đang kết nối sẵn '$($net.Ssid)'."; return 0 }

    # 3. Hồ sơ Wi-Fi: mạng đã lưu dùng mật khẩu đã lưu; mạng mới (hoặc muốn gõ lại) thì hỏi mật khẩu.
    $useSaved = [bool]$net.Profile
    if ($useSaved -and $sec.Key) { $useSaved = -not (Read-YesNo "Mạng '$($net.Ssid)' đã lưu mật khẩu. Gõ lại mật khẩu?" $false) }
    $profileName = if ($useSaved) { $net.Profile } else { $net.Ssid }
    $created = $false

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        if (-not $useSaved) {
            $key = ''
            if ($sec.Key) {
                if ($DryRun) { Write-Plan "Hỏi mật khẩu mạng '$($net.Ssid)' (gõ trong cửa sổ này)" }
                else { $key = Read-WifiKey $net.Ssid; if (-not $key) { Write-Info 'Đã huỷ.'; return 0 } }
            }
            if ($DryRun) { Write-Plan "Lưu mạng '$($net.Ssid)' ($($sec.Text)) vào Windows, tự kết nối lần sau" }
            else {
                $xml = New-WifiProfileXml -Ssid $net.Ssid -Security $sec -Key $key -Hidden $net.Hidden
                try { [TramTool.Wlan]::SetProfile($id, $xml); $created = $true }
                catch { Write-Bad "Không lưu được mạng: $($_.Exception.Message.Trim())"; return 1 }
                finally { $key = $null; $xml = $null }
            }
        }

        # 4. Tạm tắt tự kết nối để không có lần tự kết nối nào chen vào, kết nối, rồi luôn bật lại.
        if ($DryRun) {
            Write-Plan 'Tạm tắt tự kết nối Wi-Fi'
            Write-Plan "Kết nối '$($net.Ssid)' và chờ tối đa 30 giây"
            Write-Plan 'Bật lại tự kết nối Wi-Fi, kiểm tra mạng giữ được kết nối và ra được Internet'
            return 0
        }
        $t0 = Get-Date
        $paused = $false
        $ok = $false
        Write-Info "Đang kết nối '$($net.Ssid)'..."
        try {
            [TramTool.Wlan]::SetAutoConfig($id, $false); $paused = $true
            try { [TramTool.Wlan]::Disconnect($id) } catch { }
            Start-Sleep -Milliseconds 800
            [TramTool.Wlan]::Connect($id, $profileName)
            $ok = Wait-WifiConnected $id $net.Ssid 30
        } catch {
            Write-Bad "Không gửi được lệnh kết nối: $($_.Exception.Message.Trim())"
        } finally {
            if ($paused) {
                try { [TramTool.Wlan]::SetAutoConfig($id, $true) }
                catch { Write-Bad 'Không bật lại được tự kết nối Wi-Fi: chạy "Khởi động lại Wi-Fi".' }
            }
        }
        if ($ok) { break }

        $why = Get-FailureReason $t0 $net.Ssid
        if ($why -eq 'sai-mat-khau' -and $sec.Key) {
            Write-Bad "Router '$($net.Ssid)' không nhận mật khẩu (có thể gõ sai, hoặc router vừa đổi mật khẩu)."
            if ($attempt -lt 3 -and (Read-YesNo 'Gõ lại mật khẩu?' $true)) { $useSaved = $false; $profileName = $net.Ssid; continue }
        } elseif ($why -eq 'khong-thay-mang') {
            Write-Bad "Không thấy mạng '$($net.Ssid)' lúc kết nối: sóng yếu, hoặc router chỉ phát ở băng tần card không hỗ trợ."
        } else {
            Write-Bad "Chưa vào được '$($net.Ssid)' sau 30 giây."
        }
        if ($created -and (Read-YesNo "Xoá mạng '$($net.Ssid)' vừa lưu (để Windows khỏi tự thử mật khẩu sai)?" $true)) {
            try { [TramTool.Wlan]::DeleteProfile($id, $net.Ssid); Write-Ok 'Đã xoá mạng vừa lưu.' } catch { Write-Warn "Không xoá được: $($_.Exception.Message.Trim())" }
        }
        Write-Sub 'Vẫn không được: chạy "Cập nhật driver Wi-Fi", hoặc khởi động lại máy (Restart) rồi thử lại.'
        return 1
    }

    # 5. Bật lại tự kết nối xong, mạng phải còn giữ. Bị ngắt thì thử lại một lần với tự kết nối đang bật.
    Write-Ok "Đã kết nối '$($net.Ssid)'."
    if (-not (Test-StaysConnected $id $net.Ssid 10)) {
        Write-Warn 'Windows vừa ngắt mạng sau khi bật lại tự kết nối: thử kết nối lại.'
        try { [TramTool.Wlan]::Connect($id, $profileName) } catch { }
        if (-not ((Wait-WifiConnected $id $net.Ssid 25) -and (Test-StaysConnected $id $net.Ssid 5))) {
            Write-Bad 'Windows vẫn ngắt mạng: lỗi nằm ở driver Wi-Fi. Chạy "Cập nhật driver Wi-Fi".'
            Write-Sub 'Cách tạm: kết nối một mạng đã lưu trước (vd điểm phát của điện thoại), rồi chuyển sang mạng này.'
            return 1
        }
        Write-Ok "Đã kết nối lại '$($net.Ssid)'."
    }

    # 6. Internet.
    switch (Test-Internet $a) {
        'ok' { Write-Ok 'Ra được Internet.' }
        'khong-ip' { Write-Warn 'Đã vào Wi-Fi nhưng router chưa cấp địa chỉ IP: tắt bật lại router, hoặc router đã đủ người dùng.'; return 3 }
        'khong-dns' { Write-Warn 'Ra được Internet nhưng không phân giải được tên miền (DNS): thử mục 2 của menu cũ (fixwf.bat).'; return 3 }
        default { Write-Warn 'Đã vào Wi-Fi nhưng chưa ra được Internet: mạng có thể cần đăng nhập trên trình duyệt (khách sạn, quán cà phê).'; return 3 }
    }
    $age = Get-DriverAgeMonths $a
    if ($null -ne $age -and $age -ge 12) {
        Write-Info ('Driver Wi-Fi đã {0} tháng tuổi: cập nhật để khỏi phải dùng công cụ này mỗi lần (mục 4).' -f $age)
    }
    return 0
}

# ---------------------------------------------------------------- chế độ: chẩn đoán (chỉ đọc)
function Get-WifiHistory {
    # Đếm theo mã lý do trong nhật ký (không phụ thuộc ngôn ngữ Windows):
    #   treo: 8002 lý do 229377 (bị huỷ) với RSSI 255 (chưa thấy router) - lần tự kết nối kẹt rồi bị huỷ.
    #   ngắt ngay: 8001 (vào được) rồi 8003 lý do 2 ("ngắt bởi người dùng") trong 3 giây.
    #   sai khoá: 11006 (bắt tay mật khẩu không xong). thức dậy lỗi: NDIS 10317 của card ảo Wi-Fi Direct.
    param([int]$Days = 7)
    $since = (Get-Date).AddDays(-$Days)
    $rows = @()
    try {
        $rows = @(Get-WinEvent -FilterHashtable @{ LogName = $script:WlanLog; StartTime = $since; Id = 8001, 8002, 8003, 11006 } -ErrorAction Stop |
                Sort-Object TimeCreated, RecordId | ForEach-Object {
                    $d = Get-EventFields $_
                    [pscustomobject]@{ Time = $_.TimeCreated; Id = $_.Id; Ssid = $d['SSID']; Code = $d['ReasonCode']; Rssi = $d['RSSI'] }
                })
    } catch { }
    $stuck = New-Object System.Collections.ArrayList
    $dropped = New-Object System.Collections.ArrayList
    $keyFail = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]
        if ($r.Id -eq 8002 -and $r.Code -eq '229377' -and $r.Rssi -eq '255') { [void]$stuck.Add($r) }
        elseif ($r.Id -eq 11006) { [void]$keyFail.Add($r) }
        elseif ($r.Id -eq 8001) {
            for ($j = $i + 1; $j -lt $rows.Count -and ($rows[$j].Time - $r.Time).TotalSeconds -le 3; $j++) {
                if ($rows[$j].Id -eq 8003 -and $rows[$j].Code -eq '2') { [void]$dropped.Add($r); break }
            }
        }
    }
    $resume = @()
    try {
        $resume = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since; ProviderName = 'Microsoft-Windows-NDIS'; Id = 10317 } -ErrorAction Stop |
                Where-Object { [string]$_.Message -match 'Wi-?Fi Direct' })
    } catch { }
    return [pscustomobject]@{ Days = $Days; Events = $rows.Count; Stuck = @($stuck); Dropped = @($dropped); KeyFail = @($keyFail); Resume = $resume }
}

function Format-Times {
    param($Items, [int]$Max = 4)
    $t = @($Items | Sort-Object Time -Descending | Select-Object -First $Max | ForEach-Object { $_.Time.ToString('dd/MM HH:mm') })
    return ($t -join ', ')
}

function Invoke-ChanDoan {
    $script:Report.Clear(); $script:Findings.Clear()
    $started = Get-Date
    Write-Out 'BÁO CÁO KẾT NỐI WI-FI' 'Cyan'
    Write-Out ('Máy {0}, {1:dd/MM/yyyy HH:mm}. Công cụ "Kết nối Wi-Fi" {2}: chỉ đọc, không thay đổi gì trên máy.' -f $env:COMPUTERNAME, $started, $script:ToolVersion)

    Write-Head 'Card Wi-Fi'
    $a = Get-WifiAdapter
    if (-not $a) {
        Add-Finding bad 'Không thấy card Wi-Fi: chưa cài driver, card đang tắt trong Device Manager, hoặc máy không có Wi-Fi.'
    } else {
        Write-Line ('{0} ({1}): {2}' -f $a.Description, $a.Name, $(if ($a.Status -eq 'Up') { 'đang có mạng' } elseif ($a.Status -eq 'Disabled') { 'ĐANG TẮT' } else { 'chưa kết nối' }))
        $prof = Get-NetConnectionProfile -InterfaceIndex $a.IfIndex -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($prof) { Write-Line ('Đang vào mạng: {0}' -f $prof.Name) }
        $age = Get-DriverAgeMonths $a
        $dateText = if ($a.DriverDate) { $a.DriverDate.ToString('dd/MM/yyyy') } else { 'không rõ ngày' }
        Write-Line ('Driver {0}, {1}{2}' -f $a.DriverVersion, $dateText, $(if ($null -ne $age) { " ($age tháng trước)" } else { '' }))
        if ($null -ne $age -and $age -ge 12) {
            Add-Finding warn ('Driver Wi-Fi đã cũ ({0} tháng), cũ hơn bản Windows đang chạy.' -f $age) -Fix 'cap-nhat-driver'
        }
        if ($a.Status -eq 'Disabled') { Add-Finding bad 'Card Wi-Fi đang bị tắt.' -Fix 'khoi-dong-lai' }
        try {
            if ([TramTool.Wlan]::GetAutoConfig($a.Guid)) { Write-Line 'Tự kết nối Wi-Fi (WLAN AutoConfig): bật' }
            else { Add-Finding bad 'Tự kết nối Wi-Fi (WLAN AutoConfig) đang tắt: Windows không tự vào mạng đã lưu.' -Fix 'khoi-dong-lai' }
        } catch { Write-Info "Không đọc được trạng thái tự kết nối: $($_.Exception.Message.Trim())" }
    }
    $svc = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') { Add-Finding bad "Dịch vụ WLAN AutoConfig đang dừng ($($svc.Status))." -Fix 'khoi-dong-lai' }

    $h = Get-WifiHistory -Days 7
    Write-Head ('Nhật ký Wi-Fi {0} ngày gần đây' -f $h.Days)
    if (-not $h.Events) { Write-Info 'Không đọc được nhật ký WLAN-AutoConfig, hoặc nhật ký trống.' }
    else {
        Write-Line ('Tự kết nối bị treo rồi huỷ: {0} lần{1}' -f $h.Stuck.Count, $(if ($h.Stuck.Count) { ' (gần nhất: ' + (Format-Times $h.Stuck) + ')' } else { '' }))
        Write-Line ('Bấm kết nối, vào được rồi bị ngắt ngay: {0} lần{1}' -f $h.Dropped.Count, $(if ($h.Dropped.Count) { ' (' + (Format-Times $h.Dropped) + ')' } else { '' }))
        Write-Line ('Card ảo Wi-Fi Direct lỗi khi máy thức dậy: {0} lần{1}' -f $h.Resume.Count, $(if ($h.Resume.Count) { ' (' + (Format-Times ($h.Resume | ForEach-Object { [pscustomobject]@{ Time = $_.TimeCreated } })) + ')' } else { '' }))
        Write-Line ('Router không nhận mật khẩu (bắt tay không xong): {0} lần' -f $h.KeyFail.Count)
        $pattern = ($h.Dropped.Count -ge 2 -or $h.Stuck.Count -ge 3)
        if ($pattern) {
            Add-Finding bad 'Đúng lỗi "Can''t connect to this network" khi vào mạng mới.' -Fix 'ket-noi' -Hint ('Windows tự kết nối bị treo, chưa kịp bắt tay với router. Bấm vào mạng khác lúc đó thì vào được nhưng bị ngắt ngay để quay lại lần tự kết nối đang treo. Đang có mạng sẵn rồi chuyển sang mạng mới thì không bị, vì lúc đó không có lần tự kết nối nào đang treo.')
        }
        if ($h.Resume.Count) {
            Add-Finding warn 'Lỗi bắt đầu khi máy thức dậy từ chế độ ngủ: card ảo Wi-Fi Direct không bật lại được (NDIS 10317).' -Fix 'cap-nhat-driver' -Hint 'Lỗi điện năng của driver Wi-Fi; khởi động lại máy (Restart) cũng hết tạm thời.'
        }
        if ($h.KeyFail.Count -and -not $pattern) {
            Add-Finding info ('Router không nhận mật khẩu {0} lần: có thể đã gõ sai ở vài lần thử.' -f $h.KeyFail.Count)
        }
    }

    Write-Head 'Kết luận'
    Show-Conclusion

    $path = Join-Path (Get-ResultDir) ('BaoCao_WiFi_{0}_{1:yyyyMMdd_HHmmss}.txt' -f $env:COMPUTERNAME, $started)
    try {
        [IO.File]::WriteAllLines($path, $script:Report, $script:Utf8Bom)
        Write-Host ''
        Write-Host "  Báo cáo đã lưu: $path" -ForegroundColor Green
    } catch {
        Write-Host "  Không lưu được báo cáo: $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
    return 0
}

function Show-Conclusion {
    $rank = @{ bad = 0; warn = 1; info = 2 }
    $all = @($script:Findings)
    $ordered = @(for ($i = 0; $i -lt $all.Count; $i++) { [pscustomobject]@{ Key = $rank[$all[$i].Level] * 1000 + $i; F = $all[$i] } }) | Sort-Object Key | ForEach-Object { $_.F }
    if (-not $all.Count) { Write-Ok 'Không thấy dấu hiệu lỗi kết nối Wi-Fi.'; return }
    Write-Line 'Nên xử lý theo thứ tự:'
    foreach ($f in $ordered) {
        switch ($f.Level) { 'bad' { Write-Bad $f.Text } 'warn' { Write-Warn $f.Text } default { Write-Info $f.Text } }
        if ($f.Fix -and $script:Modes.Contains($f.Fix)) {
            $m = $script:Modes[$f.Fix]
            Write-Sub ('→ Chạy "{0}" (trong Trạm Tool, hoặc KET_NOI_WIFI.bat mục {1}).' -f $m.Label, $m.No)
        }
    }
}

# ---------------------------------------------------------------- chế độ: khởi động lại, cập nhật driver
function Invoke-KhoiDongLai {
    param([switch]$DryRun)
    Write-Head 'Khởi động lại Wi-Fi'
    $a = Get-WifiAdapter
    if (-not $a) { Write-Bad 'Không thấy card Wi-Fi.'; return 2 }
    Write-Line ('Card: {0} ({1})' -f $a.Description, $a.Name)
    $okAuto = Confirm-AutoConfig $a.Guid -DryRun:$DryRun
    $svc = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        if ($DryRun) { Write-Plan 'Bật dịch vụ WLAN AutoConfig' }
        else { try { Start-Service -Name WlanSvc; Write-Ok 'Đã bật dịch vụ WLAN AutoConfig.' } catch { Write-Bad "Không bật được dịch vụ WLAN AutoConfig: $($_.Exception.Message.Trim())" } }
    }
    $okRestart = Restart-WifiAdapter $a -DryRun:$DryRun
    if (-not $DryRun -and $okRestart) { Write-Info 'Windows sẽ tự vào lại mạng đã lưu. Mạng mới: dùng "Kết nối Wi-Fi".' }
    if ($okAuto -and $okRestart) { return 0 }
    return 1
}

function Invoke-CapNhatDriver {
    param([switch]$DryRun)
    Write-Head 'Cập nhật driver Wi-Fi'
    $a = Get-WifiAdapter
    if (-not $a) { Write-Bad 'Không thấy card Wi-Fi.'; return 2 }
    $age = Get-DriverAgeMonths $a
    Write-Line ('Card: {0}, driver {1}{2}' -f $a.Description, $a.DriverVersion, $(if ($null -ne $age) { " ($age tháng trước)" } else { '' }))
    $maker = ''
    try { $maker = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).Manufacturer } catch { }
    if ($a.Description -match 'Intel') {
        $url = $script:IntelUrl
        Write-Info 'Trang Intel: tải file "WiFi-<phiên bản>-Driver64-Win10-Win11.exe", chạy file đó (Windows hỏi quyền Admin), rồi khởi động lại máy.'
        Write-Sub 'Driver của Intel dùng chung cho mọi hãng máy có card Intel; bản mới sửa nhiều lỗi kết nối, ngủ, thức dậy.'
    } else {
        $url = 'ms-settings:windowsupdate-optionalupdates'
        Write-Info 'Card không phải Intel: xem driver trong Windows Update > Advanced options > Optional updates, hoặc trang hỗ trợ của hãng máy.'
    }
    if ($maker -match 'LENOVO') { Write-Info 'Máy Lenovo: cũng cập nhật được trong Lenovo Vantage > Device > System Update.' }
    if ($DryRun) { Write-Plan "Mở $url"; return 0 }
    try { Start-Process $url } catch { Write-Bad "Không mở được trang: $($_.Exception.Message.Trim())"; Write-Sub $url; return 1 }
    return 0
}

# ---------------------------------------------------------------- chạy chế độ, nâng quyền, menu
function Invoke-Mode {
    param([string]$Id, [hashtable]$O)
    $dry = [bool]$O.ChayThu
    switch ($Id) {
        'ket-noi' { return (Invoke-KetNoi -TenMang ([string]$O.TenMang) -DryRun:$dry) }
        'chan-doan' { return (Invoke-ChanDoan) }
        'khoi-dong-lai' { return (Invoke-KhoiDongLai -DryRun:$dry) }
        'cap-nhat-driver' { return (Invoke-CapNhatDriver -DryRun:$dry) }
    }
    return 1
}

function Invoke-ModeSafe {
    param([string]$Id, [hashtable]$O)
    try {
        $out = @(Invoke-Mode $Id $O)
        if ($out.Count -and $out[-1] -is [int]) { return $out[-1] }
        return 0
    } catch {
        Write-Bad ('Lỗi không lường trước: {0}' -f $_.Exception.Message.Trim())
        Write-Sub (([string]$_.InvocationInfo.PositionMessage).Split("`n")[0])
        return 1
    }
}

function Invoke-Elevated {
    # Mở lại chính script này bằng quyền Admin (Windows hỏi UAC) với cùng chế độ, chờ xong, trả mã thoát.
    param([string]$Id, [hashtable]$O)
    $q = { param([string]$s) '"' + $s.Replace('"', '').TrimEnd('\') + '"' }
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (& $q $script:MainScript), '-Mode', $Id)
    foreach ($k in @($O.Keys)) {
        $v = $O[$k]
        if ($v -is [bool]) { if ($v) { $parts += "-$k" } }
        elseif ([string]$v) { $parts += "-$k"; $parts += (& $q ([string]$v)) }
    }
    try { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList ($parts -join ' ') -Verb RunAs -Wait -PassThru }
    catch {
        $e = $_.Exception; $native = 0
        while ($e) { if ($e -is [ComponentModel.Win32Exception]) { $native = $e.NativeErrorCode; break }; $e = $e.InnerException }
        if ($native -eq 1223) { Write-Warn 'Bạn đã chọn "Không" ở hộp thoại quyền Admin nên chưa chạy.'; return 2 }
        Write-Bad "Không mở được bằng quyền Admin: $($_.Exception.Message.Trim())"
        return 1
    }
    try { return [int]$p.ExitCode } catch { return 0 }
}

function Show-Menu {
    while ($true) {
        try { $Host.UI.RawUI.WindowTitle = 'Kết nối Wi-Fi' } catch { }
        Write-Host ''
        Write-Host '  KẾT NỐI WI-FI' -ForegroundColor Cyan
        Write-Host '  Sửa lỗi "Can''t connect to this network" khi vào mạng Wi-Fi mới.' -ForegroundColor Gray
        Write-Host ''
        foreach ($id in $script:Modes.Keys) { Write-Host ('   {0}. {1}' -f $script:Modes[$id].No, $script:Modes[$id].Label) }
        Write-Host '   0. Thoát'
        Write-Host ''
        $c = Read-Text 'Chọn số'
        if ($c -eq '0' -or (-not $c -and [Console]::IsInputRedirected)) { return 0 }
        $id = $null
        foreach ($k in $script:Modes.Keys) { if ([string]$script:Modes[$k].No -eq $c) { $id = $k } }
        if (-not $id) { continue }
        $o = @{}
        if ($script:Modes[$id].Admin -eq 'yes' -and -not (Test-IsAdmin)) {
            Write-Info 'Windows sẽ hỏi quyền Admin, chọn "Có". Việc kết nối làm trong cửa sổ mới.'
            [void](Invoke-Elevated $id $o)
        } else {
            [void](Invoke-ModeSafe $id $o)
            Wait-Close 'Bấm Enter để về menu'
        }
    }
}

# ---------------------------------------------------------------- bắt đầu
try { $Host.UI.RawUI.WindowTitle = 'Kết nối Wi-Fi' } catch { }
$opts = @{ TenMang = $TenMang; ChayThu = [bool]$ChayThu }

if (-not $Mode) {
    if ([Console]::IsInputRedirected) {
        Write-Host ('Cách dùng: KetNoiWifi.ps1 -Mode <chế độ> [-ChayThu]. Chế độ: {0}.' -f (@($script:Modes.Keys) -join ', '))
        exit 1
    }
    exit (Show-Menu)
}
if (-not $script:Modes.Contains($Mode)) {
    Write-Bad ('Không có chế độ "{0}". Các chế độ: {1}.' -f $Mode, (@($script:Modes.Keys) -join ', '))
    Wait-Close
    exit 1
}
if ($TenMang -and ([Text.Encoding]::UTF8.GetByteCount($TenMang) -gt 32 -or $TenMang -match '["\r\n]')) {
    Write-Bad 'Tên mạng Wi-Fi không hợp lệ (tối đa 32 byte, không có dấu ").'
    Wait-Close
    exit 1
}

$def = $script:Modes[$Mode]
try { $Host.UI.RawUI.WindowTitle = 'Kết nối Wi-Fi - ' + $def.Label } catch { }
if ($def.Admin -eq 'yes' -and -not (Test-IsAdmin)) {
    if ($ChayThu) { Write-Info 'Chạy thử không có quyền Admin: vài thông tin có thể thiếu.' }
    else {
        Write-Info 'Chế độ này cần quyền Admin: Windows sẽ hỏi (UAC), chọn "Có".'
        exit (Invoke-Elevated $Mode $opts)
    }
}
$code = Invoke-ModeSafe $Mode $opts
Wait-Close
exit $code
