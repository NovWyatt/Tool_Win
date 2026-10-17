<#
  Đồng bộ phiên Claude giữa các tài khoản.

  Claude Desktop lưu danh sách phiên tab Code riêng cho từng tài khoản đăng nhập
  (%APPDATA%\Claude\claude-code-sessions\<mã tài khoản>\<mã tổ chức>\local_*.json), còn nội dung hội thoại nằm chung
  trong ~\.claude\projects\<thư mục dự án>\<mã phiên>.jsonl. Đăng nhập tài khoản khác thì thanh bên trống dù nội dung
  vẫn còn trên máy. Công cụ chép các mục danh sách sang tài khoản đang đăng nhập để mở lại và làm tiếp được.

  Chế độ (-Mode):
    kiem-tra  chỉ đọc: tài khoản đang đăng nhập, các tài khoản từng dùng trên máy và số phiên của từng tài khoản, gói
              sao lưu có sẵn, số phiên tài khoản đang dùng chưa có.
    sao-luu   gói danh sách phiên và nội dung hội thoại của tài khoản đang đăng nhập vào du-lieu\Goi_<tài khoản>_<giờ>
              (hoặc -Den <thư mục>) để mang sang máy khác. Cùng một máy thì không bắt buộc: Đồng bộ đọc thẳng danh sách
              của các tài khoản khác trên máy.
    dong-bo   thêm vào tài khoản đang đăng nhập các phiên nó chưa có, lấy từ các tài khoản khác trên máy và các gói sao
              lưu (trong du-lieu, hoặc -Tu <gói hay thư mục chứa gói>). Phiên đã xoá ở tài khoản này thì không thêm lại.
              Claude Desktop phải tắt (-DongClaude: tự đóng). Mở lại Claude là thấy các phiên ở thanh bên.
    hoan-tac  bỏ các mục lần đồng bộ gần nhất đã thêm, trả lại các mục đã thay; mục nào đã dùng tiếp sau khi đồng bộ
              thì giữ.
  Không có -Mode: menu (bấm đúp DONG_BO_CLAUDE.bat).
  -ChayThu: chỉ in việc sẽ làm, không ghi gì. -KhongDung: không chờ Enter khi xong.
  Mỗi lần chạy ghi ket_qua\KetQua_ClaudeDongBo_<máy>_<giờ>.json (chuẩn tramtool.ketqua/1) cho Trạm Tool.
  Mã thoát: 0 xong (kể cả khi không có gì để làm), 1 lỗi, 2 chưa làm (chưa cài Claude Desktop, chưa đăng nhập, Claude
  Desktop đang mở, đã huỷ, thiếu chỗ trống), 3 làm được một phần.
#>
param(
    [string]$Mode = '',
    [string]$Tu = '',
    [string]$Den = '',
    [switch]$DongClaude,
    [switch]$ChayThu,
    [switch]$KhongDung
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:Version = '1.0'
# Bài thử trỏ các biến CDB_* vào thư mục tạm để không đụng dữ liệu Claude thật.
$script:DataDir = if ($env:CDB_DU_LIEU) { $env:CDB_DU_LIEU } else { Join-Path $PSScriptRoot 'du-lieu' }
$script:ResultDir = if ($env:CDB_KET_QUA) { $env:CDB_KET_QUA } else { Join-Path $PSScriptRoot 'ket_qua' }
$script:UserDir = $(if ($env:CDB_NGUOI_DUNG) { $env:CDB_NGUOI_DUNG } else { $env:USERPROFILE }).TrimEnd('\')
$script:ProjectsDir = Join-Path $script:UserDir '.claude\projects'
$script:ClaudeJson = Join-Path $script:UserDir '.claude.json'
$script:UndoDir = Join-Path $script:DataDir 'HoanTac'
$script:LabelFile = Join-Path $script:DataDir 'tai-khoan.json'
# Tiến trình Claude Desktop nhận theo đường dẫn file chạy (bản cài thường hoặc Microsoft Store); claude.exe của Claude
# Code chạy trong cửa sổ lệnh không bị đụng tới.
$script:DesktopExe = if ($env:CDB_MAU_CLAUDE) { $env:CDB_MAU_CLAUDE } else { '(?i)\\AnthropicClaude\\|\\WindowsApps\\Claude_|\\Packages\\Claude_' }
$script:GuidMau = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
$script:GoiChuan = 'tramtool.claudedongbo.goi/1'
$script:NhatKyChuan = 'tramtool.claudedongbo.hoantac/1'
# Trường gắn với tài khoản cũ: kết nối claude.ai (connector) của tài khoản đó, phiên Remote Control trên máy chủ.
$script:AccountFields = @('remoteMcpServersConfig', 'bridgeSessionIds')
$script:Modes = [ordered]@{
    'kiem-tra' = @{ Label = 'Kiểm tra phiên của các tài khoản (chỉ đọc)' }
    'sao-luu'  = @{ Label = 'Sao lưu phiên của tài khoản đang đăng nhập' }
    'dong-bo'  = @{ Label = 'Đồng bộ phiên vào tài khoản đang đăng nhập' }
    'hoan-tac' = @{ Label = 'Hoàn tác lần đồng bộ gần nhất' }
}
$script:Levels = @{ 'loi' = 0; 'canh-bao' = 1; 'thong-tin' = 2; 'ok' = 3 }
$script:Findings = New-Object System.Collections.ArrayList
$script:Files = New-Object System.Collections.ArrayList
$script:Labels = @{}

# ---------------------------------------------------------------- in ra, hỏi
function Write-Head { param([string]$Text) Write-Host ''; Write-Host ("== $Text " + ('=' * [Math]::Max(3, 68 - $Text.Length))) -ForegroundColor Cyan }
function Write-Line { param([string]$Text) Write-Host "  $Text" }
function Write-Sub { param([string]$Text) Write-Host "       $Text" -ForegroundColor Gray }
function Write-Ok { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Write-Bad { param([string]$Text) Write-Host "  [X]  $Text" -ForegroundColor Red }
function Write-Info { param([string]$Text) Write-Host "  [i]  $Text" -ForegroundColor Gray }
function Write-Plan { param([string]$Text) Write-Host "   ->  $Text" -ForegroundColor White }

function Read-Text {
    param([string]$Prompt, [string]$Default = '')
    if ([Console]::IsInputRedirected) { return $Default }
    $a = ([string](Read-Host "  $Prompt")).Trim()
    if (-not $a) { return $Default }
    return $a
}

function Read-YesNo {
    # Không có bàn phím (chạy tự động) thì trả mặc định thay vì treo.
    param([string]$Question, [bool]$Default = $false)
    if ([Console]::IsInputRedirected) { return $Default }
    $hint = if ($Default) { '[C/k]' } else { '[c/K]' }
    while ($true) {
        $a = ([string](Read-Host "  $Question $hint")).Trim().ToLowerInvariant()
        if (-not $a) { return $Default }
        if ($a -in 'c', 'co', 'có', 'y', 'yes') { return $true }
        if ($a -in 'k', 'khong', 'không', 'n', 'no') { return $false }
        Write-Host '  Gõ C (có) hoặc K (không).' -ForegroundColor Yellow
    }
}

function Wait-Close {
    param([string]$Text = 'Bấm Enter để đóng cửa sổ')
    if ($KhongDung -or [Console]::IsInputRedirected) { return }
    Write-Host ''
    [void](Read-Host "  $Text")
}

# ---------------------------------------------------------------- file, JSON
function Get-Serializer {
    # Mục danh sách phiên đọc thành Dictionary và ghi lại bằng cùng bộ đọc: giữ đủ mọi trường kể cả trường công cụ chưa
    # biết, không vướng giới hạn độ sâu của ConvertTo-Json.
    if (-not $script:Ser) {
        Add-Type -AssemblyName System.Web.Extensions
        $script:Ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $script:Ser.MaxJsonLength = [int]::MaxValue
        $script:Ser.RecursionLimit = 1000
    }
    return $script:Ser
}

function Read-Dict {
    param([string]$Path)
    try { $o = (Get-Serializer).DeserializeObject([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)) } catch { return $null }
    if ($o -is [System.Collections.IDictionary]) { return $o }
    return $null
}

function Copy-Dict { param($Dict) $s = Get-Serializer; return $s.DeserializeObject($s.Serialize($Dict)) }

function Read-Obj {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { return $null }
}

function Write-TextAtomic {
    # Ghi ra file tạm rồi đổi tên: đứt giữa chừng thì file cũ vẫn nguyên.
    param([string]$Path, [string]$Text)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = "$Path.cdb-tmp"
    [IO.File]::WriteAllText($tmp, $Text, (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Write-Dict { param([string]$Path, $Dict) Write-TextAtomic $Path ((Get-Serializer).Serialize($Dict)) }
function Write-Obj { param([string]$Path, $Obj) Write-TextAtomic $Path ($Obj | ConvertTo-Json -Depth 10) }

function Get-Hash {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    return ''
}

function Get-Num { param($Value) try { return [long]$Value } catch { return [long]0 } }

function Get-DirSize {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [long]0 }
    $n = [long]0
    foreach ($f in @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)) { $n += $f.Length }
    return $n
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f [Math]::Ceiling($Bytes / 1KB)
}

function Format-Time {
    param([long]$Ms)
    if ($Ms -le 0) { return '?' }
    try { return [DateTimeOffset]::FromUnixTimeMilliseconds($Ms).LocalDateTime.ToString('dd/MM/yyyy HH:mm') } catch { return '?' }
}

function Get-FreeName {
    # Đường dẫn chưa có: thêm _2, _3... khi hai lần chạy trùng giây.
    param([string]$Path)
    $p = $Path; $i = 2
    while (Test-Path -LiteralPath $p) { $p = "${Path}_$i"; $i++ }
    return $p
}

function Get-FreeBytes {
    # Chỗ trống của ổ chứa $Path; không đọc được (đường mạng) thì trả -1.
    param([string]$Path)
    try { return (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path)))).AvailableFreeSpace } catch { return [long]-1 }
}

# ---------------------------------------------------------------- Claude Desktop
function Get-ClaudeAppDir {
    # Thư mục dữ liệu Claude Desktop. Bản Microsoft Store có thể lưu trong Packages\Claude_*\LocalCache\Roaming\Claude;
    # lấy nơi có config.json mới nhất.
    if ($env:CDB_CLAUDE_APPDATA) { return $env:CDB_CLAUDE_APPDATA }
    $cands = @(Join-Path $env:APPDATA 'Claude')
    $cands += @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'LocalCache\Roaming\Claude' })
    $best = $null; $t = [datetime]::MinValue
    foreach ($d in $cands) {
        $f = Join-Path $d 'config.json'
        if (Test-Path -LiteralPath $f -PathType Leaf) {
            $w = (Get-Item -LiteralPath $f).LastWriteTimeUtc
            if ($w -gt $t) { $t = $w; $best = $d }
        }
    }
    return $best
}

