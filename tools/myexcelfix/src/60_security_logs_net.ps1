
# ----------------------------------------------------------------------------
Section '9. PHẦN MỀM DIỆT VIRUS / WINDOWS SECURITY (có xóa file MyExcel không?)'
try {
    $avs = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)
    foreach ($av in $avs) {
        $hex = '{0:X6}' -f [int]$av.productState
        $on = $hex.Substring(2, 2) -match '1[0-1]'
        Info 'Antivirus' ("{0} (đang bật: {1})" -f $av.displayName, $on)
    }
    $third = @($avs | Where-Object { $_.displayName -notmatch '(?i)windows defender|microsoft defender' })
    if ($third.Count -gt 0) {
        Add-Finding 'AV_BEN_THU_BA' 'THONGTIN' ("Có phần mềm diệt virus bên thứ 3: {0}" -f (($third | ForEach-Object { $_.displayName }) -join ', ')) 'Thêm C:\MyExcel vào danh sách loại trừ (Exclusions) của phần mềm này; kiểm tra khu cách ly (Quarantine) xem có file QR Code/xlam không.'
    }
} catch {}
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    Info 'Defender real-time protection' $mp.RealTimeProtectionEnabled
    $pref = Get-MpPreference -ErrorAction Stop
    $ex = @($pref.ExclusionPath)
    if ($ex.Count -eq 1 -and "$($ex[0])" -match 'N/A') {
        Info 'Defender Exclusions' 'cần chạy quyền admin mới xem được'
    } else {
        Info 'Defender Exclusions' ($ex -join ' | ')
        if ($mp.RealTimeProtectionEnabled -and -not ($ex | Where-Object { "$_" -match '(?i)myexcel' })) {
            Add-Finding 'CHUA_LOAI_TRU_DEFENDER' 'CANHBAO' 'Chưa thêm thư mục MyExcel vào Exclusions của Windows Security' 'Windows Security > Virus & threat protection > Manage settings > Exclusions > Add or remove exclusions > Add folder > C:\MyExcel (bước 7 hướng dẫn cài MyExcel).'
        }
    }
    Info 'Controlled folder access' ($(switch ($pref.EnableControlledFolderAccess) { 1 { 'BẬT' } 2 { 'audit' } default { 'tắt' } }))
    if ($pref.EnableControlledFolderAccess -eq 1) {
        Add-Finding 'CFA_BAT' 'CANHBAO' 'Controlled folder access đang bật: Excel có thể bị chặn ghi file vào Documents/Desktop' 'Windows Security > Ransomware protection > Allow an app through Controlled folder access > thêm EXCEL.EXE.'
    }
    $asrNames = @{
        '92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B' = 'Chặn macro Office gọi Win32 API'
        'D4F940AB-401B-4EFC-AADC-AD5F3C50688A' = 'Chặn Office tạo tiến trình con'
        '3B576869-A4EC-4529-8536-B80A7769E899' = 'Chặn Office tạo nội dung thực thi'
        '75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84' = 'Chặn Office chèn code vào tiến trình khác'
    }
    $ids = @($pref.AttackSurfaceReductionRules_Ids); $acts = @($pref.AttackSurfaceReductionRules_Actions)
    for ($i = 0; $i -lt $ids.Count; $i++) {
        $n = $asrNames[[string]$ids[$i]]
        if ($n -and $acts[$i] -eq 1) {
            Add-Finding 'ASR_BAT' 'CANHBAO' "Defender ASR đang bật luật: $n" 'Luật này có thể chặn macro MyExcel (áp dụng cả máy). Cần admin tắt/đặt Audit hoặc thêm loại trừ ASR cho C:\MyExcel.'
        }
    }
} catch { Note "Không đọc được Defender: $($_.Exception.Message)" }
try {
    $det = @(Get-MpThreatDetection -ErrorAction Stop | Where-Object { ($_.Resources -join ';') -match '(?i)myexcel|qr.?code|\.xlam|\.xla\b' })
    foreach ($d in ($det | Select-Object -First 10)) { Note ("{0}  {1}" -f $d.InitialDetectionTime, ($d.Resources -join '; ')) }
    if ($det.Count -gt 0) {
        Add-Finding 'DEFENDER_DA_XU_LY' 'LOI' "Windows Defender từng phát hiện/xử lý $($det.Count) lần trên file MyExcel/add-in" 'Windows Security > Protection history > chọn mục MyExcel > Actions > Allow/Restore; thêm C:\MyExcel vào Exclusions; copy lại file bị xóa từ bộ cài.'
    } else { Ok 'Defender không ghi nhận phát hiện nào trên file MyExcel' }
} catch { Note 'Không đọc được lịch sử Defender (thường cần quyền admin).' }

