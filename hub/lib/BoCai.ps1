# Bộ cài có sẵn trong bản portable (runtime\bo-cai): mỗi gói một thư mục <mã gói>\ có goi.json và file bộ cài.
# hub\dev\DongGoi.ps1 dựng các thư mục này từ 'winget download' (đọc file .yaml kê khai đi kèm, đối chiếu mã SHA-256).
# Trạm (nút Cài của yêu cầu loại winget) và Bộ ứng dụng văn phòng cài từ đây, không cần mạng: kiểm lại mã SHA-256 trước
# khi chạy, cài gói phụ thuộc trước, chạy bộ cài im lặng theo loại (msi, burn, nullsoft, inno, exe có lệnh im lặng, zip).
# File này không phụ thuộc thư viện khác của trạm: công cụ nạp được riêng.

$script:BoCaiUninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
)
$script:BoCaiOkCodes = @(0, 3010, 1641, 1638)   # xong; cần khởi động lại; đã khởi động lại; đã có bản này hoặc mới hơn
$script:BoCaiRebootCodes = @(3010, 1641)
# Ứng dụng dạng nén chạy ngay (portable): chép vào đây, lối tắt ở Start menu, một mục trong Programs and Features.
$script:BoCaiPortableRoot = $env:ProgramFiles
$script:BoCaiStartMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
$script:BoCaiUninstallWriteKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'

function Get-BoCaiRoot {
    # Thư mục bộ cài: TRAMTOOL_BO_CAI (bài thử) hoặc <thư mục trạm>\runtime\bo-cai.
    param([string]$TramDir)
    if ($env:TRAMTOOL_BO_CAI) { return $env:TRAMTOOL_BO_CAI }
    return (Join-Path $TramDir 'runtime\bo-cai')
}

