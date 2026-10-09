# Kết quả JSON chung và máy chủ giao diện của công cụ (hub\lib\KetQua.ps1, Launcher, Catalog): đọc, chuẩn hoá file
# kết quả (cả cách ghi của bản cũ), tìm file của đúng lần chạy, ghi tóm tắt vào Lịch sử khi cửa sổ đóng, mã 2/3 thành
# "chưa làm"/"một phần", theo dõi action tự nâng quyền; webServer: nhận ra máy chủ đang chạy, tắt (máy chủ giả là một
# tiến trình PowerShell nghe trên 127.0.0.1). Mọi file trong thư mục tạm; không mở trình duyệt, không hỏi UAC.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\Catalog.ps1"; . "$HubDir\lib\AnToan.ps1"; . "$HubDir\lib\Launcher.ps1"
. "$HubDir\lib\Checks.ps1"; . "$HubDir\lib\KetQua.ps1"
$dir = $TestRoot
function Save-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false)) }
function Save-Obj([string]$Path, $Obj) { Save-Utf8 $Path (ConvertTo-Json -InputObject $Obj -Depth 8) }

# Không mở cửa sổ, không giành focus, không mở trình duyệt hay hỏi UAC: Start-ToolAction, Open-ToolServer gọi các hàm này.
$script:Launched = New-Object System.Collections.ArrayList
function Invoke-BringToFront { }
function Start-Process {
    param([Parameter(Position = 0)]$FilePath, $ArgumentList, $WorkingDirectory, [switch]$PassThru, $Verb)
    [void]$script:Launched.Add([pscustomobject]@{ FilePath = [string]$FilePath; Verb = [string]$Verb })
    if ($Verb -or [string]$FilePath -match '^https?://') { return }
    $sp = @{ FilePath = $FilePath; PassThru = $true; WindowStyle = 'Hidden' }
    if ($ArgumentList) { $sp.ArgumentList = $ArgumentList }
    if ($WorkingDirectory) { $sp.WorkingDirectory = $WorkingDirectory }
    Microsoft.PowerShell.Management\Start-Process @sp
}

Write-Host '== Read-RunResult: chuẩn tramtool.ketqua/1'
$std = Join-Path $dir 'chuan.json'
Save-Obj $std ([ordered]@{
        chuan = 'tramtool.ketqua/1'; congCu = 'thu-ket-qua'; cheDo = 'kiem-tra'; phienBan = '1.0'; may = 'MAYGIA'; taiKhoan = 'thu'
        batDau = '2026-10-09T10:00:00'; ketThuc = '2026-10-09T10:01:00'; maThoat = 0; trangThai = 'xong'; ma = 'XONG'; thongDiep = 'Đã kiểm tra xong.'
        tomTat = [ordered]@{ loi = 1; canhBao = 1; thongTin = 1 }
        phatHien = @(
            [ordered]@{ ma = 'A'; mucDo = 'loi'; tieuDe = 'Lỗi A'; cachSua = 'Sửa A'; chayTiep = [ordered]@{ congCu = 'myexcelfix'; action = 'sua-loi' } }
            [ordered]@{ ma = 'B'; mucDo = 'canh-bao'; tieuDe = 'Cần xem B'; chiTiet = "dòng 1`ndòng 2"; chayTiep = [ordered]@{ congCu = '../x'; action = 'a b' } }
            [ordered]@{ ma = 'C'; mucDo = 'la-lam'; tieuDe = 'Thông tin C' }
        )
        tep = @([ordered]@{ nhan = 'Báo cáo'; duongDan = 'C:\BaoCao.txt' }, [ordered]@{ nhan = 'Tương đối'; duongDan = 'bao_cao.txt' })
    })
