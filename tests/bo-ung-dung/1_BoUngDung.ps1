# Bài thử BoUngDung.ps1 bằng giả lập winget: danh sách đã cài (winget export), cài, cập nhật, mã thoát (lỗi, không có
# bản mới, cần khởi động lại), bộ cài báo 0 mà chưa cài; danh sách DanhSach.json khớp ô chọn trong tool.json.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\Catalog.ps1"; . "$HubDir\lib\KetQua.ps1"
$toolDir = Join-Path $ToolsDir 'bo-ung-dung'
$env:TRAMTOOL_BOUNGDUNG_TEST = '1'
. "$toolDir\BoUngDung.ps1"
$ChayThu = $false; $KhongDung = $true; $ConLai = $null
$script:ResultDir = New-TestDir 'bud_ketqua'
$manifest = [IO.File]::ReadAllText((Join-Path $toolDir 'tool.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$validLevels = 'loi', 'canh-bao', 'thong-tin', 'ok'
$apps = Read-AppList
function App([string]$Khoa) { return @($apps | Where-Object { $_.khoa -eq $Khoa })[0] }

# ---- giả lập
$script:Calls = New-Object System.Collections.ArrayList
$script:Answers = New-Object System.Collections.Queue
function Get-WingetCommand { if ($script:HasWinget) { return 'C:\gia\winget.exe' } return $null }
function Get-InstalledIds {
    # lần gọi thứ ExportFailFrom trở đi báo hỏng (1: hỏng ngay; 2: đọc được trước khi cài, hỏng khi đọc lại)
    $script:ExportCalls++
    if ($script:ExportCalls -ge $script:ExportFailFrom) { return [pscustomobject]@{ Ok = $false; Ids = @(); Error = 'winget export mã -1: hỏng' } }
    return [pscustomobject]@{ Ok = $true; Ids = @($script:Installed); Error = '' }
}
function Invoke-Winget {
    param([string[]]$Arguments)
    [void]$script:Calls.Add($Arguments -join ' ')
    $id = $Arguments[[array]::IndexOf($Arguments, '--id') + 1]
    $c = if ($script:Codes.ContainsKey($id)) { $script:Codes[$id] } else { 0 }
    if ($Arguments[0] -eq 'install' -and $script:NeverInstalls -notcontains $id -and ($c -eq 0 -or $script:InstallsAnyway -contains $id -or $c -eq $script:CodeReboot)) { $script:Installed += $id }
    return $c
}
function Read-YesNo { param([string]$Question, [bool]$Default = $false) if ($script:Answers.Count) { return $script:Answers.Dequeue() } return $Default }
function Test-IsAdmin { return $true }
function Reset-Case {
    $script:Calls.Clear(); $script:Answers.Clear(); $script:Findings.Clear()
    $script:HasWinget = $true; $script:ExportCalls = 0; $script:ExportFailFrom = [int]::MaxValue; $script:Installed = @('VNGCorp.Zalo', 'Some.Other')
    $script:Codes = @{}; $script:NeverInstalls = @(); $script:InstallsAnyway = @()
    $script:AllApps = $apps
    Get-ChildItem -LiteralPath $script:ResultDir -File -ErrorAction SilentlyContinue | Remove-Item -Force
}
function Codes { return @($script:Findings | ForEach-Object { $_.ma }) }
function Find([string]$Ma) { return , @($script:Findings | Where-Object { $_.ma -eq $Ma }) }
function Last($x) { return @($x)[-1] }

Write-KT '1. Danh sách và tool.json' Cyan
$cai = @($manifest.actions | Where-Object { $_.id -eq 'cai' })[0]
$appArgs = @($cai.args | Where-Object { $_.id -ne 'chay-thu' })
Check ($apps.Count -ge 10) "danh sách có $($apps.Count) ứng dụng"
Check (@($apps | Group-Object khoa | Where-Object { $_.Count -gt 1 }).Count -eq 0 -and @($apps | Group-Object id | Where-Object { $_.Count -gt 1 }).Count -eq 0) 'khoá, mã gói không trùng'
Check (-not @($apps | Where-Object { $_.khoa -notmatch '^[A-Za-z][A-Za-z0-9]*$' -or $_.id -notmatch '^[A-Za-z0-9][A-Za-z0-9.+_-]*$' -or -not $_.ten }).Count) 'khoá chỉ chữ và số, mã gói đúng dạng, có tên'
$sync = @($apps | Where-Object { $a = $_; $x = @($appArgs | Where-Object { $_.id -eq $a.khoa })[0]
        -not $x -or $x.type -ne 'bool' -or $x.flag -ne "-$($a.khoa)" -or [bool]$x.default -ne [bool]$a.macDinh })
Check ($sync.Count -eq 0 -and $appArgs.Count -eq $apps.Count) "mỗi ứng dụng một ô chọn trong tool.json, cùng mặc định ($(@($sync | ForEach-Object { $_.khoa }) -join ', '))"
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $toolDir 'BoUngDung.ps1'), [ref]$null, [ref]$null)
$params = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) + @([Management.Automation.Internal.CommonParameters].GetProperties() | ForEach-Object { $_.Name; $_.GetCustomAttributes([Alias], $false) | ForEach-Object { $_.AliasNames } })
$clash = @($apps | Where-Object { $k = $_.khoa; @($params | Where-Object { $_.StartsWith($k, [StringComparison]::OrdinalIgnoreCase) }).Count })
Check ($clash.Count -eq 0) "không khoá nào là tiền tố của tham số của script (PowerShell sẽ hiểu là viết tắt) ($(@($clash | ForEach-Object { $_.khoa }) -join ', '))"
foreach ($a in $manifest.actions) {
    $flags = @(@($a.fixedArgs) | Where-Object { $_ -like '-*' }) + @(@($a.args) | ForEach-Object { $_.flag })
    $miss = @($flags | Where-Object { $_ -and $params -notcontains $_.TrimStart('-') -and -not (App $_.TrimStart('-')) })
    $fa = @($a.fixedArgs | Where-Object { $_ })
    Check ($miss.Count -eq 0 -and (-not $fa.Count -or $script:Modes.Contains($fa[1]))) "$($a.id): cờ, chế độ có trong script hoặc danh sách ($($miss -join ', '))"
}

