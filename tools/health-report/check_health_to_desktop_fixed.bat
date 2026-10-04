@echo off
setlocal EnableExtensions
chcp 65001 >nul

REM =============================================================
REM Check Health - tao file TXT tren Desktop de gui chan doan
REM Tao boi ChatGPT tu file check_health.ps1
REM =============================================================

REM Tu yeu cau quyen Administrator de doc log he thong day du hon
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Dang yeu cau quyen Administrator...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "TMPPS1=%TEMP%\check_health_%RANDOM%_%RANDOM%.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$raw = Get-Content -LiteralPath '%~f0' -Raw -Encoding UTF8; $marker = '### POWERSHELL_SCRIPT_' + 'BELOW ###'; $idx = $raw.LastIndexOf($marker); if ($idx -lt 0) { throw 'Khong tim thay phan PowerShell trong file BAT.' }; $script = $raw.Substring($idx + $marker.Length); Set-Content -LiteralPath '%TMPPS1%' -Value $script -Encoding UTF8"

if not exist "%TMPPS1%" (
    echo Khong tao duoc file PowerShell tam.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%TMPPS1%"
set "ERR=%ERRORLEVEL%"
del "%TMPPS1%" >nul 2>&1

echo.
if "%ERR%"=="0" (
    echo Da chay xong. Hay kiem tra file TXT moi tao ngoai Desktop.
) else (
    echo Script co loi hoac chay chua hoan tat. Van hay kiem tra Desktop xem co file TXT khong.
)
pause
exit /b %ERR%

### POWERSHELL_SCRIPT_BELOW ###
# check_health.ps1 embedded
# Muc tieu: kiem tra nhanh tinh trang may Windows va xuat log TXT ra Desktop.

$ErrorActionPreference = 'Continue'

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "============================================================"
    Write-Host $Title
    Write-Host "============================================================"
}

function Safe-Run {
    param(
        [string]$Title,
        [scriptblock]$Block
    )
    Write-Section $Title
    try {
        & $Block
    } catch {
        Write-Host "[LOI] $($_.Exception.Message)"
    }
}

$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path $desktop)) {
    $desktop = Join-Path $env:USERPROFILE 'Desktop'
}
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$computerSafe = ($env:COMPUTERNAME -replace '[^a-zA-Z0-9_-]', '_')
$logPath = Join-Path $desktop "health_report_${computerSafe}_${stamp}.txt"

Start-Transcript -Path $logPath -Force | Out-Null

