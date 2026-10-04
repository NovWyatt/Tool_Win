# Cài môi trường cho công cụ DWG -> PDF (chạy được không cần quyền Admin).
#   1. Tìm Python 3.12 (thiếu thì cài bản cho riêng người dùng bằng winget)
#   2. Tạo .venv, cài thư viện đúng phiên bản trong requirements.txt (chỉ bản dựng sẵn, không biên dịch)
#   3. Tải LibreDWG 0.14 (GPL-3.0) từ GitHub, kiểm SHA256, giải nén vào bin\libredwg
#   4. Tự kiểm tra
# Chạy lại an toàn: phần nào đã có và còn dùng được thì bỏ qua. Thêm -LamLai để dựng lại từ đầu.
param([switch]$LamLai)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$here = $PSScriptRoot
$venvPy = Join-Path $here '.venv\Scripts\python.exe'
$binDir = Join-Path $here 'bin'
$dwg2dxf = Join-Path $binDir 'libredwg\dwg2dxf.exe'
$libreUrl = 'https://github.com/LibreDWG/libredwg/releases/download/0.14/libredwg-0.14-win64.zip'
$libreSha256 = '1AD7E15344D20B3426C3435B078D82FB84B35062815946B2CCA9C5FC9810FEA8'

function Buoc([string]$text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }
function Loi([string]$text) { Write-Host "LOI: $text" -ForegroundColor Red; exit 1 }

function Tim-Python312 {
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) {
        $exe = & $py.Source -3.12 -c 'import sys; print(sys.executable)' 2>$null
        if ($LASTEXITCODE -eq 0 -and $exe -and (Test-Path -LiteralPath $exe)) { return $exe }
    }
    $macDinh = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'
    if (Test-Path -LiteralPath $macDinh) { return $macDinh }
    return $null
}

Buoc 'Python 3.12'
$python = Tim-Python312
if (-not $python) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { Loi 'Không có Python 3.12 và không có winget. Cài Python 3.12 từ python.org rồi chạy lại.' }
    Write-Host 'Chưa có Python 3.12, đang cài bản cho riêng tài khoản này (không cần Admin)...'
    & $winget.Source install --id Python.Python.3.12 -e --scope user --silent --accept-package-agreements --accept-source-agreements --override 'InstallAllUsers=0 PrependPath=1 Include_launcher=1 Include_test=0 /quiet'
    $python = Tim-Python312
    if (-not $python) { Loi 'Cài Python 3.12 không thành công.' }
}
Write-Host "Dùng: $python"

Buoc 'Môi trường .venv'
$venvOk = $false
if ((Test-Path -LiteralPath $venvPy) -and -not $LamLai) {
    & $venvPy -c 'import ezdxf, pymupdf, olefile, PIL' 2>$null
    $venvOk = $LASTEXITCODE -eq 0
}
if (-not $venvOk) {
    $venvDir = Join-Path $here '.venv'
    if (Test-Path -LiteralPath $venvDir) { Remove-Item -LiteralPath $venvDir -Recurse -Force }
    & $python -m venv $venvDir
    if ($LASTEXITCODE -ne 0) { Loi 'Không tạo được .venv.' }
    & $venvPy -m pip install --disable-pip-version-check --only-binary=:all: -r (Join-Path $here 'requirements.txt') -c (Join-Path $here 'requirements-lock.txt')
    if ($LASTEXITCODE -ne 0) { Loi 'Cài thư viện Python không thành công (cần mạng Internet).' }
} else {
    Write-Host 'Đã có, bỏ qua.'
}

Buoc 'LibreDWG 0.14'
if ((Test-Path -LiteralPath $dwg2dxf) -and -not $LamLai) {
    Write-Host 'Đã có, bỏ qua.'
} else {
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    $zip = Join-Path $binDir 'libredwg-0.14-win64.zip'
    Write-Host "Tải $libreUrl"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $libreUrl -OutFile $zip -UseBasicParsing
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    if ($hash -ne $libreSha256) {
        Remove-Item -LiteralPath $zip -Force
        Loi "File tải về sai mã kiểm tra (SHA256 $hash). Đã xoá, không giải nén."
    }
    $dich = Join-Path $binDir 'libredwg'
    if (Test-Path -LiteralPath $dich) { Remove-Item -LiteralPath $dich -Recurse -Force }
    Expand-Archive -LiteralPath $zip -DestinationPath $dich -Force
    Remove-Item -LiteralPath $zip -Force
    if (-not (Test-Path -LiteralPath $dwg2dxf)) { Loi 'Giải nén xong nhưng không thấy dwg2dxf.exe.' }
}

Buoc 'Tự kiểm tra'
$ver = & $dwg2dxf --version 2>&1 | Select-Object -First 1
# PowerShell 5.1 làm rơi dấu " khi truyền cho chương trình ngoài, nên mã Python chỉ dùng dấu '
& $venvPy -c 'import ezdxf, pymupdf; print(''ezdxf'', ezdxf.__version__, ''- PyMuPDF'', pymupdf.VersionBind)'
if ($LASTEXITCODE -ne 0) { Loi 'Thư viện Python chưa dùng được.' }
Write-Host "LibreDWG: $ver"
Write-Host ''
Write-Host 'XONG. Kéo thả thư mục bản vẽ .dwg vào CHUYEN_DWG_SANG_PDF.bat để chuyển.' -ForegroundColor Green
exit 0
