# BitLocker - kiểm tra, chỉ đọc. Ghi báo cáo ket_qua\BaoCao_BitLocker_<tên máy>_<thời gian>.txt.
# Báo cáo có Mã khoá (Key ID) để đối chiếu, không bao giờ có khoá khôi phục.

$script:Diag = @{}

function Invoke-Section {
    # Một phần của báo cáo; phần lỗi thì ghi lý do rồi chạy tiếp phần sau.
    param([string]$Title, [scriptblock]$Body)
    Write-Head $Title
    try { & $Body } catch { Write-Warn ('Không đọc được phần này: {0}' -f $_.Exception.Message.Trim()) }
}

function Invoke-KiemTra {
    param([string]$ThuMucKhoa = '')
    $script:Report.Clear(); $script:Findings.Clear()
    $script:Diag = @{ Admin = (Test-IsAdmin); Volumes = @(); VolumeError = $null; Events = @(); SavedKeys = @() }
    $started = Get-Date
    Write-Out 'BÁO CÁO BITLOCKER VÀ KHOÁ KHÔI PHỤC' 'Cyan'
    Write-Out ('Máy {0}, {1:dd/MM/yyyy HH:mm}. Công cụ "BitLocker" {2}: chỉ đọc, không thay đổi gì trên máy. Báo cáo không chứa khoá khôi phục.' -f $env:COMPUTERNAME, $started, $script:ToolVersion)

    # Đọc trước, in sau: phần ổ đĩa cần nhật ký và file khoá để biết khoá đã được lưu ở đâu.
    if ($script:Diag.Admin) { try { $script:Diag.Volumes = @(Get-AllVolumeInfo) } catch { $script:Diag.VolumeError = $_ } }
    $script:Diag.Events = @(Get-BdeEvents)
    $script:Diag.SavedKeys = @(Find-SavedKeys -Extra $ThuMucKhoa)

    Invoke-Section 'Máy này' { Show-MachineSection }
    Invoke-Section 'TPM và Secure Boot' { Show-TpmSection }
    Invoke-Section 'Các ổ đĩa' { Show-VolumeSection }
    Invoke-Section 'Nhật ký BitLocker 2 năm gần đây' { Show-EventSection }
    Invoke-Section 'Chính sách' { Show-PolicySection }
    Show-Conclusion
    $script:Diag.SavedKeys = @()
    if ($script:Diag.Admin -and -not @($script:Findings | Where-Object { $_.Level -in 'bad', 'warn' }).Count) {
        # chỉ cho file kết quả: phần kết luận đã in kết quả
        [void]$script:Findings.Add([pscustomobject]@{ Ma = 'KHONG_CO_VAN_DE'; Level = 'ok'; Text = 'Không thấy vấn đề BitLocker nào cần xử lý.'; Fix = ''; Hint = '' })
    }

    $path = Join-Path (Get-ResultDir) ('BaoCao_BitLocker_{0}_{1:yyyyMMdd_HHmmss}.txt' -f $env:COMPUTERNAME, $started)
    $code = 0
    try {
        [IO.File]::WriteAllLines($path, $script:Report, $script:Utf8Bom)
        Write-Host ''
        Write-Host "  Báo cáo đã lưu: $path" -ForegroundColor Green
    } catch {
        Write-Host "  Không lưu được báo cáo: $($_.Exception.Message)" -ForegroundColor Red
        $path = ''; $code = 1
    }
    $files = @(if ($path) { [ordered]@{ nhan = 'Báo cáo kiểm tra'; duongDan = $path } })
    [void](Save-RunResult -CheDo 'kiem-tra' -Code $code -Start $started -Files $files -Message $(if ($code) { 'Không lưu được báo cáo kiểm tra.' } elseif (-not $script:Diag.Admin) { 'Chạy bằng quyền thường nên chưa đọc được từng ổ; chạy lại bằng quyền Admin.' } else { '' }))
    return $code
}

