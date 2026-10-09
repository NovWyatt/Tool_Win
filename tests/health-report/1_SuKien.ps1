# Bài thử health-report: không có sự kiện thì báo [OK] chứ không phải [LOI]; tự nâng quyền và tách phần PowerShell
# chạy được khi thư mục có dấu '. Không chạy file .bat thật (sẽ hỏi UAC) và không chạy các mục kiểm tra máy.
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$Bat = Join-Path $ToolsDir 'health-report\check_health_to_desktop_fixed.bat'
$batText = [IO.File]::ReadAllText($Bat)
$marker = '### POWERSHELL_SCRIPT_' + 'BELOW ###'
$psPart = $batText.Substring($batText.LastIndexOf($marker) + $marker.Length)

# ---- 1. Hàm đọc sự kiện
Write-KT '1. Get-RecentEvents với Get-WinEvent giả' Cyan
$ps1 = Join-Path $TestRoot 'health.ps1'
[IO.File]::WriteAllText($ps1, $psPart, (New-Object Text.UTF8Encoding $true))
$env:TRAMTOOL_HEALTH_TEST = '1'
. $ps1
Remove-Item Env:\TRAMTOOL_HEALTH_TEST
$ErrorActionPreference = 'Stop'   # phần PowerShell của .bat đặt Continue
Check ([bool](Get-Command Get-RecentEvents -ErrorAction SilentlyContinue)) 'nạp được hàm (dừng trước phần chính nhờ TRAMTOOL_HEALTH_TEST)'
Check (-not (Get-Variable logPath -ErrorAction SilentlyContinue)) 'chưa chạy phần chính (không tạo báo cáo trên Desktop)'

$script:Mode = 'none'
function Get-WinEvent {
    [CmdletBinding()]
    param([hashtable]$FilterHashtable, [int]$MaxEvents)
    switch ($script:Mode) {
        'none' {
            $er = New-Object Management.Automation.ErrorRecord ((New-Object Exception 'No events were found that match the specified selection criteria.'), 'NoMatchingEventsFound', 'ObjectNotFound', $null)
            $PSCmdlet.ThrowTerminatingError($er)
        }
        'denied' {
            $er = New-Object Management.Automation.ErrorRecord ((New-Object UnauthorizedAccessException 'Attempted to perform an unauthorized operation.'), 'LogInfoUnavailable', 'NotSpecified', $null)
            $PSCmdlet.ThrowTerminatingError($er)
        }
        'some' {
            [pscustomobject]@{ TimeCreated = Get-Date; Id = 41; ProviderName = 'Microsoft-Windows-Kernel-Power'; LevelDisplayName = 'Critical'; Message = "dòng 1`r`ndòng 2" }
            [pscustomobject]@{ TimeCreated = Get-Date; Id = 6008; ProviderName = 'EventLog'; LevelDisplayName = 'Error'; Message = $null }
        }
    }
}

