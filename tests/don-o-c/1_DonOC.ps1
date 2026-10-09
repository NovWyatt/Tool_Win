# Giả lập cho tools\don-o-c: Get-KnownDirs trỏ vào thư mục cát (sandbox) trong tests\.tam, chỉ xoá ở đó.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$tool = "$ToolsDir\don-o-c"
$script:ToolDir = Join-Path $TestRoot 'tooldir'
$script:ToolVersion = 'test'
. "$tool\lib\Chung.ps1"; . "$tool\lib\Muc.ps1"; . "$tool\lib\Don.ps1"; . "$tool\lib\KiemTra.ps1"
$script:Modes = [ordered]@{
    'kiem-tra' = @{ No = 1; Label = 'kt'; Admin = 'no'; Log = '' }
    'don-cua-toi' = @{ No = 2; Label = 'dct'; Admin = 'no'; Log = 'x' }
    'don-he-thong' = @{ No = 3; Label = 'dht'; Admin = 'yes'; Log = 'x' }
}
$script:NoPause = $true

$sb = Join-Path $TestRoot 'sb'

# ---- thư mục chuẩn giả
function Get-KnownDirs {
    [pscustomobject]@{ Local = "$sb\Users\u\AppData\Local"; Roaming = "$sb\Users\u\AppData\Roaming"; Windows = "$sb\Windows"; Data = "$sb\ProgramData"; Temp = $script:FakeTemp; Drive = 'C:' }
}
$script:FakeTemp = "$sb\Users\u\AppData\Local\Temp"
function Get-DriveInfo { [pscustomobject]@{ Name = 'C:'; Size = 100GB; Free = 10GB } }
function Test-SameUser { $script:SameUser }
$script:SameUser = $true
function Test-IsAdmin { $script:Admin }
$script:Admin = $true
function Get-RunningApps { param($Apps) @($script:Running | Where-Object { $l = $_.Label; @($Apps | Where-Object { $_.Label -eq $l }).Count }) }
$script:Running = @()
$script:Answers = New-Object System.Collections.Queue
function Read-Choice { param([string]$Prompt, [string[]]$Keys, [string]$Fallback) if ($script:Answers.Count) { return $script:Answers.Dequeue() } return $Fallback }
function Test-RebootPending { $script:Reboot }
$script:Reboot = $false
function Test-UpdateInstalling { $script:Installing }
$script:Installing = $false
$script:DOBytes = [int64]50MB; $script:DOCleared = 0
function Get-DOCacheBytes { $script:DOBytes }
function Clear-DOCache { $script:DOCleared++; $script:DOBytes = 0 }

$old = 30; $now = 0
function New-F {
    param([string]$Path, [int]$Days = 30, [int]$Size = 1000, [int]$CreateDays = -1, [switch]$ReadOnly)
    if ($CreateDays -lt 0) { $CreateDays = $Days }
    $d = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    [IO.File]::WriteAllBytes($Path, (New-Object byte[] $Size))
    $f = Get-Item -LiteralPath $Path
    $f.CreationTime = (Get-Date).AddDays(-$CreateDays)
    $f.LastWriteTime = (Get-Date).AddDays(-$Days)
    if ($ReadOnly) { $f.Attributes = 'ReadOnly' }
}
function Set-DirAge { param([string]$Path, [int]$Days) (Get-Item -LiteralPath $Path).CreationTime = (Get-Date).AddDays(-$Days) }

