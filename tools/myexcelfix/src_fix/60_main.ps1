
# ----------------------------------------------------------------------------
function Show-Verification {
    Step 'KIỂM TRA SAU KHI SỬA'
    $ver = Get-ExcelMainVersion
    $k = Open-UserKey "Software\Microsoft\Office\$ver\Excel\Options"
    $opens = if ($k) { @($k.GetValueNames() | Where-Object { $_ -match '^OPEN\d*$' } | ForEach-Object { "$_ = $($k.GetValue($_))" }) } else { @() }
    Note ('Add-in đang bật (Excel {0}): {1}' -f $ver, $(if ($opens.Count) { $opens -join ' ; ' } else { 'không có' }))
    foreach ($f in @($script:Manifest.Folders)) { Note ('Đã cất: {0} -> {1}' -f $f.From, $f.To) }
    foreach ($n in (Get-MyExcelStateKeys)) {
        $stack = New-Object System.Collections.Stack
        $root = Open-UserKey "Software\VB and VBA Program Settings\$n"
        if ($root) { $stack.Push($root) }
        while ($stack.Count -gt 0) {
            $key = $stack.Pop()
            if ($key.GetValueNames() -contains 'DuongDanADDin') { Note "DuongDanADDin = $($key.GetValue('DuongDanADDin'))" }
            foreach ($sn in $key.GetSubKeyNames()) { $sk = $key.OpenSubKey($sn); if ($sk) { $stack.Push($sk) } }
            $key.Close()
        }
    }
    Say ''
    Say ('  Tổng: {0} thay đổi, {1} cảnh báo.' -f $script:Changes, $script:Problems) $(if ($script:Problems) { 'Yellow' } else { 'Green' })
}

function Show-QrSteps([bool]$AfterReset) {
    $sep = (Get-Culture).TextInfo.ListSeparator
    Say '  Làm trong Excel:' 'White'
    Say '   - Có thông báo không tìm thấy file MyExcel cũ thì bấm OK.'
    if ($AfterReset) { Say '   - MyExcel hiện màn hình chạy lần đầu thì làm theo như lúc mới cài.' }
    Say '   - Tab Mini Tool > Tạo QR Code: TẮT rồi BẬT lại hàm QR, phải thấy "Bạn đã có thể dùng Hàm QR".'
    if ($AfterReset) {
        $info = if ($script:BackupDir) { Join-Path $script:BackupDir 'ThongTinKhaiBao.txt' } else { $null }
        $hint = if ($info -and (Test-Path -LiteralPath $info)) { " (thông tin cũ: mở bằng Notepad file $info)" } else { '' }
        Say "   - Khai báo lại tài khoản: Mini Tool > Tạo QR Code > Tạo QR Code tài khoản ngân hàng > Khai báo$hint."
    }
    Say ('   - Thử tạo mã VietQR như mọi khi, hoặc gõ =QrBank_Sotien_Noidung(10000{0}"THU NGHIEM") vào một ô trống.' -f $sep)
}

function Show-StillBroken {
    $script:StillBroken = $true
    Step 'VẪN CHƯA ĐƯỢC - VIỆC CẦN LÀM TIẾP'
    Say '  1) Chạy CheckMyExcel_VietQR.bat trong profile lỗi, rồi chạy thêm 1 lần trong một profile mới (tạo QR được).'
    Say '     Báo cáo lần 2 có mục 12 so sánh 2 profile - gửi cả 2 báo cáo.'
    Say '  2) Thiết lập Windows theo user hay gây khác biệt: định dạng ngày/số (Region), Clipboard history (Win+V).'
}

