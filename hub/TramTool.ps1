<#
  Trạm Tool - máy chủ cục bộ cho giao diện chọn và chạy công cụ.
  Chỉ lắng nghe trên 127.0.0.1, mọi API cần mã thông hành ngẫu nhiên sinh mỗi lần mở,
  nên trang web khác đang mở trên máy không gọi được. Chạy bằng TramTool.bat ở thư mục gốc.
#>
[CmdletBinding()]
param(
    [int]$Port = 0,
    [switch]$NoBrowser,
    [string]$Browser = '',
    [string]$DataDir = '',    # chạy thử: thư mục dữ liệu riêng (mặc định hub\data), không đụng lịch sử, cài đặt thật
    [string]$ToolsDir = ''    # chạy thử: thư mục công cụ khác (mặc định tools\)
)

$ErrorActionPreference = 'Stop'
$HubVersion = '1.5.0'
$HubDir = $PSScriptRoot
$RootDir = Split-Path $HubDir -Parent
if (-not $ToolsDir) { $ToolsDir = Join-Path $RootDir 'tools' }
$WebDir = Join-Path $HubDir 'web'
if (-not $DataDir) { $DataDir = Join-Path $HubDir 'data' }
$RuntimeFile = Join-Path $DataDir 'runtime.json'
$HistoryFile = Join-Path $DataDir 'history.jsonl'
$SettingsFile = Join-Path $DataDir 'settings.json'
# Lan can an toàn: script chạy trong cửa sổ Admin, ảnh trạng thái trước khi chạy, kết quả tạo điểm khôi phục.
$SafetyDir = Join-Path $HubDir 'safety'
$SnapshotDir = Join-Path $DataDir 'snapshots'
$RestoreLogFile = Join-Path $DataDir 'restore-points.jsonl'
# File tiến độ công cụ ghi trong lúc chạy (action có tienDo), xoá khi cửa sổ đóng.
$ProgressDir = Join-Path $DataDir 'tien-do'

. (Join-Path $HubDir 'lib\Common.ps1')
. (Join-Path $HubDir 'lib\Catalog.ps1')
. (Join-Path $HubDir 'lib\AnToan.ps1')
. (Join-Path $HubDir 'lib\Launcher.ps1')
. (Join-Path $HubDir 'lib\Checks.ps1')
. (Join-Path $HubDir 'lib\KetQua.ps1')
. (Join-Path $HubDir 'lib\CapNhat.ps1')

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$Host.UI.RawUI.WindowTitle = 'Trạm Tool - máy chủ (đóng cửa sổ này để tắt trạm)'
if (-not (Test-Path -LiteralPath $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

# ------------------------------------------------------------------ cài đặt
function Get-HubSettings {
    # Ghim, giao diện sáng/tối và chế độ đơn giản lưu ở máy chủ: localStorage của trình duyệt gắn với cổng,
    # mà cổng có thể đổi (47800-47820) nên lưu ở trình duyệt sẽ mất.
    # restorePoint: tạo điểm khôi phục hệ thống trước action đổi máy (người dùng vẫn bỏ chọn được từng lần chạy).
    $s = [ordered]@{ browser = 'auto'; autoExitMinutes = 10; pins = @(); theme = 'system'; simple = $false; restorePoint = $true }
    if (Test-Path -LiteralPath $SettingsFile) {
        try {
            $saved = Read-JsonFile $SettingsFile
            foreach ($k in @($s.Keys)) { $v = Get-Prop $saved $k $null; if ($null -ne $v) { $s[$k] = $v } }
        } catch { Write-HubLog "settings.json lỗi, dùng mặc định: $($_.Exception.Message)" 'warn' }
    }
    $s.pins = @(@($s.pins) | Where-Object { $_ } | ForEach-Object { [string]$_ })   # 1 phần tử đọc từ JSON thành chuỗi
    $s.simple = [bool]$s.simple
    $s.restorePoint = [bool]$s.restorePoint
    return $s
}

function Find-Browser {
    param([string]$Kind)
    $candidates = switch ($Kind) {
        'brave' { @("$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe", "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe", "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe") }
        'edge' { @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") }
        'chrome' { @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") }
        default { @() }
    }
    foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath $c)) { return $c } }
    return $null
}

function Open-HubUi {
    # Mở giao diện dạng cửa sổ ứng dụng (--app). Ưu tiên Brave (trình duyệt của Wyatt), rồi Edge.
    param([string]$Url, [string]$Preference = 'auto')
    $order = switch ($Preference) { 'brave' { @('brave') } 'edge' { @('edge') } 'chrome' { @('chrome') } 'default' { @() } default { @('brave', 'edge', 'chrome') } }
    foreach ($kind in $order) {
        $exe = Find-Browser $kind
        if ($exe) {
            Start-Process -FilePath $exe -ArgumentList @("--app=$Url", '--window-size=1320,880')
            return $kind
        }
    }
    Start-Process $Url
    return 'default'
}

# ------------------------------------------------------------------ một phiên bản duy nhất
function Test-RunningHub {
    if (-not (Test-Path -LiteralPath $RuntimeFile)) { return $null }
    try {
        $rt = Read-JsonFile $RuntimeFile
        $proc = Get-Process -Id ([int]$rt.pid) -ErrorAction SilentlyContinue
        if (-not $proc) { return $null }
        $req = [Net.HttpWebRequest]::Create("http://127.0.0.1:$($rt.port)/api/ping")
        $req.Proxy = $null; $req.Timeout = 2000; $req.Headers.Add('X-Tram-Token', $rt.token)
        $resp = $req.GetResponse(); $resp.Close()
        return $rt
    } catch { return $null }
}

$existing = Test-RunningHub
if ($existing) {
    Write-HubLog "Trạm Tool đang chạy sẵn (cổng $($existing.port)), mở lại giao diện." 'ok'
    if (-not $NoBrowser) {
        $pref = if ($Browser) { $Browser } else { (Get-HubSettings).browser }
        [void](Open-HubUi -Url "http://127.0.0.1:$($existing.port)/#t=$($existing.token)" -Preference $pref)
    }
    return
}

# ------------------------------------------------------------------ khởi động máy chủ
$Token = New-HubToken
$Listener = $null
$ports = if ($Port) { @($Port) } else { @(47800..47820) + @(0) }
foreach ($p in $ports) {
    if ($p -eq 0) {
        $tcp = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $tcp.Start(); $p = $tcp.LocalEndpoint.Port; $tcp.Stop()
    }
    $l = New-Object Net.HttpListener
    $l.Prefixes.Add("http://127.0.0.1:$p/")
    try { $l.Start(); $Listener = $l; $Port = $p; break } catch { $l.Close() }
}
if (-not $Listener) { throw 'Không mở được cổng nào trên 127.0.0.1. Thử chạy lại hoặc khởi động lại máy.' }

$State = @{
    Catalog = @(); Categories = @(); LastSeen = Get-Date; Connected = $false; StartedAt = Get-Date
    Settings = Get-HubSettings; Stop = $false; Browser = ''
}

function Update-Catalog {
    $State.Categories = Get-HubCategories -HubDir $HubDir
    $State.Catalog = Get-HubCatalog -ToolsDir $ToolsDir -RootDir $RootDir
    Clear-CheckCache
}

function Get-ToolById {
    param([string]$Id)
    $t = $State.Catalog | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $t) { throw "Không tìm thấy công cụ '$Id'. Bấm Làm mới danh sách." }
    return $t
}

