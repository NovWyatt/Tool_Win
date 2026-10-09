# Chuyển dữ liệu khi cài lại Windows - XUẤT (trước khi cài lại).

# ============================================================================ 1. WI-FI
function Export-Wifi {
    Head '1/5  WI-FI'
    $wDir = Join-Path $Out 'WiFi'
    Ensure-Dir $wDir
    $svc = Get-Service -Name WlanSvc -ErrorAction SilentlyContinue
    if (-not $svc) { Info 'Máy không có Wi-Fi (không có dịch vụ WlanSvc) - bỏ qua.'; return }
    try { if ([string]$svc.StartType -eq 'Disabled') { Set-Service -Name WlanSvc -StartupType Manual -ErrorAction Stop } } catch {}
    if ($svc.Status -ne 'Running') { try { Start-Service -Name WlanSvc -ErrorAction Stop; Start-Sleep -Seconds 2 } catch {} }

    $items = New-Object System.Collections.ArrayList     # mỗi phần tử: @{Name; Flags; Xml}
    $seen  = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $apiOk = $false
    if (Load-WlanApi) {
        try {
            foreach ($pr in [WlanTool]::Export()) {
                if (($pr.Flags -band 1) -ne 0) { Info "Bỏ qua mạng do công ty quản lý (Group Policy): $($pr.Name)"; continue }
                if (-not $pr.Xml) { Warn "Không đọc được Wi-Fi '$($pr.Name)' (mã lỗi $($pr.Error))"; continue }
                if (-not $seen.Add($pr.Name + '|' + $pr.Flags)) { continue }    # trùng do có 2 card Wi-Fi
                [void]$items.Add(@{ Name = $pr.Name; Flags = [int]($pr.Flags -band 2); Xml = $pr.Xml })
            }
            $apiOk = $true
        } catch { Warn "WLAN API lỗi: $($_.Exception.Message) - chuyển sang dùng netsh." }
    }
    if (-not $apiOk) {
        # Dự phòng: netsh (thư mục tạm phải NGẮN vì netsh cắt đường dẫn dài ~128 ký tự)
        $tmp = Join-Path $env:SystemRoot ('Temp\wx' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        try {
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            & netsh.exe wlan export profile key=clear folder="$tmp" | Out-Null
            foreach ($f in @(Get-ChildItem -LiteralPath $tmp -Filter '*.xml' -File -ErrorAction SilentlyContinue)) {
                $x = [IO.File]::ReadAllText($f.FullName)
                $nm = (Get-WifiInfo $x).Name
                if ($nm -and $seen.Add($nm + '|0')) { [void]$items.Add(@{ Name = $nm; Flags = 0; Xml = $x }) }
            }
        } finally { try { [IO.Directory]::Delete($tmp, $true) } catch {} }
    }

    # Không đọc được mạng nào nhưng Windows vẫn còn hồ sơ Wi-Fi -> card Wi-Fi đang tắt / thiếu driver: phải báo rõ
    if ($items.Count -eq 0) {
        $nIf = 0
        if ($apiOk) { try { $nIf = [WlanTool]::InterfaceCount() } catch {} }
        $stored = @(Get-ChildItem -LiteralPath (Join-Path $env:ProgramData 'Microsoft\Wlansvc\Profiles\Interfaces') -Recurse -Filter '*.xml' -File -ErrorAction SilentlyContinue).Count
        if ($nIf -eq 0 -and $stored -gt 0) {
            Fail "Máy còn $stored hồ sơ Wi-Fi nhưng KHÔNG đọc được (card Wi-Fi đang tắt / thiếu driver / dịch vụ WlanSvc bị tắt). Bật card Wi-Fi (ncpa.cpl) rồi chạy lại TRƯỚC khi cài Win."
        }
    }

    $index = New-Object System.Collections.ArrayList
    $lines = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($it in $items) {
        $i++
        $fn = '{0:D3}.xml' -f $i
        Save-SecretText "WiFi\$fn" $it.Xml   # có mật khẩu: mã hoá thì chỉ nằm trong bộ nhớ tới lúc ghi BiMat.aes
        $wi = Get-WifiInfo $it.Xml
        [void]$index.Add([pscustomobject]@{ File = $fn; Name = $it.Name; Flags = $it.Flags; Auth = $wi.Auth; HasPassword = $wi.HasKey; Encrypted = $wi.Encrypted })
        $tag = if ($wi.HasKey) { 'có mật khẩu' } elseif ($wi.Encrypted) { 'MẬT KHẨU BỊ MÃ HÓA - phải nhập lại' } elseif ($wi.Auth -eq 'open') { 'mạng mở' } else { $wi.Auth }
        [void]$lines.Add(('{0,3}. {1}   ({2})' -f $i, $it.Name, $tag))
        if ($wi.Encrypted) { $Stat.WifiNoKey++ }
    }
    Save-Json @($index) (Join-Path $wDir 'danh-sach.json')
    Save-Text (Join-Path $wDir 'DanhSachWiFi.txt') (($lines -join "`r`n") + "`r`n")
    $Stat.Wifi = $index.Count
    if ($index.Count -gt 0) { Ok "Đã lưu $($index.Count) mạng Wi-Fi" } else { Info 'Không có mạng Wi-Fi nào được lưu trên máy.' }
    if ($Stat.WifiNoKey -gt 0) { Warn "$($Stat.WifiNoKey) mạng Wi-Fi không lấy được mật khẩu (sau khi cài Win sẽ phải nhập lại)." }
}

# ============================================================================ 2. MÁY IN
$SkipPorts   = @('PORTPROMPT:', 'nul:', 'SHRFAX:', 'XPSPort:', 'FILE:')
$SkipDrivers = @('Microsoft Print To PDF', 'Microsoft XPS Document Writer', 'Microsoft XPS Document Writer v4', 'Microsoft Software Printer Driver', 'Microsoft Shared Fax Driver')
function Test-BuiltinPrinter($p) {
    return (($SkipPorts -contains $p.PortName) -or ($SkipDrivers -contains $p.DriverName) -or ($p.DriverName -like 'Send to Microsoft OneNote*') -or ($p.DriverName -like 'Send To OneNote*'))
}

$script:PnpCache = $null
function Get-WsdIp([string]$portName) {
    # Cổng WSD không tạo lại được -> tìm IP thật của máy in để bên nhập tạo cổng TCP/IP thay thế
    try {
        $k = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\WSD Port\Ports\$portName"
        $uuid = [string](Get-ItemProperty -LiteralPath $k -ErrorAction Stop).'Printer UUID'
        if (-not $uuid) { return $null }
        if ($null -eq $script:PnpCache) { $script:PnpCache = @(Get-PnpDevice -ErrorAction SilentlyContinue) }
        foreach ($d in @($script:PnpCache | Where-Object { $_.InstanceId -like "*$uuid*" })) {
            $loc = [string](Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_LocationInfo' -ErrorAction SilentlyContinue).Data
            if ($loc -match '(\d{1,3}(\.\d{1,3}){3})') { return $Matches[1] }
        }
    } catch {}
    return $null
}

function Export-Printers {
    Head '2/5  MÁY IN'
    $pDir   = Join-Path $Out 'MayIn'
    $drvDir = Join-Path $pDir 'Drivers'
    $tkDir  = Join-Path $pDir 'CauHinh'
    Ensure-Dir $drvDir; Ensure-Dir $tkDir

    $sp = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if (-not $sp) { Fail 'Không có dịch vụ Print Spooler - bỏ qua máy in.'; return }
    if ($sp.Status -ne 'Running') {
        try { Start-Service -Name Spooler -ErrorAction Stop; Start-Sleep -Seconds 2 } catch { Fail 'Không bật được Print Spooler - bỏ qua máy in.'; return }
    }

    $printers = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { -not (Test-BuiltinPrinter $_) })
    $portMap = @{}
    foreach ($pt in @(Get-PrinterPort -ErrorAction SilentlyContinue)) { $portMap[$pt.Name] = $pt }

    # Máy in mặc định
    $winKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'
    $wk = Get-ItemProperty -Path $winKey -ErrorAction SilentlyContinue
    # Giá trị Device có thể là "Tên,winspool,Ne01:" hoặc "Tên,Driver,Cổng" - tên máy in không bao giờ chứa dấu phẩy
    $defaultName = $null
    try { $defaultName = [string](Get-CimInstance -ClassName Win32_Printer -Filter 'Default=TRUE' -ErrorAction Stop | Select-Object -First 1).Name } catch {}
    if (-not $defaultName -and $wk -and $wk.Device) { $defaultName = ([string]$wk.Device).Split(',')[0].Trim() }
    if (-not $defaultName) { $defaultName = $null }
    $legacyMode = $null
    if ($wk -and $wk.PSObject.Properties['LegacyDefaultPrinterMode']) { $legacyMode = [int]$wk.LegacyDefaultPrinterMode }

    $recs = New-Object System.Collections.ArrayList
    $portRecs = [ordered]@{}
    $txt = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($p in $printers) {
        $i++
        $pt = $portMap[$p.PortName]
        $kind = 'OTHER'
        if ([string]$p.Type -eq 'Connection' -or $p.Name -like '\\*') { $kind = 'CONNECTION' }
        elseif ($pt -and $pt.CimClass.CimClassName -eq 'MSFT_TcpIpPrinterPort') { $kind = 'TCP' }
        elseif ($p.PortName -like 'WSD-*' -or ($pt -and [string]$pt.Description -eq 'WSD Port')) { $kind = 'WSD' }
        elseif ($p.PortName -like 'USB*' -or $p.PortName -like 'DOT4*') { $kind = 'USB' }
        elseif ($p.PortName -match '^(LPT|COM)\d+:$') { $kind = 'LOCAL' }

        $hostAddr = $null; $wsdIp = $null
        if ($kind -eq 'TCP') {
            $hostAddr = [string]$pt.PrinterHostAddress
            if (-not $hostAddr) { $hostAddr = [string]$pt.PrinterHostIP }
            if (-not $portRecs.Contains($pt.Name)) {
                $idx = [int]$pt.SNMPIndex; if ($idx -lt 1) { $idx = 1 }
                $portRecs[$pt.Name] = [pscustomobject]@{
                    Name = $pt.Name; Host = $hostAddr; PortNumber = [int]$pt.PortNumber
                    Protocol = $(if ([string]$pt.Protocol -match '^(2|LPR)$') { 'LPR' } else { 'RAW' })
                    LprQueueName = [string]$pt.LprQueueName; LprByteCounting = [bool]$pt.LprByteCounting
                    SNMPEnabled = [bool]$pt.SNMPEnabled; SNMPCommunity = [string]$pt.SNMPCommunity; SNMPIndex = $idx
                }
            }
        } elseif ($kind -eq 'WSD') {
            $wsdIp = Get-WsdIp $p.PortName
            $hostAddr = $wsdIp
            if (-not $wsdIp) { Warn "Máy in '$($p.Name)' dùng cổng WSD nhưng không tìm được IP - sau khi cài Win cần thêm lại bằng tay." }
        }

        # Cấu hình in (khổ giấy, in 2 mặt, màu...)
        $tf = $null
        if ($kind -ne 'CONNECTION') {
            try {
                $cfg = Get-PrintConfiguration -PrinterName $p.Name -ErrorAction Stop
                if ($cfg.PrintTicketXML) { $tf = '{0:D3}.xml' -f $i; Save-Text (Join-Path $tkDir $tf) $cfg.PrintTicketXML }
            } catch { Info "(không đọc được cấu hình in của '$($p.Name)' - sẽ dùng mặc định)" }
        }

        [void]$recs.Add([pscustomobject]@{
            Name = $p.Name; Type = [string]$p.Type; Kind = $kind
            DriverName = [string]$p.DriverName; PortName = [string]$p.PortName; Host = $hostAddr; WsdIp = $wsdIp
            Shared = [bool]$p.Shared; ShareName = [string]$p.ShareName
            Location = [string]$p.Location; Comment = [string]$p.Comment
            TicketFile = $tf; IsDefault = ($p.Name -eq $defaultName)
        })
        $where = if ($hostAddr) { $hostAddr } else { $p.PortName }
        [void]$txt.Add(('{0,3}. {1}  |  {2}  |  {3}{4}{5}' -f $i, $p.Name, $where, $p.DriverName, $(if ($p.Shared) { '  | chia sẻ' } else { '' }), $(if ($p.Name -eq $defaultName) { '  | MẶC ĐỊNH' } else { '' })))
        Ok ("{0}  ->  {1}" -f $p.Name, $where)
    }

    # Driver: chép nguyên gói driver (trừ driver có sẵn của Windows)
    $used = @{}
    foreach ($p in $printers) { if ($p.DriverName) { $used[[string]$p.DriverName] = $true } }
    $drvRecs = New-Object System.Collections.ArrayList
    $pkgMap = @{}
    foreach ($d in @(Get-PrinterDriver -ErrorAction SilentlyContinue)) {
        $inf = [string]$d.InfPath
        $infName = ''
        if ($inf) { $infName = [IO.Path]::GetFileName($inf) }
        $inbox = ([string]$d.Manufacturer -eq 'Microsoft') -or ($infName -match '^(ntprint4?|prnms\d+)\.inf$')
        $rec = [pscustomobject]@{
            Name = $d.Name; Environment = [string]$d.PrinterEnvironment; MajorVersion = [int]$d.MajorVersion
            Manufacturer = [string]$d.Manufacturer; Inbox = $inbox; Used = $used.ContainsKey([string]$d.Name); Folder = $null; Inf = $null
        }
        if (-not $inbox) {
            $key = $null
            if ($inf -and (Test-Path -LiteralPath $inf)) { $key = (Split-Path -Parent $inf).ToLowerInvariant() }
            if (-not $key) {
                if ($rec.Used) { Warn "Không tìm thấy bộ cài driver '$($d.Name)' - sau khi cài Win cần tải driver này từ trang của hãng." }
            } else {
                if (-not $pkgMap.ContainsKey($key)) {
                    $src = Split-Path -Parent $inf
                    $folder = $null
                    if ($src -like '*\DriverStore\FileRepository\*') {
                        $folder = Split-Path -Leaf $src
                        [void](Copy-Tree $src (Join-Path $drvDir $folder))
                    } elseif ($infName -match '^oem\d+\.inf$') {
                        $folder = [IO.Path]::GetFileNameWithoutExtension($infName)
                        Ensure-Dir (Join-Path $drvDir $folder)
                        & pnputil.exe /export-driver $infName (Join-Path $drvDir $folder) | Out-Null
                    }
                    $okInf = $null
                    if ($folder) {
                        $dst = Join-Path $drvDir $folder
                        if (Test-Path -LiteralPath (Join-Path $dst $infName)) { $okInf = $infName }
                        else { $f1 = @(Get-ChildItem -LiteralPath $dst -Filter '*.inf' -File -ErrorAction SilentlyContinue) | Select-Object -First 1; if ($f1) { $okInf = $f1.Name } }
                    }
                    if ($okInf) { $pkgMap[$key] = @($folder, $okInf) } else { $pkgMap[$key] = $null }
                }
                if ($pkgMap[$key]) {
                    $rec.Folder = $pkgMap[$key][0]; $rec.Inf = $pkgMap[$key][1]
                    Ok "Driver: $($d.Name)  [$($rec.Environment)]"
                    $Stat.Drivers++
                } elseif ($rec.Used) {
                    Fail "Không chép được driver '$($d.Name)' - sau khi cài Win cần tải từ trang của hãng."
                }
            }
        }
        [void]$drvRecs.Add($rec)
    }

    $data = [pscustomobject]@{
        DefaultPrinter = $defaultName; LegacyDefaultPrinterMode = $legacyMode
        Printers = @($recs); Ports = @($portRecs.Values); Drivers = @($drvRecs)
    }
    Save-Json $data (Join-Path $pDir 'may-in.json')
    $head = "DANH SÁCH MÁY IN  (Tên | IP hoặc cổng | Driver)`r`n" + ('-' * 60) + "`r`n"
    Save-Text (Join-Path $pDir 'DanhSachMayIn.txt') ($head + ($txt -join "`r`n") + "`r`n")
    $Stat.Printers = $recs.Count
    if ($defaultName) { Info "Máy in mặc định: $defaultName" }
}

# ============================================================================ 3. CLAUDE
# ---- Hội thoại tab Code: danh sách = claude-code-sessions\...\local_*.json ; nội dung = .claude\projects\...\<cliSessionId>.jsonl
function To-Local($ms) { try { return [DateTimeOffset]::FromUnixTimeMilliseconds([long]$ms).LocalDateTime } catch { return $null } }
function Html([string]$s) { return [System.Net.WebUtility]::HtmlEncode($s) }
function Safe-Name([string]$s) {
    $s = ($s -replace '[\\/:*?"<>|\x00-\x1F]', ' ' -replace '\s+', ' ').Trim().TrimEnd('.')
    if ($s.Length -gt 60) { $s = $s.Substring(0, 60).Trim() }
    if (-not $s) { $s = 'Khong-tieu-de' }
    return $s
}
function Clean-Text([string]$t) {
    if (-not $t) { return '' }
    $t = [regex]::Replace($t, '(?s)<system-reminder>.*?</system-reminder>', '')
    $t = [regex]::Replace($t, '(?s)<local-command-(stdout|stderr|caveat)>.*?</local-command-\1>', '')
    return $t.Trim()
}
function Tool-Brief($blk) {
    $d = ''
    $in = $blk['input']
    if ($in -is [System.Collections.IDictionary]) {
        foreach ($k in @('description', 'command', 'file_path', 'pattern', 'url', 'query', 'prompt')) { if ($in.ContainsKey($k) -and $in[$k]) { $d = [string]$in[$k]; break } }
    }
    $d = ($d -replace '\s+', ' ').Trim()
    if ($d.Length -gt 160) { $d = $d.Substring(0, 160) + '...' }
    if ($d) { return ([string]$blk['name'] + ': ' + $d) } else { return [string]$blk['name'] }
}
$HtmlCss = 'body{font-family:Segoe UI,Arial,sans-serif;max-width:920px;margin:24px auto;padding:0 16px;background:#f6f6f4;color:#222;line-height:1.5}' +
    'h1{font-size:22px}.meta{color:#666;font-size:13px;margin-bottom:18px}.m{border-radius:10px;padding:10px 14px;margin:10px 0}' +
    '.u{background:#dbeafe}.a{background:#fff;border:1px solid #e3e3e3}.h{font-size:12px;color:#666;margin-bottom:4px;font-weight:600}' +
    '.t{white-space:pre-wrap;word-wrap:break-word}.tool{font:12px Consolas,monospace;color:#777;margin:2px 0 2px 14px}' +
    'details{background:#fff7e0;border-radius:10px;padding:8px 14px;margin:10px 0}table{border-collapse:collapse;width:100%;background:#fff}' +
    'td,th{border-bottom:1px solid #e5e5e5;padding:6px 8px;text-align:left;font-size:14px;vertical-align:top}a{color:#1d4ed8}' +
    '@media(prefers-color-scheme:dark){body{background:#1c1c1c;color:#e6e6e6}.u{background:#1e3a5f}.a,table{background:#262626;border-color:#333}details{background:#3a3220}.meta,.h,.tool{color:#aaa}td,th{border-color:#333}a{color:#8ab4ff}}'

function Write-ConversationHtml($s, [string]$path, $ser) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>').Append((Html $s.Title)).Append('</title><style>').Append($HtmlCss).Append('</style></head><body>')
    [void]$sb.Append('<p><a href="index.html">&larr; Danh sách hội thoại</a></p><h1>').Append((Html $s.Title)).Append('</h1><div class="meta">Thư mục: ').Append((Html $s.Cwd))
    [void]$sb.Append(' &middot; Bắt đầu: ').Append($(if ($s.Created) { $s.Created.ToString('dd/MM/yyyy HH:mm') } else { '?' })).Append(' &middot; Lần cuối: ').Append($(if ($s.Last) { $s.Last.ToString('dd/MM/yyyy HH:mm') } else { '?' })).Append('</div>')
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $msgs = 0; $lastRole = ''
    $rd = New-Object System.IO.StreamReader($s.File.FullName, [Text.Encoding]::UTF8)
    try {
        while ($null -ne ($line = $rd.ReadLine())) {
            if ($line.IndexOf('"type":"user"') -lt 0 -and $line.IndexOf('"type":"assistant"') -lt 0) { continue }
            try { $o = $ser.DeserializeObject($line) } catch { continue }
            if (-not ($o -is [System.Collections.IDictionary])) { continue }
            $t = [string]$o['type']
            if ($t -ne 'user' -and $t -ne 'assistant') { continue }
            if ($o['isSidechain'] -or $o['isMeta']) { continue }
            $uuid = [string]$o['uuid']
            if ($uuid -and -not $seen.Add($uuid)) { continue }
            $m = $o['message']
            if (-not ($m -is [System.Collections.IDictionary])) { continue }
            $c = $m['content']
            $time = ''
            if ($o['timestamp']) { try { $time = ([DateTime]::Parse([string]$o['timestamp'])).ToLocalTime().ToString('dd/MM HH:mm') } catch {} }
            if ($t -eq 'user') {
                $txt = ''
                if ($c -is [string]) { $txt = Clean-Text $c }
                else {
                    $parts = New-Object System.Collections.ArrayList
                    foreach ($b in @($c)) {
                        if (-not ($b -is [System.Collections.IDictionary])) { continue }
                        if ($b['type'] -eq 'text') { $x = Clean-Text ([string]$b['text']); if ($x) { [void]$parts.Add($x) } }
                        elseif ($b['type'] -eq 'image') { [void]$parts.Add('[ảnh]') }
                    }
                    $txt = $parts -join "`n`n"
                }
                if (-not $txt) { continue }
                if ($txt -match '^\s*<task-notification>') { continue }          # thông báo tác vụ nền, không phải lời người dùng
                if ($txt -match '<command-name>\s*([^<]+?)\s*</command-name>') {  # lệnh /xxx -> hiện gọn
                    $cmdName = $Matches[1]
                    if (-not $cmdName.StartsWith('/')) { $cmdName = '/' + $cmdName }
                    $cmdArgs = ''
                    if ($txt -match '(?s)<command-args>(.*?)</command-args>') { $cmdArgs = $Matches[1].Trim() }
                    $txt = ($cmdName + ' ' + $cmdArgs).Trim()
                }
                if ($o['isCompactSummary']) {
                    [void]$sb.Append('<details><summary>Tóm tắt phần trước (hội thoại quá dài nên đã được rút gọn)</summary><div class="t">').Append((Html $txt)).Append('</div></details>')
                } else {
                    [void]$sb.Append('<div class="m u"><div class="h">Bạn &middot; ').Append($time).Append('</div><div class="t">').Append((Html $txt)).Append('</div></div>')
                    $msgs++
                }
                $lastRole = 'u'
            } else {
                $blocks = if ($c -is [string]) { @(@{ type = 'text'; text = $c }) } else { @($c) }
                foreach ($b in $blocks) {
                    if (-not ($b -is [System.Collections.IDictionary])) { continue }
                    $bt = [string]$b['type']
                    if ($bt -eq 'text') {
                        $x = ([string]$b['text']).Trim()
                        if (-not $x) { continue }
                        [void]$sb.Append('<div class="m a">')
                        if ($lastRole -ne 'a') { [void]$sb.Append('<div class="h">Claude &middot; ').Append($time).Append('</div>') }
                        [void]$sb.Append('<div class="t">').Append((Html $x)).Append('</div></div>')
                        $msgs++; $lastRole = 'a'
                    } elseif ($bt -eq 'tool_use') {
                        [void]$sb.Append('<div class="tool">&#128295; ').Append((Html (Tool-Brief $b))).Append('</div>')
                    }
                }
            }
        }
    } finally { $rd.Close() }
    [void]$sb.Append('</body></html>')
    [IO.File]::WriteAllText($path, $sb.ToString(), $Utf8NoBom)
    return $msgs
}

