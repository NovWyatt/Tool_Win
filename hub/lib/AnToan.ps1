# Trạm Tool - lan can an toàn: điểm khôi phục hệ thống, ghi lại trạng thái trước khi chạy, kiểm tra winget.
# Máy chủ trạm (quyền thường) chỉ dùng phần đọc. Phần ghi (Restore-SnapshotItem) chạy trong hub\safety\*.ps1 bằng
# quyền Admin. Cần Common.ps1 (Get-Prop, Read-JsonFile, Write-JsonFile).

# ---------------------------------------------------------------- chạy chương trình ngoài, có giới hạn thời gian
function Invoke-NativeCapture {
    # Chạy exe không mở cửa sổ, đọc stdout/stderr (UTF-8), chờ tối đa $TimeoutMs rồi dừng hẳn.
    param([Parameter(Mandatory)][string]$FilePath, [string]$Arguments = '', [int]$TimeoutMs = 15000)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $r = [ordered]@{ ExitCode = $null; Output = ''; Error = ''; TimedOut = $false }
    $p = [Diagnostics.Process]::Start($psi)
    try {
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if ($p.WaitForExit($TimeoutMs)) {
            $p.WaitForExit()   # đợi đọc xong output
            $r.ExitCode = $p.ExitCode
        } else {
            $r.TimedOut = $true
            try { $p.Kill() } catch { }
        }
        if ($outTask.Wait(3000)) { $r.Output = $outTask.Result }
        if ($errTask.Wait(1000)) { $r.Error = $errTask.Result }
    } finally { $p.Dispose() }
    return $r
}

function Format-ExitCode {
    # Mã nhỏ in số thập phân; mã kiểu HRESULT (âm hoặc lớn) in dạng 0x8A15000F.
    param($Code)
    if ($null -eq $Code) { return '?' }
    $c = [int64]$Code
    if ($c -ge 0 -and $c -lt 65536) { return [string]$c }
    if ($c -lt 0) { $c += 4294967296 }   # mã âm (Int32) -> số không dấu 32 bit
    return ('0x{0:X8}' -f $c)
}

# ---------------------------------------------------------------- điểm khôi phục hệ thống
# Windows 10, 11 tắt sẵn Bảo vệ hệ thống (System Protection). Từ 24H2 (KB5060842) điểm khôi phục giữ tối đa 60 ngày.
# https://support.microsoft.com/windows/system-protection , https://support.microsoft.com/kb/5060842

function Get-RestoreStatus {
    # Chỉ đọc, không cần Admin. enabled: $true (Bảo vệ hệ thống đang bật), $false, hoặc $null (không đọc được).
    # SystemRestoreConfig.RPSessionInterval = 0 khi System Restore tắt. Danh sách điểm khôi phục cần Admin nên trạm
    # không đọc; script tạo điểm (chạy Admin) xác nhận bằng số thứ tự điểm.
    $r = [ordered]@{ enabled = $null; diskPercent = $null; policyOff = $false; configLocked = $false; vssDisabled = $false; detail = '' }
    try {
        $cfg = Get-CimInstance -Namespace 'root/default' -ClassName SystemRestoreConfig -ErrorAction Stop
        $r.enabled = ([int]$cfg.RPSessionInterval -ne 0)
        if ($null -ne $cfg.DiskPercent) { $r.diskPercent = [int]$cfg.DiskPercent }
    } catch { }
    try {
        # Group Policy: "Turn off System Restore" (DisableSR), "Turn off Configuration" (DisableConfig).
        $pol = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' -ErrorAction Stop
        if ([int](Get-Prop $pol 'DisableSR' 0) -eq 1) { $r.policyOff = $true; $r.enabled = $false }
        if ([int](Get-Prop $pol 'DisableConfig' 0) -eq 1) { $r.configLocked = $true }
    } catch { }
    try {
        $vss = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\VSS' -ErrorAction Stop
        if ([int](Get-Prop $vss 'Start' 3) -eq 4) { $r.vssDisabled = $true }
    } catch { }
    $r.detail = if ($r.policyOff) { 'Chính sách nhóm (Group Policy) đang tắt Bảo vệ hệ thống.' }
    elseif ($r.vssDisabled) { 'Dịch vụ Volume Shadow Copy (VSS) bị vô hiệu hoá nên Windows không tạo được điểm khôi phục.' }
    elseif ($r.enabled -eq $false -and $r.configLocked) { 'Bảo vệ hệ thống đang tắt và chính sách nhóm khoá phần cài đặt.' }
    elseif ($r.enabled -eq $false) { 'Bảo vệ hệ thống (System Protection) đang tắt nên chưa có điểm khôi phục nào.' }
    elseif ($r.enabled) { 'Đang bật.' }
    else { 'Không đọc được trạng thái.' }
    return $r
}

