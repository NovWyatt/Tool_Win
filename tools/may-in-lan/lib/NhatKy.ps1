# Máy in mạng LAN - nhật ký hoàn tác. Mỗi lần sửa ghi một file ket_qua\hoan-tac\HoanTac_<thời gian>_<chế độ>.json,
# ghi lại ngay sau từng thay đổi nên dừng giữa chừng vẫn hoàn tác được phần đã làm. Chạy thử (-ChayThu) không ghi gì.

function New-Journal {
    param([string]$Mode, [string]$Title)
    return [pscustomobject]@{
        Path = $null   # tạo file ở thay đổi đầu tiên: lần chạy không đổi gì thì không có nhật ký rỗng
        Data = [ordered]@{
            version = 1; tool = 'may-in-lan'; mode = $Mode; title = $Title
            computer = $env:COMPUTERNAME; user = (Get-CurrentUser); started = (Get-Date).ToString('s'); undone = $null
            changes = New-Object System.Collections.ArrayList
        }
    }
}

function Save-Journal {
    param($Journal)
    if (-not $Journal.Path) {
        $dir = Join-Path (Get-ResultDir) 'hoan-tac'
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir) }
        $Journal.Path = Join-Path $dir ('HoanTac_{0}_{1}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), $Journal.Data.mode)
    }
    [IO.File]::WriteAllText($Journal.Path, ($Journal.Data | ConvertTo-Json -Depth 8), $script:Utf8NoBom)
}

function Invoke-Change {
    # Một thay đổi lên máy. Chạy thử: chỉ in ra. Chạy thật: làm, ghi nhật ký hoàn tác ngay, in kết quả.
    # $Undo: thông tin để hoàn tác, nơi gọi lấy TRƯỚC khi đổi. Không có $Undo: thay đổi không hoàn tác được.
    # -Quiet: không in từng dòng khi thành công (nơi gọi in tổng kết), lỗi vẫn in.
    # Lưu ý: $Action chạy trong phạm vi của hàm này, đừng dùng tên biến Journal/Text/Action/Undo/DryRun/Quiet trong đó.
    param($Journal, [string]$Text, [scriptblock]$Action, [hashtable]$Undo = $null, [switch]$DryRun, [switch]$Quiet)
    $script:LastChangeError = $null
    if ($DryRun) { if (-not $Quiet) { Write-Plan $Text }; return $true }
    try { & $Action }
    catch {
        $code = Get-ErrorCode $_
        $script:LastChangeError = $code
        Write-Bad ('{0}: {1}' -f $Text, $_.Exception.Message.Trim())
        if ($script:ErrorHelp[[string]$code]) { Write-ErrorHelp $code -Prefix 'Mã' }
        return $false
    }
    if ($Undo) {
        $Undo.text = $Text
        $Undo.time = (Get-Date).ToString('s')
        [void]$Journal.Data.changes.Add($Undo)
        try { Save-Journal $Journal }
        catch { Write-Warn "Đã đổi nhưng không ghi được nhật ký hoàn tác: $($_.Exception.Message)" }
    }
    if (-not $Quiet) { Write-Ok $Text }
    return $true
}

# ---------------------------------------------------------------- các thay đổi có hoàn tác
function Set-ServiceStartModeWithUndo {
    param($Journal, [string]$Name, [string]$Mode, [switch]$DryRun)
    $s = Get-ServiceState $Name
    if (-not $s -or $s.StartMode -eq $Mode) { return $true }
    $undo = @{ kind = 'serviceStart'; name = $Name; before = $s.StartMode; after = $Mode }
    $t = 'Dịch vụ {0} ({1}): {2} → {3}' -f $s.DisplayName, $Name, $script:StartModeText[$s.StartMode], $script:StartModeText[$Mode]
    return (Invoke-Change -Journal $Journal -Text $t -Undo $undo -DryRun:$DryRun -Action { Set-ServiceStartMode $Name $Mode })
}

function Start-ServiceWithUndo {
    param($Journal, [string]$Name, [switch]$DryRun)
    $s = Get-ServiceState $Name
    if (-not $s -or $s.Running) { return $true }
    $undo = @{ kind = 'serviceRun'; name = $Name; before = $false }
    $t = 'Bật dịch vụ {0} ({1})' -f $s.DisplayName, $Name
    return (Invoke-Change -Journal $Journal -Text $t -Undo $undo -DryRun:$DryRun -Action {
            Start-Service -Name $Name
            (Get-Service -Name $Name).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
        })
}

