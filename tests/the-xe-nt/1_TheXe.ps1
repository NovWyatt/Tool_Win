# Thử tools\the-xe-nt bằng dữ liệu thẻ giả (cần PowerShell 32 bit cho Jet, cần Excel để tạo file .xls mẫu).
# Chỉ ghi trong thư mục tạm của bài thử; không đọc danh sách thẻ thật nào.
# KiemThu: 32bit
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
if (-not (Test-Is32BitHost)) { Skip-Test 'cần PowerShell 32 bit (ChayTatCa.ps1 tự chạy bài này bằng SysWOW64\powershell.exe)'; Complete-Test }
try { $xl = New-Object -ComObject Excel.Application } catch { Skip-Test 'máy không có Excel để tạo file .xls mẫu'; Complete-Test }
$repoTool = "$ToolsDir\the-xe-nt"
$t = Join-Path $TestRoot 't'
[void](New-Item -ItemType Directory $t)
# Chạy bản chép của công cụ để báo cáo ket_qua của lần thử không rơi vào thư mục repo.
$tool = Join-Path $t 'tool'
[void](New-Item -ItemType Directory $tool)
foreach ($x in 'THE_XE.bat', 'TheXe.ps1', 'lib', 'mau') { Copy-Item (Join-Path $repoTool $x) $tool -Recurse }
$script:ToolDir = $tool
. "$tool\lib\Chung.ps1"; . "$tool\lib\DocGhi.ps1"; . "$tool\lib\TheXe.ps1"
function Run { param([string[]]$A) $ErrorActionPreference = 'Continue'; $o = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$tool\TheXe.ps1" @A -KhongDung 2>&1 | Out-String; [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o } }
$bom = New-Object Text.UTF8Encoding($true)

# ---- tạo dữ liệu giả bằng Excel
$xl.Visible = $false; $xl.DisplayAlerts = $false
function New-SellerBook {
    # Sổ một sheet "Sheet1" với tiêu đề STT, CardID, tinhtrang.
    $wb = $xl.Workbooks.Add(); while ($wb.Worksheets.Count -gt 1) { $wb.Worksheets.Item($wb.Worksheets.Count).Delete() }
    $ws = $wb.Worksheets.Item(1); $ws.Name = 'Sheet1'
    $ws.Cells(1, 1).Value2 = 'STT'; $ws.Cells(1, 2).Value2 = 'CardID'; $ws.Cells(1, 3).Value2 = 'tinhtrang'
    return $wb
}
try {
    # danh sách .xlsx: dòng tiêu đề ở dòng 3, có cả cột STT (số dòng) và SỐ THẺ
    $wb = $xl.Workbooks.Add(); $ws = $wb.Worksheets.Item(1)
    $ws.Cells(1, 1).Value2 = 'DANH SÁCH THẺ XE'
    $ws.Cells(3, 1).Value2 = 'STT'; $ws.Cells(3, 2).Value2 = 'SỐ THẺ'; $ws.Cells(3, 3).Value2 = 'ID'
    $ids = @(2085405500, 2085276316, 9569726, 2085486284)
    for ($i = 0; $i -lt $ids.Count; $i++) { $ws.Cells(4 + $i, 1).Value2 = [double]($i + 1); $ws.Cells(4 + $i, 2).Value2 = [double](5001 + $i); $ws.Cells(4 + $i, 3).Value2 = [double]$ids[$i] }
    $wb.SaveAs("$t\ds.xlsx", 51); $wb.Close($false)
    # danh sách .xlsx có mã dạng chữ (giữ số 0), cột bắt đầu từ cột B
    $wb = $xl.Workbooks.Add(); $ws = $wb.Worksheets.Item(1)
    $ws.Cells(2, 2).Value2 = 'Số thẻ'; $ws.Cells(2, 3).Value2 = 'Mã thẻ'
    $ws.Range('C:C').NumberFormat = '@'
    $ws.Cells(3, 2).Value2 = [double]6001; $ws.Cells(3, 3).Value2 = '0001234567'
    $ws.Cells(4, 2).Value2 = [double]6002; $ws.Cells(4, 3).Value2 = '0000000002'
    $wb.SaveAs("$t\ds-chu.xlsx", 51); $wb.Close($false)
    # file của bên bán giả: CardID là số, hiển thị 0000000000
    $wb = New-SellerBook; $ws = $wb.Worksheets.Item(1)
    $sid = @(1234567, 2345678, 345678, 11223344, 5566778)
    for ($i = 0; $i -lt $sid.Count; $i++) { $ws.Cells(2 + $i, 1).Value2 = [double](7001 + $i); $ws.Cells(2 + $i, 2).Value2 = [double]$sid[$i]; $ws.Cells(2 + $i, 3).Value2 = [double]1 }
    $ws.Range('B:B').NumberFormat = '0000000000'
    $wb.SaveAs("$t\7001-7005.xls", 56); $wb.Close($false)
    Copy-Item "$t\7001-7005.xls" "$t\7001-7005.nt"
    # cột CardID lẫn chữ và số: 6 ô chữ, 3 ô số -> Jet theo đa số (chữ), bỏ 3 ô số
    $wb = New-SellerBook; $ws = $wb.Worksheets.Item(1)
    for ($i = 0; $i -lt 9; $i++) {
        $ws.Cells(2 + $i, 1).Value2 = [double](8001 + $i)
        if ($i % 3 -eq 2) { $ws.Cells(2 + $i, 2).Value2 = [double](1000000000 + $i) } else { $ws.Cells(2 + $i, 2).NumberFormat = '@'; $ws.Cells(2 + $i, 2).Value2 = ('{0:D10}' -f (1000000000 + $i)) }
        $ws.Cells(2 + $i, 3).Value2 = [double]1
    }
    $wb.SaveAs("$t\tron.nt", 56); $wb.Close($false)
    # file đúng có một dòng trống ở giữa (dòng 4): số dòng phải khớp giữa hai cách đọc
    $wb = New-SellerBook; $ws = $wb.Worksheets.Item(1); $ws.Range('B:B').NumberFormat = '@'
    foreach ($p in @(@(2, 9201, '0000009201'), @(3, 9202, '0000009202'), @(5, 9203, '0000009203'))) { $ws.Cells($p[0], 1).Value2 = [double]$p[1]; $ws.Cells($p[0], 2).Value2 = $p[2]; $ws.Cells($p[0], 3).Value2 = [double]1 }
    $wb.SaveAs("$t\giua-trong.nt", 56); $wb.Close($false)
    # file .xlsx đổi đuôi .nt (phần mềm không đọc được)
    Copy-Item "$t\ds.xlsx" "$t\sai-dinh-dang.nt"
} finally { $xl.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl) }

