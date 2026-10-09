@echo off
rem Tat/bat dich vu nen (DiagTrack, wisvc, SysMain, defragsvc) - bam dup de mo menu.
rem Chay thang mot che do: TAT_BAT_DICH_VU.bat -Mode kiem-tra   (xem DichVu.ps1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DichVu.ps1" %*
exit /b %errorlevel%
