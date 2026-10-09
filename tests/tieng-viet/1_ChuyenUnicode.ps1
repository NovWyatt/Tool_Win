# Bài thử Chuyển tài liệu sang Unicode (Gói tiếng Việt): phần Python trong _chuyen_unicode.py dựng .docx, .xlsx tại chỗ
# (font đặt thẳng, kiểu ký tự, kiểu đoạn, kế thừa, chủ đề, khung chữ, đầu trang; ô Excel theo font, chữ dùng chung, chữ
# nhiều định dạng, kết quả công thức, ghi chú; file hỏng, tên bản sao, chỉ xem, JSON kết quả, tiến độ), chạy bằng Python
# của máy. vni.py, tcvn3.py phải giống hệt bản trong dwg2pdf; CHUYEN_UNICODE.bat thiếu Python thì báo, mã 2.
. "$PSScriptRoot\..\lib\KiemThu.ps1"
$ErrorActionPreference = 'Stop'
$toolDir = Join-Path $ToolsDir 'tieng-viet'
$bat = Join-Path $toolDir 'CHUYEN_UNICODE.bat'

foreach ($f in 'vni.py', 'tcvn3.py') {
    $a = [IO.File]::ReadAllBytes((Join-Path $toolDir $f))
    $b = [IO.File]::ReadAllBytes((Join-Path $ToolsDir "dwg2pdf\$f"))
    Check ([Convert]::ToBase64String($a) -ceq [Convert]::ToBase64String($b)) "$f giống hệt bản trong dwg2pdf (sửa một bên thì chép sang bên kia)"
}

$tj = Get-Content (Join-Path $toolDir 'tool.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$a = @($tj.actions | Where-Object { $_.id -eq 'chuyen' })[0]
Check ($a.file -eq 'CHUYEN_UNICODE.bat' -and $a.tienDo.flag -eq '--tien-do') 'tool.json: action chuyen chạy CHUYEN_UNICODE.bat, khai tienDo --tien-do'
$flags = @($a.args | ForEach-Object { $_.flag } | Where-Object { $_ })
$help = [IO.File]::ReadAllText((Join-Path $toolDir 'chuyen_unicode.py'))
Check (@($flags | Where-Object { $help -notmatch [regex]::Escape("`"$_`"") }).Count -eq 0) "mọi cờ trong tool.json có trong chuyen_unicode.py ($($flags -join ' '))"
$text = [IO.File]::ReadAllText($bat)
Check ($text -match 'chuyen_unicode\.py" %\*') 'file .bat chuyển mọi tham số (cả --tien-do) cho Python'

$kq = New-TestDir 'ket_qua'
$r = Invoke-Bat $bat @('x.docx') -Env @{ PATH = "$env:SystemRoot\System32"; TV_KHONG_DUNG = '1'; TV_KET_QUA = $kq }
Check ($r.Code -eq 2 -and $r.Out -match 'Python 3\.9' -and $r.Out -match 'Python\.Python\.3\.12') "thiếu Python: báo cách cài, mã 2 ($($r.Code))"

$py = Find-Python
if (-not $py) { Skip-Test 'không thấy Python: bỏ phần chuyển tài liệu'; Complete-Test }

$rong = New-TestDir 'rong'
$r = Invoke-Bat $bat @('--thu-muc', $rong, '--chi-xem') -Env @{ TV_KHONG_DUNG = '1'; TV_KET_QUA = $kq; PYTHONDONTWRITEBYTECODE = '1' }
$js = @(Get-ChildItem -LiteralPath $kq -Filter 'KetQua_TiengViet_ChuyenUnicode_*.json')
Check ($r.Code -eq 2 -and $js.Count -eq 1) "chạy qua .bat, thư mục không có tài liệu: mã 2, có file kết quả ($($r.Code), $($js.Count) file)"
if ($js.Count) {
    $j = [IO.File]::ReadAllText($js[0].FullName) | ConvertFrom-Json
    Check ($j.chuan -eq 'tramtool.ketqua/1' -and $j.congCu -eq 'tieng-viet' -and $j.cheDo -eq 'chuyen' -and $j.chayThu -eq $true) 'file kết quả đúng chuẩn, chế độ chuyen, chỉ xem là chạy thử'
}

$toolKq = Join-Path $toolDir 'ket_qua'
function Count-ToolKq { return @(Get-ChildItem -LiteralPath $toolKq -File -ErrorAction SilentlyContinue).Count }
$truoc = Count-ToolKq
$env:PYTHONDONTWRITEBYTECODE = '1'   # không để lại __pycache__ mới trong thư mục công cụ
$env:PYTHONIOENCODING = 'utf-8'
$env:TV_KET_QUA = $kq                # lỡ lời gọi nào quên --ket-qua thì cũng không ghi vào thư mục công cụ
$ErrorActionPreference = 'Continue'   # dòng stderr của Python (traceback) thành ErrorRecord: in ra chứ không dừng
$out = & $py -X utf8 (Join-Path $PSScriptRoot '_chuyen_unicode.py') (New-TestDir 'py') $toolDir 2>&1
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
Remove-Item Env:TV_KET_QUA
$n = 0; $xong = $false
foreach ($l in @($out | ForEach-Object { [string]$_ })) {
    if ($l -match '^KT ([01]) (.*)$') { $n++; Check ($Matches[1] -eq '1') $Matches[2] }
    elseif ($l -eq 'XONG') { $xong = $true }
    elseif ($l.Trim()) { Write-KT "  | $l" DarkGray }
}
Check ($code -eq 0 -and $xong) "phần Python chạy hết (mã $code)"
Check ($n -ge 35) "đủ các mục kiểm ($n)"
Check ((Count-ToolKq) -eq $truoc) 'không ghi gì vào thư mục ket_qua của công cụ'

Complete-Test
