# Các script chuyên sâu (2-CHAN-DOAN-PHAN-CUNG, 3-GIAI-MA-WHEA, 4-XUAT-BANG-CHUNG, 5-CHAN-DOAN-SUP-NGUON): mỗi kết luận
# có mã cố định, mức, việc chạy tiếp có thật; file KetQua_CheckWinFix_<chế độ>_*.json theo chuẩn mà Trạm đọc được.
# Không chạy file .bat thật (sẽ hỏi UAC): tách phần PowerShell, chạy bằng quyền thường với -KhongHoi (không hỏi tạo
# Custom View, không hỏi đổi CrashControl hay bật theo dõi) và CWF_KHONG_MO (không mở Notepad, Explorer). Chỉ đọc
# nhật ký, SMART, cài đặt nguồn; báo cáo, hồ sơ, file kết quả vào thư mục tạm.
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\Catalog.ps1"; . "$HubDir\lib\Checks.ps1"; . "$HubDir\lib\KetQua.ps1"
$cat = Get-HubCatalog -ToolsDir $ToolsDir -RootDir $RepoRoot
$tj = [IO.File]::ReadAllText("$ToolsDir\checkwinfix\tool.json", [Text.Encoding]::UTF8) | ConvertFrom-Json
$marker = '#=====PS_START====='
# Ten: phần tên file kết quả; Out: báo cáo (hoặc thư mục hồ sơ) cạnh file kết quả; Min: số mã tối thiểu trong script.
$scripts = [ordered]@{
    '2-CHAN-DOAN-PHAN-CUNG.bat' = @{ Ten = 'PhanCung'; Out = 'HwDiag_*.txt'; Min = 12; Args = '' }
    '3-GIAI-MA-WHEA.bat'        = @{ Ten = 'GiaiMaWhea'; Out = 'WheaDecode_*.txt'; Min = 8; Args = '' }
    '4-XUAT-BANG-CHUNG.bat'     = @{ Ten = 'BangChung'; Out = 'HoSoBangChung_*'; Min = 6; Args = '-KhongHoi' }
    '5-CHAN-DOAN-SUP-NGUON.bat' = @{ Ten = 'SupNguon'; Out = 'SupNguon_*.txt'; Min = 22; Args = '-KhongHoi' }
}
function Get-PsPart([string]$File) { $raw = [IO.File]::ReadAllText("$ToolsDir\checkwinfix\$File"); return $raw.Substring($raw.IndexOf($marker) + $marker.Length) }
function Test-Target([string]$Target) {
    $p = $Target -split '/'
    $tool = @($cat | Where-Object { $_.id -eq $p[0] })[0]
    return [bool]($tool -and @($tool.actions | Where-Object { $_.id -eq $p[1] -and $_.exists }).Count)
}
function Get-Named($Cmd, [string]$Name) {
    $e = @($Cmd.CommandElements)
    for ($i = 1; $i -lt $e.Count - 1; $i++) { if ($e[$i] -is [Management.Automation.Language.CommandParameterAst] -and $e[$i].ParameterName -eq $Name) { return $e[$i + 1] } }
    return $null
}

