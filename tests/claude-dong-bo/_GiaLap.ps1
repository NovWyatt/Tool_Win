# Dữ liệu Claude giả cho các bài thử claude-dong-bo: máy giả (AppData\Claude, thư mục người dùng), mục danh sách phiên,
# nội dung hội thoại. Bài thử nạp file này, đặt các biến CDB_* rồi nạp DongBoClaude.ps1 (TRAMTOOL_CLAUDEDONGBO_TEST).
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
function Save-Text([string]$Path, [string]$Text) {
    $d = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
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
    return [pscustomobject]@{ Id = "local_$u"; Uuid = $u; Cli = $cli; File = $f; Cwd = $Cwd; Title = $Title }
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
function Use-Machine($M) {
    # Đổi sang máy giả khác trong cùng bài thử (công cụ đã nạp): nơi đọc Claude Desktop, thư mục người dùng.
    $env:CDB_CLAUDE_APPDATA = $M.App
    $script:UserDir = $M.Nha
    $script:ProjectsDir = Join-Path $M.Nha '.claude\projects'
    $script:ClaudeJson = Join-Path $M.Nha '.claude.json'
}
