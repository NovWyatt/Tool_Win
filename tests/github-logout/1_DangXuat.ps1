# Bài thử DangXuatGitHub.ps1 bằng giả lập: Credential Manager là danh sách trong bộ nhớ (cmdkey giả), GitHub CLI và
# câu trả lời cũng giả. Không đọc, không xoá mục nào của máy thật.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$env:TRAMTOOL_GITHUBLOGOUT_TEST = '1'
$Tool = Join-Path $ToolsDir 'github-logout'
. (Join-Path $Tool 'DangXuatGitHub.ps1')
$ChayThu = $false; $KhongDung = $true

# ---- giả lập
$script:Vault = New-Object System.Collections.ArrayList
$script:Calls = New-Object System.Collections.ArrayList
$script:Asked = New-Object System.Collections.ArrayList
$script:Answers = New-Object System.Collections.Queue
$script:ListFails = $false; $script:DeleteFails = @(); $script:Sticky = @()
$script:Labels = @{ Target = 'Target'; Type = 'Type'; User = 'User'; Head = 'Currently stored credentials:' }
$script:GhPath = $null; $script:GhCalls = 0; $script:IsAdmin = $false

function Set-Vault([object[]]$Items) {
    $script:Vault.Clear()
    foreach ($i in $Items) { [void]$script:Vault.Add($i) }
}
function C([string]$T, [string]$User = 'NovWyatt', [string]$Kind = 'LegacyGeneric') { [pscustomobject]@{ T = $T; User = $User; Kind = $Kind } }

function Invoke-Cmdkey {
    param([string[]]$Arguments)
    [void]$script:Calls.Add(($Arguments -join ' '))
    $a = $Arguments[0]
    if ($a -eq '/list') {
        if ($script:ListFails) { return [pscustomobject]@{ Code = 1; Output = @('CMDKEY: Lỗi giả lập.') } }
        $o = New-Object System.Collections.Generic.List[string]
        $o.Add(''); $o.Add($script:Labels.Head); $o.Add('')
        foreach ($v in $script:Vault) {
            $o.Add("    $($script:Labels.Target): $($v.Kind):target=$($v.T)")
            $o.Add("    $($script:Labels.Type): Generic ")
            $o.Add("    $($script:Labels.User): $($v.User)")
            $o.Add('    Local machine persistence')
            $o.Add('')
        }
        return [pscustomobject]@{ Code = 0; Output = $o.ToArray() }
    }
    if ($a -like '/delete:*') {
        $t = $a.Substring(8)
        $hit = @($script:Vault | Where-Object { $_.T -eq $t })
        if (-not $hit.Count -or $script:DeleteFails -contains $t) { return [pscustomobject]@{ Code = 1; Output = @('CMDKEY: Element not found.') } }
        if ($script:Sticky -notcontains $t) { foreach ($h in $hit) { $script:Vault.Remove($h) } }
        return [pscustomobject]@{ Code = 0; Output = @('CMDKEY: Credential deleted successfully.') }
    }
    throw "cmdkey giả không biết lệnh: $a"
}
function Read-YesNo {
    param([string]$Question, [bool]$Default = $false)
    [void]$script:Asked.Add($Question)
    if ($script:Answers.Count) { return [bool]$script:Answers.Dequeue() }
    return $Default
}
function Get-GhPath { return $script:GhPath }
function Invoke-GhLogout { param([string]$Gh) $script:GhCalls++; return 0 }
function Test-IsAdmin { return $script:IsAdmin }