function Get-ActionById {
    param($Tool, [string]$Id)
    $a = $Tool.actions | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $a) { throw "Công cụ '$($Tool.name)' không có action '$Id'." }
    return $a
}

# Bỏ dấu "tải từ Internet" trên script của trạm (khi chép qua Zalo/USB), tránh Windows chặn chạy.
try {
    Get-ChildItem -LiteralPath $HubDir -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
    foreach ($d in @(Get-ChildItem -LiteralPath $ToolsDir -Directory -ErrorAction SilentlyContinue)) {
        Get-ChildItem -LiteralPath $d.FullName -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '^\.(bat|cmd|ps1|py|vbs)$' } | Unblock-File -ErrorAction SilentlyContinue
    }
} catch { }

Update-Catalog
Clear-ToolProgressDir -Dir $ProgressDir
Write-JsonFile -Path $RuntimeFile -InputObject ([ordered]@{ port = $Port; token = $Token; pid = $PID; startedAt = (Get-IsoTime) })
$BaseUrl = "http://127.0.0.1:$Port"
Write-HubLog "Trạm Tool $HubVersion đang chạy tại $BaseUrl (đóng cửa sổ này để tắt)." 'ok'
Write-HubLog "Đã nạp $($State.Catalog.Count) công cụ từ $ToolsDir"

# ------------------------------------------------------------------ HTTP helpers
$MimeTypes = @{
    '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.mjs' = 'text/javascript; charset=utf-8'
    '.css' = 'text/css; charset=utf-8'; '.svg' = 'image/svg+xml'; '.json' = 'application/json; charset=utf-8'
    '.png' = 'image/png'; '.ico' = 'image/x-icon'; '.woff2' = 'font/woff2'; '.md' = 'text/markdown; charset=utf-8'; '.txt' = 'text/plain; charset=utf-8'
}
$Csp = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"

function Send-Bytes {
    param($Ctx, [byte[]]$Bytes, [string]$ContentType, [int]$Status = 200)
    $res = $Ctx.Response
    $res.StatusCode = $Status
    $res.ContentType = $ContentType
    $res.Headers['X-Content-Type-Options'] = 'nosniff'
    $res.Headers['Cache-Control'] = 'no-store'
    $res.Headers['Referrer-Policy'] = 'no-referrer'
    if ($ContentType -like 'text/html*') { $res.Headers['Content-Security-Policy'] = $Csp }
    $res.ContentLength64 = $Bytes.Length
    $res.OutputStream.Write($Bytes, 0, $Bytes.Length)
}

