# BitLocker - đọc trạng thái: các ổ (Win32_EncryptableVolume, cần quyền Admin), TPM, Secure Boot, tài khoản,
# nhật ký sự kiện, file khoá đã lưu. Chỉ đọc, không đổi gì trên máy.
# Khoá khôi phục đọc từ ổ hoặc từ file chỉ giữ trong bộ nhớ để đối chiếu, không in ra, không ghi báo cáo.

$script:BdeNamespace = 'root/cimv2/Security/MicrosoftVolumeEncryption'

# Bảng chữ hiển thị, khoá là chuỗi (khoá hashtable phân biệt kiểu: 1 kiểu int khác 1 kiểu uint32 của WMI).
$script:VolumeTypeText = @{ '0' = 'ổ Windows'; '1' = 'ổ dữ liệu'; '2' = 'ổ rời (USB, thẻ nhớ)' }
$script:ProtectorText = @{
    '0' = 'không rõ'; '1' = 'TPM'; '2' = 'khoá trên USB (startup key)'; '3' = 'khoá khôi phục 48 số'; '4' = 'TPM + PIN'
    '5' = 'TPM + khoá USB'; '6' = 'TPM + PIN + khoá USB'; '7' = 'chứng chỉ'; '8' = 'mật khẩu'; '9' = 'TPM + chứng chỉ'; '10' = 'tài khoản Windows'
}
$script:MethodText = @{
    '0' = 'không'; '1' = 'AES 128 (diffuser)'; '2' = 'AES 256 (diffuser)'; '3' = 'AES 128'; '4' = 'AES 256'
    '5' = 'mã hoá phần cứng của ổ'; '6' = 'XTS-AES 128'; '7' = 'XTS-AES 256'
}
$script:StateText = [ordered]@{
    'bi-khoa' = 'đang bị khoá'; 'dang-bao-ve' = 'đang bảo vệ'; 'tam-dung' = 'TẠM DỪNG bảo vệ'
    'cho-kich-hoat' = 'đã mã hoá, chưa kích hoạt bảo vệ'; 'dang-ma-hoa' = 'đang mã hoá'; 'dang-giai-ma' = 'đang giải mã'
    'tat' = 'không mã hoá'; 'khong-ro' = 'không đọc được'
}
# Giá trị Windows ghi trong win32_encryptablevolume.mof (GetSecureBootBindingState): NotPossible, DisabledByPolicy, Possible, Bound.
$script:SecureBootBindingText = @{ '0' = 'không gắn được'; '1' = 'chính sách tắt'; '2' = 'gắn được, chưa gắn'; '3' = 'đã gắn' }
$script:TpmTypes = @(1, 4, 5, 6)
$script:KeyPattern = '\d{6}(?:-\d{6}){7}'
$script:GuidPattern = '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'

# ---------------------------------------------------------------- gọi BitLocker qua WMI
function Invoke-Bde {
    # Gọi phương thức của Win32_EncryptableVolume; ReturnValue khác 0 thì ném lỗi mang mã HRESULT.
    param($Volume, [string]$Method, [hashtable]$Arguments = $null)
    $p = @{ InputObject = $Volume; MethodName = $Method; ErrorAction = 'Stop' }
    if ($Arguments) { $p.Arguments = $Arguments }
    $r = Invoke-CimMethod @p
    $rv = [int64]$r.ReturnValue
    if ($rv -ne 0) { throw (New-BdeError (ConvertTo-UInt32Code $rv)) }
    return $r
}

function Get-BdeVolumes {
    # Các ổ BitLocker quản lý được. Quyền thường: ném lỗi 0x80041003 (không có quyền).
    return @(Get-CimInstance -Namespace $script:BdeNamespace -ClassName Win32_EncryptableVolume -ErrorAction Stop)
}

function Get-BdeLockStatus {
    # 1 = đang khoá, 0 = mở, -1 = không đọc được.
    param($Volume)
    try { return [int](Invoke-Bde $Volume 'GetLockStatus').LockStatus } catch { return -1 }
}

