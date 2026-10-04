<# :
@echo off
rem ==========================================================================
rem  MyExcel VietQR - SUA LOI cho profile bi loi (co sao luu + file hoan tac)
rem  Double-click trong profile BI LOI (vd USER). Luu va dong Excel truoc.
rem  Ban sao cua file nay ten HoanTac_FixMyExcel.bat trong thu muc sao luu
rem  se tu chay che do HOAN TAC.
rem ==========================================================================
chcp 65001 >nul
title MyExcel VietQR - Sua loi
set "MYX_SELF=%~f0"
set "MYX_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "MYX_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%MYX_PS%" -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:MYX_SELF,[Text.Encoding]::UTF8); iex $s"
echo.
if not defined MYX_NOPAUSE pause
exit /b
#>

# ============================================================================
#  MyExcel VietQR - sửa lỗi profile (dùng chung bản chuẩn C:\MyExcel như profile Test)
# ============================================================================
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$script:Log      = New-Object System.Collections.Generic.List[string]
$script:Stamp    = (Get-Date).ToString('yyyyMMdd_HHmmss')
$script:Good     = if ($env:MYX_GOOD) { $env:MYX_GOOD.TrimEnd('\') } else { 'C:\MyExcel' }
$script:Bad      = if ($env:MYX_BAD) { $env:MYX_BAD.TrimEnd('\') } else { 'C:\MyExcelAddin' }
$script:RegBase  = if ($env:MYX_REGBASE) { $env:MYX_REGBASE.Trim('\') + '\' } else { '' }   # chỉ dùng khi test
$script:Auto     = [bool]$env:MYX_AUTO                                                      # chỉ dùng khi test
$script:UndoMode = ((Split-Path $env:MYX_SELF -Leaf) -like 'HoanTac*')
$script:Changes  = 0
$script:Problems = 0
$script:BackupDir = $null
$script:Manifest = [ordered]@{
    Time = (Get-Date).ToString('dd/MM/yyyy HH:mm:ss'); User = $env:USERNAME; Computer = $env:COMPUTERNAME
    Good = $script:Good; Bad = $script:Bad; RegBase = $script:RegBase
    RegExcel = @(); RegVB = $null; NewKeys = @(); ResetKeys = @(); Folder = $null; Workbooks = @()
}

function Say([string]$Text = '', [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color; $script:Log.Add($Text) }
function Step([string]$Title) { Say ''; Say ('=' * 74) 'DarkCyan'; Say "  $Title" 'Cyan'; Say ('=' * 74) 'DarkCyan' }
function Done([string]$Text) { Say "  [ĐÃ SỬA]  $Text" 'Green'; $script:Changes++ }
function Skip([string]$Text) { Say "  [BỎ QUA]  $Text" 'DarkGray' }
function Warn([string]$Text) { Say "  [!]       $Text" 'Yellow'; $script:Problems++ }
function Note([string]$Text) { Say "            $Text" 'Gray' }
function Ask([string]$Question) {
    if ($script:Auto) { Say "  $Question (Y/N): Y  [tự động]" 'White'; return $true }
    while ($true) {
        $a = Read-Host "  $Question (Y/N)"
        if ($a -match '^\s*[YyCc]') { $script:Log.Add("  $Question => Y"); return $true }
        if ($a -match '^\s*[Nn]') { $script:Log.Add("  $Question => N"); return $false }
    }
}
function Test-SamePath([string]$A, [string]$B) {
    if (-not $A -or -not $B) { return $false }
    return (($A -replace '/', '\').TrimEnd('\') -ieq ($B -replace '/', '\').TrimEnd('\'))
}
function Test-UnderPath([string]$Child, [string]$Parent) {
    if (-not $Child -or -not $Parent) { return $false }
    $c = ($Child -replace '/', '\').TrimEnd('\').ToLowerInvariant() + '\'
    $p = ($Parent -replace '/', '\').TrimEnd('\').ToLowerInvariant() + '\'
    return $c.StartsWith($p)
}
function Get-OpenPath([string]$Raw) { return ($Raw -replace '^\s*(/[A-Za-z]\s+)+', '').Trim().Trim('"') }
function Open-UserKey([string]$Sub, [bool]$Write = $false) {
    return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:RegBase + $Sub, $Write)
}
function Get-ExcelVersions {
    $k = Open-UserKey 'Software\Microsoft\Office'
    if (-not $k) { return @() }
    $vers = @($k.GetSubKeyNames() | Where-Object { $_ -match '^\d+\.0$' -and $k.OpenSubKey("$_\Excel") })
    $k.Close()
    return $vers
}
function Get-ExcelMainVersion {
    try {
        $exe = (Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe').GetValue('')
        if ($exe -and (Test-Path -LiteralPath $exe)) { return ('{0}.0' -f (Get-Item -LiteralPath $exe).VersionInfo.FileMajorPart) }
    } catch {}
    return '16.0'
}
function Test-RightUser {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $sid = (Get-Process -Id $PID).SessionId
    $exp = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sid } | Select-Object -First 1
    if ($exp) {
        $o = Invoke-CimMethod -InputObject $exp -MethodName GetOwner -ErrorAction SilentlyContinue
        if ($o -and $o.ReturnValue -eq 0 -and "$($o.Domain)\$($o.User)" -ine $me) {
            Warn "Script đang chạy bằng '$me' nhưng màn hình là của '$($o.Domain)\$($o.User)'. Hãy double-click file .bat trong đúng profile bị lỗi."
            return $false
        }
    }
    return $true
}
function Wait-ExcelClosed {
    $mySid = (Get-Process -Id $PID).SessionId
    while ($true) {
        $all = @(Get-Process -Name 'EXCEL' -ErrorAction SilentlyContinue)
        $mine = @($all | Where-Object { $_.SessionId -eq $mySid })
        if ($mine.Count -eq 0) {
            if ($all.Count -gt 0) { Note "Có Excel đang mở ở profile khác ($($all.Count) tiến trình) - không ảnh hưởng C:\MyExcel, nhưng nên đóng." }
            return $true
        }
        Say "  Excel đang mở trong profile này ($($mine.Count) tiến trình). Hãy LƯU và ĐÓNG hết Excel." 'Yellow'
        if ($script:Auto) { return $false }
        $a = Read-Host '  Nhấn Enter khi đã đóng Excel (gõ Q để thoát)'
        if ($a -match '^\s*[Qq]') { return $false }
    }
}
function Save-Manifest {
    if (-not $script:BackupDir) { return }
    $json = $script:Manifest | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $script:BackupDir 'manifest.json'), $json, (New-Object Text.UTF8Encoding $false))
}

# ----------------------------------------------------------------------------
function Invoke-Backup {
    Step 'BƯỚC 1 - SAO LƯU (registry + file hoàn tác)'
    $root = if ($env:MYX_OUT) { $env:MYX_OUT } else { [Environment]::GetFolderPath('Desktop') }
    $script:BackupDir = Join-Path $root "MyExcelFix_SaoLuu_$($script:Stamp)"
    try {
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
    } catch {
        Warn "Không tạo được thư mục sao lưu $($script:BackupDir): $($_.Exception.Message)"
        return $false
    }
    Note "Thư mục sao lưu: $($script:BackupDir)"

    $regRoot = 'HKCU\' + $script:RegBase
    foreach ($ver in (Get-ExcelVersions)) {
        $file = "Excel_$ver.reg"
        & reg.exe export "$($regRoot)Software\Microsoft\Office\$ver\Excel" (Join-Path $script:BackupDir $file) /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Warn "Không sao lưu được HKCU\...\Office\$ver\Excel (mã lỗi $LASTEXITCODE)"; return $false }
        $script:Manifest.RegExcel += [ordered]@{ Ver = $ver; File = $file }
        Done "Đã sao lưu cấu hình Excel $ver -> $file"
    }
    if (Open-UserKey 'Software\VB and VBA Program Settings') {
        & reg.exe export "$($regRoot)Software\VB and VBA Program Settings" (Join-Path $script:BackupDir 'VBA_Settings.reg') /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Warn "Không sao lưu được dữ liệu MyExcel trong VB and VBA Program Settings (mã lỗi $LASTEXITCODE)"; return $false }
        $script:Manifest.RegVB = 'VBA_Settings.reg'
        Done 'Đã sao lưu dữ liệu MyExcel (VB and VBA Program Settings) -> VBA_Settings.reg'
    }
    try {
        Copy-Item -LiteralPath $env:MYX_SELF -Destination (Join-Path $script:BackupDir 'HoanTac_FixMyExcel.bat') -Force -ErrorAction Stop
        Done 'Đã tạo file hoàn tác HoanTac_FixMyExcel.bat trong thư mục sao lưu'
    } catch {
        Warn "Không tạo được file hoàn tác: $($_.Exception.Message)"
        return $false
    }
    Save-Manifest
    return $true
}

# ----------------------------------------------------------------------------
function Invoke-FolderFix {
    Step "BƯỚC 2 - CẤT BẢN CÀI THỨ HAI ($($script:Bad))"
    $main = Join-Path $script:Good 'MyExcel.xlam'
    if (-not (Test-Path -LiteralPath $main)) {
        Warn "Không thấy $main. Hãy cài MyExcel vào $($script:Good) (bộ cài chuẩn) rồi chạy lại - chưa sửa add-in."
        return $false
    }
    Note "Bản chuẩn: $main"
    if (-not (Test-Path -LiteralPath $script:Bad)) { Skip "Không còn thư mục $($script:Bad)"; return $true }
    $to = "$($script:Bad)_cu"
    if (Test-Path -LiteralPath $to) { $to = "$($script:Bad)_cu_$($script:Stamp)" }
    try {
        Rename-Item -LiteralPath $script:Bad -NewName (Split-Path $to -Leaf) -ErrorAction Stop
        $script:Manifest.Folder = [ordered]@{ From = $script:Bad; To = $to }
        Save-Manifest
        Done "Đổi tên $($script:Bad) -> $to (không xóa)"
    } catch {
        Warn "Không đổi tên được $($script:Bad): $($_.Exception.Message)"
        Note 'Đóng mọi cửa sổ/ứng dụng đang mở file trong thư mục đó rồi chạy lại. Các bước còn lại vẫn được thực hiện.'
    }
    return $true
}

function Invoke-AddinFix {
    Step 'BƯỚC 3 - NẠP MYEXCEL TỪ BẢN CHUẨN (Excel Add-ins, Trusted Locations)'
    $mainVer = Get-ExcelMainVersion
    $mainValue = '"' + (Join-Path $script:Good 'MyExcel.xlam') + '"'
    foreach ($ver in (Get-ExcelVersions)) {
        $k = Open-UserKey "Software\Microsoft\Office\$ver\Excel\Options" $true
        if (-not $k -and $ver -eq $mainVer) {
            $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:RegBase + "Software\Microsoft\Office\$ver\Excel\Options")
        }
        if (-not $k) { continue }
        $entries = @($k.GetValueNames() | Where-Object { $_ -match '^OPEN(\d*)$' } | ForEach-Object {
            $idx = if ($_ -eq 'OPEN') { 0 } else { [int]$_.Substring(4) }
            [pscustomobject]@{ Name = $_; Index = $idx; Value = [string]$k.GetValue($_) }
        } | Sort-Object Index)
        $new = New-Object System.Collections.Generic.List[string]
        $hasMain = $false
        foreach ($e in $entries) {
            $p = Get-OpenPath $e.Value
            $leaf = if ($p) { Split-Path $p -Leaf } else { '' }
            if ($leaf -ieq 'MyExcel.xlam') {
                if (-not $hasMain) { $new.Add($mainValue); $hasMain = $true }
                continue
            }
            if (Test-UnderPath $p $script:Bad) {
                $alt = Join-Path $script:Good ($p.Substring($script:Bad.Length).TrimStart('\'))
                if (Test-Path -LiteralPath $alt) { $new.Add('"' + $alt + '"') }
                continue
            }
            $new.Add($e.Value)
        }
        if (-not $hasMain -and $ver -eq $mainVer) { $new.Insert(0, $mainValue) }
        $old = @($entries | ForEach-Object { $_.Value })
        if (($old -join '|') -ceq ($new -join '|')) {
            Skip "Excel $ver - danh sách add-in đã đúng: $($old -join ' ; ')"
        } else {
            foreach ($e in $entries) { $k.DeleteValue($e.Name, $false) }
            for ($i = 0; $i -lt $new.Count; $i++) {
                $n = if ($i -eq 0) { 'OPEN' } else { "OPEN$i" }
                $k.SetValue($n, $new[$i], [Microsoft.Win32.RegistryValueKind]::String)
            }
            Done ("Excel {0} - add-in đang bật: {1}   (trước đây: {2})" -f $ver, ($new -join ' ; '), $(if ($old.Count) { $old -join ' ; ' } else { 'không có' }))
        }
        $k.Close()

        $am = Open-UserKey "Software\Microsoft\Office\$ver\Excel\Add-in Manager" $true
        if ($am) {
            foreach ($n in $am.GetValueNames()) {
                if ($n -and ((Test-UnderPath $n $script:Bad) -or ((Split-Path $n -Leaf) -ieq 'MyExcel.xlam'))) {
                    $am.DeleteValue($n, $false)
                    Done "Excel $ver - xóa mục cũ khỏi hộp thoại Add-ins: $n"
                }
            }
            $am.Close()
        }
        if ($ver -eq $mainVer) { Set-TrustedLocation $ver }
        Clear-DisabledItems $ver
    }
}

# ----------------------------------------------------------------------------
function Set-TrustedLocation([string]$Ver) {
    $sub = $script:RegBase + "Software\Microsoft\Office\$Ver\Excel\Security\Trusted Locations"
    $tl = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($sub)
    if ($tl.GetValue('AllLocationsDisabled') -eq 1) {
        $tl.SetValue('AllLocationsDisabled', 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        Done 'Bỏ tích "Disable all Trusted Locations"'
    }
    $found = $null; $max = -1
    foreach ($s in $tl.GetSubKeyNames()) {
        if ($s -match '^Location(\d+)$') { $max = [Math]::Max($max, [int]$Matches[1]) }
        $lk = $tl.OpenSubKey($s, $true)
        $p = [Environment]::ExpandEnvironmentVariables([string]$lk.GetValue('Path'))
        if (-not $found -and (Test-SamePath $p $script:Good)) { $found = $lk } else { $lk.Close() }
    }
    if ($found) {
        if ($found.GetValue('AllowSubfolders') -ne 1) {
            $found.SetValue('AllowSubfolders', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
            Done "Trusted Location $($script:Good): tích thêm 'Subfolders of this location are also trusted'"
        } else {
            Skip "Trusted Location $($script:Good)\ (có thư mục con) đã có sẵn"
        }
        $found.Close()
    } else {
        $nk = $tl.CreateSubKey("Location$($max + 1)")
        $nk.SetValue('Path', $script:Good + '\', [Microsoft.Win32.RegistryValueKind]::String)
        $nk.SetValue('AllowSubfolders', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
        $nk.SetValue('Description', 'MyExcel', [Microsoft.Win32.RegistryValueKind]::String)
        $nk.SetValue('Date', (Get-Date).ToString('M/d/yyyy h:mm tt', [Globalization.CultureInfo]::InvariantCulture), [Microsoft.Win32.RegistryValueKind]::String)
        $nk.Close()
        $script:Manifest.NewKeys += "Software\Microsoft\Office\$Ver\Excel\Security\Trusted Locations\Location$($max + 1)"
        Save-Manifest
        Done "Thêm Trusted Location $($script:Good)\ (có thư mục con)"
    }
    $tl.Close()
}

function Clear-DisabledItems([string]$Ver) {
    $dk = Open-UserKey "Software\Microsoft\Office\$Ver\Excel\Resiliency\DisabledItems" $true
    if (-not $dk) { return }
    foreach ($n in $dk.GetValueNames()) {
        $v = $dk.GetValue($n)
        $txt = ''
        if ($v -is [byte[]] -and $v.Length -gt 12) { $txt = [Text.Encoding]::Unicode.GetString($v, 12, $v.Length - 12) -replace '[\x00-\x1F]+', ' ' }
        if ($txt -match '(?i)myexcel|qr.?code|vietqr|minitool') {
            $dk.DeleteValue($n, $false)
            Done "Excel $Ver - bật lại add-in bị vô hiệu hóa: $($txt.Trim())"
        }
    }
    $dk.Close()
}

# ----------------------------------------------------------------------------
function Invoke-VbaPathFix {
    Step 'BƯỚC 4 - SỬA ĐƯỜNG DẪN MYEXCEL TỰ GHI NHỚ (DuongDanADDin...)'
    $root = Open-UserKey 'Software\VB and VBA Program Settings' $true
    if (-not $root) { Skip 'Profile này chưa có dữ liệu MyExcel'; return }
    $rx = '(?i)' + [regex]::Escape($script:Bad) + '(?=\\|$)'
    $good = $script:Good
    $count = 0
    $stack = New-Object System.Collections.Stack
    $stack.Push(@($root, ''))
    while ($stack.Count -gt 0) {
        $item = $stack.Pop(); $key = $item[0]; $path = $item[1]
        foreach ($vn in $key.GetValueNames()) {
            $kind = $key.GetValueKind($vn)
            if ($kind -ne [Microsoft.Win32.RegistryValueKind]::String -and $kind -ne [Microsoft.Win32.RegistryValueKind]::ExpandString) { continue }
            $val = [string]$key.GetValue($vn, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($val -notmatch $rx) { continue }
            $newVal = [regex]::Replace($val, $rx, [Text.RegularExpressions.MatchEvaluator] { param($m) $good })
            $key.SetValue($vn, $newVal, $kind)
            $count++
            Done ("{0}\{1}: {2} -> {3}" -f $path.TrimStart('\'), $vn, $val, $newVal)
        }
        foreach ($sn in $key.GetSubKeyNames()) {
            $sk = $key.OpenSubKey($sn, $true)
            if ($sk) { $stack.Push(@($sk, "$path\$sn")) }
        }
        if ($key -ne $root) { $key.Close() }
    }
    $root.Close()
    if ($count -eq 0) { Skip "Không còn giá trị nào trỏ tới $($script:Bad)" }
}

function Invoke-CacheCleanup {
    Step 'BƯỚC 5 - DỌN CACHE ACTIVEX (.exd) VÀ FILE KHÓA CŨ'
    $dirs = @("$env:TEMP\VBE", "$env:TEMP\Excel8.0", "$env:TEMP\Word8.0", "$env:APPDATA\Microsoft\Forms")
    $n = 0
    foreach ($d in ($dirs | Sort-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        foreach ($f in (Get-ChildItem -LiteralPath $d -Filter '*.exd' -File -Force -ErrorAction SilentlyContinue)) {
            try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $n++ }
            catch { Warn "Không xóa được $($f.FullName) (Word/Excel còn mở?)" }
        }
    }
    if ($n -gt 0) { Done "Xóa $n file cache .exd (Office sẽ tự tạo lại)" } else { Skip 'Không có file .exd' }
    foreach ($f in (Get-ChildItem -LiteralPath $script:Good -Recurse -Depth 1 -Filter '~$*' -File -Force -ErrorAction SilentlyContinue)) {
        if ($f.Length -lt 1KB) {
            try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; Done "Xóa file khóa cũ $($f.FullName)" }
            catch { Warn "Không xóa được file khóa $($f.FullName)" }
        }
    }
}

function Invoke-Unblock {
    Step "BƯỚC 6 - BỎ CHẶN (Unblock) CÁC FILE TRONG $($script:Good)"
    $files = @(Get-ChildItem -LiteralPath $script:Good -Recurse -File -Force -ErrorAction SilentlyContinue)
    $done = 0; $fail = 0
    foreach ($f in $files) {
        if (-not (Get-Item -LiteralPath $f.FullName -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue)) { continue }
        try { Unblock-File -LiteralPath $f.FullName -ErrorAction Stop; $done++ } catch { $fail++ }
    }
    if ($done -gt 0) { Done "Bỏ chặn $done / $($files.Count) file" } else { Skip "Không có file nào bị chặn trong $($files.Count) file" }
    if ($fail -gt 0) { Warn "$fail file không bỏ chặn được (thiếu quyền ghi?)" }
}

# ----------------------------------------------------------------------------
function Get-ScanRoots {
    if ($env:MYX_SCANROOT) { return @($env:MYX_SCANROOT) }
    $cand = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'))
    try { $cand += (Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders').GetValue('{374DE290-123F-4565-9164-39C4925E467B}') } catch {}
    foreach ($a in (Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue)) {
        $uf = $a.GetValue('UserFolder')
        if ($uf) { $cand += [Environment]::ExpandEnvironmentVariables([string]$uf) }
    }
    $roots = @()
    foreach ($c in ($cand | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object Length)) {
        if (-not ($roots | Where-Object { Test-UnderPath $c $_ })) { $roots += $c }
    }
    return $roots
}

function Get-LinkPattern {
    return '(?i)(Target="[^"]*?[\\/])' + [regex]::Escape((Split-Path $script:Bad -Leaf)) + '(?=[\\/])'
}

function Find-LinkedEntries([string]$Path, [string]$Pattern) {
    $hits = @()
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($Path)
        try {
            foreach ($e in $zip.Entries) {
                if ($e.FullName -notmatch '^xl/externalLinks/_rels/[^/]+\.rels$') { continue }
                $sr = New-Object IO.StreamReader($e.Open())
                $txt = $sr.ReadToEnd(); $sr.Close()
                if ($txt -match $Pattern) { $hits += $e.FullName }
            }
        } finally { $zip.Dispose() }
    } catch {}
    return ,$hits
}

function Update-LinkedEntries([string]$Path, [string[]]$Entries, [string]$Pattern) {
    $replacement = '${1}' + (Split-Path $script:Good -Leaf)
    $utf8 = New-Object Text.UTF8Encoding $false
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Update)
        try {
            foreach ($name in $Entries) {
                $entry = $za.GetEntry($name)
                if (-not $entry) { continue }
                $s = $entry.Open()
                try {
                    $sr = New-Object IO.StreamReader($s, $utf8, $true, 4096, $true)
                    $txt = $sr.ReadToEnd(); $sr.Dispose()
                    $bytes = $utf8.GetBytes([regex]::Replace($txt, $Pattern, $replacement))
                    $s.SetLength(0); $s.Position = 0
                    $s.Write($bytes, 0, $bytes.Length)
                } finally { $s.Dispose() }
            }
        } finally { $za.Dispose() }
    } finally { $fs.Dispose() }
}

function Invoke-WorkbookRelink {
    Step "BƯỚC 7 - NỐI LẠI FILE EXCEL CÒN TRỎ TỚI $($script:Bad)"
    try { Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem -ErrorAction Stop }
    catch { Warn "Không nạp được thư viện ZIP: $($_.Exception.Message)"; return }
    $pattern = Get-LinkPattern
    $badLeaf = Split-Path $script:Bad -Leaf
    $roots = @(Get-ScanRoots)
    Note ("Đang quét: {0}" -f ($roots -join ' ; '))
    $ooxml = @(); $binary = @(); $cloud = 0
    foreach ($r in $roots) {
        $files = Get-ChildItem -LiteralPath $r -Recurse -Depth 5 -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(xlsx|xlsm|xltx|xltm|xls|xlsb)$' -and $_.Name -notlike '~$*' -and $_.Length -lt 60MB }
        foreach ($f in $files) {
            # File OneDrive "chỉ có trên mạng" (Offline / RecallOnDataAccess): đọc vào sẽ làm tải cả file về máy
            if (([int]$f.Attributes -band 0x401000) -ne 0) { $cloud++; continue }
            if ($f.Extension -match '^\.(xls|xlsb)$') {
                if ($f.Length -ge 15MB) { continue }
                $bytes = [IO.File]::ReadAllBytes($f.FullName)
                if ([Text.Encoding]::ASCII.GetString($bytes).IndexOf($badLeaf, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                    [Text.Encoding]::Unicode.GetString($bytes).IndexOf($badLeaf, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $binary += $f }
            } else {
                $entries = Find-LinkedEntries $f.FullName $pattern
                if ($entries.Count -gt 0) { $ooxml += [pscustomobject]@{ File = $f; Entries = $entries } }
            }
        }
    }
    if ($cloud -gt 0) { Note "Bỏ qua $cloud file OneDrive chưa tải về máy. File nào báo lỗi liên kết thì sửa bằng Data > Edit Links > Change Source." }
    if ($ooxml.Count -eq 0 -and $binary.Count -eq 0) { Skip "Không có file Excel nào liên kết tới $($script:Bad)"; return }
    foreach ($o in $ooxml) { Note "Liên kết cũ: $($o.File.FullName)" }
    if ($ooxml.Count -gt 0 -and (Ask "Sửa liên kết trong $($ooxml.Count) file trên (mỗi file được sao lưu trước)?")) {
        $wbDir = Join-Path $script:BackupDir 'Workbooks'
        New-Item -ItemType Directory -Path $wbDir -Force | Out-Null
        $i = 0
        foreach ($o in $ooxml) {
            $i++
            $dest = Join-Path $wbDir ('{0:000}_{1}' -f $i, $o.File.Name)
            try {
                Copy-Item -LiteralPath $o.File.FullName -Destination $dest -Force -ErrorAction Stop
                Update-LinkedEntries $o.File.FullName $o.Entries $pattern
                $script:Manifest.Workbooks += [ordered]@{ Original = $o.File.FullName; Backup = $dest }
                Save-Manifest
                Done "Nối lại liên kết: $($o.File.FullName)"
            } catch {
                if (Test-Path -LiteralPath $dest) { Copy-Item -LiteralPath $dest -Destination $o.File.FullName -Force -ErrorAction SilentlyContinue }
                Warn "Không sửa được $($o.File.FullName) (file đang mở?): $($_.Exception.Message)"
            }
        }
    }
    foreach ($b in $binary) {
        Warn "File dạng cũ (.xls/.xlsb) có thể trỏ tới $badLeaf, cần sửa tay bằng Data > Edit Links > Change Source: $($b.FullName)"
    }
}

# ----------------------------------------------------------------------------
function Get-MyExcelStateKeys {
    # MyExcel lưu SaveSetting dưới các tên bị làm rối chỉ gồm chữ i/l (liliiliiliiiliilli, liliiliiliiiliill, ...)
    $vb = Open-UserKey 'Software\VB and VBA Program Settings'
    if (-not $vb) { return @() }
    $names = @($vb.GetSubKeyNames() | Where-Object { $_ -cmatch '^[il]{12,}[a-z0-9]*$' })
    $vb.Close()
    return $names
}

function Show-DeclaredBank {
    $k = Open-UserKey 'Software\VB and VBA Program Settings\liliiliiliiiliilli\GridLight'
    if (-not $k) { return }
    $name = [string]$k.GetValue('TenTKQRG')
    $acct = [string]$k.GetValue('SoTKQRG')
    $emv = [string]$k.GetValue('MaNganhangDongDauQR1')
    $k.Close()
    if (-not $name -and -not $acct) { return }
    $masked = if ($acct.Length -gt 4) { ('*' * ($acct.Length - 4)) + $acct.Substring($acct.Length - 4) } else { $acct }
    $bin = if ($emv -match 'A000000727\d{4}0006(\d{6})') { $Matches[1] } else { '?' }
    Note "Tài khoản đang khai báo: $name - số TK $masked - mã BIN ngân hàng $bin (bản đầy đủ nằm trong VBA_Settings.reg)"
}

function Invoke-MyExcelReset {
    Step 'BƯỚC 9 - ĐẶT LẠI DỮ LIỆU MYEXCEL CỦA PROFILE NÀY (giống profile mới)'
    $names = @(Get-MyExcelStateKeys)
    if ($names.Count -eq 0) { Skip 'Profile này không có dữ liệu MyExcel để đặt lại'; return $false }
    if (-not $script:Manifest.RegVB) { Warn 'Chưa sao lưu được dữ liệu MyExcel nên không đặt lại.'; return $false }
    Note ('Sẽ xóa: ' + (($names | ForEach-Object { "HKCU\Software\VB and VBA Program Settings\$_" }) -join ' ; '))
    Show-DeclaredBank
    Note 'Sau khi đặt lại phải khai báo lại tài khoản ngân hàng; MyExcel có thể hiện lại màn hình chạy lần đầu.'
    Note 'Nếu MyExcel đòi kích hoạt bản quyền: chạy HoanTac để lấy lại dữ liệu cũ rồi liên hệ MyExcel, đừng xóa gì thêm.'
    if (-not (Ask 'Đặt lại dữ liệu MyExcel ngay bây giờ?')) { Skip 'Không đặt lại dữ liệu MyExcel'; return $false }
    if (-not (Wait-ExcelClosed)) { Warn 'Excel chưa đóng nên chưa đặt lại.'; return $false }
    $root = Open-UserKey 'Software\VB and VBA Program Settings' $true
    $ok = $false
    foreach ($n in $names) {
        try {
            $root.DeleteSubKeyTree($n, $false)
            $script:Manifest.ResetKeys += "Software\VB and VBA Program Settings\$n"
            $ok = $true
            Done "Xóa dữ liệu MyExcel: $n"
        } catch { Warn "Không xóa được $n : $($_.Exception.Message)" }
    }
    $root.Close()
    Save-Manifest
    return $ok
}

# ----------------------------------------------------------------------------
function Show-Verification {
    Step 'KIỂM TRA SAU KHI SỬA'
    $ver = Get-ExcelMainVersion
    $k = Open-UserKey "Software\Microsoft\Office\$ver\Excel\Options"
    $opens = if ($k) { @($k.GetValueNames() | Where-Object { $_ -match '^OPEN\d*$' } | ForEach-Object { "$_ = $($k.GetValue($_))" }) } else { @() }
    Note ("Add-in đang bật (Excel {0}): {1}" -f $ver, $(if ($opens.Count) { $opens -join ' ; ' } else { 'không có' }))
    Note ("Thư mục {0}: {1}" -f $script:Bad, $(if (Test-Path -LiteralPath $script:Bad) { 'VẪN CÒN' } else { 'đã cất' }))
    $vb = Open-UserKey 'Software\VB and VBA Program Settings'
    if ($vb) {
        $stack = New-Object System.Collections.Stack
        $stack.Push($vb)
        while ($stack.Count -gt 0) {
            $key = $stack.Pop()
            if ($key.GetValueNames() -contains 'DuongDanADDin') { Note "DuongDanADDin = $($key.GetValue('DuongDanADDin'))" }
            foreach ($sn in $key.GetSubKeyNames()) { $sk = $key.OpenSubKey($sn); if ($sk) { $stack.Push($sk) } }
        }
    }
    Say ''
    Say ("  Tổng: {0} thay đổi, {1} cảnh báo." -f $script:Changes, $script:Problems) $(if ($script:Problems) { 'Yellow' } else { 'Green' })
}

function Invoke-Fix {
    Say ''
    Say '  SỬA LỖI VIETQR CỦA MYEXCEL CHO PROFILE NÀY' 'Cyan'
    Say "  Tài khoản: $env:USERNAME   Máy: $env:COMPUTERNAME"
    Say "  Script sẽ: sao lưu registry -> cất $($script:Bad) -> nạp MyExcel từ $($script:Good) ->"
    Say '  sửa đường dẫn MyExcel tự lưu -> dọn cache .exd -> bỏ chặn file -> nối lại file Excel cũ.'
    Say '  Sau đó mở Excel để thử; nếu vẫn lỗi mới HỎI để đặt lại dữ liệu MyExcel của profile này.'
    Say '  Không đổi Macro Settings / Protected View / ActiveX (profile chạy được vẫn để mặc định).'
    Say ''
    if (-not (Test-RightUser)) { return }
    if (-not (Ask 'Bắt đầu sửa?')) { Say '  Đã hủy, chưa thay đổi gì.' 'Yellow'; return }
    if (-not (Wait-ExcelClosed)) { Say '  Đã dừng, chưa thay đổi gì.' 'Yellow'; return }
    if (-not (Invoke-Backup)) { Warn 'Sao lưu thất bại nên DỪNG LẠI, chưa sửa gì.'; return }
    $goodOk = Invoke-FolderFix
    if ($goodOk) {
        Invoke-AddinFix
        Invoke-VbaPathFix
    }
    Invoke-CacheCleanup
    if ($goodOk) {
        Invoke-Unblock
        Invoke-WorkbookRelink
    }
    Save-Manifest
    Show-Verification
    if ($goodOk) { Invoke-ExcelTrial }
    Say ''
    Say "  Hoàn tác mọi thay đổi: chạy HoanTac_FixMyExcel.bat trong $($script:BackupDir)" 'White'
}

function Test-QrWorks([string]$Question) {
    if ($script:Auto) {
        $ok = ($env:MYX_QR_OK -ne '0')
        Say ("  {0} (Y/N): {1}  [tự động]" -f $Question, $(if ($ok) { 'Y' } else { 'N' })) 'White'
        return $ok
    }
    return (Ask $Question)
}

function Show-QrSteps([bool]$AfterReset) {
    $sep = (Get-Culture).TextInfo.ListSeparator
    Say '  Làm trong Excel:' 'White'
    Say '   - Có thông báo không tìm thấy file trong MyExcelAddin thì bấm OK.'
    if ($AfterReset) { Say '   - MyExcel hiện màn hình chạy lần đầu thì làm theo như lúc mới cài.' }
    Say '   - Tab Mini Tool > Tạo QR Code: TẮT rồi BẬT lại hàm QR, phải thấy "Bạn đã có thể dùng Hàm QR".'
    if ($AfterReset) { Say '   - Khai báo lại tài khoản: Mini Tool > Tạo QR Code > Tạo QR Code tài khoản ngân hàng > Khai báo.' }
    Say ('   - Thử tạo mã VietQR như mọi khi, hoặc gõ =QrBank_Sotien_Noidung(10000{0}"THU NGHIEM") vào một ô trống.' -f $sep)
}

function Show-StillBroken {
    Step 'VẪN CHƯA ĐƯỢC - VIỆC CẦN LÀM TIẾP'
    $sd = (Get-ItemProperty 'HKCU:\Control Panel\International' -ErrorAction SilentlyContinue).sShortDate
    $cb = (Get-ItemProperty 'HKCU:\Software\Microsoft\Clipboard' -ErrorAction SilentlyContinue).EnableClipboardHistory
    Say '  1) Chạy lại CheckMyExcel_VietQR.bat trong profile này rồi gửi báo cáo mới (xem mục 12: khác biệt với profile Test).'
    Say '  2) Thiết lập theo user còn có thể khác profile mới, thử đổi tạm rồi thử lại QR:'
    Say ("     Short date đang là {0}; Clipboard history (Win+V) đang {1}." -f $(if ($sd) { $sd } else { 'mặc định' }), $(if ($cb -eq 1) { 'bật' } else { 'tắt' }))
}

function Invoke-ExcelTrial {
    Step 'BƯỚC 8 - THỬ LẠI VIETQR TRONG EXCEL'
    if (-not $script:Auto) {
        if (-not (Ask 'Mở Excel để thử ngay bây giờ?')) {
            Show-QrSteps $false
            Say '  Nếu thử sau mà vẫn lỗi: chạy lại FixMyExcel_VietQR.bat, script sẽ hỏi bước đặt lại dữ liệu MyExcel.' 'Yellow'
            return
        }
        Start-Process 'excel.exe' -ErrorAction SilentlyContinue
    }
    Show-QrSteps $false
    if (Test-QrWorks 'Đã tạo được VietQR chưa?') { Say '  VietQR đã chạy được. Xong.' 'Green'; return }
    Say ''
    Say '  Chưa được: bước tiếp theo là đặt lại dữ liệu MyExcel của profile này về giống profile mới (profile Test).' 'Yellow'
    if (-not (Invoke-MyExcelReset)) { Show-StillBroken; return }
    if (-not $script:Auto -and (Ask 'Mở Excel để thử lại?')) { Start-Process 'excel.exe' -ErrorAction SilentlyContinue }
    Show-QrSteps $true
    if (Test-QrWorks 'Đã tạo được VietQR chưa?') { Say '  VietQR đã chạy được sau khi đặt lại dữ liệu MyExcel. Xong.' 'Green'; return }
    Show-StillBroken
}

function Invoke-Undo {
    $dir = Split-Path $env:MYX_SELF -Parent
    $script:BackupDir = $null
    $mf = Join-Path $dir 'manifest.json'
    Say ''
    Say '  HOÀN TÁC SỬA LỖI MYEXCEL' 'Cyan'
    if (-not (Test-Path -LiteralPath $mf)) { Warn "Không thấy manifest.json trong $dir"; return }
    $m = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:RegBase = [string]$m.RegBase
    Say "  Bản sao lưu lúc $($m.Time) của user $($m.User) trên máy $($m.Computer)"
    if ($m.User -ne $env:USERNAME) { Warn "Đang chạy bằng user $env:USERNAME - phải chạy bằng đúng user $($m.User)."; return }
    if (-not (Test-RightUser)) { return }
    if (-not (Ask 'Khôi phục cấu hình Excel, dữ liệu MyExcel, thư mục và các file đã sửa?')) { Say '  Đã hủy.' 'Yellow'; return }
    if (-not (Wait-ExcelClosed)) { return }
    foreach ($nk in @(@($m.NewKeys) + @($m.ResetKeys) | Where-Object { $_ })) {
        # Xóa khóa do script thêm, và dữ liệu MyExcel tạo mới sau khi đặt lại, trước khi nạp bản sao lưu
        try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($script:RegBase + $nk, $false); Done "Xóa khóa tạo sau khi sửa: $nk" }
        catch { Warn "Không xóa được $nk : $($_.Exception.Message)" }
    }
    foreach ($r in @($m.RegExcel)) {
        $k = Open-UserKey "Software\Microsoft\Office\$($r.Ver)\Excel\Options" $true
        if ($k) { foreach ($n in @($k.GetValueNames() | Where-Object { $_ -match '^OPEN\d*$' })) { $k.DeleteValue($n, $false) }; $k.Close() }
        & reg.exe import (Join-Path $dir $r.File) 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Done "Khôi phục cấu hình Excel $($r.Ver)" } else { Warn "Không nhập được $($r.File) (mã lỗi $LASTEXITCODE)" }
    }
    if ($m.RegVB) {
        & reg.exe import (Join-Path $dir $m.RegVB) 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Done 'Khôi phục dữ liệu MyExcel (VB and VBA Program Settings)' } else { Warn "Không nhập được $($m.RegVB)" }
    }
    if ($m.Folder -and (Test-Path -LiteralPath $m.Folder.To) -and -not (Test-Path -LiteralPath $m.Folder.From)) {
        try { Rename-Item -LiteralPath $m.Folder.To -NewName (Split-Path $m.Folder.From -Leaf) -ErrorAction Stop; Done "Đổi tên lại $($m.Folder.To) -> $($m.Folder.From)" }
        catch { Warn "Không đổi tên lại được $($m.Folder.To): $($_.Exception.Message)" }
    }
    foreach ($w in @($m.Workbooks)) {
        try { Copy-Item -LiteralPath $w.Backup -Destination $w.Original -Force -ErrorAction Stop; Done "Khôi phục file $($w.Original)" }
        catch { Warn "Không khôi phục được $($w.Original): $($_.Exception.Message)" }
    }
    Say ("  Xong: {0} mục đã khôi phục, {1} cảnh báo. (File .exd đã xóa và dấu chặn file không cần khôi phục.)" -f $script:Changes, $script:Problems) 'Green'
}

# ----------------------------------------------------------------------------
try {
    if ($script:UndoMode) { Invoke-Undo } else { Invoke-Fix }
} catch {
    Warn "Lỗi không mong muốn: $($_.Exception.Message)"
} finally {
    $logDir = if ($script:BackupDir) { $script:BackupDir } elseif ($script:UndoMode) { Split-Path $env:MYX_SELF -Parent } else { $null }
    if ($logDir) {
        $name = if ($script:UndoMode) { "NhatKy_HoanTac_$($script:Stamp).txt" } else { 'NhatKy_Sua.txt' }
        try { [IO.File]::WriteAllLines((Join-Path $logDir $name), $script:Log.ToArray(), (New-Object Text.UTF8Encoding $true)); Say "  Nhật ký: $(Join-Path $logDir $name)" 'DarkGray' } catch {}
    }
}
