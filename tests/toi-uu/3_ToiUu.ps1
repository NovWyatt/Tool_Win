# Bài thử ToiUu.ps1, cửa vào chung của "Tối ưu Windows": gộp phát hiện của hai phần (nghiêm trọng trước), mã thoát
# chung, file KetQua_ToiUu_KiemTra_*.json theo chuẩn mà trạm đọc được; mã và nút gợi ý khai trong hai script con;
# cờ trong tool.json có trong param() của script. Chạy thật script con trong cùng cửa sổ: phần dịch vụ Kiểm tra thật
# (chỉ đọc, không cần Admin), phần đồng hồ có -ChayThu nên không hỏi UAC. Không chạy ToiUu.ps1 -Mode kiem-tra thật.
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\Catalog.ps1"; . "$HubDir\lib\KetQua.ps1"
$toolDir = Join-Path $ToolsDir 'toi-uu'
$env:TRAMTOOL_TOIUU_TEST = '1'
. "$toolDir\ToiUu.ps1"
$KhongDung = $true
$script:ResultDir = New-TestDir 'toiuu_ketqua'
$script:StateFile = Join-Path $TestRoot 'toiuu_ketqua\TrangThaiGoc_TEST.json'
$realInvokePart = ${function:Invoke-Part}

$manifest = [IO.File]::ReadAllText((Join-Path $toolDir 'tool.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$actionIds = @($manifest.actions | ForEach-Object { $_.id })

Write-KT '1. Mã, mức, nút gợi ý khai trong hai script con' Cyan
$validLevels = 'loi', 'canh-bao', 'thong-tin', 'ok'
foreach ($name in 'DichVu.ps1', 'DongHo.ps1') {
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $toolDir $name), [ref]$null, [ref]$null)
    $calls = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Add-Finding' }, $true))
    $bad = @(); $next = @()
    foreach ($c in $calls) {
        $e = @($c.CommandElements | Select-Object -Skip 1)
        $ma = if ($e.Count -ge 1 -and $e[0] -is [Management.Automation.Language.StringConstantExpressionAst]) { $e[0].Value } else { '' }
        $muc = if ($e.Count -ge 2 -and $e[1] -is [Management.Automation.Language.StringConstantExpressionAst]) { $e[1].Value } else { '' }
        if ($ma -notmatch '^[A-Z][A-Z0-9_]+$' -or $validLevels -notcontains $muc) { $bad += $c.Extent.StartLineNumber }
        if ($e.Count -ge 6 -and $e[5] -is [Management.Automation.Language.StringConstantExpressionAst]) { $next += $e[5].Value }
    }
    Check ($calls.Count -ge 4) "$name có $($calls.Count) chỗ ghi phát hiện"
    Check ($bad.Count -eq 0) "$name`: mọi phát hiện có mã CHU_HOA và mức hợp lệ (dòng lỗi: $($bad -join ', '))"
    $wrong = @($next | Where-Object { $_ -notmatch '^toi-uu/(.+)$' -or $actionIds -notcontains $Matches[1] })
    Check ($next.Count -gt 0 -and $wrong.Count -eq 0) "$name`: nút gợi ý trỏ tới action có thật ($(@($next | Sort-Object -Unique) -join ', '))"
}

Write-KT '2. Cờ trong tool.json có trong param() của script' Cyan
foreach ($a in $manifest.actions) {
    if ($a.file -notmatch '\.ps1$') { continue }
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $toolDir $a.file), [ref]$null, [ref]$null)
    $params = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    $flags = @(@($a.fixedArgs) | Where-Object { $_ -like '-*' }) + @(@($a.args) | ForEach-Object { $_.flag })
    $miss = @($flags | Where-Object { $_ -and $params -notcontains $_.TrimStart('-') })
    Check ($miss.Count -eq 0) "$($a.id) ($($a.file)): cờ có trong param() ($($miss -join ', '))"
}
$cat = Get-HubCatalog -ToolsDir $ToolsDir -RootDir $RepoRoot
$t = @($cat | Where-Object { $_.id -eq 'toi-uu' })[0]
Check ($t -and @($t.problems).Count -eq 0) "trạm đọc được tool.json, không lỗi khai báo ($(@($t.problems) -join ' | '))"
Check (-not @($cat | Where-Object { $_.id -in 'service-optimizer', 'clock-optimizer', 'health-report' }).Count) 'không còn công cụ cũ đã gộp trong danh mục'

