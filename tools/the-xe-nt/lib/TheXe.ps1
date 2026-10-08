# File thẻ xe - đọc danh sách thẻ, kiểm tra, và các chế độ: xem, sửa file của bên bán, tạo từ danh sách.
#
# Phần mềm giữ xe (ITS Pro, theo mã đã dịch ngược):
# - Nạp thẻ: mỗi dòng có cả STT và CardID thành một dòng "insert into active(sttthe, cardid, trangthai=1)"; dòng thiếu
#   một trong hai bị bỏ qua; cột tinhtrang không được dùng.
# - Bảng active có khoá (sttthe, cardid): nạp lại đúng cặp cũ thì bị bỏ qua; cùng STT mà mã khác thì thành dòng mới.
# - Quẹt thẻ: tìm theo CardID, cần đúng 1 dòng; một mã nằm ở hai STT thì thẻ không được nhận.

function ConvertTo-Plain {
    # Bỏ dấu, chữ thường, chỉ giữ chữ và số: "SỐ THẺ" -> "sothe".
    param([string]$Text)
    $d = ([string]$Text).Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $d.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    return (($sb.ToString() -replace 'đ', 'd' -replace 'Đ', 'D').ToLowerInvariant() -replace '[^a-z0-9]', '')
}

# Tên cột nhận được (đã bỏ dấu). Số thẻ: ưu tiên "Số thẻ" hơn "STT" (danh sách có cả hai thì STT thường chỉ là số dòng).
$script:SttNames = @('sothe', 'sttthe', 'sothethe', 'stt')
$script:IdNames = @('cardid', 'idthe', 'mathe', 'id', 'uid', 'card')

function Find-CardHeader {
    # Dòng tiêu đề trong 15 dòng đầu: có một cột số thẻ và một cột mã thẻ. Trả @{ Line; Stt; Id; Tinh; SttName; IdName } hoặc $null.
    param($Cells)
    $max = [Math]::Min(15, @($Cells).Count)
    for ($i = 0; $i -lt $max; $i++) {
        $row = @($Cells[$i])
        $plain = @($row | ForEach-Object { ConvertTo-Plain $_ })
        $s = -1; $k = -1; $t = -1
        foreach ($n in $script:SttNames) { if ($s -lt 0) { $s = [Array]::IndexOf($plain, $n) } }
        foreach ($n in $script:IdNames) { if ($k -lt 0) { $k = [Array]::IndexOf($plain, $n) } }
        $t = [Array]::IndexOf($plain, 'tinhtrang')
        if ($s -ge 0 -and $k -ge 0 -and $s -ne $k) {
            return [pscustomobject]@{ Line = $i + 1; Stt = $s; Id = $k; Tinh = $t; SttName = $row[$s]; IdName = $row[$k] }
        }
    }
    return $null
}

