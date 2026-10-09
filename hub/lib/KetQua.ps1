# Trạm Tool - đọc file kết quả JSON theo chuẩn chung (chuan: tramtool.ketqua/1, xem docs\THEM-CONG-CU.md mục
# "Kết quả máy đọc được") và máy chủ giao diện web của công cụ (action có webServer, vd mdf2sql).
# Cần Common.ps1 và Checks.ps1 (Get-ToolOutputs).

$script:ResultMaxBytes = 2MB
$script:ResultMaxItems = 300
$script:ResultStates = @{ 0 = 'xong'; 1 = 'loi'; 2 = 'thieu-dieu-kien'; 3 = 'mot-phan' }

function Find-RunResult {
    # File kết quả của một lần chạy: trong các outputs có "ketQua": true của công cụ, file sửa trong khoảng
    # [lúc mở - 2 giây, lúc đóng + 15 giây], đúng công cụ (congCu), mới nhất. Không có thì trả ''.
    param([Parameter(Mandatory)]$Tool, [Parameter(Mandatory)][datetime]$Since, [datetime]$Until = (Get-Date))
    $from = $Since.AddSeconds(-2)
    $to = $Until.AddSeconds(15)
    $best = $null
    foreach ($o in @(Get-ToolOutputs -Tool $Tool -Limit 200 | Where-Object { $_.ketQua -and -not $_.isFolder })) {
        $fi = Get-Item -LiteralPath $o.path -ErrorAction SilentlyContinue
        if (-not $fi -or $fi.LastWriteTime -lt $from -or $fi.LastWriteTime -gt $to -or $fi.Length -gt $script:ResultMaxBytes) { continue }
        $r = $null
        try { $r = Read-JsonFile $fi.FullName } catch { continue }
        $owner = [string](Get-Prop $r 'congCu' '')
        if ($owner -and $owner -ne $Tool.id) { continue }
        if ($null -eq (Get-Prop $r 'maThoat' $null) -and -not (Get-Prop $r 'trangThai' $null)) { continue }
        if (-not $best -or $fi.LastWriteTime -gt $best.LastWriteTime) { $best = $fi }
    }
    if ($best) { return $best.FullName }
    return ''
}

function ConvertTo-ResultLevel {
    # Mức của một phát hiện: loi | canh-bao | thong-tin | ok. Nhận cả cách ghi của bản cũ (bad, warn, info).
    param([string]$Level)
    switch -Regex ($Level.Trim().ToLowerInvariant()) {
        '^(loi|bad|error|err)$' { return 'loi' }
        '^(canh-bao|canhbao|warn|warning)$' { return 'canh-bao' }
        '^(ok|dat|pass)$' { return 'ok' }
        default { return 'thong-tin' }
    }
}

function ConvertTo-ResultText {
    param($Value, [int]$Max = 4000)
    if ($null -eq $Value) { return '' }
    $s = if ($Value -is [string]) { $Value } else { (@($Value) | ForEach-Object { [string]$_ }) -join "`n" }
    if ($s.Length -gt $Max) { $s = $s.Substring(0, $Max) + '...' }
    return $s
}

