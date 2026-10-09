@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title GIAI MA WHEA - xac dinh bo phan phan cung nao dang loi (v1.0)

set "SELF=%~f0"
set "OUTDIR=%~dp0"
if "%OUTDIR:~-1%"=="\" set "OUTDIR=%OUTDIR:~0,-1%"

echo.
echo  ==========================================================================
echo    GIAI MA BAN GHI LOI PHAN CUNG (WHEA / CPER)
echo  --------------------------------------------------------------------------
echo    Doc truc tiep du lieu nhi phan trong nhat ky WHEA de biet
echo    loi "fatal hardware error" den tu: CPU, RAM, khe PCIe hay o dia.
echo    Script CHI DOC. Chay khoang 10-30 giay.
echo  ==========================================================================
echo.

where powershell >nul 2>&1
if errorlevel 1 goto :ERR_NOPS

rem fltmc chi chay duoc bang quyen Admin va khong can dich vu Server (net session thi can).
fltmc >nul 2>&1
if not errorlevel 1 goto :ADMIN_OK
if /i "%~1"=="/danangquyen" goto :ERR_ADMIN
echo  [*] Can quyen Administrator. Dang mo lai bang quyen Admin, vui long bam YES...
powershell -NoProfile -Command "try { $p = Start-Process -FilePath $env:SELF -ArgumentList '/danangquyen' -Verb RunAs -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode } catch { exit 1223 }"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="1223" exit /b %RC%
echo.
echo  [!] Khong nang duoc quyen Admin (da bam No o hop thoai UAC?).
echo      Hay chuot phai vao file nay, chon "Run as administrator".
echo.
pause
exit /b 2

:ERR_ADMIN
echo  [X] Da mo lai bang quyen Admin ma van chua co quyen. Dung lai de khong hoi UAC mai.
pause
exit /b 2

:ADMIN_OK
set "PS1=%TEMP%\CWF_Whea_%RANDOM%.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$r=Get-Content -LiteralPath $env:SELF -Raw -Encoding UTF8; $m='#====='+'PS_START'+'====='; $i=$r.IndexOf($m); if($i -lt 0){exit 1}; [IO.File]::WriteAllText($env:PS1, $r.Substring($i+$m.Length), (New-Object Text.UTF8Encoding $true)); exit 0"
if errorlevel 1 goto :ERR_SPLIT

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -OutDir "%OUTDIR%"
set "RC=%ERRORLEVEL%"
del /f /q "%PS1%" >nul 2>&1
echo.
pause
exit /b %RC%

:ERR_NOPS
echo  [X] Khong tim thay PowerShell.
pause
exit /b 1

:ERR_SPLIT
echo  [X] Khong tach duoc phan PowerShell (file bi luu sai bang ma).
pause
exit /b 1

#=====PS_START=====
<#
  Giai ma WHEA_ERROR_RECORD (chuan UEFI CPER) tu nhat ky su kien Windows.
  Chi doc, khong thay doi gi.
#>
param([string]$OutDir = "")

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$SB = New-Object System.Text.StringBuilder
function W { param([string]$t = '') [void]$SB.AppendLine($t) }
function HDR { param([string]$t) W ''; W ('=' * 88); W ("  $t"); W ('=' * 88) }
function S { param([string]$t) W ''; W ("  --- $t " + ('-' * [Math]::Max(1, 74 - $t.Length))) }
function KV { param($k, $v) W ("    {0,-26}: {1}" -f $k, $v) }