# csv
[IO.File]::WriteAllText("$t\ds.csv", "SỐ THẺ;ID`r`n2132;2085405500`r`n2133;2085276316`r`n`r`n2134;9569726`r`n", $bom)
[IO.File]::WriteAllText("$t\loi.csv", "Số thẻ,Mã thẻ`r`n1,0000000001`r`n2,0000000001`r`n3,12AB`r`n4,123456789012`r`n,555`r`n6,`r`n7,0000000007`r`n7,0000000008`r`nx,9`r`n", $bom)
[IO.File]::WriteAllText("$t\khong-tieu-de.csv", "a,b`r`n1,2`r`n", $bom)
# danh sách để so với 7001-7005.nt: 7001, 7002 khớp sau khi thêm số 0; 7003 khác mã; 7006 thiếu trong file; 7004, 7005 thừa
[IO.File]::WriteAllText("$t\so-7001.csv", "STT;CardID`r`n7001;0001234567`r`n7002;0002345678`r`n7003;0000345679`r`n7006;0000000006`r`n", $bom)
[IO.File]::WriteAllText("$t\so-7001-du.csv", "STT;CardID`r`n7001;0001234567`r`n7002;0002345678`r`n7003;0000345678`r`n7004;0011223344`r`n7005;0005566778`r`n", $bom)
[IO.File]::WriteAllText("$t\khong-phai-xlsx.xlsx", "day khong phai file zip", $bom)

