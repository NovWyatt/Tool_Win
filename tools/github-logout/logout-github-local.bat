@echo off
rem Dang xuat GitHub tren may: xoa dang nhap GitHub da luu trong Windows Credential Manager.
rem Bam dup de chay. Chi xem se xoa gi: logout-github-local.bat -ChayThu   (xem DangXuatGitHub.ps1)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DangXuatGitHub.ps1" %*
exit /b %errorlevel%
