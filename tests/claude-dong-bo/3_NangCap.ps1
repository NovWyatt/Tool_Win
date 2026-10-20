# Bài thử các phần của DongBoClaude.ps1 1.1 bằng dữ liệu Claude giả (không đụng Claude thật): bản Claude và kiểm cấu
# trúc (dừng khi cách lưu đổi, bỏ mục lạ), bộ đệm đọc mục; tác vụ hẹn giờ, mẫu phiên, mục thanh bên (chỉ đổi một khoá
# của claude_desktop_config.json, khoá bí mật không lọt vào nhật ký), nhớ mục đã thêm để không thêm lại, Hoàn tác từng
# khoá; gói cập nhật dần, nén, mã hoá (định dạng đọc được bằng new-windows), mở gói .zip/.aes (sai mật khẩu, zip slip);
# trí nhớ dự án, file tác vụ hẹn giờ sang máy khác (sửa đường dẫn); lần đồng bộ gần nhất Claude đã nhận chưa; Cowork
# (-KemCowork); mo-claude, -MoClaude, lối tắt (Claude giả).
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\KetQua.ps1"
. "$PSScriptRoot\_GiaLap.ps1"
$toolDir = Join-Path $ToolsDir 'claude-dong-bo'
function Codes { return @($script:Findings | ForEach-Object { $_.ma }) }
function Find-F([string]$Ma) { return @($script:Findings | Where-Object { $_.ma -eq $Ma })[0] }
function Latest-Result { return @(Get-ChildItem -LiteralPath $kq -Filter 'KetQua_ClaudeDongBo_*.json' | Sort-Object LastWriteTime, Name -Descending)[0] }
function Get-Ids($List) { return (@($List | ForEach-Object { [string]$_['id'] }) -join ',') }
function Find-Text([string]$Dir, [string]$Text) { return @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Force | Where-Object { [IO.File]::ReadAllText($_.FullName).Contains($Text) }).Count }
function Get-Journals { return @(Get-ChildItem -LiteralPath (Join-Path $du 'HoanTac') -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending) }

