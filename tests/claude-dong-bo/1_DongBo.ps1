# Bài thử DongBoClaude.ps1 bằng dữ liệu Claude giả trong thư mục tạm (CDB_CLAUDE_APPDATA, CDB_NGUOI_DUNG, CDB_DU_LIEU,
# CDB_KET_QUA): hai tài khoản trên một máy, Kiểm tra; Đồng bộ A sang B (thêm, bỏ phiên đã xoá ở B, bỏ phiên thiếu nội
# dung, bỏ trường gắn tài khoản cũ, hạ chế độ bypass, giữ nguyên các trường khác), chạy lại không thêm gì, Hoàn tác (giữ
# mục đã dùng tiếp); Sao lưu thành gói; Đồng bộ từ gói sang "máy khác" có thư mục người dùng khác (chép nội dung, sửa
# đường dẫn) rồi Hoàn tác; Claude Desktop đang mở (giả lập, và tiến trình claude.exe giả khi chạy qua .bat). Không đụng
# dữ liệu Claude thật.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\KetQua.ps1"
$toolDir = Join-Path $ToolsDir 'claude-dong-bo'
$manifest = [IO.File]::ReadAllText((Join-Path $toolDir 'tool.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json

$tkA = '11111111-aaaa-4aaa-8aaa-111111111111'; $tcA = '22222222-aaaa-4aaa-8aaa-222222222222'
$tkB = '33333333-bbbb-4bbb-8bbb-333333333333'; $tcB = '44444444-bbbb-4bbb-8bbb-444444444444'
$tkC = '55555555-cccc-4ccc-8ccc-555555555555'; $tcC = '66666666-cccc-4ccc-8ccc-666666666666'
Add-Type -AssemblyName System.Web.Extensions
$jser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$jser.MaxJsonLength = [int]::MaxValue

function Save-Json([string]$Path, $Obj) {
    $d = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [IO.File]::WriteAllText($Path, ($Obj | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding $false))
}
function New-Machine([string]$Name, [string]$Current, [string]$UserName = 'Thu') {
    $root = New-TestDir $Name
    $m = [pscustomobject]@{ Root = $root; App = (Join-Path $root 'AppData\Claude'); Nha = (Join-Path $root "Users\$UserName") }
    Save-Json (Join-Path $m.App 'config.json') @{ lastKnownAccountUuid = $Current; locale = 'vi' }
    New-Item -ItemType Directory -Path (Join-Path $m.Nha '.claude\projects') -Force | Out-Null
    return $m
}
function New-Session([string]$Dir, [string]$Title, [string]$Cwd, [long]$Last, [hashtable]$Extra = @{}) {
    $u = [guid]::NewGuid().ToString(); $cli = [guid]::NewGuid().ToString()
    $d = [ordered]@{
        sessionId = "local_$u"; cliSessionId = $cli; cwd = $Cwd; originCwd = $Cwd
        gitAnchors = @([ordered]@{ gitRoot = $Cwd; commonDir = "$Cwd\.git"; trustedAt = 1790941016017 })
        lastFocusedAt = $Last; createdAt = ($Last - 100000); lastActivityAt = $Last; model = 'claude-opus-5-5'; effort = 'xhigh'
        sessionSettings = [ordered]@{ ultracode = $false }; isArchived = $false; title = $Title; titleSource = 'auto'
        permissionMode = 'acceptEdits'; bypassChosenInApp = $false
        remoteMcpServersConfig = @([ordered]@{ uuid = 'gia'; name = 'Gia'; url = 'https://vd.test/mcp'; tools = @() })
        writtenBranches = @("$Cwd`0main"); bridgeSessionIds = @('session_gia'); completedTurns = 3; titleTurn = 0
        postTurnSummary = [ordered]@{ status_category = 'review_ready'; status_detail = 'Đã xong <b> & "trích" \ ngược' }
        alwaysAllowedReasons = @(); spawnSeed = @{}; promptAppendSnapshot = [ordered]@{ append = "dòng 1`ndòng 2" }; terminalClaudeTabOrdinal = 2
    }
    foreach ($k in $Extra.Keys) { $d[$k] = $Extra[$k] }
    $f = Join-Path $Dir "local_$u.json"
    Save-Json $f $d
    return [pscustomobject]@{ Id = "local_$u"; Uuid = $u; Cli = $cli; File = $f; Cwd = $Cwd }
}
function New-Transcript($M, $S, [int]$Lines = 3, [switch]$Side) {
    $dir = Join-Path $M.Nha ('.claude\projects\' + ($S.Cwd -replace '[^A-Za-z0-9]', '-'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $f = Join-Path $dir "$($S.Cli).jsonl"
    [IO.File]::WriteAllText($f, ((1..$Lines | ForEach-Object { '{"type":"user","message":{"content":"câu ' + $_ + '"}}' }) -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))
    if ($Side) { $sd = Join-Path $dir "$($S.Cli)\subagents"; New-Item -ItemType Directory -Path $sd -Force | Out-Null; [IO.File]::WriteAllText((Join-Path $sd 'a.jsonl'), '{}') }
    return $f
}
function Get-Listing([string]$Dir) { return (@(Get-ChildItem -LiteralPath $Dir -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($Dir.Length) + '=' + $_.Length }) | Sort-Object) -join '|' }
function Codes { return @($script:Findings | ForEach-Object { $_.ma }) }
function Latest-Result { return @(Get-ChildItem -LiteralPath $kq -Filter 'KetQua_ClaudeDongBo_*.json' | Sort-Object LastWriteTime, Name -Descending)[0] }

# ---- máy 1: tài khoản A có 5 phiên, B (đang đăng nhập) có 1 phiên và đã xoá phiên s5
$may1 = New-Machine 'may1' $tkB
$dA = Join-Path $may1.App "claude-code-sessions\$tkA\$tcA"
$dB = Join-Path $may1.App "claude-code-sessions\$tkB\$tcB"
New-Item -ItemType Directory -Path $dA, $dB -Force | Out-Null
$t0 = [long]1790000000000
$s1 = New-Session $dA 'Phân tích repo' (Join-Path $may1.Nha 'Du-an\Mot') ($t0 + 5000) @{ permissionMode = 'bypassPermissions'; bypassChosenInApp = $true }
$s2 = New-Session $dA 'Hai' 'D:\Repo\Hai' ($t0 + 4000)
$s3 = New-Session $dA 'Ba lưu trữ' 'D:\Repo\Ba' ($t0 + 3000) @{ isArchived = $true }
$s4 = New-Session $dA 'Bốn thiếu nội dung' 'D:\Repo\Bon' ($t0 + 2000)
$s5 = New-Session $dA 'Năm đã xoá ở B' 'D:\Repo\Nam' ($t0 + 1000)
[IO.File]::WriteAllText((Join-Path $dA ('deleted_' + [guid]::NewGuid())), '1790000000000')
$s6 = New-Session $dB 'Sáu của B' 'D:\Repo\Sau' ($t0 + 6000)
[IO.File]::WriteAllText((Join-Path $dB "deleted_$($s5.Uuid)"), '1790000000001')
$tx1 = New-Transcript $may1 $s1 -Side
foreach ($s in $s2, $s3, $s5, $s6) { [void](New-Transcript $may1 $s) }
Save-Json (Join-Path $may1.App 'claude_desktop_config.json') @{ mcpServers = @{}; preferences = @{ bypassPermissionsOptInByAccount = @{ $tkA = $true } } }
Save-Json (Join-Path $may1.Nha '.claude.json') @{ oauthAccount = @{ accountUuid = $tkB; organizationUuid = $tcB; emailAddress = 'b@vd.test' } }

$du = New-TestDir 'du-lieu'
$kq = New-TestDir 'ket_qua'
function Use-Machine($M) {
    $env:CDB_CLAUDE_APPDATA = $M.App
    $script:UserDir = $M.Nha
    $script:ProjectsDir = Join-Path $M.Nha '.claude\projects'
    $script:ClaudeJson = Join-Path $M.Nha '.claude.json'
}
$env:CDB_CLAUDE_APPDATA = $may1.App; $env:CDB_NGUOI_DUNG = $may1.Nha; $env:CDB_DU_LIEU = $du; $env:CDB_KET_QUA = $kq
$env:CDB_MAU_CLAUDE = 'KHONG-CO-TIEN-TRINH-NAY-' + [guid]::NewGuid()
$env:TRAMTOOL_CLAUDEDONGBO_TEST = '1'
. "$toolDir\DongBoClaude.ps1"
Remove-Item Env:TRAMTOOL_CLAUDEDONGBO_TEST
$ChayThu = $false; $KhongDung = $true; $DongClaude = $false; $Tu = ''; $Den = ''
Check ($script:UserDir -eq $may1.Nha -and $script:DataDir -eq $du -and $script:ResultDir -eq $kq) 'biến CDB_* đưa mọi nơi ghi vào thư mục tạm'

# ---- giả lập Claude Desktop đang mở, câu trả lời
$script:GiaMo = @()
$script:DaDong = 0
$script:Answers = New-Object System.Collections.Queue
function Get-ClaudeDesktopProcess { return $script:GiaMo }
function Stop-Process { [CmdletBinding()] param([Parameter(ValueFromPipeline = $true)]$InputObject, [switch]$Force) end { $script:DaDong++; $script:GiaMo = @() } }
function Read-YesNo { param([string]$Question, [bool]$Default = $false) if ($script:Answers.Count) { return $script:Answers.Dequeue() } return $Default }

# ---- tĩnh: mã phát hiện, nút chạy tiếp, chế độ trong tool.json
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $toolDir 'DongBoClaude.ps1'), [ref]$null, [ref]$null)
$calls = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Add-Finding' }, $true))
$bad = @($calls | Where-Object { $_.CommandElements[1] -isnot [Management.Automation.Language.StringConstantExpressionAst] -or $_.CommandElements[1].Value -cnotmatch '^[A-Z][A-Z_]+$' })
Check ($calls.Count -ge 20 -and -not $bad.Count) "Add-Finding: $($calls.Count) chỗ gọi, mã là hằng chữ HOA ($($bad.Count) chỗ sai)"
$tieps = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -match '^claude-dong-bo/' }, $true) | ForEach-Object { $_.Value.Split('/')[1] })
$ids = @($manifest.actions | ForEach-Object { $_.id })
Check ($tieps.Count -and -not @($tieps | Where-Object { $ids -notcontains $_ }).Count) "nút chạy tiếp có trong tool.json ($($tieps -join ', '))"
$modesJ = @($manifest.actions | Where-Object { $_.fixedArgs } | ForEach-Object { $_.fixedArgs[1] })
Check (-not @($modesJ | Where-Object { -not $script:Modes.Contains($_) }).Count -and $modesJ.Count -eq 4) "chế độ trong tool.json có trong công cụ ($($modesJ -join ', '))"
Check (-not @($manifest.pack.include | Where-Object { -not (Test-Path -LiteralPath (Join-Path $toolDir $_)) }).Count) 'gói có đủ file'

