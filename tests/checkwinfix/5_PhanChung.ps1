# Phần dùng chung của CheckWinFix (src\Chung.ps1, dựng vào từng .bat bằng src\build.ps1): các .bat đã dựng bản mới
# nhất, mỗi hàm chung chỉ có một định nghĩa (trong khối chung), giải mã SMART chỉ còn ở khối chung; ConvertFrom-SmartVendor
# với bảng byte giả; build.ps1 -Kiem bắt .bat cũ, dựng lại, báo lỗi cú pháp (bản sao trong thư mục tạm).
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$cwf = Join-Path $ToolsDir 'checkwinfix'
$build = Join-Path $cwf 'src\build.ps1'
$ten = 'FLAG', 'Save-KetQua', 'Get-DiskBus', 'Test-QuyenAdmin', 'ConvertFrom-SmartVendor', 'Get-SmartThuocTinh'
$dung = 'ThuThapThongTin.bat', '2-CHAN-DOAN-PHAN-CUNG.bat', '3-GIAI-MA-WHEA.bat', '4-XUAT-BANG-CHUNG.bat', '5-CHAN-DOAN-SUP-NGUON.bat'

Write-KT '1. Các .bat đã dựng phần chung' Cyan
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File $build -Kiem 2>&1
Check ($LASTEXITCODE -eq 0) "src\build.ps1 -Kiem: mọi .bat đã dựng bản mới nhất ($(@($out) -join ' '))"
foreach ($f in $dung) {
    $text = [IO.File]::ReadAllText((Join-Path $cwf $f))
    $ps = $text.Substring($text.IndexOf('#=====PS_START=====') + 19)
    $ast = [Management.Automation.Language.Parser]::ParseInput($ps, [ref]$null, [ref]$null)
    $defs = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $ten }, $true) | ForEach-Object Name)
    $dup = @($defs | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name)
    $i = $text.IndexOf("`n#=====CHUNG_BAT_DAU====="); $j = $text.IndexOf("`n#=====CHUNG_KET_THUC=====")
    $ngoai = $text.Substring(0, [Math]::Max(0, $i)) + $text.Substring([Math]::Max(0, $j))
    Check ($i -gt 0 -and $j -gt $i -and $defs.Count -eq $ten.Count -and -not $dup.Count) "${f}: một khối chung, mỗi hàm chung một định nghĩa ($($defs.Count)$(if ($dup) { ', trùng ' + ($dup -join ',') }))"
    Check ($ngoai -notmatch 'VendorSpecific' -and $ngoai -notmatch '(?m)^\$isAdmin = \(\[Security') "${f}: không còn tự giải mã SMART hay tự kiểm quyền Admin ngoài khối chung"
}
$one = [IO.File]::ReadAllText((Join-Path $cwf '1-CUU-DU-LIEU.bat'))
Check ($one -notmatch 'CHUNG_BAT_DAU') '1-CUU-DU-LIEU.bat (không ghi JSON kết quả) không cần phần chung'

Write-KT '2. ConvertFrom-SmartVendor' Cyan
. (Join-Path $cwf 'src\Chung.ps1')
function O([int[]]$b) { $o = New-Object int[] 12; for ($k = 0; $k -lt $b.Count; $k++) { $o[$k] = $b[$k] }; return $o }
$data = @(0x10, 0) + (O 5, 0, 0, 100, 99, 3) + (O 0) + (O 194, 0, 0, 35, 20, 0x23, 0x01) + (O 250, 0, 0, 1, 1, 255, 255, 255, 255, 255, 255)
$ng = @(0x10, 0) + (O 5, 36) + (O 194, 0)
$a = @(ConvertFrom-SmartVendor -Data ([byte[]]$data) -Nguong ([byte[]]$ng))
Check ($a.Count -eq 3) "bỏ ô ID 0, còn 3 thuộc tính ($($a.Count))"
Check ($a[0].Id -eq 5 -and $a[0].Ten -eq 'Reallocated_Sectors_Count' -and $a[0].Value -eq 100 -and $a[0].Worst -eq 99 -and $a[0].Nguong -eq 36 -and $a[0].Raw -eq 3) "ID 5: tên, Value, Worst, ngưỡng, Raw ($($a[0].Ten) $($a[0].Value)/$($a[0].Worst)/$($a[0].Nguong)/$($a[0].Raw))"
Check ($a[1].Id -eq 194 -and $a[1].Raw -eq 291 -and $a[1].Nguong -eq 0) "Raw 6 byte little-endian (0x0123 = $($a[1].Raw)), ngưỡng 0 vẫn giữ"
Check ($a[2].Ten -eq 'Attr_250' -and $null -eq $a[2].Nguong -and $a[2].Raw -eq [uint64]281474976710655) "ID lạ: Attr_250, không có ngưỡng, Raw tối đa ($($a[2].Raw))"
Check (@(ConvertFrom-SmartVendor -Data ([byte[]](1..13))).Count -eq 0 -and @(ConvertFrom-SmartVendor).Count -eq 0) 'dữ liệu ngắn hoặc rỗng: không có thuộc tính, không lỗi'
$sw = [Diagnostics.Stopwatch]::StartNew()
$err = $null; try { $null = @(Get-SmartThuocTinh) } catch { $err = $_.Exception.Message }
Check (-not $err -and $sw.Elapsed.TotalSeconds -lt 70) "Get-SmartThuocTinh chạy bằng quyền thường không lỗi ($([int]$sw.Elapsed.TotalSeconds) giây)"

Write-KT '3. build.ps1 trên bản sao' Cyan
$tam = Join-Path $TestRoot 'cwf'
New-Item -ItemType Directory -Path (Join-Path $tam 'src') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $cwf 'src\Chung.ps1'), $build -Destination (Join-Path $tam 'src')
Copy-Item -LiteralPath (Join-Path $cwf '3-GIAI-MA-WHEA.bat') -Destination $tam
$bat = Join-Path $tam '3-GIAI-MA-WHEA.bat'
$goc = [IO.File]::ReadAllText($bat)
[IO.File]::WriteAllText($bat, $goc.Replace("[void]`$script:FLAGS.Add(`$f)", "[void]`$script:FLAGS.Add(`$f) # sua tay"), (New-Object Text.UTF8Encoding $false))
$tb = Join-Path $tam 'src\build.ps1'
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File $tb -Kiem 2>&1
Check ($LASTEXITCODE -eq 1 -and [IO.File]::ReadAllText($bat) -match 'sua tay') "-Kiem: .bat bị sửa tay trong khối chung thì mã 1, không ghi ($LASTEXITCODE)"
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File $tb 2>&1
Check ($LASTEXITCODE -eq 0 -and [IO.File]::ReadAllText($bat) -eq $goc) 'dựng lại: khối chung trở về đúng src\Chung.ps1, phần còn lại giữ nguyên'
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File $tb -Kiem 2>&1
Check ($LASTEXITCODE -eq 0) 'dựng hai lần không đổi gì'
[IO.File]::WriteAllText($bat, $goc.Replace('$SCRIPT_VER = ', '$SCRIPT_VER = ( '), (New-Object Text.UTF8Encoding $false))
$o = & powershell -NoProfile -ExecutionPolicy Bypass -File $tb 2>&1
Check ($LASTEXITCODE -eq 1 -and (@($o) -join ' ') -match 'syntax error') 'phần PowerShell lỗi cú pháp: báo lỗi, mã 1'

Complete-Test
