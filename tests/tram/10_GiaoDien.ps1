# Giao diện trạm (Trạm 1.7.0): nhóm việc trên trang công cụ (group trong tool.json, cách đoán theo id và risk cho mọi
# action thật), tìm từ ngắn khớp đầu từ, gộp yêu cầu còn thiếu theo cách cài (chạy hàm thật của js\state.js bằng node);
# tool.json lỗi cú pháp không thành "chưa có tool.json", không bị nút Tạo tool.json ghi đè; các phần giao diện mới (kiểm
# tĩnh). Mọi file trong thư mục tạm; không mở trình duyệt, không chạy công cụ.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\Catalog.ps1"
$dir = $TestRoot
$web = Join-Path $HubDir 'web'
function Save-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false)) }
function Read-Web([string]$Rel) { [IO.File]::ReadAllText((Join-Path $web $Rel)) }

Write-KT '1. tool.json: group của action' Cyan
$tools = Join-Path $dir 'tools'
$td = Join-Path $tools 'thu-nhom'
New-Item -ItemType Directory -Path $td -Force | Out-Null
Save-Utf8 (Join-Path $td 'Chay.bat') "@echo off`r`nexit /b 0`r`n"
Save-Utf8 (Join-Path $td 'tool.json') (@{
        id = 'thu-nhom'; name = 'Thử nhóm'; category = 'khac'
        actions = @(
            @{ id = 'kiem-tra'; label = 'Kiểm tra'; file = 'Chay.bat'; risk = 'read-only' }
            @{ id = 'dat-nhom'; label = 'Đặt nhóm'; file = 'Chay.bat'; group = 'tra-lai' }
            @{ id = 'sai-nhom'; label = 'Sai nhóm'; file = 'Chay.bat'; group = 'la-lam' }
        )
    } | ConvertTo-Json -Depth 6)
$cat = Get-HubCatalog -ToolsDir $tools -RootDir $dir
$tool = @($cat | Where-Object { $_.id -eq 'thu-nhom' })[0]
$act = @{}; foreach ($a in $tool.actions) { $act[$a.id] = $a }
Check ($act['dat-nhom'].group -eq 'tra-lai' -and $act['kiem-tra'].group -eq '') 'group khai đúng đi vào danh mục, không khai thì để trống'
Check ($act['sai-nhom'].group -eq '' -and (@($tool.problems) -join ' ') -match "Action 'sai-nhom': group") 'group lạ: bỏ, báo lỗi tool.json'

Write-KT '2. tool.json lỗi cú pháp' Cyan
$tb = Join-Path $tools 'thu-hong'
New-Item -ItemType Directory -Path $tb -Force | Out-Null
Save-Utf8 (Join-Path $tb 'Chay.ps1') "exit 0`r`n"
$broken = '{ "id": "thu-hong", "name": "Hỏng", "summary": "' + ('x' * 400) + '", "path": "bin\da-cai.txt" }'
Save-Utf8 (Join-Path $tb 'tool.json') $broken
$cat = Get-HubCatalog -ToolsDir $tools -RootDir $dir
$bt = @($cat | Where-Object { $_.relDir -like '*thu-hong' })[0]
$msg = @($bt.problems) -join ' '
Check ($bt.status -eq 'broken' -and $bt.manifestBroken -eq $true -and $bt.auto) 'có script: vẫn hiện nút đoán từ script, nhưng ghi rõ tool.json hỏng (không phải "chưa có")'
Check ($msg -match 'lỗi cú pháp' -and $msg.Length -lt 200 -and $msg -notmatch 'xxxxxxxxxx') "lời báo ngắn, không chép cả nội dung file ($($msg.Length) ký tự)"
$thrown = ''
try { [void](New-ToolManifestFile -Tool $bt) } catch { $thrown = $_.Exception.Message }
Check ($thrown -match 'không ghi đè' -and [IO.File]::ReadAllText((Join-Path $tb 'tool.json')) -eq $broken) 'nút Tạo tool.json không ghi đè tool.json đang hỏng'
$te = Join-Path $tools 'thu-hong-trong'
New-Item -ItemType Directory -Path $te -Force | Out-Null
Save-Utf8 (Join-Path $te 'tool.json') '{ "id": '
$et = @(Get-HubCatalog -ToolsDir $tools -RootDir $dir | Where-Object { $_.relDir -like '*thu-hong-trong' })[0]
Check ($et -and $et.status -eq 'broken' -and $et.manifestBroken -eq $true) 'không có script: vẫn hiện ra, đánh dấu tool.json hỏng'