function Reset-Sandbox {
    if (Test-Path -LiteralPath "$sb\Users\u\AppData\Local\Temp\link") { [IO.Directory]::Delete("$sb\Users\u\AppData\Local\Temp\link", $false) }
    if (Test-Path -LiteralPath $sb) { Remove-Item -LiteralPath $sb -Recurse -Force }
    $t = "$sb\Users\u\AppData\Local\Temp"
    New-F "$t\old1.tmp" 30 1000
    New-F "$t\old2.log" 10 2000
    New-F "$t\new.tmp" 1 4000
    New-F "$t\oldwrite-newcreate.dat" 30 8000 -CreateDays 1
    New-F "$t\ro.tmp" 30 500 -ReadOnly
    New-F "$t\sub\deep\a.tmp" 30 100
    New-F "$t\sub\deep\b.tmp" 30 100
    Set-DirAge "$t\sub\deep" 30; Set-DirAge "$t\sub" 30
    New-F "$t\mix\keep-new.tmp" 0 100
    New-F "$t\mix\old.tmp" 30 100
    Set-DirAge "$t\mix" 30
    [void](New-Item -ItemType Directory -Path "$t\emptynew" -Force)
    New-F "$sb\Outside\keep.txt" 30 300
    [void](New-Item -ItemType Junction -Path "$t\link" -Target "$sb\Outside")
    New-F "$t\locked.tmp" 30 700
    # trình duyệt
    $ch = "$sb\Users\u\AppData\Local\Google\Chrome\User Data"
    New-F "$ch\Local State" 30 10
    New-F "$ch\ShaderCache\data_0" 0 1000
    New-F "$ch\Default\Preferences" 30 10
    New-F "$ch\Default\History" 30 10
    New-F "$ch\Default\Login Data" 30 10
    New-F "$ch\Default\Cache\Cache_Data\f_000001" 0 5000
    New-F "$ch\Default\Cache\Cache_Data\index" 0 50
    New-F "$ch\Default\Code Cache\js\abc" 0 3000
    New-F "$ch\Default\Service Worker\CacheStorage\x" 30 900
    New-F "$ch\Profile 1\Preferences" 30 10
    New-F "$ch\Profile 1\GPUCache\data_1" 0 700
    New-F "$ch\System Profile\Cache\zzz" 0 600
    $ff = "$sb\Users\u\AppData\Local\Mozilla\Firefox\Profiles\abc.default-release"
    New-F "$ff\cache2\entries\E1" 0 1200
    New-F "$ff\cache2\index" 0 20
    New-F "$sb\Users\u\AppData\Local\CrashDumps\app.exe.123.dmp" 30 9000
    New-F "$sb\Users\u\AppData\Local\Microsoft\Windows\WER\ReportArchive\r1\Report.wer" 30 100
    # Windows
    $w = "$sb\Windows"
    New-F "$w\Temp\old.tmp" 30 1000
    New-F "$w\Temp\new.tmp" 1 1000
    New-F "$w\SoftwareDistribution\Download\abc\update.cab" 30 5000
    New-F "$w\Logs\CBS\CbsPersist_20260901.log" 30 3000
    New-F "$w\Logs\CBS\CbsPersist_20261008.log" 1 3000
    New-F "$w\Logs\CBS\CBS.log" 30 3000
    New-F "$w\MEMORY.DMP" 30 6000
    New-F "$w\notepad.exe" 30 100
    New-F "$w\LiveKernelReports\WATCHDOG\WD-1.dmp" 30 2000
    New-F "$w\LiveKernelReports\WATCHDOG\notes.txt" 30 50
    New-F "$w\Minidump\100126-1.dmp" 30 300
    New-F "$sb\ProgramData\Microsoft\Windows\WER\ReportQueue\q1\Report.wer" 30 100
}

