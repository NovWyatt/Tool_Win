# Trạm Tool - kiểm tra yêu cầu (deps), trạng thái hiện tại (probes), kết quả (outputs), đóng gói, thông tin máy

$script:CheckCache = @{}

function Get-Cached {
    param([string]$Key, [int]$Seconds, [scriptblock]$Compute)
    $hit = $script:CheckCache[$Key]
    if ($hit -and ((Get-Date) - $hit.At).TotalSeconds -lt $Seconds) { return $hit.Value }
    $value = & $Compute
    $script:CheckCache[$Key] = @{ At = Get-Date; Value = $value }
    return $value
}

function Clear-CheckCache { $script:CheckCache = @{} }

# ---------------------------------------------------------------- Python
function Get-PythonCandidates {
    return Get-Cached -Key 'python' -Seconds 60 -Compute {
        $ErrorActionPreference = 'Continue'   # py.exe/python.exe hỏng có thể ghi stderr; xem Test-ToolRequirement
        $found = New-Object System.Collections.ArrayList
        $py = Get-Command py.exe -ErrorAction SilentlyContinue
        if ($py) {
            foreach ($line in @(& $py.Source -0p 2>$null)) {
                if ($line -match '-V:(\d+\.\d+)\S*\s+\*?\s*(.+\.exe)\s*$' -or $line -match '-(\d+\.\d+)(?:-\d+)?\s+\*?\s*(.+\.exe)\s*$') {
                    $path = $Matches[2].Trim()
                    if (Test-Path -LiteralPath $path) { [void]$found.Add([ordered]@{ version = $Matches[1]; path = $path; source = 'py' }) }
                }
            }
        }
        foreach ($cmd in @(Get-Command python.exe -All -ErrorAction SilentlyContinue)) {
            if ($cmd.Source -match '\\WindowsApps\\') { continue }   # lối tắt Microsoft Store, không phải Python thật
            if ($found | Where-Object { $_.path -eq $cmd.Source }) { continue }
            $v = (& $cmd.Source --version 2>&1) -join ' '
            if ($v -match 'Python (\d+\.\d+)') { [void]$found.Add([ordered]@{ version = $Matches[1]; path = $cmd.Source; source = 'path' }) }
        }
        , $found.ToArray()
    }
}

function Compare-Version {
    param([string]$A, [string]$B)
    return ([version]($A + '.0')).CompareTo([version]($B + '.0'))
}

function Find-Python {
    param([string]$Min = '3.8', [string]$Max = '')
    $ok = @(Get-PythonCandidates | Where-Object {
            (Compare-Version $_.version $Min) -ge 0 -and (-not $Max -or (Compare-Version $_.version $Max) -le 0)
        } | Sort-Object { [version]($_.version + '.0') } -Descending)
    if ($ok.Count) { return $ok[0] }
    return $null
}