function Get-CardList {
    # Đọc danh sách thẻ từ bảng chữ. Mã thẻ ngắn hơn $DoDai số được thêm số 0 ở đầu.
    # Trả @{ Header; Cards (Line, Stt, Raw, Id, Tinh); Errors; Padded; Blank }. Có Errors thì không được ghi file.
    param($Cells, [int]$DoDai = 10)
    $res = [pscustomobject]@{ Header = $null; Cards = @(); Errors = @(); Padded = 0; Blank = 0 }
    $h = Find-CardHeader $Cells
    if (-not $h) {
        $res.Errors = @('Không thấy dòng tiêu đề có cột số thẻ (STT, SỐ THẺ) và cột mã thẻ (CardID, ID) trong 15 dòng đầu.')
        return $res
    }
    $res.Header = $h
    $cards = New-Object System.Collections.Generic.List[object]
    $err = New-Object System.Collections.Generic.List[string]
    $all = @($Cells)
    for ($i = $h.Line; $i -lt $all.Count; $i++) {
        $row = @($all[$i]); $line = $i + 1
        $s = if ($h.Stt -lt $row.Count) { ([string]$row[$h.Stt]).Trim() } else { '' }
        $k = if ($h.Id -lt $row.Count) { ([string]$row[$h.Id]) -replace '\s', '' } else { '' }
        $tt = if ($h.Tinh -ge 0 -and $h.Tinh -lt $row.Count) { [string]$row[$h.Tinh] } else { '' }
        if (-not $s -and -not $k) { $res.Blank++; continue }
        if (-not $s) { $err.Add("Dòng ${line}: có mã $k nhưng thiếu số thẻ."); continue }
        if (-not $k) { $err.Add("Dòng ${line}: thẻ $s thiếu mã."); continue }
        $n = [int64]0
        if ($s -notmatch '^\d{1,9}$' -or -not [int64]::TryParse($s, [ref]$n) -or $n -le 0) { $err.Add("Dòng ${line}: số thẻ '$s' không phải số nguyên dương."); continue }
        if ($k -notmatch '^\d+$') { $err.Add("Dòng ${line}: mã thẻ '$k' của thẻ $s có chữ hoặc ký tự lạ (mã thẻ phải toàn số)."); continue }
        if ($k.Length -gt $DoDai) { $err.Add("Dòng ${line}: mã thẻ $k của thẻ $s dài $($k.Length) số, quá $DoDai số."); continue }
        $id = $k.PadLeft($DoDai, '0')
        if ($id -ne $k) { $res.Padded++ }
        $tv = 1.0
        if ($tt -and -not [double]::TryParse($tt, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$tv)) { $tv = 1.0 }
        $cards.Add([pscustomobject]@{ Line = $line; Stt = $n; Raw = $k; Id = $id; Tinh = $tv })
    }
    foreach ($g in @($cards | Group-Object Id | Where-Object { $_.Count -gt 1 })) {
        $err.Add(('Mã {0} trùng ở các thẻ {1}: phần mềm cần mỗi mã đúng một thẻ, trùng thì thẻ không quẹt được.' -f $g.Name, (($g.Group | ForEach-Object { $_.Stt }) -join ', ')))
    }
    foreach ($g in @($cards | Group-Object Stt | Where-Object { $_.Count -gt 1 })) {
        $err.Add(('Số thẻ {0} có {1} dòng (mã {2}).' -f $g.Name, $g.Count, (($g.Group | ForEach-Object { $_.Id }) -join ', ')))
    }
    if (-not $cards.Count -and -not $err.Count) { $err.Add('Không có thẻ nào dưới dòng tiêu đề.') }
    $res.Cards = $cards.ToArray(); $res.Errors = $err.ToArray()
    return $res
}

function Get-SttGaps {
    # Các khoảng số thẻ bị thiếu (để người dùng xem có sót thẻ không). Trả chuỗi như "3301-3305, 3310".
    param($Cards)
    $s = @($Cards | ForEach-Object { $_.Stt } | Sort-Object)
    $gaps = New-Object System.Collections.Generic.List[string]
    for ($i = 1; $i -lt $s.Count; $i++) {
        if ($s[$i] - $s[$i - 1] -gt 1) {
            $a = $s[$i - 1] + 1; $b = $s[$i] - 1
            $gaps.Add($(if ($a -eq $b) { "$a" } else { "$a-$b" }))
        }
    }
    return ($gaps -join ', ')
}

function Show-CardErrors {
    param($Errors, [int]$Max = 20)
    $e = @($Errors)
    foreach ($x in ($e | Select-Object -First $Max)) { Write-Bad $x }
    if ($e.Count -gt $Max) { Write-Sub ('... và {0} lỗi khác.' -f ($e.Count - $Max)) }
}

function Show-CardSummary {
    param($List, [int]$DoDai)
    $c = @($List.Cards)
    $min = ($c | Measure-Object Stt -Minimum).Minimum; $max = ($c | Measure-Object Stt -Maximum).Maximum
    Write-Line ('{0} thẻ, số thẻ từ {1} đến {2}. Số thẻ lấy ở cột "{3}", mã thẻ ở cột "{4}" (dòng tiêu đề {5}).' -f $c.Count, $min, $max, $List.Header.SttName, $List.Header.IdName, $List.Header.Line)
    if ($List.Padded) { Write-Info ('{0} mã ngắn hơn {1} số: thêm số 0 ở đầu cho đủ (vd {2} -> {3}).' -f $List.Padded, $DoDai, ($c | Where-Object { $_.Raw -ne $_.Id } | Select-Object -First 1).Raw, ($c | Where-Object { $_.Raw -ne $_.Id } | Select-Object -First 1).Id) }
    $gaps = Get-SttGaps $c
    if ($gaps) { Write-Info "Số thẻ không liền, thiếu: $gaps (kiểm tra có sót thẻ không)." }
}

