# Tiến độ công cụ (tienDo, chuẩn tramtool.tiendo/1) và cập nhật trạm từ kho git (hub\lib\CapNhat.ps1,
# hub\fixes\CapNhat-TramTool.ps1). Tiến độ: đọc, kẹp số, bỏ file sai chuẩn; công cụ giả nhận "<flag> <file>", trạm đọc
# trong lúc chạy, xoá khi cửa sổ đóng, đường dẫn không vào Lịch sử. Cập nhật: kho git tạm (kho gốc trống, máy phát
# triển, máy trạm) trong thư mục tạm: mới nhất, kéo bản mới, file đang sửa, nhánh lệch, file không theo dõi giữ nguyên.
# Không đụng kho thật, không mở cửa sổ, không hỏi UAC, không cần mạng.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\Catalog.ps1"; . "$HubDir\lib\AnToan.ps1"; . "$HubDir\lib\Launcher.ps1"
. "$HubDir\lib\Checks.ps1"; . "$HubDir\lib\KetQua.ps1"; . "$HubDir\lib\CapNhat.ps1"
$dir = $TestRoot
function Save-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false)) }

# Không mở cửa sổ, không giành focus (Start-ToolAction gọi các hàm này).
function Invoke-BringToFront { }
function Start-Process {
    param([Parameter(Position = 0)]$FilePath, $ArgumentList, $WorkingDirectory, [switch]$PassThru, $Verb)
    if ($Verb) { throw 'bài thử không được hỏi UAC' }
    $sp = @{ FilePath = $FilePath; PassThru = $true; WindowStyle = 'Hidden' }
    if ($ArgumentList) { $sp.ArgumentList = $ArgumentList }
    if ($WorkingDirectory) { $sp.WorkingDirectory = $WorkingDirectory }
    Microsoft.PowerShell.Management\Start-Process @sp
}

Write-KT '1. Read-ToolProgress' Cyan
$pf = Join-Path $dir 'td.json'
Save-Utf8 $pf '{ "chuan": "tramtool.tiendo/1", "phanTram": 42.567, "buoc": "Khúc 3/9", "xong": 1, "tong": 3, "conLaiGiay": 125 }'
$r = Read-ToolProgress -Path $pf
Check ($r.phanTram -eq 42.6 -and $r.buoc -eq 'Khúc 3/9' -and $r.xong -eq 1 -and $r.tong -eq 3 -and $r.conLaiGiay -eq 125) "đọc đúng ($($r.phanTram)%, $($r.buoc))"
Save-Utf8 $pf ('{ "chuan": "tramtool.tiendo/1", "phanTram": 250, "buoc": "' + ('a' * 300) + '\u0007\nb", "conLaiGiay": -5, "xong": "x" }')
$r = Read-ToolProgress -Path $pf
Check ($r.phanTram -eq 100 -and $r.buoc.Length -eq 200 -and $r.conLaiGiay -eq 0 -and $null -eq $r.xong) 'kẹp số vào khoảng, cắt chữ 200 ký tự, bỏ số hỏng'
Save-Utf8 $pf '{ "chuan": "tramtool.tiendo/1", "phanTram": "NaN", "buoc": "dòng 1\ndòng 2" }'
$r = Read-ToolProgress -Path $pf
Check ($null -eq $r.phanTram -and $r.buoc -eq 'dòng 1 dòng 2') 'phần trăm không phải số thì để trống; xuống dòng thành dấu cách'
Save-Utf8 $pf '{ "chuan": "khac/1", "phanTram": 10 }'
Check ($null -eq (Read-ToolProgress -Path $pf)) 'sai chuẩn: bỏ'
Save-Utf8 $pf '{ "chuan": "tramtool.tiendo/1", "phanTr'
Check ($null -eq (Read-ToolProgress -Path $pf)) 'file ghi dở (JSON hỏng): bỏ, không lỗi'
Save-Utf8 $pf ('{ "chuan": "tramtool.tiendo/1", "buoc": "' + ('x' * 70000) + '" }')
Check ($null -eq (Read-ToolProgress -Path $pf)) 'file quá 64 KB: bỏ'
Check ($null -eq (Read-ToolProgress -Path (Join-Path $dir 'khong-co.json')) -and $null -eq (Read-ToolProgress -Path '')) 'chưa có file: bỏ'

