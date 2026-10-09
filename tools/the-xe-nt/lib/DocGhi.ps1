# File thẻ xe - đọc, ghi file.
# File .nt là file Excel 97-2003 (.xls) đổi đuôi. Phần mềm giữ xe (ITS Pro) đọc nó bằng Jet OLEDB 4.0 "Excel 8.0":
# sheet đầu tiên, vùng A1:J65536, dòng 1 là tiêu đề, lấy cột STT và CardID theo giá trị thật của ô (không theo định
# dạng hiển thị). Jet chỉ có bản 32 bit nên mọi hàm ở đây chạy trong PowerShell 32 bit.
# File .xlsx đọc, ghi thẳng (là file zip chứa XML), không cần Excel.
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

# ---------------------------------------------------------------- .xlsx (đọc, ghi thẳng file zip, không cần Excel)
function Open-XlsxZip {
    param([string]$Path, [string]$Mode = 'Read')
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    return [IO.Compression.ZipFile]::Open($Path, $Mode)
}

function Read-ZipXml {
    # Một phần XML trong file .xlsx (tên không phân biệt hoa thường); $null khi không có.
    param($Zip, [string]$Name)
    $n = $Name.TrimStart('/')
    $e = @($Zip.Entries | Where-Object { $_.FullName -ieq $n })
    if (-not $e.Count) { return $null }
    $s = $e[0].Open()
    try {
        $x = New-Object Xml.XmlDocument
        $x.XmlResolver = $null
        $x.LoadXml((New-Object IO.StreamReader($s, [Text.Encoding]::UTF8)).ReadToEnd())
        return $x
    } finally { $s.Dispose() }
}

function Get-ColumnIndex {
    # "B12" -> 1 (cột tính từ 0).
    param([string]$Ref)
    $n = 0
    foreach ($ch in ($Ref -replace '[^A-Za-z]', '').ToUpperInvariant().ToCharArray()) { $n = $n * 26 + ([int]$ch - 64) }
    return $n - 1
}

function Get-ColumnName {
    # 0 -> "A", 26 -> "AA".
    param([int]$Index)
    $s = ''; $n = $Index + 1
    while ($n -gt 0) { $m = ($n - 1) % 26; $s = [string][char](65 + $m) + $s; $n = [int][Math]::Floor(($n - 1) / 26) }
    return $s
}

function Get-XlsxPart {
    # Đường dẫn phần XML mà quan hệ $Id (hoặc kiểu $Type, vd "sharedStrings") của workbook trỏ tới; '' khi không có.
    param($Rels, [string]$Id = '', [string]$Type = '')
    if (-not $Rels) { return '' }
    foreach ($r in @($Rels.SelectNodes("//*[local-name()='Relationship']"))) {
        if (($Id -and $r.GetAttribute('Id') -eq $Id) -or ($Type -and $r.GetAttribute('Type') -like "*/$Type")) {
            $t = $r.GetAttribute('Target')
            if ($t.StartsWith('/')) { return $t.TrimStart('/') }
            return 'xl/' + $t
        }
    }
    return ''
}