# ---------------------------------------------------------------- Requirements
function Test-ToolRequirement {
    param($Req, $Tool)
    # PowerShell 5.1: với 'Stop', chương trình ngoài ghi stderr (vd Python báo ImportError) bị biến thành lỗi dừng
    # dù đã chuyển hướng 2>$null. Trong hàm này chỉ dựa vào $LASTEXITCODE.
    $ErrorActionPreference = 'Continue'
    $type = [string](Get-Prop $Req 'type' '')
    $r = [ordered]@{
        id = [string](Get-Prop $Req 'id' $type); type = $type; label = [string](Get-Prop $Req 'label' $type)
        optional = [bool](Get-Prop $Req 'optional' $false); ok = $false; detail = ''; fix = (Get-Prop $Req 'fix' $null)
    }
    try {
        switch ($type) {
            'python' {
                $min = [string](Get-Prop $Req 'min' '3.8'); $max = [string](Get-Prop $Req 'max' '')
                $p = Find-Python -Min $min -Max $max
                if ($p) { $r.ok = $true; $r.detail = "Python $($p.version) - $($p.path)" }
                else { $r.detail = "Chưa có Python $min trở lên (lệnh 'python' hiện chỉ là lối tắt Microsoft Store hoặc chưa cài)." }
            }
            'venv' {
                $venv = Expand-HubPath -Path ([string](Get-Prop $Req 'path' '.venv')) -BaseDir $Tool.dir
                $exe = Join-Path $venv 'Scripts\python.exe'
                if (-not (Test-Path -LiteralPath $exe)) { $r.detail = 'Chưa có môi trường Python (.venv).' }
                else {
                    $out = (& $exe -c 'import sys; print(sys.version.split()[0])' 2>&1) -join ' '
                    if ($LASTEXITCODE -eq 0) {
                        $r.ok = $true; $r.detail = "Python $out trong .venv"
                        $mods = @(@(Get-Prop $Req 'modules' @()) | Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_.]*$' })
                        if ($mods.Count) {
                            $missing = @()
                            foreach ($mod in $mods) {
                                & $exe -c "import $mod" 2>$null | Out-Null
                                if ($LASTEXITCODE -ne 0) { $missing += $mod }
                            }
                            if ($missing.Count) { $r.ok = $false; $r.detail = "Python $out trong .venv nhưng thiếu thư viện: $($missing -join ', ')." }
                            else { $r.detail += ", đủ thư viện ($($mods -join ', '))" }
                        }
                    } else {
                        $home = ''
                        $cfg = Join-Path $venv 'pyvenv.cfg'
                        if (Test-Path -LiteralPath $cfg) { $home = ((Get-Content -LiteralPath $cfg) | Where-Object { $_ -match '^\s*home\s*=' }) -replace '^\s*home\s*=\s*', '' }
                        $r.detail = ".venv hỏng: Python gốc không còn ở '$home'. Cài lại đúng phiên bản đó hoặc dựng lại .venv."
                    }
                }
            }
            'file' {
                $p = Expand-HubPath -Path ([string](Get-Prop $Req 'path' '')) -BaseDir $Tool.dir
                $r.ok = Test-Path -LiteralPath $p
                $minMB = [double](Get-Prop $Req 'minSizeMB' 0)
                if ($r.ok -and $minMB -gt 0 -and (Test-Path -LiteralPath $p -PathType Leaf)) {
                    $size = (Get-Item -LiteralPath $p).Length
                    if ($size -lt $minMB * 1MB) { $r.ok = $false; $r.detail = "File chưa tải xong ($(Format-Size $size))." }
                    else { $r.detail = "Có sẵn ($(Format-Size $size))." }
                } else {
                    $r.detail = if ($r.ok) { 'Có sẵn.' } else { "Thiếu: $([string](Get-Prop $Req 'path' ''))" }
                }
            }
            'pymodule' {
                # Thư viện cài cho Python chung của máy (không phải .venv), vd pyodbc của mdf2sql.
                $mod = [string](Get-Prop $Req 'module' '')
                if ($mod -notmatch '^[A-Za-z_][A-Za-z0-9_.]*$') { throw "Tên thư viện '$mod' không hợp lệ." }
                $p = Find-Python -Min ([string](Get-Prop $Req 'min' '3.8'))
                if (-not $p) { $r.detail = 'Chưa có Python nên chưa kiểm tra được.' }
                else {
                    $ver = (& $p.path -c "import $mod; print(getattr($mod, '__version__', ''))" 2>$null) -join ' '
                    if ($LASTEXITCODE -eq 0) { $r.ok = $true; $r.detail = ("$mod $ver".Trim() + " (Python $($p.version))") }
                    else { $r.detail = "Python $($p.version) chưa có thư viện $mod." }
                }
            }
            'path' {
                foreach ($pat in @(Get-Prop $Req 'paths' @())) {
                    $hit = @(Resolve-Path -Path ([Environment]::ExpandEnvironmentVariables($pat)) -ErrorAction SilentlyContinue | Select-Object -First 1)
                    if ($hit.Count) { $r.ok = $true; $r.detail = $hit[0].Path; break }
                }
                if (-not $r.ok) { $r.detail = 'Chưa cài.' }
            }
            'command' {
                $c = Get-Command ([string](Get-Prop $Req 'name' '')) -ErrorAction SilentlyContinue | Select-Object -First 1
                $r.ok = [bool]$c
                $r.detail = if ($c) { $c.Source } else { 'Không tìm thấy lệnh trong PATH.' }
            }
            'odbc' {
                $names = @(Get-Prop $Req 'names' @())
                $installed = @()
                $key = 'HKLM:\SOFTWARE\ODBC\ODBCINST.INI\ODBC Drivers'
                if (Test-Path $key) { $installed = @((Get-Item $key).Property) }
                $match = @($names | Where-Object { $installed -contains $_ })
                $r.ok = $match.Count -gt 0
                $r.detail = if ($r.ok) { $match[0] } else { 'Chưa có. Driver đang có: ' + ($(if ($installed.Count) { $installed -join ', ' } else { 'không' })) }
            }
            'sqlserver' {
                $found = @()
                $ldb = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server Local DB\Installed Versions'
                if (Test-Path $ldb) { $found += @(Get-ChildItem $ldb | ForEach-Object { 'LocalDB ' + $_.PSChildName }) }
                $found += @(Get-Service -Name 'MSSQL*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'MSSQLFDLauncher|OLAP' } | ForEach-Object { "$($_.DisplayName) ($($_.Status))" })
                $r.ok = $found.Count -gt 0
                $r.detail = if ($r.ok) { $found -join '; ' } else { 'Chưa có SQL Server (LocalDB hoặc Express).' }
            }
            'gpu' {
                $vendor = [string](Get-Prop $Req 'vendor' '')
                $gpus = @(Get-Cached -Key 'gpu' -Seconds 300 -Compute { , @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) })
                $hit = @($gpus | Where-Object { -not $vendor -or $_ -match [regex]::Escape($vendor) })
                $r.ok = $hit.Count -gt 0
                $r.detail = if ($r.ok) { $hit -join ', ' } else { 'Không thấy. Card đang có: ' + ($gpus -join ', ') }
            }
            'windows' {
                $build = [Environment]::OSVersion.Version.Build
                $min = [int](Get-Prop $Req 'minBuild' 0)
                $r.ok = $build -ge $min
                $r.detail = "Build $build"
            }
            default { $r.detail = "Không biết kiểu kiểm tra '$type'." }
        }
    } catch { $r.detail = "Lỗi khi kiểm tra: $($_.Exception.Message)" }
    return $r
}