# ----------------------------------------------------------------------------
Section '10. THÔNG BÁO LỖI OFFICE & CRASH GẦN ĐÂY (30 ngày)'
try {
    $since = (Get-Date).AddDays(-30)
    $oaRx = '(?i)macro|visual basic|vba|add-?in|activex|trust|blocked|protected view|run-?time|compile|object library|project or library|myexcel|qr|\.xlam|\.xla\b|untrusted|security|không tin cậy|bị chặn|lỗi'
    $oa = @(Get-WinEvent -FilterHashtable @{ LogName = 'OAlerts'; StartTime = $since } -MaxEvents 500 -ErrorAction Stop |
        Where-Object { $_.Message -match $oaRx -and $_.Message -notmatch '(?i)^Compositor Type|want to save your changes' })
    Info 'Số hộp thoại lỗi Office (OAlerts) liên quan' $oa.Count
    $groups = $oa | Group-Object { (($_.Message -replace '\s+', ' ') -replace '\s*P1:.*$', '').Trim() }
    foreach ($g in ($groups | Select-Object -First 15)) {
        $m = $g.Name
        if ($m.Length -gt 260) { $m = $m.Substring(0, 260) + '...' }
        Out-Line ("    {0} (x{1})  {2}" -f $g.Group[0].TimeCreated.ToString('dd/MM HH:mm'), $g.Count, $m) 'Yellow'
    }
} catch { Note 'Không có/không đọc được nhật ký OAlerts.' }
try {
    $cr = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000, 1002; StartTime = $since } -MaxEvents 500 -ErrorAction Stop |
        Where-Object { $_.Message -match '(?i)excel\.exe' })
    Info 'Số lần EXCEL.EXE crash/treo' $cr.Count
    foreach ($e in ($cr | Select-Object -First 5)) {
        $mod = if ($e.Message -match '(?i)Faulting module (name|path):\s*([^\r\n,]+)') { $Matches[2] } else { '' }
        Note ("{0}  Event {1}  {2}" -f $e.TimeCreated.ToString('dd/MM HH:mm'), $e.Id, $mod)
    }
    if ($cr.Count -ge 3) {
        Add-Finding 'EXCEL_CRASH' 'CANHBAO' "Excel bị crash/treo $($cr.Count) lần trong 30 ngày" 'Sửa Office: Settings > Apps > Microsoft 365/Office > Modify > Quick Repair (nếu vẫn lỗi thì Online Repair).'
    }
} catch { Note 'Không đọc được nhật ký Application.' }

# ----------------------------------------------------------------------------
Section '11. MẠNG (kích hoạt bản quyền / tải dữ liệu ngân hàng nếu có)'
try {
    $is = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $pe = Get-RegValue $is 'ProxyEnable'; $ps = Get-RegValue $is 'ProxyServer'; $pac = Get-RegValue $is 'AutoConfigURL'
    Info 'Proxy của user' ("bật={0} server={1} pac={2}" -f ($pe -eq 1), $ps, $pac)
    Snap 'Net.Proxy' "$pe|$ps|$pac"
    if ($pe -eq 1 -or $pac) {
        Add-Finding 'PROXY_BAT' 'CANHBAO' "Profile này đặt proxy ($ps$pac) - profile mới thì không" 'Settings > Network & internet > Proxy > tắt "Use a proxy server"/"Use setup script" nếu không cần.'
    }
    $sp = Get-RegValue $is 'SecureProtocols'
    if ($null -ne $sp) {
        $tls12 = (([int]$sp) -band 0x800) -ne 0
        Info 'TLS 1.2 trong Internet Options' $tls12
        Snap 'Net.SecureProtocols' $sp
        if (-not $tls12) {
            Add-Finding 'TLS12_TAT' 'CANHBAO' 'Internet Options của user đang tắt TLS 1.2' 'Control Panel > Internet Options > Advanced > tích Use TLS 1.2 (và 1.3) > OK.'
        }
    }
    $wh = (netsh winhttp show proxy) -join ' '
    Info 'WinHTTP proxy' (($wh -replace '\s+', ' ').Trim())
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
    foreach ($u in 'https://myexcel.vn/', 'https://api.vietqr.io/v2/banks') {
        try {
            $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 12 -ErrorAction Stop
            Ok "$u -> HTTP $($r.StatusCode)"
        } catch {
            if ($_.Exception.Response) { Ok "$u -> HTTP $([int]$_.Exception.Response.StatusCode) (có kết nối)" }
            else {
                Add-Finding 'KHONG_KET_NOI' 'CANHBAO' "Không kết nối được $u : $($_.Exception.Message)" 'Kiểm tra mạng/tường lửa/proxy (chỉ ảnh hưởng chức năng cần Internet như kích hoạt bản quyền).'
            }
        }
    }
} catch { Note "Lỗi khi kiểm tra mạng: $($_.Exception.Message)" }
