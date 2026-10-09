<#
  File thẻ xe .nt cho phần mềm giữ xe (ITS Pro): chuyển danh sách Excel sang file .nt, kiểm tra file .nt như phần mềm
  đọc (so với danh sách Excel nếu có), chuyển file .nt sang Excel, sửa file của bên bán bị mất số 0 ở CardID.

  Không có -Mode: hiện menu (bấm đúp THE_XE.bat, hoặc kéo file thả vào THE_XE.bat).
  Chế độ: tao (Excel sang .nt, ghi <số đầu>-<số cuối>.nt), xem (kiểm tra, chỉ đọc), xuat (.nt sang <tên>.xlsx),
  sua (ghi bản sửa vào thư mục da-sua cạnh file gốc).
  -File: danh sách .xlsx/.xls/.csv/.txt (tao) hoặc file .nt (xem, xuat, sua). -DanhSach: danh sách để so (xem).
  -ThuMuc: thư mục ghi kết quả. -DoDai: số chữ số của mã thẻ (mặc định 10, mã ngắn hơn được thêm số 0 ở đầu).
  File gốc không bao giờ bị sửa. Không cần Excel: .nt đọc, ghi bằng Jet OLEDB 4.0 có sẵn trong Windows (32 bit),
  .xlsx đọc, ghi thẳng.
  Mã thoát: 0 xong, 1 lỗi (file có lỗi không tự sửa được), 2 thiếu điều kiện (không thấy file), 1223 người dùng thôi.
#>
param(
    [string]$Mode = '',
    [string]$File = '',
    [string]$DanhSach = '',
    [string]$ThuMuc = '',
    [ValidateRange(4, 20)][int]$DoDai = 10,
    [switch]$KhongDung,       # không chờ Enter khi xong (chạy tự động)
    [switch]$TuBien           # nội bộ: đọc tham số từ biến môi trường (khi tự mở lại bằng PowerShell 32 bit)
)

$ErrorActionPreference = 'Stop'

# Jet OLEDB 4.0 chỉ có bản 32 bit: đang ở PowerShell 64 bit thì mở lại chính script này bằng PowerShell 32 bit, trong
# cùng cửa sổ. Tham số đi qua biến môi trường để đường dẫn có dấu cách, dấu \ cuối không bị cắt sai.
if ([Environment]::Is64BitProcess) {
    $ps32 = Join-Path $env:SystemRoot 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
    $env:THEXE_THAMSO = (@{ Mode = $Mode; File = $File; DanhSach = $DanhSach; ThuMuc = $ThuMuc; DoDai = $DoDai; KhongDung = [bool]$KhongDung } | ConvertTo-Json -Compress)
    & $ps32 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -TuBien
    exit $LASTEXITCODE
}
if ($TuBien -and $env:THEXE_THAMSO) {
    $p = $env:THEXE_THAMSO | ConvertFrom-Json
    Remove-Item Env:\THEXE_THAMSO
    $Mode = [string]$p.Mode; $File = [string]$p.File; $DanhSach = [string]$p.DanhSach; $ThuMuc = [string]$p.ThuMuc
    $DoDai = [int]$p.DoDai; $KhongDung = [bool]$p.KhongDung
}

$script:ToolDir = $PSScriptRoot
$script:ToolVersion = '1.1'
. (Join-Path $PSScriptRoot 'lib\Chung.ps1')
. (Join-Path $PSScriptRoot 'lib\DocGhi.ps1')
. (Join-Path $PSScriptRoot 'lib\TheXe.ps1')
$script:NoPause = [bool]$KhongDung

# Log: tên đầu file báo cáo trong ket_qua.
$script:Modes = [ordered]@{
    'tao'  = @{ No = 1; Label = 'Chuyển Excel sang file .nt'; Log = 'NhatKy_TheXe' }
    'xem'  = @{ No = 2; Label = 'Kiểm tra file .nt (so với danh sách Excel nếu có, chỉ đọc)'; Log = 'BaoCao_TheXe' }
    'xuat' = @{ No = 3; Label = 'Chuyển file .nt sang Excel (kèm kết quả kiểm tra từng thẻ)'; Log = 'NhatKy_TheXe' }
    'sua'  = @{ No = 4; Label = 'Sửa file .nt của bên bán (thêm số 0 bị mất)'; Log = 'NhatKy_TheXe' }
}

function Format-PathArg {
    # Bỏ ngoặc kép, dấu cách thừa (kéo thả file vào cửa sổ có ngoặc kép); đổi sang đường dẫn đầy đủ.
    param([string]$Path)
    $p = ([string]$Path).Trim().Trim('"').Trim()
    if (-not $p) { return '' }
    try { if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).ProviderPath } } catch { }
    try { return [IO.Path]::GetFullPath($p) } catch { return $p }
}