function Send-Json {
    param($Ctx, $Object, [int]$Status = 200)
    Send-Bytes -Ctx $Ctx -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-HubJson $Object -Compress))) -ContentType 'application/json; charset=utf-8' -Status $Status
}

function Send-Text {
    param($Ctx, [string]$Text, [string]$ContentType = 'text/plain; charset=utf-8', [int]$Status = 200)
    Send-Bytes -Ctx $Ctx -Bytes ([Text.Encoding]::UTF8.GetBytes($Text)) -ContentType $ContentType -Status $Status
}

function Read-Body {
    param($Ctx)
    if (-not $Ctx.Request.HasEntityBody) { return [pscustomobject]@{} }
    $reader = New-Object IO.StreamReader($Ctx.Request.InputStream, [Text.Encoding]::UTF8)
    try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if (-not $text.Trim()) { return [pscustomobject]@{} }
    return ($text | ConvertFrom-Json)
}

function Test-RequestAllowed {
    # Chống DNS rebinding (Host phải là 127.0.0.1/localhost) và trang khác gọi API (Origin + token).
    param($Ctx, [bool]$NeedToken)
    $req = $Ctx.Request
    $hostHeader = [string]$req.Headers['Host']
    if ($hostHeader -ne "127.0.0.1:$Port" -and $hostHeader -ne "localhost:$Port") { return $false }
    $origin = [string]$req.Headers['Origin']
    if ($origin -and $origin -ne "http://127.0.0.1:$Port" -and $origin -ne "http://localhost:$Port") { return $false }
    if ($NeedToken) {
        $tok = [string]$req.Headers['X-Tram-Token']
        if (-not $tok -or $tok.Length -ne $Token.Length) { return $false }
        $diff = 0
        for ($i = 0; $i -lt $tok.Length; $i++) { $diff = $diff -bor ([int][char]$tok[$i] -bxor [int][char]$Token[$i]) }
        if ($diff -ne 0) { return $false }
    }
    return $true
}

