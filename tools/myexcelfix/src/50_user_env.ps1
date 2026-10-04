
# ----------------------------------------------------------------------------
Section '7. THƯ MỤC TẠM, CACHE ACTIVEX (.exd), ONEDRIVE, MÁY IN, BỘ GÕ'
try {
    $t = $env:TEMP
    $exists = Test-Path -LiteralPath $t -PathType Container
    $writable = Test-Writable $t
    Info 'TEMP tồn tại / ghi được' "$exists / $writable"
    Snap 'Temp.Writable' $writable
    if (-not $exists -or -not $writable) {
        Add-Finding 'LOI' "Thư mục TEMP của user ($t) không tồn tại hoặc không ghi được => VBA không tạo được file ảnh QR tạm" 'Tạo lại thư mục TEMP hoặc đặt lại biến: setx TEMP "%USERPROFILE%\AppData\Local\Temp" và setx TMP "%USERPROFILE%\AppData\Local\Temp", đăng xuất/đăng nhập lại.'
    } else {
        $cnt = 0; $tmpCnt = 0
        foreach ($f in [IO.Directory]::EnumerateFiles($t)) {
            $cnt++
            if ($f.EndsWith('.tmp', [StringComparison]::OrdinalIgnoreCase)) { $tmpCnt++ }
            if ($cnt -ge 200000) { break }
        }
        Info 'Số file trong TEMP (cấp 1) / file .tmp' "$cnt / $tmpCnt"
        Snap 'Temp.FileCountBucket' ($(if ($cnt -gt 20000) { '>20000' } elseif ($cnt -gt 2000) { '>2000' } else { '<=2000' }))
        if ($tmpCnt -gt 30000) {
            Add-Finding 'LOI' "TEMP có $tmpCnt file .tmp (Windows giới hạn 65535) => Excel/VBA có thể không tạo được file tạm" 'Đóng Excel, Win+R gõ %TEMP% > Ctrl+A > Delete (bỏ qua file đang dùng).'
        } elseif ($cnt -gt 5000) {
            Add-Finding 'CANHBAO' "TEMP có $cnt file" 'Đóng Excel, Win+R gõ %TEMP% > xóa bớt file tạm.'
        }
    }

    $exdDirs = @("$env:TEMP\VBE", "$env:TEMP\Excel8.0", "$env:TEMP\Word8.0", "$env:APPDATA\Microsoft\Forms", "$env:LOCALAPPDATA\Temp\VBE", "$env:LOCALAPPDATA\Temp\Excel8.0")
    $exd = @()
    foreach ($d in ($exdDirs | Sort-Object -Unique)) {
        if (Test-Path -LiteralPath $d) { $exd += Get-ChildItem -LiteralPath $d -Filter '*.exd' -File -Force -ErrorAction SilentlyContinue }
    }
    $exd = @($exd | Sort-Object FullName -Unique)
    foreach ($e in $exd) { Note ("{0}  {1}" -f $e.LastWriteTime.ToString('dd/MM/yyyy'), $e.FullName) }
    Snap 'Temp.ExdCount' $exd.Count
    $exdFix = 'Đóng hết Excel/Word, mở CMD chạy:  del /s /q "%TEMP%\*.exd"  và  del /q "%APPDATA%\Microsoft\Forms\*.exd"  rồi mở lại Excel (Office tự tạo lại).'
    $exeTime = $null
    if ($script:ExcelDir -and (Test-Path -LiteralPath (Join-Path $script:ExcelDir 'EXCEL.EXE'))) { $exeTime = (Get-Item -LiteralPath (Join-Path $script:ExcelDir 'EXCEL.EXE')).LastWriteTime }
    $staleExd = @($exd | Where-Object { $exeTime -and $_.LastWriteTime -lt $exeTime })
    if ($staleExd.Count -gt 0) {
        Add-Finding 'CANHBAO' ("Có {0} file cache ActiveX (.exd) cũ hơn bản Excel đang cài ({1}) - cache cũ có thể làm form/nút VBA lỗi sau khi Office cập nhật (Office tự tạo lại nên profile nào dùng lâu cũng có)" -f $staleExd.Count, $exeTime.ToString('dd/MM/yyyy')) $exdFix
    } elseif ($exd.Count -gt 0) {
        Add-Finding 'THONGTIN' "Có $($exd.Count) file cache ActiveX (.exd), không cũ hơn bản Excel đang cài - bình thường" "Chỉ cần xóa nếu form/nút VBA báo lỗi. $exdFix"
    } else { Ok 'Không có file .exd' }
} catch { Note "Lỗi khi kiểm tra TEMP: $($_.Exception.Message)" }

