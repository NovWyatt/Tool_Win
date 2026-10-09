# Không commit dữ liệu khách: không file nào đã commit (hoặc sắp commit) trông giống báo cáo, bản sao lưu, khoá,
# danh sách thẻ, ghi âm, bản vẽ, cơ sở dữ liệu; và .gitignore phải bỏ qua các đường dẫn dữ liệu mẫu. Cần git.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $git -or -not (Test-Path -LiteralPath (Join-Path $RepoRoot '.git'))) { Skip-Test 'không có git hoặc repo không phải bản git'; Complete-Test }

$files = @(& $git.Source -C $RepoRoot -c core.quotepath=off ls-files --cached --others --exclude-standard)
Check ($files.Count -gt 100) "git liệt kê $($files.Count) file"
$patterns = @(
    '(^|/)du-lieu/', '(^|/)ket_qua/', '^hub/data/', '(^|/)DuLieu_SaoLuu[^/]*/', '(^|/)BiMat\.aes$', '(^|/)node_modules/',
    '\.nt$', '\.(mdf|ldf|ndf|bak|sql|dwg|dxf|dwl2?)$', '\.(m4a|mp3|wav|aac|ogg|flac|wma|amr|mp4)$', '\.(KPG|BEK)$',
    '(^|/)BitLocker_KhoaKhoiPhuc_', '(^|/)BitLocker Recovery Key', '(^|/)(BaoCao|NhatKy|KetQua)_[^/]*\.(txt|json|csv|html)$',
    '(^|/)(LagReport|HwDiag|WheaDecode|SupNguon|PinReport|health_report)_', '^tools/office/mau/', '^tools/office/[^/]*\.xml$',
    '^tools/the-xe-nt/.*\.(xls|xlsx|csv)$'
)
$allow = @('tools/the-xe-nt/mau/mau-trong.xls')
foreach ($p in $patterns) {
    $hit = @($files | Where-Object { $_ -match $p -and $allow -notcontains $_ })
    Check ($hit.Count -eq 0) "không có file khớp '$p' ($(@($hit | Select-Object -First 5) -join ', '))"
}

# Đường dẫn dữ liệu mẫu phải bị .gitignore bỏ qua
$samples = @(
    'tools/x/du-lieu/a.txt', 'tools/x/ket_qua/a.json', 'hub/data/history.json', 'tools/new-windows/DuLieu_SaoLuu/manifest.json',
    'DuLieu_SaoLuu_cu_20261001_100000/BiMat.aes', 'a/BiMat.aes', 'danh-sach.nt', 'tools/the-xe-nt/khach.xlsx',
    'KetQua_ChuyenDuLieu_xuat_PC_20261009_080000.json', 'KetQua_MyExcel_Sua_PC_1.json', 'BaoCao_BitLocker_PC_1.txt',
    'BitLocker_KhoaKhoiPhuc_PC_1.txt', 'tools/checkwinfix/KetQua_CheckWinFix_PhanCung_PC_20261010_080000.json', 'tools/checkwinfix/SleepStudy_PC_20261010_080000.html',
    'tools/office/mau/Configuration.xml', 'ban-ghi.m4a', 'khach.mdf', 'tests/node_modules/ajv/x.js'
)
$ignored = @(& $git.Source -C $RepoRoot -c core.quotepath=off check-ignore --no-index @samples)
foreach ($s in $samples) { Check ($ignored -contains $s) ".gitignore bỏ qua $s" }

Complete-Test