Write-KT '2. Chọn ứng dụng' Cyan
$d = Get-SelectedApps $apps $null
Check ((@($d | ForEach-Object { $_.khoa }) -join ',') -eq (@($apps | Where-Object { $_.macDinh } | ForEach-Object { $_.khoa }) -join ',')) "không chọn: các ứng dụng mặc định ($(@($d | ForEach-Object { $_.khoa }) -join ','))"
$d = Get-SelectedApps $apps @('-VLC', '-zalo')
Check ((@($d | ForEach-Object { $_.khoa }) -join ',') -eq 'Zalo,VLC') 'chọn bằng cờ (không phân biệt hoa thường), theo thứ tự danh sách'
$err = ''; try { [void](Get-SelectedApps $apps @('-Zalo', '-KhongCo')) } catch { $err = $_.Exception.Message }
Check ($err -match 'KhongCo' -and $err -match '-UltraViewer') 'cờ lạ: báo lỗi kèm các cờ chọn được'

Write-KT '3. Kiểm tra' Cyan
Reset-Case; $script:HasWinget = $false
$c = Last (Invoke-Check 6>$null)
Check ($c -eq 2 -and (Codes) -contains 'WINGET_KHONG_CO') "không có winget: mã 2, WINGET_KHONG_CO ($c)"
Reset-Case; $script:ExportFailFrom = 1
$c = Last (Invoke-Check 6>$null)
Check ($c -eq 2 -and (Find 'WINGET_LOI')[0].mucDo -eq 'loi' -and (Find 'WINGET_LOI')[0].chiTiet -match 'hỏng') 'winget export lỗi: WINGET_LOI kèm chữ lỗi'
Reset-Case; $script:Installed = @('VNGCorp.Zalo', 'UniKey.UniKey', 'lamquangminh.EVKey')
$c = Last (Invoke-Check 6>$null)
$f = (Find 'UNG_DUNG_MAC_DINH_CHUA_CAI')[0]
Check ($c -eq 0 -and (Find 'UNG_DUNG_DA_CAI')[0].tieuDe -match '3/') 'đếm ứng dụng đã cài'
Check ($f -and $f.tieuDe -match '7-Zip' -and $f.tieuDe -notmatch 'Zalo' -and $f.chayTiep.congCu -eq 'bo-ung-dung' -and $f.chayTiep.action -eq 'cai') 'ứng dụng mặc định chưa cài: gợi ý Cài ứng dụng'
Check ((Find 'CUNG_NHOM_CAI_HAI')[0].mucDo -eq 'canh-bao') 'cài cả UniKey và EVKey: cảnh báo'
Reset-Case; $script:Installed = @($apps | Where-Object { $_.macDinh } | ForEach-Object { $_.id.ToLowerInvariant() })
[void](Invoke-Check 6>$null)
Check (-not (Find 'UNG_DUNG_MAC_DINH_CHUA_CAI').Count -and (Find 'UNG_DUNG_DA_CAI').Count) 'đủ ứng dụng mặc định (mã gói khác hoa thường): không gợi ý cài'

