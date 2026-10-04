# Trạm Tool - chạy action của công cụ trong cửa sổ riêng (nâng quyền Admin khi cần)

Add-Type -Namespace TramTool -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindowAsync(System.IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, System.UIntPtr dwExtraInfo);
'@ -ErrorAction SilentlyContinue

function Invoke-BringToFront {
    # Windows chặn tiến trình nền giành focus; nhấn-nhả phím Alt ảo là cách thông dụng để được phép.
    param([System.Diagnostics.Process]$Process, [int]$TimeoutMs = 2500)
    if (-not $Process) { return }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        try { $Process.Refresh(); if ($Process.HasExited) { return }; $h = $Process.MainWindowHandle } catch { return }
        if ($h -ne [IntPtr]::Zero) {
            [TramTool.Win32]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
            [TramTool.Win32]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
            [void][TramTool.Win32]::ShowWindowAsync($h, 9)
            [void][TramTool.Win32]::SetForegroundWindow($h)
            return
        }
        Start-Sleep -Milliseconds 100
    }
}

function Assert-SafeArgument {
    # Mọi tham số đều được bọc trong "..." khi gọi cmd; chỉ cần chặn ký tự phá được cặp ngoặc kép hoặc bị cmd mở rộng.
    param([string]$Value, [string]$Label = 'Tham số')
    if ($Value -match '[%"\r\n]') { throw "$Label chứa ký tự % hoặc dấu ngoặc kép nên không truyền an toàn qua cmd được. Bỏ ký tự đó (tên file, thư mục thì đổi tên) rồi thử lại." }
}

