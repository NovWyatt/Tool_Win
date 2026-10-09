# Dọn ổ C - phần dùng chung: in ra màn hình kèm ghi báo cáo, hỏi người dùng, đóng ứng dụng, quyền Admin, thư mục kết
# quả, chạy lệnh ngoài, định dạng dung lượng.

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
    # Điều tìm thấy khi kiểm tra, gom lại cho phần kết luận. Ma: mã cố định (CHU_HOA) cho file kết quả của Trạm Tool.
    # Fix: chế độ nên chạy (trống nếu phải làm tay). Bytes: dung lượng lấy lại được (để xếp việc lợi nhiều lên trước).
    # Quiet: chỉ ghi cho phần kết luận, không in ngay. ChiKetQua: chỉ ghi vào file kết quả (không in, không vào kết luận).
    param([string]$Ma, [ValidateSet('bad', 'warn', 'info', 'ok')][string]$Level, [string]$Text, [string]$Fix = '', [string]$Hint = '', [int64]$Bytes = 0, [switch]$Quiet, [switch]$ChiKetQua)
    [void]$script:Findings.Add([pscustomobject]@{ Ma = $Ma; Level = $Level; Text = $Text; Fix = $Fix; Hint = $Hint; Bytes = $Bytes; ChiKetQua = [bool]$ChiKetQua })
    if ($Quiet -or $ChiKetQua) { return }
    switch ($Level) { 'bad' { Write-Bad $Text } 'warn' { Write-Warn $Text } default { Write-Info $Text } }
    if ($Hint) { Write-Sub $Hint }
}

# ---------------------------------------------------------------- hỏi người dùng
# Không có bàn phím (chạy tự động, stdin bị chuyển hướng) thì trả giá trị an toàn thay vì treo.
function Test-NoInput { return [Console]::IsInputRedirected }

function Read-Text {
    param([string]$Prompt, [string]$Default = '')
    if (Test-NoInput) { return $Default }
    $a = ([string](Read-Host "  $Prompt")).Trim()
    if (-not $a) { return $Default }
    return $a
}

function Read-YesNo {
    param([string]$Question, [bool]$Default = $false)
    if (Test-NoInput) { return $Default }
    $hint = if ($Default) { '[C/k]' } else { '[c/K]' }
    while ($true) {
        $a = ([string](Read-Host "  $Question $hint")).Trim().ToLowerInvariant()
        if (-not $a) { return $Default }
        if ($a -in 'c', 'co', 'có', 'y', 'yes') { return $true }
        if ($a -in 'k', 'khong', 'không', 'n', 'no') { return $false }
        Write-Host '  Gõ C (có) hoặc K (không).' -ForegroundColor Yellow
    }
}

function Read-Choice {
    # Hỏi đến khi gõ đúng một trong $Keys; không có lựa chọn mặc định để khỏi lỡ tay bấm Enter.
    param([string]$Prompt, [string[]]$Keys, [string]$Fallback)
    if (Test-NoInput) { return $Fallback }
    while ($true) {
        $a = ([string](Read-Host "  $Prompt")).Trim().ToUpperInvariant()
        if ($Keys -contains $a) { return $a }
        Write-Host ('  Gõ {0} rồi Enter.' -f ($Keys -join ', ')) -ForegroundColor Yellow
    }
}

function Wait-Close {
    param([string]$Text = 'Bấm Enter để đóng cửa sổ')
    if ($script:NoPause -or (Test-NoInput)) { return }
    Write-Host ''
    [void](Read-Host "  $Text")
}

# ---------------------------------------------------------------- ứng dụng đang mở
function Get-RunningApps {
    # Ứng dụng đang chạy trong danh sách $Apps (@{ Label; Names; PathLike }), chỉ trong phiên của người đang chạy công
    # cụ (bộ nhớ đệm dọn ở đây là của người này). Trả @{ Label; Processes; Windows (số cửa sổ) }.
    param($Apps)
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $out = foreach ($a in @($Apps)) {
        $procs = @(Get-Process -Name $a.Names -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session })
        if ($a.PathLike) { $procs = @($procs | Where-Object { try { [string]$_.Path -like $a.PathLike } catch { $false } }) }
        if (-not $procs.Count) { continue }
        [pscustomobject]@{ Label = $a.Label; Processes = $procs; Windows = @($procs | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }).Count }
    }
    return @($out)
}

