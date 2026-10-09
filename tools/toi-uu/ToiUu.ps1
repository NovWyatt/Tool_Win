<#
  Tối ưu Windows: một cửa vào cho hai phần, mỗi phần một script chạy được riêng:
    DichVu.ps1  tắt/bật dịch vụ nền (DiagTrack, Windows Insider, SysMain, Tối ưu ổ đĩa), lưu kiểu khởi động gốc
                để bật lại đúng như trước khi tắt;
    DongHo.ps1  Dynamic Tick, ép HPET trong cấu hình khởi động (BCD); trả về mặc định của Windows.
  Gộp từ hai công cụ cũ "Tắt/bật dịch vụ nền" (service-optimizer) và "Tối ưu đồng hồ hệ thống" (clock-optimizer).

  -Mode kiem-tra: chạy phần Kiểm tra của cả hai (chỉ đọc) trong cùng cửa sổ, gộp các phát hiện vào
    ket_qua\KetQua_ToiUu_KiemTra_<máy>_<giờ>.json (chuẩn tramtool.ketqua/1) để Trạm Tool hiện kèm nút sửa.
  Không có -Mode: menu chung (bấm đúp TOI_UU.bat): kiểm tra tất cả, menu dịch vụ nền, menu đồng hồ.
  Cần quyền Admin (đọc BCD, đổi dịch vụ): bấm đúp thì cửa sổ tự hỏi UAC. -KhongDung: không chờ Enter khi xong.
  Mã thoát: 0 xong (kể cả khi có cảnh báo), 1 lỗi, 2 thiếu điều kiện (quyền Admin), 3 chỉ kiểm tra được một phần.