function Show-CardSample {
    # Vài thẻ đầu và thẻ cuối để so với số in trên thẻ.
    param($Cards)
    $c = @($Cards)
    $pick = @($c | Select-Object -First 3) + @(if ($c.Count -gt 3) { $c[-1] })
    Write-Line 'Số thẻ   Mã thẻ (so với số in trên thẻ)'
    foreach ($x in $pick) { Write-Line ('{0,-8} {1}' -f $x.Stt, $x.Id) }
}

# ---------------------------------------------------------------- chế độ
function Test-InputFile {
    param([string]$File, [string[]]$Ext)
    if (-not $File) { Write-Bad 'Chưa chọn file.'; return $false }
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { Write-Bad "Không thấy file '$File'."; return $false }
    if ([IO.Path]::GetExtension($File).ToLowerInvariant() -notin $Ext) { Write-Bad ('File phải có đuôi {0}.' -f ($Ext -join ', ')); return $false }
    return $true
}

function Invoke-XemFile {
    # Chỉ đọc: phần mềm giữ xe sẽ đọc file này ra sao, file có lỗi gì.
    param([string]$File, [int]$DoDai = 10)
    Write-Out 'XEM FILE THẺ NHƯ PHẦN MỀM GIỮ XE ĐỌC' 'Cyan'
    Write-Out ('{0}, {1:dd/MM/yyyy HH:mm}. Chỉ đọc, không sửa file.' -f $File, (Get-Date))
    if (-not (Test-InputFile $File @('.nt', '.xls'))) { return 2 }
    $work = New-WorkDir
    try {
        $copy = Join-Path $work 'xem.xls'
        Copy-Item -LiteralPath $File -Destination $copy -Force
        $sw = Read-AsSoftware $copy
        Write-Head 'Phần mềm giữ xe sẽ đọc'
        if (-not $sw.Ok) {
            Write-Bad "Không đọc được như file Excel 97-2003: $($sw.Error)"
            Write-Sub 'Phần mềm sẽ báo lỗi khi nạp. File có thể là .xlsx đổi đuôi, hoặc hỏng.'
            return 0
        }
        Write-Line ('Sheet {0}; cột: {1}.' -f $sw.Table.TrimEnd('$'), (($sw.Columns | ForEach-Object { '{0} ({1})' -f $_.Name, $(if ($_.Type -eq 'String') { 'chữ' } elseif ($_.Type -eq 'Double') { 'số' } else { $_.Type }) }) -join ', '))
        $fix = $false; $hard = $false
        if (-not ($sw.HasStt -and $sw.HasCard)) {
            Write-Bad 'Thiếu cột STT hoặc CardID: phần mềm sẽ báo "Vui lòng chọn file Import theo file định dạng của nhà cung cấp".'
            $fix = $true
        } else {
            Write-Line ('Phần mềm nạp được {0} thẻ.' -f $sw.Rows.Count)
            $short = @($sw.Rows | Where-Object { $_.Card.Length -lt $DoDai })
            if ($sw.CardType -ne 'String') {
                if ($short.Count) {
                    $x = $short[0]
                    Write-Bad ('CardID lưu dạng số: phần mềm đọc thẻ {0} là {1}, trong khi đầu đọc gửi {2} ({3} số). {4} thẻ như vậy sẽ không quẹt được.' -f $x.Stt, $x.Card, $x.Card.PadLeft($DoDai, '0'), $DoDai, $short.Count)
                    Write-Sub 'Số 0 ở đầu chỉ là kiểu hiển thị của Excel, không nằm trong dữ liệu.'
                } else {
                    Write-Warn ('CardID lưu dạng số nhưng mã nào cũng đủ {0} số nên phần mềm vẫn đọc đúng. Nên sửa: lô có mã bắt đầu bằng 0 sẽ mất số 0.' -f $DoDai)
                }
                $fix = $true
            } elseif ($short.Count) {
                Write-Warn ('{0} mã ngắn hơn {1} số (vd thẻ {2}: {3}): đầu đọc gửi đủ {1} số nên các thẻ này không quẹt được.' -f $short.Count, $DoDai, $short[0].Stt, $short[0].Card)
                $fix = $true
            } else {
                Write-Ok ('CardID lưu dạng chữ, đủ {0} số.' -f $DoDai)
            }
            if ($sw.Skipped.Count) {
                Write-Warn ('Phần mềm bỏ qua {0} dòng thiếu STT hoặc CardID (vd dòng {1}).' -f $sw.Skipped.Count, $sw.Skipped[0].Line)
            }
        }

        Write-Head 'Nội dung file'
        $cells = Read-JetCells $copy
        $list = Get-CardList $cells $DoDai
        if ($list.Header) { Show-CardSummary $list $DoDai }
        if ($list.Errors.Count) { Show-CardErrors $list.Errors; $hard = $true }
        if ($sw.HasStt -and $sw.HasCard -and $list.Cards.Count -gt $sw.Rows.Count) {
            Write-Bad ('File có {0} thẻ nhưng phần mềm chỉ nạp được {1}: cột lẫn số và chữ, Jet bỏ các ô khác kiểu với đa số.' -f $list.Cards.Count, $sw.Rows.Count)
            $fix = $true
        }
        if ($list.Cards.Count) { Show-CardSample $list.Cards }

        Write-Head 'KẾT LUẬN'
        if ($hard) {
            Write-Bad 'File có lỗi công cụ không tự sửa được (mã trùng, thiếu, có chữ...): báo bên bán gửi lại, hoặc sửa trong Excel rồi chạy lại.'
        } elseif ($fix) {
            Write-Warn 'Cần sửa trước khi nạp: chạy "Sửa file thẻ của bên bán" (file gốc giữ nguyên, file sửa nằm trong thư mục da-sua).'
        } else {
            Write-Ok ('File dùng được: phần mềm đọc đủ {0} thẻ, mã đủ {1} số.' -f $sw.Rows.Count, $DoDai)
        }
        return 0
    } finally { Remove-WorkDir $work }
}

