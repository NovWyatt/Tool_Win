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
        [Parameter(Mandatory)][string]$HistoryPath,
        $Values = $null   # giá trị form người dùng nhập, lưu lại để lần sau điền sẵn
    )
    $result = [ordered]@{ ok = $false; cancelled = $false; message = ''; pid = $null; elevated = [bool]$Action.admin; jobId = $null }
    $argValues = @(@($Arguments) | Where-Object { $null -ne $_ } | ForEach-Object { if ($_ -is [string]) { $_ } else { [string]$_.Value } })
    $entry = [ordered]@{
        time = Get-IsoTime; toolId = $Tool.id; toolName = $Tool.name; actionId = $Action.id; actionLabel = $Action.label
        elevated = [bool]$Action.admin; args = $argValues; ok = $false; cancelled = $false; message = ''
    }
    if ($null -ne $Values) { $entry.values = $Values }
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
                if ($proc) {
                    $result.pid = $proc.Id
                    # Script tự nâng quyền sẽ mở bản Admin rồi thoát ngay, nên không theo dõi được cửa sổ thật.
                    if (-not ($Action.selfElevates -and -not $Action.admin)) { $result.jobId = Register-ToolJob -Entry $entry -Process $proc }
                }
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
    $entry.ok = $result.ok; $entry.cancelled = $result.cancelled; $entry.message = $result.message; $entry.pid = $result.pid
    try { Add-JsonLine -Path $HistoryPath -InputObject $entry } catch { Write-HubLog "Không ghi được lịch sử: $($_.Exception.Message)" 'warn' }
    return $result
}

# ---------------------------------------------------------------- công việc: cửa sổ công cụ mở từ trạm
# Trạm giữ tiến trình của từng lần chạy để biết cửa sổ còn mở hay đã đóng; khi đóng thì ghi thêm một dòng
# { type: 'end', time: <time của lần chạy> } vào lịch sử với mã thoát và thời gian chạy.
$script:Jobs = [ordered]@{}   # id -> thông tin gửi cho giao diện
$script:JobProcs = @{}        # id -> @{ Process; Start; Ended } (giữ trong máy chủ)

function Register-ToolJob {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)][System.Diagnostics.Process]$Process)
    $id = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $script:Jobs[$id] = [ordered]@{
        id = $id; time = $Entry.time; toolId = $Entry.toolId; toolName = $Entry.toolName; actionId = $Entry.actionId
        actionLabel = $Entry.actionLabel; elevated = $Entry.elevated; pid = $Process.Id
        state = 'running'; exitCode = $null; endedAt = $null; durationSec = 0
    }
    $script:JobProcs[$id] = @{ Process = $Process; Start = Get-Date; Ended = $null }
    return $id
}

function Get-JobState {
    # done: mã thoát 0; closed: người dùng đóng cửa sổ (0xC000013A); failed: mã khác 0; ended: không đọc được mã.
    param($ExitCode)
    if ($null -eq $ExitCode) { return 'ended' }
    if ($ExitCode -eq 0) { return 'done' }
    if ($ExitCode -eq -1073741510) { return 'closed' }
    return 'failed'
}

function Update-ToolJobs {
    param([Parameter(Mandatory)][string]$HistoryPath)
    $now = Get-Date
    foreach ($job in @($script:Jobs.Values)) {
        $info = $script:JobProcs[$job.id]
        if ($job.state -ne 'running') {
            # Đã xong hơn 1 giờ thì thôi hiện ở bảng Đang chạy (lịch sử vẫn giữ).
            if ($info.Ended -and ($now - $info.Ended).TotalMinutes -gt 60) { $script:Jobs.Remove($job.id); $script:JobProcs.Remove($job.id) }
            continue
        }
        $p = $info.Process
        $exited = $false
        try { $exited = $p.HasExited } catch { $exited = -not (Get-Process -Id $job.pid -ErrorAction SilentlyContinue) }
        if (-not $exited) { $job.durationSec = [int]($now - $info.Start).TotalSeconds; continue }
        $code = $null; try { $code = $p.ExitCode } catch { }
        $end = $now; try { $end = $p.ExitTime } catch { }
        $job.exitCode = $code
        $job.endedAt = Get-IsoTime $end
        $job.durationSec = [int][Math]::Max(0, ($end - $info.Start).TotalSeconds)
        $job.state = Get-JobState -ExitCode $code
        $info.Ended = $now
        try { $p.Dispose() } catch { }
        $rec = [ordered]@{ type = 'end'; time = $job.time; endedAt = $job.endedAt; exitCode = $code; state = $job.state; durationSec = $job.durationSec }
        try { Add-JsonLine -Path $HistoryPath -InputObject $rec } catch { Write-HubLog "Không ghi được kết quả chạy: $($_.Exception.Message)" 'warn' }
    }
}

