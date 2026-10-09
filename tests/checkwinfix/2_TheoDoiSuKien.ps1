# Thử Find-WatchHits của ThuThapThongTin.bat: tách $WATCH, Ev, Find-WatchHits bằng AST rồi chạy với sự kiện giả
# (thay Ev, không đọc nhật ký thật).
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$raw = [IO.File]::ReadAllText("$ToolsDir\checkwinfix\ThuThapThongTin.bat")
$m = '#=====PS_START====='
$ps = $raw.Substring($raw.IndexOf($m) + $m.Length)
$tokens = $null; $errs = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($ps, [ref]$tokens, [ref]$errs)
Check ($errs.Count -eq 0) "phần PowerShell của ThuThapThongTin.bat không lỗi cú pháp ($(@($errs | ForEach-Object { "$($_.Message) dòng $($_.Extent.StartLineNumber)" }) -join '; '))"
if ($errs.Count) { Complete-Test }
$fn = $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in 'Ev', 'Find-WatchHits' }, $true)
$asg = $ast.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$WATCH' }, $true)
foreach ($n in @($asg) + @($fn)) { . ([scriptblock]::Create($n.Extent.Text)) }
$since14 = (Get-Date).AddDays(-14)

# Giả: thay Ev.
function E($p, $id, $lvl, $min = 0) { [pscustomobject]@{ ProviderName = $p; Id = $id; Level = $lvl; TimeCreated = (Get-Date).AddMinutes(-$min) } }
$script:Fake = @(
    (E 'disk' 154 2 5), (E 'disk' 154 2 1), (E 'disk' 153 3),
    (E 'Microsoft-Windows-Kernel-General' 1 4), (E 'Microsoft-Windows-WHEA-Logger' 1 2), (E 'Microsoft-Windows-WHEA-Logger' 18 2),
    (E 'Display' 4101 3), (E 'Microsoft-Windows-Kernel-PnP' 219 3), (E 'Microsoft-Windows-Ntfs' 98 4), (E 'Microsoft-Windows-Ntfs' 98 3),
    (E 'stornvme' 129 3), (E 'Service Control Manager' 7031 2), (E 'Microsoft-Windows-Kernel-Boot' 7 4), (E 'SomeVendor' 11 2)
)
$script:Calls = 0
function Ev { param([string]$Log, [int[]]$Level, [datetime]$Since, [int]$Max = 1500, [int[]]$Id) $script:Calls++; return @($script:Fake | Where-Object { $Id -contains $_.Id }) }
$h = @(Find-WatchHits)
$byKey = @{}; foreach ($x in $h) { $byKey["$($x.Provider)|$($x.Id)"] = $x }
Check 'disk 154 (mới thêm) đếm 2 lần' ($byKey['disk|154'].Count -eq 2)
Check 'disk 153 mức Warning được tính' ($byKey.ContainsKey('disk|153'))
Check 'WHEA 1 được tính, Kernel-General 1 (đổi giờ) không' ($byKey.ContainsKey('Microsoft-Windows-WHEA-Logger|1') -and -not $byKey.ContainsKey('Microsoft-Windows-Kernel-General|1'))
Check 'WHEA 18' ($byKey.ContainsKey('Microsoft-Windows-WHEA-Logger|18'))
Check 'Display 4101 mức Warning' ($byKey.ContainsKey('Display|4101'))
Check 'Kernel-PnP 219 Warning bị bỏ (chỉ Error)' (-not $byKey.ContainsKey('Microsoft-Windows-Kernel-PnP|219'))
Check 'Ntfs 98 Info (ổ khoẻ) bị bỏ, Warning được tính 1' ($byKey['Microsoft-Windows-Ntfs|98'].Count -eq 1)
Check 'stornvme 129' ($byKey.ContainsKey('stornvme|129'))
Check 'ID 7, 11 của nguồn khác bị bỏ' (-not $byKey.ContainsKey('Microsoft-Windows-Kernel-Boot|7') -and -not $byKey.ContainsKey('SomeVendor|11'))
Check 'gọi Ev 2 lần (mỗi lần tối đa 20 mã)' ($script:Calls -eq 2) "$($script:Calls)"
Check 'sắp theo số lần giảm dần' ($h[0].Provider -eq 'disk' -and $h[0].Id -eq 154)
Complete-Test
