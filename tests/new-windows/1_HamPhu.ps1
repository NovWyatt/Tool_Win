# Bài thử 1: mã hoá, zip, manifest, chọn nơi lưu, chọn bản sao lưu
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$Root = $TestRoot
. "$PSScriptRoot\_GiaLap.ps1" -FakeHome (Join-Path $Root 'home')

Write-Host '== mã hoá'
$data = [Text.Encoding]::UTF8.GetBytes('Dữ liệu bí mật giả ' + ('x' * 1000))
$blob = Protect-Bytes $data 'MatKhauThu123' 20000
Check ($blob -is [byte[]]) 'Protect-Bytes trả byte[]'
Check ([Text.Encoding]::ASCII.GetString($blob, 0, 5) -eq 'TTDL1') 'đầu tệp TTDL1'
$back = Unprotect-Bytes $blob 'MatKhauThu123'
Check ($back -is [byte[]] -and (Test-SameBytes $back $data)) 'giải mã đúng mật khẩu ra đúng nội dung'
$e = $null; try { [void](Unprotect-Bytes $blob 'SaiMatKhau') } catch { $e = $_.Exception.Message }
Check ($e -like 'Sai mật khẩu*') "sai mật khẩu bị từ chối ($e)"
$t = [byte[]]$blob.Clone(); $t[60] = $t[60] -bxor 1
$e = $null; try { [void](Unprotect-Bytes $t 'MatKhauThu123') } catch { $e = $_.Exception.Message }
Check ($e -like 'Sai mật khẩu*') 'sửa 1 byte bị phát hiện (HMAC)'
$e = $null; try { [void](Unprotect-Bytes ([byte[]](1..200)) 'x') } catch { $e = $_.Exception.Message }
Check ($e -like 'Không phải tệp*') 'sai đầu tệp bị từ chối'
$e = $null; try { [void](Unprotect-Bytes ([byte[]](1..10)) 'x') } catch { $e = $_.Exception.Message }
Check ($e -like '*quá ngắn*') 'tệp quá ngắn bị từ chối'
$b2 = Protect-Bytes $data 'MatKhauThu123' 20000
Check (-not (Test-SameBytes $blob $b2)) 'hai lần mã hoá khác nhau (salt, IV ngẫu nhiên)'
$blobDefault = Protect-Bytes $data 'MatKhauThu123'
Check ([BitConverter]::ToInt32($blobDefault, 21) -eq 200000) 'mặc định 200000 vòng PBKDF2'

Write-Host '== zip trong bộ nhớ'
$files = [ordered]@{ 'WiFi\001.xml' = [Text.Encoding]::UTF8.GetBytes('<a/>'); 'Claude\AppData-Claude\Claude Extensions Settings\x\y.json' = [byte[]](0, 1, 2, 255) }
$zip = New-ZipBytes $files
Check ($zip -is [byte[]] -and $zip.Length -gt 20) 'New-ZipBytes trả byte[]'
$rz = Read-ZipBytes $zip
Check ($rz.Count -eq 2 -and (Test-SameBytes $rz['WiFi\001.xml'] $files['WiFi\001.xml']) -and (Test-SameBytes $rz['Claude\AppData-Claude\Claude Extensions Settings\x\y.json'] ([byte[]](0, 1, 2, 255)))) 'zip đọc lại đúng tên, đúng nội dung'

Write-Host '== Get-BackupInfo'
$bk = Join-Path $Root 'bk'
New-Item -ItemType Directory -Force -Path "$bk\a", "$bk\b", "$bk\c", "$bk\DuLieu_SaoLuu_cu_20261001_100000", "$bk\none" | Out-Null
Save-Json @{ TrangThai = 'xong'; May = 'MAYGIA'; NguoiDung = 'gia'; BatDau = '2026-10-05T10:00:00'; MaHoa = $true } "$bk\a\manifest.json"
Save-Json @{ TrangThai = 'dang-lam'; BatDau = '2026-10-06T10:00:00' } "$bk\b\manifest.json"
Set-Content -LiteralPath "$bk\c\manifest.json" -Value '{hỏng' -Encoding UTF8
Save-Json @{ Date = '2026-10-01 10:00:00'; Computer = 'MAYCU'; UserName = 'cu' } "$bk\DuLieu_SaoLuu_cu_20261001_100000\thong-tin.json"
$a = Get-BackupInfo "$bk\a"
Check ($a.State -eq 'xong' -and $a.Encrypted -and $a.Computer -eq 'MAYGIA' -and $a.Time.Day -eq 5) 'manifest xong, mã hoá'
Check ((Get-BackupInfo "$bk\b").State -eq 'dang-lam') 'manifest đang làm'
Check ((Get-BackupInfo "$bk\c").State -eq 'hong') 'manifest hỏng'
$o = Get-BackupInfo "$bk\DuLieu_SaoLuu_cu_20261001_100000"
Check ($o.State -eq 'xong' -and $o.Legacy -and $o.Old) 'bản cũ chỉ có thong-tin.json: coi là xong, đánh dấu cũ'
Check ($null -eq (Get-BackupInfo "$bk\none")) 'thư mục thường không phải bản sao lưu'

