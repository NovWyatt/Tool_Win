# Mọi file PowerShell trong repo phải phân tích cú pháp được, kể cả phần PowerShell nhúng trong file .bat
# (kiểu "#=====PS_START=====" của CheckWinFix, "### POWERSHELL_SCRIPT_BELOW ###" của health-report và kiểu "<# :" của
# MyExcelFix). Chỉ đọc file.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
. "$PSScriptRoot\_TepRepo.ps1"

function Test-Parse([string]$Label, [string]$Text) {
    $tokens = $null; $errs = $null
    [void][Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errs)
    $msg = @($errs | Select-Object -First 3 | ForEach-Object { "dòng $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '
    Check ($errs.Count -eq 0) "$Label $msg"
}

$ps = Get-RepoFiles '.ps1', '.psm1', '.psd1'
Check ($ps.Count -gt 50) "tìm thấy $($ps.Count) file PowerShell"
foreach ($f in $ps) { Test-Parse (Get-RelPath $f) ([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)) }

$n = 0
foreach ($f in (Get-RepoFiles '.bat', '.cmd')) {
    $t = [IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)
    $mk = '#=====PS_START====='
    $mk2 = '### POWERSHELL_SCRIPT_BELOW ###'   # health-report: lấy từ lần xuất hiện cuối như chính file .bat
    if ($t.Contains($mk)) { $n++; Test-Parse ((Get-RelPath $f) + ' (phần PowerShell)') $t.Substring($t.IndexOf($mk) + $mk.Length) }
    elseif ($t.Contains($mk2)) { $n++; Test-Parse ((Get-RelPath $f) + ' (phần PowerShell)') $t.Substring($t.LastIndexOf($mk2) + $mk2.Length) }
    elseif ($t.TrimStart([char]0xFEFF).StartsWith('<# :')) { $n++; Test-Parse ((Get-RelPath $f) + ' (cả file)') $t }
}
Check ($n -ge 7) "tìm thấy $n file .bat có PowerShell nhúng"

Complete-Test
