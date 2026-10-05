# Office - gỡ sạch. Các bước, bước nào cũng in ra màn hình và vào nhật ký:
#   1. Sao lưu mẫu, macro, chữ ký Office của người đang dùng máy (ket_qua\sao-luu).
#   2. Đóng ứng dụng Office (hỏi trước).
#   3. Gỡ Click-to-Run bằng ODT của mẫu (<Remove All="TRUE"/>); không có mẫu thì bằng trình gỡ của Office.
#   4. Gỡ Office cài bằng MSI (trình gỡ của Office hiện ra) và Office từ Microsoft Store.
#   5. Tuỳ chọn: quét sâu bằng công cụ gỡ Office của Microsoft (GetHelpCmd, tải bản mới mỗi lần).
#   6. Khi đã hết Office: dọn dịch vụ, tác vụ hẹn giờ, thư mục, registry còn sót của Click-to-Run.
#   7. Gỡ khoá sản phẩm, giấy phép Office (cả thiết lập KMS); tuỳ chọn: xoá thiết lập Office của người dùng.
# Không sao lưu registry HKLM của Click-to-Run: trong đó có thể có khoá sản phẩm. Không gỡ Access Database Engine.

$script:GetHelpUrl = 'https://aka.ms/SaRA_EnterpriseVersionFiles'
$script:GetHelpFull = 'https://aka.ms/SaRA_Home'
# Mã kết quả GetHelpCmd (in dạng "NN: ..."): @(kết quả, câu báo).
$script:GetHelpCodes = @{
    '00' = @('ok', 'Đã quét và gỡ xong. Nên khởi động lại máy để Windows dọn nốt.')
    '06' = @('apps', 'Còn ứng dụng Office (hoặc Teams bản cũ) đang mở: đóng hết rồi chạy lại.')
    '08' = @('fail', "Có nhiều bản Office, bản dòng lệnh không tự xử lý được: dùng Get Help bản đầy đủ ($script:GetHelpFull).")
    '09' = @('fail', "Công cụ của Microsoft không gỡ được Office: dùng Get Help bản đầy đủ ($script:GetHelpFull).")
    '10' = @('fail', 'Công cụ của Microsoft cần quyền Admin.')
    '66' = @('none', 'Không thấy bản Office cần gỡ.')
    '67' = @('fail', 'Phiên bản Office chỉ định không hợp lệ.')
    '68' = @('none', 'Không còn Office nào để gỡ.')
}