Write-KT '4. Cài' Cyan
Reset-Case
$c = Last (Invoke-Cai @((App 'Zalo'), (App 'UniKey'), (App 'EVKey'), (App 'SevenZip')) 6>$null)
Check ($c -eq 0) "cài: mã 0 ($c)"
Check ($script:Calls.Count -eq 2 -and $script:Calls[0] -eq 'install --id UniKey.UniKey -e --silent --accept-package-agreements --source winget --accept-source-agreements --disable-interactivity' -and $script:Calls[1] -match '^install --id 7zip\.7zip ') "chỉ cài UniKey, 7-Zip, đúng tham số ($($script:Calls -join ' | '))"
Check ((Find 'DA_CAI').Count -eq 2 -and (Find 'BO_QUA_CUNG_NHOM')[0].tieuDe -match 'EVKey') 'đã có Zalo thì bỏ qua; EVKey cùng nhóm với UniKey thì bỏ qua'
Reset-Case; $script:Installed += 'UniKey.UniKey'
[void](Invoke-Cai @((App 'EVKey')) 6>$null)
Check ($script:Calls.Count -eq 0 -and (Find 'BO_QUA_CUNG_NHOM')[0].tieuDe -match 'máy đã có UniKey') 'máy đã có UniKey: không cài EVKey'
Reset-Case; $script:Codes = @{ 'Foxit.FoxitReader' = -1978335215 }
$c = Last (Invoke-Cai @((App 'Foxit'), (App 'Chrome')) 6>$null)
Check ($c -eq 3 -and (Find 'CAI_LOI')[0].tieuDe -match 'Foxit' -and (Find 'DA_CAI')[0].tieuDe -match 'Chrome') "một ứng dụng lỗi: mã 3 ($c)"
Reset-Case; $script:Codes = @{ 'Foxit.FoxitReader' = 5 }
Check ((Last (Invoke-Cai @((App 'Foxit')) 6>$null)) -eq 1) 'chỉ một ứng dụng và lỗi: mã 1'
Reset-Case; $script:Codes = @{ 'Google.Chrome' = 1603 }; $script:InstallsAnyway = @('Google.Chrome')
$c = Last (Invoke-Cai @((App 'Chrome')) 6>$null)
Check ($c -eq 0 -and (Find 'DA_CAI')[0].chiTiet -match '1603') 'bộ cài báo lỗi mà đã có trong danh sách: coi là đã cài, ghi mã'
Reset-Case; $script:NeverInstalls = @('Google.Chrome')
$c = Last (Invoke-Cai @((App 'Chrome')) 6>$null)
Check ($c -eq 1 -and (Find 'CAI_LOI')[0].chiTiet -match 'không thấy') 'báo 0 mà không thấy trong danh sách đã cài: lỗi'
Reset-Case; $script:Codes = @{ 'VideoLAN.VLC' = $script:CodeReboot }
$c = Last (Invoke-Cai @((App 'VLC')) 6>$null)
Check ($c -eq 0 -and (Codes) -contains 'CAN_KHOI_DONG_LAI') 'cần khởi động lại: đã cài, nhắc khởi động lại'
Reset-Case; $script:ExportFailFrom = 2; $script:Codes = @{ 'Mozilla.Firefox' = 7 }
$c = Last (Invoke-Cai @((App 'VLC'), (App 'Firefox')) 6>$null)
Check ($c -eq 3 -and (Find 'DA_CAI')[0].tieuDe -match 'VLC' -and (Find 'CAI_LOI')[0].tieuDe -match 'Firefox') "không đọc lại được danh sách: tin mã thoát, 0 là đã cài ($c)"
Reset-Case
$c = Last (Invoke-Cai @((App 'Foxit'), (App 'Chrome')) -DryRun 6>$null)
Check ($c -eq 0 -and $script:Calls.Count -eq 0) 'chạy thử: không cài gì'
Reset-Case; $script:Answers.Enqueue($false)
$c = Last (Invoke-Cai @((App 'Foxit')) -Ask 6>$null)
Check ($c -eq 2 -and $script:Calls.Count -eq 0) 'hỏi lại, không đồng ý: mã 2'
Reset-Case; $script:HasWinget = $false
Check ((Last (Invoke-Cai @((App 'Foxit')) 6>$null)) -eq 2) 'không có winget: mã 2'
Reset-Case
$c = Last (Invoke-Cai @((App 'Zalo')) 6>$null)
Check ($c -eq 0 -and $script:Calls.Count -eq 0) 'chỉ chọn ứng dụng đã có: mã 0, không gọi winget'