if ([string]::IsNullOrWhiteSpace($OutDir) -or -not (Test-Path -LiteralPath $OutDir)) { $OutDir = Join-Path $env:USERPROFILE 'Desktop' }
$out = Join-Path $OutDir ("WheaDecode_{0}_{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))

# --------- Bang tra GUID -------------------------------------------------------
$NOTIF = @{
  '2dce8bb1-bdd7-450e-b9ad-9cf4ebd4f890' = 'CMC  - Corrected Machine Check (CPU/RAM, da tu sua duoc)'
  '4e292f96-d843-4a55-a8c2-d481f27ebeee' = 'CPE  - Corrected Platform Error'
  'e8f56ffe-919c-4cc5-ba88-65abe14913bb' = 'MCE  - Machine Check Exception  >>> CPU hoac RAM <<<'
  'cf93c01f-1a16-4dfc-b8bc-9c4daf67c104' = 'PCIe - loi khe/thiet bi PCI Express'
  'cc5263e8-9308-454a-89d0-340bd39bc7df' = 'INIT - tin hieu INIT'
  '5bad89ff-b7e6-42c9-814a-cf2485d6e98a' = 'NMI  - Non-Maskable Interrupt'
  '3d61a466-ab40-409a-a698-f362d464b38f' = 'BOOT - loi do firmware/BIOS bao lai luc khoi dong'
  '667dd791-c6b3-4c27-8a6b-0f8e722deb41' = 'DMAr - loi DMA remapping (IOMMU/VT-d)'
  '9a78788a-bbe8-11e4-809e-67611e5d46b0' = 'SEA  - Synchronous External Abort'
  '5c284c81-b0ae-4e87-a322-b04c85624323' = 'SEI  - SError Interrupt'
  '09a9d5ac-5204-4214-96e5-94992e752bcd' = 'PEI  - Platform Error Interrupt'
}
$SECT = @{
  '9876ccad-47b4-4bdb-b65e-16f193c4f3db' = 'Processor Generic          >>> CPU <<<'
  'dc3ea0b0-a144-4797-b95b-53fa242b6e1d' = 'Processor Specific x86/x64 >>> CPU <<<'
  'e429faf1-3cb7-11d4-bca7-0080c73c8881' = 'Processor Specific IPF'
  'a5bc1114-6f64-4ede-b863-3e83ed7c83b1' = 'Platform Memory            >>> RAM <<<'
  '61ec04fc-48e6-d813-25c9-8daa44750b12' = 'Platform Memory 2          >>> RAM <<<'
  'd995e954-bbc1-430f-ad91-b44dcb3c6f35' = 'PCI Express                >>> khe PCIe <<<'
  'c5753963-3b84-4095-bf78-eddad3f9c9dd' = 'PCI/PCI-X Bus              >>> bus PCI <<<'
  'eb5e4685-ca66-4769-b6a2-26068b001326' = 'PCI Component              >>> thiet bi PCI <<<'
  '81212a96-09ed-4996-9471-8d729c8e69ed' = 'Firmware Error Record      >>> BIOS/firmware <<<'
  '5b51fef7-c79d-4434-8f1b-aa62de3e2c64' = 'DMAr Generic'
  '71761d37-32b2-45cd-a7d0-b0fedd93e8cf' = 'Intel VT for Directed I/O'
  '036f84e1-7f37-428c-a79e-575fdfaa84ec' = 'IOMMU'
  '8a1e1d01-42f9-4557-9c33-565e5cc3f7e8' = 'XPF MCA (Microsoft)        >>> CPU/RAM <<<'
  'e71254e7-c1b9-4940-ab76-909703a4320f' = 'NMI (Microsoft)'
  'e71254e8-c1b9-4940-ab76-909703a4320f' = 'Generic Error (Microsoft)'
  'e71254e9-c1b9-4940-ab76-909703a4320f' = 'WHEA Error Packet (Microsoft) - goi loi chung, doc them PortType/BusId'
  'c34832a1-02c3-4c52-a9f1-9f1d5d7723fc' = 'WHEA Recovery Info (Microsoft)'
  '6f3380d1-6eb0-497f-a578-4d4c65a71617' = 'IPF SAL Record'
}
$SEV = @{ 0 = 'Recoverable (co the phuc hoi)'; 1 = 'FATAL (nghiem trong)'; 2 = 'Corrected (da tu sua)'; 3 = 'Informational (chi thong bao)' }

function GuidAt {
  param([byte[]]$b, [int]$o)
  if (($o + 16) -gt $b.Length) { return $null }
  $g = New-Object byte[] 16
  [Array]::Copy($b, $o, $g, 0, 16)
  return (New-Object System.Guid (, $g)).ToString()
}
function HexDump {
  param([byte[]]$b, [int]$o, [int]$len)
  $end = [Math]::Min($o + $len, $b.Length)
  $sb2 = New-Object System.Text.StringBuilder
  for ($i = $o; $i -lt $end; $i += 16) {
    $line = '      {0:x4}  ' -f ($i - $o)
    $txt = ''
    for ($j = 0; $j -lt 16; $j++) {
      if (($i + $j) -lt $end) {
        $line += '{0:x2} ' -f $b[$i + $j]
        $c = $b[$i + $j]
        if ($c -ge 32 -and $c -lt 127) { $txt += [char]$c } else { $txt += '.' }
      } else { $line += '   ' }
    }
    [void]$sb2.AppendLine($line + ' ' + $txt)
  }
  return $sb2.ToString().TrimEnd()
}

W ('#' * 88)
W '#  GIAI MA BAN GHI LOI PHAN CUNG WHEA (chuan UEFI CPER)'
W ("#  May: {0}   Thoi diem: {1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
W ('#' * 88)

Write-Host '  >> Dang doc nhat ky WHEA...' -ForegroundColor Cyan
$evs = @()
try {
  $evs = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = (Get-Date).AddDays(-60) } -MaxEvents 300 -ErrorAction Stop)
} catch {}
if ($evs.Count -eq 0) {
  W ''
  W '  Khong tim thay su kien WHEA nao trong 60 ngay (hoac thieu quyen Admin).'
  try { [IO.File]::WriteAllText($out, $SB.ToString(), (New-Object System.Text.UTF8Encoding $true)) } catch { Write-Host ('  [X] Khong ghi duoc bao cao ' + $out + ': ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
  Write-Host "  Khong co su kien WHEA. Bao cao: $out" -ForegroundColor Yellow
  exit 0
}

HDR '1. TONG QUAN'
KV 'Tong so su kien WHEA' $evs.Count
KV 'Cu nhat'  ('{0:yyyy-MM-dd HH:mm:ss}' -f ($evs | Select-Object -Last 1).TimeCreated)
KV 'Moi nhat' ('{0:yyyy-MM-dd HH:mm:ss}' -f ($evs | Select-Object -First 1).TimeCreated)
S 'Nhom theo Event ID'
foreach ($g in ($evs | Group-Object Id | Sort-Object Count -Descending)) {
  W ('    ID {0,-6} x {1,4} lan' -f $g.Name, $g.Count)
}

Write-Host '  >> Dang giai ma du lieu nhi phan...' -ForegroundColor Cyan
HDR '2. GIAI MA TUNG BAN GHI (toi da 25 ban ghi moi nhat)'

$tallyNotif = @{}
$tallySect  = @{}
$n = 0
foreach ($e in ($evs | Select-Object -First 25)) {
  $n++
  W ''
  W ('  ###### [{0}] {1:yyyy-MM-dd HH:mm:ss}  Event ID {2}  ({3}) ######' -f $n, $e.TimeCreated, $e.Id, $e.LevelDisplayName)

  # lay RawData
  $hex = $null
  try {
    $x = [xml]$e.ToXml()
    foreach ($d in $x.Event.EventData.Data) {
      if ("$($d.Name)" -eq 'RawData') { $hex = "$($d.'#text')" }
    }
  } catch {}
  if ([string]::IsNullOrWhiteSpace($hex)) { W '    (su kien nay khong co RawData)'; continue }

  $hex = ($hex -replace '[^0-9A-Fa-f]', '')
  if ($hex.Length -lt 256) { W ('    (RawData qua ngan: ' + $hex.Length + ' ky tu hex)'); continue }
  $by = New-Object byte[] ($hex.Length / 2)
  for ($i = 0; $i -lt $by.Length; $i++) { $by[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16) }

  $sig = [Text.Encoding]::ASCII.GetString($by, 0, 4)
  if ($sig -ne 'CPER') {
    W ("    Chu ky khong phai CPER (thay '$sig'). 64 byte dau:")
    W (HexDump $by 0 64)
    continue
  }

  $revision   = [BitConverter]::ToUInt16($by, 4)
  $sectCount  = [BitConverter]::ToUInt16($by, 10)
  $severity   = [BitConverter]::ToUInt32($by, 12)
  $recLen     = [BitConverter]::ToUInt32($by, 20)
  $notifGuid  = GuidAt $by 0x50
  $creatorId  = GuidAt $by 0x40
  $platformId = GuidAt $by 0x20

  $sevTxt = 'khong ro'
  if ($SEV.ContainsKey([int]$severity)) { $sevTxt = $SEV[[int]$severity] }
  $notifTxt = 'KHONG CO TRONG BANG TRA'
  if ($notifGuid -and $NOTIF.ContainsKey($notifGuid)) { $notifTxt = $NOTIF[$notifGuid] }

  KV 'Do dai ban ghi'   ("{0} byte (nhan duoc {1})" -f $recLen, $by.Length)
  KV 'Muc do nghiem trong' ("{0} = {1}" -f $severity, $sevTxt)
  KV 'So section'       $sectCount
  KV 'NotificationType' $notifGuid
  W  ("      >>> LOAI LOI: {0}" -f $notifTxt)
  KV 'CreatorId'        $creatorId
  KV 'PlatformId'       $platformId

  if (-not $tallyNotif.ContainsKey($notifTxt)) { $tallyNotif[$notifTxt] = 0 }
  $tallyNotif[$notifTxt]++

  # section descriptors bat dau o 0x80
  for ($s = 0; $s -lt [Math]::Min($sectCount, 8); $s++) {
    $d0 = 0x80 + ($s * 72)
    if (($d0 + 72) -gt $by.Length) { W '      (thieu du lieu section descriptor)'; break }
    $secOff  = [BitConverter]::ToUInt32($by, $d0)
    $secLen  = [BitConverter]::ToUInt32($by, $d0 + 4)
    $secType = GuidAt $by ($d0 + 16)
    $secSev  = [BitConverter]::ToUInt32($by, $d0 + 48)
    $fru     = ''
    try { $fru = ([Text.Encoding]::ASCII.GetString($by, $d0 + 52, 20) -replace "`0", '').Trim() } catch {}
    $secTxt = 'KHONG CO TRONG BANG TRA'
    if ($secType -and $SECT.ContainsKey($secType)) { $secTxt = $SECT[$secType] }
    $secSevTxt = 'khong ro'
    if ($SEV.ContainsKey([int]$secSev)) { $secSevTxt = $SEV[[int]$secSev] }

    W ''
    W ("    -- Section {0} --" -f ($s + 1))
    KV '  SectionType'  $secType
    W  ("        >>> BO PHAN: {0}" -f $secTxt)
    KV '  Muc do'       $secSevTxt
    KV '  Offset / Len' ("{0} / {1} byte" -f $secOff, $secLen)
    if ($fru) { KV '  FRUText' $fru }

    $key = $secTxt
    if (-not $tallySect.ContainsKey($key)) { $tallySect[$key] = 0 }
    $tallySect[$key]++

    if (($secOff + 16) -gt $by.Length) { W '        (section nam ngoai du lieu nhan duoc)'; continue }

    # Giai ma chi tiet mot so loai section
    if ($secType -eq 'd995e954-bbc1-430f-ad91-b44dcb3c6f35') {
      # PCI Express Error Section
      $portType = [BitConverter]::ToUInt32($by, $secOff + 8)
      $devOff = $secOff + 24
      if (($devOff + 16) -le $by.Length) {
        $ven = [BitConverter]::ToUInt16($by, $devOff)
        $dvc = [BitConverter]::ToUInt16($by, $devOff + 2)
        $func = $by[$devOff + 7]
        $devn = $by[$devOff + 8]
        $seg  = [BitConverter]::ToUInt16($by, $devOff + 9)
        $bus  = $by[$devOff + 11]
        KV '  PCIe VendorID' ('0x{0:x4}' -f $ven)
        KV '  PCIe DeviceID' ('0x{0:x4}' -f $dvc)
        KV '  PCIe Bus:Dev.Fn' ('{0:x2}:{1:x2}.{2}  (segment {3})' -f $bus, $devn, $func, $seg)
        KV '  PortType' $portType
        $pnp = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
               Where-Object { $_.DeviceID -match ('VEN_{0:X4}&DEV_{1:X4}' -f $ven, $dvc) } | Select-Object -First 1
        if ($pnp) { W ("        >>> THIET BI: " + $pnp.Name) }
      }
    }
    elseif ($secType -eq 'a5bc1114-6f64-4ede-b863-3e83ed7c83b1' -or $secType -eq '61ec04fc-48e6-d813-25c9-8daa44750b12') {
      # Platform Memory Error Section
      if (($secOff + 40) -le $by.Length) {
        $phys = [BitConverter]::ToUInt64($by, $secOff + 16)
        $node = [BitConverter]::ToUInt16($by, $secOff + 32)
        $card = [BitConverter]::ToUInt16($by, $secOff + 34)
        $modu = [BitConverter]::ToUInt16($by, $secOff + 36)
        $bank = [BitConverter]::ToUInt16($by, $secOff + 38)
        KV '  Dia chi vat ly' ('0x{0:x}' -f $phys)
        KV '  Node/Card/Module/Bank' ("{0}/{1}/{2}/{3}" -f $node, $card, $modu, $bank)
        W  '        >>> DAY LA LOI RAM. Can chay test bo nho.'
      }
    }
    W ('      64 byte dau cua section:')
    W (HexDump $by $secOff 64)
  }
}

HDR '3. KET LUAN'
S 'Dem theo LOAI LOI (NotificationType)'
foreach ($k in ($tallyNotif.GetEnumerator() | Sort-Object Value -Descending)) { W ('    {0,4} lan -> {1}' -f $k.Value, $k.Key) }
S 'Dem theo BO PHAN (SectionType)'
foreach ($k in ($tallySect.GetEnumerator() | Sort-Object Value -Descending)) { W ('    {0,4} lan -> {1}' -f $k.Value, $k.Key) }

S 'Doi chieu voi thoi diem khoi dong may'
W '  Neu loi WHEA xay ra DUNG luc bat may => la loi duoc firmware/BIOS bao lai,'
W '  thuong di kem thiet bi khoi tao that bai (o dia, card mo rong).'
W '  Neu xay ra giua luc dang chay => nghi CPU/RAM/nguon dien.'
W ''
$boots = @()
try { $boots = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 6005; StartTime = (Get-Date).AddDays(-60) } -MaxEvents 100 -ErrorAction Stop) } catch {}
$nearBoot = 0; $farBoot = 0
foreach ($e in ($evs | Where-Object { $_.Id -eq 1 })) {
  $min = 99999.0
  foreach ($b in $boots) {
    $diff = [Math]::Abs(($e.TimeCreated - $b.TimeCreated).TotalSeconds)
    if ($diff -lt $min) { $min = $diff }
  }
  if ($min -le 180) { $nearBoot++ } else { $farBoot++ }
  W ('    [{0:yyyy-MM-dd HH:mm:ss}] cach lan bat may gan nhat {1:N0} giay' -f $e.TimeCreated, $min)
}
W ''
KV 'Loi WHEA xay ra LUC KHOI DONG (trong 3 phut)' $nearBoot
KV 'Loi WHEA xay ra LUC DANG CHAY'                $farBoot

