# Máy in mạng LAN - chẩn đoán, chỉ đọc. Ghi báo cáo ket_qua\BaoCao_MayIn_<tên máy>_<thời gian>.txt.

$script:Diag = @{}

function Invoke-Section {
    # Một phần của báo cáo; phần lỗi thì ghi lý do rồi chạy tiếp phần sau.
    param([string]$Title, [scriptblock]$Body)
    Write-Head $Title
    try { & $Body } catch { Write-Warn ('Không đọc được phần này: {0}' -f $_.Exception.Message.Trim()) }
}

function Format-YesNo { param($Value) if ($Value) { return 'có' } return 'không' }

function Get-FixForCode {
    # Chế độ nên chạy theo mã lỗi khi vào máy khác.
    param([int64]$Code)
    if ($Code -in 1272, 3227320323, 2148073478, 3221266432, 1801, 3012, 283) { return 'noi-bao-mat' }
    if ($Code -in 5, 86, 1326, 1219) { return 'ket-noi-thu-muc' }
    if ($Code -in 53, 1722, 1753) { return 'bat-chia-se' }
    return ''
}

function Invoke-ChanDoan {
    param([string]$MayChu = '')
    $script:Report.Clear(); $script:Findings.Clear()
    $script:Diag = @{ Admin = (Test-IsAdmin); Profiles = @(); Services = @{}; Printers = @(); LocalShares = @(); CheckedHost = $false }
    $started = Get-Date
    Write-Out 'BÁO CÁO MÁY IN VÀ CHIA SẺ MẠNG' 'Cyan'
    Write-Out ('Máy {0}, {1:dd/MM/yyyy HH:mm}. Công cụ "Máy in mạng LAN" {2}: chỉ đọc, không thay đổi gì trên máy.' -f $env:COMPUTERNAME, $started, $script:ToolVersion)

    try { $script:Diag.LocalShares = @(Get-SmbShare -ErrorAction Stop | Where-Object { -not $_.Special }) } catch { }

    Invoke-Section 'Máy này' { Show-MachineSection }
    Invoke-Section 'Mạng' { Show-NetworkSection }
    Invoke-Section 'Dịch vụ Windows' { Show-ServiceSection }
    Invoke-Section 'Tường lửa' { Show-FirewallSection }
    Invoke-Section 'Chia sẻ SMB' { Show-SmbSection }
    Invoke-Section 'Máy in' { Show-PrinterSection }
    Invoke-Section 'Cài driver qua mạng, RPC' { Show-PointAndPrintSection }
    Invoke-Section 'Ổ mạng và mật khẩu đã lưu' { Show-MappingSection }
    Invoke-Section 'Máy này đang chia sẻ' { Show-LocalShareSection }
    if ($MayChu.Trim()) {
        $script:Diag.CheckedHost = $true
        Invoke-Section ('Kiểm tra máy ' + $MayChu.Trim()) { Show-RemoteHostSection $MayChu }
    }
    Invoke-Section 'Nhật ký sự kiện 7 ngày' { Show-EventSection }
    Show-Conclusion
    if (-not @($script:Findings | Where-Object { $_.Level -in 'bad', 'warn' }).Count) {
        # chỉ cho file kết quả: phần kết luận đã in dòng [OK]
        [void]$script:Findings.Add([pscustomobject]@{ Ma = 'KHONG_THAY_LOI'; Level = 'ok'; Text = 'Không thấy lỗi cấu hình nào về máy in và chia sẻ mạng.'; Fix = ''; Hint = 'Vẫn không in được: kiểm tra máy in (giấy, mực, đèn báo lỗi), dây mạng hoặc Wi-Fi của máy in.' })
    }

    $path = Join-Path (Get-ResultDir) ('BaoCao_MayIn_{0}_{1:yyyyMMdd_HHmmss}.txt' -f $env:COMPUTERNAME, $started)
    $code = 0
    try {
        [IO.File]::WriteAllLines($path, $script:Report, $script:Utf8Bom)
        Write-Host ''
        Write-Host "  Báo cáo đã lưu: $path" -ForegroundColor Green
    } catch {
        Write-Host "  Không lưu được báo cáo: $($_.Exception.Message)" -ForegroundColor Red
        $path = ''; $code = 1
    }
    $files = @(if ($path) { [ordered]@{ nhan = 'Báo cáo chẩn đoán'; duongDan = $path } })
    [void](Save-RunResult -CheDo 'chan-doan' -Code $code -Start $started -Files $files -Message $(if ($code) { 'Không lưu được báo cáo chẩn đoán.' } else { '' }))
    return $code
}

# ---------------------------------------------------------------- các phần của báo cáo
function Show-MachineSection {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $product = [string]$cv.ProductName
    if ([int]$cv.CurrentBuild -ge 22000) { $product = $product -replace 'Windows 10', 'Windows 11' }
    Write-Line ('Windows: {0} {1}, build {2}.{3}' -f $product, $cv.DisplayVersion, $cv.CurrentBuild, $cv.UBR)
    $cs = Get-CimInstance Win32_ComputerSystem
    Write-Line ('Tên máy: {0}, {1} {2}' -f $env:COMPUTERNAME, $(if ($cs.PartOfDomain) { 'domain' } else { 'workgroup' }), $cs.Domain)
    $me = Get-CurrentUser
    Write-Line ('Chạy bằng: {0} ({1})' -f $me, $(if ($script:Diag.Admin) { 'quyền Admin' } else { 'không có quyền Admin' }))
    $console = [string]$cs.UserName
    if ($console -and $console -ne $me) {
        Add-Finding -Ma 'TAI_KHOAN_KHAC' warn "Đang chạy bằng tài khoản khác người đang dùng máy ($console): ổ mạng, máy in riêng của người đó có thể không hiện trong báo cáo."
    }
    if (-not $script:Diag.Admin) {
        Write-Info 'Không có quyền Admin nên bỏ qua thư mục hàng đợi in và nhật ký SMB. Chạy từ Trạm Tool (hoặc chọn "Có" ở hộp UAC) để xem đủ.'
    }
}