# ---- máy 1: A có 2 phiên đúng và 1 mục lạ (thiếu cwd), tác vụ hẹn giờ, mẫu phiên, mục thanh bên; B đang đăng nhập
$m1 = New-Machine 'm1' $tkB
$cfgM1 = Join-Path $m1.App 'config.json'
Save-Json $cfgM1 @{ lastKnownAccountUuid = $tkB; updaterLastSeenVersion = '2.42304.2' }
$dA = Join-Path $m1.App "claude-code-sessions\$tkA\$tcA"
$dB = Join-Path $m1.App "claude-code-sessions\$tkB\$tcB"
New-Item -ItemType Directory -Path $dA, $dB -Force | Out-Null
$t0 = [long]1790000000000
$cwd1 = Join-Path $m1.Nha 'Du-an\Mot'
$s1 = New-Session $dA 'Một' $cwd1 ($t0 + 5000)
$s2 = New-Session $dA 'Hai' 'D:\Repo\Hai' ($t0 + 4000)
$ux = [guid]::NewGuid().ToString()
Save-Json (Join-Path $dA "local_$ux.json") @{ sessionId = "local_$ux"; cliSessionId = [guid]::NewGuid().ToString(); title = 'Lạ'; lastActivityAt = $t0 }
$s6 = New-Session $dB 'Sáu của B' 'D:\Repo\Sau' ($t0 + 6000)
$tx1 = New-Transcript $m1 $s1 -Side
foreach ($s in $s2, $s6) { [void](New-Transcript $m1 $s) }
$skill1 = Join-Path $m1.Nha '.claude\scheduled-tasks\viec-mot\SKILL.md'
Save-Text $skill1 "Làm việc ở $cwd1`n"
$task1 = [ordered]@{ id = 'task-1'; displayName = 'Việc một'; cronExpression = '0 8 * * *'; enabled = $true; filePath = $skill1; createdAt = $t0; cwd = $cwd1; place = @{ kind = 'local' }; permissionMode = 'default' }
$task2 = [ordered]@{ id = 'task-2'; displayName = 'Việc thiếu file'; cronExpression = '0 9 * * *'; enabled = $true; filePath = (Join-Path $m1.Nha '.claude\scheduled-tasks\khong-co\SKILL.md'); createdAt = $t0; place = @{ kind = 'local' }; permissionMode = 'default' }
Save-Json (Join-Path $dA 'scheduled-tasks.json') ([ordered]@{ scheduledTasks = @($task1, $task2); recordedSkips = @{}; sundayAliasBoundaryStamped = $true })
Save-Json (Join-Path $dB 'scheduled-tasks.json') ([ordered]@{ scheduledTasks = @([ordered]@{ id = 'task-0'; displayName = 'Việc của B'; enabled = $true; filePath = 'D:\Viec\B.md'; createdAt = $t0; place = @{ kind = 'local' }; permissionMode = 'default' }); recordedSkips = @{ 'task-0' = @() } })
$presetF = Join-Path $m1.App 'ccd-session-presets.json'
Save-Json $presetF @{ byAccount = @{ $tkA = [ordered]@{ presets = @(
                [ordered]@{ id = 'pre-1'; name = 'Mẫu một'; target = [ordered]@{ kind = 'local'; cwd = $cwd1 }; createdAt = $t0; lastUsedAt = $t0 },
                [ordered]@{ id = 'pre-2'; name = 'Mẫu hai'; target = [ordered]@{ kind = 'local'; cwd = 'D:\Repo\Hai' }; createdAt = $t0; lastUsedAt = $t0 }); builtIns = @{}; seededFromDraft = $true
        } }
}
function New-Sections([object[]]$Extra = @()) {
    return [ordered]@{ sections = @([ordered]@{ id = 'pinned'; kind = 'pinned'; v = 2; name = ''; order = 0 }, [ordered]@{ id = 'routines'; kind = 'routines'; v = 2; name = ''; order = 1 },
            [ordered]@{ id = 'sessions'; kind = 'sessions'; v = 2; name = ''; order = 2; groupBy = 'folder' }, [ordered]@{ id = 'sec-kh'; kind = 'custom'; v = 2; name = 'Khách hàng'; order = 3 }) + $Extra; migratedFrom = 1; prefsSeeded = $true
    }
}
$deskCfg = Join-Path $m1.App 'claude_desktop_config.json'
Save-Json $deskCfg @{ mcpServers = @{ gia = @{ command = 'x.exe'; env = @{ TOKEN = 'BiMatMcpGia_123' } } }; preferences = @{ bypassPermissionsOptInByAccount = @{ $tkA = $true }; epitaxyPrefs = @{ 'dframe-code-sections' = @{ "$tkA/$tcA" = (New-Sections) }; 'starred-local-code-sessions' = @() } } }
Save-Json (Join-Path $m1.Nha '.claude.json') @{ oauthAccount = @{ accountUuid = $tkB; organizationUuid = $tcB; emailAddress = 'b@vd.test' } }
$slug1 = $cwd1 -replace '[^A-Za-z0-9]', '-'
$mem1 = Join-Path $m1.Nha ".claude\projects\$slug1\memory\MEMORY.md"
Save-Text $mem1 ("- Dự án ở $cwd1`n- JSON: " + $cwd1.Replace('\', '\\') + "`n- Không đổi: $($m1.Nha)2\khac`n- DauHieuTrongGoi_42`n")

$du = New-TestDir 'du-lieu'
$kq = New-TestDir 'ket_qua'
$usb = New-TestDir 'usb'
$env:CDB_CLAUDE_APPDATA = $m1.App; $env:CDB_NGUOI_DUNG = $m1.Nha; $env:CDB_DU_LIEU = $du; $env:CDB_KET_QUA = $kq
$env:CDB_MAU_CLAUDE = 'KHONG-CO-TIEN-TRINH-NAY-' + [guid]::NewGuid()
Remove-Item Env:CDB_LENH_MO_CLAUDE, Env:CDB_DESKTOP -ErrorAction SilentlyContinue
$env:TRAMTOOL_CLAUDEDONGBO_TEST = '1'
. "$toolDir\DongBoClaude.ps1"
Remove-Item Env:TRAMTOOL_CLAUDEDONGBO_TEST
$ChayThu = $false; $KhongDung = $true; $DongClaude = $false; $MoClaude = $false; $Nen = $false; $MaHoa = $false; $KemCowork = $false; $Tu = ''; $Den = ''

# ---- giả lập: Claude Desktop đang mở, mở Claude, mật khẩu gõ vào
$script:GiaMo = @(); $script:DaDong = 0; $script:DaMo = 0
$script:MatKhau = New-Object System.Collections.Queue
function Get-ClaudeDesktopProcess { return $script:GiaMo }
function Stop-Process { [CmdletBinding()] param([Parameter(ValueFromPipeline = $true)]$InputObject, [switch]$Force) end { $script:DaDong++; $script:GiaMo = @() } }
function Read-YesNo { param([string]$Question, [bool]$Default = $false) return $Default }
function Start-ClaudeDesktop { $script:DaMo++; return $true }
function Read-MatKhau { param([string]$Prompt = '', [switch]$XacNhan) if ($script:MatKhau.Count) { return [string]$script:MatKhau.Dequeue() } return '' }

# ---- bản Claude, kiểm cấu trúc
$r = Invoke-Mode 'kiem-tra' 6> $null
$raw = Read-Obj (Latest-Result).FullName
Check ($r -eq 0 -and (Codes) -notcontains 'BAN_CLAUDE_MOI' -and $raw.banClaude -eq '2.42304.2') "bản Claude đã xem (2.42304.2): không báo, ghi bản vào kết quả ($($raw.banClaude))"
$f = Find-F 'MUC_KHONG_HOP_LE'
Check ($f -and $f.chiTiet -match 'thiếu cwd' -and (Codes) -notcontains 'CACH_LUU_DA_DOI') "mục lạ của A (thiếu cwd): báo, bỏ qua, chưa coi là đổi cách lưu ($($f.chiTiet))"
Check ((Find-F 'THIEU_PHIEN').tieuDe -match 'chưa có 2 phiên') 'B thiếu 2 phiên đúng cấu trúc của A'
$f = Find-F 'THIEU_CAI_DAT'
Check ($f -and $f.chayTiep.action -eq 'dong-bo' -and $f.chiTiet -match 'tác vụ hẹn giờ tab Code: Việc một' -and $f.chiTiet -match 'mẫu phiên: Mẫu một, Mẫu hai' -and $f.chiTiet -match 'thanh bên') "Kiểm tra thấy tác vụ hẹn giờ, mẫu phiên, thanh bên B chưa có: $($f.chiTiet)"
Check ((Find-F 'HEN_GIO_THIEU_TEP').chiTiet -match 'Việc thiếu file') 'tác vụ hẹn giờ thiếu file nhắc việc: báo, không thêm'
Save-Json $cfgM1 @{ lastKnownAccountUuid = $tkB; updaterLastSeenVersion = '2.50001.0' }
$r = Invoke-Mode 'kiem-tra' 6> $null
Check ($r -eq 0 -and (Find-F 'BAN_CLAUDE_MOI').mucDo -eq 'thong-tin') 'Claude bản khác (2.50001.0): chỉ báo để biết'
Save-Json $cfgM1 @{ lastKnownAccountUuid = $tkB; updaterLastSeenVersion = '2.42304.2' }
Check ((Test-VersionSeen '2.42304') -and (Test-VersionSeen '2.42304.9') -and -not (Test-VersionSeen '2.423041') -and -not (Test-VersionSeen '2.5')) 'so bản Claude theo phần đầu'

$odd = foreach ($i in 1, 2) { $u = [guid]::NewGuid().ToString(); $p = Join-Path $dB "local_$u.json"; Save-Json $p @{ sessionId = "local_$u"; spec = 2; updatedAt = 'hôm nay' }; $p }
$before = Get-Listing $dB
$r = Invoke-Mode 'dong-bo' 6> $null
Check ($r -eq 2 -and (Codes) -contains 'CACH_LUU_DA_DOI' -and (Get-Listing $dB) -eq $before -and -not (Test-Path -LiteralPath (Join-Path $du 'HoanTac'))) "quá nửa mục của B lạ (cách lưu mới?): mã 2, không ghi gì ($r)"
$r = Invoke-Mode 'sao-luu' 6> $null
Check ($r -eq 2 -and (Codes) -contains 'CACH_LUU_DA_DOI' -and -not @(Get-ChildItem -LiteralPath $du -Directory -Filter 'Goi_*').Count) 'Sao lưu cũng dừng khi cách lưu lạ'
Remove-Item -LiteralPath $odd -Force

# ---- bộ đệm đọc mục danh sách
$cf = Join-Path $TestRoot 'dem.json'
Copy-Item -LiteralPath $s1.File -Destination $cf
$c1 = Read-DictCached (Get-Item -LiteralPath $cf); $c2 = Read-DictCached (Get-Item -LiteralPath $cf)
$d = Read-Dict $cf; $d['title'] = 'Đã đổi tên dài hơn'
[IO.File]::WriteAllText($cf, $jser.Serialize($d))
$c3 = Read-DictCached (Get-Item -LiteralPath $cf)
Check ([object]::ReferenceEquals($c1, $c2) -and -not [object]::ReferenceEquals($c2, $c3) -and $c3['title'] -eq 'Đã đổi tên dài hơn') 'đọc lại mục chưa đổi thì dùng bản đã đọc, file đổi thì đọc lại'

# ---- Đồng bộ cùng máy: phiên, tác vụ hẹn giờ, mẫu phiên, thanh bên
$r = Invoke-Mode 'dong-bo' 6> $null
Check ($r -eq 0 -and (Find-F 'DA_DONG_BO').tieuDe -match 'Đã thêm 2, thay 0 phiên, 3 mục khác') "đồng bộ vào B: 2 phiên, 3 mục khác ($r): $((Find-F 'DA_DONG_BO').tieuDe)"
$tB = Read-Dict (Join-Path $dB 'scheduled-tasks.json')
Check ((Get-Ids $tB['scheduledTasks']) -eq 'task-0,task-1' -and $tB['recordedSkips'].ContainsKey('task-0')) "tác vụ hẹn giờ B: giữ task-0 và các trường khác, thêm task-1, không thêm task-2 ($(Get-Ids $tB['scheduledTasks']))"
$pr = Read-Dict $presetF
Check ((Get-Ids $pr['byAccount'][$tkB]['presets']) -eq 'pre-1,pre-2' -and $pr['byAccount'][$tkB]['seededFromDraft'] -eq $true -and @($pr['byAccount'][$tkA]['presets']).Count -eq 2) 'B có 2 mẫu phiên của A, mẫu của A giữ nguyên'
$cfg = Read-Dict $deskCfg
$secs = $cfg['preferences']['epitaxyPrefs']['dframe-code-sections']
Check ((Get-Ids $secs["$tkB/$tcB"]['sections']) -eq 'pinned,routines,sessions,sec-kh' -and (Get-Ids $secs["$tkA/$tcA"]['sections']) -eq 'pinned,routines,sessions,sec-kh') 'B chưa có thanh bên: lấy cách sắp xếp của A (cả mục Khách hàng)'
Check ($cfg['mcpServers']['gia']['env']['TOKEN'] -eq 'BiMatMcpGia_123' -and $cfg['preferences']['bypassPermissionsOptInByAccount'][$tkA] -eq $true -and $cfg['preferences']['epitaxyPrefs'].ContainsKey('starred-local-code-sessions')) 'claude_desktop_config.json giữ nguyên các khoá khác'
$jn = Read-Obj (Join-Path (Get-Journals)[0].FullName 'nhat-ky.json')
Check (@($jn.viec | Where-Object { $_.loai -eq 'doi-khoa' }).Count -eq 1 -and -not @($jn.viec | Where-Object { $_.tep -like '*claude_desktop_config.json' -and $_.loai -ne 'doi-khoa' }).Count -and (Find-Text $du 'BiMatMcpGia_123') -eq 0) 'claude_desktop_config.json: nhật ký chỉ giữ một khoá, khoá bí mật MCP không lọt vào du-lieu'
$mm = Read-Obj (Join-Path $du 'da-them.json')
$mk = $mm.("$env:COMPUTERNAME|$tkB")
Check (@($mk.henGio) -contains 'task-1' -and @($mk.mauPhien).Count -eq 2 -and @($mk.thanhBen) -contains 'sec-kh') 'nhớ các mục đã thêm vào B (da-them.json)'
$r = Invoke-Mode 'dong-bo' 6> $null
Check ($r -eq 0 -and (Codes) -contains 'KHONG_CAN_DONG_BO' -and (Get-Journals).Count -eq 1) 'chạy lại: không còn gì, không tạo nhật ký mới'
$pr = Read-Dict $presetF
# Lọc bằng foreach: Where-Object bọc phần tử thành PSObject, JavaScriptSerializer không ghi được.
$keep = New-Object System.Collections.ArrayList
foreach ($p in $pr['byAccount'][$tkB]['presets']) { if ($p['id'] -ne 'pre-1') { [void]$keep.Add($p) } }
$pr['byAccount'][$tkB]['presets'] = $keep.ToArray()
[IO.File]::WriteAllText($presetF, $jser.Serialize($pr))
$r = Invoke-Mode 'dong-bo' 6> $null
Check ($r -eq 0 -and (Codes) -contains 'KHONG_CAN_DONG_BO' -and (Get-Ids (Read-Dict $presetF)['byAccount'][$tkB]['presets']) -eq 'pre-2') 'mẫu phiên B đã xoá không bị thêm lại'
$cfg = Read-Dict $deskCfg
$cfg['preferences']['epitaxyPrefs']['dframe-code-sections']["$tkA/$tcA"] = New-Sections @([ordered]@{ id = 'sec-moi'; kind = 'custom'; v = 2; name = 'Mới'; order = 9 })
[IO.File]::WriteAllText($deskCfg, $jser.Serialize($cfg))
$r = Invoke-Mode 'dong-bo' 6> $null
$sb = (Read-Dict $deskCfg)['preferences']['epitaxyPrefs']['dframe-code-sections']["$tkB/$tcB"]['sections']
Check ($r -eq 0 -and (Get-Ids $sb) -eq 'pinned,routines,sessions,sec-kh,sec-moi' -and $sb[4]['order'] -eq 4) "A thêm mục thanh bên mới: B thêm mục đó vào cuối ($(Get-Ids $sb))"

# ---- Hoàn tác: từng khoá, từng file; mục đã đổi sau khi đồng bộ thì giữ
$r = Invoke-Mode 'hoan-tac' 6> $null
Check ($r -eq 0 -and (Get-Ids (Read-Dict $deskCfg)['preferences']['epitaxyPrefs']['dframe-code-sections']["$tkB/$tcB"]['sections']) -eq 'pinned,routines,sessions,sec-kh') 'Hoàn tác lần 2: bỏ mục thanh bên vừa thêm'
$r = Invoke-Mode 'hoan-tac' 6> $null
$cfg = Read-Dict $deskCfg
$tB = Read-Dict (Join-Path $dB 'scheduled-tasks.json')
Check ($r -eq 3 -and -not $cfg['preferences']['epitaxyPrefs']['dframe-code-sections'].ContainsKey("$tkB/$tcB") -and (Get-Ids $tB['scheduledTasks']) -eq 'task-0' -and $cfg['mcpServers']['gia']['env']['TOKEN'] -eq 'BiMatMcpGia_123') "Hoàn tác lần 1: bỏ khoá thanh bên của B, trả file tác vụ hẹn giờ; khoá khác còn nguyên ($r)"
Check ((Find-F 'GIU_VI_DA_DOI').chiTiet -match 'mẫu phiên' -and (Get-Ids (Read-Dict $presetF)['byAccount'][$tkB]['presets']) -eq 'pre-2') 'file mẫu phiên đã đổi sau khi đồng bộ: giữ'
$mk = (Read-Obj (Join-Path $du 'da-them.json')).("$env:COMPUTERNAME|$tkB")
Check (@($mk.henGio).Count -eq 0 -and @($mk.thanhBen).Count -eq 0 -and @($mk.mauPhien).Count -eq 2) 'Hoàn tác quên các mục đã bỏ, vẫn nhớ mẫu phiên (còn giữ)'

# ---- Sao lưu (đăng nhập A): gói cập nhật dần, trí nhớ dự án, tác vụ hẹn giờ, mẫu phiên, thanh bên
Save-Json $cfgM1 @{ lastKnownAccountUuid = $tkA; updaterLastSeenVersion = '2.42304.2' }
$r = Invoke-Mode 'sao-luu' 6> $null
$pkg = Join-Path $du 'Goi_11111111'
$g = Read-Obj (Join-Path $pkg 'goi.json')
Check ($r -eq 0 -and $g.soPhien -eq 2 -and $g.dangGhi -eq $false -and $g.banClaude -eq '2.42304.2' -and (Codes) -contains 'MUC_KHONG_HOP_LE') "Sao lưu A: 2 phiên, bỏ mục lạ ($r)"
$want = "phien\$($s1.Id).json", "noi-dung\$slug1\$($s1.Cli).jsonl", "noi-dung\$slug1\$($s1.Cli)\subagents\a.jsonl", "nguoi-dung\.claude\projects\$slug1\memory\MEMORY.md", 'phien\scheduled-tasks.json', 'nguoi-dung\.claude\scheduled-tasks\viec-mot\SKILL.md', 'phien\mau-phien.json', 'phien\thanh-ben.json'
$miss = @($want | Where-Object { -not (Test-Path -LiteralPath (Join-Path $pkg $_)) })
Check (-not $miss.Count) "gói có phiên, nội dung, trí nhớ dự án, tác vụ hẹn giờ kèm file nhắc việc, mẫu phiên, thanh bên (thiếu: $($miss -join '; '))"
Check ((Find-Text $pkg 'BiMatMcpGia_123') -eq 0 -and -not @(Get-ChildItem -LiteralPath $pkg -Recurse -Filter 'claude_desktop_config.json').Count) 'gói không có claude_desktop_config.json, khoá bí mật MCP'
$txp = Join-Path $pkg "noi-dung\$slug1\$($s1.Cli).jsonl"
$w0 = (Get-Item -LiteralPath $txp).LastWriteTimeUtc
$r = Invoke-Mode 'sao-luu' 6> $null
Check ($r -eq 0 -and (Find-F 'DA_SAO_LUU').tieuDe -match 'cập nhật 0 file' -and (Get-Item -LiteralPath $txp).LastWriteTimeUtc -eq $w0) "Sao lưu lần 2 không đổi gì: không chép lại ($((Find-F 'DA_SAO_LUU').tieuDe))"
$s3 = New-Session $dA 'Ba mới' 'D:\Repo\Ba' ($t0 + 7000)
[void](New-Transcript $m1 $s3)
[IO.File]::AppendAllText((Join-Path $m1.Nha "\.claude\projects\D--Repo-Hai\$($s2.Cli).jsonl"), "{`"type`":`"user`"}`n")
$r = Invoke-Mode 'sao-luu' 6> $null
Check ($r -eq 0 -and (Find-F 'DA_SAO_LUU').tieuDe -match 'cập nhật 3 file' -and (Read-Obj (Join-Path $pkg 'goi.json')).soPhien -eq 3) "thêm 1 phiên, 1 nội dung dài thêm: chỉ chép 3 file ($((Find-F 'DA_SAO_LUU').tieuDe))"
Remove-Item -LiteralPath $s3.File
$r = Invoke-Mode 'sao-luu' 6> $null
Check ($r -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $pkg "phien\$($s3.Id).json")) -and -not (Test-Path -LiteralPath (Join-Path $pkg "noi-dung\D--Repo-Ba\$($s3.Cli).jsonl")) -and (Read-Obj (Join-Path $pkg 'goi.json')).soPhien -eq 2) 'phiên đã xoá ở A: bỏ khỏi gói cả mục lẫn nội dung'
$gd = Read-Dict (Join-Path $pkg 'goi.json'); $gd['dangGhi'] = $true
[IO.File]::WriteAllText((Join-Path $pkg 'goi.json'), $jser.Serialize($gd))
$script:DangGhi.Clear()
Check (-not @(Get-PackageStores '').Count -and $script:DangGhi -contains $pkg) 'gói đang ghi dở (Sao lưu bị ngắt): Đồng bộ bỏ qua'
$r = Invoke-Mode 'sao-luu' 6> $null
Check ($r -eq 0 -and (Read-Obj (Join-Path $pkg 'goi.json')).dangGhi -eq $false) 'Sao lưu lại: gói dùng được'

# ---- nén, mã hoá
$Nen = $true; $Den = $usb
$r = Invoke-Mode 'sao-luu' 6> $null
$Nen = $false; $Den = ''
$zip = @(Get-ChildItem -LiteralPath $usb -Filter 'Goi_11111111_*.zip')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$names = if ($zip.Count) { $za = [IO.Compression.ZipFile]::OpenRead($zip[0].FullName); try { @($za.Entries | ForEach-Object { $_.FullName }) } finally { $za.Dispose() } } else { @() }
Check ($r -eq 0 -and $zip.Count -eq 1 -and $names -contains 'Goi_11111111/goi.json' -and $names -contains "Goi_11111111/phien/$($s1.Id).json") "-Nen: một file .zip trên USB, trong có thư mục gói ($($zip.Count), $($names.Count) mục)"
$MaHoa = $true; $Den = $usb
$script:MatKhau.Enqueue('ngan')
$r = Invoke-Mode 'sao-luu' 6> $null
Check ($r -eq 2 -and (Codes) -contains 'MAT_KHAU_NGAN' -and -not @(Get-ChildItem -LiteralPath $usb -Filter '*.aes').Count) 'mật khẩu dưới 8 ký tự: mã 2, chưa tạo gói'
$r = Invoke-Mode 'sao-luu' 6> $null
Check ($r -eq 2 -and (Codes) -contains 'CHUA_CO_MAT_KHAU') 'không gõ mật khẩu (chạy tự động): mã 2'
$script:MatKhau.Enqueue('MatKhauThu123')
$r = Invoke-Mode 'sao-luu' 6> $null
$MaHoa = $false; $Den = ''
$aes = @(Get-ChildItem -LiteralPath $usb -Filter 'Goi_11111111_*.aes')
$ab = if ($aes.Count) { [IO.File]::ReadAllBytes($aes[0].FullName) } else { [byte[]]@() }
$latin = [Text.Encoding]::GetEncoding(28591).GetString($ab)
Check ($r -eq 0 -and $aes.Count -eq 1 -and $latin.StartsWith('TTDL1') -and -not $latin.Contains('DauHieuTrongGoi_42') -and -not @(Get-ChildItem -LiteralPath $du -Filter 'goi-tam-*').Count -and -not @(Get-ChildItem -LiteralPath $usb -Filter '*.cdb-tmp').Count) "-MaHoa: một file .aes (TTDL1), không lộ nội dung, không để lại file tạm ($r)"

$rnd = Join-Path $TestRoot 'ngau-nhien.bin'
$rb = New-Object byte[] 2621447; (New-Object Random 7).NextBytes($rb); [IO.File]::WriteAllBytes($rnd, $rb)
Protect-File $rnd "$rnd.aes" 'MatKhauDai_789' 20000
Unprotect-File "$rnd.aes" "$rnd.ra" 'MatKhauDai_789'
Check ((Get-FileHash -LiteralPath $rnd).Hash -eq (Get-FileHash -LiteralPath "$rnd.ra").Hash) 'mã hoá rồi giải mã file 2,5 MB (nhiều khúc): đúng từng byte'
$e1 = ''; try { Unprotect-File "$rnd.aes" "$rnd.sai" 'MatKhauSai_000' } catch { $e1 = $_.Exception.Message }
$tb = [IO.File]::ReadAllBytes("$rnd.aes"); $tb[100000] = $tb[100000] -bxor 1; [IO.File]::WriteAllBytes("$rnd.sua", $tb)
$e2 = ''; try { Unprotect-File "$rnd.sua" "$rnd.ra2" 'MatKhauDai_789' } catch { $e2 = $_.Exception.Message }
Check ($e1 -match 'Sai mật khẩu' -and $e2 -match 'Sai mật khẩu hoặc gói đã bị sửa' -and -not (Test-Path -LiteralPath "$rnd.sai") -and -not (Test-Path -LiteralPath "$rnd.ra2")) 'sai mật khẩu, tệp bị sửa một byte: báo lỗi, không ghi ra gì'
$small = Join-Path $TestRoot 'nho.txt'; Save-Text $small 'Noi dung thu dinh dang chung 456'
Protect-File $small "$small.aes" 'MatKhauChung_456'
$chung = Join-Path $ToolsDir 'new-windows\lib\Chung.ps1'
$ps = Join-Path $PSHOME 'powershell.exe'
$out = & $ps -NoProfile -ExecutionPolicy Bypass -Command ". '$chung'; [Text.Encoding]::ASCII.GetString((Unprotect-Bytes ([IO.File]::ReadAllBytes('$small.aes')) 'MatKhauChung_456'))" 2>&1 | Out-String
Check ($out.Trim() -eq 'Noi dung thu dinh dang chung 456') "new-windows (Unprotect-Bytes) đọc được gói mã hoá của công cụ: '$($out.Trim())'"
Check ((Split-Path (Get-FreeName $aes[0].FullName) -Leaf) -like 'Goi_11111111_*_2.aes') 'trùng tên file gói: thêm _2 trước đuôi'
# Gói của A mang đi (USB): các máy giả sau chỉ đọc gói qua -Tu.
Move-Item -LiteralPath $pkg -Destination (Join-Path $usb 'Goi_11111111')

# ---- máy 2 (tài khoản Windows khác), tài khoản C: đồng bộ từ gói .aes, .zip
$m2 = New-Machine 'm2' $tkC 'Khac'
$dC = Join-Path $m2.App "claude-code-sessions\$tkC\$tcC"
New-Item -ItemType Directory -Path $dC -Force | Out-Null
Save-Json (Join-Path $m2.App 'claude_desktop_config.json') @{ preferences = @{ sidebarMode = 'code' } }
Use-Machine $m2
$Tu = $aes[0].FullName
$script:MatKhau.Enqueue('SaiMatKhau99')
$r = Invoke-Mode 'dong-bo' 6> $null
Check ($r -eq 2 -and (Codes) -contains 'MO_GOI_LOI' -and -not @(Get-ChildItem -LiteralPath $dC -File).Count -and -not @(Get-ChildItem -LiteralPath $du -Directory -Filter 'GiaiNen_*').Count) "gói .aes, sai mật khẩu: mã 2, không ghi gì, xoá thư mục tạm ($r)"
$script:MatKhau.Enqueue('MatKhauThu123')
$r = Invoke-Mode 'dong-bo' 6> $null
$cwd1b = Join-Path $m2.Nha 'Du-an\Mot'
$slug1b = $cwd1b -replace '[^A-Za-z0-9]', '-'
Check ($r -eq 0 -and @(Get-ChildItem -LiteralPath $dC -Filter 'local_*.json').Count -eq 2 -and -not @(Get-ChildItem -LiteralPath $du -Directory -Filter 'GiaiNen_*').Count) "gói .aes, đúng mật khẩu: thêm 2 phiên, xoá thư mục tạm ($r)"
$mem2 = Join-Path $m2.Nha ".claude\projects\$slug1b\memory\MEMORY.md"
$mt = if (Test-Path -LiteralPath $mem2) { [IO.File]::ReadAllText($mem2) } else { '' }
Check ($mt.Contains("Dự án ở $cwd1b") -and $mt.Contains($cwd1b.Replace('\', '\\')) -and -not $mt.Contains("$cwd1") -and $mt.Contains("$($m1.Nha)2\khac")) 'trí nhớ dự án sang máy mới: sửa đường dẫn (cả dạng JSON), không đụng đường dẫn chỉ giống phần đầu'
$skill2 = Join-Path $m2.Nha '.claude\scheduled-tasks\viec-mot\SKILL.md'
$t2 = Read-Dict (Join-Path $dC 'scheduled-tasks.json')
$k1 = @($t2['scheduledTasks'])[0]
Check ((Test-Path -LiteralPath $skill2) -and [IO.File]::ReadAllText($skill2).Contains($cwd1b) -and (Get-Ids $t2['scheduledTasks']) -eq 'task-1' -and $k1['filePath'] -eq $skill2 -and $k1['cwd'] -eq $cwd1b) "tác vụ hẹn giờ sang máy mới: chép file nhắc việc, sửa filePath, cwd ($($k1['filePath']))"
$p2 = (Read-Dict (Join-Path $m2.App 'ccd-session-presets.json'))['byAccount'][$tkC]['presets']
Check ((Get-Ids $p2) -eq 'pre-1,pre-2' -and $p2[0]['target']['cwd'] -eq $cwd1b -and $p2[1]['target']['cwd'] -eq 'D:\Repo\Hai') 'mẫu phiên sang máy mới: sửa thư mục trong thư mục người dùng'
$c2 = Read-Dict (Join-Path $m2.App 'claude_desktop_config.json')
Check ((Get-Ids $c2['preferences']['epitaxyPrefs']['dframe-code-sections']["$tkC/$tcC"]['sections']) -eq 'pinned,routines,sessions,sec-kh,sec-moi' -and $c2['preferences']['sidebarMode'] -eq 'code') 'thanh bên của A (có cả mục Mới) sang máy mới, giữ cài đặt khác'
$Tu = $zip[0].FullName
$r = Invoke-Mode 'dong-bo' 6> $null
Check ($r -eq 0 -and (Codes) -contains 'KHONG_CAN_DONG_BO') 'đồng bộ lại từ gói .zip: đã đủ'
$Tu = ''
$r = Invoke-Mode 'hoan-tac' 6> $null
Check ($r -eq 0 -and -not @(Get-ChildItem -LiteralPath $dC -File).Count -and -not (Test-Path -LiteralPath $mem2) -and -not (Test-Path -LiteralPath $skill2) -and -not (Test-Path -LiteralPath (Join-Path $m2.App 'ccd-session-presets.json'))) "Hoàn tác ở máy mới: bỏ phiên, trí nhớ, file nhắc việc, mẫu phiên đã thêm ($r)"
$evil = Join-Path $TestRoot 'xau.zip'
Add-Type -AssemblyName System.IO.Compression
$fs = [IO.File]::Create($evil)
$za = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
$w = New-Object IO.StreamWriter($za.CreateEntry('../../../thoat-ra.txt').Open()); $w.Write('x'); $w.Dispose()
$za.Dispose(); $fs.Dispose()
$Tu = $evil
$r = Invoke-Mode 'dong-bo' 6> $null
$Tu = ''
Check ($r -eq 2 -and (Find-F 'MO_GOI_LOI').chiTiet -match 'ra ngoài' -and -not @(Get-ChildItem -LiteralPath $TestRoot -Recurse -Filter 'thoat-ra.txt').Count) "tệp nén có đường dẫn ..\ (zip slip): dừng, không ghi ra ngoài ($r)"

# ---- máy 3: Cowork (-KemCowork), lần đồng bộ gần nhất Claude đã nhận chưa
$m3 = New-Machine 'm3' $tkB
$dA3 = Join-Path $m3.App "claude-code-sessions\$tkA\$tcA"; $dB3 = Join-Path $m3.App "claude-code-sessions\$tkB\$tcB"
New-Item -ItemType Directory -Path $dA3, $dB3 -Force | Out-Null
$r1 = New-Session $dA3 'Ba một' 'D:\Repo\B1' ($t0 + 3); $r2 = New-Session $dA3 'Ba hai' 'D:\Repo\B2' ($t0 + 2); $r3 = New-Session $dA3 'Ba ba' 'D:\Repo\B3' ($t0 + 1)
foreach ($s in $r1, $r2, $r3) { [void](New-Transcript $m3 $s) }
$cwA = Join-Path $m3.App "local-agent-mode-sessions\$tkA\$tcA"
Save-Json (Join-Path $cwA 'local_cw1.json') @{ sessionId = 'local_cw1'; title = 'Cowork một' }
Save-Text (Join-Path $cwA 'local_cw1\outputs\bao-cao.txt') 'nội dung Cowork'
Save-Json (Join-Path $cwA 'remote-session-spaces.json') @{ entries = @() }
Save-Json (Join-Path $cwA 'scheduled-tasks.json') ([ordered]@{ scheduledTasks = @([ordered]@{ id = 'cw-task'; displayName = 'Cowork hẹn giờ'; enabled = $true; createdAt = $t0; place = @{ kind = 'local' }; permissionMode = 'default' }); recordedSkips = @{} })
Use-Machine $m3
$r = Invoke-Mode 'kiem-tra' 6> $null
Check ($r -eq 0 -and (Codes) -notcontains 'THIEU_CAI_DAT') 'không có -KemCowork: không đụng Cowork'
$KemCowork = $true
$r = Invoke-Mode 'dong-bo' 6> $null
$KemCowork = $false
$cwB = Join-Path $m3.App "local-agent-mode-sessions\$tkB\$tcB"
Check ($r -eq 0 -and (Test-Path -LiteralPath (Join-Path $cwB 'local_cw1.json')) -and (Test-Path -LiteralPath (Join-Path $cwB 'local_cw1\outputs\bao-cao.txt')) -and -not (Test-Path -LiteralPath (Join-Path $cwB 'remote-session-spaces.json')) -and (Get-Ids (Read-Dict (Join-Path $cwB 'scheduled-tasks.json'))['scheduledTasks']) -eq 'cw-task') "-KemCowork: chép phiên Cowork kèm thư mục, tác vụ hẹn giờ Cowork; không chép phiên từ xa ($r)"
$p1 = Join-Path $dB3 "$($r1.Id).json"
$d1 = Read-Dict $p1; $d1['lastFocusedAt'] = $t0 + 99
[IO.File]::WriteAllText($p1, $jser.Serialize($d1))
Remove-Item -LiteralPath (Join-Path $dB3 "$($r2.Id).json"), (Join-Path $dB3 "$($r3.Id).json")
[IO.File]::WriteAllText((Join-Path $dB3 "deleted_$($r3.Uuid)"), "$t0")
$r = Invoke-Mode 'kiem-tra' 6> $null
$f = Find-F 'LAN_DONG_BO_GAN_NHAT'
Check ($f -and $f.tieuDe -match '3 phiên; Claude đã mở hoặc ghi lại 1, chưa đụng tới 0, đã xoá 1') "Kiểm tra sau khi mở Claude: $($f.tieuDe)"
Check ((Find-F 'PHIEN_DONG_BO_MAT').chiTiet -eq 'Ba hai') 'phiên mất mà không có dấu đã xoá: cảnh báo'
$r = Invoke-Mode 'hoan-tac' 6> $null
Check ($r -eq 3 -and -not (Test-Path -LiteralPath (Join-Path $cwB 'local_cw1')) -and -not (Test-Path -LiteralPath (Join-Path $cwB 'local_cw1.json')) -and (Test-Path -LiteralPath $p1)) "Hoàn tác: bỏ Cowork đã chép, giữ phiên Claude đã mở ($r)"

# ---- máy 4: mo-claude, -MoClaude, lối tắt
$m4 = New-Machine 'm4' $tkB
$dA4 = Join-Path $m4.App "claude-code-sessions\$tkA\$tcA"; $dB4 = Join-Path $m4.App "claude-code-sessions\$tkB\$tcB"
New-Item -ItemType Directory -Path $dA4, $dB4 -Force | Out-Null
$q1 = New-Session $dA4 'Qua lối tắt' 'D:\Repo\LoiTat' $t0
[void](New-Transcript $m4 $q1)
Use-Machine $m4
$ChayThu = $true
$r = Invoke-Mode 'mo-claude' 6> $null
$ChayThu = $false
Check ($r -eq 0 -and $script:DaMo -eq 0 -and -not @(Get-ChildItem -LiteralPath $dB4 -File).Count) 'mo-claude chạy thử: không ghi, không mở Claude'
$r = Invoke-Mode 'mo-claude' 6> $null
Check ($r -eq 0 -and $script:DaMo -eq 1 -and (Test-Path -LiteralPath (Join-Path $dB4 "$($q1.Id).json"))) "mo-claude, Claude đang tắt: đồng bộ rồi mở Claude ($r)"
$nj = (Get-Journals).Count
$script:GiaMo = @([pscustomobject]@{ Id = 0; Name = 'claude' })
$q2 = New-Session $dA4 'Thêm khi Claude mở' 'D:\Repo\LoiTat2' ($t0 + 1)
[void](New-Transcript $m4 $q2)
$r = Invoke-Mode 'mo-claude' 6> $null
Check ($r -eq 0 -and $script:DaMo -eq 2 -and $script:DaDong -eq 0 -and (Find-F 'CLAUDE_DANG_MO').mucDo -eq 'thong-tin' -and (Get-Journals).Count -eq $nj) 'mo-claude, Claude đang mở: không đóng, không đồng bộ, chỉ đưa Claude lên'
$script:GiaMo = @()
$MoClaude = $true
$r = Invoke-Mode 'dong-bo' 6> $null
$MoClaude = $false
Check ($r -eq 0 -and $script:DaMo -eq 3 -and (Test-Path -LiteralPath (Join-Path $dB4 "$($q2.Id).json"))) 'dong-bo -MoClaude: đồng bộ xong thì mở Claude'
Save-Json (Join-Path $m4.App 'config.json') @{ locale = 'vi' }
$r = Invoke-Mode 'mo-claude' 6> $null
Check ($r -eq 2 -and $script:DaMo -eq 4) 'mo-claude khi chưa đăng nhập: vẫn mở Claude (mã 2 để cửa sổ ở lại báo)'
Save-Json (Join-Path $m4.App 'config.json') @{ lastKnownAccountUuid = $tkB }
$desk = New-TestDir 'man-hinh'
$env:CDB_DESKTOP = $desk
$lnk = Join-Path $desk 'Mở Claude (đồng bộ phiên).lnk'
$ChayThu = $true
$r = Invoke-Mode 'loi-tat' 6> $null
$ChayThu = $false
Check ($r -eq 0 -and -not (Test-Path -LiteralPath $lnk)) 'tạo lối tắt chạy thử: chưa tạo'
$r = Invoke-Mode 'loi-tat' 6> $null
$sc = if (Test-Path -LiteralPath $lnk) { [CdbLoiTat.Lnk]::Read($lnk) } else { @('', '', '', '') }
Check ($r -eq 0 -and $sc[0] -like '*\powershell.exe' -and $sc[1] -match '-Mode mo-claude' -and $sc[1].Contains((Join-Path $toolDir 'DongBoClaude.ps1')) -and $sc[2] -match '(claude\.ico|powershell\.exe),0$') "lối tắt Mở Claude (tên có dấu): chạy công cụ ở chế độ mo-claude ($($sc[1]))"
Check ($sc[3] -eq 'Đồng bộ phiên tab Code sang tài khoản đang đăng nhập rồi mở Claude Desktop') "mô tả lối tắt giữ nguyên dấu tiếng Việt ($($sc[3]))"
Remove-Item Env:CDB_DESKTOP

# ---- qua .bat: lối tắt mở Claude giả
$q3 = New-Session $dA4 'Qua bat' 'D:\Repo\LoiTat3' ($t0 + 2)
[void](New-Transcript $m4 $q3)
$mark = Join-Path $TestRoot 'da-mo-claude.txt'
$fakeClaude = New-FakeExe (Join-Path (New-TestDir 'claude-mo') 'ClaudeGia.exe') 'File.WriteAllText(Environment.GetEnvironmentVariable("CDB_DAU_MO"), "da mo"); return 0;'
$envBat = @{ CDB_CLAUDE_APPDATA = $m4.App; CDB_NGUOI_DUNG = $m4.Nha; CDB_DU_LIEU = (New-TestDir 'du-lieu-bat'); CDB_KET_QUA = (New-TestDir 'ket-qua-bat'); CDB_MAU_CLAUDE = $env:CDB_MAU_CLAUDE; CDB_LENH_MO_CLAUDE = $fakeClaude; CDB_DAU_MO = $mark; TRAMTOOL_CLAUDEDONGBO_TEST = '' }
$r = Invoke-Bat (Join-Path $toolDir 'DONG_BO_CLAUDE.bat') @('-Mode', 'mo-claude') -Env $envBat
for ($i = 0; $i -lt 20 -and -not (Test-Path -LiteralPath $mark); $i++) { Start-Sleep -Milliseconds 250 }
Check ($r.Code -eq 0 -and (Test-Path -LiteralPath $mark) -and (Test-Path -LiteralPath (Join-Path $dB4 "$($q3.Id).json"))) "qua .bat, mo-claude: đồng bộ rồi mở Claude (giả), mã 0 ($($r.Code))"

Remove-Item Env:CDB_CLAUDE_APPDATA, Env:CDB_NGUOI_DUNG, Env:CDB_DU_LIEU, Env:CDB_KET_QUA, Env:CDB_MAU_CLAUDE -ErrorAction SilentlyContinue
Complete-Test