function New-TempDir {
    $d = Join-Path $env:TEMP ('TramTool_Office_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    [void](New-Item -ItemType Directory -Path $d -Force)
    return $d
}

function Get-RemovalOdt {
    # setup.exe của mẫu để gỡ: chỉ dùng khi có chữ ký Microsoft hợp lệ. '' khi không dùng được.
    param([string]$TemplateDir)
    if (-not $TemplateDir) { return '' }
    $s = Join-Path $TemplateDir 'setup.exe'
    if (-not (Test-Path -LiteralPath $s -PathType Leaf)) { return '' }
    $sig = Get-AuthenticodeSignature -LiteralPath $s
    if ([string]$sig.Status -eq 'Valid' -and $sig.SignerCertificate -and $sig.SignerCertificate.Subject -match 'CN=Microsoft Corporation') { return $s }
    return ''
}

function Test-SafeToDelete {
    # Chỉ xoá thư mục nằm dưới Program Files, Common Files, ProgramData; không bao giờ xoá thư mục mẫu, thư mục công cụ
    # hay thư mục cha của chúng; không xoá junction, symlink.
    param([string]$Path, [string[]]$Protect = @())
    try { $full = [IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return $false }
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:CommonProgramFiles, ${env:CommonProgramFiles(x86)}, $env:ProgramData) |
        Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') }
    $under = $false
    foreach ($r in $roots) { if ($full.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)) { $under = $true } }
    if (-not $under) { return $false }
    foreach ($p in @(@($Protect) + $script:ToolDir) | Where-Object { $_ }) {
        try { $pf = [IO.Path]::GetFullPath($p).TrimEnd('\') } catch { continue }
        if ($pf.Equals($full, [StringComparison]::OrdinalIgnoreCase) -or $pf.StartsWith($full + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
    if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
    return $true
}

function Remove-SafeFolder {
    # Xoá một thư mục sót sau khi đã qua Test-SafeToDelete. Trả $true khi đã hết thư mục.
    param([string]$Path, [string[]]$Protect = @())
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    if (-not (Test-SafeToDelete $Path $Protect)) {
        Write-Warn "Không xoá $Path (có bộ cài mẫu hay công cụ bên trong, hoặc không nằm trong Program Files, ProgramData)."
        return $false
    }
    # Directory.Delete không đi theo junction bên trong; lỗi (file chỉ đọc) thì thử Remove-Item -Force.
    try { [IO.Directory]::Delete($Path, $true) } catch { try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop } catch { } }
    if (Test-Path -LiteralPath $Path) { Write-Warn "Chưa xoá hết $Path (file đang được dùng): khởi động lại máy rồi chạy lại."; return $false }
    Write-Ok "Đã xoá $Path"
    return $true
}

function Split-CommandLine {
    # '"C:\x\setup.exe" /uninstall PROPLUS' → @('C:\x\setup.exe', '/uninstall PROPLUS').
    param([string]$Command)
    $c = ([string]$Command).Trim()
    if ($c.StartsWith('"')) {
        $end = $c.IndexOf('"', 1)
        if ($end -lt 0) { return @($c.Trim('"'), '') }
        return @($c.Substring(1, $end - 1), $c.Substring($end + 1).Trim())
    }
    $m = [regex]::Match($c, '(?i)^(.+?\.exe)(\s+.*)?$')
    if ($m.Success) { return @($m.Groups[1].Value, $m.Groups[2].Value.Trim()) }
    return @($c, '')
}

function Invoke-Uninstaller {
    # Chạy trình gỡ ghi trong "Gỡ cài đặt chương trình" và chờ xong. Trả mã thoát ($null khi quá giờ, -1 khi không chạy được).
    param([string]$Command, [string]$What, [int]$TimeoutMin = 60)
    $exe, $args2 = Split-CommandLine $Command
    if (-not $exe) { return -1 }
    try {
        $p = if ($args2) { Start-Process -FilePath $exe -ArgumentList $args2 -PassThru } else { Start-Process -FilePath $exe -PassThru }
    } catch { Write-Bad ("Không chạy được trình gỡ của {0}: {1}" -f $What, $_.Exception.Message.Trim()); return -1 }
    return (Wait-ProcessVisible $p $What $TimeoutMin)
}

# ---------------------------------------------------------------- in hiện trạng, kế hoạch
function Format-Platform { param([string]$P) switch ($P) { 'x64' { return '64 bit' } 'x86' { return '32 bit' } } return $P }

function Get-AppLabel {
    param([string]$Id)
    if ($script:OfficeApps.Contains($Id)) { return $script:OfficeApps[$Id][0] }
    if ($script:ExcludeNames.ContainsKey($Id)) { return $script:ExcludeNames[$Id] }
    return $Id
}

function Show-OfficeState {
    # In Office đang có (dùng cho kiểm tra, gỡ, cài).
    param($State)
    $c = $State.C2R
    if ($c -and $c.Products.Count) {
        foreach ($id in $c.Products) { Write-Line ('Click-to-Run: {0} ({1})' -f (Get-ProductName $id), $id) }
        Write-Sub ('Bản {0}, {1}, ngôn ngữ {2}, kênh {3}' -f $c.Version, (Format-Platform $c.Platform), $c.Culture, $c.Channel.Label)
        if ($c.InstallPath) { Write-Sub ('Thư mục cài: ' + $c.InstallPath) }
        if ($c.Apps.Count) { Write-Sub ('Ứng dụng: ' + (($c.Apps | ForEach-Object { Get-AppLabel $_ }) -join ', ')) }
    } elseif ($State.C2RArp.Count) {
        Write-Line ('Click-to-Run hỏng (chỉ còn mục gỡ cài đặt): {0}' -f (($State.C2RArp | ForEach-Object { $_.Name }) -join ', '))
    }
    foreach ($s in $State.Suites) { Write-Line ('Cài bằng MSI: {0} {1}' -f $s.Name, $s.Version) }
    foreach ($m in $State.Msi) { Write-Line ('MSI lẻ: {0} {1}' -f $m.Name, $m.Version) }
    foreach ($a in $State.Store) { Write-Line ('Từ Microsoft Store: {0} {1}' -f $a.Name, $a.Version) }
    foreach ($a in $State.Ace) { Write-Sub ('Có {0}: không phải Office, công cụ giữ nguyên.' -f $a.Name) }
    if (-not $State.Any) { Write-Line 'Không thấy Office nào trên máy.' }
}

function Get-C2RNames {
    param($State)
    if ($State.C2R -and $State.C2R.Products.Count) { return (($State.C2R.Products | ForEach-Object { Get-ProductName $_ }) -join ', ') }
    return (($State.C2RArp | ForEach-Object { $_.Name }) -join ', ')
}

function Show-RemovePlan {
    param($State, $Left, [string]$Odt, [bool]$SameUser, [int]$LicenseCount, [switch]$QuetSau, [switch]$XoaThietLap)
    $plan = @(Get-UserDataPlan)
    if ($SameUser) {
        $size = [int64](($plan | Measure-Object Bytes -Sum).Sum)
        if ($plan.Count) { Write-Plan ('Sao lưu mẫu, macro, chữ ký Office của {0} ({1}) vào ket_qua\sao-luu' -f (Get-CurrentUser), (Format-Size $size)) }
        if ($XoaThietLap) { Write-Plan 'Sao lưu thiết lập Office trong registry (Office.reg) để trả lại được' }
    } else {
        Write-Warn ('Cửa sổ này chạy bằng tài khoản {0}, khác người đang dùng máy ({1}): bỏ qua phần của từng người dùng (sao lưu, giấy phép tài khoản, thiết lập).' -f (Get-CurrentUser), (Get-ConsoleUser))
    }
    Write-Plan 'Đóng ứng dụng Office đang mở (hỏi trước)'
    if (($State.C2R -and $State.C2R.Products.Count) -or $State.C2RArp.Count) {
        if ($Odt) { Write-Plan ('Gỡ {0} bằng Office Deployment Tool của mẫu (chạy ngầm, thường 5-15 phút)' -f (Get-C2RNames $State)) }
        else { Write-Plan ('Gỡ {0} bằng trình gỡ của Office: cửa sổ của Microsoft hiện ra, bấm Uninstall (Gỡ cài đặt)' -f (Get-C2RNames $State)) }
    }
    foreach ($s in $State.Suites) { Write-Plan ('Gỡ {0} (cài bằng MSI): cửa sổ gỡ của Office hiện ra, làm theo hướng dẫn' -f $s.Name) }
    foreach ($m in $State.Msi) { Write-Plan ('Gỡ {0} (MSI)' -f $m.Name) }
    foreach ($a in $State.Store) { Write-Plan ('Gỡ {0} (Microsoft Store, mọi tài khoản)' -f $a.Name) }
    if ($QuetSau) {
        Write-Plan 'Quét sâu bằng công cụ gỡ Office của Microsoft (GetHelpCmd): tải về (cần mạng), mở điều khoản để đọc, hỏi trước khi chạy'
        if ($State.Ace.Count) { Write-Warn ('Quét sâu do công cụ của Microsoft tự quyết gỡ gì, có thể gỡ cả {0}: phần mềm cần nó (kế toán, nhập liệu) phải cài lại.' -f (($State.Ace | ForEach-Object { $_.Name }) -join ', ')) }
    }
    Write-Plan 'Khi đã hết Office: dọn dịch vụ ClickToRunSvc, tác vụ hẹn giờ \Microsoft\Office\, thư mục Click-to-Run trong Program Files, ProgramData, khoá registry còn sót'
    if ($LicenseCount) { Write-Plan ('Gỡ {0} khoá sản phẩm Office khỏi Windows (cả máy chủ KMS đã đặt)' -f $LicenseCount) }
    if ($SameUser) {
        Write-Plan 'Xoá giấy phép, tài khoản đã đăng nhập Office của người dùng này (đăng nhập lại khi cần)'
        if ($XoaThietLap) { Write-Plan 'Xoá thiết lập Office của người dùng này (HKCU\Software\Microsoft\Office, cả hồ sơ Outlook)' }
    }
}

# ---------------------------------------------------------------- từng bước gỡ
function Invoke-OdtRemove {
    # Gỡ mọi sản phẩm Click-to-Run bằng setup.exe của mẫu với file cấu hình gỡ tạm (không có khoá).
    param([string]$Setup)
    $tmp = New-TempDir
    try {
        $logDir = Get-ResultDir 'nhat-ky-odt'
        $xml = Join-Path $tmp 'GoOffice.xml'
        $lines = @(
            '<Configuration>'
            '  <Remove All="TRUE" />'
            '  <Display Level="None" AcceptEULA="TRUE" />'
            '  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />'
            ('  <Logging Level="Standard" Path="{0}" />' -f [Security.SecurityElement]::Escape($logDir))
            '</Configuration>'
        )
        [IO.File]::WriteAllText($xml, ($lines -join "`r`n"), $script:Utf8NoBom)
        Write-Line 'Đang gỡ bằng Office Deployment Tool (chạy ngầm, không có cửa sổ)...'
        $p = Start-Process -FilePath $Setup -ArgumentList ('/configure "{0}"' -f $xml) -WorkingDirectory (Split-Path -Parent $Setup) -PassThru
        $code = Wait-ProcessVisible $p 'Đang gỡ' 90
        if ($null -eq $code) { Write-Warn 'ODT chạy quá 90 phút, công cụ không chờ nữa.'; return -1 }
        if ($code -eq 0) { Write-Ok 'Office Deployment Tool đã gỡ xong.' }
        else { Write-Bad ('Office Deployment Tool báo lỗi {0}. Nhật ký của ODT: {1}' -f (Format-ErrorCode $code), $logDir) }
        return $code
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-ArpC2RRemove {
    # Không có ODT: chạy trình gỡ của Office cho từng mục Click-to-Run (người dùng bấm Uninstall trong cửa sổ hiện ra).
    param($Entries)
    $last = 0
    foreach ($e in $Entries) {
        if (-not (Test-Path -LiteralPath $e.RegPath)) { continue }   # đã gỡ cùng mục trước
        Write-Line ('Mở trình gỡ của {0}: bấm Uninstall (Gỡ cài đặt) trong cửa sổ của Microsoft.' -f $e.Name)
        $code = Invoke-Uninstaller $e.Uninstall 'Đang gỡ' 90
        if ($null -eq $code) { Write-Warn 'Trình gỡ chạy quá 90 phút, công cụ không chờ nữa.'; $last = -1; continue }
        if ($code -ne 0) { Write-Warn ('Trình gỡ của {0} kết thúc với mã {1}.' -f $e.Name, (Format-ErrorCode $code)); $last = $code }
    }
    return $last
}

function Invoke-MsiRemove {
    # Office cài bằng MSI: bộ Office (Setup Controller, có cửa sổ) và sản phẩm MSI lẻ (msiexec, cửa sổ tiến trình).
    # Trả @{ Failed; Reboot }.
    param($State)
    $fail = 0; $reboot = $false
    foreach ($s in $State.Suites) {
        Write-Line ('Mở trình gỡ của {0}: làm theo hướng dẫn trong cửa sổ của Office.' -f $s.Name)
        $code = Invoke-Uninstaller $s.Uninstall 'Đang gỡ' 60
        if ($code -in 3010, 1641) { $reboot = $true; Write-Ok "$($s.Name): đã gỡ, cần khởi động lại máy." }
        elseif ($code -eq 0) { Write-Ok "$($s.Name): đã gỡ." }
        else { $fail++; Write-Bad ('{0}: trình gỡ kết thúc với mã {1}.' -f $s.Name, (Format-ErrorCode $code)) }
    }
    foreach ($m in $State.Msi) {
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList ('/x {0} /passive /norestart' -f $m.Code) -PassThru
        $code = Wait-ProcessVisible $p 'Đang gỡ' 60
        if ($code -in 3010, 1641) { $reboot = $true; Write-Ok "$($m.Name): đã gỡ, cần khởi động lại máy." }
        elseif ($code -in 0, 1605) { Write-Ok "$($m.Name): đã gỡ." }
        elseif ($code -eq 1602) { $fail++; Write-Warn "$($m.Name): đã huỷ gỡ." }
        else { $fail++; Write-Bad ('{0}: msiexec báo lỗi {1}.' -f $m.Name, (Format-ErrorCode $code)) }
    }
    return [pscustomobject]@{ Failed = $fail; Reboot = $reboot }
}

function Invoke-StoreRemove {
    param($State)
    $fail = 0
    foreach ($a in $State.Store) {
        try { Remove-AppxPackage -Package $a.FullName -AllUsers -ErrorAction Stop; Write-Ok "$($a.Name): đã gỡ." }
        catch { $fail++; Write-Bad ('{0}: không gỡ được ({1}).' -f $a.Name, $_.Exception.Message.Trim()) }
    }
    return $fail
}

function Invoke-GetHelpScrub {
    # Quét sâu bằng công cụ gỡ Office của Microsoft (Get Help bản dòng lệnh). Mỗi bản chỉ dùng được 90 ngày nên tải
    # bản mới mỗi lần; kiểm chữ ký; mở điều khoản cho người dùng đọc và hỏi đồng ý rồi mới chạy. Xong thì xoá file tải.
    # Trả @{ Code ('00'...'68', 'skip', 'error'); Ok ($true khi 00, 66, 68) }.
    $tmp = New-TempDir
    try {
        Write-Line 'Đang tải công cụ gỡ Office của Microsoft...'
        $zip = Join-Path $tmp 'GetHelp.zip'
        $old = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $script:GetHelpUrl -OutFile $zip -UseBasicParsing -TimeoutSec 600
            Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'x') -Force
        } catch {
            Write-Bad ('Không tải được công cụ của Microsoft: {0}' -f $_.Exception.Message.Trim())
            return [pscustomobject]@{ Code = 'error'; Ok = $false }
        } finally { $ProgressPreference = $old }
        $exe = Get-ChildItem -LiteralPath (Join-Path $tmp 'x') -Recurse -Filter 'GetHelpCmd.exe' -File | Select-Object -First 1
        if (-not $exe) { Write-Bad 'Gói tải về không có GetHelpCmd.exe.'; return [pscustomobject]@{ Code = 'error'; Ok = $false } }
        $sig = Get-AuthenticodeSignature -LiteralPath $exe.FullName
        if ([string]$sig.Status -ne 'Valid' -or -not $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch 'CN=Microsoft Corporation') {
            Write-Bad 'GetHelpCmd.exe tải về không có chữ ký số hợp lệ của Microsoft: không chạy.'
            return [pscustomobject]@{ Code = 'error'; Ok = $false }
        }
        $eula = Join-Path $tmp 'DieuKhoan_GetHelp.txt'
        [void](Invoke-Native $exe.FullName @('-DisplayEULA', $eula))
        if (Test-Path -LiteralPath $eula) {
            Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $eula)
            Write-Line 'Điều khoản sử dụng công cụ của Microsoft đã mở trong Notepad, đọc trước khi chọn.'
        } else {
            Write-Line "Điều khoản sử dụng: chạy GetHelpCmd.exe -DisplayEULA, hoặc xem $script:GetHelpFull."
        }
        $c = Read-Choice 'Gõ C nếu đồng ý điều khoản và chạy quét sâu, B để bỏ qua bước này' @('C', 'B') 'B'
        if ($c -ne 'C') { Write-Info 'Đã bỏ qua quét sâu.'; return [pscustomobject]@{ Code = 'skip'; Ok = $true } }
        if ((Close-OfficeApps 'quét sâu') -eq 'cancel') { Write-Info 'Đã bỏ qua quét sâu.'; return [pscustomobject]@{ Code = 'skip'; Ok = $true } }
        $out = Join-Path $tmp 'ketqua.txt'
        Write-Line 'Đang quét sâu (thường 5-20 phút, không có cửa sổ)...'
        $p = Start-Process -FilePath $exe.FullName -ArgumentList '-S OfficeScrubScenario -AcceptEula -OfficeVersion All' -WorkingDirectory $exe.DirectoryName `
            -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError (Join-Path $tmp 'loi.txt')
        $exit = Wait-ProcessVisible $p 'Đang quét sâu' 90
        if ($null -eq $exit) { Write-Warn 'Quét sâu chạy quá 90 phút, công cụ không chờ nữa.'; return [pscustomobject]@{ Code = 'error'; Ok = $false } }
        $text = if (Test-Path -LiteralPath $out) { [IO.File]::ReadAllText($out) } else { '' }
        $nn = if ($text -match '(?m)^\s*(\d{2})\s*:') { $Matches[1] } else { '' }
        $h = $script:GetHelpCodes[$nn]
        if (-not $h) { Write-Bad ('Không đọc được kết quả quét sâu (mã thoát {0}).' -f (Format-ErrorCode $exit)); return [pscustomobject]@{ Code = 'error'; Ok = $false } }
        switch ($h[0]) {
            'ok' { Write-Ok "$nn`: $($h[1])" }
            'none' { Write-Info "$nn`: $($h[1])" }
            default { Write-Bad "$nn`: $($h[1])" }
        }
        return [pscustomobject]@{ Code = $nn; Ok = ($h[0] -in 'ok', 'none') }
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Remove-OfficeLeftovers {
    # Dọn phần Click-to-Run còn sót. Chỉ gọi khi đã hết Office. Trả số mục không dọn được.
    param($Left, [string[]]$Protect = @())
    $fail = 0
    foreach ($n in 'OfficeClickToRun', 'OfficeC2RClient', 'AppVShNotify') {
        Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill() } catch { } }
    }
    if ($Left.Service) {
        try { Stop-Service -Name 'ClickToRunSvc' -Force -ErrorAction Stop } catch { }
        $r = Invoke-Native 'sc.exe' @('delete', 'ClickToRunSvc')
        if ($r.Code -in 0, 1072) { Write-Ok 'Đã xoá dịch vụ ClickToRunSvc.' }   # 1072: đã đánh dấu xoá, xong khi khởi động lại
        else { $fail++; Write-Bad ('Không xoá được dịch vụ ClickToRunSvc (lỗi {0}).' -f $r.Code) }
    }
    $nTask = 0
    foreach ($t in $Left.Tasks) {
        $cut = $t.LastIndexOf('\') + 1
        try { Unregister-ScheduledTask -TaskPath $t.Substring(0, $cut) -TaskName $t.Substring($cut) -Confirm:$false -ErrorAction Stop; $nTask++ }
        catch { $fail++; Write-Bad "Không xoá được tác vụ hẹn giờ $t." }
    }
    if ($nTask) { Write-Ok ('Đã xoá {0} tác vụ hẹn giờ của Office.' -f $nTask) }
    foreach ($m in $Left.C2RMsi) {
        $p = Start-Process -FilePath 'msiexec.exe' -ArgumentList ('/x {0} /qn /norestart' -f $m.Code) -PassThru -Wait
        if ($p.ExitCode -in 0, 1605, 3010) { Write-Ok "Đã gỡ $($m.Name)." } else { $fail++; Write-Bad ('Không gỡ được {0} (lỗi {1}).' -f $m.Name, $p.ExitCode) }
    }
    foreach ($f in $Left.Folders) { if (-not (Remove-SafeFolder $f $Protect)) { $fail++ } }
    foreach ($a in $Left.ArpKeys) {
        try { Remove-Item -LiteralPath $a.RegPath -Recurse -Force -ErrorAction Stop; Write-Ok "Đã xoá mục gỡ cài đặt '$($a.Name)'." }
        catch { $fail++; Write-Bad "Không xoá được mục gỡ cài đặt '$($a.Name)'." }
    }
    foreach ($k in $Left.Keys) {
        try { Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction Stop; Write-Ok "Đã xoá khoá registry $k." }
        catch { $fail++; Write-Bad "Không xoá hết khoá registry $k." }
    }
    return $fail
}

function Show-LostAce {
    # Báo Access Database Engine có trước mà giờ không còn: quét sâu, thẻ <RemoveMSI> của mẫu có thể gỡ nó.
    param($Before, $After, [string]$Why = '')
    foreach ($a in @($Before)) {
        if (-not @(@($After) | Where-Object { $_.Name -eq $a.Name }).Count) {
            Write-Warn ('{0} không còn trên máy{1}: phần mềm cần nó (kế toán, nhập liệu) phải cài lại.' -f $a.Name, $Why)
        }
    }
}

function Remove-OfficeCredentials {
    # Tài khoản Office lưu trong Credential Manager (MicrosoftOffice15_Data, MicrosoftOffice16_Data) của người đang chạy.
    # Tên mục có địa chỉ email nên chỉ đếm, không in. Trả @(đã xoá, không xoá được).
    $list = Invoke-Native 'cmdkey.exe' @('/list')
    $targets = @([regex]::Matches($list.Output, '(?i)(?:LegacyGeneric:target=)?(MicrosoftOffice1[56]_Data:\S+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $ok = 0; $fail = 0
    foreach ($t in $targets) {
        $r = Invoke-Native 'cmdkey.exe' @("/delete:LegacyGeneric:target=$t")
        if ($r.Code -ne 0) { $r = Invoke-Native 'cmdkey.exe' @("/delete:$t") }
        if ($r.Code -eq 0) { $ok++ } else { $fail++ }
    }
    return @($ok, $fail)
}

function Remove-OfficeLicenses {
    # Gỡ khoá sản phẩm Office khỏi Windows (xoá cả máy chủ KMS đã đặt cho Office); -SameUser: giấy phép, tài khoản
    # Office của người đang chạy (thư mục Licenses, khoá Licensing, Identity, Credential Manager). Trả số mục lỗi.
    param([bool]$SameUser)
    $fail = 0
    $flt = "ApplicationID='$script:OfficeAppId' AND PartialProductKey IS NOT NULL"
    $prods = @()
    try { $prods = @(Get-CimInstance -ClassName SoftwareLicensingProduct -Filter $flt -ErrorAction Stop) } catch { Write-Warn 'Không đọc được giấy phép trong Windows.' }
    $n = 0
    foreach ($p in $prods) {
        try {
            if ([string]$p.KeyManagementServiceMachine) {
                [void](Invoke-CimMethod -InputObject $p -MethodName 'ClearKeyManagementServiceMachine' -ErrorAction Stop)
                [void](Invoke-CimMethod -InputObject $p -MethodName 'ClearKeyManagementServicePort' -ErrorAction Stop)
            }
            [void](Invoke-CimMethod -InputObject $p -MethodName 'UninstallProductKey' -ErrorAction Stop)
            $n++
        } catch { $fail++; Write-Bad ('Không gỡ được khoá của {0} (lỗi {1}).' -f $p.Name, (Format-ErrorCode (Get-ErrorCode $_))) }
    }
    if ($n) { Write-Ok ('Đã gỡ {0} khoá sản phẩm Office khỏi Windows.' -f $n) }
    if (-not $SameUser) { return $fail }
    $gone = 0
    foreach ($d in (Join-Path $env:LOCALAPPDATA 'Microsoft\Office\Licenses'), (Join-Path $env:LOCALAPPDATA 'Microsoft\Office\16.0\Licensing')) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        try { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop; $gone++ } catch { $fail++; Write-Bad "Không xoá được $d." }
    }
    foreach ($k in 'HKCU:\Software\Microsoft\Office\16.0\Common\Licensing', 'HKCU:\Software\Microsoft\Office\16.0\Common\Identity') {
        if (-not (Test-Path -LiteralPath $k)) { continue }
        try { Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction Stop; $gone++ } catch { $fail++; Write-Bad "Không xoá được $k." }
    }
    $cred = Remove-OfficeCredentials
    $gone += $cred[0]; $fail += $cred[1]
    if ($gone) { Write-Ok ('Đã xoá {0} mục giấy phép, tài khoản Office của {1}.' -f $gone, (Get-CurrentUser)) }
    return $fail
}

# ---------------------------------------------------------------- các bước gỡ, theo thứ tự
function Invoke-RemoveSteps {
    # Trả @{ Code (0, 3, 1223); Clean (đã hết Office); Reboot (cần khởi động lại trước khi cài); Backup (thư mục);
    # Ace (Access Database Engine còn trên máy sau khi gỡ) }.
    param($State, [string]$Odt, [string[]]$Protect = @(), [bool]$SameUser, [switch]$QuetSau, [switch]$XoaThietLap)
    $res = [ordered]@{ Code = 0; Clean = $false; Reboot = $false; Backup = ''; Ace = @($State.Ace) }
    $fail = 0

    $regBacked = $false
    if ($SameUser) {
        Write-Head 'Sao lưu'
        try {
            $b = Backup-OfficeUserData -Registry:$XoaThietLap
            $res.Backup = $b.Dir
            Write-Ok ('Đã sao lưu {0} mục vào {1}' -f $b.Items.Count, $b.Dir)
            foreach ($f in $b.Failed) { Write-Warn "Không sao lưu được: $f" }
            $regBacked = $b.Registry
        } catch {
            Write-Bad ('Sao lưu lỗi: {0}' -f $_.Exception.Message.Trim())
            if (-not (Read-YesNo 'Vẫn gỡ tiếp khi chưa sao lưu được?' $false)) { Write-Info 'Đã dừng, máy chưa bị gỡ gì.'; $res.Code = 1223; return [pscustomobject]$res }
        }
    }

    Write-Head 'Đóng ứng dụng Office'
    if ((Close-OfficeApps 'gỡ Office') -eq 'cancel') { Write-Info 'Đã dừng, máy chưa bị gỡ gì.'; $res.Code = 1223; return [pscustomobject]$res }
    Write-Ok 'Không còn ứng dụng Office nào đang mở.'

    if (($State.C2R -and $State.C2R.Products.Count) -or $State.C2RArp.Count) {
        Write-Head 'Gỡ Office Click-to-Run'
        if ($Odt) { [void](Invoke-OdtRemove $Odt) } else { [void](Invoke-ArpC2RRemove $State.C2RArp) }
    }
    if ($State.Suites.Count -or $State.Msi.Count) {
        Write-Head 'Gỡ Office cài bằng MSI'
        $m = Invoke-MsiRemove $State
        if ($m.Reboot) { $res.Reboot = $true }
    }
    if ($State.Store.Count) {
        Write-Head 'Gỡ Office từ Microsoft Store'
        [void](Invoke-StoreRemove $State)
    }
    if ($QuetSau) {
        Write-Head 'Quét sâu bằng công cụ của Microsoft'
        $g = Invoke-GetHelpScrub
        if ($g.Code -eq '00') { $res.Reboot = $true }
    }

    Write-Head 'Kiểm tra lại'
    $after = Get-OfficeState
    Show-LostAce $State.Ace $after.Ace
    $res.Ace = @($after.Ace)
    if ($after.Any) {
        Write-Bad 'Vẫn còn Office trên máy:'
        Show-OfficeState $after
        Write-Sub '→ Khởi động lại máy rồi chạy lại "Chỉ gỡ sạch Office"; vẫn còn thì đánh dấu "Quét sâu".'
        $res.Code = 3
        return [pscustomobject]$res
    }
    Write-Ok 'Không còn Office nào trên máy.'
    $res.Clean = $true

    $left = Get-OfficeLeftovers $after
    if ($left.Any) {
        Write-Head 'Dọn phần còn sót'
        $fail += Remove-OfficeLeftovers $left $Protect
    }
    Write-Head 'Khoá sản phẩm, giấy phép'
    $fail += Remove-OfficeLicenses $SameUser
    if ($XoaThietLap) {
        Write-Head 'Thiết lập Office của người dùng'
        if (-not $SameUser) { Write-Warn 'Bỏ qua: cửa sổ này chạy bằng tài khoản khác người đang dùng máy.' }
        elseif (-not $regBacked) { Write-Warn 'Bỏ qua: chưa sao lưu được thiết lập nên không xoá.' }
        elseif (Test-Path -LiteralPath 'HKCU:\Software\Microsoft\Office') {
            try { Remove-Item -LiteralPath 'HKCU:\Software\Microsoft\Office' -Recurse -Force -ErrorAction Stop; Write-Ok 'Đã xoá thiết lập Office (bản sao: Office.reg trong thư mục sao lưu).' }
            catch { $fail++; Write-Bad ('Không xoá hết thiết lập Office: {0}' -f $_.Exception.Message.Trim()) }
        }
    }
    if (Test-OfficeRebootPending) { $res.Reboot = $true }
    if ($res.Reboot) { Write-Warn 'Windows cần khởi động lại để xoá nốt file của Office.' }
    $res.Code = if ($fail) { 3 } else { 0 }
    return [pscustomobject]$res
}

function Invoke-GoSach {
    # Chế độ go-sach: chỉ gỡ sạch Office.
    param([string]$Mau = '', [switch]$QuetSau, [switch]$XoaThietLap, [switch]$DryRun)
    Write-Out 'GỠ SẠCH OFFICE' 'Cyan'
    Write-Out ('Máy {0}, {1:dd/MM/yyyy HH:mm}, tài khoản {2}.' -f $env:COMPUTERNAME, (Get-Date), (Get-CurrentUser))
    $state = Get-OfficeState
    Write-Head 'Office trên máy'
    Show-OfficeState $state
    $tplDir = Find-TemplateDir $Mau
    $odt = Get-RemovalOdt $tplDir
    if ($tplDir -and (Test-TemplateInsideOffice ([pscustomobject]@{ Dir = $tplDir }) $state)) {
        Write-Bad ('Bộ cài mẫu đang nằm trong thư mục cài Office ({0}): gỡ Office có thể xoá mất mẫu.' -f $tplDir)
        Write-Sub '→ Chép mẫu ra chỗ khác (vd D:\MauOffice) rồi chạy lại, chọn thư mục mẫu mới.'
        return 2
    }
    $left = Get-OfficeLeftovers $state
    $lic = @()
    try { $lic = @(Get-OfficeLicenses) } catch { }
    if (-not $state.Any -and -not $left.Any -and -not $lic.Count) { Write-Ok 'Không có Office, phần sót hay khoá Office nào để gỡ.'; return 0 }
    if (-not (Test-IsAdmin) -and -not $DryRun) { Write-Bad 'Cần quyền Admin để gỡ Office.'; return 2 }
    $same = Test-SameUser

    Write-Head 'Sẽ làm'
    Show-RemovePlan $state $left $odt $same $lic.Count -QuetSau:$QuetSau -XoaThietLap:$XoaThietLap
    Show-ActivationRisk $lic
    if ($DryRun) { Write-Info 'Chạy thử: máy chưa thay đổi gì.'; return 0 }
    Write-Warn 'Gỡ rồi không hoàn tác được: muốn dùng lại Office phải cài lại.'
    if (-not (Confirm-Strong)) { Write-Info 'Đã huỷ, máy chưa thay đổi gì.'; return 1223 }
    $protect = @($tplDir) | Where-Object { $_ }
    $r = Invoke-RemoveSteps $state $odt $protect $same -QuetSau:$QuetSau -XoaThietLap:$XoaThietLap
    if ($r.Code -eq 0) {
        Write-Head 'Xong'
        Write-Ok 'Đã gỡ sạch Office.'
        if ($r.Reboot) { Write-Sub '→ Khởi động lại máy trước khi cài Office mới.' }
        if ($r.Backup) { Write-Sub ('→ Cài Office xong, chạy "Trả lại mẫu Word, macro, chữ ký" nếu thấy thiếu mẫu, macro (bản sao lưu: {0}).' -f (Split-Path -Leaf $r.Backup)) }
    }
    return $r.Code
}
