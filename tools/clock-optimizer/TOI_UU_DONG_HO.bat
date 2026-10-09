@echo off
rem Toi uu dong ho he thong (Dynamic Tick, HPET trong BCD) - bam dup de mo menu.
rem Chay thang mot che do: TOI_UU_DONG_HO.bat -Mode kiem-tra   (xem DongHo.ps1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DongHo.ps1" %*
exit /b %errorlevel%
