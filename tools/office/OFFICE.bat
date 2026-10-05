@echo off
rem Go sach va cai Office theo mau - bam dup de mo menu.
rem Chay thang mot che do: OFFICE.bat -Mode kiem-tra (xem Office.ps1).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Office.ps1" %*
exit /b %errorlevel%
