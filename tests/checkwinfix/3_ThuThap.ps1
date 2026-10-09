# Thu thập thông tin (ThuThapThongTin.bat): cảnh báo có mã, mức, việc chạy tiếp; ổ USB/ổ đã rút chỉ là cảnh báo; kiểm
# tra sâu (DISM, chkdsk /scan giả); tham số từ Trạm (-KhongHoi -BatDau -TrieuChung); file KetQua_*.json theo chuẩn.
# Không chạy file .bat thật (sẽ hỏi UAC): tách phần PowerShell, chạy bằng quyền thường, kết quả vào thư mục tạm.
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$Bat = Join-Path $ToolsDir 'checkwinfix\ThuThapThongTin.bat'
$raw = [IO.File]::ReadAllText($Bat)
$m = '#=====PS_START====='
$ps = $raw.Substring($raw.IndexOf($m) + $m.Length)
$tokens = $null; $errs = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($ps, [ref]$tokens, [ref]$errs)
Check ($errs.Count -eq 0) "phần PowerShell không lỗi cú pháp ($(@($errs | ForEach-Object { $_.Message }) -join '; '))"
if ($errs.Count) { Complete-Test }
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\Catalog.ps1"; . "$HubDir\lib\Checks.ps1"; . "$HubDir\lib\KetQua.ps1"
$cat = Get-HubCatalog -ToolsDir $ToolsDir -RootDir $RepoRoot

