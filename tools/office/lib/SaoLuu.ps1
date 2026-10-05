# Office - sao lưu và trả lại dữ liệu người dùng của Office: mẫu Word (Normal.dotm), Building Blocks, từ điển riêng,
# AutoCorrect, macro Excel dùng chung (PERSONAL.XLSB), add-in, ribbon và thanh công cụ đã chỉnh, chữ ký Outlook.
# Tuỳ chọn: thiết lập Office trong registry (HKCU\Software\Microsoft\Office) khi sắp xoá thiết lập.
# Bản sao lưu: ket_qua\sao-luu\SaoLuu_<máy>_<thời gian>\ kèm SaoLuu.json (mục nào, lấy từ đâu).
# Gỡ Office không xoá các file này; sao lưu để phòng khi quét sâu, xoá thiết lập, hay cài lại làm mất.

# Path: nơi lấy (biến môi trường của người đang chạy). Filter: chỉ lấy file khớp ở ngay thư mục đó.
$script:UserDataItems = @(
    [pscustomobject]@{ Id = 'templates'; Label = 'Mẫu Word, Excel, PowerPoint (Normal.dotm...)'; Path = '%APPDATA%\Microsoft\Templates'; Filter = ''; Exclude = @('LiveContent') }
    [pscustomobject]@{ Id = 'building-blocks'; Label = 'Building Blocks, Quick Parts của Word'; Path = '%APPDATA%\Microsoft\Document Building Blocks'; Filter = ''; Exclude = @() }
    [pscustomobject]@{ Id = 'quickstyles'; Label = 'Bộ kiểu (Style Set) của Word'; Path = '%APPDATA%\Microsoft\QuickStyles'; Filter = ''; Exclude = @() }
    [pscustomobject]@{ Id = 'uproof'; Label = 'Từ điển riêng'; Path = '%APPDATA%\Microsoft\UProof'; Filter = ''; Exclude = @() }
    [pscustomobject]@{ Id = 'proof'; Label = 'Từ điển riêng (Office cũ)'; Path = '%APPDATA%\Microsoft\Proof'; Filter = ''; Exclude = @() }
    [pscustomobject]@{ Id = 'autocorrect'; Label = 'Danh sách AutoCorrect (.acl)'; Path = '%APPDATA%\Microsoft\Office'; Filter = '*.acl'; Exclude = @() }
    [pscustomobject]@{ Id = 'word-startup'; Label = 'Add-in Word tự chạy (STARTUP)'; Path = '%APPDATA%\Microsoft\Word\STARTUP'; Filter = ''; Exclude = @() }
    [pscustomobject]@{ Id = 'xlstart'; Label = 'Macro Excel dùng chung (XLSTART, PERSONAL.XLSB)'; Path = '%APPDATA%\Microsoft\Excel\XLSTART'; Filter = ''; Exclude = @() }
    [pscustomobject]@{ Id = 'excel-toolbars'; Label = 'Thanh công cụ Excel (.xlb)'; Path = '%APPDATA%\Microsoft\Excel'; Filter = '*.xlb'; Exclude = @() }
    [pscustomobject]@{ Id = 'addins'; Label = 'Add-in Excel, PowerPoint (.xlam, .ppam...)'; Path = '%APPDATA%\Microsoft\AddIns'; Filter = ''; Exclude = @() }
    [pscustomobject]@{ Id = 'ribbon'; Label = 'Ribbon, Quick Access đã chỉnh (.officeUI)'; Path = '%LOCALAPPDATA%\Microsoft\Office'; Filter = '*.officeUI'; Exclude = @() }
    [pscustomobject]@{ Id = 'signatures'; Label = 'Chữ ký Outlook'; Path = '%APPDATA%\Microsoft\Signatures'; Filter = ''; Exclude = @() }
)
$script:OfficeRegKey = 'HKCU\Software\Microsoft\Office'

function Get-UserDataPlan {
    # Các mục có dữ liệu của người đang chạy: @{ Item; Source; Files; Bytes }.
    $list = foreach ($it in $script:UserDataItems) {
        $src = [Environment]::ExpandEnvironmentVariables($it.Path)
        if (-not (Test-Path -LiteralPath $src -PathType Container)) { continue }
        if ($it.Filter) {
            $files = @(Get-ChildItem -LiteralPath $src -Filter $it.Filter -File -Force -ErrorAction SilentlyContinue)
            if (-not $files.Count) { continue }
            $size = [pscustomobject]@{ Files = $files.Count; Bytes = [int64](($files | Measure-Object Length -Sum).Sum) }
        } else {
            $size = Get-FolderSize $src $it.Exclude
            if (-not $size.Files) { continue }
        }
        [pscustomobject]@{ Item = $it; Source = $src; Files = $size.Files; Bytes = $size.Bytes }
    }
    return @($list)
}

