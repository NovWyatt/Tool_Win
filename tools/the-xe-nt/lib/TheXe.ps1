# File thẻ xe - đọc danh sách thẻ, kiểm tra, và các chế độ: kiểm tra (xem), chuyển .nt sang Excel (xuat), sửa file của
# bên bán (sua), chuyển Excel sang .nt (tao).
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
    # Trả @{ Header; Cards (Line, Stt, Raw, Id, Tinh); Rows; Errors; Padded; Blank }. Có Errors thì không được ghi file.
    # Rows: mọi dòng có dữ liệu (Line, SttText, IdText, Stt, Id, Loi); Loi là lỗi ngắn của riêng dòng đó, để ghi ra Excel.
    param($Cells, [int]$DoDai = 10)
    $res = [pscustomobject]@{ Header = $null; Cards = @(); Rows = @(); Errors = @(); Padded = 0; Blank = 0 }
    $h = Find-CardHeader $Cells
    if (-not $h) {
        $res.Errors = @('Không thấy dòng tiêu đề có cột số thẻ (STT, SỐ THẺ) và cột mã thẻ (CardID, ID) trong 15 dòng đầu.')
        return $res
    }
    $res.Header = $h
    $cards = New-Object System.Collections.Generic.List[object]
    $rows = New-Object System.Collections.Generic.List[object]
    $byLine = @{}
    $err = New-Object System.Collections.Generic.List[string]
    $all = @($Cells)
    for ($i = $h.Line; $i -lt $all.Count; $i++) {
        $row = @($all[$i]); $line = $i + 1
        $s = if ($h.Stt -lt $row.Count) { ([string]$row[$h.Stt]).Trim() } else { '' }
        $k = if ($h.Id -lt $row.Count) { ([string]$row[$h.Id]) -replace '\s', '' } else { '' }
        $tt = if ($h.Tinh -ge 0 -and $h.Tinh -lt $row.Count) { [string]$row[$h.Tinh] } else { '' }
        if (-not $s -and -not $k) { $res.Blank++; continue }
        $o = [pscustomobject]@{ Line = $line; SttText = $s; IdText = $k; Stt = $null; Id = ''; Loi = '' }
        $rows.Add($o); $byLine[$line] = $o
        if (-not $s) { $err.Add("Dòng ${line}: có mã $k nhưng thiếu số thẻ."); $o.Loi = 'Thiếu số thẻ'; continue }
        if (-not $k) { $err.Add("Dòng ${line}: thẻ $s thiếu mã."); $o.Loi = 'Thiếu mã thẻ'; continue }
        $n = [int64]0
        if ($s -notmatch '^\d{1,9}$' -or -not [int64]::TryParse($s, [ref]$n) -or $n -le 0) { $err.Add("Dòng ${line}: số thẻ '$s' không phải số nguyên dương."); $o.Loi = 'Số thẻ không phải số nguyên dương'; continue }
        if ($k -notmatch '^\d+$') { $err.Add("Dòng ${line}: mã thẻ '$k' của thẻ $s có chữ hoặc ký tự lạ (mã thẻ phải toàn số)."); $o.Loi = 'Mã thẻ có chữ hoặc ký tự lạ'; continue }
        if ($k.Length -gt $DoDai) { $err.Add("Dòng ${line}: mã thẻ $k của thẻ $s dài $($k.Length) số, quá $DoDai số."); $o.Loi = "Mã thẻ dài $($k.Length) số, quá $DoDai số"; continue }
        $id = $k.PadLeft($DoDai, '0')
        if ($id -ne $k) { $res.Padded++ }
        $o.Stt = $n; $o.Id = $id
        $tv = 1.0
        if ($tt -and -not [double]::TryParse($tt, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$tv)) { $tv = 1.0 }
        $cards.Add([pscustomobject]@{ Line = $line; Stt = $n; Raw = $k; Id = $id; Tinh = $tv })
    }
    foreach ($g in @($cards | Group-Object Id | Where-Object { $_.Count -gt 1 })) {
        $err.Add(('Mã {0} trùng ở các thẻ {1}: phần mềm cần mỗi mã đúng một thẻ, trùng thì thẻ không quẹt được.' -f $g.Name, (($g.Group | ForEach-Object { $_.Stt }) -join ', ')))
        foreach ($x in $g.Group) {
            $o = $byLine[$x.Line]
            $o.Loi = (@($o.Loi, ('Mã trùng với thẻ {0}' -f (($g.Group | Where-Object { $_.Line -ne $x.Line } | ForEach-Object { $_.Stt }) -join ', '))) | Where-Object { $_ }) -join '; '
        }
    }
    foreach ($g in @($cards | Group-Object Stt | Where-Object { $_.Count -gt 1 })) {
        $err.Add(('Số thẻ {0} có {1} dòng (mã {2}).' -f $g.Name, $g.Count, (($g.Group | ForEach-Object { $_.Id }) -join ', ')))
        foreach ($x in $g.Group) {
            $o = $byLine[$x.Line]
            $o.Loi = (@($o.Loi, ('Số thẻ có {0} dòng' -f $g.Count)) | Where-Object { $_ }) -join '; '
        }
    }
    if (-not $cards.Count -and -not $err.Count) { $err.Add('Không có thẻ nào dưới dòng tiêu đề.') }
    $res.Cards = $cards.ToArray(); $res.Rows = $rows.ToArray(); $res.Errors = $err.ToArray()
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