Write-KT '3. Gộp hai phần (script con giả)' Cyan
$script:Fake = @{}
$script:PartCalls = New-Object System.Collections.ArrayList
function F([string]$Ma, [string]$Muc, [string]$Tieu = '', [string]$Tiep = '') {
    $f = [ordered]@{ ma = $Ma; mucDo = $Muc; tieuDe = $(if ($Tieu) { $Tieu } else { $Ma }); chiTiet = ''; cachSua = '' }
    if ($Tiep) { $f.chayTiep = [ordered]@{ congCu = 'toi-uu'; action = $Tiep } }
    return $f
}
function Invoke-Part {
    param([string]$File, [string[]]$Arguments = @())
    [void]$script:PartCalls.Add("$File " + ($Arguments -join ' '))
    $k = [IO.Path]::GetFileNameWithoutExtension($File)
    $f = $script:Fake[$k]
    $out = $Arguments[[array]::IndexOf($Arguments, '-KetQua') + 1]
    if ($f.ContainsKey('Found')) { [IO.File]::WriteAllText($out, ([ordered]@{ phatHien = @($f.Found) } | ConvertTo-Json -Depth 6)) }
    elseif ($f.ContainsKey('Raw')) { [IO.File]::WriteAllText($out, $f.Raw) }
    return $f.Code
}
function Run-Check {
    Get-ChildItem -LiteralPath $script:ResultDir -Filter 'KetQua_ToiUu_*' -ErrorAction SilentlyContinue | Remove-Item -Force
    $script:PartCalls.Clear()
    $c = @(Invoke-KiemTraChung 6>$null)[-1]
    $files = @(Get-ChildItem -LiteralPath $script:ResultDir -Filter 'KetQua_ToiUu_KiemTra_*.json')
    $j = if ($files.Count -eq 1) { [IO.File]::ReadAllText($files[0].FullName) | ConvertFrom-Json } else { $null }
    return [pscustomobject]@{ Code = $c; Json = $j; Path = $(if ($files.Count) { $files[0].FullName } else { '' }); Count = $files.Count }
}
function Codes($r) { return (@($r.Json.phatHien | ForEach-Object { $_.ma }) -join ',') }

$script:Fake = @{
    DichVu = @{ Code = 0; Found = @((F 'DICH_VU_DA_TAT' 'thong-tin'), (F 'TRIM_TAT' 'canh-bao' -Tiep 'bat-lai-dich-vu')) }
    DongHo = @{ Code = 0; Found = @((F 'HPET_DANG_EP' 'canh-bao' -Tiep 'mac-dinh-dong-ho'), (F 'DONG_HO_X' 'ok')) }
}
$r = Run-Check
Check ($r.Code -eq 0 -and $r.Count -eq 1) "hai phần xong: mã 0, ghi một file kết quả (mã $($r.Code), $($r.Count) file)"
Check ((Codes $r) -eq 'TRIM_TAT,HPET_DANG_EP,DICH_VU_DA_TAT,DONG_HO_X') "cảnh báo trước, cùng mức giữ thứ tự dịch vụ rồi đồng hồ ($(Codes $r))"
$j = $r.Json
Check ($j.chuan -eq 'tramtool.ketqua/1' -and $j.congCu -eq 'toi-uu' -and $j.cheDo -eq 'kiem-tra' -and $j.may -eq $env:COMPUTERNAME) 'đầu file theo chuẩn, congCu toi-uu'
Check ($j.trangThai -eq 'xong' -and $j.maThoat -eq 0 -and $j.ma -eq 'CO_CANH_BAO' -and -not $j.chayThu) "trạng thái xong, mã CO_CANH_BAO ($($j.ma))"
Check ($j.tomTat.loi -eq 0 -and $j.tomTat.canhBao -eq 2 -and $j.tomTat.thongTin -eq 1) 'tóm tắt đếm đúng 0 lỗi, 2 cảnh báo, 1 thông tin'
Check ($j.thongDiep -match '2 cảnh báo') "thông điệp nói số cảnh báo ($($j.thongDiep))"
Check (@($j.phatHien | Where-Object { $_.ma -eq 'TRIM_TAT' })[0].chayTiep.action -eq 'bat-lai-dich-vu') 'giữ nút gợi ý của từng phát hiện'
Check ($script:PartCalls.Count -eq 2 -and $script:PartCalls[0] -match '^DichVu\.ps1 -Mode kiem-tra -KhongDung -KetQua ' -and $script:PartCalls[1] -match '^DongHo\.ps1 -Mode kiem-tra -KhongDung -KetQua ') 'gọi Kiểm tra của dịch vụ rồi đồng hồ, có -KhongDung -KetQua'
$hr = Read-RunResult -Path $r.Path
Check ($hr -and $hr.trangThai -eq 'xong' -and @($hr.phatHien).Count -eq 4 -and @($hr.phatHien | Where-Object { $_.chayTiep }).Count -eq 2) 'trạm đọc được file kết quả, giữ hai nút gợi ý'
Check (-not @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Filter 'TramTool_ToiUu_*' -Directory -ErrorAction SilentlyContinue).Count) 'dọn thư mục tạm của hai phần'

