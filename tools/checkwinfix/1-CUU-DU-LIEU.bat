@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
title CUU DU LIEU KHAN CAP - o dia D: dang hong (v1.0)

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
  CUU DU LIEU KHAN CAP - copy du lieu ra khoi o dia dang hong
  Chi DOC tu nguon. Khong xoa/sua gi tren o nguon.
#>
param([string]$OutDir = "")

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function Say  { param([string]$t, [string]$c = 'Gray') Write-Host $t -ForegroundColor $c }
function Head { param([string]$t) Write-Host ''; Write-Host ('  ' + ('=' * 72)) -ForegroundColor DarkCyan; Write-Host "   $t" -ForegroundColor Cyan; Write-Host ('  ' + ('=' * 72)) -ForegroundColor DarkCyan }
function FmtGB { param($b) if ($null -eq $b) { return 'n/a' } '{0:N2} GB' -f ([double]$b / 1GB) }

$LOG = New-Object System.Text.StringBuilder
function L { param([string]$t = '') [void]$LOG.AppendLine($t); if ($t) { Say ('  ' + $t) } }

# --------------------------- 1. XAC DINH NGUON --------------------------------
Head '1/6  XAC DINH DU LIEU CAN CUU'

$src = 'D:\ITS'
if (-not (Test-Path -LiteralPath $src)) {
  Say "  Khong thay $src tren may nay." Yellow
  $src = Read-Host '  Nhap duong dan thu muc can cuu (vd D:\ITS)'
  if (-not (Test-Path -LiteralPath $src)) { Say '  [X] Duong dan khong ton tai. Dung script.' Red; exit 1 }
}
Say "  Thu muc nguon : $src" White

Say '  Dang do dung luong (co the cham vi o dia dang loi)...' DarkGray
$srcBytes = 0; $srcFiles = 0
try {
  foreach ($f in [System.IO.Directory]::EnumerateFiles($src, '*', [System.IO.SearchOption]::AllDirectories)) {
    try { $srcBytes += (New-Object System.IO.FileInfo $f).Length; $srcFiles++ } catch {}
  }
} catch {}
Say ("  Kich thuoc     : {0}  ({1} file)" -f (FmtGB $srcBytes), $srcFiles) White

