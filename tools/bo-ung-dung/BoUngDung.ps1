<#
  Bộ ứng dụng văn phòng bằng winget: cài một lượt các ứng dụng hay dùng (Zalo, bộ gõ tiếng Việt, 7-Zip, đọc PDF, hỗ trợ
  từ xa, trình duyệt...) từ nguồn winget chính thức của Microsoft, không tải bộ cài trôi nổi trên mạng.
  Danh sách nằm trong DanhSach.json (mã gói winget, tên, có cài mặc định không, nhóm chỉ chọn một, bản ghim).
  Bản portable đầy đủ của Trạm Tool có sẵn bộ cài (runtime\bo-cai, tải bằng 'winget download', đúng mã SHA-256 của
  winget): ứng dụng có bộ cài sẵn thì cài từ đó, không cần mạng, không cần winget; máy không có winget thì xem đã cài
  hay chưa trong Programs and Features.

  Chế độ (-Mode):
    kiem-tra   chỉ đọc, không cần Admin: winget chạy được không; ứng dụng nào trong danh sách đã cài, chưa cài
               (đọc bằng 'winget export', nhận cả ứng dụng không cài bằng winget).
    cai        cần Admin: cài các ứng dụng chọn bằng cờ -<khoa> (vd -Zalo -UniKey -Foxit); không chọn thì cài các ứng
               dụng mặc định. Bỏ qua ứng dụng đã có; đọc lại danh sách đã cài để chắc đã cài xong.
    cap-nhat   cần Admin: cập nhật các ứng dụng trong danh sách đã cài (winget upgrade).
  Không có -Mode: menu (bấm đúp BO_UNG_DUNG.bat): chọn ứng dụng bằng số; việc cần Admin mở cửa sổ Admin riêng (UAC).
  Không gỡ ứng dụng: gỡ trong Cài đặt > Ứng dụng như thường.
  Mỗi lần chạy ghi ket_qua\KetQua_BoUngDung_<máy>_<giờ>.json (chuẩn tramtool.ketqua/1) cho Trạm Tool.
  -ChayThu: chỉ in việc sẽ làm. -KhongDung: không chờ Enter khi xong.
  Mã thoát: 0 xong, 1 lỗi, 2 thiếu điều kiện (winget, quyền Admin, đã huỷ), 3 làm được một phần.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Mode = '',
    [switch]$ChayThu,
    [switch]$KhongDung,
    [switch]$DaNangQuyen,   # đánh dấu cửa sổ đã mở lại bằng quyền Admin, để không hỏi UAC lần nữa
    [Parameter(ValueFromRemainingArguments = $true)] $ConLai   # cờ chọn ứng dụng: -Zalo -UniKey ... (khoa trong DanhSach.json)
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:Version = '1.1'
$script:ListFile = Join-Path $PSScriptRoot 'DanhSach.json'
# Bộ cài có sẵn của bản portable (hub\lib\BoCai.ps1 nằm cùng trạm; công cụ chép đi riêng thì chỉ dùng winget).
$script:TramDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:BoCaiRoot = ''
$bcLib = Join-Path $script:TramDir 'hub\lib\BoCai.ps1'
if (Test-Path -LiteralPath $bcLib) { . $bcLib; $script:BoCaiRoot = Get-BoCaiRoot $script:TramDir }
$script:ResultDir = if ($env:BUD_KET_QUA) { $env:BUD_KET_QUA } else { Join-Path $PSScriptRoot 'ket_qua' }
$script:WingetCommon = @('--source', 'winget', '--accept-source-agreements', '--disable-interactivity')
$script:CodeNoUpdate = -1978335189   # 0x8A15002B: không có bản mới hơn
$script:CodeReboot = -1978334967     # 0x8A150109: cài xong, cần khởi động lại để hoàn tất
$script:Modes = [ordered]@{
    'kiem-tra' = @{ No = 1; Label = 'Kiểm tra: ứng dụng nào đã cài, chưa cài'; Admin = $false }
    'cai'      = @{ No = 2; Label = 'Cài ứng dụng (chọn trong danh sách)'; Admin = $true }
    'cap-nhat' = @{ No = 3; Label = 'Cập nhật các ứng dụng trong danh sách đã cài'; Admin = $true }
}
$script:Levels = @{ 'loi' = 0; 'canh-bao' = 1; 'thong-tin' = 2; 'ok' = 3 }
$script:Findings = New-Object System.Collections.ArrayList

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

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------- danh sách, winget
function Read-AppList {
    # Danh sách ứng dụng trong DanhSach.json (lỗi thì báo rõ file nào hỏng).
    try { $j = [IO.File]::ReadAllText($script:ListFile, [Text.Encoding]::UTF8) | ConvertFrom-Json }
    catch { throw "Không đọc được danh sách ứng dụng $script:ListFile`: $($_.Exception.Message)" }
    $list = @($j.ungDung | Where-Object { $_.khoa -and $_.id })
    if (-not $list.Count) { throw "Danh sách ứng dụng $script:ListFile không có ứng dụng nào." }
    return , $list
}

