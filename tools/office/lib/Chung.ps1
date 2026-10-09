# Office - phần dùng chung: in ra màn hình kèm ghi báo cáo, hỏi người dùng, quyền Admin, thư mục kết quả, chạy lệnh ngoài.
# Mọi dòng in ra đều qua Protect-Text: chuỗi có dạng khoá sản phẩm bị che trước khi lên màn hình hay vào báo cáo, nhật ký.

$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Report = New-Object System.Collections.Generic.List[string]
$script:Findings = New-Object System.Collections.ArrayList
$script:NoPause = $false
$script:LastReport = ''
$script:ResultLevel = @{ bad = 'loi'; warn = 'canh-bao'; info = 'thong-tin'; ok = 'ok' }

# ---------------------------------------------------------------- che khoá sản phẩm
function Protect-Text {
    # Khoá sản phẩm (5 nhóm 5 ký tự) và giá trị PIDKEY="..." thành <khoá đã che>.
    param([string]$Text)
    if (-not $Text) { return $Text }
    $t = [regex]::Replace($Text, '(?i)\b[A-Z0-9]{5}(-[A-Z0-9]{5}){4}\b', '<khoá đã che>')
    return [regex]::Replace($t, '(?i)(PIDKEY\s*=\s*")[^"]*(")', '$1<khoá đã che>$2')
}

# ---------------------------------------------------------------- in ra màn hình (và báo cáo)
function Write-Out {
    param([string]$Text = '', [string]$Color = '')
    $Text = Protect-Text $Text
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
    # Điều tìm thấy khi kiểm tra, gom lại cho phần kết luận. Fix: chế độ nên chạy để xử lý (trống nếu phải làm tay).
    # Ma: mã cố định (CHU_HOA) cho Trạm Tool.
    param([string]$Ma, [ValidateSet('bad', 'warn', 'info')][string]$Level, [string]$Text, [string]$Fix = '', [string]$Hint = '')
    [void]$script:Findings.Add([pscustomobject]@{ Ma = $Ma; Level = $Level; Text = $Text; Fix = $Fix; Hint = $Hint })
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

function Confirm-Strong {
    # Xác nhận việc không hoàn tác được: phải gõ đúng cụm từ, Enter là huỷ.
    param([string]$Phrase = 'DONG Y')
    if (Test-NoInput) { return $false }
    $a = ([string](Read-Host "  Gõ $Phrase để bắt đầu (Enter để huỷ)")).Trim()
    return ($a -eq $Phrase)
}

function Close-OfficeApps {
    # Đóng ứng dụng Office trước khi gỡ, cài, trả lại. Không tự đóng khi chưa hỏi. Trả 'ok' hoặc 'cancel'.
    # [D] chỉ đóng cửa sổ trong phiên của người đang chạy (Office tự hỏi lưu file); ứng dụng của người dùng khác
    # đang đăng nhập chỉ đóng được bằng [K].
    param([string]$Why = 'gỡ Office')
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    while ($true) {
        $run = @(Get-OfficeRunning)
        if (-not $run.Count) { return 'ok' }
        $names = foreach ($r in $run) {
            $other = @($r.Processes | Where-Object { $_.SessionId -ne $session }).Count
            $t = if ($r.Count -gt 1) { "$($r.Label) ($($r.Count))" } else { $r.Label }
            if ($other) { $t += ' (có của người dùng khác đang đăng nhập)' }
            $t
        }
        Write-Warn ('Đang mở: {0}.' -f ($names -join ', '))
        Write-Line "Cần đóng hết trước khi $Why. Lưu bài đang làm rồi chọn:"
        Write-Line '  T  Tôi đã đóng hết, kiểm tra lại'
        Write-Line '  D  Đóng giúp (Office hỏi lưu file chưa lưu)'
        Write-Line '  K  Buộc đóng ngay (mất phần chưa lưu)'
        Write-Line '  H  Huỷ'
        $c = Read-Choice 'Chọn T, D, K hoặc H' @('T', 'D', 'K', 'H') 'H'
        if ($c -eq 'H') { return 'cancel' }
        if ($c -eq 'D') {
            foreach ($r in $run) {
                foreach ($p in $r.Processes) {
                    if ($p.SessionId -ne $session) { continue }
                    try { if ($p.MainWindowHandle -ne [IntPtr]::Zero) { [void]$p.CloseMainWindow() } else { $p.Kill() } } catch { }
                }
            }
            # Chờ người dùng trả lời hộp "Lưu thay đổi?" (tối đa 60 giây) rồi hỏi lại nếu còn.
            for ($i = 0; $i -lt 30; $i++) {
                $mine = @(Get-OfficeRunning | ForEach-Object { $_.Processes } | Where-Object { $_.SessionId -eq $session })
                if (-not $mine.Count) { break }
                Start-Sleep -Seconds 2
            }
        }
        if ($c -eq 'K') {
            foreach ($r in $run) { foreach ($p in $r.Processes) { try { $p.Kill() } catch { } } }
            Start-Sleep -Seconds 2
        }
    }
}

function Wait-Close {
    param([string]$Text = 'Bấm Enter để đóng cửa sổ')
    if ($script:NoPause -or (Test-NoInput)) { return }
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

function Test-SameUser {
    # $true khi cửa sổ này chạy bằng chính tài khoản đang dùng máy (thiết lập, giấy phép từng người đọc đúng chỗ).
    $console = Get-ConsoleUser
    return (-not $console -or $console -ieq (Get-CurrentUser))
}

function Get-ResultDir {
    # ket_qua\<Sub> trong thư mục công cụ; thư mục công cụ không ghi được (vd chạy từ chỗ chỉ đọc) thì ra Desktop.
    # OFFICE_KET_QUA: thư mục khác thay cho ket_qua (bài thử).
    param([string]$Sub = '')
    $d = if ($env:OFFICE_KET_QUA) { $env:OFFICE_KET_QUA } else { Join-Path $script:ToolDir 'ket_qua' }
    if ($Sub) { $d = Join-Path $d $Sub }
    try {
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop) }
        return $d
    } catch {
        $d = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Office_ket_qua'
        if ($Sub) { $d = Join-Path $d $Sub }
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
        $script:LastReport = $path
        return $path
    } catch {
        Write-Host "  Không lưu được báo cáo: $($_.Exception.Message)" -ForegroundColor Red
        return ''
    }
}