# ---------------------------------------------------------------- các phần của báo cáo
function Show-MachineSection {
    $w = Get-WindowsInfo
    Write-Line ('Windows: {0} {1}, build {2}' -f $w.Name, $w.Version, $w.Build)
    Write-Line ('Tên máy: {0}' -f $env:COMPUTERNAME)
    $acc = Get-AccountInfo
    $src = switch ($acc.ConsoleSource) {
        'MicrosoftAccount' { 'tài khoản Microsoft' }
        'Local' { 'tài khoản cục bộ (không phải tài khoản Microsoft)' }
        'AzureAD' { 'tài khoản công ty (Entra ID)' }
        'ActiveDirectory' { 'tài khoản domain' }
        default { '' }
    }
    if ($acc.ConsoleUser) { Write-Line ('Người đang dùng máy: {0}{1}' -f $acc.ConsoleUser, $(if ($src) { ", $src" } else { '' })) }
    if ($acc.AdminsKnown) {
        Write-Line ('Admin đăng nhập bằng tài khoản Microsoft: {0}' -f $(if ($acc.MsaAdmins.Count) { $acc.MsaAdmins -join ', ' } else { 'không có' }))
    }
    $j = Get-JoinState
    if ($j.Known) {
        $jt = @()
        if ($j.Entra) { $jt += 'Entra ID (Azure AD)' }
        if ($j.Domain) { $jt += 'domain' }
        Write-Line ('Máy vào tài khoản công ty: {0}' -f $(if ($jt) { $jt -join ', ' } else { 'không' }))
        if ($jt) { Write-Info 'Máy công ty: khoá khôi phục thường được sao lưu tự động lên Entra ID hoặc AD; bộ phận IT tra được theo Mã khoá.' }
    }
    Write-Line ('Chạy bằng: {0} ({1})' -f (Get-CurrentUser), $(if ($script:Diag.Admin) { 'quyền Admin' } else { 'quyền thường' }))
    if ($w.IsHome) {
        Write-Info 'Windows Home: không có trang quản lý BitLocker đầy đủ, chỉ có "Mã hoá thiết bị" (Settings > Privacy & security > Device encryption). Công cụ này vẫn đọc, lưu khoá, tạm dừng, mở khoá được.'
    }
    if (-not $script:Diag.Admin) {
        Add-Finding -Ma 'CHAY_QUYEN_THUONG' info 'Đang chạy quyền thường nên không đọc được trạng thái từng ổ.' -Hint 'Chạy lại bằng quyền Admin: trong Trạm Tool nút Kiểm tra tự xin quyền; bấm đúp BITLOCKER.bat thì chọn "Có" ở hộp UAC.'
    }
}

function Show-TpmSection {
    $t = Get-TpmInfo
    if ($t.Present) {
        $ver = if ($t.Version) { " $($t.Version)" } else { '' }
        if ($t.Ready -eq $false) { Add-Finding -Ma 'TPM_CHUA_SAN_SANG' warn "Có chip TPM$ver nhưng chưa sẵn sàng." -Hint 'Kiểm tra trong BIOS/UEFI (Security > TPM, Intel PTT hoặc AMD fTPM) hoặc mở tpm.msc.' }
        else { Write-Ok "Có chip TPM$ver." }
    } else {
        Write-Info 'Không thấy chip TPM (hoặc đang tắt trong BIOS): không có TPM thì Windows không tự mã hoá ổ.'
    }
    $sb = Get-SecureBootState
    if ($sb -eq 1) { Write-Ok 'Secure Boot đang bật.' }
    elseif ($sb -eq 0) { Write-Info 'Secure Boot đang tắt.' }
    else { Write-Info 'Không đọc được Secure Boot (máy khởi động kiểu BIOS cũ?).' }
}

