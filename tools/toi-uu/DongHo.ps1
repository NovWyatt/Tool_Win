<#
  Tối ưu đồng hồ hệ thống: Dynamic Tick và HPET (useplatformclock) trong BCD, chỗ Windows thật sự đọc.
  Bản 1.0 ghi hai giá trị này vào registry (Session Manager\kernel) nên không có tác dụng; bản này dùng bcdedit cho
  mục khởi động hiện tại ({current}), đọc lại để xác nhận, và dọn giá trị registry bản cũ đã ghi.

  Một phần của công cụ "Tối ưu Windows" (ToiUu.ps1); trước đây là công cụ riêng "Tối ưu đồng hồ hệ thống".
  Không có -Mode: hiện menu (mục 3 của menu TOI_UU.bat). -Mode <chế độ>: chạy thẳng (Trạm Tool dùng cách này).
  Chế độ: kiem-tra (chỉ đọc), choi-game (tắt Dynamic Tick, bỏ ép HPET), mac-dinh (trả về mặc định của Windows).
  -ChayThu: chỉ in việc sẽ làm, không đổi máy. -KhongDung: không chờ Enter khi xong.
  -KetQua <file>: kiem-tra ghi thêm các phát hiện (có mã, mức, nút gợi ý) vào file này để ToiUu.ps1 gộp.
  Mã thoát: 0 xong, 1 lỗi, 2 thiếu điều kiện (quyền Admin, BitLocker chưa tạm dừng), 3 làm được một phần.
#>
param(
    [string]$Mode = '',
    [switch]$ChayThu,
    [switch]$KhongDung,
    [string]$KetQua = '',
    [switch]$DaNangQuyen   # đánh dấu cửa sổ đã mở lại bằng quyền Admin, để không hỏi UAC lần nữa
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:KernelKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
$script:OldValues = @('useplatformclock', 'disabledynamictick')
$script:Elements = [ordered]@{
    disabledynamictick = 'Tắt Dynamic Tick'
    useplatformclock   = 'Ép dùng HPET làm đồng hồ chính'
    useplatformtick    = 'Ép dùng đồng hồ nền tảng cho nhịp hẹn giờ'
}
$script:Modes = [ordered]@{
    'kiem-tra'  = @{ No = 1; Label = 'Xem thiết lập hiện tại' }
    'choi-game' = @{ No = 2; Label = 'Tối ưu cho chơi game (tắt Dynamic Tick, bỏ ép HPET)' }
    'mac-dinh'  = @{ No = 3; Label = 'Trả về mặc định của Windows' }
}

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

# ---------------------------------------------------------------- phát hiện cho Trạm Tool
$script:Findings = New-Object System.Collections.ArrayList
function Add-Finding {
    # Một phát hiện theo chuẩn tramtool.ketqua/1; $Tiep 'cong-cu/action' là nút gợi ý chạy tiếp trong Trạm.
    param([string]$Ma, [string]$Muc, [string]$TieuDe, [string]$ChiTiet = '', [string]$CachSua = '', [string]$Tiep = '')
    $f = [ordered]@{ ma = $Ma; mucDo = $Muc; tieuDe = $TieuDe; chiTiet = $ChiTiet; cachSua = $CachSua }
    if ($Tiep -match '^([a-z0-9-]+)/([A-Za-z0-9_-]+)$') { $f['chayTiep'] = [ordered]@{ congCu = $Matches[1]; action = $Matches[2] } }
    [void]$script:Findings.Add($f)
}

function Save-Findings {
    # Ghi các phát hiện của lần Kiểm tra ra file cho ToiUu.ps1 gộp (ghi file tạm rồi đổi tên).
    param([string]$Path)
    $doc = [ordered]@{ phatHien = @($script:Findings.ToArray()) }
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, ($doc | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# ---------------------------------------------------------------- BCD
function Get-BcdEditPath {
    # PowerShell 32 bit trên Windows 64 bit không thấy System32\bcdedit.exe (chuyển hướng sang SysWOW64).
    $native = Join-Path $env:SystemRoot 'Sysnative\bcdedit.exe'
    if (Test-Path -LiteralPath $native) { return $native }
    return (Join-Path $env:SystemRoot 'System32\bcdedit.exe')
}

function Invoke-BcdEdit {
    # Chạy bcdedit, trả mã thoát và toàn bộ chữ in ra (để báo lỗi đúng lời Windows).
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $out = & (Get-BcdEditPath) @Arguments 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = ((@($out) | ForEach-Object { [string]$_ }) -join "`n").Trim() }
}

function ConvertTo-BcdBool {
    # bcdedit in Yes/No (một số bản Windows dịch sang tiếng địa phương).
    param([string]$Raw)
    return ([string]$Raw).Trim() -match '^(yes|true|on|1|ja|oui|s[ií]|sim|có|evet|tak|ano|да|是)$'
}

function ConvertFrom-BcdEnum {
    # Đọc các phần tử cần quan tâm từ chữ của 'bcdedit /enum {current}'. Tên phần tử luôn là tiếng Anh.
    param([string]$Text)
    $state = [ordered]@{}
    foreach ($name in $script:Elements.Keys) { $state[$name] = [pscustomobject]@{ Set = $false; On = $false; Raw = '' } }
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*([A-Za-z]+)\s+(\S.*?)\s*$' -and $state.Contains($Matches[1].ToLowerInvariant())) {
            $raw = $Matches[2]
            $state[$Matches[1].ToLowerInvariant()] = [pscustomobject]@{ Set = $true; On = (ConvertTo-BcdBool $raw); Raw = $raw }
        }
    }
    return $state
}