function Format-SttRange {
    # Số thẻ thành chuỗi gọn: 1, 2, 3, 5 -> "1-3, 5". Quá $Max khoảng thì cắt bớt.
    param($Numbers, [int]$Max = 15)
    $num = New-Object System.Collections.Generic.List[int64]
    $other = New-Object System.Collections.Generic.List[string]
    foreach ($x in $Numbers) { $n = [int64]0; if ([int64]::TryParse([string]$x, [ref]$n)) { $num.Add($n) } else { $other.Add([string]$x) } }
    $s = @($num | Sort-Object -Unique)
    $parts = New-Object System.Collections.Generic.List[string]
    $i = 0
    while ($i -lt $s.Count) {
        $j = $i
        while ($j + 1 -lt $s.Count -and $s[$j + 1] -eq $s[$j] + 1) { $j++ }
        $parts.Add($(if ($j -gt $i) { '{0}-{1}' -f $s[$i], $s[$j] } else { [string]$s[$i] }))
        $i = $j + 1
    }
    foreach ($o in $other) { $parts.Add("'$o'") }
    if ($parts.Count -gt $Max) { return (($parts.ToArray() | Select-Object -First $Max) -join ', ') + (' ... (và {0} khoảng khác)' -f ($parts.Count - $Max)) }
    return ($parts -join ', ')
}

function Compare-CardList {
    # So thẻ phần mềm đọc từ file .nt ($Rows: Stt, Card) với danh sách ($Cards: Stt, Id), theo số thẻ.
    # Trả @{ Match; Zero (chỉ thiếu số 0 ở đầu); Diff (khác mã); Missing (có trong danh sách, không có trong file);
    # Extra (có trong file, không có trong danh sách) }.
    param($Rows, $Cards, [int]$DoDai)
    $file = @{}
    foreach ($r in @($Rows)) {
        $n = [int64]0
        $k = if ([int64]::TryParse(([string]$r.Stt).Trim(), [ref]$n)) { [string]$n } else { [string]$r.Stt }
        if (-not $file.ContainsKey($k)) { $file[$k] = New-Object System.Collections.Generic.List[string] }
        $file[$k].Add([string]$r.Card)
    }
    $list = @{}
    foreach ($c in @($Cards)) { $list[[string]$c.Stt] = $true }
    $res = [pscustomobject]@{
        Match = (New-Object System.Collections.Generic.List[object]); Zero = (New-Object System.Collections.Generic.List[object])
        Diff = (New-Object System.Collections.Generic.List[object]); Missing = (New-Object System.Collections.Generic.List[object])
        Extra = (New-Object System.Collections.Generic.List[object])
    }
    foreach ($c in @($Cards)) {
        $k = [string]$c.Stt
        if (-not $file.ContainsKey($k)) { $res.Missing.Add($c.Stt); continue }
        $got = $file[$k]
        if ($got.Contains($c.Id)) { $res.Match.Add($c.Stt); continue }
        $z = @($got | Where-Object { $_.PadLeft($DoDai, '0') -eq $c.Id })
        if ($z.Count) { $res.Zero.Add([pscustomobject]@{ Stt = $c.Stt; File = $z[0]; List = $c.Id }) }
        else { $res.Diff.Add([pscustomobject]@{ Stt = $c.Stt; File = ($got -join ', '); List = $c.Id }) }
    }
    foreach ($k in $file.Keys) { if (-not $list.ContainsKey($k)) { $res.Extra.Add($k) } }
    return $res
}