$script:Fake = @{ DichVu = @{ Code = 0; Found = @((F 'DICH_VU_MAC_DINH' 'ok')) }; DongHo = @{ Code = 0; Found = @((F 'DONG_HO_MAC_DINH' 'ok')) } }
$r = Run-Check
Check ($r.Code -eq 0 -and $r.Json.ma -eq 'KHONG_CO_CANH_BAO' -and $r.Json.thongDiep -match 'không có gì cần sửa') "mọi thứ mặc định: KHONG_CO_CANH_BAO ($($r.Json.thongDiep))"
Check (@($r.Json.tep).Count -eq 0) 'chưa có file trạng thái gốc: không liệt kê tệp'
New-Item -ItemType File -Path $script:StateFile -Force | Out-Null
$r = Run-Check
Check (@($r.Json.tep).Count -eq 1 -and $r.Json.tep[0].duongDan -eq $script:StateFile) 'có file trạng thái gốc: liệt kê trong tep'
Remove-Item -LiteralPath $script:StateFile -Force

$script:Fake = @{ DichVu = @{ Code = 0; Found = @((F 'DICH_VU_MAC_DINH' 'ok')) }; DongHo = @{ Code = 1; Found = @((F 'KHONG_DOC_DUOC_BCD' 'loi')) } }
$r = Run-Check
Check ($r.Code -eq 3 -and $r.Json.trangThai -eq 'mot-phan' -and $r.Json.ma -eq 'KIEM_TRA_MOT_PHAN') "phần đồng hồ mã 1: mã 3, một phần ($($r.Code))"
Check ((Codes $r) -eq 'KHONG_DOC_DUOC_BCD,DICH_VU_MAC_DINH') "lỗi lên đầu, vẫn giữ phát hiện của phần lỗi ($(Codes $r))"

$script:Fake = @{ DichVu = @{ Code = 0 }; DongHo = @{ Code = 0; Found = @((F 'DONG_HO_MAC_DINH' 'ok')) } }
$r = Run-Check
$p = @($r.Json.phatHien)[0]
Check ($r.Code -eq 3 -and $p.ma -eq 'PHAN_KIEM_TRA_LOI' -and $p.mucDo -eq 'loi' -and $p.tieuDe -match 'dịch vụ nền') "phần dịch vụ không ghi file (mã 0): PHAN_KIEM_TRA_LOI, mã 3"
$script:Fake = @{ DichVu = @{ Code = 0; Raw = '{ hỏng' }; DongHo = @{ Code = 0; Raw = '{"khac":1}' } }
$r = Run-Check
Check ($r.Code -eq 1 -and (Codes $r) -eq 'PHAN_KIEM_TRA_LOI,PHAN_KIEM_TRA_LOI' -and $r.Json.trangThai -eq 'loi') "file hỏng, thiếu phatHien: hai PHAN_KIEM_TRA_LOI, mã 1 ($(Codes $r))"
$script:Fake = @{ DichVu = @{ Code = 2 }; DongHo = @{ Code = 2 } }
$r = Run-Check
Check ($r.Code -eq 2 -and $r.Json.trangThai -eq 'thieu-dieu-kien') "cả hai thiếu quyền: mã 2 ($($r.Code))"
$script:Fake = @{ DichVu = @{ Code = 2 }; DongHo = @{ Code = 1 } }
$r = Run-Check
Check ($r.Code -eq 1) "một phần thiếu quyền, một phần lỗi: mã 1 ($($r.Code))"
$script:ResultDir = Join-Path $TestRoot 'toiuu_ketqua\khong\ghi\duoc'
$script:Fake = @{ DichVu = @{ Code = 0; Found = @() }; DongHo = @{ Code = 0; Found = @() } }
$ro = New-Item -ItemType File -Path (Join-Path $TestRoot 'toiuu_ketqua\khong') -Force   # file chắn chỗ thư mục: không tạo được
$c = @(Invoke-KiemTraChung 6>$null)[-1]
Check ($c -eq 0) "không ghi được file kết quả: chỉ cảnh báo, mã kiểm tra vẫn 0 ($c)"
$script:ResultDir = Join-Path $TestRoot 'toiuu_ketqua'