function Save-RunResult {
    # Ghi ket_qua\KetQua_Office_<chế độ>_<máy>_<giờ>.json theo chuẩn tramtool.ketqua/1: Trạm Tool hiện từng phát hiện
    # kèm nút chạy chế độ sửa. Mọi chữ qua Protect-Text như báo cáo. Ghi lỗi thì chỉ cảnh báo, không đổi mã thoát.
    # Gỡ, cài, kích hoạt, trả lại không gom phát hiện: chưa xong thì tóm các dòng [X], [!] đã in thành một mục.
    param([string]$CheDo, [int]$Code, [datetime]$Start, [bool]$DryRun = $false, [object[]]$Files = @())
    $list = @($script:Findings)
    if ($CheDo -ne 'kiem-tra' -and $Code -in 1, 2, 3 -and -not @($list | Where-Object { $_.Level -eq 'bad' }).Count) {
        $lines = @($script:Report | Where-Object { $_ -match '^\s*\[(X|!)\]\s' } | ForEach-Object { ($_ -replace '^\s*\[(X|!)\]\s+', '').Trim() } | Select-Object -Last 8)
        $first = @($script:Report | Where-Object { $_ -match '^\s*\[X\]\s' } | Select-Object -First 1)
        $pick = @{ 1 = @('CHUA_XONG', 'bad', 'Chưa làm xong, xem nhật ký.'); 2 = @('THIEU_DIEU_KIEN', 'warn', 'Chưa làm: thiếu điều kiện.'); 3 = @('LAM_DUOC_MOT_PHAN', 'warn', 'Mới làm được một phần, xem nhật ký.') }[$Code]
        $title = if ($first.Count) { ($first[0] -replace '^\s*\[X\]\s+', '').Trim() } else { $pick[2] }
        $list += [pscustomobject]@{
            Ma = $pick[0]; Level = $pick[1]; Text = $title; ChiTiet = (@($lines | Where-Object { $_ -ne $title }) -join "`n")
            Fix = 'kiem-tra'; Hint = 'Kiểm tra lại để biết Office, giấy phép, bộ cài mẫu đang thế nào.'
        }
    }
    $rank = @{ loi = 0; 'canh-bao' = 1; 'thong-tin' = 2; ok = 3 }
    $i = 0
    $items = @(foreach ($f in $list) {
            $muc = $script:ResultLevel[[string]$f.Level]
            $o = [ordered]@{ ma = [string]$f.Ma; mucDo = $muc; tieuDe = (Protect-Text ([string]$f.Text)); chiTiet = (Protect-Text ([string]$f.ChiTiet)); cachSua = (Protect-Text ([string]$f.Hint)) }
            if ($f.Fix -and $script:Modes -and $script:Modes.Contains([string]$f.Fix)) {
                $o.cachSua = ('Chạy "{0}".{1}' -f $script:Modes[$f.Fix].Label, $(if ($o.cachSua) { ' ' + $o.cachSua } else { '' }))
                $o['chayTiep'] = [ordered]@{ congCu = 'office'; action = [string]$f.Fix }
            }
            [pscustomobject]@{ F = $o; L = $rank[$muc]; I = $i++ }
        })
    $sorted = @($items | Sort-Object L, I | ForEach-Object { $_.F })
    $n = @{}
    foreach ($k in 'loi', 'canh-bao', 'thong-tin') { $n[$k] = @($sorted | Where-Object { $_.mucDo -eq $k }).Count }
    $label = if ($script:Modes -and $script:Modes.Contains($CheDo)) { $script:Modes[$CheDo].Label } else { $CheDo }
    $msg = if ($DryRun -and $Code -eq 0) { 'Chạy thử: chỉ xem việc sẽ làm, máy chưa thay đổi gì.' }
    elseif ($CheDo -eq 'kiem-tra' -and $Code -eq 0) {
        if ($n['loi'] + $n['canh-bao']) { 'Có {0} lỗi, {1} cảnh báo; xem chi tiết.' -f $n['loi'], $n['canh-bao'] } else { 'Không thấy vấn đề Office nào cần xử lý.' }
    } else {
        switch ($Code) {
            0 { '{0}: xong.' -f $label }
            2 { '{0}: chưa làm (thiếu quyền Admin, mẫu hỏng hoặc chưa có bản sao lưu).' -f $label }
            3 { '{0}: làm được một phần, xem chi tiết.' -f $label }
            default { '{0}: lỗi, xem chi tiết.' -f $label }
        }
    }
    $st = @{ 0 = 'xong'; 2 = 'thieu-dieu-kien'; 3 = 'mot-phan' }
    $tep = @(foreach ($f in @($Files)) { if ($f -and $f.duongDan) { [ordered]@{ nhan = [string]$f.nhan; duongDan = [string]$f.duongDan } } })
    $r = [ordered]@{
        chuan = 'tramtool.ketqua/1'; congCu = 'office'; cheDo = $CheDo; phienBan = $script:ToolVersion
        may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
        batDau = $Start.ToString('s'); ketThuc = (Get-Date).ToString('s')
        maThoat = $Code; trangThai = $(if ($st.ContainsKey($Code)) { $st[$Code] } else { 'loi' })
        chayThu = $DryRun
        ma = $(if ($n['loi']) { 'CO_LOI' } elseif ($n['canh-bao']) { 'CO_CANH_BAO' } else { 'KHONG_CO_LOI' })
        thongDiep = $msg
        tomTat = [ordered]@{ loi = $n['loi']; canhBao = $n['canh-bao']; thongTin = $n['thong-tin'] }
        phatHien = $sorted
        tep = $tep
    }
    try {
        $name = (($CheDo -split '-') | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join ''
        $f = Join-Path (Get-ResultDir) ('KetQua_Office_{0}_{1}_{2:yyyyMMdd_HHmmss}.json' -f $name, $env:COMPUTERNAME, $Start)
        [IO.File]::WriteAllText("$f.tmp", ($r | ConvertTo-Json -Depth 8), $script:Utf8NoBom)
        Move-Item -LiteralPath "$f.tmp" -Destination $f -Force
        Write-Host "  Kết quả cho Trạm Tool: $f" -ForegroundColor DarkGray
        return $f
    } catch {
        Write-Host "  Không ghi được file kết quả cho Trạm Tool: $($_.Exception.Message.Trim())" -ForegroundColor Yellow
        return ''
    }
}

function Get-RegValue {
    # Một giá trị registry, $null khi khoá hay giá trị chưa có. Chỉ đọc đúng tên được hỏi (không đọc cả khoá).
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $key = Get-Item -LiteralPath $Path
    if ($key.GetValueNames() -notcontains $Name) { return $null }
    return $key.GetValue($Name)
}

function Get-FolderSize {
    # Tổng dung lượng và số file của một thư mục (không đi vào junction). $Exclude: tên thư mục con bỏ qua.
    param([string]$Path, [string[]]$Exclude = @())
    $r = [pscustomobject]@{ Files = 0; Bytes = [int64]0 }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $r }
    $stack = New-Object System.Collections.Stack
    $stack.Push((Get-Item -LiteralPath $Path -Force))
    while ($stack.Count) {
        $d = $stack.Pop()
        try { $items = $d.GetFileSystemInfos() } catch { continue }
        foreach ($i in $items) {
            if ($i -is [IO.DirectoryInfo]) {
                if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($Exclude -contains $i.Name) { continue }
                $stack.Push($i)
            } else { $r.Files++; $r.Bytes += $i.Length }
        }
    }
    return $r
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

function Wait-ProcessVisible {
    # Chờ tiến trình xong, cứ 30 giây in thời gian đã chờ để người dùng biết công cụ vẫn chạy.
    # Trả mã thoát; $null khi quá $TimeoutMin phút (tiến trình vẫn chạy tiếp).
    param([Diagnostics.Process]$Process, [string]$What, [int]$TimeoutMin = 120)
    # Giữ handle ngay từ đầu: thiếu bước này Start-Process -PassThru hay trả ExitCode rỗng sau khi tiến trình kết thúc.
    try { [void]$Process.Handle } catch { }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $Process.WaitForExit(30000)) {
        Write-Host ('       {0}: đã {1} phút {2:00} giây...' -f $What, [Math]::Floor($sw.Elapsed.TotalMinutes), $sw.Elapsed.Seconds) -ForegroundColor DarkGray
        if ($sw.Elapsed.TotalMinutes -ge $TimeoutMin) { return $null }
    }
    $Process.WaitForExit()
    try { $code = $Process.ExitCode } catch { $code = $null }
    if ($null -eq $code) { return -1 }   # không đọc được mã: coi như lỗi, bước kiểm tra lại sẽ quyết định
    return [int]$code
}

