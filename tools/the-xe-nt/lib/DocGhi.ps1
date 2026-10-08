# File thẻ xe - đọc, ghi file.
# File .nt là file Excel 97-2003 (.xls) đổi đuôi. Phần mềm giữ xe (ITS Pro) đọc nó bằng Jet OLEDB 4.0 "Excel 8.0":
# sheet đầu tiên, vùng A1:J65536, dòng 1 là tiêu đề, lấy cột STT và CardID theo giá trị thật của ô (không theo định
# dạng hiển thị). Jet chỉ có bản 32 bit nên mọi hàm ở đây chạy trong PowerShell 32 bit.
# Luôn đọc, ghi trên bản sao trong thư mục tạm; file gốc không bị mở để ghi.

function New-WorkDir {
    $d = Join-Path ([IO.Path]::GetTempPath()) ('TheXe_' + [guid]::NewGuid().ToString('N').Substring(0, 10))
    [void](New-Item -ItemType Directory -Path $d -Force)
    return $d
}

function Remove-WorkDir {
    param([string]$Dir)
    if ($Dir -and (Split-Path $Dir -Leaf) -like 'TheXe_*' -and (Test-Path -LiteralPath $Dir)) { Remove-Item -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue }
}

function Open-Jet {
    param([string]$Path, [string]$Props)
    if ([Environment]::Is64BitProcess) { throw 'Cần PowerShell 32 bit (Jet OLEDB 4.0 của Windows chỉ có bản 32 bit). Chạy bằng THE_XE.bat hoặc TheXe.ps1.' }
    $c = New-Object System.Data.OleDb.OleDbConnection(('Provider=Microsoft.Jet.OLEDB.4.0;Data Source={0};{1}' -f $Path, $Props))
    $c.Open()
    return $c
}

function Get-FirstTable {
    # Tên bảng đầu tiên Jet thấy (như phần mềm giữ xe: hàng đầu của danh sách bảng).
    param($Conn)
    $s = $Conn.GetOleDbSchemaTable([System.Data.OleDb.OleDbSchemaGuid]::Tables, @($null))
    if (-not $s.Rows.Count) { return '' }
    return [string]$s.Rows[0]['TABLE_NAME']
}

function Read-AsSoftware {
    # Đọc đúng cách phần mềm giữ xe đọc. Trả @{ Ok; Error; Table; Columns; HasStt; HasCard; SttType; CardType; Rows; Skipped }.
    # Rows: @{ Line (số dòng trong Excel); Stt; Card } là chữ phần mềm nhận được. Skipped: dòng phần mềm bỏ qua vì thiếu một trong hai.
    param([string]$Path)
    $r = [pscustomobject]@{ Ok = $false; Error = ''; Table = ''; Columns = @(); HasStt = $false; HasCard = $false; SttType = ''; CardType = ''; Rows = @(); Skipped = @() }
    $c = $null
    try {
        $c = Open-Jet $Path 'Jet OLEDB:Engine Type=5;Extended Properties=Excel 8.0;'
        $r.Table = Get-FirstTable $c
        $a = New-Object System.Data.OleDb.OleDbDataAdapter(('select * from [{0}A1:J65536]' -f $r.Table), $c)
        $d = New-Object System.Data.DataTable
        [void]$a.Fill($d)
    } catch {
        $r.Error = $_.Exception.Message.Trim()
        return $r
    } finally { if ($c) { $c.Close() } }
    $r.Columns = @($d.Columns | ForEach-Object { [pscustomobject]@{ Name = $_.ColumnName; Type = $_.DataType.Name } })
    $sc = $d.Columns['stt']; $cc = $d.Columns['cardid']   # DataTable tìm tên cột không phân biệt hoa thường, như phần mềm
    $r.HasStt = [bool]$sc; $r.HasCard = [bool]$cc
    if ($sc) { $r.SttType = $sc.DataType.Name }
    if ($cc) { $r.CardType = $cc.DataType.Name }
    $r.Ok = $true
    if (-not ($sc -and $cc)) { return $r }
    $rows = New-Object System.Collections.Generic.List[object]
    $skip = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $d.Rows.Count; $i++) {
        $row = $d.Rows[$i]
        $s = if ($row.IsNull($sc)) { '' } else { [string]$row[$sc] }
        $k = if ($row.IsNull($cc)) { '' } else { [string]$row[$cc] }
        $o = [pscustomobject]@{ Line = $i + 2; Stt = $s; Card = $k }
        if ($s -ne '' -and $k -ne '') { $rows.Add($o) } elseif ($s -ne '' -or $k -ne '') { $skip.Add($o) }
    }
    $r.Rows = $rows.ToArray(); $r.Skipped = $skip.ToArray()
    return $r
}

