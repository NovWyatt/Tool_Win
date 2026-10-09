
# ----------------------------------------------------------------------------
Section '6. TRUST CENTER CỦA PROFILE NÀY (Macro, Protected View, ActiveX, Trusted Locations)'
try {
    $ver = if ($script:OfficeVers -contains '16.0') { '16.0' } elseif ($script:OfficeVers.Count -gt 0) { $script:OfficeVers[-1] } else { '16.0' }
    $sec = "HKCU:\Software\Microsoft\Office\$ver\Excel\Security"
    $pol = "HKCU:\Software\Policies\Microsoft\Office\$ver\Excel\Security"
    Info 'Đang đọc cấu hình Office' $ver
    Read-TrustedLocations
    # MyExcel nằm hết trong Trusted Locations (có thư mục con) thì Macro Settings / MOTW không chặn được add-in
    $myxTrusted = ($script:ActiveRoots.Count -gt 0) -and -not ($script:ActiveRoots | Where-Object { -not (Test-TrustedDir $_ -WithSubfolders) })

    # --- Macro settings
    $vw = Get-RegValue $sec 'VBAWarnings'; $vwp = Get-RegValue $pol 'VBAWarnings'
    $eff = if ($null -ne $vwp) { $vwp } elseif ($null -ne $vw) { $vw } else { 2 }
    $txt = switch ($eff) { 1 { 'Enable VBA macros (bật tất cả)' } 2 { 'Disable VBA macros with notification (mặc định)' } 3 { 'Disable except digitally signed' } 4 { 'Disable without notification' } default { "giá trị $eff" } }
    $src = if ($null -ne $vwp) { ' [bị Group Policy ép]' } else { '' }
    Info 'Macro Settings' "$txt$src"
    Snap 'Sec.VBAWarnings' "$eff$src"
    if ($eff -ne 1 -and $myxTrusted) {
        Add-Finding 'MACRO_DA_TIN_CAY' 'THONGTIN' "Macro Settings đang là '$txt' nhưng thư mục MyExcel nằm trong Trusted Locations nên macro MyExcel/QR vẫn chạy - không phải nguyên nhân" 'Chỉ file .xlsm nằm ngoài Trusted Locations mới phải bấm Enable Content. Muốn đúng hướng dẫn MyExcel: Trust Center > Macro Settings > "Enable VBA macros".'
    } elseif ($eff -ne 1) {
        Add-Finding 'MACRO_BI_CHAN' 'LOI' "Macro Settings đang là '$txt' và thư mục MyExcel chưa nằm hết trong Trusted Locations => macro MyExcel/QR bị chặn" 'Excel > File > Options > Trust Center > Trust Center Settings > Macro Settings > chọn "Enable VBA macros" (mục cuối), hoặc thêm C:\MyExcel vào Trusted Locations (tích thư mục con) > OK > đóng mở lại Excel.'
    } else { Ok 'Macro Settings = Enable VBA macros' }

    $vbom = Get-RegValue $sec 'AccessVBOM'; $vbomp = Get-RegValue $pol 'AccessVBOM'
    $vbomEff = if ($null -ne $vbomp) { $vbomp } else { $vbom }
    Info 'Trust access to VBA project object model' ($(if ($vbomEff -eq 1) { 'bật' } else { 'TẮT' }))
    Snap 'Sec.AccessVBOM' $vbomEff
    if ($vbomEff -ne 1) {
        Add-Finding 'VBA_OM_CHUA_BAT' 'THONGTIN' 'Chưa tích "Trust access to the VBA project object model" (mặc định, không cần cho VietQR)' 'Chỉ bật khi tính năng tạo nút/code của MyExcel báo lỗi: Trust Center > Macro Settings > tích "Trust access to the VBA project object model".'
    }

    # --- Protected View
    $pv = "$sec\ProtectedView"
    $pvNames = [ordered]@{ 'DisableInternetFilesInPV' = 'File từ Internet'; 'DisableUnsafeLocationsInPV' = 'File ở vị trí không an toàn'; 'DisableAttachementsInPV' = 'File đính kèm Outlook' }
    $pvOn = @(); $pvOnKeys = @()
    foreach ($n in $pvNames.Keys) {
        $val = Get-RegValue "$pol\ProtectedView" $n
        if ($null -eq $val) { $val = Get-RegValue $pv $n }
        $on = ($val -ne 1)
        Info "Protected View - $($pvNames[$n])" ($(if ($on) { 'ĐANG BẬT' } else { 'đã tắt' }))
        Snap "Sec.PV.$n" $val
        if ($on) { $pvOn += $pvNames[$n]; $pvOnKeys += $n }
    }
    if (@($pvOnKeys | Where-Object { $_ -ne 'DisableAttachementsInPV' }).Count -gt 0) {
        Add-Finding 'PROTECTED_VIEW' 'CANHBAO' ("Protected View còn bật: {0}. File Excel tải về (Zalo/Mail/Internet) mở ở chế độ bảo vệ, phải bấm Enable Editing thì hàm QR mới tính; không làm hỏng việc bật hàm QR" -f ($pvOn -join ', ')) 'Trust Center > Protected View > bỏ các dấu tích > OK (đúng hướng dẫn của MyExcel).'
    } elseif ($pvOn.Count -gt 0) {
        Add-Finding 'PROTECTED_VIEW_OUTLOOK' 'THONGTIN' 'Protected View chỉ còn bật cho file đính kèm Outlook - không liên quan VietQR' 'Không cần xử lý.'
    } else { Ok 'Protected View đã tắt cả 3 mục' }

    # --- ActiveX
    $ax = 'HKCU:\Software\Microsoft\Office\Common\Security'
    $axp = 'HKCU:\Software\Policies\Microsoft\Office\Common\Security'
    $dis = Get-RegValue $axp 'DisableAllActiveX'; if ($null -eq $dis) { $dis = Get-RegValue $ax 'DisableAllActiveX' }
    $ufi = Get-RegValue $axp 'UFIControls'; if ($null -eq $ufi) { $ufi = Get-RegValue $ax 'UFIControls' }
    $axTxt = if ($dis -eq 1) { 'Disable all controls without notification (CHẶN HẾT)' } elseif ($ufi -eq 1) { 'Enable all controls without restrictions' } elseif ($null -eq $ufi) { 'mặc định (Prompt me before enabling...)' } else { "giới hạn (UFIControls=$ufi)" }
    Info 'ActiveX Settings' $axTxt
    Snap 'Sec.ActiveX' "DisableAll=$dis;UFI=$ufi"
    if ($dis -eq 1) {
        Add-Finding 'ACTIVEX_CHAN_HET' 'LOI' 'ActiveX đang CHẶN tất cả control => form Khai báo/Tạo QR của MyExcel báo lỗi' 'Trust Center > ActiveX Settings > chọn "Enable all controls without restrictions and without prompting" > OK (https://myexcel.vn/loi-khai-bao-activex-setting-myexcel/).'
    } elseif ($ufi -ne 1) {
        Add-Finding 'ACTIVEX_CHUA_MO' 'CANHBAO' 'ActiveX chưa đặt "Enable all controls without restrictions" như hướng dẫn cài MyExcel' 'Trust Center > ActiveX Settings > chọn "Enable all controls without restrictions and without prompting" > OK.'
    } else { Ok 'ActiveX = Enable all controls' }

    # --- Trust Center > Add-ins
    $reqSig = Get-RegValue $pol 'RequireAddinSig'; if ($null -eq $reqSig) { $reqSig = Get-RegValue $sec 'RequireAddinSig' }
    $disAdd = Get-RegValue $pol 'DisableAllAddins'; if ($null -eq $disAdd) { $disAdd = Get-RegValue $sec 'DisableAllAddins' }
    Info 'Add-ins: bắt buộc chữ ký số' ($(if ($reqSig -eq 1) { 'CÓ' } else { 'không' }))
    Info 'Add-ins: Disable all Application Add-ins' ($(if ($disAdd -eq 1) { 'CÓ' } else { 'không' }))
    Snap 'Sec.AddinsPolicy' "RequireSig=$reqSig;DisableAll=$disAdd"
    if ($disAdd -eq 1) {
        Add-Finding 'ADDIN_TAT_HET' 'LOI' 'Trust Center đang bật "Disable all Application Add-ins" => mọi add-in (kể cả MyExcel/QR) bị tắt' 'Trust Center > Add-ins > bỏ tích "Disable all Application Add-ins" > OK > mở lại Excel.'
    }
    if ($reqSig -eq 1) {
        Add-Finding 'ADDIN_CAN_KY_SO' 'CANHBAO' 'Trust Center bắt buộc add-in phải có chữ ký số (MyExcel không ký số)' 'Trust Center > Add-ins > bỏ tích "Require Application Add-ins to be signed by Trusted Publisher".'
    }
} catch { Note "Lỗi khi đọc Macro/PV/ActiveX: $($_.Exception.Message)" }