function Show-VolumeSection {
    if (-not $script:Diag.Admin) { Write-Info 'Cần quyền Admin để đọc BitLocker của từng ổ.'; return }
    if ($script:Diag.VolumeError) { Write-ErrorHelp (Get-ErrorCode $script:Diag.VolumeError) -Prefix 'Không đọc được BitLocker, lỗi'; return }
    $vols = @($script:Diag.Volumes)
    if (-not $vols.Count) { Write-Info 'Windows không báo ổ nào quản lý được bằng BitLocker.'; return }
    $os = @($vols | Where-Object { $_.Type -eq 0 })[0]
    foreach ($i in $vols) { Show-Volume $i $os }
    if (-not @($vols | Where-Object { Test-IsEncrypted $_ }).Count) {
        Write-Ok 'Không ổ nào mã hoá BitLocker: sửa phần cứng, cập nhật BIOS, cài lại máy không bị hỏi khoá.'
    }
}

function Show-Volume {
    param($Info, $Os)
    $i = $Info
    $bits = @($script:StateText[$i.State])
    if ($i.State -in 'dang-ma-hoa', 'dang-giai-ma' -and $null -ne $i.Percent) { $bits[0] += (' ({0}% đã mã hoá)' -f $i.Percent) }
    if ($i.Method -gt 0) { $bits += $script:MethodText[[string]$i.Method] }
    Write-Line ('{0}: {1}' -f (Get-VolumeName $i), ($bits -join ', '))
    if ($i.Errors.Count) { Write-Sub ('Không đọc được: ' + ($i.Errors -join '; ')) }
    if ($i.State -eq 'tat') { return }

    $prot = @(foreach ($p in $i.Protectors) {
            $t = $script:ProtectorText[[string]$p.Type]
            if ($null -ne $p.Pcr) { $t += ' (PCR ' + (Format-Pcr $p.Pcr) + ')' }
            $t
        })
    Write-Sub ('Khoá bảo vệ: {0}' -f $(if ($prot.Count) { (@($prot | Select-Object -Unique)) -join '; ' } else { 'không có' }))
    foreach ($rid in $i.RecoveryIds) {
        Write-Sub ('Mã khoá khôi phục: {0} (màn hình khôi phục hiện {1})' -f (Format-KeyId $rid), (Format-ShortId $rid))
        $ev = Get-KeyEvidence -Id $rid -Events $script:Diag.Events -SavedKeys $script:Diag.SavedKeys
        foreach ($f in $ev.Files) { Write-Sub ('  Đã có file khoá: ' + $f) }
        if ($ev.Msa) { Write-Sub ('  Đã sao lưu lên tài khoản Microsoft ngày {0:dd/MM/yyyy}: xem tại https://aka.ms/myrecoverykey' -f $ev.Msa.Time) }
        if ($ev.Entra) { Write-Sub ('  Đã sao lưu lên Entra ID (tài khoản công ty) ngày {0:dd/MM/yyyy}: xem tại https://aka.ms/aadrecoverykey' -f $ev.Entra.Time) }
        if ($ev.Ad) { Write-Sub ('  Đã sao lưu lên Active Directory ngày {0:dd/MM/yyyy}: bộ phận IT tra được.' -f $ev.Ad.Time) }
    }
    if ($i.Type -ne 0 -and $null -ne $i.AutoUnlock -and -not $i.Locked) { Write-Sub ('Tự mở khoá khi vào Windows: {0}' -f $(if ($i.AutoUnlock) { 'có' } else { 'không' })) }
    if ($i.Type -eq 0 -and $null -ne $i.SecureBootBinding) { Write-Sub ('Gắn với Secure Boot (PCR 7): ' + $script:SecureBootBindingText[[string]$i.SecureBootBinding]) }
    Add-VolumeFindings $i $Os
}

