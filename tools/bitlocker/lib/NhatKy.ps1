# BitLocker - nhật ký hoàn tác. Mỗi lần đổi ghi một file ket_qua\hoan-tac\HoanTac_<thời gian>_<chế độ>.json,
# ghi ngay sau từng thay đổi nên dừng giữa chừng vẫn hoàn tác được phần đã làm. Chạy thử (-ChayThu) không ghi gì.
# Nhật ký chỉ ghi mã ổ và Mã khoá (Key ID), không bao giờ ghi khoá khôi phục.

function New-Journal {
    param([string]$Mode, [string]$Title)
    return [pscustomobject]@{
        Path = $null   # tạo file ở thay đổi đầu tiên: lần chạy không đổi gì thì không có nhật ký rỗng
        Data = [ordered]@{
            version = 1; tool = 'bitlocker'; mode = $Mode; title = $Title
            computer = $env:COMPUTERNAME; user = (Get-CurrentUser); started = (Get-Date).ToString('s'); undone = $null
            changes = New-Object System.Collections.ArrayList
        }
    }
}

function Save-Journal {
    param($Journal)
    if (-not $Journal.Path) {
        $dir = Join-Path (Get-ResultDir) 'hoan-tac'
        if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir) }
        $base = 'HoanTac_{0}_{1}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), $Journal.Data.mode
        $Journal.Path = Join-Path $dir "$base.json"
        for ($k = 2; Test-Path -LiteralPath $Journal.Path; $k++) { $Journal.Path = Join-Path $dir "${base}_$k.json" }
    }
    [IO.File]::WriteAllText($Journal.Path, ($Journal.Data | ConvertTo-Json -Depth 8), $script:Utf8NoBom)
}

function Invoke-Change {
    # Một thay đổi lên máy. Chạy thử: chỉ in ra. Chạy thật: làm, ghi nhật ký hoàn tác ngay, in kết quả.
    # $Undo: thông tin để hoàn tác; $Action có thể điền thêm vào đó (vd Mã khoá vừa tạo). Không có $Undo: không hoàn tác được.
    # Lưu ý: $Action chạy trong phạm vi của hàm này, đừng dùng tên biến Journal/Text/Action/Undo/DryRun/Quiet trong đó.
    param($Journal, [string]$Text, [scriptblock]$Action, [hashtable]$Undo = $null, [switch]$DryRun, [switch]$Quiet)
    $script:LastChangeError = $null
    if ($DryRun) { if (-not $Quiet) { Write-Plan $Text }; return $true }
    try { & $Action }
    catch {
        $code = Get-ErrorCode $_
        $script:LastChangeError = $code
        if (Get-ErrorHelp $code) { Write-ErrorHelp $code -Prefix "$Text, lỗi" }
        else { Write-Bad ('{0}, lỗi: {1}' -f $Text, $_.Exception.Message.Trim()) }
        return $false
    }
    if ($Undo) {
        $Undo.text = $Text
        $Undo.time = (Get-Date).ToString('s')
        [void]$Journal.Data.changes.Add($Undo)
        try { Save-Journal $Journal }
        catch { Write-Warn "Đã đổi nhưng không ghi được nhật ký hoàn tác: $($_.Exception.Message)" }
    }
    if (-not $Quiet) { Write-Ok $Text }
    return $true
}

# ---------------------------------------------------------------- hoàn tác
function Get-JournalEntries {
    # Các lần đổi đã ghi, mới nhất trước.
    $dir = Join-Path (Get-ResultDir) 'hoan-tac'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $list = foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter 'HoanTac_*.json' -File | Sort-Object Name -Descending)) {
        try { [pscustomobject]@{ File = $f; Data = ([IO.File]::ReadAllText($f.FullName, $script:Utf8NoBom) | ConvertFrom-Json) } } catch { }
    }
    return @($list)
}

function Find-BdeVolume {
    # Tìm lại ổ theo DeviceID (không đổi khi đổi chữ ổ).
    param([string]$DeviceId)
    return (@(Get-BdeVolumes) | Where-Object { $_.DeviceID -eq $DeviceId } | Select-Object -First 1)
}