# ---- T1 tên cột, dòng tiêu đề
Check 'T1a plain' ((ConvertTo-Plain 'SỐ THẺ') -eq 'sothe')
Check 'T1b plain id' ((ConvertTo-Plain 'Mã thẻ') -eq 'mathe')
Check 'T1c plain đ' ((ConvertTo-Plain 'Đồng') -eq 'dong')
$h = Find-CardHeader @(, [string[]]@('STT', 'CardID', 'tinhtrang'))
Check 'T1d seller header' ($h.Stt -eq 0 -and $h.Id -eq 1 -and $h.Tinh -eq 2 -and $h.Line -eq 1)
$h = Find-CardHeader @([string[]]@('x'), [string[]]@(''), [string[]]@('STT', 'SỐ THẺ', 'ID'))
Check 'T1e prefers so the' ($h.Stt -eq 1 -and $h.Id -eq 2 -and $h.Line -eq 3) ($h | Out-String)
Check 'T1f range' ((Format-SttRange @(5, 1, 2, 3, 'x', 3)) -eq "1-3, 5, 'x'") (Format-SttRange @(5, 1, 2, 3, 'x', 3))
Check 'T1g range cut' ((Format-SttRange @(1, 3, 5, 7) 2) -match '^1, 3 \.\.\. \(và 2 khoảng khác\)$')

# ---- T2 danh sách, lỗi
$w = New-WorkDir
$l = Get-CardList (Read-AnyCells "$t\loi.csv" $w) 10
$e = $l.Errors -join "`n"
Check 'T2a dup id' ($e -match 'Mã 0000000001 trùng ở các thẻ 1, 2')
Check 'T2b non digit' ($e -match "12AB")
Check 'T2c too long' ($e -match '123456789012 .*dài 12 số')
Check 'T2d missing stt' ($e -match 'có mã 555 nhưng thiếu số thẻ')
Check 'T2e missing id' ($e -match 'thẻ 6 thiếu mã')
Check 'T2f dup stt' ($e -match 'Số thẻ 7 có 2 dòng')
Check 'T2g bad stt' ($e -match "số thẻ 'x'")
$loi = @{}; foreach ($r in $l.Rows) { $loi[$r.Line] = $r.Loi }
Check 'T2g2 row errors' ($l.Rows.Count -eq 9 -and $loi[2] -eq 'Mã trùng với thẻ 2' -and $loi[3] -eq 'Mã trùng với thẻ 1' -and $loi[4] -match 'chữ' -and $loi[6] -eq 'Thiếu số thẻ' -and $loi[7] -eq 'Thiếu mã thẻ' -and $loi[8] -eq 'Số thẻ có 2 dòng' -and $loi[10] -match 'nguyên dương') (($l.Rows | Format-Table Line, Loi | Out-String))
$l = Get-CardList (Read-AnyCells "$t\khong-tieu-de.csv" $w) 10
Check 'T2h no header' ($l.Errors.Count -eq 1 -and $l.Errors[0] -match 'tiêu đề')
$l = Get-CardList (Read-AnyCells "$t\ds.csv" $w) 10
Check 'T2i csv ok' ($l.Errors.Count -eq 0 -and $l.Cards.Count -eq 3 -and $l.Padded -eq 1 -and $l.Cards[2].Id -eq '0009569726' -and $l.Blank -ge 1) ($l | Out-String)
$l = Get-CardList (Read-AnyCells "$t\ds.xlsx" $w) 10
Check 'T2j xlsx ok (no Excel)' ($l.Errors.Count -eq 0 -and $l.Cards.Count -eq 4 -and $l.Cards[0].Stt -eq 5001 -and $l.Cards[0].Id -eq '2085405500' -and $l.Cards[2].Id -eq '0009569726' -and $l.Cards[0].Line -eq 4) ($l.Cards | Out-String)
Check 'T2k gaps' ((Get-SttGaps @([pscustomobject]@{ Stt = 1 }, [pscustomobject]@{ Stt = 2 }, [pscustomobject]@{ Stt = 5 }, [pscustomobject]@{ Stt = 7 })) -eq '3-4, 6')
$l = Get-CardList (Read-AnyCells "$t\ds.csv" $w) 8
Check 'T2l DoDai 8 too long' ($l.Errors.Count -eq 2) ($l.Errors -join '|')
$l = Get-CardList (Read-AnyCells "$t\ds-chu.xlsx" $w) 10
Check 'T2m xlsx text ids, col B' ($l.Errors.Count -eq 0 -and $l.Cards.Count -eq 2 -and $l.Cards[0].Raw -eq '0001234567' -and $l.Padded -eq 0 -and $l.Header.Line -eq 2 -and $l.Header.Stt -eq 1) ($l | Out-String)
$threw = ''; try { [void](Read-AnyCells "$t\khong-phai-xlsx.xlsx" $w) } catch { $threw = $_.Exception.Message }
Check 'T2n not a zip' ($threw -match 'không phải file Excel') $threw
Check 'T2o kinds' ((Get-FileKind "$t\sai-dinh-dang.nt") -eq 'xlsx' -and (Get-FileKind "$t\7001-7005.nt") -eq 'xls' -and (Get-FileKind "$t\ds.csv") -eq 'text')
$l = Get-CardList (Read-AnyCells "$t\sai-dinh-dang.nt" $w) 10
Check 'T2p xlsx renamed .nt read by content' ($l.Cards.Count -eq 4)
Remove-WorkDir $w