function Add-VolumeFindings {
    param($Info, $Os)
    $i = $Info
    # $n đứng đầu câu ("Ổ C:"), $nl giữa câu ("ổ C:").
    $n = if ($i.Letter) { "Ổ $($i.Letter)" } else { 'Ổ không có chữ ổ' }
    $nl = Get-DriveText $i
    switch ($i.State) {
        'bi-khoa' {
            $ids = @($i.RecoveryIds | ForEach-Object { Format-ShortId $_ }) -join ', '
            Add-Finding -Ma 'O_BI_KHOA' bad "$n đang bị BitLocker khoá." -Fix 'mo-khoa' -Hint $(if ($ids) { "Cần khoá khôi phục có Mã khoá bắt đầu bằng $ids." } else { '' })
            return
        }
        'cho-kich-hoat' {
            Add-Finding -Ma 'CHO_KICH_HOAT_BAO_VE' warn "$n đã mã hoá nhưng chưa kích hoạt bảo vệ (Mã hoá thiết bị đang chờ)." -Hint 'Khoá đang để trần nên ổ không bị khoá, chưa cần khoá khôi phục. Khi một Admin đăng nhập bằng tài khoản Microsoft, Windows tự bật bảo vệ và tải khoá lên tài khoản đó: nhớ tài khoản này, hoặc chạy lại Kiểm tra lúc đó để lưu khoá.'
            return
        }
        'dang-giai-ma' { Add-Finding -Ma 'DANG_GIAI_MA' info ('{0} đang giải mã ({1}%): để máy chạy tiếp; khởi động lại vẫn làm tiếp được.' -f $n, $i.Percent); return }
        'khong-ro' { Add-Finding -Ma 'KHONG_DOC_DUOC_TRANG_THAI' warn "Không đọc được trạng thái BitLocker của $nl."; return }
        'tat' { return }
        'tam-dung' {
            $when = if ($null -eq $i.SuspendCount) { '' } elseif ($i.SuspendCount -eq 0) { ' đến khi bật lại bằng tay' } else { " (tự bật lại sau $($i.SuspendCount) lần khởi động)" }
            Add-Finding -Ma 'DANG_TAM_DUNG' warn "$n đang tạm dừng BitLocker$when`: khoá để trần trên ổ, ai cầm ổ cũng đọc được dữ liệu." -Fix 'bat-lai'
        }
    }

    # Đang bảo vệ, tạm dừng, đang mã hoá: phải có khoá khôi phục và nơi lưu khoá ngoài máy.
    $hasPassword = @($i.Protectors | Where-Object { $_.Type -eq 8 }).Count -gt 0
    if (-not $i.RecoveryIds.Count) {
        $lvl = if ($i.Type -eq 0 -or -not $hasPassword) { 'bad' } else { 'warn' }
        Add-Finding -Ma 'KHONG_CO_KHOA_KHOI_PHUC' $lvl "$n không có khoá khôi phục 48 số: khi Windows hỏi khoá (cập nhật BIOS, thay bo mạch, lỗi TPM) sẽ không mở được ổ." -Fix 'luu-khoa' -Hint '"Lưu khoá khôi phục" thêm khoá cho ổ rồi lưu ra file.'
    } else {
        foreach ($rid in $i.RecoveryIds) {
            $ev = Get-KeyEvidence -Id $rid -Events $script:Diag.Events -SavedKeys $script:Diag.SavedKeys
            if ($ev.Files.Count) { continue }
            if ($ev.Msa -or $ev.Ad -or $ev.Entra) {
                Add-Finding -Ma 'KHOA_CHI_TREN_TAI_KHOAN' info ('Khoá của {0} (Mã khoá {1}) chỉ nằm trên tài khoản trực tuyến.' -f $nl, (Format-ShortId $rid)) -Fix 'luu-khoa' -Hint 'Nên lưu thêm một bản ra USB hoặc giấy trước khi sửa phần cứng, cài lại máy.'
            } else {
                Add-Finding -Ma 'CHUA_THAY_NOI_LUU_KHOA' warn ('Chưa thấy nơi nào lưu khoá khôi phục của {0} (Mã khoá {1}).' -f $nl, (Format-ShortId $rid)) -Fix 'luu-khoa' -Hint 'Khoá có thể nằm trên tài khoản Microsoft mà nhật ký không còn ghi: xem https://aka.ms/myrecoverykey. Chắc nhất là lưu thêm một bản.'
            }
        }
    }
    if ($i.Type -eq 0 -and $i.State -eq 'dang-bao-ve') {
        $tpm = @($i.Protectors | Where-Object { $script:TpmTypes -contains $_.Type -and $null -ne $_.Pcr })
        $firmware = @($tpm | Where-Object { @($_.Pcr) -contains 0 -or @($_.Pcr) -contains 2 })
        if ($firmware.Count) {
            Add-Finding -Ma 'KHOA_THEO_FIRMWARE' warn ('{0} khoá theo cả firmware (PCR {1}): cập nhật BIOS/UEFI, đổi cài đặt BIOS sẽ làm Windows hỏi khoá khôi phục.' -f $n, (Format-Pcr $firmware[0].Pcr)) -Fix 'tam-dung'
        } else {
            Add-Finding -Ma 'NHAC_TAM_DUNG_TRUOC_KHI_SUA' info ('Trước khi cập nhật BIOS, đổi Secure Boot hay TPM trong BIOS, thay bo mạch hoặc chuyển ổ sang máy khác: tạm dừng BitLocker {0}.' -f $nl) -Fix 'tam-dung'
        }
    }
    if ($i.Type -ne 0 -and $i.AutoUnlock -eq $false -and $i.State -eq 'dang-bao-ve') {
        Add-Finding -Ma 'KHONG_TU_MO_KHOA' info "$n không tự mở khoá: mỗi lần khởi động phải mở bằng tay." -Fix 'mo-khoa'
    }
}

