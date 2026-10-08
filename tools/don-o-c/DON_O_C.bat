@echo off
rem Don o C an toan - bam dup de mo menu.
rem Chay thang mot che do: DON_O_C.bat -Mode kiem-tra (xem DonOC.ps1).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DonOC.ps1" %*
exit /b %errorlevel%