function Read-JetCells {
    # Mọi ô của sheet đầu tiên (A1:Z65536) dạng chữ, như người nhìn thấy giá trị (không phụ thuộc kiểu cột).
    # Trả mảng các dòng, mỗi dòng là mảng chữ; phần tử 0 là dòng 1 của Excel.
    param([string]$Path)
    $c = Open-Jet $Path 'Extended Properties="Excel 8.0;HDR=NO;IMEX=1";'
    try {
        $t = Get-FirstTable $c
        $a = New-Object System.Data.OleDb.OleDbDataAdapter(('select * from [{0}A1:Z65536]' -f $t), $c)
        $d = New-Object System.Data.DataTable
        [void]$a.Fill($d)
    } finally { $c.Close() }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($row in $d.Rows) {
        $out.Add([string[]]@(for ($j = 0; $j -lt $d.Columns.Count; $j++) { if ($row.IsNull($j)) { '' } else { ([string]$row[$j]).Trim() } }))
    }
    return , $out.ToArray()
}

function ConvertTo-CellText {
    param($V)
    if ($null -eq $V) { return '' }
    if ($V -is [double]) {
        if ([Math]::Abs($V) -lt 1e15 -and [Math]::Floor($V) -eq $V) { return ([int64]$V).ToString() }
        return $V.ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    return ([string]$V).Trim()
}

function Read-ExcelCells {
    # File .xlsx, .xlsm: đọc bằng Excel (cần Microsoft Excel trên máy), sheet đầu tiên.
    param([string]$Path)
    try { $xl = New-Object -ComObject Excel.Application } catch { throw 'Đọc file .xlsx cần Microsoft Excel trên máy. Mở danh sách bằng chương trình khác, lưu thành .xls hoặc .csv rồi chạy lại.' }
    try {
        $xl.Visible = $false; $xl.DisplayAlerts = $false
        $wb = $xl.Workbooks.Open($Path, 0, $true)
        $ws = $wb.Worksheets.Item(1)
        $ur = $ws.UsedRange
        $r0 = [int]$ur.Row; $c0 = [int]$ur.Column
        $nr = [int]$ur.Rows.Count; $nc = [Math]::Min([int]$ur.Columns.Count, 26)
        $v = $ur.Value2
        $out = New-Object System.Collections.Generic.List[object]
        for ($i = 1; $i -lt $r0; $i++) { $out.Add([string[]]@()) }
        for ($i = 1; $i -le $nr; $i++) {
            $cells = New-Object string[] ($c0 - 1 + $nc)
            for ($j = 0; $j -lt $cells.Length; $j++) { $cells[$j] = '' }
            for ($j = 1; $j -le $nc; $j++) {
                $x = if ($nr -eq 1 -and $nc -eq 1) { $v } else { $v[$i, $j] }
                $cells[$c0 - 2 + $j] = ConvertTo-CellText $x
            }
            $out.Add($cells)
        }
        $wb.Close($false)
        return , $out.ToArray()
    } finally {
        $xl.Quit()
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($xl)
    }
}

function Read-TextCells {
    # File .csv, .txt: tự nhận dấu phân cách (tab, ;, ,). UTF-8, không phải UTF-8 thì đọc theo bảng mã của Windows.
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    try { $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes) } catch { $text = [Text.Encoding]::Default.GetString($bytes) }
    $lines = $text.TrimStart([char]0xFEFF) -split "`r?`n"
    $first = [string]($lines | Where-Object { $_.Trim() } | Select-Object -First 1)
    $sep = "`t"
    foreach ($s in "`t", ';', ',') { if ($first.Contains($s)) { $sep = $s; break } }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($l in $lines) { $out.Add([string[]]@($l.Split($sep) | ForEach-Object { $_.Trim().Trim('"').Trim() })) }
    return , $out.ToArray()
}

