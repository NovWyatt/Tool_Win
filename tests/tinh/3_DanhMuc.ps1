# Danh mục của Trạm: mọi tools\<id>\tool.json đọc được, không có lỗi khai báo (file action có thật, kiểu, rủi ro,
# flag, restorePoint, hướng dẫn), id không trùng, nhóm có trong hub\categories.json. Chỉ đọc.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\Catalog.ps1"; . "$HubDir\lib\Launcher.ps1"

$manifests = @(Get-ChildItem -LiteralPath $ToolsDir -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'tool.json') })
foreach ($m in $manifests) {
    $ok = $true; $why = ''
    try { [void]([IO.File]::ReadAllText((Join-Path $m.FullName 'tool.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json) } catch { $ok = $false; $why = $_.Exception.Message }
    Check $ok "tools\$($m.Name)\tool.json là JSON hợp lệ $why"
}

$cat = Get-HubCatalog -ToolsDir $ToolsDir -RootDir $RepoRoot   # không bọc @(): hàm trả , mảng
Check (@($cat).Count -eq $manifests.Count) "danh mục có $(@($cat).Count) công cụ, thư mục tools có $($manifests.Count) tool.json"
$ids = @($cat | ForEach-Object { $_.id })
$dup = @($ids | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
Check ($dup.Count -eq 0) "id không trùng ($($dup -join ', '))"
$cats = @(Get-HubCategories -HubDir $HubDir | ForEach-Object { $_.id })
foreach ($t in $cat) {
    Check (@($t.problems).Count -eq 0) "$($t.id): không có lỗi khai báo ($(@($t.problems) -join ' | '))"
    Check ($cats -contains $t.category) "$($t.id): nhóm '$($t.category)' có trong categories.json"
    $missing = @($t.actions | Where-Object { -not $_.exists } | ForEach-Object { "$($_.id)=$($_.file)" })
    Check ($missing.Count -eq 0) "$($t.id): file của mọi action đều có ($($missing -join ', '))"
}

# Quy ước selfElevates: cửa sổ đầu đợi cửa sổ Admin (-Wait -PassThru) và trả đúng mã thoát của nó, để trạm (và người
# bấm đúp) biết công cụ chạy xong ra sao. Script tự mở bản Admin rồi thoát ngay thì Lịch sử luôn ghi "Xong".
foreach ($t in $cat) {
    foreach ($a in @($t.actions | Where-Object { $_.selfElevates -and $_.exists })) {
        $text = [IO.File]::ReadAllText((Join-Path $t.dir $a.file), [Text.Encoding]::UTF8)
        $waits = $text -match '-Verb\s+RunAs[^\r\n]*-Wait[^\r\n]*-PassThru' -and $text -match 'exit\s+\$p\.ExitCode'
        Check $waits "$($t.id)/$($a.id): tự nâng quyền thì đợi cửa sổ Admin và trả mã thoát của nó ($($a.file))"
    }
}

# Công cụ khai output kết quả JSON (ketQua) phải có file ghi theo chuẩn: tìm chữ 'tramtool.ketqua/1' trong mã nguồn.
foreach ($t in $cat) {
    if (-not @(@($t.outputs) | Where-Object { Get-Prop $_ 'ketQua' $false }).Count) { continue }
    $src = @(Get-ChildItem -LiteralPath $t.dir -Recurse -File -Include *.ps1, *.bat, *.cmd, *.py -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\(tests|\.venv|node_modules|LuuTru)\\' } |
            Where-Object { [IO.File]::ReadAllText($_.FullName) -match 'tramtool\.ketqua/1' })
    Check ($src.Count -gt 0) "$($t.id): khai outputs ketQua và có mã ghi theo chuẩn tramtool.ketqua/1"
}

Complete-Test
