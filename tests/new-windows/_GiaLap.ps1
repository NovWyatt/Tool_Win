# Bộ giả lập cho bài thử new-windows: không gọi WLAN thật, máy in thật, BitLocker thật, pnputil thật, Claude thật.
# Nạp sau KiemThu.ps1:  . "$PSScriptRoot\_GiaLap.ps1" -FakeHome <thư mục nhà giả>
param([string]$FakeHome)
$ErrorActionPreference = 'Continue'

# Wi-Fi giả: hai mạng có mật khẩu giả, một mạng do công ty quản lý
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
public static class WlanTool {
    public class Prof { public string Name; public uint Flags; public string Xml; public uint Error; public string Iface; }
    public static int ExportCalls = 0;
    public static List<string> Imported = new List<string>();
    public static List<string> Existing = new List<string>();
    static string X(string n, string k) {
        return "<?xml version=\"1.0\"?><WLANProfile xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v1\"><name>" + n +
          "</name><MSM><security><authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption></authEncryption>" +
          "<sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>" + k + "</keyMaterial></sharedKey></security></MSM></WLANProfile>";
    }
    public static int InterfaceCount() { return 1; }
    public static List<Prof> Export() {
        ExportCalls++;
        var r = new List<Prof>();
        r.Add(new Prof { Name = "Nha Gia 5G", Flags = 0, Xml = X("Nha Gia 5G", "KhoaWifiGia_111") });
        r.Add(new Prof { Name = "Quan Ca Phe Gia", Flags = 0, Xml = X("Quan Ca Phe Gia", "KhoaWifiGia_222") });
        r.Add(new Prof { Name = "CongTy GP", Flags = 1, Xml = X("CongTy GP", "KhoaWifiGia_333") });
        return r;
    }
    public static List<Prof> ListProfiles() {
        var r = new List<Prof>();
        foreach (var n in Existing) r.Add(new Prof { Name = n });
        return r;
    }
    public static uint[] Import(string xml, uint flags, bool overwrite) {
        string n = Regex.Match(xml, "<name>(.*?)</name>").Groups[1].Value;
        if (Existing.Contains(n)) return new uint[] { 183 };
        Imported.Add(xml); Existing.Add(n);
        return new uint[] { 0 };
    }
}
'@

# Máy giả
$env:USERPROFILE = $FakeHome
$env:APPDATA = Join-Path $FakeHome 'AppData\Roaming'
$env:LOCALAPPDATA = Join-Path $FakeHome 'AppData\Local'
$env:TRAMTOOL_CHUYENDULIEU_TEST = '1'
$env:CDL_KET_QUA = Join-Path $TestRoot 'ket_qua'
. "$ToolsDir\new-windows\ChuyenDuLieu.ps1"
Remove-Item Env:\TRAMTOOL_CHUYENDULIEU_TEST
$script:ResultDir = $env:CDL_KET_QUA

$global:Calls = New-Object System.Collections.ArrayList
function Rec([string]$s) { [void]$global:Calls.Add($s) }
$global:FakePrinters = @()
$global:FakeDrivers = @()
$global:FakeVols = @()
$global:BdeKey = '111111-222222-333333-444444-555555-666666-777777-888888'   # khoá giả
$global:BdeId = '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}'

