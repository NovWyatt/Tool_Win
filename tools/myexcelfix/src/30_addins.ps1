
# ----------------------------------------------------------------------------
Section '5. ADD-IN EXCEL CỦA PROFILE NÀY (HKCU) - bản nào đang được nạp?'
try {
    if ($script:OfficeVers.Count -eq 0) { Note 'Profile này chưa có cấu hình Excel trong HKCU (chưa mở Excel lần nào?).' }
    Info 'Các phiên bản Office có cấu hình' ($script:OfficeVers -join ', ')
    $openRelated = @()
    foreach ($a in $script:AddinEntries) {
        $exists = if ($a.Automation) { $true } else { Test-Path -LiteralPath $a.Path }
        $zone = if ($exists -and -not $a.Automation) { Get-ZoneId $a.Path } else { $null }
        $rel = Test-Related $a.Raw
        $tag = if ($a.Source -eq 'OPEN') { 'ĐANG BẬT ' } else { 'đang tắt ' }
        $flags = @()
        if (-not $exists) { $flags += 'FILE KHÔNG TỒN TẠI' }
        if ($null -ne $zone) { $flags += "bị chặn ZoneId=$zone" }
        $color = if ($flags.Count -gt 0 -and $rel) { 'Red' } elseif ($rel) { 'White' } else { 'Gray' }
        Out-Line ('    [{0}] {1} {2,-8} {3} {4}' -f $a.Ver, $tag, $a.Name, $a.Raw, ($flags -join ', ')) $color
        if ($a.Source -eq 'OPEN' -and $rel) { $openRelated += $a }
        if (-not $exists -and $a.Source -eq 'OPEN') {
            $lv = if ($rel) { 'LOI' } else { 'CANHBAO' }
            Add-Finding $lv "Excel đang cố nạp add-in không còn tồn tại: $($a.Raw)" 'Excel > File > Options > Add-ins > Manage: Excel Add-ins > Go > bỏ tích mục đó (Excel sẽ hỏi xóa khỏi danh sách => Yes).'
        }
    }
    Snap 'AddIns.OPEN' ((@($script:AddinEntries | Where-Object Source -eq 'OPEN') | ForEach-Object { $_.Raw }) -join ' | ')
    Snap 'AddIns.Manager' ((@($script:AddinEntries | Where-Object Source -ne 'OPEN') | ForEach-Object { $_.Raw }) -join ' | ')

    $main = @($openRelated | Where-Object { $_.Path -match '(?i)myexcel[^\\]*\.xlam$' })
    if ($script:MyxRoots.Count -gt 0 -and $main.Count -eq 0) {
        Add-Finding 'LOI' 'Add-in MyExcel.xlam CHƯA được bật trong profile này' 'Excel > File > Options > Add-ins > Manage: Excel Add-ins > Go > Browse > C:\MyExcel > chọn MyExcel > OK. Nếu Excel hỏi "Copy to Addins folder?" thì chọn NO.'
    }
    foreach ($m in $openRelated) {
        if ($script:MyxRoots.Count -gt 0 -and -not ($script:MyxRoots | Where-Object { Test-UnderPath $m.Path $_ })) {
            Add-Finding 'LOI' "Excel đang nạp MyExcel/QR từ vị trí lạ (không phải thư mục cài): $($m.Path)" 'Đây là lỗi hay gặp ở profile cũ: bản sao add-in (thường trong AppData\Roaming\Microsoft\AddIns hoặc Downloads) thiếu file đi kèm. Bỏ tích bản đó trong Add-ins, di chuyển file sao chép đi nơi khác, rồi Browse lại C:\MyExcel\MyExcel.xlam (trả lời NO khi hỏi copy).'
        }
    }
    $byLeaf = $script:AddinEntries | Where-Object { -not $_.Automation } | Group-Object { (Split-Path $_.Path -Leaf).ToLowerInvariant() }
    foreach ($g in $byLeaf) {
        $paths = @($g.Group | ForEach-Object { $_.Path } | Sort-Object -Unique)
        if ($paths.Count -gt 1) {
            $lv = if (Test-Related $g.Name) { 'LOI' } else { 'CANHBAO' }
            Add-Finding $lv ("Add-in '{0}' được đăng ký từ {1} đường dẫn khác nhau: {2}" -f $g.Name, $paths.Count, ($paths -join ' ; ')) 'Chỉ giữ 1 bản đúng trong C:\MyExcel. Trong Excel Add-ins bỏ tích các bản còn lại, đổi tên/di chuyển file thừa rồi mở lại Excel.'
        }
    }
} catch { Note "Lỗi khi phân tích add-in: $($_.Exception.Message)" }

