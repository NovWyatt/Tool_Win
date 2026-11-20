# Bộ cài có sẵn của bản portable (hub\lib\BoCai.ps1): đọc file kê khai của winget (YAML), dựng runtime\bo-cai\<gói>
# (đối chiếu mã SHA-256), lệnh cài im lặng theo loại bộ cài, cài gói phụ thuộc trước, mã thành công, file nén có bộ cài
# bên trong, ứng dụng dạng nén chạy ngay (chép vào thư mục thử, lối tắt, mục Programs and Features trong registry thử),
# nhận đã cài; nút Cài của trạm dùng bộ cài có sẵn, Cai-BoCai.ps1, Cai-SqlLocalDB.ps1 không xoá bộ cài của gói.
# Bộ cài là file giả: không chạy bộ cài thật nào (thay Invoke-BoCaiProcess).
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\BoCai.ps1"; . "$HubDir\lib\Checks.ps1"
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$dir = New-TestDir 'bocai'
$utf8 = New-Object Text.UTF8Encoding $false
function Sha([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

# Thư mục 'winget download' giả: file kê khai + một bộ cài (file chữ). $Installer: phần YAML của bộ cài (thụt 2).
function New-Download([string]$Id, [string]$File, [string]$Installer, [string]$Root = '', [string]$Content = "gia $Id", [string]$Sha = '') {
    $d = Join-Path $dir "tai\$Id"
    if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    $f = Join-Path $d $File
    if ($File -like '*.zip') { Copy-Item -LiteralPath $Content -Destination $f } else { [IO.File]::WriteAllText($f, $Content) }
    $h = if ($Sha) { $Sha } else { Sha $f }
    $y = "PackageIdentifier: $Id`nPackageVersion: 1.2.3`nPackageName: Ten $Id`nPublisher: Nha phat hanh`n$Root" + "Installers:`n- Architecture: x64`n  InstallerSha256: $($h.ToLower())`n$Installer`nManifestType: merged`n"
    [IO.File]::WriteAllText((Join-Path $d ([IO.Path]::GetFileNameWithoutExtension($File) + '.yaml')), $y, $utf8)
    return $d
}

Write-KT '1. Đọc YAML của winget' Cyan
$yaml = @'
# chú thích
PackageIdentifier: Thu.App
PackageVersion: 26.06
PackageName: "Thu App \u00C1"
Publisher: 'O''Brien'
ReleaseNotes: '- Sửa lỗi: một

  - Sửa lỗi hai'
Description: |
  Dòng một
  - không phải danh sách
Tags:
- zip
- archive
InstallerType: nullsoft
InstallerSwitches:
  Silent: /S /Goc
Installers:
- Architecture: x64
  InstallerType: wix
  InstallerSha256: abcdef
  Scope: machine
  ProductCode: '{11111111-2222-3333-4444-555555555555}'
  AppsAndFeaturesEntries:
  - DisplayName: Thu App 26.06 (x64 edition)
    UpgradeCode: '{99999999-2222-3333-4444-555555555555}'
  InstallerSwitches:
    Silent: /quiet /norestart
    Custom: ALLUSERS=1
  ExpectedReturnCodes:
  - InstallerReturnCode: 1638
    ReturnResponse: alreadyInstalled
  - InstallerReturnCode: 8
    ReturnResponse: rebootRequiredForInstall
  - InstallerReturnCode: 77
    ReturnResponse: rebootRequiredToFinish
  InstallerSuccessCodes:
  - 42
  Dependencies:
    PackageDependencies:
    - PackageIdentifier: Thu.Dep
      MinimumVersion: 1.0
ManifestVersion: 1.28.0
'@
$m = ConvertFrom-SimpleYaml $yaml
Check ($m.PackageIdentifier -eq 'Thu.App' -and $m.PackageVersion -eq '26.06' -and $m.PackageName -eq 'Thu App Á' -and $m.Publisher -eq "O'Brien") 'khoá gốc, chuỗi trong nháy đơn, nháy kép có \u'
Check ($m.ReleaseNotes -like '- Sửa lỗi: một*hai' -and $m.Description -match 'Dòng một' -and @($m.Tags).Count -eq 2) 'chuỗi nháy nhiều dòng có "- " không thành danh sách; khối |; danh sách chữ'
Check (@($m.Installers).Count -eq 1 -and $m.Installers[0].Scope -eq 'machine' -and $m.Installers[0].InstallerSwitches.Custom -eq 'ALLUSERS=1') 'danh sách cùng lề với khoá cha, ánh xạ lồng'
Check ($m.ManifestVersion -eq '1.28.0') 'khoá gốc sau danh sách bộ cài vẫn đọc được'
$f1 = Join-Path $dir 'thu.yaml'; [IO.File]::WriteAllText($f1, $yaml, $utf8)
$i = ConvertFrom-WingetManifest $f1
Check ($i.id -eq 'Thu.App' -and $i.loai -eq 'wix' -and $i.lenhIm -eq '/quiet /norestart' -and $i.them -eq 'ALLUSERS=1' -and $i.sha256 -eq 'ABCDEF') 'trường ở bộ cài thắng trường ở gốc; mã băm viết hoa'
Check (@($i.phuThuoc) -join ',' -eq 'Thu.Dep' -and @($i.maSanPham) -contains '{11111111-2222-3333-4444-555555555555}' -and @($i.tenCaiDat) -contains 'Thu App') "gói phụ thuộc, mã sản phẩm, tên bỏ số bản ($(@($i.tenCaiDat) -join '|'))"
Check (@($i.maThanhCong) -contains 1638 -and @($i.maThanhCong) -contains 77 -and @($i.maThanhCong) -contains 42 -and @($i.maThanhCong) -notcontains 8) "mã thành công: alreadyInstalled, rebootRequiredToFinish, InstallerSuccessCodes; không có rebootRequiredForInstall ($(@($i.maThanhCong) -join ','))"
[IO.File]::WriteAllText($f1, "PackageIdentifier: Goc.App`nPackageVersion: 1`nPackageName: Goc`nInstallerType: inno`nInstallerSwitches:`n  Silent: /VERYSILENT /X`nInstallers:`n- Architecture: x86`n  InstallerSha256: 01`n", $utf8)
$i = ConvertFrom-WingetManifest $f1
Check ($i.loai -eq 'inno' -and $i.lenhIm -eq '/VERYSILENT /X' -and $i.kienTruc -eq 'x86') 'loại và lệnh im lặng khai ở gốc'
Check ((Get-NamePrefix 'Mozilla Firefox (en-US)') -eq 'Mozilla Firefox' -and (Get-NamePrefix '7-Zip 26.06 (x64 edition)') -eq '7-Zip' -and (Get-NamePrefix 'Microsoft Visual C++ v14 Redistributable (x64) - 14.52.37029') -eq 'Microsoft Visual C++ v14 Redistributable' -and (Get-NamePrefix 'Zalo') -eq 'Zalo') 'tên trong Programs and Features bỏ số bản, phần trong ngoặc'

Write-KT '2. Lệnh cài im lặng' Cyan
$c = Get-BoCaiCommand 'wix' 'C:\a b\x.msi' '' ''
Check ($c.Exe -eq 'msiexec.exe' -and $c.Args -eq '/i "C:\a b\x.msi" /quiet /norestart') "msi/wix: msiexec /i ... /quiet /norestart ($($c.Args))"
$c = Get-BoCaiCommand 'msi' 'x.msi' '/qb' 'IACCEPT=YES'
Check ($c.Args -eq '/i "x.msi" /qb IACCEPT=YES') 'msi: lệnh im lặng và Custom của file kê khai'
Check ((Get-BoCaiCommand 'burn' 'v.exe').Args -eq '/quiet /norestart' -and (Get-BoCaiCommand 'nullsoft' 'z.exe').Args -eq '/S' -and (Get-BoCaiCommand 'inno' 'u.exe').Args -eq '/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART') 'burn, nullsoft, inno: lệnh mặc định như winget'
Check ((Get-BoCaiCommand 'exe' 'f.exe' '/quiet').Args -eq '/quiet' -and $null -eq (Get-BoCaiCommand 'exe' 'f.exe' '') -and $null -eq (Get-BoCaiCommand 'portable' 'p.exe')) 'exe cần lệnh im lặng trong file kê khai; portable đơn lẻ không cài'
Check ((Get-BoCaiCommand 'msix' 'a.msix').Kind -eq 'appx') 'msix: Add-AppxPackage'

Write-KT '3. Dựng runtime\bo-cai' Cyan
$root = Join-Path $dir 'bo-cai'
$d = New-Download 'Thu.Msi' 'thu.msi' "  InstallerType: wix`n  Scope: machine`n  ProductCode: '{AAAAAAAA-0000-0000-0000-000000000001}'`n  Dependencies:`n    PackageDependencies:`n    - PackageIdentifier: Thu.Dep"
$g = New-BoCaiPackage -SourceDir $d -DestRoot $root -Id 'Thu.Msi'
$p = Get-BoCaiPackage $root 'Thu.Msi'
Check ($g.chuan -eq 'tramtool.bocai/1' -and $p -and $p.tep -eq 'thu.msi' -and $p.sha256 -eq (Sha (Join-Path $d 'thu.msi')) -and (Test-Path -LiteralPath $p.Path) -and -not (Test-Path -LiteralPath (Join-Path $root 'Thu.Msi\thu.yaml'))) 'goi.json, bộ cài chép sang, không chép file kê khai'
$d = New-Download 'Thu.Sai' 'sai.exe' '  InstallerType: nullsoft' -Sha ('0' * 64)
$e = ''; try { New-BoCaiPackage -SourceDir $d -DestRoot $root -Id 'Thu.Sai' | Out-Null } catch { $e = $_.Exception.Message }
Check ($e -match 'SHA-256' -and -not (Test-Path -LiteralPath (Join-Path $root 'Thu.Sai'))) 'bộ cài sai mã SHA-256 so với file kê khai: không đóng'
$e = ''; try { New-BoCaiPackage -SourceDir (Join-Path $dir 'tai\Thu.Msi') -DestRoot $root -Id 'Khac.Id' | Out-Null } catch { $e = $_.Exception.Message }
Check ($e -match 'không phải Khac.Id') 'file kê khai của gói khác: không đóng'
[IO.File]::WriteAllText((Join-Path $dir 'tai\Thu.Msi\them.exe'), 'x'); $e = ''
try { New-BoCaiPackage -SourceDir (Join-Path $dir 'tai\Thu.Msi') -DestRoot $root -Id 'Thu.Msi' | Out-Null } catch { $e = $_.Exception.Message }
Check ($e -match 'đúng một file bộ cài') 'thư mục có hai bộ cài: không đoán'
$bad = Join-Path $root 'Thu.Leo'; New-Item -ItemType Directory -Path $bad -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $bad 'goi.json'), '{"tep":"..\\Thu.Msi\\thu.msi","sha256":"00"}', $utf8)
Check ($null -eq (Get-BoCaiPackage $root 'Thu.Leo') -and $null -eq (Get-BoCaiPackage $root '..\Thu.Msi') -and $null -eq (Get-BoCaiPackage $root 'Khong.Co')) 'goi.json trỏ ra ngoài thư mục gói, mã gói lạ, gói không có: không dùng'