# ---- T3 ghi, đọc lại .nt
$w = New-WorkDir
$cards = @([pscustomobject]@{ Stt = 9001; Id = '0000000001'; Tinh = 1 }, [pscustomobject]@{ Stt = 9002; Id = '0123456789'; Tinh = 1 })
$n = Write-NtFile "$t\ghi.nt" $cards $w
Copy-Item "$t\ghi.nt" "$w\doc.xls"
$r = Read-AsSoftware "$w\doc.xls"
Check 'T3a write count' ($n -eq 2 -and $r.Rows.Count -eq 2)
Check 'T3b types' ($r.CardType -eq 'String' -and $r.SttType -eq 'Double')
Check 'T3c values' ($r.Rows[0].Card -eq '0000000001' -and $r.Rows[1].Stt -eq '9002' -and $r.Rows[1].Card -eq '0123456789')
Check 'T3d one sheet' ($r.Table -eq 'Sheet1$')
Check 'T3e template untouched' ((Get-Item "$repoTool\mau\mau-trong.xls").Length -eq 25600)
$threw = $false; try { [void](Write-NtFile "$t\rong.nt" @() $w) } catch { $threw = $true }
Check 'T3f empty refuses' $threw
# file có mã trùng (để thử xuất Excel)
[void](Write-NtFile "$t\trung.nt" @([pscustomobject]@{ Stt = 9101; Id = '0000000001'; Tinh = 1 }, [pscustomobject]@{ Stt = 9102; Id = '0000000001'; Tinh = 1 }, [pscustomobject]@{ Stt = 9103; Id = '0000000003'; Tinh = 1 }) $w)
Remove-WorkDir $w
Check 'T3g workdir removed' (-not (Test-Path $w))

