@echo off
rem Nhap du lieu SAU khi cai lai Windows - bam dup de chay. Tu tim DuLieu_SaoLuu o goc cac o, USB, canh cong cu.
rem Cua so tu hoi UAC. Tuy chon them (xem ChuyenDuLieu.ps1): -Target E:\DuLieu_SaoLuu  -Phan wifi  -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ChuyenDuLieu.ps1" -Mode nhap %*
exit /b %errorlevel%
