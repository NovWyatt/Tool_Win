# File kết quả của Chẩn đoán (chuẩn tramtool.ketqua/1): mỗi chỗ ghi phát hiện có mã cố định, nút sửa trỏ tới action có
# thật, thứ tự lỗi > cảnh báo > thông tin, trạm đọc lại được. Phát hiện giả, không gọi mạng.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
. "$PSScriptRoot\_Nap.ps1"
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\Catalog.ps1"; . "$HubDir\lib\KetQua.ps1"
$out = New-TestDir 'mil_ketqua'
$env:MIL_KET_QUA = $out
$manifest = [IO.File]::ReadAllText("$ToolsDir\may-in-lan\tool.json", [Text.Encoding]::UTF8) | ConvertFrom-Json
$actionIds = @($manifest.actions | ForEach-Object { $_.id })

Write-KT '1. Mã phát hiện trong ChanDoan.ps1' Cyan
$ast = [Management.Automation.Language.Parser]::ParseFile("$ToolsDir\may-in-lan\lib\ChanDoan.ps1", [ref]$null, [ref]$null)
$calls = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Add-Finding' }, $true))
$codes = @(); $bad = @(); $fixes = @()
foreach ($c in $calls) {
    $e = @($c.CommandElements)
    $ma = $null; $fix = $null
    for ($i = 1; $i -lt $e.Count - 1; $i++) {
        if ($e[$i] -is [Management.Automation.Language.CommandParameterAst]) {
            if ($e[$i].ParameterName -eq 'Ma') { $ma = $e[$i + 1] }
            if ($e[$i].ParameterName -eq 'Fix') { $fix = $e[$i + 1] }
        }
    }
    if ($ma -isnot [Management.Automation.Language.StringConstantExpressionAst] -or $ma.Value -notmatch '^[A-Z][A-Z0-9_]+$') { $bad += $c.Extent.StartLineNumber; continue }
    $codes += $ma.Value
    if ($fix -is [Management.Automation.Language.StringConstantExpressionAst]) { $fixes += $fix.Value }
    elseif ($fix -and $fix.Extent.Text -ne '(Get-FixForCode $sl.Code)') { $bad += $c.Extent.StartLineNumber }
}
Check ($calls.Count -ge 40 -and $bad.Count -eq 0) "$($calls.Count) chỗ ghi phát hiện đều có -Ma 'CHU_HOA' (dòng thiếu: $($bad -join ', '))"
$dup = @($codes | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
Check ($dup.Count -eq 0) "mỗi mã chỉ dùng ở một chỗ ($($dup -join ', '))"
$fixes += @('noi-bao-mat', 'ket-noi-thu-muc', 'bat-chia-se')   # các giá trị Get-FixForCode trả về
$missing = @($fixes | Sort-Object -Unique | Where-Object { $actionIds -notcontains $_ })
Check ($missing.Count -eq 0) "-Fix trỏ tới action có trong tool.json ($($missing -join ', '))"
$src = [IO.File]::ReadAllText("$ToolsDir\may-in-lan\lib\ChanDoan.ps1")
foreach ($m in [regex]::Matches($src, "return '([a-z-]+)'")) { if ($actionIds -notcontains $m.Groups[1].Value) { Check $false "Get-FixForCode trả '$($m.Groups[1].Value)' không có trong tool.json" } }

Write-KT '2. Ghi file kết quả' Cyan
$script:Modes = [ordered]@{ 'sua-hang-doi' = @{ No = 2; Label = 'Sửa hàng đợi in bị kẹt' }; 'bat-chia-se' = @{ No = 4; Label = 'Bật chia sẻ file và máy in trên máy này' } }
$script:Findings.Clear()
Add-Finding -Ma 'MAY_IN_BAO_LOI' info 'Máy in X dùng cổng WSD.' 6>$null
Add-Finding -Ma 'MANG_PUBLIC' warn "Mạng 'Nha' đang để Public." -Fix 'bat-chia-se' -Hint 'Chỉ đổi khi tin cậy.' 6>$null
Add-Finding -Ma 'SPOOLER_DUNG' bad 'Dịch vụ in đang dừng.' -Fix 'sua-hang-doi' 6>$null
Add-Finding -Ma 'TUONG_LUA_TAT' warn 'Tường lửa đang tắt.' -Hint 'Bật lại trong Windows Security.' 6>$null
$start = Get-Date
$f = Save-RunResult -CheDo 'chan-doan' -Code 0 -Start $start -Files @([ordered]@{ nhan = 'Báo cáo chẩn đoán'; duongDan = 'C:\x\BaoCao_MayIn_PC_1.txt' })
Check ($f -and (Split-Path $f -Leaf) -eq ('KetQua_MayIn_ChanDoan_{0}_{1:yyyyMMdd_HHmmss}.json' -f $env:COMPUTERNAME, $start) -and (Split-Path $f -Parent) -eq $out) "tên file, nơi lưu (MIL_KET_QUA): $(Split-Path $f -Leaf)"
$j = [IO.File]::ReadAllText($f) | ConvertFrom-Json
Check ($j.chuan -eq 'tramtool.ketqua/1' -and $j.congCu -eq 'may-in-lan' -and $j.cheDo -eq 'chan-doan' -and $j.trangThai -eq 'xong' -and $j.ma -eq 'CO_LOI') 'đầu file theo chuẩn'
Check ((@($j.phatHien | ForEach-Object { $_.ma }) -join ',') -eq 'SPOOLER_DUNG,MANG_PUBLIC,TUONG_LUA_TAT,MAY_IN_BAO_LOI') "lỗi > cảnh báo (giữ thứ tự gặp) > thông tin: $(@($j.phatHien | ForEach-Object { $_.ma }) -join ',')"
$p0 = @($j.phatHien)[0]; $p1 = @($j.phatHien)[1]; $p2 = @($j.phatHien)[2]
Check ($p0.mucDo -eq 'loi' -and $p0.chayTiep.congCu -eq 'may-in-lan' -and $p0.chayTiep.action -eq 'sua-hang-doi' -and $p0.cachSua -match 'Sửa hàng đợi in bị kẹt') 'lỗi có nút sửa và cách sửa ghi tên nút'
Check ($p1.cachSua -match 'Bật chia sẻ' -and $p1.cachSua -match 'Chỉ đổi khi tin cậy') 'cách sửa gồm tên nút và lời dặn'
Check (-not $p2.chayTiep -and $p2.cachSua -eq 'Bật lại trong Windows Security.') 'phát hiện phải làm tay: không có nút, chỉ lời dặn'
Check ($j.tomTat.loi -eq 1 -and $j.tomTat.canhBao -eq 2 -and $j.tomTat.thongTin -eq 1 -and @($j.tep)[0].duongDan -eq 'C:\x\BaoCao_MayIn_PC_1.txt') 'tóm tắt, file báo cáo kèm theo'
$hr = Read-RunResult -Path $f
Check ($hr -and @($hr.phatHien | Where-Object { $_.chayTiep }).Count -eq 2) 'trạm đọc được, giữ hai nút gợi ý'
$script:Findings.Clear()
[void]$script:Findings.Add([pscustomobject]@{ Ma = 'KHONG_THAY_LOI'; Level = 'ok'; Text = 'Không thấy lỗi.'; Fix = ''; Hint = '' })
Start-Sleep -Milliseconds 1100
$f2 = Save-RunResult -CheDo 'chan-doan' -Code 0 -Start (Get-Date)
$j2 = [IO.File]::ReadAllText($f2) | ConvertFrom-Json
Check ($j2.ma -eq 'KHONG_CO_LOI' -and @($j2.phatHien)[0].mucDo -eq 'ok' -and $j2.thongDiep -eq 'Xong, không có lỗi.') 'không có lỗi: mã KHONG_CO_LOI, mục ok'
Remove-Item Env:MIL_KET_QUA

Write-KT '3. Trạm' Cyan
$cat = Get-HubCatalog -ToolsDir $ToolsDir -RootDir $RepoRoot
$t = @($cat | Where-Object { $_.id -eq 'may-in-lan' })[0]
Check ($t -and @($t.problems).Count -eq 0 -and @($manifest.outputs | Where-Object { $_.ketQua }).Count -eq 1) "tool.json khai file kết quả, không lỗi khai báo ($(@($t.problems) -join ' | '))"
Complete-Test