try {
    # --- Trusted Locations
    $tlRoot = "$sec\Trusted Locations"
    $allDis = Get-RegValue $tlRoot 'AllLocationsDisabled'
    $allowNet = Get-RegValue $tlRoot 'AllowNetworkLocations'
    Info 'Disable all Trusted Locations' ($(if ($allDis -eq 1) { 'ĐANG BẬT (mọi vị trí tin cậy bị vô hiệu)' } else { 'không' }))
    Info 'Allow Trusted Locations on network' ($(if ($allowNet -eq 1) { 'có' } else { 'không' }))
    if ($allDis -eq 1) {
        Add-Finding 'TRUSTED_LOC_TAT' 'LOI' 'Đang tích "Disable all Trusted Locations" => C:\MyExcel không được tin cậy' 'Trust Center > Trusted Locations > bỏ tích "Disable all Trusted Locations".'
    }
    $locs = @($script:TlLocs)
    foreach ($l in $locs) {
        $mark = if ($script:MyxRoots | Where-Object { Test-UnderPath $_ $l.Path }) { '  <== MyExcel' } else { '' }
        Out-Line ('    {0}  [subfolders: {1}]{2}{3}' -f $l.Path, ($(if ($l.Sub) { 'có' } else { 'KHÔNG' })), ($(if ($l.Policy) { ' [policy]' } else { '' })), $mark)
    }
    Snap 'Sec.TrustedLocations' (($locs | ForEach-Object { "$($_.Path)[sub=$($_.Sub)]" }) -join ' | ')
    $polUserLoc = Get-RegValue "HKCU:\Software\Policies\Microsoft\Office\$ver\Common\Security\Trusted Locations" 'Allow User Locations'
    if (($locs | Where-Object Policy) -and $polUserLoc -ne 1) {
        Add-Finding 'TRUSTED_LOC_POLICY' 'CANHBAO' 'Group Policy đặt Trusted Locations riêng và có thể bỏ qua vị trí do user tự thêm' 'Cần admin/IT thêm C:\MyExcel vào policy Trusted Locations hoặc bật "Allow mix of policy and user locations".'
    }

    foreach ($root in $script:MyxRoots) {
        $cov = $locs | Where-Object { (Test-SamePath $root $_.Path) -or ((Test-UnderPath $root $_.Path) -and $_.Sub) }
        $covSub = $locs | Where-Object { (Test-UnderPath $root $_.Path) -and $_.Sub }
        if ($cov) { $script:TlCoversRoot = $true }
        $qrDirs = @($script:QrFiles | Where-Object { Test-UnderPath $_ $root } | ForEach-Object { Split-Path $_ -Parent } | Sort-Object -Unique)
        $qrOk = $true
        foreach ($qd in $qrDirs) {
            if (-not ($locs | Where-Object { (Test-SamePath $qd $_.Path) -or ((Test-UnderPath $qd $_.Path) -and $_.Sub) })) { $qrOk = $false }
        }
        if ($qrDirs.Count -gt 0 -and $qrOk) { $script:TlCoversQr = $true }
        if (-not $cov) {
            Add-Finding 'THU_MUC_CHUA_TIN_CAY' 'LOI' "Thư mục $root CHƯA nằm trong Trusted Locations của profile này (profile mới đã khai báo nên chạy được)" "Trust Center > Trusted Locations > Add new location > Browse chọn $root > TÍCH 'Subfolders of this location are also trusted' > OK."
        } elseif (-not $qrOk) {
            Add-Finding 'THU_MUC_CON_CHUA_TIN_CAY' 'LOI' "Đã khai báo $root nhưng KHÔNG tích 'Subfolders of this location are also trusted' => file QR Code trong thư mục con (Mini Tool) không được tin cậy" "Trust Center > Trusted Locations > chọn dòng $root > Modify > tích 'Subfolders of this location are also trusted' > OK."
        } elseif (-not $covSub) {
            Add-Finding 'THU_MUC_CON_CHUA_TIN_CAY' 'CANHBAO' "Đã khai báo $root nhưng không tích 'Subfolders of this location are also trusted'" "Trust Center > Trusted Locations > chọn dòng $root > Modify > tích 'Subfolders of this location are also trusted' > OK."
        } else { Ok "Trusted Locations đã gồm $root và thư mục con" }
    }
    Snap 'Sec.TL.CoversMyExcel' "$($script:TlCoversRoot)|QR=$($script:TlCoversQr)"
} catch { Note "Lỗi khi đọc Trusted Locations: $($_.Exception.Message)" }

