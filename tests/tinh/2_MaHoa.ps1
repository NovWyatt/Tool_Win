# Mã hoá, xuống dòng: .ps1 phải UTF-8 có BOM (PowerShell 5.1 đọc file không BOM theo ANSI, chữ Việt hỏng) và CRLF;
# .bat/.cmd không được có BOM (cmd đọc nhầm dòng đầu) và phải CRLF (LF làm hỏng nhãn, goto).
# Sửa: powershell -File hub\dev\Normalize-Encoding.ps1 -Path <thư mục>
. "$PSScriptRoot\..\lib\KiemThu.ps1"
. "$PSScriptRoot\_TepRepo.ps1"

function Get-LfOnly([byte[]]$b) {
    $n = 0
    for ($i = 0; $i -lt $b.Length; $i++) { if ($b[$i] -eq 10 -and ($i -eq 0 -or $b[$i - 1] -ne 13)) { $n++ } }
    return $n
}
function Test-Bom([byte[]]$b) { return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) }

# Miễn: mảnh nguồn của MyExcelFix (src\, src_fix\) chỉ là đầu vào để build.ps1 ghép thành .bat (UTF-8 không BOM, CRLF),
# không bao giờ chạy riêng; build.ps1 giữ ASCII nên không cần BOM.
$exempt = '^tools\\myexcelfix\\src(_fix)?\\'
foreach ($f in (Get-RepoFiles '.ps1', '.psm1', '.psd1' | Where-Object { (Get-RelPath $_) -notmatch $exempt })) {
    $b = [IO.File]::ReadAllBytes($f)
    $why = @()
    if (-not (Test-Bom $b)) { $why += 'thiếu BOM' }
    $lf = Get-LfOnly $b
    if ($lf) { $why += "$lf dòng chỉ có LF" }
    Check (-not $why.Count) ("{0} {1}" -f (Get-RelPath $f), ($why -join ', '))
}
foreach ($f in (Get-RepoFiles '.bat', '.cmd' | Where-Object { (Get-RelPath $_) -notmatch $exempt })) {
    $b = [IO.File]::ReadAllBytes($f)
    $why = @()
    if (Test-Bom $b) { $why += 'có BOM' }
    $lf = Get-LfOnly $b
    if ($lf) { $why += "$lf dòng chỉ có LF" }
    Check (-not $why.Count) ("{0} {1}" -f (Get-RelPath $f), ($why -join ', '))
}

Complete-Test