# ---- tài khoản đang dùng, nhãn
$script:AppDir = Get-ClaudeAppDir; $script:SessRoot = Join-Path $script:AppDir 'claude-code-sessions'
$c = Get-CurrentAccount
Check ($c.Acct -eq $tkB -and $c.Org -eq $tcB -and $c.Dir -eq $dB) "tài khoản đang dùng là B, tổ chức lấy từ thư mục ($($c.Org))"

# ---- Kiểm tra
$r = Invoke-Mode 'kiem-tra' 6> $null
$cs = Codes
Check ($r -eq 0 -and $cs -contains 'TAI_KHOAN_DANG_DUNG' -and $cs -contains 'TAI_KHOAN_KHAC' -and $cs -contains 'THIEU_PHIEN') "Kiểm tra: mã 0, thấy A và B, B thiếu phiên ($($cs -join ', '))"
$th = @($script:Findings | Where-Object { $_.ma -eq 'THIEU_PHIEN' })[0]
Check ($th.tieuDe -match 'chưa có 3 phiên' -and $th.chayTiep.congCu -eq 'claude-dong-bo' -and $th.chayTiep.action -eq 'dong-bo') "B chưa có 3 phiên, gợi ý chạy Đồng bộ: $($th.tieuDe)"
Check ($cs -contains 'DA_XOA_O_DAY' -and $cs -contains 'PHIEN_THIEU_NOI_DUNG') 'báo phiên đã xoá ở B, phiên thiếu nội dung'
Check (@($script:Findings | Where-Object { $_.ma -eq 'TAI_KHOAN_DANG_DUNG' })[0].tieuDe -match 'b@vd\.test \(33333333\)') 'hiện email của tài khoản thay cho mã'
$lab = Read-Obj (Join-Path $du 'tai-khoan.json')
Check ($lab.$tkB.email -eq 'b@vd.test') 'nhớ email theo mã tài khoản trong du-lieu'
$f = Latest-Result
$hr = if ($f) { Read-RunResult -Path $f.FullName } else { $null }
Check ($hr -and $hr.cheDo -eq 'kiem-tra' -and @($hr.phatHien).Count -eq $cs.Count) 'file kết quả trạm đọc được'