function Export-CodeConversations([string]$cOut) {
    $sessDir = Join-Path $cOut 'AppData-Claude\claude-code-sessions'
    $projDir = Join-Path $cOut 'dot-claude\projects'
    if (-not (Test-Path -LiteralPath $sessDir)) { return }
    $tx = @{}
    if (Test-Path -LiteralPath $projDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $projDir -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue)) {
            if (-not $tx.ContainsKey($f.BaseName) -or $f.Length -gt $tx[$f.BaseName].Length) { $tx[$f.BaseName] = $f }
        }
    }
    $list = New-Object System.Collections.ArrayList
    foreach ($f in @(Get-ChildItem -LiteralPath $sessDir -Recurse -File -Filter 'local_*.json' -ErrorAction SilentlyContinue)) {
        try { $j = Read-Json $f.FullName } catch { continue }
        $cli = [string]$j.cliSessionId
        $tf = $null
        if ($cli -and $tx.ContainsKey($cli)) { $tf = $tx[$cli] }
        [void]$list.Add([pscustomobject]@{
            Id = [string]$j.sessionId; Title = [string]$j.title; Cwd = [string]$j.cwd; Archived = [bool]$j.isArchived
            Created = (To-Local $j.createdAt); Last = (To-Local $j.lastActivityAt); File = $tf
        })
    }
    $Stat.Code = $list.Count
    $Stat.CodeOk = @($list | Where-Object { $_.File }).Count
    if ($list.Count -eq 0) { return }
    if ($Stat.CodeOk -eq $list.Count) { Ok "Hội thoại tab Code: đủ $($Stat.CodeOk)/$($list.Count) cuộc (cả danh sách lẫn nội dung)" }
    else { Warn ("Hội thoại tab Code: chỉ có nội dung của $($Stat.CodeOk)/$($list.Count) cuộc. Thiếu: " + ((@($list | Where-Object { -not $_.File } | ForEach-Object { $_.Title })) -join '; ')) }

    # Bản đọc được bằng trình duyệt - phòng khi sau này ứng dụng không hiện lại được
    Info 'Đang tạo bản đọc được của từng cuộc hội thoại (mở bằng trình duyệt)...'
    $hDir = Join-Path $cOut 'HoiThoai-Code'
    Ensure-Dir $hDir
    try {
        Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
        $ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $ser.MaxJsonLength = [int]::MaxValue
        $ser.RecursionLimit = 1000
    } catch { Warn "Không tạo được bản đọc được: $($_.Exception.Message)"; return }
    $rows = New-Object System.Text.StringBuilder
    foreach ($s in @($list | Sort-Object -Property Last -Descending)) {
        if (-not $s.File) { continue }
        $short = ($s.Id -replace '^local_', '')
        if ($short.Length -gt 8) { $short = $short.Substring(0, 8) }
        $fn = '{0} {1} ({2}).html' -f $(if ($s.Last) { $s.Last.ToString('yyyy-MM-dd') } else { '0000-00-00' }), (Safe-Name $s.Title), $short
        try { $cnt = Write-ConversationHtml $s (Join-Path $hDir $fn) $ser }
        catch { Warn "Không tạo được bản đọc của '$($s.Title)': $($_.Exception.Message)"; continue }
        $Stat.CodeHtml++
        [void]$rows.Append('<tr><td>').Append($(if ($s.Last) { $s.Last.ToString('dd/MM/yyyy') } else { '' })).Append('</td><td><a href="').Append([Uri]::EscapeDataString($fn)).Append('">').Append((Html $s.Title)).Append('</a>')
        if ($s.Archived) { [void]$rows.Append(' <small>(đã lưu trữ)</small>') }
        [void]$rows.Append('</td><td>').Append((Html $s.Cwd)).Append('</td><td>').Append($cnt).Append('</td></tr>')
    }
    $idx = '<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Hội thoại Claude Code</title><style>' + $HtmlCss + '</style></head><body>' +
        '<h1>Hội thoại tab Code của Claude</h1><div class="meta">Sao lưu lúc ' + (Get-Date -Format 'dd/MM/yyyy HH:mm') + ' trên máy ' + (Html $env:COMPUTERNAME) + ' &middot; ' + $Stat.CodeHtml + ' cuộc hội thoại. Bản này chỉ để ĐỌC; để tiếp tục làm việc hãy dùng ứng dụng Claude sau khi khôi phục.</div>' +
        '<table><tr><th>Lần cuối</th><th>Tiêu đề</th><th>Thư mục</th><th>Tin nhắn</th></tr>' + $rows.ToString() + '</table></body></html>'
    [IO.File]::WriteAllText((Join-Path $hDir 'index.html'), $idx, $Utf8NoBom)
    Ok "Bản đọc được: Claude\HoiThoai-Code\index.html ($($Stat.CodeHtml) cuộc hội thoại)"
}

