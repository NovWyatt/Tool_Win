
# ----------------------------------------------------------------------------
function Invoke-Backup {
    Step 'BƯỚC 2 - SAO LƯU (registry + file hoàn tác)'
    # Sao lưu có số tài khoản ngân hàng và bản sao file Excel: để trong thư mục riêng của tài khoản, không để trên
    # Desktop (thường đồng bộ OneDrive) như bản trước 2026.10.2
    $root = Get-MyxDataDir 'SaoLuu'
    $script:BackupDir = Join-Path $root "MyExcelFix_SaoLuu_$($script:Stamp)"
    try {
        New-Item -ItemType Directory -Path $script:BackupDir -Force -ErrorAction Stop | Out-Null
    } catch {
        Warn "Không tạo được thư mục sao lưu $($script:BackupDir): $($_.Exception.Message)"
        return $false
    }
    Note "Thư mục sao lưu (riêng của tài khoản này): $($script:BackupDir)"
    if (-not $env:MYX_OUT -or $env:MYX_DESKTOP) {
        $old = @(Get-ChildItem -LiteralPath (Get-DesktopDir) -Directory -Filter 'MyExcelFix_SaoLuu_*' -ErrorAction SilentlyContinue)
        if ($old.Count) {
            Note "Trên Desktop còn $($old.Count) thư mục sao lưu của bản cũ (có số tài khoản ngân hàng, Desktop thường đồng bộ OneDrive)."
            Note 'Không cần hoàn tác các lần sửa đó nữa thì xoá đi; cần thì HOAN_TAC.bat vẫn liệt kê và dùng được.'
        }
    }

    $regRoot = 'HKCU\' + $script:RegBase
    foreach ($ver in (Get-ExcelVersions)) {
        $file = "Excel_$ver.reg"
        & reg.exe export "$($regRoot)Software\Microsoft\Office\$ver\Excel" (Join-Path $script:BackupDir $file) /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Warn "Không sao lưu được HKCU\...\Office\$ver\Excel (mã lỗi $LASTEXITCODE)"; return $false }
        $script:Manifest.RegExcel += [ordered]@{ Ver = $ver; File = $file }
        Done "Đã sao lưu cấu hình Excel $ver -> $file"
    }
    if (Open-UserKey 'Software\VB and VBA Program Settings') {
        & reg.exe export "$($regRoot)Software\VB and VBA Program Settings" (Join-Path $script:BackupDir 'VBA_Settings.reg') /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Warn "Không sao lưu được dữ liệu MyExcel trong VB and VBA Program Settings (mã lỗi $LASTEXITCODE)"; return $false }
        $script:Manifest.RegVB = 'VBA_Settings.reg'
        Done 'Đã sao lưu dữ liệu MyExcel (VB and VBA Program Settings) -> VBA_Settings.reg'
    }
    try {
        Copy-Item -LiteralPath $env:MYX_SELF -Destination (Join-Path $script:BackupDir 'HoanTac_FixMyExcel.bat') -Force -ErrorAction Stop
        Done 'Đã tạo file hoàn tác HoanTac_FixMyExcel.bat trong thư mục sao lưu'
    } catch {
        Warn "Không tạo được file hoàn tác: $($_.Exception.Message)"
        return $false
    }
    Save-Manifest
    return $true
}