# ---- Đồng bộ: chạy thử, Claude đang mở, thật
$before = Get-Listing $dB
$beforeA = Get-Listing $dA
$ChayThu = $true
$r = Invoke-Mode 'dong-bo' 6> $null
$ChayThu = $false
Check ($r -eq 0 -and (Get-Listing $dB) -eq $before -and -not (Test-Path -LiteralPath (Join-Path $du 'HoanTac'))) 'Đồng bộ chạy thử: mã 0, không ghi gì'
$script:GiaMo = @([pscustomobject]@{ Id = 0; Name = 'claude' })
$script:Answers.Enqueue($false)
$r = Invoke-Mode 'dong-bo' 6> $null
Check ($r -eq 2 -and (Codes) -contains 'CLAUDE_DANG_MO' -and (Get-Listing $dB) -eq $before -and $script:DaDong -eq 0) "Claude đang mở, không cho đóng: mã 2, không ghi gì ($r)"
$script:Answers.Enqueue($true)
$r = Invoke-Mode 'dong-bo' 6> $null
Check ($r -eq 0 -and $script:DaDong -eq 1 -and (Codes) -contains 'DA_DONG_BO') "Claude đang mở, cho đóng: đóng rồi đồng bộ, mã 0 ($r)"
$names = @(Get-ChildItem -LiteralPath $dB -File | ForEach-Object { $_.Name })
$want = @($s1, $s2, $s3, $s6 | ForEach-Object { "$($_.Id).json" })
Check (-not @($want | Where-Object { $names -notcontains $_ }).Count -and $names -notcontains "$($s4.Id).json" -and $names -notcontains "$($s5.Id).json") "B có s1, s2, s3 (thêm) và s6; không có s4 (thiếu nội dung), s5 (đã xoá ở B)"
$w1 = Read-Dict (Join-Path $dB "$($s1.Id).json")
Check (-not $w1.ContainsKey('remoteMcpServersConfig') -and -not $w1.ContainsKey('bridgeSessionIds')) 'bỏ kết nối claude.ai và Remote Control của tài khoản cũ'
Check ($w1['permissionMode'] -eq 'default' -and $w1['bypassChosenInApp'] -eq $false) "B chưa bật bypass: phiên mở lại ở chế độ hỏi trước ($($w1['permissionMode']))"
Check ($w1['title'] -ceq 'Phân tích repo' -and [string]$w1['writtenBranches'][0] -ceq ($s1.Cwd + [char]0 + 'main') -and $w1['cwd'] -eq $s1.Cwd) 'tiêu đề tiếng Việt, ký tự \0 trong nhánh, đường dẫn giữ nguyên'
$src2 = Read-Dict $s2.File
foreach ($k in 'remoteMcpServersConfig', 'bridgeSessionIds') { [void]$src2.Remove($k) }
Check ([IO.File]::ReadAllText((Join-Path $dB "$($s2.Id).json"), [Text.Encoding]::UTF8) -ceq $jser.Serialize($src2)) 'các trường khác giữ nguyên từng ký tự (cả thứ tự)'
Check ((Read-Dict (Join-Path $dB "$($s3.Id).json"))['isArchived'] -eq $true) 'phiên đã lưu trữ vẫn là đã lưu trữ'
$jdirs = @(Get-ChildItem -LiteralPath (Join-Path $du 'HoanTac') -Directory)
$jn = if ($jdirs.Count) { Read-Obj (Join-Path $jdirs[0].FullName 'nhat-ky.json') } else { $null }
Check ($jdirs.Count -eq 1 -and @($jn.viec | Where-Object { $_.loai -eq 'them' }).Count -eq 3 -and -not @($jn.viec | Where-Object { $_.loai -like '*noi-dung' }).Count) 'nhật ký hoàn tác: 3 mục thêm, không chép nội dung (cùng máy)'
$hr = Read-RunResult -Path (Latest-Result).FullName
Check ($hr.cheDo -eq 'dong-bo' -and $hr.maThoat -eq 0 -and @($hr.tep | Where-Object { $_.duongDan -like '*nhat-ky.json' }).Count) 'kết quả có đường dẫn nhật ký'
Check ((Get-Listing $dA) -eq $beforeA) 'tài khoản A không bị đổi'