$r = Read-RunResult -Path $std
Check ($r.trangThai -eq 'xong' -and $r.maThoat -eq 0 -and $r.chuan -eq 'tramtool.ketqua/1' -and $r.thongDiep -eq 'Đã kiểm tra xong.') "trạng thái, mã, lời nhắn: $($r.trangThai) $($r.maThoat)"
Check (@($r.phatHien).Count -eq 3 -and $r.phatHien[2].mucDo -eq 'thong-tin') 'mức lạ thành thong-tin'
Check ($r.phatHien[0].chayTiep.congCu -eq 'myexcelfix' -and $r.phatHien[0].chayTiep.action -eq 'sua-loi') 'chayTiep hợp lệ giữ lại'
Check ($null -eq $r.phatHien[1].chayTiep) 'chayTiep có ký tự lạ bị bỏ'
Check ($r.phatHien[1].chiTiet -eq "dòng 1`ndòng 2") 'chiTiet giữ xuống dòng'
Check (@($r.tep).Count -eq 1 -and $r.tep[0].duongDan -eq 'C:\BaoCao.txt') 'tep: chỉ nhận đường dẫn đầy đủ'
Check ($r.tomTat.loi -eq 1 -and $r.tomTat.canhBao -eq 1 -and $r.tomTat.thongTin -eq 1) 'tomTat lấy từ file'
$s = Get-RunResultSummary $r
Check ($s.path -eq $r.path -and $s.trangThai -eq 'xong' -and $s.tomTat.loi -eq 1 -and -not $s.Contains('phatHien')) 'tóm tắt cho Lịch sử không kèm danh sách phát hiện'

Write-Host '== Read-RunResult: cách ghi của bản cũ'
$old = Join-Path $dir 'cu_chuyendulieu.json'
Save-Obj $old ([ordered]@{ CongCu = 'new-windows'; PhienBan = '2.0'; CheDo = 'xuat'; ChayThu = $false; MaThoat = 3; KetQua = 'mot-phan'
        ThuMucSaoLuu = 'E:\DuLieu_SaoLuu'; May = 'MAYGIA'; NguoiDung = 'thu'; Loi = @('Không chép được máy in'); LuuY = @('Wi-Fi ẩn bỏ qua', 'Driver cũ') })
$r = Read-RunResult -Path $old
Check ($r.trangThai -eq 'mot-phan' -and $r.maThoat -eq 3 -and $r.congCu -eq 'new-windows' -and $r.taiKhoan -eq 'thu') "Chuyển dữ liệu 2.0 (tên trường viết hoa): $($r.trangThai)"
Check ($r.tomTat.loi -eq 1 -and $r.tomTat.canhBao -eq 2 -and $r.phatHien[0].tieuDe -eq 'Không chép được máy in') 'Loi, LuuY thành phát hiện lỗi, cần xem'
Check (@($r.tep).Count -eq 1 -and $r.tep[0].nhan -eq 'Thư mục sao lưu') 'ThuMucSaoLuu thành tep'
$old = Join-Path $dir 'cu_chualam.json'
Save-Obj $old ([ordered]@{ CongCu = 'new-windows'; MaThoat = 2; KetQua = 'chua-lam' })
Check ((Read-RunResult -Path $old).trangThai -eq 'thieu-dieu-kien') "'chua-lam' thành thieu-dieu-kien"
$old = Join-Path $dir 'cu_myexcel.json'
Save-Obj $old ([ordered]@{ congCu = 'myexcelfix'; cheDo = 'sua'; maThoat = 3; trangThai = 'mot-phan'; canhBao = @('Không sửa được liên kết HoaDon.xlsx'); soCanhBao = 1
        thuMucSaoLuu = 'C:\SaoLuu'; nhatKy = 'C:\SaoLuu\NhatKy_Sua.txt' })
$r = Read-RunResult -Path $old
Check ($r.tomTat.canhBao -eq 1 -and $r.phatHien[0].mucDo -eq 'canh-bao' -and @($r.tep).Count -eq 2) 'MyExcelFix 2026.10.2: canhBao, thuMucSaoLuu, nhatKy'
$old = Join-Path $dir 'cu_mdf2sql.json'
Save-Obj $old ([ordered]@{ cong_cu = 'mdf2sql'; phien_ban = '1.1.1'; ma_thoat = 2; thieu = 1
        muc = @([ordered]@{ ma = 'THIEU_ODBC'; muc = 'bad'; tieu_de = 'Thiếu driver ODBC'; chi_tiet = ''; cach_sua = 'Cài ODBC 18' }, [ordered]@{ ma = 'CONG'; muc = 'ok'; tieu_de = 'Cổng trống' }) })
