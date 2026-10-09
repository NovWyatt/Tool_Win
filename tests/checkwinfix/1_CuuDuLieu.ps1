# Bài thử phần PowerShell của 1-CUU-DU-LIEU.bat bằng giả lập: ổ đĩa, dịch vụ SQL, đóng ứng dụng, robocopy đều là hàm giả;
# dữ liệu "cần cứu" là thư mục giả trong thư mục tạm, dấu chạy dở ghi vào HKCU\Software\TramToolTest.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$raw = [IO.File]::ReadAllText("$ToolsDir\checkwinfix\1-CUU-DU-LIEU.bat")
$mk = '#=====PS_START====='
$psFile = Join-Path $TestRoot 'cuu_extracted.ps1'
[IO.File]::WriteAllText($psFile, $raw.Substring($raw.IndexOf($mk) + $mk.Length), (New-Object Text.UTF8Encoding $true))
$env:TRAMTOOL_CUU_TEST = '1'
. $psFile
$ErrorActionPreference = 'Stop'

$box = Join-Path $TestRoot 'sandbox'
$script:MarkerKey = 'HKCU:\Software\TramToolTest\CuuDuLieu'
$script:SettleSeconds = 0


# ---- giả lập
function Get-DiskNumberOfPath {
    param([string]$Path)
    if ($Path -like "$box\D*") { return 1 }
    if ($Path -like "$box\C*") { return 1 }   # C: cùng ổ vật lý với D:
    if ($Path -like "$box\E*") { return 2 }   # USB
    return $null
}
function Get-Candidates { param($SrcDisk, [double]$Need) return , @([pscustomobject]@{ Root = "$box\E\"; Label = 'USB'; Free = 100GB; Bus = 'USB'; Disk = 2; Enough = $script:UsbEnough }) }
function Get-FreeBytes { param([string]$Path) return [double]100GB }
$script:Svc = [ordered]@{}
function Get-SqlServices { return @($script:Svc.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Status = $(if ($script:Svc[$_]) { 'Running' } else { 'Stopped' }) } }) }
$script:Log2 = New-Object System.Collections.ArrayList
$script:StopFails = @(); $script:StartFails = @()
function Stop-Svc { param([string]$Name) [void]$script:Log2.Add("stop $Name"); if ($script:StopFails -contains $Name) { return $false }; $script:Svc[$Name] = $false; return $true }
function Start-Svc { param([string]$Name) [void]$script:Log2.Add("start $Name"); if ($script:StartFails -contains $Name) { return $false }; $script:Svc[$Name] = $true; return $true }
function Stop-AppProcesses { [void]$script:Log2.Add('kill apps') }
$script:Rc = 1; $script:Corrupt = $false; $script:RoboThrows = $false
function Invoke-Robocopy {
    param([string]$Src, [string]$Dst, [string]$Log)
    [void]$script:Log2.Add('robocopy')
    if ($script:RoboThrows) { throw 'robocopy nổ' }
    Copy-Item -LiteralPath $Src -Destination $Dst -Recurse -Force
    Set-Content -LiteralPath $Log -Value 'log giả'
    if ($script:Corrupt) { $f = Join-Path $Dst 'db\ITS.mdf'; $b = [IO.File]::ReadAllBytes($f); $b[0] = $b[0] -bxor 0xFF; [IO.File]::WriteAllBytes($f, $b) }
    return $script:Rc
}
$script:HashWhileRunning = 0
function Get-Md5 {
    param([string]$Path)
    if (@($script:Svc.Values | Where-Object { $_ }).Count) { $script:HashWhileRunning++ }
    return (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash
}
$script:Opened = 0
function Start-Process { $script:Opened++ }
$script:Answers = New-Object System.Collections.Queue
function Ask {
    # Như Ask thật: trả lời rỗng thì lấy mặc định.
    param([string]$Prompt, [string]$Default = '')
    if ($script:Answers.Count) { $v = [string]$script:Answers.Dequeue(); if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() } }
    return $Default
}

function Reset-Case {
    param([string[]]$Answers = @('', 'Y'))
    if (Test-Path $box) { Remove-Item -LiteralPath $box -Recurse -Force }
    New-Item -ItemType Directory -Path "$box\D\ITS\db", "$box\E", "$box\C" -Force | Out-Null
    [IO.File]::WriteAllBytes("$box\D\ITS\db\ITS.mdf", [byte[]](1..200))
    [IO.File]::WriteAllBytes("$box\D\ITS\db\ITS_log.ldf", [byte[]](5..90))
    Set-Content -LiteralPath "$box\D\ITS\config.ini" -Value 'x=1'
    $script:DefaultSource = "$box\D\ITS"
    $script:Svc = [ordered]@{ MSSQLSERVER = $true; SQLSERVERAGENT = $true; 'MSSQL$ITS' = $true; SQLBrowser = $false }
    $script:Log2.Clear(); $script:StopFails = @(); $script:StartFails = @()
    $script:Rc = 1; $script:Corrupt = $false; $script:RoboThrows = $false; $script:HashWhileRunning = 0; $script:Opened = 0
    $script:UsbEnough = $true; $script:LOG = New-Object System.Text.StringBuilder
    $script:Answers.Clear(); foreach ($a in $Answers) { $script:Answers.Enqueue($a) }
    if (Test-Path $script:MarkerKey) { Remove-Item -LiteralPath $script:MarkerKey -Recurse -Force }
}
function Run { return @(Invoke-CuuDuLieu 6>$null)[-1] }
function Rescues { return @(Get-ChildItem -LiteralPath "$box\E" -Directory -Filter 'CUU_DU_LIEU_ITS_*' -ErrorAction SilentlyContinue) }

# 1. đường thuận
Reset-Case
$c = Run
$r = Rescues
Check 'thuận: mã 0' ($c -eq 0) "mã $c"
Check 'thuận: thư mục mới trên USB có ITS và KET_QUA' ($r.Count -eq 1 -and (Test-Path (Join-Path $r[0].FullName 'ITS\db\ITS.mdf')) -and (Test-Path (Join-Path $r[0].FullName 'KET_QUA_CUU_DU_LIEU.txt')))
$stops = @($script:Log2 | Where-Object { $_ -like 'stop *' })
Check 'thuận: dừng Agent trước engine, không dừng SQLBrowser đang dừng' (($stops -join ',') -eq 'stop SQLSERVERAGENT,stop MSSQL$ITS,stop MSSQLSERVER') ($stops -join ',')
Check 'thuận: đối chiếu MD5 lúc SQL còn dừng' ($script:HashWhileRunning -eq 0)
Check 'thuận: robocopy rồi đối chiếu trước khi bật lại' ($script:Log2.IndexOf('robocopy') -lt $script:Log2.IndexOf('start MSSQLSERVER'))
Check 'thuận: bật lại engine trước Agent, đủ 3' (($script:Log2 | Where-Object { $_ -like 'start *' }) -join ',' -eq 'start MSSQLSERVER,start MSSQL$ITS,start SQLSERVERAGENT')
Check 'thuận: SQLBrowser vẫn dừng' (-not $script:Svc.SQLBrowser)
Check 'thuận: xoá dấu dịch vụ đang dừng' (-not (Test-Path $script:MarkerKey))
Check 'thuận: mở Explorer ở kết quả' ($script:Opened -eq 1)

# 2. chạy lại: luôn thư mục mới
Start-Sleep -Milliseconds 1100
$script:Answers.Enqueue(''); $script:Answers.Enqueue('Y'); $script:Log2.Clear()
$c = Run
Check 'chạy lại: thêm một thư mục mới, không ghi chồng' ($c -eq 0 -and (Rescues).Count -eq 2)

# 3. nơi lưu cùng ổ vật lý
Reset-Case -Answers @("$box\C\Luu")
$c = Run
Check 'cùng ổ vật lý: mã 2, không dừng dịch vụ, không tạo thư mục' ($c -eq 2 -and $script:Log2.Count -eq 0 -and -not (Test-Path "$box\C\Luu"))

# 4. nơi lưu không rõ ổ vật lý
Reset-Case -Answers @("$box\X\Luu")
$c = Run
Check 'không rõ ổ, không đồng ý: mã 2' ($c -eq 2 -and $script:Log2.Count -eq 0)
Reset-Case -Answers @("$box\X\Luu", 'Y', 'Y')
$c = Run
Check 'không rõ ổ, đồng ý: chạy, mã 0' ($c -eq 0 -and (Test-Path "$box\X\Luu"))

# 5. chọn số trong danh sách, số sai
Reset-Case -Answers @('1', 'Y')
Check 'chọn số 1: mã 0' ((Run) -eq 0 -and (Rescues).Count -eq 1)
Reset-Case -Answers @('7')
Check 'số không có: mã 2' ((Run) -eq 2 -and $script:Log2.Count -eq 0)

# 6. huỷ ở bước xác nhận
Reset-Case -Answers @('', 'n')
$c = Run
Check 'huỷ: mã 2, xoá thư mục rỗng vừa tạo, không đụng dịch vụ' ($c -eq 2 -and (Rescues).Count -eq 0 -and $script:Log2.Count -eq 0)

# 7. lệch mã băm
Reset-Case; $script:Corrupt = $true
$c = Run
Check 'lệch MD5: mã 3, vẫn bật lại dịch vụ' ($c -eq 3 -and $script:Svc.MSSQLSERVER -and $script:Svc.SQLSERVERAGENT)
Check 'lệch MD5: ghi KHONG KHOP vào kết quả' ((Get-Content -LiteralPath (Join-Path (Rescues)[0].FullName 'KET_QUA_CUU_DU_LIEU.txt') -Raw) -match 'KHONG KHOP')

# 8. robocopy có file lỗi, robocopy hỏng hẳn
Reset-Case; $script:Rc = 9
Check 'robocopy 9: mã 3' ((Run) -eq 3)
Reset-Case; $script:Rc = 16
Check 'robocopy 16: mã 1' ((Run) -eq 1)

# 9. lỗi bất ngờ giữa chừng: finally vẫn bật lại dịch vụ
Reset-Case; $script:RoboThrows = $true
$threw = $false
try { [void](Invoke-CuuDuLieu 6>$null) } catch { $threw = $true }
Check 'lỗi giữa chừng: dịch vụ được bật lại, xoá dấu' ($threw -and $script:Svc.MSSQLSERVER -and $script:Svc.'MSSQL$ITS' -and -not (Test-Path $script:MarkerKey))

# 10. không bật lại được: giữ dấu, lần sau nhắc
Reset-Case; $script:StartFails = @('MSSQL$ITS')
$c = Run
$mark = @(Get-PendingMarker)
Check 'bật lại lỗi: mã 3, dấu chỉ còn dịch vụ lỗi' ($c -eq 3 -and ($mark -join ',') -eq 'MSSQL$ITS') ($mark -join ',')
$script:StartFails = @(); $script:Log2.Clear(); $script:Answers.Clear(); $script:Answers.Enqueue(''); $script:Answers.Enqueue('n')
$c = Run
Check 'lần sau: bật lại dịch vụ còn dừng trước tiên, xoá dấu' ($script:Log2[0] -eq 'start MSSQL$ITS' -and $script:Svc.'MSSQL$ITS' -and -not (Test-Path $script:MarkerKey))

# 11. cửa sổ bị đóng giữa chừng (mô phỏng: còn dấu, dịch vụ dừng)
Reset-Case -Answers @('N', '', 'n')
Set-PendingMarker @('MSSQLSERVER'); $script:Svc.MSSQLSERVER = $false
$c = Run
Check 'còn dấu, chọn N: không bật, vẫn giữ dấu' ($c -eq 2 -and -not $script:Svc.MSSQLSERVER -and (Test-Path $script:MarkerKey))

# 12. không dừng được dịch vụ
Reset-Case; $script:StopFails = @('MSSQLSERVER')
$c = Run
Check 'không dừng được: mã 3, dịch vụ khác vẫn bật lại' ($c -eq 3 -and $script:Svc.'MSSQL$ITS' -and $script:Svc.SQLSERVERAGENT)

# 13. không có USB đủ chỗ, Enter
Reset-Case -Answers @(''); $script:UsbEnough = $false
Check 'không có nơi đủ chỗ, Enter: mã 2' ((Run) -eq 2 -and $script:Log2.Count -eq 0)

# 14. không có SQL Server
Reset-Case; $script:Svc = [ordered]@{}
Check 'không có SQL: vẫn chép, mã 0, không tạo dấu' ((Run) -eq 0 -and -not (Test-Path $script:MarkerKey))

# 15. thứ tự dừng, mẫu tên dịch vụ
$o = Get-StopOrder @('SQLBrowser', 'MSSQLSERVER', 'SQLWriter', 'SQLAgent$ITS', 'MSSQL$ITS', 'MSSQLFDLauncher$ITS')
Check 'Get-StopOrder: phụ, engine, writer/browser' (($o -join ',') -eq 'MSSQLFDLauncher$ITS,SQLAgent$ITS,MSSQL$ITS,MSSQLSERVER,SQLBrowser,SQLWriter') ($o -join ',')
$names = 'MSSQLSERVER', 'MSSQL$SQLEXPRESS', 'SQLAgent$X', 'SQLWriter', 'SQLBrowser', 'MsDtsServer150', 'SQLTELEMETRY$X', 'MSSQLLaunchpad', 'Spooler', 'MSSQLSERVERX', 'wuauserv'
$hit = @($names | Where-Object { $_ -match $script:SqlPattern })
Check 'mẫu tên: bắt mọi instance, bỏ dịch vụ khác' (($hit -join ',') -eq 'MSSQLSERVER,MSSQL$SQLEXPRESS,SQLAgent$X,SQLWriter,SQLBrowser,MsDtsServer150,SQLTELEMETRY$X,MSSQLLaunchpad') ($hit -join ',')

Clear-TestRegistry
Complete-Test