try {
    # --- File Block, Trusted Documents, policy chặn macro Internet, Attachment Manager
    $fb = @(Get-RegValues "$sec\FileBlock") + @(Get-RegValues "$pol\FileBlock")
    $fbOn = @($fb | Where-Object { $_.Kind -eq 'DWord' -and $_.Name -ne 'OpenInProtectedView' -and [int]$_.Value -ge 1 })
    foreach ($f in $fbOn) { Note "File Block: $($f.Name) = $($f.Value)" }
    Snap 'Sec.FileBlock' (($fbOn | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' | ')
    if ($fbOn.Count -gt 0) {
        Add-Finding 'FILE_BLOCK' 'CANHBAO' ("Trust Center > File Block Settings đang chặn một số loại file: {0}" -f (($fbOn | ForEach-Object { $_.Name }) -join ', ')) 'Trust Center > File Block Settings > bỏ tích Open/Save của các loại Excel Add-in / Excel 97-2003 rồi OK.'
    }
    $blk = Get-RegValue $pol 'blockcontentexecutionfrominternet'
    Info 'Policy chặn macro file từ Internet' ($(if ($null -eq $blk) { 'không đặt (Office vẫn chặn file có MOTW)' } else { $blk }))
    Snap 'Sec.BlockInternetMacrosPolicy' $blk
    $td = "$sec\Trusted Documents"
    $disTd = Get-RegValue $td 'DisableTrustedDocuments'
    $tr = @(Get-RegValues "$td\TrustRecords")
    Info 'Trusted Documents' ("tắt={0}; số file đã tin cậy={1}" -f ($disTd -eq 1), $tr.Count)
    foreach ($t in ($tr | Where-Object { Test-Related $_.Name })) { Note "Tin cậy: $($t.Name)" }
    $sz = Get-RegValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Attachments' 'SaveZoneInformation'
    Info 'Windows ghi dấu MOTW cho file tải về' ($(if ($sz -eq 1) { 'KHÔNG (policy tắt)' } else { 'có (mặc định)' }))
    Snap 'Win.SaveZoneInformation' $sz

    $polLines = @()
    foreach ($pr in 'HKCU:\Software\Policies\Microsoft\Office', 'HKLM:\SOFTWARE\Policies\Microsoft\Office') {
        if (-not (Test-Path $pr)) { continue }
        foreach ($k in @(Get-Item $pr) + @(Get-ChildItem -LiteralPath $pr -Recurse -ErrorAction SilentlyContinue)) {
            foreach ($n in $k.GetValueNames()) { $polLines += ('{0}\{1} = {2}' -f ($k.Name -replace '^HKEY_(CURRENT_USER|LOCAL_MACHINE)\\SOFTWARE\\Policies\\Microsoft\\Office', ''), $n, (Format-RegData $k.GetValue($n))) }
        }
    }
    if ($polLines.Count -gt 0) {
        Add-Finding 'GROUP_POLICY_OFFICE' 'THONGTIN' "Máy có $($polLines.Count) giá trị Group Policy cho Office (liệt kê bên dưới)" 'Policy có thể ghi đè cài đặt Trust Center; cần quyền admin để đổi.'
        foreach ($l in ($polLines | Select-Object -First 60)) { Note $l }
    }
    Snap 'Sec.OfficePolicies' ($polLines -join ' | ')
} catch { Note "Lỗi khi đọc File Block/Policy: $($_.Exception.Message)" }

try {
    # --- Dữ liệu MyExcel lưu bằng VBA SaveSetting (theo từng user)
    $vbRoot = if ($env:MYX_VBROOT) { $env:MYX_VBROOT } else { 'HKCU:\Software\VB and VBA Program Settings' }   # MYX_VBROOT chỉ dùng khi test
    Out-Line ''
    Out-Line '  >> Cài đặt VBA lưu theo user (HKCU\Software\VB and VBA Program Settings):' 'White'
    $apps = @(Get-ChildItem -LiteralPath $vbRoot -ErrorAction SilentlyContinue)
    if ($apps.Count -eq 0) { Note '(không có)' }
    $names = @()
    $bankRx = '(?i)myexcel|qr|bank|ngan.?hang|tai.?khoan|stk|mini.?tool|qlvb'
    foreach ($app in $apps) {
        $keys = @(Get-Item -LiteralPath $app.PSPath) + @(Get-ChildItem -LiteralPath $app.PSPath -Recurse -ErrorAction SilentlyContinue)
        foreach ($k in $keys) { $names += ($k.Name -replace '^.*VB and VBA Program Settings\\', '') }
        $rel = ($app.PSChildName -notmatch '(?i)ultraviewer|teamviewer|anydesk') -and
               [bool]($keys | Where-Object { $_.PSChildName -match $bankRx -or (@($_.GetValueNames()) -match $bankRx) })
        if (-not $rel) {
            Out-Line ("    [{0}] ({1} nhánh) - không liên quan" -f $app.PSChildName, $keys.Count)
            continue
        }
        foreach ($k in $keys) {
            $short = $k.Name -replace '^.*VB and VBA Program Settings\\', ''
            $vals = $k.GetValueNames()
            Out-Line ("    [{0}] ({1} giá trị)" -f $short, $vals.Count) 'White'
            foreach ($n in ($vals | Select-Object -First 25)) {
                $d = Hide-Digits (Format-RegData $k.GetValue($n))
                if ($d.Length -gt 80) { $d = $d.Substring(0, 80) + '...' }
                Note ("{0} = {1}" -f $n, $d)
            }
        }
        Add-Finding 'DU_LIEU_VBA_USER' 'THONGTIN' "Có dữ liệu VBA lưu theo user ở nhánh [$($app.PSChildName)] (có thể là tài khoản ngân hàng/cài đặt QR của MyExcel)" 'Profile mới chỉ có dữ liệu này sau khi dùng MyExcel. Nếu mọi mục LỖI đã xử lý mà vẫn lỗi: chạy FixMyExcel_VietQR.bat, ở bước 9 chọn đặt lại dữ liệu MyExcel (có sao lưu), rồi khai báo lại tài khoản ngân hàng.'
    }
    Snap 'VBA.SaveSettingKeys' ($names -join ' | ')

    # Dữ liệu MyExcel tạo từ bản cũ hơn bộ đang dùng: đúng kiểu lỗi "profile mới tạo được VietQR, profile cũ thì không"
    $dataDate = $null
    foreach ($app in ($apps | Where-Object { $_.PSChildName -cmatch '^[il]{12,}[a-z0-9]*$' } | Sort-Object { $_.PSChildName.Length })) {
        $v = [string](Get-RegValue (Join-Path $app.PSPath 'InVung') 'AndanInNgayCai')
        $d = [datetime]::MinValue
        if ($v -and [datetime]::TryParseExact($v.Trim(), [string[]]@('d.M.yyyy', 'd/M/yyyy', 'd-M-yyyy'), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { $dataDate = $d; break }
    }
    if ($dataDate) {
        $xlams = @($script:AddinEntries | Where-Object { $_.Source -eq 'OPEN' -and $_.Path -match '(?i)\\myexcel\.xlam$' -and (Test-Path -LiteralPath $_.Path) } | ForEach-Object { $_.Path }) +
                 @($script:ActiveRoots | ForEach-Object { Join-Path $_ 'MyExcel.xlam' } | Where-Object { Test-Path -LiteralPath $_ })
        Snap 'MyExcel.DataVersion' $dataDate.ToString('yyyy-MM-dd')
        if ($xlams.Count -gt 0) {
            $xlamDate = (Get-Item -LiteralPath $xlams[0] -Force).LastWriteTime
            Info 'Dữ liệu MyExcel tạo từ bản' ('{0} (bộ MyExcel đang dùng: {1})' -f $dataDate.ToString('dd/MM/yyyy'), $xlamDate.ToString('dd/MM/yyyy'))
            if (($xlamDate - $dataDate).TotalDays -gt 30) {
                Add-Finding 'DU_LIEU_MYEXCEL_CU' 'LOI' ('Dữ liệu MyExcel của profile tạo từ bản {0}, cũ hơn bộ MyExcel đang dùng ({1}) - đúng kiểu lỗi đã gặp: profile cũ không bật/tạo được VietQR, profile mới thì được' -f $dataDate.ToString('dd/MM/yyyy'), $xlamDate.ToString('dd/MM/yyyy')) 'Chạy FixMyExcel_VietQR.bat trong profile này, ở bước 9 chọn "Đặt lại dữ liệu MyExcel ngay" (có sao lưu và file hoàn tác), rồi khai báo lại tài khoản ngân hàng.'
            }
        }
    }
} catch { Note "Lỗi khi đọc VB and VBA Program Settings: $($_.Exception.Message)" }
