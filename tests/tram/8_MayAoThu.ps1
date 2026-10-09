# Bài thử hub\dev\TaoMayAoThu.ps1 (máy ảo Windows 11 để chạy thật nút sửa): chạy thử in đủ lệnh (EFI, TPM 2.0, Secure
# Boot, NAT, thư mục repo chỉ đọc, cài tự động có Guest Additions); VBoxManage.exe giả (TRAMTOOL_VBOXMANAGE) ghi lại
# lệnh: chọn đúng Windows 11 Pro trong ISO, mật khẩu chỉ nằm trong file của máy ảo, file mật khẩu tạm bị xoá; máy ảo đã
# có, thiếu ISO; chụp nhanh, trả về bản sạch. Không cần VirtualBox, không tạo máy ảo thật.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$script = Join-Path $HubDir 'dev\TaoMayAoThu.ps1'
$ps = Join-Path $PSHOME 'powershell.exe'
$iso = Join-Path (New-TestDir 'iso') 'Win11.iso'
[IO.File]::WriteAllBytes($iso, [byte[]](1, 2, 3))
function Run([string[]]$A, [hashtable]$Env = @{}) {
    $old = @{}
    foreach ($k in $Env.Keys) { $old[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    try { $o = & $ps -NoProfile -ExecutionPolicy Bypass -File $script @A 2>&1 | Out-String }
    finally { foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $old[$k]) } }
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o }
}

$vm = New-TestDir 'vm'
$r = Run @('-ChayThu', '-Iso', $iso, '-ThuMuc', $vm) @{ TRAMTOOL_VBOXMANAGE = 'VBoxManage.exe' }
Check ($r.Code -eq 0) "chạy thử: mã 0 ($($r.Code))"
$need = 'createvm --name TramTool-Win11 --ostype Windows11_64', '--firmware=efi', '--tpm-type=2.0', 'modifynvram TramTool-Win11 enrollmssignatures', 'secureboot --enable', '--nic1=nat', 'sharedfolder add TramTool-Win11 --name Tool_Win', '--readonly', 'unattended install TramTool-Win11', '--install-additions', 'storageattach'
$miss = @($need | Where-Object { $r.Out -notmatch [regex]::Escape($_) })
Check (-not $miss.Count) "in đủ lệnh tạo máy ảo (thiếu: $($miss -join '; '))"
Check (-not @(Get-ChildItem -LiteralPath $vm -Recurse -Force).Count -and $r.Out -notmatch 'Mật khẩu:') 'chạy thử không tạo file, không in mật khẩu'
$r = Run @('-ChayThu', '-Iso', (Join-Path $vm 'khong-co.iso'), '-ThuMuc', $vm) @{ TRAMTOOL_VBOXMANAGE = 'VBoxManage.exe' }
Check ($r.Code -eq 2 -and $r.Out -match 'Không thấy file ISO') "thiếu ISO: mã 2 ($($r.Code))"
$r = Run @('-ChayThu', '-ChupNhanh') @{ TRAMTOOL_VBOXMANAGE = 'VBoxManage.exe' }
Check ($r.Code -eq 0 -and $r.Out -match 'snapshot TramTool-Win11 take Sach') 'chụp nhanh "Sach"'
$r = Run @('-ChayThu', '-TraVeSach') @{ TRAMTOOL_VBOXMANAGE = 'VBoxManage.exe' }
Check ($r.Code -eq 0 -and $r.Out -match 'snapshot TramTool-Win11 restore Sach' -and $r.Out -match 'startvm TramTool-Win11') 'trả về bản "Sach" rồi mở lại'