function Get-LatestRestorePoint {
    # Điểm khôi phục mới nhất (cần Admin); $null khi chưa có hoặc không đọc được.
    try {
        $p = @(Get-ComputerRestorePoint -ErrorAction Stop | Sort-Object { [int]$_.SequenceNumber } -Descending | Select-Object -First 1)
        if (-not $p.Count) { return $null }
        $t = $null
        try { $t = [Management.ManagementDateTimeConverter]::ToDateTime([string]$p[0].CreationTime) } catch { }
        return [pscustomobject]@{ SequenceNumber = [int]$p[0].SequenceNumber; Description = [string]$p[0].Description; Time = $t }
    } catch { return $null }
}

function Enable-SystemProtection {
    # Bật Bảo vệ hệ thống cho ổ Windows (cần Admin). Dung lượng tối đa giữ mặc định của Windows: không đổi kích thước
    # shadow storage, vì thu nhỏ có thể xoá điểm cũ và ảnh chụp của Point-in-time restore dùng chung chỗ đó.
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
    for ($i = 0; $i -lt 10; $i++) {
        if ((Get-RestoreStatus).enabled) { return }
        Start-Sleep -Seconds 1
    }
    throw 'Đã gọi Enable-ComputerRestore nhưng Windows vẫn báo Bảo vệ hệ thống đang tắt.'
}

function New-SystemRestorePoint {
    # Tạo điểm khôi phục (cần Admin). Windows lặng lẽ bỏ qua nếu đã có điểm trong 24 giờ (SystemRestorePointCreationFrequency,
    # mặc định 1440 phút) nên tạm đặt 0 rồi trả lại; xác nhận bằng số thứ tự điểm mới nhất trước và sau.
    # Checkpoint-Computer chạy trong job để chờ có giới hạn; mutex tránh hai cửa sổ tạo cùng lúc.
    # https://learn.microsoft.com/windows/win32/sr/createrestorepoint-systemrestore
    param([Parameter(Mandatory)][string]$Description, [string]$Type = 'MODIFY_SETTINGS', [int]$TimeoutSec = 600)
    $r = [ordered]@{ created = $false; seq = $null; at = $null; message = '' }
    if ($Description.Length -gt 64) { $Description = $Description.Substring(0, 64) }
    $mutex = New-Object Threading.Mutex($false, 'Global\TramTool-DiemKhoiPhuc')
    $owned = $false
    try {
        try { $owned = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSec)) } catch [Threading.AbandonedMutexException] { $owned = $true }
        if (-not $owned) { $r.message = 'Cửa sổ khác đang tạo điểm khôi phục quá lâu.'; return $r }
        $before = Get-LatestRestorePoint
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $name = 'SystemRestorePointCreationFrequency'
        $orig = Get-RegistryValueState $key $name
        try {
            if (-not ($orig.exists -and $orig.kind -eq 'DWord' -and [int]$orig.value -eq 0)) {
                [void](New-ItemProperty -LiteralPath $key -Name $name -Value 0 -PropertyType DWord -Force -ErrorAction Stop)
            }
            $job = Start-Job -ScriptBlock {
                param($d, $t)
                Checkpoint-Computer -Description $d -RestorePointType $t -ErrorAction Stop -WarningAction SilentlyContinue
            } -ArgumentList $Description, $Type
            try {
                if (Wait-Job -Job $job -Timeout $TimeoutSec) {
                    try { [void](Receive-Job -Job $job -ErrorAction Stop) } catch { $r.message = $_.Exception.Message.Trim() }
                } else {
                    Stop-Job -Job $job
                    $r.message = "Windows chưa tạo xong sau $TimeoutSec giây."
                }
            } finally { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
        } catch {
            $r.message = $_.Exception.Message.Trim()
        } finally {
            # Trả SystemRestorePointCreationFrequency như cũ (chưa có thì xoá).
            try {
                if ($orig.exists) { [void](New-ItemProperty -LiteralPath $key -Name $name -Value (ConvertFrom-StateValue $orig.value $orig.kind) -PropertyType $orig.kind -Force) }
                else { Remove-ItemProperty -LiteralPath $key -Name $name -ErrorAction SilentlyContinue }
            } catch { }
        }
        $after = Get-LatestRestorePoint
        if ($after -and (-not $before -or $after.SequenceNumber -gt $before.SequenceNumber)) {
            $r.created = $true
            $r.seq = $after.SequenceNumber
            $r.at = $after.Time
            $r.message = ''
        } elseif (-not $r.message) {
            $r.message = 'Windows không báo lỗi nhưng không thấy điểm khôi phục mới.'
        }
    } finally {
        if ($owned) { try { $mutex.ReleaseMutex() } catch { } }
        $mutex.Dispose()
    }
    return $r
}

