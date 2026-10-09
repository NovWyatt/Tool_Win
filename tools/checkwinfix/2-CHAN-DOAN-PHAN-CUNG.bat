@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title CHAN DOAN PHAN CUNG - WHEA / o dia / RAM (v1.0)

set "SELF=%~f0"
set "OUTDIR=%~dp0"
if "%OUTDIR:~-1%"=="\" set "OUTDIR=%OUTDIR:~0,-1%"

echo.
echo  ==========================================================================
echo    CHAN DOAN PHAN CUNG CHUYEN SAU
echo  --------------------------------------------------------------------------
echo    Xac dinh 16 loi "fatal hardware error" (WHEA) la do bo phan nao:
echo    o cung, RAM, CPU hay khe PCIe.
echo    Script CHI DOC. Cac buoc co the thay doi may deu se hoi truoc.
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
set "PS1=%TEMP%\CWF_HwDiag_%RANDOM%.ps1"
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
param([string]$OutDir = "")

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$SB = New-Object System.Text.StringBuilder
function W { param([string]$t = '') [void]$SB.AppendLine($t) }
function HDR { param([string]$t) W ''; W ('=' * 88); W ("  $t"); W ('=' * 88) }
function S { param([string]$t) W ''; W ("  --- $t " + ('-' * [Math]::Max(1, 76 - $t.Length))) }
function KV { param($k, $v) W ("  {0,-30}: {1}" -f $k, $v) }
function Step { param([string]$t) Write-Host ("  >> $t") -ForegroundColor Cyan }

if ([string]::IsNullOrWhiteSpace($OutDir) -or -not (Test-Path -LiteralPath $OutDir)) { $OutDir = Join-Path $env:USERPROFILE 'Desktop' }
$out = Join-Path $OutDir ("HwDiag_{0}_{1}.txt" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))

