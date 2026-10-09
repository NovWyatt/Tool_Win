# Trạm Tool - hàm dùng chung (PowerShell 5.1+)
# File này phải lưu UTF-8 có BOM, nếu không PowerShell 5.1 đọc sai chữ tiếng Việt.

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-Prop {
    # Đọc thuộc tính an toàn từ PSCustomObject/hashtable, thiếu thì trả $Default.
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name) -and $null -ne $Object[$Name]) { return $Object[$Name] }
        return $Default
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p -and $null -ne $p.Value) { return $p.Value }
    return $Default
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    return ($text | ConvertFrom-Json)
}

function ConvertTo-HubJson {
    param($InputObject, [switch]$Compress)
    if ($Compress) { return (ConvertTo-Json -InputObject $InputObject -Depth 12 -Compress) }
    return (ConvertTo-Json -InputObject $InputObject -Depth 12)
}

function Write-JsonFile {
    param([Parameter(Mandatory)][string]$Path, $InputObject)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, (ConvertTo-HubJson $InputObject), $script:Utf8NoBom)
}

function Add-JsonLine {
    param([Parameter(Mandatory)][string]$Path, $InputObject)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::AppendAllText($Path, (ConvertTo-HubJson $InputObject -Compress) + "`n", $script:Utf8NoBom)
}

function Get-IsoTime {
    param([datetime]$Date = (Get-Date))
    return $Date.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Expand-HubPath {
    # Mở rộng %BIEN_MOI_TRUONG% và đường dẫn tương đối (tính từ $BaseDir).
    param([string]$Path, [string]$BaseDir)
    if (-not $Path) { return $BaseDir }
    $p = [Environment]::ExpandEnvironmentVariables($Path)
    if ($p -match '^\{Desktop\}') { $p = $p -replace '^\{Desktop\}', [Environment]::GetFolderPath('Desktop') }
    if ($p -match '^\{Documents\}') { $p = $p -replace '^\{Documents\}', [Environment]::GetFolderPath('MyDocuments') }
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $BaseDir $p }
    return [System.IO.Path]::GetFullPath($p)
}

function Test-PathInside {
    # Đúng khi $Path nằm trong $Root (chống ../ thoát ra ngoài).
    param([string]$Path, [string]$Root)
    if (-not $Path -or -not $Root) { return $false }
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    return ($full -eq $rootFull) -or $full.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)
}

function New-DesktopShortcut {
    # Lối tắt "Trạm Tool" trên Desktop trỏ tới TramTool.bat (dùng ở trang Cài đặt và CAI_DAT.bat).
    param([Parameter(Mandatory)][string]$RootDir, [Parameter(Mandatory)][string]$HubDir)
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnk = Join-Path $desktop 'Trạm Tool.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $s = $shell.CreateShortcut($lnk)
    $s.TargetPath = Join-Path $RootDir 'TramTool.bat'
    $s.WorkingDirectory = $RootDir
    $s.WindowStyle = 7
    $ico = Join-Path $HubDir 'web\tramtool.ico'
    $s.IconLocation = if (Test-Path -LiteralPath $ico) { $ico } else { "$env:SystemRoot\System32\imageres.dll,109" }
    $s.Description = 'Trạm Tool - chọn và chạy công cụ Windows'
    $s.Save()
    return $lnk
}

function Update-EnvPath {
    # Nạp lại PATH từ registry để thấy Python/winget vừa cài trong lúc trạm đang chạy.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Write-HubLog {
    param([string]$Message, [ValidateSet('info', 'ok', 'warn', 'error')][string]$Level = 'info')
    $color = @{ info = 'Gray'; ok = 'Green'; warn = 'Yellow'; error = 'Red' }[$Level]
    Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message) -ForegroundColor $color
}

function New-HubToken {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function ConvertTo-Slug {
    param([string]$Text)
    $n = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $n.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    $s = $sb.ToString().Replace('đ', 'd').Replace('Đ', 'D').ToLowerInvariant()
    $s = [regex]::Replace($s, '[^a-z0-9]+', '-').Trim('-')
    if (-not $s) { $s = 'tool' }
    return $s
}