function Invoke-GhiThe {
    # Phần chung của Sửa và Tạo: kiểm tra danh sách, hỏi khi file đích đã có, ghi file đủ và file thử 1 thẻ.
    param($List, [string]$OutDir, [string]$Name, [int]$DoDai, [string]$WorkDir)
    $cards = @($List.Cards)
    $full = Join-Path $OutDir "$Name.nt"
    $view = Join-Path $OutDir "$Name.xls"
    $test = Join-Path $OutDir ('thu-{0}.nt' -f $cards[0].Stt)
    Write-Head 'Sẽ ghi'
    Write-Line "$full  (đẩy file này lên phần mềm giữ xe)"
    Write-Line "$view  (cùng nội dung, bấm đúp để mở xem bằng Excel)"
    Write-Line ('{0}  (file thử, chỉ thẻ {1})' -f $test, $cards[0].Stt)
    $exist = @($full, $view, $test | Where-Object { Test-Path -LiteralPath $_ })
    if ($exist.Count) {
        Write-Warn ('Đã có: {0}.' -f (($exist | ForEach-Object { Split-Path $_ -Leaf }) -join ', '))
        if (-not (Read-YesNo 'Ghi đè các file này?' $false)) { Write-Warn 'Đã thôi, chưa ghi gì.'; return 1223 }
    }
    if (-not (Test-Path -LiteralPath $OutDir)) { [void](New-Item -ItemType Directory -Path $OutDir -Force) }
    $n = Write-NtFile $full $cards $WorkDir
    Copy-Item -LiteralPath $full -Destination $view -Force
    [void](Write-NtFile $test @($cards[0]) $WorkDir)
    Write-Head 'Kết quả'
    Write-Ok ('Đã ghi {0} thẻ. Đọc lại như phần mềm giữ xe: CardID dạng chữ, đủ {1} số, khớp từng thẻ.' -f $n, $DoDai)
    Show-CardSample $cards
    Write-Head 'Cách nạp'
    Write-Line ('1. Nạp file thử {0} trước, quẹt thử thẻ {1}: phải nhận mã {2}.' -f (Split-Path $test -Leaf), $cards[0].Stt, $cards[0].Id)
    Write-Line ('2. Được rồi thì nạp {0}.' -f (Split-Path $full -Leaf))
    Write-Line '3. Nếu lô này đã từng nạp với mã thiếu số 0: phần mềm thêm dòng mới (STT cũ có 2 mã). Dòng mã sai vô hại vì không thẻ nào mang mã đó, nhưng nên xoá cho gọn; thẻ đã gán cho khách (thẻ tháng) thì ghi lại trước khi xoá.'
    Write-Info 'Mở file .xls bằng Excel có thể thấy tam giác xanh "Number Stored as Text": bình thường. Đừng bấm Convert to Number rồi lưu, số 0 sẽ mất.'
    return 0
}