function Get-BcdState {
    $r = Invoke-BcdEdit @('/enum', '{current}')
    if ($r.Code -ne 0) { throw "bcdedit không đọc được mục khởi động (mã $($r.Code)): $($r.Output)" }
    return (ConvertFrom-BcdEnum $r.Output)
}

function Get-OldRegistryValues {
    # Giá trị bản 1.0 ghi vào registry: Windows không đọc, chỉ để dọn.
    $found = [ordered]@{}
    $item = Get-ItemProperty -LiteralPath $script:KernelKey -ErrorAction SilentlyContinue
    if (-not $item) { return $found }
    foreach ($n in $script:OldValues) {
        $p = $item.PSObject.Properties[$n]
        if ($p) { $found[$n] = $p.Value }
    }
    return $found
}

# ---------------------------------------------------------------- BitLocker ổ Windows
function Get-OsBitLocker {
    # Known: đọc được; On: đang bảo vệ (ProtectionStatus 1). Máy không có BitLocker coi như tắt.
    $drive = $env:SystemDrive
    try {
        $v = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter "DriveLetter='$drive'" -ErrorAction Stop
    } catch {
        if ($_.Exception.Message -match 'Invalid namespace|không hợp lệ' -or $_.CategoryInfo.Category -eq 'ObjectNotFound') {
            return [pscustomobject]@{ Known = $true; On = $false; Message = 'Máy không có BitLocker.' }
        }
        return [pscustomobject]@{ Known = $false; On = $false; Message = $_.Exception.Message.Trim() }
    }
    if (-not $v) { return [pscustomobject]@{ Known = $true; On = $false; Message = "Ổ $drive không mã hoá." } }
    $on = ([int]$v.ProtectionStatus -eq 1)
    return [pscustomobject]@{ Known = $true; On = $on; Message = $(if ($on) { "Ổ $drive đang bật BitLocker." } else { "Ổ $drive không bật bảo vệ BitLocker." }) }
}

function Suspend-OsBitLocker {
    # Tạm dừng BitLocker ổ Windows trong 1 lần khởi động; sau đó Windows tự bật lại. Trả $true khi đã tạm dừng.
    $drive = $env:SystemDrive
    if (Get-Command Suspend-BitLocker -ErrorAction SilentlyContinue) {
        try { [void](Suspend-BitLocker -MountPoint $drive -RebootCount 1 -ErrorAction Stop) }
        catch { Write-Sub $_.Exception.Message.Trim() }
    } else {
        $ErrorActionPreference = 'Continue'
        $out = & (Join-Path $env:SystemRoot 'System32\manage-bde.exe') -protectors -disable $drive -RebootCount 1 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Sub ((@($out) | ForEach-Object { [string]$_ }) -join ' ') }
    }
    return -not (Get-OsBitLocker).On
}

# ---------------------------------------------------------------- chế độ
function Show-State {
    param($State)
    foreach ($name in $script:Elements.Keys) {
        $s = $State[$name]
        $val = if ($s.Set) { "$($s.Raw)" } else { 'mặc định (chưa đặt)' }
        Write-Line ('{0,-20} {1}: {2}' -f $name, $script:Elements[$name], $val)
    }
}

