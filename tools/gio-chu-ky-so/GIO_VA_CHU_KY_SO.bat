@echo off
rem Gio may va chu ky so (USB token): kiem tra gio, mui gio, dich vu Smart Card, chung thu ky so; sua co luu gia tri cu.
rem Bam dup de mo menu. Chay thang: GIO_VA_CHU_KY_SO.bat -Mode kiem-tra   (xem GioChuKySo.ps1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0GioChuKySo.ps1" %*
exit /b %errorlevel%
