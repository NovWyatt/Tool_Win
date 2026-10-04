
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
        $hint = if ($script:BackupDir -and (Test-Path -LiteralPath (Join-Path $script:BackupDir 'ThongTinKhaiBao.txt'))) { ' (thông tin cũ trong ThongTinKhaiBao.txt ở thư mục sao lưu)' } else { '' }
        Say "   - Khai báo lại tài khoản: Mini Tool > Tạo QR Code > Tạo QR Code tài khoản ngân hàng > Khai báo$hint."
    }
    Say ('   - Thử tạo mã VietQR như mọi khi, hoặc gõ =QrBank_Sotien_Noidung(10000{0}"THU NGHIEM") vào một ô trống.' -f $sep)
}

function Show-StillBroken {
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
    Say '  SỬA LỖI VIETQR CỦA MYEXCEL CHO PROFILE NÀY' 'Cyan'
    Say "  Tài khoản: $env:USERNAME   Máy: $env:COMPUTERNAME"
    Say '  Script sẽ: tìm bộ MyExcel chuẩn -> sao lưu -> cất bộ thừa -> nạp lại add-in -> sửa đường dẫn MyExcel tự lưu'
    Say '  -> dọn cache .exd -> bỏ chặn file -> nối lại file Excel cũ -> đặt lại dữ liệu MyExcel (hỏi trước) -> thử trong Excel.'
    Say '  Không đổi Macro Settings / Protected View / ActiveX. Mọi thay đổi đều có sao lưu và file hoàn tác.'
    Say ''
    Show-FontHint
    if (-not (Test-RightUser)) { return }
    if (-not (Ask 'Bắt đầu sửa?')) { Say '  Đã hủy, chưa thay đổi gì.' 'Yellow'; return }
    if (-not (Wait-ExcelClosed)) { Say '  Đã dừng, chưa thay đổi gì.' 'Yellow'; return }
    if (-not (Select-MyExcelTarget)) { Say '  Đã dừng, chưa thay đổi gì.' 'Yellow'; return }
    if (-not (Invoke-Backup)) { Warn 'Sao lưu thất bại nên DỪNG LẠI, chưa sửa gì.'; return }
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
    Say "  Sao lưu: $($script:BackupDir)" 'White'
    Say '  HoanTac_FixMyExcel.bat trong đó trả lại mọi thứ như trước khi sửa (kể cả lỗi cũ) - chỉ chạy khi thật cần.' 'White'
}

function Invoke-Undo {
    $dir = Split-Path $env:MYX_SELF -Parent
    $script:BackupDir = $null
    $mf = Join-Path $dir 'manifest.json'
    Say ''
    Say '  HOÀN TÁC SỬA LỖI MYEXCEL' 'Cyan'
    Show-FontHint
    if (-not (Test-Path -LiteralPath $mf)) { Warn "Không thấy manifest.json trong $dir"; return }
    $m = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:RegBase = [string]$m.RegBase
    Say "  Bản sao lưu lúc $($m.Time) của user $($m.User) trên máy $($m.Computer)"
    if ($m.User -ne $env:USERNAME) { Warn "Đang chạy bằng user $env:USERNAME - phải chạy bằng đúng user $($m.User)."; return }
    if (-not (Test-RightUser)) { return }
    Say '  Lưu ý: hoàn tác đưa dữ liệu MyExcel cũ trở lại, lỗi VietQR cũ có thể quay lại.' 'Yellow'
    if (-not (Ask 'Khôi phục cấu hình Excel, dữ liệu MyExcel, thư mục và các file đã sửa?')) { Say '  Đã hủy.' 'Yellow'; return }
    if (-not (Wait-ExcelClosed)) { return }
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
    foreach ($w in @($m.Workbooks | Where-Object { $_ })) {
        try { Copy-Item -LiteralPath $w.Backup -Destination $w.Original -Force -ErrorAction Stop; Done "Khôi phục file $($w.Original)" }
        catch { Warn "Không khôi phục được $($w.Original): $($_.Exception.Message)" }
    }
    Say ('  Xong: {0} mục đã khôi phục, {1} cảnh báo. (File .exd đã xóa và dấu chặn file không cần khôi phục.)' -f $script:Changes, $script:Problems) 'Green'
}

# ----------------------------------------------------------------------------
try {
    if ($script:UndoMode) { Invoke-Undo } else { Invoke-Fix }
} catch {
    Warn "Lỗi không mong muốn: $($_.Exception.Message)"
} finally {
    $logDir = if ($script:BackupDir) { $script:BackupDir } elseif ($script:UndoMode) { Split-Path $env:MYX_SELF -Parent } else { $null }
    if ($logDir) {
        $name = if ($script:UndoMode) { "NhatKy_HoanTac_$($script:Stamp).txt" } else { 'NhatKy_Sua.txt' }
        try { [IO.File]::WriteAllLines((Join-Path $logDir $name), $script:Log.ToArray(), (New-Object Text.UTF8Encoding $true)); Say "  Nhật ký: $(Join-Path $logDir $name)" 'DarkGray' } catch {}
    }
}
