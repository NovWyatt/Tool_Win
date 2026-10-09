@echo off
rem Chay moi bai thu gia lap cua Tram Tool (quyen thuong). Tham so them duoc chuyen cho ChayTatCa.ps1, vd: -Chi office
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ChayTatCa.ps1" %*
set RC=%errorlevel%
echo.
pause
exit /b %RC%