function Export-Claude {
    Head '3/5  CLAUDE'
    $cOut = Join-Path $Out 'Claude'
    Ensure-Dir $cOut
    $UP = $env:USERPROFILE

    # (a) Claude Code: ~\.claude (cài đặt, memory, lịch sử phiên, skills, plugins, tác vụ hẹn giờ)
    #     Bỏ: cache/log tạm và .credentials.json (token đăng nhập - không nên để trên USB, chỉ cần đăng nhập lại)
    # Cấu hình có thể chứa token (MCP, API key) đi qua Save-SecretFile: chọn mã hoá thì vào BiMat.aes.
    $dc = Join-Path $UP '.claude'
    if (Test-Path -LiteralPath $dc) {
        $xd = @('cache', 'telemetry', 'shell-snapshots', 'session-env', 'ide', 'sessions', 'statsig', 'debug') | ForEach-Object { Join-Path $dc $_ }
        $secretNames = @('settings.json', 'settings.local.json')
        $xf = @('.credentials.json', 'mcp-needs-auth-cache.json') + @($secretNames | ForEach-Object { Join-Path $dc $_ })
        $rc = Copy-Tree $dc (Join-Path $cOut 'dot-claude') $xd $xf
        $okSecret = $true
        foreach ($n in $secretNames) {
            $f = Join-Path $dc $n
            if ((Test-Path -LiteralPath $f -PathType Leaf) -and -not (Save-SecretFile "Claude\dot-claude\$n" $f)) { $okSecret = $false }
        }
        if ($rc -lt 8 -and $okSecret) { Ok 'Claude Code (~\.claude): cài đặt, memory, lịch sử phiên, skills, plugins, tác vụ hẹn giờ'; $Stat.Claude = $true }
        elseif ($rc -ge 8) { Fail "Chép ~\.claude bị lỗi (robocopy mã $rc)" }
    } else { Info 'Không có thư mục ~\.claude' }

    # (b) ~\.claude.json (cấu hình chung của Claude Code, MCP theo dự án...)
    $cj = Join-Path $UP '.claude.json'
    if (Test-Path -LiteralPath $cj) {
        if (Save-SecretFile 'Claude\dot-claude.json' $cj) { Ok 'Cấu hình chung Claude Code (~\.claude.json)'; $Stat.Claude = $true }
    }

    # (c) Claude Desktop. Bản cài MSIX lưu thật ở %LOCALAPPDATA%\Packages\Claude_xxx\LocalCache\Roaming\Claude
    $srcs = New-Object System.Collections.ArrayList
    $real = Join-Path $env:APPDATA 'Claude'
    if (Test-Path -LiteralPath $real) { [void]$srcs.Add($real) }
    foreach ($d in @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue)) {
        $v = Join-Path $d.FullName 'LocalCache\Roaming\Claude'
        if (Test-Path -LiteralPath $v) { [void]$srcs.Add($v) }
    }
    $aOut = Join-Path $cOut 'AppData-Claude'
    $deskSaved = $false; $deskBad = $false
    # File bí mật: lấy bản mới nhất trong các nơi Claude Desktop lưu (nơi đầu tiên luôn được lấy)
    $secretSrc = [ordered]@{}   # đường dẫn tương đối -> file nguồn
    $secretTime = @{}
    $first = $true
    foreach ($s in $srcs) {
        $cands = @()
        $f = Join-Path $s 'claude_desktop_config.json'
        if (Test-Path -LiteralPath $f -PathType Leaf) { $cands += [pscustomobject]@{ Rel = 'claude_desktop_config.json'; File = (Get-Item -LiteralPath $f) } }
        $es = Join-Path $s 'Claude Extensions Settings'
        foreach ($x in @(Get-ChildItem -LiteralPath $es -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            $cands += [pscustomobject]@{ Rel = ('Claude Extensions Settings\' + $x.FullName.Substring($es.Length).TrimStart('\')); File = $x }
        }
        foreach ($c in $cands) {
            if ($first -or -not $secretTime.ContainsKey($c.Rel) -or $c.File.LastWriteTimeUtc -gt $secretTime[$c.Rel]) {
                $secretSrc[$c.Rel] = $c.File.FullName; $secretTime[$c.Rel] = $c.File.LastWriteTimeUtc
            }
        }
        foreach ($sub in @('claude-code-sessions', 'local-agent-mode-sessions', 'Claude Extensions')) {
            $sd = Join-Path $s $sub
            if (Test-Path -LiteralPath $sd) {
                $rc = Copy-Tree $sd (Join-Path $aOut $sub) -KeepNewer:(-not $first)
                if ($rc -ge 8) { Fail "Chép '$sub' của Claude Desktop có lỗi (robocopy mã $rc)"; $deskBad = $true } else { $deskSaved = $true }
            }
        }
        $first = $false
    }
    foreach ($rel in $secretSrc.Keys) {
        if (Save-SecretFile "Claude\AppData-Claude\$rel" $secretSrc[$rel]) { $deskSaved = $true } else { $deskBad = $true }
    }
    if ($deskSaved -and -not $deskBad) { Ok 'Claude Desktop: cấu hình, danh sách phiên Code/Cowork, tác vụ hẹn giờ, extension'; $Stat.Claude = $true }
    elseif ($deskSaved) { $Stat.Claude = $true }
    elseif ($srcs.Count -eq 0) { Info 'Không thấy dữ liệu Claude Desktop trên máy.' }

    # (d) Thư mục file của Cowork (nếu nằm trên ổ C thì mới cần chép)
    $cowork = $null; $coworkSaved = $false
    $cfgFile = $secretSrc['claude_desktop_config.json']
    if ($cfgFile) { try { $cowork = [string](Read-Json $cfgFile).coworkUserFilesPath } catch {} }
    if ($cowork -and (Test-Path -LiteralPath $cowork)) {
        if ($cowork.Length -ge 2 -and $cowork.Substring(0, 2) -ieq $env:SystemDrive) {
            $rc = Copy-Tree $cowork (Join-Path $cOut 'Cowork-Files')
            if ($rc -lt 8) { $coworkSaved = $true; Ok "Thư mục file Cowork: $cowork" } else { Fail "Chép thư mục Cowork lỗi (robocopy mã $rc)" }
        } else { Info "Thư mục file Cowork ở ổ khác ($cowork) - không bị xóa khi cài Win, không cần chép." }
    }

    # (đ) Kiểm đếm hội thoại tab Code + tạo bản đọc được
    Export-CodeConversations $cOut

    # (e) Thư mục dự án (code, tài liệu) mà Claude đã làm việc - KHÔNG chép (có thể rất lớn) nhưng phải nhắc,
    #     vì nằm trên ổ C sẽ mất khi cài Win, lịch sử phiên Claude khôi phục xong sẽ trỏ vào thư mục không còn
    $top = @()
    if (Test-Path -LiteralPath $cj) {
        try {
            $UPt = $UP.TrimEnd('\')
            $proj = New-Object 'System.Collections.Generic.List[string]'
            $seenP = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($k in @((Read-Json $cj).projects.PSObject.Properties | ForEach-Object { $_.Name })) {
                $p = ([string]$k).Replace('/', '\').TrimEnd('\')
                if ($p.Length -le 3 -or $p.Substring(0, 2) -ine $env:SystemDrive) { continue }
                if ($p -ieq $UPt -or $p -like "$UPt\AppData\*" -or $p -like '*\.claude\*') { continue }
                if ((Test-Path -LiteralPath $p) -and $seenP.Add($p)) { $proj.Add($p) }
            }
            $top = @($proj | Sort-Object | Where-Object { $x = $_; @($proj | Where-Object { $x.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0 })
        } catch {}
    }
    if ($top.Count -gt 0) {
        Save-Text (Join-Path $cOut 'thu-muc-du-an.txt') ("CÁC THƯ MỤC DỰ ÁN CLAUDE TRÊN Ổ $($env:SystemDrive) - TỰ CHÉP SANG $($CopyHint.ToUpper()) TRƯỚC KHI CÀI WIN,`r`nCÀI XONG CHÉP VỀ ĐÚNG CHỖ CŨ:`r`n`r`n" + ($top -join "`r`n") + "`r`n")
        Warn "$($top.Count) thư mục dự án Claude (Desktop, Documents...) nằm trên ổ $($env:SystemDrive) KHÔNG nằm trong bản sao lưu này - tự chép chúng trước khi cài Win (danh sách: Claude\thu-muc-du-an.txt)."
    }

    Save-Json ([pscustomobject]@{ UserProfile = $UP; UserName = $env:USERNAME; CoworkPath = $cowork; CoworkSaved = $coworkSaved; ProjectFolders = @($top); AppDataSources = @($srcs) }) (Join-Path $cOut 'claude-info.json')
    Info 'Lưu ý: cuộc trò chuyện, Projects, skills trên tài khoản claude.ai nằm trên mây - đăng nhập lại là có.'
}

# ============================================================================ 4. KHOÁ BITLOCKER
# (Invoke-Bde, Get-BdeState, Get-BdeName, Get-BdeVolumeAt: lib\Chung.ps1)
function Export-BitLocker {
    Head '4/5  KHOÁ BITLOCKER'
    $bDir = Join-Path $Out 'BitLocker'
    $state = Get-BdeState
    if ($null -eq $state) { Warn 'Không đọc được BitLocker (cần quyền Administrator) - bản sao lưu không có khoá BitLocker.'; return }
    Ensure-Dir $bDir
    $now = Get-Date
    $txt = New-Object System.Collections.ArrayList     # trang-thai.txt: không có khoá
    $keys = New-Object System.Collections.ArrayList    # file khoá
    [void]$txt.Add("TRẠNG THÁI BITLOCKER LÚC SAO LƯU (không có khoá, chỉ có Mã khoá để đối chiếu)")
    [void]$txt.Add(("Máy: {0}   Lúc: {1:dd/MM/yyyy HH:mm}" -f $env:COMPUTERNAME, $now))
    [void]$txt.Add(('-' * 70))
    foreach ($s in $state) {
        $n = Get-BdeName $s
        $st = if ($s.Locked) { 'ĐANG BỊ KHOÁ' } elseif ($s.Conv -eq 0) { 'không mã hoá' } elseif ($s.Conv -in 2, 4) { 'đang mã hoá' } elseif ($s.Conv -in 3, 5) { 'đang giải mã' } elseif ($s.Prot -eq 1) { 'mã hoá, đang bảo vệ' } elseif ($s.Conv -eq 1) { 'mã hoá, bảo vệ đang tắt (tạm dừng hoặc chờ kích hoạt)' } else { 'không đọc được' }
        [void]$txt.Add("$n`: $st")
        foreach ($id in $s.Ids) { [void]$txt.Add(("     Mã khoá: {0} (màn hình khôi phục hiện {1})" -f $id, $id.Substring(1, 8))) }
        if (-not $s.Encrypted) { continue }
        if ($s.Type -ne 0 -and $s.Letter) { $Stat.BdeData += $s.Letter }
        if ($s.Locked) { Warn "$n đang bị khoá: mở khoá (bấm đúp ổ trong This PC) rồi chạy lại để lưu khoá của ổ này."; continue }
        if (-not $s.Ids.Count) {
            if ($s.Count -eq 0) { Info "$n đã mã hoá nhưng chưa kích hoạt bảo vệ: không cần khoá khôi phục." }
            else { Warn "$n mã hoá nhưng không có khoá khôi phục 48 số: chạy công cụ BitLocker > Lưu khoá khôi phục (thêm khoá) trước khi cài lại Win." }
            continue
        }
        foreach ($id in $s.Ids) {
            try {
                $k = [string](Invoke-Bde $s.Vol 'GetKeyProtectorNumericalPassword' @{ VolumeKeyProtectorID = $id }).NumericalPassword
                [void]$keys.Add([pscustomobject]@{ Name = $n; Id = $id; Key = $k })
                Ok ("{0}: đã lưu khoá có Mã khoá {1}" -f $n, $id.Substring(1, 8))
            } catch { Fail "Không đọc được khoá $id của $n ($($_.Exception.Message))." }
        }
    }
    Save-Text (Join-Path $bDir 'trang-thai.txt') (($txt -join "`r`n") + "`r`n")
    if (-not $keys.Count) {
        if (-not @($state | Where-Object { $_.Encrypted }).Count) { Info 'Không ổ nào mã hoá BitLocker.' }
        return
    }
    $L = New-Object System.Collections.ArrayList
    [void]$L.Add('KHOÁ KHÔI PHỤC BITLOCKER')
    [void]$L.Add(('Máy: {0}    Lưu lúc: {1:dd/MM/yyyy HH:mm}    Người lưu: {2}' -f $env:COMPUTERNAME, $now, $env:USERNAME))
    [void]$L.Add('')
    [void]$L.Add('Ai có khoá này đọc được dữ liệu trên ổ, kể cả khi tháo ổ sang máy khác. Cất ở nơi KHÁC ổ đó')
    [void]$L.Add('(USB riêng, điện thoại, giấy in); đừng gửi qua tin nhắn, email.')
    [void]$L.Add('')
    foreach ($k in $keys) {
        [void]$L.Add($k.Name)
        [void]$L.Add(('  Mã khoá (Key ID):         {0}' -f $k.Id))
        [void]$L.Add(('  Màn hình khôi phục hiện:  {0}' -f $k.Id.Substring(1, 8)))
        [void]$L.Add(('  Khoá khôi phục:           {0}' -f $k.Key))
        [void]$L.Add('')
    }
    [void]$L.Add('CÁCH DÙNG')
    [void]$L.Add('- Ổ dữ liệu bị khoá sau khi cài lại Win: chạy 2_NHAP_DU_LIEU.bat, chọn [1] hoặc [5]; hoặc bấm đúp ổ trong')
    [void]$L.Add('  This PC > More options > Enter recovery key, gõ 48 chữ số của khoá có Mã khoá khớp.')
    [void]$L.Add('- Màn hình "BitLocker recovery" khi khởi động: so "Recovery key ID" với Mã khoá ở trên rồi gõ khoá')
    [void]$L.Add('  (phím số không chạy thì dùng F1-F9 cho 1-9, F10 cho 0).')
    Save-Text (Join-Path $bDir ('BitLocker_KhoaKhoiPhuc_{0}_{1:yyyyMMdd_HHmmss}.txt' -f $env:COMPUTERNAME, $now)) (($L -join "`r`n") + "`r`n")
    $Stat.BdeKeys = $keys.Count
    $keys.Clear(); $L.Clear()
    Ok "Đã lưu $($Stat.BdeKeys) khoá khôi phục vào BitLocker\ (không hiện khoá ở đây)."
    $here = Get-BdeVolumeAt $Out $state
    if ($here -and $here.Encrypted -and $here.Type -ne 0) {
        Fail "Bản sao lưu nằm trên ổ $($here.Letter) đang mã hoá: cài lại Win xong ổ này bị khoá, khoá trong bản sao lưu cũng không mở được. Chép thư mục BitLocker ra USB hoặc in file khoá ra giấy NGAY."
    }
}

# ============================================================================ 5. DRIVER
# $DriverMode: net (driver mạng: Wi-Fi, mạng dây), all (mọi driver của hãng), none. Hỏi ở phần chính.
$DriverMode = 'net'
function Export-Drivers {
    Head '5/5  DRIVER'
    if ($DriverMode -eq 'none') { Info 'Đã chọn không sao lưu driver.'; return }
    $dDir = Join-Path $Out 'Driver'
    Ensure-Dir $dDir
    $pnp = @()
    try { $pnp = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop | Where-Object { [string]$_.InfName -match '^oem\d+\.inf$' }) } catch {}
    if ($DriverMode -eq 'all') {
        Info 'Đang xuất mọi driver của hãng (pnputil), có thể mất vài phút...'
        & pnputil.exe /export-driver '*' $dDir | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "pnputil báo mã $LASTEXITCODE khi xuất driver - có thể thiếu một số driver." }
    } else {
        $pnp = @($pnp | Where-Object { [string]$_.DeviceClass -eq 'NET' })
        if (-not $pnp.Count) { Info 'Không có driver mạng của hãng (máy dùng driver sẵn có của Windows) - bỏ qua.'; return }
        foreach ($inf in @($pnp | ForEach-Object { [string]$_.InfName } | Select-Object -Unique)) {
            $sub = Join-Path $dDir ([IO.Path]::GetFileNameWithoutExtension($inf))
            Ensure-Dir $sub
            & pnputil.exe /export-driver $inf $sub | Out-Null
            if ($LASTEXITCODE -ne 0) { Fail "Không xuất được driver $inf (pnputil mã $LASTEXITCODE)." }
        }
    }
    $list = @($pnp | Sort-Object DeviceClass, DeviceName | ForEach-Object { '{0,-12} {1,-12} {2} | {3} {4}' -f $_.InfName, $_.DeviceClass, $_.DeviceName, $_.DriverProviderName, $_.DriverVersion })
    Save-Text (Join-Path $dDir 'danh-sach.txt') ("DRIVER ĐÃ SAO LƯU (file .inf | loại | thiết bị | hãng, phiên bản)`r`n" + ('-' * 70) + "`r`n" + ($list -join "`r`n") + "`r`n")
    $Stat.DriverPkgs = @(Get-ChildItem -LiteralPath $dDir -Recurse -Filter '*.inf' -File -ErrorAction SilentlyContinue).Count
    if ($Stat.DriverPkgs) { Ok ("Driver: {0} gói, {1}" -f $Stat.DriverPkgs, (Fmt-Size (Get-Size $dDir))) } else { Warn 'Không xuất được driver nào.' }
}

# ============================================================================ NƠI LƯU
function Get-SaveChoices {
    # Ổ có thể lưu: USB, ổ cứng ngoài trước; rồi ổ dữ liệu chưa mã hoá; ổ dữ liệu mã hoá; ổ Windows sau cùng
    $list = New-Object System.Collections.ArrayList
    $sys = ([string]$env:SystemDrive).ToUpperInvariant()
    foreach ($d in @(Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -in 2, 3 -and $_.Size })) {
        $l = ([string]$d.DeviceID).ToUpperInvariant()
        $usb = ([int]$d.DriveType -eq 2)
        if (-not $usb) { try { if ([string](Get-Partition -DriveLetter $l[0] -ErrorAction Stop | Get-Disk -ErrorAction Stop).BusType -eq 'USB') { $usb = $true } } catch {} }
        $bde = if ($script:BdeState) { Get-BdeVolumeAt "$l\" $script:BdeState } else { $null }
        $enc = [bool]($bde -and $bde.Encrypted)
        $rank = if ($l -eq $sys) { 3 } elseif ($usb) { 0 } elseif ($enc) { 2 } else { 1 }
        [void]$list.Add([pscustomobject]@{ Letter = $l; Label = [string]$d.VolumeName; Free = [long]$d.FreeSpace; Usb = $usb; System = ($l -eq $sys); Encrypted = $enc; Rank = $rank })
    }
    return @($list | Sort-Object Rank, Letter)
}

function Format-SaveChoice($c) {
    $kind = if ($c.System) { 'Ổ WINDOWS: bị xoá khi cài lại, xong phải chép ra USB' }
            elseif ($c.Usb) { 'USB / ổ cứng ngoài' }
            elseif ($c.Encrypted) { 'ổ dữ liệu MÃ HOÁ BitLocker: bị khoá sau khi cài lại' }
            else { 'ổ dữ liệu' }
    $label = if ($c.Label) { " ($($c.Label))" } else { '' }
    return ('{0}\{1}  còn trống {2}  - {3}' -f $c.Letter, $label, (Fmt-Size $c.Free), $kind)
}

function Resolve-SaveDir([string]$Target) {
    # Thư mục DuLieu_SaoLuu sẽ tạo trong nơi lưu (vd E:\ -> E:\DuLieu_SaoLuu); tên cuối đã là DuLieu_SaoLuu thì dùng luôn
    $t = ([string]$Target).Trim().Trim('"')
    if ($t -match '^[A-Za-z]:$') { $t += '\' }
    try { $full = [IO.Path]::GetFullPath($t) } catch { return $null }
    if ((Split-Path -Leaf $full.TrimEnd('\')) -ieq 'DuLieu_SaoLuu') { return $full.TrimEnd('\') }
    return [IO.Path]::Combine($full, 'DuLieu_SaoLuu')   # Join-Path báo lỗi khi ổ chưa có; Test-SaveDir báo gọn hơn
}

function Test-SaveDir([string]$Dir) {
    # '' = dùng được; ngược lại là lý do không lưu được vào đó
    if (-not $Dir -or $Dir -notmatch '^([A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)') { return 'phải là đường dẫn đầy đủ (vd E:\ hoặc D:\SaoLuu)' }
    $st = Get-StationDir
    if ($st -and (Test-UnderPath $Dir $st)) { return "nằm trong thư mục Trạm Tool ($st). Bản sao lưu có mật khẩu Wi-Fi, khoá BitLocker, không để cạnh công cụ" }
    if ($Dir -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $Dir.Substring(0, 3))) { return "không có ổ $($Dir.Substring(0, 2))" }
    $parent = Split-Path -Parent $Dir
    if ($parent -and (Test-Path -LiteralPath $parent -PathType Leaf)) { return "$parent là một file, không phải thư mục" }
    return ''
}

function Select-SaveDir {
    # Trả đường dẫn DuLieu_SaoLuu; $null khi huỷ
    if ($script:Opt.Target) { return (Resolve-SaveDir $script:Opt.Target) }
    $ch = @(Get-SaveChoices)
    Write-Host ''
    Write-Host '  LƯU BẢN SAO LƯU VÀO ĐÂU? (tạo thư mục DuLieu_SaoLuu ở gốc ổ được chọn)' -ForegroundColor White
    for ($i = 0; $i -lt $ch.Count; $i++) { Write-Host ('   {0}. {1}' -f ($i + 1), (Format-SaveChoice $ch[$i])) }
    Write-Host '   N. Nhập đường dẫn khác'
    Write-Host '   0. Huỷ'
    while ($true) {
        $a = Read-Answer 'Chọn' $(if ($ch.Count) { '1' } else { 'N' })
        if ($a -eq '0') { return $null }
        if ($a -match '^[Nn]$') {
            $p = Read-Answer 'Đường dẫn nơi lưu (vd E:\ hoặc D:\SaoLuu; Enter = huỷ)' ''
            if (-not $p) { return $null }
            return (Resolve-SaveDir $p)
        }
        $n = 0
        if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $ch.Count) { return (Resolve-SaveDir ($ch[$n - 1].Letter + '\')) }
        Write-Host "  Gõ một số từ 1 đến $($ch.Count), N hoặc 0." -ForegroundColor Yellow
        if ($script:Yes) { return $null }
    }
}

function Show-SaveDirNotes([string]$Dir) {
    # Cảnh báo theo ổ đích (ổ Windows, ổ mã hoá, chỗ trống). Trả $false khi không đủ chỗ mà người dùng không muốn tiếp.
    $sysRoot = ([string]$env:SystemDrive) + '\'
    if (Test-UnderPath $Dir $sysRoot) {
        Write-Host ''
        Write-Host "  [!] Nơi lưu nằm trên ổ $($env:SystemDrive), ổ này SẼ BỊ XOÁ khi cài lại Win." -ForegroundColor Yellow
        Write-Host "      Làm xong phải chép cả thư mục DuLieu_SaoLuu sang $script:CopyHint." -ForegroundColor Yellow
    }
    $here = if ($script:BdeState) { Get-BdeVolumeAt $Dir $script:BdeState } else { $null }
    if ($here -and $here.Encrypted -and $here.Type -eq 1) {
        Write-Host ''
        Write-Host "  [!] Ổ $($here.Letter) mã hoá BitLocker. Cài lại Win xong ổ $($here.Letter) bị khoá:" -ForegroundColor Red
        Write-Host '      phải có khoá ở nơi khác (USB, giấy in, https://aka.ms/myrecoverykey) mới lấy lại được bản sao lưu.' -ForegroundColor Red
    } elseif ($here -and $here.Encrypted -and $here.Type -eq 2) {
        Write-Host ''
        Write-Host "  [i] USB $($here.Letter) mã hoá BitLocker: nhớ mật khẩu của USB để mở trên Windows mới." -ForegroundColor Gray
    }
    if ($Dir -match '^([A-Za-z]):') {
        try {
            $need = (Get-Size (Join-Path $env:USERPROFILE '.claude')) + 300MB
            $free = (New-Object System.IO.DriveInfo($Matches[1])).AvailableFreeSpace
            Info ("Cần khoảng {0}, ổ đích còn trống {1}" -f (Fmt-Size $need), (Fmt-Size $free))
            if ($free -lt $need) {
                Warn 'Ổ đích có thể KHÔNG ĐỦ CHỖ.'
                if (-not $script:Opt.DryRun -and -not (Read-YesNo 'Vẫn tiếp tục?' $false)) { return $false }
            }
        } catch {}
    }
    return $true
}

# ============================================================================ MÃ HOÁ
function Read-NewPassword {
    # Hỏi mật khẩu mới 2 lần; $null khi bỏ
    for ($i = 1; $i -le 3; $i++) {
        $p1 = Read-Secret 'Đặt mật khẩu cho phần mã hoá (ít nhất 8 ký tự, không hiện chữ)'
        if ($p1.Length -lt 8) { Write-Host '  Mật khẩu phải có ít nhất 8 ký tự.' -ForegroundColor Yellow; continue }
        $p2 = Read-Secret 'Gõ lại mật khẩu'
        if ($p1 -ceq $p2) { return $p1 }
        Write-Host '  Hai lần gõ không giống nhau.' -ForegroundColor Yellow
    }
    return $null
}

function Test-SameBytes([byte[]]$A, [byte[]]$B) {
    if ($A.Length -ne $B.Length) { return $false }
    $h = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($h.ComputeHash($A)) -eq [BitConverter]::ToString($h.ComputeHash($B))) } finally { $h.Dispose() }
}

function Save-SecretBundle {
    # Ghi các file bí mật đang giữ trong bộ nhớ vào BiMat.aes, đọc lại và giải mã thử để chắc chắn mở được
    if ($null -eq $script:Secret) { return }
    Head 'MÃ HOÁ PHẦN BÍ MẬT'
    try {
        if ($script:Secret.Count -eq 0) { Info 'Không có file nào cần mã hoá.'; return }
        $zip = New-ZipBytes $script:Secret
        $blob = Protect-Bytes $zip $script:Password
        $path = Join-Path $script:Out $script:SecretFile
        [IO.File]::WriteAllBytes("$path.tmp", $blob)
        Move-Item -LiteralPath "$path.tmp" -Destination $path -Force -ErrorAction Stop
        $back = Unprotect-Bytes ([IO.File]::ReadAllBytes($path)) $script:Password
        if (-not (Test-SameBytes $back $zip)) { throw 'giải mã thử không ra đúng nội dung' }
        $script:Stat.Secret = $script:Secret.Count
        Ok ("Đã mã hoá {0} file (mật khẩu Wi-Fi, cấu hình Claude) vào {1}; đã giải mã thử được." -f $script:Secret.Count, $script:SecretFile)
    } catch {
        Fail "Không mã hoá được phần bí mật ($($_.Exception.Message)): mật khẩu Wi-Fi và cấu hình Claude KHÔNG có trong bản sao lưu, chạy lại."
    } finally {
        $script:Secret.Clear(); $script:Password = $null
    }
}

# ============================================================================ CHẠY THỬ
function Show-ExportPlan {
    Head 'CHẠY THỬ: CHỈ XEM SẼ LÀM GÌ, KHÔNG GHI FILE, KHÔNG ĐỔI MÁY'
    Plan "Nơi lưu: $script:Out"
    if (Test-Path -LiteralPath $script:Out) { Plan "Đã có bản sao lưu ở đó: sẽ đổi tên thành $(Split-Path -Leaf $script:Out)_cu_<giờ>" }
    $n = $null
    if (Load-WlanApi) {
        try { $n = @([WlanTool]::ListProfiles() | Where-Object { ($_.Flags -band 1) -eq 0 } | ForEach-Object { $_.Name } | Select-Object -Unique).Count } catch {}
    }
    Plan ('Wi-Fi: {0} mạng đã lưu (kèm mật khẩu khi chạy thật)' -f $(if ($null -ne $n) { $n } else { 'không đọc được' }))
    $pr = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { -not (Test-BuiltinPrinter $_) })
    Plan ('Máy in: {0}{1}' -f $pr.Count, $(if ($pr.Count) { ' (' + ((@($pr | ForEach-Object { $_.Name })) -join ', ') + ')' } else { '' }))
    $dc = Join-Path $env:USERPROFILE '.claude'
    $desk = @((Join-Path $env:APPDATA 'Claude')) + @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'LocalCache\Roaming\Claude' })
    $desk = @($desk | Where-Object { Test-Path -LiteralPath $_ })
    Plan ('Claude: ~\.claude {0}, ~\.claude.json {1}, dữ liệu Claude Desktop {2} nơi' -f $(if (Test-Path -LiteralPath $dc) { Fmt-Size (Get-Size $dc) } else { 'không có' }), $(if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.claude.json')) { 'có' } else { 'không có' }), $desk.Count)
    if ($null -eq $script:BdeState) { Plan 'Khoá BitLocker: chạy thật bằng quyền Admin mới đọc được' }
    else {
        $enc = @($script:BdeState | Where-Object { $_.Encrypted })
        $ids = 0; foreach ($s in $enc) { $ids += @($s.Ids).Count }
        Plan ('Khoá BitLocker: {0} ổ mã hoá, {1} khoá khôi phục sẽ được lưu (chưa đọc khoá)' -f $enc.Count, $ids)
    }
    $mode = if ($script:Opt.Driver) { $script:Opt.Driver } else { 'mang' }
    Plan ('Driver: {0}' -f @{ mang = 'driver mạng của hãng (Wi-Fi, mạng dây)'; 'tat-ca' = 'mọi driver của hãng (có thể vài GB)'; khong = 'không sao lưu' }[$mode])
    if ($script:Opt.MaHoa) { Plan 'Mã hoá mật khẩu Wi-Fi và cấu hình Claude vào BiMat.aes (hỏi mật khẩu khi chạy thật)' }
    else { Plan 'Mã hoá: chạy thật sẽ hỏi có mã hoá mật khẩu Wi-Fi và cấu hình Claude không' }
    if (@(Get-ClaudeDesktopProcess).Count) { Plan 'Claude Desktop đang mở: chạy thật sẽ hỏi có tự đóng không' }
}

# ============================================================================ XUẤT
function Write-ExportManifest([string]$State) {
    # Lúc đang làm: có chọn mã hoá không; lúc xong: BiMat.aes có thật được ghi không
    $enc = if ($State -eq 'dang-lam') { $null -ne $script:Secret } else { $script:Stat.Secret -gt 0 }
    $m = [ordered]@{
        Format = 2; CongCu = 'new-windows'; PhienBan = $script:Version; TrangThai = $State
        BatDau = $script:StartTime.ToString('s'); KetThuc = $(if ($State -ne 'dang-lam') { (Get-Date).ToString('s') } else { $null })
        May = $env:COMPUTERNAME; NguoiDung = $env:USERNAME; UserProfile = $env:USERPROFILE
        MaHoa = $enc; TepMaHoa = $(if ($enc) { $script:SecretFile } else { $null })
        Phan = [ordered]@{ WiFi = $script:Stat.Wifi; MayIn = $script:Stat.Printers; Claude = $script:Stat.Claude; KhoaBitLocker = $script:Stat.BdeKeys; GoiDriver = $script:Stat.DriverPkgs; FileMaHoa = $script:Stat.Secret }
        Loi = @($script:Errors); LuuY = @($script:Warnings)
    }
    Save-JsonAtomic $m (Join-Path $script:Out 'manifest.json')
}

function Invoke-Xuat {
    $script:Stat = @{ Wifi = 0; WifiNoKey = 0; Printers = 0; Drivers = 0; Claude = $false; Code = 0; CodeOk = 0; CodeHtml = 0; BdeKeys = 0; BdeData = @(); DriverPkgs = 0; Secret = 0 }
    $script:CopyHint = 'USB hoặc ổ khác'
    $script:StartTime = Get-Date
    try { $Host.UI.RawUI.WindowTitle = 'Xuất dữ liệu trước khi cài lại Windows' } catch {}
    Write-Host ''
    Write-Host '  ==================================================================' -ForegroundColor Cyan
    Write-Host '     XUẤT DỮ LIỆU TRƯỚC KHI CÀI LẠI WINDOWS' -ForegroundColor White
    Write-Host '     Wi-Fi (kèm mật khẩu)  -  Máy in  -  Claude  -  Khoá BitLocker  -  Driver' -ForegroundColor White
    Write-Host '  ==================================================================' -ForegroundColor Cyan

    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $console = Get-ConsoleUser
    if ($console -and $console -ine $me) {
        Warn "Đang chạy bằng tài khoản $me nhưng người đang dùng máy là ${console}: Claude, máy in mặc định sẽ là của $me."
        if (-not (Read-YesNo 'Vẫn sao lưu tài khoản đang chạy?' $false)) { return 2 }
    }
    if (-not (Test-IsAdmin)) { Info 'Chưa có quyền Administrator: chạy thật mới đọc được mật khẩu Wi-Fi, driver máy in, khoá BitLocker.' }

    # Ổ dữ liệu đang mã hoá BitLocker sẽ bị khoá sau khi cài lại Win: không khuyên chép bản sao lưu sang đó.
    $script:BdeState = Get-BdeState
    if ($null -ne $script:BdeState) {
        $plain = @($script:BdeState | Where-Object { $_.Type -eq 1 -and $_.Letter -and -not $_.Encrypted } | ForEach-Object { $_.Letter })
        $script:CopyHint = if ($plain.Count) { 'USB hoặc ổ ' + ($plain -join ', ') } else { 'USB' }
        $encData = @($script:BdeState | Where-Object { $_.Type -eq 1 -and $_.Encrypted })
        if ($encData.Count) {
            Write-Host ''
            Write-Host ("  [!] {0} đang mã hoá BitLocker: cài lại Win xong sẽ BỊ KHOÁ, cần khoá khôi phục mới mở được." -f (@($encData | ForEach-Object { Get-BdeName $_ }) -join ', ')) -ForegroundColor Yellow
            Write-Host '      Công cụ lưu khoá vào DuLieu_SaoLuu\BitLocker; đừng để bản sao lưu CHỈ nằm trên các ổ đó.' -ForegroundColor Yellow
        }
    }

    $dir = Select-SaveDir
    if (-not $dir) { Info 'Đã huỷ, chưa ghi gì.'; return 2 }
    $why = Test-SaveDir $dir
    if ($why) { Fail "Không lưu vào $dir`: $why."; return 2 }
    $script:Out = $dir
    Write-Host ''
    Write-Host "  Dữ liệu sẽ được lưu vào:  $script:Out" -ForegroundColor White
    if (-not (Show-SaveDirNotes $script:Out)) { Info 'Đã huỷ, chưa ghi gì.'; return 2 }

    if ($script:Opt.DryRun) { $null = Show-ExportPlan; return 0 }

    if (@(Get-ClaudeDesktopProcess).Count -gt 0) {
        Write-Host ''
        Write-Host '  [!] Claude Desktop đang mở. Nên thoát hẳn Claude để sao lưu đầy đủ nhất.' -ForegroundColor Yellow
        $a = Read-Answer 'Gõ T rồi Enter để TỰ ĐÓNG Claude Desktop, hoặc chỉ nhấn Enter để chép luôn' ''
        if ($a -match '^\s*[Tt]') { Get-ClaudeDesktopProcess | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3 }
    }

    if ($script:Opt.Driver) { $mode = $script:Opt.Driver }
    else {
        Write-Host ''
        Write-Host '  Sao lưu driver để cài lại khi Windows mới thiếu driver (nhất là Wi-Fi, mạng dây):' -ForegroundColor White
        $a = Read-Answer '[Enter] = driver mạng (nhỏ, nên có)   [T] = mọi driver của hãng (có thể vài GB)   [K] = không' ''
        $mode = if ($a -match '^\s*[Tt]') { 'tat-ca' } elseif ($a -match '^\s*[Kk]') { 'khong' } else { 'mang' }
    }
    $script:DriverMode = @{ mang = 'net'; 'tat-ca' = 'all'; khong = 'none' }[$mode]

    $encrypt = [bool]$script:Opt.MaHoa
    if (-not $encrypt) {
        Write-Host ''
        Write-Host '  Mật khẩu Wi-Fi và cấu hình Claude (có thể chứa token) có thể được mã hoá bằng mật khẩu riêng' -ForegroundColor White
        Write-Host '  (BiMat.aes). Nên chọn khi bản sao lưu nằm trên USB hay ổ người khác dùng; bước nhập sẽ hỏi lại mật khẩu.' -ForegroundColor White
        $encrypt = Read-YesNo 'Mã hoá phần bí mật?' (-not $script:Yes)
    }
    if ($encrypt) {
        $script:Password = Read-NewPassword
        if (-not $script:Password) { Fail 'Chưa đặt được mật khẩu, chưa ghi gì.'; return 2 }
        $script:Secret = [ordered]@{}
        Info 'Nhớ mật khẩu này: quên thì không lấy lại được mật khẩu Wi-Fi và cấu hình Claude trong bản sao lưu.'
    }

    Write-Host ''
    if (-not (Read-YesNo 'Bắt đầu sao lưu?' $true)) { Info 'Đã huỷ, chưa ghi gì.'; $script:Password = $null; return 2 }

    if (Test-Path -LiteralPath $script:Out) {
        $old = $script:Out + '_cu_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
        try { Rename-Item -LiteralPath $script:Out -NewName (Split-Path -Leaf $old) -ErrorAction Stop; Info "Bản sao lưu cũ được đổi tên thành: $(Split-Path -Leaf $old) (cũng có mật khẩu Wi-Fi: xoá khi không cần)" }
        catch { Fail "Không đổi tên được thư mục sao lưu cũ ($($_.Exception.Message)). Hãy đóng các cửa sổ đang mở thư mục đó rồi chạy lại."; return 1 }
    }
    try { Ensure-Dir $script:Out } catch { Fail "Không tạo được $script:Out`: $($_.Exception.Message)"; return 1 }
    $script:Started = $true
    $null = Write-ExportManifest 'dang-lam'
    try { Start-Transcript -Path (Join-Path $script:Out 'nhat-ky-xuat.txt') -Force | Out-Null } catch {}

    try {
        $null = Export-Wifi
        $null = Export-Printers
        $null = Export-Claude
        $null = Export-BitLocker
        $null = Export-Drivers
        $null = Save-SecretBundle
    } catch {
        Fail ('Lỗi không lường trước: {0}' -f $_.Exception.Message)
        if ($null -ne $script:Secret) { $script:Secret.Clear() }
        $script:Password = $null
        $null = Write-ExportManifest 'loi'
        try { Stop-Transcript | Out-Null } catch {}
        return 1
    }

    $osName = ''
    try { $osName = (Get-CimInstance Win32_OperatingSystem).Caption } catch {}
    Save-Json ([pscustomobject]@{
        Version = 1; Date = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); Computer = $env:COMPUTERNAME
        UserName = $env:USERNAME; UserProfile = $env:USERPROFILE; Windows = $osName
        Wifi = $Stat.Wifi; Printers = $Stat.Printers; Drivers = $Stat.Drivers; Claude = $Stat.Claude
        BitLockerKeys = $Stat.BdeKeys; BitLockerDataDrives = @($Stat.BdeData); DriverPackages = $Stat.DriverPkgs
    }) (Join-Path $script:Out 'thong-tin.json')
    $null = Write-ExportGuide

    $state = if ($script:Errors.Count) { 'mot-phan' } else { 'xong' }
    $null = Write-ExportManifest $state
    $null = Show-ExportSummary $state
    try { Stop-Transcript | Out-Null } catch {}
    if ($state -eq 'xong') { return 0 } else { return 3 }
}

function Write-ExportGuide {
    $bdeGuide = ''
    if ($Stat.BdeKeys -gt 0 -or @($Stat.BdeData).Count -gt 0) {
        $bdeGuide = "`nKHOÁ BITLOCKER: thư mục BitLocker có khoá khôi phục ($($Stat.BdeKeys) khoá) và trang-thai.txt để đối chiếu Mã khoá.`n"
        if (@($Stat.BdeData).Count -gt 0) {
            $bdeGuide += @"
- Ổ $(@($Stat.BdeData) -join ', ') đang mã hoá: cài lại Win xong sẽ BỊ KHOÁ. Chạy 2_NHAP_DU_LIEU.bat, chọn [1] hoặc [5]
  để mở bằng khoá đã lưu. Muốn ổ tự mở mỗi lần khởi động: công cụ BitLocker của Trạm Tool (Mở khoá ổ) hoặc
  chuột phải ổ > Manage BitLocker; không cần mã hoá nữa thì Giải mã.
- Bản sao lưu nằm trên chính ổ đang mã hoá thì phải có khoá ở nơi khác (USB, giấy in,
  https://aka.ms/myrecoverykey) mới mở được ổ đó để lấy bản sao lưu.

"@
        } else {
            $bdeGuide += "- Chỉ ổ Windows mã hoá: cài lại Win sẽ xoá ổ đó nên không cần khoá nữa; khoá chỉ dùng khi KHÔNG cài lại.`n"
        }
    }
    $secretGuide = if ($Stat.Secret -gt 0) { "`nMÃ HOÁ: mật khẩu Wi-Fi và cấu hình Claude nằm trong BiMat.aes, mở bằng mật khẩu đã đặt lúc xuất`n(2_NHAP_DU_LIEU.bat sẽ hỏi). Quên mật khẩu thì phải nhập lại mật khẩu Wi-Fi, cấu hình Claude bằng tay.`n" } else { '' }
    $guide = @"
HƯỚNG DẪN KHÔI PHỤC SAU KHI CÀI LẠI WINDOWS
==========================================
Sao lưu lúc: $(Get-Date -Format 'dd/MM/yyyy HH:mm') - máy: $env:COMPUTERNAME - người dùng: $env:USERNAME
Bản sao lưu: $script:Out (manifest.json ghi đã xong hay chưa)

0. TRƯỚC khi cài Win: tự chép các thư mục dự án/tài liệu của bạn trên ổ C (Desktop, Documents...;
   danh sách thư mục Claude từng làm việc nằm trong Claude\thu-muc-du-an.txt) sang $script:CopyHint.
   Cài xong chép về ĐÚNG chỗ cũ để lịch sử phiên Claude mở lại được.
1. Bản sao lưu nằm trên ổ Windows thì chép cả thư mục DuLieu_SaoLuu ra USB trước khi cài.
   Bước nhập tự tìm DuLieu_SaoLuu ở gốc các ổ và USB; để chỗ khác thì chọn thư mục đó khi được hỏi.
2. Cài Windows xong, nên đặt tên tài khoản giống cũ ($env:USERNAME) - nếu khác, công cụ tự sửa đường dẫn cho Claude.
3. Cài driver Wi-Fi (thường Windows tự cài; không có thì chạy 2_NHAP_DU_LIEU.bat chọn [6] để cài driver
   đã sao lưu trong thư mục Driver).
4. (Nên làm) Cài Claude Desktop từ https://claude.ai/download -> mở, đăng nhập -> THOÁT HẲN
   (chuột phải biểu tượng Claude ở khay đồng hồ -> Quit).
5. Chạy 2_NHAP_DU_LIEU.bat (trong Trạm Tool hoặc thư mục công cụ new-windows) -> bấm Yes -> chọn
   [1] Khôi phục tất cả (driver, mở khoá ổ BitLocker, Wi-Fi, máy in, Claude). Nếu lúc đó chưa cài Claude:
   cứ chạy, sau khi cài Claude chạy lại và chọn [4].
6. Máy in USB: cắm cáp vào, Windows tự nhận (driver đã được cài sẵn).
$bdeGuide$secretGuide
HỘI THOẠI TAB CODE CỦA CLAUDE: được khôi phục vào ứng dụng ở bước 5 (chép thư mục dự án về đúng
chỗ cũ TRƯỚC khi mở Claude). Ngoài ra còn có bản đọc được của từng cuộc hội thoại:
Claude\HoiThoai-Code\index.html (nhấp đúp mở bằng trình duyệt, không cần cài gì).

BẢO MẬT: thư mục BitLocker chứa khoá mở được ổ đĩa$(if ($Stat.Secret -gt 0) { '' } else { ', thư mục WiFi chứa mật khẩu Wi-Fi dạng chữ thường' }).
Khôi phục xong nên xóa bản sao lưu hoặc cất USB cẩn thận. Token đăng nhập Claude KHÔNG được sao lưu
(chỉ cần đăng nhập lại).
"@
    Save-Text (Join-Path $script:Out 'HUONG_DAN.txt') ($guide -replace "(?<!`r)`n", "`r`n")
}

function Show-ExportSummary([string]$State) {
    Head $(if ($State -eq 'xong') { 'HOÀN TẤT' } else { 'XONG MỘT PHẦN' })
    $total = Get-Size $script:Out
    Write-Host ("  Wi-Fi     : {0} mạng" -f $Stat.Wifi) -ForegroundColor White
    Write-Host ("  Máy in    : {0} máy in, {1} driver" -f $Stat.Printers, $Stat.Drivers) -ForegroundColor White
    Write-Host ("  Claude    : {0}" -f $(if ($Stat.Claude) { 'đã sao lưu' } else { 'không có dữ liệu' })) -ForegroundColor White
    if ($Stat.Code -gt 0) { Write-Host ("  Hội thoại Code: {0}/{1} cuộc (bản đọc được: Claude\HoiThoai-Code\index.html)" -f $Stat.CodeOk, $Stat.Code) -ForegroundColor White }
    Write-Host ("  BitLocker : {0}" -f $(if ($Stat.BdeKeys) { "$($Stat.BdeKeys) khoá khôi phục" } else { 'không có khoá cần lưu' })) -ForegroundColor White
    Write-Host ("  Driver    : {0}" -f $(if ($DriverMode -eq 'none') { 'không sao lưu' } else { "$($Stat.DriverPkgs) gói" })) -ForegroundColor White
    if ($Stat.Secret -gt 0) { Write-Host ("  Mã hoá    : {0} file trong {1}" -f $Stat.Secret, $script:SecretFile) -ForegroundColor White }
    Write-Host ("  Dung lượng: {0}" -f (Fmt-Size $total)) -ForegroundColor White
    Write-Host ("  Thư mục   : {0}" -f $script:Out) -ForegroundColor White
    if ($script:Errors.Count -gt 0) {
        Write-Host ''
        Write-Host "  Có $($script:Errors.Count) việc KHÔNG làm được (bản sao lưu ghi là 'xong một phần'):" -ForegroundColor Red
        foreach ($e in $script:Errors) { Write-Host "   - $e" -ForegroundColor Red }
    }
    if ($script:Warnings.Count -gt 0) {
        Write-Host ''
        Write-Host "  Có $($script:Warnings.Count) lưu ý:" -ForegroundColor Yellow
        foreach ($w in $script:Warnings) { Write-Host "   - $w" -ForegroundColor Yellow }
    }
    Write-Host ''
    Write-Host '  BƯỚC TIẾP THEO:' -ForegroundColor Cyan
    if (Test-UnderPath $script:Out (([string]$env:SystemDrive) + '\')) {
        Write-Host "   * CHÉP thư mục DuLieu_SaoLuu sang $script:CopyHint NGAY (ổ $($env:SystemDrive) sẽ bị xóa)!" -ForegroundColor Red
    }
    if (@($Stat.BdeData).Count -gt 0) {
        Write-Host ("   * Ổ {0} mã hoá BitLocker: giữ thêm một bản thư mục BitLocker ở nơi KHÁC các ổ đó (USB, giấy in)." -f (@($Stat.BdeData) -join ', ')) -ForegroundColor Yellow
    }
    Write-Host '   * Đọc file HUONG_DAN.txt trong thư mục sao lưu.' -ForegroundColor Cyan
    Write-Host '   * Sau khi cài lại Win: chạy 2_NHAP_DU_LIEU.bat, công cụ tự tìm DuLieu_SaoLuu ở gốc các ổ và USB.' -ForegroundColor Cyan
}
