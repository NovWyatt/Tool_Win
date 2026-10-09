# Máy in mạng LAN - phần dùng chung: in ra màn hình kèm ghi báo cáo, hỏi người dùng, kiểm tra mạng,
# dịch mã lỗi Windows, gọi API Windows (tên chia sẻ, mật khẩu mạng đã lưu, ổ mạng).

$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Report = New-Object System.Collections.Generic.List[string]
$script:Findings = New-Object System.Collections.ArrayList
$script:NoPause = $false

# ---------------------------------------------------------------- in ra màn hình (và báo cáo)
function Write-Out {
    param([string]$Text = '', [string]$Color = '')
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
    [void]$script:Report.Add($Text)
}
function Write-Head { param([string]$Text) Write-Out ''; Write-Out ("== $Text " + ('=' * [Math]::Max(3, 68 - $Text.Length))) 'Cyan' }
function Write-Line { param([string]$Text) Write-Out "  $Text" }
function Write-Sub { param([string]$Text) Write-Out "       $Text" 'Gray' }
function Write-Ok { param([string]$Text) Write-Out "  [OK] $Text" 'Green' }
function Write-Warn { param([string]$Text) Write-Out "  [!]  $Text" 'Yellow' }
function Write-Bad { param([string]$Text) Write-Out "  [X]  $Text" 'Red' }
function Write-Info { param([string]$Text) Write-Out "  [i]  $Text" 'Gray' }
function Write-Plan { param([string]$Text) Write-Out "   ->  $Text" 'White' }

function Add-Finding {
    # Vấn đề tìm thấy khi chẩn đoán. Ma: mã cố định (CHU_HOA) cho file kết quả của Trạm Tool.
    # Fix: chế độ nên chạy để sửa (để trống nếu phải làm tay).
    param([string]$Ma, [ValidateSet('bad', 'warn', 'info')][string]$Level, [string]$Text, [string]$Fix = '', [string]$Hint = '')
    [void]$script:Findings.Add([pscustomobject]@{ Ma = $Ma; Level = $Level; Text = $Text; Fix = $Fix; Hint = $Hint })
    switch ($Level) { 'bad' { Write-Bad $Text } 'warn' { Write-Warn $Text } default { Write-Info $Text } }
    if ($Hint) { Write-Sub $Hint }
}

# ---------------------------------------------------------------- kết quả cho Trạm Tool
$script:ResultLevel = @{ bad = 'loi'; warn = 'canh-bao'; info = 'thong-tin'; ok = 'ok' }