function Undo-Change {
    # Trả 'ok' hoặc 'skip' (không hoàn tác được hoặc người dùng không đồng ý, đã báo lý do); lỗi thì ném ra.
    param($Change)
    $c = $Change
    $v = Find-BdeVolume ([string]$c.deviceId)
    if (-not $v) { Write-Info "Không còn thấy ổ $($c.letter) trên máy: bỏ qua."; return 'skip' }
    switch ([string]$c.kind) {
        'suspend' {
            if ((Get-BdeLockStatus $v) -eq 1) { Write-Info "Ổ $($c.letter) đang bị khoá: bỏ qua."; return 'skip' }
            if ([int](Invoke-Bde $v 'GetProtectionStatus').ProtectionStatus -eq 1) { Write-Info "Ổ $($c.letter) đã được bảo vệ lại: bỏ qua."; return 'skip' }
            [void](Invoke-Bde $v 'EnableKeyProtectors')
        }
        'protectorAdded' {
            if (-not $c.protectorId) { Write-Info 'Không ghi được Mã khoá lúc thêm: bỏ qua.'; return 'skip' }
            $ids = @((Invoke-Bde $v 'GetKeyProtectors' @{ KeyProtectorType = [uint32]0 }).VolumeKeyProtectorID)
            if ($ids -notcontains $c.protectorId) { Write-Info "Khoá $($c.protectorId) không còn trên ổ $($c.letter): bỏ qua."; return 'skip' }
            Write-Warn "Xoá khoá khôi phục $($c.protectorId) khỏi ổ $($c.letter) thì file khoá đã lưu cho Mã khoá này không mở được ổ nữa."
            if (-not (Read-YesNo 'Vẫn xoá khoá này?' $false)) { Write-Info 'Giữ lại khoá.'; return 'skip' }
            [void](Invoke-Bde $v 'DeleteKeyProtector' @{ VolumeKeyProtectorID = [string]$c.protectorId })
        }
        'autoUnlock' {
            if ((Get-BdeLockStatus $v) -eq 1) { Write-Info "Ổ $($c.letter) đang bị khoá: bỏ qua."; return 'skip' }
            if (-not [bool](Invoke-Bde $v 'IsAutoUnlockEnabled').IsAutoUnlockEnabled) { Write-Info "Ổ $($c.letter) đã tắt tự mở khoá: bỏ qua."; return 'skip' }
            # DisableAutoUnlock xoá khoá lưu trên ổ Windows; khoá ngoài (external key) công cụ tạo thì xoá riêng.
            [void](Invoke-Bde $v 'DisableAutoUnlock')
            if ($c.protectorId) {
                $ids = @((Invoke-Bde $v 'GetKeyProtectors' @{ KeyProtectorType = [uint32]0 }).VolumeKeyProtectorID)
                if ($ids -contains $c.protectorId) { [void](Invoke-Bde $v 'DeleteKeyProtector' @{ VolumeKeyProtectorID = [string]$c.protectorId }) }
            }
        }
        default { Write-Info "Không biết cách hoàn tác '$($c.kind)': bỏ qua."; return 'skip' }
    }
    return 'ok'
}

function Invoke-UndoJournal {
    # Hoàn tác các thay đổi của một lần đổi, theo thứ tự ngược lại. Ghi kết quả vào chính file nhật ký.
    param($Entry, [switch]$DryRun)
    $changes = @($Entry.Data.changes)
    $ok = 0; $fail = 0; $skip = 0
    for ($i = $changes.Count - 1; $i -ge 0; $i--) {
        $c = $changes[$i]
        if ($DryRun) { Write-Plan "Hoàn tác: $($c.text)"; continue }
        try {
            if ((Undo-Change $c) -eq 'skip') { $skip++ } else { $ok++; Write-Ok "Đã hoàn tác: $($c.text)" }
        } catch {
            $fail++
            $code = Get-ErrorCode $_
            if (Get-ErrorHelp $code) { Write-ErrorHelp $code -Prefix "Không hoàn tác được: $($c.text), lỗi" }
            else { Write-Bad ('Không hoàn tác được: {0} ({1})' -f $c.text, $_.Exception.Message.Trim()) }
        }
    }
    if (-not $DryRun) {
        $Entry.Data | Add-Member -NotePropertyName undone -NotePropertyValue ([ordered]@{ time = (Get-Date).ToString('s'); ok = $ok; failed = $fail; skipped = $skip }) -Force
        try { [IO.File]::WriteAllText($Entry.File.FullName, ($Entry.Data | ConvertTo-Json -Depth 8), $script:Utf8NoBom) }
        catch { Write-Warn "Không ghi được kết quả hoàn tác vào nhật ký: $($_.Exception.Message)" }
    }
    return [pscustomobject]@{ Ok = $ok; Failed = $fail; Skipped = $skip }
}
