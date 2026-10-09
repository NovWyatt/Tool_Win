# Sửa (tự động) rồi hoàn tác trên bộ MyExcel giả, registry giả trong HKCU\Software\TramToolTest.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
. "$PSScriptRoot\_GiaLap.ps1"
if (Test-ExcelOpenHere) { Skip-Test 'Excel đang mở trong phiên này (bản sửa chờ đóng Excel): đóng Excel rồi chạy lại'; Complete-Test }
$root = Join-Path $TestRoot 'fx1'
$rb = 'Software\TramToolTest\Myx1\'
New-Fixture $root $rb
$envFix = Get-FixEnv $root $rb

Write-Host '== T1a: fix (auto) ==' -ForegroundColor Cyan
$r = Invoke-Bat "$Tool\FixMyExcel_VietQR.bat" -Env $envFix
$r.Out | Set-Content (Join-Path $root 'fix_out.txt') -Encoding UTF8
Check ($r.Code -eq 0) "fix exit code 0 (got $($r.Code), $($r.Sec)s)"
$bk = @(Get-ChildItem (Join-Path $root 'out') -Directory -Filter 'MyExcelFix_SaoLuu_*')[0].FullName
Check ([bool]$bk) "backup dir created: $bk"
$m = Get-Content (Join-Path $bk 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($m.Format -eq 2 -and $m.Version -eq '2026.10.1') "manifest Format=2 Version=$($m.Version)"
Check (@($m.Workbooks).Count -eq 2) "manifest has 2 workbooks"
foreach ($w in $m.Workbooks) {
    Check ($w.Backup -like 'Workbooks\*') "relative backup path $($w.Backup)"
    Check ($w.HashAfter -eq (Get-Hash $w.Original)) "HashAfter matches $($w.Original | Split-Path -Leaf)"
    Check ($w.HashBackup -eq (Get-Hash (Join-Path $bk $w.Backup))) "HashBackup matches backup copy"
}
Check (-not (Test-Path (Join-Path $root 'manifest.json.tmp')) -and -not (Test-Path (Join-Path $bk 'manifest.json.tmp'))) 'no leftover manifest.json.tmp'
Check ((Test-Path (Join-Path $root 'MyExcel_old_cu')) -and -not (Test-Path (Join-Path $root 'MyExcel_old'))) 'extra install renamed to _cu'
$open = Get-RegVal ($rb + 'Software\Microsoft\Office\16.0\Excel\Options') 'OPEN'
Check ($open -like "*$root\MyExcel\MyExcel.xlam*") "OPEN now points to standard set: $open"
Check (-not (Test-Path (Join-Path $root 'env\temp\VBE\MSForms.exd'))) 'fake .exd in redirected TEMP removed'
$link = Get-ZipText (Join-Path $root 'scan\SoQuy.xlsx') 'xl/externalLinks/_rels/externalLink1.xml.rels'
Check ($link -like "*$root\MyExcel\MiniTool\QRCodeLib.xlam*") 'workbook link repointed'
Check ($null -eq (Get-RegVal ($rb + 'Software\VB and VBA Program Settings\liliiliiliiiliilli\GridLight') 'TenTKQRG')) 'MyExcel data reset'
$res = @(Get-ChildItem (Join-Path $root 'out') -Filter 'KetQua_MyExcel_Sua_*.json')
Check ($res.Count -eq 1) 'fix result JSON written'
$j = Get-Content $res[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($j.maThoat -eq 0 -and $j.ma -eq 'XONG' -and $j.cheDo -eq 'sua' -and $j.trangThai -eq 'xong' -and $j.phienBan -eq '2026.10.1') "fix JSON: $($j.maThoat) $($j.ma) $($j.cheDo) $($j.trangThai) $($j.phienBan) soThayDoi=$($j.soThayDoi)"
Check ($j.thuMucSaoLuu -eq $bk) 'fix JSON points to backup dir'
Check (Test-Path (Join-Path $bk 'NhatKy_Sua.txt')) 'fix log written'

Write-Host '== T1b: user edits HoaDon.xlsx after the fix, then undo via HOAN_TAC.bat ==' -ForegroundColor Cyan
Edit-Zip (Join-Path $root 'scan\HoaDon.xlsx')
$edited = Get-Hash (Join-Path $root 'scan\HoaDon.xlsx')
$envUndo = Get-FixEnv $root $rb
$r = Invoke-Bat "$Tool\HOAN_TAC.bat" -BatArgs @($bk) -Env $envUndo
$r.Out | Set-Content (Join-Path $root 'undo_out.txt') -Encoding UTF8
Check ($r.Code -eq 0) "undo exit code 0 (got $($r.Code), $($r.Sec)s)"
$wb = @{}; foreach ($w in $m.Workbooks) { $wb[(Split-Path $w.Original -Leaf)] = $w }
Check ((Get-Hash (Join-Path $root 'scan\SoQuy.xlsx')) -eq $wb['SoQuy.xlsx'].HashBackup) 'SoQuy.xlsx (unchanged) restored to pre-fix copy'
Check ((Get-Hash (Join-Path $root 'scan\HoaDon.xlsx')) -eq $wb['HoaDon.xlsx'].HashBackup) 'HoaDon.xlsx restored to pre-fix copy'
$kept = Join-Path $root 'scan\HoaDon.truoc_hoantac.xlsx'
Check ((Test-Path $kept) -and (Get-Hash $kept) -eq $edited) 'edited HoaDon kept as HoaDon.truoc_hoantac.xlsx with the new data'
Check (-not (Test-Path (Join-Path $root 'scan\SoQuy.truoc_hoantac.xlsx'))) 'no keep copy for the unchanged file'
$pre = @(Get-ChildItem $bk -Directory -Filter 'TruocHoanTac_*')
Check ($pre.Count -eq 1 -and (Test-Path (Join-Path $pre[0].FullName 'Excel_16.0.reg')) -and (Test-Path (Join-Path $pre[0].FullName 'VBA_Settings.reg'))) 'current state exported to TruocHoanTac_* before undo'
Check ((Test-Path (Join-Path $root 'MyExcel_old')) -and -not (Test-Path (Join-Path $root 'MyExcel_old_cu'))) 'folder renamed back'
$open = Get-RegVal ($rb + 'Software\Microsoft\Office\16.0\Excel\Options') 'OPEN'
Check ($open -like "*MyExcel_old\MyExcel.xlam*") "OPEN restored: $open"
Check ((Get-RegVal ($rb + 'Software\VB and VBA Program Settings\liliiliiliiiliilli\GridLight') 'TenTKQRG') -eq 'NGUOI THU NGHIEM') 'MyExcel data restored'
$tl = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($rb + 'Software\Microsoft\Office\16.0\Excel\Security\Trusted Locations')
$tlSubs = if ($tl) { @($tl.GetSubKeyNames()) } else { @() }
Check ($tlSubs.Count -eq 0) "Trusted Location added by the fix removed (left: $($tlSubs -join ','))"
$res = @(Get-ChildItem (Join-Path $root 'out') -Filter 'KetQua_MyExcel_HoanTac_*.json')
Check ($res.Count -eq 1) 'undo result JSON written'
$j = Get-Content $res[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($j.maThoat -eq 0 -and $j.cheDo -eq 'hoan-tac' -and @($j.giuLai).Count -eq 1 -and $j.giuLai[0] -eq $kept) "undo JSON: $($j.maThoat) $($j.ma) giuLai=$($j.giuLai -join ';')"
Check (@(Get-ChildItem $bk -Filter 'NhatKy_HoanTac_*.txt').Count -eq 1) 'undo log written'

Clear-TestRegistry
Complete-Test