Write-KT '1. Mã, mức, việc chạy tiếp khai trong từng script' Cyan
$asts = @{}
foreach ($file in $scripts.Keys) {
    $info = $scripts[$file]
    $errs = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput((Get-PsPart $file), [ref]$null, [ref]$errs)
    $asts[$file] = $ast
    Check ($errs.Count -eq 0) "${file}: phần PowerShell không lỗi cú pháp ($(@($errs | ForEach-Object { "$($_.Message) dòng $($_.Extent.StartLineNumber)" }) -join '; '))"
    $codes = @(); $bad = @(); $targets = @()
    foreach ($c in @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in 'FLAG', 'Warn' }, $true))) {
        $fn = $c.Parent
        while ($fn -and $fn -isnot [Management.Automation.Language.FunctionDefinitionAst]) { $fn = $fn.Parent }
        if ($fn -and $fn.Name -eq 'Warn') { continue }   # Warn chuyển tiếp mã của nó cho FLAG
        $ma = Get-Named $c 'Ma'
        if (-not $ma -and $c.GetCommandName() -eq 'FLAG') { $ma = $c.CommandElements[1] }
        if ($ma -isnot [Management.Automation.Language.StringConstantExpressionAst] -or $ma.Value -notmatch '^[A-Z][A-Z0-9_]+$') { $bad += $c.Extent.StartLineNumber; continue }
        $codes += $ma.Value
        $ti = Get-Named $c 'Tiep'
        if ($ti) { if ($ti -is [Management.Automation.Language.StringConstantExpressionAst]) { $targets += $ti.Value } else { $bad += $c.Extent.StartLineNumber } }
    }
    $dup = @($codes | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    Check ($codes.Count -ge $info.Min -and -not $bad.Count -and -not $dup.Count) "${file}: $($codes.Count) chỗ ghi kết luận có mã CHU_HOA riêng (thiếu mã ở dòng: $($bad -join ', '); trùng: $($dup -join ', '))"
    $missing = @($targets | Sort-Object -Unique | Where-Object { -not (Test-Target $_) })
    Check (-not $missing.Count) "${file}: việc chạy tiếp có trong danh mục ($(@($targets | Sort-Object -Unique) -join ', '); thiếu: $($missing -join ', '))"
    $action = @($tj.actions | Where-Object { $_.file -eq $file })[0]
    $saves = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Save-KetQua' }, $true))
    $okSave = @($saves | Where-Object { (Get-Named $_ 'CheDo').Value -eq $action.id -and (Get-Named $_ 'Ten').Value -eq $info.Ten })
    Check ($saves.Count -ge 1 -and $okSave.Count -eq $saves.Count) "${file}: ghi kết quả với cheDo '$($action.id)', tên KetQua_CheckWinFix_$($info.Ten)_*.json ($($saves.Count) chỗ)"
    $glob = "KetQua_CheckWinFix_$($info.Ten)_%COMPUTERNAME%_*.json"
    Check (@($tj.outputs | Where-Object { $_.glob -eq $glob -and $_.ketQua }).Count -eq 1) "${file}: tool.json khai $glob với ketQua"
}

Write-KT '2. FLAG, Save-KetQua (hàm tách từ 2-CHAN-DOAN-PHAN-CUNG.bat)' Cyan
foreach ($n in $asts['2-CHAN-DOAN-PHAN-CUNG.bat'].FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in 'FLAG', 'Save-KetQua' }, $true)) { . ([scriptblock]::Create($n.Extent.Text)) }
$OutDir = New-TestDir 'chuyen-sau-ham'
$T0 = Get-Date; $SCRIPT_VER = '1.1'; $isAdmin = $true
$script:FLAGS = New-Object System.Collections.ArrayList
FLAG 'A_OK' 'Tot' -Muc 'ok'
FLAG 'B_TIN' 'Thong tin' -Muc 'thong-tin' -Tiep 'fix-win/ram'
FLAG 'C_LOI' 'Loi o dia' -Muc 'loi' -Tiep 'checkwinfix/bang-chung' -ChiTiet "dong 1`ndong 2"
FLAG 'C_LOI' 'Loi o dia' -Muc 'loi'
FLAG 'D_CANH' 'Canh bao' -Tiep 'khong hop le; rm'
Check ($script:FLAGS.Count -eq 4) 'cùng câu chỉ ghi một lần'
$p = Save-KetQua -CheDo 'phan-cung' -Ten 'PhanCung' -Tep @([ordered]@{ nhan = 'Báo cáo'; duongDan = 'HwDiag_X.txt' })
$f = @(Get-ChildItem -LiteralPath $OutDir -Filter "KetQua_CheckWinFix_PhanCung_$($env:COMPUTERNAME)_*.json")
Check ($p -and $f.Count -eq 1 -and $f[0].FullName -eq $p -and -not @(Get-ChildItem -LiteralPath $OutDir -Filter '*.tmp').Count) 'một file kết quả đúng tên, không còn .tmp'
if ($f.Count -eq 1) {
    $b = [IO.File]::ReadAllBytes($p)
    $j = [IO.File]::ReadAllText($p) | ConvertFrom-Json
    Check (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB)) 'UTF-8 không BOM'
    Check ((@($j.phatHien | ForEach-Object { $_.ma }) -join ',') -eq 'C_LOI,D_CANH,B_TIN,A_OK') "lỗi lên đầu, ok xuống cuối ($(@($j.phatHien | ForEach-Object { $_.ma }) -join ','))"
    Check ($j.tomTat.loi -eq 1 -and $j.tomTat.canhBao -eq 1 -and $j.tomTat.thongTin -eq 1 -and $j.ma -eq 'CO_LOI' -and $j.thongDiep -match '1 lỗi, 1 cảnh báo') 'tóm tắt, mã chung, thông điệp'
    Check ($j.chuan -eq 'tramtool.ketqua/1' -and $j.congCu -eq 'checkwinfix' -and $j.cheDo -eq 'phan-cung' -and $j.phienBan -eq '1.1' -and $j.maThoat -eq 0 -and $j.trangThai -eq 'xong' -and $j.quyenAdmin -eq $true) 'chuẩn, công cụ, chế độ, phiên bản, mã thoát'
    $c = @($j.phatHien)[0]
    Check ($c.chayTiep.congCu -eq 'checkwinfix' -and $c.chayTiep.action -eq 'bang-chung' -and $c.chiTiet -eq "dong 1`ndong 2") 'chạy tiếp, chi tiết'
    Check (-not (@($j.phatHien)[1].PSObject.Properties.Name -contains 'chayTiep')) 'Tiep sai dạng thì bỏ'
    $hr = Read-RunResult -Path $p
    Check ($hr.trangThai -eq 'xong' -and @($hr.phatHien).Count -eq 4) 'Trạm đọc được'
}
[IO.File]::Delete($p)
$script:FLAGS.Clear(); FLAG 'B_TIN' 'Thong tin' -Muc 'thong-tin'
$p = Save-KetQua -CheDo 'phan-cung' -Ten 'PhanCung'
$j = [IO.File]::ReadAllText($p) | ConvertFrom-Json
Check ($j.ma -eq 'KHONG_CO_LOI' -and $j.thongDiep -match 'Không thấy dấu hiệu') 'không lỗi, có quyền Admin: không thấy bất thường'
[IO.File]::Delete($p)
$isAdmin = $false
$p = Save-KetQua -CheDo 'phan-cung' -Ten 'PhanCung' -Message 'Đã xuất.'
$j = [IO.File]::ReadAllText($p) | ConvertFrom-Json
Check ($j.thongDiep -eq 'Đã xuất.' -and $j.quyenAdmin -eq $false) 'thông điệp riêng, ghi quyền Admin'
[IO.File]::Delete($p)
$script:FLAGS.Clear()
$p = Save-KetQua -CheDo 'phan-cung' -Ten 'PhanCung'
$j = [IO.File]::ReadAllText($p) | ConvertFrom-Json
Check ($j.thongDiep -match 'quyền Admin') 'không có quyền Admin: không kết luận máy ổn'