function Show-CardCompare {
    # In kết quả so với danh sách. Trả 'khop' (khớp hết), 'so0' (chỉ khác vì mất số 0) hoặc 'khac'.
    param($Cmp, $Ds)
    Write-Line ('Danh sách có {0} thẻ (số thẻ ở cột "{1}", mã ở cột "{2}").' -f @($Ds.Cards).Count, $Ds.Header.SttName, $Ds.Header.IdName)
    if ($Ds.Errors.Count) {
        Write-Warn ('Danh sách có {0} lỗi, các dòng lỗi không được so:' -f $Ds.Errors.Count)
        Show-CardErrors $Ds.Errors 5
    }
    if ($Cmp.Match.Count) { Write-Ok ('Khớp: {0} thẻ.' -f $Cmp.Match.Count) } else { Write-Line 'Khớp: 0 thẻ.' }
    if ($Cmp.Zero.Count) {
        $z = $Cmp.Zero[0]
        Write-Bad ('Mất số 0: {0} thẻ, phần mềm đọc thiếu số 0 so với danh sách (vd thẻ {1}: file {2}, danh sách {3}).' -f $Cmp.Zero.Count, $z.Stt, $z.File, $z.List)
    }
    if ($Cmp.Diff.Count) {
        Write-Bad ('Khác mã: {0} thẻ.' -f $Cmp.Diff.Count)
        foreach ($d in ($Cmp.Diff.ToArray() | Select-Object -First 10)) { Write-Sub ('Thẻ {0}: file {1}, danh sách {2}.' -f $d.Stt, $d.File, $d.List) }
        if ($Cmp.Diff.Count -gt 10) { Write-Sub ('... và {0} thẻ khác.' -f ($Cmp.Diff.Count - 10)) }
    }
    if ($Cmp.Missing.Count) { Write-Bad ('Có trong danh sách, không có trong file .nt: {0} thẻ: {1}.' -f $Cmp.Missing.Count, (Format-SttRange $Cmp.Missing)) }
    if ($Cmp.Extra.Count) { Write-Bad ('Có trong file .nt, không có trong danh sách: {0} thẻ: {1}.' -f $Cmp.Extra.Count, (Format-SttRange $Cmp.Extra)) }
    if ($Cmp.Diff.Count -or $Cmp.Missing.Count -or $Cmp.Extra.Count) { return 'khac' }
    if ($Cmp.Zero.Count) { return 'so0' }
    return 'khop'
}