function Get-ToolRequirements {
    param($Tool, [switch]$Fresh)
    if ($Fresh) { $script:CheckCache.Remove('python'); $script:CheckCache.Remove("req:$($Tool.id)") }
    return Get-Cached -Key "req:$($Tool.id)" -Seconds 120 -Compute {
        , @(foreach ($req in $Tool.requires) { Test-ToolRequirement -Req $req -Tool $Tool })
    }
}

function Start-RequirementFix {
    # Mở cửa sổ PowerShell chạy winget để người dùng thấy tiến trình cài.
    param($Fix)
    $winget = [string](Get-Prop $Fix 'winget' '')
    if (-not $winget) { throw 'Yêu cầu này không có cách cài tự động.' }
    if ($winget -notmatch '^[A-Za-z0-9._-]+$') { throw 'Mã gói winget không hợp lệ.' }
    $extra = [string](Get-Prop $Fix 'args' '')
    if ($extra -match '[;&|`$]') { throw 'Tham số winget không hợp lệ.' }
    $msg = 'Xong. Quay lại Trạm Tool và bấm "Kiểm tra lại". Có thể đóng cửa sổ này.'
    $cmd = "`$host.UI.RawUI.WindowTitle = 'Tram Tool - cai $winget'; winget install --id $winget --exact --accept-package-agreements --accept-source-agreements $extra; Write-Host ''; Write-Host '$msg' -ForegroundColor Green"
    $p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', $cmd) -PassThru
    Invoke-BringToFront -Process $p
}

# ---------------------------------------------------------------- Probes (đọc trạng thái, không sửa)
function Get-ToolProbes {
    param($Tool)
    $out = @()
    foreach ($p in $Tool.probes) {
        $type = [string](Get-Prop $p 'type' '')
        $row = [ordered]@{ label = [string](Get-Prop $p 'label' ''); value = ''; state = 'unknown'; detail = [string](Get-Prop $p 'note' '') }
        try {
            if ($type -eq 'service') {
                $name = [string](Get-Prop $p 'name' '')
                $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
                if (-not $svc) { $row.value = 'Không có trên máy này' }
                else {
                    $status = @{ Running = 'Đang chạy'; Stopped = 'Đã dừng'; Paused = 'Tạm dừng'; StartPending = 'Đang khởi động'; StopPending = 'Đang dừng' }[[string]$svc.Status]
                    $start = @{ Automatic = 'Tự khởi động'; Manual = 'Thủ công'; Disabled = 'Đã vô hiệu hoá'; Boot = 'Boot'; System = 'System' }[[string]$svc.StartType]
                    $row.value = "$status · $start"
                    $default = [string](Get-Prop $p 'default' '')
                    $row.state = if ($default -and [string]$svc.StartType -ne $default) { 'changed' } else { 'default' }
                    if (-not $row.label) { $row.label = $svc.DisplayName }
                }
            } elseif ($type -eq 'registry') {
                $path = [string](Get-Prop $p 'path' ''); $name = [string](Get-Prop $p 'name' '')
                $raw = $null
                if (Test-Path -LiteralPath $path) { $raw = (Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue).$name }
                $values = Get-Prop $p 'values' $null
                $key = if ($null -eq $raw) { '' } else { [string]$raw }
                $label = Get-Prop $values $key $null
                $row.value = if ($label) { $label } elseif ($null -eq $raw) { 'Chưa đặt (mặc định Windows)' } else { "Giá trị: $raw" }
                $row.state = if ($null -eq $raw) { 'default' } else { 'changed' }
            } else { $row.value = "Không biết kiểu '$type'" }
        } catch { $row.value = 'Lỗi khi đọc'; $row.detail = $_.Exception.Message }
        $out += $row
    }
    return $out   # trả từng phần tử; nơi gọi bọc @() (trả ", mảng" sẽ thành mảng lồng trong JSON)
}

