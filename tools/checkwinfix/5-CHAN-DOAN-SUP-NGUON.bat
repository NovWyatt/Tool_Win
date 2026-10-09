@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title CHAN DOAN MAY SUP NGUON / TU TAT / TU KHOI DONG LAI (v1.2)

set "SELF=%~f0"
set "OUTDIR=%~dp0"
if "%OUTDIR:~-1%"=="\" set "OUTDIR=%OUTDIR:~0,-1%"

echo.
echo  ==========================================================================
echo    CHAN DOAN MAY SUP NGUON / TU TAT / TU KHOI DONG LAI
echo  --------------------------------------------------------------------------
echo    Phan tich tung lan may tat dot ngot trong 60 ngay: mat dien that,
echo    man hinh xanh bi an, qua nhiet, bi giu nut nguon hay loi khi ngu.
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
set "PS1=%TEMP%\CWF_SupNguon_%RANDOM%.ps1"
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
param([string]$OutDir = "", [switch]$KhongHoi)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$SB = New-Object System.Text.StringBuilder
function W { param([string]$t = '') [void]$SB.AppendLine($t) }
function HDR { param([string]$t) W ''; W ('=' * 88); W ("  $t"); W ('=' * 88) }
function S { param([string]$t) W ''; W ("  --- $t " + ('-' * [Math]::Max(1, 76 - $t.Length))) }
function KV { param($k, $v) W ("  {0,-30}: {1}" -f $k, $v) }
function Step { param([string]$t) Write-Host ("  >> $t") -ForegroundColor Cyan }
function Cut { param([string]$t, [int]$n = 110) $t = ("$t" -replace '\s+', ' ').Trim(); if ($t.Length -gt $n) { $t.Substring(0, $n) + '...' } else { $t } }

$SCRIPT_VER = '1.2'
$T0 = Get-Date
#=====CHUNG_BAT_DAU=====
# Sinh tu src\Chung.ps1 bang src\build.ps1: sua o file do, dung sua o day.
# Phan dung chung cua cac script CheckWinFix (ThuThapThongTin.bat, 2-5). src\build.ps1 chep nguyen file nay vao
# giua hai dong dau moc CHUNG_BAT_DAU va CHUNG_KET_THUC cua moi .bat: moi .bat van chay doc lap (gui rieng cho
# khach duoc). Sua o day roi chay src\build.ps1, khong sua thang trong .bat.
# Script goi Save-KetQua phai dat truoc: $SCRIPT_VER, $T0 (gio bat dau), $OutDir, $isAdmin.

$script:FLAGS = New-Object System.Collections.ArrayList

function Test-QuyenAdmin {
  try { return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false }
}

function FLAG {
  # Phat hien cho Tram Tool: ma co dinh (khong doi khi sua chu), muc do (loi | canh-bao | thong-tin | ok), viec nen
  # chay tiep (<id cong cu>/<id action> trong Tram Tool), chi tiet. Cung cau thi chi ghi mot lan.
  param([string]$Ma, [string]$t, [string]$Muc = 'canh-bao', [string]$Tiep = '', [string]$ChiTiet = '')
  foreach ($x in $script:FLAGS) { if ($x.tieuDe -eq $t) { return } }
  $f = [ordered]@{ ma = $Ma; mucDo = $Muc; tieuDe = $t; chiTiet = $ChiTiet; cachSua = '' }
  if ($Tiep -match '^([a-z0-9-]+)/([A-Za-z0-9_-]+)$') { $f['chayTiep'] = [ordered]@{ congCu = $Matches[1]; action = $Matches[2] } }
  [void]$script:FLAGS.Add($f)
}

function Save-KetQua {
  # Ghi KetQua_CheckWinFix_<Ten>_<may>_<gio>.json (chuan tramtool.ketqua/1) canh bao cao: loi len dau. Tra duong dan, '' khi loi.
  param([string]$CheDo, [string]$Ten, [object[]]$Tep = @(), [string]$Message = '')
  $rank = @{ loi = 0; 'canh-bao' = 1; 'thong-tin' = 2; ok = 3 }
  $i = 0
  $sorted = @($script:FLAGS | ForEach-Object { [pscustomobject]@{ F = $_; L = $rank[[string]$_.mucDo]; I = $i++ } } | Sort-Object L, I | ForEach-Object { $_.F })
  $n = @{}
  foreach ($k in 'loi', 'canh-bao', 'thong-tin') { $n[$k] = @($sorted | Where-Object { $_.mucDo -eq $k }).Count }
  if (-not $Message) {
    $Message = if ($n['loi'] + $n['canh-bao']) { 'Có {0} lỗi, {1} cảnh báo; xem chi tiết và báo cáo.' -f $n['loi'], $n['canh-bao'] }
    elseif ($isAdmin) { 'Không thấy dấu hiệu bất thường qua các phép kiểm tự động.' } else { 'Chạy không có quyền Admin nên thiếu dữ liệu; chạy lại bằng quyền Admin.' }
  }
  $r = [ordered]@{
    chuan = 'tramtool.ketqua/1'; congCu = 'checkwinfix'; cheDo = $CheDo; phienBan = $SCRIPT_VER
    may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
    batDau = $T0.ToString('s'); ketThuc = (Get-Date).ToString('s')
    maThoat = 0; trangThai = 'xong'; chayThu = $false
    ma = $(if ($n['loi']) { 'CO_LOI' } elseif ($n['canh-bao']) { 'CO_CANH_BAO' } else { 'KHONG_CO_LOI' })
    thongDiep = $Message
    tomTat = [ordered]@{ loi = $n['loi']; canhBao = $n['canh-bao']; thongTin = $n['thong-tin'] }
    phatHien = $sorted
    tep = @($Tep)
    quyenAdmin = [bool]$isAdmin
  }
  $p = Join-Path $OutDir ('KetQua_CheckWinFix_{0}_{1}_{2}.json' -f $Ten, $env:COMPUTERNAME, $T0.ToString('yyyyMMdd_HHmmss'))
  try {
    [IO.File]::WriteAllText($p + '.tmp', ($r | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding $false))
    Move-Item -LiteralPath ($p + '.tmp') -Destination $p -Force -ErrorAction Stop
    return $p
  } catch { Write-Host ('  [!] Khong ghi duoc file ket qua JSON: ' + $_.Exception.Message) -ForegroundColor Yellow; return '' }
}

function Get-DiskBus {
  # Kieu ket noi cua o vat ly so N ('USB', 'NVMe', 'SATA'...); 'KHONG_CON' neu o khong con gan vao may (o rut ra);
  # '' neu khong doc duoc danh sach o.
  param([int]$Number)
  if ($null -eq $script:DiskBus) {
    $script:DiskBus = @{}
    try { foreach ($d in @(Get-Disk -ErrorAction Stop)) { $script:DiskBus[[int]$d.Number] = [string]$d.BusType } } catch { $script:DiskBus = @{ 'loi' = $true } }
  }
  if ($script:DiskBus.ContainsKey('loi')) { return '' }
  if ($script:DiskBus.ContainsKey($Number)) { return $script:DiskBus[$Number] }
  return 'KHONG_CON'
}

# ---- SMART (o ATA/SATA qua driver; NVMe va o USB thuong khong co bang nay)
$script:SMART_TEN = @{
  1 = 'Raw_Read_Error_Rate'; 5 = 'Reallocated_Sectors_Count'; 7 = 'Seek_Error_Rate'; 9 = 'Power_On_Hours'
  10 = 'Spin_Retry_Count'; 12 = 'Power_Cycle_Count'; 184 = 'End_to_End_Error'; 187 = 'Reported_Uncorrectable'
  188 = 'Command_Timeout'; 190 = 'Airflow_Temperature'; 194 = 'Temperature'; 196 = 'Reallocated_Event_Count'
  197 = 'Current_Pending_Sector'; 198 = 'Offline_Uncorrectable'; 199 = 'UDMA_CRC_Error_Count'
  200 = 'Multi_Zone_Error_Rate'; 231 = 'SSD_Life_Left'; 233 = 'Media_Wearout_Indicator'; 241 = 'Total_LBA_Written'
}