Write-KT '3. Phân loại lỗi ổ đĩa (Measure-DiskIo, sự kiện giả)' Cyan
foreach ($n in $asts['2-CHAN-DOAN-PHAN-CUNG.bat'].FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Measure-DiskIo' }, $true)) { . ([scriptblock]::Create($n.Extent.Text)) }
function Get-DiskBus([int]$Number) { switch ($Number) { 0 { 'SATA' } 3 { 'USB' } default { 'KHONG_CON' } } }
function DE([string]$Prov, [int]$Id, [string]$Dev = '') { [pscustomobject]@{ ProviderName = $Prov; Id = $Id; Properties = @([pscustomobject]@{ Value = $Dev }) } }
$io = Measure-DiskIo @((DE 'disk' 51 '\Device\Harddisk0\DR0'), (DE 'disk' 153 '\Device\Harddisk0\DR0'), (DE 'disk' 154 '\Device\Harddisk3\DR3'),
    (DE 'disk' 7 '\Device\Harddisk5\DR5'), (DE 'stornvme' 129 '\Device\RaidPort0'), (DE 'Ntfs' 55 'C:'), (DE 'volsnap' 36), (DE 'disk' 157 '\Device\Harddisk3\DR3'))
Check ($io.Hard -eq 2 -and $io.Soft -eq 2 -and $io.Usb -eq 2) "ổ trong máy: 2 lỗi phần cứng, 2 IO yếu; ổ USB, ổ đã rút: 2 (được $($io.Hard)/$($io.Soft)/$($io.Usb))"
Check ($io.PerDisk['Disk 0 (SATA)'] -eq 2 -and $io.PerDisk['Disk 3 (USB)'] -eq 1 -and $io.PerDisk['Disk 5 (da rut ra)'] -eq 1 -and $io.PerDisk['khong ro o nao'] -eq 2) "đếm theo ổ ($(@($io.PerDisk.Keys | Sort-Object | ForEach-Object { "$_=$($io.PerDisk[$_])" }) -join '; '))"
$io = Measure-DiskIo @()
Check ($io.Hard + $io.Soft + $io.Usb -eq 0) 'không có sự kiện: không lỗi'

Write-KT '4. Chạy thật phần PowerShell bằng quyền thường (chỉ đọc, không hỏi, không mở cửa sổ)' Cyan
$admin = Test-IsAdmin
$src = New-TestDir 'chuyen-sau-ps'
foreach ($file in $scripts.Keys) {
    $info = $scripts[$file]
    $action = @($tj.actions | Where-Object { $_.file -eq $file })[0]
    $dir = New-TestDir ('chuyen-sau-' + $info.Ten)
    $ps1 = Join-Path $src ($info.Ten + '.ps1')
    [IO.File]::WriteAllText($ps1, (Get-PsPart $file), (New-Object Text.UTF8Encoding $true))
    $psi = New-Object Diagnostics.ProcessStartInfo "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ps1`" -OutDir `"$dir`" $($info.Args)"
    $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.EnvironmentVariables['CWF_KHONG_MO'] = '1'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $pr = [Diagnostics.Process]::Start($psi)
    $pr.StandardInput.Close()
    $o = $pr.StandardOutput.ReadToEndAsync(); $er = $pr.StandardError.ReadToEndAsync()
    if (-not $pr.WaitForExit(600000)) { $pr.Kill(); Check $false "${file}: chạy xong trong 10 phút"; continue }
    $out = $o.Result
    Check ($pr.ExitCode -eq 0) "${file}: mã thoát 0 ($($pr.ExitCode), $([int]$sw.Elapsed.TotalSeconds) giây) $($er.Result.Trim())"
    Check ($out -notmatch '\[HOI\]|Tao Custom View\?|Bat theo doi\?') "${file}: không hỏi gì khi có -KhongHoi"
    $rep = @(Get-ChildItem -LiteralPath $dir -Filter $info.Out)
    $js = @(Get-ChildItem -LiteralPath $dir -Filter "KetQua_CheckWinFix_$($info.Ten)_*.json")
    Check ($rep.Count -eq 1 -and $js.Count -eq 1) "${file}: báo cáo và file kết quả cạnh nhau"
    if ($js.Count -ne 1) { continue }
    $j = [IO.File]::ReadAllText($js[0].FullName) | ConvertFrom-Json
    $items = @($j.phatHien)
    $ma = @($items | ForEach-Object { $_.ma })
    Check ($j.chuan -eq 'tramtool.ketqua/1' -and $j.congCu -eq 'checkwinfix' -and $j.cheDo -eq $action.id -and $j.phienBan -eq '1.1' -and $j.maThoat -eq 0) "${file}: chuẩn, cheDo $($j.cheDo), phiên bản $($j.phienBan)"
    Check ($rep.Count -eq 1 -and @($j.tep | Where-Object { $_.duongDan -eq $rep[0].FullName }).Count -eq 1) "${file}: tep trỏ tới $($info.Out)"
    Check (-not @($items | Where-Object { $_.ma -notmatch '^[A-Z][A-Z0-9_]+$' -or $_.mucDo -notin 'loi', 'canh-bao', 'thong-tin', 'ok' }).Count) "${file}: mã, mức hợp lệ ($($ma -join ', '))"
    $order = @($items | ForEach-Object { @{ 'loi' = 0; 'canh-bao' = 1; 'thong-tin' = 2; 'ok' = 3 }[$_.mucDo] })
    Check ((($order | ForEach-Object { $_ }) -join ',') -eq ((($order | Sort-Object) | ForEach-Object { $_ }) -join ',') -and $j.tomTat.loi + $j.tomTat.canhBao + $j.tomTat.thongTin -eq @($items | Where-Object { $_.mucDo -ne 'ok' }).Count) "${file}: thứ tự, tóm tắt khớp"
    if (-not $admin) { Check ($ma -contains 'THIEU_QUYEN_ADMIN' -and -not @($items | Where-Object { $_.mucDo -eq 'ok' }).Count -and $j.quyenAdmin -eq $false) "${file}: quyền thường: THIEU_QUYEN_ADMIN, không kết luận ổn" }
    if ($file -like '4-*') { Check ($ma -notcontains 'DA_TAO_CUSTOM_VIEW' -and $out -notmatch 'Da tao\. Mo Event Viewer') "${file}: không tạo Custom View" }
    if ($rep.Count -eq 1 -and -not $rep[0].PSIsContainer) {
        $txt = [IO.File]::ReadAllText($rep[0].FullName)
        $n = 0; foreach ($it in $items) { if ($txt.Contains("($($it.ma))")) { $n++ } }
        Check ($n -eq $items.Count) "${file}: mỗi kết luận có mã in trong báo cáo"
    }
    $hr = Read-RunResult -Path $js[0].FullName
    Check ($hr.trangThai -eq 'xong' -and @($hr.phatHien).Count -eq $items.Count) "${file}: Trạm đọc được file kết quả"
}
Complete-Test
