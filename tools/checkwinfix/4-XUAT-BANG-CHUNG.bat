@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title XUAT HO SO BANG CHUNG - de nop len cong ty (v1.0)

set "SELF=%~f0"
set "OUTDIR=%~dp0"
if "%OUTDIR:~-1%"=="\" set "OUTDIR=%OUTDIR:~0,-1%"

echo.
echo  ==========================================================================
echo    XUAT HO SO BANG CHUNG LOI O DIA
echo  --------------------------------------------------------------------------
echo    Trich xuat nhat ky goc cua Windows thanh bo ho so co the nop len
echo    cong ty: file .evtx mo duoc bang Event Viewer, bang CSV va bang tom tat.
echo    Script CHI DOC nhat ky. Khong xoa, khong sua nhat ky.
echo  ==========================================================================
echo.

where powershell >nul 2>&1
if errorlevel 1 goto :ERR_NOPS

net session >nul 2>&1
if errorlevel 1 goto :ELEVATE
goto :ADMIN_OK

:ELEVATE
echo  [*] Can quyen Administrator. Dang mo lai, vui long bam YES...
powershell -NoProfile -Command "Start-Process -FilePath $env:SELF -Verb RunAs" >nul 2>&1
if errorlevel 1 (
  echo  [!] Khong nang duoc quyen. Chuot phai file nay ^> Run as administrator.
  pause
)
exit /b

:ADMIN_OK
set "PS1=%TEMP%\CWF_Evidence_%RANDOM%.ps1"
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
  Xuat ho so bang chung loi phan cung o dia.
  Chi doc nhat ky he thong. Khong xoa/sua nhat ky.
#>
param([string]$OutDir = "")

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Say  { param([string]$t, [string]$c = 'Gray') Write-Host $t -ForegroundColor $c }
function Head { param([string]$t) Write-Host ''; Write-Host ('  ' + ('=' * 70)) -ForegroundColor DarkCyan; Write-Host "   $t" -ForegroundColor Cyan; Write-Host ('  ' + ('=' * 70)) -ForegroundColor DarkCyan }

$SUM = New-Object System.Text.StringBuilder
function W { param([string]$t = '') [void]$SUM.AppendLine($t) }
function KV { param($k, $v) W ("  {0,-34}: {1}" -f $k, $v) }

if ([string]::IsNullOrWhiteSpace($OutDir) -or -not (Test-Path -LiteralPath $OutDir)) { $OutDir = Join-Path $env:USERPROFILE 'Desktop' }
$stamp = Get-Date -Format 'yyyyMMdd_HHmm'
$dir = Join-Path $OutDir ("HoSoBangChung_{0}_{1}" -f $env:COMPUTERNAME, $stamp)
New-Item -ItemType Directory -Path $dir -Force | Out-Null
if (-not (Test-Path -LiteralPath $dir)) { Say '  [X] Khong tao duoc thu muc ho so.' Red; exit 1 }

Head '1/5  XUAT NHAT KY GOC (.evtx)'
Say '  File .evtx la nhat ky goc cua Windows, mo bang Event Viewer de kiem chung.' DarkGray
Say ''

$exports = @(
  @{ File = '01_LoiPhanCung_ODia.evtx';   Log = 'System';
     Q = "*[System[Provider[@Name='disk' or @Name='storahci' or @Name='stornvme' or @Name='storport']]]";
     Mo = 'Loi doc/ghi cap phan cung do trinh dieu khien o dia ghi nhan (Event ID 154, 153, 129, 11, 51, 7)' },
  @{ File = '02_HongHeThongTep_NTFS.evtx'; Log = 'System';
     Q = "*[System[Provider[@Name='Ntfs' or @Name='Microsoft-Windows-Ntfs' or @Name='volmgr' or @Name='volsnap' or @Name='Volsnap' or @Name='partmgr']]]";
     Mo = 'Hong cau truc he thong tep NTFS va loi quan ly o dia' },
  @{ File = '03_TatDotNgot_ManHinhXanh.evtx'; Log = 'System';
     Q = "*[System[Provider[@Name='Microsoft-Windows-Kernel-Power' or @Name='EventLog' or @Name='Microsoft-Windows-WER-SystemErrorReporting' or @Name='Microsoft-Windows-WHEA-Logger' or @Name='Microsoft-Windows-Kernel-Boot']]]";
     Mo = 'May tat/treo dot ngot, man hinh xanh va loi phan cung WHEA' },
  @{ File = '04_SQLServer_KhongDocDuocDuLieu.evtx'; Log = 'Application';
     Q = "*[System[Provider[@Name='MSSQLSERVER' or @Name='Application Error' or @Name='Application Hang']]]";
     Mo = 'SQL Server bao loi he dieu hanh 483 khi doc co so du lieu, va cac ung dung bi crash' },
  @{ File = '05_HieuNangKhoiDong.evtx'; Log = 'Microsoft-Windows-Diagnostics-Performance/Operational';
     Q = '*';
     Mo = 'Nhat ky hieu nang cua Windows: thoi gian khoi dong va thu pham lam cham' }
)

