@echo off
rem Ket noi Wi-Fi - sua loi "Can't connect to this network" khi vao mang Wi-Fi moi. Bam dup de mo menu.
rem Chay thang mot che do: KET_NOI_WIFI.bat -Mode ket-noi (xem KetNoiWifi.ps1).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0KetNoiWifi.ps1" %*
exit /b %errorlevel%