Write-KT '1. Mã, mức, việc chạy tiếp khai trong script' Cyan
$calls = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'FLAG' }, $true))
$codes = @($calls | ForEach-Object { $e = $_.CommandElements[1]; if ($e -is [Management.Automation.Language.StringConstantExpressionAst]) { $e.Value } else { $e.Extent.Text } })
Check ($calls.Count -ge 60) "có $($calls.Count) lời gọi FLAG"
Check (@($codes | Where-Object { $_ -ne '$h.M' -and $_ -notmatch '^[A-Z][A-Z0-9_]+$' }).Count -eq 0) 'mọi FLAG có mã chữ hoa cố định (hoặc mã theo bảng sự kiện)'
$watchText = ($ast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$WATCH' }, $true) | Select-Object -First 1).Extent.Text
Check (([regex]::Matches($watchText, '@\{ P = ')).Count -eq ([regex]::Matches($watchText, "M = '[A-Z][A-Z0-9_]+'")).Count) 'mọi dòng trong bảng sự kiện $WATCH có mã'
$targets = @([regex]::Matches($ps, "Tiep (?:= )?'([a-z0-9-]+/[A-Za-z0-9_-]+)'") | ForEach-Object { $_.Groups[1].Value }) + @([regex]::Matches($ps, "'(don-o-c/[a-z-]+)'") | ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Unique
$missing = @($targets | Where-Object { $p = $_ -split '/'; $t = @($cat | Where-Object { $_.id -eq $p[0] })[0]; -not ($t -and @($t.actions | Where-Object { $_.id -eq $p[1] -and $_.exists }).Count) })
Check ($targets.Count -ge 6 -and $missing.Count -eq 0) "việc chạy tiếp đều có trong danh mục: $($targets -join ', ') (thiếu: $($missing -join ', '))"

Write-KT '2. FLAG' Cyan
foreach ($n in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in 'FLAG', 'Ev', 'Get-DiskBus', 'Find-WatchHits' }, $true)) { . ([scriptblock]::Create($n.Extent.Text)) }
. ([scriptblock]::Create(($ast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$WATCH' }, $true) | Select-Object -First 1).Extent.Text))
$script:FLAGS = New-Object System.Collections.ArrayList
FLAG 'O_DIA_KHONG_KHOE' -Muc 'loi' -Tiep 'checkwinfix/phan-cung' 'O dia hong'
FLAG 'O_DIA_KHONG_KHOE' -Muc 'loi' -Tiep 'checkwinfix/phan-cung' 'O dia hong'
FLAG 'RAM_DAY' 'RAM day 95%'
FLAG 'LA' -Tiep 'khong hop le; rm' 'Tiep sai dang'
Check ($script:FLAGS.Count -eq 3) 'cùng câu chỉ ghi một lần'
$f0 = $script:FLAGS[0]
Check ($f0.ma -eq 'O_DIA_KHONG_KHOE' -and $f0.mucDo -eq 'loi' -and $f0.chayTiep.congCu -eq 'checkwinfix' -and $f0.chayTiep.action -eq 'phan-cung') 'mã, mức, chayTiep đúng'
Check ($script:FLAGS[1].mucDo -eq 'canh-bao' -and -not $script:FLAGS[1].Contains('chayTiep')) 'mặc định canh-bao, không chạy tiếp'
Check (-not $script:FLAGS[2].Contains('chayTiep')) 'Tiep sai dạng thì bỏ'

Write-KT '3. Sự kiện ổ đĩa: ổ trong máy, ổ USB, ổ đã rút' Cyan
function E($p, $id, $lvl, $disk = $null) {
    $o = [pscustomobject]@{ ProviderName = $p; Id = $id; Level = $lvl; TimeCreated = (Get-Date); Properties = @() }
    if ($null -ne $disk) { $o.Properties = @([pscustomobject]@{ Value = "\Device\Harddisk$disk\DR$disk" }) }
    $o
}
$script:Fake = @((E 'disk' 154 2 0), (E 'disk' 154 2 3), (E 'disk' 51 3 2), (E 'Microsoft-Windows-WHEA-Logger' 18 2), (E 'Microsoft-Windows-Kernel-Power' 41 1))
function Ev { param([string]$Log, [int[]]$Level, [datetime]$Since, [int]$Max = 1500, [int[]]$Id) return @($script:Fake | Where-Object { $Id -contains $_.Id }) }
function Get-Disk { [pscustomobject]@{ Number = 0; BusType = 'NVMe' }; [pscustomobject]@{ Number = 3; BusType = 'USB' } }
$script:DiskBus = $null
$since14 = (Get-Date).AddDays(-14)
$h = @(Find-WatchHits)
$d0 = @($h | Where-Object { $_.Id -eq 154 -and $_.Text -match 'Disk 0' })[0]
$d3 = @($h | Where-Object { $_.Id -eq 154 -and $_.Text -match 'Disk 3' })[0]
$d2 = @($h | Where-Object { $_.Id -eq 51 })[0]
Check ($d0.M -eq 'O_DIA_IO_THAT_BAI' -and $d0.Muc -eq 'loi' -and $d0.Tiep -eq 'checkwinfix/phan-cung') 'ổ trong máy (NVMe) hỏng: nghiêm trọng, gợi ý Chẩn đoán phần cứng'
Check ($d3.Muc -eq 'canh-bao' -and -not $d3.Tiep -and $d3.Text -match 'USB') 'ổ USB: chỉ cảnh báo, ghi rõ là ổ USB, không gợi ý chạy tiếp'
Check ($d2.Muc -eq 'canh-bao' -and -not $d2.Tiep -and $d2.Text -match 'da rut ra') 'ổ không còn gắn vào máy: chỉ cảnh báo'
$wh = @($h | Where-Object { $_.Id -eq 18 })[0]
Check ($wh.M -eq 'WHEA_NGHIEM_TRONG' -and $wh.Muc -eq 'loi' -and $wh.Tiep -eq 'checkwinfix/giai-ma-whea') 'WHEA 18: gợi ý Giải mã WHEA'
$kp = @($h | Where-Object { $_.Id -eq 41 })[0]
Check ($kp.M -eq 'TAT_DOT_NGOT' -and $kp.Tiep -eq 'checkwinfix/sup-nguon') 'Kernel-Power 41: gợi ý Sụp nguồn'
function Get-Disk { throw 'khong doc duoc' }
$script:DiskBus = $null
$h2 = @(Find-WatchHits)
Check (@($h2 | Where-Object { $_.Id -eq 51 })[0].Muc -eq 'loi') 'không đọc được danh sách ổ: giữ mức nghiêm trọng (không đoán là USB)'
Remove-Item Function:\Get-Disk

Write-KT '4. Kiểm tra sâu (DISM, chkdsk /scan giả)' Cyan
$deep = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Sec' -and $n.CommandElements[1].Extent.Text -like "'Kiem tra sau*" }, $true))
Check ($deep.Count -eq 1) 'có mục Kiểm tra sâu'
$body = [scriptblock]::Create($deep[0].CommandElements[2].ScriptBlock.EndBlock.Extent.Text)
$script:Out = New-Object System.Collections.ArrayList
function W { param([string]$t = '') [void]$script:Out.Add($t) }
function KV { param($k, $v) W ("{0}: {1}" -f $k, $v) }
function SH { param([string]$t) W "--- $t" }
function Write-Host { }
function Get-ODiaCanQuet { 'C', 'D' }
$script:Anh = 'Repairable'; $script:Vol = @{ C = 'NoErrorsFound'; D = 'ErrorsFound' }
function Get-AnhWindows { $script:Anh }
function Get-QuetODia { param([string]$Letter) $script:Vol[$Letter] }
$isAdmin = $true
$script:FLAGS.Clear(); & $body
$fl = @($script:FLAGS)
Check (@($fl | Where-Object { $_.ma -eq 'ANH_WINDOWS_HONG' -and $_.mucDo -eq 'loi' -and $_.chayTiep.action -eq 'dism-sfc' }).Count -eq 1) 'ảnh Windows hỏng sửa được: lỗi, gợi ý DISM rồi SFC'
Check (@($fl | Where-Object { $_.ma -eq 'O_DIA_LOI_HE_THONG_FILE' }).Count -eq 1 -and $fl[-1].tieuDe -like 'O D:*' -and $fl[-1].chayTiep.action -eq 'o-dia-sua') 'chỉ ổ D: có lỗi hệ thống file, gợi ý Sửa lỗi ổ đĩa'
$script:Anh = 'Healthy'; $script:Vol = @{ C = 'NoErrorsFound'; D = 'LOI: Access denied' }
$script:FLAGS.Clear(); $script:Out.Clear(); & $body
Check ($script:FLAGS.Count -eq 0 -and ($script:Out -join "`n") -match 'D:: LOI: Access denied') 'máy khoẻ: không cảnh báo; ổ không quét được thì chỉ ghi vào báo cáo'
$isAdmin = $false
$script:FLAGS.Clear(); $script:Out.Clear(); & $body
Check ($script:FLAGS.Count -eq 0 -and ($script:Out -join "`n") -match 'can quyen Administrator') 'không có quyền Admin: bỏ qua, ghi lý do'
Remove-Item Function:\Write-Host

Write-KT '5. File .bat chuyển tham số cho PowerShell' Cyan
Check ($raw -match '(?m)^powershell [^\r\n]*-File "%PS1%" -OutDir "%OUTDIR%" %\*\r?$') 'gọi PowerShell kèm %* (tham số từ Trạm)'
$tj = Get-Content (Join-Path $ToolsDir 'checkwinfix\tool.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$tt = @($tj.actions | Where-Object { $_.id -eq 'thu-thap' })[0]
$params = @($ast.ParamBlock.Parameters | ForEach-Object { '-' + $_.Name.VariablePath.UserPath })
$flags = @($tt.fixedArgs) + @($tt.args | ForEach-Object { $_.flag })
Check (@($flags | Where-Object { $params -notcontains $_ }).Count -eq 0) "mọi tham số tool.json gửi đều có trong param() ($($flags -join ' '))"

Write-KT '6. Chạy thật phần PowerShell bằng quyền thường (chỉ đọc máy này, không hỏi, không mở Notepad)' Cyan
$dir = New-TestDir 'thu-thap'
$ps1 = Join-Path $dir 'ThuThap.ps1'
[IO.File]::WriteAllText($ps1, $ps, (New-Object Text.UTF8Encoding $true))
$psi = New-Object Diagnostics.ProcessStartInfo "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ps1`" -OutDir `"$dir`" -KhongHoi -BatDau `"khoang 2 tuan truoc`" -TrieuChung `"mo Excel lau`" /danangquyen"
$psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = [Text.Encoding]::UTF8
$psi.EnvironmentVariables['CWF_KHONG_MO'] = '1'
$p = [Diagnostics.Process]::Start($psi)
$p.StandardInput.Close()
$o = $p.StandardOutput.ReadToEndAsync(); $er = $p.StandardError.ReadToEndAsync()
if (-not $p.WaitForExit(600000)) { $p.Kill(); Check $false 'chạy xong trong 10 phút'; Complete-Test }
Check ($p.ExitCode -eq 0) "mã thoát 0 ($($p.ExitCode)) $($er.Result.Trim())"
Check ($o.Result -notmatch 'Tra loi nhanh') 'không hỏi trong cửa sổ khi có -KhongHoi'
$rep = @(Get-ChildItem $dir -Filter 'LagReport_*.txt')
$js = @(Get-ChildItem $dir -Filter 'KetQua_CheckWinFix_ThuThap_*.json')
Check ($rep.Count -eq 1 -and $js.Count -eq 1) 'có báo cáo và file kết quả cạnh nhau'
if ($rep.Count -eq 1 -and $js.Count -eq 1) {
    $txt = [IO.File]::ReadAllText($rep[0].FullName)
    Check ($txt -match 'Bat dau cham tu : khoang 2 tuan truoc' -and $txt -match 'Trieu chung     : mo Excel lau') 'báo cáo ghi câu trả lời từ form'
    $j = Get-Content $js[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $items = @($j.phatHien)
    Check ($j.chuan -eq 'tramtool.ketqua/1' -and $j.congCu -eq 'checkwinfix' -and $j.cheDo -eq 'thu-thap' -and $j.maThoat -eq 0 -and $j.phienBan -eq $tj.version) "JSON: chuẩn, công cụ, chế độ, mã 0, phiên bản $($j.phienBan)"
    Check ($j.tep[0].duongDan -eq $rep[0].FullName -and $j.baoCao -eq $rep[0].FullName) 'JSON trỏ tới báo cáo'
    Check (@($items | Where-Object { $_.ma -eq 'THIEU_QUYEN_ADMIN' }).Count -eq 1) 'chạy quyền thường: có cảnh báo THIEU_QUYEN_ADMIN'
    Check ($j.tomTat.loi + $j.tomTat.canhBao + $j.tomTat.thongTin -eq $items.Count) "tomTat khớp phatHien ($($items.Count))"
    $order = @($items | ForEach-Object { @{ 'loi' = 0; 'canh-bao' = 1; 'thong-tin' = 2 }[$_.mucDo] })
    Check ((($order | ForEach-Object { $_ }) -join ',') -eq ((($order | Sort-Object) | ForEach-Object { $_ }) -join ',')) 'phát hiện xếp nghiêm trọng trước'
    $n = 0; foreach ($it in $items) { if ($txt.Contains("($($it.ma))")) { $n++ } }
    Check ($n -eq $items.Count) 'mỗi phát hiện có mã in trong báo cáo'
    $hr = Read-RunResult -Path $js[0].FullName
    Check ($hr.trangThai -eq 'xong' -and @($hr.phatHien).Count -eq $items.Count) 'Trạm đọc được file kết quả'
    Write-KT ('  mã: ' + (($items | ForEach-Object { $_.ma }) -join ', ')) DarkGray
}
Complete-Test
