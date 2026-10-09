# Bảng mã lỗi, giải thích, tách đường dẫn UNC, tên máy, tên máy in bản sao của tools\may-in-lan. Không gọi mạng.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
. "$PSScriptRoot\_Nap.ps1"

Write-Host '== mã lỗi'
try { throw (New-Object ComponentModel.Win32Exception(1326)) } catch { $c = Get-ErrorCode $_ }
Check ($c -eq 1326) "Win32Exception 1326 -> $c"
$want = [ordered]@{ '-2147024891' = '5|5 (0x00000005)'; '2148073478' = '2148073478|0x80090006'; '-1073700864' = '3221266432|0xC000A000'
    '3227320323' = '3227320323|0xC05D0003'; '-2147024843' = '53|53 (0x00000035)'; '283' = '283|283 (0x0000011B)' }
foreach ($k in $want.Keys) {
    $n = ConvertTo-ErrorCode ([int64]$k)
    $got = "$n|$(Format-ErrorCode $n)"
    Check ($got -eq $want[$k]) "$k -> $got"
}

Write-Host '== giải thích lỗi'
foreach ($p in @(@(283, 'Lỗi mã hoá RPC', 'Nới bảo mật'), @(53, 'Không tìm thấy đường dẫn mạng', 'Bật chia sẻ'), @(3221266432, 'Chữ ký SMB', 'Không bắt buộc ký SMB'))) {
    $script:Report.Clear()
    Write-ErrorHelp $p[0] 6>$null
    $t = $script:Report -join "`n"
    Check ($t -match [regex]::Escape($p[1]) -and $t -match 'Cách xử lý' -and $t -match [regex]::Escape($p[2])) "Write-ErrorHelp $($p[0]): có nghĩa và cách xử lý"
}
$script:Report.Clear()
Write-ErrorHelp 1234 6>$null
Check (($script:Report -join "`n") -match '0x000004D2' -and ($script:Report -join "`n") -notmatch 'Cách xử lý') 'mã chưa có trong bảng: in mã và thông điệp Windows'

Write-Host '== tên máy in bản sao, UNC, tên máy'
Check ((Get-CopyBaseName 'HP LaserJet (Copy 1)' @()) -eq 'HP LaserJet') 'bỏ (Copy 1)'
Check ((Get-CopyBaseName 'Canon (Bản sao 2)' @()) -eq 'Canon') 'bỏ (Bản sao 2)'
Check (-not (Get-CopyBaseName 'Canon (LBP2900)' @()) -and -not (Get-CopyBaseName 'Brother (Tầng 2)' @())) 'ngoặc là tên model, vị trí: không phải bản sao'
Check ((Get-CopyBaseName 'Brother (Tầng 2)' @('Brother')) -eq 'Brother') 'có máy in gốc cùng tên: coi là bản sao'
Check ((Split-UncPath '\\PC-KETOAN\Tai Lieu\Con').Share -eq 'Tai Lieu') 'UNC: tên thư mục chia sẻ có dấu cách'
Check ($null -eq (Split-UncPath '\\PC')) 'UNC thiếu thư mục chia sẻ: không nhận'
Check ((Split-UncPath '//192.168.1.5/share/').Path -eq '\\192.168.1.5\share') 'UNC viết bằng / và / cuối'
Check ((Test-HostName 'PC-KETOAN') -and (Test-HostName '192.168.1.50')) 'tên máy, IP hợp lệ'
Check (-not (Test-HostName 'a b') -and -not (Test-HostName 'x;y')) 'tên máy có dấu cách, dấu ; bị từ chối'

Complete-Test