function Invoke-Captured([scriptblock]$Block) {
    $all = @(& $Block 6>&1)
    [pscustomobject]@{
        Items = @($all | Where-Object { $_ -isnot [Management.Automation.InformationRecord] })
        Text  = (@($all | Where-Object { $_ -is [Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData }) -join "`n")
    }
}

$r = Invoke-Captured { Get-RecentEvents @{ LogName = 'System' } 10 'Khong co loi nao.' }
Check ($r.Items.Count -eq 0) 'không có sự kiện: không trả gì'
Check ($r.Text -eq '[OK] Khong co loi nao.') "in [OK] kèm câu giải thích ($($r.Text))"

$script:Mode = 'some'
$r = Invoke-Captured { Get-RecentEvents @{ LogName = 'System' } 10 'x' }
Check ($r.Items.Count -eq 2) "có sự kiện: trả đủ 2 ($($r.Items.Count))"
Check ($r.Text -eq '') 'có sự kiện thì không in [OK]'

$script:Mode = 'denied'
$err = $null; try { [void](Get-RecentEvents @{ LogName = 'System' } 10 'x') } catch { $err = $_ }
Check ($null -ne $err -and $err.FullyQualifiedErrorId -like 'LogInfoUnavailable*') 'lỗi thật (vd thiếu quyền) vẫn ném ra để Safe-Run in [LOI]'

Write-KT '2. Safe-Run trọn một mục' Cyan
$script:Mode = 'none'
$r = Invoke-Captured { Safe-Run 'MUC THU' { Get-RecentEvents @{ LogName = 'System' } 80 'Khong co loi Critical/Error nao trong 7 ngay.' | Select-Object TimeCreated, Id | Format-Table -AutoSize } }
Check ($r.Text -notmatch '\[LOI\]') 'không có sự kiện: không còn dòng [LOI] (lỗi của bản 1.0)'
Check ($r.Text -match '\[OK\] Khong co loi Critical/Error') 'mục in [OK]'
$script:Mode = 'denied'
$r = Invoke-Captured { Safe-Run 'MUC THU' { Get-RecentEvents @{ LogName = 'System' } 80 'x' | Format-Table } }
Check ($r.Text -match '\[LOI\]') 'lỗi thật: vẫn in [LOI]'

Write-KT '3. Format-EventMessage' Cyan
Check ((Format-EventMessage $null 500) -eq '') 'sự kiện không có nội dung: chuỗi rỗng, không lỗi'
Check ((Format-EventMessage "a`r`nb" 500) -eq 'a b') 'xuống dòng thành dấu cách'
Check ((Format-EventMessage ('x' * 900) 700).Length -eq 700) 'cắt còn 700 ký tự'

Write-KT '4. Get-WinEvent thật (chỉ đọc nhật ký Application)' Cyan
Remove-Item Function:\Get-WinEvent
$r = Invoke-Captured { Get-RecentEvents @{ LogName = 'Application'; Id = 65000; StartTime = (Get-Date).AddDays(1) } 5 'Khong co su kien.' }
Check ($r.Items.Count -eq 0 -and $r.Text -eq '[OK] Khong co su kien.') "Windows này báo 'không có sự kiện' bằng mã NoMatchingEventsFound ($($r.Text))"

# ---- 5. File .bat
Write-KT '5. File .bat: đường dẫn qua biến môi trường' Cyan
Check ($batText -match '(?m)^set "SELF=%~f0"\r?$') 'đặt SELF=%~f0'
Check ($batText -notmatch "'%~f0'" -and $batText -notmatch "'%TMPPS1%'") 'không còn đường dẫn trong dấu nháy đơn (thư mục có dấu '' làm hỏng lệnh)'
$elev = @($batText -split "`r?`n" | Where-Object { $_ -match 'Verb RunAs' })
Check ($elev.Count -eq 1 -and $elev[0] -match '-FilePath \$env:SELF' -and $elev[0] -match "/danangquyen" -and $elev[0] -match 'exit 1223') 'nâng quyền: $env:SELF, đánh dấu /danangquyen, bấm No thì mã 1223'
Check ($batText -match '(?m)^fltmc >nul 2>&1') 'kiểm quyền bằng fltmc (net session cần dịch vụ Server)'
Check ($batText -match '(?s)"%RC%"=="1223".*?exit /b 2') 'từ chối UAC: thoát mã 2'
Check ($batText -notmatch 'ChatGPT') 'không còn bảo gửi file cho ChatGPT'

# Chạy đúng dòng tách phần PowerShell của .bat trong thư mục có dấu ' và dấu cách
$dir = New-TestDir "O'Brien thu muc"
$copy = Join-Path $dir 'check.bat'
[IO.File]::WriteAllText($copy, $batText)
$line = @($batText -split "`r?`n" | Where-Object { $_ -match "POWERSHELL_SCRIPT_' \+ 'BELOW" })
Check ($line.Count -eq 1) 'tìm thấy dòng tách phần PowerShell'
$runner = Join-Path $dir 'tach.bat'
[IO.File]::WriteAllText($runner, "@echo off`r`n" + $line[0] + "`r`nexit /b %errorlevel%`r`n")
$out = Join-Path $dir "ra O'Brien.ps1"
$r = Invoke-Bat $runner -Env @{ SELF = $copy; TMPPS1 = $out } -TimeoutSec 60
Check ($r.Code -eq 0) "dòng tách chạy được trong thư mục có dấu ' (mã $($r.Code) $($r.Err.Trim()))"
if (Test-Path -LiteralPath $out) {
    $bytes = [IO.File]::ReadAllBytes($out)
    Check ($bytes.Length -gt 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) 'file tách ra có BOM UTF-8'
    Check ([IO.File]::ReadAllText($out) -eq $psPart) 'nội dung đúng phần PowerShell của .bat'
} else { Check $false 'có file PowerShell tách ra' }

Complete-Test
