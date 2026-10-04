# Máy in mạng LAN - các chế độ sửa. Mỗi chế độ: xem hiện trạng, in kế hoạch ("Sẽ làm"), hỏi, rồi làm từng bước có
# nhật ký hoàn tác. -DryRun (chạy thử): chỉ in kế hoạch, không đổi gì, không ghi nhật ký.

$script:SecurityOptions = [ordered]@{
    'rpc-named-pipe'  = @{
        Label = 'Kết nối máy in chia sẻ bằng RPC qua named pipe (chạy trên máy dùng máy in)'
        When  = 'Máy này Windows 11 22H2 trở lên, kết nối máy in chia sẻ trên máy Windows cũ báo 0x00000709 hoặc 0x00000BC4.'
        Risk  = 'Trở lại cách Windows 10 vẫn dùng; rủi ro thấp nhất trong các mục.'
    }
    'rpc-privacy-off' = @{
        Label = 'Tắt mã hoá RPC cho máy in chia sẻ (chạy trên máy CHIA SẺ máy in)'
        When  = 'Máy khác kết nối máy in chia sẻ từ máy này báo 0x0000011B, cả khi các máy đã cập nhật Windows.'
        Risk  = 'Mở lại lỗ hổng CVE-2021-1678 của dịch vụ in; chỉ dùng trong mạng nội bộ tin cậy.'
    }
    'smb-guest'       = @{
        Label = 'Cho vào thư mục chia sẻ không mật khẩu (guest)'
        When  = 'NAS, ổ cứng cắm router, máy chia sẻ không đặt mật khẩu báo lỗi 1272 hoặc 0x80070035.'
        Risk  = 'Tắt luôn yêu cầu ký SMB (khách không ký được): máy giả mạo trong mạng có thể đọc, sửa dữ liệu truyền đi.'
    }
    'smb-signing-off' = @{
        Label = 'Không bắt buộc ký SMB khi vào máy khác'
        When  = 'NAS, thiết bị cũ báo "The cryptographic signature is invalid" (0xC000A000) hoặc 0x80090006.'
        Risk  = 'Máy giả mạo trong mạng có thể chen vào kết nối (relay, sửa dữ liệu).'
    }
}

function Get-ResultCode {
    # 0 xong hết, 3 làm được một phần, 1 không làm được gì.
    param([int]$Ok, [int]$Fail)
    if ($Fail -eq 0) { return 0 }
    if ($Ok -gt 0) { return 3 }
    return 1
}

function Confirm-Plan {
    # Sau khi in kế hoạch: chạy thử thì dừng ở đây; chạy thật thì hỏi. Trả $true khi được làm.
    param([switch]$DryRun, [string]$Question = 'Làm ngay?')
    if ($DryRun) { Write-Info 'Chạy thử: máy chưa thay đổi gì.'; return $false }
    if (Read-YesNo $Question $true) { return $true }
    Write-Info 'Đã huỷ, máy chưa thay đổi gì.'
    return $false
}

function Test-PrinterReach {
    # Thử kết nối tới máy in: open, closed, timeout, unreachable, noname; n/a với USB, WSD, máy in ảo.
    param($Printer)
    $port = switch ($Printer.Kind) { 'tcp' { $Printer.PortNumber } 'lpr' { 515 } 'ipp' { 631 } 'connection' { 445 } default { 0 } }
    if (-not $port -or -not $Printer.Address) { return 'n/a' }
    $ip = $null
    try { $ip = @(Resolve-HostAddress $Printer.Address)[0] } catch { }
    if (-not $ip) { return 'noname' }
    return (Test-TcpPorts -Address $ip -Ports $port)[$port]
}

function Get-VendorDriverNames {
    # Driver máy in của hãng đã cài (bỏ máy in ảo và driver chung IPP, Point and Print).
    return @(Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $script:VirtualDrivers -and $_.Name -notmatch 'IPP Class Driver|Point and Print compatibility' } | Sort-Object Name | Select-Object -ExpandProperty Name -Unique)
}

function Select-PrinterDriver {
    # Chọn driver hãng đã cài (in qua cổng 9100). Trả tên driver; chạy thử trả chữ giữ chỗ;
    # $null khi máy chưa có driver nào hoặc người dùng không chọn.
    param([switch]$DryRun)
    $drivers = @(Get-VendorDriverNames)
    if (-not $drivers) {
        Write-Bad 'Máy này chưa có driver máy in của hãng.'
        Write-Sub 'Tải driver của hãng (tìm "<tên model máy in> driver" trên trang hãng), cài xong chạy lại.'
        return $null
    }
    Write-Line 'Driver máy in đã cài:'
    for ($i = 0; $i -lt $drivers.Count; $i++) { Write-Line ('  {0}. {1}' -f ($i + 1), $drivers[$i]) }
    if ($DryRun) { return '(chọn khi chạy thật)' }
    $n = Read-Number 'Chọn driver đúng hãng và đời máy in (gõ số)' 1 $drivers.Count $null
    if (-not $n) { Write-Info 'Chưa chọn driver, máy chưa thay đổi gì.'; return $null }
    return $drivers[$n - 1]
}

function Get-ShareNameFor {
    param([string]$Name)
    $s = ($Name -replace '[\\/,:*?"<>|]', '').Trim()
    if ($s.Length -gt 80) { $s = $s.Substring(0, 80).Trim() }
    return $s
}

function Show-ShareAccessInfo {
    $idx = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue | ForEach-Object { $_.InterfaceIndex })
    $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceIndex -in $idx -and $_.IPAddress -notlike '169.254.*' } | ForEach-Object { '\\' + $_.IPAddress })
    Write-Line ''
    Write-Line ('Máy khác vào máy này bằng: \\{0}{1}' -f $env:COMPUTERNAME, $(if ($ips) { ' hoặc ' + ($ips -join ', ') } else { '' }))
    Write-Sub 'Máy khác cần một tài khoản CÓ MẬT KHẨU của máy này để vào. Không muốn đưa tài khoản của bạn: tạo tài khoản riêng ở Settings > Accounts > Other users.'
    Write-Sub 'Chia sẻ một thư mục: chuột phải thư mục > Properties > Sharing > Share..., chọn người được dùng.'
}

# ---------------------------------------------------------------- thay đổi trên máy in (có hoàn tác)
function Resume-PrinterWithUndo {
    param($Journal, $Printer)
    $undo = @{ kind = 'printerPaused'; name = $Printer.Name }
    return (Invoke-Change -Journal $Journal -Text "Cho máy in '$($Printer.Name)' in tiếp" -Undo $undo -Action {
            $r = Invoke-CimMethod -InputObject (Get-WmiPrinter $Printer.Name) -MethodName Resume
            if ($r.ReturnValue) { throw "Windows báo lỗi $($r.ReturnValue)." }
        })
}

function Set-PrinterOnlineWithUndo {
    param($Journal, $Printer)
    $undo = @{ kind = 'printerWorkOffline'; name = $Printer.Name; before = $true }
    return (Invoke-Change -Journal $Journal -Text "Tắt 'Dùng máy in ngoại tuyến' cho '$($Printer.Name)'" -Undo $undo -Action {
            Set-CimInstance -InputObject (Get-WmiPrinter $Printer.Name) -Property @{ WorkOffline = $false }
        })
}

function Set-PrinterSharedWithUndo {
    param($Journal, $Printer, [string]$ShareName)
    $undo = @{ kind = 'printerShared'; name = $Printer.Name; before = @{ shared = $false; shareName = '' } }
    $t = "Chia sẻ máy in '{0}' với tên \\{1}\{2}" -f $Printer.Name, $env:COMPUTERNAME, $ShareName
    return (Invoke-Change -Journal $Journal -Text $t -Undo $undo -Action { Set-Printer -Name $Printer.Name -Shared $true -ShareName $ShareName })
}

