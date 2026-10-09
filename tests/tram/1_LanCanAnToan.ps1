# Kiểm thử đơn vị lan can an toàn của Trạm (hub\lib\AnToan.ps1, Catalog, Launcher). Quyền thường; chỉ đọc trạng thái
# máy (System Protection, winget, dịch vụ SysMain, HKLM CurrentBuild), chỉ ghi khoá HKCU\Software\TramToolTest rồi xoá.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\Catalog.ps1"; . "$HubDir\lib\AnToan.ps1"; . "$HubDir\lib\Launcher.ps1"
$tmp = New-TestDir 'tmp'

"== Format-ExitCode"
Check 'exit 0' ((Format-ExitCode 0) -eq '0')
Check 'exit 3' ((Format-ExitCode 3) -eq '3')
Check 'exit 1223' ((Format-ExitCode 1223) -eq '1223')
Check 'exit âm' ((Format-ExitCode -1978335217) -eq '0x8A15000F') (Format-ExitCode -1978335217)
Check 'exit uint' ((Format-ExitCode 2316632079) -eq '0x8A15000F') (Format-ExitCode 2316632079)
Check 'exit null' ((Format-ExitCode $null) -eq '?')

"== Tên file trạng thái"
$n = Get-SnapshotFileName '2026-10-05T10:32:11.123+07:00'
Check 'tên' ($n -eq 'TrangThai_20261005103211123.json') $n
Check 'tên hợp lệ' (Test-SnapshotFileName $n)
Check 'tên lạ bị chặn' (-not (Test-SnapshotFileName '..\TrangThai_20261005103211123.json'))
Check 'tên ngắn bị chặn' (-not (Test-SnapshotFileName 'TrangThai_123.json'))

"== Get-RestoreStatus (chỉ đọc)"
$rs = Get-RestoreStatus
$rs | ConvertTo-Json -Compress
Check 'có enabled' ($rs.Contains('enabled'))

"== Get-WingetStatus (chỉ đọc)"
$sw = [Diagnostics.Stopwatch]::StartNew()
$ws = Get-WingetStatus
$ws | ConvertTo-Json -Compress
"  ($([int]$sw.Elapsed.TotalMilliseconds) ms)"
Check 'Get-WingetStatus trả đủ trường' ($ws.Contains('ok') -and $ws.Contains('stage') -and $ws.Contains('problem'))
Check 'winget: ok thì không có bước hỏng, hỏng thì có lời giải thích' ((($ws.ok -and $ws.stage -eq '') -or (-not $ws.ok -and $ws.problem))) $ws.problem

"== Test-DryRunSelected"
$act = [pscustomobject]@{ args = @([pscustomobject]@{ id = 'chay-thu'; type = 'bool'; dryRun = $true }, [pscustomobject]@{ id = 'x'; type = 'text'; dryRun = $false }) }
Check 'chọn chạy thử' (Test-DryRunSelected -Action $act -Values ([pscustomobject]@{ 'chay-thu' = $true }))
Check 'không chọn' (-not (Test-DryRunSelected -Action $act -Values ([pscustomobject]@{ 'chay-thu' = $false })))
Check 'không có giá trị' (-not (Test-DryRunSelected -Action $act -Values $null))