function Read-XlsxCells {
    # File .xlsx, .xlsm: đọc thẳng các phần XML bên trong (không cần Excel), sheet đầu tiên, 26 cột đầu.
    # Trả như Read-JetCells; số nguyên ghi lại không có ".0" (mã thẻ lưu dạng số vẫn đọc ra đủ chữ số đang lưu).
    param([string]$Path)
    try { $zip = Open-XlsxZip $Path } catch { throw ("Không mở được '{0}' như file .xlsx: {1}" -f [IO.Path]::GetFileName($Path), $_.Exception.Message.Trim()) }
    try {
        $wb = Read-ZipXml $zip 'xl/workbook.xml'
        if (-not $wb) { throw 'Không phải file Excel .xlsx (thiếu xl/workbook.xml).' }
        $sheet = $wb.SelectSingleNode("//*[local-name()='sheets']/*[local-name()='sheet']")
        if (-not $sheet) { throw 'File .xlsx không có sheet nào.' }
        $rid = @($sheet.Attributes | Where-Object { $_.LocalName -eq 'id' } | ForEach-Object { $_.Value })
        $rels = Read-ZipXml $zip 'xl/_rels/workbook.xml.rels'
        $part = if ($rid.Count) { Get-XlsxPart $rels -Id $rid[0] } else { '' }
        $ws = if ($part) { Read-ZipXml $zip $part } else { $null }
        if (-not $ws) { throw 'Không tìm thấy sheet đầu tiên trong file .xlsx.' }
        $shared = New-Object System.Collections.Generic.List[string]
        $ssPart = Get-XlsxPart $rels -Type 'sharedStrings'
        $ss = Read-ZipXml $zip $(if ($ssPart) { $ssPart } else { 'xl/sharedStrings.xml' })
        if ($ss) {
            foreach ($si in @($ss.SelectNodes("//*[local-name()='si']"))) {
                $shared.Add((@($si.SelectNodes(".//*[local-name()='t' and not(ancestor::*[local-name()='rPh'])]") | ForEach-Object { $_.InnerText }) -join ''))
            }
        }
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $data = New-Object System.Collections.Generic.List[object]
        $maxCol = 0; $rn = 0
        foreach ($row in @($ws.SelectNodes("//*[local-name()='sheetData']/*[local-name()='row']"))) {
            $r = $row.GetAttribute('r')
            $rn = if ($r) { [int]$r } else { $rn + 1 }
            $cells = @{}; $cn = -1
            foreach ($c in @($row.SelectNodes("*[local-name()='c']"))) {
                $ref = $c.GetAttribute('r')
                $cn = if ($ref) { Get-ColumnIndex $ref } else { $cn + 1 }
                if ($cn -ge 26) { continue }
                $t = $c.GetAttribute('t')
                $v = $c.SelectSingleNode("*[local-name()='v']")
                $text = ''
                if ($t -eq 'inlineStr') {
                    $text = (@($c.SelectNodes(".//*[local-name()='t' and not(ancestor::*[local-name()='rPh'])]") | ForEach-Object { $_.InnerText }) -join '')
                } elseif ($v) {
                    $text = $v.InnerText
                    $d = 0.0
                    if ($t -eq 's') { $text = $shared[[int]$text] }
                    elseif (-not $t -or $t -eq 'n') { if ([double]::TryParse($text, [Globalization.NumberStyles]::Float, $inv, [ref]$d)) { $text = ConvertTo-CellText $d } }
                }
                $text = ([string]$text).Trim()
                if ($text -ne '') { $cells[$cn] = $text; if ($cn + 1 -gt $maxCol) { $maxCol = $cn + 1 } }
            }
            if ($cells.Count) { $data.Add([pscustomobject]@{ N = $rn; C = $cells }) }
        }
        $out = New-Object System.Collections.Generic.List[object]
        foreach ($d in @($data | Sort-Object N)) {
            while ($out.Count -lt $d.N - 1) { $out.Add([string[]]@()) }
            $cells = New-Object string[] $maxCol
            for ($j = 0; $j -lt $maxCol; $j++) { $cells[$j] = if ($d.C.ContainsKey($j)) { $d.C[$j] } else { '' } }
            $out.Add($cells)
        }
        return , $out.ToArray()
    } finally { $zip.Dispose() }
}