# ---------------------------------------------------------------- sua-hang-doi
function Invoke-SuaHangDoi {
    param([switch]$DryRun)
    Write-Head 'Sửa hàng đợi in'
    $sp = Get-ServiceState 'Spooler'
    if (-not $sp) { Write-Bad 'Máy này không có dịch vụ Print Spooler.'; return 2 }
    Write-Line ('Print Spooler: {0}.' -f (Format-ServiceState $sp))
    $printers = @()
    if ($sp.Running) {
        try { $printers = @(Get-PrinterList | Where-Object { $_.Kind -ne 'ao' }) } catch { Write-Warn "Không đọc được danh sách máy in: $($_.Exception.Message.Trim())" }
    }
    foreach ($p in $printers) {
        if ($p.Kind -eq 'connection') { continue }
        $n = @(Get-PrintJobsSafe $p.Name).Count
        if ($n) { Write-Line ('{0}: {1} lệnh in đang chờ.' -f $p.Name, $n) }
    }
    $spool = Get-SpoolDirectory
    $files = $null
    try {
        $files = @(Get-ChildItem -LiteralPath $spool -File -ErrorAction Stop)
        Write-Line ('Thư mục hàng đợi: {0} file ({1:N1} MB).' -f $files.Count, (($files | Measure-Object Length -Sum).Sum / 1MB))
    } catch { Write-Info 'Chưa xem được thư mục hàng đợi (cần quyền Admin).' }
    $paused = @($printers | Where-Object { $_.Status -match 'Paused' })
    $offline = @($printers | Where-Object { $_.WorkOffline })
    $needMode = $sp.StartMode -notin 'Automatic', 'AutomaticDelayed'

    Write-Head 'Sẽ làm'
    if ($needMode) { Write-Plan ('Đặt Print Spooler tự khởi động cùng Windows (đang {0})' -f $script:StartModeText[$sp.StartMode]) }
    if ($sp.Running) { Write-Plan 'Dừng Print Spooler' }
    Write-Plan ('Xoá {0} trong thư mục hàng đợi: lệnh in đang chờ sẽ mất, cần in lại' -f $(if ($null -ne $files) { "$($files.Count) file" } else { 'các file' }))
    Write-Plan 'Bật lại Print Spooler'
    foreach ($p in $paused) { Write-Plan "Cho máy in '$($p.Name)' in tiếp (đang tạm dừng)" }
    foreach ($p in $offline) { Write-Plan "Tắt 'Dùng máy in ngoại tuyến' cho '$($p.Name)'" }
    if (-not (Confirm-Plan -DryRun:$DryRun)) { return 0 }

    $j = New-Journal 'sua-hang-doi' 'Sửa hàng đợi in'
    $ok = 0; $fail = 0
    if ($needMode) { if (Set-ServiceStartModeWithUndo $j 'Spooler' 'Automatic') { $ok++ } else { $fail++ } }
    $deps = @()
    try { $deps = @((Get-Service Spooler).DependentServices | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { $_.Name }) } catch { }
    try { Stop-SpoolerHard; Write-Ok 'Đã dừng Print Spooler.' } catch { Write-Bad "Không dừng được Print Spooler: $($_.Exception.Message.Trim())"; $fail++ }
    $removed = 0; $locked = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $spool -File -ErrorAction SilentlyContinue)) {
        try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $removed++ } catch { $locked++ }
    }
    if ($removed) {
        # Không hoàn tác được nhưng vẫn ghi để nhật ký đủ các việc đã làm.
        [void]$j.Data.changes.Add(@{ kind = 'spoolClear'; count = $removed; text = "Xoá $removed file trong thư mục hàng đợi in"; time = (Get-Date).ToString('s') })
        try { Save-Journal $j } catch { }
        Write-Ok "Đã xoá $removed file trong thư mục hàng đợi."
        $ok++
    } elseif (-not $locked) { Write-Info 'Thư mục hàng đợi đã trống.' }
    if ($locked) { Write-Warn "$locked file không xoá được (chương trình khác đang giữ). Khởi động lại máy rồi chạy lại."; $fail++ }
    try {
        Start-Service Spooler
        (Get-Service Spooler).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
        Write-Ok 'Đã bật lại Print Spooler.'
        $ok++
    } catch {
        Write-Bad "Không bật lại được Print Spooler: $($_.Exception.Message.Trim())"
        Write-Sub 'Khởi động lại máy; vẫn lỗi thì chạy công cụ "Sửa lỗi Windows" (SFC, DISM).'
        return 1
    }
    foreach ($d in $deps) { try { Start-Service $d -ErrorAction Stop } catch { } }
    Start-Sleep -Seconds 2
    foreach ($p in $paused) { if (Resume-PrinterWithUndo $j $p) { $ok++ } else { $fail++ } }
    foreach ($p in $offline) { if (Set-PrinterOnlineWithUndo $j $p) { $ok++ } else { $fail++ } }
    try { [void](Get-Printer -ErrorAction Stop); Write-Ok 'Dịch vụ in đã hoạt động. Gửi in lại tài liệu cần in.' }
    catch { Write-Bad "Dịch vụ in vẫn lỗi: $($_.Exception.Message.Trim())"; $fail++ }
    return (Get-ResultCode $ok $fail)
}

