# BitLocker - phần dùng chung: in ra màn hình kèm ghi báo cáo, hỏi người dùng, quyền Admin, thư mục kết quả,
# dịch mã lỗi BitLocker và Windows.

$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Report = New-Object System.Collections.Generic.List[string]
$script:Findings = New-Object System.Collections.ArrayList
$script:NoPause = $false

# ---------------------------------------------------------------- in ra màn hình (và báo cáo)
# Khoá khôi phục không bao giờ đi qua các hàm này: báo cáo được ghi ra file và có thể gửi người khác.
function Write-Out {
    param([string]$Text = '', [string]$Color = '')
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
    [void]$script:Report.Add($Text)
}
function Write-Head { param([string]$Text) Write-Out ''; Write-Out ("== $Text " + ('=' * [Math]::Max(3, 68 - $Text.Length))) 'Cyan' }
function Write-Line { param([string]$Text) Write-Out "  $Text" }
function Write-Sub { param([string]$Text) Write-Out "       $Text" 'Gray' }
function Write-Ok { param([string]$Text) Write-Out "  [OK] $Text" 'Green' }
function Write-Warn { param([string]$Text) Write-Out "  [!]  $Text" 'Yellow' }
function Write-Bad { param([string]$Text) Write-Out "  [X]  $Text" 'Red' }
function Write-Info { param([string]$Text) Write-Out "  [i]  $Text" 'Gray' }
function Write-Plan { param([string]$Text) Write-Out "   ->  $Text" 'White' }

function Add-Finding {
    # Vấn đề tìm thấy khi kiểm tra. Fix: chế độ nên chạy để xử lý (để trống nếu phải làm tay).
    param([ValidateSet('bad', 'warn', 'info')][string]$Level, [string]$Text, [string]$Fix = '', [string]$Hint = '')
    [void]$script:Findings.Add([pscustomobject]@{ Level = $Level; Text = $Text; Fix = $Fix; Hint = $Hint })
    switch ($Level) { 'bad' { Write-Bad $Text } 'warn' { Write-Warn $Text } default { Write-Info $Text } }
    if ($Hint) { Write-Sub $Hint }
}

# ---------------------------------------------------------------- hỏi người dùng
# Không có bàn phím (chạy tự động, stdin bị chuyển hướng) thì trả giá trị mặc định thay vì treo.
function Read-Text {
    param([string]$Prompt, [string]$Default = '')
    if ([Console]::IsInputRedirected) { return $Default }
    $a = ([string](Read-Host "  $Prompt")).Trim()
    if (-not $a) { return $Default }
    return $a
}

function Read-YesNo {
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

function Read-Number {
    # Chọn một số trong khoảng; Enter trả $Default (có thể là $null = bỏ qua).
    param([string]$Prompt, [int]$Min, [int]$Max, $Default = $null)
    if ([Console]::IsInputRedirected) { return $Default }
    while ($true) {
        $a = ([string](Read-Host "  $Prompt")).Trim()
        if (-not $a) { return $Default }
        $n = 0
        if ([int]::TryParse($a, [ref]$n) -and $n -ge $Min -and $n -le $Max) { return $n }
        Write-Host "  Gõ một số từ $Min đến $Max." -ForegroundColor Yellow
    }
}

function Confirm-Strong {
    # Xác nhận cho thay đổi làm giảm bảo mật: phải gõ đúng cụm từ, Enter là huỷ.
    param([string]$Phrase = 'DONG Y')
    if ([Console]::IsInputRedirected) { return $false }
    $a = ([string](Read-Host "  Gõ $Phrase để đồng ý (Enter để huỷ)")).Trim()
    return ($a -eq $Phrase)
}

function Wait-Close {
    param([string]$Text = 'Bấm Enter để đóng cửa sổ')
    if ($script:NoPause -or [Console]::IsInputRedirected) { return }
    Write-Host ''
    [void](Read-Host "  $Text")
}

# ---------------------------------------------------------------- quyền, tài khoản, thư mục kết quả
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CurrentUser { return [Security.Principal.WindowsIdentity]::GetCurrent().Name }

function Get-ConsoleUser {
    # Người đang dùng máy (phiên trên màn hình). Khác tài khoản đang chạy khi UAC hỏi mật khẩu một Admin khác.
    try { return [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName } catch { return '' }
}

function Get-ResultDir {
    # ket_qua\ trong thư mục công cụ; thư mục công cụ không ghi được (vd giải nén vào chỗ chỉ đọc) thì ra Desktop.
    $d = Join-Path $script:ToolDir 'ket_qua'
    try {
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -ErrorAction Stop) }
        return $d
    } catch {
        $d = Join-Path ([Environment]::GetFolderPath('Desktop')) 'BitLocker_ket_qua'
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d) }
        return $d
    }
}

