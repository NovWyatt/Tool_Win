# Dọn ổ C - danh sách thứ dọn được và bộ đếm, xoá file.
# Chỉ dọn thứ Windows hay ứng dụng tự sinh lại (file tạm, bộ nhớ đệm, báo cáo lỗi, file tải về của Windows Update).
# Thư mục được dọn tính từ đường dẫn chuẩn của Windows, không nhận từ người dùng; mọi lần xoá đi qua Test-SafeRoot.

# File chỉ có trên mây (OneDrive "Files On-Demand"): không chiếm chỗ trên ổ, không đếm.
$script:CloudMask = 0x1000 -bor 0x40000 -bor 0x400000

function Get-KnownDirs {
    # Thư mục chuẩn của Windows và của người đang chạy công cụ.
    $lad = [Environment]::GetFolderPath('LocalApplicationData')
    return [pscustomobject]@{
        Local   = $lad
        Roaming = [Environment]::GetFolderPath('ApplicationData')
        Windows = [Environment]::GetFolderPath('Windows')
        Data    = [Environment]::GetFolderPath('CommonApplicationData')
        Temp    = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
        Drive   = $env:SystemDrive
    }
}

function Get-SafeRoots {
    # Thư mục gốc được phép dọn. Sub: được đi vào thư mục con. Filter: chỉ được xoá file khớp mẫu này.
    $k = Get-KnownDirs
    $rows = @(
        @{ Path = (Join-Path $k.Local 'Temp'); Sub = $true },
        @{ Path = (Join-Path $k.Local 'CrashDumps'); Sub = $true },
        @{ Path = (Join-Path $k.Local 'Microsoft\Windows\WER'); Sub = $true },
        @{ Path = (Join-Path $k.Local 'Google\Chrome\User Data'); Sub = $true },
        @{ Path = (Join-Path $k.Local 'Microsoft\Edge\User Data'); Sub = $true },
        @{ Path = (Join-Path $k.Local 'BraveSoftware\Brave-Browser\User Data'); Sub = $true },
        @{ Path = (Join-Path $k.Local 'CocCoc\Browser\User Data'); Sub = $true },
        @{ Path = (Join-Path $k.Local 'Mozilla\Firefox\Profiles'); Sub = $true },
        @{ Path = (Join-Path $k.Windows 'Temp'); Sub = $true },
        @{ Path = (Join-Path $k.Windows 'SoftwareDistribution\Download'); Sub = $true },
        @{ Path = (Join-Path $k.Data 'Microsoft\Windows\WER'); Sub = $true },
        @{ Path = (Join-Path $k.Windows 'LiveKernelReports'); Sub = $true },
        @{ Path = (Join-Path $k.Windows 'Logs\CBS'); Sub = $false; Filter = 'CbsPersist_*' },
        @{ Path = $k.Windows; Sub = $false; Filter = 'MEMORY.DMP' }
    )
    return @($rows | ForEach-Object { [pscustomobject]@{ Path = $_.Path.TrimEnd('\'); Sub = [bool]$_.Sub; Filter = [string]$_.Filter } })
}

function Test-SafeRoot {
    # Trả '' khi được dọn $Root (với $Filter, có hay không đi vào thư mục con), câu lý do khi không.
    param([string]$Root, [string]$Filter = '*', [bool]$NoRecurse = $false)
    if (-not $Root -or $Root -notmatch '^[A-Za-z]:\\') { return "Đường dẫn '$Root' không phải đường dẫn đầy đủ." }
    $full = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if ($full.Length -le 3) { return "Không dọn cả ổ đĩa ($full)." }
    $k = Get-KnownDirs
    if ($k.Local -notmatch '\\AppData\\Local$' -or $k.Local.Length -le 20) { return "Thư mục AppData\Local của tài khoản này lạ ($($k.Local)): không dọn." }
    foreach ($s in (Get-SafeRoots)) {
        $inside = $full -ieq $s.Path -or ($s.Sub -and $full.StartsWith($s.Path + '\', [StringComparison]::OrdinalIgnoreCase))
        if (-not $inside) { continue }
        if ($s.Filter) {
            if ($full -ine $s.Path -or -not $NoRecurse -or $Filter -ine $s.Filter) { continue }
        }
        return ''
    }
    return "Thư mục '$full' không nằm trong danh sách được phép dọn."
}

function Invoke-Sweep {
    # Đếm (Delete:$false) hoặc xoá (Delete:$true) file trong $Root có ngày sửa và ngày tạo đều trước $Cutoff.
    # Không đi vào, không xoá junction, symlink. Xoá xong thì xoá thư mục con rỗng tạo trước $Cutoff (không xoá $Root).
    # File đang dùng, không có quyền: bỏ qua và đếm. $Seconds: giới hạn thời gian khi chỉ đếm (Partial = chưa đếm hết).
    param([string]$Root, [datetime]$Cutoff, [string]$Filter = '*', [switch]$NoRecurse, [switch]$Delete, [int]$Seconds = 0)
    $r = [pscustomobject]@{
        Root = $Root; Bytes = [int64]0; Files = 0; Total = [int64]0; TotalFiles = 0; Dirs = 0
        Locked = 0; LockedBytes = [int64]0; Denied = 0; Links = 0; Partial = $false; Missing = $false
    }
    $why = Test-SafeRoot $Root $Filter ([bool]$NoRecurse)
    if ($why) { throw $why }
    $top = New-Object IO.DirectoryInfo($Root)
    if (-not $top.Exists) { $r.Missing = $true; return $r }
    if ($top.Attributes -band [IO.FileAttributes]::ReparsePoint) { $r.Links++; return $r }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $stack = New-Object 'System.Collections.Generic.Stack[IO.DirectoryInfo]'
    $visited = New-Object 'System.Collections.Generic.List[IO.DirectoryInfo]'
    $stack.Push($top)
    while ($stack.Count) {
        if ($Seconds -and -not $Delete -and $watch.Elapsed.TotalSeconds -gt $Seconds) { $r.Partial = $true; break }
        $d = $stack.Pop()
        try {
            foreach ($f in $d.EnumerateFiles($Filter)) {
                $attr = [int]$f.Attributes
                if ($attr -band 0x400) { $r.Links++; continue }
                if ($attr -band $script:CloudMask) { continue }
                $len = $f.Length
                $r.Total += $len; $r.TotalFiles++
                if ($f.LastWriteTime -ge $Cutoff -or $f.CreationTime -ge $Cutoff) { continue }
                if ($Delete) {
                    try {
                        if ($attr -band 1) { $f.Attributes = [IO.FileAttributes]($attr -band (-bnot 1)) }
                        $f.Delete()
                    } catch { $r.Locked++; $r.LockedBytes += $len; continue }
                }
                $r.Bytes += $len; $r.Files++
            }
            if (-not $NoRecurse) {
                foreach ($s in $d.EnumerateDirectories()) {
                    if ($s.Attributes -band [IO.FileAttributes]::ReparsePoint) { $r.Links++; continue }
                    $stack.Push($s); $visited.Add($s)
                }
            }
        } catch { $r.Denied++ }
    }
    if ($Delete) {
        # Con nằm sau cha trong $visited nên duyệt ngược là xoá từ sâu lên.
        for ($i = $visited.Count - 1; $i -ge 0; $i--) {
            $s = $visited[$i]
            try {
                $s.Refresh()
                if ($s.Exists -and $s.CreationTime -lt $Cutoff -and -not @($s.EnumerateFileSystemInfos() | Select-Object -First 1).Count) { $s.Delete(); $r.Dirs++ }
            } catch { }
        }
    }
    return $r
}

function Get-FolderBytes {
    # Dung lượng một thư mục bất kỳ (chỉ đọc, dùng cho phần báo cáo): @{ Bytes; Files; Partial; Denied; Missing }.
    param([string]$Path, [int]$Seconds = 10)
    $r = [pscustomobject]@{ Bytes = [int64]0; Files = 0; Partial = $false; Denied = 0; Missing = $false }
    $top = New-Object IO.DirectoryInfo($Path)
    if (-not $top.Exists) { $r.Missing = $true; return $r }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $stack = New-Object 'System.Collections.Generic.Stack[IO.DirectoryInfo]'
    $stack.Push($top)
    while ($stack.Count) {
        if ($Seconds -and $watch.Elapsed.TotalSeconds -gt $Seconds) { $r.Partial = $true; break }
        $d = $stack.Pop()
        try {
            foreach ($f in $d.EnumerateFiles()) {
                if ([int]$f.Attributes -band ($script:CloudMask -bor 0x400)) { continue }
                $r.Bytes += $f.Length; $r.Files++
            }
            foreach ($s in $d.EnumerateDirectories()) { if (-not ($s.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $stack.Push($s) } }
        } catch { $r.Denied++ }
    }
    return $r
}

# ---------------------------------------------------------------- trình duyệt
function Get-Browsers {
    # Trình duyệt có trên máy (thư mục dữ liệu của người đang chạy). Names: tên tiến trình; PathLike: lọc theo đường dẫn
    # khi tên tiến trình chung chung (Cốc Cốc chạy bằng browser.exe).
    $lad = (Get-KnownDirs).Local
    $defs = @(
        @{ Id = 'chrome'; Label = 'Google Chrome'; Dir = 'Google\Chrome\User Data'; Names = @('chrome'); PathLike = '' },
        @{ Id = 'edge'; Label = 'Microsoft Edge'; Dir = 'Microsoft\Edge\User Data'; Names = @('msedge'); PathLike = '' },
        @{ Id = 'brave'; Label = 'Brave'; Dir = 'BraveSoftware\Brave-Browser\User Data'; Names = @('brave'); PathLike = '' },
        @{ Id = 'coccoc'; Label = 'Cốc Cốc'; Dir = 'CocCoc\Browser\User Data'; Names = @('browser'); PathLike = '*\CocCoc\*' },
        @{ Id = 'firefox'; Label = 'Firefox'; Dir = 'Mozilla\Firefox\Profiles'; Names = @('firefox'); PathLike = '' }
    )
    $out = foreach ($d in $defs) {
        $root = Join-Path $lad $d.Dir
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        [pscustomobject]@{ Id = $d.Id; Label = $d.Label; Root = $root; Names = $d.Names; PathLike = $d.PathLike; Firefox = ($d.Id -eq 'firefox') }
    }
    return @($out)
}

function Get-BrowserCacheDirs {
    # Thư mục bộ nhớ đệm của một trình duyệt: chỉ thứ trình duyệt tự tạo lại (ảnh, mã trang web, shader đồ hoạ).
    # Không đụng mật khẩu, lịch sử, cookie, dữ liệu trang web lưu ngoại tuyến (Service Worker), tiện ích.
    param($Browser)
    $dirs = New-Object System.Collections.Generic.List[string]
    if ($Browser.Firefox) {
        foreach ($p in @(Get-ChildItem -LiteralPath $Browser.Root -Directory -Force -ErrorAction SilentlyContinue)) {
            $c = Join-Path $p.FullName 'cache2'
            if (Test-Path -LiteralPath $c -PathType Container) { $dirs.Add($c) }
        }
        return $dirs.ToArray()
    }
    foreach ($n in 'ShaderCache', 'GrShaderCache', 'GraphiteDawnCache') {
        $c = Join-Path $Browser.Root $n
        if (Test-Path -LiteralPath $c -PathType Container) { $dirs.Add($c) }
    }
    # Hồ sơ (Default, Profile 1...) là thư mục có file Preferences.
    foreach ($p in @(Get-ChildItem -LiteralPath $Browser.Root -Directory -Force -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path -LiteralPath (Join-Path $p.FullName 'Preferences') -PathType Leaf)) { continue }
        foreach ($n in 'Cache', 'Code Cache', 'GPUCache', 'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache') {
            $c = Join-Path $p.FullName $n
            if (Test-Path -LiteralPath $c -PathType Container) { $dirs.Add($c) }
        }
    }
    return $dirs.ToArray()
}

# ---------------------------------------------------------------- danh sách mục dọn
function New-CleanItem {
    param([string]$Id, [string]$Label, [string]$Scope, $Parts = @(), [bool]$All = $false, $App = $null, [string]$Kind = 'files', [string]$Note = '')
    return [pscustomobject]@{ Id = $Id; Label = $Label; Scope = $Scope; Parts = @($Parts); All = $All; App = $App; Kind = $Kind; Note = $Note; Skip = '' }
}

function New-CleanPart { param([string]$Root, [string]$Filter = '*', [bool]$NoRecurse = $false) return [pscustomobject]@{ Root = $Root; Filter = $Filter; NoRecurse = $NoRecurse } }

function Get-UserItems {
    # Rác của người đang chạy công cụ (không cần quyền Admin).
    $k = Get-KnownDirs
    $items = New-Object System.Collections.Generic.List[object]
    $tempRoot = Join-Path $k.Local 'Temp'
    $t = New-CleanItem 'temp' 'File tạm của bạn (%TEMP%)' 'user' @(New-CleanPart $k.Temp)
    if ($k.Temp -ine $tempRoot -and -not $k.Temp.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $t.Skip = "TEMP đang trỏ tới $($k.Temp), không phải thư mục tạm mặc định: không dọn."
    }
    $items.Add($t)
    $items.Add((New-CleanItem 'loi-ung-dung' 'Báo cáo lỗi, bản ghi ứng dụng bị treo' 'user' @(
                (New-CleanPart (Join-Path $k.Local 'CrashDumps')),
                (New-CleanPart (Join-Path $k.Local 'Microsoft\Windows\WER\ReportArchive')),
                (New-CleanPart (Join-Path $k.Local 'Microsoft\Windows\WER\ReportQueue')))))
    foreach ($b in (Get-Browsers)) {
        $parts = @(Get-BrowserCacheDirs $b | ForEach-Object { New-CleanPart $_ })
        if (-not $parts.Count) { continue }
        $items.Add((New-CleanItem ('trinh-duyet-' + $b.Id) ("Bộ nhớ đệm $($b.Label)") 'user' $parts $true $b 'files' 'Không mất mật khẩu, lịch sử, đăng nhập; trang web tải lại ảnh lần đầu.'))
    }
    return $items.ToArray()
}

function Get-SystemItems {
    # Rác chung của Windows (cần quyền Admin). $DumpLoi: thêm bản ghi lỗi màn hình xanh, lỗi phần cứng.
    param([switch]$DumpLoi)
    $k = Get-KnownDirs
    $items = New-Object System.Collections.Generic.List[object]
    $items.Add((New-CleanItem 'temp-win' 'File tạm của Windows (Windows\Temp)' 'system' @(New-CleanPart (Join-Path $k.Windows 'Temp'))))
    $wu = New-CleanItem 'windows-update' 'File tải về của Windows Update đã cài' 'system' @(New-CleanPart (Join-Path $k.Windows 'SoftwareDistribution\Download'))
    $wu.Skip = Get-UpdateBusyReason
    $items.Add($wu)
    $items.Add((New-CleanItem 'delivery-optimization' 'Bộ nhớ đệm chia sẻ bản cập nhật (Delivery Optimization)' 'system' @() $true $null 'do'))
    $items.Add((New-CleanItem 'loi-he-thong' 'Báo cáo lỗi của Windows' 'system' @(
                (New-CleanPart (Join-Path $k.Data 'Microsoft\Windows\WER\ReportArchive')),
                (New-CleanPart (Join-Path $k.Data 'Microsoft\Windows\WER\ReportQueue')),
                (New-CleanPart (Join-Path $k.Data 'Microsoft\Windows\WER\Temp')))))
    $items.Add((New-CleanItem 'nhat-ky-cbs' 'Nhật ký cài cập nhật cũ (Logs\CBS\CbsPersist)' 'system' @(New-CleanPart (Join-Path $k.Windows 'Logs\CBS') 'CbsPersist_*' $true)))
    if ($DumpLoi) {
        $items.Add((New-CleanItem 'dump-loi' 'Bản ghi lỗi màn hình xanh, lỗi phần cứng (MEMORY.DMP, LiveKernelReports)' 'system' @(
                    (New-CleanPart $k.Windows 'MEMORY.DMP' $true),
                    (New-CleanPart (Join-Path $k.Windows 'LiveKernelReports') '*.dmp')) $true $null 'files' 'Giữ lại Windows\Minidump (bản ghi nhỏ, công cụ chẩn đoán cần).'))
    }
    return $items.ToArray()
}

function Test-RebootPending {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    foreach ($k in $keys) { if (Test-Path -LiteralPath $k) { return $true } }
    return $false
}

function Test-UpdateInstalling {
    # Windows Modules Installer Worker đang chạy: Windows đang cài, gỡ bản cập nhật hoặc tính năng.
    return [bool](Get-Process -Name 'TiWorker' -ErrorAction SilentlyContinue)
}

function Get-UpdateBusyReason {
    if (Test-UpdateInstalling) { return 'Windows đang cài bản cập nhật: để lần sau.' }
    if (Test-RebootPending) { return 'Windows chờ khởi động lại để cài xong bản cập nhật: khởi động lại máy rồi dọn.' }
    return ''
}

# ---------------------------------------------------------------- Delivery Optimization (qua lệnh của Windows)
function Get-DOCacheBytes {
    # Dung lượng bộ nhớ đệm Delivery Optimization; -1 khi không đọc được.
    try { return [int64](Get-DeliveryOptimizationPerfSnap -ErrorAction Stop).CacheSizeBytes } catch { return [int64]-1 }
}

function Clear-DOCache {
    Delete-DeliveryOptimizationCache -Force -ErrorAction Stop | Out-Null
}

# ---------------------------------------------------------------- đếm, xoá theo mục
function Measure-CleanItem {
    # Đếm một mục (không xoá). Trả @{ Item; Bytes; Files; Total; TotalFiles; Locked; Denied; Partial; Missing; Error }.
    param($Item, [datetime]$Cutoff, [int]$Seconds = 0)
    $res = [pscustomobject]@{ Item = $Item; Bytes = [int64]0; Files = 0; Total = [int64]0; TotalFiles = 0; Locked = 0; Denied = 0; Partial = $false; Missing = $true; Error = '' }
    if ($Item.Skip) { return $res }
    if ($Item.Kind -eq 'do') {
        $b = Get-DOCacheBytes
        if ($b -lt 0) { $res.Error = 'Không đọc được dung lượng.'; return $res }
        $res.Bytes = $b; $res.Total = $b; $res.Missing = $false
        return $res
    }
    $cut = if ($Item.All) { [datetime]::MaxValue } else { $Cutoff }
    foreach ($p in $Item.Parts) {
        try { $s = Invoke-Sweep -Root $p.Root -Cutoff $cut -Filter $p.Filter -NoRecurse:$p.NoRecurse -Seconds $Seconds }
        catch { $res.Error = $_.Exception.Message; continue }
        if (-not $s.Missing) { $res.Missing = $false }
        $res.Bytes += $s.Bytes; $res.Files += $s.Files; $res.Total += $s.Total; $res.TotalFiles += $s.TotalFiles; $res.Denied += $s.Denied
        if ($s.Partial) { $res.Partial = $true }
    }
    return $res
}

function Invoke-CleanItem {
    # Xoá một mục. Trả @{ Item; Bytes (đã xoá); Files; Locked; LockedBytes; Denied; Error }.
    param($Item, [datetime]$Cutoff)
    $res = [pscustomobject]@{ Item = $Item; Bytes = [int64]0; Files = 0; Locked = 0; LockedBytes = [int64]0; Denied = 0; Error = '' }
    if ($Item.Kind -eq 'do') {
        $before = Get-DOCacheBytes
        try { Clear-DOCache } catch { $res.Error = $_.Exception.Message.Trim(); return $res }
        $after = Get-DOCacheBytes
        if ($before -ge 0 -and $after -ge 0 -and $before -gt $after) { $res.Bytes = $before - $after }
        return $res
    }
    $cut = if ($Item.All) { [datetime]::MaxValue } else { $Cutoff }
    foreach ($p in $Item.Parts) {
        try { $s = Invoke-Sweep -Root $p.Root -Cutoff $cut -Filter $p.Filter -NoRecurse:$p.NoRecurse -Delete }
        catch { $res.Error = $_.Exception.Message; continue }
        $res.Bytes += $s.Bytes; $res.Files += $s.Files; $res.Locked += $s.Locked; $res.LockedBytes += $s.LockedBytes; $res.Denied += $s.Denied
    }
    return $res
}