function ConvertFrom-SmartVendor {
  # Bang thuoc tinh tu VendorSpecific cua MSStorageDriver_FailurePredictData: 2 byte dau, roi 30 o x 12 byte
  # (ID, 2 byte co, Value, Worst, Raw 6 byte little-endian, 1 byte du). $Nguong: VendorSpecific cua
  # MSStorageDriver_FailurePredictThresholds cung o (ID, Threshold). Tra tung thuoc tinh co ID khac 0 (Nguong $null khi
  # khong co).
  param([byte[]]$Data = @(), [byte[]]$Nguong = @())
  $th = @{}
  for ($k = 0; $k -lt 30; $k++) {
    $b = 2 + 12 * $k
    if (($b + 1) -ge $Nguong.Count) { break }
    if ([int]$Nguong[$b] -ne 0) { $th[[int]$Nguong[$b]] = [int]$Nguong[$b + 1] }
  }
  for ($k = 0; $k -lt 30; $k++) {
    $b = 2 + 12 * $k
    if (($b + 11) -ge $Data.Count) { break }
    $id = [int]$Data[$b]
    if ($id -eq 0) { continue }
    $raw = [uint64]0
    for ($j = 5; $j -ge 0; $j--) { $raw = $raw * 256 + [uint64]$Data[$b + 5 + $j] }
    [pscustomobject]@{
      Id = $id; Ten = $(if ($script:SMART_TEN.ContainsKey($id)) { $script:SMART_TEN[$id] } else { 'Attr_' + $id })
      Value = [int]$Data[$b + 3]; Worst = [int]$Data[$b + 4]
      Nguong = $(if ($th.ContainsKey($id)) { $th[$id] } else { $null }); Raw = $raw
    }
  }
}

function Get-SmartThuocTinh {
  # Moi o co bang SMART: [pscustomobject]@{ O = InstanceName; ThuocTinh = @(ConvertFrom-SmartVendor) }. Can quyen Admin;
  # khong doc duoc thi khong tra gi.
  $nguong = @{}
  foreach ($t in @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictThresholds -OperationTimeoutSec 30 -ErrorAction SilentlyContinue)) {
    $nguong[[string]$t.InstanceName] = [byte[]]@($t.VendorSpecific)
  }
  foreach ($d in @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictData -OperationTimeoutSec 30 -ErrorAction SilentlyContinue)) {
    $ng = if ($nguong.ContainsKey([string]$d.InstanceName)) { $nguong[[string]$d.InstanceName] } else { [byte[]]@() }
    [pscustomobject]@{ O = [string]$d.InstanceName; ThuocTinh = @(ConvertFrom-SmartVendor -Data ([byte[]]@($d.VendorSpecific)) -Nguong $ng) }
  }
}
#=====CHUNG_KET_THUC=====
$isAdmin = Test-QuyenAdmin

$WARN = New-Object System.Collections.ArrayList
function Warn {
  # Ket luan tu dong: 3 nghiem trong, 2 dang ngo, 1 luu y. Ma, Tiep: phat hien cho Tram Tool (xem FLAG).
  param([int]$lvl, [string]$t, [string]$Ma = '', [string]$Tiep = '')
  [void]$WARN.Add([pscustomobject]@{ L = $lvl; T = $t; M = $Ma })
  FLAG $Ma $t -Muc (@{ 3 = 'loi'; 2 = 'canh-bao'; 1 = 'thong-tin' }[$lvl]) -Tiep $Tiep
}

function GetEv { param([hashtable]$f, [int]$max = 5000)
  try { @(Get-WinEvent -FilterHashtable $f -MaxEvents $max -ErrorAction Stop) } catch { @() } }
function EvData { param($e)
  $h = @{}
  try { $x = [xml]$e.ToXml(); foreach ($d in @($x.Event.EventData.Data)) { if ($d.Name) { $h[[string]$d.Name] = [string]$d.'#text' } } } catch {}
  $h }
function Span { param([TimeSpan]$t)
  if ($t.TotalDays -ge 1) { '{0}ngay {1}gio' -f [int][Math]::Floor($t.TotalDays), $t.Hours }
  elseif ($t.TotalHours -ge 1) { '{0}gio {1}phut' -f [int][Math]::Floor($t.TotalHours), $t.Minutes }
  else { '{0}phut' -f [int][Math]::Floor($t.TotalMinutes) } }

$BC = @{
  0x0A  = 'IRQL_NOT_LESS_OR_EQUAL | driver loi hoac RAM'
  0x19  = 'BAD_POOL_HEADER | driver hoac RAM'
  0x1A  = 'MEMORY_MANAGEMENT | RAM loi (hay gap)'
  0x1E  = 'KMODE_EXCEPTION_NOT_HANDLED | driver'
  0x3B  = 'SYSTEM_SERVICE_EXCEPTION | driver / phan mem diet virus'
  0x50  = 'PAGE_FAULT_IN_NONPAGED_AREA | RAM hoac driver'
  0x7A  = 'KERNEL_DATA_INPAGE_ERROR | O CUNG / cap SATA'
  0x7E  = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED | driver'
  0x8E  = 'KERNEL_MODE_EXCEPTION_NOT_HANDLED | driver hoac RAM'
  0x9C  = 'MACHINE_CHECK_EXCEPTION | PHAN CUNG: CPU / mainboard / nguon'
  0x9F  = 'DRIVER_POWER_STATE_FAILURE | driver loi khi ngu/thuc'
  0xA0  = 'INTERNAL_POWER_ERROR | loi quan ly nguon'
  0xC2  = 'BAD_POOL_CALLER | driver'
  0xD1  = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL | driver (mang, USB, VGA...)'
  0xEA  = 'THREAD_STUCK_IN_DEVICE_DRIVER | card man hinh'
  0xEF  = 'CRITICAL_PROCESS_DIED | file he thong / o cung'
  0xF4  = 'CRITICAL_OBJECT_TERMINATION | o cung / cap SATA'
  0x101 = 'CLOCK_WATCHDOG_TIMEOUT | CPU: ep xung, dien ap, nguon yeu'
  0x116 = 'VIDEO_TDR_FAILURE | card man hinh / driver VGA / nguon VGA'
  0x117 = 'VIDEO_TDR_TIMEOUT_DETECTED | card man hinh'
  0x119 = 'VIDEO_SCHEDULER_INTERNAL_ERROR | card man hinh'
  0x124 = 'WHEA_UNCORRECTABLE_ERROR | PHAN CUNG: CPU/RAM/nguon/qua nhiet'
  0x133 = 'DPC_WATCHDOG_VIOLATION | driver hoac firmware SSD'
  0x139 = 'KERNEL_SECURITY_CHECK_FAILURE | driver hoac RAM'
  0x154 = 'UNEXPECTED_STORE_EXCEPTION | o cung / SSD'
  0x15F = 'CONNECTED_STANDBY_WATCHDOG_TIMEOUT | loi khi ngu (Modern Standby)'
  0x19C = 'WIN32K_POWER_WATCHDOG_TIMEOUT | loi khi bat/tat man hinh, ngu'
  0x1A8 = 'BUGCODE_NDIS_DRIVER_LIVE_DUMP | driver mang'
}
function BcText { param($code)
  $c = [int]([uint64]$code -band 0x0FFFFFFF)
  $n = $BC[$c]; if (-not $n) { $n = '(ma it gap - tra Google)' }
  ('0x{0:X}  {1}' -f $c, $n) }