Write-KT '2. Clear-ToolProgressDir' Cyan
$pd = Join-Path $dir 'tien-do'
New-Item -ItemType Directory -Path $pd | Out-Null
foreach ($n in 'cu.json', 'cu.json.tmp', 'moi.json', 'khac.txt') { Save-Utf8 (Join-Path $pd $n) '{}' }
foreach ($n in 'cu.json', 'cu.json.tmp', 'khac.txt') { (Get-Item (Join-Path $pd $n)).LastWriteTime = (Get-Date).AddDays(-3) }
Clear-ToolProgressDir -Dir $pd
Check ((@(Get-ChildItem $pd | ForEach-Object Name) | Sort-Object) -join ',' -eq 'khac.txt,moi.json') 'xoá file tiến độ cũ hơn 2 ngày, giữ file mới và file khác'
Remove-Item (Join-Path $pd '*') -Force

Write-KT '3. tool.json: tienDo' Cyan
$tools = Join-Path $dir 'tools'
$td = Join-Path $tools 'thu-tien-do'
New-Item -ItemType Directory -Path $td -Force | Out-Null
$script = @'
param([string]$Ten = '', [string]$TienDo = '', [int]$Ngu = 4)
"$Ten|$TienDo" | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'thamso.txt') -Encoding UTF8
if ($TienDo) {
    $o = '{ "chuan": "tramtool.tiendo/1", "phanTram": 37.5, "buoc": "Bản vẽ 2/4", "xong": 1, "tong": 4 }'
    [IO.File]::WriteAllText($TienDo + '.tmp', $o, (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath ($TienDo + '.tmp') -Destination $TienDo -Force
}
Start-Sleep -Seconds $Ngu
exit 0
'@
[IO.File]::WriteAllText((Join-Path $td 'Chay.ps1'), $script, (New-Object Text.UTF8Encoding $true))
Save-Utf8 (Join-Path $td 'tool.json') (@{
        id = 'thu-tien-do'; name = 'Thử tiến độ'; category = 'khac'
        actions = @(
            @{ id = 'chay'; label = 'Chạy'; file = 'Chay.ps1'; risk = 'read-only'; tienDo = @{ flag = '-TienDo' }; args = @(@{ id = 'ten'; type = 'text'; flag = '-Ten'; label = 'Tên' }) }
            @{ id = 'hong'; label = 'Hỏng'; file = 'Chay.ps1'; risk = 'read-only'; tienDo = @{ flag = 'khong hop le' } }
        )
    } | ConvertTo-Json -Depth 8)
$cat = Get-HubCatalog -ToolsDir $tools -RootDir $dir
$tool = @($cat | Where-Object { $_.id -eq 'thu-tien-do' })[0]
$act = @($tool.actions | Where-Object { $_.id -eq 'chay' })[0]
Check ($act.tienDo.flag -eq '-TienDo') 'đọc tienDo.flag'
Check ($null -eq @($tool.actions | Where-Object { $_.id -eq 'hong' })[0].tienDo -and (@($tool.problems) -join ' ') -match 'tienDo') 'flag sai dạng: bỏ, báo lỗi tool.json'

Write-KT '4. Chạy công cụ có tiến độ' Cyan
$hist = Join-Path $dir 'history.jsonl'
$argv = Resolve-ActionArguments -Action $act -Values ([pscustomobject]@{ ten = 'Bản vẽ A' })
$res = Start-ToolAction -Tool $tool -Action $act -Arguments $argv -HistoryPath $hist -ProgressDir $pd
Check ($res.ok -and $res.jobId) "mở được ($($res.message))"
$job = $null
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 250
    Update-ToolJobs -HistoryPath $hist
    $job = @(Get-ToolJobs | Where-Object { $_.id -eq $res.jobId })[0]
    if ($job.tienDo) { break }
}
Check ($job.state -eq 'running' -and $job.tienDo.phanTram -eq 37.5 -and $job.tienDo.buoc -eq 'Bản vẽ 2/4' -and $job.tienDo.tong -eq 4) "đang chạy: trạm đọc được tiến độ ($($job.tienDo.phanTram)%)"
$ts = [IO.File]::ReadAllText((Join-Path $td 'thamso.txt')).Trim() -split '\|'
$progFile = @(Get-ChildItem $pd -Filter '*.json')[0]
Check ($ts[0] -eq 'Bản vẽ A' -and $ts[1] -and $progFile -and $ts[1] -eq $progFile.FullName) 'công cụ nhận tham số của người dùng và "-TienDo <file trong hub\data\tien-do>"'
$h = Get-Content $hist -Encoding UTF8 | Select-Object -Last 1 | ConvertFrom-Json
Check ((@($h.args) -join ' ') -eq '-Ten Bản vẽ A' -and (Get-Content $hist -Raw) -notmatch '-TienDo|\.json') 'Lịch sử chỉ ghi tham số người dùng, không ghi đường dẫn tiến độ'
for ($i = 0; $i -lt 60 -and $job.state -eq 'running'; $i++) { Start-Sleep -Milliseconds 250; Update-ToolJobs -HistoryPath $hist; $job = @(Get-ToolJobs | Where-Object { $_.id -eq $res.jobId })[0] }
Check ($job.state -eq 'done' -and $null -eq $job.tienDo) "cửa sổ đóng: hết tiến độ ($($job.state))"
Check (@(Get-ChildItem $pd).Count -eq 0) 'cửa sổ đóng: xoá file tiến độ'
$res2 = Start-ToolAction -Tool $tool -Action $act -Arguments (Resolve-ActionArguments -Action $act -Values $null) -HistoryPath $hist
$ts2 = ''
for ($i = 0; $i -lt 40 -and -not $ts2; $i++) { Start-Sleep -Milliseconds 250; try { $ts2 = [IO.File]::ReadAllText((Join-Path $td 'thamso.txt')).Trim() } catch { } ; if ($ts2 -ne '|') { $ts2 = '' } }
Check ($res2.ok -and $ts2 -eq '|') 'không truyền thư mục tiến độ (ví dụ nút Cài): không thêm -TienDo'
for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 250; Update-ToolJobs -HistoryPath $hist; if (-not (Test-ToolJobsRunning)) { break } }