$script:GiaMo = @()
$r = Invoke-Mode 'dong-bo' 6> $null
Check ($r -eq 0 -and (Codes) -contains 'KHONG_CAN_DONG_BO' -and @(Get-ChildItem -LiteralPath (Join-Path $du 'HoanTac') -Directory).Count -eq 1) 'chạy lại: đã đủ, không thêm, không tạo nhật ký mới'

# ---- Hoàn tác: s2 đã dùng tiếp ở B thì giữ
$p2 = Join-Path $dB "$($s2.Id).json"
$d2 = Read-Dict $p2; $d2['lastActivityAt'] = $t0 + 9000; $d2['completedTurns'] = 4
[IO.File]::WriteAllText($p2, $jser.Serialize($d2), (New-Object Text.UTF8Encoding $false))
$ChayThu = $true
$r = Invoke-Mode 'hoan-tac' 6> $null
$ChayThu = $false
Check ($r -eq 0 -and (Test-Path -LiteralPath (Join-Path $dB "$($s1.Id).json"))) 'Hoàn tác chạy thử: chưa bỏ gì'
$r = Invoke-Mode 'hoan-tac' 6> $null
$names = @(Get-ChildItem -LiteralPath $dB -File -Filter 'local_*' | ForEach-Object { $_.Name })
Check ($r -eq 3 -and (Codes) -contains 'GIU_VI_DA_DOI' -and $names.Count -eq 2 -and $names -contains "$($s2.Id).json" -and $names -contains "$($s6.Id).json") "Hoàn tác: bỏ s1, s3; giữ s2 (đã dùng tiếp) và s6; mã 3 ($r, $($names.Count) mục)"
Check ((Test-Path -LiteralPath $tx1) -and (Read-Obj (Join-Path $jdirs[0].FullName 'nhat-ky.json')).hoanTacLuc) 'nội dung dùng chung không bị xoá; nhật ký ghi đã hoàn tác'
$r = Invoke-Mode 'hoan-tac' 6> $null
Check ($r -eq 0 -and (Codes) -contains 'KHONG_CO_GI_DE_HOAN_TAC') 'hoàn tác lần hai: không còn gì'