function Read-RunResult {
    # Đọc file kết quả và đưa về đúng chuẩn. Tên trường không phân biệt hoa thường (bản cũ của Chuyển dữ liệu ghi
    # MaThoat, Loi, LuuY); mdf2sql bản cũ ghi tieu_de, cach_sua. Danh sách phát hiện giữ tối đa 300 mục.
    param([Parameter(Mandatory)][string]$Path)
    $fi = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($fi.Length -gt $script:ResultMaxBytes) { throw 'File kết quả lớn hơn 2 MB, mở bằng Notepad để xem.' }
    try { $r = Read-JsonFile $fi.FullName } catch { throw "File kết quả không đọc được (JSON hỏng): $($fi.Name)" }

    $code = Get-Prop $r 'maThoat' (Get-Prop $r 'ma_thoat' $null)
    $code = if ($null -ne $code -and "$code" -match '^-?\d+$') { [int]"$code" } else { $null }
    $state = [string](Get-Prop $r 'trangThai' (Get-Prop $r 'ketQua' ''))
    if ($state -eq 'chua-lam') { $state = 'thieu-dieu-kien' }
    if ($script:ResultStates.Values -notcontains $state) {
        $state = if ($null -ne $code -and $script:ResultStates.ContainsKey($code)) { $script:ResultStates[$code] } else { '' }
    }

    $items = New-Object System.Collections.ArrayList
    $seen = @{ n = 0 }   # tổng số phát hiện trong file, kể cả phần bỏ bớt
    $add = {
        param($Level, $Title, $Detail, $Fix, $Code, $Next)
        $seen.n++
        if ($items.Count -ge $script:ResultMaxItems) { return }
        [void]$items.Add([ordered]@{
                ma = [string]$Code; mucDo = $Level; tieuDe = (ConvertTo-ResultText $Title 600)
                chiTiet = (ConvertTo-ResultText $Detail); cachSua = (ConvertTo-ResultText $Fix 2000); chayTiep = $Next
            })
    }
    foreach ($p in @(Get-Prop $r 'phatHien' (Get-Prop $r 'muc' @()))) {
        if ($null -eq $p) { continue }
        if ($p -is [string]) { & $add 'thong-tin' $p '' '' '' $null; continue }
        $next = $null
        $n = Get-Prop $p 'chayTiep' $null
        if ($n) {
            $nt = [string](Get-Prop $n 'congCu' ''); $na = [string](Get-Prop $n 'action' '')
            if ($nt -match '^[a-z0-9][a-z0-9-]{0,63}$' -and $na -match '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$') { $next = [ordered]@{ congCu = $nt; action = $na } }
        }
        & $add (ConvertTo-ResultLevel ([string](Get-Prop $p 'mucDo' (Get-Prop $p 'muc' '')))) `
        (Get-Prop $p 'tieuDe' (Get-Prop $p 'tieu_de' '')) (Get-Prop $p 'chiTiet' (Get-Prop $p 'chi_tiet' '')) `
        (Get-Prop $p 'cachSua' (Get-Prop $p 'cach_sua' '')) (Get-Prop $p 'ma' '') $next
    }
    if (-not $seen.n) {
        # Bản cũ: lỗi, cảnh báo là danh sách chữ.
        foreach ($s in @(Get-Prop $r 'loi' @())) { if ($s -is [string] -and $s) { & $add 'loi' $s '' '' '' $null } }
        foreach ($k in 'canhBao', 'luuY') {
            $v = Get-Prop $r $k $null
            if ($v -is [array] -or $v -is [string]) { foreach ($s in @($v)) { if ($s -is [string] -and $s) { & $add 'canh-bao' $s '' '' '' $null } } }
        }
    }
    $total = $seen.n

    $sum = Get-Prop $r 'tomTat' $null
    $count = { param($lv) @($items | Where-Object { $_.mucDo -eq $lv }).Count }
    $num = { param($v, $fallback) if ($null -ne $v -and "$v" -match '^\d+$') { [int]"$v" } else { $fallback } }
    $tomTat = [ordered]@{
        loi      = (& $num (Get-Prop $sum 'loi' $null) (& $count 'loi'))
        canhBao  = (& $num (Get-Prop $sum 'canhBao' $null) (& $count 'canh-bao'))
        thongTin = (& $num (Get-Prop $sum 'thongTin' $null) (& $count 'thong-tin'))
    }

    # File, thư mục liên quan: tep [{ nhan, duongDan }] và các trường riêng của bản cũ.
    $files = New-Object System.Collections.ArrayList
    foreach ($t in @(Get-Prop $r 'tep' @())) {
        $p = [string](Get-Prop $t 'duongDan' '')
        if ($p -and [IO.Path]::IsPathRooted($p)) { [void]$files.Add([ordered]@{ nhan = [string](Get-Prop $t 'nhan' 'File'); duongDan = $p }) }
    }
    foreach ($pair in @(@('baoCao', 'Báo cáo'), @('thuMucSaoLuu', 'Thư mục sao lưu'), @('nhatKy', 'Nhật ký'))) {
        $p = Get-Prop $r $pair[0] $null
        if ($p -is [string] -and $p -and [IO.Path]::IsPathRooted($p) -and -not @($files | Where-Object { $_.duongDan -eq $p }).Count) {
            [void]$files.Add([ordered]@{ nhan = $pair[1]; duongDan = $p })
        }
    }

    return [ordered]@{
        path = $fi.FullName; file = $fi.Name; modified = (Get-IsoTime $fi.LastWriteTime)
        chuan = [string](Get-Prop $r 'chuan' ''); congCu = [string](Get-Prop $r 'congCu' (Get-Prop $r 'cong_cu' ''))
        cheDo = [string](Get-Prop $r 'cheDo' ''); phienBan = [string](Get-Prop $r 'phienBan' (Get-Prop $r 'phien_ban' ''))
        may = [string](Get-Prop $r 'may' ''); taiKhoan = [string](Get-Prop $r 'taiKhoan' (Get-Prop $r 'nguoiDung' ''))
        batDau = [string](Get-Prop $r 'batDau' ''); ketThuc = [string](Get-Prop $r 'ketThuc' '')
        maThoat = $code; trangThai = $state; chayThu = [bool](Get-Prop $r 'chayThu' $false)
        ma = [string](Get-Prop $r 'ma' ''); thongDiep = (ConvertTo-ResultText (Get-Prop $r 'thongDiep' '') 600)
        tomTat = $tomTat; phatHien = $items.ToArray(); boBot = [Math]::Max(0, $total - $items.Count); tep = $files.ToArray()
    }
}

