# Chuan hoa ma hoa cho file cua tram (chay sau khi sua code):
#   *.ps1 -> UTF-8 co BOM + CRLF (PowerShell 5.1 can BOM de doc dung tieng Viet)
#   *.bat, *.cmd -> khong BOM + CRLF (BOM lam hong dong dau cua cmd.exe)
# File nay chi dung ky tu ASCII de chay duoc ca khi mat BOM.
param([string[]]$Path = @((Split-Path $PSScriptRoot -Parent), (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'TramTool.bat')))

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$files = foreach ($p in $Path) {
    if (Test-Path -LiteralPath $p -PathType Container) {
        Get-ChildItem -LiteralPath $p -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.bat', '.cmd' -and $_.FullName -notmatch '\\(data|vendor|\.?venv|node_modules)\\' }
    } elseif (Test-Path -LiteralPath $p) { Get-Item -LiteralPath $p }
}
foreach ($f in $files) {
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = $utf8NoBom.GetString($bytes, $(if ($hasBom) { 3 } else { 0 }), $bytes.Length - $(if ($hasBom) { 3 } else { 0 }))
    $text = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
    $enc = if ($f.Extension -eq '.ps1') { $utf8Bom } else { $utf8NoBom }
    $new = $enc.GetPreamble() + $enc.GetBytes($text)
    if ([Convert]::ToBase64String($new) -ne [Convert]::ToBase64String($bytes)) {
        [IO.File]::WriteAllBytes($f.FullName, $new)
        Write-Host "fixed: $($f.FullName)"
    }
}
