<#
.SYNOPSIS
    Chạy mọi bài thử giả lập của Trạm Tool (tests\<bộ>\*.ps1 và tools\mdf2sql\tests bằng Python).

.DESCRIPTION
    Mỗi bài thử chạy trong một tiến trình PowerShell riêng, với quyền thường, thư mục tạm riêng nằm ngoài repo
    (mặc định <thư mục cha của repo>\.TramTool-KiemThu, đổi bằng biến TRAMTOOL_TEST_TAM); đạt hết thì xoá.
    Lệnh đổi máy (dịch vụ, registry hệ thống, BitLocker, máy in, Wi-Fi, Office, xoá file...) đều được thay bằng
    hàm giả; registry chỉ ghi vào HKCU\Software\TramToolTest và được xoá khi chạy xong.
    Bài có thẻ "doc-may" có đọc máy thật (chỉ đọc, ví dụ chạy thử -DryRun), bỏ chúng bằng -KhongDocMay.

.EXAMPLE
    .\tests\ChayTatCa.ps1
    .\tests\ChayTatCa.ps1 -Chi new-windows,office
    .\tests\ChayTatCa.ps1 -Chi 'new-windows/2*' -ChiTiet -GiuTam
#>
param(
    [string[]]$Chi = @(),          # chỉ chạy bộ/bài khớp: tên bộ (new-windows) hoặc bộ/bài (new-windows/2_*)
    [switch]$GiuTam,               # giữ thư mục tạm của cả bài đạt (bài hỏng luôn được giữ)
    [switch]$ChiTiet,              # in toàn bộ đầu ra của từng bài
    [switch]$KhongDocMay,          # bỏ các bài có đọc máy thật (chỉ đọc)
    [switch]$DanhSach,             # chỉ liệt kê bài thử
    [int]$GioiHanGiay = 900        # quá thời gian này thì dừng bài
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
$Here = $PSScriptRoot
$RepoRoot = (Resolve-Path (Join-Path $Here '..')).Path
. (Join-Path $Here 'lib\XoaAnToan.ps1')
$Tam = Get-TestBase
$env:TRAMTOOL_TEST_TAM = $Tam

if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Đang có quyền Administrator. Hãy chạy bài thử bằng cửa sổ PowerShell thường (không "Run as administrator").' -ForegroundColor Red
    exit 99
}

# ---------------------------------------------------------------------------------------------- tìm bài thử
function Get-Tags([string]$File) {
    # Thẻ ở các dòng chú thích đầu file:  # KiemThu: 32bit, doc-may
    $tags = @()
    foreach ($l in @(Get-Content -LiteralPath $File -TotalCount 15 -Encoding UTF8)) {
        if ($l -match '^\s*#\s*KiemThu:\s*(.+)$') { $tags += @($Matches[1] -split '[,\s]+' | Where-Object { $_ }) }
    }
    return $tags
}

$tests = New-Object System.Collections.Generic.List[object]
foreach ($d in @(Get-ChildItem -LiteralPath $Here -Directory | Where-Object { $_.Name -notin 'lib', 'node_modules' } | Sort-Object Name)) {
    foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter '*.ps1' -File | Where-Object { $_.Name -notlike '_*' } | Sort-Object Name)) {
        $n = [IO.Path]::GetFileNameWithoutExtension($f.Name)
        $in = Join-Path $d.FullName "$n.dauvao.txt"
        $tests.Add([pscustomobject]@{ Suite = $d.Name; Name = $n; Kind = 'ps'; File = $f.FullName; Tags = @(Get-Tags $f.FullName); Input = $(if (Test-Path -LiteralPath $in) { $in } else { '' }) })
    }
}
$m2s = Join-Path $RepoRoot 'tools\mdf2sql'
if (Test-Path -LiteralPath (Join-Path $m2s 'tests')) {
    $tests.Add([pscustomobject]@{ Suite = 'mdf2sql'; Name = 'unittest'; Kind = 'py'; File = (Join-Path $m2s 'tests'); Tags = @(); Input = '' })
}

function Test-Wanted($t) {
    if (-not $Chi.Count) { return $true }
    foreach ($c in $Chi) {
        foreach ($p in @($c -split ',' | Where-Object { $_ })) {
            if ($p.Contains('/')) { if ("$($t.Suite)/$($t.Name)" -like $p) { return $true } }
            elseif ($t.Suite -like $p) { return $true }
        }
    }
    return $false
}
$run = @($tests | Where-Object { Test-Wanted $_ })