$r = Read-RunResult -Path $old
Check ($r.trangThai -eq 'thieu-dieu-kien' -and $r.phatHien[0].mucDo -eq 'loi' -and $r.phatHien[0].cachSua -eq 'Cài ODBC 18' -and $r.phatHien[1].mucDo -eq 'ok' -and $r.congCu -eq 'mdf2sql') 'mdf2sql 1.1.1 (doctor --json)'
$many = Join-Path $dir 'nhieu.json'
Save-Obj $many ([ordered]@{ chuan = 'tramtool.ketqua/1'; maThoat = 0; phatHien = @(1..350 | ForEach-Object { [ordered]@{ ma = "M$_"; mucDo = 'loi'; tieuDe = "Lỗi $_" } }) })
$r = Read-RunResult -Path $many
Check (@($r.phatHien).Count -eq 300 -and $r.boBot -eq 50 -and $r.tomTat.loi -eq 300) "giữ 300 mục, bỏ bớt $($r.boBot)"
$bad = Join-Path $dir 'hong.json'
Save-Utf8 $bad '{ "maThoat": 0, '
$err = ''; try { [void](Read-RunResult -Path $bad) } catch { $err = $_.Exception.Message }
Check ($err -like '*JSON hỏng*') "JSON hỏng báo rõ: $err"

Write-Host '== Find-RunResult: file của đúng lần chạy'
$tdir = Join-Path $dir 'cong-cu'
$kq = Join-Path $tdir 'kq'
New-Item -ItemType Directory -Force -Path $kq, (Join-Path $tdir 'khac') | Out-Null
$tool = [ordered]@{ id = 'thu-ket-qua'; name = 'Thử kết quả'; dir = $tdir; auto = $false
    outputs = @([pscustomobject]@{ label = 'Kết quả'; dir = 'kq'; glob = 'KetQua_*.json'; ketQua = $true }, [pscustomobject]@{ label = 'Khác'; dir = 'khac'; glob = '*.json' })
}
$t0 = Get-Date
Save-Obj (Join-Path $kq 'KetQua_cu.json') @{ congCu = 'thu-ket-qua'; maThoat = 1 }
(Get-Item (Join-Path $kq 'KetQua_cu.json')).LastWriteTime = $t0.AddHours(-1)
Save-Obj (Join-Path $kq 'KetQua_congcukhac.json') @{ congCu = 'cong-cu-khac'; maThoat = 0 }
Save-Obj (Join-Path $kq 'KetQua_khongphai.json') @{ ten = 'không có maThoat' }
Save-Obj (Join-Path $tdir 'khac\KetQua_moi.json') @{ congCu = 'thu-ket-qua'; maThoat = 0 }
Check ((Find-RunResult -Tool $tool -Since $t0) -eq '') 'chỉ có file cũ, file của công cụ khác, file không phải kết quả: không chọn'
Save-Obj (Join-Path $kq 'KetQua_dung.json') @{ congCu = 'thu-ket-qua'; maThoat = 3; trangThai = 'mot-phan' }
$found = Find-RunResult -Tool $tool -Since $t0
Check ($found -like '*\kq\KetQua_dung.json') "chọn file của lần chạy: $found"
$outs = @(Get-ToolOutputs -Tool $tool)
Check (@($outs | Where-Object { $_.ketQua }).Count -eq 4 -and @($outs | Where-Object { $_.name -eq 'KetQua_moi.json' -and -not $_.ketQua }).Count -eq 1) 'Get-ToolOutputs đánh dấu ketQua theo outputs'

Write-Host '== Get-JobState: quy ước mã thoát'
$map = @{ 0 = 'done'; 1 = 'failed'; 2 = 'blocked'; 3 = 'partial'; 5 = 'failed'; 1223 = 'cancelled'; -1073741510 = 'closed' }
foreach ($k in $map.Keys) { Check ((Get-JobState -ExitCode $k) -eq $map[$k]) "mã $k -> $($map[$k])" }
Check ((Get-JobState -ExitCode $null) -eq 'ended') 'không đọc được mã -> ended'

