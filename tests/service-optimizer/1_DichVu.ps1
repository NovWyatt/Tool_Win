# Bài thử DichVu.ps1 bằng giả lập: dịch vụ (bảng trong bộ nhớ), sc.exe, Insider, SSD, câu trả lời.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$env:TRAMTOOL_DICHVU_TEST = '1'
. "$ToolsDir\service-optimizer\DichVu.ps1"
$ChayThu = $false; $KhongDung = $true
$script:StateFile = Join-Path $TestRoot 'ket_qua\TrangThaiGoc_TEST.json'

# ---- giả lập
$script:Svc = @{}
$script:Calls = New-Object System.Collections.ArrayList
$script:ConfigFails = @(); $script:ConfigIgnored = @(); $script:StopFails = @(); $script:StartFails = @()
function New-Svc([int]$Start, [bool]$Running, [int]$Delayed = 0) { @{ Start = $Start; Delayed = $Delayed; Running = $Running } }
function Get-SvcConfig {
    param([string]$Name)
    if (-not $script:Svc.ContainsKey($Name)) { return [pscustomobject]@{ Exists = $false; Start = -1; Delayed = 0; Running = $false } }
    $s = $script:Svc[$Name]
    return [pscustomobject]@{ Exists = $true; Start = $s.Start; Delayed = $s.Delayed; Running = $s.Running }
}
function Invoke-Sc {
    param([string[]]$Arguments)
    [void]$script:Calls.Add(($Arguments -join ' '))
    $n = $Arguments[1]
    switch ($Arguments[0]) {
        'config' {
            if ($script:ConfigFails -contains $n) { return [pscustomobject]@{ Code = 5; Output = '[SC] OpenService FAILED 5: Access is denied.' } }
            if ($script:ConfigIgnored -notcontains $n) {
                $v = $Arguments[3]
                $script:Svc[$n].Start = @{ boot = 0; system = 1; auto = 2; 'delayed-auto' = 2; demand = 3; disabled = 4 }[$v]
                $script:Svc[$n].Delayed = [int]($v -eq 'delayed-auto')
            }
            return [pscustomobject]@{ Code = 0; Output = '[SC] ChangeServiceConfig SUCCESS' }
        }
        'stop' {
            if ($script:StopFails -contains $n) { return [pscustomobject]@{ Code = 1051; Output = 'dependent services running' } }
            if (-not $script:Svc[$n].Running) { return [pscustomobject]@{ Code = 1062; Output = 'not started' } }
            $script:Svc[$n].Running = $false
            return [pscustomobject]@{ Code = 0; Output = 'STOP_PENDING' }
        }
        'start' {
            if ($script:StartFails -contains $n) { return [pscustomobject]@{ Code = 1058; Output = 'disabled' } }
            if ($script:Svc[$n].Running) { return [pscustomobject]@{ Code = 1056; Output = 'already running' } }
            $script:Svc[$n].Running = $true
            return [pscustomobject]@{ Code = 0; Output = 'START_PENDING' }
        }
    }
}
function Wait-SvcStopped { param([string]$Name) return (-not $script:Svc[$Name].Running) }
$script:Insider = $false; $script:Ssd = $true
function Test-Insider { return $script:Insider }
function Test-HasSsd { return $script:Ssd }
function Test-IsAdmin { return $true }
$script:Answers = New-Object System.Collections.Queue
function Read-YesNo { param([string]$Question, [bool]$Default = $false) if ($script:Answers.Count) { return $script:Answers.Dequeue() } return $Default }

function Reset-Case {
    $script:Svc = @{
        DiagTrack = (New-Svc 2 $true); wisvc = (New-Svc 3 $false); SysMain = (New-Svc 2 $true 1); defragsvc = (New-Svc 3 $false)
    }
    $script:Calls.Clear(); $script:ConfigFails = @(); $script:ConfigIgnored = @(); $script:StopFails = @(); $script:StartFails = @()
    $script:Insider = $false; $script:Ssd = $true; $script:Answers.Clear()
    $script:DiagTrack = $false; $script:WiSvc = $false; $script:SysMain = $false; $script:DefragSvc = $false
    if (Test-Path $script:StateFile) { Remove-Item -LiteralPath $script:StateFile -Force }
}
function Last($x) { return @($x)[-1] }
function Saved { if (Test-Path $script:StateFile) { return (Read-SavedState) } return @{} }