function Set-RegistryDwordWithUndo {
    param($Journal, [string]$Path, [string]$Name, [int]$Value, [string]$Text, [switch]$DryRun)
    $existed = $false; $before = $null; $beforeType = $null
    if (Test-Path -LiteralPath $Path) {
        $key = Get-Item -LiteralPath $Path
        if ($key.GetValueNames() -contains $Name) { $existed = $true; $before = $key.GetValue($Name); $beforeType = [string]$key.GetValueKind($Name) }
    }
    if ($existed -and $beforeType -eq 'DWord' -and [int]$before -eq $Value) { Write-Info "$Text`: đã đúng sẵn."; return $true }
    # Khoá chưa có thì tạo từng cấp và ghi lại, để hoàn tác xoá đúng các khoá công cụ đã tạo.
    $missing = @(); $k = $Path
    while (-not (Test-Path -LiteralPath $k)) { $missing = @($k) + $missing; $k = Split-Path $k -Parent }
    $undo = @{ kind = 'registry'; path = $Path; name = $Name; existed = $existed; before = $before; beforeType = $beforeType; after = $Value; keysCreated = $missing }
    return (Invoke-Change -Journal $Journal -Text $Text -Undo $undo -DryRun:$DryRun -Action {
            foreach ($m in $missing) { [void](New-Item -Path $m) }
            [void](New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWord -Force)
        })
}

function Enable-FirewallRuleWithUndo {
    # Bật quy tắc tường lửa chỉ cho hồ sơ mạng cần (Private hoặc Domain). Quy tắc gốc của Windows gộp "Private, Public"
    # nên bật nguyên quy tắc sẽ mở chia sẻ cả khi máy vào Wi-Fi công cộng; vì vậy thu quy tắc về đúng hồ sơ cần.
    param($Journal, $Rule, [string]$TargetProfile, [switch]$DryRun)
    $undo = @{ kind = 'firewallRule'; name = $Rule.Name; displayName = $Rule.DisplayName; before = @{ enabled = ([string]$Rule.Enabled -eq 'True'); profile = [string]$Rule.Profile } }
    $t = 'Tường lửa: bật "{0}" ({1}) cho mạng {2}' -f $Rule.DisplayName, $(if ([string]$Rule.Direction -eq 'Inbound') { 'vào' } else { 'ra' }), $TargetProfile
    return (Invoke-Change -Journal $Journal -Text $t -Undo $undo -DryRun:$DryRun -Quiet -Action { Set-NetFirewallRule -Name $Rule.Name -Profile $TargetProfile -Enabled True })
}

function Set-NetworkPrivateWithUndo {
    param($Journal, $NetProfile, [switch]$DryRun)
    $undo = @{ kind = 'netProfile'; interfaceIndex = [int]$NetProfile.InterfaceIndex; interfaceAlias = $NetProfile.InterfaceAlias; profileName = $NetProfile.Name; before = [string]$NetProfile.NetworkCategory }
    $t = "Đổi mạng '{0}' ({1}) từ Public sang Private" -f $NetProfile.Name, $NetProfile.InterfaceAlias
    return (Invoke-Change -Journal $Journal -Text $t -Undo $undo -DryRun:$DryRun -Action { Set-NetConnectionProfile -InterfaceIndex $NetProfile.InterfaceIndex -NetworkCategory Private })
}

function Set-SmbClientWithUndo {
    # Đổi cấu hình máy khách SMB (áp dụng ngay). Ghi cả việc giá trị registry có sẵn hay chưa, để hoàn tác trả về
    # đúng "chưa đặt (mặc định Windows)".
    param($Journal, [string]$Setting, [bool]$Value, [string]$Text, [switch]$DryRun)
    $before = [bool](Get-SmbClientConfiguration).$Setting
    if ($before -eq $Value) { Write-Info "$Text`: đã đúng sẵn."; return $true }
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
    $regName = @{ RequireSecuritySignature = 'RequireSecuritySignature'; EnableInsecureGuestLogons = 'AllowInsecureGuestAuth' }[$Setting]
    $regExisted = (Get-Item -LiteralPath $regPath).GetValueNames() -contains $regName
    $undo = @{ kind = 'smbClient'; setting = $Setting; before = $before; after = $Value; regPath = $regPath; regName = $regName; regExisted = $regExisted }
    return (Invoke-Change -Journal $Journal -Text $Text -Undo $undo -DryRun:$DryRun -Action {
            $smbArgs = @{ $Setting = $Value; Force = $true; Confirm = $false }
            Set-SmbClientConfiguration @smbArgs | Out-Null
        })
}

