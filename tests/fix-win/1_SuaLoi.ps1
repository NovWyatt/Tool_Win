# Bài thử SuaLoi.ps1 bằng giả lập: DISM, SFC + CBS.log giả, netsh/ipconfig, ổ đĩa, dịch vụ, thư mục Windows giả.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$env:TRAMTOOL_SUALOI_TEST = '1'
. "$ToolsDir\fix-win\SuaLoi.ps1"
$ChayThu = $false; $KhongDung = $true; $ODia = ''; $TepSaoLuu = ''
$root = Join-Path $TestRoot 'sandbox'
$script:WinDir = Join-Path $root 'Windows'
$script:OutDir = Join-Path $root 'ket_qua'
$script:CbsLog = Join-Path $root 'CBS.log'

function Last($x) { return @($x)[-1] }

# ---- giả lập
$script:Calls = New-Object System.Collections.ArrayList
$script:NativeCodes = @{}
function Invoke-Native {
    param([string]$Exe, [string[]]$Arguments, [switch]$Show)
    $k = ($Exe -replace '\.exe$', '') + ' ' + ($Arguments -join ' ')
    [void]$script:Calls.Add($k)
    $code = 0
    foreach ($p in $script:NativeCodes.Keys) { if ($k -like $p) { $code = $script:NativeCodes[$p] } }
    if ($k -like 'netsh advfirewall export *' -and $code -eq 0 -and -not $script:ExportNoFile) { Set-Content -LiteralPath $Arguments[2] -Value 'wfw' }
    return [pscustomobject]@{ Code = $code; Output = "giả $k" }
}
$script:VisibleCode = 0; $script:CbsAppend = @()
function Invoke-Visible {
    param([string]$Exe, [string]$ArgumentLine)
    [void]$script:Calls.Add("visible $(Split-Path $Exe -Leaf) $ArgumentLine")
    if ($script:CbsAppend) {
        $t = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Add-Content -LiteralPath $script:CbsLog -Value ($script:CbsAppend | ForEach-Object { "$t, Info                  CSI    00000001 [SR] $_" })
    }
    return $script:VisibleCode
}
$script:Dism = [pscustomobject]@{ Ok = $true; State = 'Healthy'; Message = ''; HResult = 0 }
function Invoke-DismScan { [void]$script:Calls.Add('dism scan'); return $script:Dism }
function Invoke-DismRestore { [void]$script:Calls.Add('dism restore'); return $script:Dism }
$script:Manual = @()
function Get-ManualIpConfig { return , $script:Manual }
function Get-CustomFirewallRuleCount { return 7 }
$script:Health = [pscustomobject]@{ Known = $true; Healthy = $true; Text = 'Ổ giả (SSD, sức khoẻ: Healthy)' }
function Get-DiskHealth { param([string]$Letter) return $script:Health }
$script:Scan = [pscustomobject]@{ Ok = $true; Result = 'NoErrorsFound'; Message = '' }
function Invoke-VolumeScan { param([string]$Letter) [void]$script:Calls.Add("scan $Letter"); return $script:Scan }
$script:Scheduled = $true
function Test-ChkdskScheduled { param([string]$Letter) return $script:Scheduled }
$script:MemEvent = $null; $script:MemStarts = $true
function Get-LastMemTest { return $script:MemEvent }
function Start-MemTest { [void]$script:Calls.Add('mdsched'); return $script:MemStarts }
$script:Running = @{}; $script:StopFails = @(); $script:StartFails = @()
function Get-SvcRunning { param([string]$Name) return [bool]$script:Running[$Name] }
function Stop-Svc { param([string]$Name) if ($script:StopFails -contains $Name) { return $false }; $script:Running[$Name] = $false; [void]$script:Calls.Add("stop $Name"); return $true }
function Start-Svc { param([string]$Name) if ($script:StartFails -contains $Name) { return $false }; $script:Running[$Name] = $true; [void]$script:Calls.Add("start $Name"); return $true }
function Test-IsAdmin { return $true }
$script:Answers = New-Object System.Collections.Queue
function Read-YesNo { param([string]$Question, [bool]$Default = $false) if ($script:Answers.Count) { return $script:Answers.Dequeue() } return $Default }