# ---- đổi sang A: B có s6 và bản mới hơn của s2
Save-Json (Join-Path $may1.App 'config.json') @{ lastKnownAccountUuid = $tkA }
$r = Invoke-Mode 'kiem-tra' 6> $null
$c = Get-CurrentAccount
$plan = Get-SyncPlan ''
Check ($r -eq 0 -and $c.Acct -eq $tkA -and $c.Org -eq $tcA -and $plan.Them.Count -eq 1 -and $plan.Them[0].S.Id -eq $s6.Id -and $plan.Thay.Count -eq 1 -and $plan.Thay[0].S.Id -eq $s2.Id -and $plan.Giu.Count -eq 0) "đăng nhập A: thiếu s6 của B, thay s2 bằng bản mới hơn ở B (thêm $($plan.Them.Count), thay $($plan.Thay.Count), giữ $($plan.Giu.Count))"
Check ($plan.ThieuNoiDung.Count -eq 0 -and $plan.DaXoa.Count -eq 0) 'không báo thiếu nội dung hay đã xoá khi đứng ở A'
Check ((Test-NenThay @{ lastActivityAt = 1 } @{ lastActivityAt = 2 }) -and -not (Test-NenThay @{ lastActivityAt = 2 } @{ lastActivityAt = 1 }) -and -not (Test-NenThay @{ lastActivityAt = 2 } @{ lastActivityAt = 2 }) -and -not (Test-NenThay @{ lastActivityAt = 2 } @{})) 'quy tắc chọn bản: bản mới hơn thắng; bằng nhau, thiếu giờ thì giữ bản đang có'