Write-KT '4. Cài từ bộ cài có sẵn' Cyan
$script:BoCaiUninstallKeys = @('HKCU:\Software\TramToolTest\Uninstall')
$script:BoCaiUninstallWriteKey = 'HKCU:\Software\TramToolTest\Uninstall'
$script:BoCaiPortableRoot = Join-Path $dir 'ProgramFiles'
$script:BoCaiStartMenu = Join-Path $dir 'StartMenu'
Clear-TestRegistry
$script:Runs = New-Object System.Collections.ArrayList
$script:RunCodes = @{}
function Invoke-BoCaiProcess {
    param([string]$Exe, [string]$Arguments)
    $seen = if ($Arguments -match '"([^"]+)"') { Test-Path -LiteralPath $Matches[1] } else { Test-Path -LiteralPath $Exe }
    [void]$script:Runs.Add([pscustomobject]@{ Exe = $Exe; Args = $Arguments; FileThere = $seen })
    foreach ($k in $script:RunCodes.Keys) { if ("$Exe $Arguments" -like "*$k*") { return [int64]$script:RunCodes[$k] } }
    return [int64]0
}
$d = New-Download 'Thu.Dep' 'dep.exe' "  InstallerType: burn`n  AppsAndFeaturesEntries:`n  - DisplayName: Thu Dep Runtime (x64) - 14.1"
New-BoCaiPackage -SourceDir $d -DestRoot $root -Id 'Thu.Dep' | Out-Null
$r = Install-BoCaiPackage -Root $root -Id 'Thu.Msi' 6>$null
Check ($r.Ok -and $script:Runs.Count -eq 2 -and $script:Runs[0].Exe -like '*dep.exe' -and $script:Runs[0].Args -eq '/quiet /norestart' -and $script:Runs[1].Exe -eq 'msiexec.exe' -and $script:Runs[1].Args -like '/i "*thu.msi" /quiet /norestart') "gói phụ thuộc cài trước, rồi msi ($(@($script:Runs | ForEach-Object { "$($_.Exe) $($_.Args)" }) -join ' | '))"
$script:Runs.Clear()
New-Item -Path 'HKCU:\Software\TramToolTest\Uninstall\DepCo' -Force | Out-Null
Set-ItemProperty -LiteralPath 'HKCU:\Software\TramToolTest\Uninstall\DepCo' -Name DisplayName -Value 'Thu Dep Runtime (x64) - 14.9.1'
$r = Install-BoCaiPackage -Root $root -Id 'Thu.Msi' 6>$null
Check ($r.Ok -and $script:Runs.Count -eq 1 -and $script:Runs[0].Exe -eq 'msiexec.exe') 'gói phụ thuộc đã có (bản khác, cùng tên): không cài lại'
$script:Runs.Clear(); $script:RunCodes = @{ 'thu.msi' = 3010 }
$r = Install-BoCaiPackage -Root $root -Id 'Thu.Msi' 6>$null
Check ($r.Ok -and $r.Reboot -and $r.Code -eq 3010) 'mã 3010: xong, cần khởi động lại'
$script:Runs.Clear(); $script:RunCodes = @{ 'thu.msi' = 1603 }
$r = Install-BoCaiPackage -Root $root -Id 'Thu.Msi' 6>$null
Check (-not $r.Ok -and $r.Message -match '1603') "mã lỗi: báo lại mã ($($r.Message))"
$script:Runs.Clear(); $script:RunCodes = @{}
$d = New-Download 'Thu.Ma' 'ma.exe' "  InstallerType: inno`n  ExpectedReturnCodes:`n  - InstallerReturnCode: 8`n    ReturnResponse: rebootRequiredForInstall`n  InstallerSuccessCodes:`n  - 5"
New-BoCaiPackage -SourceDir $d -DestRoot $root -Id 'Thu.Ma' | Out-Null
$script:RunCodes = @{ 'ma.exe' = 5 }; $r5 = Install-BoCaiPackage -Root $root -Id 'Thu.Ma' 6>$null
$script:RunCodes = @{ 'ma.exe' = 8 }; $r8 = Install-BoCaiPackage -Root $root -Id 'Thu.Ma' 6>$null
Check ($r5.Ok -and -not $r8.Ok) 'mã thành công riêng của gói (5) nhận; 8 (cần khởi động lại rồi mới cài) là chưa cài'
$script:Runs.Clear(); $script:RunCodes = @{}
[IO.File]::AppendAllText((Join-Path $root 'Thu.Ma\ma.exe'), 'bi sua')
$r = Install-BoCaiPackage -Root $root -Id 'Thu.Ma' 6>$null
Check (-not $r.Ok -and $r.Message -match 'SHA-256' -and $script:Runs.Count -eq 0) 'bộ cài bị sửa sau khi đóng gói: không chạy'
$r = Install-BoCaiPackage -Root $root -Id 'Thu.Msi' -DryRun 6>$null
Check ($r.Ok -and $script:Runs.Count -eq 0) 'chạy thử: không chạy bộ cài nào'
$r = Install-BoCaiPackage -Root $root -Id 'Khong.Co' 6>$null
Check (-not $r.Ok -and $r.Message -match 'không có sẵn') 'gói không có trong bản này: báo rõ'

