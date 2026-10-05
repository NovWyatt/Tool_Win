# Office - kiểm tra, chỉ đọc. Ghi báo cáo ket_qua\BaoCao_Office_<tên máy>_<thời gian>.txt.
# Báo cáo không có khoá sản phẩm (kể cả 5 ký tự cuối): chỉ ghi "có khoá", "khớp khoá trong mẫu".

function Invoke-Section {
    # Một phần của báo cáo; phần lỗi thì ghi lý do rồi chạy tiếp phần sau.
    param([string]$Title, [scriptblock]$Body)
    Write-Head $Title
    try { & $Body } catch { Write-Warn ('Không đọc được phần này: {0}' -f $_.Exception.Message.Trim()) }
}

function Get-WindowsInfo {
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $name = [string](Get-RegValue $k 'ProductName')
    $build = 0
    [void][int]::TryParse([string](Get-RegValue $k 'CurrentBuildNumber'), [ref]$build)
    if ($build -ge 22000) { $name = $name -replace 'Windows 10', 'Windows 11' }   # registry vẫn ghi Windows 10 trên Windows 11
    return [pscustomobject]@{ Name = $name; Version = [string](Get-RegValue $k 'DisplayVersion'); Build = ('{0}.{1}' -f $build, (Get-RegValue $k 'UBR')) }
}

function Invoke-KiemTra {
    param([string]$Mau = '', [string]$CauHinh = '')
    $script:Report.Clear(); $script:Findings.Clear()
    $started = Get-Date
    Write-Out 'BÁO CÁO OFFICE' 'Cyan'
    Write-Out ('Máy {0}, {1:dd/MM/yyyy HH:mm}. Công cụ "Gỡ sạch và cài Office theo mẫu" {2}: chỉ đọc, không thay đổi gì trên máy. Báo cáo không chứa khoá sản phẩm.' -f $env:COMPUTERNAME, $started, $script:ToolVersion)

    $state = Get-OfficeState
    $dir = Find-TemplateDir $Mau
    $t = if ($dir) { Read-OfficeTemplate $dir $CauHinh } else { $null }
    $lic = @()
    $licError = ''
    try { $lic = @(Get-OfficeLicenses $(if ($t) { $t.KeyHashes } else { @() })) } catch { $licError = $_.Exception.Message.Trim() }

    Invoke-Section 'Máy này' { Show-MachineSection }
    Invoke-Section 'Office trên máy' { Show-InstalledSection $state $t }
    Invoke-Section 'Giấy phép' { Show-LicenseSection $lic $licError $t }
    Invoke-Section 'Bộ cài mẫu' { Show-TemplateSection $t $state }
    Invoke-Section 'Ứng dụng Office đang mở' { Show-RunningSection }
    Invoke-Section 'Sẽ sao lưu trước khi gỡ' { Show-BackupSection }
    if (-not $state.Any) { Invoke-Section 'Phần Click-to-Run còn sót' { Show-LeftoverSection $state } }
    Show-Conclusion

    if (-not (Save-Report 'BaoCao_Office' $started)) { return 1 }
    return 0
}

# ---------------------------------------------------------------- các phần của báo cáo
function Show-MachineSection {
    $w = Get-WindowsInfo
    $bits = if ([Environment]::Is64BitOperatingSystem) { '64 bit' } else { '32 bit' }
    Write-Line ('Windows: {0} {1}, build {2}, {3}' -f $w.Name, $w.Version, $w.Build, $bits)
    $free = Get-FreeSpace
    if ($free -ge 0) {
        Write-Line ('Ổ {0} còn trống {1}' -f $env:SystemDrive, (Format-Size $free))
        if ($free -lt $script:MinFreeBytes) { Add-Finding warn ('Ổ {0} còn dưới 4 GB trống: không đủ chỗ cài Office.' -f $env:SystemDrive) -Hint 'Dọn bớt file (Disk Cleanup, thùng rác, Downloads) trước khi cài.' }
    }
    $console = Get-ConsoleUser
    if ($console) { Write-Line ('Người đang dùng máy: {0}' -f $console) }
    Write-Line ('Công cụ chạy bằng tài khoản {0}{1}' -f (Get-CurrentUser), $(if (Test-IsAdmin) { ', quyền Admin' } else { '' }))
    if (-not (Test-SameUser)) { Write-Info 'Mẫu Word, macro, giấy phép tài khoản trong báo cáo là của tài khoản đang chạy công cụ, không phải người đang dùng máy.' }
}