function Show-NetworkSection {
    $profiles = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue)
    $script:Diag.Profiles = $profiles
    if (-not $profiles) { Add-Finding -Ma 'KHONG_CO_MANG' bad 'Máy không kết nối mạng nào.' -Hint 'Kiểm tra dây mạng, Wi-Fi.'; return }
    $catText = @{ Public = 'Public (công cộng)'; Private = 'Private (riêng tư)'; DomainAuthenticated = 'Domain' }
    foreach ($np in $profiles) {
        $ipc = Get-NetIPConfiguration -InterfaceIndex $np.InterfaceIndex -ErrorAction SilentlyContinue
        $ips = @($ipc.IPv4Address | Where-Object { $_ } | ForEach-Object { '{0}/{1}' -f $_.IPAddress, $_.PrefixLength })
        $gw = @($ipc.IPv4DefaultGateway | Where-Object { $_ } | ForEach-Object { $_.NextHop })
        Write-Line ("{0}: mạng '{1}', {2}, IP {3}{4}" -f $np.InterfaceAlias, $np.Name, $catText[[string]$np.NetworkCategory], $(if ($ips) { $ips -join ', ' } else { 'chưa có' }), $(if ($gw) { ', router ' + ($gw -join ', ') } else { '' }))
        if ([string]$np.NetworkCategory -eq 'Public') {
            Add-Finding -Ma 'MANG_PUBLIC' warn ("Mạng '{0}' ({1}) đang để Public: Windows ẩn máy này và chặn chia sẻ thư mục, máy in." -f $np.Name, $np.InterfaceAlias) -Fix 'bat-chia-se' -Hint 'Chỉ đổi sang Private khi đây là mạng ở văn phòng hoặc nhà mà bạn tin cậy.'
        }
        if ($ips | Where-Object { $_ -like '169.254.*' }) {
            Add-Finding -Ma 'KHONG_NHAN_IP' bad ("{0} không nhận được IP từ router (169.254.x.x): máy coi như mất mạng nội bộ." -f $np.InterfaceAlias) -Hint 'Khởi động lại router hoặc dùng công cụ "Kiểm tra và sửa lỗi Wi-Fi".'
        }
    }
    $aliases = @($profiles | ForEach-Object { $_.InterfaceAlias })
    foreach ($b in @(Get-NetAdapterBinding -ComponentID ms_msclient, ms_server -ErrorAction SilentlyContinue | Where-Object { $_.Name -in $aliases -and -not $_.Enabled })) {
        if ($b.ComponentID -eq 'ms_msclient') {
            Add-Finding -Ma 'CARD_TAT_CLIENT' bad ("Card {0} đang tắt '{1}': máy này không vào được thư mục, máy in chia sẻ." -f $b.Name, $b.DisplayName) -Fix 'bat-chia-se'
        } else {
            Add-Finding -Ma 'CARD_TAT_SERVER' warn ("Card {0} đang tắt '{1}': máy khác không vào được thư mục, máy in chia sẻ trên máy này." -f $b.Name, $b.DisplayName) -Fix 'bat-chia-se'
        }
    }
}

function Show-ServiceSection {
    $defs = @(
        @{ Name = 'Spooler'; Role = 'Cần để in' }
        @{ Name = 'LanmanWorkstation'; Role = 'Cần để vào thư mục, máy in chia sẻ của máy khác' }
        @{ Name = 'LanmanServer'; Role = 'Cần để chia sẻ thư mục, máy in của máy này' }
        @{ Name = 'FDResPub'; Role = 'Cho máy khác thấy máy này trong mục Network' }
        @{ Name = 'fdPHost'; Role = 'Tìm máy khác trong mạng' }
        @{ Name = 'SSDPSRV'; Role = 'Tìm thiết bị trong mạng (SSDP)' }
        @{ Name = 'upnphost'; Role = 'Dùng kèm phát hiện mạng (UPnP)' }
        @{ Name = 'lmhosts'; Role = 'Tìm máy theo tên NetBIOS' }
        @{ Name = 'MpsSvc'; Role = 'Tường lửa, phải bật khi chia sẻ máy in' }
    )
    $st = @{}
    foreach ($d in $defs) {
        $s = Get-ServiceState $d.Name
        $st[$d.Name] = $s
        Write-Line ('{0} ({1}): {2}. {3}.' -f $(if ($s) { $s.DisplayName } else { $d.Name }), $d.Name, (Format-ServiceState $s), $d.Role)
    }
    $script:Diag.Services = $st
    $sp = $st['Spooler']
    if (-not $sp -or $sp.StartMode -eq 'Disabled') { Add-Finding -Ma 'SPOOLER_VO_HIEU' bad 'Dịch vụ in (Print Spooler) bị vô hiệu hoá: không in được, không thêm được máy in.' -Fix 'sua-hang-doi' }
    elseif (-not $sp.Running) { Add-Finding -Ma 'SPOOLER_DUNG' bad 'Dịch vụ in (Print Spooler) đang dừng: không in được.' -Fix 'sua-hang-doi' }
    if ($st['LanmanWorkstation'] -and -not $st['LanmanWorkstation'].Running) {
        Add-Finding -Ma 'WORKSTATION_DUNG' bad 'Dịch vụ Workstation đang dừng: máy này không vào được thư mục, máy in chia sẻ.' -Fix 'bat-chia-se'
    }
    if ($st['LanmanServer'] -and -not $st['LanmanServer'].Running) {
        Add-Finding -Ma 'SERVER_DUNG' warn 'Dịch vụ Server đang dừng: máy khác không vào được thư mục, máy in chia sẻ trên máy này.' -Fix 'bat-chia-se'
    }
    if ($st['FDResPub'] -and -not $st['FDResPub'].Running) {
        Add-Finding -Ma 'MAY_NAY_AN_TRONG_NETWORK' info 'Máy khác không thấy máy này trong mục Network (vẫn vào được bằng \\tên-máy hoặc \\IP).' -Fix 'bat-chia-se'
    }
    foreach ($n in 'fdPHost', 'SSDPSRV', 'upnphost') {
        if ($st[$n] -and $st[$n].StartMode -eq 'Disabled') { Add-Finding -Ma 'DICH_VU_TIM_MANG_TAT' warn "Dịch vụ $($st[$n].DisplayName) bị vô hiệu hoá: mục Network không hiện đủ máy, máy in." -Fix 'bat-chia-se' }
    }
    if ($st['MpsSvc'] -and -not $st['MpsSvc'].Running) {
        Add-Finding -Ma 'TUONG_LUA_TAT' warn 'Tường lửa Windows đang tắt: máy khác kết nối máy in chia sẻ từ máy này sẽ báo lỗi 0x000006D9.' -Hint 'Bật lại trong Windows Security > Firewall & network protection. Chia sẻ không cần tắt tường lửa.'
    }
}