# ---------------------------------------------------------------- xoa-may-in-trung
function Invoke-XoaMayInTrung {
    param([switch]$DryRun)
    Write-Head 'Xoá máy in trùng'
    try { $printers = @(Get-PrinterList) }
    catch { Write-Bad "Không đọc được danh sách máy in: $($_.Exception.Message.Trim())"; Write-Sub 'Chạy "Sửa hàng đợi in bị kẹt" trước.'; return 2 }
    $names = @($printers | ForEach-Object { $_.Name })
    $groups = [ordered]@{}
    foreach ($p in $printers) {
        $base = Get-CopyBaseName $p.Name $names
        if (-not $base) { continue }
        if (-not $groups.Contains($base)) { $groups[$base] = New-Object System.Collections.ArrayList }
        [void]$groups[$base].Add($p)
    }
    foreach ($base in @($groups.Keys)) {
        $orig = @($printers | Where-Object { $_.Name -eq $base })
        if ($orig) { $groups[$base].Insert(0, $orig[0]) }
        elseif ($groups[$base].Count -lt 2) { $groups.Remove($base) }   # chỉ còn một bản "(Copy 1)": không có gì để xoá
    }
    if (-not $groups.Count) { Write-Ok 'Không có máy in trùng (dạng "(Copy 1)", "(Bản sao 1)").'; return 0 }

    $plan = @()
    $gi = 0
    foreach ($base in @($groups.Keys)) {
        $gi++
        $members = @($groups[$base])
        Write-Line ''
        Write-Line ('Nhóm {0}: {1}' -f $gi, $base)
        $best = 0; $bestScore = -1
        for ($i = 0; $i -lt $members.Count; $i++) {
            $m = $members[$i]
            $reach = Test-PrinterReach $m
            $jobs = @(Get-PrintJobsSafe $m.Name).Count
            # Ưu tiên giữ: kết nối được, không báo lỗi, đang là mặc định, mang tên gốc.
            $score = 0
            if ($reach -eq 'open') { $score += 4 } elseif ($reach -eq 'n/a') { $score += 1 }
            if ($m.Status -notmatch 'Offline|Error|NotAvailable') { $score += 2 }
            if ($m.Default) { $score += 1 }
            if ($m.Name -eq $base) { $score += 1 }
            if ($score -gt $bestScore) { $best = $i; $bestScore = $score }
            $bits = @((Get-PrinterStatusText $m.Status), (Get-PrinterKindText $m))
            switch ($reach) { 'open' { $bits += 'kết nối được' } 'n/a' { } 'noname' { $bits += 'không tìm thấy máy' } default { $bits += 'không kết nối được' } }
            if ($jobs) { $bits += "$jobs lệnh in đang chờ" }
            Write-Line ('  {0}. {1}{2}: {3}' -f ($i + 1), $m.Name, $(if ($m.Default) { ' (mặc định)' } else { '' }), ($bits -join '; '))
        }
        Write-Info ('Gợi ý giữ số {0}.' -f ($best + 1))
        $keepNo = if ($DryRun) { $best + 1 } else { Read-Number ('Giữ máy in số mấy? (Enter = {0}, 0 = bỏ qua nhóm này)' -f ($best + 1)) 0 $members.Count ($best + 1) }
        if (-not $keepNo) { Write-Info 'Bỏ qua nhóm này.'; continue }
        $keep = $members[$keepNo - 1]
        $plan += [pscustomobject]@{ Base = $base; Keep = $keep; Remove = @($members | Where-Object { $_.Name -ne $keep.Name }); Rename = ($keep.Name -ne $base) }
    }
    if (-not $plan) { Write-Info 'Không chọn nhóm nào, máy chưa thay đổi gì.'; return 0 }

    Write-Head 'Sẽ làm'
    foreach ($x in $plan) {
        foreach ($r in $x.Remove) { Write-Plan ("Xoá máy in '{0}'" -f $r.Name) }
        if ($x.Rename) { Write-Plan ("Đổi tên '{0}' thành '{1}'" -f $x.Keep.Name, $x.Base) }
        if (@($x.Remove | Where-Object { $_.Default })) { Write-Plan 'Đặt máy in giữ lại làm máy in mặc định' }
    }
    Write-Info 'Hoàn tác sẽ thêm lại máy in đã xoá với driver và cổng cũ; tuỳ chỉnh riêng (khay giấy, in hai mặt) của nó không giữ được.'
    if (-not (Confirm-Plan -DryRun:$DryRun)) { return 0 }

    $j = New-Journal 'xoa-may-in-trung' 'Xoá máy in trùng'
    $ok = 0; $fail = 0
    foreach ($x in $plan) {
        foreach ($r in $x.Remove) {
            $undo = @{ kind = 'printerRemoved'; printer = (Get-PrinterSnapshot $r) }
            if (Invoke-Change -Journal $j -Text ("Xoá máy in '{0}'" -f $r.Name) -Undo $undo -Action { Remove-Printer -Name $r.Name }) { $ok++ } else { $fail++ }
        }
        $final = $x.Keep.Name
        if ($x.Rename) {
            Start-Sleep -Seconds 1
            if (Get-Printer -Name $x.Base -ErrorAction SilentlyContinue) {
                Write-Warn ("Chưa đổi tên được: máy in '{0}' vẫn còn (đang chờ xoá vì còn lệnh in). In xong rồi chạy lại." -f $x.Base)
                $fail++
            } else {
                $undo = @{ kind = 'printerRenamed'; from = $x.Keep.Name; to = $x.Base }
                if (Invoke-Change -Journal $j -Text ("Đổi tên '{0}' thành '{1}'" -f $x.Keep.Name, $x.Base) -Undo $undo -Action { Rename-Printer -Name $x.Keep.Name -NewName $x.Base }) { $ok++; $final = $x.Base } else { $fail++ }
            }
        }
        if (@($x.Remove | Where-Object { $_.Default })) {
            # Không cần ghi nhật ký riêng: hoàn tác việc xoá thêm lại máy in cũ và đặt nó làm mặc định như trước.
            if (Invoke-Change -Journal $j -Text "Đặt '$final' làm máy in mặc định" -Action { [void](Invoke-CimMethod -InputObject (Get-WmiPrinter $final) -MethodName SetDefaultPrinter) }) { $ok++ } else { $fail++ }
        }
    }
    return (Get-ResultCode $ok $fail)
}

