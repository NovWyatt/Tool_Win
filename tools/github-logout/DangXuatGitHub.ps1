<#
  Đăng xuất GitHub trên máy: xoá thông tin đăng nhập GitHub mà Git lưu trong Windows Credential Manager của tài khoản
  Windows đang chạy, để lần git push sau chọn lại tài khoản. Không xoá code, commit hay repo.

  Bản 1.0 chỉ xoá 4 tên mục cố định nên sót mục Git Credential Manager lưu kèm tên người dùng
  (vd git:https://ten@github.com). Bản này đọc 'cmdkey /list', lấy mọi mục có chữ "github" rồi chia ba nhóm:
    - của Git (git:..., github.com, https://github.com/...): xoá;
    - của GitHub CLI (gh:...): không xoá ở đây, bước sau hỏi rồi chạy 'gh auth logout';
    - của ứng dụng khác (VS Code, GitHub Desktop...): liệt kê, hỏi trước khi xoá (mặc định là không).

  -ChayThu: chỉ liệt kê và in việc sẽ làm, không xoá gì. -KhongDung: không chờ Enter khi xong.
  Mã thoát: 0 xong (kể cả khi không có gì để xoá), 1 lỗi (không đọc được Credential Manager), 3 còn mục chưa xoá được.
#>
param(
    [switch]$ChayThu,
    [switch]$KhongDung
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

# ---------------------------------------------------------------- in ra, hỏi
function Write-Head { param([string]$Text) Write-Host ''; Write-Host ("== $Text " + ('=' * [Math]::Max(3, 68 - $Text.Length))) -ForegroundColor Cyan }
function Write-Line { param([string]$Text) Write-Host "  $Text" }
function Write-Ok { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Write-Bad { param([string]$Text) Write-Host "  [X]  $Text" -ForegroundColor Red }
function Write-Info { param([string]$Text) Write-Host "  [i]  $Text" -ForegroundColor Gray }
function Write-Plan { param([string]$Text) Write-Host "   ->  $Text" -ForegroundColor White }

function Read-YesNo {
    # Không có bàn phím (chạy tự động) thì trả mặc định thay vì treo.
    param([string]$Question, [bool]$Default = $false)
    if ([Console]::IsInputRedirected) { return $Default }
    $hint = if ($Default) { '[C/k]' } else { '[c/K]' }
    while ($true) {
        $a = ([string](Read-Host "  $Question $hint")).Trim().ToLowerInvariant()
        if (-not $a) { return $Default }
        if ($a -in 'c', 'co', 'có', 'y', 'yes') { return $true }
        if ($a -in 'k', 'khong', 'không', 'n', 'no') { return $false }
    }
}

function Wait-Close {
    param([string]$Text = 'Bấm Enter để đóng cửa sổ')
    if ($KhongDung -or [Console]::IsInputRedirected) { return }
    Write-Host ''
    [void](Read-Host "  $Text")
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------- Credential Manager
function Invoke-Cmdkey {
    param([string[]]$Arguments)
    $out = & "$env:SystemRoot\System32\cmdkey.exe" @Arguments 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Output = @($out | ForEach-Object { [string]$_ }) }
}

function Get-CredentialTargets {
    # Dòng mục trong 'cmdkey /list': "Target: LegacyGeneric:target=git:https://github.com". Chữ "Target" đổi theo ngôn
    # ngữ Windows nhưng phần "target=" thì không, nên chỉ dựa vào nó. Tên mục để xoá là phần sau "target=".
    $r = Invoke-Cmdkey @('/list')
    if ($r.Code -ne 0) { throw ('cmdkey /list lỗi (mã {0}): {1}' -f $r.Code, (($r.Output | Select-Object -First 3) -join ' ')) }
    $seen = @{}
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($l in $r.Output) {
        if ($l -match 'target=(.+)$') {
            $t = $Matches[1].Trim()
            if ($t -and -not $seen.ContainsKey($t)) { $seen[$t] = $true; $list.Add($t) }
        }
    }
    return $list.ToArray()   # trả từng phần tử; nơi gọi bọc @()
}

function Get-GitHubKind {
    # git: mục Git dùng khi push/pull (Git Credential Manager, wincred, bản cũ của công cụ này); gh: GitHub CLI;
    # khac: ứng dụng khác có chữ github (VS Code, GitHub Desktop...). $null: không liên quan GitHub.
    param([string]$Target)
    if ($Target -notmatch 'github') { return $null }
    if ($Target -match '^git:') { return 'git' }
    if ($Target -match '^gh:') { return 'gh' }
    if ($Target -match '^(https?://)?([^/@\s]+@)?(www\.)?github\.com(/\S*)?$') { return 'git' }
    return 'khac'
}

function Get-GitHubTargets {
    param([string[]]$Targets)
    foreach ($t in $Targets) {
        $k = Get-GitHubKind $t
        if ($k) { [pscustomobject]@{ Target = $t; Kind = $k } }
    }
}

function Remove-CredentialTarget {
    param([string]$Target)
    $r = Invoke-Cmdkey @("/delete:$Target")
    return ($r.Code -eq 0)
}

# ---------------------------------------------------------------- GitHub CLI
function Get-GhPath {
    $c = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    return $null
}

function Invoke-GhLogout {
    # Chạy chung cửa sổ (không bắt đầu ra) để gh hỏi được khi có nhiều tài khoản
    param([string]$Gh)
    $p = Start-Process -FilePath $Gh -ArgumentList 'auth', 'logout', '--hostname', 'github.com' -NoNewWindow -Wait -PassThru
    return $p.ExitCode
}

# ---------------------------------------------------------------- chạy
function Invoke-DangXuat {
    $kindLabel = @{ git = 'Git'; gh = 'GitHub CLI'; khac = 'ứng dụng khác' }
    if (Test-IsAdmin) {
        Write-Warn 'Đang chạy bằng quyền Admin. Công cụ chỉ xoá mục của tài khoản Windows đang chạy cửa sổ này;'
        Write-Warn 'nếu cửa sổ Admin là tài khoản khác thì mục của bạn vẫn còn. Nên chạy bằng quyền thường.'
    }

    Write-Head 'Mục GitHub đang lưu trong Credential Manager'
    try { $all = @(Get-CredentialTargets) } catch { Write-Bad $_.Exception.Message; return 1 }
    $found = @(Get-GitHubTargets $all)
    $git = @($found | Where-Object { $_.Kind -eq 'git' })
    $gh = @($found | Where-Object { $_.Kind -eq 'gh' })
    $other = @($found | Where-Object { $_.Kind -eq 'khac' })
    if (-not $found.Count) { Write-Ok 'Không có mục GitHub nào đang lưu: không có gì để xoá.' }
    foreach ($f in $found) { Write-Line ('{0,-14} {1}' -f ($kindLabel[$f.Kind] + ':'), $f.Target) }

    $toDelete = New-Object System.Collections.Generic.List[string]
    foreach ($f in $git) { $toDelete.Add($f.Target) }
    if ($other.Count) {
        Write-Info ('{0} mục của ứng dụng khác (VS Code, GitHub Desktop...): xoá thì phải đăng nhập GitHub lại trong ứng dụng đó.' -f $other.Count)
        if ($ChayThu) { Write-Plan 'Sẽ hỏi có xoá các mục này không (mặc định: không).' }
        elseif (Read-YesNo 'Xoá cả các mục của ứng dụng khác?' $false) { foreach ($f in $other) { $toDelete.Add($f.Target) } }
    }
    if ($gh.Count) { Write-Info 'Mục của GitHub CLI không xoá trực tiếp: bước sau hỏi rồi chạy "gh auth logout".' }

    $failed = New-Object System.Collections.Generic.List[string]
    if ($toDelete.Count) {
        Write-Head 'Xoá'
        foreach ($t in $toDelete) {
            if ($ChayThu) { Write-Plan "Sẽ xoá: $t"; continue }
            if (Remove-CredentialTarget $t) { Write-Ok "Đã xoá: $t" } else { Write-Bad "Không xoá được: $t" }
        }
    }

    $ghPath = Get-GhPath
    if ($ghPath) {
        Write-Head 'GitHub CLI'
        if ($ChayThu) { Write-Plan 'Sẽ hỏi có đăng xuất GitHub CLI (gh auth logout) không (mặc định: không).' }
        elseif (Read-YesNo 'Máy có GitHub CLI (gh). Đăng xuất gh khỏi github.com?' $false) {
            $code = Invoke-GhLogout $ghPath
            if ($code -eq 0) { Write-Ok 'Đã đăng xuất GitHub CLI.' } else { Write-Warn "gh auth logout trả mã $code (có thể gh chưa đăng nhập)." }
        }
    }

    if ($ChayThu) {
        Write-Head 'Chạy thử'
        Write-Info 'Chưa xoá gì. Chạy lại không có -ChayThu để xoá.'
        return 0
    }
    if ($toDelete.Count) {
        # Đọc lại để chắc chắn: cmdkey có thể báo thành công mà mục vẫn còn (vd mục do chính sách quản lý)
        try { $left = @(Get-CredentialTargets) } catch { Write-Bad $_.Exception.Message; return 1 }
        foreach ($t in $toDelete) { if ($left -contains $t) { $failed.Add($t) } }
        Write-Head 'Kết quả'
        if ($failed.Count) {
            Write-Bad ('Còn {0} mục chưa xoá được:' -f $failed.Count)
            foreach ($t in $failed) { Write-Line "  $t" }
            Write-Info 'Mở Control Panel > Credential Manager > Windows Credentials để xoá tay.'
            return 3
        }
        Write-Ok ('Đã xoá {0} mục.' -f $toDelete.Count)
    }
    Write-Info 'Lần git push sau Git sẽ hỏi đăng nhập GitHub: chọn đúng tài khoản cần dùng.'
    return 0
}

# ---------------------------------------------------------------- bắt đầu
if ($env:TRAMTOOL_GITHUBLOGOUT_TEST) { return }   # bài thử nạp các hàm rồi tự gọi
try { $Host.UI.RawUI.WindowTitle = 'Đăng xuất GitHub trên máy' } catch { }
Write-Host ''
Write-Host '  ĐĂNG XUẤT GITHUB TRÊN MÁY' -ForegroundColor Cyan
Write-Host '  Chỉ xoá thông tin đăng nhập GitHub đã lưu trong Windows. Không xoá code, commit hay repo.'
$code = Invoke-DangXuat
Wait-Close
exit $code
