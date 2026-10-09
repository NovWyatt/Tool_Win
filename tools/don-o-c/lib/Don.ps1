# Dọn ổ C - các chế độ dọn: xem trước, hỏi, rồi mới xoá. Chạy thử thì dừng sau phần xem trước.

function Show-DriveLine {
    param($Drive, [string]$Prefix = 'Ổ')
    if (-not $Drive) { return }
    $pct = if ($Drive.Size) { [Math]::Round(100 * $Drive.Free / $Drive.Size) } else { 0 }
    Write-Line ('{0} {1} còn trống {2} trên {3} ({4}%).' -f $Prefix, $Drive.Name, (Format-Size $Drive.Free), (Format-Size $Drive.Size), $pct)
}

function Show-ItemTable {
    # In từng mục và dung lượng dọn được. Trả tổng byte dọn được.
    param($Results, [int]$Days)
    $sum = [int64]0
    foreach ($r in $Results) {
        $i = $r.Item
        if ($i.Skip) { Write-Line $i.Label; Write-Sub ('Bỏ qua: ' + $i.Skip); continue }
        if ($r.Error) { Write-Warn ('{0}: {1}' -f $i.Label, $r.Error); continue }
        if ($r.Missing) { continue }
        if ($r.Denied -and -not $r.TotalFiles -and -not $r.Total -and -not (Test-IsAdmin)) {
            Write-Line ('{0,-62} {1,9}' -f $i.Label, '?')
            Write-Sub 'Cần quyền Admin để đo.'
            continue
        }
        Write-Line ('{0,-62} {1,9}' -f $i.Label, (Format-Size $r.Bytes))
        if ($i.Kind -ne 'do') {
            $what = if ($i.All) { '{0:N0} file' -f $r.Files } else { '{0:N0} file cũ hơn {1} ngày, trong tổng {2}' -f $r.Files, $Days, (Format-Size $r.Total) }
            if ($r.Partial) { $what += ' (chưa đếm hết)' }
            Write-Sub $what
        }
        if ($i.Note) { Write-Sub $i.Note }
        $sum += $r.Bytes
    }
    return $sum
}

function Measure-Items {
    param($Items, [datetime]$Cutoff, [int]$Seconds = 0)
    return @(foreach ($i in $Items) { Measure-CleanItem $i $Cutoff $Seconds })
}