function Invoke-KiemTra {
    Write-Head 'Thiết lập đồng hồ trong BCD (mục khởi động hiện tại)'
    $script:Findings.Clear()
    $code = 0
    $sua = 'Chạy "Trả đồng hồ về mặc định của Windows" rồi khởi động lại máy.'
    try {
        $state = Get-BcdState
        Show-State $state
        Write-Line ''
        if ($state.useplatformclock.On) {
            Write-Warn 'Đang ép dùng HPET: trên máy đời mới thường làm game giật hơn. Nên trả về mặc định.'
            Add-Finding 'HPET_DANG_EP' 'canh-bao' 'Đang ép dùng HPET làm đồng hồ chính (useplatformclock)' 'Trên máy đời mới thường làm game giật hơn.' $sua 'toi-uu/mac-dinh-dong-ho'
        }
        if ($state.useplatformtick.On) {
            Write-Warn 'Đang ép dùng đồng hồ nền tảng cho nhịp hẹn giờ: hiếm khi có lợi, nên trả về mặc định.'
            Add-Finding 'PLATFORM_TICK_DANG_EP' 'canh-bao' 'Đang ép dùng đồng hồ nền tảng cho nhịp hẹn giờ (useplatformtick)' 'Hiếm khi có lợi.' $sua 'toi-uu/mac-dinh-dong-ho'
        }
        if ($state.disabledynamictick.On) {
            Write-Info 'Đang tắt Dynamic Tick: máy tốn điện hơn một chút khi rảnh (laptop tụt pin nhanh hơn). Không thấy game mượt hơn thì trả về mặc định.'
            Add-Finding 'DYNAMIC_TICK_TAT' 'thong-tin' 'Đang tắt Dynamic Tick (disabledynamictick)' 'Máy tốn điện hơn một chút khi rảnh, laptop tụt pin nhanh hơn.' 'Không thấy game mượt hơn thì chạy "Trả đồng hồ về mặc định của Windows".'
        }
        if (-not ($state.Values | Where-Object { $_.Set })) {
            Write-Ok 'Đang để mặc định của Windows, hợp với đa số máy.'
            Add-Finding 'DONG_HO_MAC_DINH' 'ok' 'Đồng hồ hệ thống đang để mặc định của Windows'
        }
    } catch {
        $msg = $_.Exception.Message
        Write-Bad $msg
        $admin = Test-IsAdmin
        if (-not $admin) { Write-Sub 'Đọc BCD cần quyền Admin.' }
        $code = $(if ($admin) { 1 } else { 2 })
        Add-Finding 'KHONG_DOC_DUOC_BCD' 'loi' 'Không đọc được thiết lập đồng hồ trong BCD' $msg $(if ($admin) { '' } else { 'Đọc BCD cần quyền Admin: chạy lại bằng quyền Admin.' })
    }
    $old = Get-OldRegistryValues
    if ($old.Count) {
        $list = ($old.Keys | ForEach-Object { "$_=$($old[$_])" }) -join ', '
        Write-Warn ('Còn giá trị bản cũ ghi vào registry (Windows không đọc): {0}. Chế độ "Trả về mặc định" sẽ xoá.' -f $list)
        Add-Finding 'GIA_TRI_REGISTRY_CU' 'thong-tin' 'Còn giá trị bản cũ của công cụ ghi vào registry' "$list trong Session Manager\kernel. Windows không đọc các giá trị này." 'Hai nút đổi thiết lập đồng hồ đều xoá chúng.' 'toi-uu/mac-dinh-dong-ho'
    }
    $bl = Get-OsBitLocker
    if ($bl.On) { Write-Info 'Ổ Windows đang bật BitLocker: khi đổi thiết lập, công cụ tạm dừng BitLocker 1 lần khởi động để máy không hỏi khoá khôi phục.' }
    elseif (-not $bl.Known) { Write-Info "Không đọc được BitLocker: $($bl.Message)" }
    if ($KetQua) {
        try { Save-Findings $KetQua } catch { Write-Bad ('Không ghi được file kết quả {0}: {1}' -f $KetQua, $_.Exception.Message.Trim()); return 1 }
    }
    return $code
}

