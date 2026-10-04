@echo off
rem May in mang LAN va thu muc chia se - bam dup de mo menu.
rem Chay thang mot che do: MAY_IN_LAN.bat -Mode chan-doan (xem MayInLan.ps1).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0MayInLan.ps1" %*
exit /b %errorlevel%
