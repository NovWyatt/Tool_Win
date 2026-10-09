<#
  Máy ảo Windows 11 để chạy thật các nút sửa của Trạm Tool (thay cho chỉ thử bằng giả lập). Dùng VirtualBox, không
  cần quyền Admin (cài VirtualBox thì cần, một lần).

  Không tham số: tạo máy ảo <Ten> trong <ThuMuc> rồi cài Windows tự động:
    - Firmware EFI, TPM 2.0, Secure Boot (khoá của Microsoft).
    - RAM, CPU, ổ đĩa ảo theo tham số.
    - Mạng NAT (không cài driver mạng lên máy thật).
    - Thư mục repo chia sẻ chỉ đọc (\\VBOXSVR\Tool_Win, ổ tự gắn trong máy ảo).
    - Guest Additions.
    Tài khoản thử của máy ảo có mật khẩu ngẫu nhiên, ghi vào <ThuMuc>\<Ten>\TaiKhoanThu.txt (không in ra màn hình).
    Cài xong (thấy màn hình Windows, Guest Additions đã chạy) thì chạy lại với -ChupNhanh.
  -ChupNhanh:  chụp nhanh tên "Sach" (máy mới cài), làm mốc trả về.
  -TraVeSach:  tắt máy ảo, trả về bản chụp "Sach", mở lại. Dùng sau mỗi lần thử nút sửa.
  -ChiSoAnh N: chọn bản Windows trong ISO (mặc định tìm Windows 11 Pro).
  -ChayThu:    chỉ in các lệnh VBoxManage sẽ chạy.
  Mã thoát: 0 xong, 1 lỗi, 2 thiếu điều kiện (chưa cài VirtualBox, thiếu ISO, máy ảo đã có).
