# Build: join src\NN_*.cmd/ps1 into one .bat (UTF-8 without BOM, CRLF line endings).
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$out = Join-Path (Split-Path $src -Parent) 'CheckMyExcel_VietQR.bat'
$parts = Get-ChildItem -LiteralPath $src -File | Where-Object { $_.Name -match '^\d\d_.*\.(cmd|ps1)$' } | Sort-Object Name
$utf8 = New-Object Text.UTF8Encoding $false
$sb = New-Object Text.StringBuilder
foreach ($p in $parts) {
    $text = [IO.File]::ReadAllText($p.FullName, $utf8) -replace "`r`n", "`n"
    [void]$sb.Append($text.TrimEnd("`n")).Append("`n")
}
$all = $sb.ToString() -replace "`n", "`r`n"
[IO.File]::WriteAllText($out, $all, $utf8)

# Syntax check of the PowerShell payload
$tokens = $null; $errors = $null
[void][Management.Automation.Language.Parser]::ParseInput($all, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host ("Line {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) -ForegroundColor Red }
    throw "$($errors.Count) syntax error(s)"
}
# The batch header must stay ASCII (cmd.exe parses it before PowerShell takes over)
$header = ([IO.File]::ReadAllText($out, $utf8) -split "#>")[0]
if ($header -match '[^\x00-\x7F]') { throw 'Batch header contains non-ASCII characters' }
Write-Host ("Built {0} ({1:N0} bytes, {2} parts)" -f $out, (Get-Item $out).Length, $parts.Count)
