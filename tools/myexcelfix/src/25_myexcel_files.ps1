
# ----------------------------------------------------------------------------
Section '4. THƯ MỤC CÀI MYEXCEL, FILE QR CODE & TRẠNG THÁI BỊ CHẶN (Unblock)'
try {
    $cands = New-Object System.Collections.ArrayList
    foreach ($d in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)) {
        foreach ($p in "$($d.DeviceID)\MyExcel", "$($d.DeviceID)\MyExcelAddin") {
            if (Test-Path -LiteralPath $p -PathType Container) { [void]$cands.Add($p) }
        }
    }
    foreach ($a in $script:AddinEntries) {
        if ($a.Path -and $a.Path -match '(?i)^(.*?\\[^\\]*myexcel[^\\]*)\\') {
            $r = $Matches[1]
            if ((Test-Path -LiteralPath $r -PathType Container) -and -not ($cands -contains $r)) { [void]$cands.Add($r) }
        }
    }
    foreach ($x in @(if ($env:MYX_EXTRA_ROOT) { $env:MYX_EXTRA_ROOT -split ';' })) { if ($x -and (Test-Path -LiteralPath $x)) { [void]$cands.Add($x) } }  # chỉ dùng khi test
    foreach ($r in $cands) { if (-not ($script:MyxRoots -contains $r)) { [void]$script:MyxRoots.Add($r) } }
    Snap 'MyExcel.Roots' ($script:MyxRoots -join ' | ')
    Read-TrustedLocations
    # Bộ MyExcel mà profile này thật sự nạp (OPEN); chưa nạp bộ nào thì xét hết
    $script:ActiveRoots = @($script:MyxRoots | Where-Object { $r = $_; @($script:AddinEntries | Where-Object { $_.Source -eq 'OPEN' -and (Test-UnderPath $_.Path $r) }).Count -gt 0 })
    if ($script:ActiveRoots.Count -eq 0) { $script:ActiveRoots = @($script:MyxRoots) }

    $installs = @($script:MyxRoots | Where-Object { Get-ChildItem -LiteralPath $_ -Filter 'MyExcel*.xlam' -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1 })
    if ($installs.Count -gt 1) {
        $loaded = @($script:AddinEntries | Where-Object { $_.Source -eq 'OPEN' -and $_.Path -match '(?i)myexcel[^\\]*\.xlam$' } | ForEach-Object { $_.Path })
        $loadedTxt = if ($loaded.Count -gt 0) { $loaded -join ' ; ' } else { 'chưa nạp bộ nào' }
        $lv = if (@($loaded | Where-Object { -not (Test-UnderPath $_ 'C:\MyExcel') }).Count -gt 0) { 'LOI' } else { 'CANHBAO' }
        Add-Finding 'NHIEU_BO_MYEXCEL' $lv ("Máy có {0} bộ MyExcel ({1}); profile này đang nạp: {2}" -f $installs.Count, ($installs -join ', '), $loadedTxt) 'Chỉ dùng 1 bộ ở C:\MyExcel như hướng dẫn MyExcel. Chạy FixMyExcel_VietQR.bat trong profile này: tự chọn bộ chuẩn, hỏi trước khi cất bộ thừa, có sao lưu và file hoàn tác.'
    }

    if ($script:MyxRoots.Count -eq 0) {
        Add-Finding 'KHONG_CO_MYEXCEL' 'LOI' 'Không tìm thấy thư mục cài MyExcel (C:\MyExcel) và không có add-in MyExcel nào được đăng ký' 'Cài lại MyExcel theo https://myexcel.vn/download/ (giải nén, copy thư mục MyExcel vào ổ C:).'
    }
    if ($script:MyxRoots.Count -gt 0 -and -not ($script:MyxRoots | Where-Object { Test-SamePath $_ 'C:\MyExcel' })) {
        Add-Finding 'MYEXCEL_SAI_CHO' 'CANHBAO' ("MyExcel không nằm ở C:\MyExcel mà ở: {0}" -f ($script:MyxRoots -join ', ')) 'MyExcel khuyến nghị cài đúng C:\MyExcel, nếu không file tạo từ máy khác sẽ lỗi #NAME / lỗi nút bấm.'
    }

    $execExt = '(?i)\.(xlam|xla|xll|xlsm|xlsb|xls|xltm|dll|ocx|exe|tlb)$'
    foreach ($root in $script:MyxRoots) {
        Out-Line ''
        Out-Line "  >> Thư mục: $root" 'White'
        $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue)
        $size = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 1)
        Info 'Số file / dung lượng' "$($files.Count) file / $size MB"
        $canWrite = Test-Writable $root
        Info 'User này ghi được vào thư mục' $canWrite
        Snap "MyExcel.Writable[$root]" $canWrite
        if (-not $canWrite) {
            Add-Finding 'THU_MUC_KHONG_GHI_DUOC' 'CANHBAO' "User này KHÔNG ghi được vào $root (nếu profile mới là tài khoản admin thì ghi được => khác biệt)" "Mở CMD bằng quyền Admin chạy:  icacls `"$root`" /grant *S-1-5-32-545:(OI)(CI)M /T  (cấp quyền Modify cho nhóm Users) rồi thử lại."
        }
        $blocked = @()
        $shown = 0
        foreach ($f in $files) {
            $zone = Get-ZoneId $f.FullName
            $isQr = $f.Name -match '(?i)qr'
            $isQrAddin = $isQr -and $f.Extension -match '(?i)^\.(xlam|xla|xll|dll)$'
            if ($isQr) { [void]$script:QrFiles.Add($f.FullName) }
            if ($isQrAddin) { $script:QrAddinCount++ }
            if ($null -ne $zone) { $blocked += $f }
            if ($isQrAddin -or ($f.Name -match $execExt -and $shown -lt 60)) {
                if (-not $isQrAddin) { $shown++ }
                $flag = if ($null -ne $zone) { "  <== BỊ CHẶN (ZoneId=$zone)" } else { '' }
                $ro = if ($f.IsReadOnly) { ' [ReadOnly]' } else { '' }
                $color = if ($null -ne $zone) { 'Red' } elseif ($isQrAddin) { 'White' } else { 'Gray' }
                Out-Line ('    {0}  {1,9:N0} KB  {2}{3}{4}' -f $f.LastWriteTime.ToString('dd/MM/yyyy'), ($f.Length / 1KB), $f.FullName.Substring($root.Length).TrimStart('\'), $ro, $flag) $color
            }
        }
        Info 'Số file đang bị Windows chặn (MOTW)' $blocked.Count
        Snap "MyExcel.BlockedCount[$root]" $blocked.Count
        $unblockCmd = "Get-ChildItem -LiteralPath '$root' -Recurse | Unblock-File"
        $blockedQr = @($blocked | Where-Object { $_.Name -match '(?i)qr' -and $_.Extension -match '(?i)^\.(xlam|xla|xll|dll)$' })
        $untrustedQr = @($blockedQr | Where-Object { -not (Test-TrustedDir $_.DirectoryName) })
        $isActive = @($script:ActiveRoots | Where-Object { Test-SamePath $_ $root }).Count -gt 0
        if ($untrustedQr.Count -gt 0) {
            $lv = if ($isActive) { 'LOI' } else { 'CANHBAO' }
            $note = if ($isActive) { '' } else { ' (bộ này profile không nạp)' }
            Add-Finding 'QR_BI_CHAN' $lv ("File QR Code trong {0} bị Windows chặn (Mark of the Web) và KHÔNG nằm trong Trusted Locations{1}: {2}" -f $root, $note, (($untrustedQr | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', ')) "Đúng lỗi MyExcel đã hướng dẫn: đóng Excel > chuột phải từng file QR Code > Properties > tích Unblock > OK. Hoặc mở PowerShell chạy:  $unblockCmd"
        } elseif ($blocked.Count -gt 0 -and (Test-TrustedDir $root -WithSubfolders)) {
            Add-Finding 'MOTW_DA_TIN_CAY' 'THONGTIN' ("{0} file trong {1} còn dấu chặn của Windows (MOTW) nhưng thư mục nằm trong Trusted Locations (có thư mục con) nên macro vẫn chạy - không phải nguyên nhân" -f $blocked.Count, $root) "Vẫn nên Unblock cho sạch: đóng Excel, mở PowerShell chạy:  $unblockCmd"
        } elseif ($blocked.Count -gt 0) {
            Add-Finding 'FILE_BI_CHAN' 'CANHBAO' "$($blocked.Count) file trong $root đang bị Windows chặn (MOTW) và thư mục chưa được tin cậy hết" "Đóng Excel, mở PowerShell chạy:  $unblockCmd  rồi thêm $root vào Trusted Locations (tích thư mục con)."
        }
        if (-not ($files | Where-Object { $_.Name -match '(?i)^myexcel.*\.xlam$' })) {
            Add-Finding 'THIEU_XLAM' 'LOI' "Không thấy file MyExcel*.xlam trong $root" 'File có thể bị phần mềm diệt virus xóa. Thêm thư mục MyExcel vào danh sách loại trừ rồi giải nén/copy lại bộ cài.'
        }
    }
    if ($script:MyxRoots.Count -gt 0 -and $script:QrAddinCount -eq 0) {
        Add-Finding 'THIEU_FILE_QR' 'LOI' 'Không thấy file nào tên QR Code trong thư mục MyExcel (Mini Tool)' 'Nhiều khả năng file QR Code đã bị antivirus xóa/cách ly. Kiểm tra lịch sử bảo vệ của Windows Security, thêm C:\MyExcel vào Exclusions, rồi copy lại thư mục MiniTool từ bộ cài.'
    }
    foreach ($q in $script:QrFiles) {
        $qd = Split-Path $q -Parent
        if (-not (Test-Writable $qd)) { Note "User này KHÔNG ghi được vào thư mục $qd" }
    }
    Snap 'MyExcel.QrFiles' (($script:QrFiles | ForEach-Object { Split-Path $_ -Leaf }) -join ' | ')
} catch { Note "Lỗi khi kiểm tra thư mục MyExcel: $($_.Exception.Message)" }

try {
    Out-Line ''
    Out-Line '  >> Tìm bản sao MyExcel / QR Code nằm lung tung trong profile (dễ bị nạp nhầm):' 'White'
    $dl = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' '{374DE290-123F-4565-9164-39C4925E467B}'
    if (-not $dl) { $dl = Join-Path $env:USERPROFILE 'Downloads' }
    $searchRoots = @(
        @{ P = [Environment]::GetFolderPath('Desktop'); D = 3 },
        @{ P = $dl; D = 3 },
        @{ P = [Environment]::GetFolderPath('MyDocuments'); D = 3 },
        @{ P = (Join-Path $env:APPDATA 'Microsoft\AddIns'); D = 1 },
        @{ P = (Join-Path $env:APPDATA 'Microsoft\Excel'); D = 2 },
        @{ P = (Join-Path $env:PUBLIC 'Desktop'); D = 2 }
    )
    $copies = @()
    foreach ($s in $searchRoots) {
        if (-not $s.P -or -not (Test-Path -LiteralPath $s.P)) { continue }
        $copies += Get-ChildItem -LiteralPath $s.P -Recurse -Depth $s.D -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)(myexcel|qr.?code|vietqr).*\.(xlam|xla|xll|xlsm|dll|zip|rar|7z)$' } |
            Where-Object { $f = $_.FullName; -not ($script:MyxRoots | Where-Object { Test-UnderPath $f $_ }) }
    }
    $copies = @($copies | Sort-Object FullName -Unique | Select-Object -First 40)
    if ($copies.Count -eq 0) { Ok 'Không thấy bản sao nào ngoài thư mục cài.' }
    foreach ($c in $copies) {
        $zone = Get-ZoneId $c.FullName
        $flag = if ($null -ne $zone) { "  (bị chặn ZoneId=$zone)" } else { '' }
        Out-Line ('    {0}  {1}{2}' -f $c.LastWriteTime.ToString('dd/MM/yyyy'), $c.FullName, $flag) 'Yellow'
    }
    $addinCopies = @($copies | Where-Object { $_.Extension -match '(?i)\.(xlam|xla|xll)$' })
    if ($addinCopies.Count -gt 0) {
        Add-Finding 'BAN_SAO_ADDIN' 'CANHBAO' ("Có {0} file add-in MyExcel/QR nằm ngoài thư mục cài (VD: {1})" -f $addinCopies.Count, $addinCopies[0].FullName) 'Nếu Excel đang nạp bản sao này (xem mục 5) thì bản sao thiếu các file đi kèm => chức năng QR lỗi. Gỡ tích bản sao trong Excel Add-ins, di chuyển file đó ra chỗ khác, rồi Browse lại đúng C:\MyExcel.'
    }
    Snap 'MyExcel.CopiesOutside' (($copies | ForEach-Object { $_.FullName }) -join ' | ')
} catch { Note "Lỗi khi tìm bản sao: $($_.Exception.Message)" }
