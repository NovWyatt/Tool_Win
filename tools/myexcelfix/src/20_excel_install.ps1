
# ----------------------------------------------------------------------------
Section '3. MICROSOFT EXCEL ĐÃ CÀI'
function Get-PeBitness([string]$File) {
    try {
        $fs = [IO.File]::Open($File, 'Open', 'Read', 'ReadWrite')
        $br = New-Object IO.BinaryReader($fs)
        $fs.Position = 0x3C; $pe = $br.ReadInt32()
        $fs.Position = $pe + 4; $m = $br.ReadUInt16()
        $fs.Close()
        switch ($m) { 0x8664 { return '64-bit' } 0x14c { return '32-bit' } 0xAA64 { return 'ARM64' } }
    } catch {}
    return 'không rõ'
}
try {
    $excel = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe' ''
    if (-not $excel -or -not (Test-Path -LiteralPath $excel)) {
        $excel = @(
            "$env:ProgramFiles\Microsoft Office\root\Office16\EXCEL.EXE",
            "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\EXCEL.EXE",
            "$env:ProgramFiles\Microsoft Office\Office16\EXCEL.EXE",
            "${env:ProgramFiles(x86)}\Microsoft Office\Office16\EXCEL.EXE",
            "$env:ProgramFiles\Microsoft Office\Office15\EXCEL.EXE",
            "${env:ProgramFiles(x86)}\Microsoft Office\Office15\EXCEL.EXE"
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    }
    if ($excel) {
        $script:ExcelDir = Split-Path $excel -Parent
        $bit = Get-PeBitness $excel
        $script:OfficeIs32 = ($bit -eq '32-bit')
        Info 'EXCEL.EXE' $excel
        Info 'Phiên bản / Kiến trúc' ("{0} / {1}" -f (Get-Item -LiteralPath $excel).VersionInfo.ProductVersion, $bit)
        Snap 'Office.ExcelVersion' (Get-Item -LiteralPath $excel).VersionInfo.ProductVersion
        Snap 'Office.Bitness' $bit
    } else {
        Add-Finding 'KHONG_CO_EXCEL' 'LOI' 'Không tìm thấy EXCEL.EXE' 'Kiểm tra lại bộ Office trên máy.'
    }
    $c2r = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    if (Test-Path $c2r) {
        Info 'Kiểu cài' 'Click-to-Run'
        Info 'Sản phẩm' (Get-RegValue $c2r 'ProductReleaseIds')
        Info 'Bản build Office' (Get-RegValue $c2r 'VersionToReport')
        $cdn = [string](Get-RegValue $c2r 'CDNBaseUrl')
        $chan = switch -Regex ($cdn) {
            '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' { 'Current Channel' }
            '55336b82-a18d-4dd6-b5f6-9e5095c314a6' { 'Monthly Enterprise' }
            '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' { 'Semi-Annual Enterprise' }
            default { $cdn }
        }
        Info 'Kênh cập nhật' $chan
    } else {
        foreach ($v in '16.0', '15.0', '14.0') {
            foreach ($base in 'HKLM:\SOFTWARE\Microsoft\Office', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office') {
                $ir = Get-RegValue "$base\$v\Common\InstallRoot" 'Path'
                if ($ir) { Info "Kiểu cài MSI (Office $v)" $ir }
            }
        }
    }
    $uninst = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
    $apps = Get-ItemProperty $uninst -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
    $offs = $apps | Where-Object { $_.DisplayName -match '(?i)^Microsoft (Office|365|Excel)' -and $_.DisplayName -notmatch '(?i)update|language|proofing|mui|tools|shared|click-to-run|\(KB' } |
        Sort-Object DisplayName -Unique
    foreach ($a in $offs) { Info 'Sản phẩm Office trong Programs' ("{0}  {1}" -f $a.DisplayName, $a.DisplayVersion) }
    if (@($offs).Count -gt 1) {
        Add-Finding 'NHIEU_BO_OFFICE' 'CANHBAO' 'Có nhiều bộ Office cùng cài trên máy' 'Nhiều phiên bản Office song song dễ làm add-in/đăng ký COM bị lẫn. Nên gỡ bộ không dùng.'
    }
    if (($apps | Where-Object { $_.DisplayName -match 'Office 2016|Excel 2016' }) -and -not (Test-Path $c2r)) {
        if (-not ($apps | Where-Object { $_.DisplayName -match 'KB4484305' })) {
            Add-Finding 'THIEU_KB4484305' 'CANHBAO' 'Office 2016 bản MSI chưa thấy bản vá KB4484305 (lỗi khởi động MyExcel do Windows Update)' 'Cài bản vá theo https://myexcel.vn/loi-khoi-dong-myexcel-do-window/ rồi khởi động lại máy.'
        }
    }
} catch { Note "Lỗi khi đọc thông tin Office: $($_.Exception.Message)" }

try {
    $xl = @(Get-CimInstance Win32_Process -Filter "Name='EXCEL.EXE'" -ErrorAction SilentlyContinue)
    Info 'Số tiến trình EXCEL.EXE đang chạy' $xl.Count
    foreach ($p in $xl) {
        Note ("PID {0} session {1}: {2}" -f $p.ProcessId, $p.SessionId, $p.CommandLine)
        if ($p.CommandLine -match '(?i)/safe') {
            Add-Finding 'EXCEL_SAFE_MODE' 'LOI' "Excel (PID $($p.ProcessId)) đang chạy ở chế độ /safe => add-in không được nạp" 'Đóng Excel, mở lại bình thường (không dùng /safe, không giữ Ctrl khi mở).'
        }
        if ($p.CommandLine -match '(?i)/automation|-embedding') {
            Add-Finding 'EXCEL_CHAY_AN' 'CANHBAO' "Có Excel chạy ẩn (PID $($p.ProcessId), /automation hoặc -Embedding)" 'Đóng hết Excel, mở Task Manager kết thúc mọi EXCEL.EXE còn sót rồi mới thử lại.'
        }
    }
    if ($xl.Count -gt 0) { Note 'Nên ĐÓNG Excel khi chạy script để kết quả chính xác nhất.' }
} catch {}

# Thu thập danh sách add-in Excel đăng ký trong HKCU (dùng cho mục 4 và 5)
function ConvertFrom-OpenValue([string]$Raw, [string]$LibDir) {
    # Giá trị OPEN dạng: /R "C:\MyExcel\MyExcel.xlam"  |  "D:\a b\x.xlam"  |  x.xlam (trong AddIns)  |  /A "ProgID"
    $isAuto = $Raw -match '^\s*/A\s'
    $p = ($Raw -replace '^\s*(/[A-Za-z]\s+)+', '').Trim().Trim('"')
    if (-not $isAuto -and $p -notmatch '\\') {
        $cand = @((Join-Path $env:APPDATA "Microsoft\AddIns\$p"))
        if ($LibDir) { $cand += (Join-Path $LibDir $p) }
        $hit = $cand | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        $p = if ($hit) { $hit } else { $cand[0] }
    }
    return [pscustomobject]@{ Path = $p; Automation = $isAuto }
}
try {
    $script:OfficeVers = @(Get-ChildItem 'HKCU:\Software\Microsoft\Office' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^\d+\.0$' -and (Test-Path (Join-Path $_.PSPath 'Excel')) } |
        ForEach-Object { $_.PSChildName })
    $libDir = if ($script:ExcelDir) { Join-Path $script:ExcelDir 'Library' } else { $null }
    foreach ($ver in $script:OfficeVers) {
        foreach ($v in (Get-RegValues "HKCU:\Software\Microsoft\Office\$ver\Excel\Options")) {
            if ($v.Name -notmatch '^OPEN\d*$') { continue }
            $parsed = ConvertFrom-OpenValue ([string]$v.Value) $libDir
            [void]$script:AddinEntries.Add([pscustomobject]@{ Ver = $ver; Source = 'OPEN'; Name = $v.Name; Raw = [string]$v.Value; Path = $parsed.Path; Automation = $parsed.Automation })
        }
        foreach ($v in (Get-RegValues "HKCU:\Software\Microsoft\Office\$ver\Excel\Add-in Manager")) {
            [void]$script:AddinEntries.Add([pscustomobject]@{ Ver = $ver; Source = 'Add-in Manager'; Name = $v.Name; Raw = $v.Name; Path = $v.Name; Automation = $false })
        }
    }
} catch { Note "Lỗi khi đọc danh sách add-in: $($_.Exception.Message)" }
