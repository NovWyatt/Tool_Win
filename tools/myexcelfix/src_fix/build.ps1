# Build: join src_fix\NN_*.cmd/ps1 into FixMyExcel_VietQR.bat (UTF-8 without BOM, CRLF).
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$out = Join-Path (Split-Path $src -Parent) 'FixMyExcel_VietQR.bat'
$parts = Get-ChildItem -LiteralPath $src -File | Where-Object { $_.Name -match '^\d\d_.*\.(cmd|ps1)$' } | Sort-Object Name
$utf8 = New-Object Text.UTF8Encoding $false
$sb = New-Object Text.StringBuilder
foreach ($p in $parts) {
    $text = [IO.File]::ReadAllText($p.FullName, $utf8) -replace "`r`n", "`n"
    [void]$sb.Append($text.TrimEnd("`n")).Append("`n")
}
$all = $sb.ToString() -replace "`n", "`r`n"

# Version stamp: every __MYX_VERSION__ (title, header, $script:Version) becomes "version" from ..\tool.json
$toolJson = Join-Path (Split-Path $src -Parent) 'tool.json'
$version = [string]((Get-Content -LiteralPath $toolJson -Raw -Encoding UTF8 | ConvertFrom-Json).version)
if ($version -notmatch '^[0-9A-Za-z][0-9A-Za-z.\-]*$') { throw "Bad version in tool.json: '$version'" }
if ($all.IndexOf('__MYX_VERSION__') -lt 0) { throw 'No __MYX_VERSION__ placeholder in the parts' }
$all = $all.Replace('__MYX_VERSION__', $version)

$tokens = $null; $errors = $null
[void][Management.Automation.Language.Parser]::ParseInput($all, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host ("Line {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) -ForegroundColor Red }
    throw "$($errors.Count) syntax error(s)"
}
$header = ($all -split "#>")[0]
if ($header -match '[^\x00-\x7F]') { throw 'Batch header contains non-ASCII characters' }
[IO.File]::WriteAllText($out, $all, $utf8)
Write-Host ("Built {0} v{1} ({2:N0} bytes, {3} parts)" -f $out, $version, (Get-Item $out).Length, $parts.Count)