function Get-StorageVolumeMap {
    # Nhãn, dung lượng theo DeviceID (\\?\Volume{...}\). Ổ đang khoá vẫn có dung lượng ở đây.
    $map = @{}
    try {
        foreach ($s in @(Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_Volume -ErrorAction Stop)) {
            if ($s.UniqueId) { $map[[string]$s.UniqueId] = $s }
        }
    } catch { }
    return $map
}

function Get-VolumeInfo {
    # Trạng thái một ổ, đủ để báo cáo và quyết định. Bước nào lỗi thì ghi vào Errors, không dừng.
    param($Volume, [hashtable]$StorageMap = @{})
    $v = $Volume
    $i = [ordered]@{
        Volume = $v; Letter = [string]$v.DriveLetter; DeviceId = [string]$v.DeviceID; Type = 1; Label = ''; Size = $null
        Locked = $false; Conversion = -1; Percent = $null; Protection = -1; Method = -1; SuspendCount = $null
        Protectors = @(); RecoveryIds = @(); AutoUnlock = $null; SecureBootBinding = $null; State = 'khong-ro'
        Errors = New-Object System.Collections.Generic.List[string]
    }
    if ($null -ne $v.VolumeType) { $i.Type = [int]$v.VolumeType }
    elseif ($i.Letter -and $i.Letter -eq $env:SystemDrive) { $i.Type = 0 }
    $s = $StorageMap[$i.DeviceId]
    if ($s) { $i.Label = [string]$s.FileSystemLabel; $i.Size = $s.Size }

    $step = {
        param([string]$Name, [scriptblock]$Do)
        try { & $Do } catch { $i.Errors.Add(('{0}: {1}' -f $Name, (Format-ErrorCode (Get-ErrorCode $_)))) }
    }
    & $step 'GetLockStatus' { $i.Locked = ([int](Invoke-Bde $v 'GetLockStatus').LockStatus -eq 1) }
    & $step 'GetProtectionStatus' { $i.Protection = [int](Invoke-Bde $v 'GetProtectionStatus').ProtectionStatus }
    & $step 'GetEncryptionMethod' { $i.Method = [int](Invoke-Bde $v 'GetEncryptionMethod').EncryptionMethod }
    if (-not $i.Locked) {
        & $step 'GetConversionStatus' {
            $r = Invoke-Bde $v 'GetConversionStatus'
            $i.Conversion = [int]$r.ConversionStatus
            $i.Percent = [int]$r.EncryptionPercentage
        }
    }
    & $step 'GetKeyProtectors' {
        $ids = @((Invoke-Bde $v 'GetKeyProtectors' @{ KeyProtectorType = [uint32]0 }).VolumeKeyProtectorID | Where-Object { $_ })
        $list = foreach ($id in $ids) {
            $p = [pscustomobject]@{ Id = [string]$id; Type = 0; Pcr = $null }
            & $step 'GetKeyProtectorType' { $p.Type = [int](Invoke-Bde $v 'GetKeyProtectorType' @{ VolumeKeyProtectorID = [string]$id }).KeyProtectorType }
            if ($script:TpmTypes -contains $p.Type) {
                & $step 'GetKeyProtectorPlatformValidationProfile' {
                    $p.Pcr = @((Invoke-Bde $v 'GetKeyProtectorPlatformValidationProfile' @{ VolumeKeyProtectorID = [string]$id }).PlatformValidationProfile | ForEach-Object { [int]$_ })
                }
            }
            $p
        }
        $i.Protectors = @($list)
        $i.RecoveryIds = @($i.Protectors | Where-Object { $_.Type -eq 3 } | ForEach-Object { $_.Id })
    }
    if ($i.Type -ne 0) {
        # Chỉ ổ dữ liệu mới tự mở khoá được; lỗi ở đây nghĩa là không áp dụng, không ghi lỗi.
        try { $i.AutoUnlock = [bool](Invoke-Bde $v 'IsAutoUnlockEnabled').IsAutoUnlockEnabled } catch { }
    } else {
        try { $i.SecureBootBinding = [int](Invoke-Bde $v 'GetSecureBootBindingState').BindingState } catch { }
    }

    if ($i.Locked) { $i.State = 'bi-khoa' }
    elseif ($i.Conversion -eq 0) { $i.State = 'tat' }
    elseif ($i.Conversion -in 2, 4) { $i.State = 'dang-ma-hoa' }
    elseif ($i.Conversion -in 3, 5) { $i.State = 'dang-giai-ma' }
    elseif ($i.Conversion -eq 1) {
        if ($i.Protection -eq 1) { $i.State = 'dang-bao-ve' }
        elseif (-not $i.Protectors.Count) { $i.State = 'cho-kich-hoat' }   # khoá để trần, chưa có khoá bảo vệ nào
        else { $i.State = 'tam-dung' }
    }
    if ($i.Type -eq 0 -and $i.State -eq 'tam-dung') {
        try { $i.SuspendCount = [int](Invoke-Bde $v 'GetSuspendCount').SuspendCount } catch { }
    }
    return [pscustomobject]$i
}

