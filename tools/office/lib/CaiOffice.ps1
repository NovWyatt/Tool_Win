# Office - cài theo mẫu bằng Office Deployment Tool: kiểm tra mẫu và máy trước, đóng ứng dụng Office, chạy
# "setup.exe /configure <file cấu hình của mẫu>" ngay trong thư mục mẫu (không chép file cấu hình đi đâu vì có khoá
# sản phẩm), rồi kiểm tra sản phẩm, ứng dụng, kích hoạt. Kích hoạt chỉ theo cách của Microsoft: Office tự kích hoạt
# (AUTOACTIVATE) hoặc gọi kích hoạt khoá đã cài.

# Mã lỗi kích hoạt hay gặp (hex 8 chữ số) → cách xử lý.
$script:ActivationHelp = @{
    'C004C008' = 'Khoá đã dùng hết số lần kích hoạt (MAK hết lượt): liên hệ nơi cấp khoá để thêm lượt hoặc dùng khoá khác.'
    'C004C020' = 'Khoá MAK đã vượt số lần kích hoạt cho phép: liên hệ nơi cấp khoá.'
    'C004C003' = 'Khoá bị Microsoft chặn: dùng khoá hợp lệ khác.'
    'C004F050' = 'Khoá không hợp lệ với sản phẩm này.'
    'C004F074' = 'Không liên lạc được máy chủ KMS: bản Volume dùng KMS phải nối mạng công ty.'
    '8007232B' = 'Không tìm thấy máy chủ KMS: bản Volume dùng KMS phải nối mạng công ty, hoặc dùng khoá MAK.'
    '80072EE7' = 'Không phân giải được tên máy chủ kích hoạt: kiểm tra Internet rồi thử lại.'
    '80072EFD' = 'Không kết nối được máy chủ kích hoạt (mạng, tường lửa): kiểm tra Internet rồi thử lại.'
    '80072EE2' = 'Kết nối máy chủ kích hoạt quá thời gian: kiểm tra Internet rồi thử lại.'
}

function Resolve-Template {
    # Đọc mẫu; mẫu có nhiều file cấu hình mà chưa chọn thì hỏi (cửa sổ có bàn phím), không thì báo lỗi.
    param([string]$Mau, [string]$CauHinh)
    $dir = Find-TemplateDir $Mau
    $t = Read-OfficeTemplate $dir $CauHinh
    if ($t.Candidates.Count -and -not (Test-NoInput)) {
        Write-Line ('Mẫu {0} có nhiều file cấu hình:' -f $t.Dir)
        for ($i = 0; $i -lt $t.Candidates.Count; $i++) { Write-Line ('  {0}  {1}' -f ($i + 1), $t.Candidates[$i]) }
        $keys = @(1..$t.Candidates.Count | ForEach-Object { [string]$_ }) + 'H'
        $c = Read-Choice 'Chọn số file cấu hình (H để huỷ)' $keys 'H'
        if ($c -ne 'H') { $t = Read-OfficeTemplate $dir $t.Candidates[[int]$c - 1] }
    }
    return $t
}