function Invoke-Trial([bool]$AfterReset, [bool]$CanReset) {
    Step 'BƯỚC 10 - THỬ VIETQR TRONG EXCEL'
    if (-not $script:Auto) {
        if (-not (Ask 'Mở Excel để thử ngay bây giờ?')) {
            Show-QrSteps $AfterReset
            if ($CanReset) { Say '  Nếu thử sau mà vẫn lỗi: chạy lại file sửa này và chọn đặt lại dữ liệu MyExcel.' 'Yellow' }
            return
        }
        Start-Process 'excel.exe' -ErrorAction SilentlyContinue
    }
    Show-QrSteps $AfterReset
    if (Test-QrWorks 'Đã tạo được VietQR chưa?') { Say '  VietQR đã chạy được. Xong.' 'Green'; return }
    if (-not $CanReset) { Show-StillBroken; return }
    Say ''
    Say '  Chưa được: bước tiếp theo là đặt lại dữ liệu MyExcel của profile này về như profile mới.' 'Yellow'
    if (-not (Invoke-MyExcelReset $true)) { Show-StillBroken; return }
    if (-not $script:Auto -and (Ask 'Mở Excel để thử lại?')) { Start-Process 'excel.exe' -ErrorAction SilentlyContinue }
    Show-QrSteps $true
    if (Test-QrWorks 'Đã tạo được VietQR chưa?') { Say '  VietQR đã chạy được sau khi đặt lại dữ liệu MyExcel. Xong.' 'Green'; return }
    Show-StillBroken
}

function Invoke-DataStep {
    Step 'BƯỚC 9 - DỮ LIỆU MYEXCEL LƯU THEO USER'
    $names = @(Get-MyExcelStateKeys)
    if ($names.Count -eq 0) { Skip 'Profile này chưa có dữ liệu MyExcel (giống profile mới)'; Invoke-Trial $false $false; return }
    $dataDate = Get-MyExcelDataDate
    $xlamDate = (Get-Item -LiteralPath (Join-Path $script:Target 'MyExcel.xlam') -Force).LastWriteTime
    $stale = [bool]($dataDate -and ($xlamDate - $dataDate).TotalDays -gt 30)
    if ($dataDate) {
        Note ('Dữ liệu MyExcel của profile tạo từ bản ngày {0}, bộ đang dùng là bản ngày {1}{2}' -f $dataDate.ToString('dd/MM/yyyy'), $xlamDate.ToString('dd/MM/yyyy'), $(if ($stale) { ' => DỮ LIỆU CŨ' } else { '' }))
    }
    Say '  Lỗi "profile mới tạo được VietQR, profile cũ thì không" đã sửa được bằng cách đặt lại dữ liệu này.' 'White'
    $opts = @('Đặt lại dữ liệu MyExcel ngay rồi mới thử (nhanh; phải khai báo lại tài khoản ngân hàng)', 'Thử trong Excel trước, vẫn lỗi mới đặt lại')
    $def = if ($env:MYX_RESET_NOW) { if ($env:MYX_RESET_NOW -eq '1') { 1 } else { 2 } } elseif ($stale) { 1 } else { 2 }   # MYX_RESET_NOW chỉ dùng khi test
    $opts[$def - 1] += '  <- khuyên dùng'
    if ((Choose 'Chọn cách làm' $opts $def) -eq 1) {
        $ok = Invoke-MyExcelReset $false
        Invoke-Trial $ok (-not $ok)
    } else {
        Invoke-Trial $false $true
    }
}

