# Kiểm tra (chỉ đọc) MyExcel trên máy này; kết quả ghi vào thư mục tạm (MYX_OUT), không mở Notepad, không chép ra Desktop.
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
. "$PSScriptRoot\_GiaLap.ps1"
$root = Join-Path $TestRoot 'fx4'
if (Test-Path $root) { Remove-Item $root -Recurse -Force }
$chk = Join-Path $root 'chk'
New-Item -ItemType Directory $chk -Force | Out-Null
Set-Content (Join-Path $chk "snapshot_$($env:COMPUTERNAME)_hong.json") '{ "a": ' -Encoding ASCII   # corrupt snapshot of another profile
# Hai bộ MyExcel giả (MYX_EXTRA_ROOT): máy nào cũng có ít nhất một lỗi bản Sửa xử lý được (NHIEU_BO_MYEXCEL)
$fake = @((Join-Path $root 'gia\MyExcel'), (Join-Path $root 'gia\MyExcel_cu'))
foreach ($d in $fake) { New-Item -ItemType Directory $d -Force | Out-Null; Set-Content (Join-Path $d 'MyExcel.xlam') 'xlam' -Encoding ASCII }
$envChk = @{ MYX_OUT = $chk; MYX_NO_NOTEPAD = '1'; MYX_NOPAUSE = '1'; MYX_EXTRA_ROOT = ($fake -join ';') }

Write-Host '== T4a: check (read-only) with a corrupt snapshot next to it ==' -ForegroundColor Cyan
$r = Invoke-Bat "$Tool\CheckMyExcel_VietQR.bat" -Env $envChk -TimeoutSec 300
$r.Out | Set-Content (Join-Path $root 'check_out.txt') -Encoding UTF8
Check ($r.Code -eq 0) "exit 0 (got $($r.Code), $($r.Sec)s)"
Check ($r.Out -match 'Bỏ qua snapshot hỏng') 'corrupt snapshot skipped with a note'
$safeUser = $env:USERNAME -replace '[^\w\.-]', '_'
Check (Test-Path (Join-Path $chk "snapshot_$($env:COMPUTERNAME)_$safeUser.json")) 'own snapshot still saved'
Check (@(Get-ChildItem $chk -Filter '*.tmp').Count -eq 0) 'no leftover .tmp'
$rep = @(Get-ChildItem $chk -Filter 'BaoCao_MyExcel_*.txt')
Check ($rep.Count -eq 1) 'report written'
$js = @(Get-ChildItem $chk -Filter 'KetQua_MyExcel_KiemTra_*.json')
Check ($js.Count -eq 1) 'result JSON written'
$j = Get-Content $js[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($j.cheDo -eq 'kiem-tra' -and $j.maThoat -eq 0 -and $j.ma -eq 'XONG' -and $j.phienBan -eq $ToolVersion) "JSON head: $($j.cheDo) $($j.maThoat) $($j.ma) $($j.phienBan)"
Check ($j.baoCao -eq $rep[0].FullName) 'JSON points to the report'
$items = @($j.phatHien)
Check ($items.Count -ge 1) "phatHien has $($items.Count) item(s)"
Check (@($items | Where-Object { $_.ma -notmatch '^[A-Z0-9_]+$' -or $_.mucDo -notin 'loi', 'canh-bao', 'thong-tin' -or -not $_.tieuDe -or -not $_.cachSua }).Count -eq 0) 'every finding has code, level, title, fix'
Check ($j.tomTat.loi + $j.tomTat.canhBao + $j.tomTat.thongTin -eq $items.Count) "tomTat adds up: $($j.tomTat.loi)/$($j.tomTat.canhBao)/$($j.tomTat.thongTin)"
Write-Host ('  codes: ' + (($items | ForEach-Object { "$($_.ma)($($_.mucDo))$(if ($_.chayTiep) { '>sua' })" }) -join ', '))
Check ($j.chuan -eq 'tramtool.ketqua/1' -and @($j.tep).Count -eq 1 -and $j.tep[0].duongDan -eq $rep[0].FullName) 'chuẩn tramtool.ketqua/1, tep trỏ tới báo cáo'
$next = @($items | Where-Object { $_.chayTiep })
Check (@($items | Where-Object { $_.ma -eq 'NHIEU_BO_MYEXCEL' -and $_.chayTiep }).Count -eq 1) 'hai bộ MyExcel giả: NHIEU_BO_MYEXCEL có gợi ý chạy tiếp'
Check ($next.Count -ge 1 -and @($next | Where-Object { $_.chayTiep.congCu -ne 'myexcelfix' -or $_.chayTiep.action -ne 'sua-loi' -or $_.mucDo -eq 'thong-tin' }).Count -eq 0) "lỗi bản Sửa xử lý được gợi ý chạy tiếp 'Sửa lỗi' ($($next.Count) mục)"
$tj = Get-Content (Join-Path $Tool 'tool.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Check (@($tj.actions | Where-Object { $_.id -eq 'sua-loi' }).Count -eq 1) "action 'sua-loi' có trong tool.json"
# Trạm đọc lại đúng như công cụ ghi (hub\lib\KetQua.ps1)
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\KetQua.ps1"
$hr = Read-RunResult -Path $js[0].FullName
Check ($hr.trangThai -eq 'xong' -and @($hr.phatHien).Count -eq $items.Count -and $hr.tomTat.loi -eq $j.tomTat.loi -and @($hr.phatHien | Where-Object { $_.chayTiep }).Count -eq $next.Count) 'Trạm đọc file kết quả: trạng thái, số phát hiện, gợi ý chạy tiếp khớp'
Check ((Get-Content $rep[0].FullName -Raw -Encoding UTF8) -match ('Phiên bản công cụ\s*: ' + [regex]::Escape($ToolVersion))) 'report shows the tool version'

Write-Host '== T4b: output folder cannot be created -> exit 1 ==' -ForegroundColor Cyan
Set-Content (Join-Path $root 'la_file.txt') 'x'
$r = Invoke-Bat "$Tool\CheckMyExcel_VietQR.bat" -Env @{ MYX_OUT = (Join-Path $root 'la_file.txt\con'); MYX_NO_NOTEPAD = '1'; MYX_NOPAUSE = '1' } -TimeoutSec 300
Check ($r.Code -eq 1) "exit 1 (got $($r.Code), $($r.Sec)s)"
Check ($r.Out -match 'Không ghi được báo cáo') 'says the report could not be written'

Assert-RealUntouched
Complete-Test