function Get-ToolJobs {
    return @($script:Jobs.Values | Sort-Object { $_.time } -Descending)
}

function Test-ToolJobsRunning {
    return [bool](@($script:Jobs.Values | Where-Object { $_.state -eq 'running' }).Count)
}

function Remove-ToolJobs {
    # Ẩn các công việc đã xong khỏi bảng Đang chạy; công việc còn chạy thì giữ.
    param([string[]]$Ids = @(), [switch]$AllFinished)
    $n = 0
    foreach ($job in @($script:Jobs.Values)) {
        if ($job.state -eq 'running') { continue }
        if ($AllFinished -or $Ids -contains $job.id) { $script:Jobs.Remove($job.id); $script:JobProcs.Remove($job.id); $n++ }
    }
    return $n
}

function Show-ToolJobWindow {
    param([Parameter(Mandatory)][string]$Id)
    $info = $script:JobProcs[$Id]
    $job = $script:Jobs[$Id]
    if (-not $info -or -not $job -or $job.state -ne 'running') { throw 'Cửa sổ này đã đóng.' }
    Invoke-BringToFront -Process $info.Process -TimeoutMs 600
}

function Get-RunHistory {
    # Mỗi lần chạy là một dòng; dòng { type: 'end' } bổ sung kết quả khi cửa sổ công cụ đóng.
    # state: running | done | closed | failed | ended | unknown (trạm tắt trước khi cửa sổ đóng) | cancelled | error
    param([string]$HistoryPath, [int]$Limit = 150)
    if (-not (Test-Path -LiteralPath $HistoryPath)) { return @() }
    $lines = @(Get-Content -LiteralPath $HistoryPath -Encoding UTF8 -Tail ($Limit * 2))
    $ends = @{}
    $runs = New-Object System.Collections.ArrayList
    foreach ($line in $lines) {
        if (-not $line.Trim()) { continue }
        try { $o = $line | ConvertFrom-Json } catch { continue }
        if ([string](Get-Prop $o 'type' '') -eq 'end') { $ends[[string]$o.time] = $o } else { [void]$runs.Add($o) }
    }
    $running = @{}
    foreach ($j in $script:Jobs.Values) { if ($j.state -eq 'running') { $running[[string]$j.time] = $j } }
    $out = New-Object System.Collections.ArrayList
    for ($i = $runs.Count - 1; $i -ge 0 -and $out.Count -lt $Limit; $i--) {
        $r = $runs[$i]
        $key = [string]$r.time
        $e = $ends[$key]
        $state = if ($e) { [string]$e.state }
        elseif ($running.ContainsKey($key)) { 'running' }
        elseif ($r.ok) { 'unknown' }
        elseif ([bool](Get-Prop $r 'cancelled' $false) -or [string]$r.message -match 'UAC') { 'cancelled' }
        else { 'error' }
        $r | Add-Member -NotePropertyName state -NotePropertyValue $state -Force
        if ($e) {
            $r | Add-Member -NotePropertyName exitCode -NotePropertyValue $e.exitCode -Force
            $r | Add-Member -NotePropertyName durationSec -NotePropertyValue $e.durationSec -Force
            $r | Add-Member -NotePropertyName endedAt -NotePropertyValue $e.endedAt -Force
        } elseif ($running.ContainsKey($key)) {
            $r | Add-Member -NotePropertyName durationSec -NotePropertyValue $running[$key].durationSec -Force
        }
        [void]$out.Add($r)
    }
    return $out.ToArray()   # trả từng phần tử; nơi gọi bọc @()
}