function Invoke-Cleanup {
    # Dùng chung cho dọn của tôi và dọn hệ thống: đo, in, hỏi C/K (không có mặc định), hỏi đóng trình duyệt, xoá.
    # Trả 0 xong, 3 có mục lỗi, 1223 người dùng thôi.
    param($Items, [int]$Days, [switch]$DryRun)
    $cutoff = (Get-Date).AddDays(-$Days)
    $before = Get-DriveInfo
    Show-DriveLine $before
    Write-Head 'Sẽ dọn'
    Write-Host '  Đang đo...' -ForegroundColor DarkGray
    $res = Measure-Items $Items $cutoff
    $sum = Show-ItemTable $res $Days
    Write-Out ''
    Write-Line ('Tổng dọn được: {0}' -f (Format-Size $sum))
    $todo = @($res | Where-Object { -not $_.Item.Skip -and -not $_.Missing -and -not $_.Error -and $_.Bytes -gt 0 })
    if (-not $todo.Count) { Write-Ok 'Không có gì cần dọn.'; Add-Finding -Ma 'KHONG_CO_GI_DE_DON' ok 'Không có gì cần dọn.' -ChiKetQua; return 0 }
    $apps = @($todo | Where-Object { $_.Item.App } | ForEach-Object { $_.Item.App })
    if ($DryRun) {
        $open = @(Get-RunningApps $apps)
        if ($open.Count) { Write-Info ('Đang mở {0}: khi dọn thật, công cụ hỏi đóng trước (hoặc bỏ qua phần của trình duyệt đó).' -f (($open | ForEach-Object { $_.Label }) -join ', ')) }
        Write-Info 'Chạy thử: không xoá gì.'
        Add-Finding -Ma 'DON_DUOC' info ('Chạy thử: dọn được {0} ({1} mục).' -f (Format-Size $sum), $todo.Count) -Bytes $sum -ChiKetQua
        return 0
    }
    Write-Out ''
    $c = Read-Choice ('Dọn {0}? Gõ C để dọn, K để thôi' -f (Format-Size $sum)) @('C', 'K') 'K'
    if ($c -ne 'C') { Write-Warn 'Đã thôi, chưa xoá gì.'; return 1223 }
    Write-Out ('Đã chọn dọn lúc {0:HH:mm:ss}.' -f (Get-Date))
    $stillOpen = @()
    if ($apps.Count) { $stillOpen = @(Close-Apps $apps 'dọn bộ nhớ đệm của trình duyệt') }

    Write-Head 'Đang dọn'
    $freed = [int64]0; $errors = 0
    foreach ($r in $todo) {
        $i = $r.Item
        if ($i.App -and $stillOpen -contains $i.App.Label) { Write-Warn ('{0}: bỏ qua vì {1} còn mở.' -f $i.Label, $i.App.Label); continue }
        $x = Invoke-CleanItem $i $cutoff
        if ($x.Error) { Write-Bad ('{0}: {1}' -f $i.Label, $x.Error); $errors++; Add-Finding -Ma 'DON_LOI' bad ('{0}: {1}' -f $i.Label, $x.Error) -ChiKetQua }
        if ($x.Bytes -or -not $x.Error) {
            $files = if ($i.Kind -eq 'do') { '' } else { ' ({0:N0} file)' -f $x.Files }
            Write-Ok ('{0}: đã dọn {1}{2}.' -f $i.Label, (Format-Size $x.Bytes), $files)
        }
        if ($x.Locked) {
            Write-Sub ('{0:N0} file đang được dùng ({1}) để lại; thường dọn được sau khi khởi động lại máy.' -f $x.Locked, (Format-Size $x.LockedBytes))
            Add-Finding -Ma 'FILE_DANG_DUNG' info ('{0}: {1:N0} file đang được dùng ({2}) để lại.' -f $i.Label, $x.Locked, (Format-Size $x.LockedBytes)) -Hint 'Thường dọn được sau khi khởi động lại máy.' -Bytes $x.LockedBytes -ChiKetQua
        }
        $freed += $x.Bytes
    }
    $after = Get-DriveInfo
    Write-Head 'Kết quả'
    Write-Line ('Đã dọn {0}.' -f (Format-Size $freed))
    if ($before -and $after) { Write-Line ('Ổ {0} còn trống: trước {1}, sau {2}.' -f $after.Name, (Format-Size $before.Free), (Format-Size $after.Free)) }
    Add-Finding -Ma 'DA_DON' ok ('Đã dọn {0}.{1}' -f (Format-Size $freed), $(if ($before -and $after) { ' Ổ {0} còn trống: trước {1}, sau {2}.' -f $after.Name, (Format-Size $before.Free), (Format-Size $after.Free) } else { '' })) -Bytes $freed -ChiKetQua
    if ($errors) { return 3 }
    return 0
}

# ---------------------------------------------------------------- các chế độ
function Invoke-DonCuaToi {
    param([int]$SoNgay = 7, [switch]$DryRun)
    Write-Out 'DỌN RÁC CỦA BẠN' 'Cyan'
    Write-Out ('Máy {0}, tài khoản {1}, {2:dd/MM/yyyy HH:mm}.{3}' -f $env:COMPUTERNAME, (Get-CurrentUser), (Get-Date), $(if ($DryRun) { ' Chạy thử: chỉ xem, không xoá.' } else { '' }))
    if (-not (Test-SameUser)) {
        Write-Bad ('Cửa sổ này chạy bằng tài khoản {0}, không phải người đang dùng máy ({1}): sẽ dọn nhầm rác của {0}.' -f (Get-CurrentUser), (Get-ConsoleUser))
        Write-Sub 'Chạy lại nút này không cần quyền Admin (bấm đúp DON_O_C.bat trong tài khoản đang dùng máy).'
        Add-Finding -Ma 'SAI_TAI_KHOAN' bad ('Cửa sổ chạy bằng tài khoản {0}, không phải người đang dùng máy ({1}).' -f (Get-CurrentUser), (Get-ConsoleUser)) -Hint 'Chạy lại nút này không cần quyền Admin, trong tài khoản đang dùng máy.' -ChiKetQua
        return 2
    }
    return (Invoke-Cleanup (Get-UserItems) $SoNgay -DryRun:$DryRun)
}

