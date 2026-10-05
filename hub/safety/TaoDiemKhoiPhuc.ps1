<#
  Trạm Tool - tạo điểm khôi phục hệ thống ngay trước khi chạy công cụ đổi máy.
  Trạm chạy script này trong cửa sổ Admin của chính công cụ (cùng một lần hỏi UAC), rồi mới chạy công cụ:
    TaoDiemKhoiPhuc.ps1 -Tool <id> -Action <id> -RunTime <thời gian lần chạy> -Log <data\restore-points.jsonl>
  Mã thoát: 0 = chạy tiếp công cụ (đã tạo điểm, hoặc người dùng chọn chạy tiếp không có điểm);
            1223 = người dùng chọn huỷ, trạm không chạy công cụ.
  Kết quả ghi một dòng JSON vào -Log để trang Lịch sử hiện "Điểm khôi phục lúc ...".
#>
param(
    [string]$Tool = '',
    [string]$Action = '',
    [string]$RunTime = '',
    [string]$Log = ''
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
. (Join-Path $PSScriptRoot '..\lib\Common.ps1')
. (Join-Path $PSScriptRoot '..\lib\AnToan.ps1')

function Save-Result {
    param([hashtable]$Data)
    if (-not $Log) { return }
    $rec = [ordered]@{ time = $RunTime; toolId = $Tool; actionId = $Action; at = (Get-IsoTime) }
    foreach ($k in $Data.Keys) { $rec[$k] = $Data[$k] }
    try { Add-JsonLine -Path $Log -InputObject $rec } catch { Write-AtWarn "Không ghi được kết quả cho trạm: $($_.Exception.Message)" }
}

function Exit-Cancelled {
    Save-Result @{ created = $false; reason = 'cancelled' }
    Write-AtInfo 'Đã huỷ. Công cụ không chạy, máy không bị thay đổi.'
    Start-Sleep -Seconds 2
    exit 1223
}

function Exit-WithChoice {
    # Không tạo được điểm khôi phục: hỏi chạy tiếp hay huỷ (không có mặc định).
    param([string]$Reason, [string]$Message = '')
    Write-Host ''
    $c = Read-AtChoice -Prompt '[C] Chạy tiếp công cụ, không có điểm khôi phục   [H] Huỷ, không chạy công cụ' -Keys @('C', 'H') -Fallback 'H'
    if ($c -eq 'H') { Exit-Cancelled }
    Save-Result @{ created = $false; reason = $Reason; message = $Message }
    Write-Host ''
    exit 0
}

function Invoke-RestorePointStep {
    $st = Get-RestoreStatus
    if ($st.policyOff) {
        Write-AtWarn $st.detail
        Write-AtInfo 'Máy do công ty quản lý thường đặt như vậy; hỏi người quản trị nếu cần bật.'
        Exit-WithChoice -Reason 'policy'
    }
    if ($st.vssDisabled) {
        Write-AtWarn $st.detail
        Write-AtInfo 'Bật lại: services.msc > Volume Shadow Copy > Startup type: Manual.'
        Exit-WithChoice -Reason 'vss'
    }
    if ($st.enabled -eq $false) {
        Write-AtWarn 'Bảo vệ hệ thống (System Protection) đang tắt nên Windows chưa tạo được điểm khôi phục.'
        if ($st.configLocked) {
            Write-AtInfo 'Chính sách nhóm khoá phần cài đặt Bảo vệ hệ thống; hỏi người quản trị nếu cần bật.'
            Exit-WithChoice -Reason 'policy'
        }
        $pct = if ($st.diskPercent) { "khoảng $($st.diskPercent)%" } else { 'một phần' }
        Write-AtInfo "Bật cho ổ $($env:SystemDrive): Windows dùng tối đa $pct dung lượng ổ cho điểm khôi phục, tự xoá điểm cũ khi đầy."
        Write-AtInfo 'Chỉ bật cho ổ Windows; ổ khác giữ nguyên. Tắt lại: sysdm.cpl > System Protection > Configure.'
        Write-Host ''
        $c = Read-AtChoice -Prompt '[B] Bật rồi tạo điểm khôi phục   [C] Chạy tiếp, không tạo   [H] Huỷ, không chạy công cụ' -Keys @('B', 'C', 'H') -Fallback 'H'
        if ($c -eq 'H') { Exit-Cancelled }
        if ($c -eq 'C') { Save-Result @{ created = $false; reason = 'disabled' }; Write-Host ''; exit 0 }
        try {
            Enable-SystemProtection
            Write-AtOk "Đã bật Bảo vệ hệ thống cho ổ $($env:SystemDrive)."
        } catch {
            $m = $_.Exception.Message.Trim()
            Write-AtBad "Không bật được Bảo vệ hệ thống: $m"
            Exit-WithChoice -Reason 'error' -Message $m
        }
    }

    Write-AtInfo 'Đang tạo điểm khôi phục (thường mất từ nửa phút đến vài phút; đừng đóng cửa sổ)...'
    $desc = "Trạm Tool: $Tool/$Action"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $res = New-SystemRestorePoint -Description $desc -Type 'MODIFY_SETTINGS' -TimeoutSec 600
    if ($res.created) {
        $at = if ($res.at) { $res.at } else { Get-Date }
        Write-AtOk ('Đã tạo điểm khôi phục "{0}" lúc {1:HH:mm:ss} (mất {2} giây).' -f $desc, $at, [int]$sw.Elapsed.TotalSeconds)
        Write-AtInfo 'Máy lỗi sau khi chạy: mở Khôi phục hệ thống (rstrui.exe, hoặc nút trong trạm) và chọn điểm này.'
        Save-Result @{ created = $true; seq = $res.seq; description = $desc; pointAt = (Get-IsoTime $at) }
        Write-Host ''
        exit 0
    }
    Write-AtBad "Không tạo được điểm khôi phục: $($res.message)"
    $hint = Get-RestoreErrorHint $res.message
    if ($hint) { Write-AtInfo $hint }
    Exit-WithChoice -Reason 'error' -Message $res.message
}

Write-AtHead 'TRẠM TOOL - ĐIỂM KHÔI PHỤC HỆ THỐNG' "Trước khi chạy: $Tool / $Action"

if (-not (Test-IsAdmin)) {
    Write-AtWarn 'Cửa sổ không có quyền Admin nên không tạo được điểm khôi phục.'
    Save-Result @{ created = $false; reason = 'not-admin' }
    exit 0
}

try {
    Invoke-RestorePointStep
} catch {
    # Lỗi ngoài dự kiến: vẫn hỏi người dùng, không để cửa sổ đóng mà công cụ không chạy và không rõ lý do.
    $m = $_.Exception.Message.Trim()
    Write-AtBad "Lỗi khi chuẩn bị điểm khôi phục: $m"
    Exit-WithChoice -Reason 'error' -Message $m
}