function Get-NtCheckRows {
    # Từng dòng có dữ liệu của file .nt: số thẻ, mã đúng, mã phần mềm giữ xe đọc được, kết quả.
    # Loai là nhóm kết quả (để đếm), KetQua là chữ ghi vào ô.
    param($Sw, $List, [int]$DoDai)
    $load = $Sw.Ok -and $Sw.HasStt -and $Sw.HasCard
    $read = @{}
    if ($load) { foreach ($r in @($Sw.Rows)) { $read[[int]$r.Line] = [string]$r.Card } }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($r in @($List.Rows)) {
        $line = [int]$r.Line
        $has = $read.ContainsKey($line)
        $doc = if (-not $Sw.Ok) { '(không đọc được file)' } elseif (-not $load) { '(thiếu cột STT, CardID)' } elseif ($has) { $read[$line] } else { '(bỏ qua dòng này)' }
        if ($r.Loi) { $loai = 'Lỗi trong file'; $kq = $r.Loi }
        elseif (-not $Sw.Ok) { $loai = 'Phần mềm không đọc được file'; $kq = 'Phần mềm không đọc được file (không phải Excel 97-2003)' }
        elseif (-not $load) { $loai = 'Phần mềm không nạp'; $kq = 'Phần mềm không nạp: file thiếu cột STT hoặc CardID' }
        elseif (-not $has) { $loai = 'Phần mềm bỏ qua'; $kq = 'Phần mềm bỏ qua dòng này (ô khác kiểu với đa số trong cột)' }
        elseif ($read[$line] -eq $r.Id) { $loai = 'Đúng'; $kq = 'Đúng' }
        elseif ($read[$line].PadLeft($DoDai, '0') -eq $r.Id) { $loai = 'Mất số 0'; $kq = ('Mất số 0: phần mềm đọc {0}, đầu đọc gửi {1}' -f $read[$line], $r.Id) }
        else { $loai = 'Phần mềm đọc ra mã khác'; $kq = 'Phần mềm đọc ra mã khác' }
        $stt = if ($null -ne $r.Stt) { [int64]$r.Stt } else { $r.SttText }
        $id = if ($r.Id) { $r.Id } else { $r.IdText }
        $out.Add([pscustomobject]@{ Line = $line; Stt = $stt; Id = $id; Doc = $doc; Loai = $loai; KetQua = $kq })
    }
    return $out.ToArray()
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

# Đuôi file danh sách nhận được (tạo file .nt, so với file .nt).
$script:ListExt = @('.xlsx', '.xlsm', '.xls', '.nt', '.csv', '.txt')

function Invoke-XemFile {
    # Chỉ đọc: phần mềm giữ xe sẽ đọc file này ra sao, file có lỗi gì; có $DanhSach thì so từng thẻ với danh sách.
    param([string]$File, [string]$DanhSach = '', [int]$DoDai = 10)
    Write-Out 'KIỂM TRA FILE THẺ NHƯ PHẦN MỀM GIỮ XE ĐỌC' 'Cyan'
    Write-Out ('{0}, {1:dd/MM/yyyy HH:mm}. Chỉ đọc, không sửa file.' -f $File, (Get-Date))
    if ($DanhSach) { Write-Out "So với danh sách: $DanhSach" }
    if (-not (Test-InputFile $File @('.nt', '.xls'))) { return 2 }
    if ($DanhSach -and -not (Test-InputFile $DanhSach $script:ListExt)) { return 2 }
    $work = New-WorkDir
    try {
        $copy = Join-Path $work 'xem.xls'
        Copy-Item -LiteralPath $File -Destination $copy -Force
        $sw = Read-AsSoftware $copy
        Write-Head 'Phần mềm giữ xe sẽ đọc'
        if (-not $sw.Ok) {
            Write-Bad "Không đọc được như file Excel 97-2003: $($sw.Error)"
            if ((Get-FileKind $File) -eq 'xlsx') {
                Write-Sub 'File là .xlsx đổi đuôi nên phần mềm sẽ báo lỗi khi nạp. Chạy "Sửa file .nt của bên bán" với chính file này để ghi lại đúng định dạng.'
            } else {
                Write-Sub 'Phần mềm sẽ báo lỗi khi nạp. File có thể hỏng, hoặc không phải file Excel.'
            }
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

        $state = ''
        if ($DanhSach) {
            Write-Head 'So với danh sách'
            $ds = $null
            try { $ds = Get-CardList (Read-AnyCells $DanhSach $work) $DoDai } catch { Write-Bad ('Không đọc được danh sách: {0}' -f $_.Exception.Message.Trim()) }
            if (-not $ds) { $state = 'loi' }
            elseif (-not $ds.Header) { Show-CardErrors $ds.Errors; $state = 'loi' }
            elseif (-not ($sw.HasStt -and $sw.HasCard)) { Write-Warn 'Chưa so được: phần mềm không nạp được file .nt này (thiếu cột STT hoặc CardID).'; $state = 'loi' }
            else { $state = Show-CardCompare (Compare-CardList $sw.Rows $ds.Cards $DoDai) $ds }
        }

        Write-Head 'KẾT LUẬN'
        if ($hard) {
            Write-Bad 'File có lỗi công cụ không tự sửa được (mã trùng, thiếu, có chữ...): báo bên bán gửi lại, hoặc sửa trong Excel rồi chạy lại.'
        } elseif ($state -eq 'khac') {
            Write-Bad 'File .nt không khớp danh sách (thiếu thẻ, thừa thẻ hoặc khác mã): hỏi lại bên bán, hoặc tạo file từ danh sách bằng "Chuyển Excel sang file .nt".'
        } elseif ($fix) {
            Write-Warn 'Cần sửa trước khi nạp: chạy "Sửa file .nt của bên bán" (file gốc giữ nguyên, file sửa nằm trong thư mục da-sua).'
            if ($state -eq 'so0') { Write-Sub 'Ngoài số 0 bị mất, mã khớp danh sách: sửa xong là đúng.' }
        } else {
            Write-Ok ('File dùng được: phần mềm đọc đủ {0} thẻ, mã đủ {1} số.' -f $sw.Rows.Count, $DoDai)
            if ($state -eq 'khop') { Write-Ok 'Khớp danh sách: từng thẻ đúng số thẻ, đúng mã.' }
        }
        if ($state -eq 'loi') { Write-Warn 'Chưa so được với danh sách (xem phần So với danh sách).' }
        return 0
    } finally { Remove-WorkDir $work }
}

function Invoke-XuatExcel {
    # Chuyển file .nt sang Excel (.xlsx): mỗi thẻ một dòng, kèm mã phần mềm giữ xe đọc được và kết quả kiểm tra.
    # Cột CardID là mã đúng (chữ, đủ $DoDai số), nên sửa trong Excel rồi "Chuyển Excel sang file .nt" là ra file đúng.
    param([string]$File, [string]$ThuMuc = '', [int]$DoDai = 10)
    Write-Out 'CHUYỂN FILE .NT SANG EXCEL' 'Cyan'
    Write-Out ('{0}, {1:dd/MM/yyyy HH:mm}. File gốc giữ nguyên.' -f $File, (Get-Date))
    if (-not (Test-InputFile $File @('.nt', '.xls'))) { return 2 }
    $work = New-WorkDir
    try {
        $copy = Join-Path $work 'xem.xls'
        Copy-Item -LiteralPath $File -Destination $copy -Force
        $sw = Read-AsSoftware $copy
        if (-not $sw.Ok -and (Get-FileKind $File) -ne 'xlsx') { Write-Bad "Không đọc được như file Excel 97-2003: $($sw.Error)"; return 1 }
        $list = Get-CardList (Read-AnyCells $File $work) $DoDai
        Write-Head 'Danh sách thẻ'
        if (-not $list.Header) { Show-CardErrors $list.Errors; Write-Bad 'Chưa ghi gì: file không có cột số thẻ và cột mã thẻ.'; return 1 }
        if ($list.Cards.Count) { Show-CardSummary $list $DoDai }
        $rows = @(Get-NtCheckRows $sw $list $DoDai)
        if (-not $rows.Count) { Write-Bad 'Chưa ghi gì: không có thẻ nào dưới dòng tiêu đề.'; return 1 }

        $out = if ($ThuMuc) { $ThuMuc } else { [IO.Path]::GetDirectoryName($File) }
        $dest = Join-Path $out ([IO.Path]::GetFileNameWithoutExtension($File) + '.xlsx')
        Write-Head 'Sẽ ghi'
        Write-Line "$dest  (mở bằng Excel)"
        if (Test-Path -LiteralPath $dest) {
            Write-Warn ('Đã có {0}.' -f (Split-Path $dest -Leaf))
            if (-not (Read-YesNo 'Ghi đè file này?' $false)) { Write-Warn 'Đã thôi, chưa ghi gì.'; return 1223 }
        }
        if (-not (Test-Path -LiteralPath $out)) { [void](New-Item -ItemType Directory -Path $out -Force) }
        $data = New-Object System.Collections.Generic.List[object]
        foreach ($r in $rows) { $data.Add([object[]]@($r.Stt, $r.Id, $r.Doc, $r.KetQua, [int64]$r.Line)) }
        try {
            Write-XlsxFile -Path $dest -Header @('STT', 'CardID', 'Phần mềm đọc', 'Kết quả', 'Dòng trong file .nt') -Rows $data.ToArray() `
                -Widths @(10, 14, 18, 52, 21) -TextCols @(1, 2) -MarkCol 3 -OkText 'Đúng'
        } catch {
            Write-Bad ('Không ghi được {0}: {1}' -f (Split-Path $dest -Leaf), $_.Exception.Message.Trim())
            Write-Sub 'File đang mở trong Excel thì đóng lại rồi chạy lại.'
            return 1
        }
        # Đọc lại file vừa ghi, so từng thẻ (số thẻ, mã).
        $back = Read-XlsxCells $dest
        $bad = @(for ($i = 0; $i -lt $rows.Count; $i++) {
            $b = @($back[$i + 1])
            if ($b.Count -lt 2 -or $b[0] -ne [string]$rows[$i].Stt -or $b[1] -ne [string]$rows[$i].Id) { $i }
        })
        if ($back.Count -ne $rows.Count + 1 -or $bad.Count) { Write-Bad ('Đọc lại {0} không khớp lúc ghi: đừng dùng file này.' -f (Split-Path $dest -Leaf)); return 1 }

        Write-Head 'Kết quả'
        Write-Ok ('Đã ghi {0} thẻ, đọc lại khớp từng thẻ.' -f $rows.Count)
        $groups = @($rows | Group-Object Loai)
        foreach ($g in @($groups | Where-Object { $_.Name -eq 'Đúng' }) + @($groups | Where-Object { $_.Name -ne 'Đúng' })) {
            $t = '{0}: {1} thẻ' -f $g.Name, $g.Count
            if ($g.Name -eq 'Đúng') { Write-Ok $t } else { Write-Bad ('{0} (vd thẻ {1}).' -f $t, $g.Group[0].Stt) }
        }
        Write-Head 'Tiếp theo'
        Write-Line ('1. Mở {0} bằng Excel: cột Kết quả tô đỏ là thẻ có vấn đề; cột CardID là mã đúng (chữ, đủ {1} số).' -f (Split-Path $dest -Leaf), $DoDai)
        Write-Line '2. Cần ra lại file .nt (vd sau khi sửa trong Excel): chạy "Chuyển Excel sang file .nt" với file này. Công cụ chỉ lấy cột STT và CardID. Chọn thư mục ghi khác để không đè file .nt gốc.'
        Write-Info 'Cột CardID để dạng chữ: gõ thêm mã vào vẫn giữ số 0 ở đầu.'
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
        if (-not $sw.Ok) {
            if ((Get-FileKind $File) -ne 'xlsx') { Write-Bad "Không đọc được như file Excel 97-2003: $($sw.Error)"; return 1 }
            Write-Warn 'File là .xlsx đổi đuôi: phần mềm giữ xe không đọc được. Công cụ đọc nội dung rồi ghi lại đúng định dạng.'
        }
        $list = Get-CardList (Read-AnyCells $File $work) $DoDai
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
    Write-Out 'CHUYỂN EXCEL SANG FILE .NT' 'Cyan'
    Write-Out ('{0}, {1:dd/MM/yyyy HH:mm}.' -f $File, (Get-Date))
    if (-not (Test-InputFile $File $script:ListExt)) { return 2 }
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