function Get-AllVolumeInfo {
    # Mọi ổ, ổ Windows trước rồi theo chữ ổ. Ném lỗi khi không đọc được BitLocker (thiếu quyền Admin).
    $map = Get-StorageVolumeMap
    $list = foreach ($v in @(Get-BdeVolumes)) { Get-VolumeInfo -Volume $v -StorageMap $map }
    return @($list | Sort-Object @{ Expression = { $_.Type -ne 0 } }, @{ Expression = { if ($_.Letter) { $_.Letter } else { 'ZZ' + $_.DeviceId } } })
}

function Get-VolumeName {
    # "C: (ổ Windows, Data, 237 GB)"
    param($Info)
    $name = if ($Info.Letter) { $Info.Letter } else { 'Ổ không có chữ ổ' }
    $bits = @($script:VolumeTypeText[[string]$Info.Type])
    if ($Info.Label) { $bits += $Info.Label }
    if ($Info.Size) { $bits += (Format-GB $Info.Size) }
    return ('{0} ({1})' -f $name, ($bits -join ', '))
}

function Get-DriveText {
    # "ổ C:" để đặt giữa câu.
    param($Info)
    if ($Info.Letter) { return ('ổ ' + $Info.Letter) }
    return 'ổ không có chữ ổ'
}

function Format-KeyId {
    # Mã khoá (Key ID) dạng chuẩn để so: {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}, chữ hoa.
    param([string]$Id)
    return ('{' + $Id.Trim().Trim('{', '}').ToUpperInvariant() + '}')
}

function Format-ShortId {
    # 8 ký tự đầu của Mã khoá: màn hình khôi phục của Windows hiện đúng phần này để đối chiếu.
    param([string]$Id)
    return ($Id.Trim().Trim('{', '}').Substring(0, 8)).ToUpperInvariant()
}

function Get-KeyEvidence {
    # Nơi đã lưu khoá có Mã khoá $Id: sự kiện sao lưu lên tài khoản Microsoft, AD, Entra ID và file khoá tìm được.
    param([string]$Id, $Events, $SavedKeys)
    $key = Format-KeyId $Id
    $ev = @($Events | Where-Object { $_.Guids -contains $key })
    return [pscustomobject]@{
        Msa = @($ev | Where-Object { $script:EventBackupMsa -contains $_.Id } | Select-Object -First 1)[0]
        Ad = @($ev | Where-Object { $script:EventBackupAd -contains $_.Id } | Select-Object -First 1)[0]
        Entra = @($ev | Where-Object { $script:EventBackupEntra -contains $_.Id } | Select-Object -First 1)[0]
        Files = @($SavedKeys | Where-Object { $_.Id -eq $key } | ForEach-Object { $_.File } | Select-Object -Unique)
    }
}

