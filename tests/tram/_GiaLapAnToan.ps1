
# ===== GIẢ LẬP (nối vào cuối bản sao Common.ps1/AnToan.ps1 để thử, không đổi gì trên máy) =====
function Test-IsAdmin { return ($env:MOCK_ADMIN -ne '0') }

function Get-RestoreStatus {
    $r = [ordered]@{ enabled = $true; diskPercent = 15; policyOff = $false; configLocked = $false; vssDisabled = $false; detail = 'Đang bật.' }
    switch ($env:MOCK_RS) {
        'off' { $r.enabled = $false; $r.detail = 'Bảo vệ hệ thống (System Protection) đang tắt (giả lập).' }
        'policy' { $r.enabled = $false; $r.policyOff = $true; $r.detail = 'Chính sách nhóm (Group Policy) đang tắt Bảo vệ hệ thống (giả lập).' }
        'vss' { $r.vssDisabled = $true; $r.detail = 'VSS bị vô hiệu hoá (giả lập).' }
        'locked' { $r.enabled = $false; $r.configLocked = $true; $r.detail = 'Tắt và bị khoá (giả lập).' }
    }
    return $r
}
function Enable-SystemProtection {
    if ($env:MOCK_ENABLE -eq 'fail') { throw 'Giả lập: Enable-ComputerRestore lỗi 0x80070422' }
    Write-Host '  (giả lập) Enable-ComputerRestore'
}
function New-SystemRestorePoint {
    param([string]$Description, [string]$Type = 'MODIFY_SETTINGS', [int]$TimeoutSec = 600)
    Write-Host "  (giả lập) Checkpoint-Computer '$Description'"
    switch ($env:MOCK_RP) {
        'ok' { return [ordered]@{ created = $true; seq = 42; at = (Get-Date '2026-10-05T10:33:00'); message = '' } }
        'throw' { throw 'Giả lập: lỗi bất ngờ trong New-SystemRestorePoint' }
        default { return [ordered]@{ created = $false; seq = $null; at = $null; message = 'Giả lập: 0x81000101 timed out' } }
    }
}
function Read-AtChoice {
    param([string]$Prompt, [string[]]$Keys, [string]$Fallback)
    $list = @(([string]$env:MOCK_ANSWERS).Split(',') | Where-Object { $_ })
    if ($null -eq $global:MockAnsIdx) { $global:MockAnsIdx = 0 }
    while ($global:MockAnsIdx -lt $list.Count) {
        $a = $list[$global:MockAnsIdx].Trim().ToUpperInvariant(); $global:MockAnsIdx++
        Write-Host "  ? $Prompt >> $a"
        if ($Keys -contains $a) { return $a }
        Write-Host ('  Gõ {0} rồi Enter.' -f ($Keys -join ', '))
    }
    Write-Host "  ? $Prompt >> (hết câu trả lời) $Fallback"
    return $Fallback
}
function Wait-AtClose { Write-Host '  (giả lập) bấm phím đóng' }
function Restore-SnapshotItem {
    param($Item)
    if ([string]$Item.label -match 'loi') { throw 'Giả lập: sc config báo mã 5' }
    Write-Host "  (giả lập) trả lại $($Item.label)"
    return 'ok'
}
function Get-WingetStatus {
    $list = @(([string]$env:MOCK_WG).Split(',') | Where-Object { $_ })
    if ($null -eq $global:MockWgIdx) { $global:MockWgIdx = 0 }
    $stage = $list[[Math]::Min($global:MockWgIdx, $list.Count - 1)]
    $global:MockWgIdx++
    $r = [ordered]@{ ok = $false; stage = $stage; version = ''; appInstaller = '1.29.379.0'; path = 'C:\x\winget.exe'; problem = '' }
    switch ($stage) {
        'ok' { $r.ok = $true; $r.stage = ''; $r.version = 'v1.29.380' }
        'install' { $r.path = ''; $r.problem = 'Giả lập: lệnh winget chưa được đăng ký cho tài khoản này.' }
        'run' { $r.problem = 'Giả lập: winget báo lỗi khi chạy (mã 0x8A15000F).' }
        'source' { $r.version = 'v1.29.380'; $r.problem = 'Giả lập: winget thiếu nguồn chính "winget".' }
    }
    return $r
}
function Add-AppxPackage { Write-Host "  (giả lập) Add-AppxPackage $($args -join ' ')" }