function Invoke-Fix {
    Say ''
    Say "  SỬA LỖI VIETQR CỦA MYEXCEL CHO PROFILE NÀY (bản $($script:Version))" 'Cyan'
    Say "  Tài khoản: $env:USERNAME   Máy: $env:COMPUTERNAME"
    Say '  Script sẽ: tìm bộ MyExcel chuẩn -> sao lưu -> cất bộ thừa -> nạp lại add-in -> sửa đường dẫn MyExcel tự lưu'
    Say '  -> dọn cache .exd -> bỏ chặn file -> nối lại file Excel cũ -> đặt lại dữ liệu MyExcel (hỏi trước) -> thử trong Excel.'
    Say '  Không đổi Macro Settings / Protected View / ActiveX. Mọi thay đổi đều có sao lưu và file hoàn tác.'
    Say ''
    Show-FontHint
    if (-not (Test-RightUser)) { Set-Result 2 'SAI_TAI_KHOAN' 'Chạy sai tài khoản Windows, chưa thay đổi gì.'; return }
    if (-not (Ask 'Bắt đầu sửa?')) { Say '  Đã hủy, chưa thay đổi gì.' 'Yellow'; Set-Result 2 'NGUOI_DUNG_HUY' 'Người dùng chọn không sửa.'; return }
    if (-not (Wait-ExcelClosed)) { Say '  Đã dừng, chưa thay đổi gì.' 'Yellow'; Set-Result 2 'EXCEL_CHUA_DONG' 'Excel chưa đóng, chưa thay đổi gì.'; return }
    if (-not (Select-MyExcelTarget)) { Say '  Đã dừng, chưa thay đổi gì.' 'Yellow'; Set-Result 2 'KHONG_CO_BO_MYEXCEL' 'Không thấy bộ MyExcel đủ file QR trên máy.'; return }
    if (-not (Invoke-Backup)) { Warn 'Sao lưu thất bại nên DỪNG LẠI, chưa sửa gì.'; Set-Result 1 'SAO_LUU_LOI' 'Không sao lưu được nên chưa sửa gì.'; return }
    $script:ChangesAtBackup = $script:Changes
    Invoke-FolderFix
    Invoke-AddinFix
    Invoke-VbaPathFix
    Invoke-CacheCleanup
    Invoke-Unblock
    Invoke-WorkbookRelink
    Save-Manifest
    Show-Verification
    Invoke-DataStep
    Save-Manifest
    Say ''
    Say "  Sao lưu (thư mục riêng của tài khoản này, có số tài khoản ngân hàng): $($script:BackupDir)" 'White'
    Say '  Hoàn tác trả lại mọi thứ như trước khi sửa (kể cả lỗi cũ) - chỉ chạy khi thật cần: HOAN_TAC.bat cạnh file này' 'White'
    Say '  (hoặc nút Hoàn tác của Trạm Tool) liệt kê các bản sao lưu để chọn; bấm đúp HoanTac_FixMyExcel.bat trong thư mục trên cũng được.' 'White'
    if ($script:StillBroken) { Set-Result 3 'VIETQR_VAN_LOI' 'Đã sửa nhưng VietQR vẫn chưa chạy được.' }
    elseif ($script:Problems -gt 0) { Set-Result 3 'CO_CANH_BAO' "Đã sửa, còn $($script:Problems) cảnh báo cần xem." }
    else { Set-Result 0 'XONG' 'Đã sửa xong.' }
}

