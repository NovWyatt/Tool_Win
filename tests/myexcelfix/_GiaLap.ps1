# Test helpers for MyExcelFix. Everything lives in the test temp folder and HKCU\Software\TramToolTest:
# the .bat files are pointed there with MYX_* variables (registry base, output, candidate folders, TEMP, APPDATA).
# Load after KiemThu.ps1:  . "$PSScriptRoot\_GiaLap.ps1"
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$script:Tool = "$ToolsDir\myexcelfix"

function Test-ExcelOpenHere {
    # The fix waits for Excel of this session to close; with MYX_AUTO it stops instead. Skip rather than fail.
    $sid = (Get-Process -Id $PID).SessionId
    return [bool]@(Get-Process -Name 'EXCEL' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sid }).Count
}

function Invoke-Bat([string]$Bat, [string[]]$BatArgs = @(), [hashtable]$Env = @{}, [string]$StdIn = '', [int]$TimeoutSec = 240) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:SystemRoot\System32\cmd.exe"
    $psi.Arguments = '/d /c ""' + $Bat + '"' + (($BatArgs | ForEach-Object { ' "' + $_ + '"' }) -join '') + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    foreach ($k in $Env.Keys) { if ([string]$Env[$k]) { $psi.EnvironmentVariables[$k] = [string]$Env[$k] } else { $psi.EnvironmentVariables.Remove($k) } }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if ($StdIn) { $p.StandardInput.Write($StdIn) }
    $p.StandardInput.Close()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) { & taskkill.exe /T /F /PID $p.Id | Out-Null; throw "TIMEOUT after $TimeoutSec s: $Bat" }
    $p.WaitForExit()
    [pscustomobject]@{ Code = $p.ExitCode; Out = $o.Result; Err = $e.Result; Sec = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
}

function New-Zip([string]$Path, [hashtable]$Entries) {
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    $z = [IO.Compression.ZipFile]::Open($Path, 'Create')
    try {
        foreach ($k in $Entries.Keys) { $en = $z.CreateEntry($k); $w = New-Object IO.StreamWriter($en.Open()); $w.Write($Entries[$k]); $w.Close() }
    } finally { $z.Dispose() }
}

function Edit-Zip([string]$Path) {
    # Simulates the user typing more data into the workbook after the fix
    $z = [IO.Compression.ZipFile]::Open($Path, 'Update')
    try { $en = $z.CreateEntry('xl/worksheets/sheet2.xml'); $w = New-Object IO.StreamWriter($en.Open()); $w.Write('<sheet>du lieu nhap them</sheet>'); $w.Close() } finally { $z.Dispose() }
}

function Get-ZipText([string]$Path, [string]$Entry) {
    $z = [IO.Compression.ZipFile]::OpenRead($Path)
    try { $en = $z.GetEntry($Entry); if (-not $en) { return $null }; $r = New-Object IO.StreamReader($en.Open()); $t = $r.ReadToEnd(); $r.Close(); return $t } finally { $z.Dispose() }
}

function Get-Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

function New-Fixture([string]$Root, [string]$RegBase) {
    if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
    $good = Join-Path $Root 'MyExcel'; $old = Join-Path $Root 'MyExcel_old'
    foreach ($d in $good, $old) {
        New-Item -ItemType Directory -Path (Join-Path $d 'MiniTool') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $d 'MyExcel.xlam') -Value 'xlam' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $d 'MiniTool\QRCodeLib.xlam') -Value 'qr' -Encoding ASCII
    }
    Set-Content -LiteralPath (Join-Path $good 'MyExcel.xlam') -Stream 'Zone.Identifier' -Value "[ZoneTransfer]`r`nZoneId=3"
    $scan = Join-Path $Root 'scan'
    New-Item -ItemType Directory -Path $scan -Force | Out-Null
    $rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/externalLinkPath" Target="file:///' + $old + '\MiniTool\QRCodeLib.xlam" TargetMode="External"/></Relationships>'
    foreach ($n in 'SoQuy.xlsx', 'HoaDon.xlsx') {
        New-Zip (Join-Path $scan $n) @{ '[Content_Types].xml' = '<Types/>'; 'xl/externalLinks/_rels/externalLink1.xml.rels' = $rels; 'xl/workbook.xml' = "<workbook name='$n'/>" }
    }
    New-Item -ItemType Directory -Path (Join-Path $Root 'env\temp\VBE'), (Join-Path $Root 'env\appdata'), (Join-Path $Root 'out') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Root 'env\temp\VBE\MSForms.exd') -Value 'exd'
    $hk = [Microsoft.Win32.Registry]::CurrentUser
    $hk.DeleteSubKeyTree($RegBase.TrimEnd('\'), $false)
    $opt = $hk.CreateSubKey($RegBase + 'Software\Microsoft\Office\16.0\Excel\Options')
    $opt.SetValue('OPEN', '/R "' + $old + '\MyExcel.xlam"'); $opt.Close()
    $vb = $RegBase + 'Software\VB and VBA Program Settings\liliiliiliiiliilli'
    # Synthetic bank data only
    $k = $hk.CreateSubKey("$vb\GridLight"); $k.SetValue('TenTKQRG', 'NGUOI THU NGHIEM'); $k.SetValue('SoTKQRG', '000011112222'); $k.SetValue('MaNganhangDongDauQR1', 'A0000007270124000697041601'); $k.Close()
    $k = $hk.CreateSubKey("$vb\InVung"); $k.SetValue('AndanInNgayCai', '30.5.2025'); $k.Close()
    $k = $hk.CreateSubKey("$vb\CaiDat"); $k.SetValue('DuongDanADDin', $old + '\'); $k.Close()
}

function Get-FixEnv([string]$Root, [string]$RegBase, [bool]$Auto = $true) {
    $e = @{
        MYX_REGBASE = $RegBase; MYX_OUT = (Join-Path $Root 'out'); MYX_PREFERRED = (Join-Path $Root 'MyExcel')
        MYX_CANDIDATES = (Join-Path $Root 'MyExcel') + ';' + (Join-Path $Root 'MyExcel_old'); MYX_SCANROOT = (Join-Path $Root 'scan')
        MYX_RESET_NOW = '1'; MYX_QR_OK = '1'; MYX_NOPAUSE = '1'; MYX_NO_NOTEPAD = '1'
        TEMP = (Join-Path $Root 'env\temp'); TMP = (Join-Path $Root 'env\temp'); APPDATA = (Join-Path $Root 'env\appdata')
        MYX_AUTO = ''
    }
    if ($Auto) { $e.MYX_AUTO = '1' }
    return $e
}

function Get-RegVal([string]$Sub, [string]$Name) {
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Sub)
    if (-not $k) { return $null }
    try { return $k.GetValue($Name) } finally { $k.Close() }
}