function Write-XlsxFile {
    # Ghi bảng ra file .xlsx (không cần Excel): một sheet "Sheet1", dòng tiêu đề in đậm, cố định khi cuộn, có nút lọc.
    # $Rows: mảng các mảng giá trị; số ([int], [int64], [double]) ghi dạng số, còn lại dạng chữ.
    # $TextCols: cột (tính từ 0) định dạng chữ "@" để gõ thêm mã vào vẫn giữ số 0 ở đầu.
    # $MarkCol: cột kết quả, ô khác $OkText tô đỏ.
    # Ghi ra file tạm cạnh $Path rồi mới đổi tên, nên lỗi giữa chừng không để lại file hỏng.
    param([string]$Path, [string[]]$Header, $Rows, [int[]]$Widths = @(), [int[]]$TextCols = @(), [int]$MarkCol = -1, [string]$OkText = '')
    $rows = @($Rows)
    $nc = $Header.Count
    $last = '{0}{1}' -f (Get-ColumnName ($nc - 1)), ($rows.Count + 1)
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$sb.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    [void]$sb.Append(('<dimension ref="A1:{0}"/>' -f $last))
    [void]$sb.Append('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>')
    for ($j = 0; $j -lt $nc; $j++) {
        $w = if ($j -lt $Widths.Count) { $Widths[$j] } else { 14 }
        $st = if ($TextCols -contains $j) { ' style="2"' } else { '' }
        [void]$sb.Append(('<col min="{0}" max="{0}" width="{1}"{2} customWidth="1"/>' -f ($j + 1), $w, $st))
    }
    [void]$sb.Append('</cols><sheetData><row r="1">')
    for ($j = 0; $j -lt $nc; $j++) {
        [void]$sb.Append(('<c r="{0}1" t="inlineStr" s="1"><is><t>{1}</t></is></c>' -f (Get-ColumnName $j), [Security.SecurityElement]::Escape($Header[$j])))
    }
    [void]$sb.Append('</row>')
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $r = $i + 2
        [void]$sb.Append(('<row r="{0}">' -f $r))
        $vals = @($rows[$i])
        for ($j = 0; $j -lt [Math]::Min($nc, $vals.Count); $j++) {
            $v = $vals[$j]
            if ($null -eq $v -or [string]$v -eq '') { continue }
            $ref = '{0}{1}' -f (Get-ColumnName $j), $r
            if ($v -is [int] -or $v -is [int64] -or $v -is [double]) {
                [void]$sb.Append(('<c r="{0}"><v>{1}</v></c>' -f $ref, ([double]$v).ToString('R', $inv)))
            } else {
                $s = if ($j -eq $MarkCol -and [string]$v -ne $OkText) { 3 } elseif ($TextCols -contains $j) { 2 } else { 0 }
                [void]$sb.Append(('<c r="{0}" t="inlineStr" s="{1}"><is><t xml:space="preserve">{2}</t></is></c>' -f $ref, $s, [Security.SecurityElement]::Escape([string]$v)))
            }
        }
        [void]$sb.Append('</row>')
    }
    [void]$sb.Append(('</sheetData><autoFilter ref="A1:{0}"/></worksheet>' -f $last))

    $head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    $parts = [ordered]@{
        '[Content_Types].xml'        = $head + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'
        '_rels/.rels'                = $head + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
        'xl/workbook.xml'            = $head + ('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets><definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">Sheet1!$A$1:${0}${1}</definedName></definedNames></workbook>' -f (Get-ColumnName ($nc - 1)), ($rows.Count + 1))
        'xl/_rels/workbook.xml.rels' = $head + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
        # Kiểu ô: 0 thường, 1 tiêu đề in đậm, 2 chữ ("@"), 3 chữ đỏ trên nền đỏ nhạt (kết quả có vấn đề).
        'xl/styles.xml'              = $head + '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="3"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font><font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font><font><sz val="11"/><color rgb="FF9C0006"/><name val="Calibri"/><family val="2"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFFC7CE"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="49" fontId="2" fillId="2" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'
        'xl/worksheets/sheet1.xml'   = $sb.ToString()
    }
    $tmp = $Path + '.tmp'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $zip = Open-XlsxZip $tmp 'Create'
    try {
        foreach ($name in $parts.Keys) {
            $s = $zip.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal).Open()
            try { $b = $utf8.GetBytes($parts[$name]); $s.Write($b, 0, $b.Length) } finally { $s.Dispose() }
        }
    } finally { $zip.Dispose() }
    try { Move-Item -LiteralPath $tmp -Destination $Path -Force } catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; throw }
}

function Get-FileKind {
    # Loại file theo nội dung, không theo đuôi (file .xlsx đổi đuôi .nt hay .xls vẫn nhận ra): 'xlsx', 'xls' hoặc 'text'.
    param([string]$Path)
    $b = New-Object byte[] 4
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try { $n = $fs.Read($b, 0, 4) } finally { $fs.Dispose() }
    if ($n -ge 2 -and $b[0] -eq 0x50 -and $b[1] -eq 0x4B) { return 'xlsx' }
    if ($n -ge 4 -and $b[0] -eq 0xD0 -and $b[1] -eq 0xCF -and $b[2] -eq 0x11 -and $b[3] -eq 0xE0) { return 'xls' }
    return 'text'
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
    # Đọc danh sách (.nt, .xls, .xlsx, .xlsm, .csv, .txt) trên bản sao trong $WorkDir. Nhận loại file theo nội dung.
    param([string]$Path, [string]$WorkDir)
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -notin '.nt', '.xls', '.xlsx', '.xlsm', '.csv', '.txt') { throw "Không đọc được file '$ext': dùng .nt, .xls, .xlsx, .csv hoặc .txt." }
    $kind = Get-FileKind $Path
    if ($kind -eq 'xlsx') { $copy = Join-Path $WorkDir 'nguon.xlsx'; Copy-Item -LiteralPath $Path -Destination $copy -Force; return , (Read-XlsxCells $copy) }
    if ($kind -eq 'xls') { $copy = Join-Path $WorkDir 'nguon.xls'; Copy-Item -LiteralPath $Path -Destination $copy -Force; return , (Read-JetCells $copy) }
    if ($ext -in '.csv', '.txt') { return , (Read-TextCells $Path) }
    throw ("File '{0}' không phải file Excel (.xls, .xlsx) cũng không phải .csv: mở bằng Excel, lưu lại thành .xlsx rồi chạy lại." -f [IO.Path]::GetFileName($Path))
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
