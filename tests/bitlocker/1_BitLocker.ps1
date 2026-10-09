# Thử các nhánh cần Admin của công cụ BitLocker bằng ổ giả: thay Invoke-Bde, Get-BdeVolumes, Test-IsAdmin,
# Get-BdeEvents, Get-KeySearchDirs, Start-Process bằng bản giả. Không gọi WMI BitLocker thật, không đổi gì trên máy.
# Khoá dùng ở đây là khoá giả sinh ngẫu nhiên đúng dạng; bài thử kiểm tra không khoá nào lọt vào báo cáo, nhật ký.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$lib = "$ToolsDir\bitlocker\lib"
$here = $TestRoot
$script:ToolDir = New-TestDir 'tool'
$usbDir = New-TestDir 'usb'
$script:ToolVersion = 'test'
. "$lib\Chung.ps1"; . "$lib\NhatKy.ps1"; . "$lib\DocBitLocker.ps1"; . "$lib\ChanDoan.ps1"; . "$lib\ThaoTac.ps1"
$script:NoPause = $true
$script:Modes = [ordered]@{
    'kiem-tra' = @{ No = 1; Label = 'Kiểm tra BitLocker và khoá khôi phục' }; 'luu-khoa' = @{ No = 2; Label = 'Lưu khoá khôi phục ra file' }
    'tam-dung' = @{ No = 3; Label = 'Tạm dừng BitLocker' }; 'bat-lai' = @{ No = 4; Label = 'Bật lại BitLocker' }
    'mo-khoa' = @{ No = 5; Label = 'Mở khoá ổ bị BitLocker khoá' }; 'giai-ma' = @{ No = 6; Label = 'Giải mã ổ' }; 'hoan-tac' = @{ No = 7; Label = 'Hoàn tác' }
}

function New-FakeKey { (1..8 | ForEach-Object { '{0:D6}' -f ((Get-Random -Minimum 0 -Maximum 65535) * 11) }) -join '-' }
function New-FakeId { '{' + [guid]::NewGuid().ToString().ToUpperInvariant() + '}' }

$script:Calls = New-Object System.Collections.ArrayList
$script:FailAutoUnlock = $false
$script:AllKeys = New-Object System.Collections.ArrayList   # để kiểm tra không khoá nào lọt vào báo cáo

function Reset-Fake {
    $kc = New-FakeKey; $ke = New-FakeKey
    [void]$script:AllKeys.Add($kc); [void]$script:AllKeys.Add($ke)
    $script:IdC = New-FakeId; $script:IdE = New-FakeId
    $script:Fake = @{
        C = @{ Letter = 'C:'; Type = 0; Locked = $false; Conv = 1; Pct = 100; Prot = 1; Method = 7; Suspend = 0; SB = 3; AutoUnlock = $null
            Protectors = @(@{ Id = (New-FakeId); Type = 1; Pcr = @(0, 2, 4, 11) }, @{ Id = $script:IdC; Type = 3 }); Keys = @{ $script:IdC = $kc } }
        D = @{ Letter = 'D:'; Type = 1; Locked = $false; Conv = 1; Pct = 100; Prot = 1; Method = 7; AutoUnlock = $false
            Protectors = @(@{ Id = (New-FakeId); Type = 8 }); Keys = @{} }
        E = @{ Letter = 'E:'; Type = 1; Locked = $true; Conv = 1; Pct = 100; Prot = 2; Method = 7; AutoUnlock = $false
            Protectors = @(@{ Id = $script:IdE; Type = 3 }); Keys = @{ $script:IdE = $ke } }
        F = @{ Letter = 'F:'; Type = 1; Locked = $false; Conv = 0; Pct = 0; Prot = 0; Method = 0; AutoUnlock = $false; Protectors = @(); Keys = @{} }
    }
    $script:Calls.Clear()
}