function Show-EventSection {
    $ev = @($script:Diag.Events)
    if (-not $ev.Count) { Write-Info 'Không có sự kiện BitLocker (hoặc nhật ký đã bị xoá).'; return }
    $ids = @{}   # Mã khoá hiện có → chữ ổ
    foreach ($v in @($script:Diag.Volumes)) { foreach ($r in $v.RecoveryIds) { $ids[(Format-KeyId $r)] = $v.Letter } }
    # Gộp các sự kiện giống nhau trong cùng một phút (Windows hay ghi lặp) thành một dòng "(n lần)".
    $rows = New-Object System.Collections.ArrayList
    foreach ($e in $ev) {
        $hit = @($e.Guids | Where-Object { $ids.ContainsKey($_) })
        $bits = @()
        if ($e.Drive) { $bits += "ổ $($e.Drive)" }
        if ($hit.Count) {
            if (-not $e.Drive -and $ids[$hit[0]]) { $bits += "ổ $($ids[$hit[0]])" }
            $bits += 'Mã khoá ' + (Format-ShortId $hit[0])
        }
        $line = ('{0:dd/MM/yyyy HH:mm}  {1}' -f $e.Time, $e.Text) + $(if ($bits) { ' (' + ($bits -join ', ') + ')' } else { '' })
        $last = if ($rows.Count) { $rows[$rows.Count - 1] } else { $null }
        if ($last -and $last.Line -eq $line) { $last.N++ }
        else { [void]$rows.Add([pscustomobject]@{ Line = $line; N = 1 }) }
    }
    foreach ($r in @($rows | Select-Object -First 15)) { Write-Line ($r.Line + $(if ($r.N -gt 1) { " ($($r.N) lần)" } else { '' })) }
    if ($rows.Count -gt 15) { Write-Info ('Còn {0} dòng cũ hơn.' -f ($rows.Count - 15)) }

    $recent = (Get-Date).AddDays(-180)
    $boot = @($ev | Where-Object { $script:EventRecoveryBoot -contains $_.Id -and $_.Time -ge $recent })
    if ($boot.Count) {
        Add-Finding -Ma 'DA_PHAI_NHAP_KHOA' warn ('Máy đã phải nhập khoá khôi phục khi khởi động {0} lần trong 6 tháng (gần nhất {1:dd/MM/yyyy}).' -f $boot.Count, $boot[0].Time) -Hint 'Lặp lại mỗi lần khởi động: tạm dừng BitLocker (1 lần khởi động), khởi động lại, rồi bật lại để TPM ghi nhận cấu hình mới.'
    }
    $dec = @($ev | Where-Object { $_.Id -in 770, 24580 -and $_.Time -ge (Get-Date).AddDays(-90) })
    if ($dec.Count) { Write-Info ('Có ổ bắt đầu giải mã ngày {0:dd/MM/yyyy}.' -f $dec[0].Time) }
    $fail = @($ev | Where-Object { $script:EventBackupFail -contains $_.Id -and $_.Time -ge $recent })
    if ($fail.Count) {
        $good = $script:EventBackupMsa + $script:EventBackupAd + $script:EventBackupEntra
        $after = @($ev | Where-Object { $good -contains $_.Id -and $_.Time -gt $fail[0].Time })
        if (-not $after.Count) {
            Add-Finding -Ma 'SAO_LUU_KHOA_THAT_BAI' warn ('Sao lưu khoá lên tài khoản trực tuyến thất bại {0} lần trong 6 tháng (gần nhất {1:dd/MM/yyyy}: {2}).' -f $fail.Count, $fail[0].Time, $fail[0].Text) -Fix 'luu-khoa'
        }
    }
    $osEncrypted = @($script:Diag.Volumes | Where-Object { $_.Type -eq 0 -and (Test-IsEncrypted $_) }).Count
    if (@($ev | Where-Object { $_.Id -eq 869 -and $_.Time -ge $recent }).Count -and ($osEncrypted -or -not $script:Diag.Admin)) {
        Add-Finding -Ma 'KHOA_CHUA_SAO_LUU' warn 'Windows báo khoá khôi phục ổ Windows chưa được sao lưu.' -Fix 'luu-khoa'
    }
}

