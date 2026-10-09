
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

function Resolve-LinkTarget([string]$Target, [string]$WbDir) {
    # Target của liên kết ngoài (file:///C:\..., /Thu/Muc/..., ../../...) -> đường dẫn tuyệt đối
    $t = $Target -replace '^(?i)file:/*', ''
    try { $t = [Uri]::UnescapeDataString($t) } catch {}
    $t = $t -replace '/', '\'
    $abs = if ($t -match '^[A-Za-z]:\\' -or $t -match '^\\\\') { $t }
           elseif ($t -match '^\\') { try { (Split-Path $WbDir -Qualifier -ErrorAction Stop) + $t } catch { $t } }
           else { Join-Path $WbDir $t }
    try { return [IO.Path]::GetFullPath($abs) } catch { return $abs }
}

function Get-NewLinkTarget([string]$Target, [string]$WbDir) {
    # '' = giữ nguyên; ngược lại là Target mới trỏ tới bộ chuẩn
    $abs = Resolve-LinkTarget $Target $WbDir
    $res = Resolve-AddinPath $abs
    if (-not $res -or (Test-SamePath $res $abs)) { return '' }
    return 'file:///' + $res
}

function Get-LinkChanges([string]$Path) {
    $hits = @()
    $wbDir = Split-Path $Path -Parent
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($Path)
        try {
            foreach ($e in $zip.Entries) {
                if ($e.FullName -notmatch '^xl/externalLinks/_rels/[^/]+\.rels$') { continue }
                $sr = New-Object IO.StreamReader($e.Open())
                $txt = $sr.ReadToEnd(); $sr.Close()
                foreach ($m in [regex]::Matches($txt, 'Target="([^"]*)"')) {
                    if (Get-NewLinkTarget ([Net.WebUtility]::HtmlDecode($m.Groups[1].Value)) $wbDir) { $hits += $e.FullName; break }
                }
            }
        } finally { $zip.Dispose() }
    } catch {}
    return ,$hits
}

function Update-LinkedEntries([string]$Path, [string[]]$Entries) {
    $wbDir = Split-Path $Path -Parent
    $utf8 = New-Object Text.UTF8Encoding $false
    $evaluator = [Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $new = Get-NewLinkTarget ([Net.WebUtility]::HtmlDecode($m.Groups[1].Value)) $wbDir
        if ($new) { 'Target="' + [Security.SecurityElement]::Escape($new) + '"' } else { $m.Value }
    }
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
                    $bytes = $utf8.GetBytes([regex]::Replace($txt, 'Target="([^"]*)"', $evaluator))
                    $s.SetLength(0); $s.Position = 0
                    $s.Write($bytes, 0, $bytes.Length)
                } finally { $s.Dispose() }
            }
        } finally { $za.Dispose() }
    } finally { $fs.Dispose() }
}

function Invoke-WorkbookRelink {
    Step 'BƯỚC 8 - NỐI LẠI FILE EXCEL CÒN LIÊN KẾT TỚI MYEXCEL Ở CHỖ KHÁC'
    try { Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem -ErrorAction Stop }
    catch { Warn "Không nạp được thư viện ZIP: $($_.Exception.Message)"; return }
    $roots = @(Get-ScanRoots)
    Note ('Đang quét: {0}' -f ($roots -join ' ; '))
    # .xls dạng cũ chỉ tìm được theo tên thư mục cài khác (BIFF lưu dấu \ thành ký tự 0x03)
    $needles = @(Get-OtherInstalls | Where-Object IsInstall | ForEach-Object { $l = Split-Path $_.Path -Leaf; "$l\"; "$l/"; "$l$([char]3)" })
    $ooxml = @(); $binary = @(); $cloud = 0
    foreach ($r in $roots) {
        $files = Get-ChildItem -LiteralPath $r -Recurse -Depth 5 -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(xlsx|xlsm|xltx|xltm|xlsb|xls)$' -and $_.Name -notlike '~$*' -and $_.Length -lt 60MB }
        foreach ($f in $files) {
            if (([int]$f.Attributes -band 0x401000) -ne 0) { $cloud++; continue }   # OneDrive "chỉ có trên mạng": đọc vào sẽ tải cả file về
            if ($f.Extension -ieq '.xls') {
                if ($needles.Count -eq 0 -or $f.Length -ge 15MB) { continue }
                try {
                    $bytes = [IO.File]::ReadAllBytes($f.FullName)
                    $a = [Text.Encoding]::ASCII.GetString($bytes); $u = [Text.Encoding]::Unicode.GetString($bytes)
                    if (@($needles | Where-Object { $a.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or $u.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0) { $binary += $f }
                } catch {}
            } else {
                $entries = Get-LinkChanges $f.FullName
                if ($entries.Count -gt 0) { $ooxml += [pscustomobject]@{ File = $f; Entries = $entries } }
            }
        }
    }
    if ($cloud -gt 0) { Note "Bỏ qua $cloud file OneDrive chưa tải về máy. File nào báo lỗi liên kết thì sửa bằng Data > Edit Links > Change Source." }
    if ($ooxml.Count -eq 0 -and $binary.Count -eq 0) { Skip 'Không có file Excel nào liên kết tới MyExcel ở chỗ khác'; return }
    foreach ($o in $ooxml) { Note "Liên kết cũ: $($o.File.FullName)" }
    if ($ooxml.Count -gt 0 -and (Ask "Sửa liên kết trong $($ooxml.Count) file trên (mỗi file được sao lưu trước)?")) {
        $wbDir = Join-Path $script:BackupDir 'Workbooks'
        New-Item -ItemType Directory -Path $wbDir -Force | Out-Null
        $i = 0
        foreach ($o in $ooxml) {
            $i++
            $leaf = '{0:000}_{1}' -f $i, $o.File.Name
            $dest = Join-Path $wbDir $leaf
            try {
                Copy-Item -LiteralPath $o.File.FullName -Destination $dest -Force -ErrorAction Stop
                $hashBackup = Get-Sha256 $dest
                Update-LinkedEntries $o.File.FullName $o.Entries
                # Backup tương đối với thư mục sao lưu (chép thư mục đi chỗ khác vẫn hoàn tác được);
                # HashAfter để hoàn tác biết file có bị sửa tiếp sau lần sửa này không
                $script:Manifest.Workbooks += [ordered]@{ Original = $o.File.FullName; Backup = "Workbooks\$leaf"; HashBackup = $hashBackup; HashAfter = (Get-Sha256 $o.File.FullName) }
                Save-Manifest
                Done "Nối lại liên kết: $($o.File.FullName)"
            } catch {
                if (Test-Path -LiteralPath $dest) { Copy-Item -LiteralPath $dest -Destination $o.File.FullName -Force -ErrorAction SilentlyContinue }
                Warn "Không sửa được $($o.File.FullName) (file đang mở?): $($_.Exception.Message)"
            }
        }
    }
    if ($binary.Count -gt 0) {
        Warn ('{0} file .xls dạng cũ còn liên kết tới bộ MyExcel khác, cần sửa tay: mở file > Data > Edit Links > Change Source > chọn {1}' -f $binary.Count, (Join-Path $script:Target 'MyExcel.xlam'))
        foreach ($b in ($binary | Select-Object -First 30)) { Note $b.FullName }
    }
}