function Resolve-ActionArguments {
    # Biến giá trị người dùng nhập (theo id từng tham số trong tool.json) thành danh sách tham số dòng lệnh.
    # Trình duyệt chỉ gửi giá trị; flag, thứ tự và kiểu đều lấy từ tool.json nên không chèn thêm lệnh được.
    # Kết quả: mảng @{ Value; IsFlag } để khi gọi .ps1 flag được truyền không ngoặc (thành tham số switch),
    # còn giá trị luôn nằm trong ngoặc (giá trị bắt đầu bằng '-' không biến thành tham số).
    param([Parameter(Mandatory)]$Action, $Values)
    $argv = New-Object System.Collections.ArrayList
    foreach ($fixed in @($Action.fixedArgs)) {
        if (-not $fixed) { continue }
        Assert-SafeArgument -Value $fixed
        [void]$argv.Add([pscustomobject]@{ Value = [string]$fixed; IsFlag = ($fixed -match '^--?[A-Za-z][A-Za-z0-9_-]*$') })
    }
    foreach ($spec in @($Action.args)) {
        $label = "'$($spec.label)'"
        $raw = Get-Prop $Values $spec.id $null
        if ($spec.type -eq 'bool') {
            if ($raw -eq $true -or [string]$raw -eq 'true') { [void]$argv.Add([pscustomobject]@{ Value = $spec.flag; IsFlag = $true }) }
            continue
        }
        $items = @(@($raw) | Where-Object { $null -ne $_ -and ([string]$_).Trim() -ne '' } | ForEach-Object { ([string]$_).Trim() })
        if (-not $items.Count) {
            if ($spec.required) { throw "Chưa nhập $label." }
            continue
        }
        if ($items.Count -gt 1 -and -not ($spec.multiple -and $spec.type -in 'file', 'folder')) { throw "$label chỉ nhận một giá trị." }
        $clean = @()
        foreach ($v in $items) {
            Assert-SafeArgument -Value $v -Label $label
            switch ($spec.type) {
                'file' {
                    if (-not [IO.Path]::IsPathRooted($v) -or -not (Test-Path -LiteralPath $v -PathType Leaf)) { throw "Không tìm thấy file: $v" }
                    $v = [IO.Path]::GetFullPath($v)
                }
                'folder' {
                    if (-not [IO.Path]::IsPathRooted($v) -or -not (Test-Path -LiteralPath $v -PathType Container)) { throw "Không tìm thấy thư mục: $v" }
                    $v = [IO.Path]::GetFullPath($v)
                    # "D:\" thành "D:\." để dấu \ cuối không nuốt dấu " khi chương trình (Python, C) tách tham số.
                    if ($v.EndsWith('\')) { $v += '.' }
                }
                'number' {
                    $num = 0
                    if (-not [int]::TryParse($v, [ref]$num)) { throw "$label phải là số nguyên." }
                    if ($null -ne $spec.min -and $num -lt [int]$spec.min) { throw "$label nhỏ nhất là $($spec.min)." }
                    if ($null -ne $spec.max -and $num -gt [int]$spec.max) { throw "$label lớn nhất là $($spec.max)." }
                    $v = [string]$num
                }
                'choice' {
                    if (-not (@($spec.options) | Where-Object { $_.value -ceq $v })) { throw "$label không có lựa chọn '$v'." }
                }
                default {
                    if ($v.Length -gt 300) { throw "$label dài quá 300 ký tự." }
                    if ($v -match '[!^]') { throw "$label không được chứa ký tự ! hoặc ^." }
                }
            }
            $clean += $v
        }
        foreach ($v in $clean) {
            if ($spec.flag) { [void]$argv.Add([pscustomobject]@{ Value = $spec.flag; IsFlag = $true }) }
            [void]$argv.Add([pscustomobject]@{ Value = $v; IsFlag = $false })
        }
    }
    return , $argv.ToArray()
}

function Get-LaunchCommand {
    # Trả về exe + chuỗi tham số. Khi chạy RunAs, Windows bỏ qua WorkingDirectory nên tự cd vào thư mục.
    # $Arguments: mảng @{ Value; IsFlag } (từ Resolve-ActionArguments) hoặc chuỗi (coi là giá trị).
    param([string]$File, [object[]]$Arguments, [bool]$KeepOpen)
    $workDir = Split-Path $File -Parent
    $ext = [IO.Path]::GetExtension($File).ToLowerInvariant()
    $items = @(@($Arguments) | Where-Object { $null -ne $_ } | ForEach-Object {
            if ($_ -is [string]) { [pscustomobject]@{ Value = $_; IsFlag = $false } } else { $_ }
        } | Where-Object { [string]$_.Value -ne '' })
    $argText = ($items | ForEach-Object { '"' + $_.Value + '"' }) -join ' '
    switch ($ext) {
        { $_ -in '.bat', '.cmd' } {
            $inner = 'cd /d "' + $workDir + '" && "' + $File + '"'
            if ($argText) { $inner += ' ' + $argText }
            if ($KeepOpen) { $inner += ' & echo. & echo [Tram Tool] Cong cu da chay xong. Bam phim bat ky de dong. & pause >nul' }
            return @{ Exe = $env:ComSpec; Args = '/s /c "' + $inner + '"'; WorkDir = $workDir }
        }
        '.ps1' {
            $q = { param($s) "'" + ($s -replace "'", "''") + "'" }
            $psArgs = ($items | ForEach-Object { if ($_.IsFlag) { $_.Value } else { & $q $_.Value } }) -join ' '
            $cmd = 'Set-Location -LiteralPath ' + (& $q $workDir) + '; & ' + (& $q $File) + ' ' + $psArgs
            $noExit = if ($KeepOpen) { '-NoExit ' } else { '' }
            return @{ Exe = 'powershell.exe'; Args = '-NoProfile -ExecutionPolicy Bypass ' + $noExit + '-Command "' + $cmd.Replace('"', '\"') + '"'; WorkDir = $workDir }
        }
        default { return @{ Exe = $File; Args = $argText; WorkDir = $workDir; Shell = $true } }
    }
}

function Start-ToolAction {
    param(
        [Parameter(Mandatory)]$Tool,
        [Parameter(Mandatory)]$Action,
        [object[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$HistoryPath
    )
    $result = [ordered]@{ ok = $false; cancelled = $false; message = ''; pid = $null; elevated = [bool]$Action.admin }
    $argValues = @(@($Arguments) | Where-Object { $null -ne $_ } | ForEach-Object { if ($_ -is [string]) { $_ } else { [string]$_.Value } })
    $entry = [ordered]@{
        time = Get-IsoTime; toolId = $Tool.id; toolName = $Tool.name; actionId = $Action.id; actionLabel = $Action.label
        elevated = [bool]$Action.admin; args = $argValues; ok = $false; message = ''
    }
    try {
        if ($Action.type -eq 'url') {
            Start-Process $Action.url
            $result.ok = $true; $result.message = 'Đã mở trang.'
        } else {
            $file = Expand-HubPath -Path $Action.file -BaseDir $Tool.dir
            if (-not (Test-PathInside -Path $file -Root $Tool.dir)) { throw 'File của action nằm ngoài thư mục công cụ.' }
            if (-not (Test-Path -LiteralPath $file)) { throw "Không tìm thấy file: $($Action.file)" }
            foreach ($a in $argValues) { Assert-SafeArgument -Value $a }
            Update-EnvPath
            if ($Action.type -eq 'open') {
                Start-Process -FilePath $file
                $result.ok = $true; $result.message = 'Đã mở.'
            } else {
                $cmd = Get-LaunchCommand -File $file -Arguments $Arguments -KeepOpen $Action.keepOpen
                $sp = @{ FilePath = $cmd.Exe; WorkingDirectory = $cmd.WorkDir; PassThru = $true }
                if ($cmd.Args) { $sp.ArgumentList = $cmd.Args }
                if ($Action.admin) { $sp.Verb = 'RunAs' }
                $proc = Start-Process @sp
                if ($proc) { $result.pid = $proc.Id }
                if (-not $Action.admin) { Invoke-BringToFront -Process $proc }
                $result.ok = $true
                $result.message = if ($Action.admin) { 'Đã mở công cụ với quyền Admin.' } else { 'Đã mở công cụ trong cửa sổ mới.' }
            }
        }
    } catch [System.ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -eq 1223) {
            $result.cancelled = $true
            $result.message = 'Bạn đã chọn "Không" ở hộp thoại quyền Admin (UAC) nên công cụ chưa chạy.'
        } else { $result.message = $_.Exception.Message }
    } catch {
        $result.message = $_.Exception.Message
    }
    $entry.ok = $result.ok; $entry.message = $result.message; $entry.pid = $result.pid
    try { Add-JsonLine -Path $HistoryPath -InputObject $entry } catch { Write-HubLog "Không ghi được lịch sử: $($_.Exception.Message)" 'warn' }
    return $result
}

function Get-RunHistory {
    param([string]$HistoryPath, [int]$Limit = 200)
    if (-not (Test-Path -LiteralPath $HistoryPath)) { return @() }
    $lines = @(Get-Content -LiteralPath $HistoryPath -Encoding UTF8 -Tail $Limit)
    $out = New-Object System.Collections.ArrayList
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if (-not $lines[$i].Trim()) { continue }
        try { [void]$out.Add(($lines[$i] | ConvertFrom-Json)) } catch { }
    }
    return $out.ToArray()   # trả từng phần tử; nơi gọi bọc @()
}

function Open-HubPath {
    # Mở file bằng ứng dụng mặc định, hoặc mở Explorer và chọn sẵn file/thư mục.
    param([string]$Path, [switch]$Reveal)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Không tìm thấy: $Path" }
    if ($Reveal) {
        if (Test-Path -LiteralPath $Path -PathType Container) { $p = Start-Process explorer.exe -ArgumentList ('"' + $Path + '"') -PassThru }
        else { $p = Start-Process explorer.exe -ArgumentList ('/select,"' + $Path + '"') -PassThru }
    } else {
        $p = Start-Process -FilePath $Path -PassThru
    }
}

function Show-FilePicker {
    # Hộp thoại chọn file gốc của Windows; form TopMost ẩn giúp hộp thoại nổi lên trên trình duyệt.
    param([string]$Title = 'Chọn file', [string]$Filter = 'Tất cả|*.*', [switch]$Multiple, [switch]$Folder, [string]$InitialDir)
    Add-Type -AssemblyName System.Windows.Forms
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true; $owner.ShowInTaskbar = $false; $owner.StartPosition = 'CenterScreen'
    $owner.Size = New-Object System.Drawing.Size(1, 1); $owner.Opacity = 0
    $owner.Show(); $owner.Activate()
    try {
        if ($Folder) {
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = $Title; $dlg.ShowNewFolderButton = $true
            if ($InitialDir -and (Test-Path -LiteralPath $InitialDir)) { $dlg.SelectedPath = $InitialDir }
            if ($dlg.ShowDialog($owner) -eq 'OK') { return , @($dlg.SelectedPath) }
            return , @()
        }
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = $Title; $dlg.Filter = $Filter; $dlg.Multiselect = [bool]$Multiple; $dlg.RestoreDirectory = $true
        if ($InitialDir -and (Test-Path -LiteralPath $InitialDir)) { $dlg.InitialDirectory = $InitialDir }
        if ($dlg.ShowDialog($owner) -eq 'OK') { return , @($dlg.FileNames) }
        return , @()
    } finally { $owner.Close(); $owner.Dispose() }
}
