# Phan dung chung cua cac script CheckWinFix (ThuThapThongTin.bat, 2-5). src\build.ps1 chep nguyen file nay vao
# giua hai dong dau moc CHUNG_BAT_DAU va CHUNG_KET_THUC cua moi .bat: moi .bat van chay doc lap (gui rieng cho
# khach duoc). Sua o day roi chay src\build.ps1, khong sua thang trong .bat.
# Script goi Save-KetQua phai dat truoc: $SCRIPT_VER, $T0 (gio bat dau), $OutDir, $isAdmin.

$script:FLAGS = New-Object System.Collections.ArrayList

function Test-QuyenAdmin {
  try { return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false }
}

function FLAG {
  # Phat hien cho Tram Tool: ma co dinh (khong doi khi sua chu), muc do (loi | canh-bao | thong-tin | ok), viec nen
  # chay tiep (<id cong cu>/<id action> trong Tram Tool), chi tiet. Cung cau thi chi ghi mot lan.
  param([string]$Ma, [string]$t, [string]$Muc = 'canh-bao', [string]$Tiep = '', [string]$ChiTiet = '')
  foreach ($x in $script:FLAGS) { if ($x.tieuDe -eq $t) { return } }
  $f = [ordered]@{ ma = $Ma; mucDo = $Muc; tieuDe = $t; chiTiet = $ChiTiet; cachSua = '' }
  if ($Tiep -match '^([a-z0-9-]+)/([A-Za-z0-9_-]+)$') { $f['chayTiep'] = [ordered]@{ congCu = $Matches[1]; action = $Matches[2] } }
  [void]$script:FLAGS.Add($f)
}

function Save-KetQua {
  # Ghi KetQua_CheckWinFix_<Ten>_<may>_<gio>.json (chuan tramtool.ketqua/1) canh bao cao: loi len dau. Tra duong dan, '' khi loi.
  param([string]$CheDo, [string]$Ten, [object[]]$Tep = @(), [string]$Message = '')
  $rank = @{ loi = 0; 'canh-bao' = 1; 'thong-tin' = 2; ok = 3 }
  $i = 0
  $sorted = @($script:FLAGS | ForEach-Object { [pscustomobject]@{ F = $_; L = $rank[[string]$_.mucDo]; I = $i++ } } | Sort-Object L, I | ForEach-Object { $_.F })
  $n = @{}
  foreach ($k in 'loi', 'canh-bao', 'thong-tin') { $n[$k] = @($sorted | Where-Object { $_.mucDo -eq $k }).Count }
  if (-not $Message) {
    $Message = if ($n['loi'] + $n['canh-bao']) { 'Có {0} lỗi, {1} cảnh báo; xem chi tiết và báo cáo.' -f $n['loi'], $n['canh-bao'] }
    elseif ($isAdmin) { 'Không thấy dấu hiệu bất thường qua các phép kiểm tự động.' } else { 'Chạy không có quyền Admin nên thiếu dữ liệu; chạy lại bằng quyền Admin.' }
  }
  $r = [ordered]@{
    chuan = 'tramtool.ketqua/1'; congCu = 'checkwinfix'; cheDo = $CheDo; phienBan = $SCRIPT_VER
    may = $env:COMPUTERNAME; taiKhoan = $env:USERNAME
    batDau = $T0.ToString('s'); ketThuc = (Get-Date).ToString('s')
    maThoat = 0; trangThai = 'xong'; chayThu = $false
    ma = $(if ($n['loi']) { 'CO_LOI' } elseif ($n['canh-bao']) { 'CO_CANH_BAO' } else { 'KHONG_CO_LOI' })
    thongDiep = $Message
    tomTat = [ordered]@{ loi = $n['loi']; canhBao = $n['canh-bao']; thongTin = $n['thong-tin'] }
    phatHien = $sorted
    tep = @($Tep)
    quyenAdmin = [bool]$isAdmin
  }
  $p = Join-Path $OutDir ('KetQua_CheckWinFix_{0}_{1}_{2}.json' -f $Ten, $env:COMPUTERNAME, $T0.ToString('yyyyMMdd_HHmmss'))
  try {
    [IO.File]::WriteAllText($p + '.tmp', ($r | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding $false))
    Move-Item -LiteralPath ($p + '.tmp') -Destination $p -Force -ErrorAction Stop
    return $p
  } catch { Write-Host ('  [!] Khong ghi duoc file ket qua JSON: ' + $_.Exception.Message) -ForegroundColor Yellow; return '' }
}