# ---- T5 ghi, đọc .xlsx không cần Excel
$hdr = @('STT', 'CardID', 'Phần mềm đọc', 'Kết quả', 'Dòng')
$rows = @([object[]]@([int64]7001, '0009569726', '9569726', 'Mất số 0', [int64]2), [object[]]@([int64]7002, '0123456789', '<&>"''', 'Đúng', [int64]3), [object[]]@('x', '', '', 'Thiếu mã thẻ', [int64]4))
Write-XlsxFile "$t\w.xlsx" $hdr $rows -Widths 10, 14 -TextCols 1, 2 -MarkCol 3 -OkText 'Đúng'
Check 'T5a no tmp left' (-not (Test-Path "$t\w.xlsx.tmp"))
$c = Read-XlsxCells "$t\w.xlsx"
Check 'T5b read back' ($c.Count -eq 4 -and $c[0][2] -eq 'Phần mềm đọc' -and $c[1][0] -eq '7001' -and $c[1][1] -eq '0009569726' -and $c[2][2] -eq '<&>"''' -and $c[3][0] -eq 'x' -and $c[3][1] -eq '' -and $c[3][4] -eq '4') ($c | ForEach-Object { $_ -join '|' } | Out-String)
$xl = New-Object -ComObject Excel.Application; $xl.Visible = $false; $xl.DisplayAlerts = $false
try {
    $wb = $xl.Workbooks.Open("$t\w.xlsx", 0, $true); $ws = $wb.Worksheets.Item(1)
    Check 'T5c excel opens, 1 sheet' ($wb.Worksheets.Count -eq 1 -and $ws.Name -eq 'Sheet1')
    Check 'T5d STT number, CardID text' ($ws.Cells(2, 1).Value2 -is [double] -and $ws.Cells(2, 1).Value2 -eq 7001 -and $ws.Cells(2, 2).Value2 -is [string] -and $ws.Cells(2, 2).Value2 -eq '0009569726')
    Check 'T5e text format on CardID column' ($ws.Cells(50, 2).NumberFormat -eq '@' -and $ws.Cells(2, 2).NumberFormat -eq '@')
    Check 'T5f header bold, autofilter' ($ws.Cells(1, 1).Font.Bold -eq $true -and $ws.AutoFilterMode -eq $true)
    Check 'T5g mark red, ok plain' ($ws.Cells(2, 4).Interior.Color -eq 13551615 -and $ws.Cells(3, 4).Interior.ColorIndex -eq -4142) ("$($ws.Cells(2, 4).Interior.Color) $($ws.Cells(3, 4).Interior.ColorIndex)")
    Check 'T5h special chars' ($ws.Cells(3, 3).Value2 -eq '<&>"''' -and $ws.Cells(1, 3).Value2 -eq 'Phần mềm đọc')
    $wb.Close($false)
} finally { $xl.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl) }
# file đích đang bị khoá: báo lỗi, không để lại file tạm
$lock = [IO.File]::Open("$t\w.xlsx", 'Open', 'Read', 'None')
$threw = $false; try { Write-XlsxFile "$t\w.xlsx" $hdr $rows } catch { $threw = $true } finally { $lock.Dispose() }
Check 'T5i locked target' ($threw -and -not (Test-Path "$t\w.xlsx.tmp"))
# .xlsx viết tay: đích sheet tuyệt đối, sharedStrings có chữ nhiều đoạn và phiên âm, ô không có r, inlineStr, str, dòng cách quãng
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$hand = "$t\viet-tay.xlsx"
$z = [IO.Compression.ZipFile]::Open($hand, 'Create')
$main = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
$parts = @{
    '[Content_Types].xml'        = '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/></Types>'
    '_rels/.rels'                = '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="r1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
    'xl/workbook.xml'            = "<?xml version=`"1.0`"?><x:workbook xmlns:x=`"$main`" xmlns:r=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships`"><x:sheets><x:sheet name=`"DS`" sheetId=`"7`" r:id=`"rIdA`"/><x:sheet name=`"Khac`" sheetId=`"8`" r:id=`"rIdB`"/></x:sheets></x:workbook>"
    'xl/_rels/workbook.xml.rels' = '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdB" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/khac.xml"/><Relationship Id="rIdA" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/ds.xml"/><Relationship Id="rIdS" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="chu.xml"/></Relationships>'
    'xl/chu.xml'                 = "<?xml version=`"1.0`"?><sst xmlns=`"$main`"><si><r><t>SỐ </t></r><r><t>THẺ</t></r><rPh><t>phien am</t></rPh></si><si><t>0000000042</t></si></sst>"
    'xl/worksheets/ds.xml'       = "<?xml version=`"1.0`"?><worksheet xmlns=`"$main`"><sheetData><row r=`"1`"><c t=`"s`"><v>0</v></c><c t=`"inlineStr`"><is><t>ID</t></is></c></row><row r=`"4`"><c r=`"A4`"><v>41</v></c><c r=`"B4`" t=`"s`"><v>1</v></c></row><row><c><v>4.2E1</v></c><c t=`"str`"><v> 43 </v></c><c r=`"AB5`"><v>9</v></c></row></sheetData></worksheet>"
    'xl/worksheets/khac.xml'     = "<?xml version=`"1.0`"?><worksheet xmlns=`"$main`"><sheetData><row r=`"1`"><c t=`"inlineStr`"><is><t>sai sheet</t></is></c></row></sheetData></worksheet>"
}
foreach ($k in $parts.Keys) { $s = $z.CreateEntry($k).Open(); $b = [Text.Encoding]::UTF8.GetBytes($parts[$k]); $s.Write($b, 0, $b.Length); $s.Dispose() }
$z.Dispose()
$c = Read-XlsxCells $hand
Check 'T5j hand-made xlsx' ($c.Count -eq 5 -and $c[0][0] -eq 'SỐ THẺ' -and $c[0][1] -eq 'ID' -and $c[1].Count -eq 0 -and $c[3][0] -eq '41' -and $c[3][1] -eq '0000000042' -and $c[4][0] -eq '42' -and $c[4][1] -eq '43' -and $c[4].Count -eq 2) ($c | ForEach-Object { '[' + ($_ -join '|') + ']' } | Out-String)
$w = New-WorkDir
$l = Get-CardList (Read-AnyCells $hand $w) 10
Remove-WorkDir $w
Check 'T5k hand-made list' ($l.Cards.Count -eq 2 -and $l.Cards[0].Id -eq '0000000042' -and $l.Cards[1].Id -eq '0000000043') ($l | Out-String)

# ---- T4 chạy cả script
$r = Run @('-Mode', 'xem', '-File', "$t\7001-7005.nt")
Check 'T4a xem seller 0' ($r.Code -eq 0 -and $r.Out -match 'CardID lưu dạng số: phần mềm đọc thẻ 7001 là 1234567' -and $r.Out -match 'Cần sửa') $r.Out
$r = Run @('-Mode', 'xem', '-File', "$t\tron.nt")
Check 'T4b xem mixed' ($r.Out -match 'File có 9 thẻ nhưng phần mềm chỉ nạp được 6') $r.Out
$r = Run @('-Mode', 'xem', '-File', "$t\sai-dinh-dang.nt")
Check 'T4c xem xlsx renamed' ($r.Code -eq 0 -and $r.Out -match 'Không đọc được như file Excel 97-2003' -and $r.Out -match '\.xlsx đổi đuôi') $r.Out
$r = Run @('-Mode', 'xem', '-File', "$t\khong-co.nt")
Check 'T4d missing file 2' ($r.Code -eq 2)
$r = Run @('-Mode', 'xem', '-File', "$t\ds.csv")
Check 'T4e xem wrong ext 2' ($r.Code -eq 2)
$before = (Get-FileHash "$t\7001-7005.nt").Hash
$r = Run @('-Mode', 'sua', '-File', "$t\7001-7005.nt")
Check 'T4f sua 0' ($r.Code -eq 0) $r.Out
Check 'T4g sua outputs' ((Test-Path "$t\da-sua\7001-7005.nt") -and (Test-Path "$t\da-sua\7001-7005.xls") -and (Test-Path "$t\da-sua\thu-7001.nt"))
Check 'T4h original untouched' ((Get-FileHash "$t\7001-7005.nt").Hash -eq $before)
$w = New-WorkDir; Copy-Item "$t\da-sua\7001-7005.nt" "$w\a.xls"; Copy-Item "$t\da-sua\thu-7001.nt" "$w\b.xls"
$a = Read-AsSoftware "$w\a.xls"; $b = Read-AsSoftware "$w\b.xls"; Remove-WorkDir $w
Check 'T4i sua content' ($a.Rows.Count -eq 5 -and $a.Rows[2].Card -eq '0000345678' -and $a.Rows[3].Card -eq '0011223344' -and $a.CardType -eq 'String')
Check 'T4j test file 1 card' ($b.Rows.Count -eq 1 -and $b.Rows[0].Stt -eq '7001' -and $b.Rows[0].Card -eq '0001234567')
$r = Run @('-Mode', 'sua', '-File', "$t\7001-7005.nt")
Check 'T4k exists, no input -> 1223' ($r.Code -eq 1223) $r.Out
$r = Run @('-Mode', 'sua', '-File', "$t\da-sua\7001-7005.nt")
Check 'T4l already correct' ($r.Code -eq 0 -and $r.Out -match 'Không cần sửa' -and -not (Test-Path "$t\da-sua\da-sua"))
$r = Run @('-Mode', 'sua', '-File', "$t\7001-7005.nt", '-ThuMuc', $t)
Check 'T4m refuse overwrite original' ($r.Code -eq 2 -and $r.Out -match 'trùng thư mục file gốc') $r.Out
$r = Run @('-Mode', 'tao', '-File', "$t\ds.xlsx", '-ThuMuc', "$t\out\")
Check 'T4n tao xlsx' ($r.Code -eq 0 -and (Test-Path "$t\out\5001-5004.nt") -and (Test-Path "$t\out\thu-5001.nt")) $r.Out
$r = Run @('-Mode', 'tao', '-File', "$t\ds.csv")
Check 'T4o tao csv default dir' ($r.Code -eq 0 -and (Test-Path "$t\2132-2134.nt")) $r.Out
$r = Run @('-Mode', 'tao', '-File', "$t\loi.csv")
Check 'T4p tao errors -> 1, nothing written' ($r.Code -eq 1 -and -not (Get-ChildItem $t -Filter '1-*.nt')) $r.Out
$r = Run @('-Mode', 'xoa', '-File', "$t\ds.csv")
Check 'T4q bad mode 1' ($r.Code -eq 1)
$r = Run @('-Mode', 'tao', '-File', "$t\ds.csv", '-DoDai', '3')
Check 'T4r DoDai range' ($r.Code -ne 0)
$r = Run @('-Mode', 'sua', '-File', "$t\sai-dinh-dang.nt")
$w = New-WorkDir; Copy-Item "$t\da-sua\sai-dinh-dang.nt" "$w\s.xls" -ErrorAction SilentlyContinue; $s = Read-AsSoftware "$w\s.xls"; Remove-WorkDir $w
Check 'T4t sua xlsx renamed' ($r.Code -eq 0 -and $r.Out -match '\.xlsx đổi đuôi' -and $s.Rows.Count -eq 4 -and $s.Rows[2].Card -eq '0009569726') $r.Out

# ---- T6 chuyển .nt sang Excel
$r = Run @('-Mode', 'xuat', '-File', "$t\7001-7005.nt")
$c = if (Test-Path "$t\7001-7005.xlsx") { Read-XlsxCells "$t\7001-7005.xlsx" } else { @() }
Check 'T6a xuat seller' ($r.Code -eq 0 -and $c.Count -eq 6 -and $c[0][1] -eq 'CardID' -and $c[1][0] -eq '7001' -and $c[1][1] -eq '0001234567' -and $c[1][2] -eq '1234567' -and $c[1][3] -like 'Mất số 0*' -and $c[1][4] -eq '2' -and $r.Out -match 'Mất số 0: 5 thẻ') ($r.Out + ($c | ForEach-Object { $_ -join '|' } | Out-String))
Check 'T6b original untouched' ((Get-FileHash "$t\7001-7005.nt").Hash -eq $before)
$r = Run @('-Mode', 'xuat', '-File', "$t\7001-7005.nt")
Check 'T6c exists -> 1223' ($r.Code -eq 1223) $r.Out
$r = Run @('-Mode', 'xuat', '-File', "$t\da-sua\7001-7005.nt", '-ThuMuc', "$t\xuat2")
$c = if (Test-Path "$t\xuat2\7001-7005.xlsx") { Read-XlsxCells "$t\xuat2\7001-7005.xlsx" } else { @() }
Check 'T6d fixed file all Đúng' ($r.Code -eq 0 -and $c.Count -eq 6 -and -not @($c | Select-Object -Skip 1 | Where-Object { $_[3] -ne 'Đúng' }).Count -and $r.Out -match 'Đúng: 5 thẻ') $r.Out
$r = Run @('-Mode', 'xuat', '-File', "$t\tron.nt")
$c = if (Test-Path "$t\tron.xlsx") { Read-XlsxCells "$t\tron.xlsx" } else { @() }
Check 'T6e mixed: 3 skipped' ($r.Code -eq 0 -and @($c | Where-Object { $_[3] -like 'Phần mềm bỏ qua*' }).Count -eq 3 -and @($c | Where-Object { $_[3] -eq 'Đúng' }).Count -eq 6 -and $c[3][2] -eq '(bỏ qua dòng này)') $r.Out
$r = Run @('-Mode', 'xuat', '-File', "$t\giua-trong.nt")
$c = if (Test-Path "$t\giua-trong.xlsx") { Read-XlsxCells "$t\giua-trong.xlsx" } else { @() }
Check 'T6f blank row: lines align' ($r.Code -eq 0 -and $c.Count -eq 4 -and $c[3][4] -eq '5' -and -not @($c | Select-Object -Skip 1 | Where-Object { $_[3] -ne 'Đúng' }).Count) ($r.Out + ($c | ForEach-Object { $_ -join '|' } | Out-String))
$r = Run @('-Mode', 'xuat', '-File', "$t\trung.nt")
$c = if (Test-Path "$t\trung.xlsx") { Read-XlsxCells "$t\trung.xlsx" } else { @() }
Check 'T6g duplicates marked' ($r.Code -eq 0 -and $c[1][3] -eq 'Mã trùng với thẻ 9102' -and $c[2][3] -eq 'Mã trùng với thẻ 9101' -and $c[3][3] -eq 'Đúng') ($c | ForEach-Object { $_ -join '|' } | Out-String)
$r = Run @('-Mode', 'xuat', '-File', "$t\sai-dinh-dang.nt")
$c = if (Test-Path "$t\sai-dinh-dang.xlsx") { Read-XlsxCells "$t\sai-dinh-dang.xlsx" } else { @() }
Check 'T6h xlsx renamed' ($r.Code -eq 0 -and $c.Count -eq 5 -and $c[1][3] -like 'Phần mềm không đọc được file*' -and $c[3][1] -eq '0009569726') $r.Out
# vòng: .nt -> Excel -> .nt
$r = Run @('-Mode', 'tao', '-File', "$t\7001-7005.xlsx", '-ThuMuc', "$t\vong")
$w = New-WorkDir; Copy-Item "$t\vong\7001-7005.nt" "$w\v.xls" -ErrorAction SilentlyContinue; $v = Read-AsSoftware "$w\v.xls"; Remove-WorkDir $w
Check 'T6i round trip' ($r.Code -eq 0 -and $v.CardType -eq 'String' -and $v.Rows.Count -eq 5 -and $v.Rows[0].Card -eq '0001234567' -and $v.Rows[4].Card -eq '0005566778') $r.Out
$r = Run @('-Mode', 'xuat', '-File', "$t\ds.csv")
Check 'T6j wrong ext 2' ($r.Code -eq 2)

# ---- T7 kiểm tra .nt so với danh sách
$r = Run @('-Mode', 'xem', '-File', "$t\7001-7005.nt", '-DanhSach', "$t\so-7001.csv")
Check 'T7a compare' ($r.Code -eq 0 -and $r.Out -match 'Mất số 0: 2 thẻ' -and $r.Out -match 'Khác mã: 1 thẻ' -and $r.Out -match 'Thẻ 7003: file 345678, danh sách 0000345679' -and $r.Out -match 'không có trong file \.nt: 1 thẻ: 7006' -and $r.Out -match 'không có trong danh sách: 2 thẻ: 7004-7005' -and $r.Out -match 'không khớp danh sách') $r.Out
$r = Run @('-Mode', 'xem', '-File', "$t\7001-7005.nt", '-DanhSach', "$t\so-7001-du.csv")
Check 'T7b only zeros' ($r.Out -match 'Mất số 0: 5 thẻ' -and $r.Out -match 'sửa xong là đúng' -and $r.Out -notmatch 'không khớp danh sách') $r.Out
$r = Run @('-Mode', 'xem', '-File', "$t\da-sua\7001-7005.nt", '-DanhSach', "$t\7001-7005.xlsx")
Check 'T7c fixed vs exported list' ($r.Code -eq 0 -and $r.Out -match 'Khớp: 5 thẻ' -and $r.Out -match 'Khớp danh sách') $r.Out
$r = Run @('-Mode', 'xem', '-File', "$t\7001-7005.nt", '-DanhSach', "$t\khong-co.xlsx")
Check 'T7d missing list 2' ($r.Code -eq 2)
$r = Run @('-Mode', 'xem', '-File', "$t\7001-7005.nt", '-DanhSach', "$t\khong-tieu-de.csv")
Check 'T7e list without header' ($r.Code -eq 0 -and $r.Out -match 'Chưa so được') $r.Out
$r = Run @('-Mode', 'xem', '-File', "$t\7001-7005.nt", '-DanhSach', "$t\khong-phai-xlsx.xlsx")
Check 'T7f list not readable' ($r.Code -eq 0 -and $r.Out -match 'Không đọc được danh sách') $r.Out

$rep = @(Get-ChildItem "$tool\ket_qua" -Filter '*.txt')
Check 'T8a reports in copy' ($rep.Count -ge 10)
$left = @(Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'TheXe_*')
Check 'T8b no temp left' ($left.Count -eq 0) ($left.Name -join ',')

Complete-Test
