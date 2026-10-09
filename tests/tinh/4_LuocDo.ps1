# tool.json đúng lược đồ hub\schema\tool.schema.json (Ajv), file JavaScript của giao diện Trạm không lỗi cú pháp.
# Cần Node.js; lược đồ cần thêm thư viện Ajv: cd tests && npm install (thiếu thì bỏ qua phần đó).
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$node = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $node) { Skip-Test 'máy không có Node.js (node.exe)'; Complete-Test }

$testsDir = Split-Path $PSScriptRoot -Parent
if (Test-Path -LiteralPath (Join-Path $testsDir 'node_modules\ajv')) {
    $out = @(& $node.Source (Join-Path $PSScriptRoot '_luocdo.cjs') $RepoRoot $testsDir 2>&1)
    $lines = @($out | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^(OK|FAIL) ' })
    Check ($lines.Count -ge 10) "kiểm được $($lines.Count) tool.json $(if (-not $lines.Count) { $out -join ' ' })"
    foreach ($l in $lines) {
        $id = ($l -split ' ', 3)[1]
        Check ($l -like 'OK *') "tools\$id\tool.json đúng lược đồ $(if ($l -like 'FAIL *') { ($l -split ' ', 3)[2] })"
    }
} else {
    Skip-Test 'chưa cài Ajv để kiểm lược đồ tool.json: cd tests && npm install'
}

# node --check từng file JavaScript (chép sang .mjs để node đọc như ES module)
$js = @(Get-ChildItem -LiteralPath (Join-Path $HubDir 'web') -Recurse -File | Where-Object { $_.Extension -in '.js', '.mjs' -and $_.FullName -notlike '*\vendor\*' })
Check ($js.Count -ge 5) "tìm thấy $($js.Count) file JavaScript trong hub\web"
foreach ($f in $js) {
    $tmp = Join-Path $TestRoot (([IO.Path]::GetFileNameWithoutExtension($f.Name)) + '_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.mjs')
    Copy-Item -LiteralPath $f.FullName -Destination $tmp
    $o = @(& $node.Source --check $tmp 2>&1)
    Check ($LASTEXITCODE -eq 0) ("{0} {1}" -f $f.FullName.Substring($RepoRoot.Length + 1), (@($o | Select-Object -First 4) -join ' '))
}

Complete-Test