if ($DanhSach) {
    foreach ($t in $run) { '{0,-40} {1}' -f "$($t.Suite)/$($t.Name)", ($t.Tags -join ', ') }
    exit 0
}
if (-not $run.Count) { Write-Host "Không có bài thử nào khớp: $($Chi -join ', ')" -ForegroundColor Yellow; exit 2 }

# ---------------------------------------------------------------------------------------------- chạy
function Find-Python {
    foreach ($n in 'python', 'py') {
        $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($c -and $c.Source -notlike '*\WindowsApps\*') { return $c.Source }
    }
    return $null
}

function Invoke-One($t) {
    $root = Join-Path $Tam "$($t.Suite)\$($t.Name)"
    $log = Join-Path $Tam "$($t.Suite)\$($t.Name).log"
    [void](New-Item -ItemType Directory -Path (Split-Path $log) -Force)
    foreach ($f in $log, "$log.err") { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    $empty = Join-Path $Tam 'dau-vao-rong.txt'
    if (-not (Test-Path -LiteralPath $empty)) { [IO.File]::WriteAllText($empty, '') }

    $r = [pscustomobject]@{ Test = $t; State = ''; Pass = 0; Fail = 0; Skip = 0; Sec = 0; Log = $log; Note = '' }
    if ($t.Kind -eq 'py') {
        $py = Find-Python
        if (-not $py) { $r.State = 'BỎ QUA'; $r.Note = 'không thấy Python'; return $r }
        $exe = $py; $argList = @('-m', 'unittest', 'discover', '-s', 'tests', '-t', '.'); $wd = Split-Path $t.File
        $env:PYTHONDONTWRITEBYTECODE = '1'; $env:PYTHONIOENCODING = 'utf-8'; $env:PYTHONUTF8 = '1'
        $env:TRAMTOOL_TEST_ROOT = $root
    } else {
        if ($t.Tags -contains 'doc-may' -and $KhongDocMay) { $r.State = 'BỎ QUA'; $r.Note = 'đọc máy thật (-KhongDocMay)'; return $r }
        $exe = if ($t.Tags -contains '32bit') { "$env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" } else { "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $t.File + '"'))
        $wd = Split-Path $t.File
        $env:TRAMTOOL_TEST_ROOT = $root
    }
    $stdin = if ($t.Input) { $t.Input } else { $empty }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $exe -ArgumentList $argList -WorkingDirectory $wd -RedirectStandardInput $stdin `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err" -NoNewWindow -PassThru
    $null = $p.Handle   # giữ handle để đọc được ExitCode sau khi tiến trình thoát
    if (-not $p.WaitForExit($GioiHanGiay * 1000)) {
        & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
        $r.Note = "quá $GioiHanGiay giây, đã dừng"
    }
    $p.WaitForExit()
    $r.Sec = [math]::Round($sw.Elapsed.TotalSeconds)
    Remove-Item Env:\TRAMTOOL_TEST_ROOT -ErrorAction SilentlyContinue
    $out = if (Test-Path -LiteralPath $log) { [IO.File]::ReadAllText($log) } else { '' }
    $err = if (Test-Path -LiteralPath "$log.err") { [IO.File]::ReadAllText("$log.err") } else { '' }

    if ($t.Kind -eq 'py') {
        # unittest in ra stderr: "Ran 12 tests ..." rồi "OK", "OK (skipped=1)" hoặc "FAILED (failures=1, errors=2)"
        $all = $out + "`n" + $err
        $ran = if ($all -match 'Ran (\d+) tests?') { [int]$Matches[1] } else { 0 }
        foreach ($k in 'failures', 'errors') { if ($all -match "$k=(\d+)") { $r.Fail += [int]$Matches[1] } }
        if ($all -match 'skipped=(\d+)') { $r.Skip = [int]$Matches[1] }
        $r.Pass = $ran - $r.Fail - $r.Skip
        if (-not $ran) { $r.State = 'LỖI CHẠY' } elseif ($r.Fail -or $p.ExitCode) { $r.State = 'HỎNG' } else { $r.State = 'ĐẠT' }
    } else {
        $m = [regex]::Matches($out, '#KIEMTHU dat=(\d+) hong=(\d+) boqua=(\d+)')
        if ($m.Count) {
            $g = $m[$m.Count - 1].Groups
            $r.Pass = [int]$g[1].Value; $r.Fail = [int]$g[2].Value; $r.Skip = [int]$g[3].Value
            $r.State = if ($r.Fail -or $p.ExitCode -or $r.Note) { 'HỎNG' } else { 'ĐẠT' }
        } else {
            $r.Pass = ([regex]::Matches($out, '(?m)^\s*PASS ')).Count
            $r.Fail = ([regex]::Matches($out, '(?m)^\s*FAIL ')).Count
            $r.State = 'LỖI CHẠY'
            if (-not $r.Note) { $r.Note = "thoát mã $($p.ExitCode) trước khi tổng kết" }
        }
    }
    $r | Add-Member -NotePropertyName Out -NotePropertyValue $out
    $r | Add-Member -NotePropertyName Err -NotePropertyValue $err
    return $r
}

Write-Host "Trạm Tool - chạy $($run.Count) bài thử (quyền thường, thư mục tạm: $Tam)" -ForegroundColor Cyan
[void](New-Item -ItemType Directory -Path $Tam -Force)
[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\TramToolTest', $false)
$results = @()
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($t in $run) {
    $label = "$($t.Suite)/$($t.Name)"
    Write-Host ('  {0,-44}' -f $label) -NoNewline
    $r = Invoke-One $t
    $results += $r
    $color = switch ($r.State) { 'ĐẠT' { 'Green' } 'BỎ QUA' { 'DarkYellow' } default { 'Red' } }
    $nums = if ($r.State -eq 'BỎ QUA' -and -not $r.Pass) { '' } else { "{0} đạt, {1} hỏng{2}" -f $r.Pass, $r.Fail, $(if ($r.Skip) { ", $($r.Skip) bỏ qua" } else { '' }) }
    Write-Host ('{0,-9}' -f $r.State) -ForegroundColor $color -NoNewline
    Write-Host ('{0,-28} {1,4} giây  {2}' -f $nums, $r.Sec, $r.Note)
    if ($ChiTiet -and $r.Out) { $r.Out.TrimEnd() -split "`r?`n" | ForEach-Object { "      | $_" }; if ($r.Err.Trim()) { $r.Err.TrimEnd() -split "`r?`n" | ForEach-Object { "      ! $_" } } }
    elseif ($r.State -in 'HỎNG', 'LỖI CHẠY') {
        $lines = @($r.Out -split "`r?`n")
        $fails = @($lines | Where-Object { $_ -match '^\s*FAIL\b|^(FAIL|ERROR):' })
        foreach ($l in ($fails | Select-Object -First 20)) { Write-Host "      $($l.Trim())" -ForegroundColor Red }
        if ($r.State -eq 'LỖI CHẠY' -or $t.Kind -eq 'py') {
            foreach ($l in (@($lines + @($r.Err -split "`r?`n")) | Where-Object { $_.Trim() } | Select-Object -Last 12)) { Write-Host "      | $l" -ForegroundColor DarkGray }
        }
        Write-Host "      Nhật ký: $($r.Log)" -ForegroundColor DarkGray
    }
    if ($r.State -eq 'ĐẠT' -and -not $GiuTam) {
        try { Remove-TestDir (Join-Path $Tam "$($t.Suite)\$($t.Name)") } catch { Write-Host "      (chưa xoá được thư mục tạm: $($_.Exception.Message))" -ForegroundColor DarkYellow }
    }
}
[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\TramToolTest', $false)

$bad = @($results | Where-Object { $_.State -in 'HỎNG', 'LỖI CHẠY' })
$sumP = ($results | Measure-Object Pass -Sum).Sum; $sumF = ($results | Measure-Object Fail -Sum).Sum; $sumS = ($results | Measure-Object Skip -Sum).Sum
$skipped = @($results | Where-Object { $_.State -eq 'BỎ QUA' }).Count
Write-Host ''
Write-Host ("Tổng: {0} bài, {1} hỏng, {2} bỏ qua; {3} mục đạt, {4} mục hỏng, {5} mục bỏ qua; {6} giây" -f $results.Count, $bad.Count, $skipped, $sumP, $sumF, $sumS, [math]::Round($sw.Elapsed.TotalSeconds)) -ForegroundColor $(if ($bad.Count) { 'Red' } else { 'Green' })
if ($bad.Count) {
    Write-Host "Thư mục tạm, nhật ký của bài hỏng được giữ ở: $Tam" -ForegroundColor DarkGray
    exit 1
}
if (-not $GiuTam) {
    try { Remove-TestDir $Tam } catch { Write-Host "(chưa xoá được thư mục tạm $($Tam): $($_.Exception.Message))" -ForegroundColor DarkYellow }
}
exit 0
