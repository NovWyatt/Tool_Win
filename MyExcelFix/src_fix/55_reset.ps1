
# ----------------------------------------------------------------------------
$script:BankBins = @{
    '970436' = 'Vietcombank'; '970415' = 'VietinBank'; '970418' = 'BIDV'; '970405' = 'Agribank'; '970422' = 'MB Bank'
    '970407' = 'Techcombank'; '970416' = 'ACB'; '970432' = 'VPBank'; '970423' = 'TPBank'; '970403' = 'Sacombank'
    '970437' = 'HDBank'; '970441' = 'VIB'; '970443' = 'SHB'; '970431' = 'Eximbank'; '970426' = 'MSB'
    '970448' = 'OCB'; '970440' = 'SeABank'; '970449' = 'LPBank'; '970454' = 'BVBank'; '970429' = 'SCB'
    '970428' = 'Nam A Bank'; '970409' = 'Bac A Bank'; '970412' = 'PVcomBank'; '970425' = 'ABBANK'; '970427' = 'VietABank'
    '970452' = 'KienlongBank'; '970419' = 'NCB'; '970433' = 'VietBank'; '970438' = 'BaoViet Bank'; '970400' = 'Saigonbank'
    '970430' = 'PGBank'; '970424' = 'Shinhan Bank'
}

function Get-DeclaredBank {
    foreach ($n in (Get-MyExcelStateKeys)) {
        $k = Open-UserKey "Software\VB and VBA Program Settings\$n\GridLight"
        if (-not $k) { continue }
        $name = [string]$k.GetValue('TenTKQRG'); $acct = [string]$k.GetValue('SoTKQRG'); $emv = [string]$k.GetValue('MaNganhangDongDauQR1')
        $k.Close()
        if (-not $name -and -not $acct) { continue }
        $bin = if ($emv -match 'A000000727\d{4}0006(\d{6})') { $Matches[1] } else { '' }
        $bank = if ($bin -and $script:BankBins.ContainsKey($bin)) { $script:BankBins[$bin] } elseif ($bin) { "mã BIN $bin" } else { '(không rõ ngân hàng)' }
        return [pscustomobject]@{ Name = $name; Account = $acct; Bin = $bin; Bank = $bank }
    }
    return $null
}

function Save-DeclaredBank {
    # Ghi thông tin tài khoản ra thư mục sao lưu để khai báo lại; màn hình và nhật ký chỉ hiện số đã che
    $b = Get-DeclaredBank
    if (-not $b) { Note 'Profile này chưa khai báo tài khoản ngân hàng trong MyExcel.'; return }
    $masked = if ($b.Account.Length -gt 4) { ('*' * ($b.Account.Length - 4)) + $b.Account.Substring($b.Account.Length - 4) } else { $b.Account }
    Note "Tài khoản đang khai báo: $($b.Bank) - số TK $masked - $($b.Name)"
    $file = Join-Path $script:BackupDir 'ThongTinKhaiBao.txt'
    $lines = @(
        'THÔNG TIN TÀI KHOẢN ĐÃ KHAI BÁO TRONG MYEXCEL (để khai báo lại sau khi đặt lại dữ liệu)'
        "Máy: $env:COMPUTERNAME   User: $env:USERNAME   Lúc: $((Get-Date).ToString('dd/MM/yyyy HH:mm'))"
        ''
        "Ngân hàng    : $($b.Bank)$(if ($b.Bin) { " (BIN $($b.Bin))" })"
        "Số tài khoản : $($b.Account)"
        "Tên tài khoản: $($b.Name)"
        ''
        'Khai báo lại: Excel > Mini Tool > Tạo QR Code > Tạo QR Code tài khoản ngân hàng > Khai báo.'
        'Các cài đặt MyExcel cũ khác (In vùng, QR hàng loạt...) xem trong VBA_Settings.reg (mở bằng Notepad).'
    )
    try {
        [IO.File]::WriteAllLines($file, [string[]]$lines, (New-Object Text.UTF8Encoding $true))
        Note "Đã lưu thông tin để khai báo lại: $file"
    } catch { Warn "Không ghi được $file : $($_.Exception.Message)" }
}

function Invoke-MyExcelReset([bool]$Confirm = $true) {
    Step 'ĐẶT LẠI DỮ LIỆU MYEXCEL CỦA PROFILE NÀY (giống profile mới)'
    $names = @(Get-MyExcelStateKeys)
    if ($names.Count -eq 0) { Skip 'Profile này không có dữ liệu MyExcel để đặt lại'; return $false }
    if (-not $script:Manifest.RegVB) { Warn 'Chưa sao lưu được dữ liệu MyExcel nên không đặt lại.'; return $false }
    Note ('Sẽ xóa: ' + (($names | ForEach-Object { "HKCU\Software\VB and VBA Program Settings\$_" }) -join ' ; '))
    Save-DeclaredBank
    Note 'Sau khi đặt lại, mọi tùy chọn MyExcel của profile (tài khoản ngân hàng, In vùng, QR hàng loạt...) về mặc định.'
    Note 'Nếu MyExcel đòi kích hoạt bản quyền: nhập lại key hoặc liên hệ MyExcel. HoanTac sẽ đưa dữ liệu cũ (và lỗi cũ) trở lại.'
    if ($Confirm -and -not (Ask 'Đặt lại dữ liệu MyExcel ngay bây giờ?')) { Skip 'Không đặt lại dữ liệu MyExcel'; return $false }
    if (-not (Wait-ExcelClosed)) { Warn 'Excel chưa đóng nên chưa đặt lại.'; return $false }
    $root = Open-UserKey 'Software\VB and VBA Program Settings' $true
    $ok = $false
    foreach ($n in $names) {
        try {
            $root.DeleteSubKeyTree($n, $false)
            $script:Manifest.ResetKeys += "Software\VB and VBA Program Settings\$n"
            $ok = $true
            Done "Xóa dữ liệu MyExcel: $n"
        } catch { Warn "Không xóa được $n : $($_.Exception.Message)" }
    }
    $root.Close()
    Save-Manifest
    return $ok
}