# File nén có bộ cài msi bên trong (như TeamViewer): giải nén ra thư mục tạm, chạy msi trong đó.
$zsrc = Join-Path $dir 'nested.zip'
$za = [IO.Compression.ZipFile]::Open($zsrc, 'Create'); $w = New-Object IO.StreamWriter($za.CreateEntry('sub/update.msi').Open()); $w.Write('msi'); $w.Dispose(); $za.Dispose()
$d = New-Download 'Thu.Zip' 'thu.zip' "  InstallerType: zip`n  NestedInstallerType: wix`n  NestedInstallerFiles:`n  - RelativeFilePath: sub\update.msi" -Content $zsrc
New-BoCaiPackage -SourceDir $d -DestRoot $root -Id 'Thu.Zip' | Out-Null
$script:Runs.Clear()
$r = Install-BoCaiPackage -Root $root -Id 'Thu.Zip' 6>$null
Check ($r.Ok -and $script:Runs.Count -eq 1 -and $script:Runs[0].Exe -eq 'msiexec.exe' -and $script:Runs[0].Args -like '/i "*sub\update.msi" /quiet /norestart' -and $script:Runs[0].FileThere) 'file nén có msi bên trong: giải nén rồi chạy msi trong đó'
$tmpLeft = @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'TramTool_bocai_*' | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-2) })
Check (-not $tmpLeft.Count) 'thư mục giải nén tạm đã xoá'

