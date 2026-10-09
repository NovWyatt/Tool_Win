# Gợi ý cho ô chọn file/thư mục (goiY trong tool.json): danh mục đọc và báo lỗi khai sai, Get-ArgSuggestions liệt kê
# mục khớp nguon, đọc JSON trong thư mục, lọc theo trường (loc), mô tả theo mẫu, sắp xếp, giới hạn; API /api/suggest
# và form (kiểm tĩnh). Mọi thư mục nằm trong thư mục tạm; không mở cửa sổ, không cần mạng.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\Catalog.ps1"; . "$HubDir\lib\Checks.ps1"
$dir = $TestRoot
function Save-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false)) }
function New-Bk([string]$Root, [string]$Name, $Manifest, [string]$Raw = '') {
    $p = Join-Path $Root $Name
    New-Item -ItemType Directory -Path $p -Force | Out-Null
    if ($Raw) { Save-Utf8 (Join-Path $p 'manifest.json') $Raw }
    elseif ($Manifest) { Save-Utf8 (Join-Path $p 'manifest.json') ($Manifest | ConvertTo-Json -Depth 5) }
    return $p
}

Write-KT '1. tool.json: goiY' Cyan
$tools = Join-Path $dir 'tools'
$td = Join-Path $tools 'thu-goi-y'
New-Item -ItemType Directory -Path $td -Force | Out-Null
Save-Utf8 (Join-Path $td 'Chay.bat') "@echo off`r`nexit /b 0`r`n"
$env:TRAMTOOL_GOIY_KT = Join-Path $dir 'nguon2'
$goiY = @{
    nguon = @(@{ dir = 'SaoLuu'; glob = 'SaoLuu_*' }, @{ dir = '%TRAMTOOL_GOIY_KT%'; glob = 'SaoLuu_*'; nhan = 'Desktop, bản cũ' })
    json = 'manifest.json'; loc = @{ User = '%USERNAME%' }; locNhan = 'Có {n} bản của tài khoản khác không hiện.'
    moTa = 'Sửa lúc {Time}: {Workbooks#} file Excel{ResetKeys?, có đặt lại dữ liệu}'; sapXep = 'ten'
}
Save-Utf8 (Join-Path $td 'tool.json') (@{
        id = 'thu-goi-y'; name = 'Thử gợi ý'; category = 'khac'
        actions = @(
            @{ id = 'hoan-tac'; label = 'Hoàn tác'; file = 'Chay.bat'; args = @(@{ id = 'thu-muc'; type = 'folder'; label = 'Bản sao lưu'; goiY = $goiY }) }
            @{ id = 'sai-kieu'; label = 'Sai kiểu'; file = 'Chay.bat'; args = @(@{ id = 'ten'; type = 'text'; goiY = @{ nguon = @(@{ dir = 'a' }) } }) }
            @{ id = 'sai-json'; label = 'Sai json'; file = 'Chay.bat'; args = @(@{ id = 'tm'; type = 'folder'; goiY = @{ nguon = @(@{ dir = 'a' }); json = '..\x.json' } }) }
            @{ id = 'loc-thieu-json'; label = 'Lọc thiếu json'; file = 'Chay.bat'; args = @(@{ id = 'tm'; type = 'folder'; goiY = @{ nguon = @(@{ dir = 'a' }); loc = @{ User = 'x' } } }) }
            @{ id = 'thieu-nguon'; label = 'Thiếu nguồn'; file = 'Chay.bat'; args = @(@{ id = 'tm'; type = 'folder'; goiY = @{ nguon = @() } }) }
        )
    } | ConvertTo-Json -Depth 10)
$cat = Get-HubCatalog -ToolsDir $tools -RootDir $dir
$tool = @($cat | Where-Object { $_.id -eq 'thu-goi-y' })[0]
$spec = @(@($tool.actions | Where-Object { $_.id -eq 'hoan-tac' })[0].args)[0]
Check ($spec.goiY -and @($spec.goiY.nguon).Count -eq 2 -and $spec.goiY.json -eq 'manifest.json' -and $spec.goiY.loc['User'] -eq '%USERNAME%' -and $spec.goiY.sapXep -eq 'ten') 'đọc goiY: nguon, json, loc, sapXep'
$probs = @($tool.problems) -join ' | '
foreach ($a in 'sai-kieu', 'sai-json', 'loc-thieu-json', 'thieu-nguon') {
    $s = @(@($tool.actions | Where-Object { $_.id -eq $a })[0].args)[0]
    Check ($null -eq $s.goiY -and $probs -match "Action '$a'") "khai sai ($a): bỏ goiY, báo lỗi tool.json"
}