function Format-Pcr {
    param($Pcr)
    if ($null -eq $Pcr) { return '' }
    return (@($Pcr) -join ', ')
}

function Test-IsEncrypted {
    # Ổ có dữ liệu mã hoá (kể cả đang mã hoá, giải mã dở, chờ kích hoạt, đang khoá).
    param($Info)
    return ($Info.State -notin 'tat', 'khong-ro')
}

function Get-VolumeOfPath {
    # Thông tin BitLocker của ổ chứa một đường dẫn (theo chữ ổ), $null khi không phải ổ BitLocker biết được.
    param([string]$Path, $Infos)
    try { $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path)) } catch { return $null }
    if ($root -notmatch '^([A-Za-z]:)\\?$') { return $null }
    $letter = $Matches[1].ToUpperInvariant()
    return (@($Infos) | Where-Object { $_.Letter -and $_.Letter.ToUpperInvariant() -eq $letter } | Select-Object -First 1)
}

# ---------------------------------------------------------------- máy, TPM, Secure Boot, tài khoản
function Get-WindowsInfo {
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $edition = [string](Get-RegValue $k 'EditionID')
    $name = [string](Get-RegValue $k 'ProductName')
    $build = [string](Get-RegValue $k 'CurrentBuild')
    # ProductName vẫn ghi "Windows 10" trên Windows 11; build từ 22000 là Windows 11.
    if ($build -and [int]$build -ge 22000) { $name = $name -replace 'Windows 10', 'Windows 11' }
    return [pscustomobject]@{
        Name = $name; Edition = $edition; IsHome = ($edition -match '^Core'); Version = [string](Get-RegValue $k 'DisplayVersion')
        Build = ('{0}.{1}' -f $build, (Get-RegValue $k 'UBR'))
    }
}

function Get-TpmInfo {
    # Có quyền Admin: đọc Win32_Tpm (phiên bản, đã sẵn sàng). Không: chỉ biết có thiết bị TPM qua Device Manager.
    $t = [ordered]@{ Present = $false; Version = ''; Ready = $null; Source = '' }
    if (Test-IsAdmin) {
        try {
            $w = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop
            if ($w) {
                $t.Present = $true; $t.Source = 'Win32_Tpm'
                $t.Version = ([string]$w.SpecVersion).Split(',')[0].Trim()
                $t.Ready = ([bool]$w.IsEnabled_InitialValue -and [bool]$w.IsActivated_InitialValue)
                return [pscustomobject]$t
            }
        } catch { }
    }
    try {
        $d = @(Get-PnpDevice -Class SecurityDevices -PresentOnly -ErrorAction Stop | Where-Object { $_.FriendlyName -match 'Trusted Platform Module' })
        if ($d.Count) {
            $t.Present = $true; $t.Source = 'PnP'
            if ($d[0].FriendlyName -match '(\d\.\d)') { $t.Version = $Matches[1] }
            $t.Ready = ($d[0].Status -eq 'OK')
        }
    } catch { }
    return [pscustomobject]$t
}

function Get-SecureBootState {
    # 1 bật, 0 tắt, $null: không có khoá (máy BIOS cũ hoặc không đọc được).
    $v = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' 'UEFISecureBootEnabled'
    if ($null -eq $v) { return $null }
    return [int]$v
}

function Get-JoinState {
    # Máy có vào Entra ID (Azure AD) hoặc domain không: khoá khôi phục khi đó thường do công ty giữ.
    $j = [ordered]@{ Entra = $false; Domain = $false; Known = $false }
    try {
        $r = Invoke-Native "$env:windir\System32\dsregcmd.exe" @('/status')
        if ($r.Output -match 'AzureAdJoined\s*:\s*(YES|NO)') { $j.Known = $true; $j.Entra = ($Matches[1] -eq 'YES') }
        if ($r.Output -match 'DomainJoined\s*:\s*(YES|NO)') { $j.Known = $true; $j.Domain = ($Matches[1] -eq 'YES') }
    } catch { }
    return [pscustomobject]$j
}

