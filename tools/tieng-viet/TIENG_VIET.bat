@echo off
rem Goi tieng Viet: bo go, font VNI va TCVN3, dinh dang so va ngay; chuyen tai lieu font cu sang Unicode.
rem Bam dup de mo menu. Chay thang: TIENG_VIET.bat -Mode kiem-tra   (xem TiengViet.ps1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0TiengViet.ps1" %*
exit /b %errorlevel%
