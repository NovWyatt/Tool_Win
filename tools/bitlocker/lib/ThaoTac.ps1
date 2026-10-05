# BitLocker - các thao tác: lưu khoá khôi phục, tạm dừng, bật lại, mở khoá ổ bị khoá, giải mã ổ dữ liệu, hoàn tác.
# Mỗi thao tác: đọc hiện trạng, in kế hoạch ("Sẽ làm"), hỏi, rồi làm. -DryRun (chạy thử): chỉ in kế hoạch, không đổi gì.
# Khoá khôi phục chỉ đi vào file khoá (và lên màn hình khi người dùng chọn), không vào báo cáo, nhật ký hoàn tác.

$script:CodeBadKey = ConvertTo-UInt32Code 0x80310027      # khoá không đúng với ổ
$script:CodeAccessDenied = ConvertTo-UInt32Code 0x80041003

function Get-ResultCode {
    # 0 xong hết, 3 làm được một phần, 1 không làm được gì.
    param([int]$Ok, [int]$Fail)
    if ($Fail -eq 0) { return 0 }
    if ($Ok -gt 0) { return 3 }
    return 1
}

function Confirm-Plan {
    # Sau khi in kế hoạch: chạy thử thì dừng ở đây; chạy thật thì hỏi. Trả $true khi được làm.
    param([switch]$DryRun, [string]$Question = 'Làm ngay?')
    if ($DryRun) { Write-Info 'Chạy thử: máy chưa thay đổi gì.'; return $false }
    if (Read-YesNo $Question $true) { return $true }
    Write-Info 'Đã huỷ, máy chưa thay đổi gì.'
    return $false
}

function Format-DriveLetter {
    # 'e', 'E:', 'E:\', 'E:\.' → 'E:'; không phải chữ ổ thì ''.
    param([string]$Text)
    $t = ([string]$Text).Trim()
    if ($t -match '^([A-Za-z])(:(\\\.?)?)?$') { return ($Matches[1].ToUpperInvariant() + ':') }
    return ''
}

function Get-VolumeState {
    # Đọc các ổ BitLocker. Không đọc được thì đã báo lý do, Ok = $false, Code là mã thoát nên trả.
    # Chạy thử không có quyền Admin: in các bước chung ($Plan) thay cho kế hoạch theo từng ổ.
    param([switch]$DryRun, [string[]]$Plan = @())
    if (-not (Test-IsAdmin)) {
        if ($DryRun) {
            Write-Info 'Chạy thử không có quyền Admin nên không đọc được các ổ. Khi chạy thật, công cụ sẽ:'
            foreach ($p in $Plan) { Write-Plan $p }
            Write-Info 'Chạy thử: máy chưa thay đổi gì.'
            return [pscustomobject]@{ Ok = $false; Code = 0; Volumes = @() }
        }
        Write-ErrorHelp $script:CodeAccessDenied -Prefix 'Không đọc được BitLocker, lỗi'
        return [pscustomobject]@{ Ok = $false; Code = 2; Volumes = @() }
    }
    try { return [pscustomobject]@{ Ok = $true; Code = 0; Volumes = @(Get-AllVolumeInfo) } }
    catch {
        Write-ErrorHelp (Get-ErrorCode $_) -Prefix 'Không đọc được BitLocker, lỗi'
        return [pscustomobject]@{ Ok = $false; Code = 1; Volumes = @() }
    }
}

function Select-ByLetter {
    param($Infos, [string]$Letter)
    if (-not $Letter) { return @($Infos) }
    return @($Infos | Where-Object { $_.Letter -and $_.Letter.ToUpperInvariant() -eq $Letter })
}