function Get-AccountInfo {
    # Người đang dùng máy đăng nhập bằng tài khoản Microsoft hay tài khoản cục bộ, và các Admin dùng tài khoản Microsoft.
    $a = [ordered]@{ ConsoleUser = (Get-ConsoleUser); ConsoleSource = ''; MsaAdmins = @(); AdminsKnown = $false }
    $short = ($a.ConsoleUser -split '\\')[-1]
    try {
        $u = Get-LocalUser -Name $short -ErrorAction Stop
        $a.ConsoleSource = [string]$u.PrincipalSource
    } catch { }
    try {
        $m = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
        $a.AdminsKnown = $true
        $a.MsaAdmins = @($m | Where-Object { [string]$_.PrincipalSource -eq 'MicrosoftAccount' } | ForEach-Object { ([string]$_.Name -split '\\')[-1] })
    } catch { }
    return [pscustomobject]$a
}

function Get-FvePolicy {
    # Chính sách BitLocker do công ty, phần mềm quản lý đặt (HKLM\SOFTWARE\Policies\Microsoft\FVE).
    $p = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'
    if (-not (Test-Path -LiteralPath $p)) { return @() }
    $key = Get-Item -LiteralPath $p
    $list = foreach ($n in @($key.GetValueNames())) { [pscustomobject]@{ Name = $n; Value = $key.GetValue($n) } }
    return @($list)
}

# ---------------------------------------------------------------- nhật ký sự kiện
# Microsoft-Windows-BitLocker/BitLocker Management (quyền thường đọc được) và System (BitLocker-Driver).
$script:EventText = @{
    '768' = 'Bắt đầu mã hoá ổ'; '770' = 'Bắt đầu giải mã ổ'; '773' = 'Tạm dừng BitLocker'; '774' = 'Bật lại BitLocker'
    '775' = 'Thêm khoá bảo vệ'; '776' = 'Xoá khoá bảo vệ'; '778' = 'Ổ trở về trạng thái không bảo vệ'; '782' = 'Mở khoá ổ'
    '784' = 'Đã sao lưu khoá lên Active Directory'; '513' = 'Đã sao lưu khoá lên Active Directory'
    '785' = 'Sao lưu khoá lên Active Directory thất bại'; '514' = 'Sao lưu khoá lên Active Directory thất bại'
    '828' = 'Đã sao lưu khoá lên tài khoản Microsoft'; '897' = 'Đã sao lưu khoá lên tài khoản Microsoft'
    '830' = 'Khoá đã có sẵn trên tài khoản Microsoft'
    '829' = 'Sao lưu khoá lên tài khoản Microsoft thất bại'; '898' = 'Sao lưu khoá lên tài khoản Microsoft thất bại'
    '831' = 'Sao lưu khoá lên tài khoản Microsoft thất bại'; '4106' = 'Sao lưu khoá lên tài khoản Microsoft thất bại'
    '845' = 'Đã sao lưu khoá lên Entra ID (tài khoản công ty)'; '846' = 'Sao lưu khoá lên Entra ID thất bại'; '847' = 'Sao lưu khoá lên Entra ID thất bại'
    '819' = 'Không bật lại được BitLocker'; '820' = 'Không bật lại được BitLocker'; '821' = 'Không bật lại được BitLocker'
    '822' = 'Không bật lại được BitLocker'; '905' = 'Không bật lại được BitLocker'
    '843' = 'Tạm dừng BitLocker trong môi trường sửa lỗi (WinRE)'; '869' = 'Khoá khôi phục ổ Windows chưa được sao lưu'
    '896' = 'Bỏ đo phần mềm khởi động (PCR) để cập nhật firmware'; '4121' = 'Cần đăng nhập tài khoản Microsoft để hoàn tất mã hoá thiết bị'
    '4146' = 'Windows tự bật mã hoá thiết bị'; '4147' = 'Người dùng bật mã hoá thiết bị'
    '24652' = 'Phải nhập khoá khôi phục để khởi động Windows'; '24654' = 'Phải dùng khoá USB khôi phục để khởi động Windows'
    '24641' = 'Lỗi đọc khoá BitLocker khi khởi động lại'; '24580' = 'Bắt đầu giải mã ổ'; '779' = 'Ổ BitLocker bị xoá hoặc định dạng lại'
}
$script:EventBackupMsa = @(828, 897, 830)
$script:EventBackupAd = @(784, 513)
$script:EventBackupEntra = @(845)
$script:EventBackupFail = @(785, 514, 829, 898, 831, 4106, 846, 847)
$script:EventRecoveryBoot = @(24652, 24654)

