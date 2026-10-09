# Bài thử TiengViet.ps1 (Gói tiếng Việt) bằng giả lập: bộ gõ đang chạy, khởi động cùng Windows, bàn phím của Windows,
# font, bảng mã, câu trả lời là giả; định dạng số, ngày và tuỳ chọn Excel đọc, ghi thật trong registry thử
# (HKCU\Software\TramToolTest\TiengViet, qua TV_REG_GOC). Đặt định dạng, trả lại, giữ giá trị lần đổi đầu, Excel đang mở,
# đổi hỏng một mục; JSON kết quả mà trạm đọc được. Không đổi cài đặt thật.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
. "$HubDir\lib\Common.ps1"; . "$HubDir\lib\Catalog.ps1"; . "$HubDir\lib\KetQua.ps1"
$toolDir = Join-Path $ToolsDir 'tieng-viet'
$realIntl = (Get-ItemProperty 'HKCU:\Control Panel\International' | ForEach-Object { "$($_.sDecimal)|$($_.sThousand)|$($_.sList)|$($_.sShortDate)|$($_.sMonDecimalSep)|$($_.sMonThousandSep)" })
$env:TRAMTOOL_TIENGVIET_TEST = '1'
$env:TV_REG_GOC = 'HKCU:\Software\TramToolTest\TiengViet'
$env:TV_KET_QUA = New-TestDir 'tv_ketqua'
. "$toolDir\TiengViet.ps1"
Remove-Item Env:TRAMTOOL_TIENGVIET_TEST, Env:TV_REG_GOC, Env:TV_KET_QUA
$ChayThu = $false; $KhongDung = $true
$manifest = [IO.File]::ReadAllText((Join-Path $toolDir 'tool.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
$validLevels = 'loi', 'canh-bao', 'thong-tin', 'ok'
Check ($script:RegRoot -eq 'HKCU:\Software\TramToolTest\TiengViet' -and $script:IntlKey -like 'HKCU:\Software\TramToolTest\*') "TV_REG_GOC đưa định dạng vào registry thử ($script:IntlKey)"
Check ($script:ResultDir -like "$TestRoot*") 'TV_KET_QUA đưa kết quả vào thư mục tạm'

# ---- giả lập
$script:Answers = New-Object System.Collections.Queue
$script:Broadcasts = 0
$script:SetFails = @()
function Get-ImeProcesses { return $script:Procs }
function Get-ImeAutostart { return $script:Auto }
function Get-WindowsViInput { return $script:Win }
function Get-LegacyFonts { return $script:Fonts }
function Get-CodePage { return $script:Cp }
function Test-AppRunning { param([string]$Name) return ($script:Running -contains $Name) }
function Test-IsAdmin { return $false }
function Send-IntlChange { $script:Broadcasts++ }
function Read-YesNo { param([string]$Question, [bool]$Default = $false) if ($script:Answers.Count) { return $script:Answers.Dequeue() } return $Default }
$setReal = ${function:Set-IntlValue}
function Set-IntlValue { param([string]$Name, [string]$Value) if ($script:SetFails -contains $Name) { return $false } return (& $setReal $Name $Value) }

function Ime([string]$Ten, [int]$Quyen = 0, [string]$TienTrinh = '') { return [pscustomobject]@{ Ten = $Ten; TienTrinh = $(if ($TienTrinh) { $TienTrinh } else { $Ten }); Id = Get-Random -Maximum 60000; Path = "C:\Gia\$Ten.exe"; Quyen = $Quyen } }
function Auto([string]$Ten, [string]$Noi, [bool]$Bat = $true) { return [pscustomobject]@{ Ten = $Ten; Noi = $Noi; Lenh = "C:\Gia\$Ten.exe"; Bat = $Bat } }
function Set-Intl([hashtable]$V) { foreach ($k in $V.Keys) { Set-ItemProperty -LiteralPath $script:IntlKey -Name $k -Value $V[$k] -Type String } }
function Get-Intl { $p = Get-ItemProperty -LiteralPath $script:IntlKey; return "$($p.sDecimal)|$($p.sThousand)|$($p.sList)|$($p.sShortDate)|$($p.sMonDecimalSep)|$($p.sMonThousandSep)" }
function Set-Excel([string]$Ver, $Use, [string]$Dec = '', [string]$Th = '') {
    $k = "$script:OfficeKey\$Ver\Excel\Options"
    New-Item -Path $k -Force | Out-Null
    if ($null -ne $Use) { Set-ItemProperty -LiteralPath $k -Name UseSystemSeparators -Value ([int]$Use) -Type DWord }
    if ($Dec) { Set-ItemProperty -LiteralPath $k -Name DecimalSeparator -Value $Dec }
    if ($Th) { Set-ItemProperty -LiteralPath $k -Name ThousandsSeparator -Value $Th }
}
function Get-ExcelUse([string]$Ver) { $p = Get-ItemProperty -LiteralPath "$script:OfficeKey\$Ver\Excel\Options"; if ($null -ne $p.PSObject.Properties['UseSystemSeparators']) { return [int]$p.UseSystemSeparators } return $null }
$US = '.|,|,|M/d/yyyy|.|,'
$VN = ',|.|;|dd/MM/yyyy|,|.'
$QT = '.|,|,|dd/MM/yyyy|.|,'
function Reset-Case {
    Clear-TestRegistry
    New-Item -Path $script:IntlKey -Force | Out-Null
    Set-Intl @{ sDecimal = '.'; sThousand = ','; sList = ','; sShortDate = 'M/d/yyyy'; sMonDecimalSep = '.'; sMonThousandSep = ','; LocaleName = 'en-US'; sDate = '/'; iDate = '0' }
    $script:Procs = @(Ime 'EVKey' 0 'EVKey64')
    $script:Auto = @(Auto 'EVKey' 'thư mục Startup của tài khoản: EVKey64.lnk')
    $script:Win = [pscustomobject]@{ Co = $false; Ten = @() }
    $script:Fonts = [pscustomobject]@{ Vni = @(); Tcvn = @() }
    $script:Cp = [pscustomobject]@{ Acp = '1252'; Locale = 'en-US'; LocaleTen = 'English (United States)' }
    $script:Running = @(); $script:SetFails = @(); $script:Broadcasts = 0
    $script:Answers.Clear(); $script:Findings.Clear()
    Get-ChildItem -LiteralPath $script:ResultDir -File -ErrorAction SilentlyContinue | Remove-Item -Force
}
function Codes { return @($script:Findings | ForEach-Object { $_.ma }) }
function Find([string]$Ma) { return @($script:Findings | Where-Object { $_.ma -eq $Ma })[0] }
function Saved { return ([IO.File]::ReadAllText($script:StateFile) | ConvertFrom-Json) }
$script:AllFindings = New-Object System.Collections.ArrayList
function Run-Checks { Invoke-AllChecks *> $null; foreach ($f in $script:Findings) { [void]$script:AllFindings.Add($f) } }

Write-KT '1. Hàm phụ' Cyan
Check ((Get-CommandExe '"C:\Program Files\UniKey\UniKeyNT.exe" -tray') -eq 'C:\Program Files\UniKey\UniKeyNT.exe' -and (Get-CommandExe 'C:\EVKey\EVKey64.exe /min') -eq 'C:\EVKey\EVKey64.exe' -and (Get-CommandExe 'openkey') -eq 'openkey') 'tách file chạy khỏi dòng lệnh khởi động (có ngoặc kép, có tham số, chỉ tên)'
$names = @{ 'UniKeyNT' = 'UniKey'; 'unikey' = 'UniKey'; 'EVKey64' = 'EVKey'; 'EVKey32' = 'EVKey'; 'OpenKey64' = 'OpenKey'; 'Vietkey2000' = 'Vietkey'; 'vk2007' = 'Vietkey'; 'GoTiengViet' = 'GoTiengViet'; 'LabanKey' = 'Laban Key'; 'notepad' = $null; 'EVKeyHelper' = $null; 'unikeyx' = $null }
$bad = @($names.Keys | Where-Object { (Get-ImeName $_) -ne $names[$_] })
Check (-not $bad.Count) "nhận tên bộ gõ theo file chạy, không nhận nhầm tên gần giống (sai: $($bad -join ', '))"
Check ((Get-DateOrder 'M/d/yyyy') -ceq 'M' -and (Get-DateOrder 'dd/MM/yyyy') -ceq 'd' -and (Get-DateOrder 'yyyy-MM-dd') -ceq 'y' -and (Get-DateOrder "dd'.'MM") -ceq 'd' -and (Get-DateOrder '') -eq '') 'thứ tự ngày, tháng, năm trong mẫu ngày'
Check ((Get-MatchingPreset @{ sDecimal = ','; sThousand = '.'; sList = ';' }) -eq 'vn' -and (Get-MatchingPreset @{ sDecimal = '.'; sThousand = ','; sList = ',' }) -eq 'quoc-te' -and (Get-MatchingPreset @{ sDecimal = '.'; sThousand = ' '; sList = ';' }) -eq '') 'nhận kiểu định dạng Việt Nam, quốc tế, kiểu riêng'
Clear-TestRegistry
$sa = 'HKCU:\Software\TramToolTest\StartupApproved'
New-Item -Path $sa -Force | Out-Null
Set-ItemProperty $sa -Name 'Bat' -Value ([byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) -Type Binary
Set-ItemProperty $sa -Name 'TatTM' -Value ([byte[]](3, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8)) -Type Binary
Set-ItemProperty $sa -Name 'Tat1' -Value ([byte[]](1, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8)) -Type Binary
Check ((Test-StartupApproved $sa 'Bat') -and -not (Test-StartupApproved $sa 'TatTM') -and -not (Test-StartupApproved $sa 'Tat1') -and (Test-StartupApproved $sa 'KhongCo') -and (Test-StartupApproved "$sa\KhongCoKhoa" 'X')) 'đọc bật, tắt trong Task Manager (byte đầu lẻ là tắt; không có giá trị là bật)'
$e = Get-ProcElevation $PID
Check ($e -eq 0) "đọc quyền của tiến trình đang chạy bằng quyền thường: 0 ($e)"

Write-KT '2. Bộ gõ' Cyan
Reset-Case; Run-Checks
$f = Find 'BO_GO_DANG_CHAY'
Check ($f -and $f.mucDo -eq 'ok' -and $f.tieuDe -match 'EVKey' -and $f.tieuDe -match 'quyền thường') "một bộ gõ quyền thường: ok ($($f.tieuDe))"
Check ((Find 'BO_GO_QUYEN_THUONG').mucDo -eq 'thong-tin' -and -not @(Codes | Where-Object { $_ -match 'TRUNG|HAI_LAN|KHONG_CO_BO_GO' }).Count) 'nhắc phần mềm quyền Admin không gõ được dấu; không báo trùng'
Reset-Case; $script:Procs = @(Ime 'EVKey' 1 'EVKey64'); Run-Checks
Check ((Find 'BO_GO_DANG_CHAY').tieuDe -match 'quyền Admin' -and -not (Find 'BO_GO_QUYEN_THUONG')) 'bộ gõ chạy bằng quyền Admin: không nhắc'
Reset-Case; $script:Procs = @(Ime 'EVKey' -1 'EVKey64'); Run-Checks
Check ((Find 'BO_GO_DANG_CHAY').tieuDe -match 'có lẽ quyền Admin' -and -not (Find 'BO_GO_QUYEN_THUONG')) 'không đọc được quyền (chạy bằng quyền thường): đoán là quyền Admin'
Reset-Case; $script:Procs = @((Ime 'UniKey' 0 'UniKeyNT'), (Ime 'EVKey' 0 'EVKey64')); Run-Checks
$f = Find 'BO_GO_TRUNG'
Check ($f -and $f.mucDo -eq 'loi' -and $f.tieuDe -match 'UniKey' -and $f.tieuDe -match 'EVKey' -and -not (Find 'BO_GO_DANG_CHAY')) "hai bộ gõ cùng chạy: lỗi ($($f.tieuDe))"
Reset-Case; $script:Procs = @((Ime 'EVKey' 0 'EVKey64'), (Ime 'EVKey' 0 'EVKey32')); Run-Checks
Check ((Find 'BO_GO_CHAY_HAI_LAN').mucDo -eq 'canh-bao' -and -not (Find 'BO_GO_TRUNG') -and (Find 'BO_GO_CHAY_HAI_LAN').chiTiet -match 'EVKey32') 'một bộ gõ chạy hai bản: cảnh báo, không tính là hai bộ'
Reset-Case; $script:Auto = @((Auto 'UniKey' 'khoá Run của tài khoản: UniKey'), (Auto 'EVKey' 'thư mục Startup: EVKey64.lnk')); Run-Checks
Check ((Find 'BO_GO_KHOI_DONG_TRUNG').mucDo -eq 'canh-bao' -and (Find 'BO_GO_KHOI_DONG_TRUNG').chiTiet -match 'khoá Run') 'hai bộ gõ cùng khởi động với Windows: cảnh báo, nói ở đâu'
Reset-Case; $script:Auto = @((Auto 'UniKey' 'khoá Run của tài khoản: UniKey' $false), (Auto 'EVKey' 'thư mục Startup: EVKey64.lnk')); Run-Checks
Check (-not (Find 'BO_GO_KHOI_DONG_TRUNG')) 'mục khởi động đã tắt trong Task Manager thì không tính'
Reset-Case; $script:Auto = @((Auto 'EVKey' 'thư mục Startup: EVKey64.lnk'), (Auto 'EVKey' 'Task Scheduler: \EVKey')); Run-Checks
Check ((Find 'BO_GO_KHOI_DONG_HAI_LAN').mucDo -eq 'canh-bao' -and (Find 'BO_GO_KHOI_DONG_HAI_LAN').chiTiet -match 'Task Scheduler' -and -not (Find 'BO_GO_KHOI_DONG_TRUNG')) 'một bộ gõ đặt khởi động ở hai chỗ: cảnh báo'
Reset-Case; $script:Procs = @(); Run-Checks
$f = Find 'BO_GO_CHUA_CHAY'
Check ($f.mucDo -eq 'canh-bao' -and $f.chayTiep.congCu -eq 'bo-ung-dung') 'có khởi động mà không chạy: cảnh báo'
Reset-Case; $script:Procs = @(); $script:Auto = @(); $script:Win = [pscustomobject]@{ Co = $true; Ten = @('bàn phím Vietnamese') }; Run-Checks
Check ((Find 'BAN_PHIM_WINDOWS').mucDo -eq 'ok' -and -not (Find 'KHONG_CO_BO_GO')) 'chỉ dùng bàn phím tiếng Việt của Windows: ok'
Reset-Case; $script:Procs = @(); $script:Auto = @(); Run-Checks
$f = Find 'KHONG_CO_BO_GO'
Check ($f.mucDo -eq 'canh-bao' -and $f.chayTiep.congCu -eq 'bo-ung-dung' -and $f.chayTiep.action -eq 'cai') 'không có bộ gõ nào: cảnh báo, gợi ý cài bằng Bộ ứng dụng'
Reset-Case; $script:Win = [pscustomobject]@{ Co = $true; Ten = @('bàn phím Vietnamese') }; Run-Checks
$f = Find 'BAN_PHIM_WINDOWS_TRUNG'
Check ($f.mucDo -eq 'canh-bao' -and $f.tieuDe -match 'EVKey' -and $f.chiTiet -match 'Vietnamese') "bàn phím tiếng Việt của Windows bật cùng bộ gõ ngoài: cảnh báo ($($f.tieuDe))"

Write-KT '3. Font, phần mềm cũ' Cyan
Reset-Case; Run-Checks
Check ((Find 'FONT_CU_KHONG').mucDo -eq 'thong-tin' -and (Find 'FONT_CU_KHONG').chayTiep.action -eq 'chuyen') 'không có font cũ: thông tin, gợi ý chuyển tài liệu'
Check ((Find 'NGON_NGU_HE_THONG').mucDo -eq 'thong-tin' -and -not (Find 'UTF8_BETA')) 'ngôn ngữ cho chương trình không Unicode khác tiếng Việt: thông tin'
Reset-Case; $script:Fonts = [pscustomobject]@{ Vni = @('VNI-Times', 'VNI-Helve'); Tcvn = @('.VnTime') }; $script:Cp = [pscustomobject]@{ Acp = '65001'; Locale = 'vi-VN'; LocaleTen = 'Vietnamese (Vietnam)' }; Run-Checks
$f = Find 'FONT_CU_CO'
Check ($f.tieuDe -match '2 font VNI, 1 font TCVN3' -and $f.chiTiet -match 'VNI-Helve') "có font cũ: đếm, kể tên ($($f.tieuDe))"
Check ((Find 'UTF8_BETA').mucDo -eq 'canh-bao' -and (Find 'NGON_NGU_HE_THONG').mucDo -eq 'ok') 'bật UTF-8 (Beta): cảnh báo; ngôn ngữ tiếng Việt: ok'

Write-KT '4. Định dạng số, ngày, Excel' Cyan
Reset-Case; Run-Checks
Check ((Find 'SO_DINH_DANG').mucDo -eq 'ok' -and (Find 'SO_DINH_DANG').tieuDe -match 'quốc tế') 'số kiểu quốc tế: ok'
$f = Find 'NGAY_THANG_TRUOC'
Check ($f.mucDo -eq 'canh-bao' -and $f.chayTiep.congCu -eq 'tieng-viet' -and $f.chayTiep.action -eq 'dinh-dang') 'ngày kiểu tháng trước: cảnh báo, nút Đặt định dạng'
Reset-Case; Set-Intl @{ sDecimal = ','; sThousand = ',' }; Run-Checks
Check ((Find 'SO_TRUNG_DAU').mucDo -eq 'loi' -and -not (Find 'SO_DINH_DANG')) 'dấu thập phân trùng dấu nghìn: lỗi'
Reset-Case; Set-Intl @{ sDecimal = ','; sThousand = '.'; sList = ','; sMonDecimalSep = ','; sMonThousandSep = '.' }; Run-Checks
Check ((Find 'DANH_SACH_TRUNG_THAP_PHAN').mucDo -eq 'loi') 'dấu ngăn danh sách trùng dấu thập phân: lỗi'
Reset-Case; Set-Intl @{ sDecimal = ','; sThousand = '.'; sList = ';'; sShortDate = 'dd/MM/yyyy'; sMonDecimalSep = ','; sMonThousandSep = '.' }; Run-Checks
Check ((Find 'SO_DINH_DANG').tieuDe -match 'Việt Nam' -and (Find 'NGAY_DINH_DANG').mucDo -eq 'ok' -and -not @($script:Findings | Where-Object { $_.ma -match '^(SO|NGAY|DANH_SACH)' -and $_.mucDo -in 'loi', 'canh-bao' }).Count) 'kiểu Việt Nam, ngày dd/MM/yyyy: không cảnh báo định dạng'
Reset-Case; Set-Intl @{ sMonDecimalSep = ','; sMonThousandSep = '.' }; Run-Checks
Check ((Find 'SO_TIEN_KHAC').mucDo -eq 'canh-bao') 'định dạng tiền khác định dạng số: cảnh báo'
Reset-Case; Set-Intl @{ sThousand = ' '; sList = ';'; sMonThousandSep = ' '; sShortDate = 'dd/MM/yy' }; Run-Checks
Check ((Find 'SO_DINH_DANG_KHAC').mucDo -eq 'thong-tin' -and (Find 'NGAY_NAM_HAI_SO').mucDo -eq 'thong-tin') 'kiểu số riêng, năm 2 số: thông tin'
Reset-Case; Set-Intl @{ sShortDate = 'yyyy-MM-dd' }; Run-Checks
Check ((Find 'NGAY_NAM_TRUOC').mucDo -eq 'thong-tin') 'ngày năm trước: thông tin'
Reset-Case; Clear-TestRegistry; Run-Checks
Check ((Find 'DINH_DANG_KHONG_DOC_DUOC').mucDo -eq 'canh-bao' -and (Find 'NGAY_KHONG_DOC_DUOC')) 'không đọc được định dạng: cảnh báo, không văng'
Reset-Case; Set-Excel '16.0' 0 ',' ','; Set-Excel '14.0' 1; Run-Checks
$f = @($script:Findings | Where-Object { $_.ma -eq 'EXCEL_DAU_RIENG' })
Check ($f.Count -eq 1 -and $f[0].mucDo -eq 'loi' -and $f[0].tieuDe -match '2016' -and $f[0].chayTiep.action -eq 'dinh-dang') 'Excel dùng dấu riêng mà thập phân trùng nghìn: lỗi; Excel dùng dấu Windows thì thôi'
Reset-Case; Set-Excel '16.0' 0 ',' '.'; Run-Checks
Check ((Find 'EXCEL_DAU_RIENG').mucDo -eq 'canh-bao') 'Excel dùng dấu riêng: cảnh báo'

Write-KT '5. Đặt định dạng, trả lại' Cyan
Reset-Case; Set-Excel '16.0' 0 '.' ','
$c = Invoke-DinhDang -Preset 'vn' -Excel $true -DryRun *>&1 | Out-String
Check ((Get-Intl) -eq $US -and (Get-ExcelUse '16.0') -eq 0 -and -not (Test-Path -LiteralPath $script:StateFile) -and $c -match 'Dấu thập phân: "\." -> ","' -and $c -match 'Excel') 'chạy thử: in việc sẽ làm (cả Excel), không đổi, không lưu giá trị cũ'
$script:Answers.Enqueue($false)
$c = Invoke-DinhDang -Preset 'vn' -Excel $true -Ask 6> $null
Check ($c -eq 2 -and (Get-Intl) -eq $US -and -not (Test-Path -LiteralPath $script:StateFile)) "trả lời Không: mã 2, không đổi ($c)"
$c = Invoke-DinhDang -Preset 'vn' -Excel $true 6> $null
Check ($c -eq 0) "đặt kiểu Việt Nam: mã 0 ($c)"
Check ((Get-Intl) -eq $VN -and (Get-ExcelUse '16.0') -eq 1 -and $script:Broadcasts -eq 1) "định dạng đổi đủ 6 mục, Excel dùng dấu Windows, báo cho cửa sổ đọc lại ($(Get-Intl))"
$s = Saved
Check ($s.dinhDang.sDecimal -eq '.' -and $s.dinhDang.sShortDate -eq 'M/d/yyyy' -and $s.excel.'16.0'.co -eq $true -and $s.excel.'16.0'.gia -eq 0 -and $s.taiKhoan -eq $env:USERNAME) 'lưu giá trị cũ trước khi đổi (định dạng, Excel, tài khoản)'
$luu = $s.luuLuc
$c = Invoke-DinhDang -Preset 'vn' -Excel $true *>&1 | Out-String
Check ($c -match 'đã đúng' -and $script:Broadcasts -eq 1) 'đặt lại cùng kiểu: không cần đổi'
$c = Invoke-DinhDang -Preset 'quoc-te' -Excel $true 6> $null
$s = Saved
Check ($c -eq 0 -and (Get-Intl) -eq $QT -and $s.dinhDang.sDecimal -eq '.' -and $s.dinhDang.sList -eq ',' -and $s.dinhDang.sShortDate -eq 'M/d/yyyy' -and $s.luuLuc -eq $luu) 'đổi lần hai sang kiểu quốc tế: file giá trị cũ vẫn giữ giá trị lúc đầu'
$c = Invoke-TraLai -DryRun *>&1 | Out-String
Check ((Get-Intl) -eq $QT -and (Test-Path -LiteralPath $script:StateFile) -and $c -match 'M/d/yyyy') 'trả lại chạy thử: in việc sẽ làm, không đổi, giữ file'
$c = Invoke-TraLai 6> $null
Check ($c -eq 0 -and (Get-Intl) -eq $US -and (Get-ExcelUse '16.0') -eq 0 -and -not (Test-Path -LiteralPath $script:StateFile)) "trả lại: định dạng, Excel như lúc đầu, xoá file giá trị cũ ($c, $(Get-Intl))"
$c = Invoke-TraLai *>&1 | Out-String
Check ($c -match 'Chưa có giá trị cũ') 'trả lại khi chưa lưu gì: báo, không văng'

Reset-Case; Set-Excel '16.0' 0 '.' ','; $script:Running = @('EXCEL')
$c = Invoke-DinhDang -Preset 'vn' -Excel $true 6> $null
Check ($c -eq 3 -and (Get-Intl) -eq $VN -and (Get-ExcelUse '16.0') -eq 0 -and -not @((Saved).excel.PSObject.Properties).Count) "Excel đang mở: đổi định dạng Windows, bỏ tuỳ chọn Excel, mã 3 ($c)"
$script:Running = @()
$c = Invoke-DinhDang -Preset 'vn' -Excel $true 6> $null
Check ($c -eq 0 -and (Get-ExcelUse '16.0') -eq 1 -and (Saved).excel.'16.0'.gia -eq 0 -and (Saved).dinhDang.sDecimal -eq '.') 'đóng Excel rồi chạy lại: đổi nốt Excel, lưu thêm giá trị cũ của Excel'
$c = Invoke-TraLai 6> $null
Check ($c -eq 0 -and (Get-Intl) -eq $US -and (Get-ExcelUse '16.0') -eq 0) 'trả lại cả hai lần đổi'

Reset-Case; $script:SetFails = @('sList')
$c = Invoke-DinhDang -Preset 'vn' -Excel $false 6> $null
Check ($c -eq 3 -and (Get-ItemProperty $script:IntlKey).sList -eq ',' -and (Get-ItemProperty $script:IntlKey).sDecimal -eq ',') "đổi hỏng một mục: các mục khác vẫn đổi, mã 3 ($c)"
$script:SetFails = @($script:IntlNames.Keys)
$c = Invoke-TraLai 6> $null
Check ($c -eq 1 -and (Test-Path -LiteralPath $script:StateFile) -and (Get-ItemProperty $script:IntlKey).sDecimal -eq ',') "trả lại mà không ghi được mục nào: mã 1, giữ file giá trị cũ ($c)"
$script:SetFails = @('sThousand')
$c = Invoke-TraLai 6> $null
Check ($c -eq 3 -and (Test-Path -LiteralPath $script:StateFile) -and (Get-ItemProperty $script:IntlKey).sDecimal -eq '.') "trả lại được một phần: mã 3, giữ file ($c)"
$script:SetFails = @()
$c = Invoke-TraLai 6> $null
Check ($c -eq 0 -and (Get-Intl) -eq $US -and -not (Test-Path -LiteralPath $script:StateFile)) "chạy lại khi ghi được: trả lại hết, xoá file ($c)"

Reset-Case; Set-Excel '16.0' 0
[IO.File]::WriteAllText($script:StateFile, '{"may":"X","luuLuc":"2026-01-01 00:00:00","dinhDang":{},"excel":{"16.0":{"co":false,"gia":null}}}')
$c = Invoke-TraLai 6> $null
Check ($c -eq 0 -and $null -eq (Get-ExcelUse '16.0')) 'Excel lúc đầu chưa đặt UseSystemSeparators: trả lại bằng cách xoá giá trị'
[IO.File]::WriteAllText($script:StateFile, '{hỏng')
Check ((Invoke-TraLai *>&1 | Select-Object -Last 1) -eq 1) 'file giá trị cũ hỏng: trả lại báo lỗi, mã 1'
Run-Checks
Check ((Find 'TRANG_THAI_GOC_HONG').mucDo -eq 'canh-bao') 'Kiểm tra báo file giá trị cũ hỏng'
Remove-Item -LiteralPath $script:StateFile

Write-KT '6. Kết quả cho trạm' Cyan
Reset-Case
$Mau = 'vn'; $ExcelTheoWindows = [switch]$true
$c = Invoke-Mode 'dinh-dang' 6> $null
$c = Invoke-Mode 'tra-lai' 6> $null
$files = @(Get-ChildItem -LiteralPath $script:ResultDir -Filter 'KetQua_TiengViet_*.json' | Sort-Object Name)
Check ($files.Count -ge 1) "mỗi lần chạy ghi một file kết quả ($($files.Count))"
$glob = [Environment]::ExpandEnvironmentVariables(@($manifest.outputs | Where-Object { $_.ketQua -and $_.glob -notmatch 'ChuyenUnicode' })[0].glob)
Check (@($files | Where-Object { $_.Name -notlike $glob }).Count -eq 0) "tên file khớp mẫu khai trong tool.json ($glob)"
Reset-Case
$Mau = 'quoc-te'
$c = Invoke-Mode 'dinh-dang' 6> $null
$f = @(Get-ChildItem -LiteralPath $script:ResultDir -Filter 'KetQua_TiengViet_*.json')[0]
$j = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json
Check ($j.chuan -eq 'tramtool.ketqua/1' -and $j.congCu -eq 'tieng-viet' -and $j.cheDo -eq 'dinh-dang' -and $j.maThoat -eq 0 -and $j.trangThai -eq 'xong' -and -not $j.chayThu) 'JSON: chuẩn, công cụ, chế độ, mã thoát'
Check (@($j.phatHien | ForEach-Object { $_.ma }) -contains 'NGAY_DINH_DANG' -and @($j.tep).Count -eq 1 -and $j.tep[0].duongDan -eq $script:StateFile) 'kiểm tra lại sau khi đổi; kèm file giá trị cũ'
$lv = @($j.phatHien | ForEach-Object { $script:Levels[[string]$_.mucDo] })
Check ((($lv | Sort-Object) -join ',') -eq ($lv -join ',')) 'phát hiện xếp lỗi, cảnh báo trước'
$hr = Read-RunResult -Path $f.FullName
Check ($hr -and @($hr.phatHien).Count -eq @($j.phatHien).Count) 'trạm đọc được file kết quả'
$sg = [Environment]::ExpandEnvironmentVariables(@($manifest.outputs | Where-Object { $_.glob -like 'TrangThaiGoc_*' })[0].glob)
Check ((Split-Path $script:StateFile -Leaf) -like $sg) "file giá trị cũ khớp mẫu khai trong tool.json ($sg)"
Reset-Case
$ChayThu = $true
$c = Invoke-Mode 'dinh-dang' 6> $null
$j = [IO.File]::ReadAllText(@(Get-ChildItem -LiteralPath $script:ResultDir -Filter 'KetQua_TiengViet_*.json')[0].FullName) | ConvertFrom-Json
Check ($j.chayThu -eq $true -and $j.thongDiep -match 'Chạy thử' -and (Get-Intl) -eq $US) 'chạy thử ghi chayThu, không đổi'
$ChayThu = $false

Write-KT '7. Mã phát hiện, nút chạy tiếp, tool.json' Cyan
$bad = @($script:AllFindings | Where-Object { $_.ma -notmatch '^[A-Z0-9_]+$' -or $validLevels -notcontains $_.mucDo -or -not $_.tieuDe })
Check (-not $bad.Count) "mọi phát hiện có mã, mức, tiêu đề hợp lệ ($(@($script:AllFindings).Count) phát hiện)"
$tiep = @($script:AllFindings | Where-Object { $_.chayTiep } | ForEach-Object { '{0}/{1}' -f $_.chayTiep.congCu, $_.chayTiep.action } | Select-Object -Unique)
$sai = @()
foreach ($t in $tiep) {
    $cc, $ac = $t -split '/'
    $tf = Join-Path $ToolsDir "$cc\tool.json"
    if (-not (Test-Path $tf)) { $sai += $t; continue }
    $m = [IO.File]::ReadAllText($tf, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not @($m.actions | Where-Object { $_.id -eq $ac }).Count) { $sai += $t }
}
Check ($tiep.Count -ge 4 -and -not $sai.Count) "nút chạy tiếp trỏ tới action có thật ($($tiep -join ', ')$(if ($sai) { '; sai: ' + ($sai -join ', ') }))"
$params = @((Get-Command (Join-Path $toolDir 'TiengViet.ps1')).Parameters.Keys)
$sai = @()
foreach ($a in @($manifest.actions | Where-Object { $_.file -eq 'TiengViet.ps1' })) {
    $fx = @($a.fixedArgs)
    if ($fx.Count -ge 2 -and -not $script:Modes.Contains([string]$fx[1])) { $sai += "$($a.id): chế độ $($fx[1])" }
    foreach ($g in @($a.args)) { if ($g.flag -and $params -notcontains $g.flag.TrimStart('-')) { $sai += "$($a.id): $($g.flag)" } }
}
Check (-not $sai.Count) "action trong tool.json gọi đúng chế độ, cờ của TiengViet.ps1 ($($sai -join '; '))"
$oMau = @(@($manifest.actions | Where-Object { $_.id -eq 'dinh-dang' })[0].args | Where-Object { $_.id -eq 'mau' })[0]
Check ((@($oMau.options | ForEach-Object { $_.value }) -join ',') -eq (@($script:MauDinhDang.Keys) -join ',') -and $oMau.default -eq 'vn') 'ô Kiểu định dạng khớp các kiểu trong script, mặc định kiểu Việt Nam'

Clear-TestRegistry
$after = (Get-ItemProperty 'HKCU:\Control Panel\International' | ForEach-Object { "$($_.sDecimal)|$($_.sThousand)|$($_.sList)|$($_.sShortDate)|$($_.sMonDecimalSep)|$($_.sMonThousandSep)" })
Check ($after -eq $realIntl) 'định dạng thật của tài khoản không đổi'
Complete-Test
