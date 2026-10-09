# Bài thử DongHo.ps1 bằng giả lập: BCD (bảng trong bộ nhớ), BitLocker, quyền Admin, câu trả lời; registry dùng HKCU.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$env:TRAMTOOL_DONGHO_TEST = '1'
. "$ToolsDir\clock-optimizer\DongHo.ps1"
$ChayThu = $false; $KhongDung = $true
$script:KernelKey = 'HKCU:\Software\TramToolTest\kernel'

# ---- giả lập
$script:Bcd = @{}
$script:SetWorks = $true; $script:SetSticks = $true; $script:EnumWorks = $true
$script:Calls = New-Object System.Collections.ArrayList
function Invoke-BcdEdit {
    param([string[]]$Arguments)
    [void]$script:Calls.Add(($Arguments -join ' '))
    switch ($Arguments[0]) {
        '/enum' {
            if (-not $script:EnumWorks) { return [pscustomobject]@{ Code = 1; Output = 'The boot configuration data store could not be opened. Access is denied.' } }
            $t = "Windows Boot Loader`n-------------------`nidentifier              {current}`ndevice                  partition=C:`npath                    \WINDOWS\system32\winload.efi`ndescription             Windows 11`n"
            foreach ($k in $script:Bcd.Keys) { $t += ('{0,-24}{1}' -f $k, $script:Bcd[$k]) + "`n" }
            return [pscustomobject]@{ Code = 0; Output = $t }
        }
        '/set' {
            if (-not $script:SetWorks) { return [pscustomobject]@{ Code = 1; Output = 'An error occurred while attempting to modify the specified entry.' } }
            if ($script:SetSticks) { $script:Bcd[$Arguments[2]] = $(if ($Arguments[3] -eq 'yes') { 'Yes' } else { 'No' }) }
            return [pscustomobject]@{ Code = 0; Output = 'The operation completed successfully.' }
        }
        '/deletevalue' {
            if (-not $script:Bcd.ContainsKey($Arguments[2])) { return [pscustomobject]@{ Code = 1; Output = 'Element not found.' } }
            $script:Bcd.Remove($Arguments[2])
            return [pscustomobject]@{ Code = 0; Output = 'The operation completed successfully.' }
        }
    }
}
$script:Bl = [pscustomobject]@{ Known = $true; On = $false; Message = 'tắt' }
$script:SuspendOk = $true; $script:Suspended = 0
function Get-OsBitLocker { return $script:Bl }
function Suspend-OsBitLocker { $script:Suspended++; if ($script:SuspendOk) { $script:Bl = [pscustomobject]@{ Known = $true; On = $false; Message = 'tạm dừng' } }; return $script:SuspendOk }
function Test-IsAdmin { return $true }
$script:Answers = New-Object System.Collections.Queue
function Read-YesNo { param([string]$Question, [bool]$Default = $false) if ($script:Answers.Count) { return $script:Answers.Dequeue() } return $Default }

function Reset-Case {
    param([hashtable]$Bcd = @{}, [string[]]$OldReg = @())
    $script:Bcd = $Bcd.Clone(); $script:SetWorks = $true; $script:SetSticks = $true; $script:EnumWorks = $true
    $script:Calls.Clear(); $script:Bl = [pscustomobject]@{ Known = $true; On = $false; Message = 'tắt' }
    $script:SuspendOk = $true; $script:Suspended = 0; $script:Answers.Clear()
    if (Test-Path $script:KernelKey) { Remove-Item -LiteralPath $script:KernelKey -Recurse -Force }
    New-Item -Path $script:KernelKey -Force | Out-Null
    foreach ($n in $OldReg) { New-ItemProperty -LiteralPath $script:KernelKey -Name $n -Value 1 -PropertyType DWord | Out-Null }
}
function Run([string]$Id, [switch]$Dry) { $c = Invoke-Change $Id -DryRun:$Dry 6>$null; return @($c)[-1] }

# 1. đọc chữ bcdedit (kể cả bản dịch)
$s = ConvertFrom-BcdEnum "identifier {current}`ndisabledynamictick      Yes`nuseplatformclock        No`nUsePlatformTick   Có"
Check 'đọc disabledynamictick Yes' ($s.disabledynamictick.Set -and $s.disabledynamictick.On)
Check 'đọc useplatformclock No' ($s.useplatformclock.Set -and -not $s.useplatformclock.On)
Check 'đọc chữ dịch "Có", tên viết hoa' ($s.useplatformtick.On)
$s2 = ConvertFrom-BcdEnum "identifier {current}`ndescription Windows"
Check 'không có phần tử = chưa đặt' (-not ($s2.Values | Where-Object { $_.Set }))

# 2. chơi game trên máy mặc định, có giá trị registry cũ
Reset-Case -OldReg 'useplatformclock', 'disabledynamictick'
$c = Run 'choi-game'
Check 'choi-game mã 0' ($c -eq 0) "mã $c"
Check 'choi-game đặt disabledynamictick' ($script:Bcd.disabledynamictick -eq 'Yes')
Check 'choi-game không xoá useplatformclock khi chưa đặt' (-not ($script:Calls -match 'deletevalue'))
Check 'choi-game dọn registry cũ' (-not (Get-ItemProperty -LiteralPath $script:KernelKey -Name useplatformclock -ErrorAction SilentlyContinue) -and -not (Get-ItemProperty -LiteralPath $script:KernelKey -Name disabledynamictick -ErrorAction SilentlyContinue))
$c = Run 'choi-game'
Check 'chạy lại: không cần đổi, mã 0' ($c -eq 0 -and -not ($script:Calls | Select-Object -Last 1 | Where-Object { $_ -match '/set' }))