function Reset-Case {
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    New-Item -ItemType Directory -Path (Join-Path $script:WinDir 'SoftwareDistribution\Download') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:WinDir 'System32\catroot2') -Force | Out-Null
    Set-Content -LiteralPath $script:CbsLog -Value '2020-01-01 00:00:00, Info                  CSI    00000001 [SR] Cannot repair member file cũ'
    $script:Calls.Clear(); $script:NativeCodes = @{}; $script:ExportNoFile = $false
    $script:VisibleCode = 0; $script:CbsAppend = @()
    $script:Dism = [pscustomobject]@{ Ok = $true; State = 'Healthy'; Message = ''; HResult = 0 }
    $script:Manual = @(); $script:Health = [pscustomobject]@{ Known = $true; Healthy = $true; Text = 'Ổ giả' }
    $script:Scan = [pscustomobject]@{ Ok = $true; Result = 'NoErrorsFound'; Message = '' }; $script:Scheduled = $true
    $script:MemEvent = $null; $script:MemStarts = $true
    $script:Running = @{ wuauserv = $true; bits = $true; cryptsvc = $true; msiserver = $false }; $script:StopFails = @(); $script:StartFails = @()
    $script:Answers.Clear(); $ODia = ''; $TepSaoLuu = ''
}

# 1. DISM
Reset-Case
Check 'dism-quet Healthy: 0' ((Last (Invoke-DismQuet 6>$null)) -eq 0)
$script:Dism = [pscustomobject]@{ Ok = $true; State = 'Repairable'; Message = ''; HResult = 0 }
Check 'dism-quet Repairable: vẫn 0 (kiểm tra xong)' ((Last (Invoke-DismQuet 6>$null)) -eq 0)
$script:Dism = [pscustomobject]@{ Ok = $false; State = ''; Message = 'Access denied'; HResult = 5 }
Check 'dism-quet lỗi: 1' ((Last (Invoke-DismQuet 6>$null)) -eq 1)
Reset-Case
Check 'dism-sua Healthy: 0' ((Last (Invoke-DismSua 6>$null)) -eq 0)
$script:Dism = [pscustomobject]@{ Ok = $false; State = ''; Message = 'The source files could not be found'; HResult = 0x800F081F }
Check 'dism-sua 0x800F081F: 1' ((Last (Invoke-DismSua 6>$null)) -eq 1)
$script:Dism = [pscustomobject]@{ Ok = $true; State = 'Repairable'; Message = ''; HResult = 0 }
Check 'dism-sua xong mà vẫn Repairable: 1' ((Last (Invoke-DismSua 6>$null)) -eq 1)
Reset-Case; $script:Calls.Clear()
Check 'dism-sua chạy thử: 0, không chạy' ((Last (Invoke-DismSua -DryRun 6>$null)) -eq 0 -and $script:Calls.Count -eq 0)

# 2. SFC qua CBS.log (dòng cũ trước giờ chạy không được tính)
Reset-Case; $script:CbsAppend = @('Verify complete')
Check 'sfc sạch: 0' ((Last (Invoke-SfcMode 6>$null)) -eq 0)
Reset-Case; $script:CbsAppend = @('Repairing corrupted file \??\C:\Windows\a.dll', 'Repair complete', 'Verify complete')
$c = Last (Invoke-SfcMode 6>$null)
$r = Get-SfcResult (Get-Date).AddMinutes(-1)
Check 'sfc đã sửa: 0, đếm 1 file' ($c -eq 0 -and $r.Repaired -eq 1 -and $r.Unrepaired -eq 0) "mã $c, $($r.Repaired)/$($r.Unrepaired)"
Reset-Case; $script:CbsAppend = @('Cannot repair member file [l:10]a.dll', 'Cannot repair member file [l:10]b.dll', 'Verify complete'); $script:VisibleCode = 1
Check 'sfc còn file không sửa được: 3' ((Last (Invoke-SfcMode 6>$null)) -eq 3)
Reset-Case; $script:VisibleCode = 1
Check 'sfc không chạy hết (chờ khởi động lại): 1' ((Last (Invoke-SfcMode 6>$null)) -eq 1)
Reset-Case; Remove-Item -LiteralPath $script:CbsLog; $script:VisibleCode = 0
Check 'sfc không đọc được CBS, mã 0: 0' ((Last (Invoke-SfcMode 6>$null)) -eq 0)
Reset-Case; Remove-Item -LiteralPath $script:CbsLog; $script:VisibleCode = 5
Check 'sfc không đọc được CBS, mã khác 0: 1' ((Last (Invoke-SfcMode 6>$null)) -eq 1)