Write-KT '2. Get-ArgSuggestions' Cyan
$sl = Join-Path $td 'SaoLuu'
$u = $env:USERNAME
$b1 = New-Bk $sl 'SaoLuu_20261001_080000' @{ User = $u; Time = '01/10/2026 08:00:00'; Workbooks = @('a.xlsx', 'b.xlsx'); ResetKeys = @(); RegExcel = @('HKCU\bi-mat') }
$b2 = New-Bk $sl 'SaoLuu_20261005_090000' @{ User = $u.ToUpper(); Time = '05/10/2026 09:00:00'; Workbooks = @(); ResetKeys = @('k') }
$null = New-Bk $sl 'SaoLuu_20261003_100000' @{ User = 'nguoi-khac'; Time = '03/10/2026 10:00:00' }
$null = New-Bk $sl 'SaoLuu_20261004_100000' $null
$null = New-Bk $sl 'SaoLuu_20261006_100000' $null '{ "User": "dở'
$null = New-Bk $sl 'SaoLuu_20261007_100000' $null '[1, 2]'
$null = New-Bk $sl 'KhacTen_20261008' @{ User = $u }
$b3 = New-Bk $env:TRAMTOOL_GOIY_KT 'SaoLuu_20260920_070000' @{ User = $u; Time = '20/09/2026 07:00:00'; Workbooks = 'mot.xlsx' }
(Get-Item $b1).LastWriteTime = (Get-Date).AddDays(-1)   # moi-nhat xếp theo giờ sửa: b1 mới hơn b2, b3
(Get-Item $b2).LastWriteTime = (Get-Date).AddDays(-5)
(Get-Item $b3).LastWriteTime = (Get-Date).AddDays(-9)
$g = Get-ArgSuggestions -Tool $tool -Spec $spec
$paths = @($g.items | ForEach-Object { $_.path })
Check (($paths -join '|') -eq (@($b2, $b1, $b3) -join '|')) "sapXep ten: tên giảm dần, gộp hai nguồn ($(@($paths | ForEach-Object { Split-Path $_ -Leaf }) -join ', '))"
Check ($g.tong -eq 3 -and $g.an -eq 1 -and $g.anNhan -eq 'Có {n} bản của tài khoản khác không hiện.') "bản của tài khoản khác bị lọc và được đếm ($($g.an)); thiếu, hỏng, mảng JSON thì bỏ hẳn"
Check ($g.items[0].moTa -eq 'Sửa lúc 05/10/2026 09:00:00: 0 file Excel, có đặt lại dữ liệu') "mô tả, {X?chữ} khi có giá trị: $($g.items[0].moTa)"
Check ($g.items[1].moTa -eq 'Sửa lúc 01/10/2026 08:00:00: 2 file Excel') "{X#} đếm phần tử, {X?chữ} rỗng khi mảng rỗng: $($g.items[1].moTa)"
Check ($g.items[2].moTa -eq 'Sửa lúc 20/09/2026 07:00:00: 1 file Excel' -and $g.items[2].nhan -eq 'Desktop, bản cũ' -and $g.items[0].nhan -eq '') "chuỗi đơn đếm là 1, nhãn theo nguồn: $($g.items[2].moTa)"
Check (($g | ConvertTo-Json -Depth 5) -notmatch 'bi-mat|RegExcel') 'không trả nội dung JSON ngoài mô tả'
$spec.goiY.sapXep = 'moi-nhat'
$paths = @((Get-ArgSuggestions -Tool $tool -Spec $spec).items | ForEach-Object { $_.path })
Check (($paths -join '|') -eq (@($b1, $b2, $b3) -join '|')) 'sapXep moi-nhat: theo giờ sửa thư mục'
$g = Get-ArgSuggestions -Tool $tool -Spec $spec -Limit 2
Check ($g.items.Count -eq 2 -and $g.tong -eq 3) 'giới hạn số mục, vẫn báo tổng'
$big = New-Bk $sl 'SaoLuu_20261009_000000' $null ('{ "User": "' + $u + '", "Pad": "' + ('x' * [int](2.1MB)) + '" }')
Check (-not @((Get-ArgSuggestions -Tool $tool -Spec $spec).items | Where-Object { $_.path -eq $big }).Count) 'JSON quá 2 MB: bỏ'
Remove-Item -LiteralPath $big -Recurse -Force