# ---------------------------------------------------------------- định dạng
function Format-ErrorCode {
    # Mã nhỏ in số thập phân; mã kiểu HRESULT (âm hoặc lớn) in dạng 0xC004C008.
    param($Code)
    if ($null -eq $Code) { return '?' }
    $c = [int64]$Code
    if ($c -ge 0 -and $c -lt 65536) { return [string]$c }
    if ($c -lt 0) { $c += 4294967296 }
    return ('0x{0:X8}' -f $c)
}

function Format-Size {
    param($Bytes)
    $b = [double]$Bytes
    if ($b -ge 1GB) { return ('{0:N1} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0:N0} MB' -f ($b / 1MB)) }
    return ('{0:N0} KB' -f [Math]::Ceiling($b / 1KB))
}

function Get-ErrorCode {
    # Mã lỗi từ lỗi PowerShell: Win32Exception, CimException (HRESULT), hoặc HResult của exception.
    param($ErrorRecord)
    $e = $ErrorRecord.Exception
    while ($e) {
        if ($e -is [ComponentModel.Win32Exception]) { return [int64]$e.NativeErrorCode }
        $e = $e.InnerException
    }
    if ([string]$ErrorRecord.FullyQualifiedErrorId -match 'HRESULT 0x([0-9a-fA-F]{8})') { return [Convert]::ToInt64($Matches[1], 16) }
    return [int64]$ErrorRecord.Exception.HResult
}
