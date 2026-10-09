@echo off
rem ============================================================
rem  TRAM TOOL - CAI DAT CHO MAY MOI. Bam dup file nay mot lan.
rem  Kiem tra moi cong cu can gi (Python, moi truong .venv, LibreDWG,
rem  mo hinh ghi am, ODBC, SQL Server LocalDB...), hoi roi cai phan
rem  con thieu, tao loi tat "Tram Tool" tren Desktop.
rem  Chay lai bao nhieu lan cung duoc: thu da co thi bo qua.
rem  Tuy chon: CAI_DAT.bat -ChayThu   (chi kiem tra, khong cai)
rem            CAI_DAT.bat -TatCa     (khong hoi, cai het)
rem ============================================================
setlocal
cd /d "%~dp0"
if not exist "%~dp0hub\CaiDat.ps1" (
    echo Khong tim thay hub\CaiDat.ps1. Hay giai nen ca thu muc Tool_Win roi chay lai.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0hub\CaiDat.ps1" %*
exit /b %errorlevel%
