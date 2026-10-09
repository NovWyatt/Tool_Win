@echo off
rem Sua loi Windows (DISM, SFC, mang, tuong lua, o dia, RAM, Windows Update) - bam dup de mo menu.
rem Chay thang mot che do: SUA_LOI_WINDOWS.bat -Mode dism-quet   (xem SuaLoi.ps1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SuaLoi.ps1" %*
exit /b %errorlevel%