function Show-TemplateInfo {
    # In bộ cài mẫu (khoá sản phẩm không bao giờ in: chỉ ghi "có khoá").
    param($T)
    Write-Line ('Thư mục: {0}' -f $T.Dir)
    if ($T.Setup) { Write-Line ('setup.exe (Office Deployment Tool) bản {0}, {1}' -f $T.SetupVersion, $(if ($T.SetupSigned) { 'chữ ký Microsoft hợp lệ' } else { 'KHÔNG có chữ ký Microsoft hợp lệ' })) }
    if (-not $T.ConfigName) { return }
    Write-Line ('File cấu hình: {0}' -f $T.ConfigName)
    foreach ($p in $T.Products) {
        $key = if ($p.Gvlk) { ', khoá KMS chung (GVLK) của Microsoft' } elseif ($p.HasKey) { ', có khoá sản phẩm (đã che)' } else { '' }
        Write-Line ('Sản phẩm: {0} ({1}){2}' -f (Get-ProductName $p.Id), $p.Id, $key)
        if ($p.Languages.Count) { Write-Sub ('Ngôn ngữ: ' + ($p.Languages -join ', ')) }
        if ($p.Exclude.Count) { Write-Sub ('Không cài: ' + (($p.Exclude | ForEach-Object { Get-AppLabel $_ }) -join ', ')) }
    }
    $chan = if ($T.Channel) { $T.Channel } else { 'mặc định theo sản phẩm' }
    Write-Line ('Bản {0} bit, kênh {1}' -f $T.Edition, $chan)
    if ($T.Source -and $T.Source.Complete) {
        Write-Line ('Bộ cài có sẵn trong mẫu: bản {0}, kênh {1}, {2}: cài không cần Internet' -f $T.Source.Build, $T.Source.Channel.Label, (Format-Size $T.Source.Size))
    }
    Write-Line ('Cập nhật tự động: {0}' -f $(if ($T.UpdatesEnabled -ieq 'FALSE') { 'tắt' } else { 'bật' }))
    if ($T.RemoveMSI) { Write-Line 'Trước khi cài, ODT gỡ Office cài bằng MSI (RemoveMSI)' }
    if ($T.AutoActivate) { Write-Line 'Tự kích hoạt sau khi cài (AUTOACTIVATE)' }
}

function Show-TemplateProblems {
    param($T)
    foreach ($p in $T.Problems) { Write-Bad $p }
    if ($T.Candidates.Count) { Write-Sub ('Các file cấu hình: {0}. Chọn một file ở ô "File cấu hình" (tham số -CauHinh).' -f ($T.Candidates -join ', ')) }
    foreach ($w in $T.Warnings) { Write-Warn $w }
    foreach ($p in $T.Products) {
        $lc = Get-ProductLifecycle $p.Id
        if ($lc.Status -in 'ended', 'soon') { Write-Warn ('Mẫu cài ' + $lc.Text) }
    }
}

function Test-SameAsTemplate {
    # Office Click-to-Run trên máy đúng sản phẩm, 32/64 bit, kênh như mẫu.
    param($T, $C2R)
    if (-not $C2R -or -not $C2R.Products.Count) { return $false }
    $want = @($T.Products | ForEach-Object { $_.Id })
    if (@($want | Where-Object { $C2R.Products -notcontains $_ }).Count -or @($C2R.Products | Where-Object { $want -notcontains $_ }).Count) { return $false }
    $plat = if ($T.Edition -eq '32') { 'x86' } else { 'x64' }
    if ($C2R.Platform -and $C2R.Platform -ne $plat) { return $false }
    $chan = Resolve-ChannelId $T.Channel
    if ($chan -and $C2R.Channel.Id -and $chan -ne $C2R.Channel.Id) { return $false }
    return $true
}