function Get-RestoreErrorHint {
    # Giải thích lỗi thường gặp khi tạo điểm khôi phục.
    param([string]$Message)
    if ($Message -match '0x81000101|timed out|hết thời gian') { return 'Volume Shadow Copy quá thời gian; ổ C: cần trống ít nhất 1 GB. Thử lại sau ít phút.' }
    if ($Message -match '1058|0x80070422|disabled|vô hiệu') { return 'Bảo vệ hệ thống hoặc dịch vụ liên quan đang tắt.' }
    if ($Message -match '112|0x80070070|disk|đầy') { return 'Ổ C: gần đầy nên Windows tạm ngừng tạo điểm khôi phục.' }
    if ($Message -match 'Safe Mode|an toàn') { return 'Không tạo được điểm khôi phục trong Safe Mode.' }
    return ''
}

# ---------------------------------------------------------------- ghi lại trạng thái trước khi chạy
# Công cụ khai báo dịch vụ, giá trị registry mình đổi trong "probes" của tool.json. Trước khi chạy action có đổi máy,
# trạm ghi trạng thái các mục đó ra data\snapshots\TrangThai_<lần chạy>.json; sau đó so được "trước khi chạy" với hiện
# tại và trả lại bằng hub\safety\TraLaiTrangThai.ps1 (quyền Admin). Chỉ ghi registry HKLM: HKCU của tài khoản Admin
# nâng quyền có thể khác tài khoản đang dùng trạm.

$script:StartTypeText = @{ 0 = 'Boot'; 1 = 'System'; 2 = 'Tự khởi động'; 3 = 'Thủ công'; 4 = 'Đã vô hiệu hoá' }

function Get-ServiceStartState {
    # Đọc thẳng registry (Start 0-4, DelayedAutostart) để trả lại đúng cả "Tự khởi động (trễ)".
    param([string]$Name)
    $s = [ordered]@{ exists = $false; start = $null; delayed = 0 }
    if (-not $Name -or $Name -match '[\\/]') { return $s }
    try {
        $p = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -ErrorAction Stop
        $start = Get-Prop $p 'Start' $null
        if ($null -ne $start) {
            $s.exists = $true
            $s.start = [int]$start
            $s.delayed = [int](Get-Prop $p 'DelayedAutostart' 0)
        }
    } catch { }
    return $s
}

function Format-ServiceStart {
    param($State)
    if (-not $State.exists) { return 'Không có trên máy' }
    $t = $script:StartTypeText[[int]$State.start]
    if (-not $t) { $t = "Start = $($State.start)" }
    if ([int]$State.start -eq 2 -and [int]$State.delayed -eq 1) { $t += ' (trễ)' }
    return $t
}

function ConvertTo-StateValue {
    # Giá trị registry -> dạng lưu được trong JSON mà vẫn trả lại đúng kiểu.
    param($Value, [string]$Kind)
    switch ($Kind) {
        'Binary' { return [Convert]::ToBase64String([byte[]]$Value) }
        'QWord' { return [string][int64]$Value }
        'MultiString' { return @(@($Value) | ForEach-Object { [string]$_ }) }
        'DWord' { return [int]$Value }
        default { return [string]$Value }
    }
}

function ConvertFrom-StateValue {
    param($Value, [string]$Kind)
    switch ($Kind) {
        'Binary' { return [byte[]][Convert]::FromBase64String([string]$Value) }
        'QWord' { return [int64][string]$Value }
        'MultiString' { return [string[]]@(@($Value) | ForEach-Object { [string]$_ }) }
        'DWord' { return [int]$Value }
        default { return [string]$Value }
    }
}