function Copy-Folder {
    # Chép bằng robocopy (giữ thời gian file, bỏ qua junction, thử lại ít lần với file đang mở).
    # Trả $true khi chép được (mã robocopy dưới 8).
    param([string]$From, [string]$To, [string]$Filter = '', [string[]]$ExcludeDirs = @(), [switch]$Recurse)
    $a = @($From.TrimEnd('\'), $To.TrimEnd('\'))
    if ($Filter) { $a += $Filter }
    if ($Recurse) { $a += '/E' }
    $a += @('/XJ', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($ExcludeDirs.Count) { $a += '/XD'; $a += @($ExcludeDirs | ForEach-Object { Join-Path $From $_ }) }
    $r = Invoke-Native 'robocopy.exe' $a
    return ($r.Code -lt 8)
}

function Backup-OfficeUserData {
    # Sao lưu dữ liệu Office của người đang chạy. -Registry: xuất thêm HKCU\Software\Microsoft\Office ra Office.reg.
    # Trả @{ Dir; Items (đã chép); Failed (tên mục lỗi); Registry ($true khi xuất được) }.
    param([switch]$Registry, [string]$Reason = 'truoc-khi-go')
    $started = Get-Date
    $base = Join-Path (Get-ResultDir 'sao-luu') ('SaoLuu_{0}_{1:yyyyMMdd_HHmmss}' -f $env:COMPUTERNAME, $started)
    $dir = $base
    for ($n = 2; Test-Path -LiteralPath $dir; $n++) { $dir = "${base}_$n" }   # hai lần sao lưu trong cùng một giây
    [void](New-Item -ItemType Directory -Path $dir)
    $done = @(); $failed = @()
    foreach ($p in (Get-UserDataPlan)) {
        $dest = Join-Path $dir $p.Item.Id
        $ok = if ($p.Item.Filter) { Copy-Folder $p.Source $dest -Filter $p.Item.Filter } else { Copy-Folder $p.Source $dest -ExcludeDirs $p.Item.Exclude -Recurse }
        if ($ok) { $done += [pscustomobject]@{ id = $p.Item.Id; label = $p.Item.Label; path = $p.Item.Path; filter = $p.Item.Filter; files = $p.Files; bytes = $p.Bytes } }
        else { $failed += $p.Item.Label }
    }
    $regOk = $false
    if ($Registry) {
        $r = Invoke-Native 'reg.exe' @('export', $script:OfficeRegKey, (Join-Path $dir 'Office.reg'), '/y')
        $regOk = ($r.Code -eq 0 -and (Test-Path -LiteralPath (Join-Path $dir 'Office.reg')))
        if (-not $regOk) { $failed += 'Thiết lập Office trong registry' }
    }
    $manifest = [ordered]@{
        tool = 'office'; version = $script:ToolVersion; reason = $Reason; computer = $env:COMPUTERNAME; user = (Get-CurrentUser)
        created = $started.ToString('yyyy-MM-ddTHH:mm:ss'); items = @($done); registry = $(if ($regOk) { 'Office.reg' } else { '' })
    }
    [IO.File]::WriteAllText((Join-Path $dir 'SaoLuu.json'), ($manifest | ConvertTo-Json -Depth 4), $script:Utf8NoBom)
    return [pscustomobject]@{ Dir = $dir; Items = @($done); Failed = @($failed); Registry = $regOk }
}

function Show-UserDataPlan {
    # In những gì sẽ được sao lưu (dùng trong kiểm tra và kế hoạch gỡ).
    param($Plan)
    if (-not $Plan.Count) { Write-Line 'Không có mẫu, macro, chữ ký Office nào cần sao lưu.'; return }
    foreach ($p in $Plan) { Write-Line ('{0}: {1} file, {2}' -f $p.Item.Label, $p.Files, (Format-Size $p.Bytes)) }
}

# ---------------------------------------------------------------- trả lại
function Get-Backups {
    # Các bản sao lưu trong ket_qua\sao-luu, mới nhất trước.
    $root = Get-ResultDir 'sao-luu'
    $list = foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -Filter 'SaoLuu_*' -ErrorAction SilentlyContinue)) {
        $f = Join-Path $d.FullName 'SaoLuu.json'
        if (-not (Test-Path -LiteralPath $f)) { continue }
        try { $m = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { continue }
        $when = [datetime]::MinValue
        [void][datetime]::TryParse([string]$m.created, [ref]$when)
        [pscustomobject]@{ Name = $d.Name; Dir = $d.FullName; Manifest = $m; Created = $when }
    }
    return @($list | Sort-Object Created -Descending)
}

function Invoke-TraLai {
    # Chép lại dữ liệu từ một bản sao lưu. Trước khi chép đè, sao lưu dữ liệu hiện tại (để trả lại được lần này).
    param([string]$SaoLuu = '', [switch]$DryRun)
    Write-Out 'TRẢ LẠI MẪU, MACRO, CHỮ KÝ OFFICE ĐÃ SAO LƯU' 'Cyan'
    Write-Out ('Máy {0}, {1:dd/MM/yyyy HH:mm}, tài khoản {2}.' -f $env:COMPUTERNAME, (Get-Date), (Get-CurrentUser))
    $all = @(Get-Backups)
    if (-not $all.Count) { Write-Warn 'Chưa có bản sao lưu nào trong ket_qua\sao-luu.'; return 2 }
    $pick = $null
    if ($SaoLuu) {
        $pick = $all | Where-Object { $_.Name -ieq $SaoLuu } | Select-Object -First 1
        if (-not $pick) { Write-Bad "Không thấy bản sao lưu '$SaoLuu'."; return 2 }
    } else {
        Write-Head 'Các bản sao lưu'
        for ($i = 0; $i -lt [Math]::Min(15, $all.Count); $i++) {
            $b = $all[$i]
            Write-Line ('{0}. {1:dd/MM/yyyy HH:mm}  {2}, {3} mục{4}' -f ($i + 1), $b.Created, $b.Manifest.user, @($b.Manifest.items).Count, $(if ($b.Manifest.registry) { ', có thiết lập registry' } else { '' }))
        }
        if (Test-NoInput) { Write-Bad 'Chưa chọn bản sao lưu (tham số -SaoLuu).'; return 2 }
        $keys = @(1..[Math]::Min(15, $all.Count) | ForEach-Object { [string]$_ }) + 'H'
        $c = Read-Choice 'Chọn số bản sao lưu (H để huỷ)' $keys 'H'
        if ($c -eq 'H') { Write-Info 'Đã huỷ.'; return 1223 }
        $pick = $all[[int]$c - 1]
    }

    $m = $pick.Manifest
    Write-Head 'Sẽ trả lại'
    Write-Line ('Bản sao lưu {0} ({1:dd/MM/yyyy HH:mm}, tài khoản {2}, máy {3}).' -f $pick.Name, $pick.Created, $m.user, $m.computer)
    $items = @(@($m.items) | Where-Object { $_ -and $_.id -and (Test-Path -LiteralPath (Join-Path $pick.Dir ([string]$_.id))) })
    foreach ($it in $items) { Write-Plan ('{0} → {1}' -f $it.label, [Environment]::ExpandEnvironmentVariables([string]$it.path)) }
    $reg = if ($m.registry) { Join-Path $pick.Dir ([string]$m.registry) } else { '' }
    if ($reg -and (Test-Path -LiteralPath $reg)) { Write-Plan 'Thiết lập Office trong registry (hỏi riêng)' } else { $reg = '' }
    if (-not $items.Count -and -not $reg) { Write-Warn 'Bản sao lưu này không còn mục nào.'; return 2 }
    Write-Info 'File hiện có được sao lưu trước rồi mới chép đè; file chỉ có ở máy hiện tại được giữ nguyên.'
    if ([string]$m.user -and [string]$m.user -ine (Get-CurrentUser)) {
        Write-Warn ('Bản sao lưu của tài khoản {0}, đang trả lại vào tài khoản {1}.' -f $m.user, (Get-CurrentUser))
    }
    if ($DryRun) { Write-Info 'Chạy thử: máy chưa thay đổi gì.'; return 0 }
    if (-not (Read-YesNo 'Trả lại ngay?' $false)) { Write-Info 'Đã huỷ, máy chưa thay đổi gì.'; return 1223 }
    if ((Close-OfficeApps 'trả lại mẫu, macro') -eq 'cancel') { Write-Info 'Đã huỷ, máy chưa thay đổi gì.'; return 1223 }

    $before = Backup-OfficeUserData -Reason 'truoc-khi-tra-lai'
    Write-Ok ('Đã sao lưu dữ liệu hiện tại vào {0} (trả lại được bằng chính chức năng này).' -f (Split-Path -Leaf $before.Dir))
    $ok = 0; $fail = 0
    foreach ($it in $items) {
        $dest = [Environment]::ExpandEnvironmentVariables([string]$it.path)
        $src = Join-Path $pick.Dir $it.id
        $done = if ($it.filter) { Copy-Folder $src $dest -Filter ([string]$it.filter) } else { Copy-Folder $src $dest -Recurse }
        if ($done) { $ok++; Write-Ok $it.label } else { $fail++; Write-Bad ('{0}: chép không được.' -f $it.label) }
    }
    if ($reg) {
        Write-Warn 'Nhập lại thiết lập registry sẽ đè thiết lập Office hiện tại (cả hồ sơ Outlook).'
        if (Read-YesNo 'Nhập lại thiết lập Office trong registry?' $false) {
            $r = Invoke-Native 'reg.exe' @('import', $reg)
            if ($r.Code -eq 0) { $ok++; Write-Ok 'Đã nhập lại thiết lập Office.' } else { $fail++; Write-Bad ('Nhập registry lỗi {0}.' -f $r.Code) }
        }
    }
    if ($fail -eq 0) { return 0 }
    if ($ok -gt 0) { return 3 }
    return 1
}