function Test-InstallReady {
    # Trước khi cài: mẫu dùng được, đủ chỗ trống, không có Office khác chặn. -WillRemove: sắp gỡ Office hiện có
    # (bỏ qua kiểm tra Office đang cài; thiếu chỗ chỉ cảnh báo vì gỡ xong sẽ trống thêm).
    # Trả @{ Blocking; Warnings; Same (Office trên máy đúng như mẫu) }.
    param($T, $State, [switch]$WillRemove)
    $block = New-Object System.Collections.Generic.List[string]
    $warn = New-Object System.Collections.Generic.List[string]
    foreach ($p in $T.Problems) { $block.Add($p) }
    $free = Get-FreeSpace
    if ($free -ge 0 -and $free -lt $script:MinFreeBytes) {
        $msg = 'Ổ {0} chỉ còn {1} trống, cần ít nhất 4 GB để cài Office.' -f $env:SystemDrive, (Format-Size $free)
        if ($WillRemove) { $warn.Add($msg + ' Công cụ kiểm tra lại sau khi gỡ.') } else { $block.Add($msg) }
    }
    $same = $false
    if (-not $WillRemove) {
        $c = $State.C2R
        if ($c -and $c.Products.Count) {
            if (Test-SameAsTemplate $T $c) { $same = $true }
            else {
                $block.Add(('Máy đang có {0} ({1}, kênh {2}), khác mẫu: cài thêm sẽ lẫn hai bản. Chạy "Gỡ sạch Office cũ rồi cài theo mẫu".' -f `
                            (Get-C2RNames $State), (Format-Platform $c.Platform), $c.Channel.Label))
            }
        } elseif ($State.C2RArp.Count) {
            $block.Add('Office Click-to-Run trên máy bị hỏng: chạy "Gỡ sạch Office cũ rồi cài theo mẫu".')
        }
        if ($State.Suites.Count) {
            $names = ($State.Suites | ForEach-Object { $_.Name }) -join ', '
            if ($T.RemoveMSI) { $warn.Add("ODT sẽ gỡ $names (cài bằng MSI) trước khi cài.") }
            else { $block.Add("Máy có $names (cài bằng MSI): cài bản Click-to-Run lên sẽ lỗi. Chạy ""Gỡ sạch Office cũ rồi cài theo mẫu"".") }
        }
        if ($State.Store.Count) { $block.Add('Máy có Office từ Microsoft Store: chạy "Gỡ sạch Office cũ rồi cài theo mẫu".') }
    }
    if ($T.RemoveMSI -and $State.Ace.Count) {
        $warn.Add(('RemoveMSI trong mẫu có thể gỡ cả {0}. Máy có phần mềm cần nó (kế toán, nhập liệu...) thì thêm <IgnoreProduct ID="AceRedist" /> vào trong <RemoveMSI> của file cấu hình.' -f (($State.Ace | ForEach-Object { $_.Name }) -join ', ')))
    }
    if ($T.Source -and -not $T.Source.Complete -and -not $T.Problems.Count -and -not (Test-Internet)) {
        $block.Add('Mẫu thiếu bộ cài (xem trên) mà máy không vào được máy chủ tải Office của Microsoft.')
    }
    if (-not $WillRemove -and (Test-OfficeRebootPending)) { $warn.Add('Windows đang chờ khởi động lại để dọn Office cũ: nên khởi động lại máy trước khi cài.') }
    return [pscustomobject]@{ Blocking = $block; Warnings = $warn; Same = $same }
}

function Invoke-OdtInstall {
    # Chạy ODT với file cấu hình của mẫu, tại chỗ. Trả mã thoát của setup.exe ($null khi quá giờ).
    param($T)
    $how = if ($T.DisplayLevel -ieq 'None') { 'chạy ngầm, không có cửa sổ' } else { 'cửa sổ cài của Office hiện ra, không cần bấm gì' }
    Write-Line ('Đang cài bằng Office Deployment Tool ({0})...' -f $how)
    $p = Start-Process -FilePath $T.Setup -ArgumentList ('/configure "{0}"' -f $T.Config) -WorkingDirectory $T.Dir -PassThru
    $code = Wait-ProcessVisible $p 'Đang cài' 120
    if ($null -eq $code) { Write-Warn 'Cài quá 120 phút, công cụ không chờ nữa (ODT vẫn chạy tiếp).' }
    elseif ($code -eq 0) { Write-Ok 'Office Deployment Tool đã cài xong.' }
    else {
        $where = if ($T.LogPath) { $T.LogPath } else { '%TEMP% của tài khoản chạy cài đặt' }
        Write-Bad ('Office Deployment Tool báo lỗi {0}. Nhật ký của ODT nằm trong {1} (có thể chứa khoá sản phẩm, đừng gửi công khai).' -f (Format-ErrorCode $code), $where)
    }
    return $code
}

function Test-InstallResult {
    # Sau khi cài: đủ sản phẩm, đúng 32/64 bit, có Word, Excel, PowerPoint (trừ ứng dụng mẫu bỏ). Trả $true khi đạt.
    param($T)
    $c = Get-C2RInfo
    if (-not $c -or -not $c.Products.Count) { Write-Bad 'Không thấy Office Click-to-Run sau khi cài.'; return $false }
    $ok = $true
    foreach ($p in $T.Products) {
        if ($c.Products -contains $p.Id) { Write-Ok ('{0}, bản {1}' -f (Get-ProductName $p.Id), $c.Version) }
        else { Write-Bad ('Chưa có {0}.' -f (Get-ProductName $p.Id)); $ok = $false }
    }
    $plat = if ($T.Edition -eq '32') { 'x86' } else { 'x64' }
    if ($c.Platform -and $c.Platform -ne $plat) { Write-Bad ('Office trên máy là bản {0}, mẫu là {1} bit.' -f (Format-Platform $c.Platform), $T.Edition); $ok = $false }
    if ($c.Apps.Count) { Write-Line ('Ứng dụng: ' + (($c.Apps | ForEach-Object { Get-AppLabel $_ }) -join ', ')) }
    $excluded = @($T.Products | ForEach-Object { $_.Exclude })
    foreach ($a in 'Word', 'Excel', 'PowerPoint') {
        $suite = @($T.Products | Where-Object { $_.Id -match '^(O365|ProPlus|Standard|Professional|HomeBusiness|HomeStudent|Personal)' }).Count
        if ($suite -and $excluded -notcontains $a -and $c.Apps -notcontains $a) { Write-Bad "Thiếu $a."; $ok = $false }
    }
    return $ok
}

function Write-ActivationError {
    param([int64]$Code)
    $hex = '{0:X8}' -f $(if ($Code -lt 0) { $Code + 4294967296 } else { $Code })
    $h = $script:ActivationHelp[$hex]
    Write-Bad ('Kích hoạt lỗi 0x{0}.' -f $hex)
    if ($h) { Write-Sub ('→ ' + $h) }
}

function Get-SafeLicenses {
    param([string[]]$Hashes = @())
    try { return @(Get-OfficeLicenses $Hashes) } catch { return @() }
}

function Invoke-OfficeActivate {
    # Kích hoạt một sản phẩm Office bằng khoá đã cài: MAK, bán lẻ qua Internet; khoá KMS chung qua máy chủ KMS.
    param([string]$Id)
    try {
        $p = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter ("ID='{0}'" -f $Id) -ErrorAction Stop
        [void](Invoke-CimMethod -InputObject $p -MethodName 'Activate' -ErrorAction Stop)
        return $true
    } catch { Write-ActivationError (Get-ErrorCode $_); return $false }
}

function Install-OfficeKey {
    # Nhập khoá Office của bạn (MAK, bán lẻ) rồi kích hoạt. Khoá chỉ gõ trong cửa sổ này: không hiện lên màn hình,
    # không nhận qua tham số, không vào báo cáo hay nhật ký. Trả $true khi đã kích hoạt.
    if (Test-NoInput) { Write-Warn 'Khoá phải gõ trong cửa sổ công cụ.'; return $false }
    Write-Line 'Chỉ gõ khoá Office (khoá Windows gõ vào đây sẽ được cài vào Windows).'
    $sec = Read-Host '  Khoá 25 ký tự, dạng XXXXX-XXXXX-... (không hiện khi gõ; Enter để thôi)' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    $key = ([string]$key -replace '\s', '').ToUpperInvariant()
    if (-not $key) { return $false }
    if ($key -notmatch '^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$') { $key = $null; Write-Bad 'Khoá phải có 5 nhóm 5 ký tự, cách nhau bằng dấu gạch ngang.'; return $false }
    $gvlk = Test-IsGvlk $key
    $tail = Get-KeyTailHash $key
    try {
        $svc = Get-CimInstance -ClassName SoftwareLicensingService -ErrorAction Stop
        [void](Invoke-CimMethod -InputObject $svc -MethodName 'InstallProductKey' -Arguments @{ ProductKey = $key } -ErrorAction Stop)
    } catch { Write-ActivationError (Get-ErrorCode $_); return $false }
    finally { $key = $null }
    $lic = @(Get-SafeLicenses @($tail) | Where-Object { $_.KeyMatch }) | Select-Object -First 1
    if (-not $lic) { Write-Warn 'Đã nhập khoá nhưng không sản phẩm Office nào nhận khoá này: xem lại trong Cài đặt > Hệ thống > Kích hoạt của Windows.'; return $false }
    Write-Ok ('Đã nhập khoá cho {0}.' -f $lic.Name)
    if ($gvlk) { Write-Info 'Đây là khoá KMS chung: chỉ kích hoạt được qua máy chủ KMS của tổ chức.' }
    if ($lic.Status -eq 1) { return $true }
    [void](Invoke-OfficeActivate $lic.Id)
    $lic = @(Get-SafeLicenses @($tail) | Where-Object { $_.KeyMatch }) | Select-Object -First 1
    return [bool]($lic -and $lic.Status -eq 1)
}

function Invoke-ActivationMenu {
    # Đến khi mọi sản phẩm Office có khoá đã kích hoạt, hoặc người dùng bỏ qua: K kích hoạt lại, N nhập khoá, B bỏ qua.
    # Trả $true khi đã kích hoạt hết.
    param($Lics)
    while ($true) {
        $todo = @($Lics | Where-Object { $_.Status -ne 1 })
        if ($Lics.Count -and -not $todo.Count) {
            foreach ($l in $Lics) { Write-Ok ('{0}: đã kích hoạt, {1}.' -f $l.Name, (Get-LicenseChannelText $l.Channel)) }
            return $true
        }
        if (-not $Lics.Count) { Write-Warn 'Windows chưa có khoá Office nào: Office sẽ hỏi khoá hoặc tài khoản khi mở.' }
        foreach ($l in $todo) {
            Write-Warn ('{0}: {1}, {2}.' -f $l.Name, (Get-LicenseStatusText $l.Status $l.GraceMinutes), (Get-LicenseChannelText $l.Channel))
            if ($l.Channel -match 'GVLK' -and -not $l.KmsHost -and -not $l.KmsFound) { Write-Sub 'Khoá KMS chung cần máy chủ KMS của tổ chức; không có thì nhập khoá MAK của bạn (chọn N).' }
        }
        if ($todo.Count) { $c = Read-Choice 'K: kích hoạt ngay (cần mạng), N: nhập khoá Office của bạn, B: bỏ qua' @('K', 'N', 'B') 'B' }
        else { $c = Read-Choice 'N: nhập khoá Office của bạn, B: bỏ qua' @('N', 'B') 'B' }
        if ($c -eq 'B') { Write-Info 'Bỏ qua: chạy "Kích hoạt Office" khi có khoá hoặc khi nối được mạng có máy chủ KMS.'; return $false }
        if ($c -eq 'K') { foreach ($l in $todo) { [void](Invoke-OfficeActivate $l.Id) } }
        if ($c -eq 'N') { [void](Install-OfficeKey) }
        $Lics = @(Get-SafeLicenses)
    }
}

function Invoke-ActivationCheck {
    # Sau khi cài: chờ Office tự kích hoạt (AUTOACTIVATE), chưa được thì hỏi. Trả $true khi đã kích hoạt.
    param($T)
    if (-not @($T.Products | Where-Object { $_.Id -notmatch '^O365' }).Count) {
        Write-Info 'Microsoft 365: mở Word, đăng nhập tài khoản có giấy phép để kích hoạt.'
        return $true
    }
    $tries = if ($T.AutoActivate) { 12 } else { 2 }   # mỗi lần cách 10 giây
    if ($T.AutoActivate) { Write-Line 'Chờ Office tự kích hoạt (tối đa 2 phút)...' }
    for ($i = 1; $i -le $tries; $i++) {
        $lics = @(Get-SafeLicenses)
        if ($lics.Count -and -not @($lics | Where-Object { $_.Status -ne 1 }).Count) { break }
        if ($i -lt $tries) { Start-Sleep -Seconds 10 }
    }
    return (Invoke-ActivationMenu $lics)
}

function Show-ActivationRisk {
    # Trước khi gỡ: khoá riêng (MAK, bán lẻ) đang kích hoạt Office sẽ bị gỡ khỏi Windows, mà công cụ không đọc được khoá
    # đầy đủ để cài lại. Mẫu chỉ có khoá KMS chung và không thấy máy chủ KMS: cài xong Office sẽ chưa kích hoạt.
    param($Lics, $T = $null)
    $own = @($Lics | Where-Object { $_.Status -eq 1 -and $_.Channel -notmatch 'GVLK' -and -not $_.KeyMatch })
    foreach ($l in $own) {
        Write-Warn ('{0} đang kích hoạt bằng {1}: gỡ sẽ xoá khoá này khỏi Windows; công cụ không đọc được khoá đầy đủ để cài lại.' -f $l.Name, (Get-LicenseChannelText $l.Channel))
    }
    if ($T -and $T.KeyKind -eq 'gvlk' -and -not (Test-KmsDiscoverable)) {
        Write-Warn 'Mẫu chỉ có khoá KMS chung mà máy không thấy máy chủ KMS: cài xong Office sẽ chưa kích hoạt. Chuẩn bị sẵn khoá MAK hoặc khoá bản quyền Office để nhập ở bước kích hoạt.'
    } elseif ($own.Count -and -not $T) {
        Write-Sub '→ Sẽ cài lại Office thì chuẩn bị sẵn khoá đó.'
    }
}

function Invoke-InstallSteps {
    # Đóng ứng dụng, cài, kiểm tra, kích hoạt. Trả mã: 0 xong, 3 cài được nhưng còn việc (thiếu, chưa kích hoạt), 1 lỗi, 1223 huỷ.
    # $AceBefore: Access Database Engine trên máy trước khi cài (<RemoveMSI> của mẫu có thể gỡ nó).
    param($T, $AceBefore = @())
    Write-Head 'Đóng ứng dụng Office'
    if ((Close-OfficeApps 'cài Office') -eq 'cancel') { Write-Info 'Đã dừng, chưa cài.'; return 1223 }
    Write-Ok 'Không còn ứng dụng Office nào đang mở.'
    Write-Head 'Cài Office theo mẫu'
    $code = Invoke-OdtInstall $T
    Write-Head 'Kiểm tra sau khi cài'
    $ok = Test-InstallResult $T
    if (@($AceBefore).Count) { Show-LostAce $AceBefore (Get-OfficeState).Ace $(if ($T.RemoveMSI) { ' (thẻ <RemoveMSI> của mẫu gỡ cả nó)' } else { '' }) }
    if (-not $ok) {
        if ($code -ne 0) { Write-Sub '→ Xem lỗi ODT ở trên, xử lý rồi chạy lại "Chỉ cài Office theo mẫu".' }
        return 1
    }
    Write-Head 'Kích hoạt'
    $act = Invoke-ActivationCheck $T
    foreach ($p in $T.Products) {
        $lc = Get-ProductLifecycle $p.Id
        if ($lc.Status -in 'ended', 'soon') { Write-Warn $lc.Text }
    }
    if ($code -ne 0 -or -not $act) { return 3 }
    return 0
}

function Invoke-CaiDat {
    # Chế độ cai-dat: chỉ cài Office theo mẫu.
    param([string]$Mau = '', [string]$CauHinh = '', [switch]$DryRun)
    Write-Out 'CÀI OFFICE THEO MẪU' 'Cyan'
    Write-Out ('Máy {0}, {1:dd/MM/yyyy HH:mm}, tài khoản {2}.' -f $env:COMPUTERNAME, (Get-Date), (Get-CurrentUser))
    $t = Resolve-Template $Mau $CauHinh
    Write-Head 'Bộ cài mẫu'
    if ($t.Dir) { Show-TemplateInfo $t }
    Show-TemplateProblems $t
    $state = Get-OfficeState
    Write-Head 'Office trên máy'
    Show-OfficeState $state
    $ready = Test-InstallReady $t $state
    foreach ($w in $ready.Warnings) { Write-Warn $w }
    if ($ready.Blocking.Count) {
        Write-Head 'Chưa cài được'
        foreach ($b in $ready.Blocking) { Write-Bad $b }
        return 2
    }
    if (-not (Test-IsAdmin) -and -not $DryRun) { Write-Bad 'Cần quyền Admin để cài Office.'; return 2 }
    Write-Head 'Sẽ làm'
    if ($ready.Same) { Write-Info 'Office trên máy đã đúng như mẫu: cài lại sẽ sửa Office (giữ nguyên file, thiết lập).' }
    Write-Plan 'Đóng ứng dụng Office đang mở (hỏi trước)'
    Write-Plan ('Cài {0} bằng "setup.exe /configure {1}" trong thư mục mẫu' -f (($t.Products | ForEach-Object { Get-ProductName $_.Id }) -join ', '), $t.ConfigName)
    Write-Plan 'Kiểm tra sản phẩm, ứng dụng, kích hoạt'
    if ($DryRun) { Write-Info 'Chạy thử: máy chưa thay đổi gì.'; return 0 }
    $q = if ($ready.Same) { 'Cài lại đè lên Office hiện có?' } else { 'Cài ngay?' }
    if (-not (Read-YesNo $q (-not $ready.Same))) { Write-Info 'Đã huỷ, máy chưa thay đổi gì.'; return 1223 }
    return (Invoke-InstallSteps $t $state.Ace)
}

function Invoke-KichHoat {
    # Chế độ kich-hoat: xem trạng thái kích hoạt Office, kích hoạt lại, nhập khoá Office của bạn.
    param([switch]$DryRun)
    Write-Out 'KÍCH HOẠT OFFICE' 'Cyan'
    Write-Out ('Máy {0}, {1:dd/MM/yyyy HH:mm}, tài khoản {2}.' -f $env:COMPUTERNAME, (Get-Date), (Get-CurrentUser))
    Write-Head 'Office trên máy'
    Show-OfficeState (Get-OfficeState)
    Write-Head 'Giấy phép'
    $lics = @(Get-SafeLicenses)
    if ($DryRun) {
        foreach ($l in $lics) { Write-Line ('{0}: {1}, {2}.' -f $l.Name, (Get-LicenseStatusText $l.Status $l.GraceMinutes), (Get-LicenseChannelText $l.Channel)) }
        if (-not $lics.Count) { Write-Line 'Windows chưa có khoá Office nào.' }
        Write-Info 'Chạy thử: máy chưa thay đổi gì.'
        return 0
    }
    if (-not (Test-IsAdmin)) { Write-Bad 'Cần quyền Admin để kích hoạt, nhập khoá.'; return 2 }
    if (Invoke-ActivationMenu $lics) { return 0 }
    return 3
}

function Invoke-GoVaCai {
    # Chế độ go-va-cai: kiểm tra mẫu trước (mẫu hỏng thì không gỡ gì), gỡ sạch, rồi cài theo mẫu.
    param([string]$Mau = '', [string]$CauHinh = '', [switch]$QuetSau, [switch]$XoaThietLap, [switch]$DryRun)
    Write-Out 'GỠ SẠCH OFFICE CŨ RỒI CÀI THEO MẪU' 'Cyan'
    Write-Out ('Máy {0}, {1:dd/MM/yyyy HH:mm}, tài khoản {2}.' -f $env:COMPUTERNAME, (Get-Date), (Get-CurrentUser))
    $t = Resolve-Template $Mau $CauHinh
    Write-Head 'Bộ cài mẫu'
    if ($t.Dir) { Show-TemplateInfo $t }
    Show-TemplateProblems $t
    $state = Get-OfficeState
    Write-Head 'Office trên máy'
    Show-OfficeState $state
    if ($t.Dir -and (Test-TemplateInsideOffice $t $state)) {
        Write-Bad ('Bộ cài mẫu đang nằm trong thư mục cài Office ({0}): gỡ Office có thể xoá mất mẫu.' -f $t.Dir)
        Write-Sub '→ Chép mẫu ra chỗ khác (vd D:\MauOffice) rồi chạy lại, chọn thư mục mẫu mới.'
        return 2
    }
    $ready = Test-InstallReady $t $state -WillRemove
    foreach ($w in $ready.Warnings) { Write-Warn $w }
    if ($ready.Blocking.Count) {
        Write-Head 'Chưa làm được'
        foreach ($b in $ready.Blocking) { Write-Bad $b }
        Write-Info 'Máy chưa bị gỡ gì.'
        return 2
    }
    if (-not (Test-IsAdmin) -and -not $DryRun) { Write-Bad 'Cần quyền Admin để gỡ và cài Office.'; return 2 }
    $left = Get-OfficeLeftovers $state
    $lic = @()
    try { $lic = @(Get-OfficeLicenses $t.KeyHashes) } catch { }
    $same = Test-SameUser
    $odt = Get-RemovalOdt $t.Dir

    Write-Head 'Sẽ làm'
    $needRemove = ($state.Any -or $left.Any -or $lic.Count)
    if ($needRemove) { Show-RemovePlan $state $left $odt $same $lic.Count -QuetSau:$QuetSau -XoaThietLap:$XoaThietLap }
    Write-Plan ('Cài {0} theo mẫu ({1})' -f (($t.Products | ForEach-Object { Get-ProductName $_.Id }) -join ', '), $t.ConfigName)
    Write-Plan 'Kiểm tra sản phẩm, ứng dụng, kích hoạt'
    Show-ActivationRisk $lic $t
    if ($DryRun) { Write-Info 'Chạy thử: máy chưa thay đổi gì.'; return 0 }
    Write-Warn 'Gỡ rồi không hoàn tác được. Nếu bước cài lỗi, máy tạm không có Office: xử lý lỗi rồi chạy "Chỉ cài Office theo mẫu".'
    if (-not (Confirm-Strong)) { Write-Info 'Đã huỷ, máy chưa thay đổi gì.'; return 1223 }

    $backup = ''
    $ace = @($state.Ace)
    if ($needRemove) {
        $r = Invoke-RemoveSteps $state $odt @($t.Dir) $same -QuetSau:$QuetSau -XoaThietLap:$XoaThietLap
        if ($r.Code -eq 1223) { return 1223 }
        $backup = $r.Backup
        $ace = @($r.Ace)
        if (-not $r.Clean) { Write-Bad 'Chưa gỡ hết Office nên chưa cài.'; return 3 }
        if ($r.Reboot) {
            Write-Head 'Cần khởi động lại'
            Write-Warn 'Đã gỡ xong nhưng Windows cần khởi động lại trước khi cài.'
            Write-Sub '→ Khởi động lại máy rồi chạy "Chỉ cài Office theo mẫu".'
            return 3
        }
        $free = Get-FreeSpace
        if ($free -ge 0 -and $free -lt $script:MinFreeBytes) {
            Write-Bad ('Ổ {0} chỉ còn {1} trống, cần ít nhất 4 GB để cài Office: dọn bớt rồi chạy "Chỉ cài Office theo mẫu".' -f $env:SystemDrive, (Format-Size $free))
            return 3
        }
    }
    $code = Invoke-InstallSteps $t $ace
    if ($backup -and $code -in 0, 3) {
        Write-Sub ('→ Thiếu mẫu Word, macro, chữ ký thì chạy "Trả lại mẫu Word, macro, chữ ký đã sao lưu" (bản sao lưu: {0}).' -f (Split-Path -Leaf $backup))
    }
    return $code
}