function Get-DiskBus {
  # Kieu ket noi cua o vat ly so N ('USB', 'NVMe', 'SATA'...); 'KHONG_CON' neu o khong con gan vao may (o rut ra);
  # '' neu khong doc duoc danh sach o.
  param([int]$Number)
  if ($null -eq $script:DiskBus) {
    $script:DiskBus = @{}
    try { foreach ($d in @(Get-Disk -ErrorAction Stop)) { $script:DiskBus[[int]$d.Number] = [string]$d.BusType } } catch { $script:DiskBus = @{ 'loi' = $true } }
  }
  if ($script:DiskBus.ContainsKey('loi')) { return '' }
  if ($script:DiskBus.ContainsKey($Number)) { return $script:DiskBus[$Number] }
  return 'KHONG_CON'
}

# ---- SMART (o ATA/SATA qua driver; NVMe va o USB thuong khong co bang nay)
$script:SMART_TEN = @{
  1 = 'Raw_Read_Error_Rate'; 5 = 'Reallocated_Sectors_Count'; 7 = 'Seek_Error_Rate'; 9 = 'Power_On_Hours'
  10 = 'Spin_Retry_Count'; 12 = 'Power_Cycle_Count'; 184 = 'End_to_End_Error'; 187 = 'Reported_Uncorrectable'
  188 = 'Command_Timeout'; 190 = 'Airflow_Temperature'; 194 = 'Temperature'; 196 = 'Reallocated_Event_Count'
  197 = 'Current_Pending_Sector'; 198 = 'Offline_Uncorrectable'; 199 = 'UDMA_CRC_Error_Count'
  200 = 'Multi_Zone_Error_Rate'; 231 = 'SSD_Life_Left'; 233 = 'Media_Wearout_Indicator'; 241 = 'Total_LBA_Written'
}

function ConvertFrom-SmartVendor {
  # Bang thuoc tinh tu VendorSpecific cua MSStorageDriver_FailurePredictData: 2 byte dau, roi 30 o x 12 byte
  # (ID, 2 byte co, Value, Worst, Raw 6 byte little-endian, 1 byte du). $Nguong: VendorSpecific cua
  # MSStorageDriver_FailurePredictThresholds cung o (ID, Threshold). Tra tung thuoc tinh co ID khac 0 (Nguong $null khi
  # khong co).
  param([byte[]]$Data = @(), [byte[]]$Nguong = @())
  $th = @{}
  for ($k = 0; $k -lt 30; $k++) {
    $b = 2 + 12 * $k
    if (($b + 1) -ge $Nguong.Count) { break }
    if ([int]$Nguong[$b] -ne 0) { $th[[int]$Nguong[$b]] = [int]$Nguong[$b + 1] }
  }
  for ($k = 0; $k -lt 30; $k++) {
    $b = 2 + 12 * $k
    if (($b + 11) -ge $Data.Count) { break }
    $id = [int]$Data[$b]
    if ($id -eq 0) { continue }
    $raw = [uint64]0
    for ($j = 5; $j -ge 0; $j--) { $raw = $raw * 256 + [uint64]$Data[$b + 5 + $j] }
    [pscustomobject]@{
      Id = $id; Ten = $(if ($script:SMART_TEN.ContainsKey($id)) { $script:SMART_TEN[$id] } else { 'Attr_' + $id })
      Value = [int]$Data[$b + 3]; Worst = [int]$Data[$b + 4]
      Nguong = $(if ($th.ContainsKey($id)) { $th[$id] } else { $null }); Raw = $raw
    }
  }
}

function Get-SmartThuocTinh {
  # Moi o co bang SMART: [pscustomobject]@{ O = InstanceName; ThuocTinh = @(ConvertFrom-SmartVendor) }. Can quyen Admin;
  # khong doc duoc thi khong tra gi.
  $nguong = @{}
  foreach ($t in @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictThresholds -OperationTimeoutSec 30 -ErrorAction SilentlyContinue)) {
    $nguong[[string]$t.InstanceName] = [byte[]]@($t.VendorSpecific)
  }
  foreach ($d in @(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictData -OperationTimeoutSec 30 -ErrorAction SilentlyContinue)) {
    $ng = if ($nguong.ContainsKey([string]$d.InstanceName)) { $nguong[[string]$d.InstanceName] } else { [byte[]]@() }
    [pscustomobject]@{ O = [string]$d.InstanceName; ThuocTinh = @(ConvertFrom-SmartVendor -Data ([byte[]]@($d.VendorSpecific)) -Nguong $ng) }
  }
}