Write-KT '5. Kho git tạm' Cyan
$ErrorActionPreference = 'Continue'   # git in cảnh báo ra stderr (2>&1 thành ErrorRecord): không dừng bài
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $git) { Skip-Test 'máy chưa cài Git'; Complete-Test }
function G([string]$Repo, [Parameter(ValueFromRemainingArguments = $true)][string[]]$GitRest) {
    $o = & git.exe -C $Repo @GitRest 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitRest -join ' ') lỗi: $o" }
    return $o
}
$origin = Join-Path $dir 'goc.git'; $dev = Join-Path $dir 'may-dev'; $tram = Join-Path $dir 'may-tram'
& git.exe init --quiet --bare -b main $origin 2>&1 | Out-Null
& git.exe clone --quiet $origin $dev 2>&1 | Out-Null
foreach ($r in $dev) { G $r config user.name 'Thu Nghiem' | Out-Null; G $r config user.email 'thu@example.invalid' | Out-Null; G $r config commit.gpgsign false | Out-Null }
New-Item -ItemType Directory -Path (Join-Path $dev 'tools\a') -Force | Out-Null
Save-Utf8 (Join-Path $dev 'tools\a\tool.json') '{ "id": "a" }'
Save-Utf8 (Join-Path $dev 'README.md') "ban 1`n"
G $dev add --all | Out-Null; G $dev commit --quiet -m 'ban 1' | Out-Null; G $dev push --quiet -u origin main 2>&1 | Out-Null
& git.exe clone --quiet $origin $tram 2>&1 | Out-Null
G $tram config user.name 'Tram' | Out-Null; G $tram config user.email 'tram@example.invalid' | Out-Null; G $tram config commit.gpgsign false | Out-Null
function Commit-Dev([string]$Rel, [string]$Text, [string]$Msg) {
    $p = Join-Path $dev $Rel
    New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force | Out-Null
    Save-Utf8 $p $Text
    G $dev add --all | Out-Null; G $dev commit --quiet -m $Msg | Out-Null; G $dev push --quiet 2>&1 | Out-Null
}
function Invoke-CapNhat([string]$Repo) {
    $psi = New-Object Diagnostics.ProcessStartInfo "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$HubDir\fixes\CapNhat-TramTool.ps1`" -ThuMuc `"$Repo`" -KhongHoi"
    $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'; $psi.EnvironmentVariables['GCM_INTERACTIVE'] = 'never'
    $p = [Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(120000)) { $p.Kill(); return @{ Code = -1; Out = 'quá 2 phút' } }
    return @{ Code = $p.ExitCode; Out = ($o.Result + $e.Result) }
}
$head = { param($r) (& git.exe -C $r rev-parse HEAD).Trim() }