function Show-PolicySection {
    $pol = @(Get-FvePolicy)
    if ($pol.Count) {
        Write-Line ('Có {0} chính sách BitLocker (HKLM\SOFTWARE\Policies\Microsoft\FVE): máy do công ty hoặc phần mềm quản lý.' -f $pol.Count)
        foreach ($p in @($pol | Select-Object -First 15)) { Write-Sub ('{0} = {1}' -f $p.Name, $p.Value) }
    } else {
        Write-Line 'Không có chính sách BitLocker riêng.'
    }
    if ((Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker' 'PreventDeviceEncryption') -eq 1) {
        Write-Info 'Đã chặn Windows tự mã hoá thiết bị (PreventDeviceEncryption = 1).'
    }
}

function Show-Conclusion {
    Write-Head 'KẾT LUẬN'
    $rank = @{ bad = 0; warn = 1; info = 2 }
    $all = @($script:Findings)
    $ordered = @(for ($k = 0; $k -lt $all.Count; $k++) { [pscustomobject]@{ Key = $rank[$all[$k].Level] * 1000 + $k; F = $all[$k] } }) | Sort-Object Key | ForEach-Object { $_.F }
    $show = @($ordered | Where-Object { $_.Level -ne 'info' -or $_.Fix -or $_.Hint })
    $nBad = @($all | Where-Object { $_.Level -eq 'bad' }).Count
    $nWarn = @($all | Where-Object { $_.Level -eq 'warn' }).Count
    if (-not $show.Count) {
        Write-Ok 'Không thấy vấn đề BitLocker nào cần xử lý.'
    } else {
        if ($nBad + $nWarn) { Write-Line ('{0} lỗi, {1} cảnh báo. Nên xử lý theo thứ tự:' -f $nBad, $nWarn) }
        else { Write-Line 'Không có lỗi hay cảnh báo. Gợi ý:' }
        foreach ($f in $show) {
            switch ($f.Level) { 'bad' { Write-Bad $f.Text } 'warn' { Write-Warn $f.Text } default { Write-Info $f.Text } }
            if ($f.Fix -and $script:Modes.Contains($f.Fix)) {
                $m = $script:Modes[$f.Fix]
                Write-Sub ('→ Chạy "{0}" (trong Trạm Tool, hoặc BITLOCKER.bat mục {1}).' -f $m.Label, $m.No)
            } elseif ($f.Hint) { Write-Sub ('→ ' + $f.Hint) }
        }
    }
    Write-Info 'Báo cáo không chứa khoá khôi phục; Mã khoá (Key ID) chỉ dùng để đối chiếu, gửi người khác được.'
}
