@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title CUU DU LIEU KHAN CAP - o dia D: dang hong (v2.0)

set "SELF=%~f0"
set "OUTDIR=%~dp0"
if "%OUTDIR:~-1%"=="\" set "OUTDIR=%OUTDIR:~0,-1%"

echo.
echo  ==========================================================================
echo    CUU DU LIEU KHAN CAP  -  O DIA D: DANG HONG PHAN CUNG
echo  --------------------------------------------------------------------------
echo    Script CHI DOC tu o D: va GHI ra noi khac.
echo    KHONG xoa, KHONG sua bat cu file nao tren o D:.
echo.
echo    Script se tam DUNG dich vu SQL Server de copy duoc file database,
echo    sau do TU BAT LAI. Phan mem giu xe se ngung vai phut.
echo    =^> Hay chay vao luc bai xe vang nhat.
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
set "PS1=%TEMP%\CWF_Rescue_%RANDOM%.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$r=Get-Content -LiteralPath $env:SELF -Raw -Encoding UTF8; $m='#====='+'PS_START'+'====='; $i=$r.IndexOf($m); if($i -lt 0){exit 1}; [IO.File]::WriteAllText($env:PS1, $r.Substring($i+$m.Length), (New-Object Text.UTF8Encoding $true)); exit 0"
if errorlevel 1 goto :ERR_SPLIT

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -OutDir "%OUTDIR%"
set "RC=%ERRORLEVEL%"
del /f /q "%PS1%" >nul 2>&1
echo.
pause
exit /b %RC%

:ERR_NOPS
echo  [X] Khong tim thay PowerShell. Script khong chay duoc.
pause
exit /b 1

:ERR_SPLIT
echo  [X] Khong tach duoc phan PowerShell (file bi luu sai bang ma).
pause
exit /b 1

#=====PS_START=====
<#
  CUU DU LIEU KHAN CAP - chep du lieu ra khoi o dia dang hong (ca may giu xe ITS-Pro tren SQL Server).
  Chi DOC tu nguon, khong xoa/sua gi tren o nguon.
  Ban 2: noi luu phai nam tren o VAT LY khac voi nguon; dung moi dich vu SQL Server (moi instance MSSQL*);
  doi chieu MD5 trong luc SQL Server con dung (file database khong bi khoa); luon bat lai dich vu (finally),
  neu cua so bi dong giua chung thi lan chay sau nhac bat lai; luon ghi vao mot thu muc moi.
  Ma thoat: 0 xong, 1 loi, 2 huy hoac thieu dieu kien, 3 xong mot phan (co file loi, lech ma bam, dich vu chua bat lai).
#>
param([string]$OutDir = "")

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$script:DefaultSource = 'D:\ITS'
$script:MarkerKey     = 'HKLM:\SOFTWARE\TramTool\CuuDuLieu'
$script:SqlPattern    = '^(MSSQL\$.+|MSSQLSERVER|SQLAgent\$.+|SQLSERVERAGENT|MSSQLFDLauncher.*|MSSQLServerOLAPService|MSOLAP\$.+|MsDtsServer\d*|SQLWriter|SQLBrowser|ReportServer.*|SQLTELEMETRY.*|SSISTELEMETRY.*|MSSQLLaunchpad.*)$'
$script:AppProcs      = @('ITS-Pro', 'Ssms', 'sqlservr')
$script:SettleSeconds = 3

function Say  { param([string]$t, [string]$c = 'Gray') Write-Host $t -ForegroundColor $c }
function Head { param([string]$t) Write-Host ''; Write-Host ('  ' + ('=' * 72)) -ForegroundColor DarkCyan; Write-Host "   $t" -ForegroundColor Cyan; Write-Host ('  ' + ('=' * 72)) -ForegroundColor DarkCyan }
function FmtGB { param($b) if ($null -eq $b) { return 'n/a' } '{0:N2} GB' -f ([double]$b / 1GB) }

$script:LOG = New-Object System.Text.StringBuilder
function L { param([string]$t = '') [void]$script:LOG.AppendLine($t); if ($t) { Say ('  ' + $t) } }

function Ask {
  # Khong co ban phim (chay tu dong) thi tra mac dinh thay vi treo.
  param([string]$Prompt, [string]$Default = '')
  if ([Console]::IsInputRedirected) { return $Default }
  $a = Read-Host $Prompt
  if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
  return $a.Trim()
}