function Invoke-DonHeThong {
    param([int]$SoNgay = 7, [switch]$DumpLoi, [switch]$DryRun)
    Write-Out 'DỌN RÁC CỦA WINDOWS' 'Cyan'
    Write-Out ('Máy {0}, {1:dd/MM/yyyy HH:mm}.{2}' -f $env:COMPUTERNAME, (Get-Date), $(if ($DryRun) { ' Chạy thử: chỉ xem, không xoá.' } else { '' }))
    if (-not (Test-IsAdmin)) {
        if (-not $DryRun) { Write-Bad 'Cần quyền Admin.'; Add-Finding -Ma 'CAN_QUYEN_ADMIN' bad 'Dọn rác của Windows cần quyền Admin.' -ChiKetQua; return 2 }
        Write-Info 'Không có quyền Admin: chỉ đo được phần đọc được.'
    }
    return (Invoke-Cleanup (Get-SystemItems -DumpLoi:$DumpLoi) $SoNgay -DryRun:$DryRun)
}

# ---------------------------------------------------------------- WinSxS
function Invoke-Dism {
    # Chạy DISM, lấy output (tiếng Anh để đọc được kết quả trên mọi ngôn ngữ Windows).
    param([string[]]$Arguments)
    return (Invoke-Native (Join-Path ([Environment]::GetFolderPath('System')) 'dism.exe') ($Arguments + '/English'))
}

function Start-DismLive {
    # Chạy DISM ngay trong cửa sổ này để thấy tiến độ. Trả mã thoát.
    param([string[]]$Arguments)
    $p = Start-Process -FilePath (Join-Path ([Environment]::GetFolderPath('System')) 'dism.exe') -ArgumentList (($Arguments + '/English') -join ' ') -NoNewWindow -Wait -PassThru
    return [int]$p.ExitCode
}

function Read-ComponentStoreReport {
    # Đọc kết quả /AnalyzeComponentStore (tiếng Anh).
    param([string]$Text)
    $v = @{}
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*([A-Za-z][A-Za-z ]+?)\s*:\s*(.+?)\s*$') { $v[$Matches[1]] = $Matches[2] }
    }
    $n = 0
    [void][int]::TryParse([string]$v['Number of Reclaimable Packages'], [ref]$n)
    return [pscustomobject]@{
        Actual      = [string]$v['Actual Size of Component Store']
        Shared      = [string]$v['Shared with Windows']
        Backups     = [string]$v['Backups and Disabled Features']
        Cache       = [string]$v['Cache and Temporary Data']
        LastCleanup = [string]$v['Date of Last Cleanup']
        Packages    = $n
        Recommended = ([string]$v['Component Store Cleanup Recommended'] -ieq 'Yes')
        Found       = $v.ContainsKey('Component Store Cleanup Recommended')
    }
}