# 1. tắt từ trạng thái mặc định
Reset-Case
$c = Last (Invoke-Tat @('DiagTrack', 'wisvc', 'SysMain') 6>$null)
Check 'tat 3 dịch vụ: mã 0' ($c -eq 0) "mã $c"
Check 'tat: cả ba Disabled' ($script:Svc.DiagTrack.Start -eq 4 -and $script:Svc.wisvc.Start -eq 4 -and $script:Svc.SysMain.Start -eq 4)
Check 'tat: dừng dịch vụ đang chạy' (-not $script:Svc.DiagTrack.Running -and -not $script:Svc.SysMain.Running)
Check 'tat: không gọi stop cho dịch vụ đang dừng' (-not ($script:Calls -contains 'stop wisvc'))
$s = Saved
Check 'tat: lưu gốc DiagTrack tự động, đang chạy' ($s.DiagTrack.start -eq 2 -and $s.DiagTrack.running)
Check 'tat: lưu gốc SysMain tự động (trễ)' ($s.SysMain.start -eq 2 -and $s.SysMain.delayed -eq 1)
Check 'tat: lưu gốc wisvc thủ công' ($s.wisvc.start -eq 3 -and -not $s.wisvc.running)
Check 'tat: không lưu dịch vụ không chọn' (-not $s.ContainsKey('defragsvc'))

# 2. tắt lần nữa không ghi đè trạng thái gốc
$script:Calls.Clear()
$c = Last (Invoke-Tat @('DiagTrack') 6>$null)
Check 'tat lại: đã tắt rồi, mã 0, không gọi sc' ($c -eq 0 -and $script:Calls.Count -eq 0)
Check 'tat lại: trạng thái gốc giữ nguyên' ((Saved).DiagTrack.start -eq 2)

# 3. bật lại đúng như cũ
$c = Last (Invoke-BatLai @() 6>$null)
Check 'bat-lai: mã 0' ($c -eq 0) "mã $c"
Check 'bat-lai: DiagTrack tự động, chạy lại' ($script:Svc.DiagTrack.Start -eq 2 -and $script:Svc.DiagTrack.Delayed -eq 0 -and $script:Svc.DiagTrack.Running)
Check 'bat-lai: SysMain tự động (trễ)' ($script:Svc.SysMain.Start -eq 2 -and $script:Svc.SysMain.Delayed -eq 1)
Check 'bat-lai: wisvc thủ công, không chạy' ($script:Svc.wisvc.Start -eq 3 -and -not $script:Svc.wisvc.Running)
Check 'bat-lai: dùng sc config delayed-auto' ($script:Calls -contains 'config SysMain start= delayed-auto')
Check 'bat-lai xong: xoá file trạng thái gốc' (-not (Test-Path $script:StateFile))

# 4. bật lại khi chưa lưu gốc: mặc định Windows
Reset-Case; $script:Svc.DiagTrack = New-Svc 4 $false; $script:Svc.defragsvc = New-Svc 4 $false
$c = Last (Invoke-BatLai @() 6>$null)
Check 'không có gốc: DiagTrack về Tự động và chạy' ($c -eq 0 -and $script:Svc.DiagTrack.Start -eq 2 -and $script:Svc.DiagTrack.Running)
Check 'không có gốc: defragsvc về Thủ công, không chạy' ($script:Svc.defragsvc.Start -eq 3 -and -not $script:Svc.defragsvc.Running)
Check 'không đụng dịch vụ đang bật' (-not ($script:Calls -match 'SysMain|wisvc'))

# 5. bật lại chỉ một dịch vụ đã chọn
Reset-Case
[void](Invoke-Tat @('DiagTrack', 'wisvc') 6>$null)
$c = Last (Invoke-BatLai @('wisvc') 6>$null)
Check 'bat-lai chọn wisvc: chỉ đổi wisvc' ($c -eq 0 -and $script:Svc.wisvc.Start -eq 3 -and $script:Svc.DiagTrack.Start -eq 4)
Check 'bat-lai chọn wisvc: file còn DiagTrack' ((Saved).ContainsKey('DiagTrack') -and -not (Saved).ContainsKey('wisvc'))

# 6. sc config bị từ chối, hoặc báo 0 mà không đổi
Reset-Case; $script:ConfigFails = @('DiagTrack')
$c = Last (Invoke-Tat @('DiagTrack') 6>$null)
Check 'sc config lỗi: mã 1' ($c -eq 1 -and $script:Svc.DiagTrack.Start -eq 2) "mã $c"
Reset-Case; $script:ConfigIgnored = @('DiagTrack')
$c = Last (Invoke-Tat @('DiagTrack', 'wisvc') 6>$null)
Check 'sc báo 0 mà đọc lại chưa đổi: một phần, mã 3' ($c -eq 3) "mã $c"
Check 'không dừng dịch vụ chưa tắt được' ($script:Svc.DiagTrack.Running)
Reset-Case; [void](Invoke-Tat @('DiagTrack') 6>$null); $script:ConfigFails = @('DiagTrack')
$c = Last (Invoke-BatLai @() 6>$null)
Check 'bat-lai lỗi: mã 1, giữ trạng thái gốc' ($c -eq 1 -and (Saved).ContainsKey('DiagTrack')) "mã $c"