function Get-HubBoCaiRoot {
    # Thư mục bộ cài của trạm chứa file này (hub\lib\BoCai.ps1).
    return (Get-BoCaiRoot (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
}

# ---------------------------------------------------------------- đọc file kê khai của winget (YAML)
function Find-YamlQuoteEnd {
    # Vị trí dấu nháy đóng của chuỗi bắt đầu bằng ' hoặc " (ký tự 0 của $S); -1 khi chưa đóng trên chuỗi này.
    param([string]$S)
    $q = $S[0]
    for ($i = 1; $i -lt $S.Length; $i++) {
        if ($q -eq "'" -and $S[$i] -eq "'") {
            if ($i + 1 -lt $S.Length -and $S[$i + 1] -eq "'") { $i++; continue }   # '' là một dấu nháy
            return $i
        }
        if ($q -eq '"' -and $S[$i] -eq '\') { $i++; continue }
        if ($q -eq '"' -and $S[$i] -eq '"') { return $i }
    }
    return -1
}

function Get-YamlValuePart {
    # Phần giá trị của một dòng: bỏ "- " đầu dòng và "khoá:" (nếu có).
    param([string]$T)
    $v = $T
    while ($v -match '^-(\s+|$)') { $v = $v.Substring($Matches[0].Length) }
    if ($v -match '^[^\s''"#][^:#]*?:(\s+|$)') { $v = $v.Substring($Matches[0].Length) }
    return $v
}

function ConvertTo-YamlScalar {
    param([string]$S)
    $s = $S.Trim()
    if (-not $s) { return '' }
    if ($s[0] -eq "'" -or $s[0] -eq '"') {
        $e = Find-YamlQuoteEnd $s
        $body = if ($e -gt 0) { $s.Substring(1, $e - 1) } else { $s.Substring(1) }
        if ($s[0] -eq "'") { return $body.Replace("''", "'") }
        $body = [regex]::Replace($body, '\\u([0-9A-Fa-f]{4})|\\x([0-9A-Fa-f]{2})', { param($m) [string][char][Convert]::ToInt32($(if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }), 16) })
        return $body.Replace('\n', "`n").Replace('\t', "`t").Replace('\"', '"').Replace('\\', '\')
    }
    if ($s -match '^(.*?)\s+#') { $s = $Matches[1] }
    return $s
}

function ConvertFrom-SimpleYaml {
    # Phần YAML mà file kê khai của winget dùng: ánh xạ, danh sách (cả danh sách cùng lề với khoá cha), chuỗi trần hoặc
    # trong nháy (kể cả nhiều dòng), khối | và >. Không có neo, thẻ, ánh xạ kiểu {a: b}. Trả OrderedDictionary/mảng/chuỗi.
    param([string]$Text)
    $raw = $Text -split "`r?`n"
    $items = New-Object System.Collections.ArrayList
    $i = 0
    while ($i -lt $raw.Count) {
        $line = $raw[$i].TrimEnd(); $i++
        if ($line -match '^\s*(#.*)?$') { continue }
        $indent = $line.Length - $line.TrimStart(' ').Length
        $t = $line.Substring($indent)
        if ($t -eq '---' -or $t -eq '...') { continue }
        $block = $null
        $v = Get-YamlValuePart $t
        if ($v -and ($v[0] -eq "'" -or $v[0] -eq '"') -and (Find-YamlQuoteEnd $v) -lt 0) {
            # Chuỗi trong nháy chưa đóng: nối các dòng sau (YAML gấp xuống dòng thành dấu cách).
            while ($i -lt $raw.Count) {
                $t += ' ' + $raw[$i].Trim(); $i++
                if ((Find-YamlQuoteEnd (Get-YamlValuePart $t)) -ge 0) { break }
            }
        } elseif ($v -match '^[|>][-+0-9]*\s*(#.*)?$') {
            $lines = @()
            while ($i -lt $raw.Count -and ($raw[$i] -match '^\s*$' -or ($raw[$i].Length - $raw[$i].TrimStart(' ').Length) -gt $indent)) { $lines += $raw[$i].Trim(); $i++ }
            $block = ($lines -join "`n").Trim()
            $t = $t.Substring(0, $t.Length - $v.Length).TrimEnd()
        }
        [void]$items.Add([pscustomobject]@{ Indent = $indent; Text = $t; Block = $block })
    }
    $script:YPos = 0
    if (-not $items.Count) { return $null }
    return (Read-YamlNode $items)
}

function Read-YamlNode {
    param($Items)
    $first = $Items[$script:YPos]
    if ($first.Text -match '^-(\s|$)') { return , (Read-YamlSeq $Items $first.Indent) }
    return (Read-YamlMap $Items $first.Indent)
}

function Read-YamlMap {
    param($Items, [int]$Indent)
    $map = [ordered]@{}
    while ($script:YPos -lt $Items.Count) {
        $it = $Items[$script:YPos]
        if ($it.Indent -lt $Indent -or ($it.Indent -eq $Indent -and $it.Text -match '^-(\s|$)')) { break }
        $script:YPos++
        if ($it.Indent -gt $Indent -or $it.Text -notmatch '^([^\s''"#][^:#]*?):(\s+(.*))?$') { continue }   # dòng lạ: bỏ qua
        $key = $Matches[1].Trim(); $rest = [string]$Matches[3]
        if ($null -ne $it.Block) { $map[$key] = $it.Block; continue }
        if ($rest.Trim()) { $map[$key] = ConvertTo-YamlScalar $rest; continue }
        $map[$key] = $null
        if ($script:YPos -lt $Items.Count) {
            $n = $Items[$script:YPos]
            if ($n.Indent -gt $Indent -or ($n.Indent -eq $Indent -and $n.Text -match '^-(\s|$)')) { $map[$key] = Read-YamlNode $Items }
        }
    }
    return $map
}

function Read-YamlSeq {
    param($Items, [int]$Indent)
    $list = New-Object System.Collections.ArrayList
    while ($script:YPos -lt $Items.Count) {
        $it = $Items[$script:YPos]
        if ($it.Indent -ne $Indent -or $it.Text -notmatch '^-(\s|$)') { break }
        $after = $it.Text.Substring(1)
        $body = $after.TrimStart()
        if (-not $body) {
            $script:YPos++
            if ($script:YPos -lt $Items.Count -and $Items[$script:YPos].Indent -gt $Indent) { [void]$list.Add((Read-YamlNode $Items)) } else { [void]$list.Add($null) }
            continue
        }
        if ($body -match '^[^\s''"#][^:#]*?:(\s|$)') {
            # "- khoá: giá trị": phần tử là ánh xạ, các khoá sau thẳng cột với khoá đầu.
            $it.Indent = $Indent + 1 + ($after.Length - $body.Length); $it.Text = $body
            [void]$list.Add((Read-YamlMap $Items $it.Indent))
            continue
        }
        $script:YPos++
        [void]$list.Add($(if ($null -ne $it.Block) { $it.Block } else { ConvertTo-YamlScalar $body }))
    }
    return , $list.ToArray()
}

# ---------------------------------------------------------------- thông tin gói từ file kê khai
function Get-ManifestValue {
    param($Map, [string]$Key)
    if ($Map -is [Collections.IDictionary] -and $Map.Contains($Key)) { return $Map[$Key] }
    return $null
}

function Get-NamePrefix {
    # Tên trong Programs and Features bỏ phần số bản và phần trong ngoặc ở cuối (Windows hay ghi thêm 32/64 bit, ngôn
    # ngữ khác với file kê khai): "7-Zip 26.06 (x64 edition)" -> "7-Zip", "Mozilla Firefox (en-US)" -> "Mozilla Firefox".
    param([string]$Name)
    $n = ($Name -replace '\s*[-–]?\s*v?\d+(\.\d+)+.*$', '').Trim()
    $n = ($n -replace '(\s*\([^()]*\))+$', '').Trim()
    if ($n.Length -lt 3) { $n = $Name.Trim() }
    return $n
}

function ConvertFrom-WingetManifest {
    # Thông tin cài từ file kê khai kiểu "merged" mà 'winget download' ghi cạnh bộ cài (một bộ cài đã chọn). Trường
    # nằm ở bộ cài thì dùng, không thì lấy ở gốc (winget cho phép ghi chung ở gốc).
    param([string]$Path)
    $m = ConvertFrom-SimpleYaml ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8))
    if (-not ($m -is [Collections.IDictionary])) { throw "File kê khai $Path không đọc được." }
    $inst = @(Get-ManifestValue $m 'Installers') | Select-Object -First 1
    $pick = { param($k) $v = Get-ManifestValue $inst $k; if ($null -eq $v) { $v = Get-ManifestValue $m $k }; $v }
    $sw = & $pick 'InstallerSwitches'
    $entries = @(& $pick 'AppsAndFeaturesEntries' | Where-Object { $_ })
    $codes = @(@(& $pick 'ProductCode') + @($entries | ForEach-Object { Get-ManifestValue $_ 'ProductCode' }) | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim() } | Select-Object -Unique)
    $name = [string](Get-ManifestValue $m 'PackageName')
    $names = @(@($entries | ForEach-Object { Get-ManifestValue $_ 'DisplayName' }) + $name | Where-Object { $_ } | ForEach-Object { Get-NamePrefix ([string]$_) } | Select-Object -Unique)
    $ok = @(@(& $pick 'InstallerSuccessCodes') | Where-Object { "$_" -match '^-?\d+$' } | ForEach-Object { [int64]$_ })
    foreach ($e in @(& $pick 'ExpectedReturnCodes')) {
        # rebootRequiredForInstall không có ở đây: bộ cài chưa cài, đòi khởi động lại rồi chạy lại.
        if ([string](Get-ManifestValue $e 'ReturnResponse') -in 'alreadyInstalled', 'rebootRequiredToFinish', 'rebootInitiated', 'installSuccess') {
            $c = [string](Get-ManifestValue $e 'InstallerReturnCode'); if ($c -match '^-?\d+$') { $ok += [int64]$c }
        }
    }
    $deps = @(@(Get-ManifestValue (& $pick 'Dependencies') 'PackageDependencies') | ForEach-Object { [string](Get-ManifestValue $_ 'PackageIdentifier') } | Where-Object { $_ })
    return [pscustomobject][ordered]@{
        id = [string](Get-ManifestValue $m 'PackageIdentifier'); ten = $name; phienBan = [string](Get-ManifestValue $m 'PackageVersion')
        nhaPhatHanh = [string](Get-ManifestValue $m 'Publisher')
        kienTruc = [string](& $pick 'Architecture'); loai = ([string](& $pick 'InstallerType')).ToLowerInvariant()
        loaiTrong = ([string](& $pick 'NestedInstallerType')).ToLowerInvariant()
        tepTrong = @(@(& $pick 'NestedInstallerFiles') | ForEach-Object { [string](Get-ManifestValue $_ 'RelativeFilePath') } | Where-Object { $_ })
        sha256 = ([string](& $pick 'InstallerSha256')).ToUpperInvariant(); phamVi = [string](& $pick 'Scope')
        lenhIm = [string](Get-ManifestValue $sw 'Silent'); them = [string](Get-ManifestValue $sw 'Custom')
        maSanPham = $codes; tenCaiDat = $names; maThanhCong = @($ok | Select-Object -Unique); phuThuoc = $deps
    }
}