W ('#' * 88)
W '#  CHAN DOAN PHAN CUNG CHUYEN SAU'
W ("#  May: {0}   Thoi diem: {1}" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
W ('#' * 88)

# ============================ 1. BAN DO O DIA =================================
Step 'Lap ban do so hieu o dia (Disk 0/1/... la o nao)'
HDR '1. BAN DO O DIA - Disk N tuong ung o vat ly nao'
foreach ($d in (Get-CimInstance Win32_DiskDrive | Sort-Object Index)) {
  W ("  Disk {0} : {1}" -f $d.Index, $d.Model)
  KV '   PNPDeviceID'  $d.PNPDeviceID
  KV '   Interface'    $d.InterfaceType
  KV '   Kich thuoc'   ('{0:N2} GB' -f ($d.Size / 1GB))
  KV '   Trang thai'   $d.Status
  $parts = @()
  try {
    $parts = @(Get-Partition -DiskNumber $d.Index -ErrorAction Stop | Where-Object { $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter):" })
  } catch {
    foreach ($p in (Get-CimInstance -Query ("ASSOCIATORS OF {Win32_DiskDrive.DeviceID='" + $d.DeviceID.Replace('\', '\\') + "'} WHERE AssocClass=Win32_DiskDriveToDiskPartition"))) {
      foreach ($l in (Get-CimInstance -Query ("ASSOCIATORS OF {Win32_DiskPartition.DeviceID='" + $p.DeviceID + "'} WHERE AssocClass=Win32_LogicalDiskToPartition"))) { $parts += $l.DeviceID }
    }
  }
  KV '   Cac o logic'  (($parts | Sort-Object -Unique) -join ', ')
  W ''
}

# ============================ 2. LOI IO O DIA =================================
Step 'Thong ke loi doc/ghi o dia (Event 153/154/129/11/51/7)'
HDR '2. LOI PHAN CUNG O DIA TRONG NHAT KY (30 ngay)'
$STORPROV = '^(disk|Disk|storahci|stornvme|storport|partmgr|volmgr|volsnap|Volsnap|Ntfs|iaStor|msahci|EhStorClass|Microsoft-Windows-Ntfs|Microsoft-Windows-StorDiag|Microsoft-Windows-DiskDiagnostic)'
$dev = @()
try {
  $dev = @(Get-WinEvent -FilterHashtable @{LogName = 'System'; StartTime = (Get-Date).AddDays(-30); Level = 1, 2, 3 } -MaxEvents 6000 -ErrorAction Stop |
           Where-Object { $_.ProviderName -match $STORPROV })
} catch {}
if ($dev.Count -eq 0) { W '  (khong co su kien nao - tot)' }
else {
  KV 'Tong so su kien' $dev.Count
  S 'Nhom theo nguon + ID'
  foreach ($g in ($dev | Group-Object { "$($_.ProviderName)|$($_.Id)" } | Sort-Object Count -Descending)) {
    $f = $g.Group[0]
    W ('  {0,6} lan | {1,-22} ID {2,-5} | gan nhat {3:yyyy-MM-dd HH:mm}' -f $g.Count, $f.ProviderName, $f.Id, $f.TimeCreated)
  }
  S 'Loi thuoc ve o dia nao (tach theo so hieu Disk)'
  $byDisk = @{}
  $lbas = @{}
  foreach ($e in $dev) {
    $m = [regex]::Match("$($e.Message)", 'Disk\s+(\d+)')
    $k = 'khong ro'
    if ($m.Success) { $k = 'Disk ' + $m.Groups[1].Value }
    if (-not $byDisk.ContainsKey($k)) { $byDisk[$k] = 0 }
    $byDisk[$k]++
    $m2 = [regex]::Match("$($e.Message)", 'logical block address\s+(0x[0-9a-fA-F]+)')
    if ($m2.Success) {
      $lb = $m2.Groups[1].Value
      if (-not $lbas.ContainsKey($lb)) { $lbas[$lb] = 0 }
      $lbas[$lb]++
    }
  }
  foreach ($k in ($byDisk.Keys | Sort-Object)) { W ("  {0,-14} : {1} loi" -f $k, $byDisk[$k]) }
  S 'Cac vi tri (LBA) bi loi lap lai nhieu nhat'
  W '  LBA lap lai nhieu = vung sector hong co dinh. LBA rai rac = o dia hong toan dien.'
  W ''
  $i = 0
  foreach ($k in ($lbas.GetEnumerator() | Sort-Object Value -Descending)) {
    W ('  {0,-20} x {1} lan' -f $k.Key, $k.Value); $i++
    if ($i -ge 25) { break }
  }
  KV 'So vi tri LBA khac nhau' $lbas.Count
  S '10 su kien moi nhat'
  foreach ($e in ($dev | Select-Object -First 10)) {
    W ('  [{0:yyyy-MM-dd HH:mm:ss}] {1} ID {2}' -f $e.TimeCreated, $e.ProviderName, $e.Id)
    W ('      ' + (("$($e.Message)" -replace '\s+', ' ')))
  }
}

# ============================ 3. WHEA =========================================
Step 'Phan tich chi tiet loi WHEA (fatal hardware error)'
HDR '3. WHEA - LOI PHAN CUNG NGHIEM TRONG: DO BO PHAN NAO?'
$srcName = @{
  0 = 'MCE - Machine Check Exception (CPU hoac RAM)'
  1 = 'CMC - Corrected Machine Check (CPU/RAM, da tu sua)'
  2 = 'CPE - Corrected Platform Error'
  3 = 'NMI - Non-Maskable Interrupt'
  4 = 'PCIe - loi khe/thiet bi PCI Express (card man hinh, card mo rong, SSD NVMe)'
  5 = 'Generic Hardware Error - loi phan cung chung (hay gap voi o dia/controller)'
  6 = 'INIT'
  7 = 'BOOT - loi luc khoi dong'
  8 = 'SCI Generic'
  12 = 'Generic V2'
}
$whea = @()
try { $whea = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = (Get-Date).AddDays(-30) } -MaxEvents 500 -ErrorAction Stop) } catch {}
if ($whea.Count -eq 0) { W '  (khong co su kien WHEA nao)' }
else {
  KV 'Tong so su kien WHEA' $whea.Count
  S 'Nhom theo Event ID'
  foreach ($g in ($whea | Group-Object Id | Sort-Object Count -Descending)) {
    W ('  ID {0,-6} x {1,4} lan' -f $g.Name, $g.Count)
  }
  S 'CHI TIET TUNG SU KIEN (20 cai moi nhat) - doc ky dong "ErrorSource"'
  $srcCount = @{}
  foreach ($e in ($whea | Select-Object -First 20)) {
    W ''
    W ('  [{0:yyyy-MM-dd HH:mm:ss}]  Event ID {1}  Level={2}' -f $e.TimeCreated, $e.Id, $e.LevelDisplayName)
    try {
      $x = [xml]$e.ToXml()
      foreach ($n in $x.Event.EventData.Data) {
        $nm = "$($n.Name)"
        $vl = "$($n.'#text')"
        if ($nm -eq 'ErrorSource') {
          $si = 0
          [void][int]::TryParse($vl, [ref]$si)
          $meaning = 'khong ro'
          if ($srcName.ContainsKey($si)) { $meaning = $srcName[$si] }
          W ("      {0,-24} = {1}   <<< {2}" -f $nm, $vl, $meaning)
          if (-not $srcCount.ContainsKey($meaning)) { $srcCount[$meaning] = 0 }
          $srcCount[$meaning]++
        }
        elseif ($vl.Length -gt 300) { W ("      {0,-24} = (du lieu nhi phan {1} ky tu)" -f $nm, $vl.Length) }
        else { W ("      {0,-24} = {1}" -f $nm, $vl) }
      }
    } catch { W ('      (khong doc duoc du lieu su kien)') }
    $msg = ("$($e.Message)" -replace '\s+', ' ')
    if ($msg.Length -gt 220) { $msg = $msg.Substring(0, 220) + '...' }
    W ('      Mo ta: ' + $msg)
  }
  S 'KET LUAN WHEA'
  if ($srcCount.Count -eq 0) { W '  (khong doc duoc truong ErrorSource - xem phan chi tiet o tren)' }
  foreach ($k in ($srcCount.GetEnumerator() | Sort-Object Value -Descending)) {
    W ("  {0,4} lan -> {1}" -f $k.Value, $k.Key)
  }
  W ''
  W '  Cach doc:'
  W '   - ErrorSource = 0 hoac 1 (MCE/CMC) => nghi CPU hoac RAM. Phai test RAM.'
  W '   - ErrorSource = 4 (PCIe)          => nghi khe PCIe / card mo rong / SSD NVMe.'
  W '   - ErrorSource = 5 hoac 7          => loi chung, thuong di kem o dia/controller.'
}

# ============================ 4. SMART ========================================
Step 'Doc lai SMART cua tung o dia'
HDR '4. SUC KHOE O DIA (SMART)'
foreach ($d in (Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
  S ("O #{0}: {1}  [{2} / {3}]" -f $d.DeviceId, $d.FriendlyName, $d.MediaType, $d.BusType)
  KV 'Health / Operational' ("{0} / {1}" -f $d.HealthStatus, ($d.OperationalStatus -join ','))
  $rc = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
  if ($rc) {
    KV 'Nhiet do'          ("{0} C" -f $rc.Temperature)
    KV 'Gio da chay'       $rc.PowerOnHours
    KV 'Loi doc'           ("Corrected={0} Uncorrected={1}" -f $rc.ReadErrorsCorrected, $rc.ReadErrorsUncorrected)
    KV 'Loi ghi'           ("Corrected={0} Uncorrected={1}" -f $rc.WriteErrorsCorrected, $rc.WriteErrorsUncorrected)
    KV 'Hao mon (%)'       $rc.Wear
  }
}
$names = @{ 1 = 'Raw_Read_Error_Rate'; 5 = 'Reallocated_Sectors'; 7 = 'Seek_Error_Rate'; 9 = 'Power_On_Hours'; 10 = 'Spin_Retry';
  184 = 'End_to_End_Error'; 187 = 'Reported_Uncorrectable'; 188 = 'Command_Timeout'; 194 = 'Temperature';
  196 = 'Realloc_Event_Count'; 197 = 'Current_Pending_Sector'; 198 = 'Offline_Uncorrectable'; 199 = 'UDMA_CRC_Error'
}
S 'Bang thuoc tinh SMART (Value thap gan Threshold = sap hong)'
foreach ($disk in (Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictData -ErrorAction SilentlyContinue)) {
  W ('  O dia: ' + $disk.InstanceName)
  $th = @{}
  foreach ($t in (Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictThresholds -ErrorAction SilentlyContinue)) {
    if ($t.InstanceName -ne $disk.InstanceName) { continue }
    $vv = $t.VendorSpecific
    for ($k = 0; $k -lt 30; $k++) {
      $b = 2 + 12 * $k
      if (($b + 1) -ge $vv.Count) { break }
      if ([int]$vv[$b] -ne 0) { $th[[int]$vv[$b]] = [int]$vv[$b + 1] }
    }
  }
  $v = $disk.VendorSpecific
  W ('    {0,-24} {1,-5} {2,-7} {3,-7} {4,-10} {5}' -f 'Thuoc tinh', 'ID', 'Value', 'Worst', 'Threshold', 'Raw')
  for ($k = 0; $k -lt 30; $k++) {
    $b = 2 + 12 * $k
    if (($b + 11) -ge $v.Count) { break }
    $id = [int]$v[$b]
    if ($id -eq 0) { continue }
    $raw = [uint64]0
    for ($j = 5; $j -ge 0; $j--) { $raw = $raw * 256 + [uint64]$v[$b + 5 + $j] }
    $nm = 'Attr_' + $id
    if ($names.ContainsKey($id)) { $nm = $names[$id] }
    $tv = ''
    if ($th.ContainsKey($id)) { $tv = $th[$id] }
    $mark = ''
    if ($th.ContainsKey($id) -and $th[$id] -gt 0) {
      if ([int]$v[$b + 3] -le $th[$id])      { $mark = '  <<< DANG HONG (Value <= Threshold)' }
      elseif ([int]$v[$b + 4] -le $th[$id])  { $mark = '  <<< DA TUNG CHAM NGUONG (Worst <= Threshold)' }
    }
    if ($id -in @(5, 187, 197, 198) -and $raw -gt 0) { $mark = '  <<< RAW > 0 - CO LOI THAT' }
    W ('    {0,-24} {1,-5} {2,-7} {3,-7} {4,-10} {5}{6}' -f $nm, $id, $v[$b + 3], $v[$b + 4], $tv, $raw, $mark)
  }
}

# ============================ 5. MAN HINH XANH ================================
Step 'Doc thong tin man hinh xanh (minidump)'
HDR '5. MAN HINH XANH (BSOD)'
$bug = @{
  '0x7e' = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED - mot driver gay loi truy cap bo nho'
  '0x50' = 'PAGE_FAULT_IN_NONPAGED_AREA - thuong do RAM loi hoac driver'
  '0x1e' = 'KMODE_EXCEPTION_NOT_HANDLED - driver loi'
  '0x7a' = 'KERNEL_DATA_INPAGE_ERROR - DOC KHONG DUOC DU LIEU TU O DIA (o dia/cap hong)'
  '0x77' = 'KERNEL_STACK_INPAGE_ERROR - loi doc o dia'
  '0xf4' = 'CRITICAL_OBJECT_TERMINATION - thuong do o dia/he thong file'
  '0x124' = 'WHEA_UNCORRECTABLE_ERROR - LOI PHAN CUNG (CPU/RAM/nguon/main)'
  '0x1a' = 'MEMORY_MANAGEMENT - thuong do RAM loi'
  '0x3b' = 'SYSTEM_SERVICE_EXCEPTION - driver loi'
  '0xc4' = 'DRIVER_VERIFIER_DETECTED_VIOLATION'
  '0x9f' = 'DRIVER_POWER_STATE_FAILURE'
  '0xef' = 'CRITICAL_PROCESS_DIED'
}
$bc = @()
try { $bc = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = (Get-Date).AddDays(-60) } -MaxEvents 50 -ErrorAction Stop) } catch {}
if ($bc.Count -eq 0) { W '  (khong co su kien bugcheck)' }
foreach ($e in $bc) {
  $msg = ("$($e.Message)" -replace '\s+', ' ')
  W ('  [{0:yyyy-MM-dd HH:mm}] {1}' -f $e.TimeCreated, $msg)
  $m = [regex]::Match($msg, 'bugcheck was:\s*(0x[0-9a-fA-F]+)')
  if ($m.Success) {
    $code = '0x' + ([Convert]::ToInt64($m.Groups[1].Value, 16)).ToString('x')
    if ($bug.ContainsKey($code)) { W ('      => ' + $bug[$code]) }
  }
}
S 'File dump co tren may'
foreach ($p in @("$env:SystemRoot\MEMORY.DMP", "$env:SystemRoot\Minidump")) {
  if (-not (Test-Path -LiteralPath $p)) { W "  $p : khong co"; continue }
  $it = Get-Item -LiteralPath $p -Force
  if ($it.PSIsContainer) {
    foreach ($f in (Get-ChildItem -LiteralPath $p -Filter *.dmp -Force | Sort-Object LastWriteTime -Descending | Select-Object -First 10)) {
      W ('  {0:yyyy-MM-dd HH:mm}  {1}  ({2:N1} MB)' -f $f.LastWriteTime, $f.FullName, ($f.Length / 1MB))
    }
  } else {
    W ('  {0:yyyy-MM-dd HH:mm}  {1}  ({2:N0} MB)' -f $it.LastWriteTime, $it.FullName, ($it.Length / 1MB))
  }
}
S 'Doc truc tiep ma loi tu file minidump'
foreach ($f in (Get-ChildItem -LiteralPath "$env:SystemRoot\Minidump" -Filter *.dmp -Force -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5)) {
  try {
    $by = [IO.File]::ReadAllBytes($f.FullName)
    if ($by.Length -lt 0x60) { continue }
    $sig = [Text.Encoding]::ASCII.GetString($by, 0, 8)
    $code = [BitConverter]::ToUInt32($by, 0x38)
    $p1 = [BitConverter]::ToUInt64($by, 0x40)
    $p2 = [BitConverter]::ToUInt64($by, 0x48)
    $p3 = [BitConverter]::ToUInt64($by, 0x50)
    $p4 = [BitConverter]::ToUInt64($by, 0x58)
    $hx = '0x' + ($code -band 0x0FFFFFFF).ToString('x')
    W ('  {0}  sig={1}' -f $f.Name, $sig)
    W ('     BugCheck = {0}  ({1})' -f $hx, $(if ($bug.ContainsKey($hx)) { $bug[$hx] } else { 'khong ro' }))
    W ('     Tham so  = 0x{0:x} 0x{1:x} 0x{2:x} 0x{3:x}' -f $p1, $p2, $p3, $p4)
  } catch { W ('  ' + $f.Name + ' : khong doc duoc') }
}

# ============================ 6. RAM ==========================================
Step 'Kiem tra RAM va ket qua test bo nho truoc do'
HDR '6. RAM'
foreach ($m in (Get-CimInstance Win32_PhysicalMemory)) {
  W ('  Khe {0} | {1:N0} GB | {2} MHz | {3} | {4} | SN {5}' -f $m.DeviceLocator, ($m.Capacity / 1GB), $m.ConfiguredClockSpeed, $m.Manufacturer, $m.PartNumber, $m.SerialNumber)
}
S 'Ket qua Windows Memory Diagnostic da chay truoc day'
$md = @()
try { $md = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } -MaxEvents 20 -ErrorAction Stop) } catch {}
if ($md.Count -eq 0) { W '  (chua bao gio chay test RAM tren may nay)' }
foreach ($e in $md) { W ('  [{0:yyyy-MM-dd HH:mm}] {1}' -f $e.TimeCreated, (("$($e.Message)" -replace '\s+', ' '))) }