function Get-RunResultSummary {
    # Phần ghi vào Lịch sử: đủ để hiện một dòng "tìm thấy gì", chi tiết đọc lại từ file khi bấm Xem.
    param([Parameter(Mandatory)]$Result)
    return [ordered]@{
        path = $Result.path; trangThai = $Result.trangThai; maThoat = $Result.maThoat; ma = $Result.ma
        thongDiep = $Result.thongDiep; chayThu = $Result.chayThu; tomTat = $Result.tomTat
    }
}

# ---------------------------------------------------------------- máy chủ giao diện web của công cụ (webServer)
function Read-ToolServerState {
    # Đọc file trạng thái của máy chủ; trả $null nếu không có hoặc không hợp lệ (URL chỉ nhận 127.0.0.1 đúng cổng).
    param([Parameter(Mandatory)]$Tool, [Parameter(Mandatory)]$Action)
    $spec = Get-Prop $Action 'webServer' $null
    if (-not $spec) { return $null }
    $file = Expand-HubPath -Path ([string](Get-Prop $spec 'stateFile' '')) -BaseDir $Tool.dir
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $null }
    try { $st = Read-JsonFile $file } catch { return $null }
    $app = [string](Get-Prop $spec 'app' '')
    $port = 0; $procId = 0
    [void][int]::TryParse([string](Get-Prop $st 'port' ''), [ref]$port)
    [void][int]::TryParse([string](Get-Prop $st 'pid' ''), [ref]$procId)
    $url = [string](Get-Prop $st 'url' '')
    if (-not $app -or [string](Get-Prop $st 'app' '') -ne $app -or $port -le 0 -or $port -gt 65535 -or $procId -le 0) { return $null }
    if ($url -notmatch ('^http://127\.0\.0\.1:' + $port + '/[^\s"<>]*$')) { return $null }
    return [pscustomobject]@{
        App = $app; Port = $port; Pid = $procId; Url = $url; Token = [string](Get-Prop $st 'token' '')
        Started = [string](Get-Prop $st 'started' ''); Version = [string](Get-Prop $st 'version' '')
    }
}

