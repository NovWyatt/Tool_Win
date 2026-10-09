# Thư viện chung cho bài thử của Trạm Tool. Mỗi bài thử nạp ở dòng đầu:
#     . "$PSScriptRoot\..\lib\KiemThu.ps1"
# rồi gọi Check / Skip-Test, cuối bài gọi Complete-Test (in tổng kết, thoát 0 nếu không có mục hỏng).
#
# Biến dùng được sau khi nạp:
#     $RepoRoot   thư mục gốc repo          $ToolsDir   tools\          $HubDir   hub\
#     $TestRoot   thư mục tạm riêng của bài (<thư mục tạm chung>\<bộ>\<bài>), đã được làm sạch; thư mục tạm
#                 chung nằm ngoài repo, xem Get-TestBase trong XoaAnToan.ps1
#
# Bài thử chỉ chạy với quyền thường: lệnh đổi máy thật (cần Admin) sẽ hỏng thay vì chạy thật nếu bài thử sót
# một chỗ chưa giả lập. Đang có quyền Admin thì dừng ngay.

[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
$OutputEncoding = [Console]::OutputEncoding
. (Join-Path $PSScriptRoot 'XoaAnToan.ps1')

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ToolsDir = Join-Path $RepoRoot 'tools'
$HubDir = Join-Path $RepoRoot 'hub'
$script:KT_Pass = 0
$script:KT_Fail = 0
$script:KT_Skip = 0

if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Đang có quyền Administrator: bài thử chỉ chạy với quyền thường để không đổi máy thật. Dừng.' -ForegroundColor Red
    exit 99
}

function Write-KT([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::Gray) {
    # In thẳng ra Console: vài bài thử thay Write-Host bằng hàm im lặng để công cụ không in
    $old = [Console]::ForegroundColor
    try { [Console]::ForegroundColor = $Color; [Console]::WriteLine($Text) } finally { [Console]::ForegroundColor = $old }
}

function Check {
    # Hai kiểu gọi (giữ như các bài thử cũ):
    #     Check (điều kiện) 'mô tả'
    #     Check 'tên' (điều kiện) 'thông tin thêm khi hỏng'
    param($A, $B, $C)
    if ($A -is [string]) { $ok = [bool]$B; $msg = $A; if (-not $ok -and $C) { $msg += " ($C)" } }
    else { $ok = [bool]$A; $msg = [string]$B }
    if ($ok) { $script:KT_Pass++; Write-KT "  PASS $msg" DarkGreen }
    else { $script:KT_Fail++; Write-KT "  FAIL $msg" Red }
}

function Skip-Test([string]$Msg) {
    $script:KT_Skip++
    Write-KT "  BỎ QUA $Msg" DarkYellow
}

function Complete-Test {
    # Dòng #KIEMTHU để ChayTatCa.ps1 đọc số liệu; thiếu dòng này nghĩa là bài thử văng lỗi giữa chừng.
    Write-KT ''
    Write-KT ("Kết quả: {0} đạt, {1} hỏng, {2} bỏ qua" -f $script:KT_Pass, $script:KT_Fail, $script:KT_Skip) $(if ($script:KT_Fail) { 'Red' } else { 'Green' })
    Write-KT ("#KIEMTHU dat={0} hong={1} boqua={2}" -f $script:KT_Pass, $script:KT_Fail, $script:KT_Skip)
    if ($script:KT_Fail) { exit 1 }
    exit 0
}

function New-TestDir([string]$Name) {
    # Thư mục con sạch trong $TestRoot
    $p = Join-Path $TestRoot $Name
    Remove-TestDir $p
    [void](New-Item -ItemType Directory -Path $p -Force)
    return $p
}

function Clear-TestRegistry {
    # HKCU\Software\TramToolTest là nơi duy nhất bài thử được ghi registry
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\TramToolTest', $false)
}

function Test-Is32BitHost { return [IntPtr]::Size -eq 4 }

# Thư mục tạm: ChayTatCa.ps1 truyền qua TRAMTOOL_TEST_ROOT; chạy riêng một bài thì tự đặt theo tên bài.
$TestBase = Get-TestBase
if ($env:TRAMTOOL_TEST_ROOT) { $TestRoot = $env:TRAMTOOL_TEST_ROOT }
else {
    $caller = $MyInvocation.PSCommandPath
    $TestRoot = Join-Path $TestBase ((Split-Path (Split-Path $caller -Parent) -Leaf) + '\' + [IO.Path]::GetFileNameWithoutExtension($caller))
}
if (-not ([IO.Path]::GetFullPath($TestRoot)).StartsWith($TestBase + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Write-KT "Thư mục tạm phải nằm trong $($TestBase): $TestRoot" Red
    exit 98
}
Remove-TestDir $TestRoot
[void](New-Item -ItemType Directory -Path $TestRoot -Force)
$TestRoot = (Resolve-Path -LiteralPath $TestRoot).Path
