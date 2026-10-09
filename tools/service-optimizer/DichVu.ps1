<#
  Tắt/bật dịch vụ nền: DiagTrack (telemetry), Windows Insider (wisvc), SysMain, Tối ưu ổ đĩa (defragsvc).
  Bản 1.0 coi "đang dừng" là "đã tắt", giấu lỗi 'sc config' rồi báo thành công, và "bật lại" ghi giá trị cố định.
  Bản này xét kiểu khởi động (Services\<tên>\Start), lưu kiểu khởi động gốc ra ket_qua\TrangThaiGoc_<máy>.json
  trước khi tắt, "bật lại" trả đúng giá trị đó, và đọc lại sau mỗi lần đổi thay vì tin mã thoát.

  Không có -Mode: hiện menu (bấm đúp TAT_BAT_DICH_VU.bat). -Mode <chế độ>: chạy thẳng (Trạm Tool dùng cách này).
  Chế độ: kiem-tra (chỉ đọc, không cần Admin), tat, bat-lai.
  Chọn dịch vụ: -DiagTrack -WiSvc -SysMain -DefragSvc. Không chọn: "tat" hỏi từng dịch vụ, "bat-lai" xét cả bốn.
  -ChayThu: chỉ in việc sẽ làm, không đổi máy. -KhongDung: không chờ Enter khi xong.
  Mã thoát: 0 xong, 1 lỗi, 2 thiếu điều kiện (quyền Admin), 3 làm được một phần.