# 3. DISM rồi SFC
Reset-Case; $script:CbsAppend = @('Verify complete')
$c = Last (Invoke-DismSfc 6>$null)
Check 'dism-sfc: DISM trước SFC, 0' ($c -eq 0 -and $script:Calls.IndexOf('dism restore') -lt $script:Calls.IndexOf('visible sfc.exe /scannow') -and $script:Calls.IndexOf('dism restore') -ge 0)
Reset-Case; $script:Dism = [pscustomobject]@{ Ok = $false; State = ''; Message = 'x'; HResult = 1 }; $script:CbsAppend = @('Verify complete')
Check 'dism-sfc: DISM lỗi, SFC xong: 3' ((Last (Invoke-DismSfc 6>$null)) -eq 3)

# 4. mạng: không đụng tường lửa
Reset-Case
$c = Last (Invoke-Mang 6>$null)
Check 'mang: 0, đủ 3 lệnh' ($c -eq 0 -and ($script:Calls -contains 'ipconfig /flushdns') -and ($script:Calls -contains 'netsh winsock reset') -and ($script:Calls -contains 'netsh int ip reset'))
Check 'mang: không đặt lại tường lửa' (-not ($script:Calls -match 'advfirewall'))
Reset-Case; $script:NativeCodes = @{ 'netsh int ip reset' = 1 }
Check 'mang: int ip reset lỗi: 3' ((Last (Invoke-Mang 6>$null)) -eq 3)
Reset-Case; $script:NativeCodes = @{ 'ipconfig*' = 1; 'netsh*' = 1 }
Check 'mang: mọi lệnh lỗi: 1' ((Last (Invoke-Mang 6>$null)) -eq 1)
Reset-Case; $script:Manual = @([pscustomobject]@{ Card = 'Ethernet'; Static = $true; Ip = '192.168.1.50/24'; Gateway = '192.168.1.1'; Dns = '8.8.8.8' })
$c = Last (Invoke-Mang 6>$null)
Check 'mang có IP tĩnh, không đồng ý: 2, không chạy lệnh' ($c -eq 2 -and $script:Calls.Count -eq 0)
Reset-Case; $script:Manual = @([pscustomobject]@{ Card = 'Ethernet'; Static = $true; Ip = '192.168.1.50/24'; Gateway = '192.168.1.1'; Dns = '8.8.8.8' }); $script:Answers.Enqueue($true)
$c = Last (Invoke-Mang 6>$null)
$saved = Get-ChildItem -LiteralPath $script:OutDir -Filter 'Mang_*.txt' -ErrorAction SilentlyContinue
Check 'mang có IP tĩnh, đồng ý: ghi file rồi đặt lại' ($c -eq 0 -and $saved -and (Get-Content -LiteralPath $saved[0].FullName -Raw) -match '192\.168\.1\.50')
Reset-Case
Check 'mang chạy thử: không chạy lệnh' ((Last (Invoke-Mang -DryRun 6>$null)) -eq 0 -and $script:Calls.Count -eq 0)

