# File thẻ xe - phần dùng chung: in ra màn hình kèm ghi báo cáo, hỏi người dùng, thư mục kết quả.

$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Report = New-Object System.Collections.Generic.List[string]
$script:NoPause = $false

function Write-Out {
    param([string]$Text = '', [string]$Color = '')
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
    [void]$script:Report.Add($Text)
}
function Write-Head { param([string]$Text) Write-Out ''; Write-Out ("== $Text " + ('=' * [Math]::Max(3, 68 - $Text.Length))) 'Cyan' }
function Write-Line { param([string]$Text) Write-Out "  $Text" }
function Write-Sub { param([string]$Text) Write-Out "       $Text" 'Gray' }
function Write-Ok { param([string]$Text) Write-Out "  [OK] $Text" 'Green' }
function Write-Warn { param([string]$Text) Write-Out "  [!]  $Text" 'Yellow' }
function Write-Bad { param([string]$Text) Write-Out "  [X]  $Text" 'Red' }
function Write-Info { param([string]$Text) Write-Out "  [i]  $Text" 'Gray' }

# Không có bàn phím (chạy tự động, stdin bị chuyển hướng) thì trả giá trị an toàn thay vì treo.
function Test-NoInput { return [Console]::IsInputRedirected }

function Read-Text {
    param([string]$Prompt, [string]$Default = '')
    if (Test-NoInput) { return $Default }
    $a = ([string](Read-Host "  $Prompt")).Trim()
    if (-not $a) { return $Default }
    return $a
}

function Read-YesNo {
    param([string]$Question, [bool]$Default = $false)
    if (Test-NoInput) { return $Default }
    $hint = if ($Default) { '[C/k]' } else { '[c/K]' }
    while ($true) {
        $a = ([string](Read-Host "  $Question $hint")).Trim().ToLowerInvariant()
        if (-not $a) { return $Default }
        if ($a -in 'c', 'co', 'có', 'y', 'yes') { return $true }
        if ($a -in 'k', 'khong', 'không', 'n', 'no') { return $false }
        Write-Host '  Gõ C (có) hoặc K (không).' -ForegroundColor Yellow
    }
}

function Wait-Close {
    param([string]$Text = 'Bấm Enter để đóng cửa sổ')
    if ($script:NoPause -or (Test-NoInput)) { return }
    Write-Host ''
    [void](Read-Host "  $Text")
}

function Get-ResultDir {
    # ket_qua trong thư mục công cụ; thư mục công cụ không ghi được thì ra Desktop.
    $d = Join-Path $script:ToolDir 'ket_qua'
    try {
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force -ErrorAction Stop) }
        return $d
    } catch {
        $d = Join-Path ([Environment]::GetFolderPath('Desktop')) 'TheXe_ket_qua'
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
        return $d
    }
}

function Save-Report {
    # Ghi các dòng đã in ra file (UTF-8 có BOM để Notepad đọc đúng dấu). Trả đường dẫn, '' khi không ghi được.
    param([string]$Prefix, [string]$Name, [datetime]$Started)
    $safe = ($Name -replace '[^\w.-]', '_')
    if ($safe.Length -gt 40) { $safe = $safe.Substring(0, 40) }
    $path = Join-Path (Get-ResultDir) ('{0}_{1}_{2:yyyyMMdd_HHmmss}.txt' -f $Prefix, $safe, $Started)
    try {
        [IO.File]::WriteAllLines($path, $script:Report, $script:Utf8Bom)
        Write-Host ''
        Write-Host "  Đã lưu: $path" -ForegroundColor Green
        return $path
    } catch {
        Write-Host "  Không lưu được báo cáo: $($_.Exception.Message)" -ForegroundColor Red
        return ''
    }
}