function Enable-AdapterBindingWithUndo {
    param($Journal, $Binding, [switch]$DryRun)
    $undo = @{ kind = 'adapterBinding'; adapter = $Binding.Name; componentId = $Binding.ComponentID; before = $false }
    $t = "Bật '{0}' trên card mạng {1}" -f $Binding.DisplayName, $Binding.Name
    return (Invoke-Change -Journal $Journal -Text $t -Undo $undo -DryRun:$DryRun -Action { Enable-NetAdapterBinding -Name $Binding.Name -ComponentID $Binding.ComponentID })
}

function Get-PrinterSnapshot {
    # Đủ thông tin để thêm lại máy in khi hoàn tác việc xoá.
    param($Printer)
    return @{
        name = $Printer.Name; connection = ($Printer.Type -eq 'Connection'); driverName = $Printer.DriverName; portName = $Printer.PortName
        shared = $Printer.Shared; shareName = $Printer.ShareName; location = $Printer.Location; comment = $Printer.Comment; isDefault = $Printer.Default
    }
}

# ---------------------------------------------------------------- hoàn tác
function Get-JournalEntries {
    # Các lần sửa đã ghi, mới nhất trước.
    $dir = Join-Path (Get-ResultDir) 'hoan-tac'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $list = foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter 'HoanTac_*.json' -File | Sort-Object Name -Descending)) {
        try { [pscustomobject]@{ File = $f; Data = ([IO.File]::ReadAllText($f.FullName, $script:Utf8NoBom) | ConvertFrom-Json) } } catch { }
    }
    return @($list)
}