# Ứng dụng dạng nén chạy ngay (như UniKey): chép vào Program Files (thư mục thử), lối tắt, mục Programs and Features.
$zsrc = Join-Path $dir 'portable.zip'
$za = [IO.Compression.ZipFile]::Open($zsrc, 'Create')
foreach ($n in 'UniKeyNT.exe', 'keymap.txt') { $w = New-Object IO.StreamWriter($za.CreateEntry($n).Open()); $w.Write($n); $w.Dispose() }
$za.Dispose()
$d = New-Download 'Thu.Portable' 'thu.zip' "  InstallerType: zip`n  NestedInstallerType: portable`n  NestedInstallerFiles:`n  - RelativeFilePath: UnikeyNT.exe" -Content $zsrc
New-BoCaiPackage -SourceDir $d -DestRoot $root -Id 'Thu.Portable' | Out-Null
$script:Runs.Clear()
$before = Get-InstalledPrograms
$r = Install-BoCaiPackage -Root $root -Id 'Thu.Portable' 6>$null
$pd = Join-Path $script:BoCaiPortableRoot 'Ten Thu.Portable'
$key = 'HKCU:\Software\TramToolTest\Uninstall\TramTool_Thu.Portable'
Check ($r.Ok -and $script:Runs.Count -eq 0 -and (Test-Path -LiteralPath (Join-Path $pd 'UniKeyNT.exe')) -and (Test-Path -LiteralPath (Join-Path $pd 'keymap.txt'))) 'dạng nén chạy ngay: chép cả thư mục, không chạy gì'
Check ((Test-Path -LiteralPath (Join-Path $script:BoCaiStartMenu 'Ten Thu.Portable.lnk')) -and (Get-ItemProperty -LiteralPath $key).DisplayName -eq 'Ten Thu.Portable' -and (Get-ItemProperty -LiteralPath $key).UninstallString -match [regex]::Escape($pd)) 'lối tắt ở Start menu, mục Programs and Features có lệnh gỡ đúng thư mục'
$p = Get-BoCaiPackage $root 'Thu.Portable'
Check (-not (Test-BoCaiInstalled $p $before) -and (Test-BoCaiInstalled $p (Get-InstalledPrograms))) 'trước khi cài: chưa có; sau khi cài: nhận đã có'
$prog = @([pscustomobject]@{ Name = 'Khac'; Code = '{AAAAAAAA-0000-0000-0000-000000000001}' })
Check ((Test-BoCaiInstalled (Get-BoCaiPackage $root 'Thu.Msi') $prog) -and -not (Test-BoCaiInstalled (Get-BoCaiPackage $root 'Thu.Ma') $prog)) 'nhận đã cài theo mã sản phẩm'

