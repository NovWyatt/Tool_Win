# Hết đầu vào giữa chừng, manifest kiểu cũ, file gốc bị xoá, manifest hỏng, kiểm tra tham số HOAN_TAC.bat.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
. "$PSScriptRoot\_GiaLap.ps1"
if (Test-ExcelOpenHere) { Skip-Test 'Excel đang mở trong phiên này (bản sửa chờ đóng Excel): đóng Excel rồi chạy lại'; Complete-Test }

# ---------------------------------------------------------------- end of input (no MYX_AUTO, stdin redirected)
$root = Join-Path $TestRoot 'fx3'
$rb = 'Software\TramToolTest\Myx3\'
New-Fixture $root $rb
$envIn = Get-FixEnv $root $rb $false

Write-Host '== T3a: fix with empty stdin ==' -ForegroundColor Cyan
$r = Invoke-Bat "$Tool\FixMyExcel_VietQR.bat" -Env $envIn -StdIn '' -TimeoutSec 60
$r.Out | Set-Content (Join-Path $root 'eof_a.txt') -Encoding UTF8
Check ($r.Code -eq 2) "exit 2 (got $($r.Code), $($r.Sec)s)"
Check ($r.Sec -lt 30) 'stops quickly instead of looping'
Check ($r.Out -match 'Hết đầu vào') 'prints end-of-input message'
Check (@(Get-ChildItem (Join-Path $root 'out') -Directory -Filter 'MyExcelFix_SaoLuu_*').Count -eq 0) 'no backup dir (nothing started)'
$j = Get-Content @(Get-ChildItem (Join-Path $root 'out') -Filter 'KetQua_MyExcel_Sua_*.json')[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($j.ma -eq 'HET_DAU_VAO' -and $j.maThoat -eq 2 -and $j.trangThai -eq 'thieu-dieu-kien') "JSON: $($j.ma) $($j.maThoat) $($j.trangThai)"
Remove-Item (Join-Path $root 'out\*') -Recurse -Force

Write-Host '== T3b: answers Y + Enter, then input ends at the rename question (after backup, nothing changed) ==' -ForegroundColor Cyan
$r = Invoke-Bat "$Tool\FixMyExcel_VietQR.bat" -Env $envIn -StdIn "Y`r`n`r`n" -TimeoutSec 60
$r.Out | Set-Content (Join-Path $root 'eof_b.txt') -Encoding UTF8
Check ($r.Code -eq 2) "exit 2 (got $($r.Code), $($r.Sec)s)"
Check (@(Get-ChildItem (Join-Path $root 'out') -Directory -Filter 'MyExcelFix_SaoLuu_*').Count -eq 1) 'backup dir exists'
Check ((Test-Path (Join-Path $root 'MyExcel_old')) -and -not (Test-Path (Join-Path $root 'MyExcel_old_cu'))) 'folder not renamed'
Check ($r.Out -match 'Chưa thay đổi gì') 'says nothing changed'
Remove-Item (Join-Path $root 'out\*') -Recurse -Force

Write-Host '== T3c: Y + Enter + Y, input ends at the workbook question (real changes made) ==' -ForegroundColor Cyan
$r = Invoke-Bat "$Tool\FixMyExcel_VietQR.bat" -Env $envIn -StdIn "Y`r`n`r`nY`r`n" -TimeoutSec 60
$r.Out | Set-Content (Join-Path $root 'eof_c.txt') -Encoding UTF8
Check ($r.Code -eq 3) "exit 3 (got $($r.Code), $($r.Sec)s)"
Check (Test-Path (Join-Path $root 'MyExcel_old_cu')) 'folder renamed before input ended'
$bk = @(Get-ChildItem (Join-Path $root 'out') -Directory -Filter 'MyExcelFix_SaoLuu_*')[0].FullName
$j = Get-Content @(Get-ChildItem (Join-Path $root 'out') -Filter 'KetQua_MyExcel_Sua_*.json')[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($j.ma -eq 'HET_DAU_VAO' -and $j.maThoat -eq 3 -and $j.soThayDoi -gt 0) "JSON: $($j.ma) $($j.maThoat) soThayDoi=$($j.soThayDoi)"
Check (Test-Path (Join-Path $bk 'NhatKy_Sua.txt')) 'log written in backup dir'

Write-Host '== T3d: undo with empty stdin ==' -ForegroundColor Cyan
$r = Invoke-Bat "$bk\HoanTac_FixMyExcel.bat" -Env $envIn -StdIn '' -TimeoutSec 60
Check ($r.Code -eq 2) "undo exit 2 (got $($r.Code), $($r.Sec)s)"
Check (Test-Path (Join-Path $root 'MyExcel_old_cu')) 'nothing undone'
Check (@(Get-ChildItem $bk -Directory -Filter 'TruocHoanTac_*').Count -eq 0) 'no pre-undo export (stopped at the question)'

Write-Host '== T3e: HOAN_TAC.bat argument checks ==' -ForegroundColor Cyan
# Không kèm thư mục thì HOAN_TAC.bat tìm bản sao lưu trong LOCALAPPDATA và Desktop thật: thử ở 4_NoiLuu (T5c, T5d)
# với các thư mục đó trỏ vào thư mục tạm, không gọi ở đây.
$sb = New-TestDir 'fx3noi'
$envArg = @{ MYX_NOPAUSE = '1'; LOCALAPPDATA = $sb; PUBLIC = $sb; MYX_DESKTOP = $sb; MYX_OUT = (Join-Path $root 'out') }
$r = Invoke-Bat "$Tool\HOAN_TAC.bat" -BatArgs @((Join-Path $root 'khong_co')) -Env $envArg -TimeoutSec 30
Check ($r.Code -eq 2) "missing folder -> 2 (got $($r.Code))"
$r = Invoke-Bat "$Tool\HOAN_TAC.bat" -BatArgs @((Join-Path $root 'scan')) -Env $envArg -TimeoutSec 30
Check ($r.Code -eq 2) "folder without manifest -> 2 (got $($r.Code))"

# ---------------------------------------------------------------- old-format manifest, missing original, corrupt manifest
$root = Join-Path $TestRoot 'fx2'
$rb = 'Software\TramToolTest\Myx2\'
New-Fixture $root $rb
$envFix = Get-FixEnv $root $rb
Write-Host '== T2a: fix, then turn the manifest into the old format (absolute paths, no hashes) ==' -ForegroundColor Cyan
$r = Invoke-Bat "$Tool\FixMyExcel_VietQR.bat" -Env $envFix
Check ($r.Code -eq 0) "fix exit 0 (got $($r.Code))"
$bk = @(Get-ChildItem (Join-Path $root 'out') -Directory -Filter 'MyExcelFix_SaoLuu_*')[0].FullName
$mfPath = Join-Path $bk 'manifest.json'
$m = Get-Content $mfPath -Raw -Encoding UTF8 | ConvertFrom-Json
$old = [ordered]@{ Time = $m.Time; User = $m.User; Computer = $m.Computer; Target = $m.Target; RegBase = $m.RegBase; RegExcel = $m.RegExcel; RegVB = $m.RegVB
    NewKeys = $m.NewKeys; ResetKeys = $m.ResetKeys; Folders = $m.Folders
    Workbooks = @($m.Workbooks | ForEach-Object { [ordered]@{ Original = $_.Original; Backup = (Join-Path $bk $_.Backup) } }) }
[IO.File]::WriteAllText($mfPath, ($old | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
$hoaDonAfter = Get-Hash (Join-Path $root 'scan\HoaDon.xlsx')
Remove-Item (Join-Path $root 'scan\SoQuy.xlsx')   # user moved/deleted one fixed workbook
Remove-Item (Join-Path $root 'out\KetQua_*.json')

Write-Host '== T2b: undo by double-clicking the HoanTac copy in the backup dir ==' -ForegroundColor Cyan
$r = Invoke-Bat "$bk\HoanTac_FixMyExcel.bat" -Env $envFix
$r.Out | Set-Content (Join-Path $root 'undo_old.txt') -Encoding UTF8
Check ($r.Code -eq 3) "exit 3: done with a warning for the missing file (got $($r.Code))"
$kept = Join-Path $root 'scan\HoaDon.truoc_hoantac.xlsx'
Check ((Test-Path $kept) -and (Get-Hash $kept) -eq $hoaDonAfter) 'old manifest without hashes: current HoaDon kept before restoring'
Check (-not (Test-Path (Join-Path $root 'scan\SoQuy.xlsx'))) 'missing SoQuy.xlsx not recreated'
Check ($r.Out -match 'không còn ở chỗ cũ') 'warns about the missing file'
Check (Test-Path (Join-Path $root 'MyExcel_old')) 'folder renamed back'
$j = Get-Content @(Get-ChildItem (Join-Path $root 'out') -Filter 'KetQua_MyExcel_HoanTac_*.json')[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($j.ma -eq 'CO_CANH_BAO' -and $j.soCanhBao -ge 1 -and $j.thuMucSaoLuu -eq $bk) "JSON: $($j.ma) canhBao=$($j.soCanhBao)"

Write-Host '== T2c: second undo run also keeps a timestamped copy instead of overwriting the first keep file ==' -ForegroundColor Cyan
$r = Invoke-Bat "$bk\HoanTac_FixMyExcel.bat" -Env $envFix
Check (@(Get-ChildItem (Join-Path $root 'scan') -Filter 'HoaDon.truoc_hoantac*.xlsx').Count -eq 2) 'two keep copies after two undo runs'
Check ((Get-Hash $kept) -eq $hoaDonAfter) 'first keep copy untouched'

Write-Host '== T2d: corrupt manifest ==' -ForegroundColor Cyan
Set-Content $mfPath '{ hong' -Encoding ASCII
$r = Invoke-Bat "$bk\HoanTac_FixMyExcel.bat" -Env $envFix
Check ($r.Code -eq 1) "corrupt manifest -> 1 (got $($r.Code))"

Assert-RealUntouched
Clear-TestRegistry
Complete-Test