Write-KT '5. Cập nhật' Cyan
Reset-Case; $script:Installed = @('VNGCorp.Zalo', '7zip.7zip', 'Google.Chrome')
$script:Codes = @{ '7zip.7zip' = $script:CodeNoUpdate; 'Google.Chrome' = 5 }
$c = Last (Invoke-CapNhat 6>$null)
Check ($c -eq 3 -and $script:Calls.Count -eq 3 -and $script:Calls[0] -match '^upgrade --id VNGCorp\.Zalo -e --silent') "cập nhật ba ứng dụng đã cài: mã 3 vì Chrome lỗi ($c)"
Check ((Find 'DA_CAP_NHAT')[0].tieuDe -match 'Zalo' -and (Find 'DA_MOI_NHAT')[0].tieuDe -match '7-Zip' -and (Find 'CAP_NHAT_LOI')[0].tieuDe -match 'Chrome') 'tách đã cập nhật, đã mới nhất, lỗi'
Reset-Case; $script:Installed = @()
Check ((Last (Invoke-CapNhat 6>$null)) -eq 0 -and $script:Calls.Count -eq 0) 'chưa cài gì trong danh sách: mã 0'
Reset-Case
Check ((Last (Invoke-CapNhat -DryRun 6>$null)) -eq 0 -and $script:Calls.Count -eq 0) 'chạy thử: không cập nhật'

Write-KT '6. File kết quả' Cyan
Reset-Case; $ConLai = @('-Foxit', '-Chrome'); $script:Codes = @{ 'Google.Chrome' = 5 }
$c = Last (Invoke-Mode 'cai' 6>$null)
$files = @(Get-ChildItem -LiteralPath $script:ResultDir -Filter 'KetQua_BoUngDung_*.json')
Check ($c -eq 3 -and $files.Count -eq 1) "Cài qua cờ: mã 3, một file kết quả ($c, $($files.Count))"
$j = [IO.File]::ReadAllText($files[0].FullName) | ConvertFrom-Json
Check ($j.chuan -eq 'tramtool.ketqua/1' -and $j.congCu -eq 'bo-ung-dung' -and $j.cheDo -eq 'cai' -and $j.trangThai -eq 'mot-phan' -and $j.ma -eq 'CO_LOI') 'đầu file theo chuẩn'
Check (@($j.phatHien)[0].ma -eq 'CAI_LOI' -and $j.thongDiep -match 'một phần') 'lỗi lên đầu, thông điệp làm được một phần'
$hr = Read-RunResult -Path $files[0].FullName
Check ($hr -and $hr.trangThai -eq 'mot-phan') 'trạm đọc được file kết quả'
Reset-Case; $ConLai = @('-KhongCo')
$c = Last (Invoke-Mode 'cai' 6>$null)
Check ($c -eq 1 -and (Codes) -contains 'LOI_KHONG_LUONG_TRUOC' -and $script:Calls.Count -eq 0) 'cờ lạ qua Invoke-Mode: mã 1, ghi lỗi, không cài'
$ConLai = $null

Write-KT '7. Mã, nút gợi ý' Cyan
$addCalls = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Add-Finding' }, $true))
$bad = @(); $next = @()
foreach ($cl in $addCalls) {
    $e = @($cl.CommandElements | Select-Object -Skip 1)
    if ($e[0] -isnot [Management.Automation.Language.StringConstantExpressionAst] -or $e[0].Value -notmatch '^[A-Z][A-Z0-9_]+$') { $bad += $cl.Extent.StartLineNumber }
    if ($e[1] -isnot [Management.Automation.Language.StringConstantExpressionAst] -or $validLevels -notcontains $e[1].Value) { $bad += $cl.Extent.StartLineNumber }
    if ($e.Count -ge 6 -and $e[5] -is [Management.Automation.Language.StringConstantExpressionAst]) { $next += $e[5].Value }
}
Check ($addCalls.Count -ge 12 -and $bad.Count -eq 0) "$($addCalls.Count) chỗ ghi phát hiện: mã CHU_HOA, mức hợp lệ (dòng lỗi: $($bad -join ', '))"
$ids = @($manifest.actions | ForEach-Object { "bo-ung-dung/$($_.id)" })
Check ($next.Count -gt 0 -and -not @($next | Where-Object { $ids -notcontains $_ }).Count) "nút gợi ý trỏ tới action có thật ($(@($next | Sort-Object -Unique) -join ', '))"
$cat = Get-HubCatalog -ToolsDir $ToolsDir -RootDir $RepoRoot
$t = @($cat | Where-Object { $_.id -eq 'bo-ung-dung' })[0]
Check ($t -and @($t.problems).Count -eq 0) "trạm đọc được tool.json, không lỗi khai báo ($(@($t.problems) -join ' | '))"

Complete-Test