function Invoke-DonWinSxS {
    param([switch]$DryRun)
    Write-Out 'DỌN KHO THÀNH PHẦN WINDOWS (WinSxS)' 'Cyan'
    Write-Out ('Máy {0}, {1:dd/MM/yyyy HH:mm}.{2}' -f $env:COMPUTERNAME, (Get-Date), $(if ($DryRun) { ' Chạy thử: chỉ phân tích, không dọn.' } else { '' }))
    if (-not (Test-IsAdmin)) {
        Write-Bad 'Phân tích kho thành phần cần quyền Admin.'
        Write-Sub 'Chạy từ Trạm Tool (tự hỏi quyền Admin), hoặc bấm đúp DON_O_C.bat rồi chọn mục này.'
        Add-Finding -Ma 'WINSXS_CAN_QUYEN_ADMIN' bad 'Phân tích kho thành phần cần quyền Admin.' -ChiKetQua
        return 2
    }
    $busy = Get-UpdateBusyReason
    if ($busy) { Write-Warn $busy; Add-Finding -Ma 'WINDOWS_DANG_CAP_NHAT' warn $busy -Hint 'Chờ Windows cài xong bản cập nhật (khởi động lại nếu được hỏi) rồi chạy lại.' -ChiKetQua; return 2 }
    Write-Head 'Phân tích'
    Write-Host '  DISM đang phân tích, 1-5 phút...' -ForegroundColor DarkGray
    $a = Invoke-Dism @('/Online', '/Cleanup-Image', '/AnalyzeComponentStore')
    $info = Read-ComponentStoreReport $a.Output
    if ($a.Code -ne 0 -or -not $info.Found) {
        Write-Bad ('DISM không phân tích được (mã {0}).' -f (Format-ErrorCode $a.Code))
        foreach ($l in @(($a.Output -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 4)) { Write-Sub $l.Trim() }
        Add-Finding -Ma 'DISM_LOI' bad ('DISM không phân tích được kho thành phần (mã {0}).' -f (Format-ErrorCode $a.Code)) -ChiKetQua
        return 1
    }
    Write-Line ('Kích thước thật của kho:            {0}' -f $info.Actual)
    Write-Sub ('Dùng chung với Windows (không dọn được): {0}' -f $info.Shared)
    Write-Sub ('Bản cũ của thành phần, tính năng đã tắt: {0}' -f $info.Backups)
    Write-Sub ('Bộ nhớ đệm, file tạm:                    {0}' -f $info.Cache)
    if ($info.LastCleanup) { Write-Line ('Lần dọn trước: {0}' -f $info.LastCleanup) }
    Write-Line ('Gói dọn được: {0}' -f $info.Packages)
    if (-not $info.Recommended) {
        Write-Ok 'Windows chưa cần dọn kho thành phần.'
        Add-Finding -Ma 'WINSXS_CHUA_CAN_DON' ok ('Windows chưa cần dọn kho thành phần (kho {0}).' -f $info.Actual) -ChiKetQua
        return 0
    }
    Write-Warn 'Windows khuyên dọn kho thành phần.'
    Write-Info 'Bản cũ của thành phần Windows bị xoá ngay (Windows tự dọn thì chờ 30 ngày). Không dùng /ResetBase nên các bản cập nhật đang cài vẫn gỡ được.'
    if ($DryRun) {
        Write-Info 'Chạy thử: chưa dọn.'
        Add-Finding -Ma 'WINSXS_NEN_DON' info ('Windows khuyên dọn kho thành phần ({0} gói dọn được, bản cũ {1}).' -f $info.Packages, $info.Backups) -Fix 'don-winsxs' -ChiKetQua
        return 0
    }
    Write-Out ''
    $c = Read-Choice 'Dọn kho thành phần (5-30 phút, đừng tắt máy)? Gõ C để dọn, K để thôi' @('C', 'K') 'K'
    if ($c -ne 'C') { Write-Warn 'Đã thôi, chưa dọn gì.'; return 1223 }
    $before = Get-DriveInfo
    Write-Head 'Đang dọn'
    $code = Start-DismLive @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
    $after = Get-DriveInfo
    Write-Head 'Kết quả'
    if ($code -ne 0 -and $code -ne 3010) {
        Write-Bad ('DISM báo lỗi {0}.' -f (Format-ErrorCode $code))
        Add-Finding -Ma 'DISM_LOI' bad ('DISM dọn kho thành phần báo lỗi {0}.' -f (Format-ErrorCode $code)) -ChiKetQua
        return 1
    }
    $done = if ($before -and $after) { 'Xong. Ổ {0} còn trống: trước {1}, sau {2}.' -f $after.Name, (Format-Size $before.Free), (Format-Size $after.Free) } else { 'Xong.' }
    Write-Ok $done
    Add-Finding -Ma 'DA_DON_WINSXS' ok ('Đã dọn kho thành phần. ' + $done) -ChiKetQua
    if ($code -eq 3010) { Write-Warn 'Khởi động lại máy để dọn xong.'; Add-Finding -Ma 'CAN_KHOI_DONG_LAI' warn 'Khởi động lại máy để dọn kho thành phần xong.' -ChiKetQua }
    return 0
}