# ---------------------------------------------------------------- Outputs
function Get-ToolOutputs {
    # outputs[]: { label, dir (mặc định thư mục công cụ; nhận %BIEN%, {Desktop}, dấu * ở phần cuối),
    #              glob (nhiều mẫu cách nhau ';', nhận %COMPUTERNAME%...), type file|folder, recurse }
    param($Tool, [int]$Limit = 40)
    $files = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($o in $Tool.outputs) {
        # Dấu * chỉ được ở phần cuối của dir; tách ra trước vì GetFullPath không nhận ký tự đại diện.
        $rawDir = ([string](Get-Prop $o 'dir' '.')).TrimEnd('\')
        $pattern = ''
        $cut = $rawDir.LastIndexOf('\')
        if ($rawDir.Substring($cut + 1) -match '[*?]') {
            $pattern = $rawDir.Substring($cut + 1)
            $rawDir = if ($cut -gt 0) { $rawDir.Substring(0, $cut) } else { '.' }
            if ($rawDir -match '^[A-Za-z]:$') { $rawDir += '\' }
        }
        $dir = Expand-HubPath -Path $rawDir -BaseDir $Tool.dir
        $dirs = @()
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { $dirs = @() }
        elseif ($pattern) { $dirs = @(Get-ChildItem -LiteralPath $dir -Directory -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) }
        else { $dirs = @($dir) }
        $isFolder = [string](Get-Prop $o 'type' 'file') -eq 'folder'
        $recurse = [bool](Get-Prop $o 'recurse' $false)
        $globs = @(([Environment]::ExpandEnvironmentVariables([string](Get-Prop $o 'glob' '*'))) -split ';' | Where-Object { $_ })
        foreach ($d in $dirs) {
            foreach ($glob in $globs) {
                $gci = @{ LiteralPath = $d; Filter = $glob; ErrorAction = 'SilentlyContinue' }
                if ($isFolder) { $gci.Directory = $true } else { $gci.File = $true; if ($recurse) { $gci.Recurse = $true } }
                foreach ($f in @(Get-ChildItem @gci)) {
                    if ($seen.ContainsKey($f.FullName)) { continue }
                    $seen[$f.FullName] = $true
                    [void]$files.Add([ordered]@{
                            toolId = $Tool.id; toolName = $Tool.name; label = [string](Get-Prop $o 'label' 'Kết quả')
                            name = $f.Name; path = $f.FullName; isFolder = $isFolder
                            size = $(if ($isFolder) { 0 } else { $f.Length }); sizeText = $(if ($isFolder) { 'Thư mục' } else { Format-Size $f.Length })
                            modified = (Get-IsoTime $f.LastWriteTime)
                        })
                }
            }
        }
    }
    return @($files | Sort-Object { $_.modified } -Descending | Select-Object -First $Limit)
}

# ---------------------------------------------------------------- Đóng gói gửi khách
function New-ToolPackage {
    param($Tool, [string]$DestDir = [Environment]::GetFolderPath('Desktop'))
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $spec = $Tool.pack
    $include = @(Get-Prop $spec 'include' @())
    if (-not $include.Count) {
        $include = @($Tool.actions | Where-Object { $_.file } | ForEach-Object { $_.file })
        if ($Tool.docs) { $include += $Tool.docs }
    }
    $exclude = @(Get-Prop $spec 'exclude' @())
    $packName = ConvertTo-Slug ([string](Get-Prop $spec 'name' $Tool.id))
    $stage = Join-Path ([IO.Path]::GetTempPath()) ("tramtool_pack_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    try {
        $count = 0
        foreach ($pattern in $include) {
            $rel = $pattern.Replace('/', '\')
            $sub = Split-Path $rel -Parent
            $leaf = Split-Path $rel -Leaf
            $srcDir = if ($sub) { Join-Path $Tool.dir $sub } else { $Tool.dir }
            if (-not (Test-Path -LiteralPath $srcDir)) { continue }
            foreach ($f in @(Get-ChildItem -LiteralPath $srcDir -Filter $leaf -File -ErrorAction SilentlyContinue)) {
                $relPath = $f.FullName.Substring($Tool.dir.TrimEnd('\').Length + 1)
                if ($exclude | Where-Object { $relPath -like $_.Replace('/', '\') }) { continue }
                $dest = Join-Path $stage $relPath
                $destDir = Split-Path $dest -Parent
                if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
                $count++
            }
        }
        if ($count -eq 0) { throw 'Không có file nào để đóng gói.' }

        $primary = $Tool.actions | Where-Object { $_.primary } | Select-Object -First 1
        $lines = @("$($Tool.name)", ('=' * 40), '', $Tool.summary, '')
        if ($primary) {
            $lines += "CÁCH CHẠY: bấm chuột phải vào '$($primary.file)' > Run as administrator."
            if (-not $primary.admin) { $lines[-1] = "CÁCH CHẠY: bấm đúp vào '$($primary.file)'." }
        }
        foreach ($o in $Tool.outputs) { $lines += "KẾT QUẢ: $([string](Get-Prop $o 'label' 'Kết quả')) ($([string](Get-Prop $o 'glob' '*'))) - gửi lại file này." }
        if ($Tool.docs) { $lines += "HƯỚNG DẪN CHI TIẾT: mở file $($Tool.docs)." }
        $lines += ''; $lines += 'Lưu ý: không mở file .bat bằng Notepad rồi lưu lại, sẽ hỏng chữ tiếng Việt.'
        [IO.File]::WriteAllText((Join-Path $stage 'DOC-TRUOC.txt'), ($lines -join "`r`n"), (New-Object Text.UTF8Encoding($true)))

        $zip = Join-Path $DestDir ("{0}_{1}.zip" -f $packName, (Get-Date -Format 'yyyyMMdd-HHmm'))
        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
        [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
        return [ordered]@{ path = $zip; files = $count; size = (Format-Size (Get-Item -LiteralPath $zip).Length) }
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------- Thông tin máy
function Get-SystemSummary {
    return Get-Cached -Key 'system' -Seconds 30 -Compute {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        $uptime = (Get-Date) - $os.LastBootUpTime
        $disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
                [ordered]@{
                    drive = $_.DeviceID; label = [string]$_.VolumeName; size = (Format-Size $_.Size); free = (Format-Size $_.FreeSpace)
                    freePct = $(if ($_.Size) { [math]::Round($_.FreeSpace * 100.0 / $_.Size, 1) } else { 0 })
                }
            })
        $physical = @()
        try {
            $physical = @(Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
                    [ordered]@{ name = $_.FriendlyName; media = [string]$_.MediaType; health = [string]$_.HealthStatus; size = (Format-Size $_.Size) }
                })
        } catch { }
        $py = Find-Python
        [ordered]@{
            computer   = $env:COMPUTERNAME
            user       = "$env:USERDOMAIN\$env:USERNAME"
            isAdmin    = (Test-IsAdmin)
            os         = $os.Caption
            displayVersion = [string](Get-Prop $cv 'DisplayVersion' '')
            build      = "$($os.BuildNumber).$([string](Get-Prop $cv 'UBR' ''))"
            uptimeText = ('{0} ngày {1} giờ' -f [int][math]::Floor($uptime.TotalDays), $uptime.Hours)
            lastBoot   = (Get-IsoTime $os.LastBootUpTime)
            model      = ("$($cs.Manufacturer) $($cs.Model)").Trim()
            cpu        = ([string]$cpu.Name).Trim()
            ramTotal   = (Format-Size $cs.TotalPhysicalMemory)
            ramFree    = (Format-Size ($os.FreePhysicalMemory * 1KB))
            ramUsedPct = [math]::Round(100 - ($os.FreePhysicalMemory * 1KB * 100.0 / $cs.TotalPhysicalMemory), 0)
            disks      = $disks
            physical   = $physical
            gpus       = @(Get-CimInstance Win32_VideoController | ForEach-Object { [string]$_.Name })
            python     = $(if ($py) { "Python $($py.version)" } else { '' })
            pythonPath = $(if ($py) { $py.path } else { '' })
            winget     = [bool](Get-Command winget.exe -ErrorAction SilentlyContinue)
        }
    }
}
