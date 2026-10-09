@echo off
rem Xuat du lieu TRUOC khi cai lai Windows (Wi-Fi, may in, khoa BitLocker, driver, Claude) - bam dup de chay.
rem Cua so tu hoi UAC. Tuy chon them (xem ChuyenDuLieu.ps1): -Target E:\  -MaHoa  -Driver mang  -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ChuyenDuLieu.ps1" -Mode xuat %*
exit /b %errorlevel%
