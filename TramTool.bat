@echo off
rem ============================================================
rem  TRAM TOOL - bam dup file nay de mo tram cong cu.
rem  Giao dien mo trong cua so trinh duyet (Brave, khong co thi Edge).
rem  Cua so PowerShell thu nho la may chu cua tram: dong no = tat tram.
rem  Tuy chon: TramTool.bat -Browser edge   |   TramTool.bat -NoBrowser
rem ============================================================
setlocal
cd /d "%~dp0"
if not exist "%~dp0hub\TramTool.ps1" (
    echo Khong tim thay hub\TramTool.ps1. Hay giu nguyen cau truc thu muc Tool_Win.
    pause
    exit /b 1
)
start "Tram Tool" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0hub\TramTool.ps1" %*
exit /b 0