# Không có json: liệt kê theo tên, không lọc, không mô tả; nguồn chưa có thư mục thì bỏ qua.
$plain = [ordered]@{ type = 'folder'; goiY = [ordered]@{ nguon = @([ordered]@{ dir = 'SaoLuu'; glob = 'SaoLuu_2026100*'; nhan = '' }, [ordered]@{ dir = 'khong-co'; glob = '*'; nhan = '' }); json = ''; loc = [ordered]@{}; locNhan = ''; moTa = ''; sapXep = 'ten' } }
$g = Get-ArgSuggestions -Tool $tool -Spec $plain
Check ($g.items.Count -eq 6 -and $g.an -eq 0 -and -not @($g.items | Where-Object { $_.moTa }).Count) "không khai json: mọi thư mục khớp mẫu ($($g.items.Count)), nguồn chưa có thì bỏ qua"
$files = [ordered]@{ type = 'file'; goiY = [ordered]@{ nguon = @([ordered]@{ dir = '.'; glob = '*.bat'; nhan = '' }); json = ''; loc = [ordered]@{}; locNhan = ''; moTa = ''; sapXep = 'moi-nhat' } }
$g = Get-ArgSuggestions -Tool $tool -Spec $files
Check ($g.items.Count -eq 1 -and $g.items[0].name -eq 'Chay.bat') 'tham số file: liệt kê file, không lấy thư mục'

Write-KT '3. Format-GoiYMoTa' Cyan
$d = [pscustomobject]@{ A = 'x'; B = @('p', $null, 'q'); C = $false; D = 0; E = ''; F = 3 }
Check ((Format-GoiYMoTa -Template '{A}|{B}|{B#}|{C?c}|{D?d}|{E?e}|{F?f}|{G}|{G#}|{G?g}' -Data $d) -eq 'x|p, q|2||||f||0|') 'mẫu: giá trị, mảng, đếm, có giá trị, trường thiếu'

Write-KT '4. API và form (kiểm tĩnh)' Cyan
$srv = [IO.File]::ReadAllText((Join-Path $HubDir 'TramTool.ps1'))
Check ($srv -match "'GET /api/suggest'" -and $srv -match 'Get-ArgSuggestions -Tool \$tool -Spec \$spec') 'máy chủ có GET /api/suggest gọi Get-ArgSuggestions'
$run = [IO.File]::ReadAllText((Join-Path $HubDir 'web\js\run.js'))
Check ($run -match '/api/suggest\?id=' -and $run -match 'if \(s\.goiY\) loadSuggest' -and $run -match 'seq !== form\.seq') 'form tải gợi ý khi mở, bỏ kết quả về muộn của form trước'
Check ($run -match "type=""radio""" -and $run -match 'g\.items\[0\]\.path') 'form: chọn bằng nút radio, chưa có giá trị thì chọn sẵn mục đầu (mới nhất)'
$mx = Read-JsonFile (Join-Path $ToolsDir 'myexcelfix\tool.json')
$mg = @(@($mx.actions | Where-Object { $_.id -eq 'hoan-tac' })[0].args)[0].goiY
Check ($mg -and $mg.json -eq 'manifest.json' -and $mg.loc.User -eq '%USERNAME%') 'MyExcelFix: form Hoàn tác liệt kê bản sao lưu của tài khoản đang mở trạm'

Remove-Item Env:\TRAMTOOL_GOIY_KT -ErrorAction SilentlyContinue
Complete-Test
