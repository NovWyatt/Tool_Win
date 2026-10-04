
# ----------------------------------------------------------------------------
function Invoke-FolderFix {
    Step 'BƯỚC 3 - CẤT BỘ CÀI MYEXCEL THỪA (đổi tên, không xóa)'
    $extra = @(Get-OtherInstalls | Where-Object { $_.Scanned -and $_.IsInstall })
    if ($extra.Count -eq 0) { Skip 'Không có bộ cài MyExcel thừa ở gốc ổ đĩa'; return }
    $others = @(Get-OtherProfiles)
    if ($others.Count -gt 0) {
        Note ('Máy còn các profile: {0}. Profile nào đang dùng bộ bị cất thì chạy file sửa này ở profile đó để trỏ về bộ chuẩn.' -f ($others -join ', '))
    }
    foreach ($i in $extra) {
        if (-not (Ask "Đổi tên $($i.Path) thành $($i.Path)_cu?")) { Skip "Giữ nguyên $($i.Path)"; continue }
        $to = "$($i.Path)_cu"
        if (Test-Path -LiteralPath $to) { $to = "$($i.Path)_cu_$($script:Stamp)" }
        try {
            Rename-Item -LiteralPath $i.Path -NewName (Split-Path $to -Leaf) -ErrorAction Stop
            $script:Manifest.Folders += [ordered]@{ From = $i.Path; To = $to }
            Save-Manifest
            Done "Đổi tên $($i.Path) -> $to"
        } catch {
            Warn "Không đổi tên được $($i.Path): $($_.Exception.Message)"
            Note 'Đóng mọi cửa sổ/ứng dụng đang mở file trong thư mục đó. Các bước còn lại vẫn được thực hiện.'
        }
    }
}

function Invoke-AddinFix {
    Step 'BƯỚC 4 - NẠP MYEXCEL TỪ BỘ CHUẨN (Excel Add-ins, Trusted Locations, Disabled Items)'
    $mainVer = Get-ExcelMainVersion
    $mainPath = Join-Path $script:Target 'MyExcel.xlam'
    $vers = @(Get-ExcelVersions)
    if ($vers -notcontains $mainVer) { $vers += $mainVer }
    foreach ($ver in $vers) {
        $k = Open-UserKey "Software\Microsoft\Office\$ver\Excel\Options" $true
        if (-not $k -and $ver -eq $mainVer) {
            if (-not (Open-UserKey "Software\Microsoft\Office\$ver\Excel")) {
                $script:Manifest.NewKeys += "Software\Microsoft\Office\$ver\Excel"   # profile chưa từng mở Excel
                Save-Manifest
            }
            $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:RegBase + "Software\Microsoft\Office\$ver\Excel\Options")
        }
        if (-not $k) { continue }
        $entries = @($k.GetValueNames() | Where-Object { $_ -match '^OPEN(\d*)$' } | ForEach-Object {
            $idx = if ($_ -eq 'OPEN') { 0 } else { [int]$_.Substring(4) }
            [pscustomobject]@{ Name = $_; Index = $idx; Value = [string]$k.GetValue($_) }
        } | Sort-Object Index)
        $new = New-Object System.Collections.Generic.List[string]
        $seen = New-Object System.Collections.Generic.HashSet[string]
        $hasMain = $false
        foreach ($e in $entries) {
            $p = Get-OpenPath $e.Value
            $res = Resolve-AddinPath $p
            if ($null -eq $res) { $val = $e.Value; $path = $p }
            elseif ($res -eq '') { continue }
            else { $val = (Get-OpenFlags $e.Value) + '"' + $res + '"'; $path = $res }
            if ($path -and -not $seen.Add($path.ToLowerInvariant())) { continue }   # bỏ mục trùng
            if (Test-SamePath $path $mainPath) { $hasMain = $true }
            $new.Add($val)
        }
        if (-not $hasMain -and $ver -eq $mainVer) { $new.Insert(0, '"' + $mainPath + '"') }
        $old = @($entries | ForEach-Object { $_.Value })
        if (($old -join '|') -ceq ($new -join '|')) {
            Skip ('Excel {0} - danh sách add-in đã đúng: {1}' -f $ver, $(if ($old.Count) { $old -join ' ; ' } else { 'không có' }))
        } else {
            foreach ($e in $entries) { $k.DeleteValue($e.Name, $false) }
            for ($i = 0; $i -lt $new.Count; $i++) {
                $n = if ($i -eq 0) { 'OPEN' } else { "OPEN$i" }
                $k.SetValue($n, $new[$i], [Microsoft.Win32.RegistryValueKind]::String)
            }
            Done ('Excel {0} - add-in đang bật: {1}   (trước đây: {2})' -f $ver, ($new -join ' ; '), $(if ($old.Count) { $old -join ' ; ' } else { 'không có' }))
        }
        $k.Close()

        $am = Open-UserKey "Software\Microsoft\Office\$ver\Excel\Add-in Manager" $true
        if ($am) {
            foreach ($n in $am.GetValueNames()) {
                if (-not $n) { continue }
                $res = Resolve-AddinPath $n
                if ($null -ne $res -and -not (Test-SamePath $res $n)) {
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