function Invoke-SuaFile {
    # Sửa file của bên bán: ghi bản sửa vào <thư mục file>\da-sua (hoặc -ThuMuc), cùng tên. File gốc giữ nguyên.
    param([string]$File, [string]$ThuMuc = '', [int]$DoDai = 10)
    Write-Out 'SỬA FILE THẺ CỦA BÊN BÁN' 'Cyan'
    Write-Out ('{0}, {1:dd/MM/yyyy HH:mm}. File gốc giữ nguyên.' -f $File, (Get-Date))
    if (-not (Test-InputFile $File @('.nt', '.xls'))) { return 2 }
    $work = New-WorkDir
    try {
        $copy = Join-Path $work 'nguon.xls'
        Copy-Item -LiteralPath $File -Destination $copy -Force
        $sw = Read-AsSoftware $copy
        if (-not $sw.Ok) { Write-Bad "Không đọc được như file Excel 97-2003: $($sw.Error)"; return 1 }
        $list = Get-CardList (Read-JetCells $copy) $DoDai
        Write-Head 'Danh sách thẻ'
        if ($list.Header) { Show-CardSummary $list $DoDai }
        if ($list.Errors.Count) {
            Show-CardErrors $list.Errors
            Write-Bad 'Chưa ghi gì: sửa các lỗi trên trong Excel (hoặc báo bên bán gửi lại) rồi chạy lại.'
            return 1
        }
        $same = $sw.HasStt -and $sw.HasCard -and $sw.CardType -eq 'String' -and -not $sw.Skipped.Count -and $sw.Rows.Count -eq $list.Cards.Count -and
            -not @(for ($i = 0; $i -lt $list.Cards.Count; $i++) { if ($sw.Rows[$i].Card -ne $list.Cards[$i].Id) { $i } }).Count
        if ($same) { Write-Ok ('File đã đúng: phần mềm đọc đủ {0} thẻ, mã dạng chữ đủ {1} số. Không cần sửa.' -f $list.Cards.Count, $DoDai); return 0 }
        $out = if ($ThuMuc) { $ThuMuc } else { Join-Path ([IO.Path]::GetDirectoryName($File)) 'da-sua' }
        $name = [IO.Path]::GetFileNameWithoutExtension($File)
        if ([IO.Path]::GetFullPath((Join-Path $out "$name.nt")) -ieq [IO.Path]::GetFullPath($File)) { Write-Bad 'Thư mục ghi trùng thư mục file gốc: chọn thư mục khác để không đè file gốc.'; return 2 }
        return (Invoke-GhiThe $list $out $name $DoDai $work)
    } finally { Remove-WorkDir $work }
}

function Invoke-TaoFile {
    # Tạo file .nt từ danh sách (.xlsx, .xls, .csv, .txt) có cột số thẻ và mã thẻ. Tên file: <số đầu>-<số cuối>.nt.
    param([string]$File, [string]$ThuMuc = '', [int]$DoDai = 10)
    Write-Out 'TẠO FILE THẺ TỪ DANH SÁCH' 'Cyan'
    Write-Out ('{0}, {1:dd/MM/yyyy HH:mm}.' -f $File, (Get-Date))
    if (-not (Test-InputFile $File @('.xlsx', '.xlsm', '.xls', '.nt', '.csv', '.txt'))) { return 2 }
    $work = New-WorkDir
    try {
        $cells = Read-AnyCells $File $work
        $list = Get-CardList $cells $DoDai
        Write-Head 'Danh sách thẻ'
        if ($list.Header) { Show-CardSummary $list $DoDai }
        if ($list.Errors.Count) {
            Show-CardErrors $list.Errors
            Write-Bad 'Chưa ghi gì: sửa các lỗi trên trong danh sách rồi chạy lại.'
            return 1
        }
        $c = @($list.Cards)
        $min = ($c | Measure-Object Stt -Minimum).Minimum; $max = ($c | Measure-Object Stt -Maximum).Maximum
        $out = if ($ThuMuc) { $ThuMuc } else { [IO.Path]::GetDirectoryName($File) }
        return (Invoke-GhiThe $list $out ('{0}-{1}' -f $min, $max) $DoDai $work)
    } finally { Remove-WorkDir $work }
}