# ---------------------------------------------------------------- bat-chia-se
function Invoke-BatChiaSe {
    param([switch]$DryRun)
    Write-Head 'Bật chia sẻ file và máy in trên máy này'
    $profiles = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue)
    if (-not $profiles) { Write-Bad 'Máy chưa kết nối mạng nào.'; return 2 }
    $toPrivate = @()
    foreach ($np in $profiles) {
        Write-Line ("Mạng '{0}' ({1}): {2}" -f $np.Name, $np.InterfaceAlias, $np.NetworkCategory)
        if ([string]$np.NetworkCategory -ne 'Public') { continue }
        Write-Warn 'Chỉ đổi sang Private khi đây là mạng ở văn phòng hoặc nhà mà bạn tin cậy. Wi-Fi quán cà phê, sân bay, khách sạn: giữ Public.'
        if ($DryRun) { Write-Info 'Chạy thật sẽ hỏi có đổi mạng này sang Private không.'; $toPrivate += $np }
        elseif (Read-YesNo ("Đổi mạng '{0}' sang Private?" -f $np.Name) $false) { $toPrivate += $np }
    }
    # Hồ sơ tường lửa cần mở: 1 Domain, 2 Private. Không bao giờ mở cho Public.
    $mask = 0
    foreach ($np in $profiles) {
        $cat = [string]$np.NetworkCategory
        if ($cat -eq 'Private' -or @($toPrivate | Where-Object { $_.InterfaceIndex -eq $np.InterfaceIndex })) { $mask = $mask -bor 2 }
        elseif ($cat -eq 'DomainAuthenticated') { $mask = $mask -bor 1 }
    }
    if (-not $mask) {
        Write-Warn 'Không có mạng Private nào: chia sẻ vẫn bị chặn tới khi đổi mạng sang Private. Công cụ vẫn mở tường lửa cho mạng Private để dùng sau.'
        $mask = 2
    }
    $groupNames = [ordered]@{ '@FirewallAPI.dll,-28502' = 'Chia sẻ file và máy in'; '@FirewallAPI.dll,-32752' = 'Phát hiện mạng' }
    $ruleTodo = @()
    foreach ($gid in @($groupNames.Keys)) {
        foreach ($r in @(Get-NetFirewallRule -Group $gid -ErrorAction SilentlyContinue)) {
            if ([string]$r.Enabled -eq 'True') { continue }
            $rm = [int]$r.Profile
            if ($rm -eq 0) { $rm = 7 }
            $m = $rm -band $mask
            if (-not $m) { continue }
            $target = @()
            if ($m -band 1) { $target += 'Domain' }
            if ($m -band 2) { $target += 'Private' }
            $ruleTodo += [pscustomobject]@{ Rule = $r; Target = ($target -join ', '); Group = $gid }
        }
    }
    $svcPlan = @()
    $svcDefs = @(
        @{ Name = 'LanmanWorkstation'; Mode = 'Automatic'; IfMode = @('Manual', 'Disabled'); Start = $true }
        @{ Name = 'LanmanServer'; Mode = 'Automatic'; IfMode = @('Manual', 'Disabled'); Start = $true }
        @{ Name = 'FDResPub'; Mode = 'AutomaticDelayed'; IfMode = @('Manual', 'Disabled'); Start = $true }
        @{ Name = 'fdPHost'; Mode = 'Manual'; IfMode = @('Disabled'); Start = $true }
        @{ Name = 'SSDPSRV'; Mode = 'Manual'; IfMode = @('Disabled'); Start = $false }
        @{ Name = 'upnphost'; Mode = 'Manual'; IfMode = @('Disabled'); Start = $false }
        @{ Name = 'lmhosts'; Mode = 'Manual'; IfMode = @('Disabled'); Start = $true }
    )
    foreach ($d in $svcDefs) {
        $s = Get-ServiceState $d.Name
        if (-not $s) { continue }
        $setMode = $s.StartMode -in $d.IfMode
        $start = $d.Start -and -not $s.Running
        if ($setMode -or $start) { $svcPlan += [pscustomobject]@{ State = $s; Mode = $(if ($setMode) { $d.Mode } else { $null }); Start = $start } }
    }
    $aliases = @($profiles | ForEach-Object { $_.InterfaceAlias })
    $bindTodo = @(Get-NetAdapterBinding -ComponentID ms_msclient, ms_server -ErrorAction SilentlyContinue | Where-Object { $_.Name -in $aliases -and -not $_.Enabled })
    $shareTodo = @()
    $local = @()
    try { $local = @(Get-PrinterList | Where-Object { $_.Kind -notin 'ao', 'connection' -and -not $_.Shared }) } catch { }
    if ($local) {
        Write-Line 'Máy in trên máy này có thể chia sẻ cho máy khác:'
        for ($i = 0; $i -lt $local.Count; $i++) { Write-Line ('  {0}. {1}' -f ($i + 1), $local[$i].Name) }
        if ($DryRun) { Write-Info 'Chạy thật sẽ hỏi chia sẻ máy in nào (có thể bỏ qua).' }
        else {
            $picked = @{}
            foreach ($tok in @((Read-Text 'Chia sẻ máy in nào? Gõ số, nhiều số cách nhau dấu phẩy; Enter để bỏ qua') -split '[,; ]+' | Where-Object { $_ })) {
                $n = 0
                if ([int]::TryParse($tok, [ref]$n) -and $n -ge 1 -and $n -le $local.Count -and -not $picked[$n]) { $picked[$n] = $true; $shareTodo += $local[$n - 1] }
            }
        }
    }

    Write-Head 'Sẽ làm'
    $any = $false
    foreach ($np in $toPrivate) { Write-Plan ("Đổi mạng '{0}' ({1}) từ Public sang Private" -f $np.Name, $np.InterfaceAlias); $any = $true }
    foreach ($gid in @($groupNames.Keys)) {
        $rs = @($ruleTodo | Where-Object { $_.Group -eq $gid })
        if (-not $rs) { continue }
        Write-Plan ("Tường lửa: bật {0} quy tắc '{1}' cho mạng {2} (không mở trên mạng Public)" -f $rs.Count, $groupNames[$gid], (@($rs | ForEach-Object { $_.Target } | Select-Object -Unique) -join ', '))
        $any = $true
    }
    foreach ($x in $svcPlan) {
        $parts = @()
        if ($x.Mode) { $parts += ('đặt ' + $script:StartModeText[$x.Mode]) }
        if ($x.Start) { $parts += 'bật' }
        Write-Plan ('Dịch vụ {0} ({1}): {2}' -f $x.State.DisplayName, $x.State.Name, ($parts -join ', '))
        $any = $true
    }
    foreach ($b in $bindTodo) { Write-Plan ("Bật '{0}' trên card {1}" -f $b.DisplayName, $b.Name); $any = $true }
    foreach ($p in $shareTodo) { Write-Plan ("Chia sẻ máy in '{0}' với tên {1}" -f $p.Name, (Get-ShareNameFor $p.Name)); $any = $true }
    if (-not $any) { Write-Ok 'Máy đã bật đủ chia sẻ, không cần đổi gì.'; Show-ShareAccessInfo; return 0 }
    if (-not (Confirm-Plan -DryRun:$DryRun)) { return 0 }

    $j = New-Journal 'bat-chia-se' 'Bật chia sẻ file và máy in'
    $ok = 0; $fail = 0
    foreach ($np in $toPrivate) { if (Set-NetworkPrivateWithUndo $j $np) { $ok++ } else { $fail++ } }
    foreach ($gid in @($groupNames.Keys)) {
        $rs = @($ruleTodo | Where-Object { $_.Group -eq $gid })
        if (-not $rs) { continue }
        $n = 0
        foreach ($x in $rs) { if (Enable-FirewallRuleWithUndo $j $x.Rule $x.Target) { $n++ } else { $fail++ } }
        if ($n) { Write-Ok ("Tường lửa: đã bật {0} quy tắc '{1}'." -f $n, $groupNames[$gid]); $ok++ }
    }
    foreach ($x in $svcPlan) {
        if ($x.Mode) { if (Set-ServiceStartModeWithUndo $j $x.State.Name $x.Mode) { $ok++ } else { $fail++; continue } }
        if ($x.Start) { if (Start-ServiceWithUndo $j $x.State.Name) { $ok++ } else { $fail++ } }
    }
    foreach ($b in $bindTodo) { if (Enable-AdapterBindingWithUndo $j $b) { $ok++ } else { $fail++ } }
    foreach ($p in $shareTodo) { if (Set-PrinterSharedWithUndo $j $p (Get-ShareNameFor $p.Name)) { $ok++ } else { $fail++ } }
    $fw = Get-ServiceState 'MpsSvc'
    if ($shareTodo -and $fw -and -not $fw.Running) {
        Write-Warn 'Tường lửa Windows đang tắt: máy khác kết nối máy in chia sẻ sẽ báo 0x000006D9. Bật lại trong Windows Security.'
    }
    Show-ShareAccessInfo
    return (Get-ResultCode $ok $fail)
}

