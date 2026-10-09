# Bài thử GioChuKySo.ps1 bằng giả lập: máy chủ giờ (độ lệch), múi giờ, dịch vụ (bảng trong bộ nhớ), sc.exe, w32tm,
# tzutil, đặt giờ, đầu đọc thẻ, Device Manager, chứng thư, phần mềm đã cài, câu trả lời. Không đổi máy thật.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\Catalog.ps1"; . "$HubDir\lib\KetQua.ps1"
$toolDir = Join-Path $ToolsDir 'gio-chu-ky-so'
$env:TRAMTOOL_GIOCHUKYSO_TEST = '1'
. "$toolDir\GioChuKySo.ps1"
$ChayThu = $false; $KhongDung = $true; $MuiGioVN = $false
$script:ResultDir = New-TestDir 'gck_ketqua'
$script:StateFile = Join-Path $script:ResultDir 'TrangThaiGoc_GioChuKySo_TEST.json'
$manifest = [IO.File]::ReadAllText((Join-Path $toolDir 'tool.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$validLevels = 'loi', 'canh-bao', 'thong-tin', 'ok'

# ---- giả lập
$script:Calls = New-Object System.Collections.ArrayList
$script:NtpQueue = New-Object System.Collections.Queue
$script:Answers = New-Object System.Collections.Queue
function Ntp([double]$Off) { return [pscustomobject]@{ Ok = $true; Offset = $Off; Source = 'gia (NTP)' } }
function Get-NtpOffset { if ($script:NtpQueue.Count -gt 1) { return $script:NtpQueue.Dequeue() } return $script:NtpQueue.Peek() }
function Get-ZoneInfo { return $script:Zone }
function Get-SvcConfig {
    param([string]$Name)
    if (-not $script:Svc.ContainsKey($Name)) { return [pscustomobject]@{ Exists = $false; Start = -1; Running = $false } }
    return [pscustomobject]@{ Exists = $true; Start = $script:Svc[$Name].Start; Running = $script:Svc[$Name].Running }
}
function Get-W32Params { return [pscustomobject]@{ Type = $script:W32.Type; NtpServer = $script:W32.NtpServer } }
function Get-SmartCardReaders { return $script:Readers }
function Get-TokenDevices { return , @($script:Devices) }
function Get-SigningCerts { return , @($script:Certs) }
function Get-SigningApps { return , @($script:Apps) }
function Test-IsAdmin { return $true }
function Start-Sleep { }
function Read-YesNo { param([string]$Question, [bool]$Default = $false) if ($script:Answers.Count) { return $script:Answers.Dequeue() } return $Default }
function Invoke-Sc {
    param([string[]]$Arguments)
    [void]$script:Calls.Add('sc ' + ($Arguments -join ' '))
    $n = $Arguments[1]
    if ($script:ScFails -contains $n) { return [pscustomobject]@{ Code = 5; Output = 'Access is denied.' } }
    $script:Svc[$n].Start = @{ auto = 2; demand = 3; disabled = 4 }[$Arguments[3]]
    return [pscustomobject]@{ Code = 0; Output = 'SUCCESS' }
}
function Invoke-W32tm {
    param([string[]]$Arguments)
    [void]$script:Calls.Add('w32tm ' + ($Arguments -join ' '))
    if ($Arguments[0] -eq '/config' -and $Arguments -contains '/syncfromflags:manual') { $script:W32.Type = 'NTP'; $script:W32.NtpServer = 'time.windows.com,0x9' }
    return [pscustomobject]@{ Code = 0; Output = 'The command completed successfully.' }
}
function Start-Svc {
    param([string]$Name, [switch]$Restart)
    [void]$script:Calls.Add($(if ($Restart) { "restart $Name" } else { "start $Name" }))
    if ($script:StartFails -contains $Name) { return $false }
    $script:Svc[$Name].Running = $true
    return $true
}
function Set-ZoneId { param([string]$Id) [void]$script:Calls.Add("tzutil $Id"); $script:Zone = [pscustomobject]@{ Id = $Id; Name = "ten $Id"; Offset = 7 }; return [pscustomobject]@{ Code = 0; Output = '' } }
function Set-ClockAdjust { param([double]$Seconds) [void]$script:Calls.Add("adjust $Seconds"); return $true }
function Set-W32Params { param([string]$Type, [string]$NtpServer) [void]$script:Calls.Add("w32params $Type $NtpServer"); $script:W32.Type = $Type; $script:W32.NtpServer = $NtpServer; return $true }

function Cert([string]$Ten, [int]$TuNgay, [int]$DenNgay, [bool]$ChuoiOk = $true, [string[]]$ChuoiLoi = @()) {
    return [pscustomobject]@{ Ten = $Ten; NhaCungCap = 'CA GIA'; TuNgay = (Get-Date).AddDays($TuNgay); DenNgay = (Get-Date).AddDays($DenNgay); Thumbprint = 'AB'; ChuoiOk = $ChuoiOk; ChuoiLoi = $ChuoiLoi }
}
function Reset-Case {
    $script:Calls.Clear(); $script:NtpQueue.Clear(); $script:Answers.Clear(); $script:Findings.Clear()
    $script:NtpQueue.Enqueue((Ntp 0.3))
    $script:Zone = [pscustomobject]@{ Id = 'SE Asia Standard Time'; Name = '(UTC+07:00) Bangkok, Hanoi, Jakarta'; Offset = 7 }
    $script:Svc = @{ W32Time = @{ Start = 3; Running = $true }; SCardSvr = @{ Start = 3; Running = $false }; CertPropSvc = @{ Start = 3; Running = $false } }
    $script:W32 = @{ Type = 'NTP'; NtpServer = 'time.windows.com,0x9' }
    $script:Readers = [pscustomobject]@{ Readers = @('Token GIA 0'); Error = '' }
    $script:Devices = @([pscustomobject]@{ Name = 'Token GIA'; Status = 'OK'; Class = 'SmartCardReader' })
    $script:Certs = @(Cert 'NGUOI THU NGHIEM' -100 200)
    $script:Apps = @('VNPT-CA Plugin (gia)')
    $script:ScFails = @(); $script:StartFails = @()
    Get-ChildItem -LiteralPath $script:ResultDir -File -ErrorAction SilentlyContinue | Remove-Item -Force
}
function Codes { return @($script:Findings | ForEach-Object { $_.ma }) }
function Find([string]$Ma) { return @($script:Findings | Where-Object { $_.ma -eq $Ma })[0] }
function Last($x) { return @($x)[-1] }
function Saved { return ([IO.File]::ReadAllText($script:StateFile) | ConvertFrom-Json) }

Write-KT '1. Hàm phụ' Cyan
$want = New-Object DateTime 2026, 10, 9, 8, 30, 15, ([DateTimeKind]::Utc)
$sec = [uint64](($want - (New-Object DateTime 1900, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc))).TotalSeconds)
$b = New-Object byte[] 48
for ($k = 0; $k -lt 4; $k++) { $b[40 + $k] = [byte](($sec -shr (8 * (3 - $k))) -band 0xFF) }
$b[44] = 0x80   # phần lẻ 0,5 giây
$got = ConvertFrom-NtpStamp $b 40
Check ($got -eq $want.AddMilliseconds(500)) "đọc mốc thời gian NTP ($($got.ToString('o')))"
Check ((Format-Lech 0.4) -eq 'lệch dưới 1 giây' -and (Format-Lech 45) -eq 'chậm 45 giây' -and (Format-Lech -400) -eq 'nhanh 7 phút' -and (Format-Lech 90000) -eq 'chậm 25 giờ' -and (Format-Lech -259200) -eq 'nhanh 3 ngày') "viết độ lệch ra chữ ($(Format-Lech -400); $(Format-Lech 90000))"

Write-KT '2. Kiểm tra: máy ổn' Cyan
Reset-Case
Invoke-AllChecks 6>$null
$c = Codes
Check (($c -join ',') -eq 'GIO_DUNG,MUI_GIO_VN,TOKEN_DANG_CAM,CHUNG_THU_CON_HAN,PHAN_MEM_KY_SO') "máy ổn: chỉ phát hiện ổn và thông tin ($($c -join ','))"
Check (-not @($script:Findings | Where-Object { $_.mucDo -in 'loi', 'canh-bao' }).Count) 'máy ổn: không lỗi, không cảnh báo'

Write-KT '3. Kiểm tra: máy có đủ thứ hỏng' Cyan
Reset-Case
$script:NtpQueue.Clear(); $script:NtpQueue.Enqueue((Ntp -400))
$script:Zone = [pscustomobject]@{ Id = 'Pacific Standard Time'; Name = '(UTC-08:00) Pacific Time'; Offset = -8 }
$script:Svc.W32Time = @{ Start = 4; Running = $false }; $script:W32.Type = 'NoSync'
$script:Svc.SCardSvr = @{ Start = 4; Running = $false }; $script:Svc.CertPropSvc = @{ Start = 4; Running = $false }
$script:Devices = @([pscustomobject]@{ Name = 'Token GIA'; Status = 'Error'; Class = 'SmartCardReader' })
$script:Readers = [pscustomobject]@{ Readers = @(); Error = 'DICH_VU' }
$script:Certs = @((Cert 'CONG TY GIA' -400 -5), (Cert 'NGUOI SAP HET' -300 10), (Cert 'NGUOI CHUA HIEU LUC' 2 700), (Cert 'NGUOI THIEU GOC' -10 300 $false @('PartialChain')))
$script:Apps = @()
Invoke-AllChecks 6>$null
$c = Codes
foreach ($m in 'GIO_LECH_NHIEU', 'MUI_GIO_KHAC', 'DICH_VU_GIO_TAT', 'DONG_BO_GIO_TAT', 'DICH_VU_SMART_CARD_TAT', 'DICH_VU_CERTPROP_TAT', 'TOKEN_LOI_DRIVER', 'KHONG_THAY_TOKEN', 'CHUNG_THU_HET_HAN', 'CHUNG_THU_SAP_HET_HAN', 'CHUNG_THU_CHUA_HIEU_LUC', 'CHUNG_THU_THIEU_GOC', 'KHONG_THAY_PHAN_MEM_KY_SO') {
    Check ($c -contains $m) "có $m"
}
$f = Find 'GIO_LECH_NHIEU'
Check ($f.mucDo -eq 'loi' -and $f.tieuDe -match 'nhanh 7 phút' -and $f.chayTiep.action -eq 'sua-gio') "lệch 400 giây: lỗi, nói rõ máy nhanh, gợi ý Sửa giờ ($($f.tieuDe))"
$f = Find 'DICH_VU_SMART_CARD_TAT'
Check ($f.mucDo -eq 'loi' -and $f.chayTiep.congCu -eq 'gio-chu-ky-so' -and $f.chayTiep.action -eq 'sua-token') 'Smart Card tắt: lỗi, gợi ý Sửa dịch vụ token'
Check ((Find 'DICH_VU_CERTPROP_TAT').mucDo -eq 'canh-bao') 'Certificate Propagation tắt: cảnh báo'
Check ((Find 'KHONG_THAY_TOKEN').chiTiet -match 'Device Manager') 'Device Manager có token mà dịch vụ không thấy: nói rõ'
Check ((Find 'CHUNG_THU_CHUA_HIEU_LUC').mucDo -eq 'loi' -and (Find 'CHUNG_THU_CHUA_HIEU_LUC').chayTiep.action -eq 'sua-gio') 'chứng thư chưa tới ngày hiệu lực: lỗi, gợi ý Sửa giờ'
Check ((Find 'CHUNG_THU_SAP_HET_HAN').tieuDe -match '10 ngày') "sắp hết hạn: nói số ngày ($((Find 'CHUNG_THU_SAP_HET_HAN').tieuDe))"
Check ((Find 'CHUNG_THU_THIEU_GOC').chiTiet -match 'PartialChain') 'thiếu chứng thư gốc: ghi trạng thái chuỗi'

Write-KT '4. Kiểm tra: các trường hợp khác' Cyan
Reset-Case; $script:NtpQueue.Clear(); $script:NtpQueue.Enqueue((Ntp 45))
$script:Zone = [pscustomobject]@{ Id = 'North Asia Standard Time'; Name = '(UTC+07:00) Krasnoyarsk'; Offset = 7 }
$script:W32.Type = 'NT5DS'
$script:Certs = @((Cert 'NGUOI THU NGHIEM' -800 -20), (Cert 'NGUOI THU NGHIEM' -20 345))
Invoke-AllChecks 6>$null; $c = Codes
Check ((Find 'GIO_LECH').mucDo -eq 'canh-bao') 'lệch 45 giây: cảnh báo'
Check ((Find 'MUI_GIO_KHAC_TEN').mucDo -eq 'thong-tin' -and $c -notcontains 'MUI_GIO_KHAC') 'múi giờ khác tên nhưng cùng UTC+7: chỉ thông tin'
Check ($c -contains 'MAY_TRONG_DOMAIN') 'máy trong domain: thông tin'
Check ($c -contains 'CHUNG_THU_CU_HET_HAN' -and $c -notcontains 'CHUNG_THU_HET_HAN' -and $c -contains 'CHUNG_THU_CON_HAN') 'chứng thư cũ hết hạn đã có chứng thư mới: chỉ thông tin'
Reset-Case; $script:NtpQueue.Clear(); $script:NtpQueue.Enqueue([pscustomobject]@{ Ok = $false; Offset = 0; Source = '' }); $script:Certs = @(); $script:Readers = [pscustomobject]@{ Readers = @(); Error = 'KHONG_CO' }; $script:Devices = @()
Invoke-AllChecks 6>$null; $c = Codes
Check ($c -contains 'KHONG_DO_DUOC_GIO' -and $c -contains 'KHONG_CO_CHUNG_THU' -and $c -contains 'KHONG_THAY_TOKEN') "không mạng, không chứng thư, không token: chỉ thông tin ($($c -join ','))"
Check ((Find 'KHONG_THAY_TOKEN').chiTiet -match 'Chưa cắm token') 'không có thiết bị: gợi ý cắm token'
Reset-Case; $script:Svc.Remove('SCardSvr')
Invoke-AllChecks 6>$null
Check ((Find 'DICH_VU_TOKEN_KHONG_CO').chayTiep.congCu -eq 'fix-win') 'thiếu dịch vụ Smart Card: gợi ý Sửa lỗi Windows'

Write-KT '5. File kết quả' Cyan
Reset-Case; $script:NtpQueue.Clear(); $script:NtpQueue.Enqueue((Ntp 300)); $script:Svc.SCardSvr.Start = 4
$code = Last (Invoke-Mode 'kiem-tra' 6>$null)
$files = @(Get-ChildItem -LiteralPath $script:ResultDir -Filter 'KetQua_GioChuKySo_*.json')
Check ($code -eq 0 -and $files.Count -eq 1) "Kiểm tra: mã 0, một file kết quả ($($files.Count))"
$j = [IO.File]::ReadAllText($files[0].FullName) | ConvertFrom-Json
Check ($j.chuan -eq 'tramtool.ketqua/1' -and $j.congCu -eq 'gio-chu-ky-so' -and $j.cheDo -eq 'kiem-tra' -and $j.trangThai -eq 'xong' -and $j.ma -eq 'CO_CANH_BAO') 'đầu file theo chuẩn'
Check (@($j.phatHien)[0].mucDo -eq 'loi' -and @($j.phatHien)[-1].mucDo -in 'ok', 'thong-tin') 'lỗi lên đầu'
Check ($j.tomTat.loi -eq 2 -and $j.tomTat.canhBao -eq 0) "tóm tắt: 2 lỗi (giờ, Smart Card) ($($j.tomTat.loi), $($j.tomTat.canhBao))"
$hr = Read-RunResult -Path $files[0].FullName
Check ($hr -and @($hr.phatHien | Where-Object { $_.chayTiep }).Count -eq 2) 'trạm đọc được, giữ hai nút gợi ý'

Write-KT '6. Sửa giờ' Cyan
Reset-Case
$script:Svc.W32Time = @{ Start = 4; Running = $false }; $script:W32.Type = 'NoSync'; $script:W32.NtpServer = 'cu.vi.du,0x1'
$script:Zone = [pscustomobject]@{ Id = 'Pacific Standard Time'; Name = '(UTC-08:00) Pacific Time'; Offset = -8 }
$script:NtpQueue.Clear(); foreach ($o in 400, 400, 0.2) { $script:NtpQueue.Enqueue((Ntp $o)) }
$code = Last (Invoke-SuaGio -SetZone $true 6>$null)
Check ($code -eq 0) "đủ bước: mã 0 ($code)"
Check ($script:Svc.W32Time.Start -eq 3 -and $script:Svc.W32Time.Running) 'Windows Time: Thủ công, đang chạy'
Check ($script:W32.Type -eq 'NTP' -and $script:Zone.Id -eq 'SE Asia Standard Time') 'bật đồng bộ, múi giờ Việt Nam'
Check ($script:Calls -contains 'adjust 400' -and @($script:Calls | Where-Object { $_ -eq 'w32tm /resync /force' }).Count -eq 2) 'đồng bộ xong vẫn lệch: đặt giờ theo máy chủ giờ rồi đồng bộ lại'
$s = Saved
Check ($s.dichVu.W32Time.start -eq 4 -and $s.dongBoGio.type -eq 'NoSync' -and $s.dongBoGio.ntpServer -eq 'cu.vi.du,0x1' -and $s.muiGio -eq 'Pacific Standard Time') 'lưu giá trị cũ trước khi đổi'
$script:NtpQueue.Clear(); $script:NtpQueue.Enqueue((Ntp 0.1))
[void](Invoke-SuaGio -SetZone $true 6>$null)
$s = Saved
Check ($s.dichVu.W32Time.start -eq 4 -and $s.dongBoGio.type -eq 'NoSync') 'sửa lần hai: giữ giá trị của lần đầu'

Reset-Case; $script:NtpQueue.Clear(); $script:NtpQueue.Enqueue((Ntp 0.2))
$code = Last (Invoke-SuaGio -SetZone $true 6>$null)
Check ($code -eq 0 -and -not ($script:Calls -match '^(sc|tzutil|adjust|w32tm /config)') -and $script:Calls -contains 'w32tm /resync /force') 'máy đúng sẵn: chỉ đồng bộ lại'
Reset-Case; $script:Svc.W32Time.Start = 4; $script:W32.Type = 'NoSync'
$code = Last (Invoke-SuaGio -DryRun -SetZone $true 6>$null)
Check ($code -eq 0 -and $script:Calls.Count -eq 0 -and -not (Test-Path $script:StateFile)) 'chạy thử: không đổi, không lưu'
Reset-Case; $script:Svc.W32Time.Start = 4; $script:Answers.Enqueue($false)
$code = Last (Invoke-SuaGio -Ask 6>$null)
Check ($code -eq 2 -and $script:Calls.Count -eq 0 -and $script:Svc.W32Time.Start -eq 4) 'hỏi lại, không đồng ý: mã 2, không đổi'
Reset-Case; $script:Zone = [pscustomobject]@{ Id = 'Pacific Standard Time'; Name = 'x'; Offset = -8 }
[void](Invoke-SuaGio -SetZone $false 6>$null)
Check ($script:Zone.Id -eq 'Pacific Standard Time' -and -not ($script:Calls -match '^tzutil')) 'không đánh dấu múi giờ: không đổi múi giờ'
Reset-Case; $script:W32.Type = 'NT5DS'; $script:NtpQueue.Clear(); $script:NtpQueue.Enqueue((Ntp 400))
$code = Last (Invoke-SuaGio -SetZone $true 6>$null)
Check ($code -eq 1 -and -not ($script:Calls -match '^(adjust|w32tm /config)')) "máy trong domain còn lệch: không tự đặt giờ, không đổi cấu hình, mã 1 ($code)"
Reset-Case; $script:NtpQueue.Clear(); $script:NtpQueue.Enqueue([pscustomobject]@{ Ok = $false; Offset = 0; Source = '' })
$code = Last (Invoke-SuaGio 6>$null)
Check ($code -eq 3) "không đo lại được: mã 3 ($code)"
Reset-Case; $script:Svc.W32Time.Start = 4; $script:ScFails = @('W32Time')
$code = Last (Invoke-SuaGio 6>$null)
Check ($code -eq 1 -and -not ($script:Calls -match 'resync')) 'không bật được dịch vụ: mã 1, dừng ở đó'
Reset-Case; $script:Svc.Remove('W32Time')
Check ((Last (Invoke-SuaGio 6>$null)) -eq 1) 'không có dịch vụ Windows Time: mã 1'

Write-KT '7. Sửa dịch vụ token' Cyan
Reset-Case; $script:Svc.SCardSvr.Start = 4; $script:Svc.CertPropSvc.Start = 4
$code = Last (Invoke-SuaToken 6>$null)
Check ($code -eq 0 -and $script:Svc.SCardSvr.Start -eq 3 -and $script:Svc.CertPropSvc.Start -eq 3 -and $script:Svc.SCardSvr.Running -and $script:Svc.CertPropSvc.Running) 'hai dịch vụ tắt: Thủ công, đang chạy, mã 0'
$s = Saved
Check ($s.dichVu.SCardSvr.start -eq 4 -and $s.dichVu.CertPropSvc.start -eq 4 -and -not $s.dongBoGio) 'lưu kiểu khởi động cũ, không lưu phần giờ'
Reset-Case; $script:Svc.CertPropSvc.Running = $true
[void](Invoke-SuaToken 6>$null)
Check ($script:Calls -contains 'restart CertPropSvc' -and -not (Test-Path $script:StateFile)) 'Certificate Propagation đang chạy: chạy lại; không tắt gì thì không lưu file'
Reset-Case; $script:StartFails = @('SCardSvr')
Check ((Last (Invoke-SuaToken 6>$null)) -eq 0) 'Smart Card chưa chạy ngay (chưa cắm token): vẫn mã 0'
Reset-Case; $script:Svc.SCardSvr.Start = 4; $script:Svc.CertPropSvc.Start = 4; $script:ScFails = @('CertPropSvc')
Check ((Last (Invoke-SuaToken 6>$null)) -eq 3) 'một dịch vụ không bật được: mã 3'
Reset-Case; $script:Svc.SCardSvr.Start = 4
$code = Last (Invoke-SuaToken -DryRun 6>$null)
Check ($code -eq 0 -and $script:Calls.Count -eq 0 -and $script:Svc.SCardSvr.Start -eq 4) 'chạy thử: không đổi'

Write-KT '8. Trả lại như trước khi sửa' Cyan
Reset-Case
$script:Svc.W32Time = @{ Start = 4; Running = $false }; $script:W32.Type = 'NoSync'; $script:W32.NtpServer = 'cu.vi.du,0x1'
$script:Zone = [pscustomobject]@{ Id = 'Pacific Standard Time'; Name = 'x'; Offset = -8 }
$script:Svc.SCardSvr.Start = 4
[void](Invoke-SuaGio -SetZone $true 6>$null); [void](Invoke-SuaToken 6>$null)
$code = Last (Invoke-HoanTac -DryRun 6>$null)
Check ($code -eq 0 -and $script:Svc.W32Time.Start -eq 3 -and (Test-Path $script:StateFile)) 'chạy thử trả lại: không đổi, giữ file'
$script:Calls.Clear()
$code = Last (Invoke-HoanTac 6>$null)
Check ($code -eq 0 -and $script:Svc.W32Time.Start -eq 4 -and $script:Svc.SCardSvr.Start -eq 4) "trả kiểu khởi động dịch vụ về như cũ ($code)"
Check ($script:W32.Type -eq 'NoSync' -and $script:W32.NtpServer -eq 'cu.vi.du,0x1' -and $script:Zone.Id -eq 'Pacific Standard Time') 'trả đồng bộ giờ, múi giờ về như cũ'
Check (-not (Test-Path $script:StateFile)) 'trả xong: xoá file giá trị cũ'
Check ((Last (Invoke-HoanTac 6>$null)) -eq 0) 'chưa lưu gì: mã 0'
Reset-Case; $script:Svc.SCardSvr.Start = 4; $script:Svc.CertPropSvc.Start = 4
[void](Invoke-SuaToken 6>$null); $script:ScFails = @('CertPropSvc')
$code = Last (Invoke-HoanTac 6>$null)
Check ($code -eq 3 -and (Test-Path $script:StateFile) -and $script:Svc.SCardSvr.Start -eq 4) "một mục không trả được: mã 3, giữ file ($code)"
Reset-Case; New-Item -ItemType Directory -Path (Split-Path $script:StateFile) -Force | Out-Null
[IO.File]::WriteAllText($script:StateFile, '{ hỏng')
Check ((Last (Invoke-HoanTac 6>$null)) -eq 1) 'file giá trị cũ hỏng: mã 1'
$code = Last (Invoke-SuaToken 6>$null)
Check ($code -eq 0 -or $code -eq 1) 'file hỏng không làm văng Sửa dịch vụ token'
Remove-Item -LiteralPath $script:StateFile -Force

Write-KT '9. Chế độ ghi kết quả sau khi sửa' Cyan
Reset-Case; $script:Svc.SCardSvr.Start = 4; $ChayThu = $true
$code = Last (Invoke-Mode 'sua-token' 6>$null)
$j = [IO.File]::ReadAllText(@(Get-ChildItem -LiteralPath $script:ResultDir -Filter 'KetQua_GioChuKySo_*.json')[0].FullName) | ConvertFrom-Json
Check ($code -eq 0 -and $j.cheDo -eq 'sua-token' -and $j.chayThu -eq $true -and $j.thongDiep -match 'Chạy thử') 'chạy thử Sửa token: file kết quả ghi chạy thử'
Check (@($j.phatHien | Where-Object { $_.ma -eq 'DICH_VU_SMART_CARD_TAT' }).Count -eq 1) 'kết quả là trạng thái máy sau lần chạy (chưa sửa nên vẫn báo)'
$ChayThu = $false

Write-KT '10. Mã, nút gợi ý, cờ khai trong script và tool.json' Cyan
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $toolDir 'GioChuKySo.ps1'), [ref]$null, [ref]$null)
$calls = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Add-Finding' }, $true))
$bad = @(); $next = @()
foreach ($cl in $calls) {
    $e = @($cl.CommandElements | Select-Object -Skip 1)
    if ($e[0] -is [Management.Automation.Language.StringConstantExpressionAst]) { if ($e[0].Value -notmatch '^[A-Z][A-Z0-9_]+$') { $bad += $cl.Extent.StartLineNumber } }
    elseif ($e[0].Extent.Text -ne '$s.Code') { $bad += $cl.Extent.StartLineNumber }
    if ($e[1] -is [Management.Automation.Language.StringConstantExpressionAst] -and $validLevels -notcontains $e[1].Value) { $bad += $cl.Extent.StartLineNumber }
    if ($e.Count -ge 6 -and $e[5] -is [Management.Automation.Language.StringConstantExpressionAst]) { $next += $e[5].Value }
}
Check ($calls.Count -ge 20 -and $bad.Count -eq 0) "$($calls.Count) chỗ ghi phát hiện: mã CHU_HOA, mức hợp lệ (dòng lỗi: $($bad -join ', '))"
$codesOk = @($script:TokenServices.Values | Where-Object { $_.Code -notmatch '^[A-Z][A-Z0-9_]+$' -or $validLevels -notcontains $_.Muc }).Count -eq 0
Check $codesOk 'mã, mức trong bảng dịch vụ token hợp lệ'
$cat = Get-HubCatalog -ToolsDir $ToolsDir -RootDir $RepoRoot
$wrong = @($next | Sort-Object -Unique | Where-Object {
        $parts = $_ -split '/'; $t = @($cat | Where-Object { $_.id -eq $parts[0] })[0]
        -not $t -or -not @($t.actions | Where-Object { $_.id -eq $parts[1] }).Count })
Check ($next.Count -gt 0 -and $wrong.Count -eq 0) "nút gợi ý trỏ tới action có thật ($(@($next | Sort-Object -Unique) -join ', '))"
$params = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
foreach ($a in $manifest.actions) {
    $flags = @(@($a.fixedArgs) | Where-Object { $_ -like '-*' }) + @(@($a.args) | ForEach-Object { $_.flag })
    $miss = @($flags | Where-Object { $_ -and $params -notcontains $_.TrimStart('-') })
    $fa = @($a.fixedArgs | Where-Object { $_ })   # @($null) có một phần tử
    $modeOk = -not $fa.Count -or $script:Modes.Contains($fa[1])
    Check ($miss.Count -eq 0 -and $modeOk) "$($a.id): cờ, chế độ có trong script ($($miss -join ', '))"
}
$t = @($cat | Where-Object { $_.id -eq 'gio-chu-ky-so' })[0]
Check ($t -and @($t.problems).Count -eq 0) "trạm đọc được tool.json, không lỗi khai báo ($(@($t.problems) -join ' | '))"

Complete-Test