function Resolve-BackupFile([string]$Dir, [string]$Path) {
    # Bản sao lưu cũ ghi đường dẫn tuyệt đối; từ bản 2 ghi tương đối với thư mục sao lưu
    if (-not $Path) { return $null }
    if ([IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $Dir $Path)
}

function Get-KeepPath([string]$Path) {
    # SoQuy.xlsx -> SoQuy.truoc_hoantac.xlsx (đã có thì thêm giờ), vẫn mở được bằng Excel
    $dir = Split-Path $Path -Parent
    $base = [IO.Path]::GetFileNameWithoutExtension($Path); $ext = [IO.Path]::GetExtension($Path)
    $p = Join-Path $dir "$base.truoc_hoantac$ext"
    if (Test-Path -LiteralPath $p) { $p = Join-Path $dir "$base.truoc_hoantac_$($script:Stamp)$ext" }
    return $p
}

function Get-WorkbookPlan($Workbooks, [string]$Dir) {
    # Action: Restore = chưa đổi sau lần sửa, chép lại bản cũ | Keep = đã đổi (hoặc không biết), giữ bản hiện tại rồi mới chép | Skip
    foreach ($w in @($Workbooks | Where-Object { $_ })) {
        $orig = [string]$w.Original
        $bak = Resolve-BackupFile $Dir ([string]$w.Backup)
        $p = [pscustomobject]@{ Original = $orig; Backup = $bak; Action = 'Restore'; Why = '' }
        if (-not $bak -or -not (Test-Path -LiteralPath $bak -PathType Leaf)) { $p.Action = 'Skip'; $p.Why = "thiếu bản sao lưu $bak" }
        elseif ($w.HashBackup -and (Get-Sha256 $bak) -ne [string]$w.HashBackup) { $p.Action = 'Skip'; $p.Why = "bản sao lưu $bak đã bị thay đổi hoặc hỏng" }
        elseif (-not (Test-Path -LiteralPath $orig -PathType Leaf)) { $p.Action = 'Skip'; $p.Why = "file không còn ở chỗ cũ (đã chuyển hoặc xoá), bản trước khi sửa: $bak" }
        elseif (-not $w.HashAfter) { $p.Action = 'Keep'; $p.Why = 'bản sao lưu cũ không ghi dấu file nên không biết đã sửa tiếp chưa' }
        elseif ((Get-Sha256 $orig) -ne [string]$w.HashAfter) { $p.Action = 'Keep'; $p.Why = 'đã được sửa tiếp sau lần sửa' }
        $p
    }
}

function Restore-Workbook($P) {
    if ($P.Action -eq 'Skip') { Warn "Không khôi phục $($P.Original): $($P.Why)"; return }
    $keep = $null
    if ($P.Action -eq 'Keep') {
        $keep = Get-KeepPath $P.Original
        try { Copy-Item -LiteralPath $P.Original -Destination $keep -ErrorAction Stop }
        catch { Warn "Không giữ được bản hiện tại của $($P.Original) nên không chép đè: $($_.Exception.Message)"; return }
    }
    try { Copy-Item -LiteralPath $P.Backup -Destination $P.Original -Force -ErrorAction Stop }
    catch { Warn "Không khôi phục được $($P.Original) (file đang mở?): $($_.Exception.Message)"; return }
    if ($keep) {
        $script:KeptFiles.Add($keep)
        Done "Khôi phục file $($P.Original); bản hiện tại ($($P.Why)) giữ ở $keep"
    } else {
        Done "Khôi phục file $($P.Original)"
    }
}

function Save-PreUndoState([string]$Dir) {
    # Cấu hình ngay trước khi hoàn tác: hoàn tác nhầm thì nạp lại các file .reg này
    $pre = Join-Path $Dir "TruocHoanTac_$($script:Stamp)"
    try { New-Item -ItemType Directory -Path $pre -Force -ErrorAction Stop | Out-Null }
    catch { Warn "Không tạo được thư mục $pre : $($_.Exception.Message)"; return $false }
    $regRoot = 'HKCU\' + $script:RegBase
    foreach ($ver in (Get-ExcelVersions)) {
        & reg.exe export "$($regRoot)Software\Microsoft\Office\$ver\Excel" (Join-Path $pre "Excel_$ver.reg") /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Warn "Không lưu được cấu hình Excel $ver hiện tại (mã lỗi $LASTEXITCODE)"; return $false }
    }
    $vb = Open-UserKey 'Software\VB and VBA Program Settings'
    if ($vb) {
        $vb.Close()
        & reg.exe export "$($regRoot)Software\VB and VBA Program Settings" (Join-Path $pre 'VBA_Settings.reg') /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Warn "Không lưu được dữ liệu MyExcel hiện tại (mã lỗi $LASTEXITCODE)"; return $false }
    }
    Note "Đã lưu cấu hình hiện tại (trước khi hoàn tác) vào $pre"
    return $true
}

function Select-UndoBackup {
    # HOAN_TAC.bat không kèm thư mục: chọn trong các bản sao lưu của tài khoản này, mới nhất trước
    $all = @(Get-BackupList)
    $mine = @($all | Where-Object { $_.User -eq $env:USERNAME })
    if ($mine.Count -eq 0) {
        $other = if ($all.Count) { " (có $($all.Count) bản của tài khoản khác: phải hoàn tác bằng đúng tài khoản đó)" } else { '' }
        Warn "Không thấy bản sao lưu nào của tài khoản $env:USERNAME$other."
        Note "Nơi tìm: $(Get-MyxDataDir 'SaoLuu') và Desktop."
        return $null
    }
    $opts = foreach ($b in $mine) {
        $n = @($b.Manifest.Workbooks | Where-Object { $_ }).Count
        $reset = @($b.Manifest.ResetKeys | Where-Object { $_ }).Count
        '{0}  ({1} file Excel{2}){3}  {4}' -f $b.Time, $n, $(if ($reset) { ', có đặt lại dữ liệu MyExcel' } else { '' }), $(if ($b.OnDesktop) { ' [Desktop]' } else { '' }), $b.Dir
    }
    Say '  Các bản sao lưu của tài khoản này (mới nhất trước):' 'White'
    $i = Choose 'Chọn bản sao lưu cần hoàn tác' @($opts) 1
    return $mine[$i - 1].Dir
}