function Get-ClaudeDesktopProcess {
    @(Get-Process -Name 'claude' -ErrorAction SilentlyContinue | Where-Object {
            $p = $null; try { $p = [string]$_.Path } catch { }
            $p -and $p -match $script:DesktopExe
        })
}

function Confirm-DesktopClosed {
    # Claude Desktop đọc danh sách phiên lúc mở và giữ trong bộ nhớ: phải tắt trước khi ghi, mở lại mới thấy.
    if (-not @(Get-ClaudeDesktopProcess).Count) { return $true }
    Write-Warn 'Claude Desktop đang mở. Phải thoát hẳn Claude (chuột phải biểu tượng Claude ở khay đồng hồ, chọn Quit) trước khi ghi.'
    $close = [bool]$DongClaude
    if (-not $close) { $close = Read-YesNo 'Tự đóng Claude Desktop ngay (mọi cửa sổ Claude, kể cả phiên đang chạy)?' $false }
    if (-not $close) { return $false }
    Get-ClaudeDesktopProcess | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 20 -and @(Get-ClaudeDesktopProcess).Count; $i++) { Start-Sleep -Milliseconds 500 }
    if (@(Get-ClaudeDesktopProcess).Count) { Write-Bad 'Chưa đóng được Claude Desktop.'; return $false }
    Write-Ok 'Đã đóng Claude Desktop.'
    return $true
}

function Get-CurrentAccount {
    # Tài khoản Claude Desktop đang đăng nhập: lastKnownAccountUuid trong config.json. Mã tổ chức: thư mục danh sách phiên
    # của tài khoản đó (ưu tiên tổ chức ghi trong ~\.claude.json, rồi thư mục mới nhất); chưa có thư mục thì lấy từ
    # ~\.claude.json (cùng tài khoản) hoặc remote-control-state.json.
    $cfg = Read-Obj (Join-Path $script:AppDir 'config.json')
    $acct = if ($cfg) { [string]$cfg.lastKnownAccountUuid } else { '' }
    if ($acct -notmatch $script:GuidMau) { return $null }
    $cj = Read-Obj $script:ClaudeJson
    $cjOrg = ''
    if ($cj -and $cj.oauthAccount -and [string]$cj.oauthAccount.accountUuid -eq $acct) { $cjOrg = [string]$cj.oauthAccount.organizationUuid }
    $dirs = @(Get-ChildItem -LiteralPath (Join-Path $script:SessRoot $acct) -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $script:GuidMau } | Sort-Object LastWriteTimeUtc -Descending)
    $org = ''
    if ($cjOrg -and @($dirs | Where-Object { $_.Name -eq $cjOrg }).Count) { $org = $cjOrg }
    elseif ($dirs.Count) { $org = $dirs[0].Name }
    elseif ($cjOrg) { $org = $cjOrg }
    else {
        $rc = Read-Obj (Join-Path $script:AppDir 'remote-control-state.json')
        if ($rc -and $rc.identities) {
            foreach ($k in @($rc.identities.PSObject.Properties | ForEach-Object { $_.Name })) {
                if ($k -match ('^([0-9a-f-]{36}):' + [regex]::Escape($acct) + '$')) { $org = $Matches[1]; break }
            }
        }
    }
    if ($org -notmatch $script:GuidMau) { $org = '' }
    return [pscustomobject]@{ Acct = $acct; Org = $org; Dir = $(if ($org) { Join-Path (Join-Path $script:SessRoot $acct) $org } else { '' }) }
}

function Test-BypassAllowed {
    # Tài khoản đã tự bật chế độ không hỏi quyền (bypass permissions) trong Claude Desktop chưa.
    param([string]$Acct)
    $c = Read-Obj (Join-Path $script:AppDir 'claude_desktop_config.json')
    if (-not $c -or -not $c.preferences -or -not $c.preferences.bypassPermissionsOptInByAccount) { return $false }
    return ($c.preferences.bypassPermissionsOptInByAccount.$Acct -eq $true)
}