function Test-KeyKnown {
    # Khoá khôi phục của ổ đã có ở đâu đó ngoài ổ: file khoá, tài khoản Microsoft, AD, Entra ID.
    param($Info, $Events, $SavedKeys)
    foreach ($rid in $Info.RecoveryIds) {
        $ev = Get-KeyEvidence -Id $rid -Events $Events -SavedKeys $SavedKeys
        if ($ev.Files.Count -or $ev.Msa -or $ev.Ad -or $ev.Entra) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------- luu-khoa
function Read-RecoveryPasswords {
    # Khoá khôi phục hiện có của một ổ, đọc từ ổ, chỉ giữ trong bộ nhớ.
    param($Info)
    $list = foreach ($id in $Info.RecoveryIds) {
        $r = Invoke-Bde $Info.Volume 'GetKeyProtectorNumericalPassword' @{ VolumeKeyProtectorID = [string]$id }
        [pscustomobject]@{ Id = (Format-KeyId $id); Key = [string]$r.NumericalPassword }
    }
    return @($list)
}

function Write-KeyFile {
    # Ghi file khoá (UTF-8 có BOM, CRLF), trả đường dẫn. $Items: Info, Id, Key. Mã khoá đứng trước khoá để
    # "Mở khoá" và "Kiểm tra" ghép lại được (Read-KeyFile).
    param([string]$Dir, $Items, [datetime]$When)
    if (-not (Test-Path -LiteralPath $Dir)) { [void](New-Item -ItemType Directory -Path $Dir -Force -ErrorAction Stop) }
    $path = Join-Path $Dir ('BitLocker_KhoaKhoiPhuc_{0}_{1:yyyyMMdd_HHmmss}.txt' -f $env:COMPUTERNAME, $When)
    $L = New-Object System.Collections.Generic.List[string]
    $L.Add('KHOÁ KHÔI PHỤC BITLOCKER')
    $L.Add(('Máy: {0}    Lưu lúc: {1:dd/MM/yyyy HH:mm}    Người lưu: {2}' -f $env:COMPUTERNAME, $When, (Get-CurrentUser)))
    $L.Add('')
    $L.Add('Ai có khoá này đọc được dữ liệu trên ổ, kể cả khi tháo ổ sang máy khác. Cất file ở nơi KHÁC máy này')
    $L.Add('(USB riêng, điện thoại, giấy in để chỗ an toàn); đừng gửi qua tin nhắn, email.')
    $L.Add('')
    foreach ($it in $Items) {
        $L.Add(('Ổ {0}' -f (Get-VolumeName $it.Info)))
        $L.Add(('  Mã khoá (Key ID):         {0}' -f $it.Id))
        $L.Add(('  Màn hình khôi phục hiện:  {0}' -f (Format-ShortId $it.Id)))
        $L.Add(('  Khoá khôi phục:           {0}' -f $it.Key))
        $L.Add('')
    }
    $L.Add('CÁCH DÙNG')
    $L.Add('- Màn hình "BitLocker recovery" khi khởi động: so "Recovery key ID" trên màn hình với Mã khoá ở trên; đúng thì gõ')
    $L.Add('  48 chữ số của khoá rồi Enter (phím số không chạy thì dùng F1-F9 cho 1-9, F10 cho 0).')
    $L.Add('- Ổ dữ liệu, USB bị khoá: bấm đúp ổ trong This PC > More options > Enter recovery key; hoặc chạy')
    $L.Add('  "Mở khoá ổ bị BitLocker khoá" của công cụ BitLocker (Trạm Tool), công cụ tự tìm file này.')
    $L.Add('- Bật lại BitLocker từ đầu hoặc thêm khoá mới thì khoá đổi: lưu lại bản mới.')
    [IO.File]::WriteAllText($path, (($L -join "`r`n") + "`r`n"), $script:Utf8Bom)
    return $path
}

function Copy-KeyFileToUsb {
    # Hỏi chép thêm một bản file khoá vào USB đang cắm (trừ ổ đang chứa file).
    param([string]$Path)
    $here = ([IO.Path]::GetPathRoot($Path)).TrimEnd('\').ToUpperInvariant()
    $usb = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 2' -ErrorAction SilentlyContinue | Where-Object { $_.FileSystem -and ([string]$_.DeviceID).ToUpperInvariant() -ne $here })
    if (-not $usb.Count) { Write-Info 'Không thấy USB nào đang cắm: nhớ tự chép file ra USB, điện thoại hoặc in ra giấy.'; return }
    Write-Line 'USB đang cắm:'
    for ($k = 0; $k -lt $usb.Count; $k++) {
        $u = $usb[$k]
        Write-Line ('  {0}. {1} {2} ({3})' -f ($k + 1), $u.DeviceID, $u.VolumeName, (Format-GB $u.Size))
    }
    $n = Read-Number 'Chép thêm một bản vào USB số mấy? (Enter để bỏ qua)' 1 $usb.Count $null
    if (-not $n) { return }
    $to = Join-Path ([string]$usb[$n - 1].DeviceID + '\') ([IO.Path]::GetFileName($Path))
    try { Copy-Item -LiteralPath $Path -Destination $to -ErrorAction Stop; Write-Ok "Đã chép vào $to" }
    catch { Write-Bad ('Không chép được vào {0}: {1}' -f $usb[$n - 1].DeviceID, $_.Exception.Message.Trim()) }
}

function Invoke-LuuKhoa {
    param([string]$NoiLuu, [switch]$DryRun)
    Write-Head 'Lưu khoá khôi phục BitLocker'
    $dir = if ($NoiLuu) { [IO.Path]::GetFullPath($NoiLuu) } else { Join-Path (Get-ResultDir) 'khoa-bitlocker' }
    $st = Get-VolumeState -DryRun:$DryRun -Plan @(
        'Đọc khoá khôi phục 48 số của các ổ đã mã hoá'
        'Ổ đã mã hoá mà chưa có khoá khôi phục: thêm khoá (hỏi trước, hoàn tác được)'
        "Ghi các khoá vào một file trong $dir; hỏi có chép thêm ra USB, in ra giấy không"
    )
    if (-not $st.Ok) { return $st.Code }
    $infos = @($st.Volumes)
    $have = New-Object System.Collections.ArrayList
    $add = New-Object System.Collections.ArrayList
    foreach ($i in @($infos | Where-Object { Test-IsEncrypted $_ })) {
        $n = Get-VolumeName $i
        if ($i.State -eq 'bi-khoa') { Write-Warn "$n đang bị khoá: chạy `"Mở khoá ổ bị BitLocker khoá`" trước rồi mới đọc được khoá." }
        elseif ($i.State -eq 'cho-kich-hoat') { Write-Info "$n chưa kích hoạt bảo vệ (khoá để trần): chưa có khoá khôi phục nào để lưu." }
        elseif ($i.State -eq 'dang-giai-ma') { Write-Info "$n đang giải mã: không cần khoá nữa." }
        elseif ($i.RecoveryIds.Count) { [void]$have.Add($i) }
        else { [void]$add.Add($i) }
    }
    if (-not ($have.Count + $add.Count)) {
        if (-not @($infos | Where-Object { Test-IsEncrypted $_ }).Count) { Write-Ok 'Không ổ nào mã hoá BitLocker: không có khoá nào cần lưu.' }
        return 0
    }

    Write-Head 'Sẽ làm'
    foreach ($i in $add) { Write-Plan ('Thêm khoá khôi phục 48 số cho ' + (Get-VolumeName $i)) }
    Write-Plan ('Ghi khoá khôi phục của {0} vào một file trong {1}' -f ((@($have) + @($add) | ForEach-Object { Get-DriveText $_ }) -join ', '), $dir)
    $destVol = Get-VolumeOfPath $dir $infos
    if ($destVol -and (Test-IsEncrypted $destVol)) {
        Write-Warn ('Thư mục lưu nằm trên ổ {0} đã mã hoá BitLocker: lúc Windows hỏi khoá thì không mở được file này. Lưu xong nhớ chép ra USB, điện thoại hoặc in ra giấy.' -f $destVol.Letter)
    } elseif (-not $NoiLuu) {
        Write-Info 'File nằm trong máy này: lưu xong nhớ chép ra USB, điện thoại hoặc in ra giấy (công cụ sẽ hỏi).'
    }
    if (-not (Confirm-Plan -DryRun:$DryRun -Question 'Lưu ngay?')) { return 0 }

    $j = New-Journal 'luu-khoa' 'Lưu khoá khôi phục BitLocker'
    $ok = 0; $fail = 0
    foreach ($i in $add) {
        $vol = $i.Volume
        $u = @{ kind = 'protectorAdded'; deviceId = $i.DeviceId; letter = $i.Letter; protectorId = $null }
        $added = Invoke-Change $j ('Thêm khoá khôi phục cho ' + (Get-DriveText $i)) {
            $u.protectorId = [string](Invoke-Bde $vol 'ProtectKeyWithNumericalPassword' @{ FriendlyName = $null; NumericalPassword = $null }).VolumeKeyProtectorID
        } -Undo $u
        if ($added) { $i.RecoveryIds = @($u.protectorId); [void]$have.Add($i) } else { $fail++ }
    }
    $items = New-Object System.Collections.ArrayList
    foreach ($i in $have) {
        try {
            foreach ($p in @(Read-RecoveryPasswords $i)) { [void]$items.Add([pscustomobject]@{ Info = $i; Id = $p.Id; Key = $p.Key }) }
            $ok++
        } catch {
            $fail++
            Write-ErrorHelp (Get-ErrorCode $_) -Prefix ('Không đọc được khoá của {0}, lỗi' -f (Get-DriveText $i))
        }
    }
    if (-not $items.Count) { Write-Bad 'Không đọc được khoá nào nên chưa ghi file.'; return 1 }
    try { $path = Write-KeyFile -Dir $dir -Items $items -When (Get-Date) }
    catch {
        Write-Bad ('Không ghi được file khoá vào {0}: {1}' -f $dir, $_.Exception.Message.Trim())
        Write-Info 'Chọn thư mục khác (vd USB) rồi chạy lại.'
        return 1
    }
    Write-Ok ('Đã lưu {0} khoá vào {1}' -f $items.Count, $path)
    foreach ($it in $items) { Write-Sub ('Mã khoá của {0} là {1}' -f (Get-DriveText $it.Info), $it.Id) }

    Copy-KeyFileToUsb $path
    if (Read-YesNo 'In file khoá ra giấy ngay (máy in mặc định)?' $false) {
        try { Start-Process -FilePath 'notepad.exe' -ArgumentList ('/p "{0}"' -f $path) -ErrorAction Stop; Write-Ok 'Đã gửi lệnh in.' }
        catch { Write-Bad ('Không in được: {0}' -f $_.Exception.Message.Trim()) }
    }
    if (Read-YesNo 'Hiện khoá lên màn hình để chép tay?' $false) {
        # Chỉ Write-Host: khoá không đi vào báo cáo.
        Write-Host ''
        foreach ($it in $items) {
            Write-Host ('  {0}, Mã khoá {1}:' -f (Get-DriveText $it.Info), (Format-ShortId $it.Id)) -ForegroundColor Cyan
            Write-Host ('  {0}' -f $it.Key) -ForegroundColor White
        }
        Write-Host ''
    }
    $items.Clear()
    if (Read-YesNo 'Mở thư mục chứa file khoá?' $true) {
        try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $path) } catch { }
    }
    Write-Info 'Bật lại BitLocker từ đầu, thêm khoá mới thì khoá đổi: chạy lại mục này để lưu bản mới.'
    return (Get-ResultCode $ok $fail)
}

# ---------------------------------------------------------------- tam-dung, bat-lai
function Format-SuspendCount {
    param([int]$Count)
    if ($Count -eq 0) { return 'đến khi bật lại bằng tay' }
    return ('trong {0} lần khởi động' -f $Count)
}

function Invoke-TamDung {
    param([string]$SoLan, [switch]$DryRun)
    Write-Head 'Tạm dừng BitLocker'
    Write-Info 'Dùng trước khi cập nhật BIOS/UEFI, đổi Secure Boot hay TPM trong BIOS, thay bo mạch, chuyển ổ sang máy khác: Windows không hỏi khoá khôi phục trong những lần khởi động đó.'
    $n = 1
    if ($SoLan -ne '') { $n = [int]$SoLan }
    elseif (-not $DryRun) { $n = [int](Read-Number 'Tạm dừng trong mấy lần khởi động? 1-15, 0 = đến khi bật lại bằng tay (Enter = 1)' 0 15 1) }
    $st = Get-VolumeState -DryRun:$DryRun -Plan @(('Tạm dừng BitLocker ổ Windows {0} (ghi nhật ký để hoàn tác)' -f (Format-SuspendCount $n)))
    if (-not $st.Ok) { return $st.Code }
    $os = @($st.Volumes | Where-Object { $_.Type -eq 0 })[0]
    if (-not $os) { Write-Bad 'Không thấy ổ Windows trong danh sách BitLocker.'; return 1 }
    $name = Get-VolumeName $os
    if ($os.State -eq 'tam-dung') {
        $left = if ($null -eq $os.SuspendCount) { '' } elseif ($os.SuspendCount -eq 0) { ' đến khi bật lại bằng tay' } else { " (tự bật lại sau $($os.SuspendCount) lần khởi động)" }
        Write-Ok "$name đang tạm dừng$left."
        Write-Info 'Muốn bật lại ngay: chạy "Bật lại BitLocker".'
        return 0
    }
    if ($os.State -eq 'khong-ro') { Write-Bad "$name`: không đọc được trạng thái BitLocker."; return 1 }
    if ($os.State -notin 'dang-bao-ve', 'dang-ma-hoa') {
        Write-Ok ('{0}: {1}, không cần tạm dừng.' -f $name, $script:StateText[$os.State])
        return 0
    }
    if (-not $os.RecoveryIds.Count) {
        Write-Warn 'Ổ Windows chưa có khoá khôi phục 48 số: lỡ vẫn bị hỏi khoá thì không mở được. Nên chạy "Lưu khoá khôi phục" trước (công cụ thêm khoá rồi lưu ra file).'
    } elseif (-not (Test-KeyKnown $os @(Get-BdeEvents) @(Find-SavedKeys))) {
        Write-Warn 'Chưa thấy nơi nào lưu khoá khôi phục của ổ Windows. Nên chạy "Lưu khoá khôi phục" trước: hết số lần khởi động đã chọn mà máy vẫn đổi thì Windows sẽ hỏi khoá.'
    }

    Write-Head 'Sẽ làm'
    Write-Plan ('Tạm dừng BitLocker {0} {1}' -f $name, (Format-SuspendCount $n))
    Write-Warn 'Trong lúc tạm dừng, khoá giải mã để trần trên ổ: ai cầm ổ cũng đọc được dữ liệu. Xong việc nên bật lại ngay.'
    if (-not (Confirm-Plan -DryRun:$DryRun -Question 'Tạm dừng ngay?')) { return 0 }

    $j = New-Journal 'tam-dung' ('Tạm dừng BitLocker ổ ' + $os.Letter)
    $vol = $os.Volume
    $count = [uint32]$n
    $done = Invoke-Change $j ('Tạm dừng BitLocker ổ {0} {1}' -f $os.Letter, (Format-SuspendCount $n)) {
        [void](Invoke-Bde $vol 'DisableKeyProtectors' @{ DisableCount = $count })
    } -Undo @{ kind = 'suspend'; deviceId = $os.DeviceId; letter = $os.Letter }
    if (-not $done) { return 1 }
    try {
        if ([int](Invoke-Bde $vol 'GetProtectionStatus').ProtectionStatus -ne 0) { Write-Warn 'Windows vẫn báo ổ đang được bảo vệ: kiểm tra lại bằng "Kiểm tra".' }
    } catch { }
    if ($n -eq 0) { Write-Info 'Không tự bật lại: xong việc nhớ chạy "Bật lại BitLocker".' }
    else { Write-Info ('Windows tự bật lại sau {0} lần khởi động. Xong sớm thì chạy "Bật lại BitLocker".' -f $n) }
    return 0
}

function Invoke-BatLai {
    param([switch]$DryRun)
    Write-Head 'Bật lại BitLocker'
    $st = Get-VolumeState -DryRun:$DryRun -Plan @('Bật lại bảo vệ cho các ổ đang tạm dừng BitLocker')
    if (-not $st.Ok) { return $st.Code }
    foreach ($i in @($st.Volumes | Where-Object { $_.State -eq 'cho-kich-hoat' })) {
        Write-Info ('{0} đã mã hoá nhưng chưa kích hoạt bảo vệ: Windows tự kích hoạt khi một Admin đăng nhập bằng tài khoản Microsoft (khoá được tải lên tài khoản đó).' -f (Get-VolumeName $i))
    }
    $targets = @($st.Volumes | Where-Object { $_.State -eq 'tam-dung' })
    if (-not $targets.Count) { Write-Ok 'Không ổ nào đang tạm dừng BitLocker.'; return 0 }
    Write-Head 'Sẽ làm'
    foreach ($i in $targets) { Write-Plan ('Bật lại BitLocker ' + (Get-VolumeName $i)) }
    if (-not (Confirm-Plan -DryRun:$DryRun -Question 'Bật lại ngay?')) { return 0 }
    $j = New-Journal 'bat-lai' 'Bật lại BitLocker'   # bật lại không ghi hoàn tác (muốn tạm dừng lại thì chạy Tạm dừng)
    $ok = 0; $fail = 0
    foreach ($i in $targets) {
        $vol = $i.Volume
        if (Invoke-Change $j ('Bật lại BitLocker ' + (Get-DriveText $i)) { [void](Invoke-Bde $vol 'EnableKeyProtectors') }) { $ok++ } else { $fail++ }
    }
    return (Get-ResultCode $ok $fail)
}

# ---------------------------------------------------------------- mo-khoa
function Get-RecoveryPasswordProblem {
    # Vì sao khoá gõ vào sai dạng; không nhắc lại chữ số nào.
    param([string]$Text)
    $digits = ($Text -replace '[\s\-]', '')
    if ($digits -notmatch '^\d+$') { return 'Khoá chỉ gồm chữ số (có thể có dấu gạch giữa các nhóm).' }
    if ($digits.Length -ne 48) { return ('Khoá có 48 chữ số, bạn gõ {0}.' -f $digits.Length) }
    for ($k = 0; $k -lt 8; $k++) {
        $g = [int]$digits.Substring($k * 6, 6)
        if ($g % 11 -ne 0 -or $g -ge 720896) { return ('Nhóm thứ {0} gõ nhầm: kiểm tra lại 6 số của nhóm đó.' -f ($k + 1)) }
    }
    return 'Khoá sai dạng.'
}

function Unlock-Volume {
    # Thử khoá tìm được trong file, rồi khoá người dùng gõ (tối đa 3 lần). Trả 'ok', 'nokey' hoặc 'fail'.
    param($Info, $Candidates)
    $vol = $Info.Volume
    $drive = Get-DriveText $Info
    $tried = @{}
    foreach ($c in @($Candidates)) {
        if ($tried.ContainsKey($c.Key)) { continue }
        $tried[$c.Key] = $true
        try {
            [void](Invoke-Bde $vol 'UnlockWithNumericalPassword' @{ NumericalPassword = $c.Key })
            Write-Ok ('Đã mở khoá {0} bằng khoá trong file {1}' -f $drive, $c.File)
            return 'ok'
        } catch {
            $code = Get-ErrorCode $_
            if ($code -ne $script:CodeBadKey) { Write-ErrorHelp $code -Prefix "Không mở được $drive, lỗi"; return 'fail' }
        }
    }
    if ($tried.Count) { Write-Warn ('Khoá trong các file tìm thấy không mở được {0}.' -f $drive) }
    if ([Console]::IsInputRedirected) { Write-Warn "Không có bàn phím để gõ khoá cho $drive."; return 'nokey' }
    Write-Info 'Khoá khôi phục gồm 48 chữ số. Tìm ở https://aka.ms/myrecoverykey (tài khoản Microsoft), https://aka.ms/aadrecoverykey (tài khoản công ty), giấy in hoặc USB đã lưu; chọn khoá có Mã khoá khớp với ổ.'
    for ($k = 1; $k -le 3; $k++) {
        $t = ([string](Read-Host ('  Gõ khoá khôi phục của {0} (Enter để bỏ qua)' -f $drive))).Trim()
        if (-not $t) { return 'nokey' }
        $key = Test-RecoveryPassword $t
        if (-not $key) { Write-Host ('  ' + (Get-RecoveryPasswordProblem $t)) -ForegroundColor Yellow; continue }
        try {
            [void](Invoke-Bde $vol 'UnlockWithNumericalPassword' @{ NumericalPassword = $key })
            Write-Ok "Đã mở khoá $drive"
            return 'ok'
        } catch {
            $code = Get-ErrorCode $_
            if ($code -eq $script:CodeBadKey) { Write-Host '  Khoá không đúng với ổ này: đối chiếu Mã khoá rồi gõ lại.' -ForegroundColor Yellow; continue }
            Write-ErrorHelp $code -Prefix "Không mở được $drive, lỗi"
            return 'fail'
        }
    }
    Write-Bad "Gõ sai 3 lần, chưa mở được $drive."
    return 'fail'
}

function Enable-AutoUnlockWithUndo {
    # Cho ổ dữ liệu tự mở khoá khi vào Windows: thêm khoá ngoài (external key) rồi lưu khoá đó trên ổ Windows.
    param($Journal, $Info)
    $vol = $Info.Volume
    $u = @{ kind = 'autoUnlock'; deviceId = $Info.DeviceId; letter = $Info.Letter; protectorId = $null }
    return (Invoke-Change $Journal ('Cho {0} tự mở khoá khi vào Windows' -f (Get-DriveText $Info)) {
            $id = [string](Invoke-Bde $vol 'ProtectKeyWithExternalKey').VolumeKeyProtectorID
            try { [void](Invoke-Bde $vol 'EnableAutoUnlock' @{ VolumeKeyProtectorID = $id }) }
            catch {
                $err = $_
                try { [void](Invoke-Bde $vol 'DeleteKeyProtector' @{ VolumeKeyProtectorID = $id }) } catch { }
                throw $err.Exception
            }
            $u.protectorId = $id
        } -Undo $u)
}

function Invoke-MoKhoa {
    param([string]$ODia, [string]$ThuMucKhoa, [switch]$DryRun)
    Write-Head 'Mở khoá ổ bị BitLocker khoá'
    $st = Get-VolumeState -DryRun:$DryRun -Plan @(
        'Tìm file khoá khôi phục có Mã khoá khớp với ổ bị khoá: thư mục khoá của công cụ, USB, Desktop, Documents, Downloads, OneDrive, bản sao lưu "Chuyển dữ liệu khi cài lại Windows"'
        'Không thấy file thì hỏi bạn gõ khoá 48 số trong cửa sổ này'
        'Mở khoá ổ, rồi hỏi có cho ổ tự mở khoá mỗi lần vào Windows không'
    )
    if (-not $st.Ok) { return $st.Code }
    $infos = @($st.Volumes)
    $scope = @(Select-ByLetter $infos $ODia)
    if ($ODia -and -not $scope.Count) { Write-Bad "Không thấy ổ $ODia trong danh sách ổ BitLocker."; return 1 }
    $os = @($infos | Where-Object { $_.Type -eq 0 })[0]
    $osReady = [bool]($os -and $os.State -in 'dang-bao-ve', 'tam-dung')
    $locked = @($scope | Where-Object { $_.State -eq 'bi-khoa' })
    $noAuto = @($scope | Where-Object { $_.Type -ne 0 -and $_.State -eq 'dang-bao-ve' -and $_.AutoUnlock -eq $false })
    if (-not $locked.Count -and -not $noAuto.Count) {
        if ($ODia) { Write-Ok "Ổ $ODia không bị khoá." } else { Write-Ok 'Không ổ nào đang bị BitLocker khoá.' }
        return 0
    }

    $saved = @()
    if ($locked.Count) { $saved = @(Find-SavedKeys -Extra $ThuMucKhoa) }
    $plan = New-Object System.Collections.ArrayList
    Write-Head 'Sẽ làm'
    foreach ($i in $locked) {
        $ids = @($i.RecoveryIds | ForEach-Object { Format-KeyId $_ })
        $match = @($saved | Where-Object { $_.Id -and $ids -contains $_.Id })
        $loose = @($saved | Where-Object { -not $_.Id })
        $how = if ($match.Count) { 'khoá trong file ' + $match[0].File } elseif ($loose.Count) { 'khoá không ghi Mã khoá trong file tìm thấy, không được thì hỏi bạn gõ' } else { 'khoá khôi phục bạn gõ (48 số)' }
        Write-Plan ('Mở khoá {0} bằng {1}' -f (Get-VolumeName $i), $how)
        if ($ids.Count) { Write-Sub ('Mã khoá của ổ: {0} (màn hình, giấy in ghi {1})' -f ($ids -join ', '), (@($ids | ForEach-Object { Format-ShortId $_ }) -join ', ')) }
        elseif (-not @($i.Protectors | Where-Object { $_.Type -eq 3 }).Count) { Write-Sub 'Ổ không có khoá khôi phục 48 số: chỉ mở được bằng mật khẩu, thẻ thông minh của ổ (bấm đúp ổ trong This PC).' }
        [void]$plan.Add([pscustomobject]@{ Info = $i; Candidates = @($match) + @($loose) })
    }
    foreach ($i in $noAuto) { Write-Plan ('Hỏi có cho {0} tự mở khoá mỗi lần vào Windows không' -f (Get-VolumeName $i)) }
    if (-not (Confirm-Plan -DryRun:$DryRun -Question 'Làm ngay?')) { return 0 }

    $j = New-Journal 'mo-khoa' 'Mở khoá ổ BitLocker'
    $ok = 0; $fail = 0; $noKey = 0
    $auto = New-Object System.Collections.ArrayList
    foreach ($p in $plan) {
        $r = Unlock-Volume -Info $p.Info -Candidates $p.Candidates
        if ($r -eq 'ok') { $ok++; if ($p.Info.Type -ne 0) { [void]$auto.Add($p.Info) } }
        elseif ($r -eq 'nokey') { $noKey++ }
        else { $fail++ }
    }
    $saved = @()
    foreach ($i in $noAuto) { [void]$auto.Add($i) }
    foreach ($i in $auto) {
        $drive = Get-DriveText $i
        try { if ([bool](Invoke-Bde $i.Volume 'IsAutoUnlockEnabled').IsAutoUnlockEnabled) { continue } } catch { }
        if ($i.Type -eq 1 -and -not $osReady) {
            Write-Info ('Muốn {0} tự mở khoá thì ổ Windows cũng phải bật BitLocker. Không cần mã hoá {0} nữa thì chạy "Giải mã ổ dữ liệu, USB" (giữ nguyên dữ liệu).' -f $drive)
            continue
        }
        if (-not (Read-YesNo ('Cho {0} tự mở khoá mỗi lần vào Windows trên máy này?' -f $drive) $true)) { continue }
        if (Enable-AutoUnlockWithUndo $j $i) { $ok++ } else { $fail++ }
    }
    if ($ok -eq 0 -and $fail -eq 0 -and $noKey -gt 0) { return 2 }
    return (Get-ResultCode $ok ($fail + $noKey))
}

# ---------------------------------------------------------------- giai-ma
function Open-EncryptionSettings {
    # Trang tắt mã hoá ổ Windows: Windows Home là "Device encryption" trong Settings, bản khác là BitLocker trong Control Panel.
    if ((Get-WindowsInfo).IsHome) { Start-Process 'ms-settings:deviceencryption' }
    else { Start-Process -FilePath 'control.exe' -ArgumentList '/name Microsoft.BitLockerDriveEncryption' }
}

function Invoke-GiaiMa {
    param([string]$ODia, [switch]$DryRun)
    Write-Head 'Giải mã ổ (tắt BitLocker)'
    Write-Info 'Giải mã giữ nguyên dữ liệu và ổ không cần khoá nữa. Ổ lớn mất vài giờ; vẫn dùng máy được, tắt máy giữa chừng thì lần sau Windows làm tiếp.'
    $st = Get-VolumeState -DryRun:$DryRun -Plan @('Giải mã ổ dữ liệu, USB bạn chọn (phải gõ DONG Y để đồng ý); ổ Windows thì mở trang cài đặt mã hoá của Windows')
    if (-not $st.Ok) { return $st.Code }
    $scope = @(Select-ByLetter @($st.Volumes) $ODia)
    if ($ODia -and -not $scope.Count) { Write-Bad "Không thấy ổ $ODia trong danh sách ổ BitLocker."; return 1 }
    $enc = @($scope | Where-Object { Test-IsEncrypted $_ })
    if (-not $enc.Count) {
        if ($ODia) { Write-Ok "Ổ $ODia không mã hoá BitLocker." } else { Write-Ok 'Không ổ nào mã hoá BitLocker.' }
        return 0
    }
    $osVol = @($enc | Where-Object { $_.Type -eq 0 })[0]
    if ($osVol) {
        Write-Info ('{0}: công cụ không tự giải mã ổ Windows. Tắt trong Settings > Privacy & security > Device encryption (Windows Home) hoặc Control Panel > BitLocker Drive Encryption; trước khi thay phần cứng, cập nhật BIOS chỉ cần "Tạm dừng BitLocker".' -f (Get-VolumeName $osVol))
        if (-not $DryRun -and $enc.Count -eq 1 -and (Read-YesNo 'Mở trang cài đặt đó?' $true)) {
            try { Open-EncryptionSettings } catch { Write-Bad ('Không mở được: {0}' -f $_.Exception.Message.Trim()) }
        }
    }
    foreach ($i in @($enc | Where-Object { $_.Type -ne 0 -and $_.State -eq 'bi-khoa' })) { Write-Warn ('{0} đang bị khoá: chạy "Mở khoá ổ bị BitLocker khoá" trước.' -f (Get-VolumeName $i)) }
    foreach ($i in @($enc | Where-Object { $_.Type -ne 0 -and $_.State -eq 'dang-giai-ma' })) { Write-Info ('{0} đang giải mã ({1}%).' -f (Get-VolumeName $i), $i.Percent) }
    $cands = @($enc | Where-Object { $_.Type -ne 0 -and $_.State -notin 'bi-khoa', 'dang-giai-ma', 'khong-ro' })
    if (-not $cands.Count) { return 0 }

    $pick = $cands
    if ($cands.Count -gt 1 -and -not $DryRun) {
        for ($k = 0; $k -lt $cands.Count; $k++) { Write-Line ('  {0}. {1}' -f ($k + 1), (Get-VolumeName $cands[$k])) }
        $n = Read-Number 'Giải mã ổ số mấy? (Enter để huỷ)' 1 $cands.Count $null
        if (-not $n) { Write-Info 'Đã huỷ, máy chưa thay đổi gì.'; return 0 }
        $pick = @($cands[$n - 1])
    }
    Write-Head 'Sẽ làm'
    foreach ($i in $pick) { Write-Plan ('Giải mã ' + (Get-VolumeName $i)) }
    if ($DryRun -and $cands.Count -gt 1) { Write-Info 'Chạy thật sẽ hỏi chọn một ổ.' }
    Write-Warn 'Sau khi giải mã, ai cầm ổ (hoặc USB) cũng đọc được dữ liệu. Không hoàn tác được: muốn mã hoá lại thì bật BitLocker từ đầu.'
    if ($DryRun) { Write-Info 'Chạy thử: máy chưa thay đổi gì.'; return 0 }
    if (-not (Confirm-Strong)) { Write-Info 'Đã huỷ, máy chưa thay đổi gì.'; return 0 }

    $j = New-Journal 'giai-ma' 'Giải mã ổ BitLocker'
    $ok = 0; $fail = 0
    foreach ($i in $pick) {
        $vol = $i.Volume
        if (Invoke-Change $j ('Bắt đầu giải mã ' + (Get-DriveText $i)) { [void](Invoke-Bde $vol 'Decrypt') }) {
            $ok++
            Start-Sleep -Seconds 2
            try { Write-Info ('Đang giải mã: {0}%. Đóng cửa sổ được, Windows giải mã tiếp trong nền.' -f [int](Invoke-Bde $vol 'GetConversionStatus').EncryptionPercentage) } catch { }
        } else { $fail++ }
    }
    return (Get-ResultCode $ok $fail)
}

# ---------------------------------------------------------------- hoan-tac
function Invoke-HoanTac {
    param([string]$NhatKy, [switch]$DryRun)
    Write-Head 'Hoàn tác lần thay đổi trước'
    $entries = @(Get-JournalEntries)
    if (-not $entries) { Write-Info 'Chưa có lần thay đổi nào để hoàn tác.'; return 0 }
    $pick = $null
    if ($NhatKy) {
        $pick = @($entries | Where-Object { $_.File.Name -eq $NhatKy -or $_.File.BaseName -eq $NhatKy })[0]
        if (-not $pick) { Write-Bad "Không thấy nhật ký '$NhatKy'."; return 1 }
    } else {
        $show = @($entries | Select-Object -First 15)
        $default = $null
        for ($i = 0; $i -lt $show.Count; $i++) {
            $d = $show[$i].Data
            $when = [string]$d.started
            try { $when = ([datetime]$d.started).ToString('dd/MM/yyyy HH:mm') } catch { }
            $state = if ($d.undone) { 'đã hoàn tác' } else { '{0} thay đổi' -f @($d.changes).Count }
            if (-not $d.undone -and $null -eq $default) { $default = $i + 1 }
            Write-Line ('  {0}. {1}  {2} ({3})' -f ($i + 1), $when, $d.title, $state)
        }
        if ($null -eq $default) { Write-Info 'Các lần thay đổi trong danh sách đều đã hoàn tác.'; return 0 }
        $n = if ($DryRun) { $default } else { Read-Number ('Hoàn tác lần số mấy? (Enter = {0})' -f $default) 1 $show.Count $default }
        if (-not $n) { return 0 }
        $pick = $show[$n - 1]
    }
    $d = $pick.Data
    if ($d.computer -and $d.computer -ne $env:COMPUTERNAME) { Write-Bad "Nhật ký này của máy $($d.computer), không phải máy này."; return 1 }
    if ($d.undone) {
        Write-Warn 'Lần thay đổi này đã được hoàn tác trước đó.'
        if ($DryRun -or -not (Read-YesNo 'Vẫn chạy hoàn tác lại?' $false)) { return 0 }
    }
    $changes = @($d.changes)
    if (-not $changes) { Write-Info 'Lần thay đổi này không có gì để hoàn tác.'; return 0 }

    Write-Head 'Sẽ làm'
    for ($i = $changes.Count - 1; $i -ge 0; $i--) { Write-Plan ('Hoàn tác: ' + $changes[$i].text) }
    if (@($changes | Where-Object { $_.kind -eq 'protectorAdded' })) { Write-Info 'Xoá khoá khôi phục đã thêm sẽ hỏi lại riêng: file khoá đã lưu cho Mã khoá đó sẽ không mở được ổ nữa.' }
    if (-not (Test-IsAdmin)) {
        if ($DryRun) { Write-Info 'Chạy thử: máy chưa thay đổi gì.'; return 0 }
        Write-ErrorHelp $script:CodeAccessDenied -Prefix 'Không đọc được BitLocker, lỗi'
        return 2
    }
    if (-not (Confirm-Plan -DryRun:$DryRun -Question 'Hoàn tác ngay?')) { return 0 }

    $r = Invoke-UndoJournal $pick
    Write-Line ('Hoàn tác xong: {0} việc, {1} lỗi, {2} bỏ qua.' -f $r.Ok, $r.Failed, $r.Skipped)
    return (Get-ResultCode $r.Ok $r.Failed)
}