function Get-RegistryValueState {
    param([string]$Path, [string]$Name)
    $s = [ordered]@{ keyExists = $false; exists = $false; kind = $null; value = $null }
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $s }
        $s.keyExists = $true
        $k = Get-Item -LiteralPath $Path -ErrorAction Stop
        try {
            if ($k.GetValueNames() -contains $Name) {
                $s.exists = $true
                $s.kind = [string]$k.GetValueKind($Name)
                $s.value = ConvertTo-StateValue -Value $k.GetValue($Name, $null, 'DoNotExpandEnvironmentNames') -Kind $s.kind
            }
        } finally { $k.Close() }
    } catch { }
    return $s
}

function Test-RegistryStateEqual {
    param($A, $B)
    if ([bool]$A.exists -ne [bool]$B.exists) { return $false }
    if (-not $A.exists) { return $true }
    if ([string]$A.kind -ne [string]$B.kind) { return $false }
    $va = @(@($A.value) | ForEach-Object { [string]$_ }) -join "`0"
    $vb = @(@($B.value) | ForEach-Object { [string]$_ }) -join "`0"
    return ($va -ceq $vb)
}

function Format-RegistryState {
    param($State, $ValuesMap)
    if (-not $State.exists) { return 'Chưa đặt (mặc định Windows)' }
    $key = @(@($State.value) | ForEach-Object { [string]$_ }) -join '; '
    $label = if ($ValuesMap -and $State.kind -ne 'Binary') { Get-Prop $ValuesMap $key $null } else { $null }
    if ($label) { return [string]$label }
    if ($State.kind -eq 'Binary') { return "Dữ liệu nhị phân ($(([Convert]::FromBase64String([string]$State.value)).Length) byte)" }
    return "Giá trị: $key"
}

function Get-ProbeItemState {
    # Trạng thái hiện tại của một mục trong probes; $null nếu kiểu không hỗ trợ ghi lại hoặc probe đặt
    # "snapshot": false (chỉ để hiển thị: trả lại mục đó sẽ hại máy, vd registry của phần mềm vừa gỡ).
    param($Probe)
    if ((Get-Prop $Probe 'snapshot' $true) -eq $false) { return $null }
    $type = [string](Get-Prop $Probe 'type' '')
    $label = [string](Get-Prop $Probe 'label' '')
    if ($type -eq 'service') {
        $name = [string](Get-Prop $Probe 'name' '')
        if (-not $name) { return $null }
        return [ordered]@{ type = 'service'; name = $name; label = $(if ($label) { $label } else { $name }); state = (Get-ServiceStartState $name) }
    }
    if ($type -eq 'registry') {
        $path = [string](Get-Prop $Probe 'path' '')
        $name = [string](Get-Prop $Probe 'name' '')
        if (-not $name -or $path -notmatch '^HKLM:\\') { return $null }
        return [ordered]@{
            type = 'registry'; path = $path; name = $name; label = $(if ($label) { $label } else { $name })
            values = (Get-Prop $Probe 'values' $null); state = (Get-RegistryValueState $path $name)
        }
    }
    return $null
}

function Get-SnapshotFileName {
    # Thời gian lần chạy '2026-10-05T10:32:11.123+07:00' -> 'TrangThai_20261005103211123.json'.
    param([string]$RunTime)
    $digits = ($RunTime.Substring(0, [Math]::Min(23, $RunTime.Length)) -replace '[^0-9]', '')
    return "TrangThai_$digits.json"
}

function Test-SnapshotFileName {
    param([string]$Name)
    return $Name -match '^TrangThai_\d{17}\.json$'
}

function New-RunSnapshot {
    # Ghi trạng thái các mục trong probes; trả về tên file, hoặc '' khi công cụ không khai báo mục nào ghi được.
    param([Parameter(Mandatory)]$Tool, [Parameter(Mandatory)]$Action, [Parameter(Mandatory)][string]$RunTime, [Parameter(Mandatory)][string]$Dir)
    $items = @(foreach ($p in @($Tool.probes)) { $s = Get-ProbeItemState $p; if ($s) { $s } })
    if (-not $items.Count) { return '' }
    $name = Get-SnapshotFileName $RunTime
    Write-JsonFile -Path (Join-Path $Dir $name) -InputObject ([ordered]@{
            version = 1; time = $RunTime; toolId = $Tool.id; toolName = $Tool.name
            actionId = $Action.id; actionLabel = $Action.label; items = $items
        })
    return $name
}