$plain = Join-Path $dir 'khong-phai-kho'
New-Item -ItemType Directory -Path $plain | Out-Null
$i0 = Get-RepoUpdateInfo -RootDir $plain
Check ($i0.git -and -not $i0.repo -and -not $i0.canUpdate -and $i0.reason -match 'không phải bản sao git') "thư mục không phải kho git: $($i0.reason)"
$r = Invoke-CapNhat $plain
Check ($r.Code -eq 2) "script: không phải kho git thì mã 2 ($($r.Code))"

$i1 = Get-RepoUpdateInfo -RootDir $tram -Fetch
Check ($i1.repo -and $i1.branch -eq 'main' -and $i1.upstream -eq 'origin/main' -and $i1.fetched -and $i1.behind -eq 0 -and -not $i1.canUpdate -and $i1.subject -eq 'ban 1') "máy trạm mới nhất: nhánh $($i1.branch), $($i1.commit) $($i1.subject)"
$r = Invoke-CapNhat $tram
Check ($r.Code -eq 0 -and $r.Out -match 'Đã là bản mới nhất') "script: đã mới nhất, mã 0 ($($r.Code))"

Commit-Dev 'tools\a\tool.json' '{ "id": "a", "version": "2" }' 'a ban 2'
Commit-Dev 'tools\b\requirements.txt' "numpy==2.1`n" 'them b'
$i2 = Get-RepoUpdateInfo -RootDir $tram
Check ($i2.behind -eq 0 -and -not $i2.fetched) 'chưa hỏi kho (không -Fetch): chưa biết có bản mới'
$i2 = Get-RepoUpdateInfo -RootDir $tram -Fetch
Check ($i2.fetched -and $i2.behind -eq 2 -and $i2.canUpdate -and @($i2.incoming).Count -eq 2 -and $i2.incoming[0].subject -eq 'them b') "hỏi kho: 2 commit mới, cập nhật được ($($i2.behind))"
Save-Utf8 (Join-Path $tram 'ket_qua_khach.txt') 'du lieu khach'
$r = Invoke-CapNhat $tram
Check ($r.Code -eq 0 -and (& $head $tram) -eq (& $head $dev)) "script: kéo bản mới, mã 0 ($($r.Code))"
Check ([IO.File]::ReadAllText((Join-Path $tram 'tools\a\tool.json')) -match '"version": "2"' -and (Test-Path (Join-Path $tram 'tools\b\requirements.txt'))) 'file mới về máy trạm'
Check ([IO.File]::ReadAllText((Join-Path $tram 'ket_qua_khach.txt')) -eq 'du lieu khach') 'file không theo dõi (kết quả, dữ liệu khách) giữ nguyên'
Check ($r.Out -match 'Công cụ đổi thư viện[^\r\n]*: b' -and $r.Out -notmatch 'Tắt trạm') 'báo công cụ đổi thư viện (b); không đổi hub thì không bảo khởi động lại trạm'