try {
    Reset-Sandbox
    $t = "$sb\Users\u\AppData\Local\Temp"
    $cut = (Get-Date).AddDays(-7)

    # ---- T1 Test-SafeRoot
    Check 'T1a temp ok' ((Test-SafeRoot $t) -eq '')
    Check 'T1b temp sub ok' ((Test-SafeRoot "$t\sub") -eq '')
    Check 'T1c drive root no' ((Test-SafeRoot 'C:\') -ne '')
    Check 'T1d users no' ((Test-SafeRoot "$sb\Users\u") -ne '')
    Check 'T1e windows recurse no' ((Test-SafeRoot "$sb\Windows") -ne '')
    Check 'T1f windows memory.dmp only' ((Test-SafeRoot "$sb\Windows" 'MEMORY.DMP' $true) -eq '')
    Check 'T1g windows * no' ((Test-SafeRoot "$sb\Windows" '*' $true) -ne '')
    Check 'T1h cbs * no' ((Test-SafeRoot "$sb\Windows\Logs\CBS" '*' $true) -ne '')
    Check 'T1i cbs persist ok' ((Test-SafeRoot "$sb\Windows\Logs\CBS" 'CbsPersist_*' $true) -eq '')
    Check 'T1j dotdot no' ((Test-SafeRoot "$t\..\..\Roaming") -ne '')
    Check 'T1k unc no' ((Test-SafeRoot '\\server\share\Temp') -ne '')
    Check 'T1l relative no' ((Test-SafeRoot 'Temp') -ne '')
    Check 'T1m system32 no' ((Test-SafeRoot "$sb\Windows\System32") -ne '')
    Check 'T1n prefix trick no' ((Test-SafeRoot "$sb\Users\u\AppData\Local\TempX") -ne '')
    Check 'T1o cbs recurse no' ((Test-SafeRoot "$sb\Windows\Logs\CBS" 'CbsPersist_*' $false) -ne '')
    $threw = $false; try { [void](Invoke-Sweep -Root "$sb\Users\u" -Cutoff $cut) } catch { $threw = $true }
    Check 'T1p sweep refuses' $threw

    # ---- T2 đếm, rồi xoá
    $fs = [IO.File]::Open("$t\locked.tmp", 'Open', 'ReadWrite', 'None')
    $m = Invoke-Sweep -Root $t -Cutoff $cut
    # cũ: old1 1000, old2 2000, ro 500, a 100, b 100, mix\old 100, locked 700 = 4500 (không tính file trong junction)
    Check 'T2a count bytes' ($m.Bytes -eq 4500) "bytes=$($m.Bytes)"
    Check 'T2b count files' ($m.Files -eq 7) "files=$($m.Files)"
    Check 'T2c link counted' ($m.Links -eq 1) "links=$($m.Links)"
    Check 'T2d nothing deleted when counting' ((Test-Path "$t\old1.tmp") -and (Test-Path "$t\sub\deep\a.tmp"))
    $d = Invoke-Sweep -Root $t -Cutoff $cut -Delete
    $fs.Close()
    Check 'T2e deleted bytes (locked excluded)' ($d.Bytes -eq 3800) "bytes=$($d.Bytes)"
    Check 'T2f locked counted' ($d.Locked -eq 1 -and $d.LockedBytes -eq 700) "locked=$($d.Locked)"
    Check 'T2g locked file kept' (Test-Path "$t\locked.tmp")
    Check 'T2h old gone' (-not (Test-Path "$t\old1.tmp") -and -not (Test-Path "$t\old2.log") -and -not (Test-Path "$t\ro.tmp"))
    Check 'T2i new kept' (Test-Path "$t\new.tmp")
    Check 'T2j new creation kept' (Test-Path "$t\oldwrite-newcreate.dat")
    Check 'T2k old empty dirs removed' (-not (Test-Path "$t\sub"))
    Check 'T2l dir with new file kept' ((Test-Path "$t\mix\keep-new.tmp") -and -not (Test-Path "$t\mix\old.tmp"))
    Check 'T2m new empty dir kept' (Test-Path "$t\emptynew")
    Check 'T2n junction target untouched' (Test-Path "$sb\Outside\keep.txt")
    Check 'T2o junction kept' (Test-Path "$t\link")
    Check 'T2p root kept' (Test-Path $t)

    # ---- T3 trình duyệt
    $b = @(Get-Browsers)
    Check 'T3a browsers found' ($b.Count -eq 2 -and $b[0].Id -eq 'chrome' -and $b[1].Id -eq 'firefox') ($b.Id -join ',')
    $cd = @(Get-BrowserCacheDirs $b[0])
    $names = @($cd | ForEach-Object { $_.Substring($b[0].Root.Length + 1) })
    Check 'T3b chrome dirs' (($names -join '|') -eq 'ShaderCache|Default\Cache|Default\Code Cache|Profile 1\GPUCache') ($names -join '|')
    $fd = @(Get-BrowserCacheDirs $b[1])
    Check 'T3c firefox cache2' ($fd.Count -eq 1 -and $fd[0] -like '*\cache2')
    $items = @(Get-UserItems)
    Check 'T3d user items' ((($items | ForEach-Object { $_.Id }) -join ',') -eq 'temp,loi-ung-dung,trinh-duyet-chrome,trinh-duyet-firefox') (($items | ForEach-Object { $_.Id }) -join ',')
    $chItem = $items | Where-Object { $_.Id -eq 'trinh-duyet-chrome' }
    $mc = Measure-CleanItem $chItem $cut
    Check 'T3e chrome measure all ages' ($mc.Bytes -eq (1000 + 5000 + 50 + 3000 + 700)) "bytes=$($mc.Bytes)"
    $x = Invoke-CleanItem $chItem $cut
    $ch = "$sb\Users\u\AppData\Local\Google\Chrome\User Data"
    Check 'T3f chrome cleaned' ($x.Bytes -eq 9750 -and -not (Test-Path "$ch\Default\Cache\Cache_Data\f_000001")) "bytes=$($x.Bytes)"
    Check 'T3g cache folder itself kept' (Test-Path "$ch\Default\Cache")
    Check 'T3h profile data kept' ((Test-Path "$ch\Default\History") -and (Test-Path "$ch\Default\Login Data") -and (Test-Path "$ch\Default\Preferences") -and (Test-Path "$ch\Local State"))
    Check 'T3i service worker kept' (Test-Path "$ch\Default\Service Worker\CacheStorage\x")
    Check 'T3j non-profile kept' (Test-Path "$ch\System Profile\Cache\zzz")

    # ---- T4 TEMP lạ
    $script:FakeTemp = 'D:\SomewhereElse\Temp'
    $it = @(Get-UserItems)[0]
    Check 'T4a temp elsewhere skipped' ($it.Skip -ne '')
    $script:FakeTemp = "$sb\Users\u\AppData\Local\Temp"
    Check 'T4b temp default ok' (@(Get-UserItems)[0].Skip -eq '')

    # ---- T5 Invoke-Cleanup: chạy thử, thôi, dọn
    Reset-Sandbox
    $script:Report.Clear()
    $r = Invoke-DonCuaToi -SoNgay 7 -DryRun
    Check 'T5a dryrun 0' ($r -eq 0) "r=$r"
    Check 'T5b dryrun no delete' ((Test-Path "$t\old1.tmp") -and (Test-Path "$ch\Default\Cache\Cache_Data\f_000001"))
    $script:Answers.Clear(); $script:Answers.Enqueue('K')
    $r = Invoke-DonCuaToi -SoNgay 7
    Check 'T5c K -> 1223' ($r -eq 1223) "r=$r"
    Check 'T5d K no delete' (Test-Path "$t\old1.tmp")
    $script:Answers.Clear(); $script:Answers.Enqueue('C')
    $r = Invoke-DonCuaToi -SoNgay 7
    Check 'T5e C -> 0' ($r -eq 0) "r=$r"
    Check 'T5f C deleted' (-not (Test-Path "$t\old1.tmp") -and -not (Test-Path "$ch\Default\Cache\Cache_Data\f_000001") -and -not (Test-Path "$sb\Users\u\AppData\Local\CrashDumps\app.exe.123.dmp"))
    Check 'T5g C kept new' ((Test-Path "$t\new.tmp") -and (Test-Path "$ch\Default\History"))
    $txt = $script:Report -join "`n"
    Check 'T5h report total' ($txt -match 'Đã dọn')

    # ---- T6 trình duyệt đang mở, chọn B
    Reset-Sandbox
    $script:Running = @([pscustomobject]@{ Label = 'Google Chrome'; Processes = @(); Windows = 1 })
    function Close-Apps { param($Apps, [string]$Why) $script:CloseAsked++; return @('Google Chrome') }
    $script:CloseAsked = 0
    $script:Answers.Clear(); $script:Answers.Enqueue('C')
    $r = Invoke-DonCuaToi -SoNgay 7
    Check 'T6a asked close' ($script:CloseAsked -eq 1)
    Check 'T6b chrome skipped' (Test-Path "$ch\Default\Cache\Cache_Data\f_000001")
    Check 'T6c firefox cleaned' (-not (Test-Path "$sb\Users\u\AppData\Local\Mozilla\Firefox\Profiles\abc.default-release\cache2\entries\E1"))
    Check 'T6d temp cleaned' (-not (Test-Path "$t\old1.tmp"))
    $script:Running = @()

    # ---- T7 sai tài khoản
    $script:SameUser = $false
    $r = Invoke-DonCuaToi -SoNgay 7 -DryRun
    Check 'T7 wrong user -> 2' ($r -eq 2) "r=$r"
    $script:SameUser = $true

    # ---- T8 dọn hệ thống
    Reset-Sandbox
    $w = "$sb\Windows"
    $script:Admin = $false
    $r = Invoke-DonHeThong -SoNgay 7
    Check 'T8a not admin -> 2' ($r -eq 2) "r=$r"
    $script:Admin = $true
    $script:Reboot = $true
    $si = @(Get-SystemItems)
    Check 'T8b wu skipped when reboot pending' (($si | Where-Object { $_.Id -eq 'windows-update' }).Skip -ne '')
    Check 'T8c no dump item by default' (-not @($si | Where-Object { $_.Id -eq 'dump-loi' }).Count)
    $script:Answers.Clear(); $script:Answers.Enqueue('C')
    $script:DOBytes = [int64]50MB; $script:DOCleared = 0
    $r = Invoke-DonHeThong -SoNgay 7
    Check 'T8d result 0' ($r -eq 0) "r=$r"
    Check 'T8e win temp old gone, new kept' (-not (Test-Path "$w\Temp\old.tmp") -and (Test-Path "$w\Temp\new.tmp"))
    Check 'T8f wu kept (reboot pending)' (Test-Path "$w\SoftwareDistribution\Download\abc\update.cab")
    Check 'T8g cbs persist old gone, others kept' (-not (Test-Path "$w\Logs\CBS\CbsPersist_20260901.log") -and (Test-Path "$w\Logs\CBS\CbsPersist_20261008.log") -and (Test-Path "$w\Logs\CBS\CBS.log"))
    Check 'T8h DO cleared' ($script:DOCleared -eq 1)
    Check 'T8i wer queue gone' (-not (Test-Path "$sb\ProgramData\Microsoft\Windows\WER\ReportQueue\q1\Report.wer"))
    Check 'T8j memory.dmp kept without DumpLoi' (Test-Path "$w\MEMORY.DMP")
    $script:Reboot = $false
    $script:Answers.Clear(); $script:Answers.Enqueue('C')
    $r = Invoke-DonHeThong -SoNgay 7 -DumpLoi
    Check 'T8k dump: memory.dmp gone' (-not (Test-Path "$w\MEMORY.DMP"))
    Check 'T8l dump: livekernel dmp gone, txt kept' (-not (Test-Path "$w\LiveKernelReports\WATCHDOG\WD-1.dmp") -and (Test-Path "$w\LiveKernelReports\WATCHDOG\notes.txt"))
    Check 'T8m minidump kept' (Test-Path "$w\Minidump\100126-1.dmp")
    Check 'T8n other windows files kept' (Test-Path "$w\notepad.exe")
    Check 'T8o wu cleaned when no reboot' (-not (Test-Path "$w\SoftwareDistribution\Download\abc\update.cab"))
    $script:Installing = $true
    Check 'T8p wu skipped while installing' ((@(Get-SystemItems) | Where-Object { $_.Id -eq 'windows-update' }).Skip -ne '')
    $script:Installing = $false

    # ---- T9 DO lỗi -> mã 3
    Reset-Sandbox
    function Clear-DOCache { throw 'boom' }
    $script:DOBytes = [int64]10MB
    $script:Answers.Clear(); $script:Answers.Enqueue('C')
    $r = Invoke-DonHeThong -SoNgay 7
    Check 'T9 DO error -> 3' ($r -eq 3) "r=$r"
    function Clear-DOCache { $script:DOCleared++; $script:DOBytes = 0 }

    # ---- T10 WinSxS
    $yes = @"
Deployment Image Servicing and Management tool
Version: 10.0.26100.1

Image Version: 10.0.26300.1

[==========================100.0%==========================]

Component Store (WinSxS) information:

Windows Explorer Reported Size of Component Store : 9.21 GB

Actual Size of Component Store : 8.93 GB

    Shared with Windows : 5.81 GB
    Backups and Disabled Features : 2.78 GB
    Cache and Temporary Data :  346.22 MB

Date of Last Cleanup : 2026-09-01 10:11:12

Number of Reclaimable Packages : 2
Component Store Cleanup Recommended : Yes

The operation completed successfully.
"@
    $p = Read-ComponentStoreReport $yes
    Check 'T10a parse' ($p.Found -and $p.Recommended -and $p.Packages -eq 2 -and $p.Actual -eq '8.93 GB' -and $p.Cache -eq '346.22 MB') ($p | Out-String)
    $script:DismOut = $yes; $script:DismCode = 0; $script:LiveArgs = $null; $script:LiveCode = 0
    function Invoke-Dism { param([string[]]$Arguments) $script:DismArgs = $Arguments; [pscustomobject]@{ Code = $script:DismCode; Output = $script:DismOut } }
    function Start-DismLive { param([string[]]$Arguments) $script:LiveArgs = $Arguments; $script:LiveCode }
    $r = Invoke-DonWinSxS -DryRun
    Check 'T10b dryrun no cleanup' ($r -eq 0 -and $null -eq $script:LiveArgs)
    $script:Answers.Clear(); $script:Answers.Enqueue('K')
    $r = Invoke-DonWinSxS
    Check 'T10c K -> 1223' ($r -eq 1223 -and $null -eq $script:LiveArgs) "r=$r"
    $script:Answers.Clear(); $script:Answers.Enqueue('C')
    $r = Invoke-DonWinSxS
    Check 'T10d C runs StartComponentCleanup' ($r -eq 0 -and ($script:LiveArgs -join ' ') -eq '/Online /Cleanup-Image /StartComponentCleanup') ($script:LiveArgs -join ' ')
    Check 'T10e never ResetBase' (($script:LiveArgs -join ' ') -notmatch 'ResetBase')
    $script:LiveCode = 3010; $script:LiveArgs = $null
    $script:Answers.Clear(); $script:Answers.Enqueue('C')
    $r = Invoke-DonWinSxS
    Check 'T10f 3010 -> 0' ($r -eq 0) "r=$r"
    $script:LiveCode = 5
    $script:Answers.Clear(); $script:Answers.Enqueue('C')
    $r = Invoke-DonWinSxS
    Check 'T10g error -> 1' ($r -eq 1) "r=$r"
    $script:DismOut = $yes.Replace('Recommended : Yes', 'Recommended : No'); $script:LiveArgs = $null
    $r = Invoke-DonWinSxS
    Check 'T10h not recommended -> 0, no cleanup' ($r -eq 0 -and $null -eq $script:LiveArgs)
    $script:DismCode = 87; $script:DismOut = 'Error: 87'
    $r = Invoke-DonWinSxS
    Check 'T10i analyze error -> 1' ($r -eq 1) "r=$r"
    $script:Admin = $false
    $r = Invoke-DonWinSxS -DryRun
    Check 'T10j not admin -> 2' ($r -eq 2) "r=$r"
    $script:Admin = $true
    $script:Reboot = $true
    $script:DismCode = 0; $script:DismOut = $yes
    $r = Invoke-DonWinSxS
    Check 'T10k reboot pending -> 2' ($r -eq 2) "r=$r"
    $script:Reboot = $false

    # ---- T11 Format-Size
    Check 'T11a' ((Format-Size 0) -eq '0 KB')
    Check 'T11b' ((Format-Size 1500) -eq '2 KB') (Format-Size 1500)
    Check 'T11c' ((Format-Size (5MB)) -match '^5 MB$') (Format-Size (5MB))
    Check 'T11d' ((Format-Size (1.5GB)) -match '^1[.,]5 GB$') (Format-Size (1.5GB))

    # ---- T12 Kiểm tra (đo trong cát)
    Reset-Sandbox
    $script:Report.Clear(); $script:Findings.Clear()
    $r = Invoke-KiemTra -SoNgay 7
    $txt = $script:Report -join "`n"
    Check 'T12a kiem-tra 0' ($r -eq 0) "r=$r"
    Check 'T12b no deletion' ((Test-Path "$t\old1.tmp") -and (Test-Path "$ch\Default\Cache\Cache_Data\f_000001") -and (Test-Path "$sb\Windows\MEMORY.DMP"))
    Check 'T12c sections' ($txt -match 'Rác của bạn' -and $txt -match 'Rác của Windows' -and $txt -match 'KẾT LUẬN')

    # ---- T13 File kết quả cho Trạm Tool (chuẩn tramtool.ketqua/1)
    $kq = Join-Path $TestRoot 'kq'
    $env:DOC_KET_QUA = $kq
    Add-Finding -Ma 'THUNG_RAC' info 'Thùng rác: 3 GB' -Hint 'Mở Thùng rác.' -Bytes 3GB -ChiKetQua
    Add-Finding -Ma 'WINDOWS_OLD' info 'Windows.old: 20 GB' -Hint 'Settings.' -Bytes 20GB -ChiKetQua
    Check 'T13a ChiKetQua: không in, không vào báo cáo' (($script:Report -join "`n") -notmatch 'Windows\.old: 20 GB')
    $f = Save-RunResult -CheDo 'kiem-tra' -Code 0 -Start (Get-Date)
    $j = [IO.File]::ReadAllText($f) | ConvertFrom-Json
    $mas = @($j.phatHien | ForEach-Object { $_.ma })
    Check 'T13b file theo chuẩn' ($j.chuan -eq 'tramtool.ketqua/1' -and $j.congCu -eq 'don-o-c' -and $j.cheDo -eq 'kiem-tra' -and (Split-Path $f -Leaf) -like "KetQua_DonOC_KiemTra_$($env:COMPUTERNAME)_*.json") (Split-Path $f -Leaf)
    Check 'T13c ổ còn ít chỗ lên đầu, không kết luận ổn' ($mas[0] -eq 'O_IT_CHO_TRONG' -and $mas -notcontains 'DU_CHO_TRONG') ($mas -join ',')
    $wi = [array]::IndexOf($mas, 'WINDOWS_OLD'); $tr = [array]::IndexOf($mas, 'THUNG_RAC')
    Check 'T13d cùng mức: mục lớn lên trước' ($wi -ge 0 -and $tr -gt $wi) ($mas -join ',')
    Check 'T13e mã đúng dạng' (-not @($mas | Where-Object { $_ -notmatch '^[A-Z][A-Z0-9_]+$' }).Count) ($mas -join ',')
    Reset-Sandbox
    $script:Report.Clear(); $script:Findings.Clear()
    $r = Invoke-DonCuaToi -SoNgay 7 -DryRun
    $d = @($script:Findings | Where-Object { $_.Ma -in 'DON_DUOC', 'KHONG_CO_GI_DE_DON' })
    Check 'T13f chạy thử dọn: ghi dọn được bao nhiêu cho file kết quả' ($r -eq 0 -and $d.Count -eq 1) "r=$r"
    $script:SameUser = $false; $script:Findings.Clear()
    $r = Invoke-DonCuaToi -SoNgay 7 -DryRun
    Check 'T13g sai tài khoản: mã 2, SAI_TAI_KHOAN' ($r -eq 2 -and @($script:Findings | Where-Object { $_.Ma -eq 'SAI_TAI_KHOAN' -and $_.Level -eq 'bad' }).Count -eq 1) "r=$r"
    $script:SameUser = $true
    Remove-Item Env:DOC_KET_QUA
    # Mọi chỗ ghi phát hiện có -Ma: chuỗi CHU_HOA, hoặc $r.Ma của mục chiếm chỗ (mã đặt khi dựng danh sách mục).
    $bad = @(); $cnt = 0
    foreach ($fn in 'KiemTra.ps1', 'Don.ps1') {
        $ast = [Management.Automation.Language.Parser]::ParseFile("$tool\lib\$fn", [ref]$null, [ref]$null)
        foreach ($c in @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Add-Finding' }, $true))) {
            $cnt++
            $e = @($c.CommandElements)
            $k = -1; for ($i = 1; $i -lt $e.Count; $i++) { if ($e[$i] -is [Management.Automation.Language.CommandParameterAst] -and $e[$i].ParameterName -eq 'Ma') { $k = $i } }
            $v = if ($k -ge 0) { $e[$k + 1] } else { $null }
            if (-not (($v -is [Management.Automation.Language.StringConstantExpressionAst] -and $v.Value -match '^[A-Z][A-Z0-9_]+$') -or ($v -and $v.Extent.Text -eq '$r.Ma'))) { $bad += "$fn`:$($c.Extent.StartLineNumber)" }
        }
    }
    $src = [IO.File]::ReadAllText("$tool\lib\KiemTra.ps1")
    $rowCodes = @([regex]::Matches($src, "& \`$add '([A-Z_]+)'|Ma = '([A-Z_]+)'") | ForEach-Object { if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } })
    Check 'T13h mọi chỗ ghi phát hiện có -Ma' ($cnt -ge 20 -and $bad.Count -eq 0) ("$cnt chỗ; thiếu: " + ($bad -join ', '))
    Check 'T13i mục chiếm chỗ có mã' ($rowCodes.Count -ge 9 -and $src -match "'THU_MUC_TAI_VE'" -and $src -match "'DU_LIEU_CA_NHAN'") ($rowCodes -join ',')
} finally {
    if (Test-Path -LiteralPath "$sb\Users\u\AppData\Local\Temp\link") { [IO.Directory]::Delete("$sb\Users\u\AppData\Local\Temp\link", $false) }
}
Complete-Test