function Show-FirewallSection {
    $cats = @($script:Diag.Profiles | ForEach-Object { @{ Public = 'Public'; Private = 'Private'; DomainAuthenticated = 'Domain' }[[string]$_.NetworkCategory] } | Select-Object -Unique)
    if (-not $cats) { Write-Info 'Không có mạng nào đang kết nối.'; return }
    foreach ($fp in @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)) {
        if (-not $fp.Enabled -and $fp.Name -in $cats) { Write-Info "Tường lửa đang tắt cho mạng $($fp.Name)." }
    }
    $sharing = [bool]($script:Diag.LocalShares -or @(Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Shared }))
    $groups = @(
        @{ Id = '@FirewallAPI.dll,-28502'; Name = 'Chia sẻ file và máy in'; Off = 'máy khác không vào được thư mục, máy in chia sẻ trên máy này' }
        @{ Id = '@FirewallAPI.dll,-32752'; Name = 'Phát hiện mạng'; Off = 'mục Network không hiện máy khác, máy khác không thấy máy này' }
    )
    foreach ($g in $groups) {
        $rules = @(Get-NetFirewallRule -Group $g.Id -Direction Inbound -ErrorAction SilentlyContinue)
        if (-not $rules) { Write-Info "Không thấy nhóm quy tắc '$($g.Name)'."; continue }
        foreach ($cat in $cats) {
            $mask = @{ Domain = 1; Private = 2; Public = 4 }[$cat]
            $applies = @($rules | Where-Object { $pr = [int]$_.Profile; $pr -eq 0 -or ($pr -band $mask) })
            $on = @($applies | Where-Object { [string]$_.Enabled -eq 'True' })
            Write-Line ("{0}, mạng {1}: bật {2}/{3} quy tắc nhận kết nối vào." -f $g.Name, $cat, $on.Count, $applies.Count)
            if ($cat -eq 'Public') {
                if ($g.Id -eq '@FirewallAPI.dll,-28502' -and $on.Count) {
                    Add-Finding -Ma 'CHIA_SE_MO_TREN_PUBLIC' warn 'Chia sẻ file và máy in đang mở cả trên mạng Public: nguy hiểm khi dùng Wi-Fi công cộng.' -Hint 'Tắt ở Settings > Network & internet > Advanced network settings > Advanced sharing settings > Public networks.'
                }
            } elseif (-not $on.Count) {
                $level = if ($g.Id -eq '@FirewallAPI.dll,-28502' -and -not $sharing) { 'info' } else { 'warn' }
                $text = "Tường lửa chặn '{0}' trên mạng {1}: {2}." -f $g.Name, $cat, $g.Off
                if ($g.Id -eq '@FirewallAPI.dll,-28502') { Add-Finding -Ma 'TUONG_LUA_CHAN_CHIA_SE' $level $text -Fix 'bat-chia-se' }
                else { Add-Finding -Ma 'TUONG_LUA_CHAN_PHAT_HIEN' $level $text -Fix 'bat-chia-se' }
            }
        }
    }
}