#>
param(
    [string]$Mode = '',
    [switch]$DiagTrack,
    [switch]$WiSvc,
    [switch]$SysMain,
    [switch]$DefragSvc,
    [switch]$ChayThu,
    [switch]$KhongDung,
    [switch]$DaNangQuyen   # đánh dấu cửa sổ đã mở lại bằng quyền Admin, để không hỏi UAC lần nữa
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:ServicesKey = 'HKLM:\SYSTEM\CurrentControlSet\Services'
$script:StateFile = Join-Path $PSScriptRoot ("ket_qua\TrangThaiGoc_{0}.json" -f $env:COMPUTERNAME)
# Default: kiểu khởi động mặc định của Windows 10/11 (2 tự động, 3 thủ công), dùng khi chưa lưu trạng thái gốc.
$script:Services = [ordered]@{
    DiagTrack = @{ Switch = 'DiagTrack'; Label = 'Gửi dữ liệu chẩn đoán cho Microsoft (DiagTrack, telemetry)'; Default = 2; Suggest = $true
                   Note = 'Tắt thì bớt gửi dữ liệu sử dụng về Microsoft; Windows Update, Store vẫn chạy bình thường.' }
    wisvc     = @{ Switch = 'WiSvc'; Label = 'Chương trình Windows Insider (wisvc)'; Default = 3; Suggest = $true
                   Note = 'Chỉ cần khi máy nhận bản Windows thử nghiệm (Insider).' }
    SysMain   = @{ Switch = 'SysMain'; Label = 'SysMain (nạp sẵn ứng dụng hay dùng vào RAM)'; Default = 2; Suggest = $false
                   Note = 'Nên để bật trên phần lớn máy; chỉ tắt khi ổ cứng HDD thường chạy 100% hoặc RAM rất ít (4 GB trở xuống).' }
    defragsvc = @{ Switch = 'DefragSvc'; Label = 'Tối ưu ổ đĩa (defragsvc)'; Default = 3; Suggest = $false
                   Note = 'Dịch vụ này chạy TRIM định kỳ cho SSD; tắt lâu ngày SSD chậm đi. Không nên tắt.' }
}
$script:Modes = [ordered]@{
    'kiem-tra' = @{ No = 1; Label = 'Xem trạng thái các dịch vụ' }
    'tat'      = @{ No = 2; Label = 'Tắt dịch vụ (chọn từng cái)' }
    'bat-lai'  = @{ No = 3; Label = 'Bật lại như trước khi tắt' }
}

# ---------------------------------------------------------------- in ra, hỏi
function Write-Head { param([string]$Text) Write-Host ''; Write-Host ("== $Text " + ('=' * [Math]::Max(3, 68 - $Text.Length))) -ForegroundColor Cyan }
function Write-Line { param([string]$Text) Write-Host "  $Text" }
function Write-Sub { param([string]$Text) Write-Host "       $Text" -ForegroundColor Gray }
function Write-Ok { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Write-Bad { param([string]$Text) Write-Host "  [X]  $Text" -ForegroundColor Red }
function Write-Info { param([string]$Text) Write-Host "  [i]  $Text" -ForegroundColor Gray }
function Write-Plan { param([string]$Text) Write-Host "   ->  $Text" -ForegroundColor White }

function Read-Text {
    param([string]$Prompt, [string]$Default = '')
    if ([Console]::IsInputRedirected) { return $Default }
    $a = ([string](Read-Host "  $Prompt")).Trim()
    if (-not $a) { return $Default }
    return $a
}

function Read-YesNo {
    # Không có bàn phím (chạy tự động) thì trả mặc định thay vì treo.
    param([string]$Question, [bool]$Default = $false)
    if ([Console]::IsInputRedirected) { return $Default }
    $hint = if ($Default) { '[C/k]' } else { '[c/K]' }
    while ($true) {
        $a = ([string](Read-Host "  $Question $hint")).Trim().ToLowerInvariant()
        if (-not $a) { return $Default }
        if ($a -in 'c', 'co', 'có', 'y', 'yes') { return $true }
        if ($a -in 'k', 'khong', 'không', 'n', 'no') { return $false }
        Write-Host '  Gõ C (có) hoặc K (không).' -ForegroundColor Yellow
    }
}

function Wait-Close {
    param([string]$Text = 'Bấm Enter để đóng cửa sổ')
    if ($KhongDung -or [Console]::IsInputRedirected) { return }
    Write-Host ''
    [void](Read-Host "  $Text")
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------- dịch vụ
function Get-SvcConfig {
    # Kiểu khởi động đọc từ registry (người dùng thường đọc được), trạng thái chạy từ Get-Service.
    param([string]$Name)
    $item = Get-ItemProperty -LiteralPath (Join-Path $script:ServicesKey $Name) -ErrorAction SilentlyContinue
    if (-not $item -or $null -eq $item.PSObject.Properties['Start']) { return [pscustomobject]@{ Exists = $false; Start = -1; Delayed = 0; Running = $false } }
    $delayed = 0
    if ($item.PSObject.Properties['DelayedAutostart']) { $delayed = [int]$item.DelayedAutostart }
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Exists = $true; Start = [int]$item.Start; Delayed = $delayed; Running = [bool]($svc -and $svc.Status -eq 'Running') }
}

function Format-Start {
    param([int]$Start, [int]$Delayed = 0)
    switch ($Start) {
        0 { 'Boot' } 1 { 'System' }
        2 { if ($Delayed) { 'Tự động (trễ)' } else { 'Tự động' } }
        3 { 'Thủ công' } 4 { 'Đã tắt' }
        default { "không rõ ($Start)" }
    }
}

function ConvertTo-ScStart {
    # Giá trị cho 'sc config <tên> start= ...'.
    param([int]$Start, [int]$Delayed = 0)
    switch ($Start) {
        0 { 'boot' } 1 { 'system' }
        2 { if ($Delayed) { 'delayed-auto' } else { 'auto' } }
        3 { 'demand' } 4 { 'disabled' }
        default { throw "Kiểu khởi động không hợp lệ: $Start" }
    }
}

function Invoke-Sc {
    # Chạy sc.exe, trả mã thoát và chữ in ra (để báo lỗi đúng lời Windows).
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $out = & (Join-Path $env:SystemRoot 'System32\sc.exe') @Arguments 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = ((@($out) | ForEach-Object { [string]$_ }) -join ' ').Trim() }
}

function Wait-SvcStopped {
    param([string]$Name, [int]$Seconds = 15)
    try { (Get-Service -Name $Name -ErrorAction Stop).WaitForStatus('Stopped', [TimeSpan]::FromSeconds($Seconds)); return $true }
    catch { return $false }
}

function Test-Insider {
    # Máy đang nhận bản Windows thử nghiệm thì tắt wisvc sẽ ngừng nhận bản mới.
    $a = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\WindowsSelfHost\Applicability' -ErrorAction SilentlyContinue
    if (-not $a) { return $false }
    $branch = if ($a.PSObject.Properties['BranchName']) { [string]$a.BranchName } else { '' }
    $preview = if ($a.PSObject.Properties['EnablePreviewBuilds']) { [int]$a.EnablePreviewBuilds } else { 0 }
    return [bool]($branch.Trim() -or $preview -gt 0)
}

function Test-HasSsd {
    try { return [bool](@(Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.MediaType -eq 'SSD' }).Count) }
    catch { return $false }
}