#>
param(
    [string]$Ten = 'TramTool-Win11',
    [string]$Iso = 'D:\SETUP\Win11_26300_x64_en-US.iso',
    [string]$ThuMuc = 'D:\VirtualBox VMs',
    [string]$Repo = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [int]$RamMB = 4096,
    [int]$Cpu = 2,
    [int]$DiaGB = 64,
    [int]$ChiSoAnh = 0,
    [switch]$ChupNhanh,
    [switch]$TraVeSach,
    [switch]$ChayThu
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

function Find-VBoxManage {
    if ($env:TRAMTOOL_VBOXMANAGE) { return $env:TRAMTOOL_VBOXMANAGE }
    $dirs = @()
    $k = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Oracle\VirtualBox' -ErrorAction SilentlyContinue
    if ($k -and $k.InstallDir) { $dirs += [string]$k.InstallDir }
    $dirs += 'D:\Program Files\Oracle\VirtualBox', 'D:\Program Files\VirtualBox', "$env:ProgramFiles\Oracle\VirtualBox"
    foreach ($d in $dirs) { $p = Join-Path $d 'VBoxManage.exe'; if (Test-Path -LiteralPath $p) { return $p } }
    return $null
}

$script:VBox = Find-VBoxManage
function VBox {
    # Chạy VBoxManage, in lệnh (giấu đường dẫn file mật khẩu không cần); lỗi thì dừng.
    param([string[]]$A, [switch]$Doc)
    Write-Host ('  > VBoxManage ' + (($A | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')) -ForegroundColor DarkGray
    if ($ChayThu -and -not $Doc) { return @() }
    $ErrorActionPreference = 'Continue'
    $out = & $script:VBox @A 2>&1 | ForEach-Object { [string]$_ }
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($code -ne 0) { $out | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }; throw "VBoxManage $($A[0]) lỗi (mã $code)." }
    return $out
}

function New-MatKhau {
    $chu = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $b = New-Object byte[] 16
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    return -join ($b | ForEach-Object { $chu[$_ % $chu.Length] })
}

if (-not $script:VBox) {
    if (-not $ChayThu) {
        Write-Host '  [X] Chưa cài VirtualBox. Cài (cần quyền Admin, một lần) rồi chạy lại.' -ForegroundColor Red
        exit 2
    }
    $script:VBox = 'VBoxManage.exe'
}
$vmDir = Join-Path $ThuMuc $Ten

try {
    if ($ChupNhanh) {
        [void](VBox @('snapshot', $Ten, 'take', 'Sach', '--description', 'Windows mới cài, có Guest Additions; mốc trả về sau mỗi lần thử nút sửa.'))
        Write-Host '  [OK] Đã chụp nhanh "Sach".' -ForegroundColor Green
        exit 0
    }
    if ($TraVeSach) {
        $st = if ($ChayThu) { @() } else { VBox @('showvminfo', $Ten, '--machinereadable') -Doc }
        if (@($st | Where-Object { $_ -match '^VMState="(running|paused|stuck)"' }).Count) { [void](VBox @('controlvm', $Ten, 'poweroff')); if (-not $ChayThu) { Start-Sleep -Seconds 3 } }
        [void](VBox @('snapshot', $Ten, 'restore', 'Sach'))
        [void](VBox @('startvm', $Ten, '--type', 'gui'))
        Write-Host '  [OK] Máy ảo đã về bản "Sach" và đang mở.' -ForegroundColor Green
        exit 0
    }

    if (-not (Test-Path -LiteralPath $Iso)) { Write-Host "  [X] Không thấy file ISO: $Iso" -ForegroundColor Red; exit 2 }
    if (-not $ChayThu) {
        $vms = VBox @('list', 'vms') -Doc
        if (@($vms | Where-Object { $_ -match ('^"' + [regex]::Escape($Ten) + '"') }).Count) {
            Write-Host "  [X] Đã có máy ảo $Ten. Muốn làm lại thì xoá nó trong VirtualBox trước (Remove > Delete all files)." -ForegroundColor Red
            exit 2
        }
    }
    if ($ChiSoAnh -le 0 -and -not $ChayThu) {
        $det = VBox @('unattended', 'detect', "--iso=$Iso") -Doc
        $det | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        foreach ($l in $det) {
            if ($l -match '(?i)(?:#|index\s*[=:]?\s*)(\d+)\b.*windows 11 pro\b(?!\s*(n\b|education|for workstations))') { $ChiSoAnh = [int]$Matches[1]; break }
        }
        if ($ChiSoAnh -le 0) { Write-Host '  [X] Không tìm ra Windows 11 Pro trong ISO. Xem danh sách trên, chạy lại với -ChiSoAnh <số>.' -ForegroundColor Red; exit 2 }
    }

    $disk = Join-Path $vmDir "$Ten.vdi"
    [void](VBox @('createvm', '--name', $Ten, '--ostype', 'Windows11_64', '--basefolder', $ThuMuc, '--register'))
    [void](VBox @('modifyvm', $Ten, "--memory=$RamMB", "--cpus=$Cpu", '--ioapic=on', '--firmware=efi', '--tpm-type=2.0',
            '--graphicscontroller=vboxsvga', '--vram=128', '--nic1=nat', '--clipboard-mode=bidirectional'))
    [void](VBox @('modifynvram', $Ten, 'inituefivarstore'))
    [void](VBox @('modifynvram', $Ten, 'enrollmssignatures'))
    [void](VBox @('modifynvram', $Ten, 'enrollorclpk'))
    [void](VBox @('modifynvram', $Ten, 'secureboot', '--enable'))
    [void](VBox @('storagectl', $Ten, '--name', 'SATA', '--add', 'sata', '--controller', 'IntelAhci', '--portcount', '4', '--bootable', 'on'))
    [void](VBox @('createmedium', 'disk', '--filename', $disk, '--size', [string]($DiaGB * 1024), '--format', 'VDI'))
    [void](VBox @('storageattach', $Ten, '--storagectl', 'SATA', '--port', '0', '--device', '0', '--type', 'hdd', '--medium', $disk))
    [void](VBox @('sharedfolder', 'add', $Ten, '--name', 'Tool_Win', '--hostpath', $Repo, '--readonly', '--automount'))

    # Tài khoản thử: mật khẩu ngẫu nhiên vào file trong thư mục máy ảo, không in ra.
    $tk = Join-Path $vmDir 'TaiKhoanThu.txt'
    $pwFile = Join-Path $vmDir 'mat-khau.tmp'
    if (-not $ChayThu) {
        if (-not (Test-Path -LiteralPath $vmDir)) { New-Item -ItemType Directory -Path $vmDir -Force | Out-Null }
        $mk = New-MatKhau
        [IO.File]::WriteAllText($tk, "Máy ảo $Ten (chỉ để thử, không dùng mật khẩu này ở đâu khác)`r`nTài khoản: thu`r`nMật khẩu: $mk`r`n", (New-Object Text.UTF8Encoding $true))
        [IO.File]::WriteAllText($pwFile, $mk, (New-Object Text.UTF8Encoding $false))
        $mk = $null
    }
    try {
        [void](VBox @('unattended', 'install', $Ten, "--iso=$Iso", '--user=thu', "--password-file=$pwFile", '--full-user-name=Thu Nghiem',
                "--image-index=$(if ($ChiSoAnh -gt 0) { $ChiSoAnh } else { '<Windows 11 Pro>' })", '--locale=en_US', '--country=VN',
                '--hostname=tramtool-thu.local', '--install-additions', '--start-vm=gui'))
    } finally { if (Test-Path -LiteralPath $pwFile) { Remove-Item -LiteralPath $pwFile -Force } }

    Write-Host ''
    if ($ChayThu) { Write-Host '  [i] Chạy thử: chưa tạo gì.' -ForegroundColor Gray; exit 0 }
    Write-Host "  [OK] Đã tạo máy ảo $Ten và bắt đầu cài Windows (khoảng 20-40 phút, máy ảo tự khởi động lại vài lần)." -ForegroundColor Green
    Write-Host "       Tài khoản thử: $tk"
    Write-Host '       Setup hỏi khoá sản phẩm thì chọn "I don''t have a product key". Bản cài không kích hoạt vẫn đủ để thử.'
    Write-Host "       Cài xong, thấy màn hình Windows thì chạy: powershell -File `"$PSCommandPath`" -ChupNhanh"
    exit 0
} catch {
    Write-Host "  [X] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