function Save-RunResult {
    # Ghi ket_qua\KetQua_MayIn_<chế độ>_<máy>_<giờ>.json theo chuẩn tramtool.ketqua/1: Trạm Tool hiện từng phát hiện
    # kèm nút chạy chế độ sửa. Ghi lỗi thì chỉ cảnh báo, không đổi mã thoát. Trả đường dẫn file (hoặc '').
    param([string]$CheDo, [int]$Code, [datetime]$Start, [string]$Message = '', [bool]$DryRun = $false, [object[]]$Files = @())
    $rank = @{ loi = 0; 'canh-bao' = 1; 'thong-tin' = 2; ok = 3 }
    $i = 0
    $items = @(foreach ($f in @($script:Findings)) {
            $muc = $script:ResultLevel[[string]$f.Level]
            $o = [ordered]@{ ma = [string]$f.Ma; mucDo = $muc; tieuDe = [string]$f.Text; chiTiet = ''; cachSua = [string]$f.Hint }
            if ($f.Fix -and $script:Modes -and $script:Modes.Contains([string]$f.Fix)) {
                $o.cachSua = ('Chạy "{0}".{1}' -f $script:Modes[$f.Fix].Label, $(if ($f.Hint) { ' ' + $f.Hint } else { '' }))
                $o['chayTiep'] = [ordered]@{ congCu = 'may-in-lan'; action = [string]$f.Fix }
            }
            [pscustomobject]@{ F = $o; L = $rank[$muc]; I = $i++ }
        })
    $sorted = @($items | Sort-Object L, I | ForEach-Object { $_.F })
    $n = @{}
    foreach ($k in 'loi', 'canh-bao', 'thong-tin') { $n[$k] = @($sorted | Where-Object { $_.mucDo -eq $k }).Count }
    if (-not $Message) { $Message = if ($n['loi'] + $n['canh-bao']) { 'Có {0} lỗi, {1} cảnh báo; xem chi tiết.' -f $n['loi'], $n['canh-bao'] } else { 'Xong, không có lỗi.' } }
    $r = [ordered]@{
        chuan = 'tramtool.ketqua/1'; congCu = 'may-in-lan'; cheDo = $CheDo; phienBan = $script:ToolVersion
        may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
        batDau = $Start.ToString('s'); ketThuc = (Get-Date).ToString('s')
        maThoat = $Code; trangThai = @{ 0 = 'xong'; 1 = 'loi'; 2 = 'thieu-dieu-kien'; 3 = 'mot-phan' }[$Code]
        chayThu = $DryRun
        ma = $(if ($n['loi']) { 'CO_LOI' } elseif ($n['canh-bao']) { 'CO_CANH_BAO' } else { 'KHONG_CO_LOI' })
        thongDiep = $Message
        tomTat = [ordered]@{ loi = $n['loi']; canhBao = $n['canh-bao']; thongTin = $n['thong-tin'] }
        phatHien = $sorted
        tep = @($Files)
    }
    try {
        $f = Join-Path (Get-ResultDir) ('KetQua_MayIn_{0}_{1}_{2:yyyyMMdd_HHmmss}.json' -f ((($CheDo -split '-') | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ''), $env:COMPUTERNAME, $Start)
        [IO.File]::WriteAllText("$f.tmp", ($r | ConvertTo-Json -Depth 8), $script:Utf8NoBom)
        Move-Item -LiteralPath "$f.tmp" -Destination $f -Force
        return $f
    } catch { Write-Host "  Không ghi được file kết quả cho Trạm Tool: $($_.Exception.Message.Trim())" -ForegroundColor Yellow; return '' }
}

# ---------------------------------------------------------------- hỏi người dùng
# Không có bàn phím (chạy tự động, stdin bị chuyển hướng) thì trả giá trị mặc định thay vì treo.
function Read-Text {
    param([string]$Prompt, [string]$Default = '')
    if ([Console]::IsInputRedirected) { return $Default }
    $a = ([string](Read-Host "  $Prompt")).Trim()
    if (-not $a) { return $Default }
    return $a
}

function Read-YesNo {
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

function Read-Number {
    # Chọn một số trong khoảng; Enter trả $Default (có thể là $null = bỏ qua).
    param([string]$Prompt, [int]$Min, [int]$Max, $Default = $null)
    if ([Console]::IsInputRedirected) { return $Default }
    while ($true) {
        $a = ([string](Read-Host "  $Prompt")).Trim()
        if (-not $a) { return $Default }
        $n = 0
        if ([int]::TryParse($a, [ref]$n) -and $n -ge $Min -and $n -le $Max) { return $n }
        Write-Host "  Gõ một số từ $Min đến $Max." -ForegroundColor Yellow
    }
}

function Confirm-Strong {
    # Xác nhận cho thay đổi làm giảm bảo mật: phải gõ đúng cụm từ, Enter là huỷ.
    param([string]$Phrase = 'DONG Y')
    if ([Console]::IsInputRedirected) { return $false }
    $a = ([string](Read-Host "  Gõ $Phrase để đồng ý (Enter để huỷ)")).Trim()
    return ($a -eq $Phrase)
}

function Wait-Close {
    param([string]$Text = 'Bấm Enter để đóng cửa sổ')
    if ($script:NoPause -or [Console]::IsInputRedirected) { return }
    Write-Host ''
    [void](Read-Host "  $Text")
}

# ---------------------------------------------------------------- quyền, tài khoản, thư mục kết quả
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CurrentUser { return [Security.Principal.WindowsIdentity]::GetCurrent().Name }

function Get-ConsoleUser {
    # Người đang dùng máy (phiên trên màn hình). Khác tài khoản đang chạy khi UAC hỏi mật khẩu một Admin khác.
    try { return [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName } catch { return '' }
}

function Get-ResultDir {
    # ket_qua\ trong thư mục công cụ; thư mục công cụ không ghi được (vd giải nén vào chỗ chỉ đọc) thì ra Desktop.
    # MIL_KET_QUA: thư mục khác (bài thử).
    $d = if ($env:MIL_KET_QUA) { $env:MIL_KET_QUA } else { Join-Path $script:ToolDir 'ket_qua' }
    try {
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -ErrorAction Stop) }
        return $d
    } catch {
        $d = Join-Path ([Environment]::GetFolderPath('Desktop')) 'MayInLan_ket_qua'
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d) }
        return $d
    }
}

function Get-RegValue {
    # Giá trị registry, $null khi chưa đặt (khác với giá trị 0).
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $key = Get-Item -LiteralPath $Path
    if ($key.GetValueNames() -notcontains $Name) { return $null }
    return $key.GetValue($Name)
}

function Invoke-Native {
    # Chạy lệnh ngoài, trả mã thoát và output. Tạm đổi ErrorActionPreference để PowerShell 5.1 không biến dòng
    # stderr thành lỗi dừng script.
    param([string]$FilePath, [string[]]$ArgumentList = @())
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { [string]$_ }) }
    finally { $ErrorActionPreference = $prev }
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = ($out -join "`n") }
}

# ---------------------------------------------------------------- kiểm tra tên, đường dẫn người dùng nhập
function Test-HostName { param([string]$Value) return ($Value -match '^[\p{L}\p{N}][\p{L}\p{N}._-]{0,252}$') }