if ([string]::IsNullOrWhiteSpace($OutDir) -or -not (Test-Path -LiteralPath $OutDir)) { $OutDir = Join-Path $env:USERPROFILE 'Desktop' }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$out   = Join-Path $OutDir ("SupNguon_{0}_{1}.txt" -f $env:COMPUTERNAME, $stamp)
$DAYS  = 60
$since = (Get-Date).AddDays(-$DAYS)
$t0    = Get-Date
if (-not $isAdmin) { Warn 2 -Ma 'THIEU_QUYEN_ADMIN' 'Chay khong co quyen Admin nen thieu mot phan nhat ky va cai dat. Chuot phai file .bat > Run as administrator roi chay lai.' }

# =========================== 1. THONG TIN MAY ================================
Step 'Thong tin may'
HDR '1. THONG TIN MAY'
$cs   = Get-CimInstance Win32_ComputerSystem
$os   = Get-CimInstance Win32_OperatingSystem
$bios = Get-CimInstance Win32_BIOS
$bb   = Get-CimInstance Win32_BaseBoard
$cpu  = @(Get-CimInstance Win32_Processor)[0]
$enc  = @(Get-CimInstance Win32_SystemEnclosure)[0]
$bat  = @(Get-CimInstance Win32_Battery)
$isLaptop = $false
foreach ($ct in @($enc.ChassisTypes)) { if (@(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32) -contains [int]$ct) { $isLaptop = $true } }
if ($cs.PCSystemType -eq 2) { $isLaptop = $true }
KV 'Ten may'          $env:COMPUTERNAME
KV 'Hang / Model'     ("{0} / {1}" -f $cs.Manufacturer, $cs.Model)
KV 'Mainboard'        ("{0} {1}" -f $bb.Manufacturer, $bb.Product)
KV 'BIOS'             ("{0}  (ngay {1:yyyy-MM-dd})" -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate)
KV 'CPU'              $cpu.Name
KV 'RAM'              ('{0:N1} GB' -f ($cs.TotalPhysicalMemory / 1GB))
KV 'He dieu hanh'     ("{0}  build {1}" -f $os.Caption, $os.BuildNumber)
KV 'Loai may'         $(if ($isLaptop) { 'LAPTOP' } else { 'DESKTOP (may ban)' })
KV 'Khoi dong luc'    ('{0:yyyy-MM-dd HH:mm:ss}' -f $os.LastBootUpTime)
KV 'Da chay duoc'     (Span ((Get-Date) - $os.LastBootUpTime))
$oldest = $null
try { $oldest = (Get-WinEvent -LogName System -MaxEvents 1 -Oldest -ErrorAction Stop).TimeCreated } catch {}
KV 'Nhat ky System co tu' $(if ($oldest) { '{0:yyyy-MM-dd HH:mm}' -f $oldest } else { '(khong doc duoc)' })
if ($oldest -and $oldest -gt (Get-Date).AddDays(-7)) {
  Warn 1 -Ma 'NHAT_KY_QUA_NGAN' ("Nhat ky System chi luu tu {0:dd/MM} - qua ngan, co the da bi xoa hoac bi phan mem 'don dep' xoa. Ket qua thong ke chi tinh tu ngay do." -f $oldest)
}