Write-Host '== nơi lưu'
Check ((Resolve-SaveDir 'E:') -eq 'E:\DuLieu_SaoLuu') "Resolve-SaveDir E: -> $(Resolve-SaveDir 'E:')"
Check ((Resolve-SaveDir 'E:\') -eq 'E:\DuLieu_SaoLuu') 'Resolve-SaveDir E:\'
Check ((Resolve-SaveDir 'D:\SaoLuu\DuLieu_SaoLuu\') -eq 'D:\SaoLuu\DuLieu_SaoLuu') 'tên cuối đã là DuLieu_SaoLuu'
Check ((Resolve-SaveDir '"D:\Sao Luu"') -eq 'D:\Sao Luu\DuLieu_SaoLuu') 'bỏ ngoặc kép'
$why = Test-SaveDir "$ToolsDir\new-windows\DuLieu_SaoLuu"
Check ($why -like '*Trạm Tool*') "từ chối lưu trong thư mục công cụ ($why)"
Check ((Test-SaveDir "$RepoRoot\DuLieu_SaoLuu") -like '*Trạm Tool*') 'từ chối lưu trong thư mục Trạm Tool'
Check ((Test-SaveDir 'DuLieu_SaoLuu') -like 'phải là đường dẫn đầy đủ*') 'từ chối đường dẫn tương đối'
$free = [char[]](70..90) | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -First 1
Check ((Test-SaveDir "$($free):\DuLieu_SaoLuu") -like 'không có ổ*') "từ chối ổ không có ($free)"
Check ((Test-SaveDir (Join-Path $Root 'usb\DuLieu_SaoLuu')) -eq '') 'nhận thư mục hợp lệ'
Check ((Format-TargetArg 'E:\.') -eq 'E:\' -and (Format-TargetArg 'e:') -eq 'E:\' -and (Format-TargetArg 'D:\x\') -eq 'D:\x' -and (Format-TargetArg '"D:\x"') -eq 'D:\x') 'Format-TargetArg'

Write-Host '== chọn bản sao lưu'
$script:ToolDir = Join-Path $Root 'tool'
New-Item -ItemType Directory -Force -Path $script:ToolDir | Out-Null
$script:Opt = @{ Target = ''; Phan = ''; Driver = ''; MaHoa = $false; DryRun = $false }
$script:Yes = $true
# bản mới đang làm dở + bản _cu_ đã xong cạnh công cụ
New-Item -ItemType Directory -Force -Path "$($script:ToolDir)\DuLieu_SaoLuu", "$($script:ToolDir)\DuLieu_SaoLuu_cu_20261001_090000" | Out-Null
Save-Json @{ TrangThai = 'dang-lam'; BatDau = '2026-10-08T10:00:00' } "$($script:ToolDir)\DuLieu_SaoLuu\manifest.json"
Save-Json @{ TrangThai = 'xong'; BatDau = '2026-10-01T09:00:00' } "$($script:ToolDir)\DuLieu_SaoLuu_cu_20261001_090000\manifest.json"
$found = @(Find-Backups)
Check ($found.Count -eq 2) "Find-Backups thấy 2 bản cạnh công cụ ($($found.Count))"
$script:Warnings.Clear()
$p = Select-Backup
Check ($null -eq $p) '-Yes không tự dùng bản _cu_'
Check (@($script:Warnings | Where-Object { $_ -like '*CHƯA XONG*' }).Count -eq 1) 'báo bản đang làm dở bị bỏ qua'
# trả lời "c" qua đầu vào chuyển hướng: không làm được trong cùng tiến trình, thử ở 3_TrangThai (C3)
$script:Opt.Target = "$($script:ToolDir)\DuLieu_SaoLuu"
$script:Errors.Clear()
Check ($null -eq (Select-Backup)) '-Target trỏ bản đang làm dở: từ chối'
Check (@($script:Errors | Where-Object { $_ -like '*CHƯA XONG*' }).Count -eq 1) 'lỗi nêu rõ CHƯA XONG'
$script:Opt.Target = "$($script:ToolDir)\DuLieu_SaoLuu_cu_20261001_090000"
$p = Select-Backup
Check ($p -and $p.Old -and $p.State -eq 'xong') '-Target trỏ thẳng bản _cu_: dùng (người dùng đã chỉ rõ)'
$script:Opt.Target = "$($free):\DuLieu_SaoLuu"
$script:Errors.Clear()
$e = $null; try { $p = Select-Backup } catch { $e = $_ }
Check ($null -eq $e -and $null -eq $p -and @($script:Errors | Where-Object { $_ -like 'Không thấy bản sao lưu*' }).Count -eq 1) '-Target trỏ ổ không có: báo gọn, không văng lỗi'
$script:Opt.Target = $script:ToolDir
$script:Errors.Clear()
Check ($null -eq (Select-Backup)) '-Target là thư mục cha có DuLieu_SaoLuu dở: từ chối'
# thêm bản xong mới hơn ở nơi lần xuất trước ghi trong ket_qua
$usb = Join-Path $Root 'usb'
New-Item -ItemType Directory -Force -Path "$usb\DuLieu_SaoLuu" | Out-Null
Save-Json @{ TrangThai = 'mot-phan'; BatDau = '2026-10-09T08:00:00'; Loi = @('lỗi giả') } "$usb\DuLieu_SaoLuu\manifest.json"
New-Item -ItemType Directory -Force -Path $script:ResultDir | Out-Null
Save-Json @{ ThuMucSaoLuu = "$usb\DuLieu_SaoLuu" } (Join-Path $script:ResultDir 'KetQua_ChuyenDuLieu_xuat_MAYGIA_20261009_080000.json')
$script:Opt.Target = ''
$p = Select-Backup
Check ($p -and $p.Path -eq "$usb\DuLieu_SaoLuu" -and $p.State -eq 'mot-phan') "tự tìm qua ket_qua, ưu tiên bản không cũ ($($p.Path))"

Complete-Test