function Get-ChangePlan {
    # Danh sách lệnh bcdedit cần chạy và giá trị registry cần xoá cho một chế độ. $State = $null khi chưa đọc được BCD.
    param([string]$Id, $State)
    $ops = New-Object System.Collections.ArrayList
    $want = [ordered]@{}   # trạng thái mong muốn sau khi đổi: $true bật, $false chưa đặt
    if ($Id -eq 'choi-game') {
        if (-not $State -or -not $State.disabledynamictick.On) { [void]$ops.Add(@('/set', '{current}', 'disabledynamictick', 'yes')) }
        if (-not $State -or $State.useplatformclock.Set) { [void]$ops.Add(@('/deletevalue', '{current}', 'useplatformclock')) }
        $want.disabledynamictick = $true; $want.useplatformclock = $false
    } else {
        foreach ($name in $script:Elements.Keys) {
            if (-not $State -or $State[$name].Set) { [void]$ops.Add(@('/deletevalue', '{current}', $name)) }
            $want[$name] = $false
        }
    }
    return [pscustomobject]@{ Ops = $ops.ToArray(); Want = $want; Registry = @((Get-OldRegistryValues).Keys) }
}

function Invoke-Change {
    param([string]$Id, [switch]$DryRun, [switch]$Ask)
    Write-Head $script:Modes[$Id].Label
    $state = $null
    try { $state = Get-BcdState; Show-State $state }
    catch {
        if (-not $DryRun) { Write-Bad $_.Exception.Message; return $(if (Test-IsAdmin) { 1 } else { 2 }) }
        Write-Warn 'Chưa đọc được BCD (cần quyền Admin): in mọi lệnh có thể chạy.'
    }
    $plan = Get-ChangePlan $Id $state
    if (-not $plan.Ops.Count -and -not $plan.Registry.Count) { Write-Ok 'Đã đúng như vậy rồi, không cần đổi gì.'; return 0 }
    Write-Line ''
    Write-Line 'Sẽ làm:'
    foreach ($op in $plan.Ops) { Write-Plan ('bcdedit ' + ($op -join ' ')) }
    foreach ($n in $plan.Registry) { Write-Plan "Xoá giá trị registry $n (bản cũ ghi, Windows không đọc)" }
    if ($DryRun) { Write-Info 'Chạy thử: không đổi gì.'; return 0 }
    if ($Ask -and -not (Read-YesNo 'Làm các việc trên?' $false)) { Write-Info 'Đã huỷ, chưa đổi gì.'; return 0 }

    if ($plan.Ops.Count) {
        $bl = Get-OsBitLocker
        if ($bl.On) {
            Write-Warn 'Ổ Windows đang bật BitLocker. Đổi BCD lúc này có thể làm lần khởi động tới hỏi khoá khôi phục 48 số.'
            Write-Sub 'Công cụ tạm dừng BitLocker đúng 1 lần khởi động, sau đó Windows tự bật lại. Nên lưu khoá khôi phục trước (công cụ BitLocker).'
            if (-not (Read-YesNo 'Tạm dừng BitLocker 1 lần khởi động rồi đổi?' $false)) { Write-Warn 'Chưa đổi gì.'; return 2 }
            if (-not (Suspend-OsBitLocker)) { Write-Bad 'Không tạm dừng được BitLocker nên chưa đổi gì.'; return 1 }
            Write-Ok 'Đã tạm dừng BitLocker 1 lần khởi động.'
        } elseif (-not $bl.Known) {
            Write-Warn "Không đọc được trạng thái BitLocker ổ Windows: $($bl.Message)"
            if (-not (Read-YesNo 'Vẫn đổi? (nếu ổ có BitLocker, lần khởi động tới có thể hỏi khoá khôi phục)' $false)) { Write-Warn 'Chưa đổi gì.'; return 2 }
        }
    }

    $done = 0; $fail = 0; $passed = @{}
    foreach ($op in $plan.Ops) {
        $r = Invoke-BcdEdit $op
        if ($r.Code -eq 0) { Write-Ok ('bcdedit ' + ($op -join ' ')); $done++; $passed[$op[2]] = $true }
        else { Write-Bad ('bcdedit {0}: mã {1}. {2}' -f ($op -join ' '), $r.Code, $r.Output); $fail++ }
    }
    foreach ($n in $plan.Registry) {
        try { Remove-ItemProperty -LiteralPath $script:KernelKey -Name $n -ErrorAction Stop; Write-Ok "Đã xoá giá trị registry $n."; $done++ }
        catch { Write-Bad "Không xoá được giá trị registry ${n}: $($_.Exception.Message.Trim())"; $fail++ }
    }

    # Đọc lại để chắc Windows đã nhận, không tin vào mã thoát.
    if ($plan.Ops.Count) {
        try {
            $after = Get-BcdState
            foreach ($name in $plan.Want.Keys) {
                $ok = if ($plan.Want[$name]) { $after[$name].On } else { -not $after[$name].Set }
                if (-not $ok) {
                    Write-Bad "Đọc lại BCD: $name chưa đúng như mong muốn ($($after[$name].Raw))."
                    if ($passed[$name]) { $done-- }   # bcdedit báo xong nhưng Windows chưa nhận
                    $fail++
                }
            }
        } catch { Write-Bad "Không đọc lại được BCD: $($_.Exception.Message)"; $fail++ }
    }
    Write-Line ''
    if ($fail -and $done) { Write-Warn 'Làm được một phần, xem các dòng [X] ở trên.'; return 3 }
    if ($fail) { return 1 }
    if ($plan.Ops.Count) { Write-Warn 'Khởi động lại máy để thiết lập mới có hiệu lực.' }
    if ($Id -eq 'choi-game') { Write-Info 'Không thấy game mượt hơn sau khi khởi động lại thì chạy "Trả về mặc định".' }
    return 0
}