function Show-SmbSection {
    $cli = Get-SmbClientConfiguration -ErrorAction Stop
    Write-Line ('Khi vào máy khác: bắt buộc ký SMB = {0}, cho đăng nhập khách = {1}' -f (Format-YesNo $cli.RequireSecuritySignature), (Format-YesNo $cli.EnableInsecureGuestLogons))
    $pol = Get-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation' 'AllowInsecureGuestAuth'
    if ($null -ne $pol) { Write-Line ('Chính sách nhóm AllowInsecureGuestAuth = {0} (ghi đè cấu hình trên).' -f $pol) }
    if ($cli.RequireSecuritySignature) {
        Write-Info 'Windows bắt buộc ký SMB: NAS, ổ cứng cắm router, máy in đời cũ không hỗ trợ ký sẽ báo "The cryptographic signature is invalid" (0xC000A000).'
    }
    if (-not $cli.EnableInsecureGuestLogons -or $pol -eq 0) {
        Write-Info 'Windows chặn đăng nhập khách: NAS, máy chia sẻ không mật khẩu sẽ báo lỗi 1272 hoặc 0x80070035. Nên vào bằng tài khoản có mật khẩu.'
    } elseif ($cli.RequireSecuritySignature) {
        Write-Info 'Cho đăng nhập khách nhưng vẫn bắt buộc ký SMB: vào thư mục không mật khẩu vẫn bị từ chối, vì khách không ký được.'
    }
    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10') {
        Add-Finding -Ma 'SMB1_DA_CAI' warn 'Máy đang cài SMB1 (giao thức cũ, mã độc tống tiền lây qua nó).' -Hint 'Gỡ ở Turn Windows features on or off > SMB 1.0/CIFS khi không còn thiết bị nào bắt buộc SMB1.'
    } else {
        Write-Line 'SMB1: chưa cài (đúng khuyến nghị). Thiết bị chỉ hỗ trợ SMB1 cần cập nhật firmware, không bật lại SMB1.'
    }
    $srv = Get-SmbServerConfiguration -ErrorAction Stop
    Write-Line ('Khi máy khác vào máy này: bắt buộc ký SMB = {0}, SMB1 = {1}' -f (Format-YesNo $srv.RequireSecuritySignature), (Format-YesNo $srv.EnableSMB1Protocol))
    if ($srv.EnableSMB1Protocol) { Add-Finding -Ma 'SMB1_MAY_NAY_NHAN' warn 'Máy này đang nhận kết nối SMB1.' -Hint 'Tắt bằng PowerShell Admin: Set-SmbServerConfiguration -EnableSMB1Protocol $false' }
    if ($srv.RequireSecuritySignature -and $script:Diag.LocalShares) {
        Write-Info 'Máy này bắt buộc ký SMB: máy photocopy quét vào thư mục (scan to folder) đời cũ có thể không ghi được vào thư mục chia sẻ trên máy này.'
    }
}