Commit-Dev 'hub\lib\X.ps1' '# x' 'sua hub'
$r = Invoke-CapNhat $tram
Check ($r.Code -eq 0 -and $r.Out -match 'Tắt trạm') 'đổi phần máy chủ (hub/): bảo tắt trạm rồi mở lại'

Commit-Dev 'README.md' "ban 3`n" 'ban 3'
Save-Utf8 (Join-Path $tram 'README.md') "sua tren may tram`n"
$truoc = & $head $tram
$i3 = Get-RepoUpdateInfo -RootDir $tram -Fetch
Check (-not $i3.canUpdate -and @($i3.dirty) -contains 'README.md' -and $i3.reason -match 'file đang sửa') "file đang sửa: không cho cập nhật ($($i3.reason))"
$r = Invoke-CapNhat $tram
Check ($r.Code -eq 2 -and (& $head $tram) -eq $truoc -and [IO.File]::ReadAllText((Join-Path $tram 'README.md')) -eq "sua tren may tram`n") 'script: file đang sửa thì dừng mã 2, không đổi gì, giữ nguyên sửa đổi'
& git.exe -C $tram checkout -- README.md 2>&1 | Out-Null

G $tram commit --quiet --allow-empty -m 'commit rieng tren may tram' | Out-Null
$i4 = Get-RepoUpdateInfo -RootDir $tram -Fetch
Check ($i4.ahead -eq 1 -and $i4.behind -eq 1 -and -not $i4.canUpdate -and $i4.reason -match 'lệch') "nhánh lệch: không cho cập nhật ($($i4.ahead) riêng, $($i4.behind) mới)"
$truoc = & $head $tram
$r = Invoke-CapNhat $tram
Check ($r.Code -eq 2 -and (& $head $tram) -eq $truoc -and @(& git.exe -C $tram log --merges --oneline).Count -eq 0) 'script: nhánh lệch thì dừng mã 2, không gộp'

& git.exe -C $tram checkout --quiet --detach 2>&1 | Out-Null
$i5 = Get-RepoUpdateInfo -RootDir $tram
Check (-not $i5.canUpdate -and $i5.reason -match 'detached') 'không ở nhánh nào: không cho cập nhật'

Write-KT '6. Trạm: API, giao diện' Cyan
$srv = [IO.File]::ReadAllText((Join-Path $HubDir 'TramTool.ps1'))
Check ($srv -match "'GET /api/update'" -and $srv -match "'POST /api/update/run'" -and $srv -match "file = 'CapNhat-TramTool\.ps1'; admin = \`$false") 'máy chủ có API cập nhật, cửa sổ cập nhật chạy quyền thường'
Check ($srv -match '-ProgressDir \$ProgressDir\)' -and $srv -match 'Clear-ToolProgressDir -Dir \$ProgressDir') 'máy chủ truyền thư mục tiến độ khi chạy, dọn file cũ khi mở'
$tk = $null; $er = $null
[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $HubDir 'fixes\CapNhat-TramTool.ps1'), [ref]$tk, [ref]$er)
$fix = (@($tk | Where-Object { $_.Kind -ne 'Comment' } | ForEach-Object { $_.Text }) -join ' ')   # bỏ chú thích (có nói 'không stash, không rebase')
Check ($fix -notmatch '(?i)reset --hard|stash|push|rebase|--force|clean -' -and $fix -match 'merge.*--ff-only') 'script chỉ fast-forward: không reset, stash, rebase, push, clean'
$js = [IO.File]::ReadAllText((Join-Path $HubDir 'web\js\jobs.js'))
Check ($js -match 'j\.tienDo' -and $js -match '<progress class="job-bar"' -and $js -match "actionId === 'cap-nhat'") 'thanh Đang chạy vẽ tiến độ; cửa sổ cập nhật đóng thì đọc lại danh sách'

Complete-Test