# ---- Đồng bộ ở A: thêm s6, thay s2 (cất bản cũ), rồi Hoàn tác trả lại bản cũ
$p2A = Join-Path $dA "$($s2.Id).json"
$old2 = [IO.File]::ReadAllBytes($p2A)
$r = Invoke-Mode 'dong-bo' 6> $null
$jA = @(Get-ChildItem -LiteralPath (Join-Path $du 'HoanTac') -Directory | Sort-Object Name -Descending)[0]
$jnA = Read-Obj (Join-Path $jA.FullName 'nhat-ky.json')
$thay = @($jnA.viec | Where-Object { $_.loai -eq 'thay' })
Check ($r -eq 0 -and (Get-Num (Read-Dict $p2A)['lastActivityAt']) -eq ($t0 + 9000) -and (Test-Path -LiteralPath (Join-Path $dA "$($s6.Id).json"))) "đồng bộ vào A: s2 lấy bản mới của B, thêm s6 ($r)"
Check ($thay.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $jA.FullName $thay[0].banCu))) 'bản cũ của s2 được cất trong nhật ký'
$r = Invoke-Mode 'hoan-tac' 6> $null
Check ($r -eq 0 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($p2A)) -eq [Convert]::ToBase64String($old2) -and -not (Test-Path -LiteralPath (Join-Path $dA "$($s6.Id).json"))) "Hoàn tác ở A: s2 trả lại đúng từng byte, bỏ s6 ($r)"

