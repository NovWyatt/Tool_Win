# Chạy thật Dọn ổ C bằng quyền thường, không xoá gì: "Xem ổ C" (chỉ đọc) và "Dọn rác của bạn" ở chế độ chạy thử
# (-ChayThu: đo rồi dừng trước bước hỏi xoá). Báo cáo và file kết quả vào thư mục tạm (DOC_KET_QUA).
# KiemThu: doc-may
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\KetQua.ps1"
$out = New-TestDir 'doc_that'
$env:DOC_KET_QUA = $out
if (Test-IsAdmin) { Skip-Test 'đang có quyền Admin: bài này chỉ chạy bằng quyền thường'; Complete-Test }
$manifest = [IO.File]::ReadAllText("$ToolsDir\don-o-c\tool.json", [Text.Encoding]::UTF8) | ConvertFrom-Json
$actionIds = @($manifest.actions | ForEach-Object { $_.id })
$script = "$ToolsDir\don-o-c\DonOC.ps1"
$ps = Join-Path $PSHOME 'powershell.exe'

function Test-Result([string]$Prefix, [string]$CheDo, [bool]$DryRun) {
    $j = @(Get-ChildItem -LiteralPath $out -Filter "$Prefix*.json")
    Check ($j.Count -eq 1) "$CheDo`: một file kết quả ($($j.Count))"
    if (-not $j.Count) { return }
    $r = [IO.File]::ReadAllText($j[0].FullName) | ConvertFrom-Json
    $ph = @($r.phatHien)
    Check ($r.chuan -eq 'tramtool.ketqua/1' -and $r.cheDo -eq $CheDo -and [bool]$r.chayThu -eq $DryRun -and $ph.Count -ge 1) "$CheDo`: đầu file, có phát hiện ($(@($ph | ForEach-Object { $_.ma }) -join ', '))"
    Check (-not @($ph | Where-Object { $_.ma -notmatch '^[A-Z][A-Z0-9_]+$' -or ($_.chayTiep -and $actionIds -notcontains $_.chayTiep.action) }).Count) "$CheDo`: mã hợp lệ, nút trỏ tới action có thật"
    $hr = Read-RunResult -Path $j[0].FullName
    Check ($hr -and @($hr.phatHien).Count -eq $ph.Count) "$CheDo`: trạm đọc được"
}

$sw = [Diagnostics.Stopwatch]::StartNew()
$o = & $ps -NoProfile -ExecutionPolicy Bypass -File $script -Mode kiem-tra -KhongDung 2>&1 | Out-String
Check ($LASTEXITCODE -eq 0 -and @(Get-ChildItem -LiteralPath $out -Filter 'BaoCao_DonOC_*.txt').Count -eq 1 -and $o -notmatch 'Lỗi không lường trước') "Xem ổ C thật: mã $LASTEXITCODE, có báo cáo ($([int]$sw.Elapsed.TotalSeconds) giây)"
Test-Result 'KetQua_DonOC_KiemTra_' 'kiem-tra' $false

$sw.Restart()
$o = & $ps -NoProfile -ExecutionPolicy Bypass -File $script -Mode don-cua-toi -ChayThu -KhongDung 2>&1 | Out-String
Check ($LASTEXITCODE -eq 0 -and $o -match 'Chạy thử: không xoá gì|Không có gì cần dọn' -and @(Get-ChildItem -LiteralPath $out -Filter 'NhatKy_DonOC_*.txt').Count -eq 0) "Dọn rác của bạn chạy thử: mã $LASTEXITCODE, không xoá, không ghi nhật ký dọn ($([int]$sw.Elapsed.TotalSeconds) giây)"
Test-Result 'KetQua_DonOC_DonCuaToi_' 'don-cua-toi' $true
Remove-Item Env:DOC_KET_QUA
Complete-Test