Write-KT '4. Chạy thật script con trong cùng cửa sổ' Cyan
Set-Item -Path function:Invoke-Part -Value $realInvokePart
$gia = New-TestDir 'toiuu_gia'
[IO.File]::WriteAllText((Join-Path $gia 'gia.ps1'), "param([string]`$KetQua, [switch]`$Co)`r`n[IO.File]::WriteAllText(`$KetQua, ('co=' + [bool]`$Co))`r`nexit 3`r`n", (New-Object Text.UTF8Encoding $true))
$script:PartDir = $gia
$out = Join-Path $gia 'có dấu cách\kq.txt'
New-Item -ItemType Directory -Path (Split-Path $out) -Force | Out-Null
$c = Invoke-Part 'gia.ps1' @('-KetQua', $out, '-Co') 6>$null
Check ($c -eq 3) "trả đúng mã thoát của script con ($c)"
Check ((Test-Path -LiteralPath $out) -and [IO.File]::ReadAllText($out) -eq 'co=True') 'đường dẫn có dấu cách và cờ tới được script con'

$script:PartDir = $toolDir
$out = Join-Path $gia 'dichvu.json'
$c = Invoke-Part 'DichVu.ps1' @('-Mode', 'kiem-tra', '-KhongDung', '-KetQua', $out) 6>$null
$list = Read-PartFindings $out
Check ($c -eq 0 -and $null -ne $list -and $list.Count -ge 1) "dịch vụ nền, Kiểm tra thật: mã 0, $(@($list).Count) phát hiện"
Check (-not @($list | Where-Object { $validLevels -notcontains $_.mucDo -or $_.ma -notmatch '^[A-Z_]+$' }).Count) "phát hiện thật có mã và mức hợp lệ ($(@($list | ForEach-Object { $_.ma }) -join ', '))"
$out = Join-Path $gia 'dongho.json'
$c = Invoke-Part 'DongHo.ps1' @('-Mode', 'kiem-tra', '-ChayThu', '-KhongDung', '-KetQua', $out) 6>$null
$list = Read-PartFindings $out
if (Test-IsAdmin) { Check ($c -in 0, 1 -and $null -ne $list) "đồng hồ (Admin), Kiểm tra thật: mã $c" }
else { Check ($c -eq 2 -and @($list | Where-Object { $_.ma -eq 'KHONG_DOC_DUOC_BCD' }).Count -eq 1) "đồng hồ không quyền Admin (-ChayThu, không hỏi UAC): mã 2, KHONG_DOC_DUOC_BCD ($c)" }

Write-KT '5. Chạy ToiUu.ps1 thật, không hỏi UAC' Cyan
Remove-Item Env:TRAMTOOL_TOIUU_TEST   # tiến trình con thừa hưởng biến này thì dừng ở móc thử
$ps = Join-Path $PSHOME 'powershell.exe'
$o = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $toolDir 'ToiUu.ps1') -Mode 'sua' -KhongDung 2>&1 | Out-String
Check ($LASTEXITCODE -eq 1 -and $o -match '"sua"') "chế độ sai: mã 1 ($LASTEXITCODE)"
if (Test-IsAdmin) { Skip-Test 'đang chạy bằng quyền Admin: bỏ qua phép thử "đã nâng quyền mà vẫn chưa có quyền"' }
else {
    $o = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $toolDir 'ToiUu.ps1') -Mode kiem-tra -DaNangQuyen -KhongDung 2>&1 | Out-String
    Check ($LASTEXITCODE -eq 2 -and $o -match 'Admin')"đã mở lại mà chưa có quyền Admin: mã 2, không hỏi UAC lần nữa ($LASTEXITCODE)"
}

Complete-Test