function Get-SelectedApps {
    # Ứng dụng được chọn bằng cờ -<khoa>; không chọn gì thì các ứng dụng mặc định. Cờ lạ thì báo lỗi.
    param([object[]]$Apps, [object[]]$Tokens)
    $keys = @(@($Tokens) | Where-Object { $_ } | ForEach-Object { ([string]$_).TrimStart('-', '/') })
    $unknown = @($keys | Where-Object { $k = $_; -not @($Apps | Where-Object { $_.khoa -eq $k }).Count })
    if ($unknown.Count) { throw ('Không có ứng dụng "{0}" trong danh sách. Các cờ chọn được: {1}.' -f ($unknown -join '", "'), (($Apps | ForEach-Object { '-' + $_.khoa }) -join ' ')) }
    if (-not $keys.Count) { return , @($Apps | Where-Object { $_.macDinh }) }
    return , @($Apps | Where-Object { $keys -contains $_.khoa })
}

function Get-WingetCommand {
    # Đường dẫn winget (App Installer); $null khi máy chưa có.
    $c = Get-Command winget -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

function Invoke-Winget {
    # Chạy winget trong cùng cửa sổ (thấy tiến trình tải, cài), trả mã thoát.
    param([string[]]$Arguments)
    $text = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ } }) -join ' '
    $p = Start-Process -FilePath (Get-WingetCommand) -ArgumentList $text -NoNewWindow -Wait -PassThru
    try { return [int]$p.ExitCode } catch { return 1 }
}

function Get-InstalledIds {
    # Mã gói winget của các ứng dụng đã cài (winget export đối chiếu danh sách Programs and Features với nguồn winget,
    # nên nhận cả ứng dụng không cài bằng winget). Trả Ok = $false và chữ lỗi khi winget hỏng.
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('TramTool_winget_{0}.json' -f [guid]::NewGuid().ToString('N'))
    try {
        $ErrorActionPreference = 'Continue'
        $common = $script:WingetCommon
        $out = & (Get-WingetCommand) export -o $tmp @common 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0 -or -not (Test-Path -LiteralPath $tmp)) {
            $msg = ((@($out) | ForEach-Object { [string]$_ } | Where-Object { $_ -and $_ -notmatch 'not available from any source|không có sẵn' } | Select-Object -Last 3) -join ' ').Trim()
            return [pscustomobject]@{ Ok = $false; Ids = @(); Error = ('winget export mã {0}: {1}' -f $code, $msg) }
        }
        $j = [IO.File]::ReadAllText($tmp) | ConvertFrom-Json
        $ids = @($j.Sources | ForEach-Object { $_.Packages } | ForEach-Object { [string]$_.PackageIdentifier } | Where-Object { $_ })
        return [pscustomobject]@{ Ok = $true; Ids = $ids; Error = '' }
    } catch { return [pscustomobject]@{ Ok = $false; Ids = @(); Error = $_.Exception.Message } }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Get-AppPackage {
    # Bộ cài có sẵn trong bản portable cho ứng dụng này ($null khi không có).
    param($App)
    if (-not $script:BoCaiRoot) { return $null }
    return (Get-BoCaiPackage $script:BoCaiRoot $App.id)
}