# ---- Sao lưu (đang ở A)
$ChayThu = $true
$r = Invoke-Mode 'sao-luu' 6> $null
$ChayThu = $false
Check ($r -eq 0 -and -not @(Get-ChildItem -LiteralPath $du -Directory -Filter 'Goi_*').Count) 'Sao lưu chạy thử: chưa tạo gói'
$realFree = ${function:Get-FreeBytes}
function Get-FreeBytes { param([string]$Path) return [long]10 }
$r = Invoke-Mode 'sao-luu' 6> $null
Check ($r -eq 2 -and (Codes) -contains 'THIEU_CHO_TRONG' -and -not @(Get-ChildItem -LiteralPath $du -Directory -Filter 'Goi_*').Count) "thiếu chỗ trống: mã 2, không tạo gói ($r)"
Set-Item function:Get-FreeBytes $realFree
$r = Invoke-Mode 'sao-luu' 6> $null
$pk = @(Get-ChildItem -LiteralPath $du -Directory -Filter 'Goi_11111111_*')
$g = if ($pk.Count) { Read-Obj (Join-Path $pk[0].FullName 'goi.json') } else { $null }
Check ($r -eq 0 -and $pk.Count -eq 1 -and $g.chuan -eq 'tramtool.claudedongbo.goi/1' -and $g.taiKhoan.acct -eq $tkA -and $g.taiKhoan.org -eq $tcA -and $g.thuMucNguoiDung -eq $may1.Nha) "Sao lưu: một gói Goi_11111111_*, goi.json đúng tài khoản ($r)"
$pPhien = @(Get-ChildItem -LiteralPath (Join-Path $pk[0].FullName 'phien') -File | ForEach-Object { $_.Name })
$pNd = @(Get-ChildItem -LiteralPath (Join-Path $pk[0].FullName 'noi-dung') -Recurse -File -Filter '*.jsonl' | Where-Object { $_.Directory.Name -ne 'subagents' })
Check ($pPhien.Count -eq 4 -and $pPhien -notcontains "$($s4.Id).json" -and $pNd.Count -eq 4 -and $g.soPhien -eq 4 -and (Codes) -contains 'PHIEN_THIEU_NOI_DUNG') "gói có 4 phiên kèm nội dung, bỏ s4 thiếu nội dung ($($pPhien.Count), $($pNd.Count))"
Check (Test-Path -LiteralPath (Join-Path $pk[0].FullName ('noi-dung\' + ($s1.Cwd -replace '[^A-Za-z0-9]', '-') + "\$($s1.Cli)\subagents\a.jsonl"))) 'gói có cả thư mục tác tử con của phiên'

# ---- máy 2: tài khoản C, thư mục người dùng khác; đồng bộ từ gói
$may2 = New-Machine 'may2' $tkC 'Khac'
$dC = Join-Path $may2.App "claude-code-sessions\$tkC\$tcC"
New-Item -ItemType Directory -Path $dC -Force | Out-Null
Use-Machine $may2
$Tu = Join-Path $may2.Root 'khong-phai-goi'; New-Item -ItemType Directory -Path $Tu -Force | Out-Null
$r = Invoke-Mode 'dong-bo' 6> $null
Check ($r -eq 2 -and (Codes) -contains 'KHONG_THAY_GOI') "-Tu không phải gói: mã 2 ($r)"
$Tu = $pk[0].FullName
$r = Invoke-Mode 'dong-bo' 6> $null
$Tu = ''
$names = @(Get-ChildItem -LiteralPath $dC -File -Filter 'local_*' | ForEach-Object { $_.Name })
Check ($r -eq 0 -and $names.Count -eq 4) "máy khác, tài khoản C: thêm 4 phiên từ gói ($r, $($names.Count)) $(@($script:Findings | Where-Object { $_.ma -eq 'DONG_BO_LOI' } | ForEach-Object { $_.chiTiet }))"
$c1 = Read-Dict (Join-Path $dC "$($s1.Id).json")
$newCwd = Join-Path $may2.Nha 'Du-an\Mot'
Check ($c1['cwd'] -eq $newCwd -and $c1['originCwd'] -eq $newCwd -and $c1['gitAnchors'][0]['gitRoot'] -eq $newCwd -and [string]$c1['writtenBranches'][0] -ceq ($newCwd + [char]0 + 'main')) "sửa đường dẫn theo thư mục người dùng mới: $($c1['cwd'])"
Check ((Read-Dict (Join-Path $dC "$($s2.Id).json"))['cwd'] -eq 'D:\Repo\Hai') 'đường dẫn ngoài thư mục người dùng giữ nguyên'
$nd1 = Join-Path $may2.Nha ('.claude\projects\' + ($newCwd -replace '[^A-Za-z0-9]', '-') + "\$($s1.Cli).jsonl")
$nd2 = Join-Path $may2.Nha ".claude\projects\D--Repo-Hai\$($s2.Cli).jsonl"
Check ((Test-Path -LiteralPath $nd1) -and (Test-Path -LiteralPath $nd2) -and ([IO.File]::ReadAllText($nd1) -ceq [IO.File]::ReadAllText($tx1))) 'chép nội dung vào thư mục dự án mang tên mới'
Check (Test-Path -LiteralPath (Join-Path (Split-Path $nd1 -Parent) "$($s1.Cli)\subagents\a.jsonl")) 'chép cả thư mục tác tử con'
Check ($c1['permissionMode'] -eq 'default') 'C chưa bật bypass: chế độ hỏi trước'
$r = Invoke-Mode 'hoan-tac' 6> $null
Check ($r -eq 0 -and -not @(Get-ChildItem -LiteralPath $dC -File).Count -and -not (Test-Path -LiteralPath $nd1) -and -not (Test-Path -LiteralPath (Join-Path (Split-Path $nd1 -Parent) $s1.Cli))) 'Hoàn tác ở máy khác: bỏ cả mục danh sách lẫn nội dung đã chép'

# ---- thiếu điều kiện
$may3 = New-Machine 'may3' $tkC
Use-Machine $may3
$r = Invoke-Mode 'kiem-tra' 6> $null
Check ($r -eq 2 -and (Codes) -contains 'CHUA_MO_TAB_CODE') "tài khoản chưa có thư mục, không rõ tổ chức: mã 2 ($r)"
Save-Json (Join-Path $may3.App 'remote-control-state.json') @{ version = 1; identities = @{ "${tcC}:$tkC" = @{} } }
$script:AppDir = Get-ClaudeAppDir; $script:SessRoot = Join-Path $script:AppDir 'claude-code-sessions'
$c = Get-CurrentAccount
Check ($c.Org -eq $tcC -and $c.Dir -like "*\$tkC\$tcC") 'chưa có thư mục: lấy tổ chức từ remote-control-state.json'
Save-Json (Join-Path $may3.App 'config.json') @{ locale = 'vi' }
$r = Invoke-Mode 'kiem-tra' 6> $null
Check ($r -eq 2 -and (Codes) -contains 'CHUA_DANG_NHAP') "chưa đăng nhập: mã 2 ($r)"
$env:CDB_CLAUDE_APPDATA = Join-Path $may3.Root 'khong-co'
$r = Invoke-Mode 'kiem-tra' 6> $null
Check ($r -eq 2 -and (Codes) -contains 'CHUA_CAI_CLAUDE') "chưa cài Claude Desktop: mã 2 ($r)"

# ---- chạy qua .bat (tiến trình riêng): Claude Desktop giả đang mở
$may4 = New-Machine 'may4' $tkB
$dB4 = Join-Path $may4.App "claude-code-sessions\$tkB\$tcB"
$dA4 = Join-Path $may4.App "claude-code-sessions\$tkA\$tcA"
New-Item -ItemType Directory -Path $dA4, $dB4 -Force | Out-Null
$q = New-Session $dA4 'Phiên qua bat' 'D:\Repo\Bat' $t0
[void](New-Transcript $may4 $q)
$fakeDir = Join-Path (New-TestDir 'claude-gia') 'AnthropicClaude'
New-Item -ItemType Directory -Path $fakeDir -Force | Out-Null
$fakeExe = New-FakeExe (Join-Path $fakeDir 'claude.exe') 'System.Threading.Thread.Sleep(120000); return 0;'
$bat = Join-Path $toolDir 'DONG_BO_CLAUDE.bat'
$kq4 = New-TestDir 'ket_qua4'
$envBat = @{ CDB_CLAUDE_APPDATA = $may4.App; CDB_NGUOI_DUNG = $may4.Nha; CDB_DU_LIEU = (New-TestDir 'du-lieu4'); CDB_KET_QUA = $kq4; CDB_MAU_CLAUDE = [regex]::Escape($fakeDir); TRAMTOOL_CLAUDEDONGBO_TEST = '' }
$env:CDB_MAU_CLAUDE = $envBat.CDB_MAU_CLAUDE
$proc = Start-Process -FilePath $fakeExe -PassThru -WindowStyle Hidden
try {
    $null = $proc.Handle
    $r = Invoke-Bat $bat @('-Mode', 'kiem-tra', '-KhongDung') -Env $envBat
    Check ($r.Code -eq 0 -and $r.Out -match 'Claude Desktop đang mở' -and @(Get-ChildItem -LiteralPath $kq4 -Filter 'KetQua_ClaudeDongBo_*.json').Count -eq 1) "qua .bat, Kiểm tra: mã 0, thấy Claude (giả) đang mở ($($r.Code))"
    $r = Invoke-Bat $bat @('-Mode', 'dong-bo', '-KhongDung') -Env $envBat
    Check ($r.Code -eq 2 -and -not $proc.HasExited -and -not @(Get-ChildItem -LiteralPath $dB4 -File).Count) "Claude đang mở, chạy tự động không có -DongClaude: mã 2, không đóng, không ghi ($($r.Code))"
    $r = Invoke-Bat $bat @('-Mode', 'dong-bo', '-DongClaude', '-KhongDung') -Env $envBat
    Start-Sleep -Milliseconds 300
    Check ($r.Code -eq 0 -and $proc.HasExited -and (Test-Path -LiteralPath (Join-Path $dB4 "$($q.Id).json"))) "-DongClaude: đóng Claude (giả) rồi đồng bộ, mã 0 ($($r.Code))"
    $r = Invoke-Bat $bat @() -Env $envBat
    Check ($r.Code -eq 1 -and $r.Out -match 'Cách dùng') "không có bàn phím, không chế độ: in cách dùng, mã 1 ($($r.Code))"
} finally {
    if (-not $proc.HasExited) { $proc.Kill() }
}

Remove-Item Env:CDB_CLAUDE_APPDATA, Env:CDB_NGUOI_DUNG, Env:CDB_DU_LIEU, Env:CDB_KET_QUA, Env:CDB_MAU_CLAUDE -ErrorAction SilentlyContinue
Complete-Test