try {
    $desk = [Environment]::GetFolderPath('Desktop')
    $docs = [Environment]::GetFolderPath('MyDocuments')
    Info 'Desktop' $desk
    Info 'Documents' $docs
    $od = @(Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue |
        Where-Object { $_.GetValue('UserFolder') } | ForEach-Object { "$($_.PSChildName): $($_.GetValue('UserFolder'))" })
    foreach ($o in $od) { Info 'OneDrive đăng nhập' $o }
    Snap 'OneDrive.KFM' (($desk -match '(?i)onedrive') -or ($docs -match '(?i)onedrive'))
    if ($desk -match '(?i)onedrive' -or $docs -match '(?i)onedrive') {
        Add-Finding 'CANHBAO' 'Desktop/Documents đang đồng bộ OneDrive: file Excel mở từ đó có đường dẫn dạng https:// nên macro lưu/chèn ảnh QR có thể lỗi' 'Copy file Excel cần tạo VietQR ra thư mục thường (VD C:\Data) rồi mở và thử lại. Nếu chạy được => tắt backup Desktop/Documents của OneDrive hoặc làm việc ngoài OneDrive.'
    }
} catch { Note "Lỗi khi kiểm tra OneDrive: $($_.Exception.Message)" }

try {
    $prn = @(Get-CimInstance Win32_Printer -OperationTimeoutSec 20 -ErrorAction Stop)
    $def = $prn | Where-Object { $_.Default } | Select-Object -First 1
    Info 'Số máy in' $prn.Count
    if ($def) {
        Info 'Máy in mặc định của user' ("{0} (offline: {1}, mạng: {2})" -f $def.Name, $def.WorkOffline, $def.Network)
        Snap 'Printer.Default' $def.Name
        if ($def.WorkOffline) {
            Add-Finding 'CANHBAO' "Máy in mặc định '$($def.Name)' đang offline - VBA đụng tới PageSetup/In sẽ treo hoặc báo lỗi" 'Đặt "Microsoft Print to PDF" làm máy in mặc định rồi thử lại.'
        }
    } else {
        Snap 'Printer.Default' ''
        Add-Finding 'CANHBAO' 'User này không có máy in mặc định' 'Settings > Bluetooth & devices > Printers & scanners > tắt "Let Windows manage my default printer" > chọn Microsoft Print to PDF > Set as default.'
    }
} catch { Note "Không đọc được danh sách máy in: $($_.Exception.Message)" }

try {
    $pn = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
    $ime = @($pn | Where-Object { $_ -match '(?i)^(unikey|unikeynt|evkey|evkey64|evkey32|openkey|gotiengviet|vietkey)' })
    $rem = @($pn | Where-Object { $_ -match '(?i)^(ultraviewer|teamviewer|anydesk|rustdesk)' })
    Info 'Bộ gõ tiếng Việt đang chạy' ($ime -join ', ')
    Info 'Phần mềm điều khiển từ xa' ($rem -join ', ')
    Snap 'Proc.IME' ($ime -join ',')
    if ($ime.Count -gt 0) {
        Add-Finding 'THONGTIN' "Bộ gõ $($ime -join ', ') đang chạy" 'Khi gõ công thức =QrBank_Sotien_Noidung(...) hoặc khai báo tài khoản, chuyển bộ gõ sang chế độ E (tiếng Anh) để tránh bị bỏ dấu/đổi ký tự.'
    }
    $clip = Get-RegValue 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory'
    Info 'Clipboard history (Win+V)' ($(if ($clip -eq 1) { 'bật' } else { 'tắt' }))
    Snap 'Win.ClipboardHistory' $clip
} catch {}

# ----------------------------------------------------------------------------
Section '8. THÀNH PHẦN COM MÀ MACRO VBA HAY DÙNG + ĐĂNG KÝ COM HỎNG TRONG HKCU'
try {
    $ids = "'Scripting.FileSystemObject','Scripting.Dictionary','VBScript.RegExp','Shell.Application','WIA.ImageFile','MSXML2.DOMDocument.6.0'"
    $code = "foreach (`$id in @($ids)) { try { `$o = New-Object -ComObject `$id -ErrorAction Stop; [void][Runtime.InteropServices.Marshal]::ReleaseComObject(`$o); 'OK|' + `$id } catch { 'FAIL|' + `$id + '|' + `$_.Exception.Message } }"
    $useWow = $script:OfficeIs32 -and [Environment]::Is64BitProcess
    $bitTxt = if ($useWow) { '32-bit (giống Excel)' } else { "$(if ([Environment]::Is64BitProcess) { '64' } else { '32' })-bit" }
    Info 'Kiểm tra COM ở chế độ' $bitTxt
    if ($useWow) {
        $ps32 = "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
        $res = $code | & $ps32 -NoProfile -NonInteractive -Command -
    } else {
        $res = & ([scriptblock]::Create($code))
    }
    $fails = @()
    foreach ($r in $res) {
        $parts = ([string]$r).Split('|')
        if ($parts[0] -eq 'OK') { Ok "COM $($parts[1])" }
        elseif ($parts[0] -eq 'FAIL') { $fails += $parts[1]; Out-Line "  [X]   COM $($parts[1]) : $($parts[2])" 'Red' }
    }
    Snap 'COM.Fail' ($fails -join ',')
    if ($fails.Count -gt 0) {
        Add-Finding 'CANHBAO' ("Không tạo được đối tượng COM: {0}" -f ($fails -join ', ')) 'Nếu profile mới tạo được còn profile này thì không => đăng ký COM theo user bị hỏng (xem danh sách HKCU bên dưới). Nếu cả máy đều lỗi => mở CMD (Admin) chạy: regsvr32 scrrun.dll  /  regsvr32 vbscript.dll  /  regsvr32 wiaaut.dll.'
    }
} catch { Note "Lỗi khi thử COM: $($_.Exception.Message)" }

