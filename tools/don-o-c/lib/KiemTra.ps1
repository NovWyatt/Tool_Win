# Dọn ổ C - kiểm tra, chỉ đọc. Ghi báo cáo ket_qua\BaoCao_DonOC_<tên máy>_<thời gian>.txt.

function Invoke-Section {
    # Một phần của báo cáo; phần lỗi thì ghi lý do rồi chạy tiếp phần sau.
    param([string]$Title, [scriptblock]$Body)
    Write-Head $Title
    try { & $Body } catch { Write-Warn ('Không đọc được phần này: {0}' -f $_.Exception.Message.Trim()) }
}

function Get-DownloadsDir {
    $v = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' '{374DE290-123F-4565-9164-39C4925E467B}'
    if ($v) { return [string]$v }
    return (Join-Path $env:USERPROFILE 'Downloads')
}

function Get-ReportItems {
    # Thứ chiếm nhiều chỗ mà công cụ không tự dọn: chỉ báo dung lượng và cách xử lý.
    param([int]$Seconds = 10)
    $k = Get-KnownDirs
    $drive = $k.Drive
    $rows = New-Object System.Collections.Generic.List[object]
    # Ma: mã cố định của mục trong file kết quả cho Trạm Tool.
    $add = {
        param([string]$Ma, [string]$Label, [string]$Path, [string]$Hint, [string]$Level = 'info')
        if (-not (Test-Path -LiteralPath $Path)) { return }
        $m = Get-FolderBytes $Path $Seconds
        $rows.Add([pscustomobject]@{ Ma = $Ma; Label = $Label; Path = $Path; Bytes = $m.Bytes; Partial = $m.Partial; Denied = $m.Denied; Hint = $Hint; Level = $Level })
    }

    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    & $add 'THUNG_RAC' 'Thùng rác' (Join-Path "$drive\" ('$Recycle.Bin\' + $sid)) 'Mở Thùng rác, xem lại rồi bấm Empty Recycle Bin. Công cụ không xoá thùng rác hộ.'
    & $add 'WINDOWS_OLD' 'Bản Windows cũ (Windows.old)' "$drive\Windows.old" 'Dùng để quay về bản Windows trước; Windows tự xoá sau 10 ngày. Chắc không quay lại thì xoá ở Settings > System > Storage > Temporary files > Previous Windows installation(s).'

    # File hệ thống ở gốc ổ C (Test-Path không thấy file ẩn hệ thống, đọc thẳng thư mục gốc).
    try {
        foreach ($f in ([IO.DirectoryInfo]"$drive\").GetFiles('*.sys')) {
            switch ($f.Name.ToLowerInvariant()) {
                'hiberfil.sys' { $rows.Add([pscustomobject]@{ Ma = 'FILE_NGU_DONG'; Label = 'File ngủ đông (hiberfil.sys)'; Path = $f.FullName; Bytes = $f.Length; Partial = $false; Denied = 0; Level = 'info'; Hint = 'Không dùng ngủ đông (Hibernate) thì chạy trong cửa sổ Admin: powercfg /h /type reduced (file nhỏ lại, vẫn khởi động nhanh) hoặc powercfg /h off (tắt hẳn, mất cả khởi động nhanh).' }) }
                'pagefile.sys' { $rows.Add([pscustomobject]@{ Ma = 'BO_NHO_AO'; Label = 'Bộ nhớ ảo (pagefile.sys)'; Path = $f.FullName; Bytes = $f.Length; Partial = $false; Denied = 0; Level = 'info'; Hint = 'Windows tự quản lý; không nên tắt hay xoá.' }) }
            }
        }
    } catch { }

    if (Test-IsAdmin) {
        try {
            $used = [int64]0
            foreach ($s in @(Get-CimInstance Win32_ShadowStorage -ErrorAction Stop)) { $used += [int64]$s.UsedSpace }
            if ($used) { $rows.Add([pscustomobject]@{ Ma = 'DIEM_KHOI_PHUC'; Label = 'Điểm khôi phục hệ thống'; Path = ''; Bytes = $used; Partial = $false; Denied = 0; Level = 'info'; Hint = 'Giữ lại để quay về khi Windows lỗi. Muốn giảm giới hạn: System Properties > System Protection > Configure.' }) }
        } catch { }
    }

    & $add 'DU_LIEU_ZALO' 'Dữ liệu Zalo (tin nhắn, ảnh, file đã nhận)' (Join-Path $k.Roaming 'ZaloData') 'Xoá ảnh, video, file cũ ngay trong Zalo (phần dữ liệu, bộ nhớ trong cài đặt). Không xoá tay thư mục ZaloData: mất tin nhắn lưu trên máy.'
    & $add 'BO_CAI_ZALO' 'Bộ cài cập nhật Zalo đã tải' (Join-Path $k.Local 'zalo-updater') 'Zalo tự tải lại khi cần cập nhật.'
    & $add 'BO_NHO_DEM_TEAMS' 'Bộ nhớ đệm Microsoft Teams' (Join-Path $k.Local 'Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams') 'Thoát hẳn Teams rồi xoá nội dung thư mục này (cách của Microsoft khi Teams lỗi); Teams tạo lại.'
    foreach ($v in 'AMD', 'NVIDIA', 'Intel') { & $add 'BO_CAI_DRIVER' "Bộ cài driver $v đã giải nén ($drive\$v)" "$drive\$v" 'Cài driver xong thì không cần nữa: xoá được bằng tay.' }

    $mine = [ordered]@{
        'Tải về (Downloads)' = (Get-DownloadsDir)
        'Màn hình (Desktop)' = [Environment]::GetFolderPath('Desktop')
        'Tài liệu (Documents)' = [Environment]::GetFolderPath('MyDocuments')
        'Ảnh (Pictures)' = [Environment]::GetFolderPath('MyPictures')
        'Video (Videos)' = [Environment]::GetFolderPath('MyVideos')
        'Nhạc (Music)' = [Environment]::GetFolderPath('MyMusic')
    }
    foreach ($label in $mine.Keys) {
        $p = [string]$mine[$label]
        if (-not $p -or -not $p.StartsWith("$drive\", [StringComparison]::OrdinalIgnoreCase)) { continue }
        $hint = if ($label -like 'Tải về*') { 'Xem lại bộ cài, file nén đã tải và xoá thứ không cần.' } else { 'Dữ liệu cá nhân: chuyển bớt sang ổ khác hoặc ổ ngoài. Công cụ không đụng tới.' }
        & $add $(if ($label -like 'Tải về*') { 'THU_MUC_TAI_VE' } else { 'DU_LIEU_CA_NHAN' }) $label $p $hint
    }
    return $rows.ToArray()
}

function Get-StorageSenseState {
    # $true bật, $false tắt, $null chưa từng đặt.
    $v = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01'
    if ($null -eq $v) { return $null }
    return ([int]$v -eq 1)
}

function Invoke-KiemTra {
    param([int]$SoNgay = 7)
    $script:Report.Clear(); $script:Findings.Clear()
    $started = Get-Date
    $cutoff = $started.AddDays(-$SoNgay)
    Write-Out 'BÁO CÁO DUNG LƯỢNG Ổ C' 'Cyan'
    Write-Out ('Máy {0}, tài khoản {1}{2}, {3:dd/MM/yyyy HH:mm}. Công cụ "Dọn ổ C an toàn" {4}: chỉ đọc, không xoá gì.' -f $env:COMPUTERNAME, (Get-CurrentUser), $(if (Test-IsAdmin) { ' (Admin)' } else { '' }), $started, $script:ToolVersion)
    $script:UserSum = [int64]0; $script:SysSum = [int64]0; $script:DriveNow = $null

    Invoke-Section 'Ổ đĩa' {
        $d = Get-DriveInfo
        if (-not $d) { Write-Warn 'Không đọc được dung lượng ổ.'; return }
        Show-DriveLine $d
        $script:DriveNow = $d
        $pct = if ($d.Size) { 100 * $d.Free / $d.Size } else { 100 }
        if ($d.Free -lt 5GB -or $pct -lt 5) { Add-Finding -Ma 'O_GAN_DAY' bad ('Ổ {0} gần đầy: Windows chậm, không cài được bản cập nhật.' -f $d.Name) }
        elseif ($d.Free -lt 15GB -or $pct -lt 10) { Add-Finding -Ma 'O_IT_CHO_TRONG' warn ('Ổ {0} còn ít chỗ trống.' -f $d.Name) }
        $ss = Get-StorageSenseState
        if ($ss -eq $true) { Write-Line 'Storage Sense (Windows tự dọn file tạm, thùng rác): đang bật.' }
        else { Add-Finding -Ma 'STORAGE_SENSE_TAT' info 'Storage Sense (Windows tự dọn file tạm, thùng rác cũ) đang tắt.' -Hint 'Bật ở Settings > System > Storage > Storage Sense (nút "Mở Storage Sense" trong Trạm Tool).' }
    }
    Invoke-Section ('Rác của bạn (dọn không cần quyền Admin, file tạm cũ hơn {0} ngày)' -f $SoNgay) {
        Write-Host '  Đang đo...' -ForegroundColor DarkGray
        $res = Measure-Items (Get-UserItems) $cutoff 30
        $script:UserSum = Show-ItemTable $res $SoNgay
        Write-Line ('Cộng: {0}' -f (Format-Size $script:UserSum))
    }
    Invoke-Section ('Rác của Windows (cần quyền Admin)') {
        Write-Host '  Đang đo...' -ForegroundColor DarkGray
        $res = Measure-Items (Get-SystemItems) $cutoff 30
        $script:SysSum = Show-ItemTable $res $SoNgay
        Write-Line ('Cộng: {0}{1}' -f (Format-Size $script:SysSum), $(if (Test-IsAdmin) { '' } else { ' (chỉ phần đo được khi không có quyền Admin)' }))
        Write-Info 'Kho thành phần WinSxS: chạy "Dọn kho thành phần Windows" để phân tích (1-5 phút).'
    }
    Invoke-Section 'Chiếm nhiều chỗ, bạn tự quyết (công cụ không xoá)' {
        Write-Host '  Đang đo...' -ForegroundColor DarkGray
        $rows = @(Get-ReportItems | Where-Object { $_.Bytes -ge 50MB } | Sort-Object Bytes -Descending)
        if (-not $rows.Count) { Write-Line 'Không có mục nào trên 50 MB.'; return }
        foreach ($r in $rows) {
            $size = (Format-Size $r.Bytes) + $(if ($r.Partial) { '+' } else { '' })
            Write-Line ('{0,-62} {1,9}' -f $r.Label, $size)
            Write-Sub $r.Hint
            # Mục từ 1 GB vào file kết quả cho Trạm Tool (bộ nhớ ảo thì không: Windows tự quản lý).
            if ($r.Bytes -ge 1GB -and $r.Ma -ne 'BO_NHO_AO') { Add-Finding -Ma $r.Ma info ('{0}: {1}' -f $r.Label, $size) -Hint $r.Hint -Bytes $r.Bytes -ChiKetQua }
        }
        if (@($rows | Where-Object { $_.Partial }).Count) { Write-Info 'Dấu + : thư mục lớn, chưa đếm hết trong thời gian cho phép.' }
    }

    $userSum = [int64]$script:UserSum; $sysSum = [int64]$script:SysSum
    if ($userSum -ge 100MB) { Add-Finding -Ma 'RAC_CUA_BAN' info ('Dọn được {0} rác của bạn.' -f (Format-Size $userSum)) -Fix 'don-cua-toi' -Bytes $userSum -Quiet }
    if ($sysSum -ge 100MB) { Add-Finding -Ma 'RAC_CUA_WINDOWS' info ('Dọn được {0} rác của Windows.' -f (Format-Size $sysSum)) -Fix 'don-he-thong' -Bytes $sysSum -Quiet }
    Show-Conclusion
    $d = $script:DriveNow
    if ($d -and -not @($script:Findings | Where-Object { $_.Level -in 'bad', 'warn' }).Count) {
        Add-Finding -Ma 'DU_CHO_TRONG' ok ('Ổ {0} còn trống {1} trên {2}.' -f $d.Name, (Format-Size $d.Free), (Format-Size $d.Size)) -ChiKetQua
    }
    $script:LastReport = Save-Report 'BaoCao_DonOC' $started
    if (-not $script:LastReport) { return 1 }
    return 0
}

function Show-Conclusion {
    Write-Head 'KẾT LUẬN'
    $rank = @{ bad = 0; warn = 1; info = 2 }
    $all = @($script:Findings)
    $ordered = @($all | Sort-Object @{ Expression = { $rank[$_.Level] } }, @{ Expression = { $_.Bytes }; Descending = $true })
    $show = @($ordered | Where-Object { -not $_.ChiKetQua -and ($_.Level -ne 'info' -or $_.Fix -or $_.Hint) })
    if (-not $show.Count) { Write-Ok 'Ổ C ổn, không có gì đáng dọn.'; return }
    foreach ($f in $show) {
        switch ($f.Level) { 'bad' { Write-Bad $f.Text } 'warn' { Write-Warn $f.Text } default { Write-Info $f.Text } }
        if ($f.Fix -and $script:Modes.Contains($f.Fix)) {
            $m = $script:Modes[$f.Fix]
            Write-Sub ('→ Chạy "{0}" (trong Trạm Tool, hoặc DON_O_C.bat mục {1}).' -f $m.Label, $m.No)
        }
        if ($f.Hint) { Write-Sub ('→ ' + $f.Hint) }
    }
}