function Show-InstalledSection {
    param($State, $T)
    Show-OfficeState $State
    $tplOk = ($T -and -not $T.Problems.Count)
    $c = $State.C2R
    $families = 0
    if ($c -and $c.Products.Count) {
        $families++
        foreach ($id in $c.Products) {
            $lc = Get-ProductLifecycle $id
            if ($lc.Status -in 'ended', 'soon') {
                $fix = if ($tplOk -and -not (Test-SameAsTemplate $T $c) -and -not @($T.Products | Where-Object { (Get-ProductLifecycle $_.Id).Status -eq 'ended' }).Count) { 'go-va-cai' } else { '' }
                Add-Finding warn $lc.Text -Fix $fix -Hint 'Nên chuyển sang Office LTSC 2024 hoặc Microsoft 365 (tạo file cấu hình mới ở https://config.office.com).'
            } elseif ($lc.Text) { Write-Info $lc.Text }
        }
        if ($c.UpdatesEnabled -ieq 'False') { Add-Finding info 'Office đang tắt cập nhật tự động: không nhận bản vá bảo mật.' -Hint 'Bật lại trong Word: File > Account > Update Options > Enable Updates.' }
    } elseif ($State.C2RArp.Count) {
        Add-Finding bad 'Office Click-to-Run bị hỏng: còn mục gỡ cài đặt nhưng thiếu cấu hình.' -Fix $(if ($tplOk) { 'go-va-cai' } else { 'go-sach' })
    }
    if ($State.Suites.Count) {
        $families++
        foreach ($s in $State.Suites) {
            $lc = Get-ProductLifecycle -MsiMajor $s.Major
            if ($lc.Status -eq 'ended') { Add-Finding warn ('{0}: {1}' -f $s.Name, $lc.Text) -Fix $(if ($tplOk) { 'go-va-cai' } else { 'go-sach' }) }
        }
    }
    if ($State.Store.Count) { $families++ }
    if ($families -gt 1) { Add-Finding warn 'Máy có nhiều kiểu Office cùng lúc (Click-to-Run, MSI, Microsoft Store): dễ lỗi khi mở file, cập nhật, kích hoạt.' -Fix $(if ($tplOk) { 'go-va-cai' } else { 'go-sach' }) }
    if ($State.Msi.Count -and -not $State.Suites.Count -and -not ($c -and $c.Products.Count)) { Write-Info 'Chỉ còn sản phẩm Office MSI lẻ (không có bộ Office).' }
    if (-not $State.Any) {
        if ($tplOk) { Add-Finding info 'Máy chưa cài Office.' -Fix 'cai-dat' } else { Write-Info 'Máy chưa cài Office.' }
    }
}

