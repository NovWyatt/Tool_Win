# Build: copy src\Chung.ps1 into every ..\*.bat between the lines #=====CHUNG_BAT_DAU===== and #=====CHUNG_KET_THUC=====
# (the rest of each .bat is edited by hand). Each .bat stays standalone, so it can still be sent to a customer alone.
#   build.ps1          rewrite the .bat files whose shared part is out of date
#   build.ps1 -Kiem    only check (exit 1 when a .bat is out of date or its PowerShell part does not parse)
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less scripts as ANSI.
param([switch]$Kiem)
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$toolDir = Split-Path $src -Parent
$utf8 = New-Object Text.UTF8Encoding $false
$begin = '#=====CHUNG_BAT_DAU====='
$end = '#=====CHUNG_KET_THUC====='
$psStart = '#=====PS_START====='

$chung = [IO.File]::ReadAllText((Join-Path $src 'Chung.ps1'), $utf8).TrimStart([char]0xFEFF) -replace "`r`n", "`n"
# Markers count only as whole lines, so the shared code may not contain them as whole lines.
$reBegin = New-Object Text.RegularExpressions.Regex ('(?m)^' + [regex]::Escape($begin) + '[ \t]*$')
$reEnd = New-Object Text.RegularExpressions.Regex ('(?m)^' + [regex]::Escape($end) + '[ \t]*$')
if ($reBegin.IsMatch($chung) -or $reEnd.IsMatch($chung)) { throw 'Chung.ps1 must not contain a marker line' }
$block = $begin + "`n# Sinh tu src\Chung.ps1 bang src\build.ps1: sua o file do, dung sua o day.`n" + $chung.TrimEnd("`n") + "`n" + $end

$stale = @(); $bad = @(); $done = 0
foreach ($bat in @(Get-ChildItem -LiteralPath $toolDir -Filter '*.bat' -File | Sort-Object Name)) {
    $text = [IO.File]::ReadAllText($bat.FullName, $utf8) -replace "`r`n", "`n"
    $mb = $reBegin.Matches($text)
    if (-not $mb.Count) { continue }
    $me = $reEnd.Matches($text)
    if ($mb.Count -ne 1 -or $me.Count -ne 1 -or $me[0].Index -lt $mb[0].Index) { $bad += "$($bat.Name): needs exactly one $begin line followed by one $end line"; continue }
    $i = $mb[0].Index
    if ($text.IndexOf($psStart) -lt 0 -or $text.IndexOf($psStart) -gt $i) { $bad += "$($bat.Name): shared part must be after $psStart"; continue }
    $new = $text.Substring(0, $i) + $block + $text.Substring($me[0].Index + $me[0].Length)
    $ps = $new.Substring($new.IndexOf($psStart) + $psStart.Length)
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseInput($ps, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { $bad += ("{0}: {1} syntax error(s), first at line {2}: {3}" -f $bat.Name, $errors.Count, $errors[0].Extent.StartLineNumber, $errors[0].Message); continue }
    $done++
    if ($new -eq $text) { continue }
    $stale += $bat.Name
    if (-not $Kiem) { [IO.File]::WriteAllText($bat.FullName, ($new -replace "`n", "`r`n"), $utf8) }
}
foreach ($b in $bad) { Write-Host "  [X] $b" -ForegroundColor Red }
if ($Kiem) {
    foreach ($s in $stale) { Write-Host "  [!] $s is out of date: run src\build.ps1" -ForegroundColor Yellow }
    Write-Host ("Checked {0} .bat file(s): {1} out of date, {2} error(s)" -f $done, $stale.Count, $bad.Count)
    if ($stale.Count -or $bad.Count) { exit 1 }
    exit 0
}
Write-Host ("Built {0} .bat file(s), rewrote {1}: {2}" -f $done, $stale.Count, ($stale -join ', '))
if ($bad.Count) { exit 1 }
exit 0