Write-KT '3. Hàm của js\state.js (node)' Cyan
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Skip-Test 'chưa có node để chạy hàm của giao diện' }
else {
    # state.js chỉ cần norm từ core.js (core.js nạp lit-html, cần trình duyệt): thay dòng import bằng hàm norm thật.
    $state = Read-Web 'js\state.js'
    $normLine = @((Read-Web 'js\core.js') -split "`r?`n" | Where-Object { $_ -match '^export const norm = ' })[0]
    Check ([bool]$normLine) 'tìm thấy hàm norm trong core.js'
    $state = $state -replace "(?m)^import \{[^}]*\} from '\./core\.js';", ($normLine.Replace('export const', 'const') + "`nconst api = null; const local = { get: (k, d) => d, set() {} };")
    Save-Utf8 (Join-Path $dir 'state.mjs') $state
    $acts = @()
    foreach ($f in Get-ChildItem -LiteralPath $ToolsDir -Directory) {
        $mf = Join-Path $f.FullName 'tool.json'
        if (-not (Test-Path -LiteralPath $mf)) { continue }
        foreach ($a in @((Read-JsonFile $mf).actions)) { $acts += [ordered]@{ tool = $f.Name; id = $a.id; risk = [string]$a.risk; group = [string]$a.group } }
    }
    Save-Utf8 (Join-Path $dir 'actions.json') (ConvertTo-Json -InputObject @($acts) -Depth 4)
    Save-Utf8 (Join-Path $dir 'chay.mjs') @'
import fs from 'node:fs';
import { actionGroup, ACTION_GROUPS, hayHas, missingFixes } from './state.mjs';
const acts = JSON.parse(fs.readFileSync(new URL('./actions.json', import.meta.url), 'utf8').replace(/^﻿/, ''));
const g = {};
for (const a of acts) g[`${a.tool}/${a.id}`] = actionGroup(a);
const reqs = [
  { id: 'venv', ok: false, label: 'Môi trường', fix: { label: 'Cài', action: 'cai-dat' } },
  { id: 'mo-hinh', ok: false, label: 'Mô hình', fix: { label: 'Cài', action: 'cai-dat' } },
  { id: 'odbc', ok: false, label: 'ODBC', fix: { label: 'Cài ODBC', winget: 'x' } },
  { id: 'gpu', ok: false, optional: true, label: 'Card' },
  { id: 'jet', ok: true, label: 'Jet' },
  { id: 'tay', ok: false, label: 'Cài tay' },
];
const mf = missingFixes({ id: 't' }, reqs).map((f) => f.labels.join('+'));
console.log(JSON.stringify({
  g, ids: ACTION_GROUPS.map((x) => x.id), n: acts.length,
  hay: [hayHas('kiem tra windows admin', 'in'), hayHas('may in lan', 'in'), hayHas('myexcel vietqr', 'excel'), hayHas('wi-fi', 'fi')],
  mf,
}));
'@
    $out = & $node.Source (Join-Path $dir 'chay.mjs') 2>&1
    $ok = $LASTEXITCODE -eq 0
    Check $ok "chạy được hàm của state.js: $(@($out) -join ' ')"
    if ($ok) {
        $r = (@($out) -join '') | ConvertFrom-Json
        $grp = $r.g
        Check ((@($r.ids) -join ',') -eq 'xem,sua,tra-lai,cai-dat,khac') 'đủ 5 nhóm, đúng thứ tự (an toàn trước)'
        $valid = @($grp.PSObject.Properties | Where-Object { $_.Value -notin @($r.ids) })
        Check ($r.n -ge 50 -and -not $valid.Count) "mọi action thật ($($r.n)) đều vào một nhóm"
        $expect = [ordered]@{
            'wifi-fix/menu' = 'khac'; 'wifi-fix/menu-cu' = 'khac'; 'wifi-fix/chan-doan' = 'xem'; 'wifi-fix/ket-noi' = 'sua'
            'fix-win/tuong-lua-khoi-phuc' = 'tra-lai'; 'fix-win/dism-quet' = 'xem'; 'fix-win/sfc' = 'sua'
            'dwg2pdf/cai-dat' = 'cai-dat'; 'dwg2pdf/chuyen-file' = 'xem'
            'toi-uu/bat-lai-dich-vu' = 'tra-lai'; 'toi-uu/mac-dinh-dong-ho' = 'tra-lai'; 'office/tra-lai' = 'tra-lai'
            'myexcelfix/hoan-tac' = 'tra-lai'; 'the-xe-nt/tao' = 'sua'
        }
        foreach ($k in $expect.Keys) {
            $v = $grp.$k
            Check ($v -eq $expect[$k]) "$k vào nhóm $($expect[$k]) (được: $v)"
        }
        Check ((@($r.hay) -join ',') -eq 'False,True,True,True') 'từ 1-2 chữ khớp đầu từ ("in" không khớp "windows", "admin"); từ dài khớp giữa từ'
        Check ((@($r.mf) -join ' | ') -eq 'Môi trường+Mô hình | ODBC | Cài tay') "gộp yêu cầu thiếu theo cách cài, bỏ mục không bắt buộc: $(@($r.mf) -join ' | ')"
    }
}