# 5. tường lửa: sao lưu trước, hỏi (mặc định không)
Reset-Case
$c = Last (Invoke-TuongLua 6>$null)
Check 'tuong-lua không đồng ý: 2, đã sao lưu, không reset' ($c -eq 2 -and ($script:Calls -match 'advfirewall export') -and -not ($script:Calls -contains 'netsh advfirewall reset'))
Reset-Case; $script:Answers.Enqueue($true)
$c = Last (Invoke-TuongLua 6>$null)
Check 'tuong-lua đồng ý: export rồi reset, 0' ($c -eq 0 -and $script:Calls.IndexOf('netsh advfirewall reset') -gt 0 -and ($script:Calls[0] -like 'netsh advfirewall export*'))
Reset-Case; $script:NativeCodes = @{ 'netsh advfirewall export*' = 1 }; $script:Answers.Enqueue($true)
$c = Last (Invoke-TuongLua 6>$null)
Check 'tuong-lua sao lưu lỗi: 1, không reset' ($c -eq 1 -and -not ($script:Calls -contains 'netsh advfirewall reset'))
Reset-Case; $script:ExportNoFile = $true; $script:Answers.Enqueue($true)
Check 'tuong-lua export báo 0 mà không có file: 1' ((Last (Invoke-TuongLua 6>$null)) -eq 1 -and -not ($script:Calls -contains 'netsh advfirewall reset'))
Reset-Case; $script:Answers.Enqueue($true); $script:NativeCodes = @{ 'netsh advfirewall reset' = 1 }
Check 'tuong-lua reset lỗi: 1' ((Last (Invoke-TuongLua 6>$null)) -eq 1)
Reset-Case
Check 'tuong-lua chạy thử: không gọi netsh' ((Last (Invoke-TuongLua -DryRun 6>$null)) -eq 0 -and $script:Calls.Count -eq 0)

# 6. khôi phục tường lửa
Reset-Case
Check 'khôi phục khi chưa có sao lưu: 2' ((Last (Invoke-TuongLuaKhoiPhuc 6>$null)) -eq 2)
Reset-Case; $script:Answers.Enqueue($true); [void](Invoke-TuongLua 6>$null); $script:Calls.Clear()
$c = Last (Invoke-TuongLuaKhoiPhuc 6>$null)
Check 'khôi phục bản mới nhất: import, 0' ($c -eq 0 -and ($script:Calls[0] -like 'netsh advfirewall import*TuongLua_*.wfw'))

# 7. ổ đĩa
Reset-Case
Check 'o-dia-quet sạch: 0' ((Last (Invoke-ODiaQuet 6>$null)) -eq 0 -and ($script:Calls -contains ('scan ' + $env:SystemDrive.TrimEnd(':'))))
$script:Scan = [pscustomobject]@{ Ok = $true; Result = 'SpotFixNeeded'; Message = '' }
Check 'o-dia-quet có lỗi: vẫn 0' ((Last (Invoke-ODiaQuet 6>$null)) -eq 0)
$script:Scan = [pscustomobject]@{ Ok = $false; Result = ''; Message = 'x' }
Check 'o-dia-quet lỗi: 1' ((Last (Invoke-ODiaQuet 6>$null)) -eq 1)
Reset-Case
$c = Last (Invoke-ODiaSua 6>$null)
Check 'o-dia-sua ổ Windows: hẹn bằng cmd echo Y, 0' ($c -eq 0 -and ($script:Calls -match 'visible cmd\.exe /c echo Y\| chkdsk [A-Z]: /f$'))
Reset-Case; $script:Scheduled = $false
Check 'o-dia-sua không thấy lịch: 3' ((Last (Invoke-ODiaSua 6>$null)) -eq 3)
Reset-Case; $script:Health = [pscustomobject]@{ Known = $true; Healthy = $false; Text = 'Ổ giả (HDD, sức khoẻ: Warning)' }
$c = Last (Invoke-ODiaSua 6>$null)
Check 'o-dia-sua ổ không khoẻ, không đồng ý: 2, không chạy' ($c -eq 2 -and $script:Calls.Count -eq 0)
Reset-Case; $ODia = 'Z:'; $script:VisibleCode = 1
$c = Last (Invoke-ODiaSua 6>$null)
Check 'o-dia-sua ổ khác: chkdsk Z: /f /x, mã 1 = đã sửa: 0' ($c -eq 0 -and ($script:Calls -contains 'visible chkdsk.exe Z: /f /x'))
Reset-Case; $ODia = 'z'; $script:VisibleCode = 3
Check 'o-dia-sua ổ khác mã 3: 1' ((Last (Invoke-ODiaSua 6>$null)) -eq 1)
$ODia = ''