function New-BoCaiPackage {
    # Dựng runtime\bo-cai\<mã gói> từ thư mục 'winget download' (file .yaml và bộ cài): đối chiếu mã SHA-256 với file kê
    # khai, chép bộ cài sang, ghi goi.json. Trả nội dung goi.json; lỗi thì ném lỗi.
    param([string]$SourceDir, [string]$DestRoot, [string]$Id)
    $yaml = @(Get-ChildItem -LiteralPath $SourceDir -Filter '*.yaml' -File)
    if ($yaml.Count -ne 1) { throw "Thư mục $SourceDir cần đúng một file .yaml kê khai (đang có $($yaml.Count))." }
    $info = ConvertFrom-WingetManifest $yaml[0].FullName
    if ($Id -and $info.id -ne $Id) { throw "File kê khai trong $SourceDir là của $($info.id), không phải $Id." }
    $files = @(Get-ChildItem -LiteralPath $SourceDir -File | Where-Object { $_.Extension -ne '.yaml' })
    if ($files.Count -ne 1) { throw "Thư mục $SourceDir cần đúng một file bộ cài (đang có $($files.Count))." }
    $hash = (Get-FileHash -LiteralPath $files[0].FullName -Algorithm SHA256).Hash
    if (-not $info.sha256 -or $hash -ne $info.sha256) { throw "Bộ cài $($files[0].Name) sai mã SHA-256 so với file kê khai." }
    $dest = Join-Path $DestRoot $info.id
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -LiteralPath $files[0].FullName -Destination $dest
    $goi = [ordered]@{ chuan = 'tramtool.bocai/1'; nguon = 'winget'; tep = $files[0].Name; kichThuoc = $files[0].Length }
    foreach ($p in $info.PSObject.Properties) { $goi[$p.Name] = $p.Value }
    [IO.File]::WriteAllText((Join-Path $dest 'goi.json'), ([pscustomobject]$goi | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
    return [pscustomobject]$goi
}

function New-BoCaiFilePackage {
    # Gói không lấy từ winget (vd SQL Server LocalDB .msi tải thẳng từ Microsoft): chép file, ghi goi.json với mã SHA-256
    # tính lúc đóng gói. $Info: id, ten, phienBan, nhaPhatHanh, loai, lenhIm, phamVi, tenCaiDat.
    param([string]$File, [string]$DestRoot, [hashtable]$Info)
    $dest = Join-Path $DestRoot $Info.id
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -LiteralPath $File -Destination $dest
    $fi = Get-Item -LiteralPath $File
    $goi = [ordered]@{
        chuan = 'tramtool.bocai/1'; nguon = 'tai-thang'; tep = $fi.Name; kichThuoc = $fi.Length
        id = $Info.id; ten = $Info.ten; phienBan = $Info.phienBan; nhaPhatHanh = $Info.nhaPhatHanh; kienTruc = 'x64'
        loai = $Info.loai; loaiTrong = ''; tepTrong = @(); sha256 = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
        phamVi = $Info.phamVi; lenhIm = $Info.lenhIm; them = ''; maSanPham = @(); tenCaiDat = @($Info.tenCaiDat); maThanhCong = @(); phuThuoc = @()
    }
    [IO.File]::WriteAllText((Join-Path $dest 'goi.json'), ([pscustomobject]$goi | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
    return [pscustomobject]$goi
}

# ---------------------------------------------------------------- dùng gói
function Get-BoCaiPackage {
    # goi.json của gói (thêm Dir, Path); $null khi gói không có trong bản này hoặc thiếu file bộ cài.
    param([string]$Root, [string]$Id)
    if (-not $Root -or -not $Id -or $Id -notmatch '^[A-Za-z0-9][A-Za-z0-9.+_-]*$') { return $null }
    $dir = Join-Path $Root $Id
    $j = Join-Path $dir 'goi.json'
    if (-not (Test-Path -LiteralPath $j -PathType Leaf)) { return $null }
    try { $p = [IO.File]::ReadAllText($j, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { return $null }
    if (-not $p.tep -or $p.tep -match '[\\/]|^\.\.?$') { return $null }
    $path = Join-Path $dir $p.tep
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $p | Add-Member -NotePropertyName Dir -NotePropertyValue $dir -Force
    $p | Add-Member -NotePropertyName Path -NotePropertyValue $path -Force
    return $p
}

function Test-BoCaiHash {
    param($Pkg)
    return ((Get-FileHash -LiteralPath $Pkg.Path -Algorithm SHA256).Hash -eq ([string]$Pkg.sha256).ToUpperInvariant())
}

function Get-BoCaiCommand {
    # Lệnh cài im lặng theo loại bộ cài (như winget làm). Trả Kind (run, appx, portable) với Exe, Args; $null khi loại này
    # không cài im lặng được (exe không khai lệnh im lặng, portable không phải zip).
    param([string]$Type, [string]$File, [string]$Silent = '', [string]$Custom = '')
    $sw = $Silent.Trim()
    $flags = switch ($Type) {
        { $_ -in 'msi', 'wix' } { return [pscustomobject]@{ Kind = 'run'; Exe = 'msiexec.exe'; Args = ('/i "{0}" {1} {2}' -f $File, $(if ($sw) { $sw } else { '/quiet /norestart' }), $Custom).Trim() } }
        'burn' { if ($sw) { $sw } else { '/quiet /norestart' } }
        'nullsoft' { if ($sw) { $sw } else { '/S' } }
        'inno' { if ($sw) { $sw } else { '/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART' } }
        'exe' { if ($sw) { $sw } else { return $null } }
        { $_ -in 'msix', 'appx' } { return [pscustomobject]@{ Kind = 'appx'; Exe = ''; Args = '' } }
        default { return $null }
    }
    return [pscustomobject]@{ Kind = 'run'; Exe = $File; Args = ('{0} {1}' -f $flags, $Custom).Trim() }
}

function Invoke-BoCaiProcess {
    # Chạy bộ cài trong cùng cửa sổ, chờ xong, trả mã thoát (bài thử thay hàm này).
    param([string]$Exe, [string]$Arguments)
    $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -Wait -PassThru
    try { return [int64]$p.ExitCode } catch { return 1 }
}

function Get-InstalledPrograms {
    # Danh sách Programs and Features (64 bit, 32 bit, của tài khoản): tên, mã (tên khoá, mã sản phẩm MSI), bản.
    $out = foreach ($k in $script:BoCaiUninstallKeys) {
        foreach ($s in @(Get-ChildItem -LiteralPath $k -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $s.PSPath -ErrorAction SilentlyContinue
            if ($p -and $p.DisplayName -and -not $p.SystemComponent) { [pscustomobject]@{ Name = [string]$p.DisplayName; Code = $s.PSChildName; Version = [string]$p.DisplayVersion } }
        }
    }
    return , @($out)
}

function Test-BoCaiInstalled {
    # Gói đã có trong Programs and Features: trùng mã sản phẩm, hoặc tên bắt đầu bằng tên của gói.
    param($Pkg, [object[]]$Programs)
    foreach ($c in @($Pkg.maSanPham)) { if (@($Programs | Where-Object { $_.Code -ieq $c }).Count) { return $true } }
    foreach ($n in @($Pkg.tenCaiDat)) { if ($n -and @($Programs | Where-Object { $_.Name.StartsWith($n, [StringComparison]::OrdinalIgnoreCase) }).Count) { return $true } }
    return $false
}

function Install-BoCaiPortable {
    # Ứng dụng dạng nén chạy ngay (vd UniKey): chép vào Program Files\<tên>, lối tắt ở Start menu, một mục trong
    # Programs and Features để gỡ được và để kiểm tra biết đã cài.
    param($Pkg, [string]$Folder)
    $name = ([string]$Pkg.ten -replace '[\\/:*?"<>|]', '').Trim()
    if (-not $name) { $name = $Pkg.id }
    $exeRel = @($Pkg.tepTrong)[0]
    if (-not $exeRel -or $exeRel -match '(^|[\\/])\.\.([\\/]|$)' -or -not (Test-Path -LiteralPath (Join-Path $Folder $exeRel) -PathType Leaf)) { throw "Gói $($Pkg.id) không có file chạy $exeRel." }
    $dest = Join-Path $script:BoCaiPortableRoot $name
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path (Join-Path $Folder '*') -Destination $dest -Recurse -Force
    $exe = Join-Path $dest $exeRel
    New-Item -ItemType Directory -Path $script:BoCaiStartMenu -Force | Out-Null
    $lnk = Join-Path $script:BoCaiStartMenu "$name.lnk"
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk); $s.TargetPath = $exe; $s.WorkingDirectory = Split-Path $exe; $s.Save()
    $key = Join-Path $script:BoCaiUninstallWriteKey ('TramTool_' + ($Pkg.id -replace '[^A-Za-z0-9._-]', '_'))
    New-Item -Path $key -Force | Out-Null
    $go = "powershell.exe -NoProfile -Command `"Remove-Item -LiteralPath '$dest' -Recurse -Force; Remove-Item -LiteralPath '$lnk' -Force; Remove-Item -LiteralPath '$key' -Recurse -Force`""
    $vals = [ordered]@{ DisplayName = $name; DisplayVersion = [string]$Pkg.phienBan; Publisher = [string]$Pkg.nhaPhatHanh; InstallLocation = $dest; DisplayIcon = $exe; UninstallString = $go }
    foreach ($k in $vals.Keys) { Set-ItemProperty -LiteralPath $key -Name $k -Value $vals[$k] }
    foreach ($k in 'NoModify', 'NoRepair') { Set-ItemProperty -LiteralPath $key -Name $k -Value 1 -Type DWord }
    return $exe
}

function Install-BoCaiPackage {
    # Cài một gói (gói phụ thuộc trước). Trả Ok, Code, Reboot, Message. -DryRun: chỉ in việc sẽ làm.
    param([string]$Root, [string]$Id, [switch]$DryRun, [hashtable]$Seen = @{})
    $r = [pscustomobject]@{ Ok = $false; Code = [int64]-1; Reboot = $false; Message = '' }
    if ($Seen.ContainsKey($Id)) { $r.Ok = $true; return $r }
    $Seen[$Id] = $true
    $p = Get-BoCaiPackage $Root $Id
    if (-not $p) { $r.Message = "Bản này không có sẵn bộ cài $Id."; return $r }
    $programs = $null
    foreach ($d in @($p.phuThuoc)) {
        $dp = Get-BoCaiPackage $Root $d
        if (-not $dp) { Write-Host "       Gói phụ thuộc $d không có sẵn trong bản này: bộ cài $($p.ten) có thể báo thiếu." -ForegroundColor Yellow; continue }
        if ($null -eq $programs) { $programs = Get-InstalledPrograms }
        if (Test-BoCaiInstalled $dp $programs) { Write-Host "       Đã có $($dp.ten) (gói phụ thuộc)." -ForegroundColor Gray; continue }
        $dr = Install-BoCaiPackage -Root $Root -Id $d -DryRun:$DryRun -Seen $Seen
        if (-not $dr.Ok) { $r.Message = "Chưa cài được gói phụ thuộc $($dp.ten): $($dr.Message)"; return $r }
        if ($dr.Reboot) { $r.Reboot = $true }
    }
    $cmd = if ($p.loai -eq 'zip') { if ($p.loaiTrong -eq 'portable') { [pscustomobject]@{ Kind = 'portable' } } else { Get-BoCaiCommand $p.loaiTrong '<trong file nén>' $p.lenhIm $p.them } }
    else { Get-BoCaiCommand $p.loai $p.Path $p.lenhIm $p.them }
    if (-not $cmd) { $r.Message = "Bộ cài $($p.tep) (loại $($p.loai)$(if ($p.loaiTrong) { "/$($p.loaiTrong)" })) không cài im lặng được."; return $r }
    Write-Host ("       Bộ cài có sẵn: {0} bản {1} ({2})" -f $p.ten, $p.phienBan, $p.tep) -ForegroundColor Gray
    if ($DryRun) { $r.Ok = $true; $r.Code = 0; $r.Message = 'Chạy thử: không cài.'; return $r }
    if (-not (Test-BoCaiHash $p)) { $r.Message = "Bộ cài $($p.tep) sai mã SHA-256 (file hỏng hoặc bị sửa): không chạy."; return $r }
    $ok = @($script:BoCaiOkCodes) + @($p.maThanhCong | ForEach-Object { [int64]$_ })
    $tmp = $null
    try {
        if ($p.loai -eq 'zip') {
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('TramTool_bocai_' + [guid]::NewGuid().ToString('N'))
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::ExtractToDirectory($p.Path, $tmp)
            if ($cmd.Kind -eq 'portable') {
                $exe = Install-BoCaiPortable $p $tmp
                $r.Ok = $true; $r.Code = 0; $r.Message = "Đã chép vào $(Split-Path $exe), lối tắt ở Start menu."; return $r
            }
            $inner = @($p.tepTrong)[0]
            if (-not $inner -or $inner -match '(^|[\\/])\.\.([\\/]|$)') { $r.Message = 'File nén không ghi bộ cài bên trong.'; return $r }
            $cmd = Get-BoCaiCommand $p.loaiTrong (Join-Path $tmp $inner) $p.lenhIm $p.them
        }
        if ($cmd.Kind -eq 'appx') {
            try { Add-AppxPackage -Path $p.Path -ErrorAction Stop; $r.Code = 0 } catch { $r.Code = 1; $r.Message = $_.Exception.Message.Trim(); return $r }
        } else {
            $r.Code = Invoke-BoCaiProcess $cmd.Exe $cmd.Args
        }
    } finally { if ($tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } }
    $r.Ok = $ok -contains $r.Code
    if ($script:BoCaiRebootCodes -contains $r.Code) { $r.Reboot = $true }
    if (-not $r.Ok) { $r.Message = "Bộ cài báo mã $($r.Code)." }
    return $r
}