function Invoke-Undo {
    Say ''
    Say "  HOÀN TÁC SỬA LỖI MYEXCEL (bản $($script:Version))" 'Cyan'
    Show-FontHint
    if (-not $script:UndoDir) {
        $script:UndoDir = Select-UndoBackup
        if (-not $script:UndoDir) { Set-Result 2 'KHONG_CO_SAO_LUU' 'Không thấy bản sao lưu nào của tài khoản này.'; return }
    }
    $dir = $script:UndoDir
    $script:BackupDir = $null
    $mf = Join-Path $dir 'manifest.json'
    if (-not (Test-Path -LiteralPath $mf)) { Warn "Không thấy manifest.json trong $dir"; Set-Result 2 'THIEU_MANIFEST' 'Thư mục sao lưu thiếu manifest.json.'; return }
    try { $m = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { Warn "manifest.json hỏng, không đọc được: $($_.Exception.Message)"; Set-Result 1 'MANIFEST_HONG' 'manifest.json hỏng nên không hoàn tác được.'; return }
    $script:RegBase = [string]$m.RegBase
    Say "  Bản sao lưu lúc $($m.Time) của user $($m.User) trên máy $($m.Computer)"
    if ($m.User -ne $env:USERNAME) { Warn "Đang chạy bằng user $env:USERNAME - phải chạy bằng đúng user $($m.User)."; Set-Result 2 'SAI_TAI_KHOAN' "Phải chạy bằng đúng user $($m.User)."; return }
    if (-not (Test-RightUser)) { Set-Result 2 'SAI_TAI_KHOAN' 'Chạy sai tài khoản Windows, chưa hoàn tác gì.'; return }
    foreach ($p in @(Get-WorkbookPlan $m.Workbooks $dir)) {
        switch ($p.Action) {
            'Restore' { Note "Chép lại bản trước khi sửa: $($p.Original)" }
            'Keep'    { Say ('  {0}: {1}, bản hiện tại sẽ được giữ thành {2} rồi mới chép bản trước khi sửa.' -f $p.Original, $p.Why, (Split-Path (Get-KeepPath $p.Original) -Leaf)) 'Yellow' }
            default   { Say "  Bỏ qua $($p.Original): $($p.Why)" 'Yellow' }
        }
    }
    Say '  Lưu ý: hoàn tác đưa dữ liệu MyExcel cũ trở lại, lỗi VietQR cũ có thể quay lại.' 'Yellow'
    if (-not (Ask 'Khôi phục cấu hình Excel, dữ liệu MyExcel, thư mục và các file đã sửa?')) { Say '  Đã hủy.' 'Yellow'; Set-Result 2 'NGUOI_DUNG_HUY' 'Người dùng chọn không hoàn tác.'; return }
    if (-not (Wait-ExcelClosed)) { Set-Result 2 'EXCEL_CHUA_DONG' 'Excel chưa đóng, chưa hoàn tác gì.'; return }
    if (-not (Save-PreUndoState $dir)) { Set-Result 1 'SAO_LUU_LOI' 'Không lưu được cấu hình hiện tại nên chưa hoàn tác gì.'; return }
    $script:ChangesAtBackup = $script:Changes
    foreach ($nk in @(@($m.NewKeys) + @($m.ResetKeys) | Where-Object { $_ })) {
        # Xóa khóa do script thêm, và dữ liệu MyExcel tạo mới sau khi đặt lại, trước khi nạp bản sao lưu
        try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($script:RegBase + $nk, $false); Done "Xóa khóa tạo sau khi sửa: $nk" }
        catch { Warn "Không xóa được $nk : $($_.Exception.Message)" }
    }
    foreach ($r in @($m.RegExcel)) {
        $k = Open-UserKey "Software\Microsoft\Office\$($r.Ver)\Excel\Options" $true
        if ($k) { foreach ($n in @($k.GetValueNames() | Where-Object { $_ -match '^OPEN\d*$' })) { $k.DeleteValue($n, $false) }; $k.Close() }
        & reg.exe import (Join-Path $dir $r.File) 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Done "Khôi phục cấu hình Excel $($r.Ver)" } else { Warn "Không nhập được $($r.File) (mã lỗi $LASTEXITCODE)" }
    }
    if ($m.RegVB) {
        & reg.exe import (Join-Path $dir $m.RegVB) 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Done 'Khôi phục dữ liệu MyExcel (VB and VBA Program Settings)' } else { Warn "Không nhập được $($m.RegVB)" }
    }
    foreach ($f in @(@($m.Folders) + @($m.Folder) | Where-Object { $_ })) {
        if ((Test-Path -LiteralPath $f.To) -and -not (Test-Path -LiteralPath $f.From)) {
            try { Rename-Item -LiteralPath $f.To -NewName (Split-Path $f.From -Leaf) -ErrorAction Stop; Done "Đổi tên lại $($f.To) -> $($f.From)" }
            catch { Warn "Không đổi tên lại được $($f.To): $($_.Exception.Message)" }
        }
    }
    # Tính lại ngay trước khi chép: file có thể vừa được lưu trong lúc chờ đóng Excel
    foreach ($p in @(Get-WorkbookPlan $m.Workbooks $dir)) { Restore-Workbook $p }
    Say ('  Xong: {0} mục đã khôi phục, {1} cảnh báo. (File .exd đã xóa và dấu chặn file không cần khôi phục.)' -f ($script:Changes - $script:ChangesAtBackup), $script:Problems) $(if ($script:Problems) { 'Yellow' } else { 'Green' })
    foreach ($k in $script:KeptFiles) { Say "  Bản file Excel ngay trước khi hoàn tác được giữ ở: $k (dữ liệu nhập thêm sau lần sửa nằm trong file này)" 'Yellow' }
    if ($script:Problems -gt 0) { Set-Result 3 'CO_CANH_BAO' "Hoàn tác xong, còn $($script:Problems) cảnh báo cần xem." }
    else { Set-Result 0 'XONG' 'Đã hoàn tác xong.' }
}