function Invoke-ToolServerRequest {
    param([int]$Port, [string]$Path, [string]$Method = 'GET', [string]$Token = '', [int]$TimeoutMs = 1500)
    $req = [Net.HttpWebRequest]::Create("http://127.0.0.1:$Port$Path")
    $req.Proxy = $null; $req.Timeout = $TimeoutMs; $req.ReadWriteTimeout = $TimeoutMs; $req.Method = $Method; $req.KeepAlive = $false
    if ($Token) { $req.Headers.Add('X-Token', $Token) }
    # POST không kèm thân: máy chủ trả lời rồi tắt ngay, còn thân chưa đọc thì Windows cắt kết nối giữa lúc trạm đang ghi.
    if ($Method -eq 'POST') { $req.ContentLength = 0 }
    $status = 0; $text = ''
    try { $resp = $req.GetResponse() } catch [Net.WebException] {
        $resp = $_.Exception.Response
        if (-not $resp) { throw }
    }
    try {
        $status = [int]$resp.StatusCode
        $sr = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
        try { $text = $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $resp.Close() }
    $obj = $null
    try { $obj = $text | ConvertFrom-Json } catch { }
    return [pscustomobject]@{ Status = $status; Body = $obj }
}

function Get-ToolServer {
    # Máy chủ giao diện của action còn chạy không: file trạng thái hợp lệ, tiến trình còn, GET /api/health trả đúng
    # app và pid. Không trả URL (có mã thông hành) cho giao diện; trạm tự mở URL.
    param([Parameter(Mandatory)]$Tool, [Parameter(Mandatory)]$Action)
    $res = [ordered]@{ running = $false; port = 0; pid = 0; startedAt = ''; version = ''; busy = 0 }
    $st = Read-ToolServerState -Tool $Tool -Action $Action
    if (-not $st) { return $res }
    if (-not (Get-Process -Id $st.Pid -ErrorAction SilentlyContinue)) { return $res }
    try { $h = Invoke-ToolServerRequest -Port $st.Port -Path '/api/health' } catch { return $res }
    if ($h.Status -ne 200 -or [string](Get-Prop $h.Body 'app' '') -ne $st.App -or [int](Get-Prop $h.Body 'pid' 0) -ne $st.Pid) { return $res }
    $res.running = $true; $res.port = $st.Port; $res.pid = $st.Pid; $res.startedAt = $st.Started; $res.version = $st.Version
    $busy = Get-Prop $h.Body 'jobs_running' 0
    $res.busy = if ("$busy" -match '^\d+$') { [int]"$busy" } else { 0 }
    return $res
}

function Open-ToolServer {
    # Mở lại trang của máy chủ đang chạy bằng trình duyệt mặc định (như công cụ tự mở). Trả số cổng.
    param([Parameter(Mandatory)]$Tool, [Parameter(Mandatory)]$Action)
    $s = Get-ToolServer -Tool $Tool -Action $Action
    if (-not $s.running) { throw 'Giao diện không còn chạy. Bấm Chạy để mở lại.' }
    $st = Read-ToolServerState -Tool $Tool -Action $Action
    $null = Start-Process $st.Url
    return $s.port
}

function Stop-ToolServer {
    # Tắt máy chủ bằng POST /api/shutdown (kèm X-Token từ file trạng thái). Máy chủ đang bận (409) thì báo lại lời
    # của nó, không ép tắt.
    param([Parameter(Mandatory)]$Tool, [Parameter(Mandatory)]$Action)
    $s = Get-ToolServer -Tool $Tool -Action $Action
    if (-not $s.running) { return [ordered]@{ ok = $true; message = 'Giao diện đã tắt từ trước.' } }
    $st = Read-ToolServerState -Tool $Tool -Action $Action
    try { $r = Invoke-ToolServerRequest -Port $st.Port -Path '/api/shutdown' -Method 'POST' -Token $st.Token -TimeoutMs 4000 }
    catch { throw "Không gửi được lệnh tắt: $($_.Exception.Message)" }
    if ($r.Status -eq 200) { return [ordered]@{ ok = $true; message = 'Đã tắt giao diện.' } }
    $msg = [string](Get-Prop $r.Body 'error' '')
    if ($r.Status -eq 409) { return [ordered]@{ ok = $false; busy = $true; message = $(if ($msg) { $msg } else { 'Giao diện đang làm việc, chưa tắt được.' }) } }
    throw "Giao diện không nhận lệnh tắt (mã $($r.Status))$(if ($msg) { ": $msg" })."
}
