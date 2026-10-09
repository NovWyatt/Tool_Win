
# ----------------------------------------------------------------------------
Section '2. NGÔN NGỮ, ĐỊNH DẠNG SỐ & ĐƯỜNG DẪN CỦA PROFILE'
try {
    $cp = $script:AnsiEnc.CodePage
    $sysLoc = try { (Get-WinSystemLocale).Name } catch { '?' }
    Info 'Ngôn ngữ non-Unicode (system locale)' "$sysLoc (ANSI code page $cp)"
    $intl = 'HKCU:\Control Panel\International'
    $loc = Get-RegValue $intl 'LocaleName'
    $dec = Get-RegValue $intl 'sDecimal'
    $tho = Get-RegValue $intl 'sThousand'
    $lst = Get-RegValue $intl 'sList'
    $sd  = Get-RegValue $intl 'sShortDate'
    Info 'Định dạng vùng (Region format)' $loc
    Info 'Dấu thập phân / nhóm số / phân cách' ("'{0}'  /  '{1}'  /  '{2}'" -f $dec, $tho, $lst)
    Info 'Kiểu ngày ngắn' $sd
    Snap 'Region.LocaleName' $loc
    Snap 'Region.sDecimal' $dec
    Snap 'Region.sThousand' $tho
    Snap 'Region.sList' $lst
    Snap 'Region.sShortDate' $sd
    if ($dec -ne '.' -or $tho -ne ',') {
        Add-Finding 'DINH_DANG_SO' 'CANHBAO' ("Profile này dùng dấu thập phân '{0}' và nhóm số '{1}' (khác kiểu Mỹ '.' ','). Profile mới thường là mặc định => một số macro xử lý số tiền VietQR có thể lỗi" -f $dec, $tho) 'Thử: Settings > Time & language > Language & region > Regional format = English (United States), hoặc Control Panel > Region > Additional settings: Decimal = "."  Digit grouping = ","; sau đó mở lại Excel và thử tạo VietQR.'
    }
    if ($lst -ne ',' -and $lst -ne ';') {
        Add-Finding 'PHAN_CACH_DANH_SACH' 'CANHBAO' "Ký tự phân cách danh sách (List separator) lạ: '$lst'" 'Đặt lại List separator về "," (hoặc ";") trong Region > Additional settings.'
    }
} catch { Note "Lỗi khi đọc Region: $($_.Exception.Message)" }

try {
    $pathsToCheck = [ordered]@{
        'USERPROFILE'  = $env:USERPROFILE
        'TEMP'         = $env:TEMP
        'TMP'          = $env:TMP
        'APPDATA'      = $env:APPDATA
        'LOCALAPPDATA' = $env:LOCALAPPDATA
    }
    $badPath = @()
    foreach ($k in $pathsToCheck.Keys) {
        $v = $pathsToCheck[$k]
        $safe = Test-AnsiSafe $v
        $flag = if ($safe) { '' } else { '   <== có ký tự Unicode (VBA đọc sai)' }
        Info "%$k%" ("$v$flag")
        if (-not $safe) { $badPath += $k }
    }
    Snap 'Path.UnicodeVars' ($badPath -join ',')
    if ($badPath.Count -gt 0) {
        Add-Finding 'DUONG_DAN_UNICODE' 'LOI' ("Đường dẫn {0} chứa ký tự có dấu/Unicode mà code page {1} không biểu diễn được. VBA (MyExcel) dùng API ANSI nên không tạo/lưu được file ảnh QR tạm. Profile mới tên không dấu nên chạy được" -f ($badPath -join ', '), $script:AnsiEnc.CodePage) 'Cho riêng user này: tạo thư mục C:\Temp rồi chạy trong CMD:  setx TEMP C:\Temp  và  setx TMP C:\Temp  => đăng xuất/đăng nhập lại => thử VietQR. (Nếu chính USERPROFILE có dấu thì cách triệt để là dùng profile tên không dấu.)'
    }
    $userEnv = Get-RegValues 'HKCU:\Environment'
    foreach ($e in $userEnv) {
        if ($e.Name -match '^(TEMP|TMP)$') {
            $raw = (Get-Item 'HKCU:\Environment').GetValue($e.Name, $null, 'DoNotExpandEnvironmentNames')
            Info "HKCU\Environment\$($e.Name)" $raw
        }
    }
} catch { Note "Lỗi khi kiểm tra đường dẫn: $($_.Exception.Message)" }