# --------------------------- o dia --------------------------------------------
function Get-DiskNumberOfPath {
  # So o vat ly (Disk N) chua duong dan; khong xac dinh duoc (o mang, o ao...) thi tra $null.
  param([string]$Path)
  try {
    $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
    if (-not ($root -match '^([A-Za-z]):\\$')) { return $null }
    $p = Get-Partition -DriveLetter $Matches[1] -ErrorAction Stop | Select-Object -First 1
    if ($null -eq $p) { return $null }
    return [int]$p.DiskNumber
  } catch { return $null }
}

function Get-Candidates {
  # Cac o co chu cai nam tren o vat ly KHAC nguon.
  param($SrcDisk, [double]$Need)
  $list = @()
  foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and ([string]$_.DriveType -in 'Fixed', 'Removable') -and $_.FileSystem } | Sort-Object DriveLetter)) {
    $root = "$($v.DriveLetter):\"
    $disk = Get-DiskNumberOfPath $root
    if ($null -eq $disk) { continue }
    if ($null -ne $SrcDisk -and $disk -eq $SrcDisk) { continue }
    $bus = ''
    try { $bus = [string](Get-Disk -Number $disk -ErrorAction Stop).BusType } catch {}
    $list += [pscustomobject]@{ Root = $root; Label = [string]$v.FileSystemLabel; Free = [double]$v.SizeRemaining; Bus = $bus; Disk = $disk; Enough = ([double]$v.SizeRemaining -ge $Need) }
  }
  return , $list
}

function Get-FreeBytes {
  param([string]$Path)
  try { return [double](New-Object IO.DriveInfo ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path)))).AvailableFreeSpace } catch { return 0 }
}

# --------------------------- dich vu SQL Server -------------------------------
function Get-SqlServices { return @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $script:SqlPattern }) }

function Get-StopOrder {
  # Dich vu phu (Agent, Full-text, SSIS...) dung truoc, engine (MSSQL*) sau, SQLWriter/SQLBrowser cuoi cung.
  param([string[]]$Names)
  return @($Names | Sort-Object { if ($_ -match '^(MSSQL\$.+|MSSQLSERVER)$') { 2 } elseif ($_ -match '^(SQLWriter|SQLBrowser)$') { 3 } else { 1 } }, { $_ })
}

function Stop-Svc {
  param([string]$Name)
  try { Stop-Service -Name $Name -Force -ErrorAction Stop; (Get-Service -Name $Name).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(90)); return $true } catch { return $false }
}

function Start-Svc {
  param([string]$Name)
  try { Start-Service -Name $Name -ErrorAction Stop; return $true } catch { return $false }
}

function Get-PendingMarker {
  try { return @((Get-ItemProperty -LiteralPath $script:MarkerKey -Name DichVu -ErrorAction Stop).DichVu | Where-Object { $_ }) } catch { return @() }
}