function Get-RegValue {
    # Giá trị registry, $null khi chưa đặt (khác với giá trị 0).
    param([string]$Path, [string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $key = Get-Item -LiteralPath $Path
    if ($key.GetValueNames() -notcontains $Name) { return $null }
    return $key.GetValue($Name)
}

function Invoke-Native {
    # Chạy lệnh ngoài, trả mã thoát và output. Tạm đổi ErrorActionPreference để PowerShell 5.1 không biến dòng
    # stderr thành lỗi dừng script.
    param([string]$FilePath, [string[]]$ArgumentList = @())
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { [string]$_ }) }
    finally { $ErrorActionPreference = $prev }
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = ($out -join "`n") }
}

function Format-GB {
    param($Bytes)
    if (-not $Bytes) { return '' }
    return ('{0:N0} GB' -f ([double]$Bytes / 1GB))
}

# ---------------------------------------------------------------- mã lỗi
function ConvertTo-UInt32Code {
    # HRESULT âm (vd -2144272384) → số 32 bit không dấu (0x80310000).
    param([int64]$Code)
    if ($Code -lt 0) { $Code += 4294967296 }
    return $Code
}

function New-BdeError {
    # Lỗi mang mã HRESULT để nơi bắt lỗi đọc lại được mã (Win32Exception.NativeErrorCode) và có câu báo của Windows.
    param([int64]$Code)
    $signed = if ($Code -gt 2147483647) { [int]($Code - 4294967296) } else { [int]$Code }
    return (New-Object ComponentModel.Win32Exception($signed))
}

function Get-ErrorCode {
    # Mã lỗi từ lỗi PowerShell: Win32Exception (Invoke-Bde ném), CimException (HRESULT trong FullyQualifiedErrorId).
    param($ErrorRecord)
    $e = $ErrorRecord.Exception
    while ($e) {
        if ($e -is [ComponentModel.Win32Exception]) { return ConvertTo-UInt32Code $e.NativeErrorCode }
        $e = $e.InnerException
    }
    if ([string]$ErrorRecord.FullyQualifiedErrorId -match 'HRESULT 0x([0-9a-fA-F]{8})') { return [Convert]::ToInt64($Matches[1], 16) }
    return ConvertTo-UInt32Code ([int64]$ErrorRecord.Exception.HResult)
}

function Format-ErrorCode {
    param([int64]$Code)
    if ($Code -le 0xFFFF) { return ('{0} (0x{0:X8})' -f $Code) }
    return ('0x{0:X8}' -f $Code)
}

# Mã lỗi hay gặp, khoá là mã hex 8 chữ số: @(nghĩa, cách xử lý).
$script:ErrorHelp = @{
    '80041003' = @('Không có quyền đọc BitLocker.', 'Chạy lại bằng quyền Admin (trong Trạm Tool nút này tự xin quyền; bấm đúp BITLOCKER.bat thì chọn "Có" ở hộp UAC).')
    '80310000' = @('Ổ đang bị BitLocker khoá.', 'Mở khoá trước: nút "Mở khoá ổ bị BitLocker khoá", hoặc bấm đúp ổ trong This PC rồi nhập khoá khôi phục.')
    '80310008' = @('Ổ này không bật BitLocker.', 'Không cần làm gì với ổ này.')
    '80310027' = @('Khoá không đúng với ổ này.', 'Đối chiếu Mã khoá (Key ID) trên màn hình với khoá đang dùng; mỗi ổ, mỗi lần bật BitLocker có khoá riêng.')
    '80310030' = @('Đang cắm đĩa, USB khởi động.', 'Rút đĩa CD/DVD, USB cài Windows ra rồi chạy lại.')
    '80310033' = @('Không thấy khoá đó trên ổ (có thể đã bị xoá).', 'Chạy "Kiểm tra BitLocker" để xem các khoá hiện có của ổ.')
    '80310035' = @('Khoá khôi phục sai dạng.', 'Khoá khôi phục gồm 48 chữ số, chia 8 nhóm 6 số (vd 123456-...); kiểm tra lại từng nhóm.')
}

function Get-ErrorHelp {
    param([int64]$Code)
    return $script:ErrorHelp[('{0:X8}' -f $Code)]
}

function Write-ErrorHelp {
    param([int64]$Code, [string]$Prefix = 'Lỗi')
    $h = Get-ErrorHelp $Code
    if ($h) {
        Write-Bad ('{0} {1}: {2}' -f $Prefix, (Format-ErrorCode $Code), $h[0])
        Write-Sub ('Cách xử lý: ' + $h[1])
    } else {
        Write-Bad ('{0} {1}: {2}' -f $Prefix, (Format-ErrorCode $Code), (New-BdeError $Code).Message)
    }
}