# 3. chơi game khi đang ép HPET
Reset-Case -Bcd @{ useplatformclock = 'Yes' }
$c = Run 'choi-game'
Check 'bỏ ép HPET' ($c -eq 0 -and -not $script:Bcd.ContainsKey('useplatformclock') -and $script:Bcd.disabledynamictick -eq 'Yes')

# 4. trả về mặc định
Reset-Case -Bcd @{ useplatformclock = 'Yes'; useplatformtick = 'Yes'; disabledynamictick = 'Yes' } -OldReg 'disabledynamictick'
$c = Run 'mac-dinh'
Check 'mac-dinh mã 0, xoá cả ba' ($c -eq 0 -and $script:Bcd.Count -eq 0) "mã $c, còn $($script:Bcd.Keys -join ',')"
Check 'mac-dinh dọn registry' (-not (Get-ItemProperty -LiteralPath $script:KernelKey -Name disabledynamictick -ErrorAction SilentlyContinue))
Reset-Case
$c = Run 'mac-dinh'
Check 'mac-dinh trên máy mặc định: không gọi deletevalue' ($c -eq 0 -and -not ($script:Calls -match 'deletevalue'))

# 5. BitLocker đang bật
Reset-Case; $script:Bl = [pscustomobject]@{ Known = $true; On = $true; Message = 'bật' }; $script:Answers.Enqueue($false)
$c = Run 'choi-game'
Check 'BitLocker bật, không đồng ý: mã 2, không đổi' ($c -eq 2 -and $script:Bcd.Count -eq 0 -and $script:Suspended -eq 0)
Reset-Case; $script:Bl = [pscustomobject]@{ Known = $true; On = $true; Message = 'bật' }; $script:Answers.Enqueue($true)
$c = Run 'choi-game'
Check 'BitLocker bật, đồng ý: tạm dừng rồi đổi' ($c -eq 0 -and $script:Suspended -eq 1 -and $script:Bcd.disabledynamictick -eq 'Yes')
Reset-Case; $script:Bl = [pscustomobject]@{ Known = $true; On = $true; Message = 'bật' }; $script:Answers.Enqueue($true); $script:SuspendOk = $false
$c = Run 'choi-game'
Check 'không tạm dừng được: mã 1, không đổi' ($c -eq 1 -and $script:Bcd.Count -eq 0)
Reset-Case; $script:Bl = [pscustomobject]@{ Known = $false; On = $false; Message = 'Access denied' }
$c = Run 'choi-game'
Check 'không đọc được BitLocker, mặc định không: mã 2' ($c -eq 2 -and $script:Bcd.Count -eq 0)
Reset-Case -OldReg 'disabledynamictick'; $script:Bl = [pscustomobject]@{ Known = $true; On = $true; Message = 'bật' }
$script:Bcd = @{ disabledynamictick = 'Yes' }
$c = Run 'choi-game'
Check 'chỉ dọn registry thì không hỏi BitLocker' ($c -eq 0 -and $script:Suspended -eq 0)

# 6. bcdedit lỗi, đọc lại sai
Reset-Case; $script:SetWorks = $false
$c = Run 'choi-game'
Check 'bcdedit /set lỗi: mã 1' ($c -eq 1) "mã $c"
Reset-Case -OldReg 'useplatformclock'; $script:SetWorks = $false
$c = Run 'choi-game'
Check 'bcdedit lỗi nhưng dọn được registry: mã 3' ($c -eq 3) "mã $c"
Reset-Case; $script:SetSticks = $false
$c = Run 'choi-game'
Check 'bcdedit báo 0 mà đọc lại chưa đổi: mã 1' ($c -eq 1) "mã $c"
Reset-Case -OldReg 'useplatformclock'; $script:SetSticks = $false
$c = Run 'choi-game'
Check 'đọc lại chưa đổi nhưng dọn được registry: mã 3' ($c -eq 3) "mã $c"

# 7. chạy thử
Reset-Case -Bcd @{ useplatformclock = 'Yes' } -OldReg 'useplatformclock'
$c = Run 'mac-dinh' -Dry
Check 'chạy thử: mã 0, không đổi gì' ($c -eq 0 -and $script:Bcd.useplatformclock -eq 'Yes' -and (Get-ItemProperty -LiteralPath $script:KernelKey -Name useplatformclock -ErrorAction SilentlyContinue))
Reset-Case; $script:EnumWorks = $false
$c = Run 'choi-game' -Dry
Check 'chạy thử khi không đọc được BCD: mã 0' ($c -eq 0 -and $script:Bcd.Count -eq 0)
Reset-Case; $script:EnumWorks = $false
$c = Run 'choi-game'
Check 'chạy thật khi không đọc được BCD: mã 1, không đổi' ($c -eq 1 -and $script:Bcd.Count -eq 0)

# 8. kiểm tra
Reset-Case -Bcd @{ useplatformclock = 'Yes' } -OldReg 'disabledynamictick'
$c = @(Invoke-KiemTra 6>$null)[-1]
Check 'kiem-tra mã 0' ($c -eq 0)
Reset-Case; $script:EnumWorks = $false
$c = @(Invoke-KiemTra 6>$null)[-1]
Check 'kiem-tra không đọc được BCD (Admin): mã 1' ($c -eq 1)

Clear-TestRegistry
Complete-Test