function Invoke-ModeSafe {
    # Chạy một chế độ; lỗi không lường trước thì in ra và trả mã 1. Ghi báo cáo vào ket_qua (trừ khi người dùng thôi).
    param([string]$Id, [string]$F, [string]$Ds, [string]$Out, [int]$Len)
    $script:Report.Clear()
    $started = Get-Date
    $code = 1
    try {
        $r = switch ($Id) {
            'tao' { Invoke-TaoFile -File $F -ThuMuc $Out -DoDai $Len }
            'xem' { Invoke-XemFile -File $F -DanhSach $Ds -DoDai $Len }
            'xuat' { Invoke-XuatExcel -File $F -ThuMuc $Out -DoDai $Len }
            'sua' { Invoke-SuaFile -File $F -ThuMuc $Out -DoDai $Len }
        }
        $r = @($r)
        $code = if ($r.Count -and $r[-1] -is [int]) { $r[-1] } else { 0 }
    } catch {
        Write-Bad ('Lỗi không lường trước: {0}' -f $_.Exception.Message.Trim())
        Write-Sub (([string]$_.InvocationInfo.PositionMessage).Split("`n")[0])
        $code = 1
    } finally {
        if ($code -ne 1223 -and $script:Report.Count) {
            Write-Out ''
            Write-Out ('Kết thúc {0:dd/MM/yyyy HH:mm}, mã {1}.' -f (Get-Date), $code)
            [void](Save-Report $script:Modes[$Id].Log ([IO.Path]::GetFileNameWithoutExtension($F)) $started)
        }
    }
    return $code
}

function Show-Menu {
    param([string]$Preset = '')
    while ($true) {
        try { $Host.UI.RawUI.WindowTitle = 'File thẻ xe .nt' } catch { }
        Write-Host ''
        Write-Host '  FILE THẺ XE .NT (PHẦN MỀM GIỮ XE)' -ForegroundColor Cyan
        Write-Host '  File gốc không bao giờ bị sửa. Mã thẻ phải là chữ đủ 10 số thì thẻ mới quẹt được.' -ForegroundColor Gray
        if ($Preset) { Write-Host "  File: $Preset" -ForegroundColor Gray }
        Write-Host ''
        foreach ($id in $script:Modes.Keys) { Write-Host ('   {0}. {1}' -f $script:Modes[$id].No, $script:Modes[$id].Label) }
        Write-Host '   0. Thoát'
        Write-Host ''
        $c = Read-Text 'Chọn số'
        if ($c -eq '0') { return 0 }
        $id = $null
        foreach ($k in $script:Modes.Keys) { if ([string]$script:Modes[$k].No -eq $c) { $id = $k } }
        if (-not $id) { continue }
        $f = $Preset
        if (-not $f) {
            $hint = if ($id -eq 'tao') { 'File danh sách Excel (.xlsx, .xls, .csv), kéo thả file vào đây' } else { 'File thẻ (.nt), kéo thả file vào đây' }
            $f = Format-PathArg (Read-Text $hint)
        }
        $ds = ''; $out = ''
        if ($id -eq 'xem') {
            $ds = Format-PathArg (Read-Text 'File danh sách Excel để so từng thẻ (Enter = không so)')
        } else {
            $def = if ($id -eq 'sua') { 'thư mục da-sua cạnh file gốc' } elseif ($id -eq 'tao') { 'cùng thư mục với danh sách' } else { 'cùng thư mục với file .nt' }
            $out = Format-PathArg (Read-Text "Thư mục ghi kết quả (Enter = $def)")
        }
        [void](Invoke-ModeSafe $id $f $ds $out $DoDai)
        Wait-Close 'Bấm Enter để về menu'
    }
}

# ---------------------------------------------------------------- bắt đầu
try { $Host.UI.RawUI.WindowTitle = 'File thẻ xe .nt' } catch { }
$File = Format-PathArg $File
$DanhSach = Format-PathArg $DanhSach
$ThuMuc = Format-PathArg $ThuMuc

# Kéo thả file vào THE_XE.bat: đường dẫn nằm ở vị trí của -Mode.
if ($Mode -and -not $script:Modes.Contains($Mode) -and (Test-Path -LiteralPath $Mode.Trim('"') -PathType Leaf)) {
    $File = Format-PathArg $Mode
    $Mode = ''
}
if (-not $Mode) {
    if ([Console]::IsInputRedirected) {
        Write-Host ('Cách dùng: TheXe.ps1 -Mode <chế độ> -File <file> [-DanhSach <file>] [-ThuMuc <thư mục>]. Chế độ: {0}.' -f (@($script:Modes.Keys) -join ', '))
        exit 1
    }
    exit (Show-Menu $File)
}
if (-not $script:Modes.Contains($Mode)) {
    Write-Bad ('Không có chế độ "{0}". Các chế độ: {1}.' -f $Mode, (@($script:Modes.Keys) -join ', '))
    Wait-Close
    exit 1
}
try { $Host.UI.RawUI.WindowTitle = 'File thẻ xe - ' + $script:Modes[$Mode].Label } catch { }
$code = Invoke-ModeSafe $Mode $File $DanhSach $ThuMuc $DoDai
Wait-Close
exit $code