Write-Host '== Cửa sổ công cụ đóng: Lịch sử có mã thoát và tóm tắt kết quả'
$hist = Join-Path $dir 'history.jsonl'
$ps1 = Join-Path $tdir 'chay.ps1'
Set-Content -LiteralPath $ps1 -Encoding UTF8 -Value (@'
$r = [ordered]@{ chuan = 'tramtool.ketqua/1'; congCu = 'thu-ket-qua'; cheDo = 'sua'; maThoat = 3; trangThai = 'mot-phan'; thongDiep = 'Làm được 2 trên 3 việc'
    phatHien = @([ordered]@{ ma = 'VIEC_3'; mucDo = 'loi'; tieuDe = 'Việc 3 không làm được' }) }
Start-Sleep -Milliseconds 300
[IO.File]::WriteAllText((Join-Path $PSScriptRoot ('kq\KetQua_chay_{0}.json' -f (Get-Date -Format 'HHmmssfff'))), ($r | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
exit 3
'@)
Remove-Item (Join-Path $kq 'KetQua_dung.json')
$action = [ordered]@{ id = 'chay'; label = 'Chạy thử'; type = 'console'; file = 'chay.ps1'; admin = $false; selfElevates = $false; keepOpen = $false; restorePoint = $false; risk = 'read-only'; args = @(); fixedArgs = @() }
$res = Start-ToolAction -Tool $tool -Action $action -HistoryPath $hist
Check ($res.ok -and $res.jobId) "mở được, có jobId ($($res.message))"
$job = $script:Jobs[$res.jobId]
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($job.state -eq 'running' -and $sw.Elapsed.TotalSeconds -lt 60) { Start-Sleep -Milliseconds 300; Update-ToolJobs -HistoryPath $hist }
Check ($job.state -eq 'partial' -and $job.exitCode -eq 3) "công việc: $($job.state), mã $($job.exitCode)"
Check ($job.ketQua -and $job.ketQua.trangThai -eq 'mot-phan' -and $job.ketQua.tomTat.loi -eq 1 -and $job.ketQua.thongDiep -like 'Làm được 2*') 'công việc có tóm tắt kết quả'
$h = @(Get-RunHistory -HistoryPath $hist)[0]
Check ($h.state -eq 'partial' -and $h.exitCode -eq 3 -and $h.ketQua.path -like '*\kq\KetQua_chay_*.json') "Lịch sử: $($h.state), kết quả $($h.ketQua.path)"
$endLine = @(Get-Content $hist -Encoding UTF8 | Where-Object { $_ -like '*"type":"end"*' })[0]
Check ($endLine -match '"ketQua"' -and $endLine -notmatch 'phatHien') 'dòng kết thúc trong history.jsonl chỉ ghi tóm tắt'

Write-Host '== Lịch sử ghi trước 1.4.0: mã 2, 3 đã ghi là failed'
$hist2 = Join-Path $dir 'history_cu.jsonl'
foreach ($c in 2, 3, 1) {
    $tm = "2026-10-0$($c)T10:00:00.000+07:00"
    Add-JsonLine -Path $hist2 -InputObject ([ordered]@{ time = $tm; toolId = 'x'; toolName = 'X'; actionId = 'a'; actionLabel = 'A'; ok = $true })
    Add-JsonLine -Path $hist2 -InputObject ([ordered]@{ type = 'end'; time = $tm; exitCode = $c; state = 'failed'; durationSec = 1 })
}
$states = @(Get-RunHistory -HistoryPath $hist2 | ForEach-Object { "$($_.exitCode)=$($_.state)" }) -join ' '
Check ($states -eq '1=failed 3=partial 2=blocked') "đọc lại theo quy ước: $states"

Write-Host '== Tự nâng quyền (selfElevates): theo dõi khi công cụ có tool.json'
Save-Utf8 (Join-Path $tdir 'tu_nang.ps1') 'exit 2'
# File kết quả của lần chạy trên ghi cách đây chưa tới 2 giây (khoảng nới khi tìm): lùi giờ để lần này không nhận nhầm.
Get-ChildItem $kq -Filter 'KetQua_*.json' | ForEach-Object { $_.LastWriteTime = (Get-Date).AddMinutes(-5) }
$self = [ordered]@{ id = 'tu-nang'; label = 'Tự nâng quyền'; type = 'console'; file = 'tu_nang.ps1'; admin = $false; selfElevates = $true; keepOpen = $false; restorePoint = $false; risk = 'read-only'; args = @(); fixedArgs = @() }
$res = Start-ToolAction -Tool $tool -Action $self -HistoryPath $hist
Check ($res.ok -and $res.jobId) 'có tool.json: theo dõi (cửa sổ đầu đợi cửa sổ Admin, quy ước kiểm ở tinh\3_DanhMuc)'
$job = $script:Jobs[$res.jobId]
Check ($job.selfElevates -eq $true -and $job.elevated -eq $false) 'công việc đánh dấu tự nâng quyền'
$sw.Restart()
while ($job.state -eq 'running' -and $sw.Elapsed.TotalSeconds -lt 60) { Start-Sleep -Milliseconds 300; Update-ToolJobs -HistoryPath $hist }
Check ($job.state -eq 'blocked' -and $null -eq $job.ketQua) "mã 2 -> chưa làm, không có file kết quả mới: $($job.state)"
$autoTool = [ordered]@{ id = 'tu-phat-hien'; name = 'Chưa có tool.json'; dir = $tdir; auto = $true; outputs = @() }
$res = Start-ToolAction -Tool $autoTool -Action $self -HistoryPath $hist
Check ($res.ok -and -not $res.jobId) 'chưa có tool.json: không theo dõi (không biết script có đợi không)'
$adm = [ordered]@{ id = 'admin'; label = 'Admin'; type = 'console'; file = 'tu_nang.ps1'; admin = $true; selfElevates = $true; keepOpen = $false; restorePoint = $false; risk = 'read-only'; args = @(); fixedArgs = @() }
$res = Start-ToolAction -Tool $tool -Action $adm -HistoryPath $hist
Check (@($script:Launched | Where-Object { $_.Verb -eq 'RunAs' }).Count -eq 1) 'admin: trạm tự mở bằng RunAs (bài thử không hỏi UAC thật)'

Write-Host '== Catalog: webServer'
$wdir = Join-Path $dir 'tools\web-gia'
New-Item -ItemType Directory -Force -Path $wdir | Out-Null
Save-Utf8 (Join-Path $wdir 'chay.bat') '@echo off'
Save-Obj (Join-Path $wdir 'tool.json') ([ordered]@{ id = 'web-gia'; name = 'Web giả'; category = 'khac'; actions = @(
            [ordered]@{ id = 'giao-dien'; label = 'Giao diện'; file = 'chay.bat'; webServer = [ordered]@{ stateFile = 'server.json'; app = 'thu-web' } }
            [ordered]@{ id = 'thieu'; label = 'Thiếu app'; file = 'chay.bat'; webServer = [ordered]@{ stateFile = 'server.json' } }
        ) })
$wt = Read-ToolManifest -ManifestPath (Join-Path $wdir 'tool.json') -RootDir $dir
$wa = $wt.actions[0]
Check ($wa.webServer.app -eq 'thu-web' -and $wa.webServer.stateFile -eq 'server.json') 'đọc webServer'
Check ($null -eq $wt.actions[1].webServer -and @($wt.problems | Where-Object { $_ -like '*webServer cần stateFile và app*' }).Count -eq 1) 'webServer thiếu app: báo lỗi khai báo'
Check (-not (Get-ToolServer -Tool $wt -Action $wa).running) 'chưa có file trạng thái: không chạy'

Write-Host '== Máy chủ giao diện giả'
$fake = Join-Path $dir 'may_chu_gia.ps1'
$busyFlag = Join-Path $dir 'ban.txt'
$stateFile = Join-Path $wdir 'server.json'
Set-Content -LiteralPath $fake -Encoding UTF8 -Value @'
param([string]$StateFile, [string]$BusyFlag)
$tcp = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $tcp.Start(); $port = $tcp.LocalEndpoint.Port; $tcp.Stop()
$l = New-Object Net.HttpListener; $l.Prefixes.Add("http://127.0.0.1:$port/"); $l.Start()
$token = 'tok' + [guid]::NewGuid().ToString('N')
$st = [ordered]@{ app = 'thu-web'; version = '9.9'; pid = $PID; port = $port; url = "http://127.0.0.1:$port/?k=$token"; token = $token; started = (Get-Date).ToString('s') }
[IO.File]::WriteAllText($StateFile, ($st | ConvertTo-Json))
$deadline = (Get-Date).AddMinutes(3)
while ((Get-Date) -lt $deadline) {
    $task = $l.GetContextAsync()
    while (-not $task.AsyncWaitHandle.WaitOne(300)) { if ((Get-Date) -gt $deadline) { break } }
    if (-not $task.IsCompleted) { break }
    $ctx = $task.Result; $path = $ctx.Request.Url.AbsolutePath; $code = 200; $body = '{}'; $stop = $false
    if ($path -eq '/api/health') { $body = ([ordered]@{ ok = $true; app = 'thu-web'; pid = $PID; port = $port; jobs_running = [int](Test-Path $BusyFlag) } | ConvertTo-Json -Compress) }
    elseif ($path -eq '/api/shutdown' -and $ctx.Request.HttpMethod -eq 'POST') {
        Add-Content -LiteralPath ($StateFile + '.than') -Value $ctx.Request.ContentLength64   # máy chủ không đọc thân: trạm phải gửi rỗng
        if ($ctx.Request.Headers['X-Token'] -ne $token) { $code = 403; $body = '{"error":"Từ chối truy cập"}' }
        elseif (Test-Path $BusyFlag) { $code = 409; $body = '{"error":"Đang chuyển đổi, tắt lúc này sẽ để lại database tạm."}' }
        else { $body = '{"ok":true}'; $stop = $true }
    } else { $code = 404 }
    $b = [Text.Encoding]::UTF8.GetBytes($body)
    $ctx.Response.StatusCode = $code; $ctx.Response.ContentType = 'application/json; charset=utf-8'
    $ctx.Response.OutputStream.Write($b, 0, $b.Length); $ctx.Response.Close()
    if ($stop) { break }
}
$l.Stop(); Remove-Item -LiteralPath $StateFile -ErrorAction SilentlyContinue
'@
$srvProc = Microsoft.PowerShell.Management\Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$fake`"", '-StateFile', "`"$stateFile`"", '-BusyFlag', "`"$busyFlag`"") -WindowStyle Hidden -PassThru
try {
    $sw.Restart()
    while (-not (Test-Path $stateFile) -and $sw.Elapsed.TotalSeconds -lt 20) { Start-Sleep -Milliseconds 200 }
    Start-Sleep -Milliseconds 300
    $s = Get-ToolServer -Tool $wt -Action $wa
    Check ($s.running -and $s.pid -eq $srvProc.Id -and $s.port -gt 0 -and $s.version -eq '9.9' -and $s.busy -eq 0) "đang chạy: cổng $($s.port), pid $($s.pid)"
    Check (-not $s.Contains('url') -and -not $s.Contains('token')) 'không trả URL, mã thông hành cho giao diện'
    $script:Launched.Clear()
    $port = Open-ToolServer -Tool $wt -Action $wa
    Check ($port -eq $s.port -and @($script:Launched | Where-Object { $_.FilePath -like "http://127.0.0.1:$port/?k=tok*" }).Count -eq 1) 'mở lại đúng URL của máy chủ (bài thử không mở trình duyệt)'

    $real = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8
    $st = $real | ConvertFrom-Json
    $variants = @(
        @{ Name = 'app khác'; Json = ($real -replace '"thu-web"', '"app-khac"') }
        @{ Name = 'URL ra ngoài 127.0.0.1'; Json = ($real -replace [regex]::Escape("http://127.0.0.1:$($st.port)/"), 'http://example.com/') }
        @{ Name = 'URL khác cổng'; Json = ($real -replace [regex]::Escape("http://127.0.0.1:$($st.port)/"), "http://127.0.0.1:$($st.port + 1)/") }
        @{ Name = 'pid không khớp /api/health'; Json = ($real -replace ('"pid":\s*' + $st.pid), ('"pid": ' + $PID)) }
        @{ Name = 'tiến trình đã tắt'; Json = ($real -replace ('"pid":\s*' + $st.pid), '"pid": 4999999') }
    )
    foreach ($v in $variants) {
        Save-Utf8 $stateFile $v.Json
        Check (-not (Get-ToolServer -Tool $wt -Action $wa).running) "file trạng thái $($v.Name): coi là không chạy"
    }
    Save-Utf8 $stateFile $real

    Save-Utf8 $busyFlag 'ban'
    $stop = Stop-ToolServer -Tool $wt -Action $wa
    Check (-not $stop.ok -and $stop.busy -and $stop.message -like 'Đang chuyển đổi*') "đang bận: không tắt, báo lời của máy chủ ($($stop.message))"
    Check ((Get-ToolServer -Tool $wt -Action $wa).busy -eq 1) 'health báo đang làm 1 việc'
    Remove-Item $busyFlag
    $stop = Stop-ToolServer -Tool $wt -Action $wa
    Check ($stop.ok) "tắt: $($stop.message)"
    $lens = @(Get-Content -LiteralPath ($stateFile + '.than') -ErrorAction SilentlyContinue)
    Check ($lens.Count -eq 2 -and @($lens | Where-Object { $_ -ne '0' }).Count -eq 0) "lệnh tắt gửi POST không kèm thân (máy chủ tắt ngay không bị cắt kết nối giữa chừng): $($lens -join ',')"
    $exited = $srvProc.WaitForExit(15000)
    Check ($exited -and -not (Test-Path $stateFile)) 'máy chủ giả thoát, xoá file trạng thái'
    Check (-not (Get-ToolServer -Tool $wt -Action $wa).running) 'sau khi tắt: không chạy'
    $stop = Stop-ToolServer -Tool $wt -Action $wa
    Check ($stop.ok -and $stop.message -like '*từ trước*') 'tắt lần nữa: báo đã tắt từ trước'
} finally {
    if (-not $srvProc.HasExited) { try { $srvProc.Kill() } catch { } }
}

Complete-Test