function Update-Labels {
    # Email của tài khoản (từ ~\.claude.json) để hiện tên dễ hiểu thay cho mã; chỉ lưu trong du-lieu của công cụ.
    $script:Labels = @{}
    $old = Read-Obj $script:LabelFile
    if ($old) { foreach ($p in $old.PSObject.Properties) { if ($p.Value.email) { $script:Labels[$p.Name] = [string]$p.Value.email } } }
    $cj = Read-Obj $script:ClaudeJson
    if (-not $cj -or -not $cj.oauthAccount) { return }
    $a = [string]$cj.oauthAccount.accountUuid
    $e = [string]$cj.oauthAccount.emailAddress
    if ($a -notmatch $script:GuidMau -or -not $e -or $script:Labels[$a] -eq $e) { return }
    $script:Labels[$a] = $e
    if ($ChayThu) { return }
    $o = [ordered]@{}
    foreach ($k in @($script:Labels.Keys | Sort-Object)) { $o[$k] = [ordered]@{ email = $script:Labels[$k] } }
    try { Write-Obj $script:LabelFile $o } catch { }
}

function Get-Label {
    param([string]$Acct)
    $short = if ($Acct.Length -ge 8) { $Acct.Substring(0, 8) } else { $Acct }
    if ($script:Labels[$Acct]) { return '{0} ({1})' -f $script:Labels[$Acct], $short }
    return "tài khoản $short"
}

function Get-StoreLabel {
    param($Store)
    if ($Store.Kind -eq 'goi') { return 'gói {0} của {1}' -f $Store.Ten, (Get-Label $Store.Acct) }
    return Get-Label $Store.Acct
}

# ---------------------------------------------------------------- danh sách phiên, nội dung
function Get-MachineStores {
    # Danh sách phiên của từng tài khoản đã đăng nhập trên máy: claude-code-sessions\<tài khoản>\<tổ chức>.
    $list = @()
    foreach ($a in @(Get-ChildItem -LiteralPath $script:SessRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $script:GuidMau })) {
        foreach ($o in @(Get-ChildItem -LiteralPath $a.FullName -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $script:GuidMau })) {
            $list += [pscustomobject]@{ Kind = 'may'; Acct = $a.Name; Org = $o.Name; Dir = $o.FullName; NoiDung = ''; UserDir = $script:UserDir; Ten = '' }
        }
    }
    return $list
}

function Get-PackageStores {
    # Gói sao lưu: thư mục có goi.json. $From là một gói hoặc thư mục chứa các gói (mặc định du-lieu của công cụ).
    param([string]$From)
    $roots = if ($From) { @($From) } else { @($script:DataDir) }
    $dirs = @()
    foreach ($r in $roots) {
        if (-not (Test-Path -LiteralPath $r -PathType Container)) { continue }
        if (Test-Path -LiteralPath (Join-Path $r 'goi.json') -PathType Leaf) { $dirs += (Get-Item -LiteralPath $r).FullName; continue }
        $dirs += @(Get-ChildItem -LiteralPath $r -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'goi.json') -PathType Leaf } | ForEach-Object { $_.FullName })
    }
    $list = @()
    foreach ($d in $dirs) {
        $g = Read-Obj (Join-Path $d 'goi.json')
        if (-not $g -or $g.chuan -ne $script:GoiChuan -or -not $g.taiKhoan -or [string]$g.taiKhoan.acct -notmatch $script:GuidMau) { continue }
        $acct = [string]$g.taiKhoan.acct
        if ($g.taiKhoan.email -and -not $script:Labels[$acct]) { $script:Labels[$acct] = [string]$g.taiKhoan.email }
        $list += [pscustomobject]@{
            Kind = 'goi'; Acct = $acct; Org = [string]$g.taiKhoan.org; Dir = (Join-Path $d 'phien'); NoiDung = (Join-Path $d 'noi-dung')
            UserDir = ([string]$g.thuMucNguoiDung).TrimEnd('\'); Ten = (Split-Path $d -Leaf); Goc = $d; Luc = [string]$g.luc; May = [string]$g.may
        }
    }
    return $list
}

function Read-Sessions {
    # Các mục local_<mã>.json của một nơi. Data: Dictionary đủ mọi trường để ghi lại nguyên vẹn.
    param($Store)
    $list = @()
    if (-not $Store.Dir) { return $list }
    foreach ($f in @(Get-ChildItem -LiteralPath $Store.Dir -File -Filter 'local_*.json' -ErrorAction SilentlyContinue)) {
        $m = [regex]::Match($f.Name, '^local_([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.json$')
        if (-not $m.Success) { continue }
        $d = Read-Dict $f.FullName
        if (-not $d -or [string]$d['sessionId'] -ne "local_$($m.Groups[1].Value)") { continue }
        $list += [pscustomobject]@{
            Id = [string]$d['sessionId']; Uuid = $m.Groups[1].Value; File = $f.FullName; Data = $d; Store = $Store
            Last = (Get-Num $d['lastActivityAt']); Cli = [string]$d['cliSessionId']; Cwd = [string]$d['cwd']
            Title = [string]$d['title']; Archived = [bool]$d['isArchived']
        }
    }
    return $list
}

function Get-TranscriptIndex {
    # Nội dung hội thoại: projects\<thư mục dự án>\<mã phiên>.jsonl; trùng mã thì lấy file lớn nhất.
    param([string]$ProjDir)
    $ix = @{}
    foreach ($p in @(Get-ChildItem -LiteralPath $ProjDir -Directory -Force -ErrorAction SilentlyContinue)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $p.FullName -File -Filter '*.jsonl' -Force -ErrorAction SilentlyContinue)) {
            if (-not $ix.ContainsKey($f.BaseName) -or $f.Length -gt $ix[$f.BaseName].Length) { $ix[$f.BaseName] = $f }
        }
    }
    return $ix
}

# Claude Code đặt tên thư mục dự án theo đường dẫn, ký tự không phải chữ, số thành '-' (C:\Users\A\x -> C--Users-A-x).
function Convert-ProjectName { param([string]$Path) return ($Path -replace '[^A-Za-z0-9]', '-') }