function Show-PrinterSection {
    $sp = $script:Diag.Services['Spooler']
    if (-not $sp -or -not $sp.Running) { Write-Warn 'Print Spooler không chạy nên không đọc được danh sách máy in.'; return }
    $printers = @(Get-PrinterList)
    $script:Diag.Printers = $printers
    $names = @($printers | ForEach-Object { $_.Name })
    $real = @($printers | Where-Object { $_.Kind -ne 'ao' })

    # Thử kết nối các máy in mạng và máy chia sẻ, mỗi địa chỉ một lượt (các cổng thử song song).
    $reach = @{}
    $need = @{}
    foreach ($p in $real) {
        $port = switch ($p.Kind) { 'tcp' { $p.PortNumber } 'lpr' { 515 } 'ipp' { 631 } 'connection' { 445 } default { 0 } }
        if ($port -and $p.Address) { if (-not $need[$p.Address]) { $need[$p.Address] = @() }; $need[$p.Address] += $port }
    }
    foreach ($addr in @($need.Keys)) {
        $ip = $null
        try { $ip = @(Resolve-HostAddress $addr)[0] } catch { }
        if (-not $ip) { foreach ($port in $need[$addr]) { $reach["$addr|$port"] = 'noname' }; continue }
        $r = Test-TcpPorts -Address $ip -Ports ($need[$addr] | Select-Object -Unique)
        foreach ($port in $need[$addr]) { $reach["$addr|$port"] = $r[$port] }
    }

    $copies = @()
    $jobsAll = 0
    foreach ($p in $printers) {
        $mark = if ($p.Default) { ' (mặc định)' } else { '' }
        $share = if ($p.Shared) { "; chia sẻ là \\$env:COMPUTERNAME\$($p.ShareName)" } else { '' }
        Write-Line ('- {0}{1}: {2}; {3}; driver {4}{5}' -f $p.Name, $mark, (Get-PrinterStatusText $p.Status), (Get-PrinterKindText $p), $p.DriverName, $share)
        if ($p.Kind -eq 'ao') { continue }

        $port = switch ($p.Kind) { 'tcp' { $p.PortNumber } 'lpr' { 515 } 'ipp' { 631 } 'connection' { 445 } default { 0 } }
        $state = if ($port) { $reach["$($p.Address)|$port"] } else { $null }
        if ($state -eq 'open') { Write-Sub 'Kết nối tới máy in: được.' }
        elseif ($state -and $p.Kind -eq 'connection') {
            Add-Finding -Ma 'MAY_IN_KHONG_VAO_MAY_CHIA_SE' bad ("Máy in '{0}': không vào được máy chia sẻ {1} ({2})." -f $p.Name, $p.Address, $(if ($state -eq 'noname') { 'không tìm thấy tên máy' } else { 'cổng 445 ' + $script:PortStateText[$state] })) -Hint 'Máy đó phải đang bật, cùng mạng; trên máy đó chạy "Bật chia sẻ file và máy in".'
        } elseif ($state -eq 'closed') {
            Add-Finding -Ma 'MAY_IN_CONG_DONG' warn ("Máy in '{0}': {1} có trả lời nhưng cổng {2} đóng, IP có thể đã thuộc thiết bị khác." -f $p.Name, $p.Address, $port) -Fix 'them-may-in-ip' -Hint 'Xem IP trên màn hình máy in hoặc in trang cấu hình mạng, rồi thêm lại bằng IP đó.'
        } elseif ($state) {
            Add-Finding -Ma 'MAY_IN_KHONG_KET_NOI' bad ("Máy in '{0}': không kết nối được {1}:{2} (máy in tắt, đã đổi IP, hoặc khác mạng)." -f $p.Name, $p.Address, $port) -Fix 'them-may-in-ip' -Hint 'Xem IP trên màn hình máy in hoặc in trang cấu hình mạng, rồi thêm lại bằng IP đó.'
        }

        if (-not ($p.Kind -eq 'connection' -and $state -ne 'open')) {
            $jobs = @(Get-PrintJobsSafe $p.Name)
            $jobsAll += $jobs.Count
            if ($jobs.Count) {
                $old = @($jobs | Where-Object { $_.SubmittedTime -and $_.SubmittedTime -lt (Get-Date).AddMinutes(-30) })
                $err = @($jobs | Where-Object { [string]$_.JobStatus -match 'Error|Deleting|Blocked|Offline|PaperOut|UserIntervention' })
                Write-Sub ('Hàng đợi: {0} lệnh in{1}{2}.' -f $jobs.Count, $(if ($err) { ", $($err.Count) lệnh báo lỗi" } else { '' }), $(if ($old) { ", $($old.Count) lệnh chờ quá 30 phút" } else { '' }))
                if ($err -or $old) { Add-Finding -Ma 'LENH_IN_KET' warn ("Máy in '{0}' có lệnh in bị kẹt." -f $p.Name) -Fix 'sua-hang-doi' }
            }
        }
        if (Get-CopyBaseName $p.Name $names) { $copies += $p.Name }
        if ($p.WorkOffline) { Add-Finding -Ma 'MAY_IN_NGOAI_TUYEN' warn ("Máy in '{0}' đang bật 'Dùng máy in ngoại tuyến' (Use Printer Offline): lệnh in chỉ nằm chờ." -f $p.Name) -Fix 'sua-hang-doi' }
        $flags = @(($p.Status -split ',\s*') | Where-Object { $_ -in $script:PrinterBadStatus })
        if ($flags -contains 'Paused') { Add-Finding -Ma 'MAY_IN_TAM_DUNG' warn ("Máy in '{0}' đang tạm dừng (Pause)." -f $p.Name) -Fix 'sua-hang-doi' }
        elseif ($flags) { Add-Finding -Ma 'MAY_IN_BAO_LOI' warn ("Máy in '{0}' báo: {1}." -f $p.Name, (Get-PrinterStatusText $p.Status)) -Hint 'Kiểm tra giấy, mực, nắp và đèn báo trên máy in.' }
        if ($p.Kind -eq 'wsd') {
            Add-Finding -Ma 'MAY_IN_CONG_WSD' info ("Máy in '{0}' dùng cổng WSD (tự dò): hay mất kết nối khi máy in đổi IP hoặc ngủ." -f $p.Name) -Fix 'them-may-in-ip' -Hint 'Nên đặt IP cố định cho máy in rồi thêm lại bằng IP.'
        }
        if ($p.Snmp -and $p.Status -match 'Offline') {
            Add-Finding -Ma 'MAY_IN_SNMP_OFFLINE' info ("Máy in '{0}' báo Offline và cổng đang bật SNMP: máy in không trả lời SNMP thì Windows báo Offline dù vẫn in được." -f $p.Name) -Hint 'Thuộc tính máy in > Ports > Configure Port > bỏ chọn "SNMP Status Enabled".'
        }
    }
    if ($copies) { Add-Finding -Ma 'MAY_IN_TRUNG' warn ('Có {0} máy in trùng: {1}.' -f $copies.Count, ($copies -join '; ')) -Fix 'xoa-may-in-trung' }
    if (-not $real) { Write-Info 'Chưa có máy in thật nào, chỉ có máy in ảo (Microsoft Print to PDF...).' }
    elseif ($real.Count -ge 2 -and (Get-RegValue 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' 'LegacyDefaultPrinterMode') -ne 1) {
        Write-Info 'Windows tự đổi máy in mặc định theo máy in dùng gần nhất. Tắt ở Settings > Printers & scanners > "Let Windows manage my default printer".'
    }

    $spool = Get-SpoolDirectory
    try {
        $files = @(Get-ChildItem -LiteralPath $spool -File -ErrorAction Stop)
        $mb = ($files | Measure-Object Length -Sum).Sum / 1MB
        Write-Line ('Thư mục hàng đợi {0}: {1} file ({2:N1} MB).' -f $spool, $files.Count, $mb)
        if ($files.Count -and -not $jobsAll) { Add-Finding -Ma 'HANG_DOI_FILE_SOT' warn ('Thư mục hàng đợi còn {0} file sót dù không có lệnh in nào.' -f $files.Count) -Fix 'sua-hang-doi' }
    } catch { Write-Info 'Không xem được thư mục hàng đợi in (cần quyền Admin).' }

    $drivers = @(Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $script:VirtualDrivers } | ForEach-Object { '{0} (v{1})' -f $_.Name, $_.MajorVersion } | Select-Object -Unique)
    Write-Line ('Driver máy in đã cài: {0}' -f $(if ($drivers) { $drivers -join '; ' } else { 'chưa có driver hãng nào' }))
}

