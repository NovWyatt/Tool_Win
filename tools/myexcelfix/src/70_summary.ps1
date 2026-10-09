
# ----------------------------------------------------------------------------
Section '12. SO SÁNH VỚI PROFILE KHÁC TRÊN CÙNG MÁY'
$outDir = if ($env:MYX_OUT) { $env:MYX_OUT } else { Join-Path $env:PUBLIC 'Documents\MyExcelCheck' }
$stamp = $script:Started.ToString('yyyyMMdd_HHmmss')
$safeUser = ($env:USERNAME -replace '[^\w\.-]', '_')
try {
    if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $snapFile = Join-Path $outDir ("snapshot_{0}_{1}.json" -f $env:COMPUTERNAME, $safeUser)
    $others = @(Get-ChildItem -LiteralPath $outDir -Filter ("snapshot_{0}_*.json" -f $env:COMPUTERNAME) -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $snapFile })
    if ($others.Count -eq 0) {
        Note 'Chưa có kết quả của profile nào khác.'
        Note '=> Hãy chạy file .bat này thêm 1 lần trong PROFILE MỚI (profile tạo VietQR được).'
        Note '   Lần chạy thứ 2 sẽ tự in ra bảng khác biệt giữa 2 profile tại mục này.'
    }
    foreach ($of in $others) {
        # Một snapshot hỏng (ghi dở, sửa tay) chỉ bỏ qua file đó, không chặn so sánh và lưu snapshot của lần này
        try { $o = Get-Content -LiteralPath $of.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        catch { Note "Bỏ qua snapshot hỏng $($of.Name): $($_.Exception.Message)"; continue }
        if (-not $o) { Note "Bỏ qua snapshot rỗng $($of.Name)"; continue }
        $oName = $o.'_User'
        Out-Line ''
        Out-Line ("  >> Khác biệt: profile NÀY ({0})  vs  profile '{1}' (chạy lúc {2})" -f $env:USERNAME, $oName, $o.'_Time') 'White'
        $keys = @($script:Snap.Keys) + @($o.PSObject.Properties.Name | Where-Object { $_ -notlike '_*' }) | Sort-Object -Unique
        $diff = 0
        foreach ($k in $keys) {
            $a = if ($script:Snap.Contains($k)) { [string]$script:Snap[$k] } else { '(không có)' }
            $bp = $o.PSObject.Properties[$k]
            $b = if ($bp) { [string]$bp.Value } else { '(không có)' }
            if ($a -cne $b) {
                $diff++
                Out-Line ("    {0}" -f $k) 'Yellow'
                Out-Line ("        profile này : {0}" -f $a)
                Out-Line ("        '{0}' : {1}" -f $oName, $b)
            }
        }
        if ($diff -eq 0) { Ok 'Không có khác biệt ở các mục đã đo.' }
        else { Note "=> $diff mục khác nhau. Các mục Sec.*, AddIns.*, Temp.*, Path.*, Region.* khác nhau chính là nghi phạm hàng đầu." }
    }
    $script:Snap['_User'] = $env:USERNAME
    $script:Snap['_Time'] = $script:Started.ToString('dd/MM/yyyy HH:mm')
    [IO.File]::WriteAllText("$snapFile.tmp", ($script:Snap | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath "$snapFile.tmp" -Destination $snapFile -Force -ErrorAction Stop
} catch { Note "Lỗi khi so sánh profile: $($_.Exception.Message)" }

# ----------------------------------------------------------------------------
Section 'KẾT LUẬN & HƯỚNG GIẢI QUYẾT'
$order = @{ 'LOI' = 0; 'CANHBAO' = 1; 'THONGTIN' = 2 }
$sorted = @($script:Findings | Sort-Object @{ Expression = { $order[$_.Level] } }, Idx)
$nLoi = @($sorted | Where-Object Level -eq 'LOI').Count
$nWarn = @($sorted | Where-Object Level -eq 'CANHBAO').Count
Info 'Số mục LỖI (nhiều khả năng là nguyên nhân)' $nLoi
Info 'Số mục CẢNH BÁO (có thể liên quan)' $nWarn
$i = 0
foreach ($f in $sorted) {
    $i++
    $label = switch ($f.Level) { 'LOI' { '[LỖI]' } 'CANHBAO' { '[CẢNH BÁO]' } default { '[THÔNG TIN]' } }
    $color = switch ($f.Level) { 'LOI' { 'Red' } 'CANHBAO' { 'Yellow' } default { 'DarkYellow' } }
    Out-Line ''
    Out-Line ("  {0}. {1} {2}  ({3})" -f $i, $label, $f.Title, $f.Code) $color
    Out-Line ("     => Cách xử lý: {0}" -f $f.Fix) 'Green'
}
if ($sorted.Count -eq 0) { Ok 'Không phát hiện bất thường ở các mục đã kiểm tra.' }

Out-Line ''
Out-Line '  CÁCH NHANH: chạy FixMyExcel_VietQR.bat trong profile lỗi. Script tự làm phần lớn các bước dưới (không đổi' 'Green'
Out-Line '  Macro/Protected View/ActiveX) và hỏi để đặt lại dữ liệu MyExcel; có sao lưu và file hoàn tác.' 'Green'
Out-Line ''
Out-Line '  QUY TRÌNH XỬ LÝ BẰNG TAY (làm theo thứ tự, thử VietQR sau mỗi bước):' 'Cyan'
$steps = @(
    '1) Đóng hết Excel (kể cả EXCEL.EXE chạy ẩn trong Task Manager).',
    '2) Unblock toàn bộ C:\MyExcel: mở PowerShell gõ  Get-ChildItem -LiteralPath C:\MyExcel -Recurse | Unblock-File',
    '3) Mở Excel > File > Options > Trust Center > Trust Center Settings:',
    '     - Trusted Locations: có C:\MyExcel và TÍCH "Subfolders of this location are also trusted".',
    '     - Macro Settings: chọn "Enable VBA macros" + tích "Trust access to the VBA project object model".',
    '     - Protected View: bỏ cả 3 dấu tích.   - ActiveX Settings: "Enable all controls without restrictions".',
    '4) File > Options > Add-ins > Manage: Disabled Items > Go: Enable mọi mục MyExcel/QR nếu có.',
    '5) Manage: Excel Add-ins > Go: chỉ để 1 MyExcel trỏ tới C:\MyExcel (bỏ tích bản sao ở nơi khác).',
    '6) Mini Tool > Tạo QR Code: TẮT rồi BẬT lại hàm QR, đóng mở lại Excel.',
    '7) Nếu vẫn lỗi: đóng Excel, xóa cache  del /s /q "%TEMP%\*.exd"  và dọn thư mục %TEMP%.',
    '8) Vẫn lỗi => đặt lại dữ liệu MyExcel của profile (cách đã sửa được lỗi "profile mới chạy, profile cũ không"):',
    '     reg export "HKCU\Software\VB and VBA Program Settings" "%USERPROFILE%\Desktop\MyExcel_data_backup.reg"',
    '     rồi trong regedit xóa các nhánh tên chỉ gồm chữ i/l (vd liliiliiliiiliilli, liliiliiliiiliill) dưới key đó,',
    '     mở Excel, TẮT/BẬT hàm QR và khai báo lại tài khoản ngân hàng.',
    '9) Vẫn lỗi => reset riêng cấu hình Excel của profile (giống profile mới, không cần tạo user mới):',
    '     reg export "HKCU\Software\Microsoft\Office\16.0\Excel" "%USERPROFILE%\Desktop\Excel_backup.reg"',
    '     rồi đổi tên key HKCU\Software\Microsoft\Office\16.0\Excel thành Excel_old (bằng regedit),',
    '     mở Excel và làm lại các bước cài MyExcel (Trust Center + Add-in). Có thể khôi phục bằng file .reg.'
)
foreach ($s in $steps) { Out-Line "  $s" }

# ----------------------------------------------------------------------------
# Mã thoát: 0 kiểm tra xong (kể cả khi có phát hiện), 1 không ghi được báo cáo, 2 chạy sai tài khoản (kết quả không dùng được)
$exitCode = 0
$reason = 'XONG'; $reasonText = 'Đã kiểm tra xong.'
if (@($script:Findings | Where-Object Code -eq 'SAI_TAI_KHOAN').Count -gt 0) {
    $exitCode = 2; $reason = 'SAI_TAI_KHOAN'; $reasonText = 'Chạy sai tài khoản Windows nên kết quả không phải của profile bị lỗi.'
}
$reportPath = $null
try {
    $elapsed = [math]::Round(((Get-Date) - $script:Started).TotalSeconds, 0)
    Out-Line ''
    Out-Line "  (Thời gian kiểm tra: $elapsed giây)" 'DarkGray'
    if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop | Out-Null }
    $reportName = "BaoCao_MyExcel_{0}_{1}_{2}.txt" -f $env:COMPUTERNAME, $safeUser, $stamp
    $reportPath = Join-Path $outDir $reportName
    $utf8Bom = New-Object Text.UTF8Encoding $true
    [IO.File]::WriteAllLines($reportPath, $script:Report.ToArray(), $utf8Bom)
    $deskCopy = $null
    if (-not $env:MYX_OUT) {
        try {
            $deskCopy = Join-Path ([Environment]::GetFolderPath('Desktop')) $reportName
            [IO.File]::WriteAllLines($deskCopy, $script:Report.ToArray(), $utf8Bom)
        } catch { $deskCopy = $null }
    }
    Write-Host ''
    Write-Host (Txt "  Đã lưu báo cáo: $reportPath") -ForegroundColor Cyan
    if ($deskCopy) { Write-Host (Txt "  Bản sao trên Desktop: $deskCopy") -ForegroundColor Cyan }
    Write-Host (Txt '  => Gửi file báo cáo này (của CẢ profile lỗi và profile mới nếu có) cho kỹ thuật.') -ForegroundColor Cyan
    Write-Host '  (Chu tieng Viet tren man hinh bi loi font? Mo file bao cao bang Notepad - file luon dung chinh ta.)' -ForegroundColor DarkGray
    if (-not $env:MYX_NO_NOTEPAD) { Start-Process notepad.exe -ArgumentList "`"$reportPath`"" }
} catch {
    Write-Host (Txt "Không ghi được báo cáo: $($_.Exception.Message)") -ForegroundColor Red
    $exitCode = 1; $reason = 'BAO_CAO_LOI'; $reasonText = "Không ghi được báo cáo: $($_.Exception.Message)"
    $reportPath = $null
}

# Kết quả máy đọc được cho Trạm Tool: mỗi phát hiện có mã ổn định, mức độ, cách sửa
$levelMap = @{ 'LOI' = 'loi'; 'CANHBAO' = 'canh-bao'; 'THONGTIN' = 'thong-tin' }
$result = [ordered]@{
    congCu = 'myexcelfix'; cheDo = 'kiem-tra'; phienBan = $script:Version
    may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
    batDau = $script:Started.ToString('s'); ketThuc = (Get-Date).ToString('s')
    maThoat = $exitCode; trangThai = $(switch ($exitCode) { 0 { 'xong' } 2 { 'thieu-dieu-kien' } default { 'loi' } })
    ma = $reason; thongDiep = $reasonText
    tomTat = [ordered]@{ loi = $nLoi; canhBao = $nWarn; thongTin = ($sorted.Count - $nLoi - $nWarn) }
    phatHien = @($sorted | ForEach-Object { [ordered]@{ ma = $_.Code; mucDo = $levelMap[$_.Level]; tieuDe = $_.Title; cachSua = $_.Fix } })
    baoCao = $reportPath
}
try {
    if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop | Out-Null }
    $jsonPath = Join-Path $outDir ("KetQua_MyExcel_KiemTra_{0}_{1}_{2}.json" -f $env:COMPUTERNAME, $safeUser, $stamp)
    [IO.File]::WriteAllText($jsonPath, ($result | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
    Write-Host (Txt "  Kết quả (JSON): $jsonPath") -ForegroundColor DarkGray
} catch { Write-Host (Txt "  Không ghi được file kết quả JSON: $($_.Exception.Message)") -ForegroundColor DarkGray }
if ($exitCode -eq 2) { Write-Host (Txt '  => Kết quả này KHÔNG dùng được: chạy lại bằng double-click trong đúng profile bị lỗi.') -ForegroundColor Red }
exit $exitCode