function Set-PendingMarker {
  # Ghi lai dich vu dang bi dung: cua so bi dong giua chung thi lan chay sau con biet de bat lai.
  param([string[]]$Names)
  try {
    if (-not (Test-Path -LiteralPath $script:MarkerKey)) { New-Item -Path $script:MarkerKey -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -LiteralPath $script:MarkerKey -Name DichVu -Value $Names -PropertyType MultiString -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -LiteralPath $script:MarkerKey -Name LuuLuc -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -PropertyType String -Force -ErrorAction Stop | Out-Null
  } catch { Say ('  [!] Khong ghi duoc danh sach dich vu dang dung vao registry: ' + $_.Exception.Message) Yellow }
}

function Clear-PendingMarker { try { Remove-Item -LiteralPath $script:MarkerKey -Recurse -Force -ErrorAction Stop } catch {} }

function Start-Services {
  # Bat lai theo thu tu nguoc voi luc dung. Tra danh sach dich vu chua bat lai duoc (giu trong registry).
  param([string[]]$Names)
  $order = @(Get-StopOrder $Names); [array]::Reverse($order)
  $failed = @()
  foreach ($n in $order) {
    if (Start-Svc $n) { L "Bat lai dich vu: $n -> da bat" } else { L "Bat lai dich vu: $n -> KHONG bat duoc"; $failed += $n }
  }
  if ($failed.Count) { Set-PendingMarker $failed } else { Clear-PendingMarker }
  return $failed   # noi goi boc @(...)
}

function Stop-AppProcesses {
  foreach ($pn in $script:AppProcs) {
    foreach ($p in @(Get-Process -Name $pn -ErrorAction SilentlyContinue)) {
      L "Dong tien trinh: $pn (PID $($p.Id))"
      try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { L "   -> khong dong duoc: $($_.Exception.Message)" }
    }
  }
}

# --------------------------- chep, doi chieu ----------------------------------
function Invoke-Robocopy {
  param([string]$Src, [string]$Dst, [string]$Log)
  $common = @('/E', '/COPY:DAT', '/DCOPY:DAT', '/R:1', '/W:1', '/XJ', '/NP', '/TEE', ('/LOG+:' + $Log))
  & robocopy.exe @(@($Src, $Dst, '/B') + $common) | Out-Host
  $rc = $LASTEXITCODE
  if ($rc -ge 16) {
    L "Robocopy loi nghiem trong (ma $rc). Thu lai khong dung che do Backup (/B)..."
    & robocopy.exe @(@($Src, $Dst) + $common) | Out-Host
    $rc = $LASTEXITCODE
  }
  return $rc
}

function Get-Md5 {
  param([string]$Path)
  try { return (Get-FileHash -LiteralPath $Path -Algorithm MD5 -ErrorAction Stop).Hash } catch { return $null }
}

function Test-Copies {
  # Doi chieu MD5 file database (moi kich thuoc); khong co file database thi 30 file lon nhat (toi da 4 GB moi file).
  param([string]$Src, [string]$Dst2)
  $res = [pscustomobject]@{ Checked = 0; Good = 0; Bad = 0 }
  $files = @(Get-ChildItem -LiteralPath $Src -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '(?i)^\.(mdf|ldf|ndf|bak)$' })
  $limit = [double]::MaxValue
  if ($files.Count -eq 0) {
    L '   (khong co file .mdf/.ldf/.ndf/.bak - doi chieu 30 file lon nhat thay the)'
    $files = @(Get-ChildItem -LiteralPath $Src -Recurse -Force -File -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 30)
    $limit = 4GB
  }
  foreach ($f in $files) {
    if ($f.Length -gt $limit) { L ('   BO QUA (qua lon): ' + $f.Name); continue }
    $rel = $f.FullName.Substring($Src.Length).TrimStart('\')
    $cp  = Join-Path $Dst2 $rel
    if (-not (Test-Path -LiteralPath $cp)) { L "   THIEU BAN SAO : $rel"; $res.Bad++; continue }
    $res.Checked++
    Say ('   Dang doi chieu: {0} ({1})' -f $rel, (FmtGB $f.Length)) DarkGray
    $h1 = Get-Md5 $f.FullName
    $h2 = Get-Md5 $cp
    if (-not $h1) { L "   KHONG DOC DUOC NGUON: $rel"; $res.Bad++ }
    elseif ($h1 -eq $h2) { L ('   OK            : {0}  ({1})' -f $rel, (FmtGB $f.Length)); $res.Good++ }
    else { L "   KHONG KHOP    : $rel"; $res.Bad++ }
  }
  if ($res.Checked -eq 0 -and $res.Bad -eq 0) { L '   (khong co file nao de doi chieu)' }
  return $res
}

function Measure-Folder {
  param([string]$Path)
  $r = [pscustomobject]@{ Bytes = [double]0; Files = 0 }
  try {
    foreach ($f in [System.IO.Directory]::EnumerateFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)) {
      try { $r.Bytes += (New-Object System.IO.FileInfo $f).Length; $r.Files++ } catch {}
    }
  } catch {}
  return $r
}

