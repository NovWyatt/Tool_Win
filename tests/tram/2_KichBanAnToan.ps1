# Chạy các script hub\safety, hub\fixes\Sua-Winget.ps1 với hàm giả lập (quyền thường, không đổi gì trên máy).
# Bản sao hub\lib\AnToan.ps1 được nối thêm _GiaLapAnToan.ps1 (hàm giả: quyền Admin, System Protection, điểm khôi phục,
# trả lại trạng thái, winget, câu trả lời), nên không script nào tạo điểm khôi phục hay đổi dịch vụ thật.
param([switch]$Verbose2)
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$Hub = $HubDir
$M = Join-Path $TestRoot 'mock'
foreach ($d in 'lib', 'safety', 'fixes', 'data', 'tool (thử) công cụ') { New-Item -ItemType Directory (Join-Path $M $d) -Force | Out-Null }
$bom = New-Object Text.UTF8Encoding($true)
[IO.File]::WriteAllText("$M\lib\Common.ps1", [IO.File]::ReadAllText("$Hub\lib\Common.ps1"), $bom)
[IO.File]::WriteAllText("$M\lib\AnToan.ps1", [IO.File]::ReadAllText("$Hub\lib\AnToan.ps1") + "`r`n" + [IO.File]::ReadAllText("$PSScriptRoot\_GiaLapAnToan.ps1"), $bom)
Copy-Item "$Hub\safety\*.ps1" "$M\safety\"
Copy-Item "$Hub\fixes\Sua-Winget.ps1" "$M\fixes\"
$Log = "$M\data\restore-points.jsonl"