function Close-Apps {
    # Hỏi đóng các ứng dụng đang mở trước khi dọn bộ nhớ đệm của chúng. Không tự đóng khi chưa hỏi.
    # T: đã đóng, kiểm tra lại. D: đóng giúp (đóng cửa sổ như bấm X; tiến trình chạy nền không cửa sổ thì dừng).
    # B: bỏ qua, không dọn phần của ứng dụng còn mở. Trả tên các ứng dụng vẫn còn mở (bỏ qua chúng).
    param($Apps, [string]$Why = 'dọn bộ nhớ đệm')
    while ($true) {
        $run = @(Get-RunningApps $Apps)
        if (-not $run.Count) { return @() }
        $names = foreach ($r in $run) { if ($r.Windows) { $r.Label } else { "$($r.Label) (chạy nền, không có cửa sổ)" } }
        Write-Warn ('Đang mở: {0}.' -f ($names -join ', '))
        Write-Line "Cần đóng trước khi $Why. Chọn:"
        Write-Line '  T  Tôi đã đóng, kiểm tra lại'
        Write-Line '  D  Đóng giúp (như bấm nút X; trình duyệt mở lại các thẻ khi chạy lại nếu đã bật "tiếp tục từ chỗ cũ")'
        Write-Line '  B  Bỏ qua, không dọn phần của ứng dụng đang mở'
        $c = Read-Choice 'Chọn T, D hoặc B' @('T', 'D', 'B') 'B'
        if ($c -eq 'B') { return @($run | ForEach-Object { $_.Label }) }
        if ($c -eq 'D') {
            foreach ($r in $run) {
                foreach ($p in $r.Processes) {
                    try { if ($p.MainWindowHandle -ne [IntPtr]::Zero) { [void]$p.CloseMainWindow() } else { $p.Kill() } } catch { }
                }
            }
            # Chờ ứng dụng tự đóng (hộp hỏi "đóng tất cả thẻ?", lưu phiên) tối đa 30 giây, rồi dừng tiến trình nền còn sót.
            for ($i = 0; $i -lt 15; $i++) {
                if (-not @(Get-RunningApps $Apps).Count) { break }
                Start-Sleep -Seconds 2
            }
            foreach ($r in @(Get-RunningApps $Apps)) {
                foreach ($p in $r.Processes) { if ($p.MainWindowHandle -eq [IntPtr]::Zero) { try { $p.Kill() } catch { } } }
            }
        }
    }
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

function Test-SameUser {
    # $true khi cửa sổ này chạy bằng chính tài khoản đang dùng máy (TEMP, bộ nhớ đệm là của đúng người đó).
    $console = Get-ConsoleUser
    return (-not $console -or $console -ieq (Get-CurrentUser))
}

function Get-ResultDir {
    # ket_qua trong thư mục công cụ; thư mục công cụ không ghi được (vd chạy từ chỗ chỉ đọc) thì ra Desktop.
    # DOC_KET_QUA: thư mục khác (bài thử).
    $d = if ($env:DOC_KET_QUA) { $env:DOC_KET_QUA } else { Join-Path $script:ToolDir 'ket_qua' }
    try {
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop) }
        return $d
    } catch {
        $d = Join-Path ([Environment]::GetFolderPath('Desktop')) 'DonOC_ket_qua'
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
        return $d
    }
}

function Save-Report {
    # Ghi các dòng đã in ra file (UTF-8 có BOM để Notepad đọc đúng dấu). Trả đường dẫn, '' khi không ghi được.
    param([string]$Prefix, [datetime]$Started)
    $path = Join-Path (Get-ResultDir) ('{0}_{1}_{2:yyyyMMdd_HHmmss}.txt' -f $Prefix, $env:COMPUTERNAME, $Started)
    try {
        [IO.File]::WriteAllLines($path, $script:Report, $script:Utf8Bom)
        Write-Host ''
        Write-Host "  Đã lưu: $path" -ForegroundColor Green
        return $path
    } catch {
        Write-Host "  Không lưu được báo cáo: $($_.Exception.Message)" -ForegroundColor Red
        return ''
    }
}

# ---------------------------------------------------------------- kết quả cho Trạm Tool
$script:ResultLevel = @{ bad = 'loi'; warn = 'canh-bao'; info = 'thong-tin'; ok = 'ok' }