# ---- bản giả
function Test-IsAdmin { $true }
function Start-Process { [void]$script:Calls.Add('START-PROCESS ' + ($args -join ' ')) }
function Get-BdeVolumes {
    foreach ($t in 'C', 'D', 'E', 'F') {
        [pscustomobject]@{ Tag = $t; DriveLetter = $script:Fake[$t].Letter; DeviceID = "\\?\Volume{fake-$t}\"; VolumeType = [uint32]$script:Fake[$t].Type }
    }
}
function Get-KeySearchDirs { param([string]$Extra = '') @((Join-Path (Get-ResultDir) 'khoa-bitlocker'), (Join-Path $here 'usb')) + @($(if ($Extra) { $Extra })) | Where-Object { $_ -and (Test-Path $_) } }
function Get-BdeEvents {
    param([int]$Days = 730)
    @(
        [pscustomobject]@{ Time = (Get-Date).AddDays(-10); Id = 24652; Text = $script:EventText['24652']; Drive = ''; Guids = @() }
        [pscustomobject]@{ Time = (Get-Date).AddDays(-30); Id = 829; Text = $script:EventText['829']; Drive = 'C:'; Guids = @($script:IdC) }
        [pscustomobject]@{ Time = (Get-Date).AddDays(-400); Id = 828; Text = $script:EventText['828']; Drive = 'C:'; Guids = @($script:IdC) }
    )
}
function Invoke-Bde {
    param($Volume, [string]$Method, [hashtable]$Arguments = $null)
    $f = $script:Fake[$Volume.Tag]
    $argText = if ($Arguments) { (@($Arguments.Keys | Sort-Object | ForEach-Object { "$_=" + $(if ($_ -eq 'NumericalPassword' -and $Arguments[$_]) { '<khoá>' } else { [string]$Arguments[$_] }) }) -join ';') } else { '' }
    [void]$script:Calls.Add(('{0} {1} {2}' -f $Volume.Tag, $Method, $argText).Trim())
    $locked = { throw (New-BdeError (ConvertTo-UInt32Code 0x80310000)) }
    switch ($Method) {
        'GetLockStatus' { return [pscustomobject]@{ LockStatus = [uint32]([int]$f.Locked) } }
        'GetProtectionStatus' { return [pscustomobject]@{ ProtectionStatus = [uint32]$f.Prot } }
        'GetEncryptionMethod' { return [pscustomobject]@{ EncryptionMethod = [uint32]$f.Method } }
        'GetConversionStatus' { if ($f.Locked) { & $locked }; return [pscustomobject]@{ ConversionStatus = [uint32]$f.Conv; EncryptionPercentage = [uint32]$f.Pct } }
        'GetKeyProtectors' { return [pscustomobject]@{ VolumeKeyProtectorID = [string[]]@($f.Protectors | ForEach-Object { $_.Id }) } }
        'GetKeyProtectorType' { return [pscustomobject]@{ KeyProtectorType = [uint32](@($f.Protectors | Where-Object { $_.Id -eq $Arguments.VolumeKeyProtectorID })[0].Type) } }
        'GetKeyProtectorPlatformValidationProfile' { return [pscustomobject]@{ PlatformValidationProfile = [byte[]]@(@($f.Protectors | Where-Object { $_.Id -eq $Arguments.VolumeKeyProtectorID })[0].Pcr) } }
        'IsAutoUnlockEnabled' { if ($f.Type -eq 0) { throw (New-BdeError 2150694912) }; return [pscustomobject]@{ IsAutoUnlockEnabled = [bool]$f.AutoUnlock } }
        'GetSecureBootBindingState' { return [pscustomobject]@{ BindingState = [uint32]$f.SB } }
        'GetSuspendCount' { return [pscustomobject]@{ SuspendCount = [uint32]$f.Suspend } }
        'GetKeyProtectorNumericalPassword' { if ($f.Locked) { & $locked }; return [pscustomobject]@{ NumericalPassword = $f.Keys[$Arguments.VolumeKeyProtectorID] } }
        'ProtectKeyWithNumericalPassword' {
            $id = New-FakeId; $k = New-FakeKey; [void]$script:AllKeys.Add($k)
            $f.Protectors += @{ Id = $id; Type = 3 }; $f.Keys[$id] = $k
            return [pscustomobject]@{ VolumeKeyProtectorID = $id }
        }
        'DisableKeyProtectors' { $f.Prot = 0; $f.Suspend = [int]$Arguments.DisableCount; return }
        'EnableKeyProtectors' { if ($script:FailEnable) { throw (New-BdeError (ConvertTo-UInt32Code 0x80310030)) }; if (-not $f.Protectors.Count) { throw (New-BdeError (ConvertTo-UInt32Code 0x80310033)) }; $f.Prot = 1; return }
        'UnlockWithNumericalPassword' {
            if ($f.Keys.Values -contains $Arguments.NumericalPassword) { $f.Locked = $false; $f.Prot = 1; return }
            throw (New-BdeError (ConvertTo-UInt32Code 0x80310027))
        }
        'ProtectKeyWithExternalKey' { $id = New-FakeId; $f.Protectors += @{ Id = $id; Type = 2 }; return [pscustomobject]@{ VolumeKeyProtectorID = $id } }
        'EnableAutoUnlock' { if ($script:FailAutoUnlock) { throw (New-BdeError (ConvertTo-UInt32Code 0x80310019)) }; $f.AutoUnlock = $true; return }
        'DeleteKeyProtector' { $f.Protectors = @($f.Protectors | Where-Object { $_.Id -ne $Arguments.VolumeKeyProtectorID }); return }
        'DisableAutoUnlock' { $f.AutoUnlock = $false; return }
        'Decrypt' { $f.Conv = 3; $f.Pct = 97; return }
    }
    throw "Bản giả chưa có $Method"
}


$script:ReadOnlyMethods = 'GetLockStatus|GetProtectionStatus|GetEncryptionMethod|GetConversionStatus|GetKeyProtectors|GetKeyProtectorType|GetKeyProtectorPlatformValidationProfile|IsAutoUnlockEnabled|GetSecureBootBindingState|GetSuspendCount'
function Invoke-Case {
    # Chạy một chế độ, trả mã thoát và các lời gọi BitLocker có tác dụng (bỏ lời gọi chỉ đọc trạng thái)
    param([string]$Name, [scriptblock]$Do)
    Write-Host "`n#### $Name" -ForegroundColor Magenta
    $script:Calls.Clear()
    $r = & $Do
    $calls = @($script:Calls | Where-Object { $_ -notmatch " ($script:ReadOnlyMethods)\b" })
    Write-Host ('  => mã {0}; lời gọi: {1}' -f @($r)[-1], ($calls -join ' | ')) -ForegroundColor DarkCyan
    return [pscustomobject]@{ Code = @($r)[-1]; Calls = $calls; Text = ($calls -join "`n") }
}
function Test-NoChange($c) { return ($c.Calls.Count -eq 0) }

Write-Host '#### hàm nhỏ' -ForegroundColor Magenta
$k = New-FakeKey
Check ([bool](Test-RecoveryPassword $k) -and [bool](Test-RecoveryPassword ($k -replace '-', '')) -and [bool](Test-RecoveryPassword ($k -replace '-', ' '))) 'Test-RecoveryPassword nhận khoá có gạch, không gạch, có cách'
Check (-not (Test-RecoveryPassword ('000001' + $k.Substring(6))) -and -not (Test-RecoveryPassword $k.Substring(1))) 'Test-RecoveryPassword từ chối nhóm sai (không chia hết 11), thiếu số'
Check ((Get-RecoveryPasswordProblem $k.Substring(1)) -match 'gõ 47') 'báo thiếu số'
Check ((Get-RecoveryPasswordProblem ('000001' + $k.Substring(6))) -match 'Nhóm thứ 1') 'báo nhóm gõ nhầm'
Check ((Get-RecoveryPasswordProblem ($k.Substring(0, 13) + '000001' + $k.Substring(19))) -match 'gõ 49') 'báo thừa số'
Check ((Get-RecoveryPasswordProblem 'abc') -match 'chỉ gồm chữ số') 'báo có chữ'
$fd = @('e', 'E:', 'E:\', 'E:\.', 'EE', 'E:\x', '') | ForEach-Object { Format-DriveLetter $_ }
Check (($fd -join ',') -eq 'E:,E:,E:,E:,,,') "Format-DriveLetter: $($fd -join ',')"
Check ((Format-KeyId ' {abcdef01-2345-6789-abcd-ef0123456789} ') -eq '{ABCDEF01-2345-6789-ABCD-EF0123456789}' -and (Format-KeyId 'abcdef01-2345-6789-abcd-ef0123456789') -eq '{ABCDEF01-2345-6789-ABCD-EF0123456789}') 'Format-KeyId'
Check ((Format-ShortId '{abcdef01-2345-6789-abcd-ef0123456789}') -eq 'ABCDEF01') 'Format-ShortId'

Reset-Fake
$c = Invoke-Case 'kiem-tra' { Invoke-KiemTra }
Check ($c.Code -eq 0 -and (Test-NoChange $c)) "kiem-tra: mã $($c.Code), không đổi gì"
Check (-not (@($script:Calls) -match 'GetKeyProtectorNumericalPassword')) 'kiem-tra không đọc khoá khôi phục'

$c = Invoke-Case 'luu-khoa chạy thử' { Invoke-LuuKhoa -DryRun }
Check ($c.Code -eq 0 -and (Test-NoChange $c)) "luu-khoa -DryRun: mã $($c.Code), không gọi gì"
$c = Invoke-Case 'luu-khoa' { Invoke-LuuKhoa -NoiLuu $usbDir }
Check ($c.Code -eq 0) "luu-khoa: mã $($c.Code)"
Check ($c.Text -match '(?m)^D ProtectKeyWithNumericalPassword') 'ổ D: chưa có khoá khôi phục: tạo khoá'
Check ($c.Text -match '(?m)^C GetKeyProtectorNumericalPassword' -and $c.Text -match '(?m)^D GetKeyProtectorNumericalPassword') 'đọc khoá của C: và D:'
Check ($c.Text -match 'START-PROCESS .*explorer\.exe') 'mở Explorer chỉ vào file khoá'
$kf = @(Get-ChildItem -LiteralPath $usbDir -Filter 'BitLocker_KhoaKhoiPhuc_*.txt')
Check ($kf.Count -eq 1 -and [IO.File]::ReadAllText($kf[0].FullName).Contains($script:Fake.C.Keys[$script:IdC])) 'file khoá có khoá của C:'
$origYesNo = ${function:Read-YesNo}
${function:Read-YesNo} = { param($Question, $Default) Write-Host "  (hỏi: $Question -> có)"; $true }
$c = Invoke-Case 'hoan-tac luu-khoa' { Invoke-HoanTac -NhatKy (@(Get-ChildItem (Join-Path $script:ToolDir 'ket_qua\hoan-tac') -Filter '*luu-khoa*')[0].BaseName) }
${function:Read-YesNo} = $origYesNo
Check ($c.Code -eq 0 -and $c.Text -match '(?m)^D DeleteKeyProtector' -and $c.Calls.Count -eq 1) "hoàn tác lưu khoá: xoá đúng khoá đã tạo cho D: (mã $($c.Code))"

$c = Invoke-Case 'tam-dung chạy thử' { Invoke-TamDung -SoLan '0' -DryRun }
Check ($c.Code -eq 0 -and (Test-NoChange $c)) 'tam-dung -DryRun: không gọi gì'
$c = Invoke-Case 'tam-dung 2' { Invoke-TamDung -SoLan '2' }
Check ($c.Code -eq 0 -and $c.Text -eq 'C DisableKeyProtectors DisableCount=2') "tam-dung 2 lần khởi động: $($c.Text)"
$c = Invoke-Case 'tam-dung lần hai' { Invoke-TamDung -SoLan '1' }
Check ($c.Code -eq 0 -and $c.Text -notmatch 'DisableKeyProtectors') 'đã tạm dừng: không tạm dừng lần nữa'
$c = Invoke-Case 'bat-lai' { Invoke-BatLai }
Check ($c.Code -eq 0 -and $c.Text -eq 'C EnableKeyProtectors') "bat-lai: $($c.Text)"
$c = Invoke-Case 'tam-dung 1' { Invoke-TamDung -SoLan '1' }
Check ($c.Code -eq 0 -and $c.Text -eq 'C DisableKeyProtectors DisableCount=1') "tam-dung 1: $($c.Text)"
$script:FailEnable = $true
$c = Invoke-Case 'bat-lai lỗi' { Invoke-BatLai }
$script:FailEnable = $false
Check ($c.Code -eq 1) "bat-lai báo lỗi đĩa khởi động: mã $($c.Code)"

$c = Invoke-Case 'mo-khoa chạy thử' { Invoke-MoKhoa -DryRun }
Check ($c.Code -eq 0 -and (Test-NoChange $c)) 'mo-khoa -DryRun: không gọi gì'
$c = Invoke-Case 'mo-khoa (không có bàn phím)' { Invoke-MoKhoa }
Check ($c.Code -eq 3) "không gõ được khoá cho E: -> mã 3: $($c.Code)"
Check ($c.Text -notmatch 'UnlockWithNumericalPassword') 'không thử mở khoá E: khi không có khoá'
Check ($c.Text -match '(?m)^D ProtectKeyWithExternalKey' -and $c.Text -match '(?m)^D EnableAutoUnlock') 'D: được bật tự mở khoá'
$c = Invoke-Case 'hoan-tac mo-khoa' { Invoke-HoanTac -NhatKy (@(Get-ChildItem (Join-Path $script:ToolDir 'ket_qua\hoan-tac') -Filter '*mo-khoa*')[0].Name) }
Check ($c.Code -eq 0 -and $c.Text -match '(?m)^D DisableAutoUnlock' -and $c.Text -match '(?m)^D DeleteKeyProtector') "hoàn tác tự mở khoá D: (mã $($c.Code))"

Reset-Fake
# File khoá kiểu Windows (UTF-16 có BOM) cho ổ E:
$winKey = "BitLocker Drive Encryption recovery key`r`n`r`nIdentifier:`r`n`r`n`t$($script:IdE.Trim('{}'))`r`n`r`nIf the above identifier matches the one displayed by your PC, then use the following key to unlock your drive.`r`n`r`nRecovery Key:`r`n`r`n`t$($script:Fake.E.Keys[$script:IdE])`r`n"
[IO.File]::WriteAllText((Join-Path $usbDir ("BitLocker Recovery Key {0}.TXT" -f $script:IdE.Trim('{}'))), $winKey, [Text.Encoding]::Unicode)
$script:FailAutoUnlock = $true
$c = Invoke-Case 'mo-khoa E: bằng file khoá, tự mở khoá lỗi' { Invoke-MoKhoa -ODia 'E:' -ThuMucKhoa $usbDir }
$script:FailAutoUnlock = $false
Check ($c.Code -eq 3 -and -not $script:Fake.E.Locked) "mở được E: bằng file khoá của Windows, tự mở khoá lỗi -> mã 3: $($c.Code)"
Check ($c.Text -match '(?m)^E UnlockWithNumericalPassword NumericalPassword=<khoá>') 'mở khoá bằng khoá khôi phục'
Check ($c.Text -match '(?m)^E DeleteKeyProtector') 'tự mở khoá lỗi: xoá khoá ngoài vừa tạo, không để thừa'
$c = Invoke-Case 'mo-khoa ổ không có' { Invoke-MoKhoa -ODia 'Z:' }
Check ($c.Code -eq 1 -and (Test-NoChange $c)) "ổ Z: không có -> mã 1: $($c.Code)"

$c = Invoke-Case 'giai-ma chạy thử' { Invoke-GiaiMa -DryRun }
Check ($c.Code -eq 0 -and (Test-NoChange $c)) 'giai-ma -DryRun: không gọi gì'
$c = Invoke-Case 'giai-ma C:' { Invoke-GiaiMa -ODia 'C:' }
Check ($c.Code -eq 0 -and $c.Text -match 'START-PROCESS ms-settings:deviceencryption' -and $c.Text -notmatch 'Decrypt') 'ổ hệ điều hành: mở Cài đặt, không tự giải mã'
function Confirm-Strong { $true }
$c = Invoke-Case 'giai-ma D:' { Invoke-GiaiMa -ODia 'D:' }
Check ($c.Code -eq 0 -and $c.Text -eq 'D Decrypt') "giai-ma D: (đã xác nhận): $($c.Text)"
$c = Invoke-Case 'hoan-tac chạy thử' { Invoke-HoanTac -DryRun }
Check ($c.Code -eq 0 -and (Test-NoChange $c)) 'hoan-tac -DryRun: không gọi gì'
$c = Invoke-Case 'hoan-tac' { Invoke-HoanTac }
Check ($c.Code -eq 0 -and (Test-NoChange $c)) 'hoan-tac tạm dừng khi C: đã được bảo vệ lại: bỏ qua'

Write-Host "`n#### rò khoá" -ForegroundColor Magenta
$files = @(Get-ChildItem -LiteralPath $script:ToolDir -Recurse -File | Where-Object { $_.Name -notmatch '^BitLocker_KhoaKhoiPhuc_' })
$leak = @()
foreach ($f in $files) { $t = [IO.File]::ReadAllText($f.FullName); foreach ($kk in $script:AllKeys) { if ($t.Contains($kk)) { $leak += $f.Name } } }
$rep = ($script:Report -join "`n"); foreach ($kk in $script:AllKeys) { if ($rep.Contains($kk)) { $leak += 'bộ nhớ báo cáo' } }
Check ($files.Count -ge 4) "có báo cáo, nhật ký hoàn tác để soát ($($files.Count) file)"
Check ($leak.Count -eq 0) "không khoá khôi phục nào lọt vào báo cáo, nhật ký ($($leak -join ', '))"

Complete-Test