try {
    $broken = @()
    foreach ($k in (Get-ChildItem -LiteralPath 'HKCU:\Software\Classes\CLSID' -ErrorAction SilentlyContinue)) {
        foreach ($srv in 'InprocServer32', 'LocalServer32') {
            $sk = $k.OpenSubKey($srv)
            if (-not $sk) { continue }
            $val = [string]$sk.GetValue('')
            $sk.Close()
            if (-not $val) { continue }
            $file = [Environment]::ExpandEnvironmentVariables($val)
            if ($file -match '^"([^"]+)"') { $file = $Matches[1] } else { $file = ($file -split '\s+/')[0].Trim() }
            if ($file -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $file)) { $broken += "CLSID $($k.PSChildName) -> $file" }
        }
    }
    foreach ($k in (Get-ChildItem -LiteralPath 'HKCU:\Software\Classes\TypeLib' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^win(32|64)$' })) {
        $file = [Environment]::ExpandEnvironmentVariables([string]$k.GetValue('')) -replace '\\\d+$', ''
        if ($file -match '^[A-Za-z]:\\' -and -not (Test-Path -LiteralPath $file)) { $broken += "TypeLib $($k.Name -replace '^.*\\TypeLib\\', '') -> $file" }
    }
    # TypeLib/COM mà VBA của Office hay tham chiếu: MSForms, Office, VBA, VBIDE, Excel, stdole, Scripting, MSComctl, WIA, MSXML
    $vbaRx = '(?i)0D452EE1-E08F-101A-852E-02608C4D0BB4|2DF8D04C-5BFA-101B-BDE5-00AA0044DE52|000204EF-0000-0000-C000-000000000046|0002E157-0000-0000-C000-000000000046|00020813-0000-0000-C000-000000000046|00020430-0000-0000-C000-000000000046|420B2830-E718-11CF-893D-00A0C9054228|831FDD16-0C5C-11D2-A9FC-0000F8754DA1|94A0E92D-43C0-494E-AC29-FD45948A5221|F5078F18-C551-11D3-89B9-0000F81FE221|fm20|mscomctl|vbe7|scrrun|wiaaut|msxml|Microsoft Office|Microsoft Shared'
    $vbaBroken = @($broken | Where-Object { $_ -match $vbaRx })
    Info 'Đăng ký COM/TypeLib hỏng trong HKCU' ("{0} (liên quan VBA/Office: {1})" -f $broken.Count, $vbaBroken.Count)
    foreach ($b in ($vbaBroken | Select-Object -First 20)) { Out-Line "    $b" 'Red' }
    Snap 'COM.HKCUBrokenVBA' $vbaBroken.Count
    if ($vbaBroken.Count -gt 0) {
        $coreRx = '(?i)0D452EE1-E08F-101A-852E-02608C4D0BB4|2DF8D04C-5BFA-101B-BDE5-00AA0044DE52|000204EF-0000-0000-C000-000000000046|0002E157-0000-0000-C000-000000000046|00020813-0000-0000-C000-000000000046|00020430-0000-0000-C000-000000000046|fm20|vbe7'
        $lv = if ($vbaBroken | Where-Object { $_ -match $coreRx }) { 'LOI' } else { 'CANHBAO' }
        Add-Finding $lv "Có $($vbaBroken.Count) đăng ký COM/TypeLib của VBA/Office trong HKCU trỏ tới file không tồn tại (VBA báo lỗi thư viện/ActiveX, profile mới không bị)" 'Mở regedit, Export rồi xóa đúng các key GUID được liệt kê ở trên trong HKCU\Software\Classes (CLSID/TypeLib), sau đó mở lại Excel. Đăng ký ở cấp máy (HKLM) vẫn còn nên Excel dùng lại bản đúng.'
    }
} catch { Note "Lỗi khi quét HKCU\Software\Classes: $($_.Exception.Message)" }