function Undo-Change {
    # Trả 'ok' hoặc 'skip' (không hoàn tác được, đã báo lý do); lỗi thì ném ra.
    param($Change)
    $c = $Change
    switch ([string]$c.kind) {
        'serviceStart' { Set-ServiceStartMode $c.name $c.before }
        'serviceRun' {
            $s = Get-Service -Name $c.name
            if ($c.before -and $s.Status -ne 'Running') { Start-Service -Name $c.name }
            elseif (-not $c.before -and $s.Status -eq 'Running') { Stop-Service -Name $c.name -Force }
        }
        'registry' {
            if ($c.existed) {
                $type = if ($c.beforeType) { [string]$c.beforeType } else { 'DWord' }
                [void](New-ItemProperty -LiteralPath $c.path -Name $c.name -Value $c.before -PropertyType $type -Force)
            } elseif (Test-Path -LiteralPath $c.path) {
                Remove-ItemProperty -LiteralPath $c.path -Name $c.name -ErrorAction SilentlyContinue
            }
            # Xoá các khoá công cụ đã tạo nếu giờ trống, từ trong ra ngoài.
            $created = @($c.keysCreated | Where-Object { $_ })
            for ($i = $created.Count - 1; $i -ge 0; $i--) {
                if (-not (Test-Path -LiteralPath $created[$i])) { continue }
                $key = Get-Item -LiteralPath $created[$i]
                if ($key.SubKeyCount -eq 0 -and $key.ValueCount -eq 0) { Remove-Item -LiteralPath $created[$i] } else { break }
            }
        }
        'firewallRule' {
            $en = if ($c.before.enabled) { 'True' } else { 'False' }
            Set-NetFirewallRule -Name $c.name -Profile $c.before.profile -Enabled $en
        }
        'netProfile' {
            $np = Get-NetConnectionProfile -InterfaceIndex $c.interfaceIndex -ErrorAction SilentlyContinue
            if (-not $np) { $np = Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $c.profileName } | Select-Object -First 1 }
            if (-not $np) { Write-Info "Mạng '$($c.profileName)' không còn kết nối: bỏ qua."; return 'skip' }
            Set-NetConnectionProfile -InterfaceIndex $np.InterfaceIndex -NetworkCategory $c.before
        }
        'smbClient' {
            $smbArgs = @{ $c.setting = [bool]$c.before; Force = $true; Confirm = $false }
            Set-SmbClientConfiguration @smbArgs | Out-Null
            if (-not $c.regExisted) { Remove-ItemProperty -LiteralPath $c.regPath -Name $c.regName -ErrorAction SilentlyContinue }
        }
        'adapterBinding' { Disable-NetAdapterBinding -Name $c.adapter -ComponentID $c.componentId }
        'printerRemoved' {
            $p = $c.printer
            if (Get-Printer -Name $p.name -ErrorAction SilentlyContinue) { Write-Info "Máy in '$($p.name)' đã có lại: bỏ qua."; return 'skip' }
            if ($p.connection) { Add-Printer -ConnectionName $p.name }
            else {
                $addArgs = @{ Name = $p.name; DriverName = $p.driverName; PortName = $p.portName }
                if ($p.location) { $addArgs.Location = $p.location }
                if ($p.comment) { $addArgs.Comment = $p.comment }
                if ($p.shared -and $p.shareName) { $addArgs.Shared = $true; $addArgs.ShareName = $p.shareName }
                Add-Printer @addArgs
            }
            if ($p.isDefault) {
                $w = Get-WmiPrinter $p.name
                if ($w) { [void](Invoke-CimMethod -InputObject $w -MethodName SetDefaultPrinter) }
            }
        }
        'printerAdded' {
            if (Get-Printer -Name $c.name -ErrorAction SilentlyContinue) { Remove-Printer -Name $c.name }
            if ($c.portCreated) {
                $inUse = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.PortName -eq $c.portCreated })
                if (-not $inUse) {
                    # Spooler giữ cổng thêm vài giây sau khi xoá máy in.
                    try { Remove-PrinterPort -Name $c.portCreated -ErrorAction Stop } catch { Start-Sleep -Seconds 3; Remove-PrinterPort -Name $c.portCreated }
                }
            }
        }
        'printerConnection' {
            if ($c.perMachine) {
                $p = Start-Process rundll32.exe -ArgumentList ('printui.dll,PrintUIEntry /gd /q /n"{0}"' -f $c.connectionName) -Wait -PassThru
                if ($p.ExitCode) { throw "printui báo lỗi $($p.ExitCode)." }
            } elseif (Get-Printer -Name $c.connectionName -ErrorAction SilentlyContinue) { Remove-Printer -Name $c.connectionName }
        }
        'printerRenamed' { Rename-Printer -Name $c.to -NewName $c.from }
        'printerShared' {
            if ($c.before.shared) { Set-Printer -Name $c.name -Shared $true -ShareName $c.before.shareName }
            else { Set-Printer -Name $c.name -Shared $false }
        }
        'printerWorkOffline' {
            $w = Get-WmiPrinter $c.name
            if (-not $w) { Write-Info "Không còn máy in '$($c.name)': bỏ qua."; return 'skip' }
            Set-CimInstance -InputObject $w -Property @{ WorkOffline = [bool]$c.before }
        }
        'printerPaused' {
            $w = Get-WmiPrinter $c.name
            if (-not $w) { Write-Info "Không còn máy in '$($c.name)': bỏ qua."; return 'skip' }
            [void](Invoke-CimMethod -InputObject $w -MethodName Pause)
        }
        'spoolClear' { Write-Info "$($c.text): lệnh in đã xoá không lấy lại được."; return 'skip' }
        default { Write-Info "Không biết cách hoàn tác '$($c.kind)': bỏ qua."; return 'skip' }
    }
    return 'ok'
}

function Invoke-UndoJournal {
    # Hoàn tác các thay đổi của một lần sửa, theo thứ tự ngược lại. Ghi kết quả vào chính file nhật ký.
    param($Entry, [switch]$DryRun)
    $changes = @($Entry.Data.changes)
    $ok = 0; $fail = 0; $skip = 0
    for ($i = $changes.Count - 1; $i -ge 0; $i--) {
        $c = $changes[$i]
        if ($DryRun) { Write-Plan "Hoàn tác: $($c.text)"; continue }
        try {
            if ((Undo-Change $c) -eq 'skip') { $skip++ } else { $ok++; Write-Ok "Đã hoàn tác: $($c.text)" }
        } catch {
            $fail++
            Write-Bad ('Không hoàn tác được: {0} ({1})' -f $c.text, $_.Exception.Message.Trim())
        }
    }
    if (-not $DryRun) {
        $Entry.Data | Add-Member -NotePropertyName undone -NotePropertyValue ([ordered]@{ time = (Get-Date).ToString('s'); ok = $ok; failed = $fail; skipped = $skip }) -Force
        try { [IO.File]::WriteAllText($Entry.File.FullName, ($Entry.Data | ConvertTo-Json -Depth 8), $script:Utf8NoBom) }
        catch { Write-Warn "Không ghi được kết quả hoàn tác vào nhật ký: $($_.Exception.Message)" }
    }
    return [pscustomobject]@{ Ok = $ok; Failed = $fail; Skipped = $skip }
}