W ('=' * 78)
W '  HO SO BANG CHUNG LOI PHAN CUNG O DIA'
W ('=' * 78)
W ''
KV 'Ten may'            $env:COMPUTERNAME
$cs = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
KV 'Bo mach chu'        ("{0} {1}" -f $cs.Manufacturer, $cs.Model)
KV 'He dieu hanh'       ("{0} build {1}" -f $os.Caption, $os.BuildNumber)
KV 'Ngay cai Windows'   ('{0:yyyy-MM-dd HH:mm}' -f $os.InstallDate)
KV 'Thoi diem trich xuat' (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
KV 'Nguoi thuc hien'    ("{0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)
W ''
W '  Toan bo du lieu duoi day do chinh Windows ghi lai, khong phai nhan dinh cua nguoi lap.'
W ''

W ('-' * 78)
W '  PHAN 1 - CAC FILE NHAT KY GOC KEM THEO'
W ('-' * 78)
foreach ($e in $exports) {
  $target = Join-Path $dir $e.File
  Say ("  Dang xuat: " + $e.File) Gray
  $res = & wevtutil.exe epl $e.Log $target ("/q:" + $e.Q) /ow:true 2>&1
  if (Test-Path -LiteralPath $target) {
    $cnt = 0
    try { $cnt = @(Get-WinEvent -Path $target -ErrorAction Stop).Count } catch {}
    $sz = (Get-Item -LiteralPath $target).Length
    Say ("     -> {0} su kien, {1:N0} KB" -f $cnt, ($sz / 1KB)) Green
    W ''
    W ("  " + $e.File)
    W ("    Nhat ky nguon : " + $e.Log)
    W ("    Noi dung      : " + $e.Mo)
    W ("    So su kien    : " + $cnt)
  } else {
    $why = ((($res | Out-String) -replace '\s+', ' ').Trim())
    if ($why.Length -gt 160) { $why = $why.Substring(0, 160) }
    Say ('     -> khong xuat duoc: ' + $why) Yellow
    W ''
    W ("  " + $e.File + "  -> KHONG XUAT DUOC")
    W ("    Ly do         : " + $why)
  }
}

Head '2/5  BANG TONG HOP SU KIEN (CSV va TXT)'
$since = (Get-Date).AddDays(-60)
$prov = '^(disk|Disk|storahci|stornvme|storport|partmgr|volmgr|volsnap|Volsnap|Ntfs|Microsoft-Windows-Ntfs|Microsoft-Windows-Kernel-Power|Microsoft-Windows-WHEA-Logger|Microsoft-Windows-WER-SystemErrorReporting|EventLog|Microsoft-Windows-Kernel-Boot)$'
$all = @()
foreach ($lg in @('System', 'Application')) {
  try {
    $all += @(Get-WinEvent -FilterHashtable @{ LogName = $lg; StartTime = $since; Level = 1, 2, 3 } -MaxEvents 8000 -ErrorAction Stop |
      Where-Object { $_.ProviderName -match $prov -or $_.ProviderName -eq 'MSSQLSERVER' })
  } catch {}
}
Say ("  Tim thay {0} su kien lien quan trong 60 ngay." -f $all.Count) Gray

$csv = Join-Path $dir '06_TongHopSuKien.csv'
$all | Sort-Object TimeCreated -Descending |
  Select-Object @{n = 'ThoiDiem'; e = { '{0:yyyy-MM-dd HH:mm:ss}' -f $_.TimeCreated } },
                @{n = 'NhatKy'; e = { $_.LogName } },
                @{n = 'Nguon'; e = { $_.ProviderName } },
                @{n = 'EventID'; e = { $_.Id } },
                @{n = 'MucDo'; e = { $_.LevelDisplayName } },
                @{n = 'NoiDung'; e = { ("$($_.Message)" -replace '\s+', ' ') } } |
  Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
if (Test-Path -LiteralPath $csv) { Say ("  Da ghi: 06_TongHopSuKien.csv") Green }

W ''
W ('-' * 78)
W '  PHAN 2 - THONG KE SU KIEN (60 ngay gan nhat)'
W ('-' * 78)
W ''
W ('  {0,7}  {1,-12} {2,-44} {3}' -f 'So lan', 'Nhat ky', 'Nguon', 'ID')
W ('  ' + ('-' * 74))
foreach ($g in ($all | Group-Object { "$($_.LogName)|$($_.ProviderName)|$($_.Id)" } | Sort-Object Count -Descending)) {
  $f = $g.Group[0]
  W ('  {0,7}  {1,-12} {2,-44} {3}' -f $g.Count, $f.LogName, $f.ProviderName, $f.Id)
}
W ''
W '  Trich nguyen van mot so su kien tieu bieu:'
W ''
foreach ($id in @(154, 823, 18210, 55, 98, 41, 1001)) {
  $s = $all | Where-Object { $_.Id -eq $id } | Select-Object -First 1
  if (-not $s) { continue }
  W ("  [{0}] {1} - Event ID {2} - xuat hien {3} lan" -f $s.LogName, $s.ProviderName, $id, (@($all | Where-Object { $_.Id -eq $id -and $_.ProviderName -eq $s.ProviderName })).Count)
  W ('    "' + (("$($s.Message)" -replace '\s+', ' ')) + '"')
  W ''
}

Head '3/5  THONG TIN O DIA VA SMART'
W ('-' * 78)
W '  PHAN 3 - PHAN CUNG LUU TRU'
W ('-' * 78)
W ''
foreach ($d in (Get-CimInstance Win32_DiskDrive | Sort-Object Index)) {
  $vols = @()
  try { $vols = @(Get-Partition -DiskNumber $d.Index -ErrorAction Stop | Where-Object { $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter):" }) } catch {}
  W ("  Disk {0} : {1}" -f $d.Index, $d.Model)
  W ("     Giao tiep     : " + $d.InterfaceType)
  W ("     Dung luong    : {0:N2} GB" -f ($d.Size / 1GB))
  W ("     Serial        : " + ("$($d.SerialNumber)").Trim())
  W ("     Firmware      : " + ("$($d.FirmwareRevision)").Trim())
  W ("     O logic       : " + ($vols -join ', '))
  $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { [int]$_.DeviceId -eq [int]$d.Index }
  if ($pd) {
    W ("     Loai o        : {0} / {1}" -f $pd.MediaType, $pd.BusType)
    W ("     Windows danh gia: Health={0}" -f $pd.HealthStatus)
    $rc = $pd | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
    if ($rc) {
      W ("     Gio da chay   : {0}" -f $rc.PowerOnHours)
      W ("     Nhiet do      : {0} C" -f $rc.Temperature)
      W ("     Loi doc       : Corrected={0}  Uncorrected={1}" -f $rc.ReadErrorsCorrected, $rc.ReadErrorsUncorrected)
    }
  }
  W ''
}
$names = @{ 1 = 'Raw_Read_Error_Rate'; 5 = 'Reallocated_Sectors'; 7 = 'Seek_Error_Rate'; 9 = 'Power_On_Hours';
  10 = 'Spin_Retry'; 184 = 'End_to_End_Error'; 187 = 'Reported_Uncorrectable'; 188 = 'Command_Timeout';
  194 = 'Temperature'; 196 = 'Realloc_Event_Count'; 197 = 'Current_Pending_Sector';
  198 = 'Offline_Uncorrectable'; 199 = 'UDMA_CRC_Error' }
foreach ($disk in (Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictData -ErrorAction SilentlyContinue)) {
  W ('  Bang thuoc tinh SMART - ' + $disk.InstanceName)
  $th = @{}
  foreach ($t in (Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictThresholds -ErrorAction SilentlyContinue)) {
    if ($t.InstanceName -ne $disk.InstanceName) { continue }
    $vv = $t.VendorSpecific
    for ($k = 0; $k -lt 30; $k++) { $b2 = 2 + 12 * $k; if (($b2 + 1) -ge $vv.Count) { break }; if ([int]$vv[$b2] -ne 0) { $th[[int]$vv[$b2]] = [int]$vv[$b2 + 1] } }
  }
  $v = $disk.VendorSpecific
  W ('    {0,-24} {1,-5} {2,-8} {3,-8} {4,-10} {5}' -f 'Chi so', 'ID', 'Hien tai', 'Thap nhat', 'Nguong', 'Gia tri tho')
  for ($k = 0; $k -lt 30; $k++) {
    $b2 = 2 + 12 * $k
    if (($b2 + 11) -ge $v.Count) { break }
    $id = [int]$v[$b2]
    if ($id -eq 0) { continue }
    $raw = [uint64]0
    for ($j = 5; $j -ge 0; $j--) { $raw = $raw * 256 + [uint64]$v[$b2 + 5 + $j] }
    $nm = 'Attr_' + $id
    if ($names.ContainsKey($id)) { $nm = $names[$id] }
    $tv = ''
    if ($th.ContainsKey($id)) { $tv = $th[$id] }
    W ('    {0,-24} {1,-5} {2,-8} {3,-8} {4,-10} {5}' -f $nm, $id, $v[$b2 + 3], $v[$b2 + 4], $tv, $raw)
  }
  W ''
}

Head '4/5  GOM CAC BAO CAO DA CHAY TRUOC DO'
$copied = 0
foreach ($pat in @('LagReport_*.txt', 'HwDiag_*.txt', 'WheaDecode_*.txt', 'KET_QUA_CUU_DU_LIEU.txt')) {
  foreach ($f in (Get-ChildItem -LiteralPath $OutDir -Filter $pat -ErrorAction SilentlyContinue)) {
    Copy-Item -LiteralPath $f.FullName -Destination $dir -Force -ErrorAction SilentlyContinue
    if ($?) { Say ('  Da chep: ' + $f.Name) Green; $copied++ }
  }
}
if ($copied -eq 0) { Say '  (khong tim thay bao cao nao canh file bat nay)' DarkGray }

Head '5/5  TAO CUA SO XEM SAN TRONG EVENT VIEWER'
Say '  Buoc nay tao mot "Custom View" trong Event Viewer de mo ra la thay ngay' DarkGray
Say '  cac su kien loi, tien cho viec chup anh man hinh nop kem ho so.' DarkGray
Say '  No chi THEM mot muc xem, khong sua nhat ky va xoa duoc bat cu luc nao.' DarkGray
Say ''
$ans = Read-Host '  Tao Custom View? (Y = tao, Enter = bo qua)'
if ($ans -eq 'Y' -or $ans -eq 'y') {
  $viewDir = Join-Path $env:ProgramData 'Microsoft\Event Viewer\Views'
  try {
    New-Item -ItemType Directory -Path $viewDir -Force -ErrorAction Stop | Out-Null
    $xml = @'
<ViewerConfig>
  <QueryConfig>
    <QueryParams><UserQuery /></QueryParams>
    <QueryNode>
      <Name>CheckWinFix - Bang chung loi o dia</Name>
      <Description>Loi doc/ghi cap phan cung, hong NTFS, tat dot ngot, man hinh xanh va loi SQL Server</Description>
      <QueryList>
        <Query Id="0" Path="System">
          <Select Path="System">*[System[Provider[@Name='disk' or @Name='storahci' or @Name='storport' or @Name='Ntfs' or @Name='Microsoft-Windows-Ntfs' or @Name='volmgr' or @Name='Volsnap' or @Name='Microsoft-Windows-Kernel-Power' or @Name='Microsoft-Windows-WHEA-Logger' or @Name='Microsoft-Windows-WER-SystemErrorReporting']]]</Select>
        </Query>
        <Query Id="1" Path="Application">
          <Select Path="Application">*[System[Provider[@Name='MSSQLSERVER']]]</Select>
        </Query>
      </QueryList>
    </QueryNode>
  </QueryConfig>
</ViewerConfig>
'@
    $viewFile = Join-Path $viewDir 'CheckWinFix_BangChung.xml'
    [IO.File]::WriteAllText($viewFile, $xml, (New-Object System.Text.UTF8Encoding $false))
    Say ('  Da tao. Mo Event Viewer > Custom Views > "CheckWinFix - Bang chung loi o dia"') Green
    Say ('  File: ' + $viewFile) DarkGray
    W ''
    W '  Da tao Custom View trong Event Viewer: "CheckWinFix - Bang chung loi o dia"'
    W ('  (' + $viewFile + ' - xoa file nay la go bo)')
  } catch { Say ('  Khong tao duoc Custom View: ' + $_.Exception.Message) Yellow }
} else { Say '  Da bo qua.' DarkGray }

# ---------------- huong dan chup anh ----------------
W ''
W ('-' * 78)
W '  PHAN 4 - CACH KIEM CHUNG LAI VA CHUP ANH MAN HINH'
W ('-' * 78)
W ''
W '  1. Nhan Windows + R, go: eventvwr.msc'
W '  2. Vao Windows Logs > System, cot ben phai chon "Filter Current Log..."'
W '  3. O "Event sources" chon: disk     O "Event IDs" go: 154     bam OK'
W '  4. So su kien hien ra o thanh tren chinh la con so neu trong bao cao.'
W '     Mo mot su kien bat ky se thay nguyen van:'
W '       "The IO operation at logical block address 0x... for Disk 0'
W '        failed due to a hardware error."'
W '  5. Nhan phim PrtScn (hoac Windows + Shift + S) de chup man hinh nop kem.'
W '  6. Lam tuong tu voi Windows Logs > Application, nguon MSSQLSERVER, Event ID 823'
W '     de thay loi 483 tren tep co so du lieu.'
W ''
W '  Neu da tao Custom View o buoc 5: mo Event Viewer > Custom Views >'
W '  "CheckWinFix - Bang chung loi o dia" la thay ngay toan bo, khong can loc tay.'
W ''
W ('-' * 78)
W '  DANH MUC FILE TRONG HO SO'
W ('-' * 78)

$sumPath = Join-Path $dir '00_BAN_TOM_TAT.txt'
[IO.File]::WriteAllText($sumPath, $SUM.ToString(), (New-Object System.Text.UTF8Encoding $true))

$listing = New-Object System.Text.StringBuilder
foreach ($f in (Get-ChildItem -LiteralPath $dir | Sort-Object Name)) {
  [void]$listing.AppendLine(('  {0,-46} {1,10:N0} KB' -f $f.Name, ($f.Length / 1KB)))
}
[IO.File]::AppendAllText($sumPath, $listing.ToString(), (New-Object System.Text.UTF8Encoding $false))

Write-Host ''
Write-Host ('  ' + ('=' * 70)) -ForegroundColor Green
Write-Host '   XONG. Ho so bang chung nam tai:' -ForegroundColor Green
Write-Host ('   ' + $dir) -ForegroundColor White
Write-Host ('  ' + ('=' * 70)) -ForegroundColor Green
Write-Host ''
Write-Host '   Mo file 00_BAN_TOM_TAT.txt de xem toan bo noi dung ho so.' -ForegroundColor Cyan
Write-Host '   Nen nen ca thu muc thanh .zip roi dinh kem khi nop.' -ForegroundColor Cyan
Write-Host ''
try { Start-Process explorer.exe -ArgumentList ('"' + $dir + '"') } catch {}
exit 0