function Save-RunResult {
    # Ghi ket_qua\KetQua_DonOC_<chế độ>_<máy>_<giờ>.json theo chuẩn tramtool.ketqua/1: Trạm Tool hiện từng phát hiện
    # kèm nút chạy chế độ dọn. Trong cùng mức, việc lấy lại nhiều chỗ lên trước. Ghi lỗi thì chỉ cảnh báo, không đổi mã
    # thoát. Trả đường dẫn file (hoặc '').
    param([string]$CheDo, [int]$Code, [datetime]$Start, [string]$Message = '', [bool]$DryRun = $false, [object[]]$Files = @())
    $rank = @{ loi = 0; 'canh-bao' = 1; 'thong-tin' = 2; ok = 3 }
    $i = 0
    $items = @(foreach ($f in @($script:Findings)) {
            $muc = $script:ResultLevel[[string]$f.Level]
            $o = [ordered]@{ ma = [string]$f.Ma; mucDo = $muc; tieuDe = [string]$f.Text; chiTiet = ''; cachSua = [string]$f.Hint }
            if ($f.Fix -and $script:Modes -and $script:Modes.Contains([string]$f.Fix)) {
                $o.cachSua = ('Chạy "{0}".{1}' -f $script:Modes[$f.Fix].Label, $(if ($f.Hint) { ' ' + $f.Hint } else { '' }))
                $o['chayTiep'] = [ordered]@{ congCu = 'don-o-c'; action = [string]$f.Fix }
            }
            [pscustomobject]@{ F = $o; L = $rank[$muc]; B = - [int64]$f.Bytes; I = $i++ }
        })
    $sorted = @($items | Sort-Object L, B, I | ForEach-Object { $_.F })
    $n = @{}
    foreach ($k in 'loi', 'canh-bao', 'thong-tin') { $n[$k] = @($sorted | Where-Object { $_.mucDo -eq $k }).Count }
    if (-not $Message) { $Message = if ($n['loi'] + $n['canh-bao']) { 'Có {0} lỗi, {1} cảnh báo; xem chi tiết.' -f $n['loi'], $n['canh-bao'] } else { 'Xong, không có lỗi.' } }
    $r = [ordered]@{
        chuan = 'tramtool.ketqua/1'; congCu = 'don-o-c'; cheDo = $CheDo; phienBan = $script:ToolVersion
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
        $f = Join-Path (Get-ResultDir) ('KetQua_DonOC_{0}_{1}_{2:yyyyMMdd_HHmmss}.json' -f ((($CheDo -split '-') | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ''), $env:COMPUTERNAME, $Start)
        [IO.File]::WriteAllText("$f.tmp", ($r | ConvertTo-Json -Depth 8), $script:Utf8NoBom)
        Move-Item -LiteralPath "$f.tmp" -Destination $f -Force
        return $f
    } catch { Write-Host "  Không ghi được file kết quả cho Trạm Tool: $($_.Exception.Message.Trim())" -ForegroundColor Yellow; return '' }
}

function Get-RegValue {
    # Một giá trị registry, $null khi khoá hay giá trị chưa có.
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

# ---------------------------------------------------------------- ổ đĩa, định dạng
function Get-DriveInfo {
    # Dung lượng ổ Windows: @{ Name; Size; Free } (byte). $null khi không đọc được.
    try {
        $d = [IO.DriveInfo]::new($env:SystemDrive)
        return [pscustomobject]@{ Name = $d.Name.TrimEnd('\'); Size = [int64]$d.TotalSize; Free = [int64]$d.AvailableFreeSpace }
    } catch { return $null }
}

function Format-Size {
    param($Bytes)
    $b = [double]$Bytes
    if ($b -ge 1GB) { return ('{0:N1} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N0} MB' -f ($b / 1MB)) }
    if ($b -le 0) { return '0 KB' }
    return ('{0:N0} KB' -f [Math]::Ceiling($b / 1KB))
}

function Format-ErrorCode {
    # Mã nhỏ in số thập phân; mã kiểu HRESULT (âm hoặc lớn) in dạng 0x800F0818.
    param($Code)
    if ($null -eq $Code) { return '?' }
    $c = [int64]$Code
    if ($c -ge 0 -and $c -lt 65536) { return [string]$c }
    if ($c -lt 0) { $c += 4294967296 }
    return ('0x{0:X8}' -f $c)
}