Say ''
Say '  Cac thu muc khac tren o D: :' DarkGray
foreach ($d in (Get-ChildItem -LiteralPath 'D:\' -Directory -Force -ErrorAction SilentlyContinue)) {
  if ($d.Name -match '^\$RECYCLE|System Volume Information') { continue }
  Say ('    - ' + $d.FullName)
}

# --------------------------- 2. CHON DICH ------------------------------------
Head '2/6  CHON NOI LUU BAN SAO'
Say '  Tot nhat: mot o USB / o cung ngoai. Neu khong co thi luu vao o C: (SSD).' Yellow
Say ''
$defDst = 'C:\CUU_DU_LIEU_ITS_' + (Get-Date -Format 'yyyyMMdd_HHmm')
$dst = Read-Host "  Nhap noi luu (Enter de dung mac dinh: $defDst)"
if ([string]::IsNullOrWhiteSpace($dst)) { $dst = $defDst }

$dstRoot = [System.IO.Path]::GetPathRoot($dst)
$free = 0
try { $free = (Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $dstRoot.TrimEnd('\') + "'")).FreeSpace } catch {}
Say ("  Noi luu        : $dst") White
Say ("  Con trong      : {0}" -f (FmtGB $free)) White
if ($free -gt 0 -and $srcBytes -gt 0 -and $free -lt ($srcBytes * 1.1)) {
  Say '  [!] KHONG DU CHO. Hay chon o khac.' Red
  exit 1
}
if ($dstRoot -like 'D:*') { Say '  [X] Khong duoc luu nguoc lai o D: (o dang hong). Dung script.' Red; exit 1 }

try { New-Item -ItemType Directory -Path $dst -Force -ErrorAction Stop | Out-Null } catch { Say "  [X] Khong tao duoc thu muc dich: $($_.Exception.Message)" Red; exit 1 }

# --------------------------- 3. XAC NHAN -------------------------------------
Head '3/6  XAC NHAN TRUOC KHI CHAY'
Say '  Script sap lam:' White
Say '    1. Dung cac dich vu SQL Server + dong phan mem ITS-Pro'
Say '    2. Copy toan bo du lieu tu nguon sang noi luu (chi doc, khong xoa)'
Say '    3. Bat lai cac dich vu nhu cu'
Say '    4. Doi chieu ma bam (hash) cac file database de kiem tra ban sao'
Say ''
Say '  Trong luc chay, phan mem giu xe SE KHONG DUNG DUOC.' Yellow
Say ''
$ok = Read-Host '  Go Y roi Enter de bat dau (bat ky phim khac = huy)'
if ($ok -ne 'Y' -and $ok -ne 'y') { Say '  Da huy.' Yellow; exit 0 }

L ('CUU DU LIEU - ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
L ("Nguon : $src")
L ("Dich  : $dst")
L ''

# --------------------------- 4. DUNG DICH VU ---------------------------------
Head '4/6  DUNG DICH VU SQL SERVER VA PHAN MEM ITS'

$svcNames = @('MSSQLFDLauncher', 'SQLSERVERAGENT', 'MsDtsServer110', 'MSSQLServerOLAPService', 'MSSQLSERVER', 'SQLWriter', 'SQLBrowser')
$svcState = @{}
foreach ($n in $svcNames) {
  $s = Get-Service -Name $n -ErrorAction SilentlyContinue
  if (-not $s) { continue }
  $svcState[$n] = $s.Status
  if ($s.Status -eq 'Running') {
    L "Dung dich vu: $n"
    try { Stop-Service -Name $n -Force -ErrorAction Stop; L "   -> da dung" } catch { L "   -> KHONG dung duoc: $($_.Exception.Message)" }
  } else {
    L ("Dich vu {0}: dang {1}, bo qua" -f $n, $s.Status)
  }
}

foreach ($pn in @('ITS-Pro', 'Ssms', 'sqlservr')) {
  $ps = @(Get-Process -Name $pn -ErrorAction SilentlyContinue)
  foreach ($p in $ps) {
    L "Dong tien trinh: $pn (PID $($p.Id))"
    try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { L "   -> khong dong duoc: $($_.Exception.Message)" }
  }
}
Start-Sleep -Seconds 3

# --------------------------- 5. COPY -----------------------------------------
Head '5/6  DANG COPY DU LIEU (khong tat cua so nay)'
Say '  Neu o dia gap sector hong, robocopy se bao loi va bo qua file do' DarkGray
Say '  roi di tiep - dung lo, cuoi cung se co danh sach file khong cuu duoc.' DarkGray
Say ''

$rcLog = Join-Path $dst 'robocopy_log.txt'
$leaf  = Split-Path $src -Leaf
if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = 'DU_LIEU' }
$dst2  = Join-Path $dst $leaf
$common = @('/E', '/COPY:DAT', '/DCOPY:DAT', '/R:1', '/W:1', '/XJ', '/NP', '/TEE', ('/LOG+:' + $rcLog))
$rcArgs = @($src, $dst2, '/B') + $common
$t0 = Get-Date
& robocopy.exe @rcArgs | Out-Null
$rc = $LASTEXITCODE
if ($rc -ge 16) {
  L "Robocopy loi nghiem trong (ma $rc). Thu lai khong dung che do Backup (/B)..."
  Say '  [!] Thu lai khong dung che do Backup...' Yellow
  $rcArgs = @($src, $dst2) + $common
  & robocopy.exe @rcArgs | Out-Null
  $rc = $LASTEXITCODE
}
$dur = (Get-Date) - $t0
L ''
L ("Robocopy ket thuc sau {0:N0} giay, ma tra ve = {1}" -f $dur.TotalSeconds, $rc)
if ($rc -lt 8) { Say ("  [OK] Copy xong sau {0:N0} giay (ma {1})." -f $dur.TotalSeconds, $rc) Green }
else { Say ("  [!] Copy xong nhung CO FILE LOI (ma {0}). Xem robocopy_log.txt." -f $rc) Yellow }

$failed = @()
try {
  $failed = @(Get-Content -LiteralPath $rcLog -ErrorAction Stop | Where-Object { $_ -match 'ERROR \d+ \(' -or $_ -match '0x0000045D|0x00000017|0x0000001F' })
} catch {}
if ($failed.Count -gt 0) {
  L ''
  L "CAC LOI KHI COPY ($($failed.Count) dong):"
  foreach ($l in ($failed | Select-Object -First 40)) { L ('   ' + $l.Trim()) }
}

# --------------------------- 6. BAT LAI + KIEM TRA ---------------------------
Head '6/6  BAT LAI DICH VU VA KIEM TRA BAN SAO'

foreach ($n in @('SQLWriter', 'MSSQLSERVER', 'MSSQLServerOLAPService', 'MsDtsServer110', 'SQLSERVERAGENT', 'MSSQLFDLauncher', 'SQLBrowser')) {
  if (-not $svcState.ContainsKey($n)) { continue }
  if ($svcState[$n] -ne 'Running') { continue }
  L "Bat lai dich vu: $n"
  try { Start-Service -Name $n -ErrorAction Stop; L '   -> da bat' } catch { L "   -> KHONG bat duoc: $($_.Exception.Message)" }
}

L ''
L 'DOI CHIEU MA BAM (hash) CAC FILE DATABASE:'
$checked = 0; $good = 0; $bad = 0
$dbFiles = @(Get-ChildItem -LiteralPath $src -Recurse -Force -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Extension -match '(?i)^\.(mdf|ldf|ndf|bak)$' })
if ($dbFiles.Count -eq 0) {
  L '   (khong co file .mdf/.ldf/.bak - doi chieu 30 file bat ky thay the)'
  $dbFiles = @(Get-ChildItem -LiteralPath $src -Recurse -Force -File -ErrorAction SilentlyContinue |
               Sort-Object Length -Descending | Select-Object -First 30)
}
foreach ($f in $dbFiles) {
  if ($f.Length -gt 4GB) { L ("   BO QUA (qua lon): " + $f.Name); continue }
  $rel = $f.FullName.Substring($src.Length).TrimStart('\')
  $cp  = Join-Path $dst2 $rel
  if (-not (Test-Path -LiteralPath $cp)) { L ("   THIEU BAN SAO : $rel"); $bad++; continue }
  $checked++
  $h1 = $null; $h2 = $null
  try { $h1 = (Get-FileHash -LiteralPath $f.FullName -Algorithm MD5 -ErrorAction Stop).Hash } catch { L ("   KHONG DOC DUOC NGUON: $rel  ($($_.Exception.Message))") }
  try { $h2 = (Get-FileHash -LiteralPath $cp -Algorithm MD5 -ErrorAction Stop).Hash } catch {}
  if ($h1 -and $h2 -and $h1 -eq $h2) { L ("   OK            : $rel  ({0})" -f (FmtGB $f.Length)); $good++ }
  else { L ("   KHONG KHOP    : $rel"); $bad++ }
}
if ($checked -eq 0) { L '   (khong co file nao de doi chieu)' }

# --------------------------- TONG KET ----------------------------------------
$dstBytes = 0; $dstFiles = 0
try {
  foreach ($f in [System.IO.Directory]::EnumerateFiles($dst2, '*', [System.IO.SearchOption]::AllDirectories)) {
    try { $dstBytes += (New-Object System.IO.FileInfo $f).Length; $dstFiles++ } catch {}
  }
} catch {}

L ''
L '================ TONG KET ================'
L ("Nguon : {0} file, {1}" -f $srcFiles, (FmtGB $srcBytes))
L ("Ban sao: {0} file, {1}" -f $dstFiles, (FmtGB $dstBytes))
L ("File database doi chieu OK : $good")
L ("File database co van de    : $bad")
L ("Ma tra ve robocopy         : $rc")

$logPath = Join-Path $dst 'KET_QUA_CUU_DU_LIEU.txt'
[IO.File]::WriteAllText($logPath, $LOG.ToString(), (New-Object System.Text.UTF8Encoding $true))

Write-Host ''
if ($bad -eq 0 -and $rc -lt 8 -and $dstFiles -ge $srcFiles) {
  Say '  ===================================================================' Green
  Say '   CUU DU LIEU THANH CONG - ban sao day du va khop ma bam.' Green
  Say '  ===================================================================' Green
} else {
  Say '  ===================================================================' Yellow
  Say '   DA COPY XONG NHUNG CO VAN DE - hay doc ky file KET_QUA_CUU_DU_LIEU.txt' Yellow
  Say '   (mot so file tren o hong co the khong doc duoc - dieu nay binh thuong' Yellow
  Say '    voi o dia dang loi; hay bao lai de duoc huong dan buoc tiep theo)' Yellow
  Say '  ===================================================================' Yellow
}
Write-Host ''
Say ("   Ban sao   : $dst2") White
Say ("   Nhat ky   : $logPath") White
Say ("   Log chi tiet: $rcLog") White
Write-Host ''
Say '   VIEC TIEP THEO: chep them ban sao nay ra mot o USB/o cung ngoai nua.' Cyan
Say '   Du lieu chi an toan khi co it nhat 2 ban o 2 o dia khac nhau.' Cyan
Write-Host ''
try { Start-Process explorer.exe -ArgumentList ('/select,"' + $logPath + '"') } catch {}
exit 0