# --------------------------- chay ---------------------------------------------
function Invoke-CuuDuLieu {
  $pending = @(Get-PendingMarker)
  if ($pending.Count) {
    Head 'LAN TRUOC CUA SO BI DONG KHI SQL SERVER DANG DUNG'
    Say ('  Cac dich vu chua duoc bat lai: ' + ($pending -join ', ')) Yellow
    $a = Ask '  Bat lai ngay? (Enter hoac Y = bat lai, N = de sau)' 'Y'
    if ($a -match '^[yYcC]') {
      $f0 = @(Start-Services $pending)
      if ($f0.Count) { Say ('  [!] Chua bat lai duoc: ' + ($f0 -join ', ') + '. Mo services.msc de bat bang tay.') Red } else { Say '  [OK] Da bat lai.' Green }
    }
  }

  # 1. nguon
  Head '1/6  XAC DINH DU LIEU CAN CUU'
  $src = $script:DefaultSource
  if (-not (Test-Path -LiteralPath $src)) {
    Say "  Khong thay $src tren may nay." Yellow
    $src = Ask '  Nhap duong dan thu muc can cuu (vd D:\ITS)' ''
    if (-not $src -or -not (Test-Path -LiteralPath $src)) { Say '  [X] Duong dan khong ton tai. Dung script.' Red; return 2 }
  }
  $src = (Resolve-Path -LiteralPath $src).ProviderPath
  if ($src.Length -gt 3) { $src = $src.TrimEnd('\') }   # giu 'D:\' (bo '\' thanh 'D:' la thu muc hien tai cua o D)
  Say "  Thu muc nguon : $src" White
  Say '  Dang do dung luong (co the cham vi o dia dang loi)...' DarkGray
  $m = Measure-Folder $src
  Say ('  Kich thuoc     : {0}  ({1} file)' -f (FmtGB $m.Bytes), $m.Files) White
  $srcDisk = Get-DiskNumberOfPath $src
  if ($null -eq $srcDisk) { Say '  [!] Khong xac dinh duoc o vat ly cua nguon; noi luu se phai xac nhan rieng.' Yellow }
  else { Say "  O vat ly nguon: Disk $srcDisk" White }
  $srcRoot = [IO.Path]::GetPathRoot($src)
  Say ''
  Say ("  Cac thu muc khac tren {0} :" -f $srcRoot) DarkGray
  foreach ($d in (Get-ChildItem -LiteralPath $srcRoot -Directory -Force -ErrorAction SilentlyContinue)) {
    if ($d.Name -match '^\$RECYCLE|System Volume Information') { continue }
    Say ('    - ' + $d.FullName)
  }

  # 2. noi luu
  Head '2/6  CHON NOI LUU BAN SAO (o vat ly KHAC o dang hong)'
  $need = [double]$m.Bytes * 1.1
  $cands = Get-Candidates $srcDisk $need
  $i = 0
  foreach ($c in $cands) {
    $i++
    $lbl = if ($c.Label) { " '" + $c.Label + "'" } else { '' }
    $col = if ($c.Enough) { 'White' } else { 'DarkGray' }
    Say ('  [{0}] {1}{2}  Disk {3} {4}, con trong {5}{6}' -f $i, $c.Root, $lbl, $c.Disk, $c.Bus, (FmtGB $c.Free), $(if ($c.Enough) { '' } else { '  (KHONG DU CHO)' })) $col
  }
  $okC = @($cands | Where-Object { $_.Enough })
  $def = $okC | Where-Object { $_.Bus -eq 'USB' } | Select-Object -First 1
  if (-not $def) { $def = $okC | Select-Object -First 1 }
  $defText = if ($def) { $def.Root } else { '' }
  if (-not $def) {
    Say ''
    Say ('  [!] Khong co o nao khac o vat ly nguon con du cho (can khoang {0}).' -f (FmtGB $need)) Yellow
    Say '      Cam USB / o cung ngoai roi chay lai, hoac nhap duong dan khac ben duoi.' Yellow
  }
  Say ''
  $ans = Ask ('  Chon so trong danh sach hoac nhap duong dan' + $(if ($def) { " (Enter = $defText)" } else { '' })) $defText
  if (-not $ans) { Say '  Da huy.' Yellow; return 2 }
  $base = $ans
  if ($ans -match '^\d+$') {
    $k = [int]$ans
    if ($k -lt 1 -or $k -gt $cands.Count) { Say '  [X] Khong co so do trong danh sach.' Red; return 2 }
    $base = $cands[$k - 1].Root
  }
  $dstDisk = Get-DiskNumberOfPath $base
  if ($null -ne $srcDisk -and $null -ne $dstDisk -and $dstDisk -eq $srcDisk) {
    Say ("  [X] {0} nam tren CUNG o vat ly voi nguon (Disk {1}). Ghi vao o dang hong co the lam mat them du lieu." -f $base, $srcDisk) Red
    Say '      Chon USB / o cung ngoai, hoac o thuoc o vat ly khac.' Red
    return 2
  }
  if ($null -eq $srcDisk -or $null -eq $dstDisk) {
    Say '  [!] Khong xac dinh duoc noi luu co cung o vat ly voi nguon hay khong.' Yellow
    $a = Ask '  Van luu vao day? (Y = co, Enter = khong)' 'N'
    if ($a -notmatch '^[yYcC]') { Say '  Da huy.' Yellow; return 2 }
  }
  $free = Get-FreeBytes $base
  Say ('  Con trong      : {0}' -f (FmtGB $free)) White
  if ($free -gt 0 -and $need -gt 0 -and $free -lt $need) { Say '  [X] KHONG DU CHO. Hay chon o khac.' Red; return 2 }

  # Luon ghi vao thu muc moi, khong bao gio chep chong len ban cuu truoc.
  $dst = Join-Path $base ('CUU_DU_LIEU_ITS_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
  $n = 2
  while (Test-Path -LiteralPath $dst) { $dst = Join-Path $base ('CUU_DU_LIEU_ITS_{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), $n); $n++ }
  try { New-Item -ItemType Directory -Path $dst -ErrorAction Stop | Out-Null } catch { Say "  [X] Khong tao duoc thu muc dich: $($_.Exception.Message)" Red; return 1 }
  Say "  Noi luu        : $dst" White

  # 3. xac nhan
  $svcs = @(Get-SqlServices)
  $running = @(Get-StopOrder @($svcs | Where-Object { [string]$_.Status -eq 'Running' } | ForEach-Object { $_.Name }))
  Head '3/6  XAC NHAN TRUOC KHI CHAY'
  Say '  Script sap lam:' White
  if ($running.Count) { Say ('    1. Dung dich vu SQL Server: ' + ($running -join ', ')) } else { Say '    1. (khong co dich vu SQL Server nao dang chay)' }
  Say '       va dong ITS-Pro, SSMS'
  Say '    2. Chep toan bo du lieu tu nguon sang noi luu (chi doc, khong xoa)'
  Say '    3. Doi chieu ma bam MD5 file database TRONG LUC SQL SERVER CON DUNG'
  Say '    4. Bat lai dung cac dich vu da dung (ke ca khi co loi giua chung)'
  Say ''
  Say '  Trong luc chay, phan mem giu xe SE KHONG DUNG DUOC. Dung dong cua so nay giua chung.' Yellow
  Say ''
  $ok = Ask '  Go Y roi Enter de bat dau (bat ky phim khac = huy)' ''
  if ($ok -notmatch '^[yY]$') {
    Say '  Da huy.' Yellow
    try { Remove-Item -LiteralPath $dst -Force -ErrorAction Stop } catch {}
    return 2
  }

  L ('CUU DU LIEU - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' - may ' + $env:COMPUTERNAME)
  L ("Nguon : $src" + $(if ($null -ne $srcDisk) { " (Disk $srcDisk)" } else { '' }))
  L ("Dich  : $dst" + $(if ($null -ne $dstDisk) { " (Disk $dstDisk)" } else { '' }))
  L ''
  foreach ($s in $svcs) { if ([string]$s.Status -ne 'Running') { L ('Dich vu {0}: dang {1}, bo qua' -f $s.Name, $s.Status) } }

  $leaf = (Split-Path $src -Leaf) -replace '[:\\]', ''
  if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = 'DU_LIEU' }
  $dst2 = Join-Path $dst $leaf
  $rcLog = Join-Path $dst 'robocopy_log.txt'
  $rc = -1; $ver = [pscustomobject]@{ Checked = 0; Good = 0; Bad = 0 }; $stopFail = @(); $startFail = @(); $failed = @()
  if ($running.Count) { Set-PendingMarker $running }
  try {
    Head '4/6  DUNG DICH VU SQL SERVER VA PHAN MEM ITS'
    foreach ($n in $running) {
      if (Stop-Svc $n) { L "Dung dich vu: $n -> da dung" } else { L "Dung dich vu: $n -> KHONG dung duoc"; $stopFail += $n }
    }
    Stop-AppProcesses
    if ($script:SettleSeconds) { Start-Sleep -Seconds $script:SettleSeconds }
    if ($stopFail.Count) { Say '  [!] Con dich vu SQL Server dang chay: file database dang mo se KHONG chep duoc.' Yellow }

    Head '5/6  DANG CHEP DU LIEU (khong tat cua so nay)'
    Say '  O dia gap sector hong thi robocopy bao loi, bo qua file do roi di tiep;' DarkGray
    Say '  cuoi cung se co danh sach file khong cuu duoc.' DarkGray
    $t0 = Get-Date
    $rc = Invoke-Robocopy $src $dst2 $rcLog
    $dur = (Get-Date) - $t0
    L ''
    L ('Robocopy ket thuc sau {0:N0} giay, ma tra ve = {1}' -f $dur.TotalSeconds, $rc)
    if ($rc -lt 8) { Say ('  [OK] Chep xong (ma {0}).' -f $rc) Green } else { Say ('  [!] Chep xong nhung CO FILE LOI (ma {0}). Xem robocopy_log.txt.' -f $rc) Yellow }
    try { $failed = @(Get-Content -LiteralPath $rcLog -ErrorAction Stop | Where-Object { $_ -match 'ERROR \d+ \(' -or $_ -match '0x0000045D|0x00000017|0x0000001F' }) } catch {}
    if ($failed.Count -gt 0) {
      L ''
      L "CAC LOI KHI CHEP ($($failed.Count) dong):"
      foreach ($x in ($failed | Select-Object -First 40)) { L ('   ' + $x.Trim()) }
    }

    Head '6/6  DOI CHIEU MA BAM (SQL Server van dang dung nen file database khong bi khoa)'
    L ''
    L 'DOI CHIEU MA BAM MD5 CAC FILE DATABASE:'
    $ver = Test-Copies $src $dst2
  } finally {
    if ($running.Count) {
      Head 'BAT LAI DICH VU SQL SERVER'
      $startFail = @(Start-Services $running)
    }
  }

  $dm = Measure-Folder $dst2
  L ''
  L '================ TONG KET ================'
  L ('Nguon  : {0} file, {1}' -f $m.Files, (FmtGB $m.Bytes))
  L ('Ban sao: {0} file, {1}' -f $dm.Files, (FmtGB $dm.Bytes))
  L ("File doi chieu OK          : $($ver.Good)")
  L ("File doi chieu co van de   : $($ver.Bad)")
  L ("Ma tra ve robocopy         : $rc")
  if ($startFail.Count) { L ('DICH VU CHUA BAT LAI DUOC  : ' + ($startFail -join ', ') + ' (mo services.msc de bat, hoac chay lai script nay)') }

  $logPath = Join-Path $dst 'KET_QUA_CUU_DU_LIEU.txt'
  $wrote = $true
  try { [IO.File]::WriteAllText($logPath, $script:LOG.ToString(), (New-Object System.Text.UTF8Encoding $true)) }
  catch { $wrote = $false; Say ('  [X] Khong ghi duoc ' + $logPath + ': ' + $_.Exception.Message) Red }

  $code = 0
  if ($rc -lt 0 -or $rc -ge 16) { $code = 1 }
  elseif ($rc -ge 8 -or $ver.Bad -gt 0 -or $startFail.Count -or $stopFail.Count -or -not $wrote -or $dm.Files -lt $m.Files) { $code = 3 }

  Write-Host ''
  if ($code -eq 0) {
    Say '  ===================================================================' Green
    Say '   CUU DU LIEU THANH CONG - ban sao day du va khop ma bam.' Green
    Say '  ===================================================================' Green
  } else {
    Say '  ===================================================================' Yellow
    Say '   DA CHEP NHUNG CO VAN DE - hay doc ky file KET_QUA_CUU_DU_LIEU.txt' Yellow
    Say '   (mot so file tren o hong co the khong doc duoc - dieu nay binh thuong' Yellow
    Say '    voi o dia dang loi; hay bao lai de duoc huong dan buoc tiep theo)' Yellow
    if ($startFail.Count) { Say ('   DICH VU CHUA BAT LAI: ' + ($startFail -join ', ') + ' - mo services.msc de bat.') Red }
    Say '  ===================================================================' Yellow
  }
  Write-Host ''
  Say "   Ban sao     : $dst2" White
  Say "   Nhat ky     : $logPath" White
  Say "   Log chi tiet: $rcLog" White
  Write-Host ''
  Say '   Mo lai phan mem giu xe ITS-Pro.' Cyan
  Say '   VIEC TIEP THEO: chep them ban sao nay ra mot o USB/o cung ngoai nua.' Cyan
  Say '   Du lieu chi an toan khi co it nhat 2 ban o 2 o dia khac nhau.' Cyan
  Write-Host ''
  if ($wrote) { try { Start-Process explorer.exe -ArgumentList ('/select,"' + $logPath + '"') } catch {} }
  return $code
}

if ($env:TRAMTOOL_CUU_TEST) { return }
exit (Invoke-CuuDuLieu)
