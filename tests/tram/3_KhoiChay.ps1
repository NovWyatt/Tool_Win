# Trạm chạy công cụ .ps1 qua powershell -Command: mã thoát của công cụ phải đi ra ngoài nguyên vẹn (hub\lib\Launcher.ps1),
# và tham số dựng từ tool.json (fixedArgs + giá trị form) phải tới đúng công cụ. Phần sau chạy Máy in LAN ở chế độ
# chạy thử (-ChayThu -KhongDung) trên máy này: chỉ đọc (dò máy này, địa chỉ 127.0.0.1), không đổi gì.
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"
. "$HubDir\lib\Launcher.ps1"
$dir = $TestRoot
Set-Content -LiteralPath (Join-Path $dir 'exit3.ps1') -Value 'Write-Host "thu exit 3"; exit 3' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $dir 'throw.ps1') -Value 'throw "loi thu"' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $dir 'ok.ps1') -Value 'cmd /c exit 5; Write-Host "xong"' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $dir 'thamso.ps1') -Value ("param([switch]`$ChayThu, [string]`$Duong)`r`n" + 'Set-Content -LiteralPath (Join-Path $PSScriptRoot "thamso.txt") -Value "ChayThu=$ChayThu Duong=$Duong" -Encoding UTF8; exit 0') -Encoding UTF8

function Invoke-LikeHub {
    param([string]$File, $Arguments, [bool]$KeepOpen = $false, [string]$Log = '')
    $cmd = Get-LaunchCommand -File $File -Arguments $Arguments -KeepOpen $KeepOpen
    $sp = @{ FilePath = $cmd.Exe; ArgumentList = $cmd.Args; WorkingDirectory = $cmd.WorkDir; PassThru = $true; WindowStyle = 'Hidden' }
    if ($Log) { $sp.RedirectStandardOutput = $Log }
    $p = Start-Process @sp
    $null = $p.Handle   # giữ handle để đọc được ExitCode sau khi tiến trình thoát
    if (-not $p.WaitForExit(180000)) { $p.Kill(); return 'treo' }
    $p.WaitForExit()
    return $p.ExitCode
}

Write-Host '== mã thoát qua Launcher'
$c = Invoke-LikeHub (Join-Path $dir 'exit3.ps1') @()
Check ($c -eq 3) "exit 3 đi ra ngoài: $c"
$c = Invoke-LikeHub (Join-Path $dir 'throw.ps1') @()
Check ($c -eq 1) "throw thành mã 1: $c"
$c = Invoke-LikeHub (Join-Path $dir 'ok.ps1') @()
Check ($c -eq 0) "lệnh ngoài lỗi trước đó không làm hỏng mã 0: $c"
$argv = @([pscustomobject]@{ Value = '-ChayThu'; IsFlag = $true }, [pscustomobject]@{ Value = '-Duong'; IsFlag = $true }, [pscustomobject]@{ Value = "D:\Thư mục (x86)\it's a b"; IsFlag = $false })
$c = Invoke-LikeHub (Join-Path $dir 'thamso.ps1') $argv
$got = if (Test-Path (Join-Path $dir 'thamso.txt')) { (Get-Content (Join-Path $dir 'thamso.txt') -Raw -Encoding UTF8).Trim() } else { '' }
Check ($c -eq 0 -and $got -eq "ChayThu=True Duong=D:\Thư mục (x86)\it's a b") "tham số có dấu, ngoặc, nháy đơn tới nguyên vẹn: $got"

Write-Host '== Máy in LAN: tham số dựng từ tool.json, chạy thử'
$tool = Get-Content "$ToolsDir\may-in-lan\tool.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$main = "$ToolsDir\may-in-lan\MayInLan.ps1"
$cases = @(
    @{ Action = 'ket-noi-may-in'; Values = @{ 'may-chu' = $env:COMPUTERNAME; 'chay-thu' = $true } }
    @{ Action = 'them-may-in-ip'; Values = @{ 'dia-chi' = '127.0.0.1'; 'kieu' = 'tu-dong'; 'chay-thu' = $true } }
    @{ Action = 'ket-noi-thu-muc'; Values = @{ 'duong-dan' = "\\$env:COMPUTERNAME\TramToolKhongCo"; 'chay-thu' = $true } }
    @{ Action = 'noi-bao-mat'; Values = @{ 'muc' = 'rpc-named-pipe'; 'chay-thu' = $true } }
)
foreach ($cs in $cases) {
    $action = $tool.actions | Where-Object { $_.id -eq $cs.Action }
    $argv = @(Resolve-ActionArguments -Action $action -Values ([pscustomobject]$cs.Values))
    $argv += [pscustomobject]@{ Value = '-KhongDung'; IsFlag = $true }   # thử tự động: không chờ Enter
    $log = Join-Path $dir ("out-" + $cs.Action + ".txt")
    $c = Invoke-LikeHub $main $argv -Log $log
    $out = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '' }
    # 0 = xong, 2 = thiếu điều kiện (vd không thấy máy in ở 127.0.0.1), 3 = một phần; 1 = lỗi (tham số sai, văng lỗi)
    Check ($c -in 0, 2, 3) "$($cs.Action) -ChayThu: mã $c ($((@($argv | ForEach-Object { $_.Value })) -join ' '))"
    Check ($out -notmatch 'A parameter cannot be found|Cannot bind|ParameterBindingException') "$($cs.Action): tham số khớp với MayInLan.ps1"
}

Complete-Test