# ---------------------------------------------------------------- trạng thái gốc
function Read-SavedState {
    # Trả name -> @{ start; delayed; running; luuLuc }. File hỏng thì báo lỗi, không ghi đè.
    $map = @{}
    if (-not (Test-Path -LiteralPath $script:StateFile)) { return $map }
    try { $json = [IO.File]::ReadAllText($script:StateFile) | ConvertFrom-Json }
    catch { throw "File trạng thái gốc bị hỏng: $script:StateFile. Đổi tên hoặc chép file đó đi chỗ khác rồi chạy lại." }
    if ($json -and $json.dichVu) {
        foreach ($p in $json.dichVu.PSObject.Properties) {
            $v = $p.Value
            $map[$p.Name] = @{ start = [int]$v.start; delayed = [int]$v.delayed; running = [bool]$v.running; luuLuc = [string]$v.luuLuc }
        }
    }
    return $map
}

function Save-SavedState {
    param([hashtable]$Map)
    if (-not $Map.Count) {
        if (Test-Path -LiteralPath $script:StateFile) { Remove-Item -LiteralPath $script:StateFile -Force }
        return
    }
    $dir = Split-Path -Parent $script:StateFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $svc = [ordered]@{}
    foreach ($k in ($Map.Keys | Sort-Object)) { $svc[$k] = [ordered]@{ start = $Map[$k].start; delayed = $Map[$k].delayed; running = $Map[$k].running; luuLuc = $Map[$k].luuLuc } }
    $doc = [ordered]@{ may = $env:COMPUTERNAME; ghiChu = 'Kiểu khởi động trước khi công cụ Tắt/bật dịch vụ nền tắt; Bật lại dùng file này.'; dichVu = $svc }
    $tmp = "$script:StateFile.tmp"
    [IO.File]::WriteAllText($tmp, ($doc | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $script:StateFile -Force
}

# ---------------------------------------------------------------- chế độ
function Get-SelectedNames {
    $names = @()
    foreach ($n in $script:Services.Keys) {
        $sw = $script:Services[$n].Switch
        if ((Get-Variable -Name $sw -Scope Script -ValueOnly -ErrorAction SilentlyContinue)) { $names += $n }
    }
    return , $names
}

function Invoke-KiemTra {
    Write-Head 'Trạng thái dịch vụ nền'
    $saved = @{}
    try { $saved = Read-SavedState } catch { Write-Warn $_.Exception.Message }
    $changed = 0
    foreach ($n in $script:Services.Keys) {
        $s = $script:Services[$n]; $c = Get-SvcConfig $n
        Write-Line ''
        Write-Line $s.Label
        if (-not $c.Exists) { Write-Info 'Máy này không có dịch vụ này.'; continue }
        $line = 'Kiểu khởi động: {0} (mặc định Windows: {1}); {2}.' -f (Format-Start $c.Start $c.Delayed), (Format-Start $s.Default), $(if ($c.Running) { 'đang chạy' } else { 'đang dừng' })
        if ($c.Start -eq 4) { Write-Warn $line; $changed++ } else { Write-Ok $line }
        if ($saved.ContainsKey($n)) { Write-Sub ('Trạng thái gốc đã lưu: {0} (lưu lúc {1}). "Bật lại" trả về giá trị này.' -f (Format-Start $saved[$n].start $saved[$n].delayed), $saved[$n].luuLuc) }
        elseif ($c.Start -eq 4) { Write-Sub ('Chưa lưu trạng thái gốc: "Bật lại" sẽ trả về mặc định của Windows ({0}).' -f (Format-Start $s.Default)) }
        Write-Sub $s.Note
    }
    Write-Line ''
    if ((Get-SvcConfig 'defragsvc').Start -eq 4 -and (Test-HasSsd)) { Write-Warn 'Máy có SSD mà Tối ưu ổ đĩa đang tắt: SSD không được TRIM định kỳ. Nên bật lại.' }
    if ((Get-SvcConfig 'wisvc').Start -eq 4 -and (Test-Insider)) { Write-Warn 'Máy đang nhận bản Windows Insider mà wisvc đang tắt: có thể ngừng nhận bản mới.' }
    if ($changed) { Write-Info "$changed dịch vụ đang tắt." } else { Write-Info 'Không dịch vụ nào đang tắt.' }
    Write-Info "File trạng thái gốc: $script:StateFile"
    return 0
}

function Select-Services {
    # Hỏi từng dịch vụ trong cửa sổ (khi chưa chọn bằng tham số).
    $names = @()
    foreach ($n in $script:Services.Keys) {
        $s = $script:Services[$n]; $c = Get-SvcConfig $n
        if (-not $c.Exists) { continue }
        Write-Line ''
        Write-Line ('{0}: {1}' -f $s.Label, (Format-Start $c.Start $c.Delayed))
        Write-Sub $s.Note
        if ($c.Start -eq 4) { Write-Sub 'Đã tắt rồi.'; continue }
        if (Read-YesNo 'Tắt dịch vụ này?' $s.Suggest) { $names += $n }
    }
    return , $names
}

function Invoke-Tat {
    param([string[]]$Names, [switch]$DryRun, [switch]$Ask)
    Write-Head 'Tắt dịch vụ nền'
    $list = New-Object System.Collections.ArrayList
    foreach ($n in $Names) {
        $c = Get-SvcConfig $n
        if (-not $c.Exists) { Write-Info "$n`: máy này không có dịch vụ này."; continue }
        if ($c.Start -eq 4) { Write-Ok ('{0}: đã tắt rồi.' -f $script:Services[$n].Label); continue }
        if ($n -eq 'wisvc' -and (Test-Insider)) {
            Write-Warn 'Máy đang nhận bản Windows Insider: tắt wisvc thì có thể ngừng nhận bản mới.'
            if (-not (Read-YesNo 'Vẫn tắt Windows Insider (wisvc)?' $false)) { Write-Info 'Bỏ qua wisvc.'; continue }
        }
        if ($n -eq 'defragsvc') {
            Write-Warn 'Tối ưu ổ đĩa chạy TRIM định kỳ cho SSD: tắt lâu ngày SSD chậm đi.'
            if (-not (Read-YesNo 'Vẫn tắt Tối ưu ổ đĩa (defragsvc)?' $false)) { Write-Info 'Bỏ qua defragsvc.'; continue }
        }
        [void]$list.Add([pscustomobject]@{ Name = $n; Config = $c })
    }
    if (-not $list.Count) { Write-Info 'Không có dịch vụ nào cần tắt.'; return 0 }

    Write-Line ''
    Write-Line 'Sẽ làm:'
    foreach ($it in $list) {
        Write-Plan ('Lưu kiểu khởi động hiện tại của {0} ({1}) để bật lại đúng như cũ' -f $it.Name, (Format-Start $it.Config.Start $it.Config.Delayed))
        Write-Plan "sc config $($it.Name) start= disabled"
        if ($it.Config.Running) { Write-Plan "sc stop $($it.Name)" }
    }
    if ($DryRun) { Write-Info 'Chạy thử: không đổi gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo 'Làm các việc trên?' $false)) { Write-Info 'Đã huỷ, chưa đổi gì.'; return 0 }

    # Lưu trạng thái gốc trước khi đổi; không lưu được thì không đổi.
    try {
        $saved = Read-SavedState
        $now = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        foreach ($it in $list) { $saved[$it.Name] = @{ start = $it.Config.Start; delayed = $it.Config.Delayed; running = $it.Config.Running; luuLuc = $now } }
        Save-SavedState $saved
        Write-Ok "Đã lưu trạng thái gốc vào $script:StateFile"
    } catch {
        Write-Bad ('Không lưu được trạng thái gốc nên chưa đổi gì: {0}' -f $_.Exception.Message.Trim())
        return 1
    }

    $done = 0; $fail = 0
    foreach ($it in $list) {
        $n = $it.Name
        $r = Invoke-Sc @('config', $n, 'start=', 'disabled')
        $after = Get-SvcConfig $n
        if ($r.Code -ne 0 -or $after.Start -ne 4) {
            Write-Bad ('{0}: chưa tắt được (sc config mã {1}; kiểu khởi động bây giờ: {2}). {3}' -f $n, $r.Code, (Format-Start $after.Start $after.Delayed), $r.Output)
            $fail++; continue
        }
        Write-Ok "$n`: đã đặt kiểu khởi động Đã tắt."
        $done++
        if ($it.Config.Running) {
            $s = Invoke-Sc @('stop', $n)
            if (($s.Code -eq 0 -or $s.Code -eq 1062) -and (Wait-SvcStopped $n)) { Write-Ok "$n`: đã dừng." }
            else { Write-Warn ('{0}: chưa dừng được ngay (sc stop mã {1}); sau khi khởi động lại máy sẽ không chạy nữa.' -f $n, $s.Code) }
        }
    }
    Write-Line ''
    if ($fail -and $done) { Write-Warn 'Tắt được một phần, xem các dòng [X] ở trên.'; return 3 }
    if ($fail) { return 1 }
    Write-Info 'Muốn trả lại như cũ: chạy "Bật lại như trước khi tắt".'
    return 0
}

function Invoke-BatLai {
    param([string[]]$Names, [switch]$DryRun, [switch]$Ask)
    Write-Head 'Bật lại dịch vụ nền'
    if (-not $Names -or -not $Names.Count) { $Names = @($script:Services.Keys) }
    try { $saved = Read-SavedState } catch { Write-Bad $_.Exception.Message; return 1 }
    $list = New-Object System.Collections.ArrayList
    $stale = @()
    foreach ($n in $Names) {
        $c = Get-SvcConfig $n
        if (-not $c.Exists) { continue }
        if ($c.Start -ne 4) {
            Write-Ok ('{0}: đang bật ({1}), không cần đổi.' -f $script:Services[$n].Label, (Format-Start $c.Start $c.Delayed))
            if ($saved.ContainsKey($n)) { $stale += $n }   # đã được bật lại ngoài công cụ
            continue
        }
        if ($saved.ContainsKey($n)) {
            $t = $saved[$n]; $why = "trạng thái gốc lưu lúc $($t.luuLuc)"
        } else {
            $t = @{ start = $script:Services[$n].Default; delayed = 0; running = ($script:Services[$n].Default -eq 2) }
            $why = 'chưa lưu trạng thái gốc nên dùng mặc định của Windows'
        }
        [void]$list.Add([pscustomobject]@{ Name = $n; Target = $t; Why = $why })
    }
    if (-not $list.Count) {
        if ($stale.Count -and -not $DryRun) { foreach ($n in $stale) { $saved.Remove($n) }; try { Save-SavedState $saved } catch { } }
        Write-Info 'Không có dịch vụ nào cần bật lại.'
        return 0
    }

    Write-Line ''
    Write-Line 'Sẽ làm:'
    foreach ($it in $list) {
        Write-Plan ('sc config {0} start= {1}   ({2}: {3})' -f $it.Name, (ConvertTo-ScStart $it.Target.start $it.Target.delayed), $it.Why, (Format-Start $it.Target.start $it.Target.delayed))
        if ($it.Target.running) { Write-Plan "sc start $($it.Name)" }
    }
    if ($DryRun) { Write-Info 'Chạy thử: không đổi gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo 'Làm các việc trên?' $false)) { Write-Info 'Đã huỷ, chưa đổi gì.'; return 0 }

    $done = 0; $fail = 0
    foreach ($it in $list) {
        $n = $it.Name; $t = $it.Target
        $r = Invoke-Sc @('config', $n, 'start=', (ConvertTo-ScStart $t.start $t.delayed))
        $after = Get-SvcConfig $n
        $match = $after.Start -eq $t.start -and ($t.start -ne 2 -or [bool]$after.Delayed -eq [bool]$t.delayed)
        if ($r.Code -ne 0 -or -not $match) {
            Write-Bad ('{0}: chưa bật lại được (sc config mã {1}; kiểu khởi động bây giờ: {2}). {3}' -f $n, $r.Code, (Format-Start $after.Start $after.Delayed), $r.Output)
            $fail++; continue
        }
        Write-Ok ('{0}: đã trả kiểu khởi động về {1}.' -f $n, (Format-Start $t.start $t.delayed))
        $done++
        $saved.Remove($n)
        if ($t.running) {
            $s = Invoke-Sc @('start', $n)
            if ($s.Code -eq 0 -or $s.Code -eq 1056) { Write-Ok "$n`: đang chạy." }
            else { Write-Warn ('{0}: chưa chạy được ngay (sc start mã {1}); Windows sẽ chạy nó ở lần khởi động sau.' -f $n, $s.Code) }
        }
    }
    foreach ($n in $stale) { $saved.Remove($n) }
    try { Save-SavedState $saved } catch { Write-Warn ('Không cập nhật được file trạng thái gốc: {0}' -f $_.Exception.Message.Trim()) }
    Write-Line ''
    if ($fail -and $done) { Write-Warn 'Bật lại được một phần, xem các dòng [X] ở trên.'; return 3 }
    if ($fail) { return 1 }
    return 0
}

function Invoke-Mode {
    param([string]$Id, [switch]$Ask)
    try {
        switch ($Id) {
            'kiem-tra' { return (Invoke-KiemTra) }
            'tat' {
                $names = Get-SelectedNames
                if (-not $names.Count) {
                    if ([Console]::IsInputRedirected) { Write-Bad 'Chưa chọn dịch vụ nào (-DiagTrack, -WiSvc, -SysMain, -DefragSvc).'; return 1 }
                    $names = Select-Services
                    if (-not $names.Count) { Write-Info 'Không chọn dịch vụ nào, chưa đổi gì.'; return 0 }
                }
                return (Invoke-Tat $names -DryRun:$ChayThu -Ask:$Ask)
            }
            'bat-lai' { return (Invoke-BatLai (Get-SelectedNames) -DryRun:$ChayThu -Ask:$Ask) }
        }
    } catch {
        Write-Bad ('Lỗi không lường trước: {0}' -f $_.Exception.Message.Trim())
        return 1
    }
}

function Invoke-Elevated {
    # Mở lại chính script này bằng quyền Admin (Windows hỏi UAC), chờ xong, trả mã thoát. Chỉ một lần.
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-DaNangQuyen')
    if ($Mode) { $parts += @('-Mode', $Mode) }
    foreach ($n in $script:Services.Keys) {
        $sw = $script:Services[$n].Switch
        if ((Get-Variable -Name $sw -Scope Script -ValueOnly -ErrorAction SilentlyContinue)) { $parts += "-$sw" }
    }
    if ($KhongDung) { $parts += '-KhongDung' }
    try { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList ($parts -join ' ') -Verb RunAs -Wait -PassThru }
    catch {
        $e = $_.Exception; $native = 0
        while ($e) { if ($e -is [ComponentModel.Win32Exception]) { $native = $e.NativeErrorCode; break }; $e = $e.InnerException }
        if ($native -eq 1223) { Write-Warn 'Bạn đã chọn "Không" ở hộp thoại quyền Admin nên chưa chạy.'; return 2 }
        Write-Bad "Không mở được bằng quyền Admin: $($_.Exception.Message.Trim())"
        return 1
    }
    try { return [int]$p.ExitCode } catch { return 0 }
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '  TẮT/BẬT DỊCH VỤ NỀN' -ForegroundColor Cyan
        Write-Host '  Tắt thì lưu kiểu khởi động cũ; Bật lại trả đúng như trước khi tắt.' -ForegroundColor Gray
        Write-Host ''
        foreach ($id in $script:Modes.Keys) { Write-Host ('   {0}. {1}' -f $script:Modes[$id].No, $script:Modes[$id].Label) }
        Write-Host '   0. Thoát'
        Write-Host ''
        $c = Read-Text 'Chọn số' '0'
        if ($c -eq '0') { return 0 }
        $id = $null
        foreach ($k in $script:Modes.Keys) { if ([string]$script:Modes[$k].No -eq $c) { $id = $k } }
        if (-not $id) { continue }
        [void](Invoke-Mode $id -Ask)
        Wait-Close 'Bấm Enter để về menu'
    }
}

# ---------------------------------------------------------------- bắt đầu
if ($env:TRAMTOOL_DICHVU_TEST) { return }   # bài thử nạp các hàm rồi tự gọi
try { $Host.UI.RawUI.WindowTitle = 'Tắt/bật dịch vụ nền' } catch { }
if ($Mode -and -not $script:Modes.Contains($Mode)) {
    Write-Bad ('Không có chế độ "{0}". Các chế độ: {1}.' -f $Mode, (@($script:Modes.Keys) -join ', '))
    Wait-Close
    exit 1
}
if ($Mode -ne 'kiem-tra' -and -not $ChayThu -and -not (Test-IsAdmin)) {
    if ($DaNangQuyen) { Write-Bad 'Đã mở lại mà vẫn chưa có quyền Admin.'; Wait-Close; exit 2 }
    Write-Info 'Đổi kiểu khởi động dịch vụ cần quyền Admin: Windows sẽ hỏi (UAC), chọn "Có".'
    exit (Invoke-Elevated)
}
if (-not $Mode) {
    if ([Console]::IsInputRedirected) { Write-Host 'Cách dùng: DichVu.ps1 -Mode kiem-tra|tat|bat-lai [-DiagTrack] [-WiSvc] [-SysMain] [-DefragSvc] [-ChayThu]'; exit 1 }
    exit (Show-Menu)
}
$code = Invoke-Mode $Mode
Wait-Close
exit $code