W ''
W '  --- Doc ket qua ---'
W '   * Neu thay "Platform Memory"  => RAM loi. Phai thay/test RAM.'
W '   * Neu thay "Processor ..."    => CPU loi.'
W '   * Neu thay "PCI Express" hoac "PCI Component" => xem dong ">>> THIET BI:" o tren.'
W '   * Neu chi thay "WHEA Error Packet (Microsoft)" va loi don vao luc khoi dong,'
W '     thuong la thiet bi khoi tao that bai - phu hop voi o cung dang hong.'

try { [IO.File]::WriteAllText($out, $SB.ToString(), (New-Object System.Text.UTF8Encoding $true)) } catch { Write-Host ('  [X] Khong ghi duoc bao cao ' + $out + ': ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
Write-Host ''
Write-Host ('  ' + ('=' * 72)) -ForegroundColor Green
Write-Host '   XONG. Bao cao luu tai:' -ForegroundColor Green
Write-Host ('   ' + $out) -ForegroundColor White
Write-Host ('  ' + ('=' * 72)) -ForegroundColor Green
Write-Host ''
foreach ($k in ($tallySect.GetEnumerator() | Sort-Object Value -Descending)) {
  Write-Host ('    {0,4} lan -> {1}' -f $k.Value, $k.Key) -ForegroundColor Yellow
}
Write-Host ''
try { Start-Process notepad.exe -ArgumentList ('"' + $out + '"') } catch {}
exit 0
