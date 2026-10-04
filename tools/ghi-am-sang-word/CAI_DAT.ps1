# Cài môi trường cho công cụ Ghi âm -> Word (không cần quyền Admin).
#   1. Tìm Python 3.12 (thiếu thì cài bản cho riêng người dùng bằng winget)
#   2. Kiểm tra .venv; hỏng hoặc thiếu thì dựng lại theo requirements.txt + requirements-lock.txt
#      (máy có card NVIDIA thì cài thêm thư viện CUDA trong requirements-cuda.txt, khoảng 1 GB)
#   3. Thiếu mô hình faster-whisper-large-v3 thì tải từ Hugging Face (khoảng 3 GB, đúng bản đã kiểm)
#   4. Tự kiểm tra: nạp thư viện, đếm card đồ họa CUDA
# Chạy lại an toàn: phần nào còn dùng được thì bỏ qua. -LamLai: dựng lại .venv (không tải lại mô hình).
param([switch]$LamLai)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$here = $PSScriptRoot
$venvDir = Join-Path $here '.venv'
$venvPy = Join-Path $venvDir 'Scripts\python.exe'
$modelDir = Join-Path $here 'models\faster-whisper-large-v3'
$modelRepo = 'Systran/faster-whisper-large-v3'
$modelRev = 'edaa852ec7e145841d8ffdb056a99866b5f0a478'

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

$coNvidia = [bool](Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' })

Buoc 'Môi trường .venv'
$venvOk = $false
if ((Test-Path -LiteralPath $venvPy) -and -not $LamLai) {
    # .venv chép từ máy khác sẽ trỏ tới Python không có ở máy này: python.exe báo lỗi ngay, coi như hỏng.
    & $venvPy -c 'import faster_whisper, ctranslate2, docx' 2>$null
    $venvOk = $LASTEXITCODE -eq 0
}
if ($venvOk) {
    Write-Host 'Đã có và nạp được thư viện, bỏ qua.'
} else {
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
    if (Test-Path -LiteralPath $venvDir) { Remove-Item -LiteralPath $venvDir -Recurse -Force }
    & $python -m venv $venvDir
    if ($LASTEXITCODE -ne 0) { Loi 'Không tạo được .venv.' }
    $pipArgs = @('-m', 'pip', 'install', '--disable-pip-version-check', '--only-binary=:all:',
        '-r', (Join-Path $here 'requirements.txt'), '-c', (Join-Path $here 'requirements-lock.txt'))
    if ($coNvidia) {
        Write-Host 'Máy có card NVIDIA: cài thêm thư viện CUDA (khoảng 1 GB).'
        $pipArgs += @('-r', (Join-Path $here 'requirements-cuda.txt'))
    }
    & $venvPy @pipArgs
    if ($LASTEXITCODE -ne 0) { Loi 'Cài thư viện Python không thành công (cần mạng Internet).' }
}

Buoc 'Mô hình nhận dạng tiếng nói'
$modelBin = Join-Path $modelDir 'model.bin'
if ((Test-Path -LiteralPath $modelBin) -and (Get-Item -LiteralPath $modelBin).Length -gt 2.5GB) {
    Write-Host 'faster-whisper-large-v3: đã có, bỏ qua.'
} else {
    Write-Host "Tải $modelRepo (khoảng 3 GB, tải tiếp được nếu đứt mạng)..."
    $code = 'import sys; from huggingface_hub import snapshot_download; snapshot_download(sys.argv[1], revision=sys.argv[2], local_dir=sys.argv[3], allow_patterns=[''config.json'', ''preprocessor_config.json'', ''model.bin'', ''tokenizer.json'', ''vocabulary.*''])'
    & $venvPy -c $code $modelRepo $modelRev $modelDir
    if ($LASTEXITCODE -ne 0) { Loi 'Tải mô hình không thành công. Chạy lại để tải tiếp.' }
}
$pho = Join-Path $here 'models\phowhisper-large-ct2\model.bin'
if (-not (Test-Path -LiteralPath $pho)) {
    Write-Host 'phowhisper-large-ct2: chưa có (không bắt buộc; cách tạo xem HUONG_DAN_SU_DUNG.txt).'
}

Buoc 'Tự kiểm tra'
& $venvPy -c 'import faster_whisper, ctranslate2; print(''faster-whisper'', faster_whisper.__version__, ''- ctranslate2'', ctranslate2.__version__, ''- so card CUDA:'', ctranslate2.get_cuda_device_count())'
if ($LASTEXITCODE -ne 0) { Loi 'Thư viện chưa dùng được.' }
if ($coNvidia) {
    $soCard = & $venvPy -c 'import ctranslate2; print(ctranslate2.get_cuda_device_count())'
    if ([int]$soCard -lt 1) {
        Write-Host 'Có card NVIDIA nhưng CUDA không nhận: cập nhật driver NVIDIA (cần bản 525 trở lên). Tạm thời công cụ sẽ chạy bằng CPU.' -ForegroundColor Yellow
    }
} else {
    Write-Host 'Máy không có card NVIDIA: công cụ chạy bằng CPU, chậm hơn nhiều (1 giờ ghi âm có thể mất vài giờ).' -ForegroundColor Yellow
}
Write-Host ''
Write-Host 'XONG. Chép file ghi âm vào thư mục này rồi bấm đúp CHUYEN_DOI_GHI_AM.bat.' -ForegroundColor Green
exit 0