function Show-PointAndPrintSection {
    $pp = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint'
    $restrict = Get-RegValue $pp 'RestrictDriverInstallationToAdministrators'
    if ($restrict -eq 0) {
        Add-Finding -Ma 'CAI_DRIVER_KHONG_CAN_ADMIN' warn 'Đã tắt yêu cầu quyền Admin khi cài driver máy in qua mạng (RestrictDriverInstallationToAdministrators = 0): mở lại lỗ hổng PrintNightmare.' -Hint 'Xoá giá trị này (registry hoặc Group Policy) khi không còn cần.'
    } else {
        Write-Line 'Cài driver khi kết nối máy in chia sẻ: chỉ Admin được cài (mặc định an toàn từ 2021).'
        Write-Sub 'Người dùng thường hay gặp lỗi 0x00000BCB hoặc hộp hỏi mật khẩu Admin: dùng "Kết nối máy in chia sẻ" của công cụ (chạy quyền Admin).'
    }
    $rpc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\RPC'
    if ((Get-RegValue $rpc 'RpcUseNamedPipeProtocol') -eq 1) {
        Add-Finding -Ma 'DANG_NOI_RPC_NAMED_PIPE' info 'Đang nới: kết nối máy in chia sẻ dùng RPC qua named pipe (RpcUseNamedPipeProtocol = 1).' -Hint 'Chỉ cần khi máy chia sẻ là Windows cũ. Bỏ bằng "Hoàn tác" khi không còn cần.'
    } else {
        Write-Line 'Kết nối máy in chia sẻ: RPC qua TCP (mặc định từ Windows 11 22H2).'
    }
    foreach ($n in 'RpcProtocols', 'RpcAuthentication', 'ForceKerberosForRpc', 'RpcTcpPort') {
        $v = Get-RegValue $rpc $n
        if ($null -ne $v) { Write-Sub "Chính sách $n = $v" }
    }
    if ((Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Print' 'RpcAuthnLevelPrivacyEnabled') -eq 0) {
        Add-Finding -Ma 'DANG_TAT_MA_HOA_RPC' info 'Đang nới: tắt mã hoá RPC khi máy khác in qua máy này (RpcAuthnLevelPrivacyEnabled = 0, cách tạm cho lỗi 0x0000011B).' -Hint 'Bỏ bằng "Hoàn tác" khi các máy khác đã cập nhật Windows.'
    } else {
        Write-Line 'Mã hoá RPC khi máy khác in qua máy này: bật (mặc định).'
    }
}

function Show-MappingSection {
    $maps = @(Get-MappedDrives)
    $live = @{}
    try { foreach ($m in @(Get-SmbMapping -ErrorAction Stop)) { $live[([string]$m.LocalPath).ToUpperInvariant()] = [string]$m.Status } } catch { }
    if ($maps) {
        $hostState = @{}
        foreach ($m in $maps) {
            $u = Split-UncPath $m.Remote
            if (-not $u -or $hostState.ContainsKey($u.Host)) { continue }
            $hostState[$u.Host] = 'noname'
            try { $ip = @(Resolve-HostAddress $u.Host)[0]; if ($ip) { $hostState[$u.Host] = (Test-TcpPorts -Address $ip -Ports 445)[445] } } catch { }
        }
        foreach ($m in $maps) {
            $u = Split-UncPath $m.Remote
            $st = if ($u) { $hostState[$u.Host] } else { '' }
            $extra = @()
            if ($m.User) { $extra += "tài khoản $($m.User)" }
            if ($live[$m.Letter]) { $extra += "trạng thái $($live[$m.Letter])" }
            Write-Line ('{0} → {1}{2}' -f $m.Letter, $m.Remote, $(if ($extra) { ' (' + ($extra -join ', ') + ')' } else { '' }))
            if ($st -and $st -ne 'open') {
                Add-Finding -Ma 'O_MANG_KHONG_VAO_DUOC' warn ("Ổ {0}: không vào được máy {1} ({2})." -f $m.Letter, $u.Host, $(if ($st -eq 'noname') { 'không tìm thấy tên máy' } else { 'cổng 445 ' + $script:PortStateText[$st] })) -Hint 'Máy đó phải đang bật và cùng mạng. Tên máy không tìm được thì gắn lại ổ bằng IP.'
            }
        }
        foreach ($grp in @($maps | Where-Object { $_.User } | Group-Object { $h = Split-UncPath $_.Remote; if ($h) { $h.Host.ToUpperInvariant() } else { '' } })) {
            $users = @($grp.Group | ForEach-Object { $_.User.ToLowerInvariant() } | Select-Object -Unique)
            if ($grp.Name -and $users.Count -gt 1) {
                Add-Finding -Ma 'O_MANG_NHIEU_TAI_KHOAN' warn ("Các ổ mạng tới máy {0} dùng {1} tài khoản khác nhau: Windows sẽ báo lỗi 1219." -f $grp.Name, $users.Count) -Hint 'Dùng một tài khoản cho mỗi máy, hoặc gắn ổ bằng IP cho tài khoản thứ hai.'
            }
        }
    } else {
        Write-Line 'Chưa có ổ mạng nào (dạng Z: → \\máy\thư-mục).'
    }
    if ($script:Diag.Admin -and (Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLinkedConnections') -ne 1) {
        Write-Info 'Đang chạy quyền Admin: phiên Admin không thấy ổ mạng của phiên thường; danh sách trên đọc từ cấu hình người dùng.'
    }
    $creds = @(Get-SavedNetworkCredentials | Where-Object { $_.Target -match '^[\p{L}\p{N}*][\p{L}\p{N}._*-]*$' })
    Write-Line ('Mật khẩu mạng đã lưu trong Windows: {0} (chỉ đọc tên máy và tài khoản, không đọc mật khẩu).' -f $creds.Count)
    foreach ($c in $creds) { Write-Sub ('{0}: tài khoản {1}' -f $c.Target, $c.User) }
}

function Show-LocalShareSection {
    $shares = @($script:Diag.LocalShares)
    $printers = @($script:Diag.Printers | Where-Object { $_.Shared })
    if (-not $shares -and -not $printers) { Write-Line 'Máy này không chia sẻ thư mục hay máy in nào.'; return }
    foreach ($s in $shares) { Write-Line ('Thư mục: \\{0}\{1} → {2}' -f $env:COMPUTERNAME, $s.Name, $s.Path) }
    foreach ($p in $printers) { Write-Line ('Máy in: \\{0}\{1} ({2})' -f $env:COMPUTERNAME, $p.ShareName, $p.Name) }
    $ips = @()
    foreach ($np in $script:Diag.Profiles) {
        $ipc = Get-NetIPConfiguration -InterfaceIndex $np.InterfaceIndex -ErrorAction SilentlyContinue
        $ips += @($ipc.IPv4Address | Where-Object { $_ -and $_.IPAddress -notlike '169.254.*' } | ForEach-Object { '\\' + $_.IPAddress })
    }
    Write-Sub ('Máy khác vào bằng: \\{0}{1}' -f $env:COMPUTERNAME, $(if ($ips) { ' hoặc ' + ($ips -join ', ') } else { '' }))
}

function Show-RemoteHostSection {
    param([string]$Name)
    $hostName = $Name.Trim()
    if ($hostName -like '\\*') {
        $u = Split-UncPath $hostName
        $hostName = if ($u) { $u.Host } else { $hostName.TrimStart('\').Split('\')[0] }
    }
    $addrs = $null
    try { $addrs = @(Resolve-HostAddress $hostName) } catch { }
    if (-not $addrs) {
        Add-Finding -Ma 'MAY_KHONG_TIM_THAY' bad "Không tìm thấy máy '$hostName' trong mạng." -Hint 'Kiểm tra lại tên. Tên máy không tìm được thì dùng địa chỉ IP của máy đó.'
        return
    }
    $ip = $addrs[0]
    Write-Line ('Địa chỉ: {0}' -f (($addrs | Select-Object -First 4) -join ', '))
    Write-Line ('Ping: {0}' -f $(if (Test-Ping $ip) { 'có trả lời' } else { 'không trả lời (bình thường nếu tường lửa máy đó chặn ping)' }))
    $portList = 445, 139, 135, 9100, 631, 515, 80, 443
    $ports = Test-TcpPorts -Address $ip -Ports $portList
    foreach ($port in $portList) { Write-Sub ('Cổng {0}, {1}: {2}' -f $port, $script:PortRole[$port], $script:PortStateText[$ports[$port]]) }
    $isPrinter = $ports[9100] -eq 'open' -or $ports[631] -eq 'open' -or $ports[515] -eq 'open'

    if ($ports[445] -eq 'open') {
        $sl = Get-ShareList $hostName
        if ($sl.Code -eq 0) {
            Write-Ok "Vào được máy $hostName."
            if ($sl.Shares) {
                foreach ($s in $sl.Shares) {
                    Write-Sub ('{0} \\{1}\{2}{3}' -f $(if ($s.Kind -eq 'may-in') { 'Máy in: ' } else { 'Thư mục:' }), $hostName, $s.Name, $(if ($s.Remark) { "  ($($s.Remark))" } else { '' }))
                }
            } else { Write-Info "Máy $hostName không chia sẻ thư mục hay máy in nào mà tài khoản này thấy được." }
            if (@($sl.Shares | Where-Object { $_.Kind -eq 'may-in' }) -and $ports[135] -ne 'open') {
                Add-Finding -Ma 'MAY_CHU_RPC_DONG' warn "Máy $hostName chia sẻ máy in nhưng cổng 135 (RPC) không mở: kết nối máy in sẽ lỗi." -Hint 'Trên máy đó chạy "Bật chia sẻ file và máy in".'
            }
        } else {
            $h = $script:ErrorHelp[[string]$sl.Code]
            $what = if ($h) { (Get-ErrorMeaning $sl.Code).TrimEnd('.') } else { 'Windows báo lỗi' }
            Add-Finding -Ma 'MAY_CHU_TU_CHOI' bad ('Không vào được máy {0}: {1} (lỗi {2}).' -f $hostName, $what, (Format-ErrorCode $sl.Code)) -Fix (Get-FixForCode $sl.Code) -Hint $(if ($h) { $h[1] } else { '' })
        }
    } elseif ($ports[139] -eq 'open') {
        Add-Finding -Ma 'MAY_CHU_CHI_SMB1' warn "Máy $hostName chỉ mở cổng 139, không mở 445: thiết bị rất cũ, có thể chỉ hỗ trợ SMB1." -Hint 'Không bật SMB1. Cập nhật firmware thiết bị hoặc chép file bằng cách khác.'
    } elseif (-not $isPrinter -and ($ports[80] -eq 'open' -or $ports[443] -eq 'open')) {
        Add-Finding -Ma 'MAY_CHU_CHI_WEB' warn "$hostName chỉ mở trang quản trị web (cổng 80/443), không chia sẻ thư mục và không nhận lệnh in: có thể là router, camera, hoặc máy in chưa bật in qua mạng." -Hint ('Mở http://{0} trong trình duyệt để xem đó là thiết bị gì. Máy in: bật in qua mạng (RAW 9100 hoặc IPP) trong trang đó. Máy tính: chạy "Bật chia sẻ file và máy in" trên máy đó.' -f $ip)
    } elseif (-not $isPrinter) {
        $why = switch ($ports[445]) {
            'closed' { 'máy có trả lời nhưng cổng 445 đóng (chưa bật chia sẻ, dịch vụ Server tắt)' }
            'unreachable' { 'khác mạng với máy này' }
            default { 'cổng 445 không phản hồi (máy tắt, tường lửa chặn, hoặc mạng Public trên máy đó)' }
        }
        Add-Finding -Ma 'MAY_CHU_KHONG_VAO_DUOC' bad "Không vào được thư mục, máy in chia sẻ trên $hostName`: $why." -Hint 'Trên máy đó chạy "Bật chia sẻ file và máy in" của công cụ này.'
    }
    if ($isPrinter) {
        $how = if ($ports[631] -eq 'open') { 'IPP, không cần driver hãng' } elseif ($ports[9100] -eq 'open') { 'cổng 9100, cần driver hãng' } else { 'LPR' }
        Add-Finding -Ma 'MAY_IN_MANG' info "$hostName là máy in mạng (in được qua $how)." -Fix 'them-may-in-ip' -Hint "Thêm bằng địa chỉ $ip."
    }
}

function Show-EventSection {
    $since = (Get-Date).AddDays(-7)
    foreach ($log in 'Microsoft-Windows-SMBClient/Security', 'Microsoft-Windows-SMBClient/Connectivity', 'Microsoft-Windows-PrintService/Admin') {
        $info = $null
        try { $info = Get-WinEvent -ListLog $log -ErrorAction Stop } catch { Write-Info "${log}: không đọc được (cần quyền Admin)."; continue }
        if (-not $info.IsEnabled) { Write-Info "${log}: đang tắt."; continue }
        $events = @()
        try { $events = @(Get-WinEvent -FilterHashtable @{ LogName = $log; Level = 1, 2, 3; StartTime = $since } -MaxEvents 6 -ErrorAction Stop) }
        catch { if ([string]$_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { Write-Info "${log}: $($_.Exception.Message.Trim())"; continue } }
        Write-Line ('{0}: {1}' -f $log, $(if ($events) { "$($events.Count) cảnh báo/lỗi gần nhất" } else { 'không có cảnh báo, lỗi' }))
        foreach ($e in $events) {
            $msg = (([string]$e.Message) -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
            if (-not $msg) { $msg = '(không có nội dung)' }
            if ($msg.Length -gt 150) { $msg = $msg.Substring(0, 150) + '...' }
            Write-Sub ('{0:dd/MM HH:mm} [{1}] {2}' -f $e.TimeCreated, $e.Id, $msg)
        }
        if ($log -eq 'Microsoft-Windows-SMBClient/Security') {
            $guest = $null
            try { $guest = Get-WinEvent -FilterHashtable @{ LogName = $log; Id = 31017; StartTime = $since } -MaxEvents 1 -ErrorAction Stop } catch { }
            if ($guest) {
                Add-Finding -Ma 'CHAN_DANG_NHAP_KHACH' warn 'Windows đã chặn đăng nhập khách vào thư mục chia sẻ (sự kiện 31017).' -Fix 'noi-bao-mat' -Hint 'Cách an toàn: vào bằng tài khoản có mật khẩu của máy/NAS chia sẻ ("Kết nối thư mục chia sẻ" có ô Tài khoản).'
            }
        }
    }
}

function Show-Conclusion {
    Write-Head 'KẾT LUẬN'
    $rank = @{ bad = 0; warn = 1; info = 2 }
    $all = @($script:Findings)
    $ordered = @(for ($i = 0; $i -lt $all.Count; $i++) { [pscustomobject]@{ Key = $rank[$all[$i].Level] * 1000 + $i; F = $all[$i] } }) | Sort-Object Key | ForEach-Object { $_.F }
    $show = @($ordered | Where-Object { $_.Level -ne 'info' -or $_.Fix })
    $nBad = @($all | Where-Object { $_.Level -eq 'bad' }).Count
    $nWarn = @($all | Where-Object { $_.Level -eq 'warn' }).Count
    if (-not $show) {
        Write-Ok 'Không thấy lỗi cấu hình nào về máy in và chia sẻ mạng.'
        Write-Sub 'Vẫn không in được: kiểm tra máy in (giấy, mực, đèn báo lỗi), dây mạng hoặc Wi-Fi của máy in.'
    } else {
        Write-Line ('{0} lỗi, {1} cảnh báo. Nên xử lý theo thứ tự:' -f $nBad, $nWarn)
        foreach ($f in $show) {
            switch ($f.Level) { 'bad' { Write-Bad $f.Text } 'warn' { Write-Warn $f.Text } default { Write-Info $f.Text } }
            if ($f.Fix -and $script:Modes.Contains($f.Fix)) {
                $m = $script:Modes[$f.Fix]
                Write-Sub ('→ Chạy "{0}" (trong Trạm Tool, hoặc MAY_IN_LAN.bat mục {1}).' -f $m.Label, $m.No)
            } elseif ($f.Hint) { Write-Sub ('→ ' + $f.Hint) }
        }
    }
    if (-not $script:Diag.CheckedHost) {
        Write-Info 'Muốn kiểm tra một máy cụ thể (máy chia sẻ, máy in, NAS): chạy lại Chẩn đoán và nhập tên hoặc IP máy đó.'
    }
}