"== Catalog: restorePoint, dryRun"
$td = Join-Path $tmp 'tools\thu-cat'
New-Item -ItemType Directory $td -Force | Out-Null
foreach ($f in 'a.bat', 'b.ps1', 'c.bat', 'd.bat', 'e.bat', 'f.txt') { Set-Content (Join-Path $td $f) 'echo' }
@'
{
  "id": "thu-cat", "name": "Thử", "category": "tien-ich", "summary": "Thử",
  "actions": [
    { "id": "admin-doi", "label": "A", "file": "a.bat", "admin": true, "risk": "modifies-system",
      "args": [ { "id": "chay-thu", "type": "bool", "flag": "-ChayThu" }, { "id": "thu-khac", "type": "bool", "flag": "-X", "dryRun": true }, { "id": "k", "type": "bool", "flag": "-K" } ] },
    { "id": "admin-ps1-hoi", "label": "B", "file": "b.ps1", "admin": true, "risk": "asks-before-change" },
    { "id": "admin-ps1-hoi-co-rp", "label": "B2", "file": "b.ps1", "admin": true, "risk": "asks-before-change", "restorePoint": true },
    { "id": "admin-doc", "label": "C", "file": "c.bat", "admin": true, "risk": "read-only" },
    { "id": "thuong-co-rp", "label": "D", "file": "d.bat", "risk": "modifies-system", "restorePoint": true },
    { "id": "admin-tat-rp", "label": "E", "file": "e.bat", "admin": true, "risk": "modifies-system", "restorePoint": false },
    { "id": "mo-file", "label": "F", "type": "open", "file": "f.txt", "admin": true }
  ]
}
'@ | Set-Content (Join-Path $td 'tool.json') -Encoding UTF8
$cat = @(Get-HubCatalog -ToolsDir (Join-Path $tmp 'tools') -RootDir $tmp)
$t = $cat[0]
$rp = @{}; foreach ($a in $t.actions) { $rp[$a.id] = $a.restorePoint }
Check 'admin đổi máy -> có' ($rp['admin-doi'] -eq $true)
Check 'admin hỏi trước -> không (mặc định)' ($rp['admin-ps1-hoi'] -eq $false)
Check 'admin hỏi trước + restorePoint:true -> có' ($rp['admin-ps1-hoi-co-rp'] -eq $true)
Check 'admin chỉ đọc -> không' ($rp['admin-doc'] -eq $false)
Check 'thường + restorePoint:true -> không' ($rp['thuong-co-rp'] -eq $false)
Check 'admin tắt -> không' ($rp['admin-tat-rp'] -eq $false)
Check 'open -> không' ($rp['mo-file'] -eq $false)
Check 'báo lỗi restorePoint sai chỗ' (@($t.problems | Where-Object { $_ -match "thuong-co-rp" -and $_ -match 'restorePoint' }).Count -eq 1) ($t.problems -join ' | ')
$args0 = @(($t.actions | Where-Object { $_.id -eq 'admin-doi' }).args)
Check 'chay-thu -> dryRun' ($args0[0].dryRun -eq $true)
Check 'dryRun khai báo' ($args0[1].dryRun -eq $true)
Check 'bool khác -> không' ($args0[2].dryRun -eq $false)