Write-KT '4. Giao diện (kiểm tĩnh)' Cyan
$parts = Read-Web 'js\parts.js'
$toolRowSrc = [regex]::Match($parts, '(?s)export function toolRow.*?\n}').Value
Check ($toolRowSrc -and $toolRowSrc -notmatch 'runButton' -and $toolRowSrc -match 'trow-go') 'danh mục: dòng công cụ là liên kết, không có nút Chạy mơ hồ'
Check ($parts -match "manifestBroken\) return badge\('danger', 'tool.json bị lỗi'\)") 'nhãn "tool.json bị lỗi" đứng trước "Chưa có tool.json"'
$toolJs = Read-Web 'js\pages\tool.js'
Check ($toolJs -match 'function needPanel' -and $toolJs -match 'missingFixes\(t, d\.reqs\)' -and $toolJs -match 'id="need"') 'trang công cụ: khung Cần cài trước khi chạy, nút cài cạnh từng thứ'
Check ($toolJs -match 'const others = actions\.filter\(\(a\) => a !== a0\)' -and $toolJs -match 'ACTION_GROUPS\.map') 'việc chính không lặp trong danh sách; việc khác theo nhóm'
Check ($toolJs -match 'watchJob\(r\.jobId\)' -and $toolJs -match "addEventListener\('focus'") 'nút Cài: theo dõi việc cài; cài bằng winget thì quay lại trạm tự kiểm tra lại'
Check ($toolJs -match 't\.manifestBroken \? nothing') 'tool.json hỏng: không có nút Tạo tool.json'
$run = Read-Web 'js\run.js'
Check ($run -match 'async function confirmMissing' -and $run -match 'if \(!await confirmMissing\(t, a\)\) return;' -and $run -match 'f\.fix\.action === a\.id') 'bấm Chạy khi thiếu yêu cầu: hỏi trước, trừ chính việc cài'
$jobs = Read-Web 'js\jobs.js'
Check ($jobs -match "if \(t && \(t\.requires \|\| \[\]\)\.length\) loadReqs\(t, true\)") 'việc xong: kiểm lại yêu cầu của công cụ'
$homeJs = Read-Web 'js\pages\home.js'
Check (([regex]::Matches($homeJs, 'class="page"')).Count -eq 1 -and $homeJs -match '\$\{q \? findResults\(q\) : homeBody\(\)\}') 'Tổng quan: một khung trang cho cả lúc tìm (ô tìm không mất con trỏ)'
Check ($homeJs -match "act: 'Xem cách cài'" -and $homeJs -notmatch "act: 'Cài'") 'Cần chú ý: chữ trên nút nói đúng việc nút làm'
$nav = Read-Web 'js\pages\nav.js'
Check ($nav -notmatch 'simple-toggle' -and $nav -match 'p\.bottom') 'thanh bên: bỏ công tắc Đơn giản, Cài đặt ở chân'
$ui = Read-Web 'js\ui.js'
$srv = [IO.File]::ReadAllText((Join-Path $HubDir 'TramTool.ps1'))
Check ($ui -match 'export const launcherName' -and $srv -match "launcher = \`$\(if \(Test-Path -LiteralPath \(Join-Path \`$RootDir 'TramTool\.exe'\)\)") 'lời nhắc mở lại trạm theo file thật (TramTool.exe ở bản portable)'
$allJs = @(Get-ChildItem -LiteralPath $web -Recurse -File -Include *.js, *.css, *.html | Where-Object { $_.FullName -notlike '*\vendor\*' })
$dash = @($allJs | Where-Object { [IO.File]::ReadAllText($_.FullName) -match '[–—]' } | ForEach-Object { $_.Name })
Check (-not $dash.Count) "chữ giao diện không có gạch dài: $($dash -join ', ')"

Complete-Test
