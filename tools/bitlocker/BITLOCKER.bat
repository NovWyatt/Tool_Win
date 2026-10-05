@echo off
rem BitLocker va khoa khoi phuc - bam dup de mo menu.
rem Chay thang mot che do: BITLOCKER.bat -Mode kiem-tra (xem BitLocker.ps1).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0BitLocker.ps1" %*
exit /b %errorlevel%