#>
param(
    [string]$Mode = '',
    [switch]$KhongDung,
    [switch]$DaNangQuyen   # đánh dấu cửa sổ đã mở lại bằng quyền Admin, để không hỏi UAC lần nữa
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
$script:Version = '1.0'
$script:PartDir = $PSScriptRoot
$script:ResultDir = Join-Path $PSScriptRoot 'ket_qua'
$script:StateFile = Join-Path $PSScriptRoot ("ket_qua\TrangThaiGoc_{0}.json" -f $env:COMPUTERNAME)
$script:Parts = [ordered]@{
    DichVu = @{ File = 'DichVu.ps1'; Label = 'dịch vụ nền' }
    DongHo = @{ File = 'DongHo.ps1'; Label = 'đồng hồ hệ thống' }
}
$script:Levels = @{ 'loi' = 0; 'canh-bao' = 1; 'thong-tin' = 2; 'ok' = 3 }

# ---------------------------------------------------------------- in ra, hỏi
function Write-Head { param([string]$Text) Write-Host ''; Write-Host ("== $Text " + ('=' * [Math]::Max(3, 68 - $Text.Length))) -ForegroundColor Cyan }
function Write-Ok { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Write-Bad { param([string]$Text) Write-Host "  [X]  $Text" -ForegroundColor Red }
function Write-Info { param([string]$Text) Write-Host "  [i]  $Text" -ForegroundColor Gray }

function Read-Text {
    param([string]$Prompt, [string]$Default = '')
    if ([Console]::IsInputRedirected) { return $Default }
    $a = ([string](Read-Host "  $Prompt")).Trim()
    if (-not $a) { return $Default }
    return $a
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

# ---------------------------------------------------------------- chạy từng phần
function Invoke-Part {
    # Chạy một script con trong cùng cửa sổ (giữ màu chữ, hỏi đáp được như bấm đúp), trả mã thoát của nó.
    param([string]$File, [string[]]$Arguments = @())
    $parts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f (Join-Path $script:PartDir $File)))
    foreach ($a in $Arguments) { $parts += $(if ($a -match '\s') { '"{0}"' -f $a } else { $a }) }
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList ($parts -join ' ') -NoNewWindow -Wait -PassThru
    try { return [int]$p.ExitCode } catch { return 1 }
}

function Read-PartFindings {
    # Các phát hiện một phần đã ghi; không có file hoặc file hỏng (phần đó dừng giữa chừng) thì trả $null.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { $j = [IO.File]::ReadAllText($Path) | ConvertFrom-Json } catch { return $null }
    if ($null -eq $j -or $null -eq $j.PSObject.Properties['phatHien']) { return $null }
    return , @(@($j.phatHien) | Where-Object { $null -ne $_ })
}

function Get-OverallCode {
    # Mã thoát chung từ mã từng phần ($ok: phần đó chạy xong và ghi được phát hiện).
    param([object[]]$Runs)
    $ok = @($Runs | Where-Object { $_.Ok }).Count
    if ($ok -eq $Runs.Count) { return 0 }
    if ($ok) { return 3 }
    if (-not @($Runs | Where-Object { $_.Code -ne 2 }).Count) { return 2 }
    return 1
}

function Save-JsonAtomic {
    param($Object, [string]$Path)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, ($Object | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Invoke-KiemTraChung {
    # Kiểm tra cả hai phần, gộp phát hiện (nghiêm trọng trước), ghi file kết quả cho Trạm Tool. Trả mã thoát chung.
    $start = Get-Date
    $found = New-Object System.Collections.ArrayList
    $runs = @()
    $tmpDir = Join-Path ([IO.Path]::GetTempPath()) ('TramTool_ToiUu_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    try {
        foreach ($k in $script:Parts.Keys) {
            $part = $script:Parts[$k]
            $out = Join-Path $tmpDir "$k.json"
            $code = Invoke-Part $part.File @('-Mode', 'kiem-tra', '-KhongDung', '-KetQua', $out)
            $list = Read-PartFindings $out
            if ($null -eq $list) {
                [void]$found.Add([ordered]@{
                    ma = 'PHAN_KIEM_TRA_LOI'; mucDo = 'loi'; tieuDe = "Không kiểm tra được $($part.Label)"
                    chiTiet = "$($part.File) dừng với mã $code mà không ghi kết quả."
                    cachSua = 'Xem chữ lỗi trong cửa sổ công cụ, hoặc mở menu và chạy riêng phần đó.'
                })
            } else { foreach ($f in $list) { [void]$found.Add($f) } }
            $runs += [pscustomobject]@{ Part = $k; Code = $code; Ok = ($null -ne $list -and $code -eq 0) }
        }
    } finally { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }

    # Nghiêm trọng trước; cùng mức thì giữ thứ tự in ra (dịch vụ rồi đồng hồ).
    $i = 0
    $sorted = @($found | ForEach-Object { [pscustomobject]@{ F = $_; L = $(if ($script:Levels.ContainsKey([string]$_.mucDo)) { $script:Levels[[string]$_.mucDo] } else { 2 }); I = $i++ } } |
            Sort-Object L, I | ForEach-Object { $_.F })
    $nLoi = @($sorted | Where-Object { $_.mucDo -eq 'loi' }).Count
    $nCanh = @($sorted | Where-Object { $_.mucDo -eq 'canh-bao' }).Count
    $nTin = @($sorted | Where-Object { $_.mucDo -eq 'thong-tin' }).Count
    $code = Get-OverallCode $runs
    $msg = switch ($code) {
        0 { if ($nLoi + $nCanh) { 'Kiểm tra xong: {0} lỗi, {1} cảnh báo; xem gợi ý sửa.' -f $nLoi, $nCanh } else { 'Kiểm tra xong: dịch vụ nền và đồng hồ hệ thống không có gì cần sửa.' } }
        3 { 'Chỉ kiểm tra được một phần, xem mục lỗi.' }
        2 { 'Chưa kiểm tra được: thiếu quyền Admin.' }
        default { 'Không kiểm tra được, xem mục lỗi.' }
    }

    Write-Head 'Tóm tắt'
    foreach ($f in $sorted) {
        switch ([string]$f.mucDo) {
            'loi' { Write-Bad $f.tieuDe }
            'canh-bao' { Write-Warn $f.tieuDe }
            'thong-tin' { Write-Info $f.tieuDe }
            default { Write-Ok $f.tieuDe }
        }
    }
    $tep = @()
    if (Test-Path -LiteralPath $script:StateFile) { $tep += [ordered]@{ nhan = 'Trạng thái gốc để bật lại dịch vụ'; duongDan = $script:StateFile } }
    $r = [ordered]@{
        chuan = 'tramtool.ketqua/1'; congCu = 'toi-uu'; cheDo = 'kiem-tra'; phienBan = $script:Version
        may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
        batDau = $start.ToString('s'); ketThuc = (Get-Date).ToString('s')
        maThoat = $code; trangThai = @{ 0 = 'xong'; 1 = 'loi'; 2 = 'thieu-dieu-kien'; 3 = 'mot-phan' }[$code]
        chayThu = $false
        ma = $(if ($code -eq 3) { 'KIEM_TRA_MOT_PHAN' } elseif ($code) { 'KHONG_KIEM_TRA_DUOC' } elseif ($nLoi + $nCanh) { 'CO_CANH_BAO' } else { 'KHONG_CO_CANH_BAO' })
        thongDiep = $msg
        tomTat = [ordered]@{ loi = $nLoi; canhBao = $nCanh; thongTin = $nTin }
        phatHien = $sorted
        tep = $tep
    }
    $file = Join-Path $script:ResultDir ('KetQua_ToiUu_KiemTra_{0}_{1:yyyyMMdd_HHmmss}.json' -f $env:COMPUTERNAME, $start)
    try { Save-JsonAtomic $r $file; Write-Info "Kết quả cho Trạm Tool: $file" }
    catch { Write-Warn "Không ghi được file kết quả: $($_.Exception.Message.Trim())" }
    return $code
}

function Show-Menu {
    while ($true) {
        Write-Host ''
        Write-Host '  TỐI ƯU WINDOWS' -ForegroundColor Cyan
        Write-Host '  Mọi thay đổi đều trả lại được: dịch vụ bật lại đúng như cũ, đồng hồ trả về mặc định.' -ForegroundColor Gray
        Write-Host ''
        Write-Host '   1. Kiểm tra tất cả (chỉ đọc)'
        Write-Host '   2. Dịch vụ nền: tắt, bật lại như trước khi tắt'
        Write-Host '   3. Đồng hồ hệ thống: tối ưu cho chơi game, trả về mặc định'
        Write-Host '   0. Thoát'
        Write-Host ''
        $c = Read-Text 'Chọn số' '0'
        if ($c -eq '0') { return 0 }
        if ($c -eq '1') { [void](Invoke-KiemTraChung); Wait-Close 'Bấm Enter để về menu' }
        elseif ($c -eq '2') { [void](Invoke-Part 'DichVu.ps1' @('-DaNangQuyen')) }
        elseif ($c -eq '3') { [void](Invoke-Part 'DongHo.ps1' @('-DaNangQuyen')) }
    }
}

# ---------------------------------------------------------------- bắt đầu
if ($env:TRAMTOOL_TOIUU_TEST) { return }   # bài thử nạp các hàm rồi tự gọi
try { $Host.UI.RawUI.WindowTitle = 'Tối ưu Windows' } catch { }
if ($Mode -and $Mode -ne 'kiem-tra') {
    Write-Bad ('Không có chế độ "{0}". ToiUu.ps1 chỉ có -Mode kiem-tra; đổi dịch vụ hay đồng hồ thì chạy DichVu.ps1, DongHo.ps1.' -f $Mode)
    Wait-Close
    exit 1
}
if (-not (Test-IsAdmin)) {
    if ($DaNangQuyen) { Write-Bad 'Đã mở lại mà vẫn chưa có quyền Admin.'; Wait-Close; exit 2 }
    Write-Info 'Đọc cấu hình khởi động (BCD) và đổi dịch vụ cần quyền Admin: Windows sẽ hỏi (UAC), chọn "Có".'
    $argText = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -DaNangQuyen{1}{2}' -f $PSCommandPath, $(if ($Mode) { " -Mode $Mode" }), $(if ($KhongDung) { ' -KhongDung' })
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
    if ([Console]::IsInputRedirected) { Write-Host 'Cách dùng: ToiUu.ps1 [-Mode kiem-tra] [-KhongDung]'; exit 1 }
    exit (Show-Menu)
}
$code = Invoke-KiemTraChung
Wait-Close
exit $code
