<#
  Trạm Tool - cài một lần cho máy mới. Chạy bằng CAI_DAT.bat ở thư mục gốc (bấm đúp).
  Kiểm tra từng công cụ cần gì (giống mục "Yêu cầu để chạy" của trạm), liệt kê phần còn thiếu, hỏi rồi cài theo thứ tự:
  gói winget, script cài đặt của từng công cụ (CAI_DAT.ps1), script cài đặt của trạm (hub\fixes, có thể cần Admin).
  Xong thì kiểm tra lại, tạo lối tắt trên Desktop và mở trạm. Chạy lại bao nhiêu lần cũng được: thứ đã có thì bỏ qua.
    -ChayThu  : chỉ kiểm tra và in kế hoạch, không cài, không đổi gì trên máy.
    -TatCa    : không hỏi; cài mọi thứ còn thiếu (kể cả mô hình ghi âm khoảng 5 GB), tạo lối tắt, mở trạm.
    -KhongMo  : xong không mở Trạm Tool.
    -KhongLoiTat : không tạo lối tắt trên Desktop.
    -ToolsDir : thư mục công cụ khác (để thử với công cụ giả).
  Mã thoát: 0 đủ hết (hoặc chạy thử), 3 còn thiếu sau khi cài, 1 lỗi.
#>
[CmdletBinding()]
param(
    [switch]$ChayThu,
    [switch]$TatCa,
    [switch]$KhongMo,
    [switch]$KhongLoiTat,
    [string]$ToolsDir = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$HubDir = $PSScriptRoot
$RootDir = Split-Path $HubDir -Parent
$customTools = [bool]$ToolsDir
if (-not $ToolsDir) { $ToolsDir = Join-Path $RootDir 'tools' }

. (Join-Path $HubDir 'lib\Common.ps1')
. (Join-Path $HubDir 'lib\Catalog.ps1')
. (Join-Path $HubDir 'lib\AnToan.ps1')
. (Join-Path $HubDir 'lib\Checks.ps1')

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
try { $Host.UI.RawUI.WindowTitle = 'Trạm Tool - cài đặt cho máy này' } catch { }

function Ask([string]$Prompt, [string[]]$Keys, [string]$Fallback) {
    if ($TatCa) { return $Keys[0] }
    return Read-AtChoice -Prompt $Prompt -Keys $Keys -Fallback $Fallback
}

# Submodule (vd tools\mdf2sql) trống khi tải repo dạng .zip: lấy bằng git nếu có, không thì tải .zip của repo công khai.
function Get-EmptySubmodules {
    $file = Join-Path $RootDir '.gitmodules'
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    $list = @()
    $cur = $null
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        if ($line -match '^\s*\[submodule ') { if ($cur) { $list += $cur }; $cur = @{ path = ''; url = '' } }
        elseif ($cur -and $line -match '^\s*path\s*=\s*(.+?)\s*$') { $cur.path = $Matches[1] }
        elseif ($cur -and $line -match '^\s*url\s*=\s*(.+?)\s*$') { $cur.url = $Matches[1] }
    }
    if ($cur) { $list += $cur }
    return @($list | Where-Object {
            $_.path -and $_.url -and -not @(Get-ChildItem -LiteralPath (Join-Path $RootDir $_.path) -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.git' }).Count
        })
}

function Install-Submodule($Sub) {
    $dest = Join-Path $RootDir ($Sub.path -replace '/', '\')
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($git -and (Test-Path -LiteralPath (Join-Path $RootDir '.git'))) {
        & $git.Source -C $RootDir submodule update --init -- $Sub.path
        if ($LASTEXITCODE -eq 0) { return $true }
        Write-AtWarn "git báo lỗi (mã $LASTEXITCODE), thử tải bản .zip."
    }
    if ($Sub.url -notmatch '^https://github\.com/[\w.-]+/[\w.-]+?(\.git)?$') { Write-AtBad "Không biết cách tải $($Sub.url)."; return $false }
    $zipUrl = ($Sub.url -replace '\.git$', '') + '/archive/HEAD.zip'
    $tmp = Join-Path $env:TEMP ('TramTool_sub_' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $tmp | Out-Null
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-AtInfo "Tải $zipUrl"
        Invoke-WebRequest -Uri $zipUrl -OutFile (Join-Path $tmp 'src.zip') -UseBasicParsing
        Expand-Archive -LiteralPath (Join-Path $tmp 'src.zip') -DestinationPath (Join-Path $tmp 'x')
        $top = @(Get-ChildItem -LiteralPath (Join-Path $tmp 'x') -Directory)
        if ($top.Count -ne 1) { throw 'File .zip không đúng cấu trúc.' }
        if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
        Get-ChildItem -LiteralPath $top[0].FullName -Force | Move-Item -Destination $dest
        return $true
    } catch {
        Write-AtBad "Tải không được: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Gom phần còn thiếu theo cách cài: hai yêu cầu cùng một script cài (vd .venv và LibreDWG) chỉ chạy một lần.
function Get-InstallPlan($Catalog) {
    $plan = [ordered]@{}
    $manual = New-Object System.Collections.ArrayList
    $optional = New-Object System.Collections.ArrayList
    foreach ($t in $Catalog) {
        if (-not @($t.requires).Count) { continue }
        foreach ($r in @(Get-ToolRequirements -Tool $t -Fresh)) {
            if ($r.ok) { continue }
            if ($r.optional) { [void]$optional.Add("$($t.name): $($r.label)"); continue }
            $fix = $r.fix
            $act = [string](Get-Prop $fix 'action' '')
            $wg = [string](Get-Prop $fix 'winget' '')
            $hs = [string](Get-Prop $fix 'hubScript' '')
            $item = $null
            if ($act) {
                $a = @($t.actions | Where-Object { $_.id -eq $act }) | Select-Object -First 1
                if ($a -and $a.exists) {
                    $item = [ordered]@{ key = "a:$($t.id):$act"; order = 1; kind = 'action'; tool = $t; action = $a; label = "$($t.name): $($a.label)"
                        how = "chạy $($a.file) của công cụ$(if ($a.admin) { ', cần quyền Admin' } else { ', không cần Admin' })"; note = $a.duration; heavy = ($a.duration -match 'GB') }
                }
            } elseif ($wg) {
                $extra = [string](Get-Prop $fix 'args' '')
                $item = [ordered]@{ key = "w:$wg"; order = $(if ($wg -like 'Python.*') { 0 } else { 0.5 }); kind = 'winget'; id = $wg; args = $extra; label = [string](Get-Prop $fix 'label' $r.label)
                    how = "winget ($wg)$(if ($extra -match '--scope\s+user') { ', không cần Admin' } else { ', Windows có thể hỏi quyền Admin' })"; note = ''; heavy = $false }
            } elseif ($hs -match '^[A-Za-z0-9._-]+\.ps1$') {
                $adm = [bool](Get-Prop $fix 'admin' $false)
                $item = [ordered]@{ key = "h:$hs"; order = 2; kind = 'hub'; file = $hs; admin = $adm; label = [string](Get-Prop $fix 'label' $r.label)
                    how = "script của trạm hub\fixes\$hs$(if ($adm) { ', cần quyền Admin' })"; note = ''; heavy = $false }
            }
            if (-not $item) { [void]$manual.Add("$($t.name): $($r.label). $($r.detail)"); continue }
            if (-not $plan.Contains($item.key)) { $item.reqs = New-Object System.Collections.ArrayList; $item.tools = New-Object System.Collections.ArrayList; $plan[$item.key] = $item }
            $p = $plan[$item.key]
            [void]$p.reqs.Add($r.label)
            if (-not $p.tools.Contains($t.name)) { [void]$p.tools.Add($t.name) }
        }
    }
    $items = @($plan.Values | Sort-Object { $_.order }, { $_.label })
    return @{ items = $items; manual = $manual.ToArray(); optional = $optional.ToArray() }
}

function Invoke-PlanItem($It) {
    switch ($It.kind) {
        'winget' {
            $w = Get-Command winget.exe -ErrorAction SilentlyContinue
            if (-not $w) { Write-AtBad 'Không có winget.'; return $false }
            $argv = @('install', '--id', $It.id, '--exact', '--accept-package-agreements', '--accept-source-agreements') + @($It.args -split '\s+' | Where-Object { $_ })
            & $w.Source @argv
            $code = $LASTEXITCODE
            Update-EnvPath
            if ($code -ne 0) { Write-AtWarn "winget trả mã $(Format-ExitCode $code) (có thể gói đã có sẵn); kiểm tra lại ở cuối." }
            return $true
        }
        'action' {
            $file = Expand-HubPath -Path $It.action.file -BaseDir $It.tool.dir
            $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
            if ($It.action.admin -and -not (Test-IsAdmin)) {
                $exe = if ($ext -eq '.ps1') { 'powershell.exe' } else { 'cmd.exe' }
                $argv = if ($ext -eq '.ps1') { @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$file`"") } else { @('/c', "`"$file`"") }
                try { $p = Start-Process -FilePath $exe -ArgumentList $argv -WorkingDirectory $It.tool.dir -Verb RunAs -Wait -PassThru }
                catch { Write-AtWarn 'Đã huỷ ở hộp thoại quyền Admin.'; return $false }
                $code = $p.ExitCode
            } else {
                Push-Location -LiteralPath $It.tool.dir
                try {
                    if ($ext -eq '.ps1') { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $file }
                    else { & cmd.exe /c "`"$file`"" }
                    $code = $LASTEXITCODE
                } finally { Pop-Location }
            }
            Update-EnvPath
            if ($code -ne 0) { Write-AtBad "Script cài báo lỗi (mã $(Format-ExitCode $code))."; return $false }
            return $true
        }
        'hub' {
            $file = Join-Path $HubDir "fixes\$($It.file)"
            if (-not (Test-Path -LiteralPath $file)) { Write-AtBad "Thiếu $file."; return $false }
            if ($It.admin -and -not (Test-IsAdmin)) {
                Write-AtInfo 'Windows sẽ hỏi quyền Admin, bấm "Có" để tiếp tục. Cửa sổ cài mở riêng, xong tự đóng.'
                try { $p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$file`"") -Verb RunAs -Wait -PassThru }
                catch { Write-AtWarn 'Đã huỷ ở hộp thoại quyền Admin.'; return $false }
                $code = $p.ExitCode
            } else {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $file
                $code = $LASTEXITCODE
            }
            Update-EnvPath
            if ($code -ne 0) { Write-AtBad "Script cài báo lỗi (mã $(Format-ExitCode $code))."; return $false }
            return $true
        }
    }
    return $false
}

function Show-ToolStatus($Catalog) {
    $missing = 0
    foreach ($t in $Catalog) {
        if (-not @($t.requires).Count) { continue }
        $reqs = @(Get-ToolRequirements -Tool $t -Fresh)
        $bad = @($reqs | Where-Object { -not $_.ok -and -not $_.optional })
        if ($bad.Count) { $missing++; Write-AtBad "$($t.name): còn thiếu $(($bad | ForEach-Object { $_.label }) -join ', ')" }
        else { Write-AtOk "$($t.name): đủ" }
    }
    return $missing
}

# ================================================================== bắt đầu
Write-AtHead 'Trạm Tool: cài đặt cho máy này' "Thư mục: $RootDir"
if ($ChayThu) { Write-AtWarn 'Chạy thử: chỉ kiểm tra và in kế hoạch, không cài, không đổi gì.' }

Write-Host ''
Write-Host '  Máy' -ForegroundColor Cyan
$os = [Environment]::OSVersion.Version
if ($os.Build -lt 17763) { Write-AtBad "Windows build $($os.Build): trạm cần Windows 10 bản 1809 trở lên."; Wait-AtClose; exit 1 }
Write-AtOk "Windows build $($os.Build), PowerShell $($PSVersionTable.PSVersion)$(if (Test-IsAdmin) { ', đang chạy với quyền Admin' })"

# Bỏ dấu "tải từ Internet" của file trong thư mục trạm (giải nén từ .zip tải về) để .bat, .ps1 không bị Windows chặn.
$blocked = @(Get-BlockedFiles $RootDir)
if ($blocked.Count) {
    if ($ChayThu) { Write-AtWarn "$($blocked.Count) file còn dấu tải từ Internet (sẽ bỏ dấu khi cài thật)." }
    else {
        foreach ($f in $blocked) { Unblock-File -LiteralPath $f -ErrorAction SilentlyContinue }
        Write-AtOk "Đã bỏ dấu tải từ Internet cho $($blocked.Count) file của trạm."
    }
} else { Write-AtOk 'File của trạm không bị Windows đánh dấu tải từ Internet.' }

# Bản portable: Python và .venv mang theo, chỉ cần trỏ lại đúng thư mục này (không cài gì).
$portable = Initialize-PortableRuntime -RootDir $RootDir -ToolsDir $ToolsDir
if ($portable) {
    Write-AtOk "Bản portable: Python $($portable.Version) mang theo trong runtime\python, không cần cài Python."
    if (@($portable.Fixed).Count) { Write-AtOk "Đã trỏ lại .venv về thư mục này: $(@($portable.Fixed) -join ', ')." }
}

if (-not $customTools) {
    foreach ($sub in @(Get-EmptySubmodules)) {
        if ($ChayThu) { Write-AtWarn "Thư mục $($sub.path) đang trống (sẽ tải từ $($sub.url))." ; continue }
        Write-AtInfo "Thư mục $($sub.path) đang trống, lấy về từ $($sub.url)"
        if (Install-Submodule $sub) { Write-AtOk "Đã có $($sub.path)." } else { Write-AtBad "Chưa lấy được $($sub.path); công cụ này sẽ không hiện trong trạm." }
    }
}

$w = Get-WingetStatus
if ($w.ok) { Write-AtOk "winget $($w.version)" } else { Write-AtWarn "winget chưa dùng được: $($w.problem)" }

Write-Host ''
Write-Host '  Công cụ' -ForegroundColor Cyan
$catalog = Get-HubCatalog -ToolsDir $ToolsDir -RootDir $RootDir   # trả sẵn mảng; bọc @() sẽ thành mảng lồng
Write-AtInfo "$($catalog.Count) công cụ trong $ToolsDir. Đang kiểm tra yêu cầu (vài giây)..."
$plan = Get-InstallPlan $catalog
$items = @($plan.items)

if (-not $items.Count) {
    Write-AtOk 'Mọi công cụ đã đủ yêu cầu để chạy.'
} else {
    Write-Host ''
    Write-Host "  Cần cài $($items.Count) mục:" -ForegroundColor Yellow
    $i = 0
    foreach ($it in $items) {
        $i++
        Write-Host ("   {0}. {1}" -f $i, $it.label) -ForegroundColor White
        Write-AtInfo "Cho: $($it.tools -join ', ') ($($it.reqs -join ', '))"
        Write-AtInfo "Cách cài: $($it.how)$(if ($it.note) { ". Thời gian: $($it.note)" })"
        if ($it.heavy) { Write-AtWarn 'Mục này tải nhiều (vài GB): cần mạng ổn định và chỗ trống trên ổ đĩa.' }
    }
}
foreach ($m in $plan.manual) { Write-AtWarn "Cần cài tay: $m" }
foreach ($o in $plan.optional) { Write-AtInfo "Không bắt buộc, chưa có: $o" }

$failed = 0
if ($ChayThu) {
    Write-Host ''
    Write-AtInfo 'Chạy thử: dừng ở đây, chưa cài gì.'
} elseif ($items.Count) {
    # Các nút Cài dùng winget: hỏng thì sửa trước (script của trạm, hỏi từng bước).
    if (-not $w.ok -and @($items | Where-Object { $_.kind -eq 'winget' }).Count) {
        Write-Host ''
        if ((Ask 'winget chưa dùng được. Sửa winget trước? Gõ C (có) hoặc K (bỏ qua) rồi Enter' @('C', 'K') 'K') -eq 'C') {
            [void](Invoke-PlanItem ([ordered]@{ kind = 'hub'; file = 'Sua-Winget.ps1'; admin = $false }))
            $w = Get-WingetStatus
        }
    }
    Write-Host ''
    $mode = Ask 'Gõ C để cài tất cả, T để hỏi từng mục, K để thoát, rồi Enter' @('C', 'T', 'K') 'K'
    if ($mode -ne 'K') {
        $n = 0
        foreach ($it in $items) {
            $n++
            if ($mode -eq 'T' -and (Ask "Cài mục $n ($($it.label))? Gõ C hoặc K rồi Enter" @('C', 'K') 'K') -ne 'C') { continue }
            Write-AtHead "$n/$($items.Count). $($it.label)" $it.how
            if ($it.kind -eq 'winget' -and -not $w.ok) { Write-AtBad 'Bỏ qua: winget chưa dùng được.'; $failed++; continue }
            $ok = $false
            try { $ok = Invoke-PlanItem $it } catch { Write-AtBad $_.Exception.Message }
            if (-not $ok) { $failed++ }
        }
    }
}

Write-Host ''
Write-Host '  Kết quả' -ForegroundColor Cyan
Clear-CheckCache
$catalog = Get-HubCatalog -ToolsDir $ToolsDir -RootDir $RootDir   # trả sẵn mảng; bọc @() sẽ thành mảng lồng
$missing = Show-ToolStatus $catalog
if (-not $missing) { Write-AtOk 'Các công cụ khác không cần cài thêm gì.' }

if (-not $ChayThu) {
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Trạm Tool.lnk'
    if (Test-Path -LiteralPath $lnk) { Write-AtOk 'Đã có lối tắt Trạm Tool trên Desktop.' }
    elseif (-not $KhongLoiTat -and (Ask 'Tạo lối tắt Trạm Tool trên Desktop? Gõ C hoặc K rồi Enter' @('C', 'K') 'K') -eq 'C') {
        try { Write-AtOk "Đã tạo $(New-DesktopShortcut -RootDir $RootDir -HubDir $HubDir)" } catch { Write-AtWarn "Không tạo được lối tắt: $($_.Exception.Message)" }
    }
    if (-not $KhongMo -and (Ask 'Mở Trạm Tool ngay? Gõ C hoặc K rồi Enter' @('C', 'K') 'K') -eq 'C') {
        Start-Process -FilePath (Join-Path $RootDir 'TramTool.bat') -WorkingDirectory $RootDir
    }
}

Write-Host ''
if ($ChayThu) { Write-AtInfo 'Xong phần kiểm tra. Chạy lại CAI_DAT.bat (không có -ChayThu) để cài.'; $code = 0 }
elseif ($missing) { Write-AtWarn "Còn $missing công cụ thiếu yêu cầu. Mở trạm, vào trang công cụ đó để xem chi tiết hoặc chạy lại CAI_DAT.bat."; $code = 3 }
else { Write-AtOk 'Xong. Mở trạm bằng lối tắt Trạm Tool hoặc TramTool.bat.'; $code = 0 }
if (-not $TatCa) { Wait-AtClose }
exit $code