function Invoke-Mode {
    param([string]$Id, [switch]$Ask)
    try {
        if ($Id -eq 'kiem-tra') { return (Invoke-KiemTra) }
        return (Invoke-Change $Id -DryRun:$ChayThu -Ask:$Ask)
    } catch {
        Write-Bad ('Lỗi không lường trước: {0}' -f $_.Exception.Message.Trim())
        return 1
    }
}

function Invoke-Elevated {
    # Mở lại chính script này bằng quyền Admin (Windows hỏi UAC), chờ xong, trả mã thoát. Chỉ một lần.
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-DaNangQuyen')
    if ($Mode) { $parts += @('-Mode', $Mode) }
    if ($KhongDung) { $parts += '-KhongDung' }
    try { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList ($parts -join ' ') -Verb RunAs -Wait -PassThru }
    catch {
        $e = $_.Exception; $native = 0
        while ($e) { if ($e -is [ComponentModel.Win32Exception]) { $native = $e.NativeErrorCode; break }; $e = $e.InnerException }
        if ($native -eq 1223) { Write-Warn 'Bạn đã chọn "Không" ở hộp thoại quyền Admin nên chưa chạy.'; return 2 }
        Write-Bad "Không mở được bằng quyền Admin: $($_.Exception.Message.Trim())"
        return 1
    }
    try { return [int]$p.ExitCode } catch { return 0 }
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '  TỐI ƯU ĐỒNG HỒ HỆ THỐNG' -ForegroundColor Cyan
        Write-Host '  Đổi Dynamic Tick và HPET trong BCD. Cần khởi động lại máy để có hiệu lực.' -ForegroundColor Gray
        Write-Host ''
        foreach ($id in $script:Modes.Keys) { Write-Host ('   {0}. {1}' -f $script:Modes[$id].No, $script:Modes[$id].Label) }
        Write-Host '   0. Thoát'
        Write-Host ''
        $c = Read-Text 'Chọn số' '0'
        if ($c -eq '0') { return 0 }
        $id = $null
        foreach ($k in $script:Modes.Keys) { if ([string]$script:Modes[$k].No -eq $c) { $id = $k } }
        if (-not $id) { continue }
        [void](Invoke-Mode $id -Ask)
        Wait-Close 'Bấm Enter để về menu'
    }
}

# ---------------------------------------------------------------- bắt đầu
if ($env:TRAMTOOL_DONGHO_TEST) { return }   # bài thử nạp các hàm rồi tự gọi
try { $Host.UI.RawUI.WindowTitle = 'Tối ưu đồng hồ hệ thống' } catch { }
if ($Mode -and -not $script:Modes.Contains($Mode)) {
    Write-Bad ('Không có chế độ "{0}". Các chế độ: {1}.' -f $Mode, (@($script:Modes.Keys) -join ', '))
    Wait-Close
    exit 1
}
if (-not (Test-IsAdmin) -and -not $ChayThu) {
    if ($DaNangQuyen) { Write-Bad 'Đã mở lại mà vẫn chưa có quyền Admin.'; Wait-Close; exit 2 }
    Write-Info 'Đọc và đổi BCD cần quyền Admin: Windows sẽ hỏi (UAC), chọn "Có".'
    exit (Invoke-Elevated)
}
if (-not $Mode) {
    if ([Console]::IsInputRedirected) { Write-Host 'Cách dùng: DongHo.ps1 -Mode kiem-tra|choi-game|mac-dinh [-ChayThu]'; exit 1 }
    exit (Show-Menu)
}
$code = Invoke-Mode $Mode
Wait-Close
exit $code
