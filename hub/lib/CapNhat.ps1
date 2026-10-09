# Trạm Tool - cập nhật trạm và công cụ từ kho git (dùng chung cho máy chủ và hub\fixes\CapNhat-TramTool.ps1).
# Chỉ đọc trạng thái ở đây; việc kéo bản mới (fast-forward) nằm trong script chạy ở cửa sổ riêng.

function Invoke-HubGit {
    # Chạy git trong thư mục $Dir, không mở hộp thoại đăng nhập (máy chủ không có cửa sổ để hỏi).
    # Trả @{ Code; Out (mảng dòng); Err; TimedOut }. Không có git thì Code = -1.
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string[]]$GitArgs, [int]$TimeoutSec = 20)
    $git = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $git) { return @{ Code = -1; Out = @(); Err = 'Máy này chưa cài Git.'; TimedOut = $false } }
    $psi = New-Object Diagnostics.ProcessStartInfo $git.Source
    $psi.Arguments = (@('-C', $Dir) + $GitArgs | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $psi.EnvironmentVariables['GCM_INTERACTIVE'] = 'never'
    $psi.EnvironmentVariables['LC_ALL'] = 'C'
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch { }
        return @{ Code = -2; Out = @(); Err = "git chạy quá $TimeoutSec giây."; TimedOut = $true }
    }
    $p.WaitForExit()
    $lines = @(($o.Result -split "`r?`n") | Where-Object { $_ -ne '' })
    return @{ Code = $p.ExitCode; Out = $lines; Err = $e.Result.Trim(); TimedOut = $false }
}

function Get-RepoUpdateInfo {
    # Trạng thái kho git chứa trạm: nhánh, commit, số commit trên kho chưa về máy (behind), commit trên máy chưa đẩy
    # (ahead), file đang sửa (chỉ file git theo dõi). -Fetch: hỏi kho trước (cần mạng; không hỏi mật khẩu).
    # canUpdate: kéo được an toàn bằng fast-forward. reason: vì sao không (để giao diện hiện).
    param([Parameter(Mandatory)][string]$RootDir, [switch]$Fetch, [int]$TimeoutSec = 25)
    $info = [ordered]@{
        git = $false; repo = $false; branch = ''; commit = ''; commitDate = ''; subject = ''; upstream = ''
        behind = 0; ahead = 0; dirty = @(); fetched = $false; fetchError = ''; incoming = @(); canUpdate = $false; reason = ''
        checkedAt = (Get-Date).ToString('s')
    }
    $r = Invoke-HubGit -Dir $RootDir -GitArgs @('rev-parse', '--show-toplevel')
    if ($r.Code -eq -1) { $info.reason = 'Máy này chưa cài Git: cập nhật bằng cách chép bản mới đè lên thư mục trạm.'; return $info }
    $info.git = $true
    $top = if ($r.Code -eq 0 -and $r.Out.Count) { [IO.Path]::GetFullPath(($r.Out[0] -replace '/', '\')).TrimEnd('\') } else { '' }
    if (-not $top -or $top -ne [IO.Path]::GetFullPath($RootDir).TrimEnd('\')) {
        $info.reason = 'Thư mục trạm không phải bản sao git (chép từ USB hoặc file nén): cập nhật bằng cách chép bản mới đè lên.'
        return $info
    }
    $info.repo = $true
    $r = Invoke-HubGit -Dir $RootDir -GitArgs @('log', '-1', '--format=%h%x1f%cI%x1f%s')
    if ($r.Code -eq 0 -and $r.Out.Count) { $f = $r.Out[0] -split [char]0x1f; $info.commit = $f[0]; $info.commitDate = $f[1]; $info.subject = $f[2] }
    $r = Invoke-HubGit -Dir $RootDir -GitArgs @('symbolic-ref', '--quiet', '--short', 'HEAD')
    if ($r.Code -ne 0) { $info.reason = 'Kho đang không ở nhánh nào (detached HEAD): cập nhật bằng tay.'; return $info }
    $info.branch = $r.Out[0]
    $r = Invoke-HubGit -Dir $RootDir -GitArgs @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
    if ($r.Code -ne 0 -or -not $r.Out.Count) { $info.reason = "Nhánh $($info.branch) chưa gắn với nhánh trên kho (upstream)."; return $info }
    $info.upstream = $r.Out[0]
    $r = Invoke-HubGit -Dir $RootDir -GitArgs @('status', '--porcelain', '--untracked-files=no')
    $info.dirty = @($r.Out | ForEach-Object { $_.Substring([Math]::Min(3, $_.Length)) } | Select-Object -First 50)
    if ($Fetch) {
        $r = Invoke-HubGit -Dir $RootDir -GitArgs @('fetch', '--prune', '--quiet') -TimeoutSec $TimeoutSec
        if ($r.Code -eq 0) { $info.fetched = $true }
        else { $info.fetchError = $(if ($r.Err) { ($r.Err -split "`r?`n")[-1] } else { "git fetch trả mã $($r.Code)." }) }
    }
    $r = Invoke-HubGit -Dir $RootDir -GitArgs @('rev-list', '--left-right', '--count', 'HEAD...@{u}')
    if ($r.Code -eq 0 -and $r.Out.Count -and $r.Out[0] -match '^(\d+)\s+(\d+)$') { $info.ahead = [int]$Matches[1]; $info.behind = [int]$Matches[2] }
    if ($info.behind -gt 0) {
        $r = Invoke-HubGit -Dir $RootDir -GitArgs @('log', '--format=%h%x1f%cI%x1f%s', '-n', '30', 'HEAD..@{u}')
        $info.incoming = @($r.Out | ForEach-Object { $f = $_ -split [char]0x1f; [ordered]@{ commit = $f[0]; date = $f[1]; subject = $f[2] } })
    }
    if ($info.dirty.Count) { $info.reason = "Có $($info.dirty.Count) file đang sửa trên máy này: cập nhật sẽ dừng để không ghi đè." }
    elseif ($info.ahead -gt 0 -and $info.behind -gt 0) { $info.reason = 'Nhánh trên máy và trên kho đã lệch nhau (cả hai cùng có commit mới): cập nhật bằng tay.' }
    elseif ($info.behind -gt 0) { $info.canUpdate = $true }
    return $info
}
