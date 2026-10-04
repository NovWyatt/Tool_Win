
# ----------------------------------------------------------------------------
function Invoke-VbaPathFix {
    Step 'BƯỚC 5 - SỬA ĐƯỜNG DẪN MYEXCEL TỰ GHI NHỚ (DuongDanADDin...)'
    $names = @(Get-MyExcelStateKeys)
    if ($names.Count -eq 0) { Skip 'Profile này chưa có dữ liệu MyExcel'; return }
    $others = @(Get-OtherInstalls | ForEach-Object { $_.Path } | Sort-Object Length -Descending)
    if ($others.Count -eq 0) { Skip 'Không có thư mục MyExcel nào khác để trỏ lại'; return }
    $good = $script:Target
    $count = 0
    foreach ($name in $names) {
        $root = Open-UserKey "Software\VB and VBA Program Settings\$name" $true
        if (-not $root) { continue }
        $stack = New-Object System.Collections.Stack
        $stack.Push(@($root, $name))
        while ($stack.Count -gt 0) {
            $item = $stack.Pop(); $key = $item[0]; $path = $item[1]
            foreach ($vn in $key.GetValueNames()) {
                $kind = $key.GetValueKind($vn)
                if ($kind -ne [Microsoft.Win32.RegistryValueKind]::String -and $kind -ne [Microsoft.Win32.RegistryValueKind]::ExpandString) { continue }
                $val = [string]$key.GetValue($vn, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if (Test-UnderPath $val $good) { continue }   # đã trỏ đúng bộ chuẩn
                $newVal = $val
                foreach ($o in $others) {
                    $rx = '(?i)' + [regex]::Escape($o) + '(?=[\\/]|$)'
                    $newVal = [regex]::Replace($newVal, $rx, [Text.RegularExpressions.MatchEvaluator] { param($m) $good })
                }
                if ($newVal -ceq $val) { continue }
                $key.SetValue($vn, $newVal, $kind)
                $count++
                Done ('{0}\{1}: {2} -> {3}' -f $path, $vn, $val, $newVal)
            }
            foreach ($sn in $key.GetSubKeyNames()) {
                $sk = $key.OpenSubKey($sn, $true)
                if ($sk) { $stack.Push(@($sk, "$path\$sn")) }
            }
            $key.Close()
        }
    }
    if ($count -eq 0) { Skip 'Dữ liệu MyExcel không còn trỏ tới thư mục MyExcel khác' }
}

function Invoke-CacheCleanup {
    Step 'BƯỚC 6 - DỌN CACHE ACTIVEX (.exd) VÀ FILE KHÓA CŨ'
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
    foreach ($f in (Get-ChildItem -LiteralPath $script:Target -Recurse -Depth 1 -Filter '~$*' -File -Force -ErrorAction SilentlyContinue)) {
        if ($f.Length -lt 1KB) {
            try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; Done "Xóa file khóa cũ $($f.FullName)" }
            catch { Warn "Không xóa được file khóa $($f.FullName)" }
        }
    }
}

function Invoke-Unblock {
    Step "BƯỚC 7 - BỎ CHẶN (Unblock) CÁC FILE TRONG $($script:Target)"
    $files = @(Get-ChildItem -LiteralPath $script:Target -Recurse -File -Force -ErrorAction SilentlyContinue)
    $done = 0; $fail = 0
    foreach ($f in $files) {
        if (-not (Get-Item -LiteralPath $f.FullName -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue)) { continue }
        try { Unblock-File -LiteralPath $f.FullName -ErrorAction Stop; $done++ } catch { $fail++ }
    }
    if ($done -gt 0) { Done "Bỏ chặn $done / $($files.Count) file" } else { Skip "Không có file nào bị chặn trong $($files.Count) file" }
    if ($fail -gt 0) { Warn "$fail file không bỏ chặn được (thiếu quyền ghi?)" }
}
