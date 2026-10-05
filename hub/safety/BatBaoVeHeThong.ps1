<#
  Trạm Tool - bật Bảo vệ hệ thống (System Protection) cho ổ Windows rồi tạo điểm khôi phục đầu tiên.
  Mở từ trang Máy này của trạm (quyền Admin). Hỏi trước khi bật; không đổi dung lượng tối đa Windows đặt sẵn.
  Mã thoát: 0 = xong, 1 = lỗi, 2 = không làm được (thiếu Admin, chính sách nhóm chặn), 1223 = người dùng huỷ.
#>
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
. (Join-Path $PSScriptRoot '..\lib\Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\AnToan.ps1')
$Host.UI.RawUI.WindowTitle = 'Trạm Tool - bật Bảo vệ hệ thống'

Write-AtHead 'BẬT BẢO VỆ HỆ THỐNG (SYSTEM PROTECTION)' "Ổ Windows: $($env:SystemDrive)"
if (-not (Test-IsAdmin)) { Write-AtBad 'Cần quyền Admin.'; Wait-AtClose; exit 2 }

$st = Get-RestoreStatus
if ($st.policyOff -or $st.configLocked -or $st.vssDisabled) {
    Write-AtBad $st.detail
    if ($st.vssDisabled) { Write-AtInfo 'Bật lại: services.msc > Volume Shadow Copy > Startup type: Manual, rồi chạy lại.' }
    else { Write-AtInfo 'Máy do công ty quản lý thường đặt như vậy; hỏi người quản trị.' }
    Wait-AtClose
    exit 2
}

if ($st.enabled) {
    Write-AtOk "Bảo vệ hệ thống đã bật sẵn cho máy này."
    Write-Host ''
    $c = Read-AtChoice -Prompt '[T] Tạo một điểm khôi phục ngay   [D] Đóng' -Keys @('T', 'D') -Fallback 'D'
    if ($c -eq 'D') { exit 0 }
} else {
    $pct = if ($st.diskPercent) { "khoảng $($st.diskPercent)%" } else { 'một phần' }
    Write-AtInfo 'Bảo vệ hệ thống giúp quay lại trạng thái trước khi cài phần mềm, driver hoặc sửa máy (không đụng tài liệu).'
    Write-AtInfo "Windows dùng tối đa $pct dung lượng ổ $($env:SystemDrive) cho điểm khôi phục, tự xoá điểm cũ khi đầy;"
    Write-AtInfo 'từ Windows 11 24H2 mỗi điểm giữ tối đa 60 ngày. Chỉ bật cho ổ Windows, ổ khác giữ nguyên.'
    Write-AtInfo 'Tắt lại: sysdm.cpl > System Protection > Configure > Disable protection.'
    Write-Host ''
    $c = Read-AtChoice -Prompt '[B] Bật và tạo điểm khôi phục đầu tiên   [H] Huỷ' -Keys @('B', 'H') -Fallback 'H'
    if ($c -eq 'H') { Write-AtInfo 'Đã huỷ, không thay đổi gì.'; Start-Sleep -Seconds 2; exit 1223 }
    try {
        Enable-SystemProtection
        Write-AtOk "Đã bật Bảo vệ hệ thống cho ổ $($env:SystemDrive)."
    } catch {
        Write-AtBad "Không bật được: $($_.Exception.Message.Trim())"
        Wait-AtClose
        exit 1
    }
}

Write-AtInfo 'Đang tạo điểm khôi phục (thường mất từ nửa phút đến vài phút)...'
$res = New-SystemRestorePoint -Description 'Trạm Tool: điểm khôi phục tạo tay' -Type 'MODIFY_SETTINGS' -TimeoutSec 600
if ($res.created) {
    $at = if ($res.at) { $res.at } else { Get-Date }
    Write-AtOk ('Đã tạo điểm khôi phục lúc {0:HH:mm:ss}.' -f $at)
    Write-AtInfo 'Từ giờ trạm tạo điểm khôi phục trước mỗi lần chạy công cụ đổi máy (tắt được trong Cài đặt).'
    Wait-AtClose
    exit 0
}
Write-AtBad "Không tạo được điểm khôi phục: $($res.message)"
$hint = Get-RestoreErrorHint $res.message
if ($hint) { Write-AtInfo $hint }
Wait-AtClose
exit 1