"== Get-LaunchCommand"
$rpi = @{ Script = 'D:\Repo\Tool_Win\hub\safety\TaoDiemKhoiPhuc.ps1'; Tool = 'cong-cu'; Action = 'sua'; RunTime = '2026-10-05T10:32:11.123+07:00'; Log = 'D:\Repo\Tool_Win\hub\data\restore-points.jsonl' }
$argv = @([pscustomobject]@{ Value = '-ChayThu'; IsFlag = $true }, [pscustomobject]@{ Value = "D:\Thư mục (x86)\a b"; IsFlag = $false })
$c1 = Get-LaunchCommand -File 'D:\Tools\x\chay.bat' -Arguments $argv -KeepOpen $false -RestorePoint $rpi
"  bat+rp: $($c1.Exe) $($c1.Args)"
Check 'bat: rp && ( ... )' ($c1.Args -match '^/s /c "powershell\.exe .*-Log "[^"]+" && \(cd /d "D:\\Tools\\x" && "D:\\Tools\\x\\chay\.bat" "-ChayThu" "D:\\Thư mục \(x86\)\\a b" \)"$')
$c2 = Get-LaunchCommand -File 'D:\Tools\x\chay.bat' -Arguments @() -KeepOpen $true -RestorePoint $rpi
"  bat+rp+keep: $($c2.Args)"
Check 'bat keepOpen nằm trong khối' ($c2.Args -match '&& \(cd /d .* & pause >nul \)"$')
$c3 = Get-LaunchCommand -File 'D:\Tools\x\chay.ps1' -Arguments $argv -KeepOpen $false -RestorePoint $rpi
"  ps1+rp: $($c3.Args)"
Check 'ps1: rp trước, 1223 thoát' ($c3.Args -match "^-NoProfile -ExecutionPolicy Bypass -Command `"& 'D:\\Repo\\Tool_Win\\hub\\safety\\TaoDiemKhoiPhuc\.ps1' -Tool 'cong-cu' .*; if \(\`$LASTEXITCODE -eq 1223\) \{ exit 1223 \}; Set-Location")
$c4 = Get-LaunchCommand -File 'D:\Tools\x\chay.bat' -Arguments @() -KeepOpen $false
Check 'bat không rp như cũ' ($c4.Args -eq '/s /c "cd /d "D:\Tools\x" && "D:\Tools\x\chay.bat""') $c4.Args
$bad = $rpi.Clone(); $bad.Tool = 'a"b'
try { [void](Get-LaunchCommand -File 'D:\Tools\x\chay.bat' -Arguments @() -KeepOpen $false -RestorePoint $bad); Check 'chặn " trong rp' $false } catch { Check 'chặn " trong rp' $true }

"== Registry: ghi lại đủ kiểu rồi trả lại (khoá HKCU thử)"
$k = 'HKCU:\Software\TramToolTest\AnToan'
try {
    New-Item $k -Force | Out-Null
    New-ItemProperty $k -Name 'dw' -Value 0xFFFFFFFE -PropertyType DWord | Out-Null   # âm khi đọc
    New-ItemProperty $k -Name 'qw' -Value ([int64]9007199254740993) -PropertyType QWord | Out-Null
    New-ItemProperty $k -Name 'sz' -Value 'Chữ "có" dấu' -PropertyType String | Out-Null
    New-ItemProperty $k -Name 'ex' -Value '%SystemRoot%\x' -PropertyType ExpandString | Out-Null
    New-ItemProperty $k -Name 'ms' -Value ([string[]]@('một', 'hai')) -PropertyType MultiString | Out-Null
    New-ItemProperty $k -Name 'ms1' -Value ([string[]]@('một')) -PropertyType MultiString | Out-Null
    New-ItemProperty $k -Name 'bin' -Value ([byte[]](0, 1, 254, 255)) -PropertyType Binary | Out-Null
    foreach ($name in 'dw', 'qw', 'sz', 'ex', 'ms', 'ms1', 'bin', 'khongco') {
        $s = Get-RegistryValueState $k $name
        # Qua JSON như file trạng thái thật
        $j = (ConvertTo-HubJson ([ordered]@{ state = $s })) | ConvertFrom-Json
        $back = $j.state
        if ($back.exists) {
            New-ItemProperty $k -Name "$name-2" -Value (ConvertFrom-StateValue $back.value $back.kind) -PropertyType $back.kind -Force | Out-Null
            $s2 = Get-RegistryValueState $k "$name-2"
            Check "kiểu $name ($($s.kind))" ((Test-RegistryStateEqual $back $s2) -and (Test-RegistryStateEqual $s $s2)) "$($s | ConvertTo-Json -Compress) / $($s2 | ConvertTo-Json -Compress)"
        } else {
            Check "chưa có $name" (-not $s.exists -and $s.keyExists)
        }
    }
    $s = Get-RegistryValueState $k 'ex'
    Check 'ExpandString không bị mở rộng' ($s.value -eq '%SystemRoot%\x') $s.value
    Check 'khác kiểu là khác' (-not (Test-RegistryStateEqual (Get-RegistryValueState $k 'dw') (Get-RegistryValueState $k 'qw')))
    Check 'khoá không có' (-not (Get-RegistryValueState 'HKCU:\Software\TramToolKhongCo' 'x').keyExists)
    "  Format: " + (Format-RegistryState (Get-RegistryValueState $k 'dw') ([pscustomobject]@{ '-2' = 'Giá trị âm' })) + ' | ' + (Format-RegistryState (Get-RegistryValueState $k 'bin') $null) + ' | ' + (Format-RegistryState (Get-RegistryValueState $k 'ms') $null)
} finally { Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue }
Check 'đã xoá khoá thử' (-not (Test-Path $k))

"== Ghi trạng thái và so sánh (dịch vụ, registry HKLM chỉ đọc)"
$tool = [pscustomobject]@{ id = 'thu'; name = 'Thử'; probes = @(
        [pscustomobject]@{ type = 'service'; name = 'SysMain'; label = 'SysMain' },
        [pscustomobject]@{ type = 'service'; name = 'TramToolKhongCo'; label = 'Dịch vụ không có' },
        [pscustomobject]@{ type = 'registry'; path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; name = 'CurrentBuild'; label = 'Build' },
        [pscustomobject]@{ type = 'registry'; path = 'HKCU:\Software\X'; name = 'Y'; label = 'HKCU bị bỏ' },
        [pscustomobject]@{ type = 'command'; name = 'x' }) }
$action = [pscustomobject]@{ id = 'sua'; label = 'Sửa' }
$snapDir = Join-Path $tmp 'snapshots'
$name = New-RunSnapshot -Tool $tool -Action $action -RunTime '2026-10-05T10:32:11.123+07:00' -Dir $snapDir
Check 'tạo file trạng thái' ($name -eq 'TrangThai_20261005103211123.json') $name
$path = Join-Path $snapDir $name
$snap = Read-JsonFile $path
Check 'ghi 3 mục (bỏ HKCU, kiểu lạ)' (@($snap.items).Count -eq 3) (@($snap.items).Count)
$rows = @(Compare-RunSnapshot -Path $path)
Check 'không mục nào đổi' (@($rows | Where-Object { $_.changed }).Count -eq 0) ($rows | ConvertTo-Json -Compress)
# Giả lập máy đã đổi: sửa trạng thái "trước" trong file
$svc = $snap.items[0].state
$svc.start = if ($svc.start -eq 4) { 3 } else { 4 }
$snap.items[1].state.exists = $true; $snap.items[1].state.start = 3
$snap.items[2].state.exists = $false; $snap.items[2].state.kind = $null; $snap.items[2].state.value = $null
Write-JsonFile -Path $path -InputObject $snap
$rows = @(Compare-RunSnapshot -Path $path)
foreach ($r in $rows) { '  {0} | {1} | {2} -> {3} | đổi={4} trả lại={5} {6}' -f $r.label, $r.target, $r.before, $r.after, $r.changed, $r.restorable, $r.note }
Check 'SysMain đã đổi, trả lại được' ($rows[0].changed -and $rows[0].restorable)
Check 'dịch vụ mất: không trả lại được' ($rows[1].changed -and -not $rows[1].restorable -and $rows[1].note)
Check 'registry trước chưa có: trả lại (xoá)' ($rows[2].changed -and $rows[2].restorable -and $rows[2].before -match 'Chưa đặt')
Check 'không có trạng thái thì không tạo file' ((New-RunSnapshot -Tool ([pscustomobject]@{ id = 'x'; name = 'x'; probes = @() }) -Action $action -RunTime '2026-10-05T10:32:12.000+07:00' -Dir $snapDir) -eq '')

"== Restore-SnapshotItem (giả lập sc.exe, registry)"
$script:calls = New-Object System.Collections.ArrayList
$script:svcState = @{ exists = $true; start = 4; delayed = 0 }
function Get-ServiceStartState { param([string]$Name) if ($Name -eq 'Mat') { return @{ exists = $false; start = $null; delayed = 0 } }; return $script:svcState.Clone() }
function sc.exe {
    [void]$script:calls.Add(($args -join ' '))
    $mode = $args[3]
    switch ($mode) { 'auto' { $script:svcState.start = 2; $script:svcState.delayed = 0 } 'delayed-auto' { $script:svcState.start = 2; $script:svcState.delayed = 1 } 'demand' { $script:svcState.start = 3 } 'disabled' { $script:svcState.start = 4 } }
    $global:LASTEXITCODE = 0
}
$item = [pscustomobject]@{ type = 'service'; name = 'SysMain'; state = [pscustomobject]@{ exists = $true; start = 2; delayed = 1 } }
$r = Restore-SnapshotItem -Item $item
Check 'dịch vụ -> delayed-auto' ($r -eq 'ok' -and $script:calls[-1] -eq 'config SysMain start= delayed-auto') ($script:calls -join ' / ')
Check 'lần hai: đã như trước' ((Restore-SnapshotItem -Item $item) -eq 'same')
$item.state.delayed = 0
[void](Restore-SnapshotItem -Item $item)
Check 'dịch vụ -> auto' ($script:calls[-1] -eq 'config SysMain start= auto' -and $script:svcState.delayed -eq 0)
function sc.exe { [void]$script:calls.Add(($args -join ' ')); $global:LASTEXITCODE = 5 }
$item.state.start = 3
try { [void](Restore-SnapshotItem -Item $item); Check 'sc báo 5 -> lỗi' $false } catch { Check 'sc báo 5 -> lỗi' ($_.Exception.Message -match 'mã 5') $_.Exception.Message }
function sc.exe { [void]$script:calls.Add(($args -join ' ')); $global:LASTEXITCODE = 0 }   # báo xong mà không đổi
try { [void](Restore-SnapshotItem -Item $item); Check 'sc báo xong mà không đổi -> lỗi' $false } catch { Check 'sc báo xong mà không đổi -> lỗi' ($_.Exception.Message -match 'vẫn là') $_.Exception.Message }
try { [void](Restore-SnapshotItem -Item ([pscustomobject]@{ type = 'service'; name = 'Mat'; state = [pscustomobject]@{ exists = $true; start = 3; delayed = 0 } })); Check 'dịch vụ mất -> lỗi' $false } catch { Check 'dịch vụ mất -> lỗi' $true }
try { [void](Restore-SnapshotItem -Item ([pscustomobject]@{ type = 'registry'; path = 'HKCU:\Software\X'; name = 'Y'; state = [pscustomobject]@{ exists = $false } })); Check 'HKCU -> từ chối' $false } catch { Check 'HKCU -> từ chối' $true }
# Registry HKLM: giả lập lệnh ghi
$script:reg = @{ exists = $true; keyExists = $true; kind = 'DWord'; value = 1 }
function Get-RegistryValueState { param($Path, $Name) return [pscustomobject]$script:reg }
function New-ItemProperty { param($LiteralPath, $Name, $Value, $PropertyType, [switch]$Force, $ErrorAction) [void]$script:calls.Add("set $LiteralPath\$Name=$Value ($PropertyType)"); return $null }
function Remove-ItemProperty { param($LiteralPath, $Name, $ErrorAction) [void]$script:calls.Add("del $LiteralPath\$Name") }
$ri = [pscustomobject]@{ type = 'registry'; path = 'HKLM:\SOFTWARE\Microsoft'; name = 'TramToolThu'; state = [pscustomobject]@{ exists = $false; keyExists = $true; kind = $null; value = $null } }
Check 'registry trước chưa có -> xoá' ((Restore-SnapshotItem -Item $ri) -eq 'ok' -and $script:calls[-1] -eq 'del HKLM:\SOFTWARE\Microsoft\TramToolThu') $script:calls[-1]
$ri.state = [pscustomobject]@{ exists = $true; keyExists = $true; kind = 'DWord'; value = 0 }
Check 'registry trả giá trị cũ' ((Restore-SnapshotItem -Item $ri) -eq 'ok' -and $script:calls[-1] -eq 'set HKLM:\SOFTWARE\Microsoft\TramToolThu=0 (DWord)') $script:calls[-1]
$ri.state = [pscustomobject]@{ exists = $true; keyExists = $true; kind = 'DWord'; value = 1 }
Check 'registry như cũ -> same' ((Restore-SnapshotItem -Item $ri) -eq 'same')

Clear-TestRegistry
Complete-Test