function Get-BdeEvents {
    # Sự kiện BitLocker trong $Days ngày, mới nhất trước. Guids: các mã GUID trong sự kiện để ghép với Mã khoá.
    # Drive: chữ ổ trong câu báo (vd "volume C:"). Cùng một việc được ghi ở cả hai nhật ký (770 và 24580) thì giữ một.
    param([int]$Days = 730)
    $since = (Get-Date).AddDays(-$Days)
    $raw = @()
    try { $raw += @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-BitLocker/BitLocker Management'; StartTime = $since } -MaxEvents 2000 -ErrorAction Stop) } catch { }
    try { $raw += @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-BitLocker-Driver'; StartTime = $since } -MaxEvents 500 -ErrorAction Stop) } catch { }
    $seen = @{}
    $list = foreach ($e in @($raw | Sort-Object TimeCreated -Descending)) {
        $key = [string]$e.Id
        if (-not $script:EventText.ContainsKey($key)) { continue }
        $msg = [string]$e.Message
        $drive = ''
        if ($msg -match '(?<![\w\\])([A-Za-z]):(?![\\\w])') { $drive = $Matches[1].ToUpperInvariant() + ':' }
        $once = '{0:yyyyMMddHHmmss}|{1}|{2}' -f $e.TimeCreated, $script:EventText[$key], $drive
        if ($drive -and $seen.ContainsKey($once)) { continue }
        $seen[$once] = $true
        $text = (@($e.Properties | ForEach-Object { [string]$_.Value }) -join ' ') + ' ' + $msg
        $guids = @([regex]::Matches($text, $script:GuidPattern) | ForEach-Object { '{' + $_.Value.ToUpperInvariant() + '}' } | Select-Object -Unique)
        [pscustomobject]@{ Time = $e.TimeCreated; Id = [int]$e.Id; Text = $script:EventText[$key]; Drive = $drive; Guids = $guids }
    }
    return @($list)
}

# ---------------------------------------------------------------- khoá khôi phục: kiểm tra, đọc file đã lưu
function Test-RecoveryPassword {
    # Khoá khôi phục: 48 chữ số, 8 nhóm 6 số; mỗi nhóm chia hết cho 11 và nhỏ hơn 720896.
    # Nhận cả kiểu gõ có dấu cách hoặc không có gạch. Trả khoá đã chuẩn hoá (nhóm cách nhau bằng '-'), sai thì $null.
    param([string]$Text)
    $digits = ($Text -replace '[\s\-]', '')
    if ($digits -notmatch '^\d{48}$') { return $null }
    $groups = for ($k = 0; $k -lt 8; $k++) { $digits.Substring($k * 6, 6) }
    foreach ($g in $groups) { $n = [int]$g; if ($n % 11 -ne 0 -or $n -ge 720896) { return $null } }
    return ($groups -join '-')
}

function Read-KeyFile {
    # Các cặp (Mã khoá, khoá) trong một file: file "BitLocker Recovery Key ....txt" của Windows (UTF-16) hoặc file
    # công cụ này lưu (UTF-8). Mỗi khoá đi với Mã khoá đứng gần nhất phía trước nó.
    param([string]$Path)
    try {
        $bytes = [IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -gt 1MB) { return @() }
        if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $text = [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) }
        elseif ($bytes.Length -ge 2 -and $bytes[1] -eq 0 -and $bytes[0] -ne 0) { $text = [Text.Encoding]::Unicode.GetString($bytes) }
        else { $text = [Text.Encoding]::UTF8.GetString($bytes) }
    } catch { return @() }
    $items = New-Object System.Collections.ArrayList
    $ids = @([regex]::Matches($text, $script:GuidPattern))
    foreach ($m in @([regex]::Matches($text, $script:KeyPattern))) {
        $key = Test-RecoveryPassword $m.Value
        if (-not $key) { continue }
        $id = $null
        foreach ($g in $ids) { if ($g.Index -lt $m.Index) { $id = '{' + $g.Value.ToUpperInvariant() + '}' } }
        [void]$items.Add([pscustomobject]@{ Id = $id; Key = $key; File = $Path })
    }
    return @($items)
}

function Get-KeySearchDirs {
    # Nơi hay có file khoá: ket_qua\khoa-bitlocker, thư mục người dùng chỉ, gốc các ổ (USB), bản sao lưu của
    # "Chuyển dữ liệu khi cài lại Windows", Desktop, Documents, Downloads, OneDrive.
    param([string]$Extra = '')
    $dirs = New-Object System.Collections.Generic.List[string]
    $add = { param([string]$d) if ($d -and -not $dirs.Contains($d) -and (Test-Path -LiteralPath $d -PathType Container)) { $dirs.Add($d) } }
    & $add (Join-Path (Get-ResultDir) 'khoa-bitlocker')
    if ($Extra) { & $add $Extra }
    foreach ($d in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 2 OR DriveType = 3' -ErrorAction SilentlyContinue)) {
        $root = [string]$d.DeviceID + '\'
        & $add $root
        & $add (Join-Path $root 'DuLieu_SaoLuu\BitLocker')
        foreach ($sub in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Select-Object -First 200)) {
            & $add (Join-Path $sub.FullName 'DuLieu_SaoLuu\BitLocker')
        }
    }
    foreach ($f in 'Desktop', 'MyDocuments') { & $add ([Environment]::GetFolderPath($f)) }
    & $add (Join-Path $env:USERPROFILE 'Downloads')
    & $add $env:OneDrive
    return @($dirs)
}