function Compare-RunSnapshot {
    # So trạng thái đã ghi với hiện tại. Mỗi mục: index (vị trí trong items của file), label, target, before, after
    # (chữ), changed, restorable, note.
    param([Parameter(Mandatory)][string]$Path)
    $snap = Read-JsonFile $Path
    $out = New-Object System.Collections.ArrayList
    $items = @($snap.items)
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]
        $row = [ordered]@{ index = $i; type = [string]$it.type; label = [string]$it.label; target = ''; before = ''; after = ''; changed = $false; restorable = $false; note = '' }
        if ($it.type -eq 'service') {
            $now = Get-ServiceStartState $it.name
            $row.target = "Dịch vụ $($it.name)"
            $row.before = Format-ServiceStart $it.state
            $row.after = Format-ServiceStart $now
            $row.changed = ([bool]$it.state.exists -ne $now.exists) -or ($now.exists -and ([int]$it.state.start -ne $now.start -or [int]$it.state.delayed -ne $now.delayed))
            $row.restorable = $row.changed -and [bool]$it.state.exists -and $now.exists
            if ($row.changed -and -not $row.restorable) { $row.note = if ($it.state.exists) { 'Dịch vụ không còn trên máy.' } else { 'Dịch vụ mới được cài thêm; trạm không tự gỡ.' } }
        } elseif ($it.type -eq 'registry') {
            $now = Get-RegistryValueState $it.path $it.name
            $row.target = "$($it.path)\$($it.name)"
            $row.before = Format-RegistryState $it.state $it.values
            $row.after = Format-RegistryState $now $it.values
            $row.changed = -not (Test-RegistryStateEqual $it.state $now)
            $row.restorable = $row.changed
        } else { continue }
        [void]$out.Add($row)
    }
    return $out.ToArray()   # nơi gọi bọc @()
}

function Restore-SnapshotItem {
    # Trả một mục về trạng thái đã ghi (cần Admin). Trả 'ok' hoặc 'same'; không làm được thì ném lỗi có lời giải thích.
    param([Parameter(Mandatory)]$Item)
    if ($Item.type -eq 'service') {
        $name = [string]$Item.name
        $now = Get-ServiceStartState $name
        if (-not $Item.state.exists) { throw 'Lúc trước dịch vụ này chưa có trên máy; trạm không tự gỡ dịch vụ.' }
        if (-not $now.exists) { throw 'Dịch vụ không còn trên máy.' }
        $start = [int]$Item.state.start
        $delayed = [int]$Item.state.delayed
        if ($now.start -eq $start -and $now.delayed -eq $delayed) { return 'same' }
        $mode = switch ($start) {
            0 { 'boot' } 1 { 'system' } 3 { 'demand' } 4 { 'disabled' }
            2 { if ($delayed -eq 1) { 'delayed-auto' } else { 'auto' } }
            default { throw "Kiểu khởi động $start không hỗ trợ." }
        }
        # Gọi sc.exe (không gọi "sc": trong PowerShell đó là Set-Content). Lời báo của sc theo bảng mã OEM nên chỉ dựa vào mã thoát.
        $null = & sc.exe config $name start= $mode 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            $msg = if ($code -eq 5) { 'Windows từ chối (dịch vụ được bảo vệ hoặc thiếu quyền Admin).' } else { (New-Object ComponentModel.Win32Exception([int]$code)).Message }
            throw "sc config báo mã $code`: $msg"
        }
        $after = Get-ServiceStartState $name
        if ($after.start -ne $start -or $after.delayed -ne $delayed) { throw "Đã gọi sc config nhưng dịch vụ vẫn là '$(Format-ServiceStart $after)'." }
        return 'ok'
    }
    if ($Item.type -eq 'registry') {
        $path = [string]$Item.path
        $name = [string]$Item.name
        if ($path -notmatch '^HKLM:\\') { throw 'Chỉ trả lại được registry HKLM.' }
        $now = Get-RegistryValueState $path $name
        if (Test-RegistryStateEqual $Item.state $now) { return 'same' }
        if ($Item.state.exists) {
            if (-not (Test-Path -LiteralPath $path)) { [void](New-Item -Path $path -Force) }
            $kind = [string]$Item.state.kind
            [void](New-ItemProperty -LiteralPath $path -Name $name -Value (ConvertFrom-StateValue $Item.state.value $kind) -PropertyType $kind -Force -ErrorAction Stop)
        } else {
            Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop
        }
        return 'ok'
    }
    throw "Không hỗ trợ kiểu '$($Item.type)'."
}