function Convert-UserPath {
    # Gói làm ở thư mục người dùng khác (máy khác, tên tài khoản Windows khác): đổi phần đầu đường dẫn.
    param([string]$Path, [string]$Old, [string]$New)
    if (-not $Path -or -not $Old -or $Old -ieq $New) { return $Path }
    if ($Path -ieq $Old) { return $New }
    if ($Path.StartsWith($Old + '\', [StringComparison]::OrdinalIgnoreCase)) { return $New + $Path.Substring($Old.Length) }
    return $Path
}

function Convert-ProjectSlug {
    param([string]$Slug, [string]$Old, [string]$New)
    if (-not $Old -or $Old -ieq $New) { return $Slug }
    $o = Convert-ProjectName $Old; $n = Convert-ProjectName $New
    if ($Slug -ieq $o) { return $n }
    if ($Slug.StartsWith($o + '-', [StringComparison]::OrdinalIgnoreCase)) { return $n + $Slug.Substring($o.Length) }
    return $Slug
}

function Find-Transcript {
    # Nội dung của một phiên. Có sẵn trên máy (cùng mã) thì dùng luôn. Phiên trong gói: bản trong gói lớn hơn bản trên máy
    # (hoặc máy chưa có) thì chép vào ~\.claude\projects, kèm thư mục <mã phiên> (hội thoại của tác tử con, kết quả lệnh).
    param($S, $Ix)
    if (-not $S.Cli) { return $null }
    $local = if ($Ix.ContainsKey($S.Cli)) { $Ix[$S.Cli] } else { $null }
    if ($S.Store.Kind -eq 'goi') {
        $pf = $null
        foreach ($p in @(Get-ChildItem -LiteralPath $S.Store.NoiDung -Directory -ErrorAction SilentlyContinue)) {
            $c = Join-Path $p.FullName "$($S.Cli).jsonl"
            if (Test-Path -LiteralPath $c -PathType Leaf) { $pf = Get-Item -LiteralPath $c; break }
        }
        if ($pf -and (-not $local -or $pf.Length -gt $local.Length)) {
            $dest = if ($local) { $local.FullName } else {
                Join-Path (Join-Path $script:ProjectsDir (Convert-ProjectSlug $pf.Directory.Name $S.Store.UserDir $script:UserDir)) $pf.Name
            }
            $side = Join-Path $pf.DirectoryName $S.Cli
            return [pscustomobject]@{
                Copy = $true; Src = $pf.FullName; Dest = $dest; Size = ($pf.Length + (Get-DirSize $side))
                Side = $side; SideDest = (Join-Path (Split-Path $dest -Parent) $S.Cli)
            }
        }
    }
    if ($local) { return [pscustomobject]@{ Copy = $false; Src = $local.FullName; Dest = $local.FullName; Size = [long]0; Side = ''; SideDest = '' } }
    return $null
}

function Convert-ForTarget {
    # Bản mục danh sách cho tài khoản đang dùng: bỏ trường gắn với tài khoản cũ; tài khoản này chưa tự bật chế độ không
    # hỏi quyền thì phiên mở lại ở chế độ hỏi trước; gói làm ở thư mục người dùng khác thì đổi đường dẫn.
    param($Data, [bool]$BypassOk, [string]$OldUser, [string]$NewUser)
    $d = Copy-Dict $Data
    foreach ($k in $script:AccountFields) { [void]$d.Remove($k) }
    if (-not $BypassOk -and [string]$d['permissionMode'] -eq 'bypassPermissions') {
        $d['permissionMode'] = 'default'
        if ($d.ContainsKey('bypassChosenInApp')) { $d['bypassChosenInApp'] = $false }
    }
    if ($OldUser -and $OldUser -ine $NewUser) {
        foreach ($k in 'cwd', 'originCwd') { if ($d.ContainsKey($k)) { $d[$k] = Convert-UserPath ([string]$d[$k]) $OldUser $NewUser } }
        if ($d['gitAnchors'] -is [array]) {
            foreach ($g in $d['gitAnchors']) {
                if ($g -isnot [System.Collections.Generic.IDictionary[string, object]]) { continue }
                foreach ($k in 'gitRoot', 'commonDir') { if ($g.ContainsKey($k)) { $g[$k] = Convert-UserPath ([string]$g[$k]) $OldUser $NewUser } }
            }
        }
        if ($d['writtenBranches'] -is [array]) {
            # "đường dẫn repo\0tên nhánh"
            $d['writtenBranches'] = @($d['writtenBranches'] | ForEach-Object {
                    $p = [string]$_; $i = $p.IndexOf([char]0)
                    if ($i -gt 0) { (Convert-UserPath $p.Substring(0, $i) $OldUser $NewUser) + $p.Substring($i) } else { Convert-UserPath $p $OldUser $NewUser }
                })
        }
    }
    return $d
}

function Test-NenThay {
    # Tài khoản đang dùng đã có phiên này (cùng mã) nhưng khác bản ở nơi khác: bản có lần dùng cuối (lastActivityAt) mới
    # hơn thắng, hợp với kiểu dùng xoay vòng A, B, A. Bằng nhau thì giữ bản đang có để chạy nhiều lần không thay qua lại.
    # Thay thì bản đang có được cất vào du-lieu\HoanTac, Hoàn tác trả lại được.
    param($Dich, $Nguon)
    return ((Get-Num $Nguon['lastActivityAt']) -gt (Get-Num $Dich['lastActivityAt']))
}

function Get-SyncPlan {
    # So danh sách phiên của tài khoản đang dùng với các nguồn (tài khoản khác trên máy, gói sao lưu). Mỗi mã phiên lấy
    # bản mới nhất trong các nguồn; cùng lúc thì ưu tiên bản trên máy (nội dung đã nằm sẵn).
    param([string]$From)
    $tgt = [pscustomobject]@{ Kind = 'may'; Acct = $script:Cur.Acct; Org = $script:Cur.Org; Dir = $script:Cur.Dir; NoiDung = ''; UserDir = $script:UserDir; Ten = '' }
    $have = @{}
    foreach ($s in @(Read-Sessions $tgt)) { $have[$s.Id] = $s }
    $tomb = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @(Get-ChildItem -LiteralPath $script:Cur.Dir -File -Filter 'deleted_*' -ErrorAction SilentlyContinue)) {
        [void]$tomb.Add(($f.Name -replace '^deleted_', '' -replace '\.json$', ''))
    }
    $sources = @(Get-MachineStores | Where-Object { -not ($_.Acct -eq $script:Cur.Acct -and $_.Org -eq $script:Cur.Org) })
    $sources += @(Get-PackageStores $From)
    $best = @{}
    foreach ($src in $sources) {
        foreach ($s in @(Read-Sessions $src)) {
            $b = $best[$s.Id]
            if (-not $b -or $s.Last -gt $b.Last -or ($s.Last -eq $b.Last -and $s.Store.Kind -eq 'may' -and $b.Store.Kind -ne 'may')) { $best[$s.Id] = $s }
        }
    }
    $ix = Get-TranscriptIndex $script:ProjectsDir
    $plan = [pscustomobject]@{
        Nguon = $sources; Co = $have.Count; Giong = 0
        Them = (New-Object System.Collections.ArrayList); Thay = (New-Object System.Collections.ArrayList)
        Giu = (New-Object System.Collections.ArrayList); DaXoa = (New-Object System.Collections.ArrayList)
        ThieuNoiDung = (New-Object System.Collections.ArrayList)
    }
    foreach ($s in @($best.Values | Sort-Object Last -Descending)) {
        if ($tomb.Contains($s.Uuid)) { [void]$plan.DaXoa.Add($s); continue }
        $h = $have[$s.Id]
        if ($h -and $h.Last -eq $s.Last -and $h.Title -ceq $s.Title -and $h.Archived -eq $s.Archived) { $plan.Giong++; continue }
        $tx = Find-Transcript $s $ix
        if (-not $tx) { [void]$plan.ThieuNoiDung.Add($s); continue }
        $item = [pscustomobject]@{ S = $s; Tx = $tx; Cu = $h }
        if (-not $h) { [void]$plan.Them.Add($item) }
        elseif (Test-NenThay $h.Data $s.Data) { [void]$plan.Thay.Add($item) }
        else { [void]$plan.Giu.Add($item) }
    }
    return $plan
}

# ---------------------------------------------------------------- phát hiện, kết quả
function Add-Finding {
    # Một phát hiện theo chuẩn tramtool.ketqua/1; $Tiep 'cong-cu/action' là nút gợi ý chạy tiếp trong Trạm.
    param([string]$Ma, [string]$Muc, [string]$TieuDe, [string]$ChiTiet = '', [string]$CachSua = '', [string]$Tiep = '')
    $f = [ordered]@{ ma = $Ma; mucDo = $Muc; tieuDe = $TieuDe; chiTiet = $ChiTiet; cachSua = $CachSua }
    if ($Tiep -match '^([a-z0-9-]+)/([A-Za-z0-9_-]+)$') { $f['chayTiep'] = [ordered]@{ congCu = $Matches[1]; action = $Matches[2] } }
    [void]$script:Findings.Add($f)
    switch ($Muc) { 'loi' { Write-Bad $TieuDe } 'canh-bao' { Write-Warn $TieuDe } 'thong-tin' { Write-Info $TieuDe } default { Write-Ok $TieuDe } }
    if ($ChiTiet) { Write-Sub $ChiTiet }
}

function Save-RunResult {
    # Ghi kết quả lần chạy cho Trạm Tool (chuẩn tramtool.ketqua/1).
    param([string]$CheDo, [int]$Code, [datetime]$Start, [string]$Message = '')
    $i = 0
    $sorted = @($script:Findings | ForEach-Object { [pscustomobject]@{ F = $_; L = $script:Levels[[string]$_.mucDo]; I = $i++ } } | Sort-Object L, I | ForEach-Object { $_.F })
    $nLoi = @($sorted | Where-Object { $_.mucDo -eq 'loi' }).Count
    $nCanh = @($sorted | Where-Object { $_.mucDo -eq 'canh-bao' }).Count
    $nTin = @($sorted | Where-Object { $_.mucDo -eq 'thong-tin' }).Count
    if (-not $Message) {
        $Message = if ($nLoi + $nCanh) { 'Có {0} lỗi, {1} cảnh báo; xem gợi ý.' -f $nLoi, $nCanh } else { 'Không có gì cần làm.' }
    }
    $r = [ordered]@{
        chuan = 'tramtool.ketqua/1'; congCu = 'claude-dong-bo'; cheDo = $CheDo; phienBan = $script:Version
        may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
        batDau = $Start.ToString('s'); ketThuc = (Get-Date).ToString('s')
        maThoat = $Code; trangThai = @{ 0 = 'xong'; 1 = 'loi'; 2 = 'thieu-dieu-kien'; 3 = 'mot-phan' }[$Code]
        chayThu = [bool]$ChayThu
        ma = $(if ($nLoi + $nCanh) { 'CO_CANH_BAO' } else { 'KHONG_CO_CANH_BAO' })
        thongDiep = $Message
        tomTat = [ordered]@{ loi = $nLoi; canhBao = $nCanh; thongTin = $nTin }
        phatHien = $sorted
        tep = @($script:Files)
    }
    try {
        if (-not (Test-Path -LiteralPath $script:ResultDir)) { New-Item -ItemType Directory -Path $script:ResultDir -Force | Out-Null }
        $f = Join-Path $script:ResultDir ('KetQua_ClaudeDongBo_{0}_{1:yyyyMMdd_HHmmss}.json' -f $env:COMPUTERNAME, $Start)
        Write-TextAtomic $f ($r | ConvertTo-Json -Depth 8)
        Write-Info "Kết quả cho Trạm Tool: $f"
    } catch { Write-Warn "Không ghi được file kết quả: $($_.Exception.Message.Trim())" }
}

function Initialize-Claude {
    # Thư mục dữ liệu Claude Desktop, tài khoản đang đăng nhập. Trả 0 khi dùng được, 2 khi thiếu điều kiện.
    $script:AppDir = Get-ClaudeAppDir
    if (-not $script:AppDir -or -not (Test-Path -LiteralPath $script:AppDir -PathType Container)) {
        Add-Finding 'CHUA_CAI_CLAUDE' 'loi' 'Không thấy dữ liệu Claude Desktop trên máy' '' 'Cài Claude Desktop (https://claude.ai/download), đăng nhập, mở tab Code một lần rồi chạy lại.'
        return 2
    }
    $script:SessRoot = Join-Path $script:AppDir 'claude-code-sessions'
    Update-Labels
    [void](Get-PackageStores '')   # lấy thêm email ghi trong các gói
    $script:Cur = Get-CurrentAccount
    if (-not $script:Cur) {
        Add-Finding 'CHUA_DANG_NHAP' 'loi' 'Không biết Claude Desktop đang đăng nhập tài khoản nào' '' 'Mở Claude Desktop, đăng nhập rồi chạy lại.'
        return 2
    }
    if (-not $script:Cur.Org) {
        Add-Finding 'CHUA_MO_TAB_CODE' 'loi' ('{0} chưa có danh sách phiên tab Code trên máy này' -f (Get-Label $script:Cur.Acct)) '' 'Mở tab Code bằng tài khoản này một lần (tạo một phiên bất kỳ), thoát Claude rồi chạy lại.'
        return 2
    }
    return 0
}

function Show-PlanItems {
    param($Items, [string]$Mark, [int]$Max = 40)
    $n = 0
    foreach ($x in $Items) {
        if ($n -ge $Max) { Write-Sub ('... và {0} phiên khác' -f ($Items.Count - $Max)); break }
        $s = $x.S
        Write-Plan ('{0} {1}  {2}{3}' -f $Mark, (Format-Time $s.Last), $s.Title, $(if ($s.Archived) { ' (đã lưu trữ)' } else { '' }))
        Write-Sub ('{0}; từ {1}' -f $s.Cwd, (Get-StoreLabel $s.Store))
        $n++
    }
}

# ---------------------------------------------------------------- chế độ
function Invoke-KiemTra {
    param([string]$From)
    Write-Head 'Tài khoản Claude trên máy'
    $plan = Get-SyncPlan $From
    $tgt = [pscustomobject]@{ Kind = 'may'; Acct = $script:Cur.Acct; Dir = $script:Cur.Dir }
    $mine = @(Read-Sessions $tgt)
    Add-Finding 'TAI_KHOAN_DANG_DUNG' 'ok' ('Đang đăng nhập {0}: {1} phiên ({2} đã lưu trữ)' -f (Get-Label $script:Cur.Acct), $mine.Count, @($mine | Where-Object { $_.Archived }).Count) $script:Cur.Dir
    foreach ($src in $plan.Nguon) {
        $ss = @(Read-Sessions $src)
        $last = ($ss | Measure-Object -Property Last -Maximum).Maximum
        if ($src.Kind -eq 'goi') {
            Add-Finding 'GOI_SAO_LUU' 'thong-tin' ('Gói sao lưu {0}: {1} phiên, làm lúc {2} trên máy {3}' -f $src.Ten, $ss.Count, $src.Luc, $src.May) $src.Goc
        } else {
            Add-Finding 'TAI_KHOAN_KHAC' 'thong-tin' ('{0}: {1} phiên, lần cuối {2}' -f (Get-Label $src.Acct), $ss.Count, (Format-Time ([long]$last))) $src.Dir
        }
    }
    if (-not $plan.Nguon.Count) {
        Add-Finding 'KHONG_CO_NGUON' 'thong-tin' 'Máy chưa có tài khoản Claude nào khác và chưa có gói sao lưu' '' 'Đăng nhập tài khoản cũ, chạy Sao lưu (hoặc chỉ cần đăng nhập rồi thoát), sau đó đăng nhập lại tài khoản này và chạy Đồng bộ.'
    }
    $n = $plan.Them.Count + $plan.Thay.Count
    if ($n) {
        Add-Finding 'THIEU_PHIEN' 'canh-bao' ('Tài khoản đang dùng chưa có {0} phiên, có bản mới hơn của {1} phiên' -f $plan.Them.Count, $plan.Thay.Count) (@($plan.Them + $plan.Thay | Select-Object -First 8 | ForEach-Object { $_.S.Title }) -join '; ') 'Thoát Claude Desktop rồi chạy Đồng bộ.' 'claude-dong-bo/dong-bo'
    } elseif ($plan.Nguon.Count) {
        Add-Finding 'DU_PHIEN' 'ok' 'Tài khoản đang dùng đã có đủ phiên của các tài khoản khác và các gói'
    }
    if ($plan.Giu.Count) { Add-Finding 'GIU_BAN_DANG_CO' 'thong-tin' ('{0} phiên tài khoản này đã có, bản ở nơi khác khác bản đang có nhưng không thay' -f $plan.Giu.Count) }
    if ($plan.DaXoa.Count) { Add-Finding 'DA_XOA_O_DAY' 'thong-tin' ('{0} phiên đã xoá ở tài khoản này nên không thêm lại' -f $plan.DaXoa.Count) (@($plan.DaXoa | Select-Object -First 8 | ForEach-Object { $_.Title }) -join '; ') }
    if ($plan.ThieuNoiDung.Count) {
        Add-Finding 'PHIEN_THIEU_NOI_DUNG' 'canh-bao' ('{0} phiên không có nội dung hội thoại trên máy nên không đồng bộ được' -f $plan.ThieuNoiDung.Count) (@($plan.ThieuNoiDung | Select-Object -First 8 | ForEach-Object { $_.Title }) -join '; ') 'Nội dung nằm trong ~\.claude\projects; phiên làm ở máy khác thì sao lưu ở máy đó rồi đồng bộ từ gói.'
    }
    if (@(Get-ClaudeDesktopProcess).Count) { Add-Finding 'CLAUDE_DANG_MO' 'thong-tin' 'Claude Desktop đang mở: Đồng bộ, Hoàn tác cần thoát Claude trước' }
    return 0
}

function Invoke-SaoLuu {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head $script:Modes['sao-luu'].Label
    $src = [pscustomobject]@{ Kind = 'may'; Acct = $script:Cur.Acct; Dir = $script:Cur.Dir }
    $ss = @(Read-Sessions $src)
    if (-not $ss.Count) { Add-Finding 'KHONG_CO_PHIEN' 'thong-tin' ('{0} chưa có phiên nào để sao lưu' -f (Get-Label $script:Cur.Acct)); return 0 }
    $ix = Get-TranscriptIndex $script:ProjectsDir
    $items = @(); $miss = @()
    foreach ($s in $ss) {
        if ($s.Cli -and $ix.ContainsKey($s.Cli)) {
            $tx = $ix[$s.Cli]; $side = Join-Path $tx.DirectoryName $s.Cli
            $items += [pscustomobject]@{ S = $s; Tx = $tx; Side = $side; Size = ($tx.Length + (Get-DirSize $side) + (Get-Item -LiteralPath $s.File).Length) }
        } else { $miss += $s }
    }
    $size = [long](($items | Measure-Object -Property Size -Sum).Sum)
    $root = if ($Den) { $Den } else { $script:DataDir }
    $pkg = Get-FreeName (Join-Path $root ('Goi_{0}_{1:yyyyMMdd_HHmmss}' -f $script:Cur.Acct.Substring(0, 8), (Get-Date)))
    Write-Line ('Tài khoản: {0}' -f (Get-Label $script:Cur.Acct))
    Write-Line ('{0} phiên có nội dung, cần khoảng {1}. Lưu vào: {2}' -f $items.Count, (Format-Size $size), $pkg)
    if ($miss.Count) { Add-Finding 'PHIEN_THIEU_NOI_DUNG' 'canh-bao' ('{0} phiên không có nội dung hội thoại trên máy nên không đưa vào gói' -f $miss.Count) (@($miss | Select-Object -First 8 | ForEach-Object { $_.Title }) -join '; ') }
    if (-not $items.Count) { return 0 }
    $free = Get-FreeBytes $root
    if ($free -ge 0 -and $free -lt $size + 50MB) {
        Add-Finding 'THIEU_CHO_TRONG' 'loi' ('Ổ chứa {0} còn {1}, cần khoảng {2}' -f $root, (Format-Size $free), (Format-Size ($size + 50MB))) '' 'Chọn nơi lưu khác (USB, ổ khác) ở ô Lưu vào.'
        return 2
    }
    if ($DryRun) { Write-Info 'Chạy thử: chưa chép gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo 'Sao lưu bây giờ?' $true)) { return 2 }

    $fail = 0; $errs = @()
    New-Item -ItemType Directory -Path (Join-Path $pkg 'phien') -Force | Out-Null
    foreach ($it in $items) {
        try {
            Copy-Item -LiteralPath $it.S.File -Destination (Join-Path $pkg 'phien') -Force
            $nd = Join-Path (Join-Path $pkg 'noi-dung') $it.Tx.Directory.Name
            if (-not (Test-Path -LiteralPath $nd)) { New-Item -ItemType Directory -Path $nd -Force | Out-Null }
            Copy-Item -LiteralPath $it.Tx.FullName -Destination $nd -Force
            if (Test-Path -LiteralPath $it.Side -PathType Container) { Copy-Item -LiteralPath $it.Side -Destination $nd -Recurse -Force }
        } catch { $fail++; $errs += ('{0}: {1}' -f $it.S.Title, $_.Exception.Message.Trim()); Write-Bad "Không chép được $($errs[-1])" }
    }
    # goi.json ghi sau cùng: gói đứt giữa chừng không có goi.json nên Đồng bộ bỏ qua.
    $cj = Read-Obj $script:ClaudeJson
    $email = if ($cj -and $cj.oauthAccount -and [string]$cj.oauthAccount.accountUuid -eq $script:Cur.Acct) { [string]$cj.oauthAccount.emailAddress } else { '' }
    Write-Obj (Join-Path $pkg 'goi.json') ([ordered]@{
            chuan = $script:GoiChuan; phienBan = $script:Version; luc = (Get-Date).ToString('s'); may = $env:COMPUTERNAME
            thuMucNguoiDung = $script:UserDir; taiKhoan = [ordered]@{ acct = $script:Cur.Acct; org = $script:Cur.Org; email = $email }
            soPhien = ($items.Count - $fail)
        })
    [void]$script:Files.Add([ordered]@{ nhan = 'Gói sao lưu phiên Claude'; duongDan = $pkg })
    if ($fail) {
        Add-Finding 'SAO_LUU_MOT_PHAN' 'canh-bao' ('Đã sao lưu {0}/{1} phiên vào {2}' -f ($items.Count - $fail), $items.Count, $pkg) (@($errs | Select-Object -First 5) -join '; ')
        return 3
    }
    Add-Finding 'DA_SAO_LUU' 'ok' ('Đã sao lưu {0} phiên ({1}) vào {2}' -f $items.Count, (Format-Size $size), $pkg) '' 'Đăng nhập tài khoản khác (máy này hoặc máy khác, chép cả thư mục gói sang), thoát Claude rồi chạy Đồng bộ.'
    return 0
}

function Invoke-DongBo {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head $script:Modes['dong-bo'].Label
    if ($Tu -and -not @(Get-PackageStores $Tu).Count) {
        Add-Finding 'KHONG_THAY_GOI' 'loi' ('Không thấy gói sao lưu trong {0}' -f $Tu) '' 'Chọn thư mục Goi_... (có goi.json) hoặc thư mục chứa nó.'
        return 2
    }
    $plan = Get-SyncPlan $Tu
    Write-Line ('Vào tài khoản: {0} (đang có {1} phiên)' -f (Get-Label $script:Cur.Acct), $plan.Co)
    Write-Line ('Nguồn: {0}' -f $(if ($plan.Nguon.Count) { (@($plan.Nguon | ForEach-Object { Get-StoreLabel $_ }) -join '; ') } else { 'không có' }))
    if ($plan.DaXoa.Count) { Add-Finding 'DA_XOA_O_DAY' 'thong-tin' ('{0} phiên đã xoá ở tài khoản này nên không thêm lại' -f $plan.DaXoa.Count) (@($plan.DaXoa | Select-Object -First 8 | ForEach-Object { $_.Title }) -join '; ') }
    if ($plan.ThieuNoiDung.Count) { Add-Finding 'PHIEN_THIEU_NOI_DUNG' 'canh-bao' ('{0} phiên không có nội dung hội thoại trên máy nên không đồng bộ được' -f $plan.ThieuNoiDung.Count) (@($plan.ThieuNoiDung | Select-Object -First 8 | ForEach-Object { $_.Title }) -join '; ') 'Phiên làm ở máy khác: sao lưu ở máy đó rồi đồng bộ từ gói.' }
    if ($plan.Giu.Count) { Add-Finding 'GIU_BAN_DANG_CO' 'thong-tin' ('{0} phiên tài khoản này đã có, giữ bản đang có' -f $plan.Giu.Count) }
    $work = @($plan.Them) + @($plan.Thay)
    if (-not $work.Count) {
        Add-Finding 'KHONG_CAN_DONG_BO' 'ok' $(if ($plan.Nguon.Count) { 'Tài khoản đang dùng đã có đủ phiên, không cần đồng bộ' } else { 'Máy chưa có tài khoản Claude nào khác và chưa có gói sao lưu' })
        return 0
    }
    Show-PlanItems @($plan.Them) '[+]'
    Show-PlanItems @($plan.Thay) '[~]'
    $copy = [long](($work | ForEach-Object { $_.Tx.Size } | Measure-Object -Sum).Sum)
    if ($copy) {
        Write-Line ('Chép thêm nội dung hội thoại từ gói: {0}' -f (Format-Size $copy))
        $free = Get-FreeBytes $script:UserDir
        if ($free -ge 0 -and $free -lt $copy + 50MB) {
            Add-Finding 'THIEU_CHO_TRONG' 'loi' ('Ổ chứa {0} còn {1}, cần khoảng {2}' -f $script:UserDir, (Format-Size $free), (Format-Size ($copy + 50MB)))
            return 2
        }
    }
    $bypassOk = Test-BypassAllowed $script:Cur.Acct
    if (-not $bypassOk -and @($work | Where-Object { [string]$_.S.Data['permissionMode'] -eq 'bypassPermissions' }).Count) {
        Write-Info 'Tài khoản này chưa bật chế độ không hỏi quyền: các phiên đang ở chế độ đó sẽ mở lại ở chế độ hỏi trước.'
    }
    if ($DryRun) { Write-Info 'Chạy thử: chưa ghi gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo ('Thêm {0}, thay {1} phiên vào tài khoản này?' -f $plan.Them.Count, $plan.Thay.Count) $true)) { return 2 }
    if (-not (Confirm-DesktopClosed)) {
        Add-Finding 'CLAUDE_DANG_MO' 'loi' 'Chưa đồng bộ vì Claude Desktop đang mở' '' 'Thoát hẳn Claude (chuột phải biểu tượng ở khay đồng hồ, Quit) rồi chạy lại, hoặc đánh dấu Tự đóng Claude.'
        return 2
    }

    # Nhật ký để Hoàn tác: mỗi việc ghi file đích và mã băm sau khi ghi; bản bị thay cất trong thư mục nhật ký.
    $jd = Get-FreeName (Join-Path $script:UndoDir ('DongBo_{0:yyyyMMdd_HHmmss}' -f (Get-Date)))
    New-Item -ItemType Directory -Path $jd -Force | Out-Null
    $viec = New-Object System.Collections.ArrayList
    $journal = [ordered]@{ chuan = $script:NhatKyChuan; luc = (Get-Date).ToString('s'); may = $env:COMPUTERNAME; taiKhoan = $script:Cur.Acct; thuMuc = $script:Cur.Dir; viec = $viec }
    $ok = 0; $fail = 0; $k = 0; $errs = @()
    try {
        foreach ($it in $work) {
            $k++
            $s = $it.S
            try {
                # Nội dung trước, mục danh sách sau: mục mới không bao giờ trỏ vào nội dung chưa có.
                if ($it.Tx.Copy) {
                    $v = [ordered]@{ loai = 'them-noi-dung'; tep = $it.Tx.Dest; banCu = ''; hash = ''; thuMuc = '' }
                    if (Test-Path -LiteralPath $it.Tx.Dest -PathType Leaf) {
                        $v.loai = 'thay-noi-dung'; $v.banCu = "noi-dung\$k.jsonl"
                        New-Item -ItemType Directory -Path (Join-Path $jd 'noi-dung') -Force | Out-Null
                        Copy-Item -LiteralPath $it.Tx.Dest -Destination (Join-Path $jd $v.banCu) -Force
                    }
                    $dd = Split-Path $it.Tx.Dest -Parent
                    if (-not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Path $dd -Force | Out-Null }
                    Copy-Item -LiteralPath $it.Tx.Src -Destination $it.Tx.Dest -Force
                    $v.hash = Get-Hash $it.Tx.Dest
                    if ((Test-Path -LiteralPath $it.Tx.Side -PathType Container) -and -not (Test-Path -LiteralPath $it.Tx.SideDest)) {
                        Copy-Item -LiteralPath $it.Tx.Side -Destination $it.Tx.SideDest -Recurse -Force
                        $v.thuMuc = $it.Tx.SideDest
                    }
                    [void]$viec.Add($v)
                }
                $dest = Join-Path $script:Cur.Dir "$($s.Id).json"
                $v = [ordered]@{ loai = 'them'; tep = $dest; banCu = ''; hash = ''; tieuDe = $s.Title }
                if (Test-Path -LiteralPath $dest -PathType Leaf) {
                    $v.loai = 'thay'; $v.banCu = "phien\$($s.Id).json"
                    New-Item -ItemType Directory -Path (Join-Path $jd 'phien') -Force | Out-Null
                    Copy-Item -LiteralPath $dest -Destination (Join-Path $jd $v.banCu) -Force
                }
                Write-Dict $dest (Convert-ForTarget $s.Data $bypassOk $s.Store.UserDir $script:UserDir)
                $v.hash = Get-Hash $dest
                [void]$viec.Add($v)
                $ok++
            } catch { $fail++; $errs += ('{0}: {1}' -f $s.Title, $_.Exception.Message.Trim()); Write-Bad "Không đồng bộ được $($errs[-1])" }
        }
    } finally {
        $journal['xong'] = (Get-Date).ToString('s')
        Write-Obj (Join-Path $jd 'nhat-ky.json') $journal
    }
    [void]$script:Files.Add([ordered]@{ nhan = 'Nhật ký để hoàn tác'; duongDan = (Join-Path $jd 'nhat-ky.json') })
    if ($ok) {
        Add-Finding 'DA_DONG_BO' 'ok' ('Đã thêm {0}, thay {1} phiên vào {2}' -f @($viec | Where-Object { $_.loai -eq 'them' }).Count, @($viec | Where-Object { $_.loai -eq 'thay' }).Count, (Get-Label $script:Cur.Acct)) '' 'Mở lại Claude Desktop, các phiên hiện ở thanh bên tab Code. Phiên có thư mục dự án chưa có trên máy thì chép thư mục đó về đúng chỗ trước khi mở.'
    }
    if ($fail) {
        Add-Finding 'DONG_BO_LOI' 'loi' ('{0} phiên không đồng bộ được' -f $fail) (@($errs | Select-Object -First 5) -join '; ')
        if ($ok) { return 3 } else { return 1 }
    }
    return 0
}

function Invoke-HoanTac {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head $script:Modes['hoan-tac'].Label
    $j = $null; $jf = ''
    foreach ($d in @(Get-ChildItem -LiteralPath $script:UndoDir -Directory -Filter 'DongBo_*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
        $f = Join-Path $d.FullName 'nhat-ky.json'
        $o = Read-Obj $f
        if ($o -and $o.chuan -eq $script:NhatKyChuan -and -not $o.hoanTacLuc) { $j = $o; $jf = $f; break }
    }
    if (-not $j) { Add-Finding 'KHONG_CO_GI_DE_HOAN_TAC' 'thong-tin' 'Không có lần đồng bộ nào chưa hoàn tác'; return 0 }
    $jd = Split-Path $jf -Parent
    $viec = @($j.viec)
    [array]::Reverse($viec)
    Write-Line ('Lần đồng bộ lúc {0} vào {1}: {2} việc' -f $j.luc, (Get-Label ([string]$j.taiKhoan)), $viec.Count)
    $todo = @(); $keep = @()
    foreach ($v in $viec) {
        $now = Get-Hash ([string]$v.tep)
        if (-not $now) { continue }                       # đã bị xoá sau khi đồng bộ: không còn gì để bỏ
        if ($now -ne [string]$v.hash) { $keep += $v; continue }
        $todo += $v
    }
    foreach ($v in $todo) { Write-Plan ('{0} {1}' -f $(if ($v.loai -like 'them*') { 'Bỏ' } else { 'Trả lại bản cũ' }), $(if ($v.tieuDe) { $v.tieuDe } else { $v.tep })) }
    if ($keep.Count) {
        Add-Finding 'GIU_VI_DA_DOI' 'canh-bao' ('Giữ {0} mục vì đã dùng tiếp sau khi đồng bộ' -f $keep.Count) (@($keep | ForEach-Object { if ($_.tieuDe) { $_.tieuDe } else { $_.tep } }) -join '; ')
    }
    if ($DryRun) { Write-Info 'Chạy thử: chưa đổi gì.'; return 0 }
    if ($todo.Count) {
        if ($Ask -and -not (Read-YesNo 'Hoàn tác bây giờ?' $true)) { return 2 }
        if (-not (Confirm-DesktopClosed)) {
            Add-Finding 'CLAUDE_DANG_MO' 'loi' 'Chưa hoàn tác vì Claude Desktop đang mở' '' 'Thoát hẳn Claude rồi chạy lại, hoặc đánh dấu Tự đóng Claude.'
            return 2
        }
    }
    $fail = 0; $errs = @()
    foreach ($v in $todo) {
        try {
            if ($v.loai -like 'them*') {
                Remove-Item -LiteralPath ([string]$v.tep) -Force
                if ($v.thuMuc -and (Test-Path -LiteralPath ([string]$v.thuMuc))) { Remove-Item -LiteralPath ([string]$v.thuMuc) -Recurse -Force }
            } else {
                Copy-Item -LiteralPath (Join-Path $jd ([string]$v.banCu)) -Destination ([string]$v.tep) -Force
            }
        } catch { $fail++; $errs += ('{0}: {1}' -f $v.tep, $_.Exception.Message.Trim()); Write-Bad "Không hoàn tác được $($errs[-1])" }
    }
    $o = [IO.File]::ReadAllText($jf, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $o | Add-Member -NotePropertyName hoanTacLuc -NotePropertyValue (Get-Date).ToString('s') -Force
    Write-Obj $jf $o
    if ($fail) { Add-Finding 'HOAN_TAC_LOI' 'loi' ('{0} mục không hoàn tác được' -f $fail) (@($errs | Select-Object -First 5) -join '; '); return 3 }
    Add-Finding 'DA_HOAN_TAC' 'ok' ('Đã hoàn tác {0} mục của lần đồng bộ lúc {1}' -f $todo.Count, $j.luc) '' 'Mở lại Claude Desktop.'
    if ($keep.Count) { return 3 }
    return 0
}

function Invoke-Mode {
    # Chạy một chế độ và ghi file kết quả. Trả mã thoát.
    param([string]$Id, [switch]$Ask)
    $start = Get-Date
    $script:Findings.Clear(); $script:Files.Clear()
    $code = 0; $msg = ''
    try {
        $code = Initialize-Claude
        if ($code -eq 0) {
            switch ($Id) {
                'kiem-tra' { $code = Invoke-KiemTra $Tu }
                'sao-luu' { $code = Invoke-SaoLuu -DryRun:$ChayThu -Ask:$Ask }
                'dong-bo' { $code = Invoke-DongBo -DryRun:$ChayThu -Ask:$Ask }
                'hoan-tac' { $code = Invoke-HoanTac -DryRun:$ChayThu -Ask:$Ask }
            }
        }
    } catch {
        Write-Bad ('Lỗi không lường trước: {0}' -f $_.Exception.Message.Trim())
        $code = 1
    }
    if ($Id -ne 'kiem-tra') {
        $msg = switch ($code) {
            0 { if ($ChayThu) { 'Chạy thử: chỉ xem việc sẽ làm, chưa ghi gì.' } else { '{0}: xong.' -f $script:Modes[$Id].Label } }
            2 { 'Chưa làm: thiếu điều kiện hoặc đã huỷ, xem chi tiết.' }
            3 { '{0}: làm được một phần.' -f $script:Modes[$Id].Label }
            default { '{0}: lỗi, xem cửa sổ công cụ.' -f $script:Modes[$Id].Label }
        }
    }
    Save-RunResult -CheDo $Id -Code $code -Start $start -Message $msg
    return $code
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '  ĐỒNG BỘ PHIÊN CLAUDE' -ForegroundColor Cyan
        Write-Host '  Đưa các phiên tab Code của tài khoản Claude khác sang tài khoản đang đăng nhập.' -ForegroundColor Gray
        Write-Host ''
        Write-Host '   1. Kiểm tra (chỉ đọc)'
        Write-Host '   2. Sao lưu phiên của tài khoản đang đăng nhập (để mang sang máy khác)'
        Write-Host '   3. Đồng bộ phiên vào tài khoản đang đăng nhập'
        Write-Host '   4. Hoàn tác lần đồng bộ gần nhất'
        Write-Host '   0. Thoát'
        Write-Host ''
        $c = Read-Text 'Chọn số' '0'
        switch ($c) {
            '0' { return 0 }
            '1' { [void](Invoke-Mode 'kiem-tra' -Ask) }
            '2' { [void](Invoke-Mode 'sao-luu' -Ask) }
            '3' { [void](Invoke-Mode 'dong-bo' -Ask) }
            '4' { [void](Invoke-Mode 'hoan-tac' -Ask) }
            default { continue }
        }
        Wait-Close 'Bấm Enter để về menu'
    }
}

# ---------------------------------------------------------------- bắt đầu
if ($env:TRAMTOOL_CLAUDEDONGBO_TEST) { return }   # bài thử nạp các hàm rồi tự gọi
try { $Host.UI.RawUI.WindowTitle = 'Đồng bộ phiên Claude' } catch { }
if ($Mode -and -not $script:Modes.Contains($Mode)) {
    Write-Bad ('Không có chế độ "{0}". Các chế độ: {1}.' -f $Mode, (@($script:Modes.Keys) -join ', '))
    Wait-Close
    exit 1
}
if (-not $Mode) {
    if ([Console]::IsInputRedirected) { Write-Host 'Cách dùng: DongBoClaude.ps1 -Mode kiem-tra|sao-luu|dong-bo|hoan-tac [-Tu <gói>] [-Den <thư mục>] [-DongClaude] [-ChayThu] [-KhongDung]'; exit 1 }
    exit (Show-Menu)
}
$code = Invoke-Mode $Mode
Wait-Close
exit $code