function Send-Static {
    param($Ctx, [string]$RelPath)
    if (-not $RelPath -or $RelPath -eq '/') { $RelPath = 'index.html' }
    $rel = [Uri]::UnescapeDataString($RelPath.TrimStart('/')).Replace('/', '\')
    $full = [IO.Path]::GetFullPath((Join-Path $WebDir $rel))
    if (-not (Test-PathInside -Path $full -Root $WebDir) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
        Send-Text -Ctx $Ctx -Text 'Không tìm thấy.' -Status 404; return
    }
    $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
    $type = $MimeTypes[$ext]; if (-not $type) { $type = 'application/octet-stream' }
    Send-Bytes -Ctx $Ctx -Bytes ([IO.File]::ReadAllBytes($full)) -ContentType $type
}

function ConvertTo-ToolSummary {
    param($Tool)
    $copy = [ordered]@{}
    foreach ($k in $Tool.Keys) { $copy[$k] = $Tool[$k] }
    return $copy
}

function Get-RepoDoc {
    # Chỉ cho đọc các file .md trong docs\ và README.md ở gốc.
    param([string]$Name)
    if ($Name -eq 'readme') { $path = Join-Path $RootDir 'README.md' }
    else {
        if ($Name -notmatch '^[A-Za-z0-9_-]+$') { throw 'Tên tài liệu không hợp lệ.' }
        $path = Join-Path $RootDir ("docs\$Name.md")
    }
    if (-not (Test-Path -LiteralPath $path)) { throw "Chưa có tài liệu '$Name'." }
    return [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
}

# ------------------------------------------------------------------ định tuyến API
function Invoke-Api {
    param($Ctx, [string]$Method, [string]$Path)
    $q = $Ctx.Request.QueryString
    switch ("$Method $Path") {
        'GET /api/ping' { $State.LastSeen = Get-Date; $State.Connected = $true; return @{ ok = $true; version = $HubVersion } }
        'GET /api/state' {
            return [ordered]@{
                hub        = [ordered]@{
                    version = $HubVersion; root = $RootDir; toolsDir = $ToolsDir; computer = $env:COMPUTERNAME; user = $env:USERNAME
                    isAdmin = (Test-IsAdmin); startedAt = (Get-IsoTime $State.StartedAt); browser = $State.Browser; settings = $State.Settings
                }
                categories = $State.Categories
                tools      = @($State.Catalog | ForEach-Object { ConvertTo-ToolSummary $_ })
            }
        }
        'POST /api/reload' { Update-Catalog; return @{ ok = $true; count = $State.Catalog.Count } }
        'GET /api/system' {
            if ($q['fresh'] -eq '1') { $script:CheckCache.Remove('system'); $script:CheckCache.Remove('winget') }
            return (Get-SystemSummary)
        }
        'GET /api/deps' {
            $tool = Get-ToolById $q['id']
            return @{ id = $tool.id; items = @(Get-ToolRequirements -Tool $tool -Fresh:($q['fresh'] -eq '1')) }
        }
        'GET /api/deps-all' {
            $all = [ordered]@{}
            foreach ($t in $State.Catalog) { if (@($t.requires).Count) { $all[$t.id] = @(Get-ToolRequirements -Tool $t -Fresh:($q['fresh'] -eq '1')) } }
            return $all
        }
        'GET /api/probes' { $tool = Get-ToolById $q['id']; return @{ id = $tool.id; items = @(Get-ToolProbes -Tool $tool) } }
        'GET /api/outputs' {
            if ($q['id']) { $tool = Get-ToolById $q['id']; return @{ items = @(Get-ToolOutputs -Tool $tool) } }
            $all = New-Object System.Collections.ArrayList
            foreach ($t in $State.Catalog) { foreach ($o in @(Get-ToolOutputs -Tool $t -Limit 15)) { [void]$all.Add($o) } }
            return @{ items = @($all | Sort-Object { $_.modified } -Descending | Select-Object -First 80) }
        }
        'GET /api/result' {
            # File kết quả JSON (chuẩn của trạm) của công cụ: chỉ đọc file đang được liệt kê là kết quả có ketQua.
            $tool = Get-ToolById $q['id']
            $path = [string]$q['path']
            if (-not @(Get-ToolOutputs -Tool $tool -Limit 1000 | Where-Object { $_.ketQua -and $_.path -eq $path }).Count) {
                throw 'File này không phải kết quả JSON của công cụ (có thể đã bị xoá hoặc đổi tên).'
            }
            return (Read-RunResult -Path $path)
        }
        'POST /api/result/reveal' {
            # Mở Explorer tới file, thư mục mà kết quả ghi (mục tep); chỉ chọn sẵn, không chạy file.
            $b = Read-Body $Ctx
            $tool = Get-ToolById ([string](Get-Prop $b 'toolId' ''))
            $path = [string](Get-Prop $b 'path' '')
            if (-not @(Get-ToolOutputs -Tool $tool -Limit 1000 | Where-Object { $_.ketQua -and $_.path -eq $path }).Count) { throw 'File này không phải kết quả JSON của công cụ.' }
            $files = @((Read-RunResult -Path $path).tep)
            $i = [int](Get-Prop $b 'index' -1)
            if ($i -lt 0 -or $i -ge $files.Count) { throw 'Không có mục này trong kết quả.' }
            Open-HubPath -Path $files[$i].duongDan -Reveal
            return @{ ok = $true }
        }
        'GET /api/server' {
            $tool = Get-ToolById $q['id']
            $items = [ordered]@{}
            foreach ($a in @($tool.actions | Where-Object { $_.webServer })) { $items[$a.id] = Get-ToolServer -Tool $tool -Action $a }
            return @{ id = $tool.id; items = $items }
        }
        'POST /api/server/open' {
            $b = Read-Body $Ctx
            $tool = Get-ToolById ([string](Get-Prop $b 'toolId' ''))
            $action = Get-ActionById -Tool $tool -Id ([string](Get-Prop $b 'actionId' ''))
            $port = Open-ToolServer -Tool $tool -Action $action
            Write-HubLog "Mở lại giao diện đang chạy: $($tool.name) (cổng $port)"
            return @{ ok = $true; port = $port }
        }
        'POST /api/server/stop' {
            $b = Read-Body $Ctx
            $tool = Get-ToolById ([string](Get-Prop $b 'toolId' ''))
            $action = Get-ActionById -Tool $tool -Id ([string](Get-Prop $b 'actionId' ''))
            $r = Stop-ToolServer -Tool $tool -Action $action
            Write-HubLog "Tắt giao diện: $($tool.name): $($r.message)"
            return $r
        }
        'GET /api/docs' {
            $tool = Get-ToolById $q['id']
            if (-not $tool.hasDocs) { throw 'Công cụ này chưa có hướng dẫn.' }
            $p = Expand-HubPath -Path $tool.docs -BaseDir $tool.dir
            return @{ id = $tool.id; name = $tool.docs; markdown = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) }
        }
        'GET /api/doc' { return @{ name = $q['name']; markdown = (Get-RepoDoc $q['name']) } }
        'GET /api/history' { Update-ToolJobs -HistoryPath $HistoryFile; return @{ items = @(Get-RunHistory -HistoryPath $HistoryFile -RestoreLogPath $RestoreLogFile) } }
        'POST /api/history/delete' {
            $b = Read-Body $Ctx
            if ([bool](Get-Prop $b 'all' $false)) {
                $n = Remove-RunHistory -HistoryPath $HistoryFile -All
                Get-ChildItem -LiteralPath $SnapshotDir -Filter 'TrangThai_*.json' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $RestoreLogFile -Force -ErrorAction SilentlyContinue
            } else {
                $times = @(@(Get-Prop $b 'times' @()) | ForEach-Object { [string]$_ } | Where-Object { $_ })
                if (-not $times.Count) { throw 'Chưa chọn lần chạy nào để xoá.' }
                $n = Remove-RunHistory -HistoryPath $HistoryFile -Times $times
                foreach ($t in $times) { Remove-Item -LiteralPath (Join-Path $SnapshotDir (Get-SnapshotFileName $t)) -Force -ErrorAction SilentlyContinue }
            }
            Write-HubLog "Xoá lịch sử: $n lần chạy"
            return @{ removed = $n }
        }
        'GET /api/snapshot' {
            # So trạng thái ghi lúc trước khi chạy (dịch vụ, registry công cụ khai báo) với hiện tại.
            $time = [string]$q['time']
            $path = Join-Path $SnapshotDir (Get-SnapshotFileName $time)
            if (-not $time -or -not (Test-Path -LiteralPath $path)) { throw 'Lần chạy này không có trạng thái đã ghi (hoặc đã xoá).' }
            $snap = Read-JsonFile $path
            return [ordered]@{ time = $time; toolName = [string]$snap.toolName; actionLabel = [string]$snap.actionLabel; items = @(Compare-RunSnapshot -Path $path) }
        }
        'POST /api/snapshot/restore' {
            # Mở cửa sổ Admin trả các mục về trạng thái trước khi chạy (hub\safety\TraLaiTrangThai.ps1).
            $b = Read-Body $Ctx
            $time = [string](Get-Prop $b 'time' '')
            $name = Get-SnapshotFileName $time
            $path = Join-Path $SnapshotDir $name
            if (-not $time -or -not (Test-SnapshotFileName $name) -or -not (Test-Path -LiteralPath $path)) { throw 'Lần chạy này không có trạng thái đã ghi (hoặc đã xoá).' }
            $snap = Read-JsonFile $path
            $tool = $State.Catalog | Where-Object { $_.id -eq [string]$snap.toolId } | Select-Object -First 1
            $fixTool = [ordered]@{ id = [string]$snap.toolId; name = $(if ($tool) { $tool.name } else { [string]$snap.toolName }); dir = $SafetyDir }
            $fixAction = [ordered]@{ id = 'tra-lai-trang-thai'; label = "Trả lại trạng thái trước lần chạy $([string]$snap.actionLabel)"; type = 'console'; file = 'TraLaiTrangThai.ps1'; admin = $true; keepOpen = $false }
            Write-HubLog "Trả lại trạng thái: $($fixTool.name) > $($snap.actionLabel) (Admin)"
            $argv = @([pscustomobject]@{ Value = '-Snapshot'; IsFlag = $true }, [pscustomobject]@{ Value = $path; IsFlag = $false })
            return (Start-ToolAction -Tool $fixTool -Action $fixAction -Arguments $argv -HistoryPath $HistoryFile)
        }
        'POST /api/restore-ui' {
            # Khôi phục hệ thống của Windows (rstrui.exe tự hỏi quyền Admin).
            Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\rstrui.exe')
            return @{ ok = $true }
        }
        'POST /api/restore/enable' {
            # Cửa sổ Admin bật Bảo vệ hệ thống cho ổ Windows rồi tạo điểm khôi phục đầu tiên.
            $script:CheckCache.Remove('system')
            $fixTool = [ordered]@{ id = 'tram-tool'; name = 'Trạm Tool'; dir = $SafetyDir }
            $fixAction = [ordered]@{ id = 'bat-bao-ve-he-thong'; label = 'Bật Bảo vệ hệ thống'; type = 'console'; file = 'BatBaoVeHeThong.ps1'; admin = $true; keepOpen = $false }
            Write-HubLog 'Bật Bảo vệ hệ thống (Admin)'
            return (Start-ToolAction -Tool $fixTool -Action $fixAction -HistoryPath $HistoryFile)
        }
        'POST /api/winget/fix' {
            Clear-CheckCache
            $fixTool = [ordered]@{ id = 'tram-tool'; name = 'Trạm Tool'; dir = (Join-Path $HubDir 'fixes') }
            $fixAction = [ordered]@{ id = 'sua-winget'; label = 'Sửa winget'; type = 'console'; file = 'Sua-Winget.ps1'; admin = $false; keepOpen = $false }
            Write-HubLog 'Sửa winget'
            return (Start-ToolAction -Tool $fixTool -Action $fixAction -HistoryPath $HistoryFile)
        }
        'GET /api/update' {
            # Trạng thái kho git của trạm; fetch=1 thì hỏi kho trước (cần mạng, không hỏi mật khẩu, tối đa 25 giây).
            return (Get-RepoUpdateInfo -RootDir $RootDir -Fetch:($q['fetch'] -eq '1'))
        }
        'POST /api/update/run' {
            # Cửa sổ cập nhật (quyền thường): fast-forward, không ghi đè file đang sửa; hỏi lại trước khi kéo.
            $fixTool = [ordered]@{ id = 'tram-tool'; name = 'Trạm Tool'; dir = (Join-Path $HubDir 'fixes') }
            $fixAction = [ordered]@{ id = 'cap-nhat'; label = 'Cập nhật trạm và công cụ'; type = 'console'; file = 'CapNhat-TramTool.ps1'; admin = $false; keepOpen = $false }
            Write-HubLog 'Cập nhật trạm và công cụ (git)'
            return (Start-ToolAction -Tool $fixTool -Action $fixAction -HistoryPath $HistoryFile)
        }
        'GET /api/jobs' { Update-ToolJobs -HistoryPath $HistoryFile; return @{ items = @(Get-ToolJobs); now = (Get-IsoTime) } }
        'POST /api/jobs/dismiss' {
            $b = Read-Body $Ctx
            $ids = @(@(Get-Prop $b 'ids' @()) | ForEach-Object { [string]$_ })
            return @{ removed = (Remove-ToolJobs -Ids $ids -AllFinished:([bool](Get-Prop $b 'all' $false))) }
        }
        'POST /api/jobs/focus' { $b = Read-Body $Ctx; Show-ToolJobWindow -Id ([string](Get-Prop $b 'id' '')); return @{ ok = $true } }
        'POST /api/run' {
            $b = Read-Body $Ctx
            $tool = Get-ToolById ([string](Get-Prop $b 'toolId' ''))
            $action = Get-ActionById -Tool $tool -Id ([string](Get-Prop $b 'actionId' ''))
            $values = Get-Prop $b 'values' $null
            if ($action.webServer) {
                # Giao diện web của công cụ đang chạy: mở lại trang đó, không mở thêm máy chủ thứ hai.
                $srv = Get-ToolServer -Tool $tool -Action $action
                if ($srv.running) {
                    $port = Open-ToolServer -Tool $tool -Action $action
                    Write-HubLog "Mở lại giao diện đang chạy: $($tool.name) (cổng $port)"
                    return @{ ok = $true; reopened = $true; port = $port; message = "Giao diện đang chạy (cổng $port), đã mở lại trong trình duyệt." }
                }
            }
            $argv = Resolve-ActionArguments -Action $action -Values $values
            # Lan can: điểm khôi phục theo lựa chọn ở hộp xác nhận (mặc định theo Cài đặt); ghi trạng thái trước khi
            # chạy với mọi action đổi máy. Chạy thử thì không làm cả hai.
            $dry = Test-DryRunSelected -Action $action -Values $values
            $safety = @{
                RestorePoint = ($action.restorePoint -and -not $dry -and [bool](Get-Prop $b 'restorePoint' $State.Settings.restorePoint))
                Snapshot     = ($action.risk -ne 'read-only' -and -not $dry)
                ScriptDir    = $SafetyDir; Log = $RestoreLogFile; SnapshotDir = $SnapshotDir
            }
            Write-HubLog "Chạy: $($tool.name) > $($action.label)$(if ($action.admin) { ' (Admin)' })$(if ($safety.RestorePoint) { ', tạo điểm khôi phục' })"
            return (Start-ToolAction -Tool $tool -Action $action -Arguments $argv -HistoryPath $HistoryFile -Values $values -Safety $safety -ProgressDir $ProgressDir)
        }
        'POST /api/pick' {
            $b = Read-Body $Ctx
            $tool = Get-ToolById ([string](Get-Prop $b 'toolId' ''))
            $action = Get-ActionById -Tool $tool -Id ([string](Get-Prop $b 'actionId' ''))
            $argId = [string](Get-Prop $b 'argId' '')
            $spec = @($action.args | Where-Object { $_.id -eq $argId -and $_.type -in 'file', 'folder' }) | Select-Object -First 1
            if (-not $spec) { throw 'Tham số này không phải chọn file hay thư mục.' }
            $initial = switch ($spec.startIn) {
                'tool' { $tool.dir }
                'documents' { [Environment]::GetFolderPath('MyDocuments') }
                default { [Environment]::GetFolderPath('Desktop') }
            }
            $paths = Show-FilePicker -Title $spec.label -Filter $spec.filter -Multiple:$spec.multiple -Folder:($spec.type -eq 'folder') -InitialDir $initial
            $State.LastSeen = Get-Date
            return @{ paths = @($paths) }
        }
        'POST /api/open' {
            $b = Read-Body $Ctx
            $tool = Get-ToolById ([string](Get-Prop $b 'toolId' ''))
            $target = [string](Get-Prop $b 'target' 'folder')
            switch ($target) {
                'folder' { Open-HubPath -Path $tool.dir -Reveal }
                'docs' {
                    # hasDocs chỉ đúng khi file hướng dẫn tồn tại và nằm trong thư mục công cụ (kiểm lúc đọc tool.json).
                    if (-not $tool.hasDocs) { throw 'Công cụ này không có file hướng dẫn.' }
                    Open-HubPath -Path (Expand-HubPath -Path $tool.docs -BaseDir $tool.dir)
                }
                { $_ -in 'output', 'output-folder' } {
                    $path = [string](Get-Prop $b 'path' '')
                    $known = @(Get-ToolOutputs -Tool $tool -Limit 500 | Where-Object { $_.path -eq $path })
                    if (-not $known.Count) { throw 'File này không thuộc kết quả của công cụ.' }
                    Open-HubPath -Path $path -Reveal:($target -eq 'output-folder')
                }
                default { throw "Không hiểu yêu cầu mở '$target'." }
            }
            return @{ ok = $true }
        }
        'POST /api/outputs/delete' {
            # Chỉ xoá đúng file/thư mục đang được liệt kê là kết quả của công cụ, và chuyển vào Thùng rác.
            $b = Read-Body $Ctx
            $items = @(Get-Prop $b 'items' @())
            if (-not $items.Count) { throw 'Chưa chọn mục nào để xoá.' }
            if ($items.Count -gt 200) { throw 'Mỗi lần xoá tối đa 200 mục.' }
            $known = @{}
            $results = New-Object System.Collections.ArrayList
            foreach ($it in $items) {
                $toolId = [string](Get-Prop $it 'toolId' '')
                $path = [string](Get-Prop $it 'path' '')
                $r = [ordered]@{ toolId = $toolId; path = $path; status = 'error'; message = '' }
                try {
                    if (-not $known.ContainsKey($toolId)) {
                        $map = @{}
                        foreach ($o in @(Get-ToolOutputs -Tool (Get-ToolById $toolId) -Limit 1000)) { $map[$o.path] = $o }
                        $known[$toolId] = $map
                    }
                    $o = $known[$toolId][$path]
                    if (-not $o) { throw 'Không thuộc kết quả của công cụ (có thể đã bị xoá hoặc đổi tên).' }
                    if (-not $o.deletable) { throw 'Kết quả này không xoá từ trạm được.' }
                    $r.status = Remove-ToRecycleBin -Path $path
                    if ($r.status -eq 'cancelled') { $r.message = 'Đã huỷ ở hộp thoại của Windows.' }
                } catch { $r.message = $_.Exception.Message }
                [void]$results.Add($r)
            }
            $deleted = @($results | Where-Object { $_.status -eq 'deleted' }).Count
            Write-HubLog "Xoá kết quả: $deleted/$($items.Count) mục vào Thùng rác"
            return @{ deleted = $deleted; results = @($results) }
        }
        'POST /api/fix' {
            $b = Read-Body $Ctx
            $tool = Get-ToolById ([string](Get-Prop $b 'toolId' ''))
            $req = @($tool.requires | Where-Object { (Get-Prop $_ 'id' (Get-Prop $_ 'type' '')) -eq (Get-Prop $b 'reqId' '') }) | Select-Object -First 1
            if (-not $req) { throw 'Không tìm thấy yêu cầu này.' }
            $fix = Get-Prop $req 'fix' $null
            if (-not $fix) { throw 'Yêu cầu này không có cách sửa tự động.' }
            $actionId = [string](Get-Prop $fix 'action' '')
            if ($actionId) {
                $action = Get-ActionById -Tool $tool -Id $actionId
                return (Start-ToolAction -Tool $tool -Action $action -Arguments (Resolve-ActionArguments -Action $action -Values $null) -HistoryPath $HistoryFile)
            }
            $hubScript = [string](Get-Prop $fix 'hubScript' '')
            if ($hubScript) {
                # Script cài đặt dùng chung của trạm, chỉ lấy trong hub\fixes.
                if ($hubScript -notmatch '^[A-Za-z0-9._-]+\.ps1$') { throw 'Tên script cài đặt không hợp lệ.' }
                $fixTool = [ordered]@{ id = $tool.id; name = $tool.name; dir = (Join-Path $HubDir 'fixes') }
                $fixAction = [ordered]@{
                    id = "fix-$(Get-Prop $req 'id' 'yeu-cau')"; label = [string](Get-Prop $fix 'label' 'Cài đặt'); type = 'console'; file = $hubScript
                    admin = [bool](Get-Prop $fix 'admin' $false); keepOpen = $true
                }
                Write-HubLog "Cài: $($tool.name) > $hubScript$(if ($fixAction.admin) { ' (Admin)' })"
                return (Start-ToolAction -Tool $fixTool -Action $fixAction -HistoryPath $HistoryFile)
            }
            Start-RequirementFix -Fix $fix
            return @{ ok = $true; message = 'Đã mở cửa sổ cài đặt. Cài xong bấm "Kiểm tra lại".' }
        }
        'POST /api/pack' {
            $b = Read-Body $Ctx
            $tool = Get-ToolById ([string](Get-Prop $b 'toolId' ''))
            $r = New-ToolPackage -Tool $tool
            Open-HubPath -Path $r.path -Reveal
            return $r
        }
        'POST /api/scaffold' {
            $b = Read-Body $Ctx
            $tool = Get-ToolById ([string](Get-Prop $b 'toolId' ''))
            $path = New-ToolManifestFile -Tool $tool
            Update-Catalog
            Open-HubPath -Path $path -Reveal
            return @{ ok = $true; path = $path }
        }
        'GET /api/settings' { return $State.Settings }
        'POST /api/settings' {
            # Chỉ đổi những mục có trong yêu cầu.
            $b = Read-Body $Ctx
            $s = $State.Settings
            $browser = [string](Get-Prop $b 'browser' $s.browser)
            if (@('auto', 'brave', 'edge', 'chrome', 'default') -notcontains $browser) { throw 'Trình duyệt không hợp lệ.' }
            $minutes = [int](Get-Prop $b 'autoExitMinutes' $s.autoExitMinutes)
            if ($minutes -lt 0 -or $minutes -gt 1440) { throw 'Số phút tự tắt phải từ 0 đến 1440.' }
            $theme = [string](Get-Prop $b 'theme' $s.theme)
            if (@('system', 'light', 'dark') -notcontains $theme) { throw 'Giao diện không hợp lệ.' }
            $pins = @($s.pins)
            if ($b.PSObject.Properties['pins']) {
                # Không dùng Get-Prop: hàm trả mảng rỗng thành $null, bỏ ghim hết sẽ không lưu được.
                $pins = @(@($b.pins) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ } |
                        Where-Object { $_ -match '^[a-z0-9][a-z0-9-]{0,63}$' } | Select-Object -Unique -First 100)
            }
            $s.browser = $browser; $s.autoExitMinutes = $minutes; $s.theme = $theme; $s.pins = $pins
            $s.simple = [bool](Get-Prop $b 'simple' $s.simple)
            $s.restorePoint = [bool](Get-Prop $b 'restorePoint' $s.restorePoint)
            Write-JsonFile -Path $SettingsFile -InputObject $s
            return $s
        }
        'POST /api/shortcut' { return @{ ok = $true; path = (New-DesktopShortcut -RootDir $RootDir -HubDir $HubDir) } }
        'POST /api/open-root' { Open-HubPath -Path $RootDir -Reveal; return @{ ok = $true } }
        'POST /api/shutdown' { $State.Stop = $true; return @{ ok = $true } }
        default { throw [System.Collections.Generic.KeyNotFoundException]::new("Không có API $Method $Path") }
    }
}