try {
    foreach ($ver in $script:OfficeVers) {
        $dk = "HKCU:\Software\Microsoft\Office\$ver\Excel\Resiliency\DisabledItems"
        $items = Get-RegValues $dk
        foreach ($it in $items) {
            $txt = ''
            if ($it.Value -is [byte[]] -and $it.Value.Length -gt 12) {
                $txt = [Text.Encoding]::Unicode.GetString($it.Value, 12, $it.Value.Length - 12) -replace '[\x00-\x1F]+', ' | '
            }
            $lv = if (Test-Related $txt) { 'LOI' } else { 'CANHBAO' }
            Add-Finding $lv "Excel $ver đã VÔ HIỆU HÓA (Disabled Items): $txt" 'Excel > File > Options > Add-ins > Manage: Disabled Items > Go > chọn mục đó > Enable > đóng mở lại Excel.'
        }
        Snap "AddIns.DisabledItems[$ver]" @($items).Count
        if (@($items).Count -eq 0) { Ok "Excel $ver không có Disabled Items" }
        $st = @(Get-RegValues "HKCU:\Software\Microsoft\Office\$ver\Excel\Resiliency\StartupItems")
        if ($st.Count -gt 0) { Note "Excel $ver có $($st.Count) mục StartupItems (từng bị crash lúc khởi động)." }

        $opt = "HKCU:\Software\Microsoft\Office\$ver\Excel\Options"
        $use = Get-RegValue $opt 'UseSystemSeparators'
        $dsep = Get-RegValue $opt 'DecimalSeparator'
        $tsep = Get-RegValue $opt 'ThousandsSeparator'
        Info "Excel $ver - Use system separators" ($(if ($use -eq 0) { "TẮT (thập phân '$dsep', nghìn '$tsep')" } else { 'bật (theo Windows)' }))
        Snap "Excel.UseSystemSeparators[$ver]" ("$use|$dsep|$tsep")
        $alt = Get-RegValue $opt 'AltStartup'
        if ($alt) {
            Add-Finding 'CANHBAO' "Excel $ver có thư mục khởi động phụ (AltStartup): $alt" 'File trong thư mục này tự mở cùng Excel và có thể xung đột. Kiểm tra File > Options > Advanced > General > "At startup, open all files in".'
        }
    }
} catch { Note "Lỗi khi đọc Disabled Items: $($_.Exception.Message)" }

try {
    Out-Line ''
    Out-Line '  >> File tự mở cùng Excel (XLSTART) và thư mục AddIns của user:' 'White'
    $dirs = @((Join-Path $env:APPDATA 'Microsoft\Excel\XLSTART'), (Join-Path $env:APPDATA 'Microsoft\AddIns'))
    if ($script:ExcelDir) { $dirs += (Join-Path $script:ExcelDir 'XLSTART') }
    $startFiles = @()
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $d -File -Force -ErrorAction SilentlyContinue)) {
            Out-Line ('    {0}  {1}' -f $f.LastWriteTime.ToString('dd/MM/yyyy'), $f.FullName)
            if ($d -match 'XLSTART') { $startFiles += $f }
        }
    }
    Snap 'Excel.XLSTART' (($startFiles | ForEach-Object { $_.Name }) -join ' | ')
    if ($startFiles.Count -gt 0) {
        Add-Finding 'CANHBAO' ("Có file tự mở cùng Excel trong XLSTART: {0}" -f (($startFiles | ForEach-Object { $_.Name }) -join ', ')) 'Profile mới không có các file này. PERSONAL.XLSB có thể đặt chế độ tính toán Manual (hàm VietQR không cập nhật) hoặc trùng tên macro. Thử: Formulas > Calculation Options = Automatic; hoặc tạm di chuyển file ra khỏi XLSTART rồi mở lại Excel.'
    }
    $xlb = @(Get-ChildItem -LiteralPath (Join-Path $env:APPDATA 'Microsoft\Excel') -Filter '*.xlb' -File -ErrorAction SilentlyContinue)
    foreach ($x in $xlb) { Note ("File thanh công cụ: {0} ({1:N0} KB)" -f $x.FullName, ($x.Length / 1KB)) }
    $ui = Join-Path $env:LOCALAPPDATA 'Microsoft\Office\Excel.officeUI'
    if (Test-Path -LiteralPath $ui) { Note "Có tùy biến Ribbon: $ui" }
} catch { Note "Lỗi khi đọc XLSTART: $($_.Exception.Message)" }

try {
    Out-Line ''
    Out-Line '  >> COM add-in của Excel (không phải MyExcel nhưng có thể xung đột):' 'White'
    $comRoots = @(
        'HKCU:\Software\Microsoft\Office\Excel\Addins',
        'HKLM:\SOFTWARE\Microsoft\Office\Excel\Addins',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Excel\Addins',
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\REGISTRY\MACHINE\Software\Microsoft\Office\Excel\Addins',
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\REGISTRY\MACHINE\Software\Wow6432Node\Microsoft\Office\Excel\Addins'
    )
    $comList = @()
    foreach ($r in $comRoots) {
        foreach ($k in (Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue)) {
            $lb = $k.GetValue('LoadBehavior')
            $state = if ($null -eq $lb) { '(không đặt LoadBehavior)' } else {
                switch ([int]$lb) { 0 { 'tắt' } 1 { 'đã nạp (không tự nạp)' } 2 { 'tự nạp nhưng chưa nạp được' } 3 { 'tự nạp khi mở Excel' } 8 { 'nạp khi cần' } 9 { 'nạp khi cần (đã nạp)' } 16 { 'nạp lần đầu' } default { "LoadBehavior=$lb" } }
            }
            $scope = if ($r -like 'HKCU*') { 'user' } else { 'máy' }
            Out-Line ('    [{0}] {1,-45} {2}' -f $scope, $k.PSChildName, $state)
            $comList += "$($k.PSChildName)=$lb"
        }
    }
    if ($comList.Count -eq 0) { Ok 'Không có COM add-in.' }
    Snap 'AddIns.COM' ($comList -join ' | ')
} catch { Note "Lỗi khi đọc COM add-in: $($_.Exception.Message)" }
