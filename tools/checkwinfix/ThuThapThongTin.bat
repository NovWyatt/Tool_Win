@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title CheckWinFix - Thu thap thong tin may Windows bi cham (v2026.10.4)

set "SELF=%~f0"
set "OUTDIR=%~dp0"
if "%OUTDIR:~-1%"=="\" set "OUTDIR=%OUTDIR:~0,-1%"

echo.
echo  ==========================================================================
echo    CheckWinFix  ^|  THU THAP THONG TIN MAY WINDOWS BI CHAM  ^|  v2026.10.4
echo  --------------------------------------------------------------------------
echo    Script nay CHI DOC thong tin de chan doan.
echo    KHONG xoa, KHONG sua, KHONG cai dat gi tren may.
echo    Ket qua luu thanh 1 file .txt ngay canh file bat nay.
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
set "PS1=%TEMP%\CheckWinFix_Collect_%RANDOM%.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$r=Get-Content -LiteralPath $env:SELF -Raw -Encoding UTF8; $m='#====='+'PS_START'+'====='; $i=$r.IndexOf($m); if($i -lt 0){exit 1}; [IO.File]::WriteAllText($env:PS1, $r.Substring($i+$m.Length), (New-Object Text.UTF8Encoding $true)); exit 0"
if errorlevel 1 goto :ERR_SPLIT

rem Tham so (vd tu Tram Tool: -KhongHoi -BatDau "..." -TrieuChung "..." -KiemTraSau) chuyen nguyen cho PowerShell.
rem Khi script tu mo lai bang quyen Admin thi tham so khong theo sang (Tram Tool luon mo bang quyen Admin).
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -OutDir "%OUTDIR%" %*
set "RC=%ERRORLEVEL%"
del /f /q "%PS1%" >nul 2>&1
echo.
echo  ==========================================================================
echo    XONG. Hay gui file LagReport_*.txt vua tao cho nguoi ho tro.
echo  ==========================================================================
echo.
pause
exit /b %RC%

:ERR_NOPS
echo  [X] Khong tim thay PowerShell tren may nay. Script khong chay duoc.
pause
exit /b 1

:ERR_SPLIT
echo  [X] Khong tach duoc phan PowerShell tu file bat.
echo      Nguyen nhan thuong gap: file bi luu lai sai bang ma (encoding).
echo      Hay lay lai ban goc va KHONG mo roi luu lai bang Notepad.
pause
exit /b 1

#=====PS_START=====
<#
  CheckWinFix - Bo thu thap thong tin chan doan may Windows bi cham dot ngot
  Phien ban : 2026.10.4
  Tinh chat : CHI DOC (read-only). Khong thay doi bat ky thiet lap nao.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$OutDir = "",
  [string]$BatDau = "",        # cau 1: may bat dau cham tu khi nao (form cua Tram Tool)
  [string]$TrieuChung = "",    # cau 2: cham the nao
  [switch]$KhongHoi,           # khong hoi trong cua so (Tram Tool da hoi bang form)
  [switch]$KiemTraSau,         # them anh Windows (DISM /ScanHealth) va loi he thong file (chkdsk /scan), 5-20 phut
  [Parameter(ValueFromRemainingArguments = $true)] $ConLai   # /danangquyen cua phan .bat
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
$SCRIPT_VER = '2026.10.4'
$TOTAL      = 26
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $Host.UI.RawUI.WindowTitle = 'CheckWinFix - dang thu thap thong tin...' } catch {}

$script:N     = 0
$script:SB    = New-Object System.Text.StringBuilder
$T0           = Get-Date

# ----------------------------- HAM TIEN ICH -----------------------------------
function W  { param([string]$t = '') [void]$script:SB.AppendLine($t) }
function KV { param($k, $v) W ("  {0,-30}: {1}" -f $k, $v) }
function HDR { param([string]$t) W ''; W ('=' * 90); W ("  $t"); W ('=' * 90) }
function SH { param([string]$t) W ''; W ("  --- $t " + ('-' * [Math]::Max(1, 78 - $t.Length))) }
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

function WL {
  param($o, [int]$Width = 200)
  if ($null -eq $o) { W '  (khong co du lieu)'; return }
  $s = ($o | Out-String -Width $Width).TrimEnd()
  if ([string]::IsNullOrWhiteSpace($s)) { W '  (khong co du lieu)' } else { W $s }
}

function FmtGB { param($b) if ($null -eq $b -or $b -eq '') { return 'n/a' } '{0:N2} GB' -f ([double]$b / 1GB) }
function FmtMB { param($b) if ($null -eq $b -or $b -eq '') { return 'n/a' } '{0:N0} MB' -f ([double]$b / 1MB) }

function Trunc {
  param([string]$s, [int]$len = 200)
  if ([string]::IsNullOrEmpty($s)) { return '' }
  $s = ($s -replace '[\r\n\t]+', ' ') -replace '\s{2,}', ' '
  if ($s.Length -gt $len) { return $s.Substring(0, $len) + '...' }
  return $s
}

function AsDate {
  param($v)
  if ($null -eq $v) { return $null }
  if ($v -is [datetime]) { return $v }
  try { return [System.Management.ManagementDateTimeConverter]::ToDateTime([string]$v) } catch { return $null }
}

function Cim {
  param([string]$Class, [string]$Namespace = 'root\cimv2', [string]$Filter)
  try {
    if ($Filter) { Get-CimInstance -ClassName $Class -Namespace $Namespace -Filter $Filter -ErrorAction Stop }
    else { Get-CimInstance -ClassName $Class -Namespace $Namespace -ErrorAction Stop }
  } catch {
    try {
      if ($Filter) { Get-WmiObject -Class $Class -Namespace $Namespace -Filter $Filter -ErrorAction Stop }
      else { Get-WmiObject -Class $Class -Namespace $Namespace -ErrorAction Stop }
    } catch { $null }
  }
}

function Reg {
  param([string]$Path, [string]$Name)
  try { (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name } catch { $null }
}

function FolderSize {
  param([string]$Path, [int]$TimeoutSec = 15)
  if (-not (Test-Path -LiteralPath $Path)) { return 'khong ton tai' }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $sum = 0; $cnt = 0; $timeout = $false
  try {
    foreach ($f in [System.IO.Directory]::EnumerateFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)) {
      try { $sum += (New-Object System.IO.FileInfo $f).Length; $cnt++ } catch {}
      if (($cnt % 400) -eq 0 -and $sw.Elapsed.TotalSeconds -gt $TimeoutSec) { $timeout = $true; break }
    }
  } catch {}
  $r = "{0} ({1} file)" -f (FmtMB $sum), $cnt
  if ($timeout) { $r += ' [dem do dang - con nhieu hon]' }
  return $r
}

function Sec {
  param([string]$Title, [scriptblock]$Body)
  $script:N++
  Write-Host ("  [{0,2}/{1}] {2}" -f $script:N, $TOTAL, $Title) -ForegroundColor Cyan
  HDR ("{0}. {1}" -f $script:N, $Title.ToUpper())
  try { & $Body } catch { W ("  [LOI KHI DOC MUC NAY] " + $_.Exception.Message) }
}


# ----------------------------- CHUAN BI ---------------------------------------
if ([string]::IsNullOrWhiteSpace($OutDir) -or -not (Test-Path -LiteralPath $OutDir)) {
  $OutDir = Join-Path $env:USERPROFILE 'Desktop'
}
try {
  $probe = Join-Path $OutDir ('.cwf_' + [Guid]::NewGuid().ToString('N') + '.tmp')
  Set-Content -LiteralPath $probe -Value 'x' -ErrorAction Stop
  Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
} catch {
  $OutDir = Join-Path $env:USERPROFILE 'Desktop'
  if (-not (Test-Path -LiteralPath $OutDir)) { $OutDir = $env:TEMP }
}
$stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
$reportPath = Join-Path $OutDir ("LagReport_{0}_{1}.txt" -f $env:COMPUTERNAME, $stamp)

$ansWhen = $BatDau
$ansWhat = $TrieuChung
if (-not $KhongHoi) {
  Write-Host ''
  Write-Host '  Tra loi nhanh 3 cau hoi (bam Enter de bo qua):' -ForegroundColor Yellow
  Write-Host ''
  if (-not $ansWhen) { $ansWhen = Read-Host '  1) May bat dau cham tu khi nao? (vd: 10/09/2026 hoac "khoang 2 tuan truoc")' }
  if (-not $ansWhat) { $ansWhat = Read-Host '  2) Cham the nao? (vd: mo may lau, Chrome giat, chuot lag, keu quat to...)' }
  if (-not $KiemTraSau) {
    $ansDeep = Read-Host '  3) Kiem tra them anh Windows (DISM) va loi he thong file (chkdsk /scan)? Mat them 5-20 phut. (C/K, Enter = khong)'
    if ($ansDeep -match '^\s*(c|co|y|yes)\s*$') { $KiemTraSau = [switch]$true }
  }
}
if ($KiemTraSau) { $TOTAL = 27 }
Write-Host ''
Write-Host '  Dang thu thap. Vui long cho 1-3 phut, KHONG tat cua so nay.' -ForegroundColor Yellow
Write-Host ''

$isAdmin = Test-QuyenAdmin
$since14 = (Get-Date).AddDays(-14)
$since30 = (Get-Date).AddDays(-30)
$since90 = (Get-Date).AddDays(-90)