function Invoke-Request {
    param($Ctx)
    $req = $Ctx.Request
    $path = $req.Url.AbsolutePath
    $isApi = $path.StartsWith('/api/')
    if (-not (Test-RequestAllowed -Ctx $Ctx -NeedToken $isApi)) {
        Send-Json -Ctx $Ctx -Object @{ error = 'Từ chối: yêu cầu không đến từ giao diện Trạm Tool.' } -Status 403
        return
    }
    if (-not $isApi) {
        if ($req.HttpMethod -ne 'GET') { Send-Text -Ctx $Ctx -Text 'Method not allowed' -Status 405; return }
        Send-Static -Ctx $Ctx -RelPath $path
        return
    }
    $State.LastSeen = Get-Date
    try {
        $result = Invoke-Api -Ctx $Ctx -Method $req.HttpMethod -Path $path
        Send-Json -Ctx $Ctx -Object $result
    } catch [System.Collections.Generic.KeyNotFoundException] {
        Send-Json -Ctx $Ctx -Object @{ error = $_.Exception.Message } -Status 404
    } catch {
        Write-HubLog "$($req.HttpMethod) $path lỗi: $($_.Exception.Message)" 'error'
        Send-Json -Ctx $Ctx -Object @{ error = $_.Exception.Message } -Status 500
    }
}