function Read-AnyCells {
    # Đọc danh sách theo đuôi file (đọc trên bản sao trong $WorkDir).
    param([string]$Path, [string]$WorkDir)
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($ext) {
        { $_ -in '.nt', '.xls' } { $copy = Join-Path $WorkDir 'nguon.xls'; Copy-Item -LiteralPath $Path -Destination $copy -Force; return , (Read-JetCells $copy) }
        { $_ -in '.xlsx', '.xlsm' } { $copy = Join-Path $WorkDir ('nguon' + $ext); Copy-Item -LiteralPath $Path -Destination $copy -Force; return , (Read-ExcelCells $copy) }
        { $_ -in '.csv', '.txt' } { return , (Read-TextCells $Path) }
    }
    throw "Không đọc được file '$ext': dùng .nt, .xls, .xlsx, .csv hoặc .txt."
}

function Write-NtFile {
    # Ghi danh sách thẻ ra file .nt theo mẫu trống (mau\mau-trong.xls: Sheet1, STT số, CardID chữ, tinhtrang số).
    # Ghi bằng Jet nên không cần Excel; đọc lại như phần mềm giữ xe và so từng thẻ trước khi chép tới $Path.
    param([string]$Path, $Cards, [string]$WorkDir)
    $cards = @($Cards)
    if (-not $cards.Count) { throw 'Không có thẻ nào để ghi.' }
    if ($cards.Count -gt 65000) { throw 'Quá 65000 thẻ: phần mềm giữ xe chỉ đọc tới dòng 65536.' }
    $tpl = Join-Path $script:ToolDir 'mau\mau-trong.xls'
    if (-not (Test-Path -LiteralPath $tpl)) { throw "Thiếu file mẫu $tpl." }
    $work = Join-Path $WorkDir ('ghi_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.xls')
    Copy-Item -LiteralPath $tpl -Destination $work -Force
    $c = Open-Jet $work 'Extended Properties="Excel 8.0;HDR=YES";'
    try {
        # Dòng mẫu (STT 0) cho Jet biết kiểu từng cột; ghi đè nó bằng thẻ đầu tiên rồi thêm các thẻ còn lại.
        $up = $c.CreateCommand()
        $up.CommandText = 'UPDATE [Sheet1$] SET [STT] = ?, [CardID] = ?, [tinhtrang] = ? WHERE [STT] = 0'
        $ins = $c.CreateCommand()
        $ins.CommandText = 'INSERT INTO [Sheet1$] ([STT], [CardID], [tinhtrang]) VALUES (?, ?, ?)'
        foreach ($cmd in $up, $ins) {
            [void]$cmd.Parameters.Add('stt', [System.Data.OleDb.OleDbType]::Double)
            [void]$cmd.Parameters.Add('card', [System.Data.OleDb.OleDbType]::VarWChar, 255)
            [void]$cmd.Parameters.Add('tt', [System.Data.OleDb.OleDbType]::Double)
        }
        for ($i = 0; $i -lt $cards.Count; $i++) {
            $cmd = if ($i -eq 0) { $up } else { $ins }
            $cmd.Parameters[0].Value = [double]$cards[$i].Stt
            $cmd.Parameters[1].Value = [string]$cards[$i].Id
            $cmd.Parameters[2].Value = [double]$cards[$i].Tinh
            if ($cmd.ExecuteNonQuery() -ne 1) { throw "Không ghi được thẻ $($cards[$i].Stt)." }
        }
    } finally { $c.Close() }

    $chk = Read-AsSoftware $work
    if (-not $chk.Ok) { throw "Đọc lại file vừa ghi bị lỗi: $($chk.Error)" }
    if ($chk.CardType -ne 'String') { throw "File vừa ghi có cột CardID kiểu $($chk.CardType), không phải chữ." }
    if ($chk.Rows.Count -ne $cards.Count -or $chk.Skipped.Count) { throw "Đọc lại được $($chk.Rows.Count) thẻ, cần $($cards.Count)." }
    for ($i = 0; $i -lt $cards.Count; $i++) {
        if ($chk.Rows[$i].Stt -ne [string]$cards[$i].Stt -or $chk.Rows[$i].Card -ne [string]$cards[$i].Id) {
            throw "Đọc lại thẻ $($cards[$i].Stt) ra '$($chk.Rows[$i].Stt)', '$($chk.Rows[$i].Card)', khác lúc ghi."
        }
    }
    Copy-Item -LiteralPath $work -Destination $Path -Force
    return $chk.Rows.Count
}