# 7. dừng/chạy không được ngay: chỉ cảnh báo
Reset-Case; $script:StopFails = @('DiagTrack')
$c = Last (Invoke-Tat @('DiagTrack') 6>$null)
Check 'không dừng được ngay: vẫn mã 0, đã Disabled' ($c -eq 0 -and $script:Svc.DiagTrack.Start -eq 4)
$script:StartFails = @('DiagTrack')
$c = Last (Invoke-BatLai @() 6>$null)
Check 'không chạy được ngay: mã 0, đã Tự động' ($c -eq 0 -and $script:Svc.DiagTrack.Start -eq 2)

# 8. Insider, defragsvc hỏi riêng (mặc định không)
Reset-Case; $script:Insider = $true
$c = Last (Invoke-Tat @('wisvc') 6>$null)
Check 'Insider, không đồng ý: bỏ qua wisvc' ($c -eq 0 -and $script:Svc.wisvc.Start -eq 3)
Reset-Case; $script:Insider = $true; $script:Answers.Enqueue($true)
$c = Last (Invoke-Tat @('wisvc') 6>$null)
Check 'Insider, đồng ý: tắt wisvc' ($c -eq 0 -and $script:Svc.wisvc.Start -eq 4)
Reset-Case
$c = Last (Invoke-Tat @('defragsvc') 6>$null)
Check 'defragsvc mặc định không tắt' ($c -eq 0 -and $script:Svc.defragsvc.Start -eq 3 -and $script:Calls.Count -eq 0)
Reset-Case; $script:Answers.Enqueue($true)
$c = Last (Invoke-Tat @('defragsvc') 6>$null)
Check 'defragsvc đồng ý: tắt' ($c -eq 0 -and $script:Svc.defragsvc.Start -eq 4)

# 9. chạy thử, file trạng thái hỏng, dịch vụ không có
Reset-Case
$c = Last (Invoke-Tat @('DiagTrack', 'SysMain') -DryRun 6>$null)
Check 'chạy thử tat: không đổi, không ghi file' ($c -eq 0 -and $script:Calls.Count -eq 0 -and -not (Test-Path $script:StateFile))
Reset-Case; $script:Svc.DiagTrack = New-Svc 4 $false
$c = Last (Invoke-BatLai @() -DryRun 6>$null)
Check 'chạy thử bat-lai: không đổi' ($c -eq 0 -and $script:Calls.Count -eq 0 -and $script:Svc.DiagTrack.Start -eq 4)
Reset-Case; New-Item -ItemType Directory -Path (Split-Path $script:StateFile) -Force | Out-Null
Set-Content -LiteralPath $script:StateFile -Value '{ hỏng' -Encoding UTF8
$c = Last (Invoke-Tat @('DiagTrack') 6>$null)
Check 'file hỏng: tat mã 1, không đổi, không ghi đè' ($c -eq 1 -and $script:Svc.DiagTrack.Start -eq 2 -and (Get-Content -LiteralPath $script:StateFile -Raw) -match 'hỏng')
$c = Last (Invoke-BatLai @() 6>$null)
Check 'file hỏng: bat-lai mã 1' ($c -eq 1)
Reset-Case; $script:Svc.Remove('wisvc')
$c = Last (Invoke-Tat @('wisvc') 6>$null)
Check 'dịch vụ không có: mã 0, không gọi sc' ($c -eq 0 -and $script:Calls.Count -eq 0)

# 10. bật lại ngoài công cụ: bỏ mục cũ trong file
Reset-Case; [void](Invoke-Tat @('DiagTrack') 6>$null); $script:Svc.DiagTrack = New-Svc 3 $false
$c = Last (Invoke-BatLai @() 6>$null)
Check 'đã bật ngoài công cụ: không đổi, bỏ mục cũ' ($c -eq 0 -and $script:Svc.DiagTrack.Start -eq 3 -and -not (Test-Path $script:StateFile))

# 11. chọn bằng tham số, kiểm tra
Reset-Case; $script:WiSvc = $true; $script:DefragSvc = $true
$n = Get-SelectedNames
Check 'Get-SelectedNames theo tham số' (($n -join ',') -eq 'wisvc,defragsvc') ($n -join ',')
Reset-Case; $n = Get-SelectedNames
Check 'Get-SelectedNames không chọn: rỗng' ($n.Count -eq 0)
Reset-Case; $script:Svc.defragsvc = New-Svc 4 $false
$c = Last (Invoke-KiemTra 6>$null)
Check 'kiem-tra mã 0' ($c -eq 0)
Check 'ConvertTo-ScStart' ((ConvertTo-ScStart 2 1) -eq 'delayed-auto' -and (ConvertTo-ScStart 2 0) -eq 'auto' -and (ConvertTo-ScStart 3) -eq 'demand')

Complete-Test