# ------------------------------------------------------------------ vòng lặp chính
try {
    if (-not $NoBrowser) {
        $pref = if ($Browser) { $Browser } else { $State.Settings.browser }
        $State.Browser = Open-HubUi -Url "$BaseUrl/#t=$Token" -Preference $pref
        Write-HubLog "Đã mở giao diện bằng: $($State.Browser)"
    }
    $lastJobCheck = Get-Date
    while ($Listener.IsListening -and -not $State.Stop) {
        $task = $Listener.GetContextAsync()
        while (-not $task.AsyncWaitHandle.WaitOne(1000)) {
            # Ghi kết quả của cửa sổ công cụ vừa đóng kể cả khi không mở giao diện.
            if (((Get-Date) - $lastJobCheck).TotalSeconds -ge 3) {
                $lastJobCheck = Get-Date
                try { Update-ToolJobs -HistoryPath $HistoryFile } catch { Write-HubLog "Lỗi theo dõi công cụ: $($_.Exception.Message)" 'warn' }
            }
            $limit = [int]$State.Settings.autoExitMinutes
            $idle = ((Get-Date) - $State.LastSeen).TotalMinutes
            # Còn công cụ đang chạy thì chờ, để ghi được kết quả khi cửa sổ đóng.
            if ($limit -gt 0 -and $idle -ge $limit -and -not (Test-ToolJobsRunning)) {
                Write-HubLog "Không còn cửa sổ giao diện nào trong $limit phút, tự tắt trạm." 'warn'
                $State.Stop = $true
                break
            }
        }
        if ($State.Stop) { break }
        $ctx = $task.GetAwaiter().GetResult()
        try { Invoke-Request -Ctx $ctx }
        catch { Write-HubLog "Lỗi xử lý yêu cầu: $($_.Exception.Message)" 'error' }
        finally { try { $ctx.Response.Close() } catch { } }
    }
} finally {
    try { $Listener.Stop(); $Listener.Close() } catch { }
    try {
        $rt = Read-JsonFile $RuntimeFile
        if ([int]$rt.pid -eq $PID) { Remove-Item -LiteralPath $RuntimeFile -Force -ErrorAction SilentlyContinue }
    } catch { }
    Write-HubLog 'Trạm Tool đã tắt.'
}