# 8. RAM
Reset-Case
Check 'ram: mở mdsched, 0' ((Last (Invoke-Ram 6>$null)) -eq 0 -and ($script:Calls -contains 'mdsched'))
$script:MemStarts = $false
Check 'ram: không mở được, 1' ((Last (Invoke-Ram 6>$null)) -eq 1)
Reset-Case; $script:MemEvent = [pscustomobject]@{ TimeCreated = (Get-Date); Message = "Không có lỗi`r`ndòng 2"; Level = 4 }
Check 'ram: có kết quả cũ vẫn mở, 0' ((Last (Invoke-Ram 6>$null)) -eq 0)
Reset-Case; $script:Calls.Clear()
Check 'ram chạy thử: không mở' ((Last (Invoke-Ram -DryRun 6>$null)) -eq 0 -and $script:Calls.Count -eq 0)

# 9. Windows Update
Reset-Case
$c = Last (Invoke-WindowsUpdate 6>$null)
$sd = @(Get-ChildItem -LiteralPath $script:WinDir -Directory -Filter 'SoftwareDistribution*' | ForEach-Object { $_.Name })
$cr = @(Get-ChildItem -LiteralPath (Join-Path $script:WinDir 'System32') -Directory -Filter 'catroot2*' | ForEach-Object { $_.Name })
Check 'wu: 0, đổi tên có thời gian' ($c -eq 0 -and $sd.Count -eq 1 -and $sd[0] -match '^SoftwareDistribution\.old_\d{8}_\d{6}$' -and $cr[0] -match '^catroot2\.old_\d{8}_\d{6}$') "$sd $cr"
Check 'wu: chạy lại dịch vụ đã chạy, không chạy msiserver' ($script:Running.wuauserv -and $script:Running.bits -and $script:Running.cryptsvc -and -not ($script:Calls -contains 'start msiserver'))
New-Item -ItemType Directory -Path (Join-Path $script:WinDir 'SoftwareDistribution') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $script:WinDir 'System32\catroot2') -Force | Out-Null
Start-Sleep -Seconds 1
Check 'wu chạy lần hai: không trùng tên .old, 0' ((Last (Invoke-WindowsUpdate 6>$null)) -eq 0)
Reset-Case; $script:StopFails = @('cryptsvc')
$c = Last (Invoke-WindowsUpdate 6>$null)
Check 'wu: không dừng được dịch vụ: 1, không đổi tên, chạy lại dịch vụ' ($c -eq 1 -and (Test-Path (Join-Path $script:WinDir 'SoftwareDistribution')) -and $script:Running.wuauserv -and $script:Running.bits)
Reset-Case
$h = [IO.File]::Open((Join-Path $script:WinDir 'System32\catroot2\khoa.txt'), 'Create', 'ReadWrite', 'None')
try { $c = Last (Invoke-WindowsUpdate 6>$null) } finally { $h.Dispose() }
Check 'wu: catroot2 bị khoá: 3, dịch vụ vẫn chạy lại' ($c -eq 3 -and $script:Running.cryptsvc) "mã $c"
Reset-Case
Check 'wu chạy thử: không đổi' ((Last (Invoke-WindowsUpdate -DryRun 6>$null)) -eq 0 -and $script:Calls.Count -eq 0 -and (Test-Path (Join-Path $script:WinDir 'SoftwareDistribution')))

# 10. Invoke-Mode bắt lỗi lạ
function Invoke-DismScan { throw 'nổ' }
Check 'lỗi lạ: Invoke-Mode trả 1' ((Last (Invoke-Mode 'dism-quet' 6>$null)) -eq 1)

Complete-Test