# ---------------------------------------------------------------- ket-noi-may-in
function Invoke-KetNoiMayIn {
    param([string]$MayChu, [string]$TenChiaSe, [switch]$ChoMoiNguoi, [switch]$DryRun)
    Write-Head 'Kết nối máy in chia sẻ'
    $target = ([string]$MayChu).Trim()
    if (-not $target) { $target = Read-Text 'Tên hoặc IP máy đang chia sẻ máy in (vd PC-KETOAN)' }
    if (-not $target) { Write-Info 'Chưa nhập tên máy, máy chưa thay đổi gì.'; return 2 }
    $hostName = $target.TrimStart('\').Split('\')[0]
    if ($target -like '\\*' -and -not $TenChiaSe) { $u = Split-UncPath $target; if ($u) { $TenChiaSe = $u.Share } }
    if (-not (Test-HostName $hostName)) { Write-Bad "Tên máy '$hostName' không hợp lệ."; return 1 }
    $ip = $null
    try { $ip = @(Resolve-HostAddress $hostName)[0] } catch { }
    if (-not $ip) { Write-Bad "Không tìm thấy máy '$hostName' trong mạng."; Write-Sub 'Kiểm tra tên máy, hoặc dùng địa chỉ IP của máy đó.'; return 2 }
    $ports = Test-TcpPorts -Address $ip -Ports 445, 135
    Write-Line ('Máy {0} ({1}): cổng 445 {2}, cổng 135 {3}.' -f $hostName, $ip, $script:PortStateText[$ports[445]], $script:PortStateText[$ports[135]])
    if ($ports[445] -ne 'open') { Write-ErrorHelp 53; return 2 }
    if ($ports[135] -ne 'open') {
        Write-Warn 'Cổng 135 (RPC) không mở: kết nối có thể lỗi 0x000006BA hoặc 0x00000709.'
        Write-Sub 'Trên máy chia sẻ chạy "Bật chia sẻ file và máy in".'
    }
    $sl = Get-ShareList $hostName
    $prs = @($sl.Shares | Where-Object { $_.Kind -eq 'may-in' })
    if ($sl.Code -ne 0) {
        Write-ErrorHelp $sl.Code -Prefix 'Không xem được danh sách chia sẻ, lỗi'
        if ($sl.Code -in 5, 86, 1326) { Write-Sub 'Máy kia cần tài khoản: chạy "Kết nối thư mục chia sẻ" một lần với tài khoản của máy đó (Windows lưu lại), rồi kết nối máy in.' }
    } elseif ($prs) {
        Write-Line 'Máy in đang chia sẻ:'
        for ($i = 0; $i -lt $prs.Count; $i++) { Write-Line ('  {0}. {1}{2}' -f ($i + 1), $prs[$i].Name, $(if ($prs[$i].Remark) { "  ($($prs[$i].Remark))" } else { '' })) }
    } elseif (-not $TenChiaSe) {
        Write-Bad "Máy $hostName không chia sẻ máy in nào."
        Write-Sub 'Trên máy đó chạy "Bật chia sẻ file và máy in" và chọn máy in cần chia sẻ.'
        return 2
    }
    if (-not $TenChiaSe) {
        if ($prs.Count -eq 1) { $TenChiaSe = $prs[0].Name }
        elseif ($prs.Count -gt 1) {
            $n = if ($DryRun) { 1 } else { Read-Number 'Kết nối máy in số mấy?' 1 $prs.Count $null }
            if (-not $n) { Write-Info 'Chưa chọn máy in, máy chưa thay đổi gì.'; return 0 }
            $TenChiaSe = $prs[$n - 1].Name
        } else {
            $TenChiaSe = Read-Text 'Tên chia sẻ của máy in (vd HP)'
            if (-not $TenChiaSe) { Write-Info 'Chưa có tên máy in, máy chưa thay đổi gì.'; return 2 }
        }
    }
    if ($TenChiaSe -match '[\\/:*?"<>|]') { Write-Bad 'Tên chia sẻ có ký tự không hợp lệ.'; return 1 }
    $conn = "\\$hostName\$TenChiaSe"
    if (Get-Printer -Name $conn -ErrorAction SilentlyContinue) { Write-Ok "Máy này đã kết nối $conn."; return 0 }
    $me = Get-CurrentUser
    $console = Get-ConsoleUser
    $perMachine = [bool]$ChoMoiNguoi
    if (-not $perMachine -and $console -and $console -ne $me) {
        # UAC hỏi mật khẩu một Admin khác: kết nối thêm cho tài khoản Admin đó sẽ không hiện với người dùng máy.
        Write-Warn "Đang chạy bằng $me nhưng người dùng máy là $console`: kết nối riêng cho $me sẽ không hiện với $console."
        if ($DryRun -or (Read-YesNo 'Thêm cho mọi tài khoản trên máy này?' $true)) { $perMachine = $true }
    }

    Write-Head 'Sẽ làm'
    if ($perMachine) { Write-Plan "Thêm máy in $conn cho mọi tài khoản trên máy (hiện sau khi đăng nhập lại)" }
    else { Write-Plan "Thêm máy in $conn cho tài khoản $me" }
    Write-Info 'Windows tải driver từ máy chia sẻ. Công cụ chạy bằng quyền Admin nên tránh được lỗi 0x00000BCB.'
    if (-not (Confirm-Plan -DryRun:$DryRun -Question 'Kết nối ngay?')) { return 0 }

    $j = New-Journal 'ket-noi-may-in' "Kết nối máy in $conn"
    $undo = @{ kind = 'printerConnection'; connectionName = $conn; perMachine = $perMachine }
    if ($perMachine) {
        $done = Invoke-Change -Journal $j -Text "Thêm $conn cho mọi tài khoản" -Undo $undo -Action {
            [void](Start-Process rundll32.exe -ArgumentList ('printui.dll,PrintUIEntry /ga /q /n"{0}"' -f $conn) -Wait -PassThru)
            if (-not (Test-Path -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Control\Print\Connections\,,{0},{1}' -f $hostName, $TenChiaSe))) {
                throw 'Windows không ghi nhận kết nối. Kiểm tra tên máy in, hoặc thử thêm cho riêng tài khoản này.'
            }
        }
        if (-not $done) { return 1 }
        Write-Info 'Máy in hiện với mọi tài khoản sau khi đăng xuất rồi đăng nhập lại (hoặc khởi động lại máy).'
        return 0
    }
    if (-not (Invoke-Change -Journal $j -Text "Kết nối máy in $conn" -Undo $undo -Action { Add-Printer -ConnectionName $conn })) {
        switch ($script:LastChangeError) {
            283 { Write-Sub 'Lỗi này cần sửa trên máy chia sẻ. Máy in có cổng mạng thì cách bền nhất là thêm thẳng bằng IP trên từng máy.' }
            { $_ -in 1801, 3012, 1722 } { Write-Sub 'Thử "Nới bảo mật" > RPC qua named pipe trên máy này, rồi kết nối lại.' }
            { $_ -in 3019, 124 } { Write-Sub 'Cài sẵn driver của hãng (đúng đời máy in) trên máy này, rồi kết nối lại.' }
        }
        return 1
    }
    if (Read-YesNo 'In trang thử?' $false) { Invoke-TestPage $conn }
    return 0
}

# ---------------------------------------------------------------- them-may-in-ip
function Invoke-ThemMayInIp {
    param([string]$DiaChi, [string]$TenMayIn, [string]$Kieu = 'tu-dong', [switch]$DryRun)
    Write-Head 'Thêm máy in mạng bằng địa chỉ IP'
    $addr = ([string]$DiaChi).Trim()
    if (-not $addr) { $addr = Read-Text 'Địa chỉ IP của máy in (vd 192.168.1.50)' }
    if (-not $addr) { Write-Info 'Chưa nhập địa chỉ, máy chưa thay đổi gì.'; return 2 }
    if (-not (Test-HostName $addr)) { Write-Bad "Địa chỉ '$addr' không hợp lệ."; return 1 }
    $ip = $null
    try { $ip = @(Resolve-HostAddress $addr)[0] } catch { }
    if (-not $ip) { Write-Bad "Không tìm thấy '$addr' trong mạng."; return 2 }
    $alive = Test-Ping $ip
    $portList = 9100, 631, 515, 80, 443
    $ports = Test-TcpPorts -Address $ip -Ports $portList
    Write-Line ('{0}: ping {1}' -f $ip, $(if ($alive) { 'có trả lời' } else { 'không trả lời' }))
    foreach ($port in $portList) { Write-Sub ('Cổng {0}, {1}: {2}' -f $port, $script:PortRole[$port], $script:PortStateText[$ports[$port]]) }
    if ($ports[631] -ne 'open' -and $ports[9100] -ne 'open') {
        if ($ports[515] -eq 'open') { Write-Bad 'Máy in chỉ mở cổng LPR (515): công cụ chưa hỗ trợ, thêm tay ở Settings > Printers & scanners > Add device > Add manually.' }
        elseif ($alive -or @($ports.Values | Where-Object { $_ -in 'open', 'closed' })) { Write-Bad "$ip có trả lời nhưng không mở cổng in (9100, 631): có thể không phải máy in, hoặc máy in đã tắt in qua mạng." }
        else {
            Write-Bad "Không thấy thiết bị nào ở $ip."
            Write-Sub 'Kiểm tra máy in đã bật, cùng mạng với máy này; xem IP trên màn hình máy in hoặc in trang cấu hình mạng.'
        }
        return 2
    }
    $existing = @()
    try { $existing = @(Get-PrinterList | Where-Object { $_.Address -and ($_.Address -eq [string]$ip -or $_.Address -eq $addr) }) } catch { }
    if ($existing) {
        Write-Warn ('Đã có máy in dùng địa chỉ này: {0}.' -f (($existing | ForEach-Object { $_.Name }) -join ', '))
        if (-not $DryRun -and -not (Read-YesNo 'Vẫn thêm một máy in nữa?' $false)) { Write-Info 'Máy chưa thay đổi gì.'; return 0 }
    }
    $method = $Kieu
    if ($method -eq 'tu-dong') { $method = if ($ports[631] -eq 'open') { 'ipp' } else { 'raw' } }
    if ($method -eq 'ipp' -and $ports[631] -ne 'open') { Write-Warn 'Cổng 631 (IPP) không mở: dùng cổng 9100.'; $method = 'raw' }
    if ($method -eq 'raw' -and $ports[9100] -ne 'open') { Write-Warn 'Cổng 9100 không mở: dùng IPP.'; $method = 'ipp' }
    $name = if ($TenMayIn) { $TenMayIn.Trim() } else { "Máy in $ip" }
    if ($name -match '[\\,"]') { Write-Bad 'Tên máy in không được có dấu \ , hoặc ".'; return 1 }
    if (Get-Printer -Name $name -ErrorAction SilentlyContinue) { Write-Bad "Đã có máy in tên '$name'. Đặt tên khác."; return 1 }
    $driver = $null
    if ($method -eq 'raw') {
        $driver = Select-PrinterDriver -DryRun:$DryRun
        if (-not $driver) {
            if ($ports[631] -eq 'open') { Write-Sub 'Máy in này hỗ trợ IPP (cổng 631): chọn cách kết nối IPP thì không cần driver hãng.' }
            return 2
        }
    }
    $portName = "IP_$ip"
    $hasPort = [bool](Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)

    Write-Head 'Sẽ làm'
    if ($method -eq 'ipp') {
        Write-Plan ("Thêm máy in '{0}' qua IPP: http://{1}:631/ipp/print, dùng driver chung của Windows, không cần driver hãng" -f $name, $ip)
    } else {
        if ($hasPort) { Write-Plan "Dùng cổng có sẵn $portName" } else { Write-Plan "Tạo cổng TCP/IP $portName ($ip, cổng 9100)" }
        Write-Plan ("Thêm máy in '{0}' với driver {1}" -f $name, $driver)
    }
    if (-not (Confirm-Plan -DryRun:$DryRun -Question 'Thêm ngay?')) { return 0 }

    $j = New-Journal 'them-may-in-ip' "Thêm máy in $ip"
    if ($method -eq 'ipp') {
        $undo = @{ kind = 'printerAdded'; name = $name; portCreated = $null }
        if (-not (Invoke-Change -Journal $j -Text "Thêm máy in '$name' qua IPP" -Undo $undo -Action { Add-Printer -Name $name -IppURL ('http://{0}:631/ipp/print' -f $ip) })) {
            if ($ports[9100] -eq 'open' -and $Kieu -ne 'ipp' -and @(Get-VendorDriverNames).Count) {
                Write-Info 'IPP không được: thử lại qua cổng 9100 với driver của hãng.'
                return (Invoke-ThemMayInIp -DiaChi $addr -TenMayIn $TenMayIn -Kieu 'raw')
            }
            return 1
        }
    } else {
        $portCreated = $null
        if (-not $hasPort) {
            # Cổng không ghi nhật ký riêng: hoàn tác máy in xoá luôn cổng công cụ đã tạo (portCreated).
            if (-not (Invoke-Change -Journal $j -Text "Tạo cổng $portName" -Action { Add-PrinterPort -Name $portName -PrinterHostAddress ([string]$ip) -PortNumber 9100 })) { return 1 }
            $portCreated = $portName
        }
        $undo = @{ kind = 'printerAdded'; name = $name; portCreated = $portCreated }
        if (-not (Invoke-Change -Journal $j -Text "Thêm máy in '$name' ($driver)" -Undo $undo -Action { Add-Printer -Name $name -DriverName $driver -PortName $portName })) {
            if ($portCreated) { try { Remove-PrinterPort -Name $portCreated -ErrorAction Stop } catch { } }
            return 1
        }
    }
    Write-Info 'Nên đặt IP cố định cho máy in (trên máy in, hoặc giữ IP trên router): IP đổi thì máy in báo Offline.'
    if (Read-YesNo 'In trang thử?' $false) { Invoke-TestPage $name }
    return 0
}

# ---------------------------------------------------------------- ket-noi-thu-muc (chạy quyền thường)
function Invoke-KetNoiThuMuc {
    param([string]$DuongDan, [string]$ODia, [string]$TaiKhoan, [switch]$Ngat, [switch]$DryRun)
    if ($Ngat) { return (Invoke-NgatThuMuc -DuongDan $DuongDan -ODia $ODia -DryRun:$DryRun) }
    Write-Head 'Kết nối thư mục chia sẻ thành ổ mạng'
    if ((Test-IsAdmin) -and (Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLinkedConnections') -ne 1) {
        Write-Bad 'Đang chạy bằng quyền Admin: ổ mạng gắn ở đây không hiện trong File Explorer của bạn.'
        Write-Sub 'Chạy lại không có quyền Admin: trong Trạm Tool nút này đã chạy quyền thường; bấm đúp MAY_IN_LAN.bat thì chọn mục 7.'
        return 2
    }
    $path = ([string]$DuongDan).Trim()
    if (-not $path) { $path = Read-Text 'Đường dẫn thư mục chia sẻ (vd \\PC-KETOAN\TaiLieu)' }
    $u = Split-UncPath $path
    if (-not $u) { Write-Bad "Đường dẫn '$path' không đúng dạng \\tên-máy\thư-mục."; return 1 }
    $maps = @(Get-MappedDrives)
    $same = @($maps | Where-Object { $_.Remote -eq $u.Path })
    if ($same) { Write-Ok ('Thư mục này đã gắn ở ổ {0}.' -f $same[0].Letter); return 0 }
    $used = @([IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 2).ToUpperInvariant() }) + @($maps | ForEach-Object { $_.Letter })
    if ($ODia) {
        $letter = $ODia.Trim().TrimEnd(':').ToUpperInvariant() + ':'
        if ($letter -notmatch '^[A-Z]:$') { Write-Bad "Chữ ổ '$ODia' không hợp lệ."; return 1 }
        if ($used -contains $letter) { Write-ErrorHelp 85; return 2 }
    } else {
        $letter = $null
        foreach ($c in [char[]]'ZYXWVUTSRQPONMLKJIHGFED') { if ($used -notcontains "$($c):") { $letter = "$($c):"; break } }
        if (-not $letter) { Write-Bad 'Hết chữ ổ đĩa trống.'; return 2 }
    }
    $ip = $null
    try { $ip = @(Resolve-HostAddress $u.Host)[0] } catch { }
    if (-not $ip) { Write-Bad "Không tìm thấy máy '$($u.Host)' trong mạng."; Write-Sub 'Thử dùng địa chỉ IP thay cho tên máy, vd \\192.168.1.20\TaiLieu.'; return 2 }
    $state = (Test-TcpPorts -Address $ip -Ports 445)[445]
    Write-Line ('Máy {0} ({1}): cổng 445 {2}.' -f $u.Host, $ip, $script:PortStateText[$state])
    if ($state -ne 'open') { Write-ErrorHelp 53; return 2 }
    $saved = @(Get-SavedNetworkCredentials | Where-Object { $_.Target -eq $u.Host })

    Write-Head 'Sẽ làm'
    if ($TaiKhoan) {
        Write-Plan ('Lưu tài khoản {0} cho máy {1} vào Windows; mật khẩu gõ ở bước sau, không hiện ra màn hình{2}' -f $TaiKhoan, $u.Host, $(if ($saved) { " (thay tài khoản đã lưu $($saved[0].User))" } else { '' }))
    } elseif ($saved) {
        Write-Line ('Dùng tài khoản đã lưu cho {0}: {1}.' -f $u.Host, $saved[0].User)
    }
    Write-Plan ('Gắn ổ {0} → {1}, tự kết nối lại mỗi lần đăng nhập' -f $letter, $u.Path)
    if (-not (Confirm-Plan -DryRun:$DryRun -Question 'Kết nối ngay?')) { return 0 }

    if ($TaiKhoan) {
        Write-Info 'Gõ mật khẩu của tài khoản trên máy chia sẻ rồi bấm Enter (ký tự không hiện ra là bình thường).'
        & cmdkey.exe "/add:$($u.Host)" "/user:$TaiKhoan" '/pass'
        if ($LASTEXITCODE -ne 0) { Write-Bad 'Không lưu được tài khoản vào Windows (cmdkey).'; return 1 }
    }
    $rc = [MayInLan.Native]::MapDrive($letter, $u.Path, $true)
    if ($rc -ne 0) {
        Write-ErrorHelp ([int64]$rc) -Prefix 'Không kết nối được, lỗi'
        if ($rc -in 5, 86, 1326 -and -not $TaiKhoan) { Write-Sub 'Chạy lại và nhập Tài khoản của máy chia sẻ.' }
        return 1
    }
    Write-Ok ('Đã gắn ổ {0} → {1}.' -f $letter, $u.Path)
    if (Read-YesNo "Mở ổ $letter trong File Explorer?" $true) { Start-Process explorer.exe "$letter\" }
    return 0
}

function Invoke-NgatThuMuc {
    param([string]$DuongDan, [string]$ODia, [switch]$DryRun)
    Write-Head 'Ngắt ổ mạng'
    $maps = @(Get-MappedDrives)
    $targets = @()
    if ($ODia) {
        $l = $ODia.Trim().TrimEnd(':').ToUpperInvariant() + ':'
        $targets = @($maps | Where-Object { $_.Letter -eq $l })
        if (-not $targets) { $targets = @([pscustomobject]@{ Letter = $l; Remote = '(ổ tạm)'; User = '' }) }
    } elseif ($DuongDan) {
        $u = Split-UncPath $DuongDan
        if ($u) { $targets = @($maps | Where-Object { $_.Remote -eq $u.Path }) }
    } else {
        if (-not $maps) { Write-Info 'Không có ổ mạng nào.'; return 0 }
        for ($i = 0; $i -lt $maps.Count; $i++) { Write-Line ('  {0}. {1} → {2}' -f ($i + 1), $maps[$i].Letter, $maps[$i].Remote) }
        $n = if ($DryRun) { $null } else { Read-Number 'Ngắt ổ số mấy? (Enter để huỷ)' 1 $maps.Count $null }
        if (-not $n) { Write-Info 'Chưa chọn ổ, máy chưa thay đổi gì.'; return 0 }
        $targets = @($maps[$n - 1])
    }
    if (-not $targets) { Write-Info 'Không thấy ổ mạng nào khớp.'; return 0 }
    $hosts = @($targets | ForEach-Object { $h = Split-UncPath $_.Remote; if ($h) { $h.Host } } | Select-Object -Unique)
    $creds = @(Get-SavedNetworkCredentials | Where-Object { $_.Target -in $hosts })

    Write-Head 'Sẽ làm'
    foreach ($t in $targets) { Write-Plan ('Ngắt ổ {0} ({1})' -f $t.Letter, $t.Remote) }
    if ($creds) { Write-Info 'Sau đó sẽ hỏi có xoá mật khẩu đã lưu cho máy đó không.' }
    if (-not (Confirm-Plan -DryRun:$DryRun -Question 'Ngắt ngay?')) { return 0 }

    $fail = 0
    foreach ($t in $targets) {
        $rc = [MayInLan.Native]::UnmapDrive($t.Letter, $true, $false)
        if ($rc -in 2401, 2404) {
            Write-ErrorHelp $rc
            if (Read-YesNo 'Ngắt bắt buộc? File đang mở trên ổ này có thể mất phần chưa lưu.' $false) { $rc = [MayInLan.Native]::UnmapDrive($t.Letter, $true, $true) }
        }
        if ($rc -eq 2250 -and (Test-Path -LiteralPath ('HKCU:\Network\' + $t.Letter.TrimEnd(':')))) {
            # Ổ nhớ sẵn nhưng chưa nối lại được: xoá phần ghi nhớ để Windows thôi nối lại khi đăng nhập.
            Remove-Item -LiteralPath ('HKCU:\Network\' + $t.Letter.TrimEnd(':'))
            $rc = 0
        }
        if ($rc -eq 0) { Write-Ok "Đã ngắt ổ $($t.Letter)." } else { Write-ErrorHelp ([int64]$rc); $fail++ }
    }
    foreach ($c in $creds) {
        if (Read-YesNo ('Xoá cả mật khẩu đã lưu cho máy {0} (tài khoản {1})?' -f $c.Target, $c.User) $false) {
            $r = Invoke-Native 'cmdkey.exe' @("/delete:$($c.Target)")
            if ($r.Code -eq 0) { Write-Ok "Đã xoá mật khẩu đã lưu cho $($c.Target)." } else { Write-Warn "Không xoá được mật khẩu đã lưu cho $($c.Target)." }
        }
    }
    if ($fail) { return 1 }
    return 0
}

# ---------------------------------------------------------------- noi-bao-mat
function Get-SecurityOptionState {
    param([string]$Id)
    switch ($Id) {
        'rpc-named-pipe' { return ((Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC' 'RpcUseNamedPipeProtocol') -eq 1) }
        'rpc-privacy-off' { return ((Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' 'RpcAuthnLevelPrivacyEnabled') -eq 0) }
        'smb-guest' { $c = Get-SmbClientConfiguration; return ($c.EnableInsecureGuestLogons -and -not $c.RequireSecuritySignature) }
        'smb-signing-off' { return (-not (Get-SmbClientConfiguration).RequireSecuritySignature) }
    }
    return $false
}

function Invoke-NoiBaoMat {
    param([string]$Muc, [switch]$DryRun)
    Write-Head 'Nới bảo mật cho thiết bị cũ'
    Write-Warn 'Chỉ dùng khi đã thử cách an toàn mà vẫn lỗi. Mỗi mục làm máy dễ bị tấn công hơn trong mạng nội bộ.'
    Write-Info 'Công cụ không bao giờ bật SMB1: thiết bị chỉ chạy SMB1 thì cập nhật firmware hoặc thay thiết bị.'
    $ids = @($script:SecurityOptions.Keys)
    for ($i = 0; $i -lt $ids.Count; $i++) {
        $o = $script:SecurityOptions[$ids[$i]]
        $on = $false
        try { $on = Get-SecurityOptionState $ids[$i] } catch { }
        Write-Line ('{0}. {1}{2}' -f ($i + 1), $o.Label, $(if ($on) { '  [đang nới]' } else { '' }))
        Write-Sub ('Khi nào: ' + $o.When)
    }
    if (-not $Muc) {
        $n = if ($DryRun) { $null } else { Read-Number 'Chọn mục (Enter để huỷ)' 1 $ids.Count $null }
        if (-not $n) { Write-Info 'Chưa chọn mục nào, máy chưa thay đổi gì.'; return 0 }
        $Muc = $ids[$n - 1]
    }
    $opt = $script:SecurityOptions[$Muc]
    if (-not $opt) { Write-Bad "Không có mục '$Muc'."; return 1 }
    if ($Muc -eq 'rpc-privacy-off' -and -not @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Shared })) {
        Write-Warn 'Máy này không chia sẻ máy in nào: mục này chỉ có tác dụng trên máy CHIA SẺ máy in.'
        if (-not $DryRun -and -not (Read-YesNo 'Vẫn làm?' $false)) { Write-Info 'Máy chưa thay đổi gì.'; return 0 }
    }

    Write-Head 'Sẽ làm'
    switch ($Muc) {
        'rpc-named-pipe' { Write-Plan 'Đặt chính sách RpcUseNamedPipeProtocol = 1 (HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC), khởi động lại dịch vụ in' }
        'rpc-privacy-off' { Write-Plan 'Đặt RpcAuthnLevelPrivacyEnabled = 0 (HKLM\SYSTEM\CurrentControlSet\Control\Print), khởi động lại dịch vụ in' }
        'smb-guest' { Write-Plan 'Cho đăng nhập khách (EnableInsecureGuestLogons), không bắt buộc ký SMB (RequireSecuritySignature)' }
        'smb-signing-off' { Write-Plan 'Không bắt buộc ký SMB khi vào máy khác (RequireSecuritySignature)' }
    }
    Write-Warn ('Rủi ro: ' + $opt.Risk)
    Write-Info 'Mọi thay đổi ghi vào nhật ký; chạy "Hoàn tác lần sửa trước" để bật lại bảo mật.'
    if ($DryRun) { Write-Info 'Chạy thử: máy chưa thay đổi gì.'; return 0 }
    if (-not (Confirm-Strong)) { Write-Info 'Đã huỷ, máy chưa thay đổi gì.'; return 0 }

    $j = New-Journal 'noi-bao-mat' ('Nới bảo mật: ' + $opt.Label)
    $ok = 0; $fail = 0
    $restartSpooler = $false
    switch ($Muc) {
        'rpc-named-pipe' {
            if (Set-RegistryDwordWithUndo $j 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC' 'RpcUseNamedPipeProtocol' 1 'Bật RPC qua named pipe khi kết nối máy in chia sẻ') { $ok++; $restartSpooler = $true } else { $fail++ }
        }
        'rpc-privacy-off' {
            if (Set-RegistryDwordWithUndo $j 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' 'RpcAuthnLevelPrivacyEnabled' 0 'Tắt mã hoá RPC cho máy in chia sẻ trên máy này') { $ok++; $restartSpooler = $true } else { $fail++ }
        }
        'smb-guest' {
            if (Set-SmbClientWithUndo $j 'EnableInsecureGuestLogons' $true 'Cho đăng nhập khách (guest) khi vào thư mục chia sẻ') { $ok++ } else { $fail++ }
            if (Set-SmbClientWithUndo $j 'RequireSecuritySignature' $false 'Không bắt buộc ký SMB (khách không ký được)') { $ok++ } else { $fail++ }
            $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation'
            if ((Get-RegValue $pol 'AllowInsecureGuestAuth') -eq 0) {
                if (Set-RegistryDwordWithUndo $j $pol 'AllowInsecureGuestAuth' 1 'Chính sách nhóm: cho đăng nhập khách') { $ok++ } else { $fail++ }
            }
        }
        'smb-signing-off' {
            if (Set-SmbClientWithUndo $j 'RequireSecuritySignature' $false 'Không bắt buộc ký SMB khi vào máy khác') { $ok++ } else { $fail++ }
        }
    }
    if ($restartSpooler) {
        try { Restart-Spooler; Write-Ok 'Đã khởi động lại dịch vụ in để áp dụng.' }
        catch { Write-Warn 'Chưa khởi động lại được dịch vụ in: khởi động lại máy để áp dụng.' }
    }
    Write-Info 'Xong việc cần thiết (hoặc đã cập nhật thiết bị) thì chạy "Hoàn tác lần sửa trước" để bật lại bảo mật.'
    return (Get-ResultCode $ok $fail)
}

# ---------------------------------------------------------------- hoan-tac
function Invoke-HoanTac {
    param([string]$NhatKy, [switch]$DryRun)
    Write-Head 'Hoàn tác lần sửa trước'
    $entries = @(Get-JournalEntries)
    if (-not $entries) { Write-Info 'Chưa có lần sửa nào để hoàn tác.'; return 0 }
    $pick = $null
    if ($NhatKy) {
        $pick = @($entries | Where-Object { $_.File.Name -eq $NhatKy -or $_.File.BaseName -eq $NhatKy })[0]
        if (-not $pick) { Write-Bad "Không thấy nhật ký '$NhatKy'."; return 1 }
    } else {
        $show = @($entries | Select-Object -First 15)
        $default = $null
        for ($i = 0; $i -lt $show.Count; $i++) {
            $d = $show[$i].Data
            $when = [string]$d.started
            try { $when = ([datetime]$d.started).ToString('dd/MM/yyyy HH:mm') } catch { }
            $state = if ($d.undone) { 'đã hoàn tác' } else { '{0} thay đổi' -f @($d.changes).Count }
            if (-not $d.undone -and $null -eq $default) { $default = $i + 1 }
            Write-Line ('  {0}. {1}  {2} ({3})' -f ($i + 1), $when, $d.title, $state)
        }
        if ($null -eq $default) { Write-Info 'Các lần sửa trong danh sách đều đã hoàn tác.'; return 0 }
        $n = if ($DryRun) { $default } else { Read-Number ('Hoàn tác lần số mấy? (Enter = {0})' -f $default) 1 $show.Count $default }
        if (-not $n) { return 0 }
        $pick = $show[$n - 1]
    }
    $d = $pick.Data
    if ($d.computer -and $d.computer -ne $env:COMPUTERNAME) { Write-Bad "Nhật ký này của máy $($d.computer), không phải máy này."; return 1 }
    if ($d.undone) {
        Write-Warn 'Lần sửa này đã được hoàn tác trước đó.'
        if ($DryRun -or -not (Read-YesNo 'Vẫn chạy hoàn tác lại?' $false)) { return 0 }
    }
    $changes = @($d.changes)
    if (-not $changes) { Write-Info 'Lần sửa này không có thay đổi nào.'; return 0 }

    Write-Head 'Sẽ làm'
    for ($i = $changes.Count - 1; $i -ge 0; $i--) { Write-Plan ('Hoàn tác: ' + $changes[$i].text) }
    if (-not (Confirm-Plan -DryRun:$DryRun -Question 'Hoàn tác ngay?')) { return 0 }

    $r = Invoke-UndoJournal $pick
    if (@($changes | Where-Object { $_.kind -eq 'registry' -and $_.path -match 'Printers\\RPC$|Control\\Print$' })) {
        try { Restart-Spooler; Write-Ok 'Đã khởi động lại dịch vụ in để áp dụng.' } catch { Write-Warn 'Chưa khởi động lại được dịch vụ in: khởi động lại máy để áp dụng.' }
    }
    Write-Line ('Hoàn tác xong: {0} việc, {1} lỗi, {2} bỏ qua.' -f $r.Ok, $r.Failed, $r.Skipped)
    return (Get-ResultCode $r.Ok $r.Failed)
}
