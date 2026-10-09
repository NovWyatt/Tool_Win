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

Write-KT '4b. Secure Boot 2023, bản quyền, WinRE (dữ liệu giả)' Cyan
foreach ($n in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in 'Trunc', 'WL', 'Test-KmsLau', 'ConvertFrom-YeuCauNguon' }, $true)) { . ([scriptblock]::Create($n.Extent.Text)) }
. ([scriptblock]::Create(($ast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$CA2011_HET_HAN' }, $true) | Select-Object -First 1).Extent.Text))
function Get-SecBody([string]$Prefix) {
    $c = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Sec' -and $n.CommandElements[1].Extent.Text -like "'$Prefix*" }, $true))
    if ($c.Count -ne 1) { return $null }
    return [scriptblock]::Create($c[0].CommandElements[2].ScriptBlock.EndBlock.Extent.Text)
}
$sb24 = Get-SecBody 'Secure Boot'
$sb25 = Get-SecBody 'Chuong trinh giu may thuc'
Check ($sb24 -and $sb25) 'có hai mục mới (Secure Boot, bản quyền, WinRE; giữ máy thức, giấc ngủ, test RAM)'
Check ([regex]::Match($ps, '\$TOTAL\s+= (\d+)').Groups[1].Value -eq '26' -and $ps -match 'if \(\$KiemTraSau\) \{ \$TOTAL = 27 \}') 'tổng số mục 26 (27 khi kiểm tra sâu)'
foreach ($k in @('127.0.0.2', 'localhost', 'kms8.msguides.com', 'kms.digiboy.ir', 'kms.03k.org', 's8.uk.to')) { Check (Test-KmsLau $k) "KMS lậu: $k" }
foreach ($k in @('kms.congty.local', '10.0.0.5', '')) { Check (-not (Test-KmsLau $k)) "không coi là KMS lậu: '$k'" }

function TE([int]$Id, [int]$Ngay) { [pscustomobject]@{ Id = $Id; TimeCreated = (Get-Date).AddDays(-$Ngay); Message = "su kien $Id"; ProviderName = 'Microsoft-Windows-TPM-WMI' } }
function SanPham([int]$St, [string]$Kenh, [string]$Kms = '') { [pscustomobject]@{ Name = 'Windows(R), Professional edition'; Description = "Windows(R) Operating System, $Kenh channel"; LicenseStatus = $St; ProductKeyChannel = $Kenh; KeyManagementServiceMachine = $Kms; DiscoveredKeyManagementServiceMachineName = ''; GracePeriodRemaining = 0; PartialProductKey = 'QZXWV' } }
$script:SB = $null; $script:Lic = $null; $script:Crack = @(); $script:Re = $null
function Get-SecureBootTrangThai { $script:SB }
function Get-BanQuyenWindows { if ($null -eq $script:Lic) { return $null }; return , @($script:Lic) }
function Get-DauVetCrack { return , @($script:Crack) }
function Get-WinRE { $script:Re }
$cs = [pscustomobject]@{ PartOfDomain = $false }
function Run24 { $script:FLAGS.Clear(); $script:Out.Clear(); & $sb24; return , @($script:FLAGS) }
function Codes($fl) { return (@($fl | ForEach-Object { $_.ma }) -join ',') }

$script:SB = [pscustomobject]@{ Firmware = 'UEFI'; Bat = $true; Status = 'InProgress'; Capable = 1; Loi = [int64]2147942402; SuKien = @((TE 1801 1), (TE 1796 3)) }
$script:Lic = @(SanPham 1 'Volume:GVLK' '127.0.0.2'); $script:Crack = @('Tac vu lich: \AutoKMS'); $script:Re = [pscustomobject]@{ TrangThai = 'Tat'; ViTri = ''; ChiTiet = '' }
$fl = Run24; $txt = $script:Out -join "`n"
$ca = @($fl | Where-Object { $_.ma -eq 'SECURE_BOOT_CHUA_CO_CA_2023' })[0]
Check ($ca -and $ca.mucDo -eq 'canh-bao' -and $ca.tieuDe -match 'InProgress, ma loi 0x80070002' -and $ca.tieuDe -match '19/10/2026 \((con \d+ ngay|DA HET HAN)\)') 'chưa có chứng chỉ 2023: cảnh báo, trạng thái, mã lỗi, số ngày tới hạn 19/10/2026'
Check (@($fl | Where-Object { $_.ma -eq 'SECURE_BOOT_FIRMWARE_LOI' -and $_.tieuDe -match '1 lan' }).Count -eq 1) 'sự kiện 1796: firmware báo lỗi, cần cập nhật BIOS'
Check (@($fl | Where-Object { $_.ma -eq 'WINDOWS_KICH_HOAT_KMS_LAU' -and $_.tieuDe -match '127\.0\.0\.2' }).Count -eq 1) 'khoá KMS trỏ về chính máy: kích hoạt lậu'
Check (@($fl | Where-Object { $_.ma -eq 'DAU_VET_CRACK_KICH_HOAT' -and $_.tieuDe -match 'AutoKMS' }).Count -eq 1) 'dấu vết công cụ crack: cảnh báo, kể tên'
Check (@($fl | Where-Object { $_.ma -eq 'WINRE_TAT' }).Count -eq 1) 'WinRE tắt: cảnh báo'
Check (@($fl | Where-Object { $_.ma -eq 'WINDOWS_CHUA_KICH_HOAT' }).Count -eq 0) 'đã kích hoạt (dù lậu) thì không báo chưa kích hoạt'
Check ($txt -notmatch 'QZXWV' -and (Codes $fl) -notmatch 'QZXWV' -and (@($fl | ForEach-Object { $_.tieuDe }) -join ' ') -notmatch 'QZXWV') 'không in khoá sản phẩm (kể cả 5 ký tự cuối)'

$script:SB = [pscustomobject]@{ Firmware = 'UEFI'; Bat = $true; Status = 'Updated'; Capable = 2; Loi = $null; SuKien = @((TE 1808 2), (TE 1801 20)) }
$script:Lic = @(SanPham 1 'Retail'); $script:Crack = @(); $script:Re = [pscustomobject]@{ TrangThai = 'Bat'; ViTri = '\Recovery\WindowsRE'; ChiTiet = '' }
$fl = Run24
Check ($fl.Count -eq 0 -and ($script:Out -join "`n") -match 'Da co chung chi Secure Boot 2023') "máy đã cập nhật, bản quyền bán lẻ, WinRE bật: không cảnh báo ($(Codes $fl))"
$script:SB = [pscustomobject]@{ Firmware = 'UEFI'; Bat = $true; Status = ''; Capable = $null; Loi = $null; SuKien = @((TE 1808 1), (TE 1801 9), (TE 1795 12)) }
Check ((Run24).Count -eq 0) 'không đọc được trạng thái nhưng sự kiện mới nhất là 1808: coi là đã cập nhật, bỏ qua lỗi firmware cũ'
$script:SB = [pscustomobject]@{ Firmware = 'UEFI'; Bat = $true; Status = 'NotStarted'; Capable = 0; Loi = $null; SuKien = @() }
$ca = @((Run24) | Where-Object { $_.ma -eq 'SECURE_BOOT_CHUA_CO_CA_2023' })[0]
Check ($ca -and $ca.tieuDe -match 'NotStarted\)') 'NotStarted: báo chưa có chứng chỉ, không có mã lỗi'
$script:SB = [pscustomobject]@{ Firmware = 'BIOS'; Bat = $null; Status = ''; Capable = $null; Loi = $null; SuKien = @() }
Check ((Codes (Run24)) -eq 'KHOI_DONG_KIEU_BIOS') 'khởi động kiểu BIOS cũ: chỉ thông tin, không bàn chứng chỉ'
$script:SB = [pscustomobject]@{ Firmware = 'UEFI'; Bat = $false; Status = 'NotStarted'; Capable = 0; Loi = $null; SuKien = @() }
$fl = Run24
Check ((Codes $fl) -eq 'SECURE_BOOT_TAT' -and $fl[0].mucDo -eq 'thong-tin') 'Secure Boot tắt: thông tin'
$script:SB = [pscustomobject]@{ Firmware = ''; Bat = $null; Status = ''; Capable = $null; Loi = $null; SuKien = @() }
$script:Lic = $null
$fl = Run24
Check ($fl.Count -eq 0 -and ($script:Out -join "`n") -match 'khong doc duoc trang thai Secure Boot' -and ($script:Out -join "`n") -match 'khong doc duoc thong tin ban quyen') 'không đọc được Secure Boot, bản quyền: chỉ ghi vào báo cáo'
$script:Lic = @()
Check ((Codes (Run24)) -eq 'WINDOWS_CHUA_KICH_HOAT') 'không có khoá nào: chưa kích hoạt'
$script:Lic = @(SanPham 5 'Retail')
$fl = Run24
Check ((Codes $fl) -eq 'WINDOWS_CHUA_KICH_HOAT' -and $fl[0].tieuDe -match 'Thong bao') 'trạng thái 5 (Notification): chưa kích hoạt'
$script:Lic = @(SanPham 1 'Volume:GVLK' 'kms.congty.local')
$fl = Run24
Check ((Codes $fl) -eq 'WINDOWS_KMS_NGOAI_DOMAIN' -and $fl[0].mucDo -eq 'thong-tin') 'KMS của công ty mà máy không vào domain: thông tin'
$cs = [pscustomobject]@{ PartOfDomain = $true }
Check ((Run24).Count -eq 0) 'KMS của công ty, máy trong domain: bình thường'
$script:Lic = @(SanPham 1 'Volume:GVLK' 'kms8.msguides.com')
Check ((Codes (Run24)) -eq 'WINDOWS_KICH_HOAT_KMS_LAU') 'máy chủ KMS công cộng của crack: kích hoạt lậu kể cả trong domain'

Write-KT '4c. Giữ máy thức, giấc ngủ, test RAM (dữ liệu giả)' Cyan
$req = @"
DISPLAY:
[PROCESS] \Device\HarddiskVolume3\Program Files\Google\Chrome\Application\chrome.exe
Video Wake Lock

SYSTEM:
[DRIVER] Legacy Kernel Caller

AWAYMODE:
None.

EXECUTION:
[PROCESS] \Device\HarddiskVolume3\Windows\System32\svchost.exe
Ung dung dang tai

PERFBOOST:
None.

ACTIVELOCKSCREEN:
None.
"@
$rq = ConvertFrom-YeuCauNguon $req
Check ($rq.Count -eq 3 -and $rq[0].Nhom -eq 'DISPLAY' -and $rq[0].Loai -eq 'PROCESS' -and $rq[0].Nguon -eq 'chrome.exe' -and $rq[0].LyDo -eq 'Video Wake Lock') 'tách powercfg /requests: nhóm, loại, tên tiến trình, lý do'
Check ($rq[1].Nhom -eq 'SYSTEM' -and $rq[1].Loai -eq 'DRIVER' -and $rq[1].Nguon -eq 'Legacy Kernel Caller' -and -not $rq[1].LyDo -and $rq[2].Nhom -eq 'EXECUTION') 'driver không có dòng lý do; dòng None. (mọi ngôn ngữ) bị bỏ'
Check ((ConvertFrom-YeuCauNguon '').Count -eq 0) 'kết quả rỗng: không có yêu cầu'
function RE([int]$Id, [int]$Ngay) { [pscustomobject]@{ Id = $Id; TimeCreated = (Get-Date).AddDays(-$Ngay) } }
$script:Req = $req; $script:Ss = 'X:\SleepStudy_PC_1.html'; $script:Ram = @((RE 1202 2), (RE 1201 30))
function Get-YeuCauNguon { $script:Req }
function Get-SleepStudy { param([string]$Path) $script:SsPath = $Path; $script:Ss }
function Get-KetQuaTestRam { return , @($script:Ram) }
function powercfg { 'Wake History Count - 0' }
$OutDir = "$env:SystemDrive\KhongCo\ket"; $stamp = '20261010_080000'
$script:TepThem = New-Object System.Collections.ArrayList
function Run25 { $script:Out.Clear(); & $sb25; return , @($script:FLAGS) }
$script:FLAGS.Clear(); $fl = Run25
$giu = @($fl | Where-Object { $_.ma -eq 'CO_CHUONG_TRINH_GIU_MAY_THUC' })[0]
Check ($giu -and $giu.mucDo -eq 'thong-tin' -and $giu.tieuDe -match 'chrome\.exe \(DISPLAY\)' -and $giu.tieuDe -match 'Legacy Kernel Caller \(SYSTEM\)' -and $giu.tieuDe -notmatch 'svchost') 'giữ máy thức: thông tin, chỉ kể nhóm DISPLAY/SYSTEM/AWAYMODE'
Check (@($fl | Where-Object { $_.ma -eq 'RAM_CO_LOI' -and $_.mucDo -eq 'loi' }).Count -eq 1) 'lần test RAM mới nhất có lỗi: nghiêm trọng'
Check ($script:TepThem.Count -eq 1 -and $script:TepThem[0].duongDan -eq 'X:\SleepStudy_PC_1.html' -and $script:SsPath -like "$env:SystemDrive\KhongCo\ket\SleepStudy_*_20261010_080000.html") 'báo cáo giấc ngủ lưu cạnh báo cáo, ghi vào danh sách file của JSON'
$script:Req = ''; $script:Ss = ''; $script:Ram = @((RE 1201 1), (RE 1202 40))
$script:TepThem.Clear(); $script:FLAGS.Clear(); $fl = Run25
Check ($fl.Count -eq 0 -and ($script:Out -join "`n") -match 'can quyen Administrator' -and $script:TepThem.Count -eq 0) 'không có quyền Admin, lần test RAM mới nhất không lỗi: không cảnh báo'
$script:Ram = @()
$script:FLAGS.Clear(); FLAG 'MAN_HINH_XANH' 'Co 2 file minidump'; $fl = Run25
$ct = @($fl | Where-Object { $_.ma -eq 'CHUA_TEST_RAM' })[0]
Check ($ct -and $ct.mucDo -eq 'thong-tin' -and $ct.chayTiep.congCu -eq 'fix-win' -and $ct.chayTiep.action -eq 'ram') 'màn hình xanh mà chưa test RAM: gợi ý Kiểm tra RAM'
$script:FLAGS.Clear(); $fl = Run25
Check ($fl.Count -eq 0) 'chưa test RAM nhưng không có màn hình xanh, WHEA: không cảnh báo'
Remove-Item Function:\powercfg

Write-KT '4d. Chỉ đọc: lệnh hệ thống, khoá sản phẩm' Cyan
$cmds = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -in 'powercfg', 'reagentc', 'bcdedit', 'slmgr', 'cscript' }, $true))
$bad = @($cmds | Where-Object { $a = $_.CommandElements[1].Extent.Text; -not (($_.GetCommandName() -eq 'powercfg' -and $a -in '/getactivescheme', '/list', '/qh', '/requests', '/lastwake', '/sleepstudy') -or ($_.GetCommandName() -eq 'reagentc' -and $a -eq '/info') -or ($_.GetCommandName() -eq 'bcdedit' -and $a -eq '/enum')) })
Check ($bad.Count -eq 0) "powercfg, reagentc, bcdedit chỉ dùng lệnh xem; không slmgr ($(@($bad | ForEach-Object { $_.Extent.Text }) -join '; '))"
$sel = [regex]::Match($ps, 'SELECT (.+?) FROM SoftwareLicensingProduct').Groups[1].Value
Check ($sel -and $sel -notmatch 'ProductKey(?!Channel)|OA3x' -and $ps -notmatch 'OA3xOriginalProductKey') 'truy vấn bản quyền không lấy khoá sản phẩm, khoá OEM'
Check ($ps -notmatch '(?i)(Set|New)-ItemProperty|Set-SecureBootUEFI|AvailableUpdates') 'không ghi registry, không đụng biến Secure Boot'

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
    Check ($txt -match '24\. SECURE BOOT \(CHUNG CHI 2023\)' -and $txt -match 'Trang thai WinRE\s+: (Bat|Tat|khong doc duoc)' -and $txt -match 'Ket qua test RAM' -and $txt -match '26\. NHIET DO') 'báo cáo có mục Secure Boot, bản quyền, WinRE, test RAM; Nhiệt độ thành mục 26'
    Check ($txt -match 'Yeu cau giu may thuc[^\r\n]*\r?\n\s+\(can quyen Administrator\)') 'quyền thường: powercfg /requests ghi cần quyền Admin'
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