# VBoxManage giả: ghi tham số vào FAKE_VBOX_LOG; "list vms" in FAKE_VBOX_VMS; "unattended detect" in danh sách bản Windows.
$fake = New-FakeExe (Join-Path (New-TestDir 'gia') 'VBoxManage.exe') @'
File.AppendAllText(Environment.GetEnvironmentVariable("FAKE_VBOX_LOG"), string.Join(" ", a) + Environment.NewLine);
if (a.Length > 0 && a[0] == "list") { Console.WriteLine(Environment.GetEnvironmentVariable("FAKE_VBOX_VMS") ?? ""); }
if (a.Length > 1 && a[0] == "unattended" && a[1] == "detect") {
    Console.WriteLine("Detected 'x.iso' to be:");
    Console.WriteLine("    OS TypeId    = Windows11_64");
    Console.WriteLine("    Image #1: Windows 11 Home");
    Console.WriteLine("    Image #5: Windows 11 Pro N");
    Console.WriteLine("    Image #6: Windows 11 Pro");
}
if (a.Length > 1 && a[0] == "unattended" && a[1] == "install") {
    foreach (var x in a) { if (x.StartsWith("--password-file=")) { File.WriteAllText(Environment.GetEnvironmentVariable("FAKE_VBOX_LOG") + ".pw", File.Exists(x.Substring(16)) ? "co" : "khong"); } }
}
return 0;
'@
$log = Join-Path $TestRoot 'vbox.log'
$vm2 = New-TestDir 'vm2'
$r = Run @('-Iso', $iso, '-ThuMuc', $vm2, '-Repo', $RepoRoot) @{ TRAMTOOL_VBOXMANAGE = $fake; FAKE_VBOX_LOG = $log; FAKE_VBOX_VMS = '"May khac" {1111}' }
$calls = @(Get-Content -LiteralPath $log -Encoding UTF8)
Check ($r.Code -eq 0) "tạo máy ảo với VBoxManage giả: mã 0 ($($r.Code))"
$order = @('list vms', 'unattended detect', 'createvm', 'modifyvm', 'modifynvram TramTool-Win11 inituefivarstore', 'modifynvram TramTool-Win11 secureboot --enable', 'storagectl', 'createmedium', 'storageattach', 'sharedfolder add', 'unattended install')
$idx = @($order | ForEach-Object { $o = $_; $i = 0; $f = -1; foreach ($c in $calls) { if ($c.StartsWith($o)) { $f = $i; break }; $i++ }; $f })
Check (-not @($idx | Where-Object { $_ -lt 0 }).Count -and (($idx | Sort-Object) -join ',') -eq ($idx -join ',')) "gọi đủ lệnh theo thứ tự ($($idx -join ','))"
$inst = @($calls | Where-Object { $_ -like 'unattended install*' })[0]
Check ($inst -match '--image-index=6(\s|$)' -and $inst -match '--user=thu' -and $inst -notmatch 'Mật khẩu') "chọn Windows 11 Pro (không chọn Pro N): $(([regex]::Match($inst, '--image-index=\S+')).Value)"
Check ($calls -match "--hostpath $([regex]::Escape($RepoRoot))") 'chia sẻ đúng thư mục repo'
$tk = Join-Path $vm2 'TramTool-Win11\TaiKhoanThu.txt'
$tkText = if (Test-Path -LiteralPath $tk) { [IO.File]::ReadAllText($tk) } else { '' }
$mk = ([regex]::Match($tkText, 'Mật khẩu: (\S+)')).Groups[1].Value
Check ($mk.Length -eq 16 -and $r.Out -notmatch [regex]::Escape($mk) -and $r.Out -match 'TaiKhoanThu\.txt') 'mật khẩu ngẫu nhiên 16 ký tự chỉ nằm trong TaiKhoanThu.txt, màn hình chỉ in đường dẫn file'
Check (([IO.File]::ReadAllText("$log.pw")) -eq 'co' -and -not (Test-Path -LiteralPath (Join-Path $vm2 'TramTool-Win11\mat-khau.tmp'))) 'file mật khẩu tạm có lúc cài, bị xoá sau đó'
Remove-Item -LiteralPath $log
$r = Run @('-Iso', $iso, '-ThuMuc', $vm2) @{ TRAMTOOL_VBOXMANAGE = $fake; FAKE_VBOX_LOG = $log; FAKE_VBOX_VMS = '"TramTool-Win11" {2222}' }
Check ($r.Code -eq 2 -and $r.Out -match 'Đã có máy ảo' -and -not @(Get-Content -LiteralPath $log | Where-Object { $_ -like 'createvm*' }).Count) "máy ảo đã có: mã 2, không tạo lại ($($r.Code))"

Complete-Test
