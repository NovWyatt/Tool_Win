# Nhật ký hoàn tác (lib\NhatKy.ps1) với registry thật nhưng chỉ trong HKCU\Software\TramToolTest.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
. "$PSScriptRoot\_Nap.ps1"
$base = 'HKCU:\Software\TramToolTest'
Clear-TestRegistry
$path = "$base\MayInLan\RPC"

Write-Host '== A. khoá và giá trị chưa có: công cụ tạo, hoàn tác xoá sạch cả khoá đã tạo'
$j = New-Journal 'thu-a' 'Thử A'
Check (Set-RegistryDwordWithUndo $j $path 'GiaTriThu' 1 'Đặt GiaTriThu = 1') 'đặt GiaTriThu = 1'
Check (Set-RegistryDwordWithUndo $j $path 'GiaTriThu' 1 'Đặt GiaTriThu = 1') 'đặt lại cùng giá trị: báo đúng sẵn'
Check ($j.Data.changes.Count -eq 1 -and (Get-RegValue $path 'GiaTriThu') -eq 1) "nhật ký có 1 thay đổi ($($j.Data.changes.Count)), giá trị = 1"
$ea = @(Get-JournalEntries | Where-Object { $_.Data.mode -eq 'thu-a' })[0]
$kc = (@($ea.Data.changes)[0].keysCreated) -join ' > '
Check ($kc -eq "$base > $base\MayInLan > $base\MayInLan\RPC") "ghi các khoá đã tạo: $kc"
[void](Invoke-UndoJournal $ea -DryRun)
Check ((Get-RegValue $path 'GiaTriThu') -eq 1) 'hoàn tác chạy thử: không đổi gì'
$r = Invoke-UndoJournal $ea
Check ($r.Ok -eq 1 -and $r.Failed -eq 0 -and $r.Skipped -eq 0) "hoàn tác: ok=$($r.Ok) lỗi=$($r.Failed) bỏ qua=$($r.Skipped)"
Check (-not (Test-Path $base)) 'xoá cả các khoá công cụ đã tạo'

Write-Host '== B. giá trị đã có (5) -> đổi 0; hoàn tác trả lại 5, giữ khoá'
[void](New-Item -Path $path -Force)
New-ItemProperty -Path $path -Name 'CoSan' -Value 5 -PropertyType DWord -Force | Out-Null
Start-Sleep -Seconds 1   # tên file nhật ký theo giây
$j = New-Journal 'thu-b' 'Thử B'
Check ((Set-RegistryDwordWithUndo $j $path 'CoSan' 0 'Đặt CoSan = 0') -and (Get-RegValue $path 'CoSan') -eq 0) 'đổi CoSan 5 -> 0'
$eb = @(Get-JournalEntries | Where-Object { $_.Data.mode -eq 'thu-b' })[0]
$r = Invoke-UndoJournal $eb
Check ($r.Ok -eq 1 -and $r.Failed -eq 0 -and (Get-RegValue $path 'CoSan') -eq 5) "hoàn tác trả lại 5: $(Get-RegValue $path 'CoSan')"
Check (Test-Path $path) 'giữ khoá có sẵn'
$u = @(Get-JournalEntries | Where-Object { $_.Data.mode -eq 'thu-b' })[0].Data.undone
Check ($u -and $u.ok -eq 1 -and $u.failed -eq 0) 'nhật ký đánh dấu đã hoàn tác'

Clear-TestRegistry
Check (-not (Test-Path $base)) 'dọn khoá thử'
Complete-Test