function Find-SavedKeys {
    # Khoá khôi phục trong các file tìm được. Thư mục người dùng chỉ thì tìm cả thư mục con (2 cấp).
    param([string]$Extra = '')
    $found = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($d in @(Get-KeySearchDirs -Extra $Extra)) {
        $gci = @{ LiteralPath = $d; File = $true; ErrorAction = 'SilentlyContinue' }
        if ($Extra -and $d -eq $Extra) { $gci.Recurse = $true; $gci.Depth = 2 }
        foreach ($f in @(Get-ChildItem @gci | Where-Object { $_.Extension -eq '.txt' -and $_.Length -lt 1MB })) {
            if ($seen.ContainsKey($f.FullName)) { continue }
            $seen[$f.FullName] = $true
            $isKeyName = $f.Name -match 'BitLocker|KhoaKhoiPhuc|Recovery'
            # Ngoài thư mục khoá chỉ đọc file có tên giống file khoá, khỏi mở mọi file .txt trên Desktop.
            if (-not $isKeyName -and $d -notmatch 'khoa-bitlocker|DuLieu_SaoLuu\\BitLocker' -and $d -ne $Extra) { continue }
            foreach ($k in @(Read-KeyFile $f.FullName)) { [void]$found.Add($k) }
        }
    }
    return @($found)
}