function Invoke-Scenario {
    param([string]$Name, [string]$Script, [string[]]$ScriptArgs = @(), [hashtable]$Env = @{}, [int]$Expect, [scriptblock]$Check = $null)
    $keys = 'MOCK_ADMIN', 'MOCK_RS', 'MOCK_RP', 'MOCK_ENABLE', 'MOCK_ANSWERS', 'MOCK_WG'
    foreach ($k in $keys) { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
    foreach ($k in $Env.Keys) { Set-Item "env:$k" $Env[$k] }
    if (Test-Path $Log) { Remove-Item $Log }
    $ErrorActionPreference = 'Continue'
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script @ScriptArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    foreach ($k in $keys) { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
    $logObj = if (Test-Path $Log) { @(Get-Content $Log -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json }) } else { @() }
    $ok = ($code -eq $Expect)
    $why = ''
    if ($ok -and $Check) { $why = & $Check $logObj $out; if ($why) { $ok = $false } }
    Check "[$code] $Name" $ok "chờ $Expect $why"
    if (-not $ok -or $Verbose2) { ($out -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { "      | $_" }) -join "`n" }
}

$rp = "$M\safety\TaoDiemKhoiPhuc.ps1"
$rpArgs = @('-Tool', 'cong-cu', '-Action', 'sua', '-RunTime', '2026-10-05T10:32:11.123+07:00', '-Log', $Log)
$reason = { param($want) { param($l, $o) if (@($l).Count -ne 1) { return "log có $(@($l).Count) dòng" }; if ($l[0].reason -ne $want) { return "reason=$($l[0].reason)" }; if ($l[0].time -ne '2026-10-05T10:32:11.123+07:00' -or $l[0].toolId -ne 'cong-cu') { return 'thiếu time/toolId' } }.GetNewClosure() }

"== TaoDiemKhoiPhuc.ps1"
Invoke-Scenario 'không Admin -> chạy tiếp' $rp $rpArgs @{ MOCK_ADMIN = '0' } 0 (& $reason 'not-admin')
Invoke-Scenario 'đang bật, tạo được' $rp $rpArgs @{ MOCK_RS = 'on'; MOCK_RP = 'ok' } 0 { param($l, $o) if (-not $l[0].created -or $l[0].seq -ne 42 -or -not $l[0].pointAt) { 'log sai' } }
Invoke-Scenario 'đang bật, lỗi, chọn Huỷ' $rp $rpArgs @{ MOCK_RS = 'on'; MOCK_RP = 'fail'; MOCK_ANSWERS = 'H' } 1223 (& $reason 'cancelled')
Invoke-Scenario 'đang bật, lỗi, chọn Chạy tiếp' $rp $rpArgs @{ MOCK_RS = 'on'; MOCK_RP = 'fail'; MOCK_ANSWERS = 'C' } 0 { param($l, $o) if ($l[0].reason -ne 'error' -or $l[0].message -notmatch '0x81000101') { 'log sai' } elseif ($o -notmatch '1 GB') { 'thiếu gợi ý' } }
Invoke-Scenario 'tắt, Bật rồi tạo' $rp $rpArgs @{ MOCK_RS = 'off'; MOCK_RP = 'ok'; MOCK_ANSWERS = 'B' } 0 { param($l, $o) if (-not $l[0].created) { 'chưa tạo' } elseif ($o -notmatch 'Enable-ComputerRestore') { 'chưa bật' } }
Invoke-Scenario 'tắt, Chạy tiếp không tạo' $rp $rpArgs @{ MOCK_RS = 'off'; MOCK_ANSWERS = 'C' } 0 (& $reason 'disabled')
Invoke-Scenario 'tắt, Huỷ' $rp $rpArgs @{ MOCK_RS = 'off'; MOCK_ANSWERS = 'H' } 1223 (& $reason 'cancelled')
Invoke-Scenario 'tắt, gõ sai rồi Huỷ' $rp $rpArgs @{ MOCK_RS = 'off'; MOCK_ANSWERS = 'X,,Y,H' } 1223 (& $reason 'cancelled')
Invoke-Scenario 'tắt, không trả lời -> Huỷ' $rp $rpArgs @{ MOCK_RS = 'off'; MOCK_ANSWERS = '' } 1223 (& $reason 'cancelled')
Invoke-Scenario 'chính sách tắt, Chạy tiếp' $rp $rpArgs @{ MOCK_RS = 'policy'; MOCK_ANSWERS = 'C' } 0 (& $reason 'policy')
Invoke-Scenario 'VSS tắt, Huỷ' $rp $rpArgs @{ MOCK_RS = 'vss'; MOCK_ANSWERS = 'H' } 1223 (& $reason 'cancelled')
Invoke-Scenario 'tắt + bị khoá, Chạy tiếp' $rp $rpArgs @{ MOCK_RS = 'locked'; MOCK_ANSWERS = 'C' } 0 (& $reason 'policy')
Invoke-Scenario 'tắt, Bật lỗi, Chạy tiếp' $rp $rpArgs @{ MOCK_RS = 'off'; MOCK_ENABLE = 'fail'; MOCK_ANSWERS = 'B,C' } 0 { param($l, $o) if ($l[0].reason -ne 'error' -or $l[0].message -notmatch '0x80070422') { 'log sai' } }
Invoke-Scenario 'lỗi bất ngờ, Chạy tiếp' $rp $rpArgs @{ MOCK_RS = 'on'; MOCK_RP = 'throw'; MOCK_ANSWERS = 'C' } 0 { param($l, $o) if ($l[0].reason -ne 'error' -or $l[0].message -notmatch 'bất ngờ') { 'log sai' } }
Invoke-Scenario 'không có -Log vẫn chạy' $rp @('-Tool', 'a', '-Action', 'b', '-RunTime', 'x') @{ MOCK_RS = 'on'; MOCK_RP = 'ok' } 0 { param($l, $o) if (Test-Path $Log) { 'không được ghi log' } }

"== Ghép với công cụ (cmd/powershell như trạm gọi, không nâng quyền)"
. "$Hub\lib\Common.ps1"; . "$Hub\lib\Launcher.ps1"
$toolDir = Join-Path $M 'tool (thử) công cụ'
Set-Content "$toolDir\chay.bat" "@echo off`r`necho %* > `"%~dp0da-chay.txt`"`r`nexit /b 3`r`n" -Encoding ASCII
[IO.File]::WriteAllText("$toolDir\chay.ps1", "param([switch]`$ChayThu, [string]`$Duong)`r`nSet-Content -LiteralPath (Join-Path `$PSScriptRoot 'da-chay.txt') -Value `"ChayThu=`$ChayThu Duong=`$Duong`" -Encoding UTF8`r`nexit 3`r`n", $bom)
$rpInfo = @{ Script = $rp; Tool = 'cong-cu'; Action = 'sua'; RunTime = '2026-10-05T10:32:11.123+07:00'; Log = $Log }
$argv = @([pscustomobject]@{ Value = '-ChayThu'; IsFlag = $true }, [pscustomobject]@{ Value = 'D:\Thư mục (x86)\a b'; IsFlag = $false })
function Invoke-Launch {
    param([string]$Name, [string]$File, [hashtable]$Env, [int]$Expect, [bool]$ExpectRan, [bool]$KeepOpen = $false)
    $marker = Join-Path $toolDir 'da-chay.txt'
    if (Test-Path $marker) { Remove-Item $marker }
    if (Test-Path $Log) { Remove-Item $Log }
    foreach ($k in $Env.Keys) { Set-Item "env:$k" $Env[$k] }
    $cmd = Get-LaunchCommand -File $File -Arguments $argv -KeepOpen $KeepOpen -RestorePoint $rpInfo
    $p = Start-Process -FilePath $cmd.Exe -ArgumentList $cmd.Args -WorkingDirectory $cmd.WorkDir -WindowStyle Hidden -PassThru
    if (-not $p.WaitForExit(60000)) { $p.Kill(); Check "$Name (treo)" $false; return }
    foreach ($k in $Env.Keys) { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
    $ran = Test-Path $marker
    $content = if ($ran) { (Get-Content $marker -Encoding UTF8 -Raw).Trim() } else { '' }
    Check "[$($p.ExitCode)] $Name $(if ($ran) { "-> $content" })" ($p.ExitCode -eq $Expect -and $ran -eq $ExpectRan) "chờ $Expect, ran=$ran"
}
Invoke-Launch '.bat: Huỷ ở bước điểm khôi phục -> công cụ không chạy' "$toolDir\chay.bat" @{ MOCK_RS = 'on'; MOCK_RP = 'fail'; MOCK_ANSWERS = 'H' } 1223 $false
Invoke-Launch '.bat: tạo được -> công cụ chạy, giữ mã 3' "$toolDir\chay.bat" @{ MOCK_RS = 'on'; MOCK_RP = 'ok' } 3 $true
Invoke-Launch '.bat keepOpen: Huỷ -> không pause, 1223' "$toolDir\chay.bat" @{ MOCK_RS = 'off'; MOCK_ANSWERS = 'H' } 1223 $false $true
Invoke-Launch '.ps1: Huỷ -> công cụ không chạy' "$toolDir\chay.ps1" @{ MOCK_RS = 'off'; MOCK_ANSWERS = 'H' } 1223 $false
Invoke-Launch '.ps1: chạy tiếp không tạo -> công cụ chạy, giữ mã 3' "$toolDir\chay.ps1" @{ MOCK_RS = 'off'; MOCK_ANSWERS = 'C' } 3 $true

"== TraLaiTrangThai.ps1"
$tl = "$M\safety\TraLaiTrangThai.ps1"
$snapDir = "$M\data\snapshots"
New-Item -ItemType Directory $snapDir -Force | Out-Null
. "$Hub\lib\AnToan.ps1"
$svc = Get-ServiceStartState 'SysMain'
$build = Get-RegistryValueState 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'CurrentBuild'
$changedSvc = [ordered]@{ exists = $true; start = $(if ($svc.start -eq 4) { 3 } else { 4 }); delayed = 0 }
$snapChanged = [ordered]@{ version = 1; time = '2026-10-05T10:32:11.123+07:00'; toolId = 'cong-cu'; toolName = 'Công cụ'; actionId = 'sua'; actionLabel = 'Sửa'; items = @(
        [ordered]@{ type = 'service'; name = 'SysMain'; label = 'SysMain'; state = $changedSvc },
        [ordered]@{ type = 'service'; name = 'TramToolKhongCo'; label = 'Mất'; state = [ordered]@{ exists = $true; start = 3; delayed = 0 } },
        [ordered]@{ type = 'registry'; path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; name = 'CurrentBuild'; label = 'Build loi'; values = $null; state = [ordered]@{ keyExists = $true; exists = $false; kind = $null; value = $null } }) }
Write-JsonFile -Path "$snapDir\TrangThai_20261005103211123.json" -InputObject $snapChanged
$snapSame = [ordered]@{ version = 1; time = '2026-10-05T10:40:00.000+07:00'; toolId = 'cong-cu'; toolName = 'Công cụ'; actionId = 'sua'; actionLabel = 'Sửa'; items = @(
        [ordered]@{ type = 'service'; name = 'SysMain'; label = 'SysMain'; state = $svc },
        [ordered]@{ type = 'registry'; path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; name = 'CurrentBuild'; label = 'Build'; values = $null; state = $build }) }
Write-JsonFile -Path "$snapDir\TrangThai_20261005104000000.json" -InputObject $snapSame
$snapOk = [ordered]@{ version = 1; time = '2026-10-05T10:50:00.000+07:00'; toolId = 'cong-cu'; toolName = 'Công cụ'; actionId = 'sua'; actionLabel = 'Sửa'; items = @(
        [ordered]@{ type = 'service'; name = 'SysMain'; label = 'SysMain'; state = $changedSvc }) }
Write-JsonFile -Path "$snapDir\TrangThai_20261005105000000.json" -InputObject $snapOk
Invoke-Scenario 'không Admin -> 2' $tl @('-Snapshot', "$snapDir\TrangThai_20261005103211123.json") @{ MOCK_ADMIN = '0' } 2
Invoke-Scenario 'không có file -> 1' $tl @('-Snapshot', "$snapDir\TrangThai_20990101000000000.json") @{} 1
Invoke-Scenario 'tên file lạ -> 1' $tl @('-Snapshot', "$Hub\..\README.md") @{} 1
Invoke-Scenario 'một phần (1 được, 1 lỗi, 1 không trả được) -> 3' $tl @('-Snapshot', "$snapDir\TrangThai_20261005103211123.json") @{} 3 { param($l, $o) if ($o -notmatch 'trả lại SysMain' -or $o -notmatch 'Build loi.*lỗi' -or $o -notmatch 'Mất.*bỏ qua') { 'thiếu dòng' } }
Invoke-Scenario 'không gì khác -> 0' $tl @('-Snapshot', "$snapDir\TrangThai_20261005104000000.json") @{} 0 { param($l, $o) if ($o -notmatch 'không có gì để trả lại') { 'thiếu câu' } }
Invoke-Scenario 'trả lại hết -> 0' $tl @('-Snapshot', "$snapDir\TrangThai_20261005105000000.json") @{} 0 { param($l, $o) if ($o -notmatch 'Đã trả lại 1 mục') { 'thiếu câu' } }

"== BatBaoVeHeThong.ps1"
$bb = "$M\safety\BatBaoVeHeThong.ps1"
Invoke-Scenario 'không Admin -> 2' $bb @() @{ MOCK_ADMIN = '0' } 2
Invoke-Scenario 'chính sách chặn -> 2' $bb @() @{ MOCK_RS = 'policy' } 2
Invoke-Scenario 'VSS tắt -> 2' $bb @() @{ MOCK_RS = 'vss' } 2
Invoke-Scenario 'đang bật, Đóng -> 0' $bb @() @{ MOCK_RS = 'on'; MOCK_ANSWERS = 'D' } 0 { param($l, $o) if ($o -match 'Checkpoint') { 'không được tạo điểm' } }
Invoke-Scenario 'đang bật, Tạo ngay -> 0' $bb @() @{ MOCK_RS = 'on'; MOCK_ANSWERS = 'T'; MOCK_RP = 'ok' } 0 { param($l, $o) if ($o -notmatch 'Đã tạo điểm khôi phục') { 'chưa tạo' } }
Invoke-Scenario 'tắt, Huỷ -> 1223' $bb @() @{ MOCK_RS = 'off'; MOCK_ANSWERS = 'H' } 1223 { param($l, $o) if ($o -match 'Enable-ComputerRestore') { 'không được bật' } }
Invoke-Scenario 'tắt, Bật + tạo -> 0' $bb @() @{ MOCK_RS = 'off'; MOCK_ANSWERS = 'B'; MOCK_RP = 'ok' } 0
Invoke-Scenario 'tắt, Bật lỗi -> 1' $bb @() @{ MOCK_RS = 'off'; MOCK_ANSWERS = 'B'; MOCK_ENABLE = 'fail' } 1
Invoke-Scenario 'tắt, Bật được, tạo lỗi -> 1' $bb @() @{ MOCK_RS = 'off'; MOCK_ANSWERS = 'B'; MOCK_RP = 'fail' } 1 { param($l, $o) if ($o -notmatch '1 GB') { 'thiếu gợi ý' } }

"== Sua-Winget.ps1"
$sw = "$M\fixes\Sua-Winget.ps1"
Invoke-Scenario 'dùng được, bỏ qua cập nhật -> 0' $sw @() @{ MOCK_WG = 'ok'; MOCK_ANSWERS = 'B' } 0
Invoke-Scenario 'chưa đăng ký, đăng ký lại được -> 0' $sw @() @{ MOCK_WG = 'install,ok'; MOCK_ANSWERS = 'C' } 0 { param($l, $o) if ($o -notmatch 'Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe') { 'chưa gọi đăng ký' } }
Invoke-Scenario 'chạy lỗi, bỏ qua hết -> 1' $sw @() @{ MOCK_WG = 'run'; MOCK_ANSWERS = 'B,B,B' } 1 { param($l, $o) if ($o -match 'Bước 2') { 'không được hỏi bước 2 (nguồn)' } elseif ($o -notmatch 'Bước 3' -or $o -notmatch 'Microsoft Store') { 'thiếu bước' } }
Invoke-Scenario 'lỗi nguồn, bỏ qua hết -> 1' $sw @() @{ MOCK_WG = 'source'; MOCK_ANSWERS = 'B,B,B,B' } 1 { param($l, $o) if ($o -match 'Bước 1') { 'không được hỏi bước 1' } elseif ($o -notmatch 'source reset') { 'thiếu bước đặt lại nguồn' } }
Invoke-Scenario 'Dừng ở bước đầu -> 1223' $sw @() @{ MOCK_WG = 'install'; MOCK_ANSWERS = 'D' } 1223

Complete-Test