# ----------------------------------------------------------------------------
try {
    if ($script:UndoMode) { Invoke-Undo } else { Invoke-Fix }
} catch {
    $real = if ($null -ne $script:ChangesAtBackup) { $script:Changes - $script:ChangesAtBackup } else { 0 }
    if ("$($_.Exception.Message)" -eq $script:EndOfInput) {
        Say ''
        Say '  Hết đầu vào: không có ai trả lời câu hỏi (chạy không có cửa sổ dòng lệnh?) nên dừng lại.' 'Yellow'
        if ($real -gt 0) {
            $more = if ($script:UndoMode) { 'chạy lại hoàn tác để làm nốt.' } else { "mọi thay đổi đều có sao lưu ($($script:BackupDir)), chạy HOAN_TAC.bat nếu cần trả lại." }
            Say "  Đã làm $real thay đổi trước khi dừng: $more" 'Yellow'
            Set-Result 3 'HET_DAU_VAO' "Hết đầu vào sau $real thay đổi."
        } else {
            Say '  Chưa thay đổi gì.' 'Yellow'
            Set-Result 2 'HET_DAU_VAO' 'Hết đầu vào, chưa thay đổi gì.'
        }
    } else {
        Warn "Lỗi không mong muốn: $($_.Exception.Message)"
        Set-Result 1 'LOI_BAT_NGO' "Lỗi không mong muốn: $($_.Exception.Message)"
    }
} finally {
    if ($null -eq $script:ExitCode) { Set-Result 1 'LOI_BAT_NGO' 'Dừng giữa chừng.' }
    $logDir = if ($script:UndoMode) { $script:UndoDir } elseif ($script:BackupDir) { $script:BackupDir } else { $null }
    $logPath = if ($logDir) { Join-Path $logDir $(if ($script:UndoMode) { "NhatKy_HoanTac_$($script:Stamp).txt" } else { 'NhatKy_Sua.txt' }) } else { $null }
    Save-ResultJson $logPath
    if ($logPath) {
        try { [IO.File]::WriteAllLines($logPath, $script:Log.ToArray(), (New-Object Text.UTF8Encoding $true)); Say "  Nhật ký: $logPath" 'DarkGray' } catch {}
    }
}
exit $script:ExitCode