function Remove-RunHistory {
    # Xoá lịch sử chạy: -All xoá hết, hoặc chỉ các lần chạy có time nằm trong -Times. Trả về số lần chạy đã xoá.
    param([Parameter(Mandatory)][string]$HistoryPath, [string[]]$Times = @(), [switch]$All)
    if (-not (Test-Path -LiteralPath $HistoryPath)) { return 0 }
    $lines = @([IO.File]::ReadAllLines($HistoryPath, [Text.Encoding]::UTF8) | Where-Object { $_.Trim() })
    $dropTimes = @{}
    foreach ($t in $Times) { if ($t) { $dropTimes[[string]$t] = $true } }
    $keep = New-Object System.Collections.ArrayList
    $removed = 0   # chỉ đếm lần chạy, không đếm dòng kết quả { type: 'end' } đi kèm
    foreach ($l in $lines) {
        $o = $null
        try { $o = $l | ConvertFrom-Json } catch { }
        $isEnd = $o -and [string](Get-Prop $o 'type' '') -eq 'end'
        if ($All -or ($o -and $dropTimes.ContainsKey([string]$o.time))) { if (-not $isEnd) { $removed++ } }
        else { [void]$keep.Add($l) }
    }
    if ($keep.Count -ne $lines.Count) {
        $tmp = "$HistoryPath.tmp"
        [IO.File]::WriteAllText($tmp, $(if ($keep.Count) { ($keep -join "`n") + "`n" } else { '' }), $script:Utf8NoBom)
        Move-Item -LiteralPath $tmp -Destination $HistoryPath -Force
    }
    return $removed
}

function Remove-ToRecycleBin {
    # Chuyển file hoặc thư mục vào Thùng rác (khôi phục được). Ổ không có Thùng rác (USB, ổ mạng) hoặc mục quá lớn:
    # Windows tự hỏi trước khi xoá hẳn (FOF_WANTNUKEWARNING). Trả về 'deleted' hoặc 'cancelled'; lỗi thì ném ra.
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw 'Không còn trên máy (có thể đã bị xoá).' }
    if (-not ('TramTool.ShellFileOp' -as [type])) {
        $pack = if ([IntPtr]::Size -eq 4) { 1 } else { 8 }   # shellapi.h đóng gói SHFILEOPSTRUCT 1 byte trên Windows 32-bit
        Add-Type -Namespace TramTool -Name ShellFileOp -MemberDefinition @"
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode, Pack = $pack)]
public struct Op {
    public IntPtr hwnd; public uint wFunc; public string pFrom; public string pTo; public ushort fFlags;
    public bool fAnyOperationsAborted; public IntPtr hNameMappings; public string lpszProgressTitle;
}
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern int SHFileOperation(ref Op op);
"@
    }
    Add-Type -AssemblyName System.Windows.Forms
    # Cửa sổ ẩn luôn nổi trên cùng làm chủ hộp thoại cảnh báo của Windows (nếu có), để nó không nằm sau trình duyệt.
    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true; $owner.ShowInTaskbar = $false; $owner.Size = New-Object System.Drawing.Size(1, 1); $owner.Opacity = 0
    $owner.Show()
    try {
        $op = New-Object TramTool.ShellFileOp+Op
        $op.hwnd = $owner.Handle
        $op.wFunc = 3                     # FO_DELETE
        $op.pFrom = $Path + "`0`0"        # danh sách đường dẫn kết thúc bằng 2 ký tự null
        # FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI | FOF_NO_CONNECTED_ELEMENTS | FOF_WANTNUKEWARNING
        $op.fFlags = [uint16](0x40 -bor 0x10 -bor 0x4 -bor 0x400 -bor 0x2000 -bor 0x4000)
        $rc = [TramTool.ShellFileOp]::SHFileOperation([ref]$op)
    } finally { $owner.Close(); $owner.Dispose() }
    if ($op.fAnyOperationsAborted -or $rc -in 0x4C7, 0x75) { return 'cancelled' }   # ERROR_CANCELLED, DE_OPCANCELLED
    if ($rc -ne 0) {
        $msg = switch ($rc) {
            { $_ -in 5, 0x78 } { 'Không có quyền xoá, có thể cần quyền Admin.' }
            { $_ -in 32, 0x20 } { 'File đang mở trong chương trình khác. Đóng chương trình đó rồi thử lại.' }
            { $_ -in 2, 3, 0x7C } { 'Không còn trên máy (có thể đã bị xoá).' }
            default { 'Windows báo lỗi 0x{0:X} khi xoá.' -f $rc }
        }
        throw $msg
    }
    if (Test-Path -LiteralPath $Path) { throw 'Windows báo đã xoá nhưng file vẫn còn.' }
    return 'deleted'
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