Write-KT '5. Trạm: nút Cài loại winget' Cyan
$env:TRAMTOOL_BO_CAI = $root
$req = [pscustomobject]@{ type = 'command'; name = 'khong-co-lenh-nay-xyz'; label = 'ODBC'; fix = [pscustomobject]@{ label = 'Cài'; winget = 'Thu.Msi' } }
$r1 = Test-ToolRequirement -Req $req -Tool ([pscustomobject]@{ id = 'thu'; dir = $dir })
$req.fix.winget = 'Khong.Co'
$r2 = Test-ToolRequirement -Req $req -Tool ([pscustomobject]@{ id = 'thu'; dir = $dir })
Check ($r1.bundled -and -not $r2.bundled) 'yêu cầu có bộ cài sẵn: bundled = true; không có: false'
$hub = [IO.File]::ReadAllText((Join-Path $HubDir 'TramTool.ps1'), [Text.Encoding]::UTF8)
Check ($hub -match "lib\\BoCai\.ps1" -and $hub -match "file = 'Cai-BoCai\.ps1'" -and $hub -match "fixedArgs = @\('-Id'" -and $hub -match 'Resolve-ActionArguments -Action \$fixAction') 'máy chủ nạp BoCai.ps1; nút Cài có bộ cài sẵn chạy Cai-BoCai.ps1 -Id <gói>'
$ps = Join-Path $PSHOME 'powershell.exe'
$o = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HubDir 'fixes\Cai-BoCai.ps1') -Id 'Thu.Msi' -ChayThu 2>&1 | Out-String
Check ($LASTEXITCODE -eq 0 -and $o -match 'Ten Thu.Msi' -and $o -match 'Chạy thử') "Cai-BoCai.ps1 -ChayThu: mã 0, in gói ($LASTEXITCODE)"
$o = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $HubDir 'fixes\Cai-BoCai.ps1') -Id 'Khong.Co' -ChayThu 2>&1 | Out-String
Check ($LASTEXITCODE -eq 2 -and $o -match 'không có sẵn') "Cai-BoCai.ps1 gói không có: mã 2 ($LASTEXITCODE)"
# CAI_DAT.bat (hub\CaiDat.ps1): kế hoạch cài dùng bộ cài có sẵn thay cho winget.
$cdAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $HubDir 'CaiDat.ps1'), [ref]$null, [ref]$null)
$fn = @($cdAst.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-InstallPlan' }, $false))[0]
. ([scriptblock]::Create($fn.Extent.Text))
$cat = @([pscustomobject]@{ id = 'thu-cd'; name = 'Thu'; dir = $dir; actions = @(); requires = @(
            [pscustomobject]@{ id = 'a'; type = 'command'; name = 'khong-co-lenh-nay-xyz'; label = 'ODBC'; fix = [pscustomobject]@{ label = 'Cài ODBC'; winget = 'Thu.Msi' } },
            [pscustomobject]@{ id = 'b'; type = 'command'; name = 'khong-co-lenh-nay-abc'; label = 'Khác'; fix = [pscustomobject]@{ label = 'Cài khác'; winget = 'Khong.Co' } }) })
$plan = Get-InstallPlan $cat
$pa = @($plan.items | Where-Object { $_.id -eq 'Thu.Msi' })[0]; $pb = @($plan.items | Where-Object { $_.id -eq 'Khong.Co' })[0]
Check ($pa.kind -eq 'bocai' -and $pa.admin -and $pa.how -match 'bộ cài có sẵn trong bản này \(Ten Thu\.Msi bản 1\.2\.3' -and $pb.kind -eq 'winget') "CAI_DAT.bat: gói có sẵn cài từ bộ cài của bản này, gói không có thì winget ($($pa.kind), $($pb.kind))"
$cd = [IO.File]::ReadAllText((Join-Path $HubDir 'CaiDat.ps1'), [Text.Encoding]::UTF8)
Check ($cd -match "lib\\BoCai\.ps1" -and $cd -match "'bocai' \{" -and $cd -match "fixes\\Cai-BoCai\.ps1") 'CAI_DAT.bat nạp BoCai.ps1, chạy Cai-BoCai.ps1 -Id <gói>'
Remove-Item Env:TRAMTOOL_BO_CAI
$sql = [IO.File]::ReadAllText((Join-Path $HubDir 'fixes\Cai-SqlLocalDB.ps1'), [Text.Encoding]::UTF8)
Check ($sql -match "Get-BoCaiPackage \(Get-HubBoCaiRoot\) 'SqlLocalDB'" -and @([regex]::Matches($sql, 'Remove-Item -LiteralPath \$msi')).Count -eq @([regex]::Matches($sql, 'if \(-not \$coSan\) \{ Remove-Item -LiteralPath \$msi')).Count) 'Cai-SqlLocalDB.ps1 dùng bộ cài có sẵn, không bao giờ xoá nó'
Clear-TestRegistry
Complete-Test
