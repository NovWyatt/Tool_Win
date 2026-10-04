<# : ===== Phan CMD: tu xin quyen Admin roi chay phan PowerShell ben duoi (khong sua) =====
@echo off
setlocal
title Nhap du lieu sau khi cai lai Windows - Claude / Wi-Fi / May in
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
#  NHẬP (KHÔI PHỤC) DỮ LIỆU SAU KHI CÀI LẠI WINDOWS
#  Đọc thư mục "DuLieu_SaoLuu" (tạo bởi 1_XUAT_DU_LIEU.bat) nằm cạnh file .bat này
#  Khôi phục: Wi-Fi - Máy in (driver, cổng, cấu hình, máy in mặc định) - Claude
#  Chạy lại nhiều lần cũng được: Wi-Fi, máy in đã có thì bỏ qua; hội thoại Claude Code và file
#  Cowork trên máy mới hơn bản sao lưu thì giữ nguyên (không bị bản cũ chép đè).
# ============================================================================
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Warnings  = New-Object System.Collections.ArrayList
$Stat      = @{ WifiAdd = 0; WifiHave = 0; WifiBad = 0; DrvAdd = 0; PrAdd = 0; PrHave = 0; PrSkip = 0; Claude = ''; Code = 0; CodeOk = 0 }

# ---------------------------------------------------------------- tiện ích
function Head([string]$m) { Write-Host ''; Write-Host ('=' * 70) -ForegroundColor DarkCyan; Write-Host "  $m" -ForegroundColor Cyan; Write-Host ('=' * 70) -ForegroundColor DarkCyan }
function Ok([string]$m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Info([string]$m) { Write-Host "       $m" -ForegroundColor Gray }
function Warn([string]$m) { Write-Host "  [!]  $m" -ForegroundColor Yellow; [void]$Warnings.Add($m) }
function Fail([string]$m) { Write-Host "  [X]  $m" -ForegroundColor Red; [void]$Warnings.Add($m) }

function Ensure-Dir([string]$p) { if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Read-Json([string]$path) { [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json }
function Get-ErrText($code) {
    try { return ('{0} (mã {1})' -f (New-Object System.ComponentModel.Win32Exception([int]$code)).Message, $code) } catch { return "mã $code" }
}

# Chép cả thư mục bằng robocopy. Trả về mã robocopy (<8 = thành công)
# -KeepNewer: file trên máy mới hơn bản sao lưu thì giữ nguyên (robocopy /XO).
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

# ---------------------------------------------------------------- WLAN API
$WlanCs = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class WlanTool {
    [DllImport("wlanapi.dll")] static extern uint WlanOpenHandle(uint ver, IntPtr res, out uint negVer, out IntPtr h);
    [DllImport("wlanapi.dll")] static extern uint WlanCloseHandle(IntPtr h, IntPtr res);
    [DllImport("wlanapi.dll")] static extern uint WlanEnumInterfaces(IntPtr h, IntPtr res, out IntPtr list);
    [DllImport("wlanapi.dll", CharSet = CharSet.Unicode)] static extern uint WlanSetProfile(IntPtr h, ref Guid g, uint flags, string xml, string sec, bool overwrite, IntPtr res, out uint reason);
    [DllImport("wlanapi.dll")] static extern void WlanFreeMemory(IntPtr p);

    static IntPtr Open() {
        uint v; IntPtr h;
        uint r = WlanOpenHandle(2, IntPtr.Zero, out v, out h);
        if (r != 0) throw new Win32Exception((int)r);
        return h;
    }
    static List<Guid> Ifaces(IntPtr h) {
        IntPtr p; uint r = WlanEnumInterfaces(h, IntPtr.Zero, out p);
        if (r != 0) throw new Win32Exception((int)r);
        var res = new List<Guid>();
        try {
            int n = Marshal.ReadInt32(p, 0);
            for (int i = 0; i < n; i++) {
                IntPtr item = new IntPtr(p.ToInt64() + 8 + i * 532);   // WLAN_INTERFACE_INFO = GUID(16) + WCHAR[256] + DWORD
                byte[] gb = new byte[16]; Marshal.Copy(item, gb, 0, 16);
                res.Add(new Guid(gb));
            }
        } finally { WlanFreeMemory(p); }
        return res;
    }
    public static int InterfaceCount() {
        IntPtr h = Open();
        try { return Ifaces(h).Count; } finally { WlanCloseHandle(h, IntPtr.Zero); }
    }
    // Thêm hồ sơ vào mọi card Wi-Fi. Trả về mã lỗi từng card: 0 = đã thêm, 183 = đã có sẵn
    public static uint[] Import(string xml, uint flags, bool overwrite) {
        IntPtr h = Open();
        try {
            var ifs = Ifaces(h);
            var codes = new uint[ifs.Count];
            for (int i = 0; i < ifs.Count; i++) {
                Guid g = ifs[i]; uint reason;
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
function Get-WifiName([string]$xml) {
    try { $doc = New-Object System.Xml.XmlDocument; $doc.LoadXml($xml); return [string]$doc.WLANProfile.name } catch { return $null }
}

# ---------------------------------------------------------------- sửa đường dẫn khi tên thư mục người dùng khác máy cũ
# Claude Code đặt tên thư mục dự án = đường dẫn, mọi ký tự không phải chữ/số thành '-'  (C:\Users\A\x -> C--Users-A-x)
function Encode-ProjectName([string]$p) { return ($p -replace '[^A-Za-z0-9]', '-') }
function Remap-Name([string]$name, [string]$old, [string]$new) {
    $o = Encode-ProjectName $old; $n = Encode-ProjectName $new
    if ($name -ieq $o) { return $n }
    if ($name.StartsWith($o + '-', [StringComparison]::OrdinalIgnoreCase)) { return $n + $name.Substring($o.Length) }
    return $name
}
function Remap-Path([string]$path, [string]$old, [string]$new) {
    if ($path -ieq $old) { return $new }
    if ($path.StartsWith($old + '\', [StringComparison]::OrdinalIgnoreCase)) { return $new + $path.Substring($old.Length) }
    return $path
}
function Remap-Text([string]$text, [string]$old, [string]$new) {
    # JSON: C:\\Users\\Ten hoặc C:/Users/Ten ; văn bản (.md): C:\Users\Ten
    $forms = @( @($old.Replace('\', '\\'), $new.Replace('\', '\\')), @($old.Replace('\', '/'), $new.Replace('\', '/')), @($old, $new) )
    foreach ($f in $forms) {
        $pat = [regex]::Escape($f[0]) + '(?=[\\/"''`\s)\]>,;*]|$)'
        $text = [regex]::Replace($text, $pat, $f[1].Replace('$', '$$'), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    return $text
}
function Remap-JsonFile([string]$file, [string]$old, [string]$new) {
    if (-not (Test-Path -LiteralPath $file)) { return }
    try {
        $t = [IO.File]::ReadAllText($file)
        $t2 = Remap-Text $t $old $new
        if ($t2 -cne $t) { [IO.File]::WriteAllText($file, $t2, $Utf8NoBom) }
    } catch { Warn "Không sửa được đường dẫn trong $file" }
}

# ============================================================================ WI-FI
function Import-Wifi {
    Head 'WI-FI'
    $wDir = Join-Path $In 'WiFi'
    $idx = Join-Path $wDir 'danh-sach.json'
    $list = @()
    if (Test-Path -LiteralPath $idx) { $list = @((Read-Json $idx) | ForEach-Object { $_ }) }   # PS 5.1: ConvertFrom-Json trả mảng thành 1 phần tử -> phải "mở" ra
    elseif (Test-Path -LiteralPath $wDir) { $list = @(Get-ChildItem -LiteralPath $wDir -Filter '*.xml' -File | ForEach-Object { [pscustomobject]@{ File = $_.Name; Name = $null; Flags = 0 } }) }
    if ($list.Count -eq 0) { Info 'Bản sao lưu không có mạng Wi-Fi nào.'; return }
    [array]::Reverse($list)   # mạng thêm sau được Windows xếp lên ĐẦU -> thêm ngược để giữ đúng thứ tự ưu tiên cũ

    $svc = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
    if (-not $svc) { Fail 'Windows chưa có dịch vụ Wi-Fi - có thể chưa cài driver Wi-Fi. Cài xong chạy lại và chọn [2].'; return }
    try { if ([string]$svc.StartType -eq 'Disabled') { Set-Service -Name WlanSvc -StartupType Automatic -ErrorAction Stop } } catch {}
    if ($svc.Status -ne 'Running') { try { Start-Service -Name WlanSvc -ErrorAction Stop; Start-Sleep -Seconds 3 } catch {} }

    $api = Load-WlanApi
    if ($api) {
        $n = -1
        try { $n = [WlanTool]::InterfaceCount() } catch { $api = $false }
        if ($n -eq 0) { Fail 'Chưa thấy card Wi-Fi (chưa cài driver Wi-Fi?). Cài driver xong chạy lại và chọn [2].'; return }
    }

    $tmp = $null
    try {
        foreach ($e in $list) {
            $f = Join-Path $wDir ([string]$e.File)
            if (-not (Test-Path -LiteralPath $f)) { continue }
            $xml = [IO.File]::ReadAllText($f)
            $name = [string]$e.Name
            if (-not $name) { $name = Get-WifiName $xml }
            $flags = [uint32]([int]$e.Flags -band 2)
            if ($api) {
                $codes = @()
                try { $codes = @([WlanTool]::Import($xml, $flags, $false)) } catch { $codes = @([uint32]1062) }
                if (@($codes | Where-Object { $_ -eq 0 }).Count -gt 0) { $Stat.WifiAdd++ }
                elseif (@($codes | Where-Object { $_ -ne 183 }).Count -eq 0) { $Stat.WifiHave++ }
                else {
                    $Stat.WifiBad++
                    $c = @($codes | Where-Object { $_ -ne 0 -and $_ -ne 183 })[0]
                    Warn ("Không thêm được Wi-Fi '{0}': {1}" -f $name, (Get-ErrText $c))
                }
            } else {
                # Dự phòng: netsh (thư mục tạm phải NGẮN vì netsh cắt đường dẫn dài)
                if (-not $tmp) { $tmp = Join-Path $env:SystemRoot ('Temp\wi' + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory -Path $tmp -Force | Out-Null }
                if ($name) { & netsh.exe wlan show profile name="$name" | Out-Null; if ($LASTEXITCODE -eq 0) { $Stat.WifiHave++; continue } }
                $tf = Join-Path $tmp 'p.xml'
                [IO.File]::WriteAllText($tf, $xml, $Utf8NoBom)
                $usr = 'all'; if ($flags -ne 0) { $usr = 'current' }
                & netsh.exe wlan add profile filename="$tf" user=$usr | Out-Null
                if ($LASTEXITCODE -eq 0) { $Stat.WifiAdd++ } else { $Stat.WifiBad++; Warn "Không thêm được Wi-Fi '$name'" }
            }
        }
    } finally { if ($tmp) { try { [IO.Directory]::Delete($tmp, $true) } catch {} } }
    Ok ('Wi-Fi: thêm mới {0}, đã có sẵn {1}, lỗi {2}' -f $Stat.WifiAdd, $Stat.WifiHave, $Stat.WifiBad)
}

# ============================================================================ MÁY IN
function Import-Printers {
    Head 'MÁY IN'
    $pDir = Join-Path $In 'MayIn'
    $jf = Join-Path $pDir 'may-in.json'
    if (-not (Test-Path -LiteralPath $jf)) { Info 'Bản sao lưu không có dữ liệu máy in.'; return }
    $data = Read-Json $jf
    $drvDir = Join-Path $pDir 'Drivers'
    $tkDir  = Join-Path $pDir 'CauHinh'

    $sp = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if (-not $sp) { Fail 'Không có dịch vụ Print Spooler.'; return }
    try { if ([string]$sp.StartType -eq 'Disabled') { Set-Service -Name Spooler -StartupType Automatic -ErrorAction Stop } } catch {}
    if ($sp.Status -ne 'Running') {
        try { Start-Service -Name Spooler -ErrorAction Stop; Start-Sleep -Seconds 3 } catch { Fail 'Không bật được Print Spooler.'; return }
    }

    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    $envNative = 'Windows NT x86'
    if ($arch -eq 'AMD64') { $envNative = 'Windows x64' } elseif ($arch -eq 'ARM64') { $envNative = 'Windows ARM64' }
    $drivers = @($data.Drivers | Where-Object { $_ -and -not $_.Inbox -and $_.Folder -and (-not $_.Environment -or $_.Environment -eq $envNative) })

    # 1) Nạp gói driver vào kho driver của Windows
    $haveDrv = @{}
    foreach ($x in @(Get-PrinterDriver -ErrorAction SilentlyContinue)) { $haveDrv[[string]$x.Name] = $true }
    $done = @{}
    foreach ($d in $drivers) {
        if ($haveDrv.ContainsKey([string]$d.Name) -or $done.ContainsKey([string]$d.Folder)) { continue }
        $done[[string]$d.Folder] = $true
        $inf = Join-Path (Join-Path $drvDir $d.Folder) $d.Inf
        if (-not (Test-Path -LiteralPath $inf)) { Warn "Thiếu file driver $($d.Folder)\$($d.Inf)"; continue }
        Info "Đang nạp gói driver $($d.Inf) ..."
        & pnputil.exe /add-driver $inf /install | Out-Null
        $rc = $LASTEXITCODE
        if (@(0, 259, 3010) -notcontains $rc) { Info "(pnputil trả mã $rc - vẫn thử cài tiếp)" }
    }
    # 2) Cài driver máy in
    foreach ($d in $drivers) {
        $name = [string]$d.Name
        if ($haveDrv.ContainsKey($name)) { continue }
        $inf = Join-Path (Join-Path $drvDir $d.Folder) $d.Inf
        $ok = $false
        try { Add-PrinterDriver -Name $name -ErrorAction Stop; $ok = $true } catch {}
        if (-not $ok -and (Test-Path -LiteralPath $inf)) { try { Add-PrinterDriver -Name $name -InfPath $inf -ErrorAction Stop; $ok = $true } catch {} }
        if (-not $ok -and (Test-Path -LiteralPath $inf)) {
            & rundll32.exe 'printui.dll,PrintUIEntry' /ia /q /m "$name" /f "$inf" | Out-Null   # | Out-Null để PS 5.1 chờ rundll32 chạy xong
            for ($w = 0; $w -lt 10 -and -not $ok; $w++) {
                if (Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $name }) { $ok = $true } else { Start-Sleep -Seconds 1 }
            }
        }
        if ($ok) { $haveDrv[$name] = $true; $Stat.DrvAdd++; Ok "Driver: $name" }
        elseif ($d.Used) { Fail "Không cài được driver '$name' - tải driver từ trang của hãng, cài xong chạy lại và chọn [3]." }
        else { Info "(bỏ qua driver không dùng: $name)" }
    }

    # 3) Tạo cổng TCP/IP
    $havePort = @{}
    foreach ($x in @(Get-PrinterPort -ErrorAction SilentlyContinue)) { $havePort[[string]$x.Name] = $true }
    foreach ($pt in @($data.Ports)) {
        if (-not $pt -or $havePort.ContainsKey([string]$pt.Name)) { continue }
        try {
            if ($pt.Protocol -eq 'LPR') {
                $a = @{ Name = $pt.Name; LprHostAddress = $pt.Host; LprQueueName = $pt.LprQueueName; ErrorAction = 'Stop' }
                if ($pt.LprByteCounting) { $a.LprByteCounting = $true }
            } else {
                $a = @{ Name = $pt.Name; PrinterHostAddress = $pt.Host; PortNumber = [uint32]$pt.PortNumber; ErrorAction = 'Stop' }
                if ($pt.SNMPEnabled) { $a.SNMP = [uint32]$pt.SNMPIndex; $a.SNMPCommunity = [string]$pt.SNMPCommunity }
            }
            Add-PrinterPort @a
            $havePort[[string]$pt.Name] = $true
        } catch { Warn "Không tạo được cổng $($pt.Name): $($_.Exception.Message)" }
    }

    # 4) Thêm máy in
    $havePr = @{}
    foreach ($x in @(Get-Printer -ErrorAction SilentlyContinue)) { $havePr[[string]$x.Name] = $true }
    foreach ($p in @($data.Printers)) {
        if (-not $p) { continue }
        $pname = [string]$p.Name
        if ($havePr.ContainsKey($pname)) { Info "Đã có sẵn: $pname"; $Stat.PrHave++; continue }
        if ($p.Kind -eq 'CONNECTION') {
            try { Add-Printer -ConnectionName $pname -ErrorAction Stop; $havePr[$pname] = $true; $Stat.PrAdd++; Ok "$pname (máy in chia sẻ qua mạng)" }
            catch { Warn "Không kết nối được máy in chia sẻ '$pname' (máy chủ phải đang bật)."; $Stat.PrSkip++ }
            continue
        }
        if (-not $haveDrv.ContainsKey([string]$p.DriverName)) { Fail "Bỏ qua '$pname': chưa có driver '$($p.DriverName)'."; $Stat.PrSkip++; continue }

        $port = [string]$p.PortName
        if ($p.Kind -eq 'WSD') {
            if (-not $p.WsdIp) { Warn "Bỏ qua '$pname': máy in WSD không rõ IP - hãy thêm lại trong Cài đặt > Máy in."; $Stat.PrSkip++; continue }
            $port = [string]$p.WsdIp      # cổng WSD không tạo lại được -> dùng cổng TCP/IP theo IP thật
            if (-not $havePort.ContainsKey($port)) {
                try { Add-PrinterPort -Name $port -PrinterHostAddress $port -ErrorAction Stop; $havePort[$port] = $true }
                catch { Warn "Không tạo được cổng ${port}: $($_.Exception.Message)"; $Stat.PrSkip++; continue }
            }
        } elseif (-not $havePort.ContainsKey($port)) {
            if ($p.Kind -eq 'USB') { Warn "Máy in USB '$pname': hãy cắm cáp USB, Windows sẽ tự nhận (driver đã cài sẵn) rồi chạy lại mục [3] nếu muốn giữ tên cũ." }
            else { Warn "Bỏ qua '$pname': máy mới không có cổng '$port'." }
            $Stat.PrSkip++; continue
        }

        $a = @{ Name = $pname; DriverName = [string]$p.DriverName; PortName = $port; ErrorAction = 'Stop' }
        if ($p.Location) { $a.Location = [string]$p.Location }
        if ($p.Comment)  { $a.Comment  = [string]$p.Comment }
        try { Add-Printer @a } catch { Fail "Không thêm được máy in '$pname': $($_.Exception.Message)"; $Stat.PrSkip++; continue }
        $havePr[$pname] = $true; $Stat.PrAdd++

        if ($p.Shared) {
            $obj = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $pname } | Select-Object -First 1
            $sn = [string]$p.ShareName; if (-not $sn) { $sn = $pname }
            if ($obj) { try { Set-Printer -InputObject $obj -Shared $true -ShareName $sn -ErrorAction Stop } catch { Info "(không bật được chia sẻ cho '$pname')" } }
        }
        if ($p.TicketFile) {
            $tf = Join-Path $tkDir ([string]$p.TicketFile)
            if (Test-Path -LiteralPath $tf) {
                try { Set-PrintConfiguration -PrinterName $pname -PrintTicketXml ([IO.File]::ReadAllText($tf)) -ErrorAction Stop }
                catch { Info "(không áp được cấu hình in cũ cho '$pname' - dùng mặc định)" }
            }
        }
        Ok ('{0}  ->  {1}' -f $pname, $port)
    }

    # 5) Máy in mặc định
    $def = [string]$data.DefaultPrinter
    if ($def -and $havePr.ContainsKey($def)) {
        try {
            if ($null -ne $data.LegacyDefaultPrinterMode) {
                New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' -Name 'LegacyDefaultPrinterMode' -Value ([int]$data.LegacyDefaultPrinterMode) -PropertyType DWord -Force | Out-Null
            }
            (New-Object -ComObject WScript.Network).SetDefaultPrinter($def)
            Ok "Máy in mặc định: $def"
        } catch { Warn "Không đặt được máy in mặc định '$def'." }
    }
    Ok ('Máy in: thêm mới {0}, đã có sẵn {1}, bỏ qua {2}; driver cài mới {3}' -f $Stat.PrAdd, $Stat.PrHave, $Stat.PrSkip, $Stat.DrvAdd)
}

# ============================================================================ CLAUDE
function Wait-ClaudeClosed {
    for ($k = 0; $k -lt 30; $k++) {
        $pr = @(Get-Process -Name 'claude' -ErrorAction SilentlyContinue)
        if ($pr.Count -eq 0) { return $true }
        Write-Host ''
        Write-Host '  [!] Claude đang chạy. Phải THOÁT HẲN Claude trước khi khôi phục' -ForegroundColor Yellow
        Write-Host '      (chuột phải biểu tượng Claude ở khay đồng hồ -> Quit).' -ForegroundColor Yellow
        $a = Read-Host '      [Enter] = đã thoát, kiểm tra lại    [T] = tự đóng Claude    [B] = bỏ qua phần Claude'
        if ($null -eq $a) { return $false }
        if ($a -match '^\s*[Tt]') { $pr | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3 }
        elseif ($a -match '^\s*[Bb]') { return $false }
    }
    return $false
}

# Nơi Claude Desktop đọc dữ liệu: bản MSIX -> %LOCALAPPDATA%\Packages\Claude_xxx\LocalCache\Roaming\Claude
function Get-ClaudeAppDataTarget {
    $pk = Join-Path $env:LOCALAPPDATA 'Packages'
    try {
        $ap = @(Get-AppxPackage -Name 'Claude' -ErrorAction Stop | Where-Object { $_.PackageFamilyName -like 'Claude_*' }) | Select-Object -First 1
        if ($ap) { return (Join-Path $pk ($ap.PackageFamilyName + '\LocalCache\Roaming\Claude')) }
    } catch {}
    $d = @(Get-ChildItem -LiteralPath $pk -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($d) { return (Join-Path $d.FullName 'LocalCache\Roaming\Claude') }
    $real = Join-Path $env:APPDATA 'Claude'
    if ((Test-Path -LiteralPath $real) -or (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'AnthropicClaude'))) { return $real }
    return $null
}

function Check-CodeConversations([string]$sessDir, [string]$projDir) {
    if (-not (Test-Path -LiteralPath $sessDir)) { return }
    $tx = @{}
    if (Test-Path -LiteralPath $projDir) { foreach ($f in @(Get-ChildItem -LiteralPath $projDir -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue)) { $tx[$f.BaseName] = $true } }
    $all = 0; $ok = 0
    $noDir = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $sessDir -Recurse -File -Filter 'local_*.json' -ErrorAction SilentlyContinue)) {
        try { $j = Read-Json $f.FullName } catch { continue }
        $all++
        if ($j.cliSessionId -and $tx.ContainsKey([string]$j.cliSessionId)) { $ok++ }
        if ($j.cwd -and -not $j.isArchived -and -not (Test-Path -LiteralPath ([string]$j.cwd))) { [void]$noDir.Add(('{0}  ->  {1}' -f $j.title, $j.cwd)) }
    }
    $Stat.Code = $all; $Stat.CodeOk = $ok
    if ($all -eq 0) { return }
    if ($ok -eq $all) { Ok "Hội thoại tab Code: đủ $ok/$all cuộc" } else { Warn "Hội thoại tab Code: chỉ $ok/$all cuộc có nội dung." }
    if ($noDir.Count -gt 0) {
        Warn "$($noDir.Count) cuộc hội thoại Code trỏ tới thư mục dự án CHƯA có trên máy này - chép thư mục dự án về ĐÚNG đường dẫn dưới đây rồi mới mở các cuộc đó trong Claude:"
        foreach ($x in @($noDir | Select-Object -First 30)) { Info $x }
        if ($noDir.Count -gt 30) { Info "... và $($noDir.Count - 30) cuộc khác" }
    }
}

function Import-Claude {
    Head 'CLAUDE'
    $cIn = Join-Path $In 'Claude'
    if (-not (Test-Path -LiteralPath $cIn)) { Info 'Bản sao lưu không có dữ liệu Claude.'; return }
    if (-not (Wait-ClaudeClosed)) { Warn 'Đã bỏ qua phần Claude vì Claude vẫn đang chạy - thoát Claude rồi chạy lại và chọn [4].'; $Stat.Claude = 'bỏ qua'; return }

    $info = $null
    $infoFile = Join-Path $cIn 'claude-info.json'
    if (Test-Path -LiteralPath $infoFile) { try { $info = Read-Json $infoFile } catch {} }
    $OldUP = ''
    if ($info -and $info.UserProfile) { $OldUP = ([string]$info.UserProfile).TrimEnd('\') }
    $NewUP = ([string]$env:USERPROFILE).TrimEnd('\')
    $remap = ($OldUP -ne '') -and -not [string]::Equals($OldUP, $NewUP, [StringComparison]::OrdinalIgnoreCase)
    if ($remap) { Info "Thư mục người dùng đã đổi: $OldUP  ->  $NewUP  (tự sửa đường dẫn cho Claude)" }
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $okAll = $true

    # (a) ~\.claude
    $src = Join-Path $cIn 'dot-claude'
    $dst = Join-Path $NewUP '.claude'
    if (Test-Path -LiteralPath $src) {
        $st = Join-Path $dst 'settings.json'
        if (Test-Path -LiteralPath $st) { Copy-Item -LiteralPath $st -Destination "$st.truoc-khoi-phuc-$ts" -Force }
        $pj = Join-Path $src 'projects'
        if ((Copy-Tree $src $dst @($pj)) -ge 8) { $okAll = $false }
        if (Test-Path -LiteralPath $pj) {
            $pjDst = Join-Path $dst 'projects'
            Ensure-Dir $pjDst
            foreach ($d in @(Get-ChildItem -LiteralPath $pj -Directory -Force)) {
                $nn = $d.Name
                if ($remap) { $nn = Remap-Name $d.Name $OldUP $NewUP }
                if ((Copy-Tree $d.FullName (Join-Path $pjDst $nn) -KeepNewer) -ge 8) { $okAll = $false }
            }
            foreach ($f in @(Get-ChildItem -LiteralPath $pj -File -Force)) { Copy-Item -LiteralPath $f.FullName -Destination $pjDst -Force }
        }
        if ($remap) {
            foreach ($f in @(Get-ChildItem -LiteralPath $dst -Filter '*.json' -File -Force -ErrorAction SilentlyContinue)) { Remap-JsonFile $f.FullName $OldUP $NewUP }
            $pl = Join-Path $dst 'plugins'
            if (Test-Path -LiteralPath $pl) { foreach ($f in @(Get-ChildItem -LiteralPath $pl -Filter '*.json' -File -Recurse -Force -ErrorAction SilentlyContinue)) { Remap-JsonFile $f.FullName $OldUP $NewUP } }
            # memory (*.md), tác vụ hẹn giờ, CLAUDE.md cũng có đường dẫn
            foreach ($pd in @(Get-ChildItem -LiteralPath (Join-Path $dst 'projects') -Directory -Force -ErrorAction SilentlyContinue)) {
                foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $pd.FullName 'memory') -Filter '*.md' -File -Force -ErrorAction SilentlyContinue)) { Remap-JsonFile $f.FullName $OldUP $NewUP }
            }
            $stk = Join-Path $dst 'scheduled-tasks'
            if (Test-Path -LiteralPath $stk) { foreach ($f in @(Get-ChildItem -LiteralPath $stk -Filter '*.md' -File -Recurse -Force -ErrorAction SilentlyContinue)) { Remap-JsonFile $f.FullName $OldUP $NewUP } }
            Remap-JsonFile (Join-Path $dst 'CLAUDE.md') $OldUP $NewUP
        }
        if ($okAll) { Ok 'Claude Code (~\.claude): cài đặt, memory, lịch sử phiên, skills, tác vụ hẹn giờ' } else { Warn 'Khôi phục ~\.claude bị lỗi một phần (xem nhat-ky-nhap.txt).' }
    }

    # (b) ~\.claude.json
    $cjSrc = Join-Path $cIn 'dot-claude.json'
    $cjDst = Join-Path $NewUP '.claude.json'
    if (Test-Path -LiteralPath $cjSrc) {
        if (Test-Path -LiteralPath $cjDst) { Copy-Item -LiteralPath $cjDst -Destination "$cjDst.truoc-khoi-phuc-$ts" -Force }
        Copy-Item -LiteralPath $cjSrc -Destination $cjDst -Force
        if ($remap) { Remap-JsonFile $cjDst $OldUP $NewUP }
        Ok 'Cấu hình chung Claude Code (~\.claude.json)'
    }

    # (c) Claude Desktop
    $aIn = Join-Path $cIn 'AppData-Claude'
    $desktopDone = $false
    if (Test-Path -LiteralPath $aIn) {
        $target = Get-ClaudeAppDataTarget
        if (-not $target) {
            Warn 'Chưa cài ứng dụng Claude Desktop nên CHƯA khôi phục phần của nó. Cài Claude (https://claude.ai/download), đăng nhập, thoát hẳn, rồi chạy lại và chọn [4].'
        } else {
            Ensure-Dir $target
            $cfgT = Join-Path $target 'claude_desktop_config.json'
            if (Test-Path -LiteralPath $cfgT) { Copy-Item -LiteralPath $cfgT -Destination "$cfgT.truoc-khoi-phuc-$ts" -Force }
            $rc = Copy-Tree $aIn $target
            if ($remap) {
                Remap-JsonFile $cfgT $OldUP $NewUP
                foreach ($sub in @('claude-code-sessions', 'local-agent-mode-sessions')) {
                    $sd = Join-Path $target $sub
                    if (Test-Path -LiteralPath $sd) { foreach ($f in @(Get-ChildItem -LiteralPath $sd -Filter '*.json' -File -Recurse -Force -ErrorAction SilentlyContinue)) { Remap-JsonFile $f.FullName $OldUP $NewUP } }
                }
            }
            if ($rc -lt 8) { Ok 'Claude Desktop: cấu hình, danh sách phiên Code/Cowork, tác vụ hẹn giờ'; $desktopDone = $true }
            else { Warn "Khôi phục dữ liệu Claude Desktop bị lỗi (robocopy mã $rc)." }
            # Kiểm đếm hội thoại tab Code: mỗi cuộc phải có cả mục trong danh sách lẫn file nội dung
            Check-CodeConversations (Join-Path $target 'claude-code-sessions') (Join-Path $dst 'projects')
        }
    }

    # (d) Thư mục file Cowork
    $cwIn = Join-Path $cIn 'Cowork-Files'
    if ((Test-Path -LiteralPath $cwIn) -and $info -and $info.CoworkPath) {
        $cwDst = ([string]$info.CoworkPath).TrimEnd('\')
        if ($remap) { $cwDst = Remap-Path $cwDst $OldUP $NewUP }
        if ((Copy-Tree $cwIn $cwDst -KeepNewer) -lt 8) { Ok "Thư mục file Cowork: $cwDst" } else { Warn "Chép thư mục Cowork lỗi: $cwDst" }
    }
    $Stat.Claude = if ($desktopDone) { 'đã khôi phục' } else { 'đã khôi phục Claude Code (thiếu phần Claude Desktop)' }
}

# ============================================================================ CHƯƠNG TRÌNH CHÍNH
$Root = ([string]$env:__DIR).TrimEnd('\')
if (-not $Root) { $Root = (Get-Location).Path }

Clear-Host
Write-Host ''
Write-Host '  ==================================================================' -ForegroundColor Cyan
Write-Host '     NHẬP (KHÔI PHỤC) DỮ LIỆU SAU KHI CÀI LẠI WINDOWS' -ForegroundColor White
Write-Host '     Wi-Fi  -  Máy in  -  Claude' -ForegroundColor White
Write-Host '  ==================================================================' -ForegroundColor Cyan

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Fail 'Cần chạy với quyền Administrator (nhấp đúp file .bat và bấm Yes).'; return }

# Tìm thư mục sao lưu
$In = $null
$cand = Join-Path $Root 'DuLieu_SaoLuu'
if (Test-Path -LiteralPath (Join-Path $cand 'thong-tin.json')) { $In = $cand }
else {
    $c2 = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'DuLieu_SaoLuu*' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'thong-tin.json')) } | Sort-Object LastWriteTime -Descending)
    if ($c2.Count -gt 0) { $In = $c2[0].FullName }
}
while (-not $In) {
    Write-Host ''
    Write-Host "  Không thấy thư mục DuLieu_SaoLuu cạnh file .bat ($Root)." -ForegroundColor Yellow
    $a = Read-Host '  Dán (hoặc kéo-thả) đường dẫn thư mục DuLieu_SaoLuu rồi Enter (để trống = thoát)'
    if ($null -eq $a) { return }
    $a = $a.Trim().Trim('"').TrimEnd('\')
    if (-not $a) { return }
    if (Test-Path -LiteralPath (Join-Path $a 'thong-tin.json')) { $In = $a }
    elseif (Test-Path -LiteralPath (Join-Path $a 'DuLieu_SaoLuu\thong-tin.json')) { $In = Join-Path $a 'DuLieu_SaoLuu' }
}

$meta = $null
try { $meta = Read-Json (Join-Path $In 'thong-tin.json') } catch {}
Write-Host ''
Write-Host "  Bản sao lưu: $In" -ForegroundColor White
if ($meta) {
    Write-Host ("  Tạo lúc {0} trên máy {1} (người dùng {2})" -f $meta.Date, $meta.Computer, $meta.UserName) -ForegroundColor Gray
    Write-Host ("  Gồm: {0} Wi-Fi, {1} máy in, Claude: {2}" -f $meta.Wifi, $meta.Printers, $(if ($meta.Claude) { 'có' } else { 'không' })) -ForegroundColor Gray
}
Write-Host ''
Write-Host '  [1] Khôi phục TẤT CẢ  (nhấn Enter)' -ForegroundColor White
Write-Host '  [2] Chỉ Wi-Fi' -ForegroundColor White
Write-Host '  [3] Chỉ máy in' -ForegroundColor White
Write-Host '  [4] Chỉ Claude' -ForegroundColor White
Write-Host '  [0] Thoát' -ForegroundColor White
$choice = $null
while ($null -eq $choice) {
    $a = Read-Host '  Chọn'
    if ($null -eq $a) { $a = '' }
    $a = $a.Trim()
    if ($a -eq '') { $a = '1' }
    if (@('0', '1', '2', '3', '4') -contains $a) { $choice = $a } else { Write-Host '  Chỉ gõ 0, 1, 2, 3 hoặc 4.' -ForegroundColor Yellow }
}
if ($choice -eq '0') { return }

try { Start-Transcript -Path (Join-Path $In 'nhat-ky-nhap.txt') -Append | Out-Null } catch {}

if ($choice -eq '1' -or $choice -eq '2') { Import-Wifi }
if ($choice -eq '1' -or $choice -eq '3') { Import-Printers }
if ($choice -eq '1' -or $choice -eq '4') { Import-Claude }

Head 'HOÀN TẤT'
if ($choice -eq '1' -or $choice -eq '2') { Write-Host ('  Wi-Fi  : thêm mới {0}, đã có {1}, lỗi {2}' -f $Stat.WifiAdd, $Stat.WifiHave, $Stat.WifiBad) -ForegroundColor White }
if ($choice -eq '1' -or $choice -eq '3') { Write-Host ('  Máy in : thêm mới {0}, đã có {1}, bỏ qua {2}; driver cài mới {3}' -f $Stat.PrAdd, $Stat.PrHave, $Stat.PrSkip, $Stat.DrvAdd) -ForegroundColor White }
if ($choice -eq '1' -or $choice -eq '4') {
    Write-Host ('  Claude : {0}' -f $Stat.Claude) -ForegroundColor White
    if ($Stat.Code -gt 0) { Write-Host ('  Hội thoại Code: {0}/{1} cuộc' -f $Stat.CodeOk, $Stat.Code) -ForegroundColor White }
}
if ($Warnings.Count -gt 0) {
    Write-Host ''
    Write-Host "  Có $($Warnings.Count) lưu ý:" -ForegroundColor Yellow
    foreach ($w in $Warnings) { Write-Host "   - $w" -ForegroundColor Yellow }
}
Write-Host ''
Write-Host '  BƯỚC TIẾP THEO:' -ForegroundColor Cyan
if ($choice -eq '1' -or $choice -eq '4') {
    Write-Host '   * Chép các thư mục dự án về ĐÚNG chỗ cũ (nếu chưa), rồi mở Claude, đăng nhập lại nếu được hỏi.' -ForegroundColor Cyan
    Write-Host '     Hội thoại tab Code, memory, cài đặt sẽ có lại. Bản đọc được: DuLieu_SaoLuu\Claude\HoiThoai-Code\index.html' -ForegroundColor Cyan
}
if ($choice -eq '1' -or $choice -eq '3') { Write-Host '   * Máy in USB: cắm cáp vào là Windows tự nhận.' -ForegroundColor Cyan }
Write-Host '   * Kiểm tra xong, nên XÓA thư mục DuLieu_SaoLuu (có mật khẩu Wi-Fi dạng chữ thường).' -ForegroundColor Cyan
try { Stop-Transcript | Out-Null } catch {}
