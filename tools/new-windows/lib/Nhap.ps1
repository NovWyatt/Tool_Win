# Chuyển dữ liệu khi cài lại Windows - NHẬP (sau khi cài lại).

# ---------------------------------------------------------------- sửa đường dẫn khi tên thư mục người dùng khác máy cũ
# Claude Code đặt tên thư mục dự án = đường dẫn, mọi ký tự không phải chữ/số thành '-'  (C:\Users\A\x -> C--Users-A-x)
function Encode-ProjectName([string]$p) { return ($p -replace '[^A-Za-z0-9]', '-') }
function Remap-Name([string]$name, [string]$old, [string]$new) {
    $o = Encode-ProjectName $old; $n = Encode-ProjectName $new
    if ($name -ieq $o) { return $n }
    if ($name.StartsWith($o + '-', [StringComparison]::OrdinalIgnoreCase)) { return $n + $name.Substring($o.Length) }
    return $name
}
function Remap-Path([string]$path, [string]$old, [string]$new) {
    if ($path -ieq $old) { return $new }
    if ($path.StartsWith($old + '\', [StringComparison]::OrdinalIgnoreCase)) { return $new + $path.Substring($old.Length) }
    return $path
}
function Remap-Text([string]$text, [string]$old, [string]$new) {
    # JSON: C:\\Users\\Ten hoặc C:/Users/Ten ; văn bản (.md): C:\Users\Ten
    $forms = @( @($old.Replace('\', '\\'), $new.Replace('\', '\\')), @($old.Replace('\', '/'), $new.Replace('\', '/')), @($old, $new) )
    foreach ($f in $forms) {
        $pat = [regex]::Escape($f[0]) + '(?=[\\/"''`\s)\]>,;*]|$)'
        $text = [regex]::Replace($text, $pat, $f[1].Replace('$', '$$'), [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    return $text
}
function Remap-JsonFile([string]$file, [string]$old, [string]$new) {
    if (-not (Test-Path -LiteralPath $file)) { return }
    try {
        $t = [IO.File]::ReadAllText($file)
        $t2 = Remap-Text $t $old $new
        if ($t2 -cne $t) { [IO.File]::WriteAllText($file, $t2, $Utf8NoBom) }
    } catch { Warn "Không sửa được đường dẫn trong $file" }
}

# ============================================================================ WI-FI
function Import-Wifi {
    Head 'WI-FI'
    $wDir = Join-Path $In 'WiFi'
    $idx = Join-Path $wDir 'danh-sach.json'
    $list = @()
    if (Test-Path -LiteralPath $idx) { $list = @((Read-Json $idx) | ForEach-Object { $_ }) }   # PS 5.1: ConvertFrom-Json trả mảng thành 1 phần tử -> phải "mở" ra
    elseif (Test-Path -LiteralPath $wDir) { $list = @(Get-ChildItem -LiteralPath $wDir -Filter '*.xml' -File | ForEach-Object { [pscustomobject]@{ File = $_.Name; Name = $null; Flags = 0 } }) }
    if ($list.Count -eq 0) { Info 'Bản sao lưu không có mạng Wi-Fi nào.'; return }
    if ($script:SkipSecret) { Fail "Bỏ qua $($list.Count) mạng Wi-Fi: hồ sơ (kèm mật khẩu) nằm trong $script:SecretFile mà chưa giải mã được."; return }
    [array]::Reverse($list)   # mạng thêm sau được Windows xếp lên ĐẦU -> thêm ngược để giữ đúng thứ tự ưu tiên cũ

    $svc = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
    if (-not $svc) { Fail 'Windows chưa có dịch vụ Wi-Fi - có thể chưa cài driver Wi-Fi (bản sao lưu có driver thì chọn [6]). Cài xong chạy lại và chọn [2].'; return }
    try { if ([string]$svc.StartType -eq 'Disabled') { Set-Service -Name WlanSvc -StartupType Automatic -ErrorAction Stop } } catch {}
    if ($svc.Status -ne 'Running') { try { Start-Service -Name WlanSvc -ErrorAction Stop; Start-Sleep -Seconds 3 } catch {} }

    $api = Load-WlanApi
    if ($api) {
        $n = -1
        try { $n = [WlanTool]::InterfaceCount() } catch { $api = $false }
        if ($n -eq 0) { Fail 'Chưa thấy card Wi-Fi (chưa cài driver Wi-Fi? bản sao lưu có driver thì chọn [6]). Cài driver xong chạy lại và chọn [2].'; return }
    }

    $tmp = $null
    try {
        foreach ($e in $list) {
            $bytes = Get-BackupBytes ('WiFi\' + [string]$e.File)
            if ($null -eq $bytes) { Fail "Bản sao lưu thiếu hồ sơ Wi-Fi '$($e.Name)' ($($e.File))."; $Stat.WifiBad++; continue }
            $xml = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
            $name = [string]$e.Name
            if (-not $name) { $name = Get-WifiName $xml }
            $flags = [uint32]([int]$e.Flags -band 2)
            if ($api) {
                $codes = @()
                try { $codes = @([WlanTool]::Import($xml, $flags, $false)) } catch { $codes = @([uint32]1062) }
                if (@($codes | Where-Object { $_ -eq 0 }).Count -gt 0) { $Stat.WifiAdd++ }
                elseif (@($codes | Where-Object { $_ -ne 183 }).Count -eq 0) { $Stat.WifiHave++ }
                else {
                    $Stat.WifiBad++
                    $c = @($codes | Where-Object { $_ -ne 0 -and $_ -ne 183 })[0]
                    Fail ("Không thêm được Wi-Fi '{0}': {1}" -f $name, (Get-ErrText $c))
                }
            } else {
                # Dự phòng: netsh (thư mục tạm phải NGẮN vì netsh cắt đường dẫn dài)
                if (-not $tmp) { $tmp = Join-Path $env:SystemRoot ('Temp\wi' + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory -Path $tmp -Force | Out-Null }
                if ($name) { & netsh.exe wlan show profile name="$name" | Out-Null; if ($LASTEXITCODE -eq 0) { $Stat.WifiHave++; continue } }
                $tf = Join-Path $tmp 'p.xml'
                [IO.File]::WriteAllText($tf, $xml, $Utf8NoBom)
                $usr = 'all'; if ($flags -ne 0) { $usr = 'current' }
                & netsh.exe wlan add profile filename="$tf" user=$usr | Out-Null
                if ($LASTEXITCODE -eq 0) { $Stat.WifiAdd++ } else { $Stat.WifiBad++; Fail "Không thêm được Wi-Fi '$name'" }
            }
        }
    } finally { if ($tmp) { try { [IO.Directory]::Delete($tmp, $true) } catch {} } }
    Ok ('Wi-Fi: thêm mới {0}, đã có sẵn {1}, lỗi {2}' -f $Stat.WifiAdd, $Stat.WifiHave, $Stat.WifiBad)
}

# ============================================================================ MÁY IN
function Import-Printers {
    Head 'MÁY IN'
    $pDir = Join-Path $In 'MayIn'
    $jf = Join-Path $pDir 'may-in.json'
    if (-not (Test-Path -LiteralPath $jf)) { Info 'Bản sao lưu không có dữ liệu máy in.'; return }
    $data = Read-Json $jf
    $drvDir = Join-Path $pDir 'Drivers'
    $tkDir  = Join-Path $pDir 'CauHinh'

    $sp = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if (-not $sp) { Fail 'Không có dịch vụ Print Spooler.'; return }
    try { if ([string]$sp.StartType -eq 'Disabled') { Set-Service -Name Spooler -StartupType Automatic -ErrorAction Stop } } catch {}
    if ($sp.Status -ne 'Running') {
        try { Start-Service -Name Spooler -ErrorAction Stop; Start-Sleep -Seconds 3 } catch { Fail 'Không bật được Print Spooler.'; return }
    }

    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    $envNative = 'Windows NT x86'
    if ($arch -eq 'AMD64') { $envNative = 'Windows x64' } elseif ($arch -eq 'ARM64') { $envNative = 'Windows ARM64' }
    $drivers = @($data.Drivers | Where-Object { $_ -and -not $_.Inbox -and $_.Folder -and (-not $_.Environment -or $_.Environment -eq $envNative) })

    # 1) Nạp gói driver vào kho driver của Windows
    $haveDrv = @{}
    foreach ($x in @(Get-PrinterDriver -ErrorAction SilentlyContinue)) { $haveDrv[[string]$x.Name] = $true }
    $done = @{}
    foreach ($d in $drivers) {
        if ($haveDrv.ContainsKey([string]$d.Name) -or $done.ContainsKey([string]$d.Folder)) { continue }
        $done[[string]$d.Folder] = $true
        $inf = Join-Path (Join-Path $drvDir $d.Folder) $d.Inf
        if (-not (Test-Path -LiteralPath $inf)) { Warn "Thiếu file driver $($d.Folder)\$($d.Inf)"; continue }
        Info "Đang nạp gói driver $($d.Inf) ..."
        & pnputil.exe /add-driver $inf /install | Out-Null
        $rc = $LASTEXITCODE
        if (@(0, 259, 3010) -notcontains $rc) { Info "(pnputil trả mã $rc - vẫn thử cài tiếp)" }
    }
    # 2) Cài driver máy in
    foreach ($d in $drivers) {
        $name = [string]$d.Name
        if ($haveDrv.ContainsKey($name)) { continue }
        $inf = Join-Path (Join-Path $drvDir $d.Folder) $d.Inf
        $ok = $false
        try { Add-PrinterDriver -Name $name -ErrorAction Stop; $ok = $true } catch {}
        if (-not $ok -and (Test-Path -LiteralPath $inf)) { try { Add-PrinterDriver -Name $name -InfPath $inf -ErrorAction Stop; $ok = $true } catch {} }
        if (-not $ok -and (Test-Path -LiteralPath $inf)) {
            & rundll32.exe 'printui.dll,PrintUIEntry' /ia /q /m "$name" /f "$inf" | Out-Null   # | Out-Null để PS 5.1 chờ rundll32 chạy xong
            for ($w = 0; $w -lt 10 -and -not $ok; $w++) {
                if (Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $name }) { $ok = $true } else { Start-Sleep -Seconds 1 }
            }
        }
        if ($ok) { $haveDrv[$name] = $true; $Stat.DrvAdd++; Ok "Driver: $name" }
        elseif ($d.Used) { Fail "Không cài được driver '$name' - tải driver từ trang của hãng, cài xong chạy lại và chọn [3]." }
        else { Info "(bỏ qua driver không dùng: $name)" }
    }

    # 3) Tạo cổng TCP/IP
    $havePort = @{}
    foreach ($x in @(Get-PrinterPort -ErrorAction SilentlyContinue)) { $havePort[[string]$x.Name] = $true }
    foreach ($pt in @($data.Ports)) {
        if (-not $pt -or $havePort.ContainsKey([string]$pt.Name)) { continue }
        try {
            if ($pt.Protocol -eq 'LPR') {
                $a = @{ Name = $pt.Name; LprHostAddress = $pt.Host; LprQueueName = $pt.LprQueueName; ErrorAction = 'Stop' }
                if ($pt.LprByteCounting) { $a.LprByteCounting = $true }
            } else {
                $a = @{ Name = $pt.Name; PrinterHostAddress = $pt.Host; PortNumber = [uint32]$pt.PortNumber; ErrorAction = 'Stop' }
                if ($pt.SNMPEnabled) { $a.SNMP = [uint32]$pt.SNMPIndex; $a.SNMPCommunity = [string]$pt.SNMPCommunity }
            }
            Add-PrinterPort @a
            $havePort[[string]$pt.Name] = $true
        } catch { Fail "Không tạo được cổng $($pt.Name): $($_.Exception.Message)" }
    }

    # 4) Thêm máy in
    $havePr = @{}
    foreach ($x in @(Get-Printer -ErrorAction SilentlyContinue)) { $havePr[[string]$x.Name] = $true }
    foreach ($p in @($data.Printers)) {
        if (-not $p) { continue }
        $pname = [string]$p.Name
        if ($havePr.ContainsKey($pname)) { Info "Đã có sẵn: $pname"; $Stat.PrHave++; continue }
        if ($p.Kind -eq 'CONNECTION') {
            try { Add-Printer -ConnectionName $pname -ErrorAction Stop; $havePr[$pname] = $true; $Stat.PrAdd++; Ok "$pname (máy in chia sẻ qua mạng)" }
            catch { Warn "Không kết nối được máy in chia sẻ '$pname' (máy chủ phải đang bật)."; $Stat.PrSkip++ }
            continue
        }
        if (-not $haveDrv.ContainsKey([string]$p.DriverName)) { Fail "Bỏ qua '$pname': chưa có driver '$($p.DriverName)'."; $Stat.PrSkip++; continue }

        $port = [string]$p.PortName
        if ($p.Kind -eq 'WSD') {
            if (-not $p.WsdIp) { Warn "Bỏ qua '$pname': máy in WSD không rõ IP - hãy thêm lại trong Cài đặt > Máy in."; $Stat.PrSkip++; continue }
            $port = [string]$p.WsdIp      # cổng WSD không tạo lại được -> dùng cổng TCP/IP theo IP thật
            if (-not $havePort.ContainsKey($port)) {
                try { Add-PrinterPort -Name $port -PrinterHostAddress $port -ErrorAction Stop; $havePort[$port] = $true }
                catch { Warn "Không tạo được cổng ${port}: $($_.Exception.Message)"; $Stat.PrSkip++; continue }
            }
        } elseif (-not $havePort.ContainsKey($port)) {
            if ($p.Kind -eq 'USB') { Warn "Máy in USB '$pname': hãy cắm cáp USB, Windows sẽ tự nhận (driver đã cài sẵn) rồi chạy lại mục [3] nếu muốn giữ tên cũ." }
            else { Warn "Bỏ qua '$pname': máy mới không có cổng '$port'." }
            $Stat.PrSkip++; continue
        }

        $a = @{ Name = $pname; DriverName = [string]$p.DriverName; PortName = $port; ErrorAction = 'Stop' }
        if ($p.Location) { $a.Location = [string]$p.Location }
        if ($p.Comment)  { $a.Comment  = [string]$p.Comment }
        try { Add-Printer @a } catch { Fail "Không thêm được máy in '$pname': $($_.Exception.Message)"; $Stat.PrSkip++; continue }
        $havePr[$pname] = $true; $Stat.PrAdd++

        if ($p.Shared) {
            $obj = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $pname } | Select-Object -First 1
            $sn = [string]$p.ShareName; if (-not $sn) { $sn = $pname }
            if ($obj) { try { Set-Printer -InputObject $obj -Shared $true -ShareName $sn -ErrorAction Stop } catch { Info "(không bật được chia sẻ cho '$pname')" } }
        }
        if ($p.TicketFile) {
            $tf = Join-Path $tkDir ([string]$p.TicketFile)
            if (Test-Path -LiteralPath $tf) {
                try { Set-PrintConfiguration -PrinterName $pname -PrintTicketXml ([IO.File]::ReadAllText($tf)) -ErrorAction Stop }
                catch { Info "(không áp được cấu hình in cũ cho '$pname' - dùng mặc định)" }
            }
        }
        Ok ('{0}  ->  {1}' -f $pname, $port)
    }

    # 5) Máy in mặc định
    $def = [string]$data.DefaultPrinter
    if ($def -and $havePr.ContainsKey($def)) {
        try {
            if ($null -ne $data.LegacyDefaultPrinterMode) {
                New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' -Name 'LegacyDefaultPrinterMode' -Value ([int]$data.LegacyDefaultPrinterMode) -PropertyType DWord -Force | Out-Null
            }
            (New-Object -ComObject WScript.Network).SetDefaultPrinter($def)
            Ok "Máy in mặc định: $def"
        } catch { Warn "Không đặt được máy in mặc định '$def'." }
    }
    Ok ('Máy in: thêm mới {0}, đã có sẵn {1}, bỏ qua {2}; driver cài mới {3}' -f $Stat.PrAdd, $Stat.PrHave, $Stat.PrSkip, $Stat.DrvAdd)
}

# ============================================================================ CLAUDE
function Wait-ClaudeClosed {
    # Chỉ Claude Desktop; claude.exe của Claude Code (CLI) không khoá các file này. -Yes: không tự đóng, bỏ qua phần Claude.
    for ($k = 0; $k -lt 30; $k++) {
        $pr = @(Get-ClaudeDesktopProcess)
        if ($pr.Count -eq 0) { return $true }
        Write-Host ''
        Write-Host '  [!] Claude Desktop đang chạy. Phải THOÁT HẲN Claude trước khi khôi phục' -ForegroundColor Yellow
        Write-Host '      (chuột phải biểu tượng Claude ở khay đồng hồ -> Quit).' -ForegroundColor Yellow
        if ($script:Yes) { Write-Host '  -Yes: không tự đóng Claude, bỏ qua phần Claude.' -ForegroundColor Gray; return $false }
        $a = Read-Answer '[Enter] = đã thoát, kiểm tra lại    [T] = tự đóng Claude    [B] = bỏ qua phần Claude' ''
        if ($a -match '^\s*[Tt]') { $pr | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3 }
        elseif ($a -match '^\s*[Bb]') { return $false }
    }
    return $false
}

# Nơi Claude Desktop đọc dữ liệu: bản MSIX -> %LOCALAPPDATA%\Packages\Claude_xxx\LocalCache\Roaming\Claude
function Get-ClaudeAppDataTarget {
    $pk = Join-Path $env:LOCALAPPDATA 'Packages'
    try {
        $ap = @(Get-AppxPackage -Name 'Claude' -ErrorAction Stop | Where-Object { $_.PackageFamilyName -like 'Claude_*' }) | Select-Object -First 1
        if ($ap) { return (Join-Path $pk ($ap.PackageFamilyName + '\LocalCache\Roaming\Claude')) }
    } catch {}
    $d = @(Get-ChildItem -LiteralPath $pk -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($d) { return (Join-Path $d.FullName 'LocalCache\Roaming\Claude') }
    $real = Join-Path $env:APPDATA 'Claude'
    if ((Test-Path -LiteralPath $real) -or (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'AnthropicClaude'))) { return $real }
    return $null
}

function Check-CodeConversations([string]$sessDir, [string]$projDir) {
    if (-not (Test-Path -LiteralPath $sessDir)) { return }
    $tx = @{}
    if (Test-Path -LiteralPath $projDir) { foreach ($f in @(Get-ChildItem -LiteralPath $projDir -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue)) { $tx[$f.BaseName] = $true } }
    $all = 0; $ok = 0
    $noDir = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $sessDir -Recurse -File -Filter 'local_*.json' -ErrorAction SilentlyContinue)) {
        try { $j = Read-Json $f.FullName } catch { continue }
        $all++
        if ($j.cliSessionId -and $tx.ContainsKey([string]$j.cliSessionId)) { $ok++ }
        if ($j.cwd -and -not $j.isArchived -and -not (Test-Path -LiteralPath ([string]$j.cwd))) { [void]$noDir.Add(('{0}  ->  {1}' -f $j.title, $j.cwd)) }
    }
    $Stat.Code = $all; $Stat.CodeOk = $ok
    if ($all -eq 0) { return }
    if ($ok -eq $all) { Ok "Hội thoại tab Code: đủ $ok/$all cuộc" } else { Warn "Hội thoại tab Code: chỉ $ok/$all cuộc có nội dung." }
    if ($noDir.Count -gt 0) {
        Warn "$($noDir.Count) cuộc hội thoại Code trỏ tới thư mục dự án CHƯA có trên máy này - chép thư mục dự án về ĐÚNG đường dẫn dưới đây rồi mới mở các cuộc đó trong Claude:"
        foreach ($x in @($noDir | Select-Object -First 30)) { Info $x }
        if ($noDir.Count -gt 30) { Info "... và $($noDir.Count - 30) cuộc khác" }
    }
}

function Import-Claude {
    Head 'CLAUDE'
    $cIn = Join-Path $In 'Claude'
    if (-not (Test-Path -LiteralPath $cIn)) { Info 'Bản sao lưu không có dữ liệu Claude.'; return }
    if (-not (Wait-ClaudeClosed)) { Fail 'Đã bỏ qua phần Claude vì Claude Desktop vẫn đang chạy - thoát Claude rồi chạy lại và chọn [4].'; $Stat.Claude = 'bỏ qua'; return }
    if ($script:SkipSecret) { Fail "Cấu hình Claude (.claude.json, settings, claude_desktop_config.json) nằm trong $script:SecretFile mà chưa giải mã được: chưa khôi phục các file đó." }

    $info = $null
    $infoFile = Join-Path $cIn 'claude-info.json'
    if (Test-Path -LiteralPath $infoFile) { try { $info = Read-Json $infoFile } catch {} }
    $OldUP = ''
    if ($info -and $info.UserProfile) { $OldUP = ([string]$info.UserProfile).TrimEnd('\') }
    $NewUP = ([string]$env:USERPROFILE).TrimEnd('\')
    $remap = ($OldUP -ne '') -and -not [string]::Equals($OldUP, $NewUP, [StringComparison]::OrdinalIgnoreCase)
    if ($remap) { Info "Thư mục người dùng đã đổi: $OldUP  ->  $NewUP  (tự sửa đường dẫn cho Claude)" }
    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $okAll = $true

    # (a) ~\.claude
    $src = Join-Path $cIn 'dot-claude'
    $dst = Join-Path $NewUP '.claude'
    if (Test-Path -LiteralPath $src) {
        $st = Join-Path $dst 'settings.json'
        if (Test-Path -LiteralPath $st) { Copy-Item -LiteralPath $st -Destination "$st.truoc-khoi-phuc-$ts" -Force }
        $pj = Join-Path $src 'projects'
        if ((Copy-Tree $src $dst @($pj)) -ge 8) { $okAll = $false }
        if ((Write-SecretEntries 'Claude\dot-claude' $dst) -gt 0) { $okAll = $false }   # settings*.json nằm trong BiMat.aes
        if (Test-Path -LiteralPath $pj) {
            $pjDst = Join-Path $dst 'projects'
            Ensure-Dir $pjDst
            foreach ($d in @(Get-ChildItem -LiteralPath $pj -Directory -Force)) {
                $nn = $d.Name
                if ($remap) { $nn = Remap-Name $d.Name $OldUP $NewUP }
                if ((Copy-Tree $d.FullName (Join-Path $pjDst $nn) -KeepNewer) -ge 8) { $okAll = $false }
            }
            foreach ($f in @(Get-ChildItem -LiteralPath $pj -File -Force)) { Copy-Item -LiteralPath $f.FullName -Destination $pjDst -Force }
        }
        if ($remap) {
            foreach ($f in @(Get-ChildItem -LiteralPath $dst -Filter '*.json' -File -Force -ErrorAction SilentlyContinue)) { Remap-JsonFile $f.FullName $OldUP $NewUP }
            $pl = Join-Path $dst 'plugins'
            if (Test-Path -LiteralPath $pl) { foreach ($f in @(Get-ChildItem -LiteralPath $pl -Filter '*.json' -File -Recurse -Force -ErrorAction SilentlyContinue)) { Remap-JsonFile $f.FullName $OldUP $NewUP } }
            # memory (*.md), tác vụ hẹn giờ, CLAUDE.md cũng có đường dẫn
            foreach ($pd in @(Get-ChildItem -LiteralPath (Join-Path $dst 'projects') -Directory -Force -ErrorAction SilentlyContinue)) {
                foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $pd.FullName 'memory') -Filter '*.md' -File -Force -ErrorAction SilentlyContinue)) { Remap-JsonFile $f.FullName $OldUP $NewUP }
            }
            $stk = Join-Path $dst 'scheduled-tasks'
            if (Test-Path -LiteralPath $stk) { foreach ($f in @(Get-ChildItem -LiteralPath $stk -Filter '*.md' -File -Recurse -Force -ErrorAction SilentlyContinue)) { Remap-JsonFile $f.FullName $OldUP $NewUP } }
            Remap-JsonFile (Join-Path $dst 'CLAUDE.md') $OldUP $NewUP
        }
        if ($okAll) { Ok 'Claude Code (~\.claude): cài đặt, memory, lịch sử phiên, skills, tác vụ hẹn giờ' } else { Fail 'Khôi phục ~\.claude bị lỗi một phần (xem nhat-ky-nhap.txt).' }
    }

    # (b) ~\.claude.json
    $cjBytes = Get-BackupBytes 'Claude\dot-claude.json'
    $cjDst = Join-Path $NewUP '.claude.json'
    if ($null -ne $cjBytes) {
        try {
            if (Test-Path -LiteralPath $cjDst) { Copy-Item -LiteralPath $cjDst -Destination "$cjDst.truoc-khoi-phuc-$ts" -Force -ErrorAction Stop }
            [IO.File]::WriteAllBytes($cjDst, $cjBytes)
            if ($remap) { Remap-JsonFile $cjDst $OldUP $NewUP }
            Ok 'Cấu hình chung Claude Code (~\.claude.json)'
        } catch { Fail "Không khôi phục được ~\.claude.json: $($_.Exception.Message)" }
    }

    # (c) Claude Desktop
    $aIn = Join-Path $cIn 'AppData-Claude'
    $desktopDone = $false
    $aSecret = (Get-SecretEntries 'Claude\AppData-Claude').Count
    if ((Test-Path -LiteralPath $aIn) -or $aSecret) {
        $target = Get-ClaudeAppDataTarget
        if (-not $target) {
            Fail 'Chưa cài ứng dụng Claude Desktop nên CHƯA khôi phục phần của nó. Cài Claude (https://claude.ai/download), đăng nhập, thoát hẳn, rồi chạy lại và chọn [4].'
        } else {
            Ensure-Dir $target
            $cfgT = Join-Path $target 'claude_desktop_config.json'
            if (Test-Path -LiteralPath $cfgT) { Copy-Item -LiteralPath $cfgT -Destination "$cfgT.truoc-khoi-phuc-$ts" -Force }
            $rc = if (Test-Path -LiteralPath $aIn) { Copy-Tree $aIn $target } else { 0 }
            if ((Write-SecretEntries 'Claude\AppData-Claude' $target) -gt 0) { $rc = 16 }
            if ($remap) {
                Remap-JsonFile $cfgT $OldUP $NewUP
                foreach ($sub in @('claude-code-sessions', 'local-agent-mode-sessions')) {
                    $sd = Join-Path $target $sub
                    if (Test-Path -LiteralPath $sd) { foreach ($f in @(Get-ChildItem -LiteralPath $sd -Filter '*.json' -File -Recurse -Force -ErrorAction SilentlyContinue)) { Remap-JsonFile $f.FullName $OldUP $NewUP } }
                }
            }
            if ($rc -lt 8) { Ok 'Claude Desktop: cấu hình, danh sách phiên Code/Cowork, tác vụ hẹn giờ'; $desktopDone = $true }
            else { Fail "Khôi phục dữ liệu Claude Desktop bị lỗi (robocopy mã $rc)." }
            # Kiểm đếm hội thoại tab Code: mỗi cuộc phải có cả mục trong danh sách lẫn file nội dung
            Check-CodeConversations (Join-Path $target 'claude-code-sessions') (Join-Path $dst 'projects')
        }
    }

    # (d) Thư mục file Cowork
    $cwIn = Join-Path $cIn 'Cowork-Files'
    if ((Test-Path -LiteralPath $cwIn) -and $info -and $info.CoworkPath) {
        $cwDst = ([string]$info.CoworkPath).TrimEnd('\')
        if ($remap) { $cwDst = Remap-Path $cwDst $OldUP $NewUP }
        if ((Copy-Tree $cwIn $cwDst -KeepNewer) -lt 8) { Ok "Thư mục file Cowork: $cwDst" } else { Fail "Chép thư mục Cowork lỗi: $cwDst" }
    }
    $Stat.Claude = if ($desktopDone) { 'đã khôi phục' } else { 'đã khôi phục Claude Code (thiếu phần Claude Desktop)' }
}

# ============================================================================ DRIVER
# Driver do 1_XUAT_DU_LIEU.bat sao lưu (thư mục Driver): nạp vào Windows và cài cho thiết bị đang thiếu.
function Import-Drivers {
    Head 'DRIVER'
    $dDir = Join-Path $In 'Driver'
    $infs = @()
    if (Test-Path -LiteralPath $dDir) { $infs = @(Get-ChildItem -LiteralPath $dDir -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue) }
    if (-not $infs.Count) { Info 'Bản sao lưu không có driver - bỏ qua.'; $Stat.DrvPkg = 'không có trong bản sao lưu'; return }
    Info "Đang nạp $($infs.Count) gói driver và cài cho thiết bị phù hợp (có thể mất vài phút)..."
    & pnputil.exe /add-driver (Join-Path $dDir '*.inf') /subdirs /install | Out-Null
    $rc = [int]$LASTEXITCODE
    if ($rc -eq 0) { Ok "Đã nạp $($infs.Count) gói driver."; $Stat.DrvPkg = "đã nạp $($infs.Count) gói" }
    elseif ($rc -eq 3010) { Ok "Đã nạp $($infs.Count) gói driver - cần KHỞI ĐỘNG LẠI máy để dùng."; $Stat.DrvPkg = "đã nạp $($infs.Count) gói, cần khởi động lại" }
    elseif ($rc -eq 259) { Info 'Windows đã có driver phù hợp cho mọi thiết bị, không cần cài thêm.'; $Stat.DrvPkg = 'không cần cài thêm' }
    else { Fail "pnputil báo $(Get-ErrText $rc) - một số driver chưa cài được; xem danh sách trong Driver\danh-sach.txt."; $Stat.DrvPkg = "lỗi một phần (mã $rc)" }
}


# ============================================================================ BITLOCKER
# Mở ổ dữ liệu bị khoá bằng khoá trong thư mục BitLocker của bản sao lưu. Không bao giờ in khoá ra màn hình (nhật ký
# nhập đang ghi lại màn hình); khoá phải gõ tay thì dùng hộp mở khoá của Windows hoặc công cụ BitLocker.
function Read-BdeKeys([string]$dir) {
    # Cặp (Mã khoá, khoá) trong các file khoá; mỗi khoá đi với Mã khoá đứng gần nhất phía trước nó.
    $res = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.txt' -File -ErrorAction SilentlyContinue)) {
        try { $t = [IO.File]::ReadAllText($f.FullName) } catch { continue }
        $ids = @([regex]::Matches($t, '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'))
        foreach ($m in @([regex]::Matches($t, '\d{6}(?:-\d{6}){7}'))) {
            $id = $null
            foreach ($g in $ids) { if ($g.Index -lt $m.Index) { $id = '{' + $g.Value.ToUpperInvariant() + '}' } }
            [void]$res.Add([pscustomobject]@{ Id = $id; Key = $m.Value })
        }
    }
    return @($res)
}
function Import-BitLocker {
    Head 'Ổ BITLOCKER'
    try { $vols = @(Get-CimInstance -Namespace $BdeNs -ClassName Win32_EncryptableVolume -ErrorAction Stop) }
    catch { Warn "Không đọc được BitLocker ($($_.Exception.Message)) - bỏ qua."; return }
    $locked = @($vols | Where-Object { try { [int](Invoke-Bde $_ 'GetLockStatus').LockStatus -eq 1 } catch { $false } })
    if (-not $locked.Count) { Info 'Không ổ nào đang bị BitLocker khoá.'; return }
    $Stat.BdeLocked = $locked.Count
    $keys = @(Read-BdeKeys (Join-Path $In 'BitLocker'))
    $opened = 0
    foreach ($v in $locked) {
        $n = if ($v.DriveLetter) { "Ổ $($v.DriveLetter)" } else { 'Ổ không có chữ ổ' }
        $nl = if ($v.DriveLetter) { "ổ $($v.DriveLetter)" } else { 'ổ không có chữ ổ' }
        $ids = @()
        try { $ids = @((Invoke-Bde $v 'GetKeyProtectors' @{ KeyProtectorType = [uint32]3 }).VolumeKeyProtectorID | Where-Object { $_ } | ForEach-Object { '{' + ([string]$_).Trim('{', '}').ToUpperInvariant() + '}' }) } catch {}
        $cand = @($keys | Where-Object { $_.Id -and $ids -contains $_.Id }) + @($keys | Where-Object { -not $_.Id })
        $open = $false
        foreach ($k in $cand) {
            try { [void](Invoke-Bde $v 'UnlockWithNumericalPassword' @{ NumericalPassword = $k.Key }); $open = $true; break } catch {}
        }
        $cand = $null
        if ($open) { Ok "Đã mở khoá $nl bằng khoá trong bản sao lưu."; $Stat.BdeOpen++; $opened++ }
        else {
            $short = @($ids | ForEach-Object { $_.Substring(1, 8) }) -join ', '
            Fail ("{0} đang bị khoá, bản sao lưu không có khoá khớp{1}. Tìm khoá ở https://aka.ms/myrecoverykey, giấy in hoặc USB, rồi bấm đúp ổ trong This PC > More options > Enter recovery key." -f $n, $(if ($short) { " (Mã khoá bắt đầu bằng $short)" } else { '' }))
        }
    }
    $keys = $null
    if ($opened) {
        Info 'Ổ vừa mở sẽ bị khoá lại khi khởi động lại máy. Cho ổ tự mở khoá hoặc giải mã bằng công cụ BitLocker của Trạm Tool,'
        Info 'hoặc chuột phải ổ trong This PC > Manage BitLocker (Turn on auto-unlock / Turn off BitLocker).'
    }
}

# ============================================================================ TÌM BẢN SAO LƯU
function Find-Backups {
    # Thư mục DuLieu_SaoLuu* ở: -Target, cạnh công cụ (bản cũ để cạnh file .bat), gốc mọi ổ và USB, nơi các lần xuất
    # trước ghi trong ket_qua\. Trả mọi bản tìm thấy, kể cả bản chưa xong (để báo vì sao không dùng).
    $roots = New-Object System.Collections.Generic.List[string]
    if ($script:Opt.Target) { $roots.Add($script:Opt.Target) }
    $roots.Add($script:ToolDir)
    foreach ($d in @(Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -in 2, 3 })) { $roots.Add(([string]$d.DeviceID) + '\') }
    foreach ($f in @(Get-ChildItem -LiteralPath $script:ResultDir -Filter 'KetQua_ChuyenDuLieu_xuat_*.json' -File -ErrorAction SilentlyContinue)) {
        try { $p = [string](Read-Json $f.FullName).ThuMucSaoLuu; if ($p) { $roots.Add((Split-Path -Parent $p)) } } catch {}
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $list = New-Object System.Collections.ArrayList
    foreach ($r in $roots) {
        if (-not $r -or -not (Test-Path -LiteralPath $r -PathType Container)) { continue }
        $dirs = @($r) + @(Get-ChildItem -LiteralPath $r -Directory -Filter 'DuLieu_SaoLuu*' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        foreach ($d in $dirs) {
            $full = [IO.Path]::GetFullPath($d)
            if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }   # giữ 'E:\' (bỏ '\' thì thành thư mục hiện tại của ổ E)
            if (-not $seen.Add($full)) { continue }
            $b = Get-BackupInfo $full
            if ($b) { [void]$list.Add($b) }
        }
    }
    return @($list)
}

function Format-BackupLine($b) {
    $t = if ($b.Time) { $b.Time.ToString('dd/MM/yyyy HH:mm') } else { '?' }
    $who = if ($b.Computer) { " - máy $($b.Computer), người dùng $($b.User)" } else { '' }
    $tags = @()
    if ($b.Old) { $tags += 'bản CŨ' }
    if ($b.Legacy) { $tags += 'tạo bởi bản trước' }
    if ($b.Encrypted) { $tags += 'có mã hoá' }
    $tagText = if ($tags.Count) { ' [' + ($tags -join ', ') + ']' } else { '' }
    return ('{0}  (lúc {1}{2}, {3}){4}' -f $b.Path, $t, $who, (Format-BackupState $b.State), $tagText)
}

function Select-Backup {
    # Bản sao lưu dùng để nhập; $null khi không có / không đồng ý. Bản chưa xong (đang làm, lỗi) không bao giờ được dùng.
    $usable = { param($b) $b.State -in 'xong', 'mot-phan' }
    if ($script:Opt.Target) {
        $t = Get-BackupInfo $script:Opt.Target
        if (-not $t) { $t = Get-BackupInfo ([IO.Path]::Combine($script:Opt.Target, 'DuLieu_SaoLuu')) }
        if (-not $t) { Fail "Không thấy bản sao lưu (manifest.json hoặc thong-tin.json) trong $($script:Opt.Target)."; return $null }
        if (-not (& $usable $t)) { Fail ("Không dùng {0}: {1}. Chạy lại bước xuất trên máy cũ." -f $t.Path, (Format-BackupState $t.State)); return $null }
        return $t
    }
    $all = @(Find-Backups)
    foreach ($b in @($all | Where-Object { -not (& $usable $_) })) { Warn ("Bỏ qua {0}: {1}." -f $b.Path, (Format-BackupState $b.State)) }
    $ok = @($all | Where-Object { & $usable $_ } | Sort-Object @{ Expression = { [int]$_.Old } }, @{ Expression = { if ($_.Time) { $_.Time } else { [datetime]::MinValue } }; Descending = $true })
    if ($ok.Count -eq 0) {
        Write-Host ''
        Write-Host '  Không thấy bản sao lưu dùng được ở gốc các ổ, USB hay cạnh công cụ.' -ForegroundColor Yellow
        while (-not $script:Yes) {
            $a = Read-Answer 'Dán (hoặc kéo-thả) đường dẫn thư mục DuLieu_SaoLuu rồi Enter (để trống = thoát)' ''
            if (-not $a) { return $null }
            $a = $a.Trim('"').TrimEnd('\')
            $t = Get-BackupInfo $a
            if (-not $t) { $t = Get-BackupInfo ([IO.Path]::Combine($a, 'DuLieu_SaoLuu')) }
            if (-not $t) { Write-Host '  Thư mục đó không phải bản sao lưu.' -ForegroundColor Yellow; continue }
            if (-not (& $usable $t)) { Write-Host ("  Không dùng được: {0}." -f (Format-BackupState $t.State)) -ForegroundColor Yellow; continue }
            return $t
        }
        return $null
    }
    $pick = $ok[0]
    if ($ok.Count -gt 1) {
        Write-Host ''
        Write-Host '  Có nhiều bản sao lưu:' -ForegroundColor White
        for ($i = 0; $i -lt $ok.Count; $i++) { Write-Host ('   {0}. {1}' -f ($i + 1), (Format-BackupLine $ok[$i])) }
        while ($true) {
            $a = Read-Answer 'Chọn bản sao lưu' '1'
            $n = 0
            if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $ok.Count) { $pick = $ok[$n - 1]; break }
            Write-Host "  Gõ một số từ 1 đến $($ok.Count)." -ForegroundColor Yellow
        }
    }
    if ($pick.Old) {
        Write-Host ''
        Write-Host ("  [!] Bản được chọn là bản CŨ: {0}" -f (Format-BackupLine $pick)) -ForegroundColor Yellow
        Write-Host '      Bản mới hơn (nếu có) chưa xong hoặc đã bị xoá. Bản cũ có thể thiếu mạng Wi-Fi, máy in, hội thoại mới.' -ForegroundColor Yellow
        if (-not (Read-YesNo 'Dùng bản cũ này?' $false)) {
            if ($script:Yes) { Info 'Chạy với -Yes không tự dùng bản cũ: chỉ rõ thư mục bằng -Target nếu đúng là muốn dùng.' }
            return $null
        }
    }
    return $pick
}

# ============================================================================ GIẢI MÃ
function Open-SecretBundle {
    # Giải mã BiMat.aes vào bộ nhớ; $true khi được
    $f = Join-Path $script:In $script:SecretFile
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Fail "Bản sao lưu ghi là có mã hoá nhưng thiếu $script:SecretFile."; return $false }
    $blob = [IO.File]::ReadAllBytes($f)
    for ($i = 1; $i -le 3; $i++) {
        $pw = Read-Secret 'Mật khẩu của bản sao lưu (đặt lúc xuất)'
        try {
            $script:SecretIn = Read-ZipBytes (Unprotect-Bytes $blob $pw)
            Ok "Đã giải mã $($script:SecretIn.Count) file bí mật (chỉ giữ trong bộ nhớ)."
            return $true
        } catch { Write-Host "  [!]  $($_.Exception.Message)" -ForegroundColor Yellow }
        finally { $pw = $null }
    }
    return $false
}

# ============================================================================ CHẠY THỬ
function Show-ImportPlan([string]$Choice) {
    Head 'CHẠY THỬ: CHỈ XEM SẼ LÀM GÌ, KHÔNG ĐỔI MÁY'
    $all = $Choice -eq '1'
    if ($all -or $Choice -eq '6') {
        $n = @(Get-ChildItem -LiteralPath (Join-Path $script:In 'Driver') -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue).Count
        Plan ('Driver: nạp {0} gói driver (pnputil /add-driver /install)' -f $n)
    }
    if ($all -or $Choice -eq '5') {
        $keyFiles = @(Get-ChildItem -LiteralPath (Join-Path $script:In 'BitLocker') -Filter 'BitLocker_KhoaKhoiPhuc_*.txt' -File -ErrorAction SilentlyContinue).Count
        $locked = $null
        try {
            $vols = @(Get-CimInstance -Namespace $BdeNs -ClassName Win32_EncryptableVolume -ErrorAction Stop)
            $locked = @($vols | Where-Object { try { [int](Invoke-Bde $_ 'GetLockStatus').LockStatus -eq 1 } catch { $false } }).Count
        } catch {}
        Plan ('Ổ BitLocker: {0} ổ đang bị khoá; bản sao lưu có {1} file khoá (chưa đọc khoá)' -f $(if ($null -ne $locked) { $locked } else { '? (cần quyền Admin)' }), $keyFiles)
    }
    if ($all -or $Choice -eq '2') {
        $idx = Join-Path $script:In 'WiFi\danh-sach.json'
        $names = @(); if (Test-Path -LiteralPath $idx) { $names = @((Read-Json $idx) | ForEach-Object { [string]$_.Name }) }
        $have = @()
        if (Load-WlanApi) { try { $have = @([WlanTool]::ListProfiles() | ForEach-Object { $_.Name }) } catch {} }
        $new = @($names | Where-Object { $have -notcontains $_ })
        Plan ('Wi-Fi: {0} mạng trong bản sao lưu, {1} mạng chưa có trên máy sẽ được thêm' -f $names.Count, $new.Count)
    }
    if ($all -or $Choice -eq '3') {
        $jf = Join-Path $script:In 'MayIn\may-in.json'
        if (Test-Path -LiteralPath $jf) {
            $data = Read-Json $jf
            $have = @(Get-Printer -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
            $add = @($data.Printers | Where-Object { $_ -and $have -notcontains [string]$_.Name } | ForEach-Object { [string]$_.Name })
            Plan ('Máy in: thêm {0}{1}; máy in mặc định: {2}' -f $add.Count, $(if ($add.Count) { ' (' + ($add -join ', ') + ')' } else { '' }), $(if ($data.DefaultPrinter) { $data.DefaultPrinter } else { 'giữ nguyên' }))
        } else { Plan 'Máy in: bản sao lưu không có' }
    }
    if ($all -or $Choice -eq '4') {
        $info = $null; try { $info = Read-Json (Join-Path $script:In 'Claude\claude-info.json') } catch {}
        $old = if ($info) { ([string]$info.UserProfile).TrimEnd('\') } else { '' }
        $new = ([string]$env:USERPROFILE).TrimEnd('\')
        Plan ("Claude: chép vào $new\.claude, $new\.claude.json (bản đang có giữ thêm một bản .truoc-khoi-phuc-<giờ>)")
        if ($old -and $old -ine $new) { Plan "Thư mục người dùng đổi $old -> ${new}: sửa đường dẫn trong cấu hình Claude" }
        $t = Get-ClaudeAppDataTarget
        Plan ('Claude Desktop: {0}' -f $(if ($t) { "chép vào $t" } else { 'chưa cài, sẽ bỏ qua phần này' }))
        if (@(Get-ClaudeDesktopProcess).Count) { Plan 'Claude Desktop đang mở: chạy thật sẽ hỏi đóng' }
    }
    $b = Get-BackupInfo $script:In
    if ($b.Encrypted -and ($all -or $Choice -in '2', '4')) { Plan "Phần mã hoá ($script:SecretFile): chạy thật sẽ hỏi mật khẩu đặt lúc xuất" }
}

# ============================================================================ NHẬP
$script:ImportParts = [ordered]@{ 'tat-ca' = '1'; wifi = '2'; 'may-in' = '3'; claude = '4'; bitlocker = '5'; driver = '6' }

function Invoke-Nhap {
    $script:Stat = @{ WifiAdd = 0; WifiHave = 0; WifiBad = 0; DrvAdd = 0; PrAdd = 0; PrHave = 0; PrSkip = 0; Claude = ''; Code = 0; CodeOk = 0; BdeOpen = 0; BdeLocked = 0; DrvPkg = '' }
    $script:SkipSecret = $false
    try { $Host.UI.RawUI.WindowTitle = 'Nhập dữ liệu sau khi cài lại Windows' } catch {}
    Write-Host ''
    Write-Host '  ==================================================================' -ForegroundColor Cyan
    Write-Host '     NHẬP (KHÔI PHỤC) DỮ LIỆU SAU KHI CÀI LẠI WINDOWS' -ForegroundColor White
    Write-Host '     Driver  -  Ổ BitLocker  -  Wi-Fi  -  Máy in  -  Claude' -ForegroundColor White
    Write-Host '  ==================================================================' -ForegroundColor Cyan

    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $console = Get-ConsoleUser
    if ($console -and $console -ine $me) {
        Warn "Đang chạy bằng tài khoản $me nhưng người đang dùng máy là ${console}: Claude, máy in mặc định sẽ khôi phục vào tài khoản $me."
        if (-not (Read-YesNo 'Vẫn khôi phục vào tài khoản đang chạy?' $false)) { return 2 }
    }

    $b = Select-Backup
    if (-not $b) { Info 'Chưa nhập gì.'; return 2 }
    $script:In = $b.Path
    Write-Host ''
    Write-Host "  Bản sao lưu: $script:In" -ForegroundColor White
    $meta = $null
    try { $meta = Read-Json (Join-Path $script:In 'thong-tin.json') } catch {}
    if ($meta) {
        Write-Host ("  Tạo lúc {0} trên máy {1} (người dùng {2})" -f $meta.Date, $meta.Computer, $meta.UserName) -ForegroundColor Gray
        Write-Host ("  Gồm: {0} Wi-Fi, {1} máy in, Claude: {2}" -f $meta.Wifi, $meta.Printers, $(if ($meta.Claude) { 'có' } else { 'không' })) -ForegroundColor Gray
        if ($null -ne $meta.BitLockerKeys) { Write-Host ("       {0} khoá BitLocker, {1} gói driver" -f $meta.BitLockerKeys, $meta.DriverPackages) -ForegroundColor Gray }
    }
    if ($b.State -eq 'mot-phan') {
        Warn 'Bản sao lưu này chỉ xong MỘT PHẦN lúc xuất; các phần lỗi lúc đó sẽ thiếu:'
        foreach ($e in @($b.Errors | Select-Object -First 8)) { Info "- $e" }
    }

    if ($script:Opt.Phan) { $choice = $script:ImportParts[$script:Opt.Phan] }
    else {
        Write-Host ''
        Write-Host '  [1] Khôi phục TẤT CẢ  (nhấn Enter)' -ForegroundColor White
        Write-Host '  [2] Chỉ Wi-Fi' -ForegroundColor White
        Write-Host '  [3] Chỉ máy in' -ForegroundColor White
        Write-Host '  [4] Chỉ Claude' -ForegroundColor White
        Write-Host '  [5] Chỉ mở khoá ổ BitLocker (bằng khoá trong bản sao lưu)' -ForegroundColor White
        Write-Host '  [6] Chỉ cài driver đã sao lưu (máy mới thiếu driver Wi-Fi, mạng dây)' -ForegroundColor White
        Write-Host '  [0] Thoát' -ForegroundColor White
        $choice = $null
        while ($null -eq $choice) {
            $a = Read-Answer 'Chọn' '1'
            if (@('0', '1', '2', '3', '4', '5', '6') -contains $a) { $choice = $a } else { Write-Host '  Chỉ gõ một số từ 0 đến 6.' -ForegroundColor Yellow }
        }
        if ($choice -eq '0') { return 2 }
    }

    if ($script:Opt.DryRun) { $null = Show-ImportPlan $choice; return 0 }

    if ($b.Encrypted -and $choice -in '1', '2', '4') {
        Write-Host ''
        Write-Host "  Mật khẩu Wi-Fi và cấu hình Claude được mã hoá trong $script:SecretFile." -ForegroundColor White
        if (-not (Open-SecretBundle)) {
            Warn 'Không giải mã được (sai mật khẩu 3 lần hoặc tệp hỏng).'
            if (-not (Read-YesNo 'Bỏ qua Wi-Fi và cấu hình Claude, nhập các phần còn lại?' $false)) { return 2 }
            $script:SkipSecret = $true
        }
    }

    $script:Started = $true
    try { Start-Transcript -Path (Join-Path $script:In 'nhat-ky-nhap.txt') -Append | Out-Null } catch {}
    try {
        # Driver trước (Wi-Fi cần driver), rồi mở ổ BitLocker (thư mục dự án có thể nằm trên ổ dữ liệu bị khoá).
        if ($choice -eq '1' -or $choice -eq '6') { $null = Import-Drivers }
        if ($choice -eq '1' -or $choice -eq '5') { $null = Import-BitLocker }
        if ($choice -eq '1' -or $choice -eq '2') { $null = Import-Wifi }
        if ($choice -eq '1' -or $choice -eq '3') { $null = Import-Printers }
        if ($choice -eq '1' -or $choice -eq '4') { $null = Import-Claude }
    } finally {
        if ($null -ne $script:SecretIn) { $script:SecretIn.Clear(); $script:SecretIn = $null }
    }
    $null = Show-ImportSummary $choice
    try { Stop-Transcript | Out-Null } catch {}
    if ($script:Errors.Count) { return 3 }
    return 0
}

function Show-ImportSummary([string]$choice) {
    Head $(if ($script:Errors.Count) { 'XONG MỘT PHẦN' } else { 'HOÀN TẤT' })
    if ($choice -eq '1' -or $choice -eq '6') { Write-Host ('  Driver : {0}' -f $Stat.DrvPkg) -ForegroundColor White }
    if (($choice -eq '1' -or $choice -eq '5') -and $Stat.BdeLocked) { Write-Host ('  BitLocker: mở khoá {0}/{1} ổ' -f $Stat.BdeOpen, $Stat.BdeLocked) -ForegroundColor White }
    if ($choice -eq '1' -or $choice -eq '2') { Write-Host ('  Wi-Fi  : thêm mới {0}, đã có {1}, lỗi {2}' -f $Stat.WifiAdd, $Stat.WifiHave, $Stat.WifiBad) -ForegroundColor White }
    if ($choice -eq '1' -or $choice -eq '3') { Write-Host ('  Máy in : thêm mới {0}, đã có {1}, bỏ qua {2}; driver cài mới {3}' -f $Stat.PrAdd, $Stat.PrHave, $Stat.PrSkip, $Stat.DrvAdd) -ForegroundColor White }
    if ($choice -eq '1' -or $choice -eq '4') {
        Write-Host ('  Claude : {0}' -f $Stat.Claude) -ForegroundColor White
        if ($Stat.Code -gt 0) { Write-Host ('  Hội thoại Code: {0}/{1} cuộc' -f $Stat.CodeOk, $Stat.Code) -ForegroundColor White }
    }
    if ($script:Errors.Count -gt 0) {
        Write-Host ''
        Write-Host "  Có $($script:Errors.Count) việc KHÔNG làm được:" -ForegroundColor Red
        foreach ($e in $script:Errors) { Write-Host "   - $e" -ForegroundColor Red }
    }
    if ($script:Warnings.Count -gt 0) {
        Write-Host ''
        Write-Host "  Có $($script:Warnings.Count) lưu ý:" -ForegroundColor Yellow
        foreach ($w in $script:Warnings) { Write-Host "   - $w" -ForegroundColor Yellow }
    }
    Write-Host ''
    Write-Host '  BƯỚC TIẾP THEO:' -ForegroundColor Cyan
    if ($choice -eq '1' -or $choice -eq '4') {
        Write-Host '   * Chép các thư mục dự án về ĐÚNG chỗ cũ (nếu chưa), rồi mở Claude, đăng nhập lại nếu được hỏi.' -ForegroundColor Cyan
        Write-Host "     Hội thoại tab Code, memory, cài đặt sẽ có lại. Bản đọc được: $script:In\Claude\HoiThoai-Code\index.html" -ForegroundColor Cyan
    }
    if ($choice -eq '1' -or $choice -eq '3') { Write-Host '   * Máy in USB: cắm cáp vào là Windows tự nhận.' -ForegroundColor Cyan }
    Write-Host '   * Kiểm tra xong, nên XÓA thư mục DuLieu_SaoLuu (có mật khẩu Wi-Fi, khoá BitLocker).' -ForegroundColor Cyan
}