try {
    Clear-Host
    Write-Host "=== SYSTEM HEALTH CHECK / BAO CAO CHAN DOAN MAY ==="
    Write-Host "Thoi gian tao log: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "File log: $logPath"
    Write-Host "Ghi chu: file co thong tin phan cung, driver, event loi; khong chu dong lay mat khau."

    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    Write-Host "Dang chay quyen Administrator: $IsAdmin"

    Safe-Run "1) THONG TIN HE THONG" {
        $os = Get-CimInstance Win32_OperatingSystem
        $comp = Get-CimInstance Win32_ComputerSystem
        $bios = Get-CimInstance Win32_BIOS
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $gpu = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate, AdapterRAM

        Write-Host "Computer: $($comp.Name)"
        Write-Host "Manufacturer/Model: $($comp.Manufacturer) / $($comp.Model)"
        Write-Host "OS: $($os.Caption) - Version: $($os.Version) - Build: $($os.BuildNumber)"
        Write-Host "InstallDate: $($os.InstallDate)"
        Write-Host "LastBootUpTime: $($os.LastBootUpTime)"
        $uptime = ((Get-Date) - $os.LastBootUpTime).TotalDays
        Write-Host "Uptime days: $([math]::Round($uptime,2))"
        Write-Host "BIOS: $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion) - $($bios.ReleaseDate)"
        Write-Host "CPU: $($cpu.Name)"
        Write-Host "RAM total GB: $([math]::Round($comp.TotalPhysicalMemory/1GB,2))"
        Write-Host "GPU:"
        $gpu | Format-Table -AutoSize
    }

    Safe-Run "2) CPU / RAM HIEN TAI" {
        $os = Get-CimInstance Win32_OperatingSystem
        $comp = Get-CimInstance Win32_ComputerSystem
        $cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 3
        $cpuUsage = [math]::Round(($cpuCounter.CounterSamples.CookedValue | Measure-Object -Average).Average,1)
        $totalMem = [math]::Round($comp.TotalPhysicalMemory/1GB,2)
        $freeMemGB = [math]::Round($os.FreePhysicalMemory/1MB,2)
        $usedMemGB = [math]::Round($totalMem - $freeMemGB,2)
        Write-Host "CPU Usage average 3s (%): $cpuUsage"
        Write-Host "RAM: $usedMemGB GB used / $totalMem GB total / free $freeMemGB GB"
        Write-Host "Top process CPU:"
        Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 ProcessName, Id, CPU, WorkingSet64 | Format-Table -AutoSize
        Write-Host "Top process RAM:"
        Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 ProcessName, Id, @{Name='RAM_MB';Expression={[math]::Round($_.WorkingSet64/1MB,1)}} | Format-Table -AutoSize
    }

    Safe-Run "3) O DIA / DUNG LUONG" {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
            $freeGB = [math]::Round($_.FreeSpace/1GB,2)
            $sizeGB = [math]::Round($_.Size/1GB,2)
            $pctFree = if ($_.Size) { [math]::Round(($_.FreeSpace/$_.Size)*100,1) } else { 0 }
            Write-Host ("{0}: {1} GB free / {2} GB total ({3}% free)" -f $_.DeviceID, $freeGB, $sizeGB, $pctFree)
        }
    }

    Safe-Run "4) SMART / TINH TRANG O CUNG" {
        # wmic da bi go khoi Windows 11 24H2 tro len, doc thang qua CIM
        Write-Host "O dia vat ly (model / trang thai / serial):"
        Get-CimInstance Win32_DiskDrive | Select-Object Model, Status, SerialNumber, @{Name='SizeGB';Expression={[math]::Round($_.Size/1GB,1)}} | Format-Table -AutoSize
        Write-Host ""
        Write-Host "MSStorageDriver_FailurePredictStatus:"
        Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus | Select-Object InstanceName, PredictFailure, Reason | Format-Table -AutoSize
    }

    Safe-Run "5) EVENT LOG QUAN TRONG - 7 NGAY GAN DAY" {
        $since = (Get-Date).AddDays(-7)
        Write-Host "Cac loi Critical/Error trong System:"
        Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$since} -MaxEvents 80 |
            Select-Object TimeCreated, LevelDisplayName, Id, ProviderName, @{Name='Message';Expression={($_.Message -replace "`r`n"," ").Substring(0, [Math]::Min(500, ($_.Message -replace "`r`n"," ").Length))}} |
            Format-Table -Wrap -AutoSize
    }

    Safe-Run "6) LOG LIEN QUAN TU RESTART / BSOD / NGUON / PHAN CUNG" {
        $since = (Get-Date).AddDays(-14)
        $ids = 41, 1001, 6008, 1074, 18, 19, 47, 1, 14, 4101
        Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$since; Id=$ids} -MaxEvents 120 |
            Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, @{Name='Message';Expression={($_.Message -replace "`r`n"," ").Substring(0, [Math]::Min(700, ($_.Message -replace "`r`n"," ").Length))}} |
            Format-Table -Wrap -AutoSize
        Write-Host ""
        Write-Host "Goi y doc nhanh:"
        Write-Host "- Kernel-Power 41: may tat/restart bat ngo, co the do nguon, nhiet, RAM, main, driver, crash."
        Write-Host "- BugCheck 1001: co BSOD, can xem ma bugcheck/minidump."
        Write-Host "- WHEA-Logger 18/19/47: hay lien quan CPU/RAM/main/nguon/PCIe/phan cung."
        Write-Host "- Display 4101/nvlddmkm/amdkmdag: hay lien quan driver/card man hinh."
    }

    Safe-Run "7) MINI DUMP NEU CO" {
        $dumpDir = 'C:\Windows\Minidump'
        if (Test-Path $dumpDir) {
            Get-ChildItem $dumpDir -Filter '*.dmp' | Sort-Object LastWriteTime -Descending | Select-Object -First 20 Name, Length, LastWriteTime | Format-Table -AutoSize
        } else {
            Write-Host "Khong thay thu muc C:\Windows\Minidump"
        }
    }

    Safe-Run "8) DRIVER GPU / THIET BI LOI" {
        Write-Host "GPU driver:"
        Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate, Status | Format-Table -AutoSize
        Write-Host ""
        Write-Host "Thiet bi PnP dang loi:"
        Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' } | Select-Object Status, Class, FriendlyName, InstanceId | Format-Table -Wrap -AutoSize
    }

    Safe-Run "9) KIEM TRA FILE SYSTEM NHANH - CHKDSK /SCAN" {
        Get-CimInstance -ClassName Win32_Volume -Filter "DriveType=3" | ForEach-Object {
            $drv = $_.DriveLetter
            if ($drv) {
                Write-Host "Drive $drv :"
                cmd /c "chkdsk $drv /scan" 2>&1
                Write-Host ""
            }
        }
    }

    Safe-Run "10) KIEM TRA FILE HE THONG WINDOWS - SFC VERIFYONLY" {
        Write-Host "Lenh nay chi kiem tra, khong sua. Neu co loi, sau do moi can chay sfc /scannow."
        cmd /c "sfc /verifyonly" 2>&1
    }

    Safe-Run "11) POWER / SLEEP / RESTART INFO" {
        Write-Host "Power plan dang dung:"
        cmd /c "powercfg /getactivescheme" 2>&1
        Write-Host ""
        Write-Host "Sleep states:"
        cmd /c "powercfg /a" 2>&1
        Write-Host ""
        Write-Host "Lan restart/shutdown gan day co ly do neu Windows ghi nhan:"
        Get-WinEvent -FilterHashtable @{LogName='System'; Id=1074; StartTime=(Get-Date).AddDays(-30)} -MaxEvents 20 |
            Select-Object TimeCreated, ProviderName, Id, @{Name='Message';Expression={($_.Message -replace "`r`n"," ").Substring(0, [Math]::Min(700, ($_.Message -replace "`r`n"," ").Length))}} |
            Format-Table -Wrap -AutoSize
    }

    Safe-Run "12) KET LUAN SO BO / VIEC CAN GUI LAI" {
        Write-Host "Da tao log xong. Hay gui file TXT nay cho ChatGPT de doc va chan doan tiep:"
        Write-Host $logPath
        Write-Host ""
        Write-Host "Neu may tu restart khi chay Canva/de lau, can dac biet xem cac dong: Kernel-Power 41, BugCheck 1001, WHEA-Logger, Display driver, SMART Pred Fail."
        Write-Host "Neu co file .dmp trong C:\Windows\Minidump, nen nen zip va gui them neu duoc."
        Write-Host "Neu nghi phan cung: kiem tra nhiet do, RAM, SSD/HDD, nguon/adapter, driver GPU truoc khi ket luan hu tu/main."
    }
}
finally {
    Stop-Transcript | Out-Null
    Write-Host ""
    Write-Host "HOAN TAT. File TXT da nam tren Desktop:"
    Write-Host $logPath
}
