<#
  Trạm Tool - trả dịch vụ, giá trị registry về như trước một lần chạy công cụ.
  Trạm ghi trạng thái các mục công cụ khai báo (probes trong tool.json) ngay trước khi chạy, vào
  data\snapshots\TrangThai_<lần chạy>.json. Script này (quyền Admin) so với hiện tại và trả lại các mục đã khác.
    TraLaiTrangThai.ps1 -Snapshot <file TrangThai_*.json>
  Mã thoát: 0 = xong (hoặc không có gì để trả lại), 1 = lỗi, 2 = thiếu quyền Admin, 3 = trả lại được một phần.
#>
param([string]$Snapshot = '')

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
. (Join-Path $PSScriptRoot '..\lib\Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\AnToan.ps1')
$Host.UI.RawUI.WindowTitle = 'Trạm Tool - trả lại trạng thái trước khi chạy'

Write-AtHead 'TRẢ LẠI TRẠNG THÁI TRƯỚC KHI CHẠY CÔNG CỤ'
if (-not $Snapshot -or -not (Test-Path -LiteralPath $Snapshot -PathType Leaf) -or -not (Test-SnapshotFileName (Split-Path $Snapshot -Leaf))) {
    Write-AtBad 'Không thấy file trạng thái đã ghi (có thể đã xoá cùng lịch sử).'
    Wait-AtClose
    exit 1
}
if (-not (Test-IsAdmin)) {
    Write-AtBad 'Cần quyền Admin để đổi dịch vụ và registry của máy.'
    Wait-AtClose
    exit 2
}

try { $snap = Read-JsonFile $Snapshot } catch { Write-AtBad "File trạng thái hỏng: $($_.Exception.Message)"; Wait-AtClose; exit 1 }
$when = try { [datetime]::Parse([string]$snap.time).ToString('HH:mm dd/MM/yyyy') } catch { [string]$snap.time }
Write-AtInfo "Công cụ: $($snap.toolName) > $($snap.actionLabel)"
Write-AtInfo "Trạng thái ghi lúc $when, ngay trước khi chạy."
Write-Host ''

$items = @($snap.items)
$todo = @(Compare-RunSnapshot -Path $Snapshot | Where-Object { $_.changed } | ForEach-Object { , @($_, $items[$_.index]) })
if (-not $todo.Count) {
    Write-AtOk 'Không mục nào khác so với trước khi chạy: không có gì để trả lại.'
    Wait-AtClose
    exit 0
}

$ok = 0; $bad = 0
foreach ($pair in $todo) {
    $row = $pair[0]; $item = $pair[1]
    $text = '{0}: {1} -> {2}' -f $row.label, $row.after, $row.before
    if (-not $row.restorable) { Write-AtWarn "$text (bỏ qua: $($row.note))"; $bad++; continue }
    try {
        $r = Restore-SnapshotItem -Item $item
        if ($r -eq 'same') { Write-AtInfo "$($row.label): đã như trước." } else { Write-AtOk $text }
        $ok++
    } catch {
        Write-AtBad "$text, lỗi: $($_.Exception.Message.Trim())"
        $bad++
    }
}

Write-Host ''
$code = if (-not $bad) { 0 } elseif ($ok) { 3 } else { 1 }
switch ($code) {
    0 { Write-AtOk "Đã trả lại $ok mục như trước khi chạy." }
    3 { Write-AtWarn "Trả lại được $ok mục, $bad mục chưa được (xem các dòng [X], [!] ở trên)." }
    1 { Write-AtBad 'Chưa trả lại được mục nào (xem các dòng ở trên).' }
}
Write-AtInfo 'Một số thay đổi dịch vụ có hiệu lực sau khi khởi động lại máy.'
Wait-AtClose
exit $code