# ============================ 7. TOM TAT ======================================
HDR '7. TOM TAT TU DONG'
$diskErrCount = $dev.Count
$wheaCount = $whea.Count
KV 'Loi IO o dia (30 ngay)' $diskErrCount
KV 'Loi WHEA (30 ngay)'     $wheaCount
KV 'So lan man hinh xanh'   $bc.Count
W ''
if ($diskErrCount -gt 50) {
  W '  >> CO RAT NHIEU LOI DOC/GHI O DIA. Day gan nhu chac chan la o cung hong.'
  W '     Viec can lam: cuu du lieu ngay, sau do THAY O CUNG. Khong co phan mem nao sua duoc.'
}
if ($wheaCount -gt 0) {
  W '  >> Co loi WHEA. Xem muc 3 de biet ErrorSource va suy ra bo phan hong.'
}

try { [IO.File]::WriteAllText($out, $SB.ToString(), (New-Object System.Text.UTF8Encoding $true)) } catch { Write-Host ('  [X] Khong ghi duoc bao cao ' + $out + ': ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
Write-Host ''
Write-Host ('  ' + ('=' * 72)) -ForegroundColor Green
Write-Host '   XONG. Bao cao luu tai:' -ForegroundColor Green
Write-Host ('   ' + $out) -ForegroundColor White
Write-Host ('  ' + ('=' * 72)) -ForegroundColor Green
Write-Host ''
Write-Host '   Gui file nay lai de duoc phan tich.' -ForegroundColor Cyan
Write-Host ''
try { Start-Process notepad.exe -ArgumentList ('"' + $out + '"') } catch {}
exit 0