function Get-InstalledState {
    # Ứng dụng đã cài: mã gói từ winget export (khi winget dùng được) và Programs and Features (cho ứng dụng có bộ cài
    # sẵn: nhận cả bản cài từ gói mà winget không khớp được, và máy không có winget).
    $w = if (Get-WingetCommand) { Get-InstalledIds } else { $null }
    $pkgs = @($script:AllApps | Where-Object { Get-AppPackage $_ })
    return [pscustomobject]@{
        HasWinget = [bool]$w; WingetOk = [bool]($w -and $w.Ok)
        Ids = @($(if ($w -and $w.Ok) { $w.Ids }))
        Programs = $(if ($pkgs.Count) { Get-InstalledPrograms } else { @() })
        Packaged = $pkgs.Count
        Error = $(if ($w) { $w.Error } else { '' })
    }
}

function Test-Installed {
    param($App, $State)
    if (@($State.Ids | Where-Object { $_ -eq $App.id }).Count) { return $true }   # mã gói không phân biệt hoa thường
    if (-not @($State.Programs).Count) { return $false }
    $p = Get-AppPackage $App
    return [bool]($p -and (Test-BoCaiInstalled $p $State.Programs))
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

function Test-WingetReady {
    # Đọc danh sách đã cài. winget hỏng mà có bộ cài sẵn thì chỉ cảnh báo (cài từ gói, xem đã cài trong Programs and
    # Features); không có bộ cài thì ghi lỗi, trả $null. -CanWinget: việc này cần winget (cập nhật).
    param([switch]$CanWinget)
    $s = Get-InstalledState
    if ($s.WingetOk) { return $s }
    $soft = $s.Packaged -and -not $CanWinget
    $t1 = 'Máy chưa có winget (App Installer)'
    $d1 = 'Windows 10 bản cũ, Windows LTSC hoặc máy chưa đăng nhập Microsoft Store lần nào thường thiếu.'
    $f1 = 'Cài App Installer từ Microsoft Store, hoặc trong Trạm Tool mở Máy này > Sửa winget.'
    $t2 = 'winget không đọc được danh sách ứng dụng'
    $f2 = 'Trong Trạm Tool mở Máy này > Sửa winget (đăng ký lại App Installer, cập nhật nguồn).'
    $vi = "Có bộ cài sẵn cho $($s.Packaged) ứng dụng trong bản này: cài từ đó, xem đã cài trong Programs and Features."
    if ($soft) {
        if (-not $s.HasWinget) { Add-Finding 'WINGET_KHONG_CO' 'canh-bao' $t1 "$d1 $vi" $f1 } else { Add-Finding 'WINGET_LOI' 'canh-bao' $t2 "$($s.Error) $vi".Trim() $f2 }
        return $s
    }
    if (-not $s.HasWinget) { Add-Finding 'WINGET_KHONG_CO' 'loi' $t1 $d1 $f1 } else { Add-Finding 'WINGET_LOI' 'loi' $t2 $s.Error $f2 }
    return $null
}

function Get-WingetInstallArgs {
    # Lệnh winget cài một ứng dụng (ghim bản khi DanhSach.json có phienBan).
    param($App)
    $a = @('install', '--id', $App.id, '-e')
    if ($App.phienBan) { $a += @('--version', [string]$App.phienBan) }
    return , ($a + @('--silent', '--accept-package-agreements') + $script:WingetCommon)
}

function Invoke-Check {
    Write-Head 'Ứng dụng trong danh sách'
    $apps = Read-AppList
    $r = Test-WingetReady
    if (-not $r) { return 2 }
    $have = @($apps | Where-Object { Test-Installed $_ $r })
    $missDefault = @($apps | Where-Object { $_.macDinh -and -not (Test-Installed $_ $r) })
    $missOther = @($apps | Where-Object { -not $_.macDinh -and -not (Test-Installed $_ $r) })
    if ($r.Packaged) {
        $noPkg = @($apps | Where-Object { -not (Get-AppPackage $_) })
        Add-Finding 'BO_CAI_CO_SAN' 'thong-tin' ('Có bộ cài sẵn trong bản này cho {0}/{1} ứng dụng: cài không cần mạng' -f $r.Packaged, $apps.Count) $(if ($noPkg.Count) { 'Cài qua winget (cần mạng): ' + (($noPkg | ForEach-Object { $_.ten }) -join ', ') + '.' } else { '' })
    }
    if ($have.Count) { Add-Finding 'UNG_DUNG_DA_CAI' 'ok' ('Đã cài {0}/{1}: {2}' -f $have.Count, $apps.Count, (($have | ForEach-Object { $_.ten }) -join ', ')) }
    if ($missDefault.Count) {
        Add-Finding 'UNG_DUNG_MAC_DINH_CHUA_CAI' 'thong-tin' ('Ứng dụng mặc định chưa cài: {0}' -f (($missDefault | ForEach-Object { $_.ten }) -join ', ')) '' 'Chạy "Cài ứng dụng" (các ô mặc định đã đánh dấu sẵn).' 'bo-ung-dung/cai'
    } else { Write-Ok 'Đã cài đủ các ứng dụng mặc định.' }
    if ($missOther.Count) { Write-Info ('Có thể cài thêm: {0}' -f (($missOther | ForEach-Object { $_.ten }) -join ', ')) }
    $bothGo = @($have | Where-Object { $_.nhom } | Group-Object nhom | Where-Object { $_.Count -gt 1 })
    foreach ($g in $bothGo) {
        Add-Finding 'CUNG_NHOM_CAI_HAI' 'canh-bao' ('Đang cài cùng lúc {0}' -f (($g.Group | ForEach-Object { $_.ten }) -join ' và ')) 'Hai bộ gõ tiếng Việt chạy cùng lúc hay làm gõ sai dấu.' 'Gỡ một bộ trong Cài đặt > Ứng dụng.'
    }
    return 0
}

function Save-RunResult {
    # Ghi kết quả lần chạy cho Trạm Tool (chuẩn tramtool.ketqua/1).
    param([string]$CheDo, [int]$Code, [datetime]$Start, [string]$Message = '')
    $i = 0
    $sorted = @($script:Findings | ForEach-Object { [pscustomobject]@{ F = $_; L = $script:Levels[[string]$_.mucDo]; I = $i++ } } | Sort-Object L, I | ForEach-Object { $_.F })
    $nLoi = @($sorted | Where-Object { $_.mucDo -eq 'loi' }).Count
    $nCanh = @($sorted | Where-Object { $_.mucDo -eq 'canh-bao' }).Count
    $nTin = @($sorted | Where-Object { $_.mucDo -eq 'thong-tin' }).Count
    if (-not $Message) { $Message = if ($nLoi + $nCanh) { 'Có {0} lỗi, {1} cảnh báo; xem chi tiết.' -f $nLoi, $nCanh } else { 'Xong, không có lỗi.' } }
    $r = [ordered]@{
        chuan = 'tramtool.ketqua/1'; congCu = 'bo-ung-dung'; cheDo = $CheDo; phienBan = $script:Version
        may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
        batDau = $Start.ToString('s'); ketThuc = (Get-Date).ToString('s')
        maThoat = $Code; trangThai = @{ 0 = 'xong'; 1 = 'loi'; 2 = 'thieu-dieu-kien'; 3 = 'mot-phan' }[$Code]
        chayThu = [bool]$ChayThu
        ma = $(if ($nLoi) { 'CO_LOI' } elseif ($nCanh) { 'CO_CANH_BAO' } else { 'KHONG_CO_LOI' })
        thongDiep = $Message
        tomTat = [ordered]@{ loi = $nLoi; canhBao = $nCanh; thongTin = $nTin }
        phatHien = $sorted
        tep = @()
    }
    try {
        if (-not (Test-Path -LiteralPath $script:ResultDir)) { New-Item -ItemType Directory -Path $script:ResultDir -Force | Out-Null }
        $f = Join-Path $script:ResultDir ('KetQua_BoUngDung_{0}_{1:yyyyMMdd_HHmmss}.json' -f $env:COMPUTERNAME, $Start)
        $tmp = "$f.tmp"
        [IO.File]::WriteAllText($tmp, ($r | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding $false))
        Move-Item -LiteralPath $tmp -Destination $f -Force
        Write-Info "Kết quả cho Trạm Tool: $f"
    } catch { Write-Warn "Không ghi được file kết quả: $($_.Exception.Message.Trim())" }
}

# ---------------------------------------------------------------- cài, cập nhật
function Invoke-Cai {
    param([object[]]$Chosen, [switch]$DryRun, [switch]$Ask)
    Write-Head 'Cài ứng dụng'
    $r = Test-WingetReady
    if (-not $r) { return 2 }
    $todo = @(); $seen = @{}
    foreach ($a in $Chosen) {
        if (Test-Installed $a $r) { Write-Ok "Đã có: $($a.ten)"; continue }
        if ($a.nhom) {
            $other = @($script:AllApps | Where-Object { $_.nhom -eq $a.nhom -and $_.khoa -ne $a.khoa -and (Test-Installed $_ $r) })
            if ($seen.ContainsKey($a.nhom) -or $other.Count) {
                $why = if ($other.Count) { "máy đã có $($other[0].ten)" } else { "đã chọn $($seen[$a.nhom])" }
                Add-Finding 'BO_QUA_CUNG_NHOM' 'canh-bao' "Bỏ qua $($a.ten): $why" 'Hai ứng dụng cùng loại (bộ gõ tiếng Việt) chạy cùng lúc hay xung đột; chỉ cài một.'
                continue
            }
            $seen[$a.nhom] = $a.ten
        }
        $todo += $a
    }
    if (-not $todo.Count) { Write-Info 'Không có ứng dụng nào cần cài.'; return 0 }
    Write-Line ''
    Write-Line 'Sẽ cài:'
    $how = @{}
    foreach ($a in $todo) {
        $p = Get-AppPackage $a
        if ($p) { $how[$a.khoa] = 'goi'; Write-Plan ('{0}   bộ cài có sẵn trong bản này (bản {1}, không cần mạng)' -f $a.ten, $p.phienBan) }
        elseif ($r.WingetOk) { $how[$a.khoa] = 'winget'; Write-Plan ('{0}   winget {1}' -f $a.ten, ((Get-WingetInstallArgs $a | Select-Object -First 6) -join ' ')) }
        else { $how[$a.khoa] = ''; Write-Plan ('{0}   không có bộ cài sẵn, winget không dùng được: bỏ qua' -f $a.ten) }
        if ($a.ghiChu) { Write-Sub $a.ghiChu }
    }
    if ($DryRun) { Write-Info 'Chạy thử: không cài gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo 'Cài các ứng dụng trên?' $false)) { Write-Info 'Đã huỷ, chưa cài gì.'; return 2 }

    $codes = @{}; $msgs = @{}
    foreach ($a in $todo) {
        if (-not $how[$a.khoa]) { continue }
        Write-Line ''
        Write-Line "Đang cài $($a.ten)..."
        if ($how[$a.khoa] -eq 'goi') {
            $b = Install-BoCaiPackage -Root $script:BoCaiRoot -Id $a.id
            if ($b.Ok) { $codes[$a.khoa] = $(if ($b.Reboot) { $script:CodeReboot } else { 0 }); continue }
            $msgs[$a.khoa] = $b.Message
            Write-Warn "Bộ cài có sẵn: $($b.Message)"
            if (-not $r.WingetOk) { $codes[$a.khoa] = $b.Code; continue }
            Write-Info 'Thử cài bằng winget.'
        }
        $codes[$a.khoa] = Invoke-Winget (Get-WingetInstallArgs $a)
        $how[$a.khoa] = 'winget'
    }
    # Đọc lại danh sách đã cài thay vì tin mã thoát (bộ cài có thể báo 0 mà chưa cài, hoặc báo lỗi phụ mà đã cài).
    # Không xác nhận được (winget hỏng, ứng dụng không có trong Programs and Features) thì tin mã thoát.
    $after = Get-InstalledState
    Write-Line ''
    $ok = 0; $fail = 0; $reboot = $false
    foreach ($a in $todo) {
        if (-not $how[$a.khoa]) {
            Add-Finding 'CAI_KHONG_CO_NGUON' 'loi' "Chưa cài được $($a.ten)" 'Bản này không có bộ cài sẵn của ứng dụng này và winget không dùng được.' 'Sửa winget (Máy này > Sửa winget) rồi chạy lại, hoặc dùng bản portable đầy đủ.'
            $fail++; continue
        }
        $c = $codes[$a.khoa]
        $now = Test-Installed $a $after
        $canSee = $after.WingetOk -or [bool]((Get-AppPackage $a) -and @($after.Programs).Count)
        if ($c -eq $script:CodeReboot) { $reboot = $true }
        $src = if ($how[$a.khoa] -eq 'goi') { 'bộ cài có sẵn' } else { 'winget' }
        if ($now -or (-not $canSee -and $c -in 0, $script:CodeReboot)) {
            Add-Finding 'DA_CAI' 'ok' "Đã cài $($a.ten)" $(if ($c -ne 0) { "$src báo mã $c nhưng ứng dụng đã có trong danh sách đã cài." } elseif ($how[$a.khoa] -eq 'goi') { 'Từ bộ cài có sẵn trong bản này.' } else { '' })
            $ok++
        } else {
            $why = if ($msgs[$a.khoa] -and $how[$a.khoa] -eq 'goi') { $msgs[$a.khoa] } else { '{0} mã {1}{2}.' -f $src, $c, $(if ($c -eq 0) { ' nhưng không thấy trong danh sách đã cài' } else { '' }) }
            Add-Finding 'CAI_LOI' 'loi' "Chưa cài được $($a.ten)" $why 'Chạy lại; vẫn lỗi thì xem dòng báo lỗi trong cửa sổ công cụ, hoặc kiểm tra mạng.'
            $fail++
        }
    }
    if ($reboot) { Add-Finding 'CAN_KHOI_DONG_LAI' 'thong-tin' 'Có ứng dụng cần khởi động lại máy để cài xong' }
    if ($fail -and $ok) { return 3 }
    if ($fail) { return 1 }
    return 0
}

function Invoke-CapNhat {
    param([switch]$DryRun, [switch]$Ask)
    Write-Head 'Cập nhật ứng dụng trong danh sách'
    $r = Test-WingetReady -CanWinget
    if (-not $r) { return 2 }
    # Ứng dụng ghim bản (DanhSach.json phienBan) không cập nhật: bản mới hơn không cài được trên máy này.
    $todo = @($script:AllApps | Where-Object { -not $_.phienBan -and (Test-Installed $_ $r) })
    if (-not $todo.Count) { Write-Info 'Chưa cài ứng dụng nào trong danh sách.'; return 0 }
    Write-Line 'Sẽ kiểm tra bản mới và cập nhật:'
    foreach ($a in $todo) { Write-Plan ('{0}   winget upgrade --id {1} -e --silent' -f $a.ten, $a.id) }
    if ($DryRun) { Write-Info 'Chạy thử: không cập nhật gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo 'Cập nhật các ứng dụng trên?' $false)) { Write-Info 'Đã huỷ.'; return 2 }
    $up = @(); $same = @(); $fail = 0
    foreach ($a in $todo) {
        Write-Line ''
        Write-Line "Đang kiểm tra $($a.ten)..."
        $c = Invoke-Winget (@('upgrade', '--id', $a.id, '-e', '--silent', '--accept-package-agreements') + $script:WingetCommon)
        if ($c -eq 0 -or $c -eq $script:CodeReboot) { $up += $a.ten }
        elseif ($c -eq $script:CodeNoUpdate) { $same += $a.ten }
        else { Add-Finding 'CAP_NHAT_LOI' 'loi' "Chưa cập nhật được $($a.ten)" "winget upgrade mã $c." 'Chạy lại; ứng dụng đang mở thì đóng trước khi cập nhật.'; $fail++ }
    }
    Write-Line ''
    if ($up.Count) { Add-Finding 'DA_CAP_NHAT' 'ok' ('Đã cập nhật: {0}' -f ($up -join ', ')) }
    if ($same.Count) { Add-Finding 'DA_MOI_NHAT' 'ok' ('Đã là bản mới nhất: {0}' -f ($same -join ', ')) }
    if ($fail -and ($up.Count + $same.Count)) { return 3 }
    if ($fail) { return 1 }
    return 0
}

function Invoke-Mode {
    # Chạy một chế độ, ghi file kết quả. Trả mã thoát.
    param([string]$Id, [object[]]$Chosen = @(), [switch]$Ask)
    $start = Get-Date
    $script:Findings.Clear()
    $code = 0; $msg = ''
    try {
        $script:AllApps = Read-AppList
        switch ($Id) {
            'kiem-tra' { $code = Invoke-Check }
            'cai' {
                if (-not $Chosen.Count) { $Chosen = Get-SelectedApps $script:AllApps $ConLai }
                $code = Invoke-Cai $Chosen -DryRun:$ChayThu -Ask:$Ask
            }
            'cap-nhat' { $code = Invoke-CapNhat -DryRun:$ChayThu -Ask:$Ask }
        }
    } catch {
        Add-Finding 'LOI_KHONG_LUONG_TRUOC' 'loi' ('Lỗi: {0}' -f $_.Exception.Message.Trim())
        $code = 1
    }
    if ($Id -ne 'kiem-tra') {
        $msg = switch ($code) {
            0 { if ($ChayThu) { 'Chạy thử: chỉ xem việc sẽ làm, máy không bị đổi.' } else { '{0}: xong.' -f $script:Modes[$Id].Label } }
            2 { 'Chưa làm: thiếu winget, thiếu quyền Admin hoặc đã huỷ.' }
            3 { '{0}: làm được một phần, xem mục lỗi.' -f $script:Modes[$Id].Label }
            default { '{0}: lỗi, xem mục lỗi.' -f $script:Modes[$Id].Label }
        }
    }
    Save-RunResult -CheDo $Id -Code $code -Start $start -Message $msg
    return $code
}

function Read-MenuChoice {
    # Hỏi chọn ứng dụng bằng số. Enter: các ứng dụng mặc định. Trả danh sách ứng dụng ($null khi không chọn gì).
    $apps = Read-AppList
    $script:AllApps = $apps
    $r = Get-InstalledState
    Write-Host ''
    for ($i = 0; $i -lt $apps.Count; $i++) {
        $a = $apps[$i]
        $mark = if (Test-Installed $a $r) { '[đã cài]' } elseif ($a.macDinh) { '*' } else { '' }
        Write-Host ('   {0,2}. {1} {2}' -f ($i + 1), $a.ten, $mark)
    }
    Write-Host ''
    $t = Read-Text 'Gõ số các ứng dụng cần cài, cách nhau bằng dấu cách (Enter: các mục có dấu *, 0: quay lại)' ''
    if ($t -eq '0') { return $null }
    if (-not $t) { return @($apps | Where-Object { $_.macDinh }) }
    $pick = @()
    foreach ($n in ($t -split '[\s,;]+' | Where-Object { $_ })) {
        $k = 0
        if ([int]::TryParse($n, [ref]$k) -and $k -ge 1 -and $k -le $apps.Count) { $pick += $apps[$k - 1] }
        else { Write-Warn "Bỏ qua ""$n"": không có số này." }
    }
    return $pick
}

function Invoke-ElevatedMode {
    # Mở một chế độ trong cửa sổ Admin riêng (Windows hỏi UAC), chờ xong, trả mã thoát. Dùng cho menu.
    param([string]$Id, [string[]]$Keys = @())
    $argText = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -DaNangQuyen -Mode {1} {2}' -f $PSCommandPath, $Id, (($Keys | ForEach-Object { "-$_" }) -join ' ')
    try { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argText -Verb RunAs -Wait -PassThru; return [int]$p.ExitCode }
    catch {
        $e = $_.Exception; $native = 0
        while ($e) { if ($e -is [ComponentModel.Win32Exception]) { $native = $e.NativeErrorCode; break }; $e = $e.InnerException }
        if ($native -eq 1223) { Write-Warn 'Bạn đã chọn "Không" ở hộp thoại quyền Admin nên chưa chạy.'; return 2 }
        Write-Bad "Không mở được bằng quyền Admin: $($_.Exception.Message.Trim())"
        return 1
    }
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '  BỘ ỨNG DỤNG VĂN PHÒNG (WINGET)' -ForegroundColor Cyan
        Write-Host '  Cài từ nguồn winget của Microsoft, không tải bộ cài trôi nổi trên mạng.' -ForegroundColor Gray
        Write-Host ''
        foreach ($id in $script:Modes.Keys) { Write-Host ('   {0}. {1}' -f $script:Modes[$id].No, $script:Modes[$id].Label) }
        Write-Host '   0. Thoát'
        Write-Host ''
        $c = Read-Text 'Chọn số' '0'
        if ($c -eq '0') { return 0 }
        $id = $null
        foreach ($k in $script:Modes.Keys) { if ([string]$script:Modes[$k].No -eq $c) { $id = $k } }
        if (-not $id) { continue }
        $chosen = @()
        if ($id -eq 'cai') {
            try { $chosen = Read-MenuChoice } catch { Write-Bad $_.Exception.Message; continue }
            if (-not $chosen -or -not @($chosen).Count) { continue }
        }
        if ($script:Modes[$id].Admin -and -not (Test-IsAdmin)) { [void](Invoke-ElevatedMode $id @($chosen | ForEach-Object { $_.khoa })); continue }
        [void](Invoke-Mode $id -Chosen $chosen -Ask)
        Wait-Close 'Bấm Enter để về menu'
    }
}

# ---------------------------------------------------------------- bắt đầu
if ($env:TRAMTOOL_BOUNGDUNG_TEST) { return }   # bài thử nạp các hàm rồi tự gọi
try { $Host.UI.RawUI.WindowTitle = 'Bộ ứng dụng văn phòng' } catch { }
if ($Mode -and -not $script:Modes.Contains($Mode)) {
    Write-Bad ('Không có chế độ "{0}". Các chế độ: {1}.' -f $Mode, (@($script:Modes.Keys) -join ', '))
    Wait-Close
    exit 1
}
if ($Mode -and $script:Modes[$Mode].Admin -and -not $ChayThu -and -not (Test-IsAdmin)) {
    if ($DaNangQuyen) { Write-Bad 'Đã mở lại mà vẫn chưa có quyền Admin.'; Wait-Close; exit 2 }
    Write-Info 'Cài, cập nhật ứng dụng cần quyền Admin: Windows sẽ hỏi (UAC), chọn "Có".'
    $argText = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -DaNangQuyen -Mode {1}{2} {3}' -f $PSCommandPath, $Mode, $(if ($KhongDung) { ' -KhongDung' }), ((@($ConLai) | Where-Object { $_ } | ForEach-Object { [string]$_ }) -join ' ')
    try { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $argText -Verb RunAs -Wait -PassThru }
    catch {
        $e = $_.Exception; $native = 0
        while ($e) { if ($e -is [ComponentModel.Win32Exception]) { $native = $e.NativeErrorCode; break }; $e = $e.InnerException }
        if ($native -eq 1223) { Write-Warn 'Bạn đã chọn "Không" ở hộp thoại quyền Admin nên chưa chạy.'; exit 2 }
        Write-Bad "Không mở được bằng quyền Admin: $($_.Exception.Message.Trim())"
        exit 1
    }
    exit $p.ExitCode
}
if (-not $Mode) {
    if ([Console]::IsInputRedirected) { Write-Host 'Cách dùng: BoUngDung.ps1 -Mode kiem-tra|cai|cap-nhat [-Zalo -UniKey ...] [-ChayThu] [-KhongDung]'; exit 1 }
    exit (Show-Menu)
}
$code = Invoke-Mode $Mode
Wait-Close
exit $code