function Reset-Case([object[]]$Items, [object[]]$Answers = @()) {
    Set-Vault $Items
    $script:Calls.Clear(); $script:Asked.Clear(); $script:Answers.Clear()
    foreach ($x in $Answers) { $script:Answers.Enqueue($x) }
    $script:ListFails = $false; $script:DeleteFails = @(); $script:Sticky = @()
    $script:GhPath = $null; $script:GhCalls = 0; $script:IsAdmin = $false
    $script:ChayThu = $false
}
function Invoke-Flow {
    # Trả về mã thoát và chữ in ra (Write-Host là luồng 6)
    $all = @(Invoke-DangXuat 6>&1)
    $code = @($all | Where-Object { $_ -isnot [Management.Automation.InformationRecord] })
    $text = (@($all | Where-Object { $_ -is [Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData }) -join "`n")
    [pscustomobject]@{ Code = $(if ($code.Count -eq 1) { $code[0] } else { "nhiều giá trị: $($code -join ',')" }); Text = $text }
}
function Deleted { @($script:Calls | Where-Object { $_ -like '/delete:*' } | ForEach-Object { $_.Substring(8) }) }
function Left { @($script:Vault | ForEach-Object { $_.T }) }

$Mixed = @(
    (C 'git:https://github.com'),
    (C 'git:https://NovWyatt@github.com'),               # Git Credential Manager lưu kèm tên: bản 1.0 bỏ sót
    (C 'git:https://khach-hang@github.com' 'khach-hang'),
    (C 'gh:github.com:NovWyatt'),
    (C 'vscodevscode.github-authentication/github.auth' 'github.auth'),
    (C 'GitHub - https://api.github.com/NovWyatt'),
    (C 'git:https://gitlab.com'),
    (C 'TERMSRV/may-chu' 'admin' 'Domain'),
    (C 'MicrosoftAccount:user=ai@example.com' 'ai@example.com' 'WindowsLive')
)

# ---- 1. Đọc danh sách
Write-KT '1. Đọc cmdkey /list' Cyan
Reset-Case $Mixed
$t = @(Get-CredentialTargets)
Check ($t.Count -eq 9) "đọc đủ 9 mục ($($t.Count))"
Check ($t -contains 'GitHub - https://api.github.com/NovWyatt') 'giữ nguyên tên mục có dấu cách'
Check ($t -contains 'TERMSRV/may-chu' -and $t -contains 'MicrosoftAccount:user=ai@example.com') 'đọc cả mục Domain, WindowsLive'
$script:Labels = @{ Target = 'Mục tiêu'; Type = 'Kiểu'; User = 'Người dùng'; Head = 'Thông tin xác thực đang lưu:' }
$t2 = @(Get-CredentialTargets)
Check (($t2 -join '|') -eq ($t -join '|')) 'Windows tiếng Việt (nhãn khác): đọc ra y như tiếng Anh'
$script:Labels = @{ Target = 'Target'; Type = 'Type'; User = 'User'; Head = 'Currently stored credentials:' }
Set-Vault @((C 'git:https://github.com'), (C 'git:https://github.com'))
Check (@(Get-CredentialTargets).Count -eq 1) 'mục trùng tên chỉ tính một lần'
Set-Vault @()
Check (@(Get-CredentialTargets).Count -eq 0) 'Credential Manager trống: danh sách rỗng'
$script:ListFails = $true
$err = $null; try { [void](Get-CredentialTargets) } catch { $err = $_.Exception.Message }
Check ($err -like '*cmdkey /list*') "cmdkey lỗi thì báo lỗi ($err)"

# ---- 2. Phân loại
Write-KT '2. Phân loại mục' Cyan
$want = [ordered]@{
    'git:https://github.com' = 'git'; 'git:https://github.com/' = 'git'; 'git:https://NovWyatt@github.com' = 'git'
    'git:https://github.com/NovWyatt/Tool_Win.git' = 'git'; 'github.com' = 'git'; 'https://github.com' = 'git'
    'https://github.com/' = 'git'; 'https://NovWyatt@github.com' = 'git'; 'Git:HTTPS://NovWyatt@GitHub.COM/' = 'git'
    'gh:github.com:' = 'gh'; 'gh:github.com:NovWyatt' = 'gh'
    'vscodevscode.github-authentication/github.auth' = 'khac'; 'GitHub - https://api.github.com/NovWyatt' = 'khac'
    'git:https://gitlab.com' = $null; 'TERMSRV/may-chu' = $null; 'MicrosoftAccount:user=ai@example.com' = $null
}
foreach ($k in $want.Keys) {
    $got = Get-GitHubKind $k
    Check ("$got" -eq "$($want[$k])") "$k -> '$($want[$k])' (được '$got')"
}

# ---- 3. Chạy mặc định: xoá mục Git, không đụng mục khác
Write-KT '3. Mặc định (trả lời "không" cho ứng dụng khác)' Cyan
Reset-Case $Mixed
$script:GhPath = 'C:\gia\gh.exe'
$r = Invoke-Flow
Check ($r.Code -eq 0) "mã thoát 0 ($($r.Code))"
$d = @(Deleted)
$dGot = @($d | Sort-Object) -join '|'
$dWant = @('git:https://github.com', 'git:https://khach-hang@github.com', 'git:https://NovWyatt@github.com' | Sort-Object) -join '|'
Check ($dGot -eq $dWant) "xoá đúng 3 mục Git, kể cả mục kèm tên tài khoản ($($d -join ', '))"
$l = @(Left)
Check ($l -contains 'gh:github.com:NovWyatt') 'mục GitHub CLI còn nguyên (để gh auth logout lo)'
Check ($l -contains 'vscodevscode.github-authentication/github.auth' -and $l -contains 'GitHub - https://api.github.com/NovWyatt') 'mục ứng dụng khác còn nguyên khi trả lời "không"'
Check ($l -contains 'git:https://gitlab.com' -and $l -contains 'TERMSRV/may-chu' -and $l -contains 'MicrosoftAccount:user=ai@example.com') 'mục không liên quan GitHub không bị đụng'
Check ($script:Asked.Count -eq 2) "hỏi hai câu: ứng dụng khác, GitHub CLI ($($script:Asked.Count))"
Check ($script:GhCalls -eq 0) 'không đăng xuất gh khi chưa đồng ý'
Check ($r.Text -match 'Đã xoá 3 mục') 'báo đã xoá 3 mục'
Check (@($script:Calls | Where-Object { $_ -eq '/list' }).Count -eq 2) 'đọc lại danh sách sau khi xoá để xác nhận'

# ---- 4. Đồng ý xoá cả ứng dụng khác và đăng xuất gh
Write-KT '4. Đồng ý cả hai câu hỏi' Cyan
Reset-Case $Mixed @($true, $true)
$script:GhPath = 'C:\gia\gh.exe'
$r = Invoke-Flow
Check ($r.Code -eq 0) "mã thoát 0 ($($r.Code))"
Check (@(Deleted).Count -eq 5) "xoá 5 mục: 3 Git + 2 ứng dụng khác ($(@(Deleted).Count))"
Check (@(Left) -contains 'gh:github.com:NovWyatt') 'vẫn không xoá thẳng mục gh'
Check ($script:GhCalls -eq 1) 'gọi gh auth logout một lần'

# ---- 5. Không có mục GitHub nào
Write-KT '5. Không có gì để xoá' Cyan
Reset-Case @((C 'git:https://gitlab.com'), (C 'TERMSRV/may-chu' 'admin' 'Domain'))
$r = Invoke-Flow
Check ($r.Code -eq 0) "mã thoát 0 ($($r.Code))"
Check (@(Deleted).Count -eq 0) 'không gọi lệnh xoá nào'
Check ($r.Text -match 'Không có mục GitHub nào') 'nói rõ không có gì để xoá'
Check ($r.Text -notmatch 'Đã xoá') 'không báo "Đã xoá" khi không xoá gì (lỗi của bản 1.0)'
Check ($script:Asked.Count -eq 0) 'không hỏi gì khi không có gh và không có mục ứng dụng khác'

# ---- 6. Chạy thử
Write-KT '6. -ChayThu' Cyan
Reset-Case $Mixed
$script:GhPath = 'C:\gia\gh.exe'
$script:ChayThu = $true
$r = Invoke-Flow
$script:ChayThu = $false
Check ($r.Code -eq 0) "mã thoát 0 ($($r.Code))"
Check (@(Deleted).Count -eq 0) 'không xoá gì'
Check ($script:Asked.Count -eq 0 -and $script:GhCalls -eq 0) 'không hỏi, không gọi gh'
Check (@(Left).Count -eq 9) 'kho giả còn đủ 9 mục'
Check (([regex]::Matches($r.Text, 'Sẽ xoá: ')).Count -eq 3) 'in 3 dòng "Sẽ xoá"'

# ---- 7. Xoá không được
Write-KT '7. Lỗi khi xoá' Cyan
Reset-Case $Mixed
$script:DeleteFails = @('git:https://NovWyatt@github.com')
$r = Invoke-Flow
Check ($r.Code -eq 3) "cmdkey báo lỗi một mục: mã thoát 3 ($($r.Code))"
Check ($r.Text -match 'Còn 1 mục chưa xoá được' -and $r.Text -match 'NovWyatt@github.com') 'nêu đúng mục còn lại'
Reset-Case $Mixed
$script:Sticky = @('git:https://github.com')
$r = Invoke-Flow
Check ($r.Code -eq 3) "cmdkey báo xong mà mục vẫn còn: mã thoát 3 ($($r.Code))"
Reset-Case $Mixed
$script:ListFails = $true
$r = Invoke-Flow
Check ($r.Code -eq 1) "không đọc được Credential Manager: mã thoát 1 ($($r.Code))"
Check (@(Deleted).Count -eq 0) 'không xoá gì khi không đọc được danh sách'

# ---- 8. Quyền Admin: chỉ cảnh báo
Write-KT '8. Chạy bằng quyền Admin' Cyan
Reset-Case @((C 'git:https://github.com'))
$script:IsAdmin = $true
$r = Invoke-Flow
Check ($r.Text -match 'quyền Admin') 'cảnh báo khi chạy bằng quyền Admin'
Check ($r.Code -eq 0) "vẫn chạy, mã thoát 0 ($($r.Code))"

# ---- 9. File .bat chỉ là vỏ: chuyển tham số và mã thoát
Write-KT '9. logout-github-local.bat' Cyan
$dir = New-TestDir "vo bat O'Brien"
Copy-Item -LiteralPath (Join-Path $Tool 'logout-github-local.bat') -Destination $dir
$log = Join-Path $dir 'thamso.txt'
Set-Content -LiteralPath (Join-Path $dir 'DangXuatGitHub.ps1') -Encoding UTF8 -Value @(
    'param([switch]$ChayThu, [switch]$KhongDung)'
    ('Set-Content -LiteralPath ''' + $log.Replace("'", "''") + ''' -Value "$ChayThu $KhongDung"')
    'exit 3'
)
$r = Invoke-Bat (Join-Path $dir 'logout-github-local.bat') -BatArgs @('-ChayThu', '-KhongDung') -TimeoutSec 60
Check ($r.Code -eq 3) "mã thoát của script đi ra ngoài .bat ($($r.Code))"
Check ((Test-Path -LiteralPath $log) -and ((Get-Content -LiteralPath $log -Raw).Trim() -eq 'True True')) 'tham số -ChayThu -KhongDung tới được script (thư mục có dấu '' và dấu cách)'

Complete-Test
