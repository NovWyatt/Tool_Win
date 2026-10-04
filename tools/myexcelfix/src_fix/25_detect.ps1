
# ----------------------------------------------------------------------------
function Get-OtherProfiles {
    $names = @()
    foreach ($p in (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue)) {
        if ($p.PSChildName -notmatch '^S-1-5-21-') { continue }
        $path = [Environment]::ExpandEnvironmentVariables([string]$p.GetValue('ProfileImagePath'))
        if ($path -and -not (Test-SamePath $path $env:USERPROFILE)) { $names += (Split-Path $path -Leaf) }
    }
    return $names
}

function Find-MyExcelInstalls {
    # Mọi thư mục có MyExcel.xlam: X:\MyExcel* ở gốc ổ đĩa + nơi Excel/MyExcel của profile này đang trỏ tới
    $cands = New-Object System.Collections.Generic.List[object]
    $openMain = @()
    $scan = if ($env:MYX_CANDIDATES) { @($env:MYX_CANDIDATES -split ';') } else {   # MYX_CANDIDATES chỉ dùng khi test
        @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | ForEach-Object {
            Get-ChildItem -LiteralPath "$($_.DeviceID)\" -Directory -Filter 'MyExcel*' -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
        })
    }
    foreach ($d in $scan) {
        if ($d -and $d.TrimEnd('\') -notmatch '(?i)_cu(_\d{8}_\d{6})?$') { $cands.Add(@($d, $true)) }   # bỏ qua thư mục đã cất (_cu)
    }
    foreach ($ver in (Get-ExcelVersions)) {
        $k = Open-UserKey "Software\Microsoft\Office\$ver\Excel\Options"
        if ($k) {
            foreach ($n in @($k.GetValueNames() | Where-Object { $_ -match '^OPEN\d*$' })) {
                $p = Get-OpenPath ([string]$k.GetValue($n))
                if ($p -and (Split-Path $p -Leaf) -ieq 'MyExcel.xlam') { $openMain += $p; $cands.Add(@((Split-Path $p -Parent), $false)) }
            }
            $k.Close()
        }
        $am = Open-UserKey "Software\Microsoft\Office\$ver\Excel\Add-in Manager"
        if ($am) {
            foreach ($n in $am.GetValueNames()) { if ($n -and (Split-Path $n -Leaf) -ieq 'MyExcel.xlam') { $cands.Add(@((Split-Path $n -Parent), $false)) } }
            $am.Close()
        }
    }
    foreach ($s in (Get-MyExcelStateKeys)) {
        $stack = New-Object System.Collections.Stack
        $root = Open-UserKey "Software\VB and VBA Program Settings\$s"
        if ($root) { $stack.Push($root) }
        while ($stack.Count -gt 0) {
            $key = $stack.Pop()
            $dd = ([string]$key.GetValue('DuongDanADDin')).TrimEnd('\')
            if ($dd) { $cands.Add(@($dd, $false)); $cands.Add(@((Split-Path $dd -Parent), $false)) }
            foreach ($sn in $key.GetSubKeyNames()) { $sk = $key.OpenSubKey($sn); if ($sk) { $stack.Push($sk) } }
            $key.Close()
        }
    }
    $found = [ordered]@{}
    foreach ($c in $cands) {
        $dir = ([string]$c[0]).TrimEnd('\')
        if (-not $dir -or -not (Test-Path -LiteralPath (Join-Path $dir 'MyExcel.xlam') -PathType Leaf)) { continue }
        $key = $dir.ToLowerInvariant()
        if ($found.Contains($key)) { if ($c[1]) { $found[$key].Scanned = $true }; continue }
        $mini = Join-Path $dir 'MiniTool'
        $found[$key] = [pscustomobject]@{
            Path      = $dir
            Scanned   = [bool]$c[1]
            Date      = (Get-Item -LiteralPath (Join-Path $dir 'MyExcel.xlam') -Force).LastWriteTime
            IsInstall = (Test-Path -LiteralPath $mini -PathType Container)
            HasQr     = [bool](Get-ChildItem -LiteralPath $mini -Filter '*qr*.xlam' -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
            Loaded    = [bool]($openMain | Where-Object { Test-SamePath (Split-Path $_ -Parent) $dir })
        }
    }
    return @($found.Values)
}

function Select-MyExcelTarget {
    Step 'BƯỚC 1 - TÌM BỘ MYEXCEL CHUẨN TRÊN MÁY'
    $script:Installs = @(Find-MyExcelInstalls)
    if ($script:Installs.Count -eq 0) {
        Warn "Không thấy MyExcel.xlam ở $($script:Preferred) hay nơi nào khác. Tải bộ cài ở https://myexcel.vn/download/, giải nén vào $($script:Preferred) rồi chạy lại."
        return $false
    }
    foreach ($i in $script:Installs) {
        $tags = @("MyExcel.xlam ngày $($i.Date.ToString('dd/MM/yyyy'))")
        $tags += $(if ($i.HasQr) { 'có file QR' } elseif ($i.IsInstall) { 'THIẾU file QR trong MiniTool' } elseif ($i.Scanned) { 'THIẾU thư mục MiniTool' } else { 'bản sao lẻ, không có MiniTool' })
        if ($i.Loaded) { $tags += 'profile này đang nạp' }
        Note ('{0}  ({1})' -f $i.Path, ($tags -join ', '))
    }
    $valid = @($script:Installs | Where-Object HasQr)
    if ($valid.Count -eq 0) {
        Warn "Không bộ nào có đủ file QR (MiniTool\QRCodeLib.xlam...). Cài lại MyExcel vào $($script:Preferred) theo https://myexcel.vn/download/ rồi chạy lại."
        return $false
    }
    # Ưu tiên: đúng thư mục khuyên dùng > bộ profile đang nạp > bộ mới nhất
    $pick = @(@($valid | Where-Object { Test-SamePath $_.Path $script:Preferred }) + @($valid | Where-Object Loaded) + @($valid | Sort-Object Date -Descending))[0]
    if ($valid.Count -gt 1) {
        $opts = @($valid | ForEach-Object { '{0}  (ngày {1}){2}' -f $_.Path, $_.Date.ToString('dd/MM/yyyy'), $(if ($_ -eq $pick) { '  <- khuyên dùng' } else { '' }) })
        $pick = $valid[(Choose 'Chọn bộ MyExcel chuẩn cho profile này' $opts ([Array]::IndexOf($valid, $pick) + 1)) - 1]
    }
    $newest = @($valid | Sort-Object Date -Descending)[0]
    if (($newest.Date - $pick.Date).TotalDays -gt 7) {
        Warn ('Bộ đã chọn ({0}, ngày {1}) cũ hơn bộ {2} (ngày {3}) - nên cài bản mới vào {0}.' -f $pick.Path, $pick.Date.ToString('dd/MM/yyyy'), $newest.Path, $newest.Date.ToString('dd/MM/yyyy'))
    }
    if (-not (Test-SamePath $pick.Path $script:Preferred)) {
        Note "MyExcel khuyên cài đúng $($script:Preferred), nếu không file tạo từ máy khác dễ lỗi #NAME."
    }
    $script:Target = $pick.Path
    $script:Manifest.Target = $pick.Path
    $script:AddinMap = @{}
    $files = @(Get-ChildItem -LiteralPath $pick.Path -Filter '*.xlam' -File -Force -ErrorAction SilentlyContinue) +
             @(Get-ChildItem -LiteralPath (Join-Path $pick.Path 'MiniTool') -Filter '*.xlam' -File -Force -ErrorAction SilentlyContinue)
    foreach ($f in $files) { $l = $f.Name.ToLowerInvariant(); if (-not $script:AddinMap.ContainsKey($l)) { $script:AddinMap[$l] = $f.FullName } }
    Say "  Bộ MyExcel chuẩn: $($pick.Path)" 'Green'
    return $true
}

function Get-OtherInstalls { return @($script:Installs | Where-Object { -not (Test-SamePath $_.Path $script:Target) }) }

function Resolve-AddinPath([string]$Path) {
    # Đường dẫn mới trong bộ chuẩn; '' = nên bỏ; $null = giữ nguyên
    if (-not $Path -or -not $script:Target) { return $null }
    $leaf = (Split-Path $Path -Leaf).ToLowerInvariant()
    foreach ($i in (Get-OtherInstalls)) {
        if (-not $i.IsInstall -or -not (Test-UnderPath $Path $i.Path)) { continue }
        $alt = Join-Path $script:Target ($Path.Substring($i.Path.Length).TrimStart('\', '/'))
        if (Test-Path -LiteralPath $alt) { return $alt }
        if ($script:AddinMap.ContainsKey($leaf)) { return $script:AddinMap[$leaf] }
        return ''
    }
    # Bản sao lẻ / file từ máy khác: chỉ trỏ lại add-in của MyExcel (MyExcel*.xlam, *QR*.xlam), không đụng add-in khác
    if ($leaf -match '^myexcel.*\.xlam$|qr.*\.xlam$' -and $script:AddinMap.ContainsKey($leaf) -and -not (Test-UnderPath $Path $script:Target)) {
        return $script:AddinMap[$leaf]
    }
    return $null
}