$os   = Cim Win32_OperatingSystem
$cs   = Cim Win32_ComputerSystem
$bios = Cim Win32_BIOS
$cpus = @(Cim Win32_Processor)
$nlp  = 0
try { $nlp = [int](($cpus | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum) } catch {}
if ($nlp -lt 1) { $nlp = [int]$env:NUMBER_OF_PROCESSORS }
if ($nlp -lt 1) { $nlp = 1 }

# =============================== 1. THONG TIN MAY =============================
Sec 'Thong tin may va he dieu hanh' {
  $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
  KV 'Thoi diem thu thap'  (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  KV 'Ten may'             $env:COMPUTERNAME
  KV 'Nguoi dung dang chay' ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
  KV 'Chay voi quyen Admin' $isAdmin
  if (-not $isAdmin) { FLAG 'THIEU_QUYEN_ADMIN' 'BAO CAO NAY THIEU DU LIEU: script khong chay bang quyen Administrator nen khong doc duoc SMART o dia, nhat ky hieu nang va nhieu muc quan trong. Hay chuot phai file .bat > Run as administrator va chay lai.' }
  KV 'Hang / Model'        ("{0} / {1}" -f $cs.Manufacturer, $cs.Model)
  $ptype = switch ([int]$cs.PCSystemType) { 1 {'Desktop'} 2 {'Laptop / May di dong'} 3 {'Workstation'} 4 {'Enterprise Server'} default {"Khac ($($cs.PCSystemType))"} }
  KV 'Loai may'            $ptype
  KV 'He dieu hanh'        $os.Caption
  KV 'Phien ban / Build'   ("{0}  (Build {1}.{2})" -f $os.Version, $os.BuildNumber, (Reg $cv 'UBR'))
  KV 'DisplayVersion'      (Reg $cv 'DisplayVersion')
  KV 'Kien truc'           $os.OSArchitecture
  KV 'Ngon ngu / Locale'   ("{0} / {1}" -f (@($os.MUILanguages) -join ','), (Get-Culture).Name)
  $instDate = AsDate $os.InstallDate
  KV 'Ngay cai Windows'    ("{0:yyyy-MM-dd HH:mm}" -f $instDate)
  $boot = AsDate $os.LastBootUpTime
  KV 'Khoi dong lan cuoi'  ("{0:yyyy-MM-dd HH:mm}" -f $boot)
  if ($boot) {
    $up = (Get-Date) - $boot
    KV 'Da bat lien tuc'   ("{0} ngay {1} gio {2} phut" -f $up.Days, $up.Hours, $up.Minutes)
    if ($up.TotalDays -ge 7) { FLAG 'CHUA_KHOI_DONG_LAI' ("May da bat lien tuc {0:N0} ngay chua khoi dong lai - bo nho bi phan manh, nen restart." -f $up.TotalDays) }
  }
  KV 'BIOS'                ("{0} | {1} | ngay {2:yyyy-MM-dd}" -f $bios.Manufacturer, $bios.SMBIOSBIOSVersion, (AsDate $bios.ReleaseDate))
  KV 'Serial may'          $bios.SerialNumber
  KV 'Che do firmware'     $env:firmware_type
  try { KV 'Secure Boot' (Confirm-SecureBootUEFI) } catch { KV 'Secure Boot' 'n/a' }
  $hiberboot = Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'
  KV 'Fast Startup'        $(if ($null -eq $hiberboot) { 'chua dat (mac dinh: bat)' } else { $hiberboot })
  if ("$hiberboot" -eq '1' -or $null -eq $hiberboot) { W '    (Fast Startup dang bat: may "tat" nhung thuc ra la ngu dong, loi tich luy khong duoc xoa => cham dan theo thoi gian)' }
  KV 'Domain / Workgroup'  ("{0} (PartOfDomain={1})" -f $cs.Domain, $cs.PartOfDomain)
  KV 'PowerShell'          $PSVersionTable.PSVersion
  KV '.NET CLR'            ([System.Environment]::Version)
  $vm = $false
  if ($cs.Model -match 'Virtual|VMware|VirtualBox|KVM|Xen|Hyper-V' -or $bios.Manufacturer -match 'VMware|innotek|Xen|QEMU') { $vm = $true }
  KV 'La may ao?'          $vm
}

# =============================== 2. CPU =======================================
Sec 'CPU - xung nhip va dau hieu bop xung (throttle)' {
  foreach ($c in $cpus) {
    KV 'CPU'               $c.Name
    KV '  Nhan / Luong'    ("{0} nhan / {1} luong" -f $c.NumberOfCores, $c.NumberOfLogicalProcessors)
    KV '  Xung toi da'     ("{0} MHz" -f $c.MaxClockSpeed)
    KV '  Xung hien tai'   ("{0} MHz" -f $c.CurrentClockSpeed)
    KV '  Tai hien tai'    ("{0} %" -f $c.LoadPercentage)
    KV '  Socket / Rev'    ("{0} / {1}" -f $c.SocketDesignation, $c.Revision)
    KV '  Virtualization'  ("Firmware={0}  SecondLevelAddrTrans={1}" -f $c.VirtualizationFirmwareEnabled, $c.SecondLevelAddressTranslationExtensions)
    if ($c.MaxClockSpeed -gt 0 -and $c.CurrentClockSpeed -gt 0) {
      $pct = [math]::Round(100.0 * $c.CurrentClockSpeed / $c.MaxClockSpeed, 0)
      KV '  Ty le xung/max' ("{0} %" -f $pct)
      if ($pct -lt 70) { FLAG 'CPU_BOP_XUNG' ("CPU dang chay o {0}% xung toi da ({1}/{2} MHz) - RAT CO THE bi bop xung (nong, pin/sac hong, hoac Power plan gioi han)." -f $pct, $c.CurrentClockSpeed, $c.MaxClockSpeed) }
    }
  }
  SH 'Tan so thuc te theo bo dem hieu nang (Processor Information)'
  $pi = Cim Win32_PerfFormattedData_Counters_ProcessorInformation
  if ($pi) {
    WL ($pi |
        Select-Object Name,
          @{n='%CPU';e={$_.PercentProcessorTime}},
          @{n='%Privileged';e={$_.PercentPrivilegedTime}},
          @{n='%Interrupt';e={$_.PercentInterruptTime}},
          @{n='%DPC';e={$_.PercentDPCTime}},
          @{n='%OfMaxFreq';e={$_.PercentofMaximumFrequency}},
          @{n='MHz';e={$_.ProcessorFrequency}} | Sort-Object Name | Format-Table -AutoSize)
    $tot = $pi | Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
    if ($tot -and $tot.PercentofMaximumFrequency -gt 0 -and $tot.PercentofMaximumFrequency -lt 60) {
      FLAG 'CPU_BOP_XUNG' ("CPU chi chay o {0}% tan so toi da (bo dem hieu nang) - dau hieu bi throttle vi nhiet do / nguon dien." -f $tot.PercentofMaximumFrequency)
    }
    if ($tot -and ($tot.PercentInterruptTime + $tot.PercentDPCTime) -gt 12) {
      FLAG 'DPC_CAO' ("Thoi gian Interrupt+DPC cao ({0}%) - thuong do DRIVER loi (mang/chipset/card man hinh) gay giat lag." -f ($tot.PercentInterruptTime + $tot.PercentDPCTime))
    }
  } else { W '  (khong doc duoc bo dem ProcessorInformation)' }
}

# =============================== 3. RAM =======================================
Sec 'Bo nho RAM va bo nho ao (pagefile)' {
  $totKB = [double]$os.TotalVisibleMemorySize
  $freeKB = [double]$os.FreePhysicalMemory
  $usedPct = 0
  if ($totKB -gt 0) { $usedPct = [math]::Round(100.0 * ($totKB - $freeKB) / $totKB, 1) }
  KV 'Tong RAM'          (FmtGB ($totKB * 1KB))
  KV 'RAM con trong'     (FmtGB ($freeKB * 1KB))
  KV 'RAM da dung'       ("{0} %" -f $usedPct)
  KV 'Commit da dung'    (FmtGB ([double]$os.TotalVirtualMemorySize * 1KB - [double]$os.FreeVirtualMemory * 1KB))
  KV 'Commit gioi han'   (FmtGB ([double]$os.TotalVirtualMemorySize * 1KB))
  if ($totKB -gt 0 -and ($totKB * 1KB) -lt 4.5GB) { FLAG 'RAM_IT' ("May chi co {0} RAM - qua it cho Windows 10/11, day la nguyen nhan cham co ban." -f (FmtGB ($totKB*1KB))) }
  if ($usedPct -ge 88) { FLAG 'RAM_DAY' ("RAM dang day {0}% - may se swap ra o dia va cham nghiem trong." -f $usedPct) }

  SH 'Thanh RAM dang gan'
  WL (Cim Win32_PhysicalMemory | Select-Object @{n='Khe';e={$_.DeviceLocator}}, @{n='Dung luong';e={FmtGB $_.Capacity}},
      @{n='Toc do(MHz)';e={$_.ConfiguredClockSpeed}}, @{n='Toc do dinh muc';e={$_.Speed}}, Manufacturer, PartNumber | Format-Table -AutoSize)

  SH 'Cau hinh pagefile'
  KV 'Tu dong quan ly'   $cs.AutomaticManagedPagefile
  WL (Cim Win32_PageFileUsage | Select-Object Name, @{n='Kich thuoc';e={FmtMB ($_.AllocatedBaseSize*1MB)}},
      @{n='Dang dung';e={FmtMB ($_.CurrentUsage*1MB)}}, @{n='Dinh diem';e={FmtMB ($_.PeakUsage*1MB)}} | Format-Table -AutoSize)
  $pfs = @(Cim Win32_PageFileSetting)
  if ($pfs) { WL ($pfs | Select-Object Name, InitialSize, MaximumSize | Format-Table -AutoSize) }
  if (-not (Cim Win32_PageFileUsage) -and -not $cs.AutomaticManagedPagefile) {
    FLAG 'PAGEFILE_TAT' 'Pagefile (bo nho ao) dang bi TAT - Windows se treo/cham nang khi het RAM.'
  }

  SH 'Pool bo nho nhan (phat hien ro ri driver)'
  $mem = Cim Win32_PerfFormattedData_PerfOS_Memory
  if ($mem) {
    KV 'PoolNonpagedBytes' (FmtMB $mem.PoolNonpagedBytes)
    KV 'PoolPagedBytes'    (FmtMB $mem.PoolPagedBytes)
    KV 'AvailableMBytes'   ("{0} MB" -f $mem.AvailableMBytes)
    KV '%CommittedInUse'   $mem.PercentCommittedBytesInUse
    if ([double]$mem.PoolNonpagedBytes -gt 1.2GB) { FLAG 'RO_RI_BO_NHO' ("PoolNonpaged = {0} - RAT CAO, nghi ro ri bo nho do driver." -f (FmtMB $mem.PoolNonpagedBytes)) }
    if ([double]$mem.PercentCommittedBytesInUse -gt 90) { FLAG 'BO_NHO_AO_SAP_HET' ("Bo nho commit da dung {0}% - sap het bo nho ao." -f $mem.PercentCommittedBytesInUse) }
  }
}

# =============================== 4. O DIA VAT LY ==============================
Sec 'O dia vat ly, suc khoe SMART' {
  $anyHDD = $false
  $pds = @()
  try { $pds = @(Get-PhysicalDisk -ErrorAction Stop) } catch {}
  if ($pds.Count -gt 0) {
    foreach ($d in $pds) {
      SH ("O dia #{0}: {1}" -f $d.DeviceId, $d.FriendlyName)
      KV 'Loai o (MediaType)' $d.MediaType
      KV 'Ket noi (BusType)'  $d.BusType
      KV 'Dung luong'         (FmtGB $d.Size)
      KV 'Suc khoe'           ("Health={0} | Operational={1}" -f $d.HealthStatus, ($d.OperationalStatus -join ','))
      KV 'Firmware'           $d.FirmwareVersion
      KV 'SpindleSpeed'       $d.SpindleSpeed
      if ("$($d.MediaType)" -eq 'HDD' -or ($d.SpindleSpeed -gt 0 -and $d.SpindleSpeed -lt 65535)) { $anyHDD = $true }
      if ("$($d.HealthStatus)" -ne 'Healthy') { FLAG 'O_DIA_KHONG_KHOE' -Muc 'loi' -Tiep 'checkwinfix/phan-cung' ("O dia '{0}' co HealthStatus = {1} - O DIA DANG HONG, sao luu du lieu ngay." -f $d.FriendlyName, $d.HealthStatus) }
      try {
        $rc = $d | Get-StorageReliabilityCounter -ErrorAction Stop
        if ($rc) {
          KV 'SMART - Nhiet do'        ("{0} C (max {1} C)" -f $rc.Temperature, $rc.TemperatureMax)
          KV 'SMART - Gio da chay'     $rc.PowerOnHours
          KV 'SMART - Do hao mon(%)'   $rc.Wear
          KV 'SMART - Loi doc'         ("Corrected={0}  Uncorrected={1}" -f $rc.ReadErrorsCorrected, $rc.ReadErrorsUncorrected)
          KV 'SMART - Loi ghi'         ("Corrected={0}  Uncorrected={1}" -f $rc.WriteErrorsCorrected, $rc.WriteErrorsUncorrected)
          KV 'SMART - StartStopCycle'  $rc.StartStopCycleCount
          if ([double]$rc.ReadErrorsUncorrected -gt 0 -or [double]$rc.WriteErrorsUncorrected -gt 0) {
            FLAG 'O_DIA_LOI_DOC_GHI' -Muc 'loi' -Tiep 'checkwinfix/phan-cung' ("O dia '{0}' co loi doc/ghi KHONG sua duoc - o dia dang hong, day la nguyen nhan cham hang dau." -f $d.FriendlyName)
          }
          if ([double]$rc.Wear -ge 90) { FLAG 'SSD_HAO_MON' -Tiep 'checkwinfix/phan-cung' ("SSD '{0}' da hao mon {1}% - gan het tuoi tho." -f $d.FriendlyName, $rc.Wear) }
          if ([double]$rc.Temperature -ge 60) { FLAG 'O_DIA_NONG' ("O dia '{0}' nong {1}C - co the bi giam toc do bao ve." -f $d.FriendlyName, $rc.Temperature) }
        }
      } catch { W '  (khong doc duoc StorageReliabilityCounter - can quyen Admin hoac o dia khong ho tro)' }
    }
  } else {
    W '  (Get-PhysicalDisk khong kha dung - dung Win32_DiskDrive)'
    WL (Cim Win32_DiskDrive | Select-Object Model, InterfaceType, @{n='Size';e={FmtGB $_.Size}}, Status, Partitions | Format-Table -AutoSize)
  }
  if ($anyHDD) { FLAG 'O_HE_THONG_HDD' 'May dang dung o cung co (HDD) lam o he thong - Windows 10/11 tren HDD se rat cham, nang cap SSD la cach sua triet de nhat.' }

  SH 'Canh bao hong o dia tu driver (SMART FailurePredict)'
  $fps = @(Cim MSStorageDriver_FailurePredictStatus 'root\wmi')
  if ($fps) {
    foreach ($f in $fps) {
      KV 'O dia' $f.InstanceName
      KV '  Du doan se hong' $f.PredictFailure
      KV '  Ma ly do'        $f.Reason
      if ($f.PredictFailure) { FLAG 'SMART_SAP_HONG' -Muc 'loi' -Tiep 'checkwinfix/phan-cung' ("SMART bao o dia '{0}' SAP HONG (PredictFailure=TRUE). Sao luu ngay va thay o." -f $f.InstanceName) }
    }
  } else { W '  (khong co du lieu - thuong gap voi o NVMe hoac o USB)' }

  SH 'Chi so SMART chi tiet'
  $critical = @(5, 10, 184, 187, 188, 196, 197, 198)
  $fpd = @(Get-SmartThuocTinh)
  if ($fpd) {
    foreach ($disk in $fpd) {
      W ("  O dia: " + $disk.O)
      if (-not $disk.ThuocTinh.Count) { W '    (khong co du lieu)'; continue }
      W ('    {0,-28} {1,-5} {2,-6} {3,-6} {4}' -f 'Thuoc tinh', 'ID', 'Value', 'Worst', 'Raw')
      foreach ($a in $disk.ThuocTinh) {
        W ('    {0,-28} {1,-5} {2,-6} {3,-6} {4}' -f $a.Ten, $a.Id, $a.Value, $a.Worst, $a.Raw)
        if ($critical -contains $a.Id -and $a.Raw -gt 0) {
          FLAG 'SMART_BAD_SECTOR' -Muc 'loi' -Tiep 'checkwinfix/phan-cung' ("SMART: {0} (ID {1}) = {2} tren o '{3}' - O DIA CO BAD SECTOR / LOI PHAN CUNG. Day thuong la nguyen nhan may dot nhien cham." -f $a.Ten, $a.Id, $a.Raw, $disk.O)
        }
        if ($a.Id -eq 199 -and $a.Raw -gt 10) { FLAG 'SATA_CRC' -Tiep 'checkwinfix/phan-cung' ("SMART: UDMA_CRC_Error = {0} - CAP SATA long/hong hoac cong SATA kem." -f $a.Raw) }
      }
    }
  } else { W '  (khong doc duoc bang thuoc tinh SMART)' }
}

# =============================== 5. DUNG LUONG ================================
Sec 'Dung luong o dia va file rac' {
  SH 'Phan vung'
  WL (Cim Win32_LogicalDisk -Filter 'DriveType=3' | Select-Object DeviceID, VolumeName, FileSystem,
      @{n='Tong';e={FmtGB $_.Size}}, @{n='Trong';e={FmtGB $_.FreeSpace}},
      @{n='Trong(%)';e={ if ($_.Size -gt 0) { [math]::Round(100.0*$_.FreeSpace/$_.Size,1) } else { 0 } }} | Format-Table -AutoSize)
  foreach ($ld in (Cim Win32_LogicalDisk -Filter 'DriveType=3')) {
    if ([double]$ld.Size -gt 0) {
      $fp = [math]::Round(100.0 * [double]$ld.FreeSpace / [double]$ld.Size, 1)
      if ($fp -lt 10) { FLAG 'O_DIA_SAP_DAY' -Tiep $(if ($ld.DeviceID -eq $env:SystemDrive) { 'don-o-c/kiem-tra' } else { '' }) ("O {0} chi con {1}% trong ({2}) - Windows can >10-15% trong de chay muot." -f $ld.DeviceID, $fp, (FmtGB $ld.FreeSpace)) }
    }
  }

  SH 'Co dia bi danh dau loi (dirty bit) - can chkdsk'
  foreach ($ld in (Cim Win32_LogicalDisk -Filter 'DriveType=3')) {
    $r = (cmd /c "fsutil dirty query $($ld.DeviceID)" 2>&1) -join ' '
    KV $ld.DeviceID (Trunc $r 120)
    if ($r -match 'is Dirty|la Dirty|bi Dirty') { FLAG 'O_DIA_DIRTY' -Muc 'loi' -Tiep 'fix-win/o-dia-sua' ("O {0} bi danh dau DIRTY - he thong file dang loi, can chay chkdsk." -f $ld.DeviceID) }
  }

  SH 'Thu muc rac / phinh to'
  KV 'Windows\Temp'            (FolderSize "$env:SystemRoot\Temp" 10)
  KV 'Temp cua user'           (FolderSize $env:TEMP 10)
  KV 'SoftwareDistribution\Download' (FolderSize "$env:SystemRoot\SoftwareDistribution\Download" 10)
  KV 'WER ReportQueue'         (FolderSize "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" 10)
  KV 'Prefetch'                (FolderSize "$env:SystemRoot\Prefetch" 5)
  KV 'Windows.old'             $(if (Test-Path "$env:SystemDrive\Windows.old") { 'CO TON TAI - chiem nhieu dung luong' } else { 'khong co' })
  $edb = "$env:ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.edb"
  if (Test-Path -LiteralPath $edb) {
    $sz = (Get-Item -LiteralPath $edb).Length
    KV 'Chi muc tim kiem (.edb)' (FmtMB $sz)
    if ($sz -gt 4GB) { FLAG 'CHI_MUC_TIM_KIEM_LON' ("File chi muc Windows Search = {0} - qua lon, dich vu SearchIndexer co the dang an het CPU/o dia." -f (FmtMB $sz)) }
  }
  foreach ($f in @("$env:SystemDrive\pagefile.sys", "$env:SystemDrive\hiberfil.sys", "$env:SystemDrive\swapfile.sys")) {
    try { $fi = Get-Item -LiteralPath $f -Force -ErrorAction Stop; KV (Split-Path $f -Leaf) (FmtMB $fi.Length) } catch { KV (Split-Path $f -Leaf) 'khong co / khong doc duoc' }
  }
  $cbs = "$env:SystemRoot\Logs\CBS\CBS.log"
  if (Test-Path -LiteralPath $cbs) { KV 'CBS.log' (FmtMB (Get-Item -LiteralPath $cbs).Length) }
}

# =============================== 6. DO HIEU NANG ==============================
Sec 'Do hieu nang thoi gian thuc (3 lan, moi lan cach 4 giay)' {
  W '  Ghi chu: %Idle cua o dia thap (<20%) = o dia dang bi vat kiet = dau hieu "100% disk".'
  W ''
  for ($i = 1; $i -le 3; $i++) {
    $p  = Cim Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
    $sy = Cim Win32_PerfFormattedData_PerfOS_System
    $mm = Cim Win32_PerfFormattedData_PerfOS_Memory
    $dk = @(Cim Win32_PerfFormattedData_PerfDisk_PhysicalDisk)
    W ("  --- Lan do {0} ---" -f $i)
    if ($p) { W ("    CPU: tong={0}%  kernel={1}%  interrupt={2}%  DPC={3}%  ngat/s={4}" -f $p.PercentProcessorTime, $p.PercentPrivilegedTime, $p.PercentInterruptTime, $p.PercentDPCTime, $p.InterruptsPersec) }
    if ($sy) { W ("    He thong: hang doi CPU={0}  chuyen ngu canh/s={1}  system call/s={2}" -f $sy.ProcessorQueueLength, $sy.ContextSwitchesPersec, $sy.SystemCallsPersec)
               if ([double]$sy.ProcessorQueueLength -gt (2 * $nlp)) { FLAG 'CPU_QUA_TAI' ("Hang doi CPU = {0} (nhieu hon 2x so luong CPU) - CPU dang bi qua tai." -f $sy.ProcessorQueueLength) } }
    if ($mm) { W ("    Bo nho: trong={0}MB  page/s={1}  pagefault/s={2}  %commit={3}" -f $mm.AvailableMBytes, $mm.PagesPerSec, $mm.PageFaultsPersec, $mm.PercentCommittedBytesInUse)
               if ([double]$mm.PagesPerSec -gt 1000) { FLAG 'THIEU_RAM_PAGING' ("Pages/sec = {0} - may dang doc/ghi bo nho ao lien tuc (thieu RAM) => cuc ky cham." -f $mm.PagesPerSec) } }
    foreach ($d in ($dk | Sort-Object Name)) {
      W ("    O dia [{0,-10}] %Idle={1,-4} %DiskTime={2,-5} Queue={3,-4} Doc={4,8} KB/s Ghi={5,8} KB/s" -f $d.Name, $d.PercentIdleTime, $d.PercentDiskTime, $d.CurrentDiskQueueLength, [math]::Round([double]$d.DiskReadBytesPersec/1KB), [math]::Round([double]$d.DiskWriteBytesPersec/1KB))
      if ($d.Name -eq '_Total' -and [double]$d.PercentIdleTime -lt 15 -and $i -ge 2) {
        FLAG 'O_DIA_100' ("O dia dang ban gan 100% (%Idle={0}) ngay ca luc khong lam gi - kinh dien cua loi '100% disk'." -f $d.PercentIdleTime)
      }
    }
    if ($i -lt 3) { Start-Sleep -Seconds 4 }
  }
}

# =============================== 7. TIEN TRINH ================================
Sec 'Tien trinh dang an CPU / RAM / o dia' {
  $null = Cim Win32_PerfFormattedData_PerfProc_Process
  Start-Sleep -Seconds 5
  $pp = @(Cim Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.Name -ne '_Total' -and $_.Name -ne 'Idle' })
  $wmap = @{}
  foreach ($x in (Cim Win32_Process)) { try { $wmap[[int]$x.ProcessId] = $x } catch {} }

  SH ("TOP 18 theo CPU (da chia cho {0} luong CPU)" -f $nlp)
  W ('  {0,7} {1,10} {2,11} {3,8}  {4,-26} {5}' -f 'CPU%', 'RAM(MB)', 'IO(KB/s)', 'PID', 'Ten', 'Duong dan')
  $topCpu = $pp | Sort-Object { [double]$_.PercentProcessorTime } -Descending | Select-Object -First 18
  foreach ($x in $topCpu) {
    $pid2 = [int]$x.IDProcess
    $path = ''
    if ($wmap.ContainsKey($pid2)) { $path = $wmap[$pid2].ExecutablePath }
    $cpuP = [math]::Round([double]$x.PercentProcessorTime / $nlp, 1)
    W ('  {0,7} {1,10} {2,11} {3,8}  {4,-26} {5}' -f $cpuP, [math]::Round([double]$x.WorkingSetPrivate/1MB), [math]::Round([double]$x.IODataBytesPersec/1KB), $pid2, (Trunc $x.Name 26), (Trunc $path 70))
    if ($cpuP -ge 25 -and $x.Name -notmatch '^(System|Registry|MsMpEng|TiWorker|SearchIndexer|explorer)') {
      FLAG 'TIEN_TRINH_AN_CPU' ("Tien trinh '{0}' (PID {1}) dang an {2}% CPU lien tuc. Duong dan: {3}" -f $x.Name, $pid2, $cpuP, $path)
    }
    if ($x.Name -match 'MsMpEng' -and $cpuP -ge 20) { FLAG 'DEFENDER_AN_CPU' ("Windows Defender (MsMpEng) an {0}% CPU - dang quet hoac bi xung dot voi phan mem diet virus khac." -f $cpuP) }
    if ($x.Name -match 'TiWorker|TrustedInstaller' -and $cpuP -ge 15) { FLAG 'WINDOWS_UPDATE_CHAY_NEN' 'TiWorker/TrustedInstaller dang an CPU - Windows Update dang cai dat nen (hoac bi ket).' }
    if ($x.Name -match 'SearchIndexer|SearchProtocolHost|SearchFilterHost' -and $cpuP -ge 15) { FLAG 'WINDOWS_SEARCH_LAP_CHI_MUC' 'Windows Search dang lap chi muc lai toan bo o dia - cham tam thoi hoac bi ket.' }
    if ($path -match '\\AppData\\|\\Temp\\|\\ProgramData\\' -and $cpuP -ge 10) { FLAG 'NGHI_MA_DOC' -Muc 'loi' ("NGHI NGO: '{0}' chay tu thu muc tam/AppData va an {1}% CPU - can kiem tra ma doc/dao tien ao. {2}" -f $x.Name, $cpuP, $path) }
  }

  SH 'TOP 15 theo RAM'
  W ('  {0,10} {1,8}  {2,-28} {3}' -f 'RAM(MB)', 'PID', 'Ten', 'Duong dan')
  foreach ($x in ($pp | Sort-Object { [double]$_.WorkingSetPrivate } -Descending | Select-Object -First 15)) {
    $pid2 = [int]$x.IDProcess
    $path = ''
    if ($wmap.ContainsKey($pid2)) { $path = $wmap[$pid2].ExecutablePath }
    W ('  {0,10} {1,8}  {2,-28} {3}' -f [math]::Round([double]$x.WorkingSetPrivate/1MB), $pid2, (Trunc $x.Name 28), (Trunc $path 70))
  }

  SH 'TOP 12 theo luu luong doc/ghi o dia'
  W ('  {0,11} {1,11} {2,8}  {3,-28} {4}' -f 'Doc(KB/s)', 'Ghi(KB/s)', 'PID', 'Ten', 'Duong dan')
  foreach ($x in ($pp | Sort-Object { [double]$_.IODataBytesPersec } -Descending | Select-Object -First 12)) {
    $pid2 = [int]$x.IDProcess
    $path = ''
    if ($wmap.ContainsKey($pid2)) { $path = $wmap[$pid2].ExecutablePath }
    W ('  {0,11} {1,11} {2,8}  {3,-28} {4}' -f [math]::Round([double]$x.IOReadBytesPersec/1KB), [math]::Round([double]$x.IOWriteBytesPersec/1KB), $pid2, (Trunc $x.Name 28), (Trunc $path 70))
  }

  SH 'Thong ke chung'
  KV 'Tong so tien trinh' $pp.Count
  KV 'Tong so luong (thread)' (($pp | Measure-Object -Property ThreadCount -Sum).Sum)
  KV 'Tong so handle' (($pp | Measure-Object -Property HandleCount -Sum).Sum)
  $chrome = @($pp | Where-Object { $_.Name -match 'chrome|msedge|firefox|coccoc|opera|brave' })
  if ($chrome.Count -gt 0) {
    KV 'So tien trinh trinh duyet' $chrome.Count
    KV 'RAM trinh duyet dang dung' (FmtMB (($chrome | Measure-Object -Property WorkingSetPrivate -Sum).Sum))
    if ($chrome.Count -gt 40) { FLAG 'NHIEU_TIEN_TRINH_TRINH_DUYET' ("Co {0} tien trinh trinh duyet dang chay (qua nhieu tab/extension) - an rat nhieu RAM." -f $chrome.Count) }
  }

  SH 'svchost dang an CPU chua dich vu gi ben trong'
  $svcAll = @(Cim Win32_Service | Where-Object { [int]$_.ProcessId -gt 0 })
  $sv = @($topCpu | Where-Object { $_.Name -match '^svchost' })
  if ($sv.Count -eq 0) { W '  (khong co svchost nao trong top CPU)' }
  foreach ($x in $sv) {
    $pid2 = [int]$x.IDProcess
    $nms = @($svcAll | Where-Object { [int]$_.ProcessId -eq $pid2 } | ForEach-Object { $_.Name })
    $cpuP = [math]::Round([double]$x.PercentProcessorTime / $nlp, 1)
    W ('  PID {0,-7} CPU {1,6}%  ->  {2}' -f $pid2, $cpuP, ($nms -join ', '))
    if ($cpuP -ge 15 -and $nms.Count -gt 0) { FLAG 'SVCHOST_AN_CPU' ("svchost PID {0} an {1}% CPU, chua dich vu: {2}" -f $pid2, $cpuP, ($nms -join ', ')) }
  }

  SH 'Kiem tra chu ky so cua cac tien trinh dang an CPU'
  $checked = @{}
  foreach ($x in $topCpu) {
    $pid2 = [int]$x.IDProcess
    if (-not $wmap.ContainsKey($pid2)) { continue }
    $path = $wmap[$pid2].ExecutablePath
    if ([string]::IsNullOrWhiteSpace($path) -or $checked.ContainsKey($path)) { continue }
    $checked[$path] = $true
    $sig = $null
    try { $sig = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop } catch {}
    $subj = ''
    if ($sig -and $sig.SignerCertificate) { $subj = ($sig.SignerCertificate.Subject -split ',')[0] }
    $st = 'n/a'
    if ($sig) { $st = $sig.Status }
    W ("  [{0,-14}] {1,-52} {2}" -f $st, (Trunc $path 52), (Trunc $subj 50))
    if ($sig -and $sig.Status -ne 'Valid' -and $path -notmatch '\\Windows\\') {
      FLAG 'FILE_KHONG_CHU_KY' ("File '{0}' KHONG co chu ky so hop le (Status={1}) nhung dang chiem CPU - can kiem tra." -f $path, $sig.Status)
    }
  }
}

# =============================== 8. KHOI DONG CUNG ============================
Sec 'Chuong trinh khoi dong cung Windows' {
  SH 'Win32_StartupCommand (Run keys + thu muc Startup)'
  WL (Cim Win32_StartupCommand | Select-Object @{n='Ten';e={Trunc $_.Name 30}}, @{n='Vi tri';e={$_.Location}}, @{n='User';e={$_.User}}, @{n='Lenh';e={Trunc $_.Command 90}} | Format-Table -AutoSize -Wrap)

  SH 'Trang thai bat/tat trong Task Manager > Startup'
  foreach ($sa in @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder')) {
    if (-not (Test-Path -LiteralPath $sa)) { continue }
    W ("  [$sa]")
    $k = Get-Item -LiteralPath $sa
    foreach ($nm in $k.GetValueNames()) {
      $val = $k.GetValue($nm)
      $state = 'BAT'
      try { if ($val -is [byte[]] -and $val.Length -gt 0 -and ($val[0] -band 1) -eq 1) { $state = 'tat' } } catch {}
      W ("    {0,-10} {1}" -f $state, $nm)
    }
  }

  SH 'Thu muc Startup'
  foreach ($sf in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
                    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup")) {
    W ("  [$sf]")
    WL (Get-ChildItem -LiteralPath $sf -Force -ErrorAction SilentlyContinue | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize)
  }

  SH 'Cac diem hay bi ma doc chiem (kiem tra bat thuong)'
  $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  KV 'Winlogon Shell'    (Reg $wl 'Shell')
  KV 'Winlogon Userinit' (Reg $wl 'Userinit')
  if ((Reg $wl 'Shell') -and (Reg $wl 'Shell') -notmatch '^explorer\.exe,?\s*$') { FLAG 'WINLOGON_SHELL_BI_DOI' -Muc 'loi' ("Winlogon Shell bi doi thanh: " + (Reg $wl 'Shell')) }
  if ((Reg $wl 'Userinit') -and (Reg $wl 'Userinit') -notmatch '^C:\\Windows\\system32\\userinit\.exe,?\s*$') { FLAG 'WINLOGON_USERINIT_BI_DOI' -Muc 'loi' ("Winlogon Userinit bi doi thanh: " + (Reg $wl 'Userinit')) }
  $ai = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows'
  KV 'AppInit_DLLs'      (Reg $ai 'AppInit_DLLs')
  KV 'LoadAppInit_DLLs'  (Reg $ai 'LoadAppInit_DLLs')
  if ((Reg $ai 'AppInit_DLLs')) { FLAG 'APPINIT_DLLS' ("AppInit_DLLs co gia tri: " + (Reg $ai 'AppInit_DLLs') + " - DLL nay bi nap vao MOI ung dung, rat hay gay cham/treo.") }

  SH 'Image File Execution Options bi gan Debugger'
  $ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
  $cnt = 0
  foreach ($sub in (Get-ChildItem -LiteralPath $ifeo -ErrorAction SilentlyContinue)) {
    $dbg = Reg $sub.PSPath 'Debugger'
    if ($dbg) { W ("  {0,-34} -> {1}" -f $sub.PSChildName, $dbg); $cnt++
      FLAG 'IFEO_DEBUGGER' ("IFEO: '{0}' bi gan Debugger '{1}' - co the la ma doc hoac phan mem chan chuong trinh." -f $sub.PSChildName, $dbg) }
  }
  if ($cnt -eq 0) { W '  (khong co - binh thuong)' }
}

# =============================== 9. DICH VU ===================================
Sec 'Dich vu (services)' {
  $svcs = @(Cim Win32_Service)
  KV 'Tong so dich vu'       $svcs.Count
  KV 'Dang chay'             (@($svcs | Where-Object { $_.State -eq 'Running' })).Count
  KV 'Auto nhung khong chay' (@($svcs | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' })).Count

  SH 'Dich vu BEN THU BA dang chay (khong nam trong C:\Windows)'
  $third = @($svcs | Where-Object { $_.State -eq 'Running' -and $_.PathName -and $_.PathName -notmatch '(?i)^\"?C:\\Windows\\' })
  W ('  {0,-28} {1,-12} {2}' -f 'Ten dich vu', 'StartMode', 'Duong dan')
  foreach ($s in ($third | Sort-Object Name)) {
    W ('  {0,-28} {1,-12} {2}' -f (Trunc $s.Name 28), $s.StartMode, (Trunc $s.PathName 85))
  }
  KV 'So luong' $third.Count

  SH 'Dich vu Auto nhung KHONG chay duoc (co the dang loi)'
  WL (@($svcs | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' -and $_.Name -notmatch '^(gupdate|edgeupdate|MapsBroker|RemoteRegistry|sppsvc|TrustedInstaller|dbupdate)' }) |
      Select-Object Name, DisplayName, State, ExitCode | Format-Table -AutoSize)

  SH 'Cac dich vu anh huong hieu nang can chu y'
  foreach ($n in @('SysMain', 'WSearch', 'wuauserv', 'BITS', 'DPS', 'DiagTrack', 'Spooler', 'WinDefend', 'TrustedInstaller', 'CDPUserSvc', 'OneSyncSvc', 'PcaSvc', 'SgrmBroker', 'WaaSMedicSvc', 'UsoSvc')) {
    $s = $svcs | Where-Object { $_.Name -eq $n } | Select-Object -First 1
    if ($s) { W ('  {0,-20} State={1,-10} StartMode={2,-10} PID={3}' -f $s.Name, $s.State, $s.StartMode, $s.ProcessId) }
  }
}

# =============================== 10. TAC VU HEN GIO ===========================
Sec 'Tac vu theo lich (Scheduled Tasks) khong phai cua Microsoft' {
  $tasks = @()
  try { $tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' }) } catch { W '  (khong doc duoc Get-ScheduledTask)' }
  KV 'So tac vu dang bat' $tasks.Count
  W ''
  W ('  {0,-40} {1,-10} {2,-19} {3}' -f 'Duong dan\Ten', 'State', 'Chay lan cuoi', 'Hanh dong')
  foreach ($t in ($tasks | Select-Object -First 60)) {
    $info = $null
    try { $info = $t | Get-ScheduledTaskInfo -ErrorAction Stop } catch {}
    $act = ''
    try { $act = (($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ; ') } catch {}
    $lr = ''
    if ($info) { $lr = '{0:yyyy-MM-dd HH:mm}' -f $info.LastRunTime }
    W ('  {0,-40} {1,-10} {2,-19} {3}' -f (Trunc ($t.TaskPath + $t.TaskName) 40), $t.State, $lr, (Trunc $act 80))
  }
  SH 'Tac vu he thong hay gay cham (Microsoft) dang bat'
  foreach ($nm in @('ScheduledDefrag', 'StartComponentCleanup', 'ProactiveScan', 'Scheduled Scan', 'BackgroundUploadTask', 'Consolidator', 'UsbCeip', 'Proxy', 'MaintenanceTask')) {
    try {
      $mt = Get-ScheduledTask -TaskName $nm -ErrorAction SilentlyContinue
      if ($mt) { foreach ($m in $mt) { W ('  {0,-46} {1}' -f ($m.TaskPath + $m.TaskName), $m.State) } }
    } catch {}
  }
  SH 'Automatic Maintenance (bao tri tu dong)'
  $mnt = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance'
  KV 'Gio kich hoat'    (Reg $mnt 'Activation Boundary')
  KV 'Wake to run'      (Reg $mnt 'WakeUp')
}

# =============================== 11. NGUON DIEN ===============================
Sec 'Nguon dien, Power Plan, pin' {
  SH 'Power plan dang dung'
  WL ((powercfg /getactivescheme 2>&1) -join "`n")
  SH 'Danh sach power plan'
  WL ((powercfg /list 2>&1) -join "`n")

  function PwrVal {
    param([string]$sub, [string]$set)
    $o = (powercfg /qh SCHEME_CURRENT $sub $set 2>&1) -join "`n"
    $m = [regex]::Matches($o, '0x[0-9a-fA-F]{8}')
    if ($m.Count -ge 2) {
      $ac = [Convert]::ToInt64($m[$m.Count - 2].Value, 16)
      $dc = [Convert]::ToInt64($m[$m.Count - 1].Value, 16)
      return "AC=$ac  DC=$dc"
    }
    return 'n/a'
  }
  SH 'Gioi han hieu nang CPU trong power plan'
  $SUBPROC = '54533251-82be-4824-96c1-47b60b740d00'
  $vmax = PwrVal $SUBPROC 'bc5038f7-23e0-4960-96da-33abaf5935ec'
  $vmin = PwrVal $SUBPROC '893dee8e-2bef-41e0-89c6-b55d0929964c'
  KV 'Maximum processor state' $vmax
  KV 'Minimum processor state' $vmin
  KV 'System cooling policy'   (PwrVal $SUBPROC '94d3a615-a899-4ac5-ae2b-e4d8f634367f')
  KV 'Processor boost mode'    (PwrVal $SUBPROC 'be337238-0d82-4146-a960-4f3749d470c7')
  if ($vmax -match 'AC=(\d+)') {
    $acv = [int]$Matches[1]
    if ($acv -lt 100 -and $acv -gt 0) { FLAG 'POWER_PLAN_GIOI_HAN_CPU' ("Power plan dang gioi han CPU toi da o {0}% khi cam dien - day la nguyen nhan kinh dien lam may dot nhien cham." -f $acv) }
  }

  SH 'Pin (neu la laptop)'
  $bat = @(Cim Win32_Battery)
  if ($bat.Count -eq 0) { W '  (may ban - khong co pin)' }
  else {
    foreach ($b in $bat) {
      KV 'Pin'               $b.Name
      KV '  Phan tram con'   $b.EstimatedChargeRemaining
      $bs = switch ([int]$b.BatteryStatus) { 1 {'Dang dung pin (khong cam sac)'} 2 {'Dang cam dien (AC)'} 3 {'Da sac day'} 4 {'Yeu'} 5 {'Rat yeu'} default {"Ma $($b.BatteryStatus)"} }
      KV '  Trang thai'      $bs
      if ([int]$b.BatteryStatus -eq 1) { FLAG 'DANG_CHAY_PIN' 'May dang chay bang PIN - Windows tu dong giam hieu nang. Neu dang cam sac ma van bao dung pin => sac/pin loi.' }
    }
    try {
      $des = (Cim BatteryStaticData 'root\wmi'   | Select-Object -First 1).DesignedCapacity
      $ful = (Cim BatteryFullChargedCapacity 'root\wmi' | Select-Object -First 1).FullChargedCapacity
      if ($des -gt 0 -and $ful -gt 0) {
        $h = [math]::Round(100.0 * $ful / $des, 1)
        KV 'Suc khoe pin' ("{0}%  (thiet ke {1} mWh / thuc te {2} mWh)" -f $h, $des, $ful)
        if ($h -lt 60) { FLAG 'PIN_CHAI' ("Pin chi con {0}% dung luong thiet ke - pin chai. Nhieu laptop se TU BOP XUNG CPU khi pin hong." -f $h) }
      }
    } catch {}
  }
}

# =============================== 12. BAO MAT ==================================
Sec 'Phan mem diet virus / Windows Defender' {
  SH 'Cac san pham diet virus dang dang ky voi Windows'
  $avs = @(Cim AntiVirusProduct 'root\SecurityCenter2')
  if ($avs.Count -eq 0) { W '  (khong doc duoc - may co the la ban Server)' }
  foreach ($a in $avs) {
    $ps = [Convert]::ToString([int]$a.productState, 16).PadLeft(6, '0')
    $rt = 'TAT'
    if ($ps.Substring(2, 2) -match '^(10|11)$') { $rt = 'BAT' }
    $upd = 'cu'
    if ($ps.Substring(4, 2) -eq '00') { $upd = 'moi' }
    W ("  {0,-42} RealTime={1,-4} Dinh nghia={2,-5} state=0x{3}" -f $a.displayName, $rt, $upd, $ps)
    W ("     -> " + $a.pathToSignedProductExe)
  }
  if ($avs.Count -gt 1) {
    $nonDef = @($avs | Where-Object { $_.displayName -notmatch 'Windows Defender|Microsoft Defender' })
    if ($nonDef.Count -ge 1) { FLAG 'NHIEU_DIET_VIRUS' ("Co {0} phan mem diet virus cung cai ({1}) - xung dot AV la nguyen nhan cham/treo rat pho bien." -f $avs.Count, (($avs | ForEach-Object { $_.displayName }) -join ', ')) }
    if ($nonDef.Count -ge 2) { FLAG 'HAI_DIET_VIRUS_BEN_THU_BA' 'Co TU 2 phan mem diet virus ben thu ba tro len - bat buoc go bot 1 cai.' }
  }

  SH 'Trang thai Microsoft Defender'
  try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    KV 'Che do chay'            $mp.AMRunningMode
    KV 'Real-time protection'   $mp.RealTimeProtectionEnabled
    KV 'Behavior monitor'       $mp.BehaviorMonitorEnabled
    KV 'Tuoi dinh nghia (ngay)' $mp.AntivirusSignatureAge
    KV 'Quet nhanh lan cuoi'    ("{0:yyyy-MM-dd HH:mm} (cach day {1} ngay)" -f $mp.QuickScanEndTime, $mp.QuickScanAge)
    KV 'Quet day du lan cuoi'   ("{0:yyyy-MM-dd HH:mm} (cach day {1} ngay)" -f $mp.FullScanEndTime, $mp.FullScanAge)
    KV 'Tamper Protection'      $mp.IsTamperProtected
    KV 'Phien ban engine'       $mp.AMEngineVersion
    if ([int]$mp.AntivirusSignatureAge -gt 14) { FLAG 'DINH_NGHIA_VIRUS_CU' ("Dinh nghia virus cu {0} ngay - may co the dang bi nhiem hoac Update bi hong." -f $mp.AntivirusSignatureAge) }
  } catch { W '  (khong doc duoc Get-MpComputerStatus)' }

  try {
    $pref = Get-MpPreference -ErrorAction Stop
    SH 'Thiet lap Defender'
    KV 'DisableRealtimeMonitoring' $pref.DisableRealtimeMonitoring
    KV 'ScanAvgCPULoadFactor'      $pref.ScanAvgCPULoadFactor
    KV 'ScanScheduleDay'           $pref.ScanScheduleDay
    KV 'ExclusionPath'             ((@($pref.ExclusionPath)) -join ' | ')
    KV 'ExclusionProcess'          ((@($pref.ExclusionProcess)) -join ' | ')
    KV 'ExclusionExtension'        ((@($pref.ExclusionExtension)) -join ' | ')
    if ($pref.ExclusionPath -contains 'C:\' -or $pref.ExclusionPath -contains 'C:\Windows') {
      FLAG 'DEFENDER_LOAI_TRU_O_C' -Muc 'loi' 'Defender dang loai tru ca o C: - dau hieu ma doc da tu them ngoai le.'
    }
  } catch {}
}

# =============================== 13. VBS / HVCI ===============================
Sec 'Bao mat ao hoa (VBS / Core Isolation / Hyper-V)' {
  $dg = Cim Win32_DeviceGuard 'root\Microsoft\Windows\DeviceGuard'
  if ($dg) {
    $vbs = switch ([int]$dg.VirtualizationBasedSecurityStatus) { 0 {'TAT'} 1 {'Bat nhung chua chay'} 2 {'DANG CHAY'} default {'?'} }
    KV 'VBS (Virtualization Based Security)' $vbs
    $run = @($dg.SecurityServicesRunning)
    $names = @()
    foreach ($r in $run) { $names += switch ([int]$r) { 1 {'Credential Guard'} 2 {'HVCI / Memory Integrity'} 3 {'System Guard'} default {"Svc$r"} } }
    KV 'Dich vu bao mat dang chay' (($names) -join ', ')
    KV 'Dich vu duoc cau hinh'     (($dg.SecurityServicesConfigured) -join ', ')
    if ($run -contains 2) { FLAG 'HVCI_BAT' 'Memory Integrity (HVCI) dang BAT - tren CPU doi cu (truoc Intel gen 8 / AMD Zen2) no lam may cham thay ro. Day la mot nghi pham lon neu may dot nhien cham sau khi cap nhat Windows.' }
    if ([int]$dg.VirtualizationBasedSecurityStatus -eq 2) { FLAG 'VBS_BAT' -Muc 'thong-tin' 'VBS dang chay - giam hieu nang 5-15% (nhieu hon tren may cu / may choi game).' }
  }
  KV 'HVCI registry Enabled' (Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled')
  $hv = (bcdedit /enum '{current}' 2>&1) -join "`n"
  $m = [regex]::Match($hv, '(?im)^hypervisorlaunchtype\s+(\w+)')
  KV 'hypervisorlaunchtype' $(if ($m.Success) { $m.Groups[1].Value } else { 'khong ro' })
  try {
    $feat = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction Stop
    KV 'Tinh nang Hyper-V' $feat.State
  } catch {}
  $wsl = Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\LxssManager' 'Start'
  KV 'WSL (LxssManager Start)' $wsl
}

# =============================== 14. CARD MAN HINH ============================
Sec 'Card man hinh va driver hien thi' {
  WL (Cim Win32_VideoController | Select-Object Name,
      @{n='Driver';e={$_.DriverVersion}},
      @{n='Ngay driver';e={ '{0:yyyy-MM-dd}' -f (AsDate $_.DriverDate) }},
      @{n='VRAM';e={FmtMB $_.AdapterRAM}},
      @{n='Do phan giai';e={"$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution) @ $($_.CurrentRefreshRate)Hz"}},
      @{n='Trang thai';e={$_.Status}} | Format-List)
  foreach ($v in (Cim Win32_VideoController)) {
    if ($v.Name -match 'Basic Display|Standard VGA') {
      FLAG 'THIEU_DRIVER_MAN_HINH' ("Dang dung '{0}' - MAY KHONG CO DRIVER CARD MAN HINH that. Giao dien se giat, video cham. Can cai lai driver GPU." -f $v.Name)
    }
    $dd = AsDate $v.DriverDate
    if ($dd -and $dd -lt (Get-Date).AddYears(-5)) { FLAG 'DRIVER_MAN_HINH_CU' ("Driver card man hinh '{0}' rat cu (ngay {1:yyyy-MM-dd})." -f $v.Name, $dd) }
  }
  SH 'Thiet lap do hoa'
  KV 'HwSchMode (GPU scheduling)' (Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode')
  KV 'TdrDelay'                   (Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'TdrDelay')
  SH 'Man hinh dang ket noi'
  WL (Cim Win32_DesktopMonitor | Select-Object Name, ScreenWidth, ScreenHeight, Status | Format-Table -AutoSize)
}

# =============================== 15. THIET BI LOI =============================
Sec 'Thiet bi bi loi trong Device Manager' {
  $bad = @()
  try { $bad = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' }) } catch {}
  if ($bad.Count -gt 0) {
    WL ($bad | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -AutoSize -Wrap)
    foreach ($b in $bad) { FLAG 'THIET_BI_LOI' ("Thiet bi loi: [{0}] {1} (Status={2}) - thieu driver hoac phan cung loi." -f $b.Class, $b.FriendlyName, $b.Status) }
  } else {
    $bad2 = @(Cim Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
    if ($bad2.Count -gt 0) {
      WL ($bad2 | Select-Object Name, ConfigManagerErrorCode, DeviceID | Format-Table -AutoSize -Wrap)
      foreach ($b in $bad2) { FLAG 'THIET_BI_LOI' ("Thiet bi loi: {0} (ma loi {1})" -f $b.Name, $b.ConfigManagerErrorCode) }
    } else { W '  (khong co thiet bi nao bao loi - tot)' }
  }
  SH 'Driver ben thu ba moi nhat theo ngay (20 dong)'
  WL (Cim Win32_PnPSignedDriver | Where-Object { $_.DriverProviderName -and $_.DriverProviderName -ne 'Microsoft' } |
      Select-Object @{n='Ngay';e={ '{0:yyyy-MM-dd}' -f (AsDate $_.DriverDate) }}, DriverVersion, DeviceName, DriverProviderName |
      Sort-Object Ngay -Descending | Select-Object -First 20 | Format-Table -AutoSize -Wrap)
  SH 'O dia / bo dieu khien luu tru dang dung driver gi'
  WL (Cim Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -match 'SCSIADAPTER|HDC|DISKDRIVE' } |
      Select-Object DeviceName, DriverProviderName, DriverVersion, @{n='Ngay';e={ '{0:yyyy-MM-dd}' -f (AsDate $_.DriverDate) }} | Format-Table -AutoSize -Wrap)
}

# =============================== 16. MANG =====================================
Sec 'Mang, proxy, file hosts, o dia mang' {
  SH 'Card mang'
  try {
    WL (Get-NetAdapter -ErrorAction Stop | Select-Object Name, InterfaceDescription, Status, LinkSpeed, DriverVersion, DriverDate | Format-Table -AutoSize -Wrap)
  } catch {
    WL (Cim Win32_NetworkAdapter -Filter 'NetEnabled=TRUE' | Select-Object Name, Speed, MACAddress | Format-Table -AutoSize)
  }
  SH 'Cau hinh IP / DNS'
  try {
    WL (Get-DnsClientServerAddress -ErrorAction Stop | Where-Object { $_.ServerAddresses } | Select-Object InterfaceAlias, AddressFamily, @{n='DNS';e={$_.ServerAddresses -join ', '}} | Format-Table -AutoSize -Wrap)
  } catch { WL ((ipconfig /all 2>&1) -join "`n") }

  SH 'Proxy'
  $ist = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
  KV 'ProxyEnable'   (Reg $ist 'ProxyEnable')
  KV 'ProxyServer'   (Reg $ist 'ProxyServer')
  KV 'AutoConfigURL' (Reg $ist 'AutoConfigURL')
  if ((Reg $ist 'ProxyEnable') -eq 1) { FLAG 'PROXY_BAT' ("Proxy dang BAT: " + (Reg $ist 'ProxyServer') + " - neu ban khong tu dat, day co the la ma doc/adware lam mang cham.") }
  if ((Reg $ist 'AutoConfigURL')) { FLAG 'PROXY_PAC' ("Co AutoConfigURL (PAC): " + (Reg $ist 'AutoConfigURL') + " - rat hay lam trinh duyet cham; kiem tra xem co phai ban dat khong.") }
  WL ((netsh winhttp show proxy 2>&1) -join "`n")

  SH 'File hosts (dong co hieu luc)'
  $hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
  $hl = @()
  try { $hl = @(Get-Content -LiteralPath $hostsFile -ErrorAction Stop | Where-Object { $_.Trim() -ne '' -and $_.Trim() -notmatch '^#' }) } catch {}
  KV 'So dong co hieu luc' $hl.Count
  foreach ($l in ($hl | Select-Object -First 40)) { W ('    ' + $l) }
  if ($hl.Count -gt 15) { FLAG 'HOSTS_NHIEU_DONG' ("File hosts co {0} dong - thuong do phan mem be khoa (crack) chan may chu ban quyen; nhom nay hay di kem ma doc." -f $hl.Count) }

  SH 'O dia mang da anh xa'
  WL ((net use 2>&1) -join "`n")
  SH 'Ket noi mang dang mo (20 dong dau)'
  try { WL (Get-NetTCPConnection -State Established -ErrorAction Stop | Select-Object -First 20 LocalPort, RemoteAddress, RemotePort, OwningProcess | Format-Table -AutoSize) } catch {}
}

# =============================== HAM DOC EVENT LOG ============================
function Ev {
  param([string]$Log, [int[]]$Level, [datetime]$Since, [int]$Max = 1500, [int[]]$Id)
  $f = @{ LogName = $Log; StartTime = $Since }
  if ($Level) { $f['Level'] = $Level }
  if ($Id)    { $f['Id']    = $Id }
  try { Get-WinEvent -FilterHashtable $f -MaxEvents $Max -ErrorAction Stop } catch { $null }
}

# Loi da biet: so theo NGUON + MA (cung mot ma o nguon khac la chuyen khac, vd ID 1 cua Kernel-General la doi gio).
# L = cac muc can dem (1 Critical, 2 Error, 3 Warning); bo trong = ca 3 muc. Nhieu loi o dia, man hinh chi ghi muc Warning.
$WATCH = @(
  @{ P = '^Microsoft-Windows-Kernel-Power$'; Id = 41; M = 'TAT_DOT_NGOT'; Tiep = 'checkwinfix/sup-nguon'; T = 'Kernel-Power: may tat/treo dot ngot (mat dien, nguon yeu, treo cung)' }
  @{ P = '^(Microsoft-Windows-WER-SystemErrorReporting|BugCheck)$'; Id = 1001; M = 'MAN_HINH_XANH'; Tiep = 'checkwinfix/phan-cung'; T = 'BugCheck: man hinh xanh' }
  @{ P = '^EventLog$'; Id = 6008; M = 'TAT_KHONG_DUNG_CACH'; Tiep = 'checkwinfix/sup-nguon'; T = 'Lan truoc may tat khong dung cach' }
  @{ P = '^(storahci|stornvme|storport|Microsoft-Windows-StorPort|iaStor\w*|amd_sata|amdsata|nvstor\w*|LSI_SAS\w*)$'; Id = 129; M = 'O_DIA_RESET'; Tiep = 'checkwinfix/phan-cung'; T = 'Bo dieu khien RESET o dia - O DIA hoac CAP/DRIVER dang loi (gay dung hinh vai giay)' }
  @{ P = '^disk$'; Id = 153; M = 'O_DIA_THU_LAI'; Tiep = 'checkwinfix/phan-cung'; T = 'Disk: IO tren o dia phai thu lai (retry) - o dia yeu' }
  @{ P = '^disk$'; Id = 154; M = 'O_DIA_IO_THAT_BAI'; Muc = 'loi'; Tiep = 'checkwinfix/phan-cung'; T = 'Disk: IO tren o dia THAT BAI do loi phan cung - O DIA DANG HONG, cuu du lieu ngay' }
  @{ P = '^disk$'; Id = 11; M = 'O_DIA_CONTROLLER'; Tiep = 'checkwinfix/phan-cung'; T = 'Disk: controller error - cap SATA/o dia loi' }
  @{ P = '^disk$'; Id = 51; M = 'O_DIA_LOI_PAGING'; Muc = 'loi'; Tiep = 'checkwinfix/phan-cung'; T = 'Disk: loi khi doc/ghi bo nho ao (paging) - o dia sap hong' }
  @{ P = '^disk$'; Id = 7; M = 'O_DIA_BAD_BLOCK'; Muc = 'loi'; Tiep = 'checkwinfix/phan-cung'; T = 'Disk: co bad block' }
  @{ P = '^(Ntfs|Microsoft-Windows-Ntfs)$'; Id = 55; M = 'NTFS_HONG'; Muc = 'loi'; Tiep = 'fix-win/o-dia-sua'; T = 'NTFS hong cau truc - can chkdsk' }
  @{ P = '^(Ntfs|Microsoft-Windows-Ntfs)$'; Id = 98; M = 'NTFS_CAN_QUET'; Tiep = 'fix-win/o-dia-quet'; T = 'NTFS: o can quet loi ngoai tuyen (chkdsk)' }
  @{ P = '^(Ntfs|Microsoft-Windows-Ntfs)$'; Id = 140; M = 'NTFS_KHONG_GHI_DUOC'; Tiep = 'checkwinfix/phan-cung'; T = 'NTFS khong ghi duoc du lieu len o dia' }
  @{ P = '^Display$'; Id = 4101; M = 'DRIVER_MAN_HINH_TREO'; T = 'Driver card man hinh treo va phai khoi dong lai (TDR) - giat/den man hinh' }
  @{ P = '^Microsoft-Windows-Kernel-PnP$'; Id = 219; L = @(1, 2); M = 'NAP_DRIVER_THAT_BAI'; T = 'Nap driver that bai' }
  @{ P = '^Service Control Manager$'; Id = 7031; M = 'DICH_VU_CRASH'; T = 'Dich vu bi crash bat ngo' }
  @{ P = '^Service Control Manager$'; Id = 7034; M = 'DICH_VU_CRASH'; T = 'Dich vu bi crash bat ngo (khong tu khoi dong lai)' }
  @{ P = '^Service Control Manager$'; Id = 7000; M = 'DICH_VU_KHONG_CHAY'; T = 'Dich vu khong khoi dong duoc' }
  @{ P = '^Service Control Manager$'; Id = 7009; M = 'DICH_VU_KHOI_DONG_LAU'; T = 'Dich vu khoi dong qua lau (timeout)' }
  @{ P = '^Service Control Manager$'; Id = 7011; M = 'DICH_VU_KHONG_PHAN_HOI'; T = 'Dich vu khong phan hoi trong thoi gian cho - DAU HIEU MAY BI DUNG HINH' }
  @{ P = '^Microsoft-Windows-Resource-Exhaustion-Detector$'; Id = 2004; M = 'HET_BO_NHO'; T = 'Het bo nho ao (Resource-Exhaustion) - Windows phai dong ung dung' }
  @{ P = '^Microsoft-Windows-WHEA-Logger$'; Id = 1; M = 'WHEA_NGHIEM_TRONG'; Muc = 'loi'; Tiep = 'checkwinfix/giai-ma-whea'; T = 'WHEA: loi phan cung NGHIEM TRONG o lan chay truoc (thuong kem man hinh xanh 0x124)' }
  @{ P = '^Microsoft-Windows-WHEA-Logger$'; Id = 17; M = 'WHEA_DUOC_SUA'; Tiep = 'checkwinfix/giai-ma-whea'; T = 'WHEA: loi phan cung duoc sua (CPU/RAM/PCIe)' }
  @{ P = '^Microsoft-Windows-WHEA-Logger$'; Id = 18; M = 'WHEA_NGHIEM_TRONG'; Muc = 'loi'; Tiep = 'checkwinfix/giai-ma-whea'; T = 'WHEA: loi phan cung NGHIEM TRONG' }
  @{ P = '^Microsoft-Windows-WHEA-Logger$'; Id = 19; M = 'WHEA_DUOC_SUA'; Tiep = 'checkwinfix/giai-ma-whea'; T = 'WHEA: loi phan cung duoc sua' }
  @{ P = '^Microsoft-Windows-WHEA-Logger$'; Id = 47; M = 'WHEA_DUOC_SUA'; Tiep = 'checkwinfix/giai-ma-whea'; T = 'WHEA: loi RAM/PCIe duoc sua' }
)


function Find-WatchHits {
  # Doc nhat ky System 14 ngay theo cac ma trong $WATCH (moi muc), roi giu su kien dung nguon va dung muc.
  param([datetime]$Since = $since14)
  $ids = @($WATCH | ForEach-Object { [int]$_.Id } | Sort-Object -Unique)
  $events = @()
  for ($i = 0; $i -lt $ids.Count; $i += 20) {
    $chunk = $ids[$i..([Math]::Min($i + 19, $ids.Count - 1))]
    $r = Ev 'System' $null $Since 3000 $chunk
    if ($r) { $events += @($r) }
  }
  $groups = [ordered]@{}
  foreach ($e in $events) {
    foreach ($w in $WATCH) {
      if ([int]$e.Id -ne [int]$w.Id -or [string]$e.ProviderName -notmatch $w.P) { continue }
      $levels = if ($w.L) { $w.L } else { @(1, 2, 3) }
      if ($levels -notcontains [int]$e.Level) { continue }
      # Su kien cua nguon 'disk' ghi \Device\HarddiskN\... o truong dau: tach theo tung o (o USB rut ra cung ghi loi nay).
      $dev = ''; $rut = $false
      if ([string]$e.ProviderName -eq 'disk') {
        try { if ([string]$e.Properties[0].Value -match 'Harddisk(\d+)') { $dev = 'Disk ' + $Matches[1]; $rut = (Get-DiskBus ([int]$Matches[1])) -in 'USB', 'KHONG_CON' } } catch {}
      }
      $k = '{0}|{1}|{2}' -f $e.ProviderName, $e.Id, $dev
      $txt = if ($dev) { "$($w.T) [$dev, xem muc o dia de biet la o nao]" } else { $w.T }
      # O USB rut ra khi dang ghi cung ghi cac loi nay: chi la canh bao, khong goi y chan doan o trong may.
      if ($rut) { $txt = "$($w.T) [$dev la o USB hoac o da rut ra: thuong do rut o khi dang ghi, khong phai o trong may]" }
      if (-not $groups.Contains($k)) {
        $groups[$k] = [pscustomobject]@{ Provider = [string]$e.ProviderName; Id = [int]$e.Id; Count = 0; Last = $e.TimeCreated; Text = $txt
          M = $(if ($w.M) { $w.M } else { 'SU_KIEN_LAP_LAI' }); Muc = $(if ($w.Muc -and -not $rut) { $w.Muc } else { 'canh-bao' })
          Tiep = $(if ($rut) { '' } else { [string]$w.Tiep }) }
      }
      $g = $groups[$k]; $g.Count++
      if ($e.TimeCreated -gt $g.Last) { $g.Last = $e.TimeCreated }
      break
    }
  }
  return @($groups.Values | Sort-Object Count -Descending)
}

# =============================== 17. NHAT KY HIEU NANG ========================
Sec 'Nhat ky HIEU NANG cua Windows (muc quan trong nhat)' {
  W '  Log: Microsoft-Windows-Diagnostics-Performance/Operational'
  W '  Day la noi Windows tu ghi lai "cai gi lam may khoi dong/chay cham".'
  W ''
  $dp = Ev 'Microsoft-Windows-Diagnostics-Performance/Operational' $null $since30 400
  if (-not $dp) {
    if (-not $isAdmin) { W '  (KHONG DOC DUOC vi dang chay THIEU QUYEN ADMIN. Hay chay lai bang Run as administrator.)' }
    else { W '  (khong co su kien nao trong 30 ngay, hoac log da bi tat)' }
    return
  }
  KV 'So su kien trong 30 ngay' $dp.Count
  SH 'Thong ke theo loai su kien'
  WL ($dp | Group-Object Id | Sort-Object Count -Descending |
      Select-Object @{n='EventID';e={$_.Name}}, Count, @{n='Y nghia';e={
        switch ([int]$_.Name) {
          100 {'Do thoi gian khoi dong'} 101 {'Ung dung khoi dong cham'} 102 {'Driver khoi dong cham'}
          103 {'Dich vu khoi dong cham'} 106 {'Toi uu nen cham'} 109 {'Thiet bi khoi tao cham'}
          110 {'Nhan he thong khoi dong cham'} 200 {'Do thoi gian tat may'} 201 {'Ung dung lam cham tat may'}
          202 {'Dich vu lam cham tat may'} 203 {'Tat may cham'} 300 {'Do thoi gian ngu/thuc'}
          301 {'Ung dung lam cham thuc day'} 302 {'Dich vu lam cham thuc day'} default {''} }
      }} | Format-Table -AutoSize)

  SH 'Thoi gian khoi dong gan day (Event 100)'
  foreach ($e in ($dp | Where-Object { $_.Id -eq 100 } | Select-Object -First 10)) {
    $x = [xml]$e.ToXml()
    $d = @{}
    foreach ($n in $x.Event.EventData.Data) { $d[$n.Name] = $n.'#text' }
    $bt = 0; $mp = 0
    try { $bt = [int]$d['BootTime'] } catch {}
    try { $mp = [int]$d['MainPathBootTime'] } catch {}
    W ("  {0:yyyy-MM-dd HH:mm}  Tong thoi gian boot = {1} giay  (den man hinh desktop = {2} giay)" -f $e.TimeCreated, [math]::Round($bt/1000,1), [math]::Round($mp/1000,1))
  }
  $last100 = $dp | Where-Object { $_.Id -eq 100 } | Select-Object -First 1
  if ($last100) {
    try {
      $x = [xml]$last100.ToXml(); $d = @{}
      foreach ($n in $x.Event.EventData.Data) { $d[$n.Name] = $n.'#text' }
      $sec = [math]::Round([int]$d['BootTime'] / 1000, 1)
      if ($sec -gt 90) { FLAG 'KHOI_DONG_CHAM' ("Lan khoi dong gan nhat mat {0} giay - qua cham (binh thuong 15-40s tren SSD)." -f $sec) }
    } catch {}
  }

  SH 'CHI TIET: thu pham lam cham khoi dong / tat may (40 muc gan nhat)'
  foreach ($e in ($dp | Where-Object { $_.Id -in 101,102,103,106,109,110,200,201,202,203,301,302 } | Select-Object -First 40)) {
    W ("  [{0:yyyy-MM-dd HH:mm}] ID {1} - {2}" -f $e.TimeCreated, $e.Id, (Trunc $e.Message 320))
  }
  $slow = @($dp | Where-Object { $_.Id -in 101,102,103,109,110 })
  if ($slow.Count -gt 0) {
    $topSlow = $slow | Group-Object { (Trunc $_.Message 60) } | Sort-Object Count -Descending | Select-Object -First 3
    foreach ($t in $topSlow) { FLAG 'LAM_CHAM_KHOI_DONG' ("Lam cham khoi dong ({0} lan): {1}" -f $t.Count, (Trunc $t.Name 180)) }
  }
}

# =============================== 18. NHAT KY SYSTEM ===========================
Sec 'Nhat ky SYSTEM - loi va canh bao nghiem trong (14 ngay)' {
  SH 'DOI CHIEU voi danh sach loi gay cham/treo da biet (theo nguon + ma, ca muc Warning)'
  $hits = @(Find-WatchHits)
  foreach ($h in $hits) {
    W ('  >> {0} ID {1} x{2} lan (gan nhat {3:yyyy-MM-dd HH:mm}) - {4}' -f $h.Provider, $h.Id, $h.Count, $h.Last, $h.Text)
    FLAG $h.M -Muc $h.Muc -Tiep $h.Tiep ("Su kien {0} ID {1} xuat hien {2} lan trong 14 ngay: {3}" -f $h.Provider, $h.Id, $h.Count, $h.Text)
  }
  if (-not $hits.Count) { W '  (khong trung loi da biet nao - tot)' }
  $ev = Ev 'System' @(1, 2) $since14 2000
  if (-not $ev) { W ''; W '  (khong co su kien Error/Critical nao hoac khong doc duoc log)'; return }
  KV 'Tong so Error/Critical' $ev.Count
  SH 'Nhom theo nguon + EventID (25 nhom nhieu nhat)'
  $g = $ev | Group-Object { "$($_.ProviderName)|$($_.Id)" } | Sort-Object Count -Descending | Select-Object -First 25
  foreach ($x in $g) {
    $f = $x.Group[0]
    W ('  {0,5} lan | {1,-42} | ID {2,-6} | gan nhat {3:yyyy-MM-dd HH:mm}' -f $x.Count, (Trunc $f.ProviderName 42), $f.Id, $f.TimeCreated)
    W ('          -> ' + (Trunc $f.Message 300))
  }
  SH '15 su kien Error/Critical moi nhat'
  foreach ($e in ($ev | Select-Object -First 15)) {
    W ('  [{0:yyyy-MM-dd HH:mm}] {1,-34} ID {2,-6}' -f $e.TimeCreated, (Trunc $e.ProviderName 34), $e.Id)
    W ('      ' + (Trunc $e.Message 280))
  }
}

# =============================== 19. NHAT KY APPLICATION ======================
Sec 'Nhat ky APPLICATION - ung dung crash / treo (14 ngay)' {
  $ev = Ev 'Application' @(1, 2) $since14 2000
  if (-not $ev) { W '  (khong co loi nao)'; return }
  KV 'Tong so Error/Critical' $ev.Count
  SH 'Nhom theo nguon + EventID (20 nhom)'
  foreach ($x in ($ev | Group-Object { "$($_.ProviderName)|$($_.Id)" } | Sort-Object Count -Descending | Select-Object -First 20)) {
    $f = $x.Group[0]
    W ('  {0,5} lan | {1,-42} | ID {2,-6} | gan nhat {3:yyyy-MM-dd HH:mm}' -f $x.Count, (Trunc $f.ProviderName 42), $f.Id, $f.TimeCreated)
    W ('          -> ' + (Trunc $f.Message 260))
  }
  SH 'Ung dung bi treo / crash nhieu nhat'
  $crash = @($ev | Where-Object { $_.Id -in 1000, 1002 })
  if ($crash.Count -gt 0) {
    foreach ($c in ($crash | Group-Object { ($_.Properties[0].Value) } | Sort-Object Count -Descending | Select-Object -First 10)) {
      W ('  {0,5} lan - {1}' -f $c.Count, $c.Name)
    }
  } else { W '  (khong co)' }
  $rex = Ev 'Microsoft-Windows-Resource-Exhaustion-Detector/Operational' $null $since30 50
  if ($rex) {
    SH 'Canh bao HET BO NHO (Resource Exhaustion)'
    foreach ($e in ($rex | Select-Object -First 8)) { W (('  [{0:yyyy-MM-dd HH:mm}] ' -f $e.TimeCreated) + (Trunc $e.Message 320)) }
    FLAG 'HET_BO_NHO' ("Windows da ghi nhan {0} lan HET BO NHO trong 30 ngay - can them RAM hoac dong bot ung dung." -f $rex.Count)
  }
}

# =============================== 20. KHOI DONG / TAT MAY ======================
Sec 'Lich su bat / tat / man hinh xanh' {
  $ev = Ev 'System' $null $since30 3000 @(6005, 6006, 6008, 1074, 41, 1001)
  if (-not $ev) { W '  (khong doc duoc)'; return }
  foreach ($e in ($ev | Select-Object -First 40)) {
    $what = switch ([int]$e.Id) {
      6005 {'BAT MAY (khoi dong Event Log)'} 6006 {'Tat may binh thuong'}
      6008 {'!! Lan truoc TAT DOT NGOT'} 1074 {'Tat/khoi dong lai theo yeu cau'}
      41 {'!! Kernel-Power: mat dien/treo cung'} 1001 {'BugCheck / bao cao loi'} default {"ID $($e.Id)"} }
    W ('  [{0:yyyy-MM-dd HH:mm:ss}] {1,-36} {2}' -f $e.TimeCreated, $what, (Trunc $e.Message 150))
  }
  SH 'File dump man hinh xanh'
  $dmp = "$env:SystemRoot\MEMORY.DMP"
  if (Test-Path -LiteralPath $dmp) { $fi = Get-Item -LiteralPath $dmp -Force; W ("  MEMORY.DMP: {0}, sua doi {1:yyyy-MM-dd HH:mm}" -f (FmtMB $fi.Length), $fi.LastWriteTime) }
  $mini = @(Get-ChildItem -LiteralPath "$env:SystemRoot\Minidump" -Filter *.dmp -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
  KV 'So file minidump' $mini.Count
  foreach ($m in ($mini | Select-Object -First 10)) { W ('    {0:yyyy-MM-dd HH:mm}  {1}  ({2})' -f $m.LastWriteTime, $m.Name, (FmtMB $m.Length)) }
  if ($mini.Count -gt 0) { FLAG 'MAN_HINH_XANH' -Tiep 'checkwinfix/phan-cung' ("Co {0} file minidump (man hinh xanh). Gan nhat: {1:yyyy-MM-dd}. Phan cung hoac driver dang loi." -f $mini.Count, $mini[0].LastWriteTime) }
}

# =============================== 21. TIMELINE =================================
Sec 'DONG THOI GIAN thay doi tren may (90 ngay) - de doi chieu voi ngay may bat dau cham' {
  $tl = New-Object System.Collections.ArrayList
  foreach ($h in (Get-HotFix -ErrorAction SilentlyContinue)) {
    $d = $null
    try { $d = [datetime]$h.InstalledOn } catch {}
    if ($d -and $d -gt $since90) { [void]$tl.Add([pscustomobject]@{ Ngay = $d; Loai = 'Update'; NoiDung = ("{0} - {1}" -f $h.HotFixID, $h.Description) }) }
  }
  $wu = Ev 'Microsoft-Windows-WindowsUpdateClient/Operational' $null $since90 300 @(19, 20)
  foreach ($e in $wu) {
    $t = 'WinUpdate OK'
    if ($e.Id -eq 20) { $t = 'WinUpdate LOI' }
    [void]$tl.Add([pscustomobject]@{ Ngay = $e.TimeCreated; Loai = $t; NoiDung = (Trunc $e.Message 130) })
  }
  foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                      'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
    foreach ($k in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
      $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
      if (-not $p.DisplayName) { continue }
      $d = $null
      if ($p.InstallDate -and "$($p.InstallDate)" -match '^\d{8}$') { try { $d = [datetime]::ParseExact("$($p.InstallDate)", 'yyyyMMdd', $null) } catch {} }
      if ($d -and $d -gt $since90) { [void]$tl.Add([pscustomobject]@{ Ngay = $d; Loai = 'Cai phan mem'; NoiDung = ("{0} {1} [{2}]" -f $p.DisplayName, $p.DisplayVersion, $p.Publisher) }) }
    }
  }
  try {
    foreach ($rp in (Get-ComputerRestorePoint -ErrorAction Stop)) {
      $d = $null
      try { $d = $rp.ConvertToDateTime($rp.CreationTime) } catch {}
      if ($d -and $d -gt $since90) { [void]$tl.Add([pscustomobject]@{ Ngay = $d; Loai = 'Restore point'; NoiDung = $rp.Description }) }
    }
  } catch {}
  $setup = Ev 'Setup' $null $since90 200
  foreach ($e in $setup) {
    if ($e.Message -match '(?i)update|upgrade|package') { [void]$tl.Add([pscustomobject]@{ Ngay = $e.TimeCreated; Loai = 'Setup'; NoiDung = (Trunc $e.Message 120) }) }
  }
  if ($tl.Count -eq 0) { W '  (khong tim thay thay doi nao)'; return }
  W ('  {0,-17} {1,-16} {2}' -f 'Ngay gio', 'Loai', 'Noi dung')
  foreach ($r in ($tl | Sort-Object Ngay -Descending | Select-Object -First 90)) {
    W ('  {0:yyyy-MM-dd HH:mm}  {1,-16} {2}' -f $r.Ngay, $r.Loai, (Trunc $r.NoiDung 110))
  }
}

# =============================== 22. PHAN MEM DA CAI ==========================
Sec 'Phan mem da cai dat va tien ich mo rong trinh duyet' {
  $apps = New-Object System.Collections.ArrayList
  foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                      'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
    foreach ($k in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
      $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
      if ($p.DisplayName -and -not $p.SystemComponent) {
        [void]$apps.Add([pscustomobject]@{ Ten = $p.DisplayName; Ver = $p.DisplayVersion; NhaSX = $p.Publisher; Ngay = $p.InstallDate })
      }
    }
  }
  KV 'Tong so phan mem' $apps.Count
  SH 'Danh sach (sap xep theo ngay cai moi nhat)'
  W ('  {0,-10} {1,-52} {2,-18} {3}' -f 'Ngay cai', 'Ten', 'Phien ban', 'Nha san xuat')
  foreach ($a in ($apps | Sort-Object Ngay -Descending | Select-Object -First 70)) {
    W ('  {0,-10} {1,-52} {2,-18} {3}' -f $a.Ngay, (Trunc $a.Ten 52), (Trunc "$($a.Ver)" 18), (Trunc "$($a.NhaSX)" 34))
  }
  $risky = @($apps | Where-Object { $_.Ten -match '(?i)driver *booster|advanced *systemcare|iobit|pc *(cleaner|optimizer|accelerat)|speedup|onesafe|reimage|wondershare|baidu|360 *(total|safe)|hao123|toolbar|ask *toolbar|mysearch|webdiscover|opencandy|uniblue|smart *defrag' })
  foreach ($r in $risky) { FLAG 'PHAN_MEM_DON_DEP' ("Phan mem 'don dep/toi uu' hoac adware da cai: '{0}' - nhom nay thuong TU LAM CHAM may (chay nen, quang cao, doi thiet lap)." -f $r.Ten) }

  SH 'Tien ich mo rong trinh duyet'
  $brs = @{
    'Chrome'  = "$env:LOCALAPPDATA\Google\Chrome\User Data"
    'Edge'    = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    'CocCoc'  = "$env:LOCALAPPDATA\CocCoc\Browser\User Data"
    'Brave'   = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
  }
  foreach ($b in $brs.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $b.Value)) { continue }
    W ("  [{0}]" -f $b.Key)
    $n = 0
    foreach ($prof in (Get-ChildItem -LiteralPath $b.Value -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile*' })) {
      $extRoot = Join-Path $prof.FullName 'Extensions'
      if (-not (Test-Path -LiteralPath $extRoot)) { continue }
      foreach ($ext in (Get-ChildItem -LiteralPath $extRoot -Directory -ErrorAction SilentlyContinue)) {
        $nm = ''
        $mf = Get-ChildItem -LiteralPath $ext.FullName -Recurse -Filter 'manifest.json' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($mf) { try { $nm = (Get-Content -LiteralPath $mf.FullName -Raw -ErrorAction Stop | ConvertFrom-Json).name } catch {} }
        W ('    {0,-36} {1,-34} {2}' -f $ext.Name, (Trunc "$nm" 34), $prof.Name)
        $n++
      }
    }
    if ($n -eq 0) { W '    (khong co / khong doc duoc)' }
    if ($n -gt 12) { FLAG 'NHIEU_TIEN_ICH_TRINH_DUYET' ("Trinh duyet {0} co {1} tien ich mo rong - qua nhieu, an RAM va lam trinh duyet cham." -f $b.Key, $n) }
  }
}

# =============================== 23. TOAN VEN HE THONG ========================
Sec 'Toan ven he thong, cho khoi dong lai, che do bao tri' {
  SH 'Co dang cho khoi dong lai khong'
  $pr = @()
  if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $pr += 'CBS RebootPending' }
  if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $pr += 'WindowsUpdate RebootRequired' }
  if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending') { $pr += 'CBS PackagesPending' }
  $pfro = Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations'
  if ($pfro) { $pr += ('PendingFileRenameOperations (' + (@($pfro)).Count + ' muc)') }
  if (Test-Path "$env:SystemRoot\WinSxS\pending.xml") { $pr += 'WinSxS\pending.xml TON TAI' }
  if ($pr.Count -gt 0) {
    foreach ($x in $pr) { W ('  - ' + $x) }
    FLAG 'CHO_KHOI_DONG_LAI' ('May DANG CHO KHOI DONG LAI de hoan tat cap nhat (' + ($pr -join ', ') + '). Trong luc nay Windows chay nen lien tuc va rat cham.')
  } else { W '  (khong - tot)' }

  SH 'Trang thai Windows Update'
  KV 'Dich vu wuauserv' ((Cim Win32_Service -Filter "Name='wuauserv'").State)
  KV 'Lan cuoi tim update' (Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Detect' 'LastSuccessTime')
  KV 'Lan cuoi cai update' (Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install' 'LastSuccessTime')
  KV 'Bi tam dung den'     (Reg 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'PauseUpdatesExpiryTime')

  SH 'Cau hinh System Restore'
  try { WL (Get-ComputerRestorePoint -ErrorAction Stop | Select-Object -First 8 @{n='Ngay';e={$_.ConvertToDateTime($_.CreationTime)}}, Description, SequenceNumber | Format-Table -AutoSize) } catch { W '  (System Restore dang tat hoac khong doc duoc)' }

  SH 'Nhat ky CBS gan nhat (dau hieu file he thong hong)'
  $cbs = "$env:SystemRoot\Logs\CBS\CBS.log"
  if (Test-Path -LiteralPath $cbs) {
    $bad = @(Get-Content -LiteralPath $cbs -Tail 4000 -ErrorAction SilentlyContinue | Where-Object { $_ -match '(?i)cannot repair|corrupt|CSI.*Failed|Hashes for file member .* do not match' } | Select-Object -Last 12)
    if ($bad.Count -gt 0) {
      foreach ($l in $bad) { W ('  ' + (Trunc $l 180)) }
      FLAG 'FILE_HE_THONG_HONG' -Muc 'loi' -Tiep 'fix-win/dism-sfc' 'Nhat ky CBS co dau hieu FILE HE THONG BI HONG - can chay DISM /RestoreHealth roi sfc /scannow.'
    } else { W '  (khong thay dau hieu hong trong 4000 dong cuoi)' }
  } else { W '  (khong co CBS.log)' }

  SH 'Che do hieu ung giao dien'
  KV 'VisualFXSetting' (Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting')
  KV 'Transparency'    (Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency')
  KV 'Animations'      (Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate')
}

# =============================== HAM DOC: SECURE BOOT, BAN QUYEN, WINRE, NGU, RAM ===
# Tach rieng de bai thu thay bang du lieu gia. Tat ca chi doc.
$CA2011_HET_HAN = [datetime]'2026-10-19'   # Microsoft Windows Production PCA 2011 (ky trinh khoi dong Windows) het han

function Get-KieuFirmware {
  # 'UEFI' | 'BIOS' | '' (khong ro). GetFirmwareType khong can quyen Admin.
  try {
    if (-not ('CWF.Fw' -as [type])) { Add-Type -Namespace CWF -Name Fw -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool GetFirmwareType(out int t);' -ErrorAction Stop }
    $t = 0
    if ([CWF.Fw]::GetFirmwareType([ref]$t)) { switch ($t) { 1 { return 'BIOS' } 2 { return 'UEFI' } } }
  } catch {}
  return ''
}

function Get-SecureBootTrangThai {
  # Registry Servicing: UEFICA2023Status NotStarted | InProgress | Updated; WindowsUEFICA2023Capable 0 | 1 | 2; UEFICA2023Error.
  # Su kien TPM-WMI: 1801 chua cap nhat chung chi, 1808 da cap nhat, 1795/1796 firmware loi khi ghi.
  $sb = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot'
  $o = [ordered]@{ Firmware = (Get-KieuFirmware); Bat = $null; Status = ''; Capable = $null; Loi = $null; SuKien = @() }
  $v = Reg "$sb\State" 'UEFISecureBootEnabled'
  if ($null -ne $v) { $o.Bat = ([int]$v -eq 1) }
  $o.Status = [string](Reg "$sb\Servicing" 'UEFICA2023Status')
  $c = Reg "$sb\Servicing" 'WindowsUEFICA2023Capable'; if ($null -ne $c) { $o.Capable = [int]$c }
  $e = Reg "$sb\Servicing" 'UEFICA2023Error'; if ($null -ne $e) { $o.Loi = ([int64]$e) -band [int64]4294967295 }   # DWORD doc ra Int32 co the am
  $o.SuKien = @(Ev 'System' $null $since90 200 @(1795, 1796, 1801, 1808) | Where-Object { $_.ProviderName -eq 'Microsoft-Windows-TPM-WMI' } | Sort-Object TimeCreated -Descending)
  [pscustomobject]$o
}

function Get-BanQuyenWindows {
  # Chi lay cac truong can thiet: KHONG doc khoa san pham (ke ca 5 ky tu cuoi, khoa OEM trong BIOS). $null = khong doc duoc.
  $q = "SELECT Name, Description, LicenseStatus, ProductKeyChannel, KeyManagementServiceMachine, KeyManagementServicePort, DiscoveredKeyManagementServiceMachineName, GracePeriodRemaining FROM SoftwareLicensingProduct WHERE ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL"
  try { return , @(Get-CimInstance -Query $q -ErrorAction Stop) } catch {}
  try { return , @(Get-WmiObject -Query $q -ErrorAction Stop) } catch {}
  return $null
}

function Test-KmsLau {
  # May chu KMS gia lap tren chinh may (KMS_VL_ALL, KMSAuto...) hoac may chu KMS cong cong cua cong cu crack.
  param([string]$KmsHost)
  if ([string]::IsNullOrWhiteSpace($KmsHost)) { return $false }
  return ($KmsHost -match '(?i)^(localhost|127\.\d+\.\d+\.\d+|0\.0\.0\.0|::1|\[::1\])(:\d+)?$' -or
          $KmsHost -match '(?i)(^|\.)(kms[0-9]*\.(msguides|digiboy|03k|loli|lotro|chinancce|cangshui|library|ghpym|luody|cgtsoft|itsk|mrxn)\.[a-z.]+|kms\.srv\.crsoo\.com|[sz][0-9a-z]*\.(us|uk)\.to)$')
}

function Get-DauVetCrack {
  # Dau vet cong cu kich hoat lau (KMSpico, KMSAuto, AAct, KMS_VL_ALL, MAS Online KMS): tep, thu muc, tac vu lich, dich vu, IFEO.
  $hits = New-Object System.Collections.ArrayList
  foreach ($p in @("$env:SystemRoot\KMSAutoS", "$env:ProgramData\KMSAutoS", "$env:ProgramData\KMSAuto", "$env:SystemRoot\AAct_Tools",
                   "$env:ProgramData\AAct_Tools", "$env:ProgramFiles\KMSpico", "${env:ProgramFiles(x86)}\KMSpico", "$env:SystemRoot\SECOH-QAD.exe",
                   "$env:SystemRoot\SECOH-QAD.dll", "$env:SystemRoot\System32\SppExtComObjHook.dll", "$env:SystemRoot\System32\SppExtComObjPatcher.exe",
                   "$env:ProgramData\KMS_VL_ALL", "$env:ProgramFiles\KMSAuto Net")) {
    if ($p -and $p -notmatch '^\\' -and (Test-Path -LiteralPath $p)) { [void]$hits.Add("Tep/thu muc: $p") }
  }
  try {
    foreach ($t in @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskName -match '(?i)^(AutoKMS|AutoPico|KMSAuto|KMS_?VL|Activation-Renewal|Activation-Run_Once|AAct)' })) {
      [void]$hits.Add("Tac vu lich: $($t.TaskPath)$($t.TaskName)")
    }
  } catch {}
  foreach ($s in @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)^(KMSELDI|Service_KMS|KMSAutoS|KMSpico|AAct)' })) { [void]$hits.Add("Dich vu: $($s.Name)") }
  $ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
  foreach ($exe in 'SppExtComObj.exe', 'sppsvc.exe', 'osppsvc.exe') {
    foreach ($n in 'VerifierDlls', 'Debugger') { $val = Reg "$ifeo\$exe" $n; if ($val) { [void]$hits.Add("IFEO: $exe $n = $val") } }
  }
  return , @($hits)
}

function Get-WinRE {
  # ReAgent.xml: doc duoc bang quyen thuong, khong phu thuoc ngon ngu. Co quyen Admin thi kem reagentc /info (chi hien thong tin).
  $o = [ordered]@{ TrangThai = ''; ViTri = ''; ChiTiet = '' }
  try {
    [xml]$doc = Get-Content -LiteralPath "$env:SystemRoot\System32\Recovery\ReAgent.xml" -Raw -ErrorAction Stop
    $o.TrangThai = switch ([string]$doc.WindowsRE.InstallState.state) { '1' { 'Bat' } '0' { 'Tat' } default { '' } }
    $o.ViTri = [string]$doc.WindowsRE.WinreLocation.path
  } catch {}
  if ($isAdmin) { $o.ChiTiet = ((reagentc /info 2>&1) -join "`n").Trim() }
  [pscustomobject]$o
}

function Get-YeuCauNguon {
  # powercfg /requests: can quyen Admin. '' neu khong chay duoc.
  if (-not $isAdmin) { return '' }
  return ((powercfg /requests 2>&1) -join "`n")
}

function ConvertFrom-YeuCauNguon {
  # Tach ket qua powercfg /requests theo nhom (DISPLAY, SYSTEM, AWAYMODE, EXECUTION, PERFBOOST, ACTIVELOCKSCREEN).
  # Tieu de nhom va dong [PROCESS]/[DRIVER]/[SERVICE] khong doi theo ngon ngu; dong ly do nam ngay sau.
  param([string]$Text)
  $out = New-Object System.Collections.ArrayList
  $grp = ''; $last = $null
  foreach ($l in ($Text -split "`r?`n")) {
    $t = $l.Trim()
    if ($t -match '^([A-Z]+):$') { $grp = $Matches[1]; $last = $null; continue }
    if (-not $grp -or -not $t) { continue }
    if ($t -match '^\[(\w+)\]\s*(.*)$') {
      $loai = $Matches[1]; $src = $Matches[2]
      if ($loai -eq 'PROCESS' -and $src -match '\\([^\\]+)$') { $src = $Matches[1] }
      $last = [pscustomobject]@{ Nhom = $grp; Loai = $loai; Nguon = $src; LyDo = '' }
      [void]$out.Add($last)
    } elseif ($last -and -not $last.LyDo) { $last.LyDo = $t }
  }
  return , @($out)
}

function Get-SleepStudy {
  # Bao cao giac ngu 7 ngay (chi may Modern Standby, can quyen Admin). Tra duong dan file html hoac ''.
  param([string]$Path)
  if (-not $isAdmin) { return '' }
  $null = powercfg /sleepstudy /output $Path /duration 7 2>&1
  if (Test-Path -LiteralPath $Path) { return $Path }
  return ''
}

function Get-KetQuaTestRam {
  # MemoryDiagnostics-Results: 1101/1201 khong co loi, 1102/1202 co loi phan cung. Moi nhat dung dau.
  try { return , @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } -MaxEvents 20 -ErrorAction Stop | Where-Object { @(1101, 1102, 1201, 1202) -contains $_.Id }) } catch { return , @() }
}

$script:TepThem = New-Object System.Collections.ArrayList   # file phu (sleepstudy...) ghi vao JSON

# =============================== 24. SECURE BOOT, BAN QUYEN, WINRE =============
Sec 'Secure Boot (chung chi 2023), ban quyen Windows, moi truong phuc hoi WinRE' {
  SH 'Secure Boot va chung chi Windows UEFI CA 2023'
  $s = Get-SecureBootTrangThai
  KV 'Kieu firmware'      $(if ($s.Firmware) { $s.Firmware } else { 'khong ro' })
  KV 'Secure Boot'        $(if ($s.Bat -eq $true) { 'BAT' } elseif ($s.Bat -eq $false) { 'TAT' } else { 'khong ro' })
  KV 'UEFICA2023Status'   $(if ($s.Status) { $s.Status } else { '(chua co)' })
  KV 'WindowsUEFICA2023Capable' $s.Capable
  if ($s.Loi) { KV 'UEFICA2023Error' ('0x{0:X}' -f $s.Loi) }
  $ev = @($s.SuKien)
  foreach ($e in ($ev | Select-Object -First 6)) { W ('  [{0:yyyy-MM-dd HH:mm}] TPM-WMI {1}  {2}' -f $e.TimeCreated, $e.Id, (Trunc $e.Message 150)) }
  if ($s.Firmware -eq 'BIOS') {
    FLAG 'KHOI_DONG_KIEU_BIOS' -Muc 'thong-tin' 'May khoi dong kieu BIOS cu (Legacy/CSM), khong co Secure Boot - Windows 11 can UEFI va Secure Boot; may cung khong nhan duoc cac ban va bao mat khoi dong.'
  } elseif ($s.Bat -eq $false) {
    FLAG 'SECURE_BOOT_TAT' -Muc 'thong-tin' 'Secure Boot dang TAT - may khong duoc bao ve truoc ma doc nap luc khoi dong (bootkit); Windows 11 can Secure Boot. Bat lai trong BIOS/UEFI neu khong co ly do tat.'
  } elseif ($s.Bat -eq $true) {
    $moi = @($ev | Where-Object { $_.Id -in 1801, 1808 } | Select-Object -First 1)
    $xong = ($s.Status -eq 'Updated') -or ($moi.Count -and $moi[0].Id -eq 1808)
    if ($xong) { W '  => Da co chung chi Secure Boot 2023 (tot).' }
    else {
      $con = [int][Math]::Floor(($CA2011_HET_HAN - (Get-Date).Date).TotalDays)
      $han = $(if ($con -gt 0) { "con $con ngay" } else { 'DA HET HAN' })
      $ma = $(if ($s.Loi) { ', ma loi 0x{0:X}' -f $s.Loi } else { '' })
      FLAG 'SECURE_BOOT_CHUA_CO_CA_2023' ("Secure Boot chua cap nhat chung chi 2023 (UEFICA2023Status = {0}{1}). Chung chi Microsoft Windows Production PCA 2011 ky trinh khoi dong Windows het han 19/10/2026 ({2}): may van khoi dong duoc nhung khong nhan duoc ban va bao mat cho trinh khoi dong nua. Cai het Windows Update, cap nhat BIOS/UEFI tu trang hang may roi khoi dong lai 2 lan." -f $(if ($s.Status) { $s.Status } else { 'chua bat dau' }), $ma, $han)
      $fw = @($ev | Where-Object { $_.Id -in 1795, 1796 })
      if ($fw.Count) { FLAG 'SECURE_BOOT_FIRMWARE_LOI' ("Firmware (BIOS/UEFI) bao loi khi Windows ghi chung chi Secure Boot moi ({0} lan su kien TPM-WMI 1795/1796 trong 90 ngay) - can cap nhat BIOS/UEFI tu trang hang may." -f $fw.Count) }
    }
  } else { W '  (khong doc duoc trang thai Secure Boot)' }

  SH 'Ban quyen Windows (khong in khoa san pham)'
  $lic = Get-BanQuyenWindows
  if ($null -eq $lic) { W '  (khong doc duoc thong tin ban quyen)' }
  elseif (@($lic).Count -eq 0) { FLAG 'WINDOWS_CHUA_KICH_HOAT' 'Khong thay khoa ban quyen Windows nao duoc cai - Windows chua kich hoat (hinh nen bi khoa, nhac kich hoat).' }
  foreach ($p in @($lic | Where-Object { $null -ne $_ })) {   # @($null) co 1 phan tu: bo khi khong doc duoc
    $st = switch ([int]$p.LicenseStatus) { 0 {'Chua cap phep'} 1 {'Da kich hoat'} 2 {'An han OOB'} 3 {'An han (doi phan cung)'} 4 {'An han (khong chinh hang)'} 5 {'Thong bao (chua kich hoat)'} 6 {'An han gia han'} default {"Ma $($p.LicenseStatus)"} }
    $kms = $(if ($p.KeyManagementServiceMachine) { $p.KeyManagementServiceMachine } else { $p.DiscoveredKeyManagementServiceMachineName })
    KV 'San pham'       $p.Name
    KV '  Kenh khoa'    $(if ($p.ProductKeyChannel) { $p.ProductKeyChannel } else { $p.Description })
    KV '  Trang thai'   $st
    if ($kms) { KV '  May chu KMS' $kms }
    if ([int]$p.GracePeriodRemaining -gt 0) { KV '  Con han (ngay)' ([Math]::Round([double]$p.GracePeriodRemaining / 1440, 1)) }
    if ([int]$p.LicenseStatus -ne 1) { FLAG 'WINDOWS_CHUA_KICH_HOAT' ("Windows chua kich hoat (trang thai: {0}) - mua khoa hoac dang nhap tai khoan Microsoft co ban quyen so; dung dung cong cu crack." -f $st) }
    $kenh = "$($p.ProductKeyChannel) $($p.Description)"
    if ($kenh -match '(?i)GVLK|VOLUME_KMSCLIENT') {
      if (Test-KmsLau $kms) { FLAG 'WINDOWS_KICH_HOAT_KMS_LAU' ("Windows kich hoat bang may chu KMS lau '{0}' - ban quyen gia, tu het han moi 180 ngay; cong cu kich hoat lau hay kem ma doc." -f $kms) }
      elseif (-not $cs.PartOfDomain) { FLAG 'WINDOWS_KMS_NGOAI_DOMAIN' -Muc 'thong-tin' 'Windows dung khoa KMS (ban cho doanh nghiep) nhung may khong vao domain - neu khong phai may cong ty thi day thuong la kich hoat lau.' }
    }
  }
  $crack = Get-DauVetCrack   # ham tra mang bang "return , @()": khong boc them @()
  if ($crack.Count) {
    foreach ($c in $crack) { W ('  ! ' + $c) }
    FLAG 'DAU_VET_CRACK_KICH_HOAT' ("Co {0} dau vet cong cu kich hoat lau ({1}) - nhom cong cu nay hay kem ma doc, chay nen va them ngoai le cho Defender." -f $crack.Count, (Trunc (($crack | Select-Object -First 3) -join '; ') 200))
  } else { W '  (khong thay dau vet cong cu kich hoat lau)' }

  SH 'Moi truong phuc hoi Windows (WinRE)'
  $re = Get-WinRE
  KV 'Trang thai WinRE' $(if ($re.TrangThai) { $re.TrangThai } else { 'khong doc duoc' })
  if ($re.ViTri) { KV 'Vi tri' $re.ViTri }
  if ($re.ChiTiet) { WL $re.ChiTiet }
  if ($re.TrangThai -eq 'Tat') { FLAG 'WINRE_TAT' 'Moi truong phuc hoi Windows (WinRE) dang TAT - khi may khong vao duoc Windows se khong dung duoc Startup Repair, Reset this PC, go ban cap nhat; ban cap nhat WinRE cung bao loi 0x80070643. Bat lai bang lenh reagentc /enable (quyen Admin).' }
}

# =============================== 25. GIU MAY THUC, NGU, TEST RAM ==============
Sec 'Chuong trinh giu may thuc, giac ngu, ket qua test RAM' {
  SH 'Yeu cau giu may thuc / giu man hinh (powercfg /requests)'
  $txt = Get-YeuCauNguon
  if (-not $txt) { W '  (can quyen Administrator)' }
  else {
    $rq = ConvertFrom-YeuCauNguon $txt
    if (-not $rq.Count) { W '  (khong co chuong trinh nao giu may - tot)' }
    foreach ($r in $rq) { W ('  {0,-17} [{1}] {2}{3}' -f $r.Nhom, $r.Loai, $r.Nguon, $(if ($r.LyDo) { '  - ' + $r.LyDo } else { '' })) }
    $giu = @($rq | Where-Object { $_.Nhom -in 'DISPLAY', 'SYSTEM', 'AWAYMODE' })
    if ($giu.Count) {
      $ds = (@($giu | ForEach-Object { '{0} ({1})' -f $_.Nguon, $_.Nhom } | Select-Object -Unique) -join ', ')
      FLAG 'CO_CHUONG_TRINH_GIU_MAY_THUC' -Muc 'thong-tin' ("Co {0} yeu cau dang giu may khong ngu / khong tat man hinh: {1}. Neu may khong tu ngu hoac hao pin, dong cac chuong trinh nay." -f $giu.Count, (Trunc $ds 220))
    }
  }
  SH 'Lan danh thuc gan nhat (powercfg /lastwake)'
  WL ((powercfg /lastwake 2>&1) -join "`n")
  SH 'Bao cao giac ngu 7 ngay (powercfg /sleepstudy, may Modern Standby)'
  $ss = Get-SleepStudy (Join-Path $OutDir ("SleepStudy_{0}_{1}.html" -f $env:COMPUTERNAME, $stamp))
  if ($ss) { KV 'Da luu' $ss; [void]$script:TepThem.Add([ordered]@{ nhan = 'Báo cáo giấc ngủ (sleepstudy)'; duongDan = $ss }) }
  else { W '  (khong tao duoc: can quyen Administrator hoac may khong dung Modern Standby)' }

  SH 'Ket qua test RAM (Windows Memory Diagnostic)'
  $md = Get-KetQuaTestRam
  if ($md.Count) {
    foreach ($e in ($md | Select-Object -First 4)) { W ('  [{0:yyyy-MM-dd HH:mm}] ID {1}  {2}' -f $e.TimeCreated, $e.Id, $(if (@(1102, 1202) -contains $e.Id) { 'CO LOI PHAN CUNG' } else { 'khong co loi' })) }
    if (@(1102, 1202) -contains $md[0].Id) { FLAG 'RAM_CO_LOI' -Muc 'loi' ("Lan test RAM gan nhat ({0:dd/MM/yyyy}) bao LOI PHAN CUNG - thay thanh RAM loi (thu tung thanh de tim thanh hong)." -f $md[0].TimeCreated) }
  } else {
    W '  (may chua tung chay Windows Memory Diagnostic)'
    if (@($script:FLAGS | Where-Object { $_.ma -in 'MAN_HINH_XANH', 'WHEA_NGHIEM_TRONG', 'WHEA_DUOC_SUA' }).Count) {
      FLAG 'CHUA_TEST_RAM' -Muc 'thong-tin' -Tiep 'fix-win/ram' 'Co man hinh xanh hoac loi WHEA ma may chua tung test RAM - nen chay Windows Memory Diagnostic (may se khoi dong lai de test).'
    }
  }
}

# =============================== KIEM TRA SAU (chi khi chon) ==================
# Thay cho sfc /verifyonly va chkdsk /scan cua "Bao cao suc khoe" cu: doc ket qua co cau truc (khong phu thuoc ngon ngu).
function Get-AnhWindows {
  # DISM /ScanHealth, chi doc, 5-15 phut. Tra Healthy | Repairable | NonRepairable, hoac 'LOI: ...'.
  try { return [string](Repair-WindowsImage -Online -ScanHealth -ErrorAction Stop).ImageHealthState } catch { return 'LOI: ' + $_.Exception.Message }
}
function Get-ODiaCanQuet {
  @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.FileSystemType -eq 'NTFS' -and $_.DriveLetter } |
    ForEach-Object { [string]$_.DriveLetter } | Sort-Object)
}
function Get-QuetODia {
  # Nhu chkdsk X: /scan: quet truc tuyen, khong sua. Tra NoErrorsFound | ErrorsFound | ..., hoac 'LOI: ...'.
  param([string]$Letter)
  try { return [string](Repair-Volume -DriveLetter $Letter -Scan -ErrorAction Stop) } catch { return 'LOI: ' + $_.Exception.Message }
}

if ($KiemTraSau) {
Sec 'Kiem tra sau: anh Windows (DISM) va loi he thong file (chkdsk /scan)' {
  if (-not $isAdmin) { W '  (bo qua: can quyen Administrator)'; return }
  SH 'Anh Windows (Repair-WindowsImage -Online -ScanHealth, chi doc)'
  Write-Host '        Dang kiem tra anh Windows (DISM), thuong 5-15 phut...' -ForegroundColor DarkGray
  $st = Get-AnhWindows
  KV 'Trang thai' $st
  switch -Regex ($st) {
    '^Healthy$' { W '  (anh Windows khong hong - tot)' }
    '^Repairable$' { FLAG 'ANH_WINDOWS_HONG' -Muc 'loi' -Tiep 'fix-win/dism-sfc' 'Anh Windows (kho thanh phan) bi hong nhung sua duoc - chay DISM RestoreHealth roi sfc /scannow.' }
    '^NonRepairable$' { FLAG 'ANH_WINDOWS_HONG_NANG' -Muc 'loi' 'Anh Windows hong nang, DISM khong sua duoc - nen cai lai Windows giu du lieu (Repair install bang ISO cung phien ban).' }
    '^LOI: ' { W '  (khong kiem tra duoc anh Windows)' }
  }
  SH 'Loi he thong file tung o (Repair-Volume -Scan, nhu chkdsk /scan, khong sua)'
  $vols = @(Get-ODiaCanQuet)
  if (-not $vols.Count) { W '  (khong thay o NTFS co ky tu)' }
  foreach ($d in $vols) {
    Write-Host ("        Dang quet o {0}:..." -f $d) -ForegroundColor DarkGray
    $r = Get-QuetODia $d
    KV ("O {0}:" -f $d) $r
    if ($r -eq 'NoErrorsFound' -or $r -like 'LOI: *') { continue }
    FLAG 'O_DIA_LOI_HE_THONG_FILE' -Muc 'loi' -Tiep 'fix-win/o-dia-sua' ("O {0}: co loi he thong file ({1}) - chay chkdsk {0}: /f de sua (o Windows thi hen khi khoi dong lai)." -f $d, $r)
  }
}
}

# =============================== 26. NHIET DO =================================
Sec 'Nhiet do va tong ket' {
  SH 'Cam bien nhiet (ACPI - nhieu may khong ho tro)'
  $tz = @(Cim MSAcpi_ThermalZoneTemperature 'root\wmi')
  if ($tz.Count -gt 0) {
    foreach ($t in $tz) {
      $c = [math]::Round(([double]$t.CurrentTemperature / 10) - 273.15, 1)
      W ('  {0,-46} {1} C' -f $t.InstanceName, $c)
      if ($c -ge 85) { FLAG 'QUA_NONG' ("Nhiet do vung '{0}' = {1}C - QUA NONG. May se tu bop xung CPU. Can ve sinh quat/tan nhiet, thay keo tan nhiet." -f $t.InstanceName, $c) }
    }
  } else { W '  (may khong bao cao nhiet do qua WMI - can dung HWiNFO64 / HWMonitor de do)' }

  SH 'Quat'
  WL (Cim Win32_Fan | Select-Object Name, DesiredSpeed, Status | Format-Table -AutoSize)

  SH 'Thoi gian chay script'
  KV 'Bat dau'  ('{0:yyyy-MM-dd HH:mm:ss}' -f $T0)
  KV 'Ket thuc' ('{0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date))
  KV 'Mat'      ('{0:N1} giay' -f ((Get-Date) - $T0).TotalSeconds)
}

# =============================== XUAT BAO CAO =================================
Write-Host ''
Write-Host '  Dang ghi bao cao...' -ForegroundColor Cyan

$head = New-Object System.Text.StringBuilder
[void]$head.AppendLine('#' * 90)
[void]$head.AppendLine('#  CHECKWINFIX - BAO CAO CHAN DOAN MAY WINDOWS BI CHAM')
[void]$head.AppendLine('#  Phien ban script : ' + $SCRIPT_VER)
[void]$head.AppendLine('#  May              : ' + $env:COMPUTERNAME + '   (' + $cs.Manufacturer + ' ' + $cs.Model + ')')
[void]$head.AppendLine('#  He dieu hanh     : ' + $os.Caption + ' build ' + $os.BuildNumber)
[void]$head.AppendLine('#  Thoi diem        : ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$head.AppendLine('#  Quyen Admin      : ' + $isAdmin)
[void]$head.AppendLine('#' * 90)
[void]$head.AppendLine('')
[void]$head.AppendLine('NGUOI DUNG MO TA')
[void]$head.AppendLine('  Bat dau cham tu : ' + $(if ([string]::IsNullOrWhiteSpace($ansWhen)) { '(khong tra loi)' } else { $ansWhen }))
[void]$head.AppendLine('  Trieu chung     : ' + $(if ([string]::IsNullOrWhiteSpace($ansWhat)) { '(khong tra loi)' } else { $ansWhat }))
[void]$head.AppendLine('')
[void]$head.AppendLine('=' * 90)
[void]$head.AppendLine('  CANH BAO TU DONG - DOC MUC NAY TRUOC')
[void]$head.AppendLine('=' * 90)
# Nghiem trong (loi) truoc, roi canh bao, thong tin; giu thu tu phat hien trong tung muc.
$sorted = @(foreach ($lv in 'loi', 'canh-bao', 'thong-tin') { foreach ($f in $script:FLAGS) { if ($f.mucDo -eq $lv) { $f } } })
$nLoi = @($sorted | Where-Object { $_.mucDo -eq 'loi' }).Count
if ($sorted.Count -eq 0) {
  [void]$head.AppendLine('  Khong phat hien dau hieu bat thuong ro rang nao qua cac phep kiem tu dong.')
  [void]$head.AppendLine('  Hay doc ky muc 6 (do hieu nang), muc 7 (tien trinh) va muc 17 (nhat ky hieu nang).')
} else {
  $i = 0
  foreach ($f in $sorted) {
    $i++
    [void]$head.AppendLine(('  [{0,2}] {1}{2}  ({3})' -f $i, $(if ($f.mucDo -eq 'loi') { '[NGHIEM TRONG] ' } else { '' }), $f.tieuDe, $f.ma))
  }
}
[void]$head.AppendLine('')
[void]$head.AppendLine(('  Tong so canh bao: {0} (nghiem trong: {1})' -f $sorted.Count, $nLoi))

$final = $head.ToString() + $script:SB.ToString()
try {
  [IO.File]::WriteAllText($reportPath, $final, (New-Object System.Text.UTF8Encoding $true))
} catch {
  $reportPath = Join-Path $env:TEMP ("LagReport_{0}_{1}.txt" -f $env:COMPUTERNAME, $stamp)
  try { [IO.File]::WriteAllText($reportPath, $final, (New-Object System.Text.UTF8Encoding $true)) } catch { Write-Host ('  [X] Khong ghi duoc bao cao ' + $reportPath + ': ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
}

Write-Host ''
Write-Host ('  ' + ('=' * 74)) -ForegroundColor Green
Write-Host '   DA XONG. Bao cao luu tai:' -ForegroundColor Green
Write-Host ('   ' + $reportPath) -ForegroundColor White
Write-Host ('   Kich thuoc: {0:N0} KB   |   So canh bao tu dong: {1} (nghiem trong: {2})' -f ((Get-Item -LiteralPath $reportPath).Length / 1KB), $sorted.Count, $nLoi) -ForegroundColor Green
Write-Host ('  ' + ('=' * 74)) -ForegroundColor Green
Write-Host ''
if ($sorted.Count -gt 0) {
  Write-Host '   CANH BAO TU DONG:' -ForegroundColor Yellow
  $i = 0
  foreach ($f in $sorted) { $i++; Write-Host ('    [{0}] {1}' -f $i, $f.tieuDe) -ForegroundColor $(if ($f.mucDo -eq 'loi') { 'Red' } else { 'Yellow' }) }
  Write-Host ''
}

# =============================== KET QUA JSON =================================
# Chuan ket qua cua Tram Tool (tramtool.ketqua/1): Tram hien cac canh bao, goi y script chay tiep. Canh file bao cao.
$jsonPath = Join-Path (Split-Path -Parent $reportPath) ("KetQua_CheckWinFix_ThuThap_{0}_{1}.json" -f $env:COMPUTERNAME, $stamp)
$cnt = { param($lv) @($sorted | Where-Object { $_.mucDo -eq $lv }).Count }
$result = [ordered]@{
  chuan = 'tramtool.ketqua/1'; congCu = 'checkwinfix'; cheDo = 'thu-thap'; phienBan = $SCRIPT_VER
  may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
  batDau = $T0.ToString('s'); ketThuc = (Get-Date).ToString('s')
  maThoat = 0; trangThai = 'xong'; chayThu = $false
  ma = $(if ($sorted.Count) { 'CO_CANH_BAO' } else { 'KHONG_CO_CANH_BAO' })
  thongDiep = $(if ($sorted.Count) { "Thu thập xong: $nLoi nghiêm trọng, $($sorted.Count - $nLoi) cảnh báo khác. Đọc mục CẢNH BÁO TỰ ĐỘNG ở đầu báo cáo." } else { 'Thu thập xong: không thấy dấu hiệu bất thường rõ ràng qua các phép kiểm tự động.' })
  tomTat = [ordered]@{ loi = (& $cnt 'loi'); canhBao = (& $cnt 'canh-bao'); thongTin = (& $cnt 'thong-tin') }
  phatHien = $sorted
  tep = @(@([ordered]@{ nhan = 'Báo cáo'; duongDan = $reportPath }) + @($script:TepThem))
  baoCao = $reportPath; quyenAdmin = [bool]$isAdmin; kiemTraSau = [bool]$KiemTraSau
}
try {
  [IO.File]::WriteAllText($jsonPath + '.tmp', ($result | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding $false))
  Move-Item -LiteralPath ($jsonPath + '.tmp') -Destination $jsonPath -Force -ErrorAction Stop
} catch { Write-Host ('  [!] Khong ghi duoc file ket qua JSON: ' + $_.Exception.Message) -ForegroundColor Yellow }

if (-not $env:CWF_KHONG_MO) {   # bai thu dat CWF_KHONG_MO: khong mo Notepad, khong doi clipboard
  try { Set-Clipboard -Value $reportPath -ErrorAction SilentlyContinue } catch {}
  try { Start-Process notepad.exe -ArgumentList ('"' + $reportPath + '"') } catch {}
}
exit 0
