@echo off
rem Toi uu Windows: dich vu nen (DiagTrack, wisvc, SysMain, defragsvc) va dong ho he thong (Dynamic Tick, HPET).
rem Bam dup de mo menu (tu hoi quyen Admin). Kiem tra tat ca: TOI_UU.bat -Mode kiem-tra   (xem ToiUu.ps1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ToiUu.ps1" %*
exit /b %errorlevel%