function Split-UncPath {
    # \\may\chia-se[\thu-muc...] → @{ Host; Share; Path }. Sai dạng thì trả $null.
    param([string]$Value)
    $v = $Value.Trim().Replace('/', '\').TrimEnd('\')
    if ($v -notmatch '^\\\\(?<h>[\p{L}\p{N}][\p{L}\p{N}._-]*)\\(?<s>[^\\:*?"<>|]+)(?<rest>(\\[^\\:*?"<>|]+)*)$') { return $null }
    return [pscustomobject]@{ Host = $Matches['h']; Share = $Matches['s']; Path = $v }
}

# ---------------------------------------------------------------- mạng
$script:PortRole = @{
    445 = 'chia sẻ file, máy in (SMB)'; 139 = 'NetBIOS (Windows, NAS đời cũ)'; 135 = 'RPC (cần khi kết nối máy in chia sẻ)'
    9100 = 'in trực tiếp RAW/JetDirect'; 631 = 'in qua IPP'; 515 = 'in qua LPR'; 80 = 'trang quản trị web'; 443 = 'trang quản trị web (https)'
}
$script:PortStateText = @{ open = 'mở'; closed = 'đóng (máy có trả lời)'; timeout = 'không phản hồi'; unreachable = 'không tới được (khác mạng)' }

function Resolve-HostAddress {
    # Tên máy hoặc IP → danh sách địa chỉ, IPv4 trước. Có hạn giờ để không treo vài chục giây khi tên không tồn tại.
    param([string]$Name, [int]$TimeoutMs = 4000)
    $ip = $null
    if ([Net.IPAddress]::TryParse($Name, [ref]$ip)) { return @($ip) }
    $ar = [Net.Dns]::BeginGetHostAddresses($Name, $null, $null)
    if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { throw "Hết thời gian chờ tìm địa chỉ của '$Name'." }
    $all = @([Net.Dns]::EndGetHostAddresses($ar))
    $v4 = @($all | Where-Object { $_.AddressFamily -eq 'InterNetwork' })
    $v6 = @($all | Where-Object { $_.AddressFamily -ne 'InterNetwork' })
    return @($v4 + $v6)
}

function Test-TcpPorts {
    # Thử nhiều cổng TCP cùng lúc. Mỗi cổng: open, closed (máy trả lời nhưng cổng đóng),
    # timeout (máy tắt, tường lửa chặn), unreachable (khác mạng). Trả hashtable cổng → trạng thái.
    param([Parameter(Mandatory)][Net.IPAddress]$Address, [int[]]$Ports, [int]$TimeoutMs = 1500)
    $tries = @(foreach ($port in $Ports) {
            $c = New-Object Net.Sockets.TcpClient($Address.AddressFamily)
            $ar = $null
            try { $ar = $c.BeginConnect($Address, $port, $null, $null) } catch { }
            [pscustomobject]@{ Port = $port; Client = $c; Async = $ar }
        })
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    $result = @{}
    foreach ($t in $tries) {
        $state = 'timeout'
        $left = [int][Math]::Max(0, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
        if ($t.Async -and $t.Async.AsyncWaitHandle.WaitOne($left)) {
            try { $t.Client.EndConnect($t.Async); $state = 'open' }
            catch {
                $e = $_.Exception
                while ($e -and -not ($e -is [Net.Sockets.SocketException])) { $e = $e.InnerException }
                if ($e) {
                    switch ([string]$e.SocketErrorCode) {
                        'ConnectionRefused' { $state = 'closed' }
                        { $_ -in 'HostUnreachable', 'NetworkUnreachable' } { $state = 'unreachable' }
                    }
                }
            }
        }
        $t.Client.Close()
        $result[$t.Port] = $state
    }
    return $result
}

function Test-Ping {
    param([Net.IPAddress]$Address, [int]$TimeoutMs = 1000)
    try { return ((New-Object Net.NetworkInformation.Ping).Send($Address, $TimeoutMs).Status -eq 'Success') } catch { return $false }
}

# ---------------------------------------------------------------- mã lỗi Windows
function ConvertTo-ErrorCode {
    # HRESULT 0x8007xxxx → mã Win32 xxxx; số âm → số 32 bit không dấu (0xC000A000...).
    param([int64]$Code)
    if ($Code -lt 0) { $Code += 4294967296 }
    if (($Code -shr 16) -eq 0x8007) { return ($Code -band 0xFFFF) }
    return $Code
}

function Get-ErrorCode {
    # Mã lỗi từ lỗi PowerShell: cmdlet máy in/SMB (CimException), Win32Exception, HRESULT trong FullyQualifiedErrorId.
    param($ErrorRecord)
    $ex = $ErrorRecord.Exception
    try {
        $p = $ex.ErrorData.CimInstanceProperties['error_Code']
        if ($p -and $null -ne $p.Value) { return ConvertTo-ErrorCode ([int64]$p.Value) }
    } catch { }
    if ([string]$ErrorRecord.FullyQualifiedErrorId -match 'HRESULT 0x([0-9a-fA-F]{8})') { return ConvertTo-ErrorCode ([Convert]::ToInt64($Matches[1], 16)) }
    $e = $ex
    while ($e) { if ($e -is [ComponentModel.Win32Exception]) { return [int64]$e.NativeErrorCode }; $e = $e.InnerException }
    return ConvertTo-ErrorCode ([int64]$ex.HResult)
}

function Format-ErrorCode {
    param([int64]$Code)
    if ($Code -le 0xFFFF) { return ('{0} (0x{0:X8})' -f $Code) }
    return ('0x{0:X8}' -f $Code)
}

# Mã lỗi hay gặp khi in qua mạng, vào thư mục chia sẻ: @(nghĩa, cách xử lý).
$script:GuestHelp = @(
    'Windows chặn đăng nhập khách (guest, không mật khẩu).',
    'Cách an toàn: tạo tài khoản có mật khẩu trên NAS/máy chia sẻ rồi kết nối bằng tài khoản đó. Cách tạm, giảm bảo mật: "Nới bảo mật" > Cho đăng nhập khách.'
)
$script:SigningHelp = @(
    'Chữ ký SMB không hợp lệ: thiết bị không hỗ trợ ký SMB mà Windows này bắt buộc.',
    'Cách đúng: bật SMB signing trên NAS/thiết bị (cập nhật firmware). Cách tạm: "Nới bảo mật" > Không bắt buộc ký SMB.'
)
$script:ErrorHelp = @{
    '5'          = @('Không có quyền truy cập.', 'Tài khoản đang dùng chưa được cấp quyền. Trên máy chia sẻ: chuột phải thư mục hoặc máy in > Properties > Sharing (và tab Security), cấp quyền cho tài khoản đó.')
    '53'         = @('Không tìm thấy đường dẫn mạng (0x80070035).', 'Máy kia tắt, khác mạng, hoặc đang chặn chia sẻ (mạng Public, tường lửa). Thử bằng địa chỉ IP thay cho tên máy; trên máy chia sẻ chạy "Bật chia sẻ file và máy in".')
    '64'         = @('Kết nối bị ngắt giữa chừng (0x00000040).', 'Mạng chập chờn, hoặc thiết bị chỉ hỗ trợ SMB1 (NAS, máy in rất cũ). Không bật SMB1: cập nhật firmware thiết bị, hoặc in thẳng qua IP.')
    '67'         = @('Không tìm thấy tên chia sẻ.', 'Kiểm tra lại tên thư mục/máy in chia sẻ. Chạy Chẩn đoán với tên máy đó để xem các tên chia sẻ đang có.')
    '85'         = @('Chữ ổ đĩa này đã được dùng.', 'Chọn chữ ổ khác, hoặc ngắt ổ đang dùng chữ đó.')
    '86'         = @('Sai mật khẩu.', 'Chạy lại và gõ đúng mật khẩu của tài khoản trên máy chia sẻ.')
    '124'        = @('Lỗi cấp driver máy in (0x0000007C).', 'Thường gặp sau bản cập nhật bảo mật in ấn. Cài driver của hãng trên máy này trước rồi kết nối lại, hoặc thêm máy in bằng IP.')
    '283'        = @('Lỗi mã hoá RPC khi in qua máy chia sẻ (0x0000011B).', 'Cập nhật Windows trên MÁY CHIA SẺ máy in. Vẫn lỗi: chạy "Nới bảo mật" > Tắt mã hoá RPC trên máy chia sẻ, hoặc thêm máy in thẳng bằng IP trên từng máy.')
    '1203'       = @('Không có dịch vụ mạng nào nhận đường dẫn này (0x800704B3).', 'Kiểm tra đường dẫn dạng \\may\thu-muc. Dịch vụ Workstation phải đang chạy, card mạng phải bật "Client for Microsoft Networks" (chạy Chẩn đoán).')
    '1219'       = @('Đã có kết nối tới máy này bằng tài khoản khác.', 'Windows chỉ cho dùng một tài khoản với mỗi máy chủ. Ngắt các ổ mạng tới máy đó hoặc đăng xuất rồi đăng nhập lại; hoặc kết nối bằng địa chỉ IP thay cho tên máy.')
    '1222'       = @('Máy này không có mạng.', 'Kiểm tra dây mạng/Wi-Fi.')
    '1231'       = @('Không tới được mạng của máy kia.', 'Hai máy khác lớp mạng (khác router, khác VLAN, Wi-Fi khách). Cho hai máy vào cùng một mạng.')
    '1232'       = @('Không tới được máy kia.', 'Máy kia tắt hoặc khác mạng.')
    '1272'       = $script:GuestHelp
    '1326'       = @('Sai tên đăng nhập hoặc mật khẩu.', 'Dùng tài khoản của MÁY CHIA SẺ (vd PC-KETOAN\ten), không phải tài khoản máy này. Tài khoản không đặt mật khẩu thì không đăng nhập qua mạng được: đặt mật khẩu cho nó.')
    '1331'       = @('Tài khoản bị vô hiệu hoá trên máy chia sẻ.', 'Bật lại tài khoản trên máy đó hoặc dùng tài khoản khác.')
    '1722'       = @('Không kết nối được dịch vụ in của máy kia (0x000006BA).', 'Máy kia tắt, dịch vụ Print Spooler trên đó dừng, hoặc tường lửa chặn. Trên máy đó chạy "Bật chia sẻ file và máy in" và "Sửa hàng đợi in".')
    '1753'       = @('Máy chia sẻ không nhận kết nối RPC (0x000006D9).', 'Trên máy chia sẻ, dịch vụ Windows Defender Firewall đang tắt. Bật lại tường lửa trong Windows Security rồi chia sẻ máy in lại.')
    '1797'       = @('Chưa có driver máy in (0x00000705).', 'Cài driver của hãng rồi thử lại.')
    '1801'       = @('Tên máy in không hợp lệ hoặc không tìm thấy (0x00000709).', 'Kiểm tra tên chia sẻ. Máy này Windows 11 22H2 trở lên, máy chia sẻ Windows cũ: thử "Nới bảo mật" > RPC qua named pipe.')
    '1909'       = @('Tài khoản bị khoá vì nhập sai mật khẩu nhiều lần.', 'Chờ hết thời gian khoá hoặc mở khoá trên máy chia sẻ.')
    '2202'       = @('Tên đăng nhập không hợp lệ.', 'Gõ dạng TEN-MAY\tai-khoan hoặc tai-khoan.')
    '2250'       = @('Không có kết nối mạng nào ở ổ này.', 'Ổ đã được ngắt trước đó.')
    '2401'       = @('Đang có file mở trên ổ mạng.', 'Đóng các file đó rồi thử lại, hoặc chọn ngắt bắt buộc.')
    '2404'       = @('Ổ đang được dùng.', 'Đóng cửa sổ, chương trình đang mở ổ đó rồi thử lại.')
    '3012'       = @('Không tìm thấy máy in nào (0x00000BC4).', 'Kiểm tra tên chia sẻ. Máy này Windows 11 22H2 trở lên, máy chia sẻ Windows cũ: thử "Nới bảo mật" > RPC qua named pipe, hoặc thêm máy in thẳng bằng IP.')
    '3019'       = @('Cần cài driver máy in nhưng Windows chỉ cho Admin cài (0x00000BCB).', 'Kết nối bằng quyền Admin (công cụ này đã tự làm), hoặc cài sẵn driver của hãng trên máy này.')
    '2147500037' = @('Lỗi chung (0x80004005).', 'Thường do tường lửa, mạng Public, thiết bị chỉ hỗ trợ SMB1 hoặc bị chặn đăng nhập khách. Chạy Chẩn đoán với tên máy đó.')
    '2148073478' = $script:SigningHelp   # 0x80090006
    '3221266432' = $script:SigningHelp   # 0xC000A000 STATUS_INVALID_SIGNATURE
    '3227320323' = $script:GuestHelp     # 0xC05D0003
}

function Get-ErrorMeaning {
    # Nghĩa của mã lỗi trong bảng, bỏ mã hex trong ngoặc khi nó trùng mã đang in kèm (Format-ErrorCode).
    param([int64]$Code)
    $h = $script:ErrorHelp[[string]$Code]
    if (-not $h) { return '' }
    $hex = [regex]::Match((Format-ErrorCode $Code), '0x[0-9A-F]{8}').Value
    if ($hex) { return $h[0].Replace(" ($hex)", '') }
    return $h[0]
}

function Write-ErrorHelp {
    param([int64]$Code, [string]$Prefix = 'Lỗi')
    $h = $script:ErrorHelp[[string]$Code]
    if ($h) {
        Write-Bad ('{0} {1}: {2}' -f $Prefix, (Format-ErrorCode $Code), (Get-ErrorMeaning $Code))
        Write-Sub ('Cách xử lý: ' + $h[1])
    } else {
        $msg = ''
        if ($Code -le [int]::MaxValue) { $msg = (New-Object ComponentModel.Win32Exception([int]$Code)).Message }
        Write-Bad ('{0} {1}: {2}' -f $Prefix, (Format-ErrorCode $Code), $msg)
    }
}

# ---------------------------------------------------------------- dịch vụ
$script:StartModeText = @{ Automatic = 'tự khởi động'; AutomaticDelayed = 'tự khởi động (trễ)'; Manual = 'thủ công'; Disabled = 'đã vô hiệu hoá'; Boot = 'boot'; System = 'system' }
$script:ServiceStatusText = @{ Running = 'đang chạy'; Stopped = 'đã dừng'; Paused = 'tạm dừng'; StartPending = 'đang khởi động'; StopPending = 'đang dừng' }

function Get-ServiceState {
    # Trạng thái dịch vụ, phân biệt cả "tự khởi động (trễ)" mà Get-Service của PowerShell 5.1 không thấy.
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return $null }
    $start = $null; $delayed = 0
    try {
        $reg = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -ErrorAction Stop
        $start = $reg.Start
        if ($reg.PSObject.Properties['DelayedAutostart']) { $delayed = [int]$reg.DelayedAutostart }
    } catch { }
    $mode = switch ($start) {
        0 { 'Boot' } 1 { 'System' } 3 { 'Manual' } 4 { 'Disabled' }
        2 { if ($delayed) { 'AutomaticDelayed' } else { 'Automatic' } }
        default { [string]$svc.StartType }
    }
    return [pscustomobject]@{ Name = $svc.Name; DisplayName = $svc.DisplayName; Status = [string]$svc.Status; Running = ($svc.Status -eq 'Running'); StartMode = $mode }
}

function Format-ServiceState {
    param($State)
    if (-not $State) { return 'không có trên máy này' }
    return ('{0}, {1}' -f $script:ServiceStatusText[$State.Status], $script:StartModeText[$State.StartMode])
}

function Set-ServiceStartMode {
    param([string]$Name, [string]$Mode)
    $arg = @{ Automatic = 'auto'; AutomaticDelayed = 'delayed-auto'; Manual = 'demand'; Disabled = 'disabled' }[$Mode]
    if (-not $arg) { throw "Không đặt được kiểu khởi động '$Mode'." }
    $r = Invoke-Native 'sc.exe' @('config', $Name, 'start=', $arg)
    if ($r.Code -ne 0) { throw ('sc config báo lỗi {0}' -f (Format-ErrorCode $r.Code)) }
}

function Stop-SpoolerHard {
    # Print Spooler bị treo thì lệnh dừng chờ mãi: chờ tối đa 20 giây rồi dừng hẳn tiến trình spoolsv.
    $svc = Get-Service Spooler
    if ($svc.Status -eq 'Stopped') { return }
    try { $svc.Stop() } catch { }
    try { $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20)) }
    catch {
        Get-Process -Name spoolsv -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Restart-Spooler {
    # Khởi động lại Print Spooler cùng các dịch vụ phụ thuộc đang chạy (lệnh in đang chờ vẫn giữ).
    $deps = @((Get-Service Spooler).DependentServices | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { $_.Name })
    Stop-SpoolerHard
    Start-Service Spooler
    (Get-Service Spooler).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
    foreach ($d in $deps) { try { Start-Service $d -ErrorAction Stop } catch { } }
}

# ---------------------------------------------------------------- máy in
$script:PrinterStatusText = @{
    Normal = 'sẵn sàng'; Paused = 'tạm dừng'; Error = 'lỗi'; PendingDeletion = 'đang xoá'; PaperJam = 'kẹt giấy'; PaperOut = 'hết giấy'
    ManualFeed = 'chờ nạp giấy tay'; PaperProblem = 'lỗi giấy'; Offline = 'ngoại tuyến (Offline)'; IOActive = 'đang truyền'; Busy = 'bận'
    Printing = 'đang in'; OutputBinFull = 'khay ra đầy'; NotAvailable = 'không sẵn sàng'; Waiting = 'đang chờ'; Processing = 'đang xử lý'
    Initializing = 'đang khởi động'; WarmingUp = 'đang làm nóng'; TonerLow = 'sắp hết mực'; NoToner = 'hết mực'; PagePunt = 'không in được trang'
    UserIntervention = 'cần người xử lý'; OutOfMemory = 'hết bộ nhớ'; DoorOpen = 'mở nắp'; ServerUnknown = 'không rõ máy chủ'; PowerSave = 'tiết kiệm điện'
}
$script:PrinterBadStatus = 'Error', 'PaperJam', 'PaperOut', 'Offline', 'NoToner', 'UserIntervention', 'DoorOpen', 'NotAvailable', 'OutOfMemory', 'PaperProblem', 'Paused'
$script:VirtualDrivers = '^(Microsoft Print To PDF|Microsoft XPS Document Writer.*|Send to Microsoft OneNote.*|Microsoft Shared Fax Driver|Remote Desktop Easy Print|Microsoft Virtual Print Class Driver|Universal Print Class Driver)$'
$script:CopyWords = 'Copy', 'Bản sao'

function Get-PrinterStatusText {
    param([string]$Status)
    $parts = @(($Status -split ',\s*') | Where-Object { $_ } | ForEach-Object { $t = $script:PrinterStatusText[$_]; if ($t) { $t } else { $_ } })
    if (-not $parts) { return 'không rõ' }
    return ($parts -join ', ')
}

function Get-PrinterList {
    # Máy in trên máy này kèm loại cổng (TCP/IP, WSD, USB, kết nối qua máy khác), IP, SNMP và cờ của WMI.
    $ports = @{}
    foreach ($p in @(Get-PrinterPort -ErrorAction SilentlyContinue)) { $ports[$p.Name] = $p }
    $wmi = @{}
    foreach ($w in @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue)) { $wmi[$w.Name] = $w }
    $list = foreach ($p in @(Get-Printer -ErrorAction Stop)) {
        $port = $ports[$p.PortName]
        $w = $wmi[$p.Name]
        $kind = 'khac'; $addr = ''; $num = 0; $snmp = $false
        if ([string]$p.Type -eq 'Connection') { $kind = 'connection'; $addr = ([string]$p.ComputerName).TrimStart('\') }
        elseif ($port -and $port.PSObject.Properties['PrinterHostAddress'] -and $port.PrinterHostAddress) {
            $kind = 'tcp'; $addr = [string]$port.PrinterHostAddress; $num = [int]$port.PortNumber; $snmp = [bool]$port.SNMPEnabled
            if ($port.PSObject.Properties['Protocol'] -and [int]$port.Protocol -eq 2) { $kind = 'lpr'; $num = 515 }
        }
        elseif ($p.PortName -match '^(https?|ipps?)://(?<h>[^/:]+)') { $kind = 'ipp'; $addr = $Matches['h'] }
        elseif ($p.PortName -like 'WSD-*') { $kind = 'wsd' }
        elseif ($p.PortName -match '^USB\d+') { $kind = 'usb' }
        if ($p.DriverName -match $script:VirtualDrivers -or $p.PortName -in 'PORTPROMPT:', 'FILE:', 'SHRFAX:', 'nul:') { $kind = 'ao' }
        [pscustomobject]@{
            Name = $p.Name; Type = [string]$p.Type; Kind = $kind; DriverName = $p.DriverName; PortName = $p.PortName
            Address = $addr; PortNumber = $num; Snmp = $snmp; Shared = [bool]$p.Shared; ShareName = [string]$p.ShareName
            Location = [string]$p.Location; Comment = [string]$p.Comment; Status = [string]$p.PrinterStatus
            Default = [bool]($w -and $w.Default); WorkOffline = [bool]($w -and $w.WorkOffline); Wmi = $w
        }
    }
    return @($list)
}

function Get-PrinterKindText {
    param($Printer)
    switch ($Printer.Kind) {
        'connection' { return "qua máy $($Printer.Address)" }
        'tcp' { return ('TCP/IP {0}:{1}' -f $Printer.Address, $Printer.PortNumber) }
        'lpr' { return "LPR $($Printer.Address)" }
        'ipp' { return "IPP $($Printer.Address)" }
        'wsd' { return 'WSD (tự dò trong mạng)' }
        'usb' { return 'cáp USB' }
        'ao' { return 'máy in ảo' }
        default { return $Printer.PortName }
    }
}

function Get-CopyBaseName {
    # "HP LaserJet (Copy 1)" / "(Bản sao 1)" → "HP LaserJet". Tên khác dạng thì trả $null.
    # $AllNames: tên mọi máy in; chữ khác 'Copy'/'Bản sao' (Windows ngôn ngữ khác) chỉ tính khi máy in gốc còn.
    param([string]$Name, [string[]]$AllNames = @())
    if ($Name -notmatch '^(?<base>.+?)\s+\((?<w>[^()]+?)\s+\d+\)$') { return $null }
    $base = $Matches['base']; $word = $Matches['w']
    if ($word -in $script:CopyWords -or $AllNames -contains $base) { return $base }
    return $null
}

function Get-PrintJobsSafe {
    param([string]$PrinterName)
    try { return @(Get-PrintJob -PrinterName $PrinterName -ErrorAction Stop) } catch { return @() }
}

function Get-SpoolDirectory {
    $d = $null
    try { $d = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers' -ErrorAction Stop).DefaultSpoolDirectory } catch { }
    if (-not $d) { $d = Join-Path $env:SystemRoot 'System32\spool\PRINTERS' }
    return $d
}

function Get-WmiPrinter {
    param([string]$Name)
    return (Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)
}

function Invoke-TestPage {
    param([string]$Name)
    $w = Get-WmiPrinter $Name
    if (-not $w) { Write-Warn "Không tìm thấy máy in '$Name' để in trang thử."; return }
    $r = Invoke-CimMethod -InputObject $w -MethodName PrintTestPage
    if ($r.ReturnValue -eq 0) { Write-Ok 'Đã gửi trang in thử.' } else { Write-Warn "Windows báo lỗi $($r.ReturnValue) khi in trang thử." }
}

# ---------------------------------------------------------------- API Windows: tên chia sẻ, mật khẩu đã lưu, ổ mạng
if (-not ('MayInLan.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace MayInLan {
    public class ShareInfo { public string Name; public uint Type; public string Remark; }
    public class CredInfo { public string Target; public string User; public int Type; }

    public static class Native {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct SHARE_INFO_1 { public string NetName; public uint Type; public string Remark; }

        [DllImport("netapi32.dll", CharSet = CharSet.Unicode)]
        static extern int NetShareEnum(string server, int level, out IntPtr buf, int prefMaxLen, out int read, out int total, ref int resume);
        [DllImport("netapi32.dll")]
        static extern int NetApiBufferFree(IntPtr buf);

        // Tên chia sẻ trên một máy (thư mục, máy in), dùng quyền của người đang chạy. Trả mã lỗi Win32, 0 là được.
        public static int EnumShares(string server, out ShareInfo[] shares) {
            List<ShareInfo> list = new List<ShareInfo>();
            IntPtr buf = IntPtr.Zero;
            int read, total, resume = 0;
            int rc = NetShareEnum(server, 1, out buf, -1, out read, out total, ref resume);
            try {
                if (rc == 0 || rc == 234) {
                    int size = Marshal.SizeOf(typeof(SHARE_INFO_1));
                    for (int i = 0; i < read; i++) {
                        SHARE_INFO_1 s = (SHARE_INFO_1)Marshal.PtrToStructure(new IntPtr(buf.ToInt64() + (long)i * size), typeof(SHARE_INFO_1));
                        ShareInfo info = new ShareInfo();
                        info.Name = s.NetName; info.Type = s.Type; info.Remark = s.Remark;
                        list.Add(info);
                    }
                    rc = 0;
                }
            } finally { if (buf != IntPtr.Zero) NetApiBufferFree(buf); }
            shares = list.ToArray();
            return rc;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct CREDENTIAL {
            public int Flags; public int Type; public string TargetName; public string Comment;
            public int LastWrittenLow; public int LastWrittenHigh;
            public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist;
            public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName;
        }
        [DllImport("advapi32.dll", EntryPoint = "CredEnumerateW", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool CredEnumerate(string filter, int flags, out int count, out IntPtr creds);
        [DllImport("advapi32.dll")]
        static extern void CredFree(IntPtr buf);

        // Tên máy và tài khoản của các mật khẩu đã lưu trong Windows Credential Manager. Không đọc mật khẩu.
        public static CredInfo[] ListCredentials() {
            List<CredInfo> list = new List<CredInfo>();
            int count; IntPtr arr;
            if (!CredEnumerate(null, 0, out count, out arr)) return list.ToArray();
            try {
                for (int i = 0; i < count; i++) {
                    IntPtr p = Marshal.ReadIntPtr(arr, i * IntPtr.Size);
                    CREDENTIAL c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
                    CredInfo info = new CredInfo();
                    info.Target = c.TargetName; info.User = c.UserName; info.Type = c.Type;
                    list.Add(info);
                }
            } finally { CredFree(arr); }
            return list.ToArray();
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        class NETRESOURCE {
            public int Scope; public int Type; public int DisplayType; public int Usage;
            public string LocalName; public string RemoteName; public string Comment; public string Provider;
        }
        [DllImport("mpr.dll", EntryPoint = "WNetAddConnection2W", CharSet = CharSet.Unicode)]
        static extern int WNetAddConnection2(NETRESOURCE res, string password, string user, int flags);
        [DllImport("mpr.dll", EntryPoint = "WNetCancelConnection2W", CharSet = CharSet.Unicode)]
        static extern int WNetCancelConnection2(string name, int flags, bool force);

        // Gắn ổ mạng bằng mật khẩu đã lưu trong Windows; persistent: tự nối lại khi đăng nhập (như net use /persistent:yes).
        public static int MapDrive(string local, string remote, bool persistent) {
            NETRESOURCE r = new NETRESOURCE();
            r.Type = 1; r.LocalName = local; r.RemoteName = remote;
            return WNetAddConnection2(r, null, null, persistent ? 1 : 0);
        }
        public static int UnmapDrive(string local, bool updateProfile, bool force) {
            return WNetCancelConnection2(local, updateProfile ? 1 : 0, force);
        }
    }
}
'@
}

function Get-SavedNetworkCredentials {
    # Mật khẩu kiểu "Windows credential" (dùng cho thư mục, máy in chia sẻ): chỉ tên máy và tài khoản.
    return @([MayInLan.Native]::ListCredentials() | Where-Object { $_.Type -eq 2 -and $_.Target -notmatch '^(MicrosoftAccount|WindowsLive|virtualapp|LegacyGeneric):' })
}

function Get-ShareList {
    # → @{ Code; Shares } với Shares là thư mục (Kind 'thu-muc') và máy in (Kind 'may-in'), bỏ chia sẻ ẩn $.
    param([string]$Server)
    $shares = $null
    $rc = [MayInLan.Native]::EnumShares($Server, [ref]$shares)
    $list = @(@($shares) | Where-Object { $_ -and -not $_.Name.EndsWith('$') -and (($_.Type -band 0xFF) -in 0, 1) } | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Kind = $(if (($_.Type -band 0xFF) -eq 1) { 'may-in' } else { 'thu-muc' }); Remark = $_.Remark }
        })
    return [pscustomobject]@{ Code = [int64]$rc; Shares = $list }
}

function Get-MappedDrives {
    # Ổ mạng cố định của người dùng (HKCU\Network), đọc được cả khi chạy quyền Admin.
    $list = foreach ($k in @(Get-ChildItem -LiteralPath 'HKCU:\Network' -ErrorAction SilentlyContinue)) {
        $v = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
        [pscustomobject]@{ Letter = ($k.PSChildName.ToUpperInvariant() + ':'); Remote = [string]$v.RemotePath; User = [string]$v.UserName }
    }
    return @($list)
}