function Get-Process { param([Parameter(Position = 0)]$Name) @() }
function Stop-Process { throw 'Stop-Process bị chặn trong bài thử' }
function Get-Service { param([Parameter(Position = 0)]$Name) [pscustomobject]@{ Name = $Name; Status = 'Running'; StartType = 'Automatic' } }
function Set-Service { Rec 'Set-Service' }
function Start-Service { Rec 'Start-Service' }
function Get-AppxPackage { throw 'không có Appx (giả lập)' }
function Get-ItemProperty { param($Path, $LiteralPath, $Name, $ErrorAction) $null }
function New-ItemProperty { Rec 'New-ItemProperty' }
function Get-Printer { param($Name, $ErrorAction) @($global:FakePrinters) }
function Get-PrinterPort { param($ErrorAction) @([pscustomobject]@{ Name = 'IP_10.9.9.9'; CimClass = [pscustomobject]@{ CimClassName = 'MSFT_TcpIpPrinterPort' }; PrinterHostAddress = '10.9.9.9'; PortNumber = 9100; Protocol = 1; SNMPEnabled = $false; SNMPIndex = 1 }) }
function Get-PrintConfiguration { param($PrinterName, $ErrorAction) [pscustomobject]@{ PrintTicketXML = '<ve-in-gia/>' } }
function Get-PrinterDriver { param($ErrorAction) @($global:FakeDrivers) }
function Add-PrinterDriver { param($Name, $InfPath, $ErrorAction) Rec "Add-PrinterDriver $Name"; $global:FakeDrivers += [pscustomobject]@{ Name = $Name } }
function Add-PrinterPort { param($Name, $PrinterHostAddress, $PortNumber, $LprHostAddress, $LprQueueName, [switch]$LprByteCounting, $SNMP, $SNMPCommunity, $ErrorAction) Rec "Add-PrinterPort $Name" }
function Add-Printer { param($Name, $DriverName, $PortName, $ConnectionName, $Location, $Comment, $ErrorAction) Rec "Add-Printer $Name"; $global:FakePrinters += [pscustomobject]@{ Name = $Name; PortName = $PortName; DriverName = $DriverName } }
function Set-Printer { Rec 'Set-Printer' }
function Set-PrintConfiguration { param($PrinterName, $PrintTicketXml, $ErrorAction) Rec "Set-PrintConfiguration $PrinterName" }
function pnputil.exe {
    $a = @($args)
    Rec ('pnputil ' + ($a -join ' '))
    if ($a[0] -eq '/export-driver') {
        $d = $a[2]; New-Item -ItemType Directory -Path $d -Force | Out-Null
        $n = if ($a[1] -eq '*') { 'oem99.inf' } else { $a[1] }
        Set-Content -LiteralPath (Join-Path $d $n) -Value '; inf giả' -Encoding ASCII
    }
    $global:LASTEXITCODE = 0
}
function Get-CimInstance {
    param([Parameter(Position = 0)]$ClassName, $Namespace, $Filter)
    if ($Namespace) { return @($global:FakeVols) }
    switch ($ClassName) {
        'Win32_ComputerSystem' { [pscustomobject]@{ UserName = [Security.Principal.WindowsIdentity]::GetCurrent().Name } }
        'Win32_PnPSignedDriver' { [pscustomobject]@{ InfName = 'oem12.inf'; DeviceClass = 'NET'; DeviceName = 'Card Wi-Fi gia'; DriverProviderName = 'Hang Gia'; DriverVersion = '1.0' } }
        'Win32_OperatingSystem' { [pscustomobject]@{ Caption = 'Windows giả' } }
        default { @() }   # Win32_LogicalDisk, Win32_Printer: không có
    }
}
function Invoke-Bde($vol, [string]$method, [hashtable]$arguments = $null) {
    switch ($method) {
        'GetLockStatus' { return [pscustomobject]@{ LockStatus = [int]$vol.Locked } }
        'GetProtectionStatus' { return [pscustomobject]@{ ProtectionStatus = 1 } }
        'GetConversionStatus' { return [pscustomobject]@{ ConversionStatus = 1 } }
        'GetKeyProtectors' { return [pscustomobject]@{ VolumeKeyProtectorID = @($global:BdeId) } }
        'GetKeyProtectorNumericalPassword' { Rec 'Bde:GetKey'; return [pscustomobject]@{ NumericalPassword = $global:BdeKey } }
        'UnlockWithNumericalPassword' {
            if ($arguments.NumericalPassword -ne $global:BdeKey) { throw 'sai khoá' }
            Rec "Bde:Unlock $($vol.DriveLetter)"; $vol.Locked = 0; return [pscustomobject]@{ ReturnValue = 0 }
        }
    }
    throw "Invoke-Bde giả chưa có $method"
}

function New-FakeHome([string]$H, [string]$OldProfileInText) {
    # ~\.claude, ~\.claude.json, Claude Desktop (bản MSIX), một hội thoại Code
    $dc = Join-Path $H '.claude'
    $pn = ($OldProfileInText -replace '[^A-Za-z0-9]', '-') + '-DuAn'
    New-Item -ItemType Directory -Force -Path (Join-Path $dc "projects\$pn") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $dc 'cache') | Out-Null
    Set-Content -LiteralPath (Join-Path $dc 'settings.json') -Value ('{"env":{"TOKEN_GIA":"BiMatClaudeGia_444"},"dir":"' + $OldProfileInText.Replace('\', '\\') + '\\DuAn"}') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $dc 'CLAUDE.md') -Value "Ghi chú $OldProfileInText\DuAn" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $dc '.credentials.json') -Value '{"token":"KhongDuocSaoLuu_555"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $dc 'cache\x.bin') -Value 'cache' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $dc "projects\$pn\phien-1.jsonl") -Value '{"type":"user","message":{"role":"user","content":"xin chao"},"timestamp":"2026-10-01T01:00:00Z"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $H '.claude.json') -Value ('{"mcpServers":{"x":{"env":{"KEY":"BiMatMcpGia_666"}}},"projects":{}}') -Encoding UTF8
    $desk = Join-Path $H 'AppData\Local\Packages\Claude_gia123\LocalCache\Roaming\Claude'
    New-Item -ItemType Directory -Force -Path (Join-Path $desk 'claude-code-sessions\a') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $desk 'Claude Extensions Settings') | Out-Null
    Set-Content -LiteralPath (Join-Path $desk 'claude_desktop_config.json') -Value '{"mcpServers":{"y":{"env":{"API":"BiMatDesktopGia_777"}}}}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $desk 'Claude Extensions Settings\ext.json') -Value '{"apiKey":"BiMatExtGia_888"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $desk 'claude-code-sessions\a\local_1.json') -Value ('{"sessionId":"local_1","cliSessionId":"phien-1","title":"Phien thu","cwd":"' + $OldProfileInText.Replace('\', '\\') + '\\DuAn","lastActivityAt":1759280400000,"createdAt":1759280000000}') -Encoding UTF8
}

function Find-Text([string]$Dir, [string]$Text) {
    # Các file trong $Dir có chứa $Text (UTF-8 hoặc UTF-16)
    $hits = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $b = [IO.File]::ReadAllBytes($f.FullName)
        $s8 = [Text.Encoding]::UTF8.GetString($b); $s16 = [Text.Encoding]::Unicode.GetString($b)
        if ($s8.Contains($Text) -or $s16.Contains($Text)) { $hits += $f.FullName }
    }
    return $hits
}