# =========================== 2. TONG HOP SU KIEN =============================
Step 'Doc nhat ky bat/tat may 60 ngay'
$sys = GetEv @{ LogName = 'System'; StartTime = $since; Id = 41, 42, 105, 107, 109, 12, 13, 6005, 6006, 6008, 1074, 1001 } 30000
$k41   = @($sys | Where-Object { $_.Id -eq 41   -and $_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' } | Sort-Object TimeCreated -Descending)
$e6008 = @($sys | Where-Object { $_.Id -eq 6008 -and $_.ProviderName -eq 'EventLog' } | Sort-Object TimeCreated -Descending)
$e1074 = @($sys | Where-Object { $_.Id -eq 1074 -and $_.ProviderName -eq 'User32' } | Sort-Object TimeCreated -Descending)
$e1001 = @($sys | Where-Object { $_.Id -eq 1001 -and $_.ProviderName -match 'SystemErrorReporting|BugCheck' } | Sort-Object TimeCreated -Descending)
$boots = @($sys | Where-Object { $_.Id -eq 12   -and $_.ProviderName -eq 'Microsoft-Windows-Kernel-General' } | Sort-Object TimeCreated)
$e105  = @($sys | Where-Object { $_.Id -eq 105  -and $_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' } | Sort-Object TimeCreated)
$e42   = @($sys | Where-Object { $_.Id -eq 42   -and $_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' })
$whea  = GetEv @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since } 5000
$thr   = GetEv @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Processor-Power'; Id = 37; StartTime = $since } 5000
$kpBad = @(GetEv @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; StartTime = $since; Level = 1, 2, 3 } 5000 |
           Where-Object { $_.Id -ne 41 -and "$($_.Message)" -match 'thermal|nhi.t|temperature' })
$errs  = GetEv @{ LogName = 'System'; StartTime = $since; Level = 1, 2, 3 } 15000
$gpuE  = @($errs | Where-Object { $_.ProviderName -match '^(nvlddmkm|amdkmdag|amdwddmg|igfx|igfxn|igfxnd|Display|dxgkrnl)$' })
$dskE  = @($errs | Where-Object { ($_.ProviderName -match '^(disk|Disk|Ntfs|Microsoft-Windows-Ntfs|stornvme|storahci|storport|iaStorA?V?|volmgr)$') -and (@(7, 11, 15, 51, 55, 98, 129, 153, 154, 157) -contains $_.Id) })

HDR ("2. TONG HOP {0} NGAY QUA" -f $DAYS)
KV 'So lan khoi dong'                    $boots.Count
KV 'Tat DOT NGOT (Kernel-Power 41)'      $k41.Count
KV 'Tat khong dung cach (EventLog 6008)' $e6008.Count
KV 'Tat/khoi dong lai co chu dich (1074)' $e1074.Count
KV 'Man hinh xanh ghi nhan (1001)'       $e1001.Count
KV 'Loi phan cung WHEA'                  $whea.Count
KV 'CPU bi firmware bop xung (37)'       $thr.Count
KV 'Canh bao nhiet do'                   $kpBad.Count
KV 'Loi card man hinh (TDR...)'          $gpuE.Count
KV 'Loi o dia'                           $dskE.Count
KV 'Lan doi nguon AC/pin (105)'          $e105.Count

# =========================== 3. TUNG LAN SAP =================================
Step 'Phan tich tung lan sap nguon'
HDR '3. PHAN TICH TUNG LAN TAT DOT NGOT (Kernel-Power 41, moi nhat truoc)'
W '  Cot "Sap luc"  = thoi diem cua su kien CUOI CUNG Windows ghi duoc truoc khi tat (gan dung).'
W '  Cot "Chay duoc" = may da chay bao lau ke tu lan bat truoc do thi sap.'
W '  Loai:  MAT NGUON   = dien bi cat dot ngot, Windows khong kip ghi gi (PHAN CUNG / DIEN)'
W '         MAN HINH XANH = Windows bi loi nghiem trong roi tu khoi dong lai'
W '         GIU NUT NGUON = nguoi dung giu nut nguon de tat (thuong vi may bi TREO truoc do)'
W '         KHI NGU/THUC  = sap trong luc vao che do ngu / hibernate hoac luc danh thuc'
W ''
$crash = New-Object System.Collections.ArrayList
if ($k41.Count -eq 0) { W '  (khong co lan nao trong nhat ky)' }
$idx = 0
foreach ($e in ($k41 | Select-Object -First 40)) {
  $idx++
  $d = EvData $e
  $bc = [uint64]0; try { $bc = [uint64]$d['BugcheckCode'] } catch {}
  $pbt = "$($d['PowerButtonTimestamp'])"; $lp = "$($d['LongPowerButtonPressDetected'])"; $slp = "$($d['SleepInProgress'])"
  $boot = $null
  foreach ($b in $boots) { if ($b.TimeCreated -le $e.TimeCreated.AddSeconds(5)) { $boot = $b.TimeCreated } }
  if (-not $boot) { $boot = $e.TimeCreated.AddMinutes(-1) }
  $last = $null
  try { $last = Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $boot.AddDays(-45); EndTime = $boot.AddSeconds(-10) } -MaxEvents 1 -ErrorAction Stop } catch {}
  $crashAt = if ($last) { $last.TimeCreated } else { $null }
  $prevBoot = $null
  if ($crashAt) { foreach ($b in $boots) { if ($b.TimeCreated -lt $crashAt) { $prevBoot = $b.TimeCreated } } }
  $up = if ($crashAt -and $prevBoot) { $crashAt - $prevBoot } else { $null }
  $onBat = $null
  if ($crashAt) {
    $lastPs = $null; foreach ($p in $e105) { if ($p.TimeCreated -le $crashAt) { $lastPs = $p } }
    if ($lastPs) { $onBat = ((EvData $lastPs)['AcOnline'] -eq 'false') }
  }
  $type = 'MAT NGUON'
  if ($bc -ne 0) { $type = 'MAN HINH XANH' }
  elseif ($lp -eq 'true' -or ($pbt -and $pbt -ne '0')) { $type = 'GIU NUT NGUON' }
  elseif (($slp -and $slp -ne '0') -or ($last -and $last.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $last.Id -eq 42)) { $type = 'KHI NGU/THUC' }
  [void]$crash.Add([pscustomobject]@{ Reboot = $e.TimeCreated; CrashAt = $crashAt; Up = $up; Type = $type; Bc = $bc; OnBat = $onBat; Last = $last })
  W ('  #{0,-2} Bat lai {1:yyyy-MM-dd HH:mm} | Sap luc {2} | Chay duoc {3,-12} | {4}{5}' -f $idx, $e.TimeCreated,
     $(if ($crashAt) { '{0:dd/MM HH:mm:ss}' -f $crashAt } else { '   (?)        ' }),
     $(if ($up) { Span $up } else { '?' }), $type, $(if ($onBat) { '  [DANG CHAY PIN]' } else { '' }))
  if ($bc -ne 0) { W ('        Ma loi: ' + (BcText $bc)) }
  if ($last) { W ('        Su kien cuoi: {0} ID {1}: {2}' -f $last.ProviderName, $last.Id, (Cut $last.Message 80)) }
}

if ($crash.Count -gt 0) {
  S 'Thong ke'
  foreach ($g in ($crash | Group-Object Type | Sort-Object Count -Descending)) { W ('  {0,-15}: {1} lan' -f $g.Name, $g.Count) }
  $ups = @($crash | Where-Object { $_.Up } | ForEach-Object { $_.Up.TotalMinutes } | Sort-Object)
  if ($ups.Count -gt 0) {
    $med = $ups[[int][Math]::Floor($ups.Count / 2)]
    W ''
    KV 'Chay duoc ngan nhat'   (Span ([TimeSpan]::FromMinutes($ups[0])))
    KV 'Chay duoc trung vi'    (Span ([TimeSpan]::FromMinutes($med)))
    KV 'Chay duoc lau nhat'    (Span ([TimeSpan]::FromMinutes($ups[-1])))
    KV 'Sap trong 30 phut dau' ('{0} / {1} lan' -f @($ups | Where-Object { $_ -le 30 }).Count, $ups.Count)
  }
  S 'Sap theo gio trong ngay'
  $hrs = @($crash | Where-Object { $_.CrashAt } | Group-Object { $_.CrashAt.Hour } | Sort-Object { [int]$_.Name })
  foreach ($h in $hrs) { W ('  {0,2}h : {1} {2}' -f [int]$h.Name, ('#' * $h.Count), $h.Count) }
  S 'Sap theo ngay'
  foreach ($g in ($crash | Group-Object { $_.Reboot.ToString('yyyy-MM-dd') } | Sort-Object Name -Descending)) { W ('  {0} : {1} {2}' -f $g.Name, ('#' * $g.Count), $g.Count) }
}

if ($e6008.Count -gt 0) {
  S 'EventLog 6008 (Windows xac nhan lan tat truoc khong dung cach) - 10 gan nhat'
  foreach ($e in ($e6008 | Select-Object -First 10)) { W ('  {0:yyyy-MM-dd HH:mm} | {1}' -f $e.TimeCreated, (Cut $e.Message 90)) }
}

S 'Tat / khoi dong lai CO CHU DICH (User32 1074) - ai ra lenh'
if ($e1074.Count -eq 0) { W '  (khong co)' }
foreach ($g in ($e1074 | Group-Object { '{0} | {1}' -f $_.Properties[0].Value, $_.Properties[4].Value } | Sort-Object Count -Descending | Select-Object -First 12)) {
  $f = $g.Group[0]
  W ('  {0,4} lan | {1} | gan nhat {2:yyyy-MM-dd HH:mm} | ly do: {3}' -f $g.Count, (Cut $g.Name 60), $f.TimeCreated, (Cut $f.Properties[2].Value 50))
}

# =========================== 4. MAN HINH XANH & DUMP =========================
Step 'Man hinh xanh va file dump'
HDR '4. MAN HINH XANH (BSOD) VA FILE DUMP'
S 'BugCheck 1001 trong nhat ky'
if ($e1001.Count -eq 0) { W '  (khong co)' }
foreach ($e in ($e1001 | Select-Object -First 15)) {
  $m = [regex]::Match("$($e.Message)", '0x([0-9a-fA-F]{8})')
  $t = if ($m.Success) { BcText ([Convert]::ToUInt64($m.Groups[1].Value, 16)) } else { Cut $e.Message 80 }
  W ('  {0:yyyy-MM-dd HH:mm} | {1}' -f $e.TimeCreated, $t)
}
S 'Cau hinh ghi dump'
$cc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
$dumpTxt = @{ 0 = 'TAT - khong ghi dump (BSOD se khong de lai dau vet!)'; 1 = 'Complete'; 2 = 'Kernel'; 3 = 'Small (minidump)'; 7 = 'Automatic' }
KV 'CrashDumpEnabled' ("{0} = {1}" -f $cc.CrashDumpEnabled, $dumpTxt[[int]$cc.CrashDumpEnabled])
KV 'AutoReboot'       ("{0} = {1}" -f $cc.AutoReboot, $(if ($cc.AutoReboot -eq 1) { 'tu khoi dong lai ngay -> khong kip thay man hinh xanh' } else { 'dung lai o man hinh xanh' }))
$pf = @(Get-CimInstance Win32_PageFileUsage)
KV 'Pagefile' $(if ($pf.Count) { ($pf | ForEach-Object { "$($_.Name) $($_.AllocatedBaseSize)MB" }) -join ', ' } else { 'KHONG CO (khong ghi duoc dump)' })
S 'File minidump (C:\Windows\Minidump) - doc ma loi tu header'
$md = @(Get-ChildItem "$env:SystemRoot\Minidump" -Filter *.dmp -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
if ($md.Count -eq 0) { W '  (khong co file nao)' }
$mdCodes = @()
foreach ($f in ($md | Select-Object -First 20)) {
  $info = ''
  try {
    $fs = [IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite'); $buf = New-Object byte[] 0x60; [void]$fs.Read($buf, 0, 0x60); $fs.Close()
    $sig = [Text.Encoding]::ASCII.GetString($buf, 0, 8)
    $code = $null
    if ($sig -eq 'PAGEDU64') { $code = [BitConverter]::ToUInt32($buf, 0x38); $p1 = [BitConverter]::ToUInt64($buf, 0x40) }
    elseif ($sig -eq 'PAGEDUMP') { $code = [BitConverter]::ToUInt32($buf, 0x28); $p1 = [BitConverter]::ToUInt32($buf, 0x2C) }
    if ($null -ne $code) { $mdCodes += $code; $info = (BcText $code) + ('  P1=0x{0:X}' -f $p1) } else { $info = '(header la: ' + $sig + ')' }
  } catch { $info = '(khong doc duoc)' }
  W ('  {0:yyyy-MM-dd HH:mm} | {1,-22} | {2}' -f $f.LastWriteTime, $f.Name, $info)
}
$big = Get-Item "$env:SystemRoot\MEMORY.DMP" -ErrorAction SilentlyContinue
if ($big) { KV 'MEMORY.DMP' ('{0:yyyy-MM-dd HH:mm}  {1:N0} MB' -f $big.LastWriteTime, ($big.Length / 1MB)) }
S 'LiveKernelReports (loi nang nhung Windows tu phuc hoi: VGA, USB, watchdog)'
$lk = @(Get-ChildItem "$env:SystemRoot\LiveKernelReports" -Recurse -Filter *.dmp -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $since } | Sort-Object LastWriteTime -Descending)
if ($lk.Count -eq 0) { W '  (khong co)' }
foreach ($f in ($lk | Select-Object -First 15)) { W ('  {0:yyyy-MM-dd HH:mm} | {1}\{2}' -f $f.LastWriteTime, $f.Directory.Name, $f.Name) }

# =========================== 5. WHEA =========================================
Step 'Loi phan cung WHEA'
HDR '5. LOI PHAN CUNG WHEA'
if ($whea.Count -eq 0) { W '  (khong co - tot)' }
else {
  foreach ($g in ($whea | Group-Object Id | Sort-Object Count -Descending)) { W ('  ID {0,-4}: {1} lan, gan nhat {2:yyyy-MM-dd HH:mm}' -f $g.Name, $g.Count, $g.Group[0].TimeCreated) }
  S '10 ban ghi gan nhat'
  foreach ($e in ($whea | Select-Object -First 10)) { W ('  {0:yyyy-MM-dd HH:mm} ID {1,-3}| {2}' -f $e.TimeCreated, $e.Id, (Cut $e.Message 90)) }
  W ''
  W '  -> Chay them 3-GIAI-MA-WHEA.bat de biet dich danh CPU / RAM / PCIe nao loi.'
}

# =========================== 6. NHIET DO =====================================
Step 'Nhiet do va bop xung'
HDR '6. NHIET DO, BOP XUNG, TAI CPU / VGA'
S 'Cam bien nhiet ACPI (khong phai may nao cung co)'
$tzMax = $null; $tzCrit = $null
$tz = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature)
if ($tz.Count -eq 0) { W '  (mainboard khong cung cap - dung HWiNFO / Core Temp neu can do nhiet)' }
foreach ($z in $tz) {
  $c = [Math]::Round($z.CurrentTemperature / 10 - 273.15, 1); $k = [Math]::Round($z.CriticalTripPoint / 10 - 273.15, 1)
  if ($c -gt 0 -and $c -lt 150) { if ($null -eq $tzMax -or $c -gt $tzMax) { $tzMax = $c; $tzCrit = $k } }
  W ('  {0,-40} hien tai {1,5} C | nguong ngat {2} C' -f ($z.InstanceName -replace '^ACPI\\ThermalZone\\', ''), $c, $k)
}
S 'Hieu nang CPU hien tai'
$pi = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'"
KV 'Tai CPU'           ("{0} %" -f $pi.PercentProcessorTime)
KV '% hieu nang'       ("{0} %  (duoi 60% khi ranh la binh thuong, khi tai nang ma thap = bi bop)" -f $pi.PercentProcessorPerformance)
KV 'Xung thuc'         ("~{0} MHz / toi da {1} MHz" -f [int]($pi.ProcessorFrequency * $pi.PercentProcessorPerformance / 100), $cpu.MaxClockSpeed)
S 'Firmware bop xung CPU (Kernel-Processor-Power 37)'
$thrRun = @($thr | Where-Object { $t = $_.TimeCreated; -not @($boots | Where-Object { $t -ge $_.TimeCreated.AddMinutes(-1) -and $t -le $_.TimeCreated.AddMinutes(5) }).Count })
if ($thr.Count -eq 0) { W '  (khong co)' }
else {
  W ('  {0} lan, gan nhat {1:yyyy-MM-dd HH:mm}: {2}' -f $thr.Count, $thr[0].TimeCreated, (Cut $thr[0].Message 120))
  W ('  Trong do {0} lan xay ra LUC DANG CHAY (luc khoi dong ghi su kien 37 la binh thuong).' -f $thrRun.Count)
}
S 'Canh bao nhiet trong nhat ky'
if ($kpBad.Count -eq 0) { W '  (khong co)' }
foreach ($e in ($kpBad | Select-Object -First 10)) { W ('  {0:yyyy-MM-dd HH:mm} ID {1}: {2}' -f $e.TimeCreated, $e.Id, (Cut $e.Message 100)) }
S 'Card man hinh NVIDIA (nvidia-smi)'
$nv = $null
foreach ($p in @("$env:SystemRoot\System32\nvidia-smi.exe", "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe")) { if (Test-Path $p) { $nv = $p; break } }
$gpuW = $null; $gpuLim = $null
if ($nv) {
  $q = & $nv --query-gpu=name,temperature.gpu,power.draw,power.limit,utilization.gpu,clocks_throttle_reasons.active --format=csv,noheader 2>$null
  foreach ($l in @($q)) { if ("$l".Trim()) { W ('  ' + $l) } }
  $qq = @(& $nv --query-gpu=power.draw,power.limit --format=csv,noheader,nounits 2>$null)
  if ($qq.Count) { $a = "$($qq[0])".Split(','); try { $gpuW = [double]$a[0].Trim(); $gpuLim = [double]$a[1].Trim() } catch {} }
} else { W '  (khong co NVIDIA / khong co nvidia-smi)' }

# =========================== 7. NGUON / PIN / UPS ============================
Step 'Nguon, pin, UPS'
HDR '7. NGUON DIEN, PIN, UPS'
$wear = $null
if ($bat.Count -eq 0) { W '  Khong co pin / UPS ket noi USB.' }
foreach ($b in $bat) {
  KV 'Thiet bi'        ("{0}  ({1})" -f $b.Name, $(if ($isLaptop) { 'pin laptop' } else { 'co the la UPS cam USB' }))
  KV '% con lai'       $b.EstimatedChargeRemaining
  KV 'Trang thai'      $(switch ($b.BatteryStatus) { 1 { 'dang xa (chay pin)' } 2 { 'cam dien AC' } 3 { 'day' } 4 { 'yeu' } 5 { 'rat yeu' } 6 { 'dang sac' } default { $b.BatteryStatus } })
}
$bs = @(Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData)
$bf = @(Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity)
if ($bs.Count -and $bf.Count -and $bs[0].DesignedCapacity -gt 0) {
  $wear = [Math]::Round(100 - 100 * $bf[0].FullChargedCapacity / $bs[0].DesignedCapacity, 1)
  KV 'Dung luong thiet ke' ('{0} mWh' -f $bs[0].DesignedCapacity)
  KV 'Dung luong day hien tai' ('{0} mWh' -f $bf[0].FullChargedCapacity)
  KV 'Do chai pin'     ('{0} %' -f $wear)
}
$bst = @(Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus)
foreach ($b in $bst) { KV 'Dien ap pin' ('{0} mV  | cam sac: {1}' -f $b.Voltage, $b.PowerOnline) }
if ($isLaptop -and $bat.Count) {
  $br = Join-Path $OutDir ("PinReport_{0}_{1}.html" -f $env:COMPUTERNAME, $stamp)
  powercfg /batteryreport /output "$br" 2>&1 | Out-Null
  if (Test-Path $br) { KV 'Bao cao pin chi tiet' $br }
}
S 'Lan doi nguon AC <-> pin gan nhat (Kernel-Power 105)'
if ($e105.Count -eq 0) { W '  (khong co)' }
foreach ($e in ($e105 | Select-Object -Last 10)) { $d = EvData $e; W ('  {0:yyyy-MM-dd HH:mm:ss} | cam dien: {1,-5} | pin {2}/{3}' -f $e.TimeCreated, $d['AcOnline'], $d['RemainingCapacity'], $d['FullChargeCapacity']) }

# =========================== 8. CAI DAT NGUON ================================
Step 'Cai dat nguon (powercfg)'
HDR '8. CAI DAT NGUON CUA WINDOWS'
KV 'Power plan' ((powercfg /getactivescheme) -join ' ')
$hb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power').HiberbootEnabled
KV 'Fast Startup' $(if ($hb -eq 1) { 'BAT' } else { 'tat' })
S 'Cac che do ngu ho tro (powercfg /a)'
foreach ($l in (powercfg /a)) { if ("$l".Trim()) { W ('  ' + $l) } }
S 'Nut nguon / nap may lam gi'
foreach ($l in (powercfg /q SCHEME_CURRENT SUB_BUTTONS)) { if ("$l".Trim()) { W ('  ' + $l) } }
S 'Thoi gian ngu'
foreach ($l in (powercfg /q SCHEME_CURRENT SUB_SLEEP)) { if ("$l".Trim()) { W ('  ' + $l) } }
S 'Lan danh thuc gan nhat / hen gio danh thuc'
foreach ($l in (powercfg /lastwake)) { if ("$l".Trim()) { W ('  ' + $l) } }
foreach ($l in (powercfg /waketimers)) { if ("$l".Trim()) { W ('  ' + $l) } }

# =========================== 9. VGA / THIET BI / O DIA =======================
Step 'Card man hinh, thiet bi loi, o dia'
HDR '9. CARD MAN HINH, THIET BI LOI, O DIA'
S 'Card man hinh'
foreach ($v in (Get-CimInstance Win32_VideoController)) { W ('  {0} | driver {1} ngay {2:yyyy-MM-dd}' -f $v.Name, $v.DriverVersion, $v.DriverDate) }
S 'Loi card man hinh trong nhat ky'
if ($gpuE.Count -eq 0) { W '  (khong co)' }
foreach ($g in ($gpuE | Group-Object { "$($_.ProviderName)|$($_.Id)" } | Sort-Object Count -Descending)) { W ('  {0,5} lan | {1} | gan nhat {2:yyyy-MM-dd HH:mm}' -f $g.Count, $g.Name, $g.Group[0].TimeCreated) }
S 'Thiet bi dang loi trong Device Manager'
$bad = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
if ($bad.Count -eq 0) { W '  (khong co)' }
foreach ($b in $bad) { W ('  Ma {0,-3} | {1}' -f $b.ConfigManagerErrorCode, $b.Name) }
S 'O dia'
foreach ($p in (Get-PhysicalDisk)) {
  $r = $p | Get-StorageReliabilityCounter
  W ('  {0} | {1} | {2} | nhiet {3} C | loi doc khong sua duoc {4} | hao mon {5}%' -f $p.FriendlyName, $p.MediaType, $p.HealthStatus, $r.Temperature, $r.ReadErrorsUncorrected, $r.Wear)
}
if ($dskE.Count) {
  S 'Loi o dia trong nhat ky'
  foreach ($g in ($dskE | Group-Object { "$($_.ProviderName)|$($_.Id)" } | Sort-Object Count -Descending)) { W ('  {0,5} lan | {1} | gan nhat {2:yyyy-MM-dd HH:mm}' -f $g.Count, $g.Name, $g.Group[0].TimeCreated) }
}

# =========================== 10. THAY DOI GAN DAY ============================
Step 'Dong thoi gian thay doi (update, phan mem, driver)'
HDR '10. DONG THOI GIAN: THAY DOI TRUOC LAN SAP DAU TIEN'
$first = if ($k41.Count) { $k41[-1].TimeCreated } else { $null }
KV 'Lan sap dau tien trong nhat ky' $(if ($first) { '{0:yyyy-MM-dd HH:mm}' -f $first } else { '(khong co)' })
$tl = New-Object System.Collections.ArrayList
foreach ($e in (GetEv @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; Id = 19; StartTime = $since } 300)) {
  [void]$tl.Add([pscustomobject]@{ T = $e.TimeCreated; K = 'UPDATE'; N = (Cut $e.Properties[0].Value 90) }) }
foreach ($e in (GetEv @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-UserPnp'; Id = 20001, 20003; StartTime = $since } 300)) {
  [void]$tl.Add([pscustomobject]@{ T = $e.TimeCreated; K = 'DRIVER'; N = (Cut $e.Message 90) }) }
foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
  foreach ($a in (Get-ItemProperty $k -ErrorAction SilentlyContinue)) {
    if ($a.DisplayName -and $a.InstallDate -match '^\d{8}$') {
      try { $dt = [datetime]::ParseExact($a.InstallDate, 'yyyyMMdd', $null); if ($dt -ge $since.Date) { [void]$tl.Add([pscustomobject]@{ T = $dt; K = 'PHAN MEM'; N = (Cut ("{0} {1}" -f $a.DisplayName, $a.DisplayVersion) 90) }) } } catch {}
    } } }
if ($first) { [void]$tl.Add([pscustomobject]@{ T = $first; K = '>>>>>>>>'; N = '<<< LAN SAP NGUON DAU TIEN TRONG NHAT KY >>>' }) }
if ($tl.Count -le 1) { W '  (khong co thay doi nao duoc ghi nhan)' }
foreach ($x in ($tl | Sort-Object T)) { W ('  {0:yyyy-MM-dd HH:mm} | {1,-8} | {2}' -f $x.T, $x.K, $x.N) }

# =========================== 11. THEO DOI LAN TRUOC ==========================
HDR '11. KET QUA CHE DO THEO DOI LAN TRUOC (neu co)'
$mon = @(Get-ChildItem -LiteralPath $OutDir -Filter 'SupNguon_TheoDoi_*.csv' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
if ($mon.Count -eq 0) { W '  (chua bat che do theo doi lan nao)' }
else {
  $lines = @(Get-Content -LiteralPath $mon[0].FullName)
  KV 'File' $mon[0].Name
  KV 'Dong cuoi ghi luc' ('{0:yyyy-MM-dd HH:mm:ss}' -f $mon[0].LastWriteTime)
  $near = @($crash | Where-Object { $_.CrashAt -and [Math]::Abs(($_.CrashAt - $mon[0].LastWriteTime).TotalMinutes) -lt 10 })
  if ($near.Count) { W ('  -> Dong cuoi KHOP voi lan sap luc {0:dd/MM HH:mm} ({1}). Day la trang thai may ngay truoc khi tat:' -f $near[0].CrashAt, $near[0].Type) }
  else { W '  -> Dong cuoi khong trung voi lan sap nao (co the do ban tu dong cua so).' }
  W ''
  W ('  ' + $lines[0])
  foreach ($l in ($lines | Select-Object -Skip 1 | Select-Object -Last 25)) { W ('  ' + $l) }
}

# =========================== KET LUAN TU DONG ================================
Step 'Cham diem, dua ra ket luan'
$cnt = @{}; foreach ($c in $crash) { $cnt[$c.Type] = 1 + [int]$cnt[$c.Type] }
$nMat = [int]$cnt['MAT NGUON']; $nBs = [int]$cnt['MAN HINH XANH']; $nBtn = [int]$cnt['GIU NUT NGUON']; $nSlp = [int]$cnt['KHI NGU/THUC']
$ups = @($crash | Where-Object { $_.Up } | ForEach-Object { $_.Up.TotalMinutes } | Sort-Object)
$med = if ($ups.Count) { $ups[[int][Math]::Floor($ups.Count / 2)] } else { $null }

if ($k41.Count -eq 0 -and $e6008.Count -eq 0) {
  Warn 2 -Ma 'KHONG_THAY_TAT_DOT_NGOT' 'KHONG THAY lan tat dot ngot nao trong nhat ky. Neu may van "sap": (a) co the chi MAN HINH tat (kiem tra cap man hinh / nguon man hinh), (b) may duoc tat co chu dich - xem muc 3 "User32 1074", (c) nhat ky bi xoa.'
}
if ($nMat -gt 0) {
  $m = "$nMat lan MAT NGUON DOT NGOT: dien bi cat ngang, khong man hinh xanh, khong ai giu nut nguon. Day la loi PHAN CUNG / DIEN, KHONG PHAI loi Windows."
  if ($isLaptop) { $m += ' Laptop: nghi PIN chai/hong, cuc sac, chan sac, hoac qua nhiet.' }
  else { $m += ' May ban: nghi NGUON (PSU) yeu/phong tu, O CAM / O CHIA / UPS, DAY NGUON, QUA NHIET (CPU/VGA ngat bao ve), hoac MAINBOARD.' }
  Warn 3 -Ma 'MAT_NGUON_DOT_NGOT' $m
}
if ($nBs -gt 0) {
  $top = @($crash | Where-Object { $_.Bc -ne 0 } | Group-Object { BcText $_.Bc } | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Count)x $($_.Name)" }) -join ' ; '
  Warn 3 -Ma 'MAN_HINH_XANH' -Tiep 'checkwinfix/phan-cung' ("$nBs lan MAN HINH XANH roi tu khoi dong lai (nguoi dung tuong la sup nguon). Ma loi: $top")
}
if ($mdCodes.Count -gt 0 -and $nBs -eq 0) { Warn 2 -Ma 'CO_FILE_MINIDUMP' -Tiep 'checkwinfix/phan-cung' ("Co {0} file minidump -> may tung bi man hinh xanh. Ma gan nhat: {1}" -f $md.Count, (BcText $mdCodes[0])) }
if ($nBtn -gt 0) { Warn 2 -Ma 'GIU_NUT_NGUON' "$nBtn lan bi GIU NUT NGUON de tat -> may bi TREO truoc do (khong phai sup nguon). Can hoi nguoi dung may treo luc lam gi." }
if ($nSlp -gt 0) { Warn 2 -Ma 'SAP_KHI_NGU' "$nSlp lan sap KHI NGU / DANH THUC -> thuong do driver (VGA, mang, USB) hoac Fast Startup. Thu tat Fast Startup va che do ngu de kiem chung." }
if ($whea.Count -gt 0) { Warn 3 -Ma 'LOI_WHEA' -Tiep 'checkwinfix/giai-ma-whea' ("{0} loi phan cung WHEA -> CPU / RAM / khe PCIe / nguon cap dien ap khong on dinh. Chay 3-GIAI-MA-WHEA.bat de chi dich danh." -f $whea.Count) }
if ($kpBad.Count -gt 0) { Warn 3 -Ma 'CANH_BAO_NHIET_DO' ("{0} canh bao NHIET DO trong nhat ky -> ve sinh, thay keo tan nhiet, kiem tra quat." -f $kpBad.Count) }
if ($null -ne $tzMax -and $tzCrit -gt 0 -and $tzMax -ge ($tzCrit - 10)) { Warn 3 -Ma 'QUA_NHIET' ("Nhiet do ACPI hien tai {0} C, chi cach nguong ngat {1} C chua toi 10 do -> QUA NHIET." -f $tzMax, $tzCrit) }
elseif ($null -ne $tzMax -and $tzMax -ge 85) { Warn 3 -Ma 'NHIET_DO_CAO' ("Nhiet do ACPI hien tai {0} C - qua cao." -f $tzMax) }
if ($thrRun.Count -gt 0) { Warn 2 -Ma 'CPU_BI_BOP_XUNG' ("CPU bi firmware bop xung {0} lan trong luc dang chay (nhiet hoac nguon khong du) -> dau hieu tan nhiet kem / nguon yeu." -f $thrRun.Count) }
if ($gpuE.Count -gt 0) { Warn 2 -Ma 'LOI_CARD_MAN_HINH' ("{0} loi card man hinh (driver/TDR). VGA roi ra/ngat khi tai nang cung gay tat may - nghi nguon VGA hoac PSU khong du cong suat." -f $gpuE.Count) }
if ($null -ne $gpuW -and $gpuLim -gt 150 -and -not $isLaptop) { Warn 1 -Ma 'VGA_CONG_SUAT_LON' ("VGA roi co gioi han cong suat {0} W -> PSU can du cong suat that (khong phai nguon 'no name')." -f $gpuLim) }
if ($dskE.Count -gt 0) { Warn 2 -Ma 'LOI_O_DIA' -Tiep 'checkwinfix/phan-cung' ("{0} loi o dia trong nhat ky - o dia loi co the gay treo/man hinh xanh. Chay 2-CHAN-DOAN-PHAN-CUNG.bat." -f $dskE.Count) }
if ($null -ne $wear -and $wear -ge 40) { Warn 2 -Ma 'PIN_CHAI' ("Pin chai {0}% - pin yeu co the sut ap lam may tat dot ngot khi rut sac hoac khi tai nang." -f $wear) }
$nb = @($crash | Where-Object { $_.OnBat }).Count
if ($nb -gt 0) { Warn 3 -Ma 'SAP_KHI_CHAY_PIN' "$nb lan sap xay ra khi DANG CHAY PIN -> pin hong / pin bao sai dung luong." }
if ($null -ne $med -and $ups.Count -ge 3 -and $med -le 30) { Warn 2 -Ma 'SAP_SOM_SAU_KHI_BAT' ("Trung vi may chi chay duoc {0} phut sau khi bat thi sap -> nghieng ve NHIET hoac NGUON khi len tai (khong phai loi ngau nhien)." -f [int]$med) }
if ($k41.Count -ge 10) { Warn 2 -Ma 'TAT_DOT_NGOT_NHIEU' ("Tan suat cao: {0} lan tat dot ngot / {1} ngay." -f $k41.Count, $DAYS) }
if ($cc.CrashDumpEnabled -eq 0 -or $pf.Count -eq 0) { Warn 1 -Ma 'KHONG_GHI_DUMP' 'Windows KHONG ghi dump (tat dump hoac khong co pagefile) -> man hinh xanh co the bi ghi nhan nham thanh "mat nguon". Nen bat lai minidump.' }
if ($cc.AutoReboot -eq 1 -and $crash.Count -gt 0) { Warn 1 -Ma 'AUTO_REBOOT_BAT' 'AutoReboot dang bat -> co man hinh xanh cung tu khoi dong ngay, nguoi dung khong kip thay ma loi.' }
if ($bios.ReleaseDate -and $bios.ReleaseDate -lt (Get-Date).AddYears(-5)) { Warn 1 -Ma 'BIOS_CU' ("BIOS tu {0:yyyy} - cu, co the can cap nhat neu loi WHEA / man hinh xanh." -f $bios.ReleaseDate) }
if ($isAdmin -and -not @($script:FLAGS | Where-Object { $_.mucDo -in 'loi', 'canh-bao' }).Count) { FLAG 'KHONG_THAY_BAT_THUONG' 'Khong phat hien dau hieu bat thuong.' -Muc 'ok' }

$H = New-Object System.Text.StringBuilder
function HH { param([string]$t = '') [void]$H.AppendLine($t) }
HH ('#' * 88)
HH '#  CHAN DOAN MAY SUP NGUON / TU TAT / TU KHOI DONG LAI'
HH ("#  May: {0}   Thoi diem: {1}   Thoi gian chay: {2:N0} giay" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), ((Get-Date) - $t0).TotalSeconds)
HH ('#' * 88)
HH ''
HH ('=' * 88)
HH '  KET LUAN TU DONG  ([!!!] nghiem trong  [!!] dang ngo  [!] luu y)'
HH ('=' * 88)
$okF = @($script:FLAGS | Where-Object { $_.mucDo -eq 'ok' })
if ($WARN.Count -eq 0 -and -not $okF.Count) { HH '  Khong phat hien dau hieu bat thuong.' }
foreach ($w in ($WARN | Sort-Object L -Descending)) { HH ('  {0,-6}{1} ({2})' -f ('[' + ('!' * $w.L) + ']'), $w.T, $w.M) }
foreach ($f in $okF) { HH ('  {0,-6}{1} ({2})' -f '[ok]', $f.tieuDe, $f.ma) }
HH ''
HH '  KIEM TRA TAY NEN LAM (script khong do duoc):'
if ($isLaptop) {
  HH '   1. Rut sac, chay pin: tat ngay -> pin hong. Thao pin (neu duoc) chay bang sac: van tat -> sac/main.'
  HH '   2. Thu cuc sac khac dung cong suat; lac nhe chan cam sac xem may co tat khong.'
  HH '   3. So day may / nghe quat khi tai nang; ve sinh khe tan nhiet, thay keo tan nhiet.'
} else {
  HH '   1. Cam THANG vao o tuong (bo o chia / UPS / on ap), doi day nguon khac.'
  HH '   2. Mo thung: quat CPU co quay, tan nhiet co bam bui; tu tren main / trong nguon co phong khong.'
  HH '   3. Muon nguon (PSU) khac du cong suat thay thu - cach chac chan nhat de loai tru nguon.'
  HH '   4. Rut bot RAM / cam lai RAM, VGA; kiem tra day 24 pin va 8 pin CPU cam chat.'
}
HH '   *  Neu may sap co quy luat (khi choi game, luc tai nang...) -> bat che do THEO DOI (hoi o cuoi script).'
HH ''

$final = $H.ToString() + $SB.ToString()
try { [IO.File]::WriteAllText($out, $final, (New-Object Text.UTF8Encoding $true)) } catch { Write-Host ('  [X] Khong ghi duoc bao cao ' + $out + ': ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
# Ket qua cho Tram Tool ghi truoc cac cau hoi thay doi may ben duoi.
[void](Save-KetQua -CheDo 'sup-nguon' -Ten 'SupNguon' -Tep @([ordered]@{ nhan = 'Báo cáo'; duongDan = $out }))

Write-Host ''
Write-Host '  ==========================================================================' -ForegroundColor Green
Write-Host ("   XONG. Bao cao: {0}" -f $out) -ForegroundColor Green
Write-Host '  ==========================================================================' -ForegroundColor Green
Write-Host ''
foreach ($w in ($WARN | Sort-Object L -Descending)) {
  $col = @{ 3 = 'Red'; 2 = 'Yellow'; 1 = 'Gray' }[$w.L]
  Write-Host ('  ' + ('!' * $w.L).PadRight(4) + $w.T) -ForegroundColor $col
}
if (-not $KhongHoi -and -not $env:CWF_KHONG_MO) { Start-Process notepad.exe -ArgumentList "`"$out`"" }
if ($KhongHoi) { exit 0 }

# =========================== TUY CHON (co hoi) ===============================
if ($cc.CrashDumpEnabled -eq 0 -or $cc.AutoReboot -eq 1) {
  Write-Host ''
  Write-Host '  [HOI] Bat ghi minidump + dung lai o man hinh xanh (AutoReboot=0)' -ForegroundColor Cyan
  Write-Host '        de lan sap sau thay duoc MA LOI? Hoan tac: dat lai AutoReboot=1.' -ForegroundColor Cyan
  $a = Read-Host '        Dong y? (C/K)'
  if ($a -match '^[cCyY]') {
    $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
    if ($cc.CrashDumpEnabled -eq 0) { Set-ItemProperty $k CrashDumpEnabled 3 -Type DWord }
    Set-ItemProperty $k AutoReboot 0 -Type DWord
    Write-Host ('        Da doi. Truoc: CrashDumpEnabled={0}, AutoReboot={1}' -f $cc.CrashDumpEnabled, $cc.AutoReboot) -ForegroundColor Green
  }
}

Write-Host ''
Write-Host '  [HOI] Bat che do THEO DOI: cu 5 giay ghi tai CPU, xung, RAM, o dia, nhiet do,' -ForegroundColor Cyan
Write-Host '        nguon AC/pin, VGA vao file CSV. De cua so chay, dung may binh thuong.' -ForegroundColor Cyan
Write-Host '        Khi may sap -> bat lai -> chay lai script nay: muc 11 se cho biet' -ForegroundColor Cyan
Write-Host '        may dang lam gi, nong bao nhieu NGAY TRUOC khi tat.' -ForegroundColor Cyan
$a = Read-Host '        Bat theo doi? (C/K)'
if ($a -notmatch '^[cCyY]') { exit 0 }

$csv = Join-Path $OutDir ("SupNguon_TheoDoi_{0}_{1}.csv" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
[IO.File]::AppendAllText($csv, "ThoiGian,CPU_%,HieuNang_%,XungMHz,RAM_%,Disk_%,NhietACPI_C,CamSac,Pin_%,GPU_C,GPU_W,GPU_%`r`n")
Write-Host ("  Dang ghi vao {0}" -f $csv) -ForegroundColor Green
Write-Host '  Dong cua so hoac Ctrl+C de dung.' -ForegroundColor Green
while ($true) {
  $p = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'"
  $o = Get-CimInstance Win32_OperatingSystem
  $ram = [int](100 - 100 * $o.FreePhysicalMemory / $o.TotalVisibleMemorySize)
  $dk = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'"
  $disk = if ($dk) { 100 - [int]$dk.PercentIdleTime } else { '' }
  $t = ''; $zz = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature)
  if ($zz.Count) { $t = [Math]::Round(($zz | Measure-Object CurrentTemperature -Maximum).Maximum / 10 - 273.15, 1) }
  $ac = ''; $pct = ''
  $b2 = @(Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus)
  if ($b2.Count) { $ac = $b2[0].PowerOnline }
  $b1 = @(Get-CimInstance Win32_Battery); if ($b1.Count) { $pct = $b1[0].EstimatedChargeRemaining }
  $g = ',,'
  if ($nv) { $r = @(& $nv --query-gpu=temperature.gpu,power.draw,utilization.gpu --format=csv,noheader,nounits 2>$null); if ($r.Count -and "$($r[0])" -match '^\s*\d') { $g = ("$($r[0])" -replace '\s', '') } }
  $line = '{0:yyyy-MM-dd HH:mm:ss},{1},{2},{3},{4},{5},{6},{7},{8},{9}' -f (Get-Date), $p.PercentProcessorTime, $p.PercentProcessorPerformance,
          [int]($p.ProcessorFrequency * $p.PercentProcessorPerformance / 100), $ram, $disk, $t, $ac, $pct, $g
  try { [IO.File]::AppendAllText($csv, $line + "`r`n") } catch {}
  Write-Host ('  ' + $line)
  Start-Sleep -Seconds 5
}