# ---------------------------------------------------------------- winget
function Get-WingetStatus {
    # Chỉ đọc, không gọi mạng. ok: lệnh winget chạy được và có nguồn chính "winget" (cdn.winget.microsoft.com).
    # stage (khi chưa ok): 'install' chưa có lệnh winget, 'run' có lệnh nhưng chạy lỗi, 'source' lỗi nguồn.
    $r = [ordered]@{ ok = $false; stage = ''; version = ''; appInstaller = ''; path = ''; problem = '' }
    try {
        $pkg = @(Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction Stop | Sort-Object Version -Descending)
        if ($pkg.Count) { $r.appInstaller = [string]$pkg[0].Version }
    } catch { }
    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) {
        $r.stage = 'install'
        $r.problem = if ($r.appInstaller) { 'Máy có App Installer nhưng lệnh winget chưa được đăng ký cho tài khoản này.' } else { 'Máy chưa có App Installer (winget).' }
        return $r
    }
    $r.path = $cmd.Source
    $r.stage = 'run'
    try {
        $v = Invoke-NativeCapture -FilePath $cmd.Source -Arguments '--version' -TimeoutMs 15000
        if ($v.TimedOut) { $r.problem = 'winget không trả lời (quá 15 giây).'; return $r }
        $ver = ([string]$v.Output).Trim()
        if ($v.ExitCode -ne 0 -or $ver -notmatch '^v?\d+\.\d+') { $r.problem = "winget báo lỗi khi chạy (mã $(Format-ExitCode $v.ExitCode))."; return $r }
        $r.version = $ver
        $r.stage = 'source'
        $s = Invoke-NativeCapture -FilePath $cmd.Source -Arguments 'source list' -TimeoutMs 15000
        if ($s.TimedOut) { $r.problem = 'winget không trả lời khi đọc danh sách nguồn (quá 15 giây).'; return $r }
        if ($s.ExitCode -ne 0) { $r.problem = "Không đọc được danh sách nguồn của winget (mã $(Format-ExitCode $s.ExitCode))."; return $r }
        if ([string]$s.Output -notmatch 'cdn\.winget\.microsoft\.com/cache') { $r.problem = 'winget thiếu nguồn chính "winget" (cdn.winget.microsoft.com).'; return $r }
    } catch {
        $r.problem = "Không chạy được winget: $($_.Exception.Message)"
        return $r
    }
    $r.ok = $true
    $r.stage = ''
    return $r
}

# ---------------------------------------------------------------- màn hình của các script hub\safety\*.ps1
function Write-AtHead {
    param([string]$Title, [string]$Sub = '')
    Write-Host ''
    Write-Host ('  ' + ('=' * 66)) -ForegroundColor DarkCyan
    Write-Host "   $Title" -ForegroundColor Cyan
    if ($Sub) { Write-Host "   $Sub" -ForegroundColor Gray }
    Write-Host ('  ' + ('=' * 66)) -ForegroundColor DarkCyan
}
function Write-AtOk([string]$Text) { Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-AtWarn([string]$Text) { Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Write-AtBad([string]$Text) { Write-Host "  [X]  $Text" -ForegroundColor Red }
function Write-AtInfo([string]$Text) { Write-Host "       $Text" -ForegroundColor Gray }

function Read-AtChoice {
    # Hỏi đến khi gõ đúng một trong các phím; không có lựa chọn mặc định để khỏi lỡ tay bấm Enter.
    # Hết lượt hỏi (cửa sổ không nhận phím) thì trả $Fallback.
    param([string]$Prompt, [string[]]$Keys, [string]$Fallback)
    for ($i = 0; $i -lt 30; $i++) {
        $a = ([string](Read-Host "  $Prompt")).Trim().ToUpperInvariant()
        if ($Keys -contains $a) { return $a }
        Write-Host ('  Gõ {0} rồi Enter.' -f ($Keys -join ', ')) -ForegroundColor Yellow
    }
    return $Fallback
}

function Wait-AtClose {
    Write-Host ''
    Write-Host '  Bấm phím bất kỳ để đóng cửa sổ.' -ForegroundColor DarkGray
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { [void](Read-Host) }
}