function Show-LicenseSection {
    param($Lic, [string]$LicError, $T)
    if ($LicError) { Write-Warn ('Không đọc được giấy phép trong Windows: {0}' -f $LicError) }
    elseif (-not $Lic.Count) { Write-Line 'Windows không có khoá sản phẩm Office nào.' }
    foreach ($l in $Lic) {
        $desc = if ($l.Name) { $l.Name } else { $l.Description }
        Write-Line ('{0}: {1}' -f $desc, (Get-LicenseStatusText $l.Status $l.GraceMinutes))
        Write-Sub ('Loại khoá: {0}{1}' -f (Get-LicenseChannelText $l.Channel), $(if ($T -and $T.KeyHashes.Count) { if ($l.KeyMatch) { ', trùng khoá trong mẫu' } else { ', khác khoá trong mẫu' } } else { '' }))
        $kms = if ($l.KmsHost) { $l.KmsHost } else { $l.KmsFound }
        if ($kms) { Write-Sub ('Máy chủ KMS: {0}' -f $kms) }
        if ($l.Status -ne 1) { Add-Finding warn ('{0} chưa kích hoạt.' -f $desc) -Fix 'kich-hoat' -Hint 'Bản Volume cần mạng có máy chủ KMS của tổ chức, hoặc khoá MAK còn lượt.' }
        if ($l.KmsHost) {
            $domain = $false
            try { $domain = [bool](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain } catch { }
            if (-not $domain) { Add-Finding warn ('Office kích hoạt qua máy chủ KMS {0} trong khi máy không vào domain công ty.' -f $l.KmsHost) -Hint 'Nếu đây không phải máy chủ của công ty bạn thì Office đang kích hoạt không chính thống: gỡ sạch rồi cài theo mẫu có khoá hợp lệ.' }
        }
    }
    $lf = Join-Path $env:LOCALAPPDATA 'Microsoft\Office\Licenses'
    if (Test-Path -LiteralPath $lf) {
        $n = @(Get-ChildItem -LiteralPath $lf -Recurse -File -ErrorAction SilentlyContinue).Count
        if ($n) { Write-Line ('Giấy phép Microsoft 365 của {0}: {1} file.' -f (Get-CurrentUser), $n) }
    }
    $own = @($Lic | Where-Object { $_.Status -eq 1 -and $_.Channel -notmatch 'GVLK' -and -not $_.KeyMatch })
    if ($T -and $T.KeyKind -eq 'gvlk' -and $own.Count -and -not (Test-KmsDiscoverable)) {
        Add-Finding warn 'Cài lại từ mẫu này thì Office sẽ chưa kích hoạt: mẫu chỉ có khoá KMS chung, máy không thấy máy chủ KMS, còn khoá đang dùng sẽ bị gỡ cùng Office.' -Hint 'Chuẩn bị sẵn khoá MAK hoặc khoá bản quyền Office; cài xong chọn N (nhập khoá) ở bước kích hoạt, hoặc chạy "Kích hoạt Office".'
    }
    $traces = @(Find-KmsTraces)
    if ($traces.Count) {
        Add-Finding warn ('Thấy dấu vết công cụ kích hoạt không chính thống: {0}.' -f ($traces -join '; ')) -Hint 'Các công cụ này hay kèm mã độc: quét virus toàn bộ máy (Microsoft Defender) và gỡ chúng; công cụ này không tự xoá.'
    }
}

function Show-TemplateSection {
    param($T, $State)
    if (-not $T) {
        Add-Finding warn 'Không thấy bộ cài mẫu (setup.exe và file cấu hình).' -Hint 'Chép cả thư mục mẫu vào tools\office\mau, hoặc chọn thư mục mẫu ở ô "Thư mục bộ cài mẫu" khi chạy.'
        return
    }
    Show-TemplateInfo $T
    foreach ($p in $T.Problems) { Add-Finding bad $p }
    if ($T.Candidates.Count) { Write-Sub ('Các file cấu hình: {0}. Chọn một file ở ô "File cấu hình" (tham số -CauHinh).' -f ($T.Candidates -join ', ')) }
    foreach ($w in $T.Warnings) { Add-Finding warn $w }
    foreach ($p in $T.Products) {
        $lc = Get-ProductLifecycle $p.Id
        if ($lc.Status -in 'ended', 'soon') { Add-Finding warn ('Mẫu cài ' + $lc.Text) -Hint 'Tạo mẫu mới ở https://config.office.com (Office LTSC 2024 hoặc Microsoft 365), tải về cùng setup.exe mới.' }
    }
    if ($T.Problems.Count) { return }
    if ($T.Source -and -not $T.Source.Complete) {
        if (Test-Internet) { Write-Info 'Máy vào được máy chủ tải Office của Microsoft: cài được, nhưng tải vài GB.' }
        else { Add-Finding bad 'Mẫu thiếu bộ cài mà máy không vào được máy chủ tải Office của Microsoft.' -Hint 'Chép đủ thư mục Office\Data của mẫu, hoặc nối mạng rồi chạy lại.' }
    }
    if (Test-TemplateInsideOffice $T $State) {
        Add-Finding bad ('Bộ cài mẫu nằm trong thư mục cài Office ({0}): gỡ Office có thể xoá mất mẫu.' -f $T.Dir) -Hint 'Chép mẫu ra chỗ khác (vd D:\MauOffice) rồi chọn thư mục mới khi chạy.'
    }
    if (Test-SameAsTemplate $T $State.C2R) { Write-Ok 'Office trên máy đúng sản phẩm, 32/64 bit, kênh như mẫu.' }
    elseif ($State.Any) { Add-Finding info 'Office trên máy khác mẫu.' -Fix 'go-va-cai' }
    $ace = @($State.Ace)
    if ($T.RemoveMSI -and $ace.Count) {
        Add-Finding warn ('RemoveMSI trong mẫu có thể gỡ cả {0}.' -f (($ace | ForEach-Object { $_.Name }) -join ', ')) -Hint 'Máy có phần mềm cần nó (kế toán, nhập liệu...) thì thêm <IgnoreProduct ID="AceRedist" /> vào trong <RemoveMSI> của file cấu hình.'
    }
}

function Show-RunningSection {
    $run = @(Get-OfficeRunning)
    if (-not $run.Count) { Write-Line 'Không có ứng dụng Office nào đang mở.'; return }
    Write-Line ('Đang mở: {0}. Gỡ, cài sẽ hỏi đóng trước.' -f (($run | ForEach-Object { if ($_.Count -gt 1) { "$($_.Label) ($($_.Count))" } else { $_.Label } }) -join ', '))
}

function Show-BackupSection {
    Show-UserDataPlan @(Get-UserDataPlan)
    Write-Info 'Gỡ Office không xoá các file này; công cụ vẫn sao lưu trước để trả lại được nếu cần.'
}

function Show-LeftoverSection {
    param($State)
    $left = Get-OfficeLeftovers $State
    if (-not $left.Any) { Write-Ok 'Không còn gì của Click-to-Run.'; return }
    if ($left.Service) { Write-Line 'Dịch vụ ClickToRunSvc' }
    foreach ($t in $left.Tasks) { Write-Line "Tác vụ hẹn giờ $t" }
    foreach ($f in $left.Folders) { Write-Line "Thư mục $f" }
    foreach ($k in $left.Keys) { Write-Line "Khoá registry $k" }
    foreach ($a in $left.ArpKeys) { Write-Line "Mục gỡ cài đặt '$($a.Name)'" }
    foreach ($m in $left.C2RMsi) { Write-Line "Thành phần $($m.Name)" }
    Add-Finding warn 'Đã gỡ Office nhưng còn sót phần Click-to-Run: cài Office mới dễ lỗi.' -Fix 'go-sach'
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
        Write-Ok 'Không thấy vấn đề Office nào cần xử lý.'
    } else {
        if ($nBad + $nWarn) { Write-Line ('{0} lỗi, {1} cảnh báo. Nên xử lý theo thứ tự:' -f $nBad, $nWarn) }
        else { Write-Line 'Không có lỗi hay cảnh báo. Gợi ý:' }
        foreach ($f in $show) {
            switch ($f.Level) { 'bad' { Write-Bad $f.Text } 'warn' { Write-Warn $f.Text } default { Write-Info $f.Text } }
            if ($f.Fix -and $script:Modes.Contains($f.Fix)) {
                $m = $script:Modes[$f.Fix]
                Write-Sub ('→ Chạy "{0}" (trong Trạm Tool, hoặc OFFICE.bat mục {1}).' -f $m.Label, $m.No)
            }
            if ($f.Hint) { Write-Sub ('→ ' + $f.Hint) }
        }
    }
    Write-Info 'Báo cáo không chứa khoá sản phẩm; gửi người khác được.'
}
