<#
  Bộ ứng dụng văn phòng bằng winget: cài một lượt các ứng dụng hay dùng (Zalo, bộ gõ tiếng Việt, 7-Zip, đọc PDF, hỗ trợ
  từ xa, trình duyệt...) từ nguồn winget chính thức của Microsoft, không tải bộ cài trôi nổi trên mạng.
  Danh sách nằm trong DanhSach.json (mã gói winget, tên, có cài mặc định không, nhóm chỉ chọn một).

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
$script:Version = '1.0'
$script:ListFile = Join-Path $PSScriptRoot 'DanhSach.json'
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

function Test-Installed {
    param($App, [string[]]$Ids)
    return [bool]@($Ids | Where-Object { $_ -eq $App.id }).Count   # mã gói không phân biệt hoa thường
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
    # Winget có và đọc được danh sách đã cài. Ghi phát hiện khi hỏng. Trả kết quả Get-InstalledIds hoặc $null.
    if (-not (Get-WingetCommand)) {
        Add-Finding 'WINGET_KHONG_CO' 'loi' 'Máy chưa có winget (App Installer)' 'Windows 10 bản cũ, Windows LTSC hoặc máy chưa đăng nhập Microsoft Store lần nào thường thiếu.' 'Cài App Installer từ Microsoft Store, hoặc trong Trạm Tool mở Máy này > Sửa winget.'
        return $null
    }
    $r = Get-InstalledIds
    if (-not $r.Ok) {
        Add-Finding 'WINGET_LOI' 'loi' 'winget không đọc được danh sách ứng dụng' $r.Error 'Trong Trạm Tool mở Máy này > Sửa winget (đăng ký lại App Installer, cập nhật nguồn).'
        return $null
    }
    return $r
}

function Invoke-Check {
    Write-Head 'Ứng dụng trong danh sách'
    $apps = Read-AppList
    $r = Test-WingetReady
    if (-not $r) { return 2 }
    $have = @($apps | Where-Object { Test-Installed $_ $r.Ids })
    $missDefault = @($apps | Where-Object { $_.macDinh -and -not (Test-Installed $_ $r.Ids) })
    $missOther = @($apps | Where-Object { -not $_.macDinh -and -not (Test-Installed $_ $r.Ids) })
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
        if (Test-Installed $a $r.Ids) { Write-Ok "Đã có: $($a.ten)"; continue }
        if ($a.nhom) {
            $other = @($script:AllApps | Where-Object { $_.nhom -eq $a.nhom -and $_.khoa -ne $a.khoa -and (Test-Installed $_ $r.Ids) })
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
    Write-Line 'Sẽ cài (nguồn winget của Microsoft):'
    foreach ($a in $todo) { Write-Plan ('{0}   winget install --id {1} -e --silent' -f $a.ten, $a.id); if ($a.ghiChu) { Write-Sub $a.ghiChu } }
    if ($DryRun) { Write-Info 'Chạy thử: không cài gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo 'Cài các ứng dụng trên?' $false)) { Write-Info 'Đã huỷ, chưa cài gì.'; return 2 }

    $codes = @{}
    foreach ($a in $todo) {
        Write-Line ''
        Write-Line "Đang cài $($a.ten)..."
        $codes[$a.khoa] = Invoke-Winget (@('install', '--id', $a.id, '-e', '--silent', '--accept-package-agreements') + $script:WingetCommon)
    }
    # Đọc lại danh sách đã cài thay vì tin mã thoát (bộ cài có thể báo 0 mà chưa cài, hoặc báo lỗi phụ mà đã cài).
    $after = Get-InstalledIds
    Write-Line ''
    $ok = 0; $fail = 0; $reboot = $false
    foreach ($a in $todo) {
        $c = $codes[$a.khoa]
        $now = $after.Ok -and (Test-Installed $a $after.Ids)
        if ($c -eq $script:CodeReboot) { $reboot = $true }
        if ($now -or (-not $after.Ok -and $c -in 0, $script:CodeReboot)) {
            Add-Finding 'DA_CAI' 'ok' "Đã cài $($a.ten)" $(if ($c -ne 0) { "winget báo mã $c nhưng ứng dụng đã có trong danh sách đã cài." } else { '' })
            $ok++
        } else {
            Add-Finding 'CAI_LOI' 'loi' "Chưa cài được $($a.ten)" ('winget install mã {0}{1}.' -f $c, $(if ($c -eq 0) { ' nhưng không thấy trong danh sách đã cài' } else { '' })) 'Chạy lại; vẫn lỗi thì xem dòng báo lỗi của winget trong cửa sổ công cụ, hoặc kiểm tra mạng.'
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
    $r = Test-WingetReady
    if (-not $r) { return 2 }
    $todo = @($script:AllApps | Where-Object { Test-Installed $_ $r.Ids })
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
    $r = Get-InstalledIds
    Write-Host ''
    for ($i = 0; $i -lt $apps.Count; $i++) {
        $a = $apps[$i]
        $mark = if ($r.Ok -and (Test-Installed $a $r.Ids)) { '[đã cài]' } elseif ($a.macDinh) { '*' } else { '' }
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
